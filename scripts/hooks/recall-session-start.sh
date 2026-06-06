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

eval "$("$VENV_PY" "$HOOK_DIR/../recall_lib.py" --env 2>/dev/null)" || true
TRAIL="${RECALL_TRAIL:-$ROOT/memory/recall-trail.jsonl}"
mkdir -p "$(dirname "$TRAIL")"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"ts":"%s","event":"session_start"}\n' "$TS" >> "$TRAIL"

# Short banner (kept terse to reduce habituation).
cat <<'EOF'
[recall] scripts/recall.sh "<query>" — semantic search over your workspace docs + auto-memory.
[recall] Cite file:line in reply; re-Read source on (act | <2-line snippet | "..." | heading-mismatch | user challenge).
EOF

# Project registry surface (the workspace's project index; harmless where absent).
REGISTRY="$ROOT/Projects-REGISTRY.md"
[[ -f "$REGISTRY" ]] && echo "[lab] project registry: Projects-REGISTRY.md"
exit 0
