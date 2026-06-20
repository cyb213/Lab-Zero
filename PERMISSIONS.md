# Permissions across harnesses (Claude Code + Codex)

> An orientation map for picking a matching "how much can the agent do on its own?" posture when you run Lab Zero on **both** Claude Code and Codex. It is **not** a substitute for each harness's own permission reference — when in doubt, follow the upstream docs linked at the bottom.

> **Last verified** against the Claude Code permission docs and the Codex CLI config docs (live-tested here on Codex 0.137.0) on **2026-06-20**. Both harnesses' permission settings are **version-sensitive** — Codex has renamed enums across releases, and Claude's `auto` mode is a research preview — so always check your installed version's own docs.

## Start here: doing nothing is the safe default

If you change nothing, **both harnesses ask you before they act** — that is the safe default, and **Lab Zero ships no permission overrides** for either one. The clone you got does not loosen anything.

Two things this page is *not*:

- **Nothing is auto-translated.** Lab Zero does **not** read one harness's permissions and generate the other's. There is no bridge, no sync, no generated config. You configure each harness yourself; this page only helps you choose comparable settings by hand.
- **This is an orientation map, not a reference.** It summarizes each model just enough to line them up. The exact knobs, edge cases, and newest options live in each harness's own docs.

## How Claude Code thinks about permissions

Claude Code uses a `permissions` block in `.claude/settings.json` with three rule lists — **`allow`**, **`ask`**, **`deny`** — plus a `defaultMode`.

- **Rules are fine-grained.** A rule is a whole tool (`Bash`) or a tool with a specifier: command globs for Bash (`Bash(npm run test:*)`), gitignore-style path globs for file tools (`Read(./src/**)`, `Read(.env)`), a domain for fetches (`WebFetch(domain:*.example.com)`), MCP tools (`mcp__server__tool`), or subagents (`Agent(Explore)`).
- **Precedence is `deny` > `ask` > `allow`** — the first match in that order wins. A `deny` rule always beats an `allow`.
- **Modes** set the behavior when no rule matches: `default` (prompt on first use of each tool), `plan` (read-only — read and inspect, no edits), `acceptEdits` (auto-accept edits in the working dir), `bypassPermissions` (skip prompts except forced `ask`/`deny`), `dontAsk` (auto-deny anything not pre-approved), and `auto` (auto-approve with background safety checks — **research preview, may change**).
- Claude Code **also** has a separate **sandboxing** feature (an OS-level filesystem/network boundary for Bash), which is complementary to — not the same as — `permissions`.

→ Full reference: the Claude Code [permissions](https://code.claude.com/docs/en/permissions) and [sandboxing](https://code.claude.com/docs/en/sandboxing) docs.

## How Codex thinks about permissions

Codex uses **two coarse, global settings** in `~/.codex/config.toml` (or a project `.codex/config.toml`):

- **`approval_policy`** — when Codex pauses to ask you. Documented values: **`untrusted`**, **`on-request`**, **`never`**.
- **`sandbox_mode`** — what the filesystem boundary allows. Documented values: **`read-only`**, **`workspace-write`**, **`danger-full-access`**.

These are global enums, **not** per-tool or per-pattern rules — Codex has no direct equivalent of Claude's "allow this command but deny that one." (Codex also has a granular-object form of `approval_policy` and a managed-org `requirements.toml`; for those, see the upstream docs — they aren't covered here.)

→ Full reference: the Codex [configuration reference](https://developers.openai.com/codex/config-reference) and [agent approvals & security](https://developers.openai.com/codex/agent-approvals-security) docs.

## Choosing an equivalent posture by hand

*Lab Zero sets none of these for you.* This table is a hand-picking aid only — you decide and configure each harness yourself, and the two are never kept in sync.

| If you want… | What *you* set in Claude Code | What *you* set in Codex |
|---|---|---|
| **Read-only / planning** — look, don't touch | `plan` mode (or `deny` the write tools) | `sandbox_mode = read-only` |
| **Ask before acting** *(the default — recommended)* | `default` mode, no extra rules | `approval_policy = on-request` + `sandbox_mode = workspace-write` |
| **Trust within the workspace** — auto-edit here, ask outside | `acceptEdits` mode + targeted `allow` rules | `sandbox_mode = workspace-write` + `approval_policy = on-request` |
| **Full autonomy** — no prompts at all | ⚠️ disarms the guardrails — see **Dangerous postures** below | ⚠️ disarms the guardrails — see **Dangerous postures** below |

The match is **approximate**. The same row means "comparable intent," not "identical behavior."

## What's lossy (both directions)

There is no faithful one-to-one mapping, because the two models have different shapes:

- **Claude → Codex loses detail.** Claude's per-command, per-path, and per-domain `allow`/`ask`/`deny` rules collapse when you move to Codex's two global enums. Codex can't express "allow `npm` but deny `git push`," or "deny reading `.env` specifically" — its `sandbox_mode` is a whole-workspace boundary, not a rule list.
- **Codex → Claude needs two features.** Codex's `sandbox_mode` is an OS-level filesystem boundary. The closest thing in Claude is a *combination*: `Read`/`Edit`/`Write` `deny` rules (the permission layer) **plus** the separate sandboxing feature (the OS-level layer). No single Claude knob equals one Codex enum.

So treat the table as a starting point and verify the actual behavior in each harness, rather than assuming the postures are interchangeable.

## Safe defaults, and the postures to avoid

**Lead with the safe choice: change nothing.** Both harnesses prompt before acting out of the box, which is the right floor for most work.

If you want to be explicit and *more* restrictive — e.g. for a planning-only session — the read-only posture is the safest thing to write down:

```json
// .claude/settings.json — read-only / planning
{ "permissions": { "defaultMode": "plan" } }
```

```toml
# .codex/config.toml — read-only
sandbox_mode = "read-only"
```

**Dangerous postures — do not paste these into a config you share.** Claude's `bypassPermissions` mode, and Codex's `approval_policy = never` combined with `sandbox_mode = danger-full-access`, both remove the prompts that keep an agent from doing something destructive. They are occasionally useful in a throwaway, fully-disposable environment — but a permissive setting belongs **only** in your own local, **git-ignored** config (Claude's `.claude/settings.local.json`, your personal `~/.codex/config.toml`), **never** in a `settings.json` or `.codex/config.toml` you commit or share. A committed permissive config silently disarms the guardrails for everyone who clones it. If you genuinely need one of these, read the warnings in each harness's own docs first (linked above) and set it yourself.

## Reference links

- Claude Code — [permissions](https://code.claude.com/docs/en/permissions) · [settings](https://code.claude.com/docs/en/settings) · [sandboxing](https://code.claude.com/docs/en/sandboxing)
- Codex — [configuration reference](https://developers.openai.com/codex/config-reference) · [agent approvals & security](https://developers.openai.com/codex/agent-approvals-security)
