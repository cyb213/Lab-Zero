#!/bin/bash
# protect-files.sh — block agent writes to protected files.
# PreToolUse hook: JSON on stdin, exit 2 = block.
#
# Harness-aware:
#   • Claude (Edit|Write|NotebookEdit) → tool_input.file_path is the target path.
#   • Codex (apply_patch)              → tool_input carries the PATCH TEXT; the target
#     path(s) live in the patch's `*** Update/Add/Delete File:` / `*** Move to:`
#     directive lines. We match those path lines ONLY (never the patch body), so an
#     edit that merely mentions a protected name in its content is not blocked.
#
# Generic default: secrets + the engine config. Extend PROTECTED_PATTERNS per
# project (e.g. add "CLAUDE.md" to freeze the constitution once it's settled).
#
# Codex caveat: the PreToolUse hook-stdin envelope key for apply_patch is not yet
# version-pinned, so the Codex branch reads the patch DEFENSIVELY (tool_input.command,
# then .input, then any string value, then raw stdin). It is best-effort: on Codex
# versions that don't surface apply_patch edits to PreToolUse, the edit never reaches
# this hook (fails open). The Claude path is read first and independently, so a Codex
# parse miss can never turn a Claude block into an allow.

INPUT=$(cat)

LZ_HOOK_INPUT="$INPUT" python3 - <<'PY'
import os, re, sys, json

raw = os.environ.get("LZ_HOOK_INPUT", "")

PROTECTED_PATTERNS = (".env", "recall.config.json")

def matched_pattern(path):
    for pat in PROTECTED_PATTERNS:
        if pat in path:
            return pat
    return None

def block(path, pat):
    sys.stderr.write("BLOCKED: cannot modify protected file '%s' (matched: %s)\n" % (path, pat))
    sys.exit(2)

try:
    data = json.loads(raw)
except Exception:
    data = None

# ── Claude: tool_input.file_path (decided independently, FIRST) ────────────────
file_path = ""
if isinstance(data, dict):
    ti = data.get("tool_input")
    if isinstance(ti, dict):
        fp = ti.get("file_path")
        if isinstance(fp, str):
            file_path = fp
if file_path:
    pat = matched_pattern(file_path)
    if pat:
        block(file_path, pat)
    sys.exit(0)   # a path was given and it's not protected — done (Codex branch never runs)

# ── Codex: apply_patch — only when there is no file_path ───────────────────────
patch = ""
if isinstance(data, dict):
    ti = data.get("tool_input")
    if isinstance(ti, dict):
        for key in ("command", "input"):              # documented key, then transcript key
            v = ti.get(key)
            if isinstance(v, str) and "*** Begin Patch" in v:
                patch = v
                break
        if not patch:                                 # any other string value carrying a patch
            for v in ti.values():
                if isinstance(v, str) and "*** Begin Patch" in v:
                    patch = v
                    break
    elif isinstance(ti, str) and "*** Begin Patch" in ti:   # tool_input is itself the patch string
        patch = ti
if not patch and "*** Begin Patch" in raw:            # last resort: scan the whole raw stdin
    patch = raw

if patch:
    paths = []
    for m in re.finditer(r'(?m)^\*\*\*\s+(?:Update|Add|Delete)\s+File:\s*(.+?)\s*$', patch):
        paths.append(m.group(1))
    for m in re.finditer(r'(?m)^\*\*\*\s+Move to:\s*(.+?)\s*$', patch):
        paths.append(m.group(1))
    seen = set()
    for p in paths:
        p = p.strip()
        if p.startswith("./"):
            p = p[2:]
        if p in seen:
            continue
        seen.add(p)
        pat = matched_pattern(p)
        if pat:
            block(p, pat)

sys.exit(0)
PY
