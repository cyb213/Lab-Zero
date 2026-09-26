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
import json, os, pathlib
root = os.environ["ROOT"]
p = pathlib.Path(root) / ".claude" / "settings.json"
t = p.read_text()
if "__WORKSPACE__" in t:
    # json.dumps(root)[1:-1] = the path as a JSON string-literal body — a `"` or `\`
    # in the workspace path stays valid JSON (E2, W2/D-074; the D-070 idiom from
    # new-project.sh). Byte-identical to the raw path for quote/backslash-free ASCII.
    p.write_text(t.replace("__WORKSPACE__", json.dumps(root)[1:-1]))
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

# the JSON-escaped body, not the raw path — same E2 guard as wire_claude above
blob = json.dumps({"hooks": hooks}, indent=2).replace("__WORKSPACE__", json.dumps(root)[1:-1])
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
  wire_codex_agents
  echo "[bootstrap]   wired Codex: .codex/hooks.json + config.toml (features.hooks) + AGENTS.override.md (helper agents: see the line above)"
}

# ── Codex helper agents (D-111): .codex/agents/<name>.toml from the lanes ──────
# Derives one Codex custom agent per .claude/agents/lab-zero/*.md (frontmatter name →
# name, description → description, body → developer_instructions). Claude-only keys
# (model / effort / tools) are NOT carried, and no model / reasoning-effort / sandbox is
# pinned: the helper inherits the session's (D2). Line 1 of every generated file is the
# marker below; wire only (re)writes a target that is absent or carries it (a user's
# same-name file is left alone with a WARN), and sweeps marked files this run didn't
# produce (a renamed/withdrawn lane). FAIL-SOFT (D1b): a missing lanes dir or a bad lane
# only prints a line; any unexpected error is caught — bootstrap is `set -e`, and this
# runs last in wire_codex so it can never strand a half-wired tree. Python 3.9-safe.
LZ_AGENT_MARK='# generated by Lab Zero (scripts/wire-harness.sh)'
wire_codex_agents() {
  ROOT="$ROOT" LZ_AGENT_MARK="$LZ_AGENT_MARK" python3 - <<'PY' || echo "[bootstrap]   WARN: Codex helper agents not wired (generator error) — the rest of the Codex wiring is intact"
import os, pathlib, re, sys

MARK = os.environ.get("LZ_AGENT_MARK", "")
if not MARK.startswith("# generated by Lab Zero"):   # empty/unset: startswith("") would claim EVERY file
    print("[bootstrap]   WARN: LZ_AGENT_MARK unset — Codex helper agents skipped"); sys.exit(0)
R = pathlib.Path(os.environ["ROOT"])
LANES = R / ".claude" / "agents" / "lab-zero"
ADIR = R / ".codex" / "agents"
NAME_RE = re.compile(r"[A-Za-z0-9_-]+")

def say(msg):
    print("[bootstrap]   " + msg)

def warn(msg):
    say("WARN: " + msg)

def esc(s, multiline):
    # TOML basic-string escaping (D1c), done by hand: json.dumps would emit non-BMP
    # characters as surrogate pairs, which TOML rejects. Every `"` is escaped, so no run
    # of quotes can close a """ delimiter early; `\` is escaped, so no line-ending
    # backslash; control chars (incl. U+007F) become \uXXXX. Tab stays literal (legal);
    # a newline stays literal only inside the multi-line body.
    out = []
    for ch in s:
        o = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n" and multiline:
            out.append("\n")
        elif ch == "\t":
            out.append("\t")
        elif o < 0x20 or o == 0x7F:
            out.append("\\u%04X" % o)
        else:
            out.append(ch)
    return "".join(out)

def parse_lane(p):
    # -> (fields, body) or (None, reason). Frontmatter = single-line `key: value` between
    # a first-line `---` and the next `---`; body = everything after, stripped.
    lines = p.read_text(encoding="utf-8").split("\n")
    if not lines or lines[0].rstrip() != "---":
        return None, "no frontmatter (line 1 is not ---)"
    end = None
    for i in range(1, len(lines)):
        if lines[i].rstrip() == "---":
            end = i
            break
    if end is None:
        return None, "frontmatter never closes (no second ---)"
    fm = {}
    for l in lines[1:end]:
        k, sep, v = l.partition(":")
        if sep:
            fm[k.strip()] = v.strip()
    for k in ("name", "description"):
        if not fm.get(k):
            return None, "frontmatter has no " + k
    if not NAME_RE.fullmatch(fm["name"]):
        return None, "name %r is not [A-Za-z0-9_-]+" % fm["name"]
    return fm, "\n".join(lines[end + 1:]).strip()

def first_line(p):
    with open(str(p), "rb") as f:
        return f.readline().decode("utf-8", "replace").rstrip("\r\n")

def own_mark(fname):
    # the marker names the file's OWN path, so a user's `cp` to a new name (line 1 intact)
    # is not ours: never overwritten, swept, or de-provisioned (D-111 review P1)
    return MARK + " as .codex/agents/" + fname + " from "

def is_ours(p):
    # a regular file (never a symlink) whose line 1 is the marker naming this file
    try:
        return p.is_file() and not p.is_symlink() and first_line(p).startswith(own_mark(p.name))
    except OSError:
        return False

def render(stem, name, desc, body):
    return (own_mark(name + ".toml") + ".claude/agents/lab-zero/" + stem + ".md — re-wiring"
            " overwrites or removes this file; to customize, copy it to a new name\n"
            'name = "' + esc(name, False) + '"\n'
            'description = "' + esc(desc, False) + '"\n'
            'developer_instructions = """\n' + esc(body, True) + '"""\n')

def verify(p, name, desc, body):
    # post-write parse (3.11+ only; the import is optional so 3.9/3.10 still wire)
    try:
        import tomllib
    except ImportError:
        return True
    try:
        d = tomllib.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return False
    return (d.get("name"), d.get("description"), d.get("developer_instructions")) == (name, desc, body)

def main():
    if ADIR.is_symlink():
        warn(".codex/agents is a symlink — not ours to write into; Codex helper agents skipped")
        return
    produced = set()
    if not LANES.is_dir():
        say("no .claude/agents/lab-zero/ in this tree — Codex helper agents skipped")
    else:
        ADIR.mkdir(parents=True, exist_ok=True)
        for p in sorted(LANES.glob("*.md")):
            if not p.is_file():
                continue
            try:
                fm, body = parse_lane(p)
            except Exception as e:
                warn("skipped .claude/agents/lab-zero/%s (unreadable: %s)" % (p.name, e))
                continue
            if fm is None:
                warn("skipped .claude/agents/lab-zero/%s (%s)" % (p.name, body))
                continue
            name, desc = fm["name"], fm["description"]
            if name in produced:
                warn("skipped .claude/agents/lab-zero/%s (duplicate name %r)" % (p.name, name))
                continue
            t = ADIR / (name + ".toml")
            if t.parent != ADIR:          # belt-and-braces: never write outside .codex/agents/
                warn("skipped .claude/agents/lab-zero/%s (bad target path)" % p.name)
                continue
            if (t.exists() or t.is_symlink()) and not is_ours(t):
                warn(".codex/agents/%s.toml exists without the Lab Zero marker — left as-is "
                     "(lane %s from %s not wired)" % (name, name, p.name))
                continue
            text = render(p.stem, name, desc, body)
            try:
                cur = t.read_text(encoding="utf-8") if t.exists() else None
            except Exception:
                cur = None
            if cur != text:
                t.write_text(text, encoding="utf-8")
            if not verify(t, name, desc, body):
                t.unlink()
                warn("removed .codex/agents/%s.toml — it did not round-trip as TOML (from %s)"
                     % (name, p.name))
                continue
            produced.add(name)
    # stale sweep: marked files this run did not produce (renamed / withdrawn lane)
    stale = []
    if ADIR.is_dir():
        for q in sorted(ADIR.glob("*.toml")):
            if q.stem not in produced and is_ours(q):
                q.unlink()
                stale.append(q.name)
        if not produced and not any(ADIR.iterdir()):
            ADIR.rmdir()
    if stale:
        say("removed stale Codex helper agents: " + ", ".join(stale))
    if produced:
        say("wired Codex helper agents: " + ", ".join(sorted(produced)))

try:
    main()
except Exception as e:
    warn("Codex helper agents not wired (%s: %s) — the rest of the Codex wiring is intact"
         % (type(e).__name__, e))
PY
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
  ROOT="$ROOT" LZ_AGENT_MARK="$LZ_AGENT_MARK" python3 - <<'PY'
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
# D-111 helper agents: ours = line 1 is the marker naming THIS file (whatever the body
# now says — no byte-match, so a lane updated since wiring still de-provisions). A user's
# unmarked file or renamed copy (and so .codex/agents/ itself) stays. Symlinks are never
# ours. Wrapped whole: an unreadable dir must not abort a `set -e` bootstrap.
adir = cdir / "agents"
mark = os.environ.get("LZ_AGENT_MARK", "")          # empty/unset ⇒ claim nothing
try:
    if mark.startswith("# generated by Lab Zero") and adir.is_dir() and not adir.is_symlink():
        for q in sorted(adir.glob("*.toml")):
            try:
                if q.is_symlink() or not q.is_file(): continue
                with open(str(q), "rb") as f:
                    if not f.readline().decode("utf-8", "replace").startswith(mark + " as .codex/agents/" + q.name + " from "): continue
                q.unlink(); removed.append(".codex/agents/" + q.name)
            except OSError:
                pass
        try: adir.rmdir()    # only succeeds if now empty (keeps user content)
        except OSError: pass
except OSError as e:
    print("[bootstrap]   WARN: could not clean .codex/agents/ (%s) — remove Lab Zero's generated TOMLs by hand" % e)
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
