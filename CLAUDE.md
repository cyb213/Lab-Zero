# CLAUDE.md — your Lab

> Your home base for thinking through ideas, analysis, and building your projects. Loaded into every session in this workspace. (This is the genericized "Lab Zero" architecture — clone it, make it yours.)

## What this is
The **Lab** is where you ideate and analyze, then **graduate** serious ideas into their own full-rig project workspaces under `~/Projects/<slug>/`. The Lab and each project are separate git repos with separate memory namespaces, so work in one never collides with another.

Capabilities available in every session here:
- **Recall** — semantic search over your docs + the agent's long-term memory.
- **Seeded memory** — a starter set of work-habit lessons the agent follows (extend it as you go).
- **Continuity** — STATUS + session notes so any session picks up cold.
- **Skills** — `/setup` (personalize), `/kickoff` (shape a raw idea), `/new-project` (graduate it).

## Who you're working with
Your identity + working style live in `@IDENTITY.md` (imported below). Fill it in via `/setup` or by hand. Everything the agent should know about *you* goes there, not here.

@IDENTITY.md

## How to work here
- **First run:** if `IDENTITY.md` still has `<…>` placeholders, run `/setup` before anything else.
- **New idea:** `/kickoff` to shape it into a clear brief (the agent interviews you one question at a time, and reads any existing code the idea touches as ground truth). When it's shaped, `/new-project` graduates it into `~/Projects/<slug>/`.
- **Continuing project work:** do it *inside* the project workspace (`cd ~/Projects/<slug>`), which has its own context, recall, and tracking. Keep the Lab for ideation and cross-project thinking.

## Continuity
- On session start: read [Log/STATUS.md](Log/STATUS.md) + the latest file in `Sessions/`, then resume.
- Write progressive notes to `Sessions/YYYY-MM-DD_NNN_<slug>.md` as you work (numbering starts at 001).
- The Lab runs **light ceremony**: `Log/STATUS.md` + session notes are the record. Graduated projects get the fuller convention (STATUS / TASKS / PLAN / DECISIONS).

## Recall
`bash scripts/recall.sh "<query>"` — semantic search over this workspace + the agent's seeded memory. `reindex` after material doc changes. `stats` to inspect the index. Config: [recall.config.json](recall.config.json).

## Projects
Graduated projects are listed in [Projects-REGISTRY.md](Projects-REGISTRY.md) — the map of what you've spun up, surfaced at session start.

## Keeping the machinery up to date
This Lab was cloned from `Lab-Zero`. To pull newer machinery (recall engine, template, skills) without touching your personal layer (identity, memories, projects), run `bash update.sh`. See [README.md](README.md).
