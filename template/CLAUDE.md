# CLAUDE.md — Claude Code entry point for __PROJECT__

> This is the Claude Code entry point. The **canonical, harness-agnostic** constitution lives in `@AGENTS.md` (imported below) — edit *that* file to change how this project works; it's the one source every agent reads. This file just loads it and notes the Claude-Code-specific wiring.

@AGENTS.md

## Claude Code specifics
- **Skills:** the work ceremonies (`/lab-plan`, `/audit`, `/wrap`, `/review-corrections`, `/discover-skills`) ship in `.claude/skills/` as committed copies so a fresh clone works on Claude Code immediately. The canonical copies live in `.agents/skills/` (what other agents auto-discover) — the two are kept identical.
- **Automation:** recall (session-start / prompt / stop) and the file-protection hook are wired through `.claude/settings.json`; your absolute workspace path is substituted into it when the project is stamped.
- **Identity:** loaded via `@AGENTS.md` above (which imports `@identity/IDENTITY.md`) — no separate import needed here.
