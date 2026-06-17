# Lab Zero

**A clone-and-go workspace that gives your AI coding agent a memory — and a repeatable way to turn ideas into real projects.**

Lab Zero is a ready-made setup for **Claude Code** (and Codex) that remembers your context across sessions, comes with good working habits built in, and turns each idea you're serious about into its own self-contained project — in one command. You bring the ideas; it keeps the work organized and the agent grounded. Whether you write code every day or don't write it at all, the way in is the same.

*Already technical and want the mechanics? Jump to [For technical readers](#for-technical-readers).*

---

## The problem it removes

Working with an AI coding agent on anything real, you keep hitting the same walls:

- **It forgets.** New session, blank slate — you re-explain what you're building and why, all over again.
- **It drifts and guesses.** Without your past decisions in front of it, it confidently fills the gaps with made-up assumptions.
- **The work sprawls.** Notes, half-ideas, and real projects pile up in one place with no structure.
- **Every new project is a fresh setup.** You re-assemble the same memory, habits, and guardrails each time.

Lab Zero is the rig that removes all four: the agent picks up where you left off, stays grounded in what you actually decided, and every serious idea gets a clean home of its own.

---

## Why Lab Zero (and not just stock Claude Code, or rolling your own)

Stock Claude Code already has memory — `CLAUDE.md`, the `/memory` command, a file you write and curate. Lab Zero doesn't replace that; it's the **whole rig pre-assembled** on top of it, so you don't have to build it yourself.

| | Stock Claude Code | Roll your own | **Lab Zero** |
|---|---|---|---|
| **Memory** | `CLAUDE.md` + `/memory` — a file you write and curate | whatever you wire up | **smart (semantic) search** over your docs *and* a built-in memory, used automatically |
| **Work habits** | you set them up yourself | you author them | **built-in** good habits + guided routines for planning, reviewing, and wrapping up work |
| **Idea → project** | manual: new folder, re-setup each time | manual | **`/kickoff` → `/new-project`** — one command sets up a complete, ready-to-go project |
| **Across agents** | Claude Code | DIY per agent | **Claude Code + Codex** on one workspace \* |
| **Getting started** | per-project setup | hours of assembly | **clone-and-go**, plus `update.sh` to stay current |

\* Claude Code works the moment you clone; Codex is also supported, with one extra one-time trust step (details below).

**It's opinionated** — it bakes in one way of working: think in a *Lab*, *graduate* ideas into their own projects, plan before you build. If that fits how you work, it saves you assembling the setup yourself. If you'd rather start from a blank slate, stock Claude Code is lighter — and that's a perfectly good choice.

---

## What you get

- **Your agent stops forgetting.** Semantic recall searches your docs and its own memory before it answers — so you're not re-explaining context every session, and it's far less likely to make things up. *(First run downloads a ~100MB model; after that recall runs locally, no API key.)*
- **Good working habits, built in.** A seeded set of work-habit lessons (truth over reassurance, verify before calling something "done," plan before building) plus the ceremonies — `/lab-plan`, `/audit`, `/wrap` — come pre-wired.
- **Ideas become projects in one command.** `/kickoff` shapes a raw idea into a clear brief; `/new-project` graduates it into its own self-contained workspace — no re-assembling the rig each time.
- **Use it with Claude Code or Codex.** Claude Code works the moment you clone. Codex is also supported (one extra one-time trust step) — same workspace, your choice of agent.
- **Clone-and-go, and it stays current.** No assembling pieces; `update.sh` pulls engine improvements without touching your identity, memories, or projects.
- **A safety net for sensitive files — not a hard lock.** A best-effort hook warns the agent off editing files like `.env` with its normal editing tools; it catches the common slip, but a determined agent can still route around it through the shell. More below.

---

## Quick start

**You'll need:** a coding agent (**[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** is the default; Codex also works), plus **Git** and **Python 3.9+** on your machine. The first run downloads a small embedding model (~100MB) so recall can work; after that it runs locally with no API key.

*New to developer tools?* Honest heads-up: this isn't a one-click consumer app — it needs a coding agent, Git, and Python set up first, which takes some initial legwork. If that's unfamiliar, start by installing **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** (follow its official guide); once you have it, the *"let your agent set it up"* path below lets the agent itself help you through the remaining steps.

There are two ways in — easiest first.

### Easiest: let your agent set it up for you

You don't have to be comfortable on the command line. Open your coding agent, point it at this repo, and ask it to do the work — for example:

> "Clone `https://github.com/cyb213/Lab-Zero` and help me set it up — walk me through what it does as you go."

The agent clones the repo, runs the setup, and explains each step as it goes. (You still need the coding agent itself installed first — the agent just runs the same steps below, narrated, for you. It isn't magic, but it's the lowest-effort path.)

### Or do it yourself (3 steps)

**1. Clone it** (clone, don't download a zip — the git history powers updates):

```bash
git clone https://github.com/cyb213/Lab-Zero.git ~/lab
cd ~/lab
```

You can put it anywhere; `~/lab` is just an example.

**2. Bootstrap** (creates the Python venv, installs the engine, wires the hooks, seeds memory, builds the index):

```bash
bash bootstrap.sh                        # Claude Code (default)
# or, to also wire OpenAI Codex on the same workspace:
bash bootstrap.sh --harness claude,codex
```

Safe to re-run anytime — if you move the folder, or to add a harness later.

**3. Personalize.** Open the folder in Claude Code and run:

```
/setup
```

The agent interviews you (one question at a time) and writes your `IDENTITY.md` — who you are and how you like to work. Every session, and every project you graduate, reads this. (Prefer to type it yourself? Just edit `IDENTITY.md` by hand.)

That's it. You have a working Lab.

---

## What actually happens

Say you've got an idea — a small app that helps you plan a week of meals, say. Here's the shape of it end to end:

1. You open your **Lab** (your home base for thinking) and type **`/kickoff`**. The agent interviews you one question at a time — what's the core idea, who's it for, what does "done" look like — and reads any notes or code the idea touches, so it's grounded in reality, not guesses. It converges on a clear brief.
2. When the idea's shaped, you type **`/new-project`**. It **graduates** the idea: stamps a fresh workspace at `~/Projects/<slug>/` — its own git repo, its own memory, the full rig — and adds it to your project map.
3. You `cd` into the project and build. Three sessions later, the agent still knows *why* you chose the approach you did, because it's all in that project's recall. Nothing you decided got lost between sessions.

Not every idea has to graduate — some are better left as notes in the Lab. That's a valid outcome too.

---

<a name="for-technical-readers"></a>

# For technical readers

Everything above, with the mechanics underneath it.

## Requirements

- **Git** and **Python 3.9+** (`git --version`, `python3 --version`).
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** — the agent that reads `CLAUDE.md`, runs the skills, and fires the recall hooks. (See "Working across agents" below for Codex.)
- Internet on first run (the recall engine downloads a small embedding model, ~100MB, once).
- No paid API keys are required for the core experience. (Optional provider keys go in `.env` if you want the agent to use them for your own tasks.)

## Working across agents (Claude Code + Codex)

Lab Zero's skills and memory are designed to be **portable across coding agents**. The ceremonies live in the cross-agent `.agents/skills/` standard (plain `SKILL.md` files that Claude Code, Codex, and others read), and the recall **engine** is a plain Python CLI (`bash scripts/recall.sh …`) that runs under any agent.

- **Claude Code** is fully wired out of the box: the clone ships committed `.claude/` wiring, so the skills *and* the automatic recall + file-protection hooks work the moment you open it.
- **Codex** is supported too — run `bash bootstrap.sh --harness claude,codex` and it *also* wires Codex on the same workspace. Both harnesses run on one workspace at once. There's **one extra one-time step** on Codex (it ignores a project's hooks until you trust them) — details below.

<details>
<summary><strong>Codex — the full details (trust step, recall, file-protection)</strong></summary>

Working on Codex: your **identity** (resolved into a personal, git-ignored `AGENTS.override.md`), the **ceremonies** (Codex auto-discovers `.agents/skills/`), and **recall** — the session-start/prompt hooks inject the same context they do on Claude (they emit the `hookSpecificOutput.additionalContext` JSON envelope both harnesses accept; verified injecting live on Codex 0.137.0). Both harnesses run on one workspace at once.

**One-time trust step:** Codex ignores a project's hooks until you trust them — in an interactive Codex session here, approve the project's hooks (the `/hooks` review); they fire from then on. *Headless/CI note:* the hook-trust bypass flag is version-dependent and may not exist in your Codex (e.g. 0.130.0 has no such flag), so the one-time interactive approval is the reliable path.

**File-protection on Codex:** `bootstrap.sh` now also wires the file-protection hook for Codex — the shared `protect-files.sh` understands Codex's `apply_patch` edits and blocks writes to `.env` / `recall.config.json` (live-verified on Codex 0.137.0: an `apply_patch` edit to `.env` was blocked). It's **best-effort**: like recall, the new hook is OFF until you approve it in the `/hooks` review, and it can't protect you on older Codex builds that don't show `apply_patch` edits to hooks. **It guards the structured edit tools, not raw shell** — an agent denied an `apply_patch` can still write via a shell command (`echo >> .env`), which is gated by command approval, not this hook. (That's true on Claude too — its protect-files matches `Edit/Write`, not `Bash`.) *(Re-trust caveat: Codex keys hook trust on the hook's **command**, not the script's contents — so a future `update.sh` that changes `protect-files.sh`'s **content** won't force a fresh `/hooks` approval; changing its command would.)*

</details>

## The daily flow

```
  idea  ──▶  /kickoff  ──▶  /new-project  ──▶  work inside ~/Projects/<slug>
        shape it into        graduate it into       (its own full rig:
        a clear brief        its own workspace        recall, tracking, skills)
```

- **Have an idea?** Say `/kickoff`. The agent interviews you to shape it — and reads any code or systems the idea touches first, so the plan is grounded in reality, not guesses. It converges on a one-liner, the problem, who it's for, what "done" looks like, and the open questions.
- **Ready to build?** Say `/new-project`. It stamps a fresh workspace at `~/Projects/<slug>/` — its own git repo, its own memory, the full template — and registers it in your `Projects-REGISTRY.md`. To stand the new project up for **Codex** too, stamp it with `--harness`: `bash new-project.sh <slug> --harness claude,codex`. It gets the same git-ignored Codex layer the Lab does (recall + identity + ceremonies + apply_patch file-protection), after the same one-time `/hooks` trust. (Each project also ships its own `bootstrap.sh`, so you can add/drop a harness later or stand the project up after cloning it to another machine — `bash bootstrap.sh --harness claude,codex`.)
- **Then move into the project.** `cd ~/Projects/<slug>` and work there. Each project is self-sufficient: it has its own `CLAUDE.md`, recall, and the `/lab-plan`, `/audit`, `/wrap` skills. Keep the Lab for thinking; do the building in the project.

Not every idea has to graduate — some are better left as notes in the Lab. That's a valid outcome.

## Recall (semantic memory)

From any workspace (the Lab or a project):

```bash
bash scripts/recall.sh "how did I decide to handle auth?"   # search
bash scripts/recall.sh reindex                              # after big doc changes
bash scripts/recall.sh stats                                # inspect the index
```

Recall searches your docs **and** the agent's memory files. The agent is prompted to use it before answering from assumption — that's what keeps it from drifting or making things up.

## How it's organized

```
your-lab/
├── AGENTS.md              ← the Lab's instructions, canonical (every agent reads this)
├── CLAUDE.md              ← Claude Code entry point (imports AGENTS.md)
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
├── .agents/
│   └── skills/            ← the ceremonies, canonical: /setup /kickoff /new-project /lab-plan /audit /wrap
└── .claude/
    ├── settings.json      ← hook wiring (bootstrap fills in your path)
    ├── hooks/             ← the file-protection hook
    └── skills/            ← committed Claude Code copies of the skills (clone-and-go)
```

**Two layers, on purpose:**
- **Your personal layer** — `AGENTS.md`, `CLAUDE.md`, `IDENTITY.md`, `recall.config.json`, your memories, your projects, your `.env`. This is yours; nothing here is overwritten by updates.
- **The machinery** — the recall engine, the template, the skills, the hooks. Shared, generic, and updatable.

## Staying up to date

Lab Zero ships tagged releases. Your clone knows what version it's on (a `VERSION` file) and, every so often (about every 12 sessions), the agent is **reminded to check** for a newer one. That reminder is a local nudge — it does no network call, so it's instant and works offline; it just prompts the agent to run the check when you next have a moment.

**See what's new (read-only, needs network):**

```bash
bash update.sh --check     # your version vs the latest release + the changelog
```

`--check` changes nothing — it just reaches upstream, tells you the version you're on, the latest published version, and what's new (from [CHANGELOG.md](CHANGELOG.md)).

**Update (when you want it):**

```bash
bash update.sh             # pull the latest published release's machinery
git diff --staged          # review what changed
git commit -m "update lab machinery"
```

`update.sh` lands the **latest published release** (the newest version tag), not a mid-flight `main` — so you update to a version we actually announced. Want a specific one (or the bleeding edge)? `bash update.sh --ref v1.1.0` pins a tag; `--ref main` pulls the branch HEAD.

It only refreshes the machinery paths. Your personal layer — including the constitution files you may have customized (`AGENTS.md`, `CLAUDE.md`) and `recall.config.json` — is never auto-overwritten; `update.sh` prints a one-liner to diff those against upstream by hand if you want engine-side wording changes.

## Troubleshooting

<details>
<summary>Common issues</summary>

- **`reindex failed` / no recall results** — make sure `bash bootstrap.sh` finished installing deps; re-run `bash scripts/recall.sh reindex --force`. First run needs internet to fetch the embedding model.
- **Hooks not firing (Claude Code)** — re-run `bash bootstrap.sh` (it re-wires `.claude/settings.json` to the current path). If you moved the folder, this is required.
- **Recall not injecting on Codex** — Codex skips a project's hooks until they're trusted, *silently*. Approve them in an interactive Codex session (the `/hooks` review) and recall injects from then on (the hooks emit the JSON envelope Codex needs — verified live on 0.137.0). There's no reliable headless bypass in current Codex (0.130.0 has no `--dangerously-bypass-hook-trust` flag), so the one-time interactive approval is the path. Until you've trusted them, run recall by hand: `bash scripts/recall.sh "<query>"`. (Identity + ceremonies work on Codex without any trust step.)
- **A commit is blocked** — the drift-gate wants your tracking files (e.g. `Log/STATUS.md`) updated for the session. Update them, or commit with `--no-verify` if you have a real reason.
- **Python venv issues** — delete `.venv/` and re-run `bash bootstrap.sh`.

</details>

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, make it yours.
</content>
