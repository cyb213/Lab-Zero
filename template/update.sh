#!/usr/bin/env bash
# update.sh — refresh THIS PROJECT's engine MACHINERY from the published Lab Zero
# release, without touching your PERSONAL layer (your product, your docs, your
# identity, your history). Lands the latest PUBLISHED version (git tag), not a
# mid-flight branch HEAD.
#
#   Usage:
#     bash update.sh                 # update machinery to the latest published version
#     bash update.sh --check         # read-only: your version vs latest + what's new
#     bash update.sh --ref <tag|br>  # update to a specific tag (e.g. v1.17.0) or branch
#     bash update.sh --help
#
#   Machinery (refreshed from upstream): the recall + file-protection engine
#       (scripts/, .claude/hooks/), ALL shipped work-ceremony skills in BOTH the
#       canonical .agents/skills/ and the committed .claude/skills/ copies, the
#       engine tests/, bootstrap.sh, update.sh, the .agents/VERSION stamp, and —
#       merged in, never clobbered — the .gitignore leak-control lines.
#   Personal (left alone): AGENTS.md, CLAUDE.md, identity/, recall.config.json,
#       .claude/settings.json, .env, Log/, Sessions/, Source/, Reviews/, and your
#       agent memory namespace. AGENTS.md / CLAUDE.md are your constitution — yours
#       to edit; diff them against upstream by hand if you want engine-side wording
#       updates (see the footer).
#
#   .claude/settings.json is DELIBERATELY personal. It was written at stamp time with
#   this project's absolute path substituted in. Refreshing it would restore the raw
#   template placeholder and silently disable every hook.
#
# Don't hand-edit machinery files — they get overwritten here. Customize via the
# personal layer (identity / AGENTS / CLAUDE) instead.
#
# Where this pulls from — the published Lab Zero repo. Set LAB_ZERO_UPSTREAM to point
# somewhere else (your own fork, a local mirror); otherwise this project pulls from the
# canonical repo forever, which is wrong if you forked Lab Zero.
#
# Versioning — `update.sh` lands the latest PUBLISHED tag (e.g. v1.17.0), not whatever
# is on upstream's main branch right now. `--check` shows what you're on vs the latest
# plus the changelog; `--ref` pins a specific version (or a branch, to pull the
# bleeding edge). If upstream has no tags, it falls back to the branch HEAD.
#
# Limitation — extracting ADDS and UPDATES paths but NEVER DELETES. A skill or hook
# that was renamed/removed upstream leaves a stale local copy (an "orphan"); update.sh
# will not auto-remove it (deleting a path under your tree is unsafe). Your own
# scripts/check-skills-sync.sh pre-commit gate flags the skills case loudly — clean
# those by hand, e.g. `git rm -r .claude/skills/<orphan>`.
#
# Limitation — template CONTENT under personal directories never refreshes. Log/plans/
# TEMPLATE.md and the Source/ skeletons were stamped into your tree once and are yours
# now. That is deliberate (your Log/ and Source/ are your project's), but it does mean
# an improved plan template upstream will not reach this project. Copy it by hand if
# you want it.
#
# Note — this script reads upstream's `template/` subtree and lands it flat at your
# project root, because a stamped project IS that subtree flattened. Don't "simplify"
# it to a plain `git checkout` — that would create a literal template/ directory
# inside your project.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
UPSTREAM_URL="${LAB_ZERO_UPSTREAM:-https://github.com/cyb213/Lab-Zero.git}"
VERSION_FILE=".agents/VERSION"

# ── args (parse BEFORE any network; --help works even outside a git repo) ──────
MODE=update          # update | check
REF=""               # explicit --ref override (a tag like v1.17.0, or a branch)
usage() {
  cat <<'EOF'
update.sh — refresh this project's engine machinery from the published Lab Zero release.

  bash update.sh                 update machinery to the latest published version (git tag)
  bash update.sh --check         read-only: show your version vs latest + what's new
  bash update.sh --ref <tag|br>  update to a specific tag (e.g. v1.17.0) or a branch
  bash update.sh --help          this help

Refreshes only MACHINERY; your personal layer (your product, docs, identity, history)
is left alone. See the header of this file for the full machinery/personal split.

Env:
  LAB_ZERO_UPSTREAM   pull from a different Lab Zero repo (your fork, a local mirror).
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)   MODE=check ;;
    --ref)     shift; REF="${1:-}"
               [[ -n "$REF" ]] || { echo "[update] ERROR: --ref needs a value (a tag like v1.17.0, or a branch)." >&2; exit 2; } ;;
    --ref=*)   REF="${1#*=}"
               [[ -n "$REF" ]] || { echo "[update] ERROR: --ref needs a value (a tag like v1.17.0, or a branch)." >&2; exit 2; } ;;
    -h|--help) usage; exit 0 ;;
    -*)        echo "[update] ERROR: unknown flag '$1' (try --check, --ref <tag|branch>, --help)." >&2; exit 2 ;;
    *)         echo "[update] ERROR: unexpected argument '$1'." >&2; exit 2 ;;
  esac
  shift
