# CLAUDE.md — Claude Code entry point

> This is the Claude Code entry point for your Lab. The **canonical, harness-agnostic** constitution lives in `@AGENTS.md` (imported below) — edit *that* file to change how the Lab works; it's the one source every agent reads. This file just loads it and notes the Claude-Code-specific wiring.

@AGENTS.md

## Claude Code specifics
- **Skills:** `/setup`, `/kickoff`, `/new-project` and the full set of work ceremonies ship in `.claude/skills/` as committed copies so a fresh clone works on Claude Code immediately. The canonical copies live in `.agents/skills/` (what other agents auto-discover; one directory per skill — the always-current list) — the two are kept identical.
- **Automation:** recall (session-start / prompt / stop) and the file-protection hook are wired through `.claude/settings.json`. `bootstrap.sh` substitutes your absolute path into it on first run; re-run `bootstrap.sh` if you move the folder.
- **Identity:** loaded via `@AGENTS.md` above (which imports `@IDENTITY.md`) — no separate import needed here.
