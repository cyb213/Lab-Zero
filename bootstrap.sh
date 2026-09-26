#!/usr/bin/env bash
# bootstrap.sh — one-time setup for a freshly cloned Lab.
# Idempotent: safe to re-run (e.g. after moving the clone, or to add a harness).
#
# What it does: sets up the recall engine (a Python venv with its deps), installs
# the git drift-gate, seeds the starter memories, builds the recall index, and
# WIRES your coding agent(s) to this clone.
#
#   bash bootstrap.sh                       # Claude Code (default) — today's behavior
#   bash bootstrap.sh --harness claude,codex  # ALSO wire OpenAI Codex on this workspace
#
# `--harness` is the desired FULL set: re-running with a smaller set de-provisions
# the dropped harness's generated files. Recall embeds locally (fastembed) — no API
# key required. Claude wiring is the committed-substitute model (settings.json); the
# Codex layer is GENERATED clone-locally (and git-ignored), never committed.
#
# Advanced: set LAB_BOOTSTRAP_SKIP_ENGINE=1 to (re-)wire harnesses only, skipping the
# recall-engine install/index (useful after a move, or in CI).
set -euo pipefail

# ── parse args ────────────────────────────────────────────────────────────────
HARNESS_CSV="claude"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --harness)   HARNESS_CSV="${2:-}"; [[ -n "$HARNESS_CSV" ]] || { echo "[bootstrap] ERROR: --harness needs a value (e.g. claude,codex)" >&2; exit 1; }; shift 2 ;;
    --harness=*) HARNESS_CSV="${1#*=}"; shift ;;
    -h|--help)   echo "usage: bash bootstrap.sh [--harness claude[,codex]]"; exit 0 ;;
    *)           echo "[bootstrap] ERROR: unknown argument: $1 (try: --harness claude,codex)" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
echo "[bootstrap] Lab root: $ROOT"

# python3 is required for the wiring (and the engine); check once, up front.
command -v python3 >/dev/null || { echo "[bootstrap] ERROR: python3 not found. Install Python 3.9+ and re-run." >&2; exit 1; }

# normalize + validate the desired harness set (dedup; only claude|codex supported)
WANT_CLAUDE=0; WANT_CODEX=0
IFS=',' read -ra _hs <<< "$HARNESS_CSV"
for h in "${_hs[@]}"; do
  h="$(printf '%s' "$h" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  [[ -z "$h" ]] && continue
  case "$h" in
    claude) WANT_CLAUDE=1 ;;
    codex)  WANT_CODEX=1 ;;
    *)      echo "[bootstrap] ERROR: unknown harness '$h' (supported: claude, codex)" >&2; exit 1 ;;
  esac
done
[[ "$WANT_CLAUDE" -eq 1 || "$WANT_CODEX" -eq 1 ]] || { echo "[bootstrap] ERROR: no valid harness in --harness '$HARNESS_CSV'" >&2; exit 1; }
echo "[bootstrap] harnesses: $([[ $WANT_CLAUDE -eq 1 ]] && printf 'claude ')$([[ $WANT_CODEX -eq 1 ]] && printf 'codex')"

# ── the recall engine (shared spine; sourced) ──────────────────────────────────
# The venv → pip deps → git drift-gate → .env → memory-seed → recall-index spine is
# shared with every stamped project via scripts/setup-engine.sh (ONE tested code path,
# array-parameterized per flavor). Fail CLOSED if it's missing: a `&& source` would turn
# a missing lib into a silent exit-0 that skips the whole engine. Lab flavor: plain venv,
# sqlite-vec + fastembed, AND seed the starter memories.
[[ -f "$ROOT/scripts/setup-engine.sh" ]] || { echo "[bootstrap] ERROR: scripts/setup-engine.sh missing (engine incomplete — re-clone or run update.sh)." >&2; exit 1; }
source "$ROOT/scripts/setup-engine.sh"
LZ_VENV_ARGS=()                       # plain venv (fastembed installs into it)
LZ_PIP_DEPS=(sqlite-vec fastembed)    # multi-word → ARRAY, never a quoted scalar
LZ_MEMORY_SEED=1                      # seed starter memories (Lab only)

# ── wiring (shared engine generator; sourced) ──────────────────────────────────
# All per-harness wiring (wire_claude / wire_codex / wire_identity_override /
# deprovision_codex / record_harnesses) lives in scripts/wire-harness.sh so the Lab and
# every stamped project share ONE generator (and the one risky bit — the identity
# matcher — is centralized + unit-tested). Fail CLOSED if it's missing: a `&& source`
# would turn a missing lib into a silent no-wire exit-0.
[[ -f "$ROOT/scripts/wire-harness.sh" ]] || { echo "[bootstrap] ERROR: scripts/wire-harness.sh missing (engine incomplete — re-clone or run update.sh)." >&2; exit 1; }
source "$ROOT/scripts/wire-harness.sh"
# Lab identity shape: top-level IDENTITY.md, imported in AGENTS.md as the bare @IDENTITY.md.
export LZ_IDENTITY_SRC="$ROOT/IDENTITY.md"
export LZ_IDENTITY_TOKEN="@IDENTITY.md"

# ── run ────────────────────────────────────────────────────────────────────────
if [[ -n "${LAB_BOOTSTRAP_SKIP_ENGINE:-}" ]]; then
  echo "[bootstrap]   LAB_BOOTSTRAP_SKIP_ENGINE set — skipping recall-engine install/index (wiring only)"
else
  setup_engine
fi

[[ "$WANT_CLAUDE" -eq 1 ]] && wire_claude
if [[ "$WANT_CODEX" -eq 1 ]]; then wire_codex; else deprovision_codex; fi
record_harnesses

echo
echo "[bootstrap] ✅ done."
if [[ "$WANT_CODEX" -eq 1 ]]; then
  echo "[bootstrap]"
  echo "[bootstrap] ── Codex: one-time trust step (recall AND file-protection are OFF + SILENT until you do it) ──"
  echo "[bootstrap]    Codex ignores this project's .codex/ wiring until the PROJECT is trusted, and"
  echo "[bootstrap]    skips each hook until its hash is trusted — both fail silently (no error)."
  echo "[bootstrap]    Two kinds of hook need that approval here:"
  echo "[bootstrap]      • recall (SessionStart/UserPromptSubmit/Stop) — injects your memory + context;"
  echo "[bootstrap]      • file-protection (PreToolUse) — blocks apply_patch edits to .env / recall.config.json."
  echo "[bootstrap]        Until you approve it, that protection is OFF — even if you trusted recall earlier."
  echo "[bootstrap]    The helper agents (.codex/agents/: lab-reader, lab-reviewer) need no /hooks step,"
  echo "[bootstrap]    but they too load only once the project is trusted."
  echo "[bootstrap]    • In an interactive Codex session here, approve the project's hooks (the /hooks review)."
  echo "[bootstrap]    • Headless/CI: hook-trust bypass is version-dependent and may not exist in your Codex"
  echo "[bootstrap]      (e.g. 0.130.0 has no bypass flag) — the one-time interactive approval is the reliable path."
fi
echo "[bootstrap]    Next: open this folder in your agent and run /setup to personalize your IDENTITY.md."
