#!/usr/bin/env python3
"""
Generalized semantic search backend.

Reads the config-driven DB, embeds the query via fastembed, runs KNN through
sqlite-vec. Renders the line-format recall.sh consumers expect (file:line +
score + heading + snippet + hash).

Usage:
    .venv/bin/python scripts/recall-search.py "query" [--top-k N]
"""

import argparse
import os
import re
import sqlite3
import struct
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import recall_lib  # noqa: E402

CFG = recall_lib.load()
DB = CFG["db"]
SOURCE = CFG["source"]
MODEL_NAME = CFG["model_name"]
DIMS = CFG["dims"]
DEFAULT_TOP_K = 5
SNIPPET_MAX = 200


def open_db():
    import sqlite_vec

    if not os.path.exists(DB):
        print(f"[recall] no index at {DB} — run `recall.sh reindex --force` first", file=sys.stderr)
        sys.exit(2)
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)  # review I2 — package idiom
    conn.enable_load_extension(False)
    return conn


def embed_query(text):
    from fastembed import TextEmbedding

    embedder = TextEmbedding(f"sentence-transformers/{MODEL_NAME}")
    return list(next(embedder.embed([text])))


def has_heading_column(conn):
    return any(r[1] == "heading" for r in conn.execute("PRAGMA table_info(chunks)"))


def first_heading(text):
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            return stripped.lstrip("#").strip()[:80]
    return "(no heading)"


def clean_snippet(text, max_len=SNIPPET_MAX):
    text = re.sub(r"\s+", " ", text).strip()
    return text[:max_len] + "..." if len(text) > max_len else text


def search(query, top_k=DEFAULT_TOP_K):
    conn = open_db()
    emb = embed_query(query)
    blob = struct.pack(f"{len(emb)}f", *emb)

    knn = conn.execute(
        "SELECT id, distance FROM chunks_vec WHERE embedding MATCH ? AND k = ?",
        (blob, top_k * 3),
    ).fetchall()
    if not knn:
        return []

    # A7/D8: prefer the stored breadcrumb. If the column is absent the index predates the
    # A1/A7 migration — degrade to the text-only path + first_heading() and warn LOUDLY
    # (never crash: this searcher is a separate process; a 'no such column' would surface
    # as a misleading "search failed"). The fix is a one-time `recall.sh reindex --force`.
    heading_ok = has_heading_column(conn)
    if not heading_ok:
        print(
            "[recall] index schema outdated (no 'heading' column) — run "
            "`recall.sh reindex --force` to enable heading breadcrumbs",
            file=sys.stderr,
        )

    ids = [r["id"] for r in knn]
    dist_map = {r["id"]: r["distance"] for r in knn}
    placeholders = ",".join("?" for _ in ids)
    cols = "id, path, start_line, end_line, hash, text" + (", heading" if heading_ok else "")
    chunks = conn.execute(
        f"SELECT {cols} FROM chunks WHERE id IN ({placeholders}) AND source=?",
        (*ids, SOURCE),
    ).fetchall()

    results = []
    for c in chunks:
        d = dist_map.get(c["id"], 1.0)
        stored = c["heading"] if heading_ok else None
        results.append(
            {
                "score": round(1.0 - d, 4),
                "path": c["path"],
                "start_line": c["start_line"],
                "end_line": c["end_line"],
                "hash": c["hash"],
                "heading": stored or first_heading(c["text"] or ""),
                "snippet": clean_snippet(c["text"] or ""),
            }
        )
    results.sort(key=lambda r: r["score"], reverse=True)
    return results[:top_k]


def render(results):
    if not results:
        return "(no results)"
    lines = []
    for i, r in enumerate(results, 1):
        lines.append(
            f"{i}. {r['path']}:{r['start_line']}-{r['end_line']}  "
            f"[score {r['score']:.3f}]  {r['heading']}"
        )
        lines.append(f"   {r['snippet']}")
        lines.append(f"   hash: {r['hash']}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("query")
    ap.add_argument("--top-k", type=int, default=DEFAULT_TOP_K)
    args = ap.parse_args()
    print(render(search(args.query, top_k=args.top_k)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
