# AGENTS.md — your Lab

> Your home base for thinking through ideas, analysis, and building your projects. This is the **canonical, harness-agnostic** constitution for this workspace — loaded by whichever coding agent you use (via this file directly, or via the `CLAUDE.md` wrapper for Claude Code). (This is the genericized "Lab Zero" architecture — clone it, make it yours.)

## What this is
The **Lab** is where you ideate and analyze, then **graduate** serious ideas into their own full-rig project workspaces under `~/Projects/<slug>/`. The Lab and each project are separate git repos with separate memory namespaces, so work in one never collides with another.

Capabilities available in every session here:
- **Recall** — semantic search over your docs + the agent's long-term memory.
- **Seeded memory** — a starter set of work-habit lessons the agent follows (extend it as you go).
- **Continuity** — STATUS + session notes so any session picks up cold.
- **Skills** — `/setup` (personalize), `/kickoff` (shape a raw idea), `/new-project` (graduate it), plus the full set of work ceremonies shipped in `.agents/skills/` — one directory per skill; each `SKILL.md`'s frontmatter says when to use it (that directory is the always-current list).

## Who you're working with
Your identity + working style live in `@IDENTITY.md` (imported below). Fill it in via `/setup` or by hand. Everything the agent should know about *you* goes there, not here.

@IDENTITY.md

## How to work here
- **First run (fresh clone):** if there's no `.venv/` yet, the workspace isn't bootstrapped — run `bash bootstrap.sh` first (sets up the recall engine, wires the hooks, seeds memory). Then, if `IDENTITY.md` still has `<…>` placeholders, run `/setup`. If the user just says "set this up," do both, in that order.
- **New idea:** `/kickoff` to shape it into a clear brief (the agent interviews you one question at a time, and reads any existing code the idea touches as ground truth). When it's shaped, `/new-project` graduates it into `~/Projects/<slug>/`.
- **Continuing project work:** do it *inside* the project workspace (`cd ~/Projects/<slug>`), which has its own context, recall, and tracking. Keep the Lab for ideation and cross-project thinking.
- **Permissions (Claude Code + Codex):** Lab Zero ships no permission overrides — both harnesses ask before acting by default, which is the safe choice. If you also run Codex and want to match a posture across them, see [PERMISSIONS.md](PERMISSIONS.md) (a by-hand orientation map; nothing is auto-translated).

## Working discipline + continuity
- On session start: read [Log/STATUS.md](Log/STATUS.md) + the latest file in `Sessions/`, then resume.
- Write progressive notes to `Sessions/YYYY-MM-DD_NNN_<slug>.md` as you work (numbering starts at 001).
- **One task per session**, then `/wrap`. Don't batch tasks or auto-start the next from a backlog.
- **Plan before building anything non-trivial** (`/lab-plan` — it runs a 3-reviewer adversarial pass). **Lean test-first** where behavior is checkable. Run **`/audit`** when tracking or specs may have drifted from reality.
- The Lab runs **light ceremony** (`Log/STATUS.md` + session notes); graduated projects get the fuller convention (STATUS / TASKS / PLAN / DECISIONS). The full set of work ceremonies in `.agents/skills/` is available in both (that directory is the always-current list).

## Recall
`bash scripts/recall.sh "<query>"` — semantic search over this workspace + the agent's seeded memory. `reindex` after material doc changes. `stats` to inspect the index. Config: [recall.config.json](recall.config.json).

## Projects
Graduated projects are listed in [Projects-REGISTRY.md](Projects-REGISTRY.md) — the map of what you've spun up, surfaced at session start.

## Keeping the machinery up to date
This Lab was cloned from `Lab-Zero`. To pull newer machinery (recall engine, template, skills) without touching your personal layer (identity, memories, projects), run `bash update.sh`. See [README.md](README.md).
