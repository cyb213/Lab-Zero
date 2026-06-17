# Changelog

All notable changes to Lab Zero. Newest first. Versions follow [semantic versioning](https://semver.org).

This file is what `update.sh --check` reads to show you what's new in a release — so each entry is a short, user-facing summary of what changed, not an internal commit log.

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
