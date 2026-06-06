# Lab Zero

**A clone-and-go workspace for building your ideas with an AI coding agent.**

Lab Zero gives you the same architecture a working builder uses to take ideas from "shower thought" to shipped project: a home **Lab** where you think out loud, plus a one-command **graduation** that spins each serious idea into its own self-contained project workspace — each with semantic memory, continuity discipline, and guardrails baked in.

It's designed for people who are comfortable with AI coding tools (Claude Code, etc.) but don't necessarily write production code themselves. You bring the ideas; the rig keeps the work organized and the agent grounded.

---

## What you get

- **A Lab** — your home base for ideation and analysis (`CLAUDE.md` + `Log/` + `Sessions/`).
- **Recall** — semantic search over everything in your workspace plus the agent's long-term memory. Runs **fully locally** (no API key needed).
- **Seeded memory** — a starter set of solid work-habit lessons the agent follows (truth over reassurance, verify before "done," one question at a time, …). It grows as you work.
- **Skills** — `/setup` (personalize), `/kickoff` (shape a raw idea into a clear brief), `/new-project` (graduate it into its own workspace), plus the full work ceremonies `/plan` (structured planning + a 3-reviewer adversarial pass) · `/audit` (drift audit) · `/wrap` (clean session close) — available both in the Lab and in every graduated project.
- **A project template** — every graduated project is a clean, self-contained git repo with the full rig, a "genome" (INTENT/SPEC), a recall index, hooks, and a commit drift-gate.

---

## Requirements

- **Git** and **Python 3.9+** (`git --version`, `python3 --version`).
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** — the agent that reads `CLAUDE.md`, runs the skills, and fires the recall hooks. (See "A note on agents" below.)
- Internet on first run (the recall engine downloads a small embedding model, ~100MB, once).
- No paid API keys are required for the core experience. (Optional provider keys go in `.env` if you want the agent to use them for your own tasks.)

### A note on agents (Claude Code today)
Lab Zero is currently built **for Claude Code**: the skills are Claude Code `SKILL.md` files and the recall automation runs through Claude Code `settings.json` hooks. The recall **engine** is a plain Python CLI (`bash scripts/recall.sh …`) that works under any agent — so memory and search still function elsewhere (e.g. Codex) — but the skills and the automatic session-start/stop hooks won't load there. Making the rig **harness-agnostic** (skills + hooks portable across agents) is on the roadmap; for now, use Claude Code for the full experience.

---

## Setup (3 steps)

**1. Clone it** (cloning, not downloading a zip — the git history powers updates):

```bash
git clone https://github.com/cyb213/Lab-Zero.git ~/lab
cd ~/lab
```

You can put it anywhere; `~/lab` is just an example.

**2. Bootstrap** (creates the Python venv, installs the engine, wires the hooks, seeds memory, builds the index):

```bash
bash bootstrap.sh
```

Safe to re-run anytime (for example if you move the folder).

**3. Personalize.** Open the folder in Claude Code and run:

```
/setup
```

The agent interviews you (one question at a time) and writes your `IDENTITY.md` — who you are and how you like to work. Every session, and every project you graduate, reads this. (Prefer to type it yourself? Just edit `IDENTITY.md` by hand.)

That's it. You have a working Lab.

---

## The daily flow

```
  idea  ──▶  /kickoff  ──▶  /new-project  ──▶  work inside ~/Projects/<slug>
        shape it into        graduate it into       (its own full rig:
        a clear brief        its own workspace        recall, tracking, skills)
```

- **Have an idea?** Say `/kickoff`. The agent interviews you to shape it — and reads any code or systems the idea touches first, so the plan is grounded in reality, not guesses. It converges on a one-liner, the problem, who it's for, what "done" looks like, and the open questions.
- **Ready to build?** Say `/new-project`. It stamps a fresh workspace at `~/Projects/<slug>/` — its own git repo, its own memory, the full template — and registers it in your `Projects-REGISTRY.md`.
- **Then move into the project.** `cd ~/Projects/<slug>` and work there. Each project is self-sufficient: it has its own `CLAUDE.md`, recall, and the `/plan`, `/audit`, `/wrap` skills. Keep the Lab for thinking; do the building in the project.

Not every idea has to graduate — some are better left as notes in the Lab. That's a valid outcome.

---

## Recall (semantic memory)

From any workspace (the Lab or a project):

```bash
bash scripts/recall.sh "how did I decide to handle auth?"   # search
bash scripts/recall.sh reindex                              # after big doc changes
bash scripts/recall.sh stats                                # inspect the index
```

Recall searches your docs **and** the agent's memory files. The agent is prompted to use it before answering from assumption — that's what keeps it from drifting or making things up.

---

## How it's organized

```
your-lab/
├── CLAUDE.md              ← the Lab's instructions (loaded every session)
├── IDENTITY.md            ← who you are + how you work (you fill this in)
├── recall.config.json     ← what recall indexes here
├── Projects-REGISTRY.md   ← the map of projects you've graduated
├── Log/STATUS.md          ← current state of the Lab
├── Sessions/              ← one note per work session
├── new-project.sh         ← graduates an idea into ~/Projects/<slug>
├── bootstrap.sh           ← first-run setup
├── update.sh              ← pull machinery updates (see below)
├── memory-seed/           ← the starter work-habit memories
├── scripts/               ← the recall engine + hooks  (machinery)
├── template/              ← the project genome stamped by new-project.sh  (machinery)
├── tests/                 ← recall engine tests  (machinery)
└── .claude/
    ├── settings.json      ← hook wiring (bootstrap fills in your path)
    ├── hooks/             ← the file-protection hook
    └── skills/            ← /setup, /kickoff, /new-project
```

**Two layers, on purpose:**
- **Your personal layer** — `IDENTITY.md`, `CLAUDE.md`, `recall.config.json`, your memories, your projects, your `.env`. This is yours; nothing here is overwritten by updates.
- **The machinery** — the recall engine, the template, the skills, the hooks. Shared, generic, and updatable.

---

## Staying up to date

When the upstream `Lab-Zero` improves (better engine, new skills), pull just the machinery — your identity, memories, and projects are left untouched:

```bash
bash update.sh
git diff --staged          # review what changed
git commit -m "update lab machinery"
```

`update.sh` only refreshes the machinery paths from upstream. Your personal layer (and `CLAUDE.md` / `recall.config.json`, which you may have customized) is never auto-overwritten.

---

## Troubleshooting

- **`reindex failed` / no recall results** — make sure `bash bootstrap.sh` finished installing deps; re-run `bash scripts/recall.sh reindex --force`. First run needs internet to fetch the embedding model.
- **Hooks not firing** — re-run `bash bootstrap.sh` (it re-wires `.claude/settings.json` to the current path). If you moved the folder, this is required.
- **A commit is blocked** — the drift-gate wants your tracking files (e.g. `Log/STATUS.md`) updated for the session. Update them, or commit with `--no-verify` if you have a real reason.
- **Python venv issues** — delete `.venv/` and re-run `bash bootstrap.sh`.

---

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, make it yours.
