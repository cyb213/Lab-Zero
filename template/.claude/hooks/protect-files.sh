#!/bin/bash
# protect-files.sh — block agent writes to protected files.
# PreToolUse hook (Edit|Write|NotebookEdit): JSON on stdin, exit 2 = block.
#
# Generic default: secrets + the engine config. Extend PROTECTED_PATTERNS per
# project (e.g. add "CLAUDE.md" to freeze the constitution once it's settled).

INPUT=$(cat)
FILE_PATH=$(python3 -c "import sys,json; print(json.loads(sys.argv[1]).get('tool_input',{}).get('file_path',''))" "$INPUT" 2>/dev/null)
[[ -z "$FILE_PATH" ]] && exit 0

PROTECTED_PATTERNS=(
    ".env"
    "recall.config.json"
)

for pattern in "${PROTECTED_PATTERNS[@]}"; do
    if [[ "$FILE_PATH" == *"$pattern"* ]]; then
        echo "BLOCKED: cannot modify protected file '$FILE_PATH' (matched: $pattern)" >&2
        exit 2
    fi
done
exit 0
