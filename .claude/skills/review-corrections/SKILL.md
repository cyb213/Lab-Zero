---
name: review-corrections
description: Triage pending correction candidates (captured by the recall Stop hook) into memory — promote the worthy, drop the noise, surface the contested. Closes the correction→memory loop.
disable-model-invocation: true
---

# Review Corrections

The recall **Stop hook** flags messages that look like corrections or standing preferences
and appends them to `memory/recall-misses.jsonl`. The detector is deliberately **NOISY** (it
also flags praise like "nice", and bare "stop"/"don't") — so **your judgment is the filter**,
not the regex. This ceremony reads the pending candidates and, per candidate, **promotes** the
worthy ones into memory, **drops** clear noise, and **surfaces** the contested ones for the
user to rule on. Then it advances a review high-water-mark so nothing is re-reviewed.

Run it when the session-start nudge says corrections are pending, or whenever the user asks.

## 1. Read the pending candidates

```
bash scripts/recall.sh misses --json
```

Each entry: `{ts, event:"miss", last_user, transcript_path}`. "Pending" = captured since the
last review — the reader filters by the high-water-mark automatically. If the list is empty,
say so and stop. (`bash scripts/recall.sh misses` with no flag gives a human-readable list.)

## 2. Judge each candidate — promote / drop / surface

Read each `last_user` and decide:

- **PROMOTE** — a real, durable lesson: a correction of a mistake worth not repeating, or a
  standing preference ("from now on…", "I prefer…", "always/never…"). Distill it into a crisp,
  general rule — the *lesson*, not the verbatim complaint.
- **DROP** — noise the detector over-caught: praise ("nice", "good job"), a bare "stop"/"don't"
  with no durable content, a one-off that won't recur, or something already in memory. Do
  nothing — advancing the high-water-mark (step 4) excludes it from future reviews.
- **SURFACE** — genuinely ambiguous, or a judgment call the user owns (a preference you're not
  sure is durable, or one that contradicts existing memory). List it for the user; do **not**
  promote it unilaterally.

When torn between PROMOTE and DROP, prefer **SURFACE** — never auto-write a memory you're unsure
about. That is how memory gets polluted.

## 3. Promote — ONE pipeline, destination derived at runtime

First resolve the workspace's memory target. **NEVER hard-code a path** — deriving it keeps the
write inside THIS workspace's own namespace (the isolation rule):

```
.venv/bin/python scripts/recall_lib.py --json     # read auto_memory_dir + auto_memory_key
```

- **Native memory** (`auto_memory_dir` is non-null AND that directory exists — e.g. Claude
  Code): write the lesson as a new memory file in that directory, following the workspace's
  existing memory-file convention (read an existing file + its `MEMORY.md` to match the format —
  typically frontmatter `name`/`description`/`metadata`, then the lesson, linking related
  memories with `[[name]]`), and add a one-line pointer to that directory's `MEMORY.md` index.
  This is context-loaded every session AND recall-indexed — the strongest surfacing.

- **Portable fallback** (no native namespace — Codex / plain clone): index-heal once, then
  append. The config is personal-not-machinery, so a clone may not yet index `LEARNED.md`:

  ```
  bash scripts/recall.sh misses --ensure-glob       # idempotent: adds memory/LEARNED.md to index_globs
  ```

  Append a dated, structured entry to `memory/LEARNED.md` (create it if absent):

  ```
  ## <ISO-ts> — <short lesson title>
  <the distilled lesson, in plain language>
  Source: correction at <ts>
  ```

`memory/LEARNED.md` is gitignored (personal) — never commit it.

## 4. Advance the review high-water-mark

Advance the mark to the `ts` of the newest candidate for which you (and every older pending
candidate) reached a **promote-or-drop** decision — both count as "decided". Anything you
**surfaced**, and everything after it, stays pending:

```
bash scripts/recall.sh misses --mark <ts-of-last-decided-candidate>
```

Use the last *decided* ts, **never** wall-clock "now". A single watermark can't skip a hole —
so if you surface a candidate in the middle of the list, advance only up to the one just before
it, and leave the rest pending. An interrupted or partial pass must leave the remainder pending
(no-recycle must not become no-review).

## 5. Reindex + report

If you promoted anything via the **portable** path, reindex so it's searchable (native promotes
are picked up by the auto-memory indexing automatically):

```
bash scripts/recall.sh reindex
```

Then give the user a short tally: N promoted (with titles), N dropped, N surfaced — and list the
surfaced ones for a ruling.

## Worked example

Pending (`bash scripts/recall.sh misses --json`):

1. `[2026-06-10T08:00:00Z]` "no, use Celsius not Fahrenheit for everything"
2. `[2026-06-10T09:30:00Z]` "nice, that's perfect"
3. `[2026-06-11T14:00:00Z]` "from now on always run the tests before saying done"
4. `[2026-06-12T10:00:00Z]` "hmm, maybe we should prefer pnpm over npm?"

Decisions:

1. **PROMOTE** — durable unit preference → "Always use Celsius; never convert to Fahrenheit."
2. **DROP** — praise, no lesson.
3. **PROMOTE** — standing process rule → "Run the test suite and confirm it's green before reporting a task done."
4. **SURFACE** — tentative ("maybe?"); the user's call.

#1–#3 are decided; #4 is surfaced and is the newest, so advance the mark through **#3's** ts and
leave #4 pending:

```
bash scripts/recall.sh misses --mark 2026-06-11T14:00:00Z
```

Report: *"2 promoted (Celsius units; tests-before-done), 1 dropped (praise), 1 surfaced — you
floated preferring pnpm; want that as a standing rule?"*
