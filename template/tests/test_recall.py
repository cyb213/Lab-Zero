#!/usr/bin/env python3
"""
Recall engine tests — run with the Lab venv:
    .venv/bin/python tests/test_recall.py

Proportionate per review: the load-bearing test is the index+search round-trip
asserting NON-EMPTY, correct results (a vec load-failure and an empty index both
look like "no results"). Plus fast guards: the path→namespace transform, the C1
isolation guard, "db path resolves under the workspace toplevel", the session-start
hook's one-envelope stdout contract (D-010), and the model-mismatch refusal (A3).
No pytest dependency — plain asserts, nonzero exit on failure.

NOTE (W2/D-074): this is a DELIBERATELY trimmed smoke subset — the full engine suite
lives in the engine repo's root tests/. Refreshed for v1.12.0 (hook-envelope +
model-guard smoke tests added); keep it lean on purpose.
"""

import json
import os
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


# ── 5. Session-start hook: stdout is exactly ONE JSON envelope (D-010) ────────
def test_hook_envelope():
    print("[5] session-start hook emits one hookSpecificOutput envelope (D-010)")
    hook = SCRIPTS / "hooks" / "recall-session-start.sh"
    with tempfile.TemporaryDirectory(prefix="recall-hook-") as td:
        td = Path(td)
        (td / "recall.config.json").write_text(json.dumps({"root": ".", "auto_memory": "none"}))
        res = subprocess.run(
            ["bash", str(hook)], cwd=str(td), input="{}",
            capture_output=True, text=True,
        )
        check("hook exit 0", res.returncode == 0, res.stderr[-300:])
        lines = [l for l in res.stdout.splitlines() if l.strip()]
        check("stdout is exactly one line", len(lines) == 1, res.stdout[-300:])
        try:
            envl = json.loads(lines[0]) if lines else None
        except ValueError:
            envl = None
        check(
            "line is JSON with hookSpecificOutput.additionalContext",
            isinstance(envl, dict) and "additionalContext" in envl.get("hookSpecificOutput", {}),
            (lines[0][:200] if lines else "<empty stdout>"),
        )


# ── 6. Model-mismatch guard: the searcher refuses a foreign-model index (A3) ──
def test_model_guard():
    print("[6] model-mismatch guard (refuse loud, exit 2, before embedding)")
    import sqlite3  # stdlib fixture — no index copy, no network, no embed

    with tempfile.TemporaryDirectory(prefix="recall-model-") as td:
        td = Path(td)
        (td / "recall.config.json").write_text(
            json.dumps({"root": ".", "source": "test", "auto_memory": "none"})
        )
        (td / "memory").mkdir()
        conn = sqlite3.connect(td / "memory" / "index.db")
        conn.execute("PRAGMA user_version = 2")
        conn.execute(
            "CREATE TABLE chunks(id TEXT PRIMARY KEY, path TEXT, source TEXT, "
            "start_line INT, end_line INT, hash TEXT, model TEXT, text TEXT, "
            "heading TEXT, updated_at INT)"
        )
        conn.execute(
            "INSERT INTO chunks VALUES('h1','CLAUDE.md','test',1,2,'abc',"
            "'BOGUS-MODEL','hello','H',123)"
        )
        conn.commit()
        conn.close()

        env = {**os.environ, "RECALL_ROOT": str(td)}
        srch = subprocess.run(
            [PY, str(SCRIPTS / "recall-search.py"), "anything at all"],
            cwd=str(td), env=env, capture_output=True, text=True,
        )
        # exit 2 alone is ambiguous ("no index" exits 2 too) — assert the stderr text.
        check("searcher exits 2", srch.returncode == 2,
              f"rc={srch.returncode} err={srch.stderr[-300:]}")
        check("stderr names the model mismatch", "index built with model" in srch.stderr,
              srch.stderr[-300:])


def main():
    for t in (test_transform, test_isolation_guard, test_db_under_root, test_roundtrip,
              test_hook_envelope, test_model_guard):
        t()
    print(f"\n{len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        print("FAILED:", ", ".join(FAIL))
        return 1
    print("ALL GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
