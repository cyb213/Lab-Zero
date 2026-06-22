#!/usr/bin/env bash
# update.sh — refresh the Lab MACHINERY from upstream (Lab-Zero) without touching
# your PERSONAL layer. Lands the latest PUBLISHED version (git tag), not a
# mid-flight branch HEAD.
#
#   Usage:
#     bash update.sh                 # update machinery to the latest published version
#     bash update.sh --check         # read-only: your version vs latest + what's new
#     bash update.sh --ref <tag|br>  # update to a specific tag (e.g. v1.1.0) or branch
#     bash update.sh --help
#
#   Machinery (refreshed from upstream): the recall + file-protection engine
#       (scripts/, .claude/hooks/), ALL EIGHT work-ceremony skills in BOTH the
#       canonical .agents/skills/ and the committed .claude/skills/ copies, the
#       project template/, the engine tests/, new-project.sh, bootstrap.sh,
#       update.sh, contribute.sh, README.md, PERMISSIONS.md, CHANGELOG.md, VERSION, LICENSE,
#       .env.example, the memory-seed/, and — merged in, never clobbered — the
#       .gitignore leak-control lines.
#   Personal (left alone): IDENTITY.md, AGENTS.md, CLAUDE.md, recall.config.json,
#       .claude/settings.json, .env, Projects-REGISTRY.md, Log/, Sessions/, and your
#       agent memory namespace. AGENTS.md / CLAUDE.md are your constitution — yours
#       to edit; diff them against upstream by hand if you want engine-side wording
#       updates (see the footer).
#
# Don't hand-edit machinery files — they get overwritten here. Customize via the
# personal layer (IDENTITY / AGENTS / CLAUDE) instead.
#
# Versioning — `update.sh` lands the latest PUBLISHED tag (e.g. v1.2.0), not whatever
# is on upstream's main branch right now. `--check` shows what you're on vs the latest
# plus the changelog; `--ref` pins a specific version (or a branch, to pull the
# bleeding edge). If upstream has no tags, it falls back to the branch HEAD.
#
# Limitation — `git checkout` ADDS and UPDATES paths but NEVER DELETES. A skill or
# hook that was renamed/removed upstream leaves a stale local copy (an "orphan");
# update.sh will not auto-remove it (deleting a path under your tree is unsafe). The
# known live case: a pre-2A Lab still carries the old `.claude/skills/plan` (the
# planning skill was renamed /plan -> /lab-plan). After the first update that orphan
# sits with no `.agents/skills/plan` sibling, which the skills-sync gate flags — so
# clean it by hand: `git rm -r .claude/skills/plan` (see the footer).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
UPSTREAM_URL="${LAB_ZERO_UPSTREAM:-https://github.com/cyb213/Lab-Zero.git}"

# ── args (parse BEFORE any network; --help works even outside a git repo) ──────
MODE=update          # update | check
REF=""               # explicit --ref override (a tag like v1.1.0, or a branch)
usage() {
  cat <<'EOF'
update.sh — refresh Lab machinery from upstream (Lab-Zero), to the latest published version.

  bash update.sh                 update machinery to the latest published version (git tag)
  bash update.sh --check         read-only: show your version vs latest + what's new
  bash update.sh --ref <tag|br>  update to a specific tag (e.g. v1.1.0) or a branch
  bash update.sh --help          this help

Refreshes only MACHINERY; your personal layer (identity, memories, projects) is left
alone. See the header of this file for the full machinery/personal split.
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)   MODE=check ;;
    --ref)     shift; REF="${1:-}"
               [[ -n "$REF" ]] || { echo "[update] ERROR: --ref needs a value (a tag like v1.1.0, or a branch)." >&2; exit 2; } ;;
    --ref=*)   REF="${1#*=}"
               [[ -n "$REF" ]] || { echo "[update] ERROR: --ref needs a value (a tag like v1.1.0, or a branch)." >&2; exit 2; } ;;
    -h|--help) usage; exit 0 ;;
    -*)        echo "[update] ERROR: unknown flag '$1' (try --check, --ref <tag|branch>, --help)." >&2; exit 2 ;;
    *)         echo "[update] ERROR: unexpected argument '$1'." >&2; exit 2 ;;
  esac
  shift
done

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "[update] ERROR: not a git repo. Re-clone from $UPSTREAM_URL to enable updates." >&2; exit 1; }

# Highest vX.Y.Z tag from a ref/tag list on stdin (strips refs/tags/ + ^{} peels).
latest_semver() { sed -e 's#.*refs/tags/##' -e 's/\^{}$//' | grep -E '^v[0-9]' | sort -V | uniq | tail -1; }

