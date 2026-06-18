#!/usr/bin/env bash
# SessionStart hook — writes the session_start sentinel to the recall trail
# (the denominator anchor recall-user-prompt.sh greps to de-dupe nudges) and
# prints a short availability banner, plus a project-registry surface where one
# is present (the workspace's index of graduated projects).
#
# Side-effect-free other than appending one trail JSONL line.

set -uo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve workspace root: nearest recall.config.json from cwd, else scripts/../..
find_root() {
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    [[ -f "$d/recall.config.json" ]] && { echo "$d"; return; }
    d="$(dirname "$d")"
  done
  cd "$HOOK_DIR/../.." && pwd
}
ROOT="$(find_root)"
VENV_PY="$ROOT/.venv/bin/python"
[[ -x "$VENV_PY" ]] || VENV_PY="python3"

# Emit text as the hookSpecificOutput.additionalContext JSON envelope — the shape
# BOTH Claude Code and Codex accept. Codex *rejects* raw-text hook stdout (a banner
# starting with '[' trips its JSON auto-parse → "invalid session start JSON output");
# Claude injects additionalContext the same as it does raw stdout. (D-010.)
emit_context() {  # $1 = hookEventName ; $2 = additionalContext
  HOOK_EVENT="$1" HOOK_CTX="$2" "$VENV_PY" -c 'import json,os
print(json.dumps({"hookSpecificOutput":{"hookEventName":os.environ["HOOK_EVENT"],"additionalContext":os.environ["HOOK_CTX"]}}))' 2>/dev/null \
    || printf '%s\n' "$2"
}

eval "$("$VENV_PY" "$HOOK_DIR/../recall_lib.py" --env 2>/dev/null)" || true
TRAIL="${RECALL_TRAIL:-$ROOT/memory/recall-trail.jsonl}"
MISSES="${RECALL_MISSES:-$ROOT/memory/recall-misses.jsonl}"
mkdir -p "$(dirname "$TRAIL")"

# ── log rotation (keep-tail K + hysteresis) — runs once/session, BEFORE the new sentinel
# so it never drops the anchor it's about to write. Keep-tail preserves the most-recent
# session_start (the de-noise reader greps the LAST one) AND both nudge cadence markers
# (update_check_nudged + corrections_review_nudged are line-position-based, so dropping the
# last one silently resets that nudge's count) AND the misses high-water-mark — all live at
# the tail. Hysteresis (trigger only past keep+keep/4, then trim back to keep) avoids
# per-session churn. set -u SAFE: every var defaulted; offline; best-effort (no -e here).
ROTATE_KEEP="${LAB_RECALL_LOG_KEEP:-2000}"
[[ "$ROTATE_KEEP" =~ ^[1-9][0-9]*$ ]] || ROTATE_KEEP=2000
rotate_log() {  # $1 = log file
  local f="$1" n margin
  [[ -f "$f" ]] || return 0
  n="$(wc -l < "$f" 2>/dev/null || echo 0)"; n="${n//[^0-9]/}"; n="${n:-0}"
  margin="$((ROTATE_KEEP / 4))"
  if [[ "$n" -gt "$((ROTATE_KEEP + margin))" ]]; then
    tail -n "$ROTATE_KEEP" "$f" > "$f.rot.$$" 2>/dev/null && mv -f "$f.rot.$$" "$f"
  fi
}
rotate_log "$TRAIL"
rotate_log "$MISSES"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"ts":"%s","event":"session_start"}\n' "$TS" >> "$TRAIL"

# Developer-context payload: the terse recall banner (kept short to reduce
# habituation) plus the project-registry surface where one is present.
CTX='[recall] scripts/recall.sh "<query>" — semantic search over your workspace docs + auto-memory.
[recall] Cite file:line in reply; re-Read source on (act | <2-line snippet | "..." | heading-mismatch | user challenge).'

