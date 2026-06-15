---
name: wrap
description: Cleanly wrap a work session — ground state against git+filesystem, update and de-bloat the tracking files, ensure the next-session landing pad is grounded (not invented), scan staged changes for leaked secrets, then commit (and push if there's a remote). Invoke at session end, or whenever the user says "wrap".
---

# Session Wrap Protocol

Wrap is a sequence of **verified mechanical actions, not a written summary.** Writing a tidy "shipped X, next Y" paragraph fires a false *done* signal while the actual actions stay untouched. Do the actions, verify each one fired, **then** report what fired.

Run the steps in order. At every step, tracking files are **hypotheses**; `git` + the filesystem are **ground truth**. Never copy a status word ("done"/"shipped"/"deferred") from a tracking row without confirming it against reality first.

## Arguments

`$ARGUMENTS` — optional. A session-number hint (only if parallel sessions make the number genuinely ambiguous) or a one-line wrap note. Default: ground the number yourself in Step 0.

## Step 0 — Ground state

```bash
cd "$(git rev-parse --show-toplevel)"
git branch --show-current          # confirm intended branch
git status --porcelain             # what's actually changed this session
git log --oneline -8               # most recent committed sessions
ls -t Sessions/ | head -4          # most recent session notes
```

- **Session number N:** highest `NNN` across `ls Sessions/` (committed + working tree). If this session already created its note, **reuse that file** — do not mint a new number. If starting the note now, N = highest existing + 1. One session = exactly one note file (continuation work reuses the same file).
- **Parallel-session collision:** another session sharing this tree may have claimed N or the next decision ID. Cross-check `git log --oneline | grep -iE "session [0-9]+"`. If a clash is possible, take the next free number. The pre-commit hook is the mechanical backstop.
- **Clobber check:** if `git status` shows changes you did not make this session, STOP — a parallel session may have edited the tree. Re-read those files; recover via `git stash` if needed. Do not blindly overwrite.

## Step 1 — Verify completion is real

For every task this session claims to have finished: verify it, don't assume it. "I wrote the code" ≠ done. Confirm via the file existing / the test passing / the command succeeding / the deploy landing. If something is only partially done, it is **not** "done" — record it as in-progress.

## Step 2 — Update + ground + de-bloat the tracking files

Update the workspace's tracking files (those listed in `recall.config.json` → `tracking_files`; `Log/STATUS.md` at minimum) so they reflect the **final** state:

- **`Log/STATUS.md`** — current project state.
- **`Log/TASKS.md`** (if used) — live dashboard. Move completed items to "Recently Done" (keep ~10). Update WIP / Next Up.
- **`Log/PLAN.md`** (if used) — mark tasks done; the full historical record.
- **`Log/DECISIONS.md`** (if used) — add an entry for any decision made this session.

**De-bloat as you write:** keep tracking rows terse (≤200 chars); detail goes to `Sessions/`, `Log/plans/`, or DECISIONS.md — not into the row. If a row has grown into a paragraph, trim it to a pointer.

**Drift gate:** every configured tracking file MUST contain the literal `session N` (no zero-padding) before the session-note commit will pass the pre-commit hook.

## Step 3 — Session note

Ensure `Sessions/YYYY-MM-DD_NNN_<slug>.md` exists. It must carry the final state, not an "I'll come back to this" stub. If the note has a verification block, fill every field (`n/a — <reason>` if it doesn't apply) — the act of filling it IS the spot-check.

## Step 4 — Next-session landing pad (ground it — do NOT declare it)

Confirm the next session can pick up cleanly: tracking WIP / Next Up rows are **coherent and grounded against reality**, and any in-progress `Log/plans/*.md` has an accurate `Status:` field. That is the whole job here.

**Do NOT** author new scope, list "next session we should…", or announce what comes next — that presumes the user's priorities. Document state — done / blocked / decisions-needed — and let the user choose the next move.

## Step 5 — Redaction scan (before any push)

Mechanical secret-scan over the staged diff. Run **before** push:

```bash
git diff --cached -U0 | grep -nE '^\+' | grep -inE \
  'eyJ[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|[0-9]{8,12}:AA[A-Za-z0-9_-]{30,}|(token|secret|api[_-]?key|password|bearer)["'"'"' :=]+[A-Za-z0-9_./+:-]{20,}'
```

If any line matches: **STOP. Do not push.** Surface the `file:line` + matched pattern to the user — they decide redact-only vs. rotate. A false positive (test fixture, public key) is fine to clear after eyeballing, but the scan must run and you must look.

## Step 6 — Reindex recall

If any indexed doc changed materially this session (anything under the `index_globs` in `recall.config.json`, or auto-memory):

```bash
bash scripts/recall.sh reindex     # incremental — only changed files
```

## Step 7 — Commit (+ push if there's a remote)

```bash
git add -A
git commit -m "session N — <one-line: what shipped + decision id if any>"
git remote -v >/dev/null 2>&1 && git push || true
```

The pre-commit drift hook gates the tracking-file `session N` rule and the parallel-session number-collision check. If it blocks, fix the cause — use `--no-verify` only with a real reason (emergency, tooling, backfill), and say so.

## Step 8 — Confirm clean wrap, then report actions

```bash
git status --short                 # must be clean (committed, not just staged)
git log @{u}..HEAD 2>/dev/null     # empty if pushed (or no upstream)
ls -la memory/index.db             # mtime newer than your last doc edit, if you reindexed
```

Only after the checks pass, report the wrap as a list of **actions that fired** (committed SHA, files touched, tests run, decisions logged, reindex done) — not a narrative. If any check fails, do the action first, then report.

## What `/wrap` does NOT do

- Does **not** invent or announce next-session scope (Step 4).
- Does **not** push if the redaction scan hits (Step 5).
- Does **not** mark anything "done" that wasn't verified (Step 1).
- Does **not** bypass the drift gate to "save time."

## When to invoke

- the user says "wrap", "wrap it up", "let's close the session", or invokes `/wrap`.
- You judge the session's work is complete and it's time to close.
- After a context-weight warning, once the in-flight task reaches a committable state.