# ── --check : read-only current-vs-latest + changelog ──────────────────────────
# Makes NO changes to your files, machinery, or git history. The version compare is a
# pure `git ls-remote` read against the URL (no remote-add, no ref write) — so the
# common "you're current" path writes literally nothing. Only when behind does it
# fetch the new tag's objects (read-only network) to show the changelog.
if [[ "$MODE" == "check" ]]; then
  CURRENT=""
  [[ -f "$ROOT/VERSION" ]] && CURRENT="$(head -1 "$ROOT/VERSION" | tr -d '[:space:]')"
  CURRENT="${CURRENT:-unknown}"

  latest="$(git ls-remote --tags "$UPSTREAM_URL" 'refs/tags/v*' 2>/dev/null | latest_semver || true)"
  if [[ -z "$latest" ]]; then
    echo "[update] Could not reach upstream, or it has no published versions."
    echo "[update]   upstream:  $UPSTREAM_URL"
    echo "[update]   you're on: $CURRENT"
    exit 0
  fi

  # behind? "unknown" (pre-versioning) is always treated as behind.
  newest="$(printf '%s\n%s\n' "$CURRENT" "$latest" | sort -V | tail -1)"
  if   [[ "$CURRENT" == "unknown" ]]; then behind=1
  elif [[ "$CURRENT" == "$latest"  ]]; then behind=0
  elif [[ "$newest"  == "$latest"  ]]; then behind=1
  else behind=0   # local is AHEAD of the latest tag (e.g. a dev build)
  fi

  if [[ "$behind" -eq 0 ]]; then
    echo "[update] ✅ You're on the latest Lab Zero ($latest). Nothing to update."
    exit 0
  fi

  # Behind → fetch ONLY the new tag's objects (no remote-add, no local ref written)
  # and read the changelog from it.
  git fetch -q "$UPSTREAM_URL" "refs/tags/$latest" 2>/dev/null || true
  changelog="$(git show "FETCH_HEAD:CHANGELOG.md" 2>/dev/null || true)"

  if [[ "$CURRENT" == "unknown" ]]; then
    echo "[update] You're on:  unknown (pre-versioning — older than $latest)"
  else
    echo "[update] You're on:  $CURRENT"
  fi
  echo "[update] Latest:      $latest"
  echo
  if [[ -n "$changelog" ]]; then
    echo "What's new:"
    echo
    # Two-branch extractor (never dumps the whole file):
    #  - CURRENT is a header present in the changelog ⇒ print the sections NEWER than it
    #    (top `## vX` down to, but excluding, the CURRENT header);
    #  - CURRENT is "unknown" or not found ⇒ print ONLY the top section.
    if [[ "$CURRENT" != "unknown" ]] && grep -qE "^## $CURRENT([[:space:]]|$)" <<<"$changelog"; then
      section="$(awk -v cur="$CURRENT" '
        /^## v/ { started=1 }
        started && $0 ~ "^## " cur "([ \t]|$)" { exit }
        started { print }
      ' <<<"$changelog")"
    else
      section=""
    fi
    # Fallback (and the unknown/not-found case): top section only.
    [[ -n "$section" ]] || section="$(awk '/^## v/ { c++; if (c==2) exit } c>=1 { print }' <<<"$changelog")"
    printf '%s\n' "$section"
    echo
  else
    echo "[update] (changelog unavailable at $latest — see the GitHub releases page)"
    echo
  fi
  echo "[update] To update, run:  bash update.sh"
  exit 0
fi

# ── update mode ────────────────────────────────────────────────────────────────
# ensure an 'upstream' remote points at Lab-Zero
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$UPSTREAM_URL"
  echo "[update] added remote upstream -> $UPSTREAM_URL"
fi
had_error=0
git fetch -q upstream
# Belt-and-suspenders: explicitly fetch version tags (the plain fetch already
# auto-follows annotated tags reachable from main; this makes it explicit). On
# failure, WARN + bump had_error and fall back to branch HEAD below — never a silent
# HEAD update behind a green banner (D-022 discipline).
if ! git fetch -q upstream 'refs/tags/v*:refs/tags/v*' 2>/dev/null; then
  echo "[update]   WARN: could not fetch version tags from upstream." >&2
  had_error=$((had_error+1))
fi
BR="$(git remote show upstream 2>/dev/null | sed -n 's/.*HEAD branch: //p')"; BR="${BR:-main}"

# Resolve the ref to update FROM (validated BEFORE the MACHINERY loop so a typo'd
# --ref fails fast instead of WARNing on every path behind a confusing half-update):
#   --ref override → the latest published tag → (no tags) the branch HEAD.
if [[ -n "$REF" ]]; then
  if   git rev-parse --verify -q "refs/tags/$REF^{commit}" >/dev/null 2>&1; then
    :                                  # an exact tag (e.g. v1.1.0)
  elif git rev-parse --verify -q "upstream/$REF^{commit}" >/dev/null 2>&1; then
    REF="upstream/$REF"                # a branch on upstream (pull its HEAD)
  elif git rev-parse --verify -q "$REF^{commit}" >/dev/null 2>&1; then
    :                                  # a raw commit / otherwise-resolvable ref
  else
    echo "[update] ERROR: --ref '$REF' does not resolve to a tag or branch on upstream." >&2
    exit 2
  fi
  echo "[update] updating to pinned ref: $REF"
