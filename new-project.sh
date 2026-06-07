#!/usr/bin/env bash
# new-project.sh — graduate an idea into its own full-rig workspace, stamped
# from your lab's template/. Each project is self-contained (clean copy,
# vendored identity). Identity is VENDORED (a copy of the lab's identity file);
# a future `lab sync <slug>` re-pulls engine + identity.
#
# Usage:
#   new-project.sh <slug> [options]
# Options:
#   --name "Display Name"   Human name (default: slug)
#   --purpose "one-liner"   One-line purpose (default: "TODO — fill in INTENT.md")
#   --root DIR              Parent dir (default: ~/Projects)
#   --full                  Also scaffold the optional genome docs (USER-STORIES/INCEPTION/ARCH-OQ)
#   --no-venv|--no-seed|--no-reindex|--no-git   Skip that step (testing/manual)
#
# Side effects: creates <root>/<slug>/ (its own git repo) and seeds its Claude
# Code memory namespace at ~/.claude/projects/<derived-key>/memory/.

set -euo pipefail

LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$LAB/template"
# Vendored-identity source: prefer a top-level IDENTITY.md, else
# identity/IDENTITY.md, else the first identity/*.md found. Vendored into each
# project as identity/IDENTITY.md regardless of the source filename.
if   [[ -f "$LAB/IDENTITY.md" ]];          then IDENTITY="$LAB/IDENTITY.md"
elif [[ -f "$LAB/identity/IDENTITY.md" ]]; then IDENTITY="$LAB/identity/IDENTITY.md"
else IDENTITY="$(ls "$LAB"/identity/*.md 2>/dev/null | head -n1 || true)"; fi
[[ -n "$IDENTITY" ]] || IDENTITY="$LAB/IDENTITY.md"   # missing-file is reported by the check below
# Seeded memories live in the lab's own CC memory namespace (derived from path).
LAB_KEY="$(printf '%s' "$LAB" | tr '/._' '-')"
LAB_NS="$HOME/.claude/projects/$LAB_KEY/memory"
REGISTRY="$LAB/Projects-REGISTRY.md"

# ── args ──────────────────────────────────────────────────────────────────────
SLUG=""; NAME=""; PURPOSE="TODO — fill in Source/INTENT.md"; ROOT="$HOME/Projects"
FULL=0; DO_VENV=1; DO_SEED=1; DO_REINDEX=1; DO_GIT=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2;;
    --purpose) PURPOSE="$2"; shift 2;;
    --root) ROOT="$2"; shift 2;;
    --full) FULL=1; shift;;
    --no-venv) DO_VENV=0; shift;;
    --no-seed) DO_SEED=0; shift;;
    --no-reindex) DO_REINDEX=0; shift;;
    --no-git) DO_GIT=0; shift;;
    -*) echo "unknown option: $1" >&2; exit 2;;
    *) [[ -z "$SLUG" ]] && SLUG="$1" || { echo "unexpected arg: $1" >&2; exit 2; }; shift;;
  esac
done
[[ -z "$SLUG" ]] && { echo "usage: new-project.sh <slug> [--name ..] [--purpose ..] [--root ..] [--full]" >&2; exit 2; }
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "slug must be lowercase alnum/hyphen: $SLUG" >&2; exit 2; }
[[ -z "$NAME" ]] && NAME="$SLUG"
[[ -d "$TEMPLATE" ]] || { echo "missing template: $TEMPLATE" >&2; exit 1; }
[[ -f "$IDENTITY" ]] || { echo "missing identity: $IDENTITY" >&2; exit 1; }

DEST="$ROOT/$SLUG"
[[ -e "$DEST" ]] && { echo "destination already exists: $DEST" >&2; exit 1; }
DATE="$(date +%Y-%m-%d)"

echo "[new-project] $NAME → $DEST"
mkdir -p "$DEST"
cp -r "$TEMPLATE"/. "$DEST"/

