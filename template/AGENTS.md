# AGENTS.md — __PROJECT__

> __PURPOSE__
> Graduated from the Lab on __DATE__. The **canonical, harness-agnostic** constitution for this workspace — loaded by whichever coding agent you use (via this file directly, or via the `CLAUDE.md` wrapper for Claude Code). Loaded into every __PROJECT__ session.

## Who you're working with + how to work with them
Shared identity is the vendored copy `@identity/IDENTITY.md` (imported below). It was copied from your lab at stamp time; run `lab sync __SLUG__` (when available) to re-pull updates. Read it as part of this file.

@identity/IDENTITY.md

## What this is
__PURPOSE__

Fill this in: the one-paragraph "what __PROJECT__ is and why it exists." Keep the full intent in [Source/INTENT.md](Source/INTENT.md) and the spec in [Source/SPEC.md](Source/SPEC.md) — this is just the orientation.

## The genome (read these to pick the project up cold)
- [Source/INTENT.md](Source/INTENT.md) — why this exists, who it's for, what success looks like.
- [Source/SPEC.md](Source/SPEC.md) — what it is / does, scope, constraints.
- (optional, add when warranted) `Source/USER-STORIES.md`, `Source/INCEPTION.md` (quality bars), `Source/ARCHITECTURE-OPEN-QUESTIONS.md`.

## Continuity
- On session start: read [Log/STATUS.md](Log/STATUS.md) + the latest file in `Sessions/`, then resume.
- Write progressive notes to `Sessions/YYYY-MM-DD_NNN_<slug>.md` (numbering starts at 001 for this project).
- Tracking: `Log/{STATUS,TASKS,PLAN,DECISIONS}.md`. The pre-commit drift-gate requires all four to carry the literal `session N` before a new session-note commit lands.
- Skills: `/wrap` (close a session), `/lab-plan` (structured planning), `/audit` (drift audit), `/review-corrections` (corrections → memory), `/discover-skills` (find repeatable work to formalize).
- Build discipline: **plan non-trivial work** with `/lab-plan` (it runs a 3-reviewer adversarial pass); **lean test-first** (TDD) wherever behavior is checkable — a failing-then-passing test is the proof, not eyeballing.
- **One task per session**, then `/wrap`.

## Recall
`bash scripts/recall.sh "<query>"` — semantic search over this workspace + its seeded auto-memory. `reindex` after material doc changes. Config: [recall.config.json](recall.config.json).

## Isolation
This workspace is its own git repo + its own memory namespace. It does not read or write any other workspace's tree or namespace.
