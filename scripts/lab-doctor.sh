#!/usr/bin/env bash
# lab-doctor.sh — F1: a read-only health-check for a Lab Zero install.
#
# Prints OK / WARN / FAIL / INFO lines — each problem carries the one line that fixes it —
# then exits 1 iff the install is BROKEN (any FAIL: venv / deps / config / index / model),
# else 0 (WARN/INFO are advisory). The non-zero is a cheap "is this install broken?" boolean
# for a human or a wrapper; nothing auto-invokes the doctor. It writes NOTHING and touches
# no retrieval code — purely diagnostic.
#
# Why it exists: the engine reports problems only reactively + cryptically — a missing/broken
# .venv makes recall.sh silently fall back to system python3, so a search dies with "search
# failed (index missing?)" when the real cause is an unimportable sqlite_vec/fastembed; the
# A3 model-mismatch / no-FTS / no-heading warnings fire only when you happen to search; index
# staleness is invisible; Codex hook trust fails silently. `lab doctor` consolidates these.
#
# Self-referential design: a doctor that ran INSIDE .venv could not start if .venv were broken,
# so the entry is bash. The venv + Codex-wiring + formatting + exit code live here; the recall/
# DB/deps health is delegated to `recall_lib.py --doctor` (TSV on stdout — jq is not assumed).
# DB introspection there needs only stdlib sqlite3, so the doctor degrades gracefully: even
# with no venv it still reports schema/model/freshness AND flags the deps as missing.
#
# Usage:  bash scripts/lab-doctor.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Resolve workspace root: nearest recall.config.json, else git toplevel (mirror recall.sh) ──
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

# Colour only on a TTY (so a captured/piped run stays plain text for parsing).
if [[ -t 1 ]]; then C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_FAIL=$'\033[31m'; C_INFO=$'\033[36m'; C_OFF=$'\033[0m'
else C_OK=""; C_WARN=""; C_FAIL=""; C_INFO=""; C_OFF=""; fi

WORST_FAIL=0   # set to 1 by any FAIL row → drives the exit code

# emit <severity> <check> <detail> [fix] — format one row + track the worst severity.
emit() {
  local sev="$1" check="$2" detail="$3" fix="${4:-}" col tag
  case "$sev" in
    OK)   col="$C_OK";   tag="OK  " ;;
    WARN) col="$C_WARN"; tag="WARN" ;;
    FAIL) col="$C_FAIL"; tag="FAIL"; WORST_FAIL=1 ;;
    INFO) col="$C_INFO"; tag="INFO" ;;
    *)    col="";        tag="$sev" ;;
  esac
  if [[ -n "$fix" ]]; then
    printf '  %s%s%s  %-22s %s  → %s\n' "$col" "$tag" "$C_OFF" "$check" "$detail" "$fix"
  else
    printf '  %s%s%s  %-22s %s\n' "$col" "$tag" "$C_OFF" "$check" "$detail"
  fi
}

echo "lab doctor — Lab Zero install health (read-only)"
echo "  root: $ROOT"
echo

# ── 1. venv — shell-level, BEFORE any python (the self-referential check, R1) ─────────────
# Pick VENV_PY exactly like recall.sh:38-39 and report WHICH interpreter we used, so a broken
# venv yields a clean FAIL line instead of a Python stack trace.
VENV_PY="$ROOT/.venv/bin/python"
if [[ -x "$VENV_PY" ]]; then
  emit OK venv ".venv present" ""
else
  VENV_PY="python3"
  emit FAIL venv "no .venv (using system python3 — recall deps likely missing)" "run bootstrap.sh"
fi

# ── 2. recall / DB / deps health — delegate to recall_lib (TSV on STDOUT) ──────────────────
# Capture STDOUT only; recall_lib's `[recall]` notes go to STDERR (a fresh clone with no
# auto-memory namespace emits one) and must NOT enter the parse — so NO 2>&1 here (reviewer #3).
DOCTOR_TSV="$("$VENV_PY" "$SCRIPT_DIR/recall_lib.py" --doctor || true)"
if [[ -z "$DOCTOR_TSV" ]]; then
  emit FAIL recall "recall_lib.py --doctor produced no output" "check $SCRIPT_DIR/recall_lib.py"
