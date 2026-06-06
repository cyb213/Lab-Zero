#!/usr/bin/env bash
# bootstrap.sh — one-time setup for a freshly cloned Lab.
# Idempotent: safe to re-run (e.g. after moving the clone to a new path).
#
# What it does: creates a Python venv with the recall engine's deps, installs the
# git drift-gate, wires the hooks to this clone's path, creates your .env, seeds
# the starter memories into your Claude Code memory namespace, and builds the
# recall index. Recall embeds locally (fastembed) — no API key required.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
echo "[bootstrap] Lab root: $ROOT"

# 1. python3
command -v python3 >/dev/null || { echo "[bootstrap] ERROR: python3 not found. Install Python 3.9+ and re-run." >&2; exit 1; }

# 2. venv + deps (first run downloads a ~100MB embedding model; needs internet)
if [[ ! -x "$ROOT/.venv/bin/python" ]]; then
  echo "[bootstrap] creating .venv + installing sqlite-vec + fastembed…"
  python3 -m venv "$ROOT/.venv"
fi
"$ROOT/.venv/bin/pip" install -q --upgrade pip >/dev/null 2>&1 || true
"$ROOT/.venv/bin/pip" install -q sqlite-vec fastembed
echo "[bootstrap]   deps installed"

# 3. git drift-gate (needs a git repo)
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  bash "$ROOT/scripts/install-git-hooks.sh" >/dev/null && echo "[bootstrap]   git drift-gate installed"
else
  echo "[bootstrap]   (not a git repo — skipping the drift-gate; clone with git to enable it)"
fi

# 4. wire hooks: substitute __WORKSPACE__ -> this clone's absolute path
ROOT="$ROOT" python3 - <<'PY'
import os, pathlib
root = os.environ["ROOT"]
p = pathlib.Path(root) / ".claude" / "settings.json"
t = p.read_text()
if "__WORKSPACE__" in t:
    p.write_text(t.replace("__WORKSPACE__", root))
    print("[bootstrap]   wired hooks -> " + root)
else:
    print("[bootstrap]   hooks already wired (re-run with a fresh checkout to re-wire)")
PY

# 5. .env (optional — recall needs no keys)
if [[ ! -f "$ROOT/.env" ]]; then
  cp "$ROOT/.env.example" "$ROOT/.env" && echo "[bootstrap]   created .env (optional — fill in only the keys you use)"
fi

# 6. seed starter memories into this lab's Claude Code memory namespace
KEY="$(printf '%s' "$ROOT" | tr '/._' '-')"
NS="$HOME/.claude/projects/$KEY/memory"
mkdir -p "$NS"
copied=0
for f in "$ROOT"/memory-seed/*.md; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f")"
  if [[ ! -e "$NS/$base" ]]; then cp "$f" "$NS/$base"; copied=$((copied+1)); fi
done
echo "[bootstrap]   seeded $copied new memory file(s) -> $NS"

# 7. build the recall index
( cd "$ROOT" && bash scripts/recall.sh reindex --force >/dev/null 2>&1 ) \
  && echo "[bootstrap]   recall indexed" \
  || echo "[bootstrap]   WARN: reindex failed — run 'bash scripts/recall.sh reindex --force' manually" >&2

echo
echo "[bootstrap] ✅ done."
echo "[bootstrap]    Next: open this folder in Claude Code and run /setup to personalize your IDENTITY.md."
