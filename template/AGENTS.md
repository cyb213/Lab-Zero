# AGENTS.md — __PROJECT__

> __PURPOSE__
> Graduated from the Lab on __DATE__. The **canonical, harness-agnostic** constitution for this workspace — loaded by whichever coding agent you use (via this file directly, or via the `CLAUDE.md` wrapper for Claude Code). Loaded into every __PROJECT__ session.

## Who you're working with + how to work with them
Shared identity is the vendored copy `@identity/IDENTITY.md` (imported below). It was copied from your lab at stamp time and is **yours now** — this project's own. Nothing re-pulls it; if you change your lab's identity file and want that change here, copy it across by hand. (Engine machinery is different: `bash update.sh` refreshes it from the published release, and never touches this file.) Read it as part of this file.

@identity/IDENTITY.md

<!-- SYNC: keep this block byte-identical in every constitution file that carries it; edit all copies together -->
> **When you're talking to the user, communicate for the reader in front of you.** Match the depth to their declared technical level and preferences in `IDENTITY.md` — more depth or reasoning-first if that's what they asked for. Don't assume expertise they didn't claim, and don't condescend to expertise they did. Lead with the answer, then the detail. Explain or avoid jargon rather than leaving it unexplained. Keep sentences short — one idea each, rarely past about 25 words. When the user must act, give one step per sentence. Prefer the active voice when you know who acted. Use one name per thing and don't vary it for style. Stated preferences outrank these habits, but never the rules that follow. Keep paths, commands, filenames, flags, and versions **exact** — never round or "simplify" them. Use each thing's real name for the context you're in. Never drop a real caveat or uncertainty to sound simpler. None of this applies to code, tables, quoted output, or files you write — they stay as dense and complete as the work needs.

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
- Skills: `/wrap` (close a session), `/lab-plan` (structured planning), `/audit` (drift audit), `/review-corrections` (corrections → memory), `/discover-skills` (find repeatable work to formalize), `/bro` (re-explain the last answer in plain words).
- Build discipline: **plan consequential work** — any change to the shipped engine, a skill/template, a hook, recall, security, or a release (a small self-contained change doesn't need it) — with `/lab-plan` (up to a 3-reviewer adversarial pass, scaled to the change); **lean test-first** (TDD) wherever behavior is checkable — a failing-then-passing test is the proof, not eyeballing.
- **One task per session**, then `/wrap`.

## Recall
`bash scripts/recall.sh "<query>"` — semantic search over this workspace + its seeded auto-memory. `reindex` after material doc changes. Config: [recall.config.json](recall.config.json).

## Isolation
This workspace is its own git repo + its own memory namespace. It does not read or write any other workspace's tree or namespace.
