#!/usr/bin/env bash
# wire-harness.sh — the shared engine generator (M1). SOURCED by both the Lab's
# bootstrap.sh AND a stamped project's bootstrap.sh, so the per-harness wiring lives
# in ONE place. The one genuinely risky bit — resolving the identity import into the
# Codex shadow (AGENTS.override.md) — is centralized in wire_identity_override and
# unit-tested directly, instead of being copy-pasted and silently drifting.
#
# This file ONLY defines functions; it never runs wiring at source time. Each caller
# (a bootstrap.sh) sets these before calling the functions:
#   ROOT              — absolute workspace root
#   WANT_CLAUDE       — 1 to wire Claude (committed-substitute settings.json)
#   WANT_CODEX        — 1 to wire Codex (generated/clone-local/git-ignored), else de-provision
#   LZ_IDENTITY_SRC   — absolute path to the identity file to inline
#                       (Lab: $ROOT/IDENTITY.md · project: $ROOT/identity/IDENTITY.md)
#   LZ_IDENTITY_TOKEN — the EXACT import line to replace
#                       (Lab: @IDENTITY.md · project: @identity/IDENTITY.md)
# LZ_IDENTITY_SRC + LZ_IDENTITY_TOKEN are the TWO-PARAMETER identity matcher. Reusing
# the Lab's hardcoded (@IDENTITY.md → IDENTITY.md) matcher on a project would SILENTLY
# resolve nothing — Codex would get NO identity, with no error. Asserted byte-exact,
# both shapes, in tests/test_codex_stamp.sh.

# ── Claude wiring (committed-substitute, unchanged): __WORKSPACE__ -> abs path ──
wire_claude() {
  ROOT="$ROOT" python3 - <<'PY'
import os, pathlib
root = os.environ["ROOT"]
p = pathlib.Path(root) / ".claude" / "settings.json"
t = p.read_text()
if "__WORKSPACE__" in t:
    p.write_text(t.replace("__WORKSPACE__", root))
    print("[bootstrap]   wired Claude hooks -> " + root)
else:
    print("[bootstrap]   Claude hooks already wired (re-run with a fresh checkout to re-wire)")
PY
}

# ── Codex wiring (GENERATED from the canonical core; clone-local, git-ignored) ──
# recall hooks + feature flag + the file-protection PreToolUse hook (2B′:
# apply_patch-aware; always emitted — inert on Codex builds that don't surface
# apply_patch to PreToolUse, and gated behind the one-time /hooks trust). The
# identity shadow is resolved separately by wire_identity_override (the M1 centerpiece).
wire_codex() {
  ROOT="$ROOT" python3 - <<'PY'
import os, json, pathlib, re
root = os.environ["ROOT"]
R = pathlib.Path(root)
cdir = R / ".codex"
cdir.mkdir(exist_ok=True)

# (a) recall hooks — lift the recall events out of .claude/settings.json (.hooks)
#     (schema is identical to Codex's hooks.json) and substitute __WORKSPACE__.
settings = json.loads((R / ".claude" / "settings.json").read_text())
src = settings.get("hooks", {})
RECALL = ("SessionStart", "UserPromptSubmit", "Stop")
hooks = {ev: src[ev] for ev in RECALL if ev in src}

# (a2) file-protection (PreToolUse) — 2B′. Select the protect-files entry BY COMMAND
#      (never an array index — that isn't stable), and broaden its matcher to also
#      catch Codex's apply_patch tool. Always emit: it's inert on Codex builds that
#      don't surface apply_patch to PreToolUse, and bootstrap can't know which Codex
#      you'll later run. The shared protect-files.sh parses the apply_patch payload.
prot = []
for entry in src.get("PreToolUse", []):
    hks = entry.get("hooks", [])
    if any("protect-files.sh" in hk.get("command", "") for hk in hks):
        e = json.loads(json.dumps(entry))           # deep copy (don't mutate source)
        m = e.get("matcher", "")
        if "apply_patch" not in m:
            e["matcher"] = (m + "|apply_patch") if m else "apply_patch"
        prot.append(e)
if prot:
    hooks["PreToolUse"] = prot

blob = json.dumps({"hooks": hooks}, indent=2).replace("__WORKSPACE__", root)
(cdir / "hooks.json").write_text(blob + "\n")

# (b) feature flag — ensure features.hooks = true in .codex/config.toml via a
#     targeted text-edit (NO tomllib round-trip: that drops comments / ordering /
#     inline [[hooks]] tables). Never write the deprecated `codex_hooks` alias.
cfg = cdir / "config.toml"
if not cfg.exists():
    cfg.write_text("[features]\nhooks = true\n")
else:
    text = cfg.read_text()
    if not re.search(r'(?m)^\s*features\.hooks\s*=\s*true\b', text):   # not already enabled (dotted form)
        lines = text.split("\n")
        fi = next((i for i, l in enumerate(lines) if re.match(r'\s*\[features\]\s*$', l)), None)
        if fi is not None:                                            # existing [features] table
            j, done = fi + 1, False
            while j < len(lines) and not re.match(r'\s*\[', lines[j]):  # within the section
                m = re.match(r'(\s*)hooks\s*=\s*(.*)$', lines[j])
                if m:
                    lines[j] = f"{m.group(1)}hooks = true"; done = True; break
                j += 1
            if not done:
                lines.insert(fi + 1, "hooks = true")
            cfg.write_text("\n".join(lines))
        else:                                                        # no [features] table → append one
            sep = "" if text.endswith("\n") else "\n"
            cfg.write_text(text + sep + "\n[features]\nhooks = true\n")
PY
  wire_identity_override
  echo "[bootstrap]   wired Codex: .codex/hooks.json + config.toml (features.hooks) + AGENTS.override.md"
}