else
  # here-string (NOT a pipe) so emit's WORST_FAIL mutations persist in THIS shell.
  while IFS=$'\t' read -r sev check detail fix; do
    [[ -z "$sev" ]] && continue
    emit "$sev" "$check" "$detail" "$fix"
  done <<< "$DOCTOR_TSV"
fi

# ── 3. Codex wiring — honest: verify FILES only; trust is interactive + not machine-readable ─
# Gate on a desired-Codex signal (.codex/ exists OR .lab/harnesses names codex). On a Claude-
# only workspace this is one INFO line, not noise. Codex problems are WARN, never FAIL — an
# unwired harness doesn't make the recall install "broken" (D4: exit-1 is venv/deps/index/model).
codex_desired=0
if [[ -d "$ROOT/.codex" ]] || { [[ -f "$ROOT/.lab/harnesses" ]] && grep -qx codex "$ROOT/.lab/harnesses" 2>/dev/null; }; then
  codex_desired=1
fi

# D7 / R9: table-aware features.hooks detection (port of wire-harness.sh:85-97). A bare
# `grep 'hooks = true'` is table-blind (false-matches another TOML table); tomllib is 3.11+
# so it can't be assumed → dotted-form match OR a walk scoped within the [features] table.
features_hooks_on() {
  local cfg="$1"
  [[ -f "$cfg" ]] || return 1
  python3 - "$cfg" <<'PY' 2>/dev/null
import re, sys
text = open(sys.argv[1]).read()
if re.search(r'(?m)^\s*features\.hooks\s*=\s*true\b', text):   # dotted form, anywhere
    sys.exit(0)
lines = text.split("\n")
fi = next((i for i, l in enumerate(lines) if re.match(r'\s*\[features\]\s*$', l)), None)
if fi is not None:                                            # within the [features] table
    j = fi + 1
    while j < len(lines) and not re.match(r'\s*\[', lines[j]):
        if re.match(r'\s*hooks\s*=\s*true\b', lines[j]):
            sys.exit(0)
        j += 1
sys.exit(1)
PY
}

if [[ "$codex_desired" -eq 0 ]]; then
  emit INFO codex "not wired (Claude-only workspace)" ""
else
  HJ="$ROOT/.codex/hooks.json"
  if [[ -f "$HJ" ]] && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$HJ" 2>/dev/null; then
    emit OK "codex:hooks.json" "present and parses" ""
  elif [[ -f "$HJ" ]]; then
    emit WARN "codex:hooks.json" "present but not valid JSON" "re-run bootstrap.sh"
  else
    emit WARN "codex:hooks.json" "missing" "re-run bootstrap.sh"
  fi

  if features_hooks_on "$ROOT/.codex/config.toml"; then
    emit OK "codex:features.hooks" "enabled in config.toml" ""
  else
    emit WARN "codex:features.hooks" "not enabled in config.toml" "re-run bootstrap.sh"
  fi

  if [[ -f "$ROOT/AGENTS.override.md" ]]; then
    emit OK "codex:identity" "AGENTS.override.md present" ""
  else
    emit WARN "codex:identity" "AGENTS.override.md missing (no identity shadow)" "re-run bootstrap.sh"
  fi

  # ALWAYS print, even when every file is OK (Rule-Zero / D-009): a green files-check must
  # never be read as "recall fires" — Codex trust is granted interactively and is not
  # verifiable here. This INFO line is the honest ceiling.
  emit INFO "codex:trust" "files only — run /hooks in Codex to trust (not verifiable here)" ""
fi

echo
if [[ "$WORST_FAIL" -eq 1 ]]; then
  echo "lab doctor: ${C_FAIL}FAIL${C_OFF} — this install has problems (see the → fixes above)."
  exit 1
else
  echo "lab doctor: ${C_OK}OK${C_OFF} — install is healthy."
  exit 0
fi
