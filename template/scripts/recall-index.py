#!/usr/bin/env python3
"""
Generalized semantic memory indexer.

Stack: sqlite + sqlite-vec (pip package, no vendored binary) + fastembed
(all-MiniLM-L6-v2, 384d). Reads `recall.config.json` via recall_lib so paths,
globs, model, dims, and the source tag are config-driven and consistent with
the searcher.

Usage:
    .venv/bin/python scripts/recall-index.py            # incremental
    .venv/bin/python scripts/recall-index.py --force    # full reindex
"""

import bisect
import hashlib
import json
import os
import sqlite3
import struct
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import recall_lib  # noqa: E402

CFG = recall_lib.load()
ROOT = CFG["root"]
DB = CFG["db"]
STATE_FILE = CFG["state_file"]
SOURCE = CFG["source"]
MODEL_NAME = CFG["model_name"]
DIMS = CFG["dims"]

BATCH_SIZE = 200
MAX_CHUNK_CHARS = 600
CHUNK_OVERLAP = 120


# ── Chunking with real line numbers ──────────────────────────────────────────
def chunk_text(text, max_chars=MAX_CHUNK_CHARS, overlap=CHUNK_OVERLAP):
    """Yield (chunk_text, start_line, end_line) with real 1-based line numbers."""
    if not text:
        return
    lines = text.splitlines(keepends=True)
    line_starts = [0]
    for line in lines:
        line_starts.append(line_starts[-1] + len(line))

    def char_to_line(c):
        idx = bisect.bisect_right(line_starts, c) - 1
        return max(1, idx + 1)

    n = len(text)
    start = 0
    while start < n:
        end = min(start + max_chars, n)
        chunk = text[start:end].strip()
        if chunk:
            yield chunk, char_to_line(start), char_to_line(end - 1)
        if end >= n:
            break
        start = end - overlap


def chunk_id(path, start_line, body_hash):
    return hashlib.sha256(f"{SOURCE}:{path}:{start_line}:{body_hash}".encode()).hexdigest()


# ── State ────────────────────────────────────────────────────────────────────
def load_state():
    p = Path(STATE_FILE)
    if p.exists():
        try:
            return json.loads(p.read_text())
        except Exception:
            pass
    return {"last_run_ts": 0}


def save_state(state):
    Path(STATE_FILE).parent.mkdir(parents=True, exist_ok=True)
    Path(STATE_FILE).write_text(json.dumps(state))


# ── DB ───────────────────────────────────────────────────────────────────────
SCHEMA = f"""
CREATE TABLE IF NOT EXISTS chunks (
    id TEXT PRIMARY KEY,
    path TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT '{SOURCE}',
    start_line INTEGER NOT NULL,
    end_line INTEGER NOT NULL,
    hash TEXT NOT NULL,
    model TEXT NOT NULL,
    text TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_chunks_path ON chunks(path);
CREATE INDEX IF NOT EXISTS idx_chunks_source ON chunks(source);
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_vec USING vec0(
    id TEXT PRIMARY KEY,
    embedding float[{DIMS}]
);
"""


def open_db():
    import sqlite_vec

    Path(DB).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB)
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)  # review I2 — package idiom, not a reconstructed .so path
    conn.enable_load_extension(False)
    conn.executescript(SCHEMA)
    return conn


