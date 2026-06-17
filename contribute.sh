#!/usr/bin/env bash
# contribute.sh — send a MACHINERY improvement you made locally UP to the factory.
#
# update.sh pulls engine refreshes DOWN from upstream; this is the path the other way.
# It extracts a machinery-only diff of YOUR local changes vs upstream, runs a
# fail-closed leak audit over it, and writes a reviewable patch + a per-path routing
# table you apply into the factory by hand.
#
#   Usage:
#     bash contribute.sh [--force] [OUTFILE]
#       --force     overwrite an existing OUTFILE (default: refuse, so you don't
#                   clobber a patch you haven't applied yet).
#       OUTFILE     where to write the patch (default: ./lab-zero-contribution.patch).
#
# ── READ THIS — what this is and is NOT ───────────────────────────────────────
# The leak audit is a TRIPWIRE, not a guarantee. It reuses the release's redaction
# regexes — which only know the project owner's identifiers + known token shapes —
# plus two outbound classes (absolute home paths, generic SECRET=/TOKEN= lines). A
# generic password, a private hostname, or another person's name can pass clean. So:
#   * the audit just stops the OBVIOUS slips;
#   * YOU must read every changed line before you apply it;
#   * a clean audit is NOT proof the patch is personal-data-free, nor that the
#     change is even wanted upstream.
# It runs IN your consumer tree, reads it, and writes ONLY the patch file. It never
# touches the factory — applying the patch there is a separate, manual step.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVOKE_DIR="$PWD"
cd "$ROOT"
UPSTREAM_URL="${LAB_ZERO_UPSTREAM:-https://github.com/cyb213/Lab-Zero.git}"

# ── args ──────────────────────────────────────────────────────────────────────
FORCE=0
OUTFILE="lab-zero-contribution.patch"
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help)
      sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "[contribute] ERROR: unknown flag '$arg' (try --force, --help)" >&2; exit 2 ;;
    *)  OUTFILE="$arg" ;;
  esac
done
# resolve a relative OUTFILE against where you invoked the script (absolute kept as-is)
case "$OUTFILE" in /*) ;; *) OUTFILE="$INVOKE_DIR/$OUTFILE" ;; esac

# ── preconditions + upstream baseline (reused from update.sh) ──────────────────
git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "[contribute] ERROR: not a git repo. contribute.sh runs inside a cloned Lab." >&2; exit 1; }
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$UPSTREAM_URL"
  echo "[contribute] added remote upstream -> $UPSTREAM_URL"
fi
git fetch -q upstream
BR="$(git remote show upstream 2>/dev/null | sed -n 's/.*HEAD branch: //p')"; BR="${BR:-main}"

# ── the contributable set (MACHINERY-only, never a denylist) ───────────────────
# = update.sh's MACHINERY MINUS memory-seed/.  memory-seed/ is the agent's long-term
# memory seed — the single likeliest machinery path to accrete PERSONAL lessons/names,
# and generic prose is exactly what the regex audit below will NOT catch — so a
# consumer's seed edits are never contributed. CONTRIBUTABLE is therefore a STRICT
# SUBSET of MACHINERY (a file safe to pull down is the same file safe to push up).
# The personal layer (IDENTITY.md, AGENTS.md, CLAUDE.md, recall.config.json,
# .claude/settings.json, .env, Projects-REGISTRY.md, Log/, Sessions/, memory/) is
# excluded BY CONSTRUCTION — it is simply never on this list.
#   NOTE (load-bearing): .claude/settings.json is the ONE machinery file bootstrap.sh
#   substitutes a real /home/<user>/… path into; keeping it OFF this list is what makes
#   the absolute-home-path safety hold (the abs-path audit class is the backstop).
# One path per line so the test can awk-extract + subset-check it.
CONTRIBUTABLE=(
  scripts
  template
  tests
  new-project.sh
  bootstrap.sh
  update.sh
  contribute.sh
  README.md
  LICENSE
  .env.example
  .agents/skills
  .claude/skills
  .claude/hooks
)

# ── warn on untracked-new machinery (silently dropped by `git diff` otherwise) ──
# `git diff <commit> -- <paths>` does NOT include untracked files, so a brand-new
# machinery file you never `git add`-ed would be omitted from the patch AND un-audited.
# Detect + warn loudly; never silently drop.
untracked="$(git ls-files --others --exclude-standard -- "${CONTRIBUTABLE[@]}" 2>/dev/null || true)"
if [[ -n "$untracked" ]]; then
  echo "[contribute] ⚠️  WARNING: these new machinery file(s) are UNTRACKED and are NOT" >&2
  echo "[contribute]     included in the patch (and were NOT audited). \`git add\` them first" >&2
  echo "[contribute]     if you want to contribute them:" >&2
  printf '%s\n' "$untracked" | sed 's/^/[contribute]       - /' >&2
fi

# ── extract the candidate patch (committed + modified-tracked machinery) ───────
patch="$(git diff "upstream/$BR" -- "${CONTRIBUTABLE[@]}")"
if [[ -z "$patch" ]]; then
  echo "[contribute] nothing to contribute — your machinery matches upstream/$BR."
  echo "[contribute] (Personal-layer + memory-seed changes are never contributed.)"
  exit 0
fi

# ── the leak audit — a TRIPWIRE over the patch payload, fail-closed ────────────
# OWNER-IDENTIFIER class — derived AT RUNTIME from THIS consumer's own identity, so
# the shipped script hardcodes ZERO personal data. (The release audit's IDENT regex
# IS personal data — the owner's name/handle/projects — so embedding it here would leak
# it into the public release; the redaction audit blocks exactly that. We derive the
# running user's identifiers instead — which is also the correct threat model: scrub
# the contributor's data, not the factory owner's.)
#   Sources (union, all optional): git config user.name / user.email (the universal,
#   structured identity) + $LAB_CONTRIBUTE_NAMES (space/comma list — add project names).
#   Tripwire-grade: catches your name/handle slipping into a machinery comment; it is
#   NOT exhaustive (it can't know a project name you never told it). EMPTY => the owner
#   scan is SKIPPED entirely (an empty regex would match every line).
owner_toks="$(
  { git config user.name 2>/dev/null || true
    git config user.email 2>/dev/null | sed 's/@.*//' || true
    printf '%s\n' "${LAB_CONTRIBUTE_NAMES:-}"
  } | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '\n' | awk 'length($0) >= 3' | sort -u
)"
if [[ -n "$owner_toks" ]]; then
  IDENT="\\b($(printf '%s' "$owner_toks" | paste -sd'|' -))\\b"
