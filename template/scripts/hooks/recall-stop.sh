#!/usr/bin/env bash
# Stop hook — capture the user's correction-keyword messages to a misses JSONL
# log (feedback loop for "recall results were bad / drifted anyway").
#
# Correction detection is the full pattern list in
# correction_detect.is_correction(); the event arrives on the handler's stdin
# instead of being interpolated into Python source (interpolation would break on
# a triple-quote sequence in the transcript and be an injection hazard).
#
# Best-effort: any failure exits 0 silently (never block a session close).

set -uo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_root() {
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    [[ -f "$d/recall.config.json" ]] && { echo "$d"; return; }
    d="$(dirname "$d")"
  done
  cd "$HOOK_DIR/../.." && pwd
}
ROOT="$(find_root)"
export RECALL_ROOT="$ROOT"
VENV_PY="$ROOT/.venv/bin/python"
[[ -x "$VENV_PY" ]] || VENV_PY="python3"

# Event JSON → handler stdin (no heredoc, no interpolation). The handler only has
# file side-effects (the misses log); silence its streams so nothing can pollute
# the JSON line below.
cat | "$VENV_PY" "$HOOK_DIR/../recall_stop_handler.py" >/dev/null 2>&1

# Stop REQUIRES JSON on stdout at exit 0 on Codex ("plain text output is invalid
# for this event"); the empty object is the no-op — no "decision":"block" ⇒ don't
# keep the agent running. Harmless on Claude (absent decision ⇒ allow stop). (D-010.)
printf '{}\n'
exit 0
