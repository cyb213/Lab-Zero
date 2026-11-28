#!/usr/bin/env bash
# bootstrap.sh — one-time setup for a project stamped from your Lab (or freshly
# cloned to a new machine). Idempotent: safe to re-run (to add/drop a harness, or to
# re-wire Codex after a move).
#
# What it does: sets up the recall engine (a Python venv with its deps), installs the
# git drift-gate, builds the recall index, and WIRES your coding agent(s) to this
# project.
#
#   bash bootstrap.sh                       # Claude Code (default)
#   bash bootstrap.sh --harness claude,codex  # ALSO wire OpenAI Codex on this project
#
# `--harness` is the desired FULL set: re-running with a smaller set de-provisions the
# dropped harness's generated files. Recall embeds locally (fastembed) — no API key
# required. Claude wiring is committed (.claude/settings.json, whose commands use
# ${CLAUDE_PROJECT_DIR} — nothing to substitute since D-114); the Codex layer is
# GENERATED clone-locally with absolute paths (and git-ignored), never committed.
#
# When you stamp with `new-project.sh <slug> --harness claude,codex`, the Lab runs this
# (wiring only) for you at stamp time — you only run it by hand to add/drop a harness
# later, or to stand the project up after cloning it to another machine.
#
# Advanced: set LAB_BOOTSTRAP_SKIP_ENGINE=1 to (re-)wire harnesses only, skipping the
# recall-engine install/index (how new-project.sh invokes it; also useful to re-wire
# Codex after a move).
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
echo "[bootstrap] project root: $ROOT"

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
# The SAME spine the Lab uses (scripts/setup-engine.sh) — ONE tested code path,
# array-parameterized per flavor. Fail CLOSED if it's missing: a `&& source` would turn
# a missing lib into a silent no-engine exit-0. Project flavor: venv
# --system-site-packages (fastembed comes from the system site-packages, mirroring
# new-project.sh) + sqlite-vec only, and NO memory-seed (a project's memory is seeded
# once at stamp time, not on every bootstrap).
[[ -f "$ROOT/scripts/setup-engine.sh" ]] || { echo "[bootstrap] ERROR: scripts/setup-engine.sh missing (engine incomplete — re-stamp or re-clone)." >&2; exit 1; }
source "$ROOT/scripts/setup-engine.sh"
LZ_VENV_ARGS=(--system-site-packages)   # fastembed via the system site-packages
LZ_PIP_DEPS=(sqlite-vec)                 # multi-word → ARRAY, never a quoted scalar
LZ_MEMORY_SEED=0                         # projects are seeded at stamp time, not here

# ── wiring (shared engine generator; sourced) ──────────────────────────────────
# The SAME generator the Lab uses (scripts/wire-harness.sh) wires this project too —
# one tested code path. Fail CLOSED if it's missing: a `&& source` would turn a missing
# lib into a silent no-wire exit-0.
[[ -f "$ROOT/scripts/wire-harness.sh" ]] || { echo "[bootstrap] ERROR: scripts/wire-harness.sh missing (engine incomplete — re-stamp or re-clone)." >&2; exit 1; }
source "$ROOT/scripts/wire-harness.sh"
# Project identity shape: vendored identity/IDENTITY.md, imported in AGENTS.md as the
# bare @identity/IDENTITY.md (DIFFERENT from the Lab's @IDENTITY.md — the two-parameter
# matcher in wire-harness.sh is exactly what makes both resolve correctly).
export LZ_IDENTITY_SRC="$ROOT/identity/IDENTITY.md"
export LZ_IDENTITY_TOKEN="@identity/IDENTITY.md"

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
  echo "[bootstrap]    Codex ignores this project's .codex/ wiring until the PROJECT is trusted (an untrusted"
  echo "[bootstrap]    codex exec prints one warning line), and skips each hook until you approve it (silently)."
  echo "[bootstrap]    Two kinds of hook need that approval here:"
  echo "[bootstrap]      • recall (SessionStart/UserPromptSubmit/Stop) — injects your memory + context;"
  echo "[bootstrap]      • file-protection (PreToolUse) — blocks apply_patch edits to .env / recall.config.json."
  echo "[bootstrap]        Until you approve it, that protection is OFF — even if you trusted recall earlier."
  echo "[bootstrap]    The helper agents (.codex/agents/: lab-reader, lab-reviewer) need no /hooks step,"
  echo "[bootstrap]    but they too load only once the project is trusted."
  echo "[bootstrap]    • Interactive (recommended): trust the project when Codex asks, then approve the"
  echo "[bootstrap]      project's hooks in the /hooks review. Both approvals persist."
  echo "[bootstrap]    • Headless (codex exec) needs both layers, each with its own flag (tested on Codex 0.172.0):"
  echo "[bootstrap]      --trust saves trust for this project and future chats, including MCP commands outside"
  echo "[bootstrap]        the sandbox — a lasting change; undo it by deleting the project's entry in ~/.codex/config.toml."
  echo "[bootstrap]      --dangerously-bypass-hook-trust runs all enabled hooks for that one run without approval."
  echo "[bootstrap]        Codex's own warning: \"DANGEROUS. Intended only for automation that already vets hook sources.\""
  echo "[bootstrap]      Older Codex builds may lack these flags (0.130.0 lacked the hook-trust bypass)."
fi
echo "[bootstrap]    Identity is vendored at identity/IDENTITY.md — edit it there if it needs updating."
echo "[bootstrap]    Next: open this folder in your agent and start working (see Log/STATUS.md)."