done

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "[update] ERROR: not a git repo. This script extracts upstream files with git; run" >&2
  echo "[update]        'git init' here first (a stamped project is normally already a repo)." >&2; exit 1; }

# Highest vX.Y.Z tag from a ref/tag list on stdin (strips refs/tags/ + ^{} peels).
latest_semver() { sed -e 's#.*refs/tags/##' -e 's/\^{}$//' | grep -E '^v[0-9]' | sort -V | uniq | tail -1; }

# Your current engine version, from the release-written stamp. Absent ⇒ "unknown"
# (a project stamped before versioning, or from a local dev build) ⇒ always behind.
current_version() {
  local v=""
  [[ -f "$ROOT/$VERSION_FILE" ]] && v="$(head -1 "$ROOT/$VERSION_FILE" | tr -d '[:space:]')"
  printf '%s' "${v:-unknown}"
}

# ── --check : read-only current-vs-latest + changelog ──────────────────────────
# Makes NO changes to your files, machinery, or git history. The version compare is a
# pure `git ls-remote` read against the URL (no remote-add, no ref write) — so the
# common "you're current" path writes literally nothing. Only when behind does it
# fetch the new tag's objects (read-only network) to show the changelog.
if [[ "$MODE" == "check" ]]; then
  CURRENT="$(current_version)"

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
    echo "[update] ✅ This project is on the latest Lab Zero engine ($latest). Nothing to update."
    exit 0
  fi

  # Behind → fetch ONLY the new tag's objects (no remote-add, no local ref written)
  # and read the changelog from it.
  git fetch -q "$UPSTREAM_URL" "refs/tags/$latest" 2>/dev/null || true
  # NOTE the deliberate asymmetry: the version stamp comes from the template/ subtree
  # (it is the ENGINE-IN-A-PROJECT version), but the changelog comes from upstream's
  # ROOT. There is no template/CHANGELOG.md and there should not be — the changelog
  # describes the engine as a whole. Repointing this at template/CHANGELOG.md would
  # silently break --check.
  changelog="$(git show "FETCH_HEAD:CHANGELOG.md" 2>/dev/null || true)"

  if [[ "$CURRENT" == "unknown" ]]; then
    echo "[update] You're on:  unknown (stamped before engine versioning — older than $latest)"
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
# Deliberately does NOT `git remote add upstream` and does NOT write local tags. This
# project is a real repo with its OWN release tags; fetching upstream's v* tags into
# that namespace would collide with them. We fetch a single ref into FETCH_HEAD and
# resolve everything from there.
had_error=0

# Resolve the ref to update FROM, validated BEFORE the MACHINERY loop so a typo'd
# --ref fails fast instead of WARNing on every path behind a confusing half-update:
#   --ref override → the latest published tag → (no tags) the upstream default branch.
if [[ -n "$REF" ]]; then
  if   git fetch -q "$UPSTREAM_URL" "refs/tags/$REF" 2>/dev/null; then
    echo "[update] updating to pinned ref: $REF (tag)"
  elif git fetch -q "$UPSTREAM_URL" "refs/heads/$REF" 2>/dev/null; then
    echo "[update] updating to pinned ref: $REF (branch HEAD)"
  else
    echo "[update] ERROR: --ref '$REF' does not resolve to a tag or branch on upstream." >&2
    echo "[update]        upstream: $UPSTREAM_URL" >&2
    exit 2
  fi
else
  REF="$(git ls-remote --tags "$UPSTREAM_URL" 'refs/tags/v*' 2>/dev/null | latest_semver || true)"
  if [[ -n "$REF" ]]; then
    if ! git fetch -q "$UPSTREAM_URL" "refs/tags/$REF" 2>/dev/null; then
      echo "[update] ERROR: could not fetch $REF from $UPSTREAM_URL." >&2; exit 1
    fi
    echo "[update] latest published version: $REF"
  else
    if ! git fetch -q "$UPSTREAM_URL" HEAD 2>/dev/null; then
      echo "[update] ERROR: could not reach upstream ($UPSTREAM_URL)." >&2; exit 1
    fi
    REF="upstream HEAD"
    echo "[update] no version tags upstream — using branch HEAD."
  fi
fi
# Everything below reads FETCH_HEAD, which the fetch above just set. $REF is kept for
# display only from here on.
SRC=FETCH_HEAD

# machinery paths (the ONLY things refreshed), named RELATIVE TO YOUR PROJECT ROOT.
# Upstream stores them one level down, under template/ — the remap happens in the loop.
# Whole DIRECTORIES wherever possible so a future skill / hook is picked up
# automatically. Extracting adds/updates but NEVER deletes, so a renamed/removed path
# leaves an orphan (see the header + footer).
MACHINERY=(
  scripts                 # recall engine, wire-harness, setup-engine, check-skills-sync, git-hooks
  tests                   # engine tests
  bootstrap.sh            # harness wiring generator
  update.sh               # this script (so it can update itself)
  .agents/skills          # canonical ceremonies — ALL shipped skills (one dir per skill)
  .agents/VERSION         # release-stamped engine version (so this project knows what it runs)
  .claude/skills          # committed Claude Code copies — ALL shipped skills
  .claude/hooks           # file-protection hooks (recall hooks live under scripts/)
)

