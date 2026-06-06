#!/usr/bin/env bash
# update.sh — refresh the Lab MACHINERY from upstream (Lab-Zero) without touching
# your PERSONAL layer.
#
#   Machinery (refreshed): recall engine (scripts/), project template (template/),
#       tests/, new-project.sh, bootstrap.sh, update.sh, README.md, memory-seed/,
#       the /kickoff /new-project /setup skills, and the protect-files hook.
#   Personal (left alone): IDENTITY.md, CLAUDE.md, recall.config.json,
#       .claude/settings.json, .env, Projects-REGISTRY.md, Log/, Sessions/,
#       and your Claude Code memory namespace.
#
# Don't hand-edit machinery files — they get overwritten here. Customize via the
# personal layer instead.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
UPSTREAM_URL="${LAB_ZERO_UPSTREAM:-https://github.com/cyb213/Lab-Zero.git}"

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "[update] ERROR: not a git repo. Re-clone from $UPSTREAM_URL to enable updates." >&2; exit 1; }

# ensure an 'upstream' remote points at Lab-Zero
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$UPSTREAM_URL"
  echo "[update] added remote upstream -> $UPSTREAM_URL"
fi
git fetch -q upstream
BR="$(git remote show upstream 2>/dev/null | sed -n 's/.*HEAD branch: //p')"; BR="${BR:-main}"

# machinery paths (the ONLY things refreshed)
MACHINERY=(
  scripts
  template
  tests
  new-project.sh
  bootstrap.sh
  update.sh
  README.md
  memory-seed
  .claude/skills/kickoff
  .claude/skills/new-project
  .claude/skills/setup
  .claude/hooks/protect-files.sh
)

echo "[update] refreshing machinery from upstream/$BR…"
for p in "${MACHINERY[@]}"; do
  git checkout "upstream/$BR" -- "$p" 2>/dev/null && echo "[update]   refreshed $p" || true
done

# refresh deps + reindex (best-effort)
[[ -x "$ROOT/.venv/bin/pip" ]] && "$ROOT/.venv/bin/pip" install -q --upgrade sqlite-vec fastembed 2>/dev/null || true
( cd "$ROOT" && bash scripts/recall.sh reindex --force >/dev/null 2>&1 ) || true

echo
echo "[update] ✅ machinery refreshed; your personal layer was left untouched."
echo "[update]    Review:  git diff --staged"
echo "[update]    Commit:  git commit -m 'update lab machinery'"
echo "[update]    (CLAUDE.md and recall.config.json are personal and NOT auto-updated;"
echo "[update]     if you want upstream's versions, diff them manually against upstream/$BR.)"