# optional genome docs
if [[ "$FULL" -eq 1 ]]; then
  cp "$DEST"/Source/_optional/*.md "$DEST"/Source/ 2>/dev/null || true
fi
rm -rf "$DEST/Source/_optional"

# vendored identity
mkdir -p "$DEST/identity"
cp "$IDENTITY" "$DEST/identity/IDENTITY.md"

# ── placeholder substitution + per-project config (python: safe quoting) ──────
DEST="$DEST" NAME="$NAME" SLUG="$SLUG" PURPOSE="$PURPOSE" DATE="$DATE" python3 - <<'PY'
import json, os
from pathlib import Path
dest=Path(os.environ["DEST"]); repl={
    "__PROJECT__": os.environ["NAME"], "__SLUG__": os.environ["SLUG"],
    "__PURPOSE__": os.environ["PURPOSE"], "__WORKSPACE__": str(dest),
    "__DATE__": os.environ["DATE"],
}
for p in dest.rglob("*"):
    if not p.is_file(): continue
    if any(seg in (".git",".venv") for seg in p.parts): continue
    try: t=p.read_text(encoding="utf-8")
    except Exception: continue
    if "__" in t:
        for k,v in repl.items(): t=t.replace(k,v)
        p.write_text(t, encoding="utf-8")
# per-project recall config: source = slug
cfgp=dest/"recall.config.json"; cfg=json.loads(cfgp.read_text()); cfg["source"]=os.environ["SLUG"]
cfgp.write_text(json.dumps(cfg, indent=2)+"\n", encoding="utf-8")
print(f"[new-project]   substituted placeholders; source={cfg['source']}")
PY

# ── venv ──────────────────────────────────────────────────────────────────────
if [[ "$DO_VENV" -eq 1 ]]; then
  echo "[new-project]   creating .venv (+ sqlite-vec; fastembed via system site-packages)"
  python3 -m venv --system-site-packages "$DEST/.venv"
  "$DEST/.venv/bin/pip" install -q sqlite-vec
fi

# ── seed memory into the project's CC namespace ──────────────────────────────
if [[ "$DO_SEED" -eq 1 ]]; then
  KEY="$(printf '%s' "$DEST" | tr '/._' '-')"
  NS="$HOME/.claude/projects/$KEY/memory"
  if [[ -d "$LAB_NS" ]]; then
    mkdir -p "$NS"; cp "$LAB_NS"/*.md "$NS"/ 2>/dev/null || true
    echo "[new-project]   seeded $(ls "$NS"/*.md 2>/dev/null | grep -c . ) memory files → $NS"
  else
    echo "[new-project]   WARN: Lab namespace $LAB_NS not found; skipped memory seed" >&2
  fi
fi

# ── git init + hooks + initial commit ────────────────────────────────────────
if [[ "$DO_GIT" -eq 1 ]]; then
  ( cd "$DEST"
    git init -q
    git config user.name "$(git -C "$LAB" config user.name 2>/dev/null || whoami)"
    git config user.email "$(git -C "$LAB" config user.email 2>/dev/null || echo you@example.com)"
    bash scripts/install-git-hooks.sh >/dev/null
    git add -A
    git commit -q -m "scaffold $SLUG from Lab template ($DATE)"
  )
  echo "[new-project]   git initialized + drift-gate installed + initial commit"
fi

# ── reindex recall (workspace + seeded auto-memory) ──────────────────────────
if [[ "$DO_REINDEX" -eq 1 && "$DO_VENV" -eq 1 ]]; then
  ( cd "$DEST"; bash scripts/recall.sh reindex --force >/dev/null 2>&1 ) \
    && echo "[new-project]   recall reindexed" \
    || echo "[new-project]   WARN: reindex failed (run 'bash scripts/recall.sh reindex --force' in the project)" >&2
fi

# ── register in the lab (skipped on --no-git so a structural dry-run is clean) ─
if [[ -f "$REGISTRY" && "$DO_GIT" -eq 1 ]]; then
  ROW="| $SLUG | $PURPOSE | $DEST | active |"
  if grep -q '_(none yet)_' "$REGISTRY"; then
    # replace the placeholder row (any row carrying the _(none yet)_ marker)
    python3 - "$REGISTRY" "$ROW" <<'PY'
import sys
p,row=sys.argv[1],sys.argv[2]
lines=open(p).read().splitlines()
for i,l in enumerate(lines):
    if "_(none yet)_" in l:
        lines[i]=row; break
open(p,"w").write("\n".join(lines)+"\n")
PY
  else
    # insert after the table header separator
    python3 - "$REGISTRY" "$ROW" <<'PY'
import sys
p,row=sys.argv[1],sys.argv[2]
lines=open(p).read().splitlines()
for i,l in enumerate(lines):
    if l.startswith("|------"): lines.insert(i+1,row); break
open(p,"w").write("\n".join(lines)+"\n")
PY
  fi
  echo "[new-project]   registered in $REGISTRY"
fi

echo
echo "[new-project] ✅ $NAME ready at $DEST"
echo "  next: cd $DEST → fill Source/INTENT.md + Source/SPEC.md → start session 1"
