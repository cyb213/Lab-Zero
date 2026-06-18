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


def _load_searcher():
    """Import recall-search.py for in-process unit tests of its PURE helpers (the FTS query
    sanitizer + the RRF fusion math). Binds CFG at import via recall_lib.load() but those
    helpers never touch the DB."""
    spec = importlib.util.spec_from_file_location("recall_search", str(SCRIPTS / "recall-search.py"))
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
        check("degrade: warns about missing FTS too (A2 ship-blocker)", "fts" in s.stderr.lower(), s.stderr[-300:])
        check("degrade: still serves the chunk (no crash)", "corpus/d.md" in s.stdout, s.stdout[-300:])

        # (B) indexer migrates: adds the column + bumps user_version.
        ix = subprocess.run([PY, str(SCRIPTS / "recall-index.py"), "--force"],
                            cwd=str(td), env=env, capture_output=True, text=True)
        check("migrate: indexer exit 0", ix.returncode == 0, (ix.stdout + ix.stderr)[-400:])
        conn = sqlite3.connect(str(dbp))
        cols1 = [r[1] for r in conn.execute("PRAGMA table_info(chunks)")]
        ver1 = conn.execute("PRAGMA user_version").fetchone()[0]
        fts_rows = conn.execute("SELECT count(*) FROM chunks_fts").fetchone()[0]  # raises if absent
        conn.close()
        check("migrate: 'heading' column added", "heading" in cols1, str(cols1))
        check("migrate: user_version bumped to A2 (>=2)", ver1 >= 2, str(ver1))
        check("migrate: chunks_fts created + populated (0->2)", fts_rows > 0, str(fts_rows))

        # (C) post-migration: no warning + the breadcrumb is now served.
        s2 = subprocess.run([PY, str(SCRIPTS / "recall-search.py"), "how do I roll back a release"],
                            cwd=str(td), env=env, capture_output=True, text=True)
        check("post-migrate: searcher exit 0", s2.returncode == 0, s2.stderr[-300:])
        check("post-migrate: no 'schema outdated' warning", "schema outdated" not in s2.stderr.lower(), s2.stderr[-300:])
        check("post-migrate: breadcrumb 'Doc' served", "Doc" in s2.stdout, s2.stdout[-300:])


# ── 9. FTS5 schema + tokenizer keeps -_. tokens whole (A2) ───────────────────
def test_fts_schema_and_tokenizer():
    print("[9] FTS5 schema + tokenizer keeps -_. tokens (A2)")
    import sqlite_vec
    idx = _load_indexer()
    check("SCHEMA_VERSION bumped to >=2", idx.SCHEMA_VERSION >= 2, str(idx.SCHEMA_VERSION))
    check("SCHEMA declares chunks_fts (fts5)", "chunks_fts" in idx.SCHEMA and "fts5" in idx.SCHEMA, "")
    check("SCHEMA keeps tokenchars '-_.'", "tokenchars '-_.'" in idx.SCHEMA, idx.SCHEMA)

    # Functional: build the REAL schema and prove the tokenizer keeps target tokens whole.
    conn = sqlite3.connect(":memory:")
    conn.enable_load_extension(True); sqlite_vec.load(conn); conn.enable_load_extension(False)
    conn.executescript(idx.SCHEMA)
    conn.execute("INSERT INTO chunks_fts(id, text) VALUES (?, ?)",
                 ("x", "D-007 --harness v1.3.0 SESSION_SECRET recall-index.py maxmemory-policy"))
    for tok in ("D-007", "--harness", "v1.3.0", "SESSION_SECRET", "recall-index.py", "maxmemory-policy"):
        n = conn.execute("SELECT count(*) FROM chunks_fts WHERE chunks_fts MATCH ?", ('"%s"' % tok,)).fetchone()[0]
        check(f"tokenizer keeps {tok!r} as one token", n == 1, str(n))
    conn.close()


