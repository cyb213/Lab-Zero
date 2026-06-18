#!/usr/bin/env python3
"""
Generalized hybrid search backend.

Embeds the query via fastembed + runs a vector KNN through sqlite-vec, runs a
lexical bm25 query through an FTS5 index (chunks_fts), and fuses the two ranked
lists via Reciprocal Rank Fusion (A2) — so a query gets both semantic matches and
exact-token matches (identifiers, flags, paths, version tags). Always-on: an empty
FTS list reduces RRF to vector-only ordering. Renders the line-format recall.sh
consumers expect (file:line + score + heading + snippet + hash); the score is the
fused RRF score.

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
K_RRF = 60                 # Reciprocal Rank Fusion constant (the standard default)
W_FTS = 0.5                # lexical-list weight in RRF; vector list is 1.0. Semantics is the
                           # primary signal, lexical a precision booster for exact tokens —
                           # equal weight let FTS-rank-1 noise tie a true vector-rank-1 hit and
                           # regressed natural-language queries; 0.5 keeps the full lexical gain
                           # while improving positive+invariant (eval-tuned, the arbiter).
MAX_FTS_TOKENS = 32        # cap the sanitized OR-chain (SQLITE_MAX_EXPR_DEPTH guard)
_FTS_TOKEN = re.compile(r"[A-Za-z0-9_.\-]+")


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


def has_fts_table(conn):
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='chunks_fts'"
    ).fetchone() is not None


def fts_match_query(query, cap=MAX_FTS_TOKENS):
    """Build a safe FTS5 MATCH string from a raw query (A2). FTS5 MATCH throws on syntax
    chars (- " * : ( ^ and NEAR/OR/AND operators), so: extract token runs, drop tokens with
    no alphanumeric (pure punctuation like '-_.'), double-quote each (neutralizes operators —
    a quoted token is a literal phrase), OR-join, and cap the count (a pathological long query
    would build a huge OR-chain that can hit SQLITE_MAX_EXPR_DEPTH). Returns '' when no tokens
    survive — the caller then SKIPS FTS (MATCH '' itself throws). The table tokenizer's
    tokenchars '-_.' keep D-007 / --harness / v1.3.0-class tokens whole."""
    toks = [t for t in _FTS_TOKEN.findall(query or "") if re.search(r"[A-Za-z0-9]", t)]
    if not toks:
        return ""
    return " OR ".join('"%s"' % t for t in toks[:cap])


def rrf_fuse(vec_ids, fts_ids, k=K_RRF, w_vec=1.0, w_fts=1.0):
    """Reciprocal Rank Fusion: score[id] = Σ over lists of weight/(k + rank), rank 1-based
    per list (A2). Rank-based, so it blends the vector and lexical lists without reconciling
    their incompatible score scales; an empty fts_ids reduces it to vector-only ordering."""
    scores = {}
    for ids, w in ((vec_ids, w_vec), (fts_ids, w_fts)):
        for rank, cid in enumerate(ids, 1):
            scores[cid] = scores.get(cid, 0.0) + w / (k + rank)
    return scores


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
    candidate_k = max(20, top_k * 4)  # both pools deep + symmetric so neither biases RRF

    # ── vector KNN (semantic) ──────────────────────────────────────────────────
    emb = embed_query(query)
    blob = struct.pack(f"{len(emb)}f", *emb)
    vec_ids = [
        r["id"]
        for r in conn.execute(
            "SELECT id FROM chunks_vec WHERE embedding MATCH ? AND k = ?",
            (blob, candidate_k),
        ).fetchall()
    ]

    # ── lexical FTS5 (exact tokens) ─────────────────────────────────────────────
    # Degrade LOUD + vector-only if the index predates A2 (no chunks_fts): a separate
    # process must never raise 'no such table' — recall.sh would swallow it into a
    # misleading "search failed". The fix is a one-time `recall.sh reindex --force`.
    fts_ids = []
    if has_fts_table(conn):
        match = fts_match_query(query)
        if match:
            try:
                fts_ids = [
                    r["id"]
                    for r in conn.execute(
                        "SELECT id FROM chunks_fts WHERE chunks_fts MATCH ? "
                        "ORDER BY bm25(chunks_fts) LIMIT ?",
                        (match, candidate_k),
                    ).fetchall()
                ]
            except sqlite3.OperationalError as e:
                print(f"[recall] FTS query error ({e}) — using vector-only", file=sys.stderr)
    else:
        print(
            "[recall] index lacks FTS (no 'chunks_fts') — run `recall.sh reindex --force` "
            "for hybrid (lexical + vector) retrieval",
            file=sys.stderr,
        )

    if not vec_ids and not fts_ids:
        return []

    # A7/D8: prefer the stored breadcrumb. If the column is absent the index predates the
    # A1/A7 migration — degrade to the text-only path + first_heading() and warn LOUDLY.
    heading_ok = has_heading_column(conn)
    if not heading_ok:
        print(
            "[recall] index schema outdated (no 'heading' column) — run "
            "`recall.sh reindex --force` to enable heading breadcrumbs",
            file=sys.stderr,
        )

    # ── hydrate over the UNION (vector ∪ FTS), source-filter, fuse SURVIVORS ─────
    # chunks_fts is source-blind (id + text only); an FTS id of another source, or any id
    # with no surviving row, is dropped at hydration BEFORE ranking — so the rendered top-k
    # is always backed by a real, in-source row (never a phantom id / KeyError).
    union_ids = list(dict.fromkeys(vec_ids + fts_ids))
    placeholders = ",".join("?" for _ in union_ids)
    cols = "id, path, start_line, end_line, hash, text" + (", heading" if heading_ok else "")
    rows = conn.execute(
        f"SELECT {cols} FROM chunks WHERE id IN ({placeholders}) AND source=?",
        (*union_ids, SOURCE),
    ).fetchall()
    by_id = {r["id"]: r for r in rows}

    vec_surv = [cid for cid in vec_ids if cid in by_id]
    fts_surv = [cid for cid in fts_ids if cid in by_id]
    rrf = rrf_fuse(vec_surv, fts_surv, w_fts=W_FTS)
    ranked = sorted(by_id.keys(), key=lambda cid: (rrf.get(cid, 0.0), cid), reverse=True)

    results = []
    for cid in ranked[:top_k]:
        c = by_id[cid]
        stored = c["heading"] if heading_ok else None
        results.append(
            {
                "score": round(rrf.get(cid, 0.0), 4),
                "path": c["path"],
                "start_line": c["start_line"],
                "end_line": c["end_line"],
                "hash": c["hash"],
                "heading": stored or first_heading(c["text"] or ""),
                "snippet": clean_snippet(c["text"] or ""),
            }
        )
    return results


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
