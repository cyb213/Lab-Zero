#!/usr/bin/env bash
# UserPromptSubmit hook — nudge a recall call when the prompt:
#   (a) mentions a codename NOT yet recalled this session, or
#   (b) contains drift verbs ("we already decided", "earlier", etc.).
#
# Per-session de-noise: tail the trail back to the last session_start sentinel;
# any codename already searched this session is suppressed. Paths + the codename
# regex come from recall.config.json.
#
# Hook input: JSON on stdin (UserPromptSubmit); we parse `.prompt`, else raw.
# stdout is added to the model's context for the next turn.

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
VENV_PY="$ROOT/.venv/bin/python"
[[ -x "$VENV_PY" ]] || VENV_PY="python3"

eval "$("$VENV_PY" "$HOOK_DIR/../recall_lib.py" --env 2>/dev/null)" || true
TRAIL="${RECALL_TRAIL:-$ROOT/memory/recall-trail.jsonl}"
REGEX="${RECALL_CODENAME_REGEX:-\\bsession[[:space:]]+[0-9]+\\b}"
mkdir -p "$(dirname "$TRAIL")"
[[ -f "$TRAIL" ]] || touch "$TRAIL"

RAW=$(cat)
# Parse JSON `.prompt`; fall back to raw stdin. RAW is piped in (no interpolation).
PROMPT=$(printf '%s' "$RAW" | "$VENV_PY" -c 'import json,sys
raw=sys.stdin.read().strip() or "{}"
try: print(json.loads(raw).get("prompt","") or "")
except Exception: print("")' 2>/dev/null)
[[ -z "$PROMPT" ]] && PROMPT="$RAW"

# Anchor "this session" at the last session_start line.
SESSION_START_LINE=$(grep -n '"event":"session_start"' "$TRAIL" 2>/dev/null | tail -1 | cut -d: -f1 || echo 0)
[[ -z "$SESSION_START_LINE" ]] && SESSION_START_LINE=0

ALREADY_RECALLED=""
if [[ "$SESSION_START_LINE" -gt 0 ]]; then
  ALREADY_RECALLED=$(tail -n +"$SESSION_START_LINE" "$TRAIL" 2>/dev/null \
    | grep '"event":"search"' | grep -oE "$REGEX" | sort -u || true)
fi

PROMPT_IDS=$(echo "$PROMPT" | grep -oE "$REGEX" | sort -u | head -5 || true)

NEW_IDS=""
while IFS= read -r ID; do
  [[ -z "$ID" ]] && continue
  echo "$ALREADY_RECALLED" | grep -qF -- "$ID" || NEW_IDS="$NEW_IDS $ID"
done <<< "$PROMPT_IDS"

DRIFT_HIT=""
if echo "$PROMPT" | grep -qiE "\b(we (already )?decided|earlier we|we agreed|we said|drift(ed)?|you (didn't|missed|should have) read|already established|look it up)\b"; then
  DRIFT_HIT=1
fi

if [[ -n "${NEW_IDS// /}" ]]; then
  echo "[recall] New codenames in prompt:$NEW_IDS — consider \`bash scripts/recall.sh '<id>'\` (not yet surfaced this session)."
fi
if [[ -n "$DRIFT_HIT" ]]; then
  echo "[recall] Prompt contains drift verbs (decided/earlier/agreed/etc.) — consider semantic recall before answering."
fi
exit 0