# ── dirty-machinery warning (D8) ───────────────────────────────────────────────
# We are about to overwrite these paths. Warn loudly if you have uncommitted work in
# them, but don't block — git recovers anything committed, and blocking can wedge you
# mid-task with no obvious way forward.
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  dirty="$(git status --porcelain -- "${MACHINERY[@]}" 2>/dev/null || true)"
  if [[ -n "$dirty" ]]; then
    echo "[update] ⚠️  WARNING: you have uncommitted changes under machinery paths." >&2
    printf '%s\n' "$dirty" | sed 's/^/[update]     /' >&2
    echo "[update]     These are about to be OVERWRITTEN. Ctrl-C now and commit or stash" >&2
    echo "[update]     them if you want to keep them. Machinery is meant to be upstream's;" >&2
    echo "[update]     customize via the personal layer (identity / AGENTS / CLAUDE) instead." >&2
    echo >&2
  fi
fi

echo "[update] refreshing machinery from $REF…"
# ONE `git archive` PER PATH, never a batch. A single archive naming several paths
# fails WHOLESALE if ANY one of them is missing at $SRC — non-zero, and NO output at
# all, so the paths that DO exist are lost too. Against an older --ref (or after an
# upstream rename) that would leave you with an unchanged tree behind a green banner.
# Per-path means a missing path costs you that path and nothing else. Do not "optimize"
# this into a single call.
#
# --strip-components=1 is the remap: upstream's template/scripts/ lands as scripts/.
# tar extracts UNSTAGED (unlike git checkout, which stages what it writes) — the footer
# says `git diff`, not `git diff --staged`, for exactly this reason. Modes ride along
# in the archive, so exec bits on scripts and hooks survive.
for p in "${MACHINERY[@]}"; do
  if git archive "$SRC" "template/$p" 2>/dev/null | tar -x -C "$ROOT" --strip-components=1 2>/dev/null; then
    echo "[update]   refreshed $p"
  else
    echo "[update]   WARN: could not refresh $p (not in upstream tree at $REF?)" >&2
    had_error=$((had_error+1))
  fi
done

# .gitignore — APPEND-IF-MISSING, never whole-replace. A plain extract would overwrite
# the file and silently drop any ignore lines you added (itself a leak vector). Instead
# read upstream's via `git show` and append only the lines you don't already have —
# this delivers the Codex leak-control lines (.codex/, AGENTS.override.md, .lab/) with
# ZERO clobber of your own.
#
# Reads $SRC:template/.gitignore, NOT $SRC:.gitignore. The repo root's .gitignore is
# Lab Zero's OWN, for the Lab-Zero clone; yours is the one under template/. Reading the
# root one here would deliver the wrong rules — and miss the leak-control lines
# entirely.
if up_gitignore="$(git show "$SRC:template/.gitignore" 2>/dev/null)"; then
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
  echo "[update]   WARN: could not read upstream template/.gitignore" >&2
  had_error=$((had_error+1))
fi

# refresh deps + reindex (best-effort)
[[ -x "$ROOT/.venv/bin/pip" ]] && "$ROOT/.venv/bin/pip" install -q --upgrade sqlite-vec fastembed 2>/dev/null || true
( cd "$ROOT" && bash scripts/recall.sh reindex --force >/dev/null 2>&1 ) || true

NEWVER="$(current_version)"
echo
if [[ "$had_error" -eq 0 ]]; then
  echo "[update] ✅ machinery refreshed to $REF (engine now $NEWVER); your personal layer was left untouched."
else
  echo "[update] ⚠️  machinery refreshed WITH $had_error warning(s) — some paths could NOT be"
  echo "[update]     updated (see the WARN lines above). Your engine may be half-updated;"
  echo "[update]     resolve those before relying on it."
fi
# tar extracts to the WORKING TREE and stages nothing, so review with a plain diff.
echo "[update]    Review:  git diff"
echo "[update]    Commit:  git add -A && git commit -m 'update engine machinery to $NEWVER'"
echo
echo "[update] Personal files are NOT auto-updated. CLAUDE.md, AGENTS.md,"
echo "[update] identity/ and recall.config.json are yours. To see upstream's current"
echo "[update] wording for the constitution, read it directly:"
echo "[update]    git show $SRC:template/AGENTS.md | less"
echo "[update] If you drive this project on Codex, re-run the harness wiring — the"
echo "[update] generated .codex/ layer is git-ignored and does NOT refresh here:"
echo "[update]    bash bootstrap.sh --harness codex"