else
  latest_tag="$(git tag -l 'v*' | sort -V | tail -1 || true)"
  if [[ -n "$latest_tag" ]]; then
    REF="$latest_tag"
    echo "[update] latest published version: $REF"
  else
    REF="upstream/$BR"
    echo "[update] no version tags upstream — using branch HEAD ($REF)."
  fi
fi

# machinery paths (the ONLY things refreshed). Whole DIRECTORIES wherever possible so
# a future skill / hook is picked up automatically — no more hand-listing each one
# (the bug this rewrite fixes). git checkout adds/updates but NEVER deletes, so a
# renamed/removed path leaves an orphan (see the header + footer).
MACHINERY=(
  scripts                 # recall engine, wire-harness, setup-engine, check-skills-sync, git-hooks
  template                # the project genome stamped by new-project.sh
  tests                   # engine tests
  new-project.sh
  bootstrap.sh
  update.sh
  contribute.sh           # the up-path helper (sibling of this down-path script)
  README.md
  PERMISSIONS.md          # consumer-facing posture map; README links to it (must travel together)
  CHANGELOG.md            # user-facing changelog (what `update.sh --check` reads)
  VERSION                 # release-stamped version line (so a clone knows what it runs)
  LICENSE
  .env.example            # engine env template (your live .env stays personal)
  memory-seed
  .agents/skills          # canonical ceremonies — ALL eight (audit discover-skills kickoff lab-plan new-project review-corrections setup wrap)
  .claude/skills          # committed Claude Code copies — ALL eight
  .claude/hooks           # file-protection + any Claude hook scripts (recall hooks live under scripts/)
)

echo "[update] refreshing machinery from $REF…"
for p in "${MACHINERY[@]}"; do
  if git checkout "$REF" -- "$p" 2>/dev/null; then
    echo "[update]   refreshed $p"
  else
    echo "[update]   WARN: could not refresh $p (not in upstream tree?)" >&2
    had_error=$((had_error+1))
  fi
done

# .gitignore — APPEND-IF-MISSING, never whole-replace. A plain `git checkout` would
# overwrite the file and silently drop any ignore lines you added (itself a leak
# vector). Instead read upstream's via `git show` and append only the lines you don't
# already have — this delivers the Codex leak-control lines (.codex/,
# AGENTS.override.md, .lab/) with ZERO clobber of your own.
if up_gitignore="$(git show "$REF:.gitignore" 2>/dev/null)"; then
  touch "$ROOT/.gitignore"
  gi_added=0
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then continue; fi
    if ! grep -qxF -- "$line" "$ROOT/.gitignore"; then
      printf '%s\n' "$line" >> "$ROOT/.gitignore"
      gi_added=$((gi_added+1))
    fi
  done <<< "$up_gitignore"
  if [[ "$gi_added" -gt 0 ]]; then
    echo "[update]   .gitignore: appended $gi_added new line(s) (append-only — never removes yours)"
  else
    echo "[update]   .gitignore: already current"
  fi
else
  echo "[update]   WARN: could not read upstream .gitignore" >&2
  had_error=$((had_error+1))
fi

# refresh deps + reindex (best-effort)
[[ -x "$ROOT/.venv/bin/pip" ]] && "$ROOT/.venv/bin/pip" install -q --upgrade sqlite-vec fastembed 2>/dev/null || true
( cd "$ROOT" && bash scripts/recall.sh reindex --force >/dev/null 2>&1 ) || true

echo
if [[ "$had_error" -eq 0 ]]; then
  echo "[update] ✅ machinery refreshed to $REF; your personal layer was left untouched."
else
  echo "[update] ⚠️  machinery refreshed WITH $had_error warning(s) — some paths could NOT be"
  echo "[update]     updated (see the WARN lines above). Your engine may be half-updated;"
  echo "[update]     resolve those before relying on it."
fi
echo "[update]    Review:  git diff --staged"
echo "[update]    Commit:  git commit -m 'update lab machinery'"
echo
echo "[update] Personal files are NOT auto-updated. CLAUDE.md, AGENTS.md and"
echo "[update] recall.config.json are yours; if you want upstream's wording, diff by hand:"
echo "[update]    git diff HEAD $REF -- AGENTS.md CLAUDE.md recall.config.json"
echo "[update] One rename to apply by hand on a pre-2A Lab: the planning skill was"
echo "[update] renamed /plan -> /lab-plan. Update any '/plan' mention in your"
echo "[update] AGENTS.md / CLAUDE.md, and remove the stale orphan dir:"
echo "[update]    git rm -r .claude/skills/plan"