# ── 10. FTS query sanitizer (no-throw) + RRF fusion math (A2) ─────────────────
def test_fts_sanitizer_and_rrf():
    print("[10] FTS query sanitizer + RRF fusion math (A2)")
    s = _load_searcher()
    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE VIRTUAL TABLE t USING fts5(id UNINDEXED, text, tokenize=\"unicode61 tokenchars '-_.'\")")
    conn.execute("INSERT INTO t(id, text) VALUES ('a', 'the --harness flag, a:b, and a quote')")

    # Operator-laden / pathological queries: the sanitized MATCH string must never throw.
    for q in ("--harness", '"x"', "a:b", ":::", "NEAR(x)", "a* OR b", "-_.", "  ", "(unbalanced"):
        m = s.fts_match_query(q)
        threw = False
        if m:
            try:
                conn.execute("SELECT count(*) FROM t WHERE t MATCH ?", (m,)).fetchone()
            except Exception as e:
                threw = True
                check(f"sanitizer no-throw on {q!r}", False, f"{e}: match={m!r}")
        if not threw:
            check(f"sanitizer no-throw on {q!r}", True)
    conn.close()

    check("zero-token / pure-punct query → empty match (caller skips FTS)",
          s.fts_match_query(":::") == "" and s.fts_match_query("  ") == "" and s.fts_match_query("-_.") == "", "")
    check("--harness preserved as a quoted token",
          '"--harness"' in s.fts_match_query("how is --harness used"), s.fts_match_query("how is --harness used"))
    capped = s.fts_match_query(" ".join("w%d" % i for i in range(100)))
    check("token cap ~32 (expr-depth guard)", len(capped.split(" OR ")) <= 32, str(len(capped.split(" OR "))))

    # RRF: id ranked in both lists beats ids in only one; rank-1-in-one-list = 1/(60+1).
    fused = s.rrf_fuse(["a", "b", "c"], ["b", "a", "d"])
    check("RRF: 'a'(1+2) & 'b'(2+1) tie above single-list 'c'",
          abs(fused["a"] - fused["b"]) < 1e-9 and fused["a"] > fused["c"], str(fused))
    check("RRF math: lone rank-1 == 1/(60+1)", abs(s.rrf_fuse(["z"], [])["z"] - 1.0 / 61) < 1e-12,
          str(s.rrf_fuse(["z"], [])))
    check("RRF: empty fts ⇒ preserves vector order (a>b>c)",
          (lambda f: f["a"] > f["b"] > f["c"])(s.rrf_fuse(["a", "b", "c"], [])), "")
    # Weighted RRF (W_FTS<1): a vector-rank-1 hit outranks an FTS-rank-1-only noise chunk,
    # yet an exact-match lexical answer (FTS rank 1 + a weak vector rank) still beats a
    # vector-only competitor — the property that fixed the invariant regression.
    check("W_FTS is downweighted (<1.0, >0)", 0.0 < s.W_FTS < 1.0, str(s.W_FTS))
    wf = s.rrf_fuse(["vhit"], ["noise"], w_fts=s.W_FTS)
    check("weighted RRF: vector-1 beats FTS-1-only noise", wf["vhit"] > wf["noise"], str(wf))
    wf2 = s.rrf_fuse(["vtop", "x", "x", "x", "x", "ans"], ["ans"], w_fts=s.W_FTS)
    check("weighted RRF: exact lexical answer (fts1+vec6) beats vector-top-only", wf2["ans"] > wf2["vtop"], str(wf2))


# ── 11. FTS maintenance: no-orphan-after-edit + source-filter drop (A2) ───────
def test_fts_maintenance():
    print("[11] FTS maintenance: no-orphan-after-edit + source-filter drop (A2)")
    with tempfile.TemporaryDirectory(prefix="recall-fts-") as td:
        td = Path(td)
        (td / "recall.config.json").write_text(
            json.dumps({"root": ".", "source": "test", "index_globs": ["corpus/**/*.md"], "auto_memory": "none"})
        )
        (td / "corpus").mkdir()
        (td / "corpus" / "a.md").write_text("# Alpha\n\nThe alpha doc mentions maxmemory-policy here.\n")
        (td / "corpus" / "b.md").write_text("# Beta\n\nThe beta doc is about something else entirely.\n")
        env = {**os.environ, "RECALL_ROOT": str(td)}
        dbp = td / "memory" / "index.db"

        def run_index(*args):
            return subprocess.run([PY, str(SCRIPTS / "recall-index.py"), *args],
                                  cwd=str(td), env=env, capture_output=True, text=True)

        def ids(table, where=""):
            c = sqlite3.connect(str(dbp))
            try:
                return {r[0] for r in c.execute(f"SELECT id FROM {table} {where}")}
            finally:
                c.close()

        ix = run_index("--force")
        check("fts-maint: force index exit 0", ix.returncode == 0, (ix.stdout + ix.stderr)[-300:])
        check("fts-maint: chunks_fts ids == chunks ids after force",
              ids("chunks_fts") == ids("chunks", "WHERE source='test'"),
              "fts ids != chunks ids after force")

        # Edit a.md ⇒ body changes ⇒ new chunk_id; the OLD FTS row MUST be deleted (C-2).
        (td / "corpus" / "a.md").write_text("# Alpha\n\nThe alpha doc now talks about allkeys-lru instead.\n")
        ix2 = run_index()
        check("fts-maint: incremental reindex exit 0", ix2.returncode == 0, (ix2.stdout + ix2.stderr)[-300:])
        check("fts-maint: NO orphan FTS row after edit (ids still match chunks)",
              ids("chunks_fts") == ids("chunks", "WHERE source='test'"), "orphan or missing FTS row")
        c = sqlite3.connect(str(dbp))
        fts_text = " ".join(r[0] for r in c.execute("SELECT text FROM chunks_fts"))
        c.close()
        check("fts-maint: edited content present in FTS", "allkeys-lru" in fts_text, fts_text[:160])
        check("fts-maint: stale content purged from FTS", "maxmemory-policy" not in fts_text, fts_text[:160])

        # Source filter (C-1): an FTS id whose chunks row is ANOTHER source must be dropped at
        # hydration (chunks_fts is source-blind) — never surfaced, never a crash.
        c = sqlite3.connect(str(dbp))
        c.execute("INSERT INTO chunks(id, path, source, start_line, end_line, hash, model, text, heading, updated_at) "
                  "VALUES ('OTHER1','x.md','other',1,1,'h','m','qqzztoken unique foreign body',NULL,0)")
        c.execute("INSERT INTO chunks_fts(id, text) VALUES ('OTHER1','qqzztoken unique foreign body')")
        c.commit(); c.close()
        srch = subprocess.run([PY, str(SCRIPTS / "recall-search.py"), "qqzztoken"],
                              cwd=str(td), env=env, capture_output=True, text=True)
        check("fts-maint: searcher exit 0 with a foreign-source FTS hit", srch.returncode == 0, srch.stderr[-300:])
        check("fts-maint: foreign-source id dropped (not surfaced / no crash)",
              "OTHER1" not in srch.stdout and "x.md" not in srch.stdout, srch.stdout[-300:])


