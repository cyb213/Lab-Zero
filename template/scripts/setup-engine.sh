#!/usr/bin/env bash
# setup-engine.sh — the shared recall-engine setup spine (M1). SOURCED by both the
# Lab's bootstrap.sh AND a stamped project's bootstrap.sh, so the engine-setup steps
# (venv → pip deps → git drift-gate → .env → optional memory-seed → recall index) live
# in ONE place instead of being copy-pasted and silently drifting between the two.
#
# This file ONLY defines functions; it never runs setup at source time. Each caller
# (a bootstrap.sh) cd's into ROOT and sets these BEFORE calling setup_engine:
#   ROOT             — absolute workspace root (caller has already cd'd into it)
#   LZ_VENV_ARGS     — bash ARRAY of extra `python3 -m venv` args
#                      (Lab: () · project: (--system-site-packages))
#   LZ_PIP_DEPS      — bash ARRAY of pip deps to install
#                      (Lab: (sqlite-vec fastembed) · project: (sqlite-vec))
#   LZ_MEMORY_SEED   — 1 to seed starter memories into the Claude namespace (Lab only;
#                      a project's memory is seeded once at stamp time, not every run)
#
# The multi-word params are ARRAYS, never quoted scalars: `pip install "$SCALAR"` would
# pass "sqlite-vec fastembed" as ONE bogus package. They expand as "${LZ_PIP_DEPS[@]}".
#
# Behavior-preservation gate: set LZ_ENGINE_DRYRUN=1 to TRACE (echo) each command this
# would run instead of executing it — COMMANDS ONLY, never the [bootstrap] log prose
# (the two flavors used to differ on the prose; it's unified here). Every command flows
# through the same argv for both the trace and the exec, so the traced path cannot drift
# from the executed path. Golden-tested per flavor in tests/test_setup_engine.sh.

# Trace-or-exec: dry-run echoes the exact argv (so the trace can't drift from the
# command); otherwise exec it. Redirections/logging that must NOT appear in the trace
# are applied on the exec path only (never on the _run CALL — an outer redirect would
# also swallow the dry-run echo).
_run()   { if [[ -n "${LZ_ENGINE_DRYRUN:-}" ]]; then printf '%s\n' "$*"; else "$@"; fi; }
# Like _run, but the exec path is silenced + best-effort (never fatal) — for the pip
# self-upgrade, which is noise and must not abort the engine on a transient failure.
_run_q() { if [[ -n "${LZ_ENGINE_DRYRUN:-}" ]]; then printf '%s\n' "$*"; else "$@" >/dev/null 2>&1 || true; fi; }

setup_engine() {
  # venv + deps (first run may download a ~100MB embedding model; needs internet).
  if [[ ! -x "$ROOT/.venv/bin/python" ]]; then
    [[ -n "${LZ_ENGINE_DRYRUN:-}" ]] || echo "[bootstrap] creating .venv + installing recall deps…"
    _run python3 -m venv "${LZ_VENV_ARGS[@]}" "$ROOT/.venv"
  fi
  _run_q "$ROOT/.venv/bin/pip" install -q --upgrade pip
  _run "$ROOT/.venv/bin/pip" install -q "${LZ_PIP_DEPS[@]}"
  [[ -n "${LZ_ENGINE_DRYRUN:-}" ]] || echo "[bootstrap]   deps installed"

  # git drift-gate (needs a git repo). Single-source the command via an array so the
  # trace == the exec; preserve "quiet stdout, message only on success" (the install's
  # own stdout is suppressed; the failure case is set -e-exempt via the `elif` test).
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    local _hookcmd=(bash "$ROOT/scripts/install-git-hooks.sh")
    if [[ -n "${LZ_ENGINE_DRYRUN:-}" ]]; then
      printf '%s\n' "${_hookcmd[*]}"
    elif "${_hookcmd[@]}" >/dev/null; then
      echo "[bootstrap]   git drift-gate installed"
    fi
  else
    [[ -n "${LZ_ENGINE_DRYRUN:-}" ]] || echo "[bootstrap]   (not a git repo — skipping the drift-gate; clone with git to enable it)"
  fi

  # .env (optional — recall needs no keys). GUARDED form, safe for BOTH flavors: the
  # Lab always ships .env.example (so the guard is a no-op there); most projects don't,
  # so this also folds in the "guard the absent .env.example" lesson (D-014).
  if [[ -f "$ROOT/.env.example" && ! -f "$ROOT/.env" ]]; then
    _run cp "$ROOT/.env.example" "$ROOT/.env"
    [[ -n "${LZ_ENGINE_DRYRUN:-}" ]] || echo "[bootstrap]   created .env (optional — fill in only the keys you use)"
  fi

  # seed starter memories into this workspace's Claude Code memory namespace (Lab only).
  # The block stays INSIDE the function (it uses `local`); a full if-gate (NOT a bare
  # `[[ ]] && …`, which returns 1 under set -e and would abort). The dry-run marker uses
  # a LITERAL $HOME/<key> so the trace never carries a real /home/ path.
  if [[ "${LZ_MEMORY_SEED:-0}" == 1 ]]; then
    if [[ -n "${LZ_ENGINE_DRYRUN:-}" ]]; then
      printf '%s\n' "seed-memory $ROOT/memory-seed -> \$HOME/.claude/projects/<key>/memory"
    else
      local KEY NS copied f base
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
    fi
  fi

  # build the recall index (best-effort; a failure is non-fatal). Single-source the
  # command via an array so the trace == the exec.
  local _reindex=(bash scripts/recall.sh reindex --force)
  if [[ -n "${LZ_ENGINE_DRYRUN:-}" ]]; then
    printf '%s\n' "${_reindex[*]}"
  elif ( cd "$ROOT" && "${_reindex[@]}" >/dev/null 2>&1 ); then
    echo "[bootstrap]   recall indexed"
  else
    echo "[bootstrap]   WARN: reindex failed — run 'bash scripts/recall.sh reindex --force' manually" >&2
  fi
}
