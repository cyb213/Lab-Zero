# Changelog

All notable changes to Lab Zero. Newest first. Versions follow [semantic versioning](https://semver.org).

This file is what `update.sh --check` reads to show you what's new in a release — so each entry is a short, user-facing summary of what changed, not an internal commit log.

## v1.13.0 — 2026-07-12

- **Oversized tracking files now block a commit (the 64 KB size warning gained a hard 128 KB tier).** v1.12.0 added a warn-only notice when a staged tracking file (`Log/STATUS.md` / `TASKS.md` / `PLAN.md` / `DECISIONS.md`) passed 64 KB — and said it *never blocks a commit*. This adds a second, blocking tier: a tracking file staged over **128 KB** now fails the pre-commit hook (whole-file readability is load-bearing — a file that big has stopped being reliably readable in one pass). The 64 KB warn level (`LAB_TRACKING_SIZE_WARN_KB`) is unchanged; the new block level is `LAB_TRACKING_SIZE_BLOCK_KB` (default 128, and it can never be set below the warn level). To land an oversized tracking file anyway, bypass the hook with `git commit --no-verify`. This only fires once a single tracking file crosses 128 KB, so if yours are a normal size nothing changes.

## v1.12.0 — 2026-07-12

Bug-fix + hardening release — five engine fixes found by a full factory audit, all shipped test-first.

- **Fixed: recall-trail corruption.** A search with no ID hits could write malformed JSON lines into `memory/recall-trail.jsonl`; the trail now always appends exactly one valid line per search. `lab doctor` gains `trail:jsonl` / `misses:jsonl` validity rows, so if an older trail already carries corrupt lines you'll see a plain `WARN N/M unparseable` instead of silent rot.
- **Fixed: harness wiring broke on quotes in the workspace path.** `scripts/wire-harness.sh` now JSON-escapes the workspace root, so a `"` or `\` in your path no longer produces invalid `settings.json` / `hooks.json`.
- **Fixed: `setup-engine.sh` crash under `set -u`** when the extra-args array is empty (bash-3.2-safe guard; behavior otherwise unchanged).
- **Pre-commit hook hardening.** The drift gate now follows renames (`git mv`), reads *staged* content instead of the working tree (an untracked or unstaged edit can no longer satisfy — or slip past — the gate), and adds a warn-only tracking-file size warning at 64 KB (`LAB_TRACKING_SIZE_WARN_KB`; it never blocks a commit).
- **`/wrap` gains a "reconcile superseded claims" duty** — a session that ships work now also corrects any older "not started / not done" claims about it in the tracking files. Plus docs cleanup: kickoff points at `IDENTITY.md` (not a stale filename), `/lab-plan` wording is harness-neutral, seed docs name the genome trio and the `.agents/skills/` ceremony directory, and drift-prone count literals were removed.

## v1.11.2 — 2026-07-09

- **Fixed: graduating a project whose name or one-line purpose contained an apostrophe could break the new workspace and abort the graduation partway through.** `new-project.sh` filled in your `--name`/`--purpose` text across *every* stamped file — including a shell script — by raw find-and-replace, so a value like `O'Brien` or `it's` produced a syntactically broken git pre-commit hook, the initial commit failed, and the new workspace was left half-created. The stamper now substitutes your text only into Markdown, wires the JSON hooks safely, and never rewrites shell files; it also builds the virtualenv and seeds memory *after* the first commit so a failed stamp leaves less behind. Only creating a *new* project was affected — existing workspaces are unchanged.

## v1.11.1 — 2026-06-22

- **Docs: the README and AGENTS now list all the work ceremonies.** `/review-corrections` and `/discover-skills` ship in every Lab and stamped project but were missing from the ceremony lists in the docs — only the core `/lab-plan`, `/audit`, `/wrap` were named. They're now listed alongside the rest (Lab `README` / `AGENTS` / `CLAUDE` + the stamped-project template). Docs only; nothing changes if you just run your Lab.

## v1.11.0 — 2026-06-22

- **New `/discover-skills` — surface the repeatable work worth formalizing.** A ceremony that scans your workspace's own narrative (session-note titles, commit subjects, the planning/decisions logs) for work you keep doing by hand, and writes a single **read-only** review doc proposing which patterns are worth turning into a skill or script — each with a recommendation (codify / document / skip). It **proposes only**: it scaffolds nothing and changes nothing; you decide what to act on (via `/lab-plan`). A low-frequency session-start reminder points you at it once you've built up enough history, stays quiet otherwise, yields to other nudges, and is tunable/silenceable via `LAB_DISCOVER_MIN_SESSIONS` / `LAB_DISCOVER_EVERY`.

## v1.10.1 — 2026-06-21

- **New `CONTRIBUTING.md`.** A short guide on how to report bugs (open an issue) and send machinery changes upstream (`contribute.sh`) — and why you shouldn't PR this repo directly (it's a build output, overwritten each release). Docs only; nothing changes if you just run your Lab.

## v1.10.0 — 2026-06-21

- **First-run setup now shows the embedding-model download instead of looking frozen.** On a fresh clone, the very first index build downloads a ~100MB embedding model — which used to happen in silence, so setup looked hung for a minute or two. Setup now prints a one-time heads-up and lets the live download progress bar through, so you can see it working. Only the first-run bootstrap is affected; later runs are cached, and the manual `recall.sh reindex` command already showed progress.

## v1.9.1 — 2026-06-20

- **Fix: `update.sh` now delivers `PERMISSIONS.md` to existing installs.** v1.9.0 added the `PERMISSIONS.md` guide and a pointer to it from your README, but `update.sh`'s copy-list didn't include the file itself — so updating to v1.9.0 refreshed the pointer without landing the file it points to (a dangling link). This adds `PERMISSIONS.md` to the copy-list, so updating now lands it. Fresh clones already had the file, so nothing changes for them.

## v1.9.0 — 2026-06-20

- **New `PERMISSIONS.md`.** A hand-mapping guide for choosing equivalent permission/approval postures across Claude Code and Codex. It maps Claude's fine-grained `permissions {allow, ask, deny}` + modes to Codex's `approval_policy` + `sandbox_mode`, and notes what's lossy in each direction. It's a map, not an auto-translator: **Lab Zero sets no permissions for you** — safe, prompt-first defaults lead, and riskier postures are described rather than shipped as copy-paste config. Pointers added from README and AGENTS. (Only relevant if you run both harnesses and want to match a posture across them; otherwise nothing changes for you.)

## v1.8.0 — 2026-06-19

- **`lab doctor` — one command to check your install is healthy.** A new read-only `bash scripts/lab-doctor.sh` inspects the whole recall engine in a single pass — virtualenv, dependencies, config, the search index, the embedding model, index freshness, and the Codex hook wiring — and prints a plain OK / WARN / FAIL report with a one-line fix for anything that's off. It exits non-zero only when something is genuinely broken (so you can wire it into your own scripts), does no network call, and changes nothing. Until now these problems only surfaced reactively and cryptically — a failed search, a silent fallback to a degraded state; now you can ask the question directly and get a straight answer. (The Codex check confirms the hook *wiring* and reminds you to run `/hooks` — it doesn't claim the trust step is done, since that's interactive.)

## v1.7.0 — 2026-06-18

- **Hardened leak protection.** A defense-in-depth redaction screen now runs in the pre-commit hook (in addition to the release-time audit), catching accidental personal-data, secret, or absolute-path leaks in staged `src/`/`assets/` changes before they're committed. Mostly relevant if you maintain machinery under those paths; otherwise nothing changes for you.

## v1.6.0 — 2026-06-18

- **The agent learns from your corrections.** When you correct the agent — telling it it got something wrong, or stating a standing preference — those moments are now captured as candidates instead of slipping away. A new `/review-corrections` skill walks you through the pending ones so you can promote the worthwhile lessons into the agent's long-term memory, drop the noise, and flag the rest. It closes the loop, so a correction you make once actually sticks.
- **`recall.sh misses`.** Lists the correction candidates waiting for review (add `--json` for the raw entries), so you can see what's pending before you sit down to triage.
- **A gentle review nudge.** Every so often (about every 8 sessions, tunable) the session-start message reminds you to run `/review-corrections` — but only when there are actually candidates waiting. No network call, instant, works offline.
- **Self-trimming recall logs.** The recall activity logs now keep just their most recent entries (a generous tail, tunable) instead of growing without bound, so a long-lived workspace stays tidy on its own.

## v1.5.0 — 2026-06-18

- **Recall won't silently return bad results after a model change.** If you change the embedding model in your recall config without rebuilding the index, your stored vectors and your new query end up measured with different models — which aren't comparable, and used to produce quiet, low-quality results. Recall now detects the mismatch, refuses with a clear message instead of guessing, and points you at `reindex`. A plain reindex also notices the change on its own and rebuilds the index automatically, so the fix is one command. If you never change the model, nothing changes for you.

## v1.4.0 — 2026-06-18

- **Hybrid recall: exact-token search alongside meaning.** Recall now runs a lexical full-text search next to the existing meaning-based search and fuses the two rankings, so queries for exact tokens — flag names, file paths, env-var names, version tags, library names, error codes — land on the right result even when meaning-based search alone drifts past them. Natural-language search is unchanged: meaning stays the primary signal, the lexical match is a precision booster on top.
- **One-time index upgrade.** The first reindex after this update adds the new lexical index to your existing recall database. `update.sh` runs it for you.

## v1.3.0 — 2026-06-17

- **Sharper recall.** Recall now splits your documents along their heading structure instead of blind fixed-size windows, so a search lands on the right section more often — especially for answers that live in short, deeply-nested sections.
- **Heading breadcrumbs in results.** Each result now shows the full heading path it came from (e.g. `Architecture › Storage › Indexing`), so you can see a match's context at a glance instead of guessing where it sits.
- **One-time index upgrade.** The first reindex after this update rebuilds the recall index with the new structure — a full re-embed, so it's slower than usual just that once. `update.sh` runs it for you.

## v1.2.0 — 2026-06-17

- **Update notifications.** Every so often (about every 12 sessions, tunable) the session-start nudge reminds you to check whether a newer Lab Zero is out. It does no network call itself, so it's instant and works offline — it just reminds you to run the check.
- **`update.sh --check`.** A read-only command that tells you the version you're on, the latest published version, and the changelog for what's new — without changing anything. Run it, decide, then `bash update.sh` if you want it.
- **Tag-aware `update.sh`.** Updates now land the latest *published release*, not whatever happens to be on the main branch at the moment. `--ref <tag|branch>` pins a specific version (or pulls the bleeding edge) on demand.
- **Version awareness.** Every clone now carries a `VERSION` file and this `CHANGELOG.md`, so it can tell what it's running and what's changed.

## v1.1.0 — 2026-06-17

- **`contribute.sh`.** A helper for sending machinery improvements you made locally back upstream: it extracts a machinery-only patch of your changes, runs a fail-closed leak audit over it, and writes a reviewable patch plus a per-path routing table. The mirror image of `update.sh` (which pulls changes down).

## v1.0.1 — 2026-06-16

- **`/new-project --harness`.** The graduation skill now surfaces the harness option, so you can spin up a new project with the Codex layer wired in from the start (not just Claude Code).

## v1.0.0 — 2026-06-15

- **Initial public release.** A clone-and-go agent workspace with:
  - **Recall** — semantic search over your workspace docs plus the agent's long-term memory.
  - **Seeded memory** — a starter set of work-habit lessons the agent follows, extensible as you go.
  - **Continuity** — STATUS + session notes so any session picks up cold.
  - **Ceremonies** — `/setup`, `/kickoff`, `/new-project`, `/lab-plan`, `/audit`, `/wrap`.
  - **File protection** — a best-effort hook that guards sensitive files from structured edits.
- **Harness-agnostic.** Works on Claude Code out of the box; Codex is also supported with a one-time trust step.
- **`update.sh`.** Refresh the machinery (recall engine, template, skills) from upstream without touching your personal layer (identity, memories, projects).
