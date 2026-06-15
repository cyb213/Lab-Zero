#!/usr/bin/env bash
# check-skills-sync.sh — shipped skills-sync drift gate (the D-004 "discipline as
# artifact" promise).
#
# A workspace ships its work-ceremonies in TWO dirs that must stay identical: the
# canonical .agents/skills/<X> and the committed clone-and-go copies .claude/skills/<X>.
# This asserts they're byte-identical. It runs standalone (default: this repo) and is
# invoked by the pre-commit hook when a commit touches either dir. Unlike the
# factory-only check-src-sync.sh (which guards root↔src), this SHIPS into every stamped
# project (and the Lab once it's a consumer) so the dual dirs can't silently drift
# downstream.
#
# No-op ONLY when BOTH dirs are absent (a skill-less workspace). One-sided presence is
# itself drift — a user must not be able to silence the gate by `rm -rf .agents/skills`
# and leaving a stale .claude/skills/ to ship.
#
# Usage:  bash check-skills-sync.sh [ROOT]     # ROOT defaults to the git toplevel / cwd
#         exits 0 if in sync (or nothing to gate), 1 on any drift.
set -euo pipefail

ROOT="${1:-}"
if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
AGENTS="$ROOT/.agents/skills"
CLAUDE="$ROOT/.claude/skills"

# Same cruft excludes check-src-sync.sh uses (never canonical content).
EXCL=(--exclude=__pycache__ --exclude='*.pyc' --exclude='.venv*' --exclude='.git')

# No-op only when BOTH are absent. One-sided = drift (handled by the loops below).
if [[ ! -d "$AGENTS" && ! -d "$CLAUDE" ]]; then
  exit 0
fi

drift=0
tmp="$(mktemp "${TMPDIR:-/tmp}/.skills-sync.XXXXXX")"

# Forward: each canonical .agents/skills/<name> must have a byte-identical
# .claude/skills/<name> clone-and-go copy.
if [[ -d "$AGENTS" ]]; then
  for d in "$AGENTS"/*/; do
    [[ -d "$d" ]] || continue                 # nullglob safety: unmatched glob stays literal
    name="$(basename "$d")"
    cp="$CLAUDE/$name"
    if [[ ! -d "$cp" ]]; then
      echo "[skills-sync] ✗ DRIFT: .agents/skills/$name has no .claude/skills/$name copy" >&2
      drift=1; continue
    fi
    if ! diff -rq "${EXCL[@]}" "$d" "$cp" >"$tmp" 2>&1; then
      echo "[skills-sync] ✗ DRIFT: .agents/skills/$name ↔ .claude/skills/$name differ:" >&2
      sed 's/^/        /' "$tmp" >&2
      drift=1
    fi
  done
fi

# Reverse: catch a .claude/skills/<name> with no canonical sibling — including the whole
# .agents/skills/ dir being absent (the `rm -rf .agents/skills` silencing shape).
if [[ -d "$CLAUDE" ]]; then
  for d in "$CLAUDE"/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    if [[ ! -d "$AGENTS/$name" ]]; then
      echo "[skills-sync] ✗ DRIFT: .claude/skills/$name has no canonical .agents/skills/$name" >&2
      drift=1
    fi
  done
fi

rm -f "$tmp" 2>/dev/null || true

if [[ "$drift" -eq 0 ]]; then
  exit 0
fi
echo "[skills-sync] ❌ .agents/skills/ and .claude/skills/ have drifted — re-sync the copies." >&2
exit 1