else
  IDENT=""
fi
# allowlist the resolved upstream URL itself — it legitimately appears in update.sh /
# contribute.sh diffs, so a consumer whose handle collides with the upstream owner must
# not false-fire on it. Derived from the upstream remote — generic, no hardcoded handle.
up_url="$(git remote get-url upstream 2>/dev/null || true)"; up_url="${up_url:-$UPSTREAM_URL}"
ALLOWED="$(printf '%s' "$up_url" | sed -E 's#\.git$##; s#\.#\\.#g')"
[[ -n "$ALLOWED" ]] || ALLOWED='ZZ_NO_SUCH_MATCH_ZZ'

# Generic, owner-agnostic classes (these contain no personal data — they ship fine):
SECRET='eyJ[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|[0-9]{8,12}:AA[A-Za-z0-9_-]{30,}'
IPV4='\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'
PLACEHOLDER='__[A-Z_]+__'
PLACEHOLDER_OK='__WORKSPACE__|__COPYRIGHT_HOLDER__|__PROJECT__|__SLUG__|__PURPOSE__|__DATE__'
# Two OUTBOUND classes the release never needs (they can't appear in an allowlisted
# release, but a personal consumer tree can leak them upward):
ABSPATH='/home/[^/]+/|/Users/[^/]+/'
# Generic secret ASSIGNMENT with a non-empty value. The value requirement is a
# deliberate refinement of the plan's bare `(…)\s*[=:]`: the shipped .env.example is
# all EMPTY-valued key lines (GROQ_API_KEY=, CLOUDFLARE_API_TOKEN=, …); firing on those
# would block every legitimate .env.example contribution. An empty assignment carries
# no secret, so we require a value — strictly more accurate, no weaker on real leaks.
# Uppercase-keyed (env/config convention) to avoid prose false-positives ("the token: x").
GENERIC_SECRET='(PASSWORD|PASSWD|SECRET|TOKEN|API_KEY|PRIVATE_KEY)[A-Za-z0-9_]*[[:space:]]*[=:][[:space:]]*[^[:space:]]'

# AUDIT-PAYLOAD: strip the diff metadata headers, then scan the +/- payload lines
# ONLY. `^[-+]` catches added/removed lines AND the `+++`/`---` file headers; we drop
# the two headers so a flagged machinery FILENAME in the metadata can't false-fire
# (Feasibility #1a). diff --git / index / @@ lines don't start with +/- so they're
# already excluded.
payload="$(printf '%s\n' "$patch" | grep -E '^[-+]' | grep -vE '^(\+\+\+ |--- )' || true)"

