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


def main():
    for t in (test_transform, test_isolation_guard, test_db_under_root, test_roundtrip):
        t()
    print(f"\n{len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        print("FAILED:", ", ".join(FAIL))
        return 1
    print("ALL GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
