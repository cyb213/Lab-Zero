#!/usr/bin/env python3
"""
Generalized semantic memory indexer.

Stack: sqlite + sqlite-vec (pip package, no vendored binary) + fastembed
(all-MiniLM-L6-v2, 384d) + an FTS5 lexical index (chunks_fts), fused with the
vector KNN via Reciprocal Rank Fusion in the searcher (A2 hybrid retrieval).
Reads `recall.config.json` via recall_lib so paths, globs, model, dims, and the
source tag are config-driven and consistent with the searcher.

Usage:
    .venv/bin/python scripts/recall-index.py            # incremental
    .venv/bin/python scripts/recall-index.py --force    # full reindex
"""

import bisect
import hashlib
import json
import os
import re
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

# Schema marker (PRAGMA user_version): 1 = chunks.heading column (A1/A7);
# 2 = chunks_fts FTS5 lexical index for hybrid retrieval (A2).
SCHEMA_VERSION = 2

HEADING_RE = re.compile(r"^(#{1,6})\s+(\S.*?)\s*$")  # ATX heading w/ a non-empty title
FENCE_RE = re.compile(r"^\s*(```|~~~)")              # fenced code-block delimiter


# ── Heading-aware chunking with real line numbers (A1) + breadcrumbs (A7) ─────
def chunk_text(text, max_chars=MAX_CHUNK_CHARS, overlap=CHUNK_OVERLAP):
    """Yield (chunk_text, start_line, end_line, heading) with real 1-based line numbers.

    The doc is split on markdown headings: each heading plus its body (up to the next
    heading) is one section, stamped with its heading-path breadcrumb (A7), e.g.
    "Phase 5 › Risks › R2". A section whose body exceeds max_chars falls back to the
    original char window WITHIN that section (a strict refinement — never a giant chunk).
    Preamble before the first heading is its own breadcrumb-less chunk; a heading-less doc
    degenerates to the original whole-text windowing. '#' lines inside fenced code blocks
    are not treated as headings.
    """
    if not text:
        return
    lines = text.splitlines(keepends=True)
    line_starts = [0]
    for line in lines:
        line_starts.append(line_starts[-1] + len(line))

    def char_to_line(c):
        idx = bisect.bisect_right(line_starts, c) - 1
        return max(1, idx + 1)

    # Locate heading lines, skipping fenced code blocks: (line_idx, depth, title).
    headings = []
    in_fence = False
    for i, line in enumerate(lines):
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = HEADING_RE.match(line)
        if m:
            headings.append((i, len(m.group(1)), m.group(2).strip()))

    # Segments: (start_line_idx, end_line_idx, breadcrumb_or_None). One per heading
    # (body up to the next heading) + the preamble; heading-less ⇒ the whole doc.
    segments = []
    if not headings:
        segments.append((0, len(lines), None))
    else:
        if headings[0][0] > 0:
            segments.append((0, headings[0][0], None))  # preamble (no breadcrumb)
        stack = []  # ancestors: (depth, title)
        for j, (hidx, depth, title) in enumerate(headings):
            while stack and stack[-1][0] >= depth:
                stack.pop()
            stack.append((depth, title))
            crumb = " › ".join(t for _, t in stack)
            end_idx = headings[j + 1][0] if j + 1 < len(headings) else len(lines)
            segments.append((hidx, end_idx, crumb))

    def emit(a, b, crumb):
        """Tight (stripped) chunk over the raw char span [a, b), with absolute line numbers."""
        raw = text[a:b]
        stripped = raw.strip()
        if not stripped:
            return None
        lead = len(raw) - len(raw.lstrip())
        sa = a + lead
        ea = sa + len(stripped)  # exclusive
        return stripped, char_to_line(sa), char_to_line(ea - 1), crumb

    for s_idx, e_idx, crumb in segments:
        a = line_starts[s_idx]
        b = line_starts[e_idx]  # exclusive char offset
        if not text[a:b].strip():
            continue
        if (b - a) <= max_chars:
            out = emit(a, b, crumb)
            if out:
                yield out
        else:
            start = a  # window fallback WITHIN the section (absolute offsets)
            while start < b:
                end = min(start + max_chars, b)
                out = emit(start, end, crumb)
                if out:
                    yield out
                if end >= b:
                    break
                start = end - overlap


def chunk_id(path, start_line, body_hash):
    return hashlib.sha256(f"{SOURCE}:{path}:{start_line}:{body_hash}".encode()).hexdigest()


def fts_body(heading, text):
    """Shared FTS5 body builder (A2). The migration backfill AND the live insert loop both
    call this, so a migrated index and a force-reindexed index hold byte-identical FTS
    content (else search quality would silently depend on which path built the index). The
    breadcrumb leads so a heading token is searchable alongside the body."""
    return (heading or "") + "\n" + (text or "")


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
    heading TEXT,
    updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_chunks_path ON chunks(path);
CREATE INDEX IF NOT EXISTS idx_chunks_source ON chunks(source);
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_vec USING vec0(
    id TEXT PRIMARY KEY,
    embedding float[{DIMS}]
);
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
    id UNINDEXED,
    text,
    tokenize="unicode61 tokenchars '-_.'"
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