# ── identity shadow (the two-parameter matcher; the M1 centerpiece) ────────────
# Codex does NOT resolve @-imports, but it reads a per-directory AGENTS.override.md
# that shadows AGENTS.md. Generate it (untracked/git-ignored) = the canonical AGENTS.md
# body with ONLY the bare LZ_IDENTITY_TOKEN line replaced by LZ_IDENTITY_SRC's contents.
# The tracked AGENTS.md is never mutated, so no personal data ever enters a tracked file;
# regenerates from pristine source each run (so /setup edits propagate). The path+token
# are parameters precisely so the Lab and a stamped project — whose import lines DIFFER —
# both resolve correctly (see header).
wire_identity_override() {
  ROOT="$ROOT" LZ_IDENTITY_SRC="$LZ_IDENTITY_SRC" LZ_IDENTITY_TOKEN="$LZ_IDENTITY_TOKEN" python3 - <<'PY'
import os, pathlib
R = pathlib.Path(os.environ["ROOT"])
src = os.environ["LZ_IDENTITY_SRC"]
token = os.environ["LZ_IDENTITY_TOKEN"]
identity = pathlib.Path(src).read_text()
if not identity.endswith("\n"):
    identity += "\n"
out = [identity if line.strip() == token else line
       for line in (R / "AGENTS.md").read_text().splitlines(keepends=True)]
(R / "AGENTS.override.md").write_text("".join(out))
PY
}

# ── de-provision Codex when it's dropped from the desired set ──────────────────
# Removes only the files WE generate (no rm -rf on a variable); leaves any
# user-authored .codex/config.toml content intact.
deprovision_codex() {
  ROOT="$ROOT" python3 - <<'PY'
import os, pathlib
R = pathlib.Path(os.environ["ROOT"])
removed = []
ov = R / "AGENTS.override.md"
if ov.exists(): ov.unlink(); removed.append("AGENTS.override.md")
cdir = R / ".codex"
hk = cdir / "hooks.json"
if hk.exists(): hk.unlink(); removed.append(".codex/hooks.json")
cfg = cdir / "config.toml"
if cfg.exists() and cfg.read_text() == "[features]\nhooks = true\n":   # only if it's exactly our generated file
    cfg.unlink(); removed.append(".codex/config.toml")
if cdir.exists():
    try: cdir.rmdir()        # only succeeds if now empty (keeps user content)
    except OSError: pass
if removed:
    print("[bootstrap]   removed Codex wiring (de-selected): " + ", ".join(removed))
PY
}

# ── active-harness state (.lab/harnesses) ──────────────────────────────────────
# Records the desired set whenever a generated harness (codex) is active; collapses
# back to nothing for a Claude-only (committed-baseline) workspace, so state on disk
# never disagrees with what's wired.
record_harnesses() {
  if [[ "$WANT_CODEX" -eq 1 ]]; then
    mkdir -p "$ROOT/.lab"
    { [[ "$WANT_CLAUDE" -eq 1 ]] && echo claude; echo codex; } > "$ROOT/.lab/harnesses"
  else
    rm -f "$ROOT/.lab/harnesses"
    rmdir "$ROOT/.lab" 2>/dev/null || true
  fi
}