audit_fails=0
scan() {  # $1=label  $2=regex  $3="exclude" regex(optional)  $4=grep flags(optional, e.g. -i)
  local label="$1" re="$2" excl="${3:-}" gf="${4:-}" hits
  if [[ -n "$excl" ]]; then
    hits="$(printf '%s\n' "$payload" | grep -nE $gf "$re" 2>/dev/null | grep -vE $gf "$excl" || true)"
  else
    hits="$(printf '%s\n' "$payload" | grep -nE $gf "$re" 2>/dev/null || true)"
  fi
  if [[ -n "$hits" ]]; then
    echo "[contribute]   ✗ [$label] potential leak on these patch lines:" >&2
    printf '%s\n' "$hits" | sed 's/^/[contribute]       /' >&2
    audit_fails=$((audit_fails+1))
  fi
}
# The OWNER class (+ its ALLOWED upstream-URL allowlist) is case-INSENSITIVE, like
# release-lab-zero.sh — so the upstream URL drops the line whatever the case. It is
# SKIPPED when no identity could be derived (empty regex would match everything). The
# remaining classes are case-SENSITIVE on purpose (token shapes, uppercase placeholders/
# env keys), and always run.
if [[ -n "$IDENT" ]]; then scan "OWNER (your identifiers)" "$IDENT" "$ALLOWED" "-i"; fi
scan "SECRET (live token shapes)" "$SECRET"
scan "IPv4 (raw addresses)"       "$IPV4"           '0\.0\.0\.0|127\.0\.0\.1'
scan "PLACEHOLDER (leftover)"     "$PLACEHOLDER"    "$PLACEHOLDER_OK"
scan "ABSPATH (home dir)"         "$ABSPATH"
scan "GENERIC_SECRET (assignment)" "$GENERIC_SECRET"

if [[ "$audit_fails" -gt 0 ]]; then
  echo "[contribute] ❌ ABORT (fail-closed): the leak audit flagged $audit_fails class(es) above." >&2
  echo "[contribute]    NO patch was written. Remove the flagged content (or, if it's a genuine" >&2
  echo "[contribute]    false-positive, hand-build the patch yourself — never bypass this blindly)." >&2
  exit 1
fi

# ── clean audit — write the patch + honest, applicable guidance ────────────────
if [[ -e "$OUTFILE" && "$FORCE" -ne 1 ]]; then
  echo "[contribute] ERROR: $OUTFILE already exists. Re-run with --force to overwrite," >&2
  echo "[contribute]        or pass a different OUTFILE — refusing to clobber it." >&2
  exit 1
fi
printf '%s\n' "$patch" > "$OUTFILE"

# map a consumer-tree path to its canonical FACTORY home (the inverse of
# release-lab-zero.sh:36-53). The factory tree is SPLIT — engine in src/, scaffold/docs
# in assets/ — so a flat patch does NOT cleanly `git apply` there; route each hunk by hand.
factory_home() {
  local p="$1"
  case "$p" in
    scripts|scripts/*|template|template/*|tests|tests/*|new-project.sh)
        echo "src/$p" ;;
    .claude/hooks|.claude/hooks/*)
        echo "src/$p" ;;
    bootstrap.sh|update.sh|contribute.sh|README.md|LICENSE|.env.example)
        echo "assets/$p" ;;
    # ceremonies: setup is authored in assets/, the other skills in src/ (engine).
    .agents/skills/setup|.agents/skills/setup/*)
        echo "assets/$p" ;;
    .agents/skills|.agents/skills/*)
        echo "src/$p" ;;
    # .claude/skills/<X> copies are GENERATED at release time from .agents/skills/<X> —
    # editing the copy is clobbered by the next build (and the drift-gate flags it).
    # Route to the CANONICAL .agents/skills home instead.
    .claude/skills/setup|.claude/skills/setup/*)
        echo "assets/.agents/skills/setup${p#.claude/skills/setup}  (canonical; .claude/ copy is release-generated)" ;;
    .claude/skills|.claude/skills/*)
        echo "src/.agents/skills/${p#.claude/skills/}  (canonical; .claude/ copy is release-generated)" ;;
    *)  echo "??? UNKNOWN — not a contributable path; do NOT apply blindly" ;;
  esac
}

echo
echo "[contribute] ✅ leak audit clean (a TRIPWIRE, not a guarantee — see below)."
echo "[contribute]    patch written: $OUTFILE"
echo
echo "[contribute] Changed machinery (vs upstream/$BR):"
git diff --stat "upstream/$BR" -- "${CONTRIBUTABLE[@]}" | sed 's/^/[contribute]   /'
echo
echo "[contribute] Where each file goes in the FACTORY (the patch is flat / consumer-rooted;"
echo "[contribute] the factory tree is split src/ + assets/, so route each hunk by hand):"
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  printf '[contribute]   %-34s ->  %s\n' "$f" "$(factory_home "$f")"
done < <(git diff --name-only "upstream/$BR" -- "${CONTRIBUTABLE[@]}")
echo
echo "[contribute] Before you apply this anywhere:"
echo "[contribute]   1. READ EVERY CHANGED LINE in $OUTFILE — the audit only catches obvious"
echo "[contribute]      slips; it does NOT prove the patch is free of personal data."
echo "[contribute]   2. In the factory, route each hunk to its printed home (it will NOT"
echo "[contribute]      cleanly \`git apply\` flat). Engine -> src/, scaffold/docs -> assets/."
echo "[contribute]   3. Then rebuild dist/, run the full test suite + the redaction audit,"
echo "[contribute]      and only publish once all are green."