def ensure_schema(conn, force):
    """Migrate an older index in place. Runs in the INDEXER (a writer) — the SEARCHER never
    alters the schema, it degrades loudly. Both migrations are version-gated so they fire
    exactly once on an upgrade, and run here (before the not-changed early-return in main())
    so even a no-changed-files reindex upgrades a stale schema.

      v0 → v1 (A1/A7): add the 'heading' column if absent; a genuine add forces a full
        re-embed so existing rows gain breadcrumbs.
      v1 → v2 (A2): backfill the chunks_fts lexical index from existing chunks — NO re-embed
        (embeddings are untouched by A2), so the cheap backfill is correct. chunks_fts is
        already created (empty) by SCHEMA in open_db(), so the backfill MUST gate on the
        version, not table absence, or it would never fire on the common incremental upgrade.

    Returns the (possibly forced) flag."""
    cols = [r[1] for r in conn.execute("PRAGMA table_info(chunks)")]
    ver = conn.execute("PRAGMA user_version").fetchone()[0]
    if "heading" not in cols:
        conn.execute("ALTER TABLE chunks ADD COLUMN heading TEXT")
        conn.commit()
        print("[indexer] migrated schema: added 'heading' column → forcing full re-embed", flush=True)
        force = True
    if ver < SCHEMA_VERSION:
        n = 0
        for cid, heading, text in conn.execute("SELECT id, heading, text FROM chunks").fetchall():
            conn.execute("INSERT INTO chunks_fts(id, text) VALUES (?, ?)", (cid, fts_body(heading, text)))
            n += 1
        if n:
            print(f"[indexer] migrated schema: backfilled chunks_fts ({n} rows) → A2 hybrid retrieval", flush=True)
        conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
        conn.commit()
    return force


# ── Main ─────────────────────────────────────────────────────────────────────
def main(force=False):
    t_start = time.time()

    # Open + migrate the DB up front so user_version/ALTER can act and (on a genuine
    # migration) force a full re-embed before the changed-files window is computed.
    conn = open_db()
    force = ensure_schema(conn, force)

    # A3 — model-change self-heal. If the configured model differs from the one the index was
    # built with, auto-force a full re-embed so a mixed-model index never exists (the searcher
    # would otherwise refuse it). Mirrors the heading-migration force=True idiom above; heals
    # via the last_run_ts=0 reset (every file re-counts as changed), so even a no-changed-files
    # reindex fixes it. Gated on `not force` — a migration that already forced needn't re-check.
    if not force:
        models = {r[0] for r in conn.execute(
            "SELECT DISTINCT model FROM chunks WHERE source=?", (SOURCE,))}
        if models and models != {MODEL_NAME}:
            print(f"[indexer] model changed ({sorted(models)} → {MODEL_NAME}) "
                  f"→ forcing full re-embed", flush=True)
            force = True

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
        conn.close()
        save_state({"last_run_ts": t_start})
        return 0

    # Collect chunks
    all_chunks = []  # (cid, rel_path, text, sl, el, body_hash, heading)
    for abs_path, _ in changed:
        try:
            text = Path(abs_path).read_text(errors="replace")
        except Exception as e:
            print(f"  skip {abs_path}: {e}", flush=True)
            continue
        if not text.strip():
            continue
        rel = recall_lib.file_to_relpath(CFG, abs_path)
        for chunk, sl, el, heading in chunk_text(text):
            body_hash = hashlib.sha256(chunk.encode()).hexdigest()[:16]
            all_chunks.append((chunk_id(rel, sl, body_hash), rel, chunk, sl, el, body_hash, heading))

    print(f"[indexer] {len(all_chunks)} chunks to embed", flush=True)
    if not all_chunks:
        conn.close()
        save_state({"last_run_ts": t_start})
        return 0

    print(f"[indexer] loading {MODEL_NAME}...", flush=True)
    from fastembed import TextEmbedding

    embedder = TextEmbedding(f"sentence-transformers/{MODEL_NAME}")

    if force:
        conn.execute("DELETE FROM chunks WHERE source=?", (SOURCE,))
        conn.execute("DELETE FROM chunks_vec")  # vec + fts tables have no source column
        conn.execute("DELETE FROM chunks_fts")
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
            # A2: delete the FTS rows by these OLD ids — an edited chunk gets a NEW chunk_id
            # (sha over the body), so the per-insert delete (which only knows the new id)
            # would orphan the old FTS row. Mirror the chunks_vec delete here.
            for cid in ids:
                conn.execute("DELETE FROM chunks_vec WHERE id=?", (cid,))
                conn.execute("DELETE FROM chunks_fts WHERE id=?", (cid,))
            conn.execute("DELETE FROM chunks WHERE path=? AND source=?", (rel, SOURCE))
        conn.commit()

    now_ms = int(time.time() * 1000)
    inserted = 0
    t_embed = time.time()

    for i in range(0, len(all_chunks), BATCH_SIZE):
        batch = all_chunks[i : i + BATCH_SIZE]
        # A7: embed the breadcrumb + the chunk so the vector carries section context;
        # the raw chunk is still stored in `text` so the snippet stays clean.
        embeddings = list(
            embedder.embed([(c[6] + "\n\n" + c[2]) if c[6] else c[2] for c in batch])
        )
        for (cid, rel, text, sl, el, bh, heading), emb in zip(batch, embeddings):
            blob = struct.pack(f"{len(emb)}f", *emb)
            try:
                conn.execute(
                    "INSERT OR REPLACE INTO chunks(id, path, source, start_line, end_line, hash, model, text, heading, updated_at) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (cid, rel, SOURCE, sl, el, bh, MODEL_NAME, text, heading, now_ms),
                )
                conn.execute("DELETE FROM chunks_vec WHERE id=?", (cid,))
                conn.execute("INSERT INTO chunks_vec(id, embedding) VALUES (?, ?)", (cid, blob))
                conn.execute("DELETE FROM chunks_fts WHERE id=?", (cid,))
                conn.execute("INSERT INTO chunks_fts(id, text) VALUES (?, ?)", (cid, fts_body(heading, text)))
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
                conn.execute("DELETE FROM chunks_fts WHERE id=?", (cid,))
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
