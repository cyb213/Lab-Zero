#!/usr/bin/env bash
# check-constitution-drift.sh — advisory check: is the engine prose in this workspace's
# constitution (AGENTS.md / CLAUDE.md) still current? (D-096)
#
# WHY THIS EXISTS
#   update.sh's MACHINERY deliberately EXCLUDES AGENTS.md and CLAUDE.md: extraction is
#   whole-file, so refreshing them would destroy project-owned content (a project's own
#   sections, its purpose, its delegation notes). Correct — but it creates a gap. Engine
#   prose that lives inside those personal files can never reach an already-stamped
#   workspace, so it silently goes stale. The engine self-updates; the constitution never
#   does. This script is how you find out.
#
# WHAT IT DOES
#   For each constitution, reads the release-generated baseline beside it in scripts/ and
#   reports any engine-owned line that is no longer present. That is all. It never edits,
#   never fetches, never blocks.
#
# THE SELECTION RULE (why the baseline looks the way it does)
#   The baseline holds every non-blank line of the upstream constitution that contains no
#   stamp-time placeholder. Such lines are excluded because new-project.sh substitutes five
#   of them
#   (__PROJECT__ __SLUG__ __PURPOSE__ __WORKSPACE__ __DATE__) with free text that cannot
#   be recovered here — __PROJECT__ becomes a display name, __PURPOSE__ arbitrary prose.
#   Excluding them means a plain literal comparison suffices: no regex, no metachar
#   escaping, no vacuous matcher, and no false warning at someone who correctly filled in
#   their own purpose.
#
# THREE HARD CONSTRAINTS — each earned, none decorative:
#   1. IT MUST NEVER CHANGE ITS CALLER'S EXIT STATUS. The shipped pre-commit runs under
#      `set -euo pipefail`, where a non-zero child kills the hook, ABORTS the commit, and
#      skips the redaction verdict that follows. Hence: no `set -e` here, `exit 0` always,
#      and the hook invokes it with `|| true` as a second belt.
#   2. IT MUST FAIL OPEN. A missing/unreadable baseline, or an absent/empty/binary
#      constitution, means "cannot tell" — which prints NOTHING. A broken install must not
#      also become a noisy one.
#   3. `grep -Fxq -e` — NEVER `grep -Fxq "$line"`. Constitution files are bullet lists, so
#      most lines begin with "-", which grep parses as an OPTION. Without -e this script
#      reports every line as missing. That bug is not hypothetical: it produced a false
#      "missing from all 5 projects" reading during this feature's own verification.
#
# Bash 3.2 compatible — it ships to stock macOS, where bash is 3.2. Only POSIX-era
# builtins and plain indexed arrays; tests/test_precommit_gates.sh holds the exact
# construct denylist and enforces it against this file, so it is not restated here.
# Usage: bash scripts/check-constitution-drift.sh [repo_root]
set -uo pipefail

ROOT="${1:-$PWD}"
[ -d "$ROOT" ] || exit 0

check_one() {   # $1=constitution filename  $2=baseline filename
  cf="$ROOT/$1"
  bf="$ROOT/scripts/$2"
  # Fail-open gates, in cheapest-first order.
  [ -f "$bf" ] && [ -r "$bf" ] && [ -s "$bf" ] || return 0
  [ -f "$cf" ] && [ -r "$cf" ] && [ -s "$cf" ] || return 0
  grep -Iq . "$cf" 2>/dev/null || return 0     # binary ⇒ cannot tell ⇒ stay silent

  missing=0
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    if ! grep -Fxq -e "$line" "$cf" 2>/dev/null; then
      if [ "$missing" -eq 0 ]; then
        printf '[constitution] ⚠️  %s carries engine prose that is out of date:\n' "$1" >&2
      fi
      missing=$(( missing + 1 ))
      printf '[constitution]     expected: %s\n' "$line" >&2
    fi
  done < "$bf"

  if [ "$missing" -gt 0 ]; then
    printf '[constitution]     %s line(s) differ from the shipped engine.\n' "$missing" >&2
    printf '[constitution]     %s is yours to edit, so this is advisory only — nothing is blocked.\n' "$1" >&2
    printf '[constitution]     If you reworded a line deliberately, ignore this.\n' >&2
  fi
  return 0
}

check_one "AGENTS.md" "constitution-baseline-AGENTS.txt"
check_one "CLAUDE.md" "constitution-baseline-CLAUDE.txt"

exit 0
