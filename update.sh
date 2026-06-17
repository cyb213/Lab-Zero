#!/usr/bin/env bash
# update.sh — refresh the Lab MACHINERY from upstream (Lab-Zero) without touching
# your PERSONAL layer.
#
#   Machinery (refreshed from upstream): the recall + file-protection engine
#       (scripts/, .claude/hooks/), ALL SIX work-ceremony skills in BOTH the
#       canonical .agents/skills/ and the committed .claude/skills/ copies, the
#       project template/, the engine tests/, new-project.sh, bootstrap.sh,
#       update.sh, README.md, LICENSE, .env.example, the memory-seed/, and — merged
#       in, never clobbered — the .gitignore leak-control lines.
#   Personal (left alone): IDENTITY.md, AGENTS.md, CLAUDE.md, recall.config.json,
#       .claude/settings.json, .env, Projects-REGISTRY.md, Log/, Sessions/, and your
#       agent memory namespace. AGENTS.md / CLAUDE.md are your constitution — yours
#       to edit; diff them against upstream by hand if you want engine-side wording
#       updates (see the footer).
#
# Don't hand-edit machinery files — they get overwritten here. Customize via the
# personal layer (IDENTITY / AGENTS / CLAUDE) instead.
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

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "[update] ERROR: not a git repo. Re-clone from $UPSTREAM_URL to enable updates." >&2; exit 1; }

# ensure an 'upstream' remote points at Lab-Zero
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$UPSTREAM_URL"
  echo "[update] added remote upstream -> $UPSTREAM_URL"
fi
git fetch -q upstream
BR="$(git remote show upstream 2>/dev/null | sed -n 's/.*HEAD branch: //p')"; BR="${BR:-main}"

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
  LICENSE
  .env.example            # engine env template (your live .env stays personal)
  memory-seed
  .agents/skills          # canonical ceremonies — ALL six (audit kickoff lab-plan new-project setup wrap)
  .claude/skills          # committed Claude Code copies — ALL six
  .claude/hooks           # file-protection + any Claude hook scripts (recall hooks live under scripts/)
)

echo "[update] refreshing machinery from upstream/$BR…"
had_error=0
for p in "${MACHINERY[@]}"; do
  if git checkout "upstream/$BR" -- "$p" 2>/dev/null; then
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
if up_gitignore="$(git show "upstream/$BR:.gitignore" 2>/dev/null)"; then
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
  echo "[update] ✅ machinery refreshed; your personal layer was left untouched."
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
echo "[update]    git diff HEAD upstream/$BR -- AGENTS.md CLAUDE.md recall.config.json"
echo "[update] One rename to apply by hand on a pre-2A Lab: the planning skill was"
echo "[update] renamed /plan -> /lab-plan. Update any '/plan' mention in your"
echo "[update] AGENTS.md / CLAUDE.md, and remove the stale orphan dir:"
echo "[update]    git rm -r .claude/skills/plan"