# ── Main ─────────────────────────────────────────────────────────────────────
def main(force=False):
    t_start = time.time()
    state = load_state()
    last_run_ts = 0 if force else state.get("last_run_ts", 0)

    print(f"[indexer] root={ROOT} source={SOURCE} force={force} last_run={last_run_ts}", flush=True)
    if CFG.get("auto_memory_dir"):
        print(f"[indexer] auto-memory: {CFG['auto_memory_dir']}", flush=True)

    all_files = recall_lib.discover_files(CFG)
    print(f"[indexer] {len(all_files)} files in allowlist", flush=True)

    changed = []
    for abs_path in all_files:
        try:
            mtime = os.path.getmtime(abs_path)
        except OSError:
            continue
        if mtime > last_run_ts:
            changed.append((abs_path, mtime))

    print(f"[indexer] {len(changed)} files changed since last run", flush=True)
    if not changed:
        save_state({"last_run_ts": t_start})
        return 0

    # Collect chunks
    all_chunks = []  # (cid, rel_path, text, sl, el, body_hash)
    for abs_path, _ in changed:
        try:
            text = Path(abs_path).read_text(errors="replace")
        except Exception as e:
            print(f"  skip {abs_path}: {e}", flush=True)
            continue
        if not text.strip():
            continue
        rel = recall_lib.file_to_relpath(CFG, abs_path)
        for chunk, sl, el in chunk_text(text):
            body_hash = hashlib.sha256(chunk.encode()).hexdigest()[:16]
            all_chunks.append((chunk_id(rel, sl, body_hash), rel, chunk, sl, el, body_hash))

    print(f"[indexer] {len(all_chunks)} chunks to embed", flush=True)
    if not all_chunks:
        save_state({"last_run_ts": t_start})
        return 0

    print(f"[indexer] loading {MODEL_NAME}...", flush=True)
    from fastembed import TextEmbedding

    embedder = TextEmbedding(f"sentence-transformers/{MODEL_NAME}")

    conn = open_db()

    if force:
        conn.execute("DELETE FROM chunks WHERE source=?", (SOURCE,))
        conn.execute("DELETE FROM chunks_vec")  # vec table has no source column
        conn.commit()
    else:
        # Drop chunks for the files we're re-indexing (handles edits cleanly).
        for rel in sorted({c[1] for c in all_chunks}):
            ids = [
                r[0]
                for r in conn.execute(
                    "SELECT id FROM chunks WHERE path=? AND source=?", (rel, SOURCE)
                ).fetchall()
            ]
            for cid in ids:
                conn.execute("DELETE FROM chunks_vec WHERE id=?", (cid,))
            conn.execute("DELETE FROM chunks WHERE path=? AND source=?", (rel, SOURCE))
        conn.commit()

    now_ms = int(time.time() * 1000)
    inserted = 0
    t_embed = time.time()

    for i in range(0, len(all_chunks), BATCH_SIZE):
        batch = all_chunks[i : i + BATCH_SIZE]
        embeddings = list(embedder.embed([c[2] for c in batch]))
        for (cid, rel, text, sl, el, bh), emb in zip(batch, embeddings):
            blob = struct.pack(f"{len(emb)}f", *emb)
            try:
                conn.execute(
                    "INSERT OR REPLACE INTO chunks(id, path, source, start_line, end_line, hash, model, text, updated_at) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (cid, rel, SOURCE, sl, el, bh, MODEL_NAME, text, now_ms),
                )
                conn.execute("DELETE FROM chunks_vec WHERE id=?", (cid,))
                conn.execute("INSERT INTO chunks_vec(id, embedding) VALUES (?, ?)", (cid, blob))
                inserted += 1
            except Exception as e:
                print(f"  insert fail {rel}:{sl}: {e}", flush=True)
        conn.commit()
        print(
            f"[indexer]   {min(i + BATCH_SIZE, len(all_chunks))}/{len(all_chunks)} chunks "
            f"({inserted} inserted, {time.time() - t_embed:.1f}s)",
            flush=True,
        )

    elapsed = time.time() - t_embed
    rate = inserted / elapsed if elapsed > 0 else 0
    print(f"[indexer] embedded {inserted} chunks in {elapsed:.1f}s ({rate:.0f}/s)", flush=True)

    # Stale-path cleanup: chunks whose source file left the allowlist.
    in_scope = {recall_lib.file_to_relpath(CFG, p) for p in all_files}
    db_paths = {
        r[0]
        for r in conn.execute(
            "SELECT DISTINCT path FROM chunks WHERE source=?", (SOURCE,)
        ).fetchall()
    }
    stale = db_paths - in_scope
    if stale:
        for sp in stale:
            ids = [
                r[0]
                for r in conn.execute(
                    "SELECT id FROM chunks WHERE path=? AND source=?", (sp, SOURCE)
                ).fetchall()
            ]
            for cid in ids:
                conn.execute("DELETE FROM chunks_vec WHERE id=?", (cid,))
            conn.execute("DELETE FROM chunks WHERE path=? AND source=?", (sp, SOURCE))
        conn.commit()
        print(f"[indexer] cleaned {len(stale)} stale path(s)", flush=True)

    total = conn.execute("SELECT COUNT(*) FROM chunks WHERE source=?", (SOURCE,)).fetchone()[0]
    print(f"[indexer] DB: {total} chunks total", flush=True)
    print(f"[indexer] wall: {time.time() - t_start:.1f}s", flush=True)

    conn.close()
    save_state({"last_run_ts": t_start})
    return 0


if __name__ == "__main__":
    force = "--force" in sys.argv
    try:
        sys.exit(main(force=force))
    except Exception as e:
        import traceback

        print(f"[indexer] ERROR: {e}", flush=True)
        traceback.print_exc()
        sys.exit(1)