# ── 12. Migration backfill on upgrade == force content, NO re-embed (A2 R9) ───
def test_fts_backfill_no_reembed():
    print("[12] FTS migration backfill (incremental upgrade) == force content, no re-embed (A2)")
    with tempfile.TemporaryDirectory(prefix="recall-bf-") as td:
        td = Path(td)
        (td / "recall.config.json").write_text(
            json.dumps({"root": ".", "source": "test", "index_globs": ["corpus/**/*.md"], "auto_memory": "none"})
        )
        (td / "corpus").mkdir()
        (td / "corpus" / "c.md").write_text("# Conf\n\nSet maxmemory-policy to allkeys-lru for the worker.\n")
        env = {**os.environ, "RECALL_ROOT": str(td)}
        dbp = td / "memory" / "index.db"

        ix = subprocess.run([PY, str(SCRIPTS / "recall-index.py"), "--force"],
                            cwd=str(td), env=env, capture_output=True, text=True)
        check("backfill: initial force exit 0", ix.returncode == 0, (ix.stdout + ix.stderr)[-300:])

        # Snapshot the FORCE-built FTS, then simulate a pre-A2 (v1) index: drop chunks_fts +
        # rewind user_version to 1. chunks/chunks_vec untouched (the no-re-embed surface).
        # chunks_vec is a vec0 virtual table (needs the extension to read) — but we never drop
        # it, so the no-re-embed proof is simply that the model never loads on this run.
        conn = sqlite3.connect(str(dbp))
        force_fts = {r[0]: r[1] for r in conn.execute("SELECT id, text FROM chunks_fts")}
        conn.execute("DROP TABLE chunks_fts")
        conn.execute("PRAGMA user_version = 1")
        conn.commit(); conn.close()

        # Incremental run, NO changed files: must version-gate-backfill chunks_fts (before the
        # not-changed early-return) WITHOUT loading the model / re-embedding (R9).
        ix2 = subprocess.run([PY, str(SCRIPTS / "recall-index.py")],
                             cwd=str(td), env=env, capture_output=True, text=True)
        check("backfill: incremental upgrade exit 0", ix2.returncode == 0, (ix2.stdout + ix2.stderr)[-300:])
        check("backfill: did NOT re-embed (model never loaded)", "loading" not in ix2.stdout.lower(), ix2.stdout[-300:])

        conn = sqlite3.connect(str(dbp))
        ver = conn.execute("PRAGMA user_version").fetchone()[0]
        bf_fts = {r[0]: r[1] for r in conn.execute("SELECT id, text FROM chunks_fts")}
        conn.close()
        check("backfill: user_version advanced to >=2", ver >= 2, str(ver))
        check("backfill: content == force-built FTS (shared fts_body)", bf_fts == force_fts,
              f"{list(bf_fts.items())[:1]} vs {list(force_fts.items())[:1]}")


def main():
    for t in (test_transform, test_isolation_guard, test_db_under_root, test_roundtrip,
              test_hook_json_envelope, test_update_check_nudge, test_chunk_text,
              test_schema_migration, test_fts_schema_and_tokenizer, test_fts_sanitizer_and_rrf,
              test_fts_maintenance, test_fts_backfill_no_reembed):
        t()
    print(f"\n{len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        print("FAILED:", ", ".join(FAIL))
        return 1
    print("ALL GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
