#!/usr/bin/env bash
# Generalized semantic memory wrapper.
#
# Stack: sqlite + sqlite-vec (pip package) + fastembed (all-MiniLM-L6-v2, 384d).
# Config-driven via recall.config.json (read through scripts/recall_lib.py) so
# the same engine serves the Lab and every stamped project unchanged.
#
# Usage:
#   recall.sh "query"                    # default subcommand: search
#   recall.sh search "query" [--top-k N]
#   recall.sh reindex [--force]
#   recall.sh stats
#   recall.sh expand <hash>
#
# Search invocations:
#   1. ID short-circuit: grep codenames in the query across id_search_dirs.
#   2. sqlite-vec KNN on the indexed corpus.
#   3. Append a JSONL trail entry (feed-denominator metric).

set -euo pipefail

# ── Resolve workspace root: nearest recall.config.json, else git toplevel ──────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
find_root() {
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    [[ -f "$d/recall.config.json" ]] && { echo "$d"; return; }
    d="$(dirname "$d")"
  done
  git rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR"
}
ROOT="$(find_root)"
cd "$ROOT"

VENV_PY="$ROOT/.venv/bin/python"
[[ -x "$VENV_PY" ]] || VENV_PY="python3"
INDEXER="$SCRIPT_DIR/recall-index.py"
SEARCHER="$SCRIPT_DIR/recall-search.py"

# Pull resolved config (DB, TRAIL, SOURCE, regex, id dirs). recall_lib enforces
# the isolation guard here too — a bad config aborts before any DB touch.
eval "$("$VENV_PY" "$SCRIPT_DIR/recall_lib.py" --env)"
DB="$RECALL_DB"
TRAIL="$RECALL_TRAIL"
mkdir -p "$(dirname "$TRAIL")"

cmd="${1:-search}"
case "$cmd" in
  search|reindex|stats|expand) shift ;;
  *) cmd="search" ;;
esac

case "$cmd" in
  reindex)
    "$VENV_PY" "$INDEXER" "$@"
    ;;

  stats)
    if [[ ! -f "$DB" ]]; then
      echo "[recall] no index at $DB — run 'recall.sh reindex --force' first"
      exit 0
    fi
    sqlite3 "$DB" <<SQL
.mode column
.headers on
SELECT COUNT(*) AS chunks, COUNT(DISTINCT path) AS files,
       MIN(updated_at) AS oldest, MAX(updated_at) AS newest
FROM chunks WHERE source='$RECALL_SOURCE';
SQL
    ;;

  expand)
    HASH="${1:?hash required}"
    if [[ ! -f "$DB" ]]; then
      echo "[recall] no index at $DB"
      exit 2
    fi
    sqlite3 "$DB" <<SQL
.mode list
.headers off
SELECT path || ':' || start_line || '-' || end_line || char(10) || char(10) || text
FROM chunks WHERE source='$RECALL_SOURCE' AND hash='$HASH' LIMIT 1;
SQL
    ;;

  search)
    QUERY="$*"
    if [[ -z "$QUERY" ]]; then
      echo "usage: recall.sh \"query\"" >&2
      exit 2
    fi

    # ID short-circuit (grep -rn; rg not assumed present).
    IDS=$(echo "$QUERY" | grep -oE "$RECALL_CODENAME_REGEX" | sort -u | head -10 || true)
    if [[ -n "$IDS" ]]; then
      echo "## ID short-circuit"
      DIRS=()
      for d in $RECALL_ID_SEARCH_DIRS; do
        [[ -d "$ROOT/$d" ]] && DIRS+=("$ROOT/$d")
      done
      if [[ ${#DIRS[@]} -gt 0 ]]; then
        while IFS= read -r ID; do
          [[ -z "$ID" ]] && continue
          grep -rn --include='*.md' -e "$ID" "${DIRS[@]}" 2>/dev/null | head -8 || true
        done <<< "$IDS"
      fi
      echo ""
    fi

    echo "## Semantic search"
    "$VENV_PY" "$SEARCHER" "$QUERY" || \
      echo "[recall] search failed (index missing? run 'recall.sh reindex --force')"

    # Trail (feed-denominator metric).
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    QESC=$(printf '%s' "$QUERY" | "$VENV_PY" -c "import sys,json;print(json.dumps(sys.stdin.read()))")
    IDC=$(echo "$IDS" | grep -c . 2>/dev/null || echo 0)
    printf '{"ts":"%s","event":"search","query":%s,"id_hits":%s}\n' "$TS" "$QESC" "$IDC" >> "$TRAIL"
    ;;
esac
