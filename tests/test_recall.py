#!/usr/bin/env python3
"""
Recall engine tests — run with the Lab venv:
    .venv/bin/python tests/test_recall.py

Proportionate per review: the load-bearing test is the index+search round-trip
asserting NON-EMPTY, correct results (a vec load-failure and an empty index both
look like "no results"). Plus three fast guards: the path→namespace transform,
the C1 isolation guard, and "db path resolves under the workspace toplevel".
No pytest dependency — plain asserts, nonzero exit on failure.
"""

import importlib.util
import json
import os
import sqlite3
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPTS = REPO / "scripts"
VENV_PY = REPO / ".venv" / "bin" / "python"
PY = str(VENV_PY) if VENV_PY.exists() else sys.executable

sys.path.insert(0, str(SCRIPTS))
import recall_lib  # noqa: E402


def _load_indexer():
    """Import recall-index.py (hyphenated filename) for in-process unit tests of the
    pure chunker. The module binds CFG at import via recall_lib.load(), which falls back
    to DEFAULTS with no config — chunk_text() ignores CFG and never touches the DB."""
    spec = importlib.util.spec_from_file_location("recall_index", str(SCRIPTS / "recall-index.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

PASS, FAIL = [], []


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(f"  {'✓' if cond else '✗ FAIL'}  {name}{(' — ' + detail) if detail and not cond else ''}")


# ── 1. Path → CC namespace transform (verified live) ──────────────────────────
def test_transform():
    print("[1] path_to_namespace_key")
    check(
        "/home/alice/.lab -> -home-alice--lab",
        recall_lib.path_to_namespace_key("/home/alice/.lab") == "-home-alice--lab",
        recall_lib.path_to_namespace_key("/home/alice/.lab"),
    )
    check(
        "/home/alice/work/my_proj -> -home-alice-work-my-proj",
        recall_lib.path_to_namespace_key("/home/alice/work/my_proj") == "-home-alice-work-my-proj",
        recall_lib.path_to_namespace_key("/home/alice/work/my_proj"),
    )


# ── 2. C1 isolation guard: a copied config pointing at a FOREIGN namespace ────
def test_isolation_guard():
    print("[2] isolation guard (C1)")
    with tempfile.TemporaryDirectory(prefix="recall-iso-") as td:
        # An override whose namespace key doesn't match THIS workspace's derived
        # key = a config copied from another workspace. Must be refused.
        cfg = {
            "root": ".",
            "auto_memory_dir": "~/.claude/projects/-home-someone-other-workspace/memory",
        }
        (Path(td) / "recall.config.json").write_text(json.dumps(cfg))
        try:
            recall_lib.load(start=td)
            check("refuses a foreign namespace from a mismatched root", False, "no SystemExit")
        except SystemExit as e:
            check("refuses a foreign namespace from a mismatched root", e.code == 3, f"exit={e.code}")


# ── 3. DB path resolves under the workspace toplevel ──────────────────────────
def test_db_under_root():
    print("[3] db path under toplevel")
    with tempfile.TemporaryDirectory(prefix="recall-db-") as td:
        (Path(td) / "recall.config.json").write_text(json.dumps({"root": ".", "auto_memory": "none"}))
        cfg = recall_lib.load(start=td)
        real_td = str(Path(td).resolve())
        check("db under root", cfg["db"].startswith(real_td), cfg["db"])
        check("state_file under root", cfg["state_file"].startswith(real_td), cfg["state_file"])


# ── 4. Round-trip: index a tmp corpus, search it, assert NON-EMPTY + correct ──
def test_roundtrip():
    print("[4] index+search round-trip (asserts non-empty)")
    with tempfile.TemporaryDirectory(prefix="recall-rt-") as td:
        td = Path(td)
        (td / "recall.config.json").write_text(
            json.dumps(
                {
                    "root": ".",
                    "source": "test",
                    "index_globs": ["Log/**/*.md", "CLAUDE.md"],
                    "auto_memory": "none",
                }
            )
        )
        (td / "Log").mkdir()
        (td / "CLAUDE.md").write_text(
            "# Workspace\nThis user prefers temperatures in Celsius, never Fahrenheit.\n"
        )
        (td / "Log" / "notes.md").write_text(
            "# Notes\nEach workspace is walled off as its own git repo and namespace.\n"
            "User-facing times are shown in the user's local timezone.\n"
        )

        env = {**os.environ, "RECALL_ROOT": str(td)}
        idx = subprocess.run(
            [PY, str(SCRIPTS / "recall-index.py"), "--force"],
            cwd=str(td), env=env, capture_output=True, text=True,
        )
        check("indexer exit 0", idx.returncode == 0, idx.stderr[-400:])
        check("indexer embedded chunks", "chunks total" in idx.stdout, idx.stdout[-300:])

        srch = subprocess.run(
            [PY, str(SCRIPTS / "recall-search.py"), "what temperature unit does the user want?"],
            cwd=str(td), env=env, capture_output=True, text=True,
        )
        out = srch.stdout
        check("search exit 0", srch.returncode == 0, srch.stderr[-400:])
        check("search NON-EMPTY", "(no results)" not in out and out.strip(), out[-300:])
        check("top hit is the Celsius line", "Celsius" in out or "CLAUDE.md" in out, out[-400:])


# ── 5. Hook stdout is the JSON envelope BOTH harnesses accept ────────────────
# Codex 0.130.0 rejects raw-text hook stdout (SessionStart: "invalid session
# start JSON output"; Stop: "plain text is invalid") — and a banner starting with
# '[' trips its JSON auto-parse. So the shared recall hooks must emit the
# hookSpecificOutput.additionalContext envelope (Claude injects it too). (D-010.)
def _run_hook(name, td, stdin=None, env=None):
    return subprocess.run(
        ["bash", str(SCRIPTS / "hooks" / name)],
        cwd=str(td), input=stdin, capture_output=True, text=True, env=env,
    )


def _parse_json(label, out):
    """json.loads(out) but report a clean FAIL (not a traceback) on raw text."""
    try:
        return json.loads(out)
    except Exception as e:
        check(f"{label}: stdout is valid JSON", False, f"{e}: {out[:120]!r}")
        return None


def test_hook_json_envelope():
    print("[5] recall hooks emit the JSON envelope (Claude+Codex)")
    with tempfile.TemporaryDirectory(prefix="recall-hook-") as td:
        td = Path(td)
        (td / "recall.config.json").write_text(json.dumps({"root": ".", "auto_memory": "none"}))

        # SessionStart — always emits the banner; must be one JSON object.
        r = _run_hook("recall-session-start.sh", td)
        check("session-start exit 0", r.returncode == 0, r.stderr[-300:])
        check("session-start stdout starts with '{' (not raw '[recall]')",
              r.stdout.lstrip()[:1] == "{", r.stdout[:80])
        obj = _parse_json("session-start", r.stdout)
        if obj is not None:
            hso = obj.get("hookSpecificOutput", {})
            check("session-start hookEventName=SessionStart", hso.get("hookEventName") == "SessionStart", str(hso)[:120])
            check("session-start additionalContext carries the banner",
                  "recall" in (hso.get("additionalContext") or ""), str(hso)[:160])

        # UserPromptSubmit — a new codename triggers a nudge; envelope-wrapped.
        evt = json.dumps({"prompt": "continuing the session 9 cleanup", "hook_event_name": "UserPromptSubmit"})
        r = _run_hook("recall-user-prompt.sh", td, stdin=evt)
        check("user-prompt exit 0", r.returncode == 0, r.stderr[-300:])
        obj = _parse_json("user-prompt", r.stdout)
        if obj is not None:
            hso = obj.get("hookSpecificOutput", {})
            check("user-prompt hookEventName=UserPromptSubmit", hso.get("hookEventName") == "UserPromptSubmit", str(hso)[:120])
            check("user-prompt additionalContext mentions the new codename",
                  "session 9" in (hso.get("additionalContext") or ""), str(hso)[:160])

        # UserPromptSubmit — nothing to surface ⇒ empty stdout (valid on both).
        evt = json.dumps({"prompt": "just a plain question", "hook_event_name": "UserPromptSubmit"})
        r = _run_hook("recall-user-prompt.sh", td, stdin=evt)
        check("user-prompt empty-case exit 0", r.returncode == 0, r.stderr[-300:])
        check("user-prompt empty-case emits nothing", r.stdout.strip() == "", r.stdout[:120])

        # Stop — must be valid JSON at exit 0 (Codex rejects plain text), no block.
        evt = json.dumps({"transcript_path": "/nonexistent/transcript.jsonl", "hook_event_name": "Stop"})
        r = _run_hook("recall-stop.sh", td, stdin=evt)
        check("stop exit 0", r.returncode == 0, r.stderr[-300:])
        obj = _parse_json("stop", r.stdout)
        if obj is not None:
            check("stop output is a JSON object", isinstance(obj, dict), str(obj)[:120])
            check("stop does not block the session", obj.get("decision") != "block", str(obj)[:120])


# ── 6. update-check cadence nudge (Phase 7) ──────────────────────────────────
# The SessionStart hook drops a "you're due for an update check" line every ~N
# sessions, but ONLY in a deployed Lab Zero consumer (gated on $ROOT/update.sh). It
# must: fire in the SAME single JSON envelope as the banner (Codex: one object only);
# stay silent without update.sh (graduated projects + the factory); not nag a fresh
# clone (zero-marker cold-start); and NEVER abort under a hostile $LAB_UPDATE_CHECK_EVERY
# (set -u: an unbound-var abort would kill the recall banner — the D-010 failure). (D-031.)
def _ctx(out):
    try:
        return json.loads(out)["hookSpecificOutput"]["additionalContext"] or ""
    except Exception:
        return ""


def _seed_starts(td, n):
    trail = td / "memory" / "recall-trail.jsonl"
    trail.parent.mkdir(parents=True, exist_ok=True)
    trail.write_text('{"ts":"X","event":"session_start"}\n' * n)
    return trail


def test_update_check_nudge():
    print("[6] update-check cadence nudge (self-gated, set-u-safe, stdout-silent)")
    base = dict(os.environ)
    cfg = json.dumps({"root": ".", "auto_memory": "none"})

    # (a) fires: update.sh present + ≥N starts ⇒ nudge in the SAME one JSON object as
    #     the banner; a marker is appended.
    with tempfile.TemporaryDirectory(prefix="nudge-fire-") as td:
        td = Path(td)
        (td / "recall.config.json").write_text(cfg)
        (td / "update.sh").write_text("# stub\n")
        trail = _seed_starts(td, 2)                    # +1 appended by the hook ⇒ 3 ≥ N=3
        r = _run_hook("recall-session-start.sh", td, env={**base, "LAB_UPDATE_CHECK_EVERY": "3"})
        check("nudge fires: exit 0", r.returncode == 0, r.stderr[-200:])
        _parse_json("nudge-fire", r.stdout)            # must be exactly one JSON object
        ctx = _ctx(r.stdout)
        check("nudge fires: has [update] + 'update.sh --check'",
              "[update]" in ctx and "update.sh --check" in ctx, ctx[:180])
        check("nudge fires: still carries the recall banner (one envelope)", "recall" in ctx, ctx[:120])
        check("nudge fires: marker appended to trail",
              '"event":"update_check_nudged"' in trail.read_text(), trail.read_text()[-180:])

    # (b) silent without update.sh — even with many starts + N=1 (template/factory shape).
    with tempfile.TemporaryDirectory(prefix="nudge-noupd-") as td:
        td = Path(td)
        (td / "recall.config.json").write_text(cfg)
        trail = _seed_starts(td, 20)
        r = _run_hook("recall-session-start.sh", td, env={**base, "LAB_UPDATE_CHECK_EVERY": "1"})
        ctx = _ctx(r.stdout)
        check("nudge silent: NO [update] without update.sh", "[update]" not in ctx, ctx[:180])
        check("nudge silent: no marker written without update.sh",
              '"event":"update_check_nudged"' not in trail.read_text(), "")

    # (c) zero-marker cold-start ⇒ no nudge until N accrue (a fresh clone won't nag).
    with tempfile.TemporaryDirectory(prefix="nudge-cold-") as td:
        td = Path(td)
        (td / "recall.config.json").write_text(cfg)
        (td / "update.sh").write_text("# stub\n")
        r = _run_hook("recall-session-start.sh", td,
                      env={k: v for k, v in base.items() if k != "LAB_UPDATE_CHECK_EVERY"})
        ctx = _ctx(r.stdout)
        check("nudge cold-start: 1<N ⇒ no nudge", "[update]" not in ctx, ctx[:180])
        check("nudge cold-start: banner still present", "recall" in ctx, ctx[:120])

    # (d) set -u SAFETY: the recall banner survives an UNSET and a GARBAGE
    #     LAB_UPDATE_CHECK_EVERY (an unbound-var abort would kill the banner + the JSON).
    for label, val in (("unset", None), ("garbage", "not-a-number")):
        with tempfile.TemporaryDirectory(prefix=f"nudge-{label}-") as td:
            td = Path(td)
            (td / "recall.config.json").write_text(cfg)
            (td / "update.sh").write_text("# stub\n")
            _seed_starts(td, 30)
            if val is None:
                env = {k: v for k, v in base.items() if k != "LAB_UPDATE_CHECK_EVERY"}
            else:
                env = {**base, "LAB_UPDATE_CHECK_EVERY": val}
            r = _run_hook("recall-session-start.sh", td, env=env)
            check(f"nudge hostile-env ({label}): exit 0", r.returncode == 0, r.stderr[-200:])
            _parse_json(f"nudge-{label}", r.stdout)    # still exactly one JSON object
            ctx = _ctx(r.stdout)
            check(f"nudge hostile-env ({label}): recall banner survives", "recall" in ctx, ctx[:120])


# ── 7. Heading-aware chunk_text() (A1/A7) ────────────────────────────────────
# chunk_text now yields (text, start_line, end_line, heading_breadcrumb) and cuts on
# markdown heading boundaries instead of blind 600-char windows. Each section carries
# its heading-path breadcrumb (A7), an oversized section falls back to the within-section
# window (strict refinement), the preamble before the first heading is breadcrumb-less,
# and a heading-less doc degenerates to the old whole-text windowing. (D5/D-034.)
def test_chunk_text():
    print("[7] heading-aware chunk_text (A1/A7)")
    idx = _load_indexer()
    ct = idx.chunk_text

    doc = ("intro preamble before any heading\n\n# Title\n\ntitle body\n\n"
           "## Alpha\n\nalpha body here\n\n## Beta\n\nbeta body here\n")
    chunks = list(ct(doc))
    check("yields 4-tuples (text, sl, el, heading)", all(len(c) == 4 for c in chunks), str(chunks[:1]))
    alpha = [c for c in chunks if "alpha body here" in c[0]]
    check("Alpha isolated to one chunk", len(alpha) == 1, str([c[3] for c in chunks]))
    check("Alpha breadcrumb = 'Title › Alpha'", alpha and alpha[0][3] == "Title › Alpha", str(alpha and alpha[0][3]))
    check("Beta does not bleed into the Alpha chunk", alpha and "beta body" not in alpha[0][0], str(alpha))

    pre = [c for c in chunks if "intro preamble" in c[0]]
    check("preamble chunk has no breadcrumb (None)", pre and pre[0][3] is None, str(pre))

    nested = list(ct("## Risks\n\nR1 text here\n\n### R2 details\n\ncollide with backup window\n"))
    r2 = [c for c in nested if "collide with backup" in c[0]]
    check("nested breadcrumb = 'Risks › R2 details'", r2 and r2[0][3] == "Risks › R2 details", str([c[3] for c in nested]))

    headingless = list(ct("just some text\nwith two lines and no heading at all\n"))
    check("heading-less => chunks with breadcrumb None", headingless and all(c[3] is None for c in headingless), str(headingless))
    check("heading-less content preserved", "two lines" in " ".join(c[0] for c in headingless), str(headingless))

    big = list(ct("## Big\n\n" + ("alpha beta gamma delta " * 60)))  # body > MAX_CHUNK_CHARS
    check("oversized section => multiple windowed chunks", len(big) >= 2, str(len(big)))
    check("each windowed chunk <= MAX_CHUNK_CHARS", all(len(c[0]) <= idx.MAX_CHUNK_CHARS for c in big), str([len(c[0]) for c in big]))
    check("windowed chunks keep the section breadcrumb", all(c[3] == "Big" for c in big), str([c[3] for c in big]))

    anchored = list(ct("# H\n\nthird line carries the ANCHOR token\n"))
    a = [c for c in anchored if "ANCHOR" in c[0]][0]
    check("absolute line numbers sane (1 <= sl <= el <= nlines)", 1 <= a[1] <= a[2] <= 3, f"{a[1]}-{a[2]}")

    fenced = list(ct("## Real\n\n```bash\n# not a heading\necho hi\n```\n\nbody after the fence\n"))
    check("a '# comment' inside a code fence is NOT a heading",
          all(c[3] in (None, "Real") for c in fenced), str([c[3] for c in fenced]))


# ── 8. Schema migration (indexer) + searcher fail-loud degrade (D8/C2) ────────
# An old-schema index (no 'heading' column, user_version 0) must NOT crash the searcher
# (a separate process: 'no such column' would surface as a misleading "search failed").
# The searcher degrades to the text-only path + warns; the INDEXER migrates via
# PRAGMA user_version + ALTER TABLE on its next run, then breadcrumbs work. (D-034.)
def test_schema_migration():
    print("[8] schema migration + searcher degrade guard (D8/C2)")
    import sqlite_vec

    with tempfile.TemporaryDirectory(prefix="recall-mig-") as td:
        td = Path(td)
        (td / "recall.config.json").write_text(
            json.dumps({"root": ".", "source": "test", "index_globs": ["corpus/**/*.md"], "auto_memory": "none"})
        )
        (td / "corpus").mkdir()
        (td / "corpus" / "d.md").write_text("# Doc\n\nThe rollback procedure points the symlink back.\n")

        dbp = td / "memory" / "index.db"
        dbp.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(str(dbp))
        conn.enable_load_extension(True)
        sqlite_vec.load(conn)
        conn.enable_load_extension(False)
        # OLD schema: no 'heading' column, user_version left at 0.
        conn.executescript(
            "CREATE TABLE chunks (id TEXT PRIMARY KEY, path TEXT NOT NULL, source TEXT NOT NULL, "
            "start_line INTEGER NOT NULL, end_line INTEGER NOT NULL, hash TEXT NOT NULL, "
            "model TEXT NOT NULL, text TEXT NOT NULL, updated_at INTEGER NOT NULL);"
            "CREATE VIRTUAL TABLE chunks_vec USING vec0(id TEXT PRIMARY KEY, embedding float[384]);"
        )
        conn.execute(
            "INSERT INTO chunks VALUES (?,?,?,?,?,?,?,?,?)",
            ("cid1", "corpus/d.md", "test", 1, 3, "deadbeef", "all-MiniLM-L6-v2",
             "# Doc\n\nThe rollback procedure points the symlink back.", 0),
        )
        conn.execute("INSERT INTO chunks_vec(id, embedding) VALUES (?, ?)",
                     ("cid1", struct.pack("384f", *([0.0] * 384))))
        conn.execute("PRAGMA user_version = 0")
        conn.commit()
        cols0 = [r[1] for r in conn.execute("PRAGMA table_info(chunks)")]
        conn.close()
        check("old DB has no 'heading' column", "heading" not in cols0, str(cols0))

        env = {**os.environ, "RECALL_ROOT": str(td)}

        # (A) searcher must DEGRADE on the old schema: warn + serve, never crash.
        s = subprocess.run([PY, str(SCRIPTS / "recall-search.py"), "how do I roll back a release"],
                           cwd=str(td), env=env, capture_output=True, text=True)
        check("degrade: searcher exit 0 on old schema", s.returncode == 0, s.stderr[-300:])
        check("degrade: warns 'schema outdated' to stderr", "schema outdated" in s.stderr.lower(), s.stderr[-300:])
        check("degrade: still serves the chunk (no crash)", "corpus/d.md" in s.stdout, s.stdout[-300:])

        # (B) indexer migrates: adds the column + bumps user_version.
        ix = subprocess.run([PY, str(SCRIPTS / "recall-index.py"), "--force"],
                            cwd=str(td), env=env, capture_output=True, text=True)
        check("migrate: indexer exit 0", ix.returncode == 0, (ix.stdout + ix.stderr)[-400:])
        conn = sqlite3.connect(str(dbp))
        cols1 = [r[1] for r in conn.execute("PRAGMA table_info(chunks)")]
        ver1 = conn.execute("PRAGMA user_version").fetchone()[0]
        conn.close()
        check("migrate: 'heading' column added", "heading" in cols1, str(cols1))
        check("migrate: user_version bumped (>=1)", ver1 >= 1, str(ver1))

        # (C) post-migration: no warning + the breadcrumb is now served.
        s2 = subprocess.run([PY, str(SCRIPTS / "recall-search.py"), "how do I roll back a release"],
                            cwd=str(td), env=env, capture_output=True, text=True)
        check("post-migrate: searcher exit 0", s2.returncode == 0, s2.stderr[-300:])
        check("post-migrate: no 'schema outdated' warning", "schema outdated" not in s2.stderr.lower(), s2.stderr[-300:])
        check("post-migrate: breadcrumb 'Doc' served", "Doc" in s2.stdout, s2.stdout[-300:])


def main():
    for t in (test_transform, test_isolation_guard, test_db_under_root, test_roundtrip,
              test_hook_json_envelope, test_update_check_nudge, test_chunk_text,
              test_schema_migration):
        t()
    print(f"\n{len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        print("FAILED:", ", ".join(FAIL))
        return 1
    print("ALL GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