# Project registry surface (the workspace's project index; harmless where absent).
REGISTRY="$ROOT/Projects-REGISTRY.md"
[[ -f "$REGISTRY" ]] && CTX="$CTX
[lab] project registry: Projects-REGISTRY.md"

# ── update-check cadence nudge — ONLY in a deployed Lab Zero consumer ──────────
# update.sh exists only in a deployed clone (graduated projects + the factory ship
# none), so `[[ -f "$ROOT/update.sh" ]]` self-gates this block — the one shared hook
# stays byte-identical everywhere yet activates only where it belongs. OFFLINE-SAFE:
# no network here, just a local count of session starts since the last nudge; the
# agent's `bash update.sh --check` is the (networked) arbiter. set -u SAFE: every var
# is defaulted (an unbound-var abort here would fire BEFORE emit_context, killing the
# recall banner + emitting malformed JSON — the D-010 failure Codex rejects). stdout
# SILENT: the nudge goes only into $CTX, carried by the single emit_context envelope
# below (SessionStart stdout must stay exactly one JSON object).
if [[ -f "$ROOT/update.sh" ]]; then
  N="${LAB_UPDATE_CHECK_EVERY:-12}"
  [[ "$N" =~ ^[1-9][0-9]*$ ]] || N=12              # empty/garbage ⇒ default (set -u safe)
  last_nudge="$(grep -n '"event":"update_check_nudged"' "$TRAIL" 2>/dev/null | tail -1 | cut -d: -f1)"
  last_nudge="${last_nudge:-0}"                     # no marker yet ⇒ count from the start
  since="$(tail -n +"$((last_nudge+1))" "$TRAIL" 2>/dev/null | grep -c '"event":"session_start"')"
  since="${since:-0}"
  if [[ "$since" -ge "$N" ]]; then
    CTX="$CTX
[update] ~$since sessions since your last Lab Zero update check — run \`bash update.sh --check\` to see if a newer version is out."
    printf '{"ts":"%s","event":"update_check_nudged"}\n' "$TS" >> "$TRAIL"
  fi
fi

# ── corrections-review cadence nudge — wherever recall runs, when pending > 0 ──────────
# Sibling of the update-check block, with two differences: (a) NOT gated on update.sh —
# corrections are captured wherever recall runs (factory + consumer + graduated project), so
# this fires everywhere there's something to triage; (b) additionally gated on pending-count > 0
# (nothing pending ⇒ silent). Same set -u safety + single-envelope discipline (the nudge goes
# only into $CTX). OFFLINE: pending-count + the cadence count are both local reads. The agent
# runs /review-corrections at a natural break — this never auto-acts. (B1, D3.)
CN="${LAB_CORRECTION_REVIEW_EVERY:-8}"
[[ "$CN" =~ ^[1-9][0-9]*$ ]] || CN=8                # empty/garbage ⇒ default (set -u safe)
PENDING="$("$VENV_PY" "$HOOK_DIR/../recall_lib.py" --pending-count 2>/dev/null || echo 0)"
PENDING="${PENDING//[^0-9]/}"; PENDING="${PENDING:-0}"
if [[ "$PENDING" -gt 0 ]]; then
  last_cnudge="$(grep -n '"event":"corrections_review_nudged"' "$TRAIL" 2>/dev/null | tail -1 | cut -d: -f1)"
  last_cnudge="${last_cnudge:-0}"                   # no marker yet ⇒ count from the start
  csince="$(tail -n +"$((last_cnudge+1))" "$TRAIL" 2>/dev/null | grep -c '"event":"session_start"')"
  csince="${csince:-0}"
  if [[ "$csince" -ge "$CN" ]]; then
    CTX="$CTX
[corrections] $PENDING pending correction candidate(s) — run \`/review-corrections\` to triage them into memory."
    printf '{"ts":"%s","event":"corrections_review_nudged"}\n' "$TS" >> "$TRAIL"
  fi
fi

emit_context SessionStart "$CTX"
exit 0
