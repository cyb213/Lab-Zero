# Permissions across harnesses (Claude Code + Codex)

> An orientation map for picking a matching "how much can the agent do on its own?" posture when you run Lab Zero on **both** Claude Code and Codex. It is **not** a substitute for each harness's own permission reference — when in doubt, follow the upstream docs linked at the bottom.

> **Last checked** on **2026-11-27** against the Claude Code permission-modes, permissions, sandboxing and settings docs, the Codex config, approvals & security and rules docs, and the installed CLIs (Claude Code 2.1.330, Codex 0.172.0). This page was checked against those sources, not live-tested. Both harnesses' permission settings are **version-sensitive** — Claude's starting mode changed in v2.1.283, and Codex has retired approval values across releases — so always check your installed version's own docs.

## Start here: what each harness does if you change nothing

**Lab Zero ships no permission overrides** for either harness. The clone you got doesn't change how either one behaves. Out of the box, the two behave differently:

- **Claude Code** v2.1.283 or later starts interactive terminal and VS Code sessions in **`auto` mode**: it runs without routine permission prompts, and a separate classifier reviews each action before it runs and blocks the ones it judges risky. Non-interactive runs (`claude -p`, the Agent SDK) start in Manual (config value `default`), which prompts. On earlier versions the starting mode depends on your version and plan. To work prompt-first, switch modes with Shift+Tab or set `permissions.defaultMode` — see the Claude docs below.
- **Codex** starts in its default preset (`sandbox_mode = workspace-write` + `approval_policy = on-request`): it reads, edits and runs commands inside the workspace without asking, and asks before editing outside the workspace or using the network.

Two things this page is *not*:

- **Nothing is auto-translated.** Lab Zero does **not** read one harness's permissions and generate the other's. There is no bridge, no sync, no generated config. You configure each harness yourself; this page only helps you choose comparable settings by hand.
- **This is an orientation map, not a reference.** It summarizes each model just enough to line them up. The exact knobs, edge cases, and newest options live in each harness's own docs.

## How Claude Code thinks about permissions

Claude Code uses a `permissions` block in `.claude/settings.json` with three rule lists — **`allow`**, **`ask`**, **`deny`** — plus a `defaultMode`.

- **Rules are fine-grained.** A rule is a whole tool (`Bash`) or a tool with a specifier: command patterns for Bash (`Bash(npm run *)`), gitignore-style path patterns for file tools (`Read(src/**)`, `Read(./.env)`), a domain for fetches (`WebFetch(domain:*.example.com)`), MCP tools (`mcp__puppeteer__puppeteer_navigate`), or subagents (`Agent(Explore)`).
- **Precedence is `deny` > `ask` > `allow`** — rules are evaluated deny, then ask, then allow, and the first match wins. A `deny` rule always beats an `allow`, and deny rules block in every mode.
- **Modes** set the behavior when no rule matches: Manual (config value `default`; `manual` is accepted as an alias) prompts before most edits, shell commands and network requests · `plan` reads and explores but doesn't edit your source files · `acceptEdits` auto-accepts file edits and common filesystem commands · `auto` runs without routine prompts while a background classifier checks actions (the interactive starting mode since v2.1.283) · `dontAsk` auto-denies every call that would otherwise prompt · `bypassPermissions` skips permission prompts, except for the actions no mode auto-approves.
- Claude Code **also** has a separate **sandboxing** feature (an OS-level boundary around the shell commands Claude runs), which is complementary to — not the same as — `permissions`.

→ Full reference: the Claude Code [permission modes](https://code.claude.com/docs/en/permission-modes), [permissions](https://code.claude.com/docs/en/permissions) and [sandboxing](https://code.claude.com/docs/en/sandboxing) docs.

## How Codex thinks about permissions

Codex uses **two coarse settings** in `~/.codex/config.toml` (or a project `.codex/config.toml`, which Codex loads **only when you trust the project**):

- **`approval_policy`** — when Codex pauses to ask you. Current values: **`on-request`** (for interactive runs) and **`never`** (for non-interactive runs), plus a granular object form that allows or auto-rejects specific prompt categories. `untrusted` is no longer supported as an approval value and `on-failure` is deprecated. The stricter behavior now comes from marking a project `trust_level = "untrusted"` in your user-level config.
- **`sandbox_mode`** — what the filesystem boundary allows. Values: **`read-only`**, **`workspace-write`**, **`danger-full-access`**.

Codex also has **command rules** (experimental): `.rules` files under a `rules/` folder next to a config layer (for example `~/.codex/rules/default.rules`), where each `prefix_rule` matches a command prefix and decides `allow`, `prompt` or `forbidden` for running it **outside the sandbox**. The most restrictive matching decision wins. (Codex also has beta permission profiles and a managed-org `requirements.toml`; for those, see the upstream docs — they aren't covered here.)

→ Full reference: the Codex [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference), [agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security) and [rules](https://learn.chatgpt.com/docs/agent-configuration/rules) docs.

## Choosing an equivalent posture by hand

*Lab Zero sets none of these for you.* This table is a hand-picking aid only — you decide and configure each harness yourself, and the two are never kept in sync.

| If you want… | What *you* set in Claude Code | What *you* set in Codex |
|---|---|---|
| **Read-only / planning** — look, don't touch | `plan` mode (or `deny` the write tools) | `sandbox_mode = read-only` |
| **Ask before acting** | Manual mode (`default`), no extra rules | `sandbox_mode = read-only` + `approval_policy = on-request` (actions outside the read-only sandbox can require approval) |
| **Trust within the workspace** — auto-edit here, ask outside | `acceptEdits` mode + targeted `allow` rules | `sandbox_mode = workspace-write` + `approval_policy = on-request` *(Codex's default preset)* |
| **Hands-off with a safety reviewer** | `auto` mode *(the interactive starting mode since v2.1.283)* | the same `workspace-write` + `on-request`, with Codex's Auto-review reviewing eligible approval requests instead of you |
| **Full autonomy** — no prompts at all | ⚠️ disarms the guardrails — see **Dangerous postures** below | ⚠️ disarms the guardrails — see **Dangerous postures** below |

The match is **approximate**. The same row means "comparable intent," not "identical behavior."

## What's lossy (both directions)

There is no faithful one-to-one mapping, because the two models have different shapes:

- **Claude → Codex loses detail.** Claude's per-command, per-path and per-domain `allow`/`ask`/`deny` rules don't map onto Codex's two settings. Codex's command rules cover only part of that: they match command prefixes for commands run outside the sandbox, while its `sandbox_mode` is a whole-workspace boundary. Claude's per-path and per-domain rules have no counterpart in Codex's rules.
- **Codex → Claude needs two features.** Codex's `sandbox_mode` is an OS-level filesystem boundary. The closest thing in Claude is a *combination*: `Read`/`Edit`/`Write` `deny` rules (the permission layer) **plus** the separate sandboxing feature (the OS-level layer). No single Claude knob equals one Codex value.

So treat the table as a starting point and verify the actual behavior in each harness, rather than assuming the postures are interchangeable.

## Safe defaults, and the postures to avoid

**Neither harness's out-of-the-box start is prompt-first everywhere** — see *Start here*. If you want to be explicit and *more* restrictive — e.g. for a planning-only session — the read-only posture is the safest thing to write down:

```json
// .claude/settings.json — read-only / planning
{ "permissions": { "defaultMode": "plan" } }
```

```toml
# .codex/config.toml — read-only (applies only once the project is trusted)
sandbox_mode = "read-only"
```

**Dangerous postures — do not paste these into a config you share.** Claude's `bypassPermissions` mode, and Codex's full-access posture (`approval_policy = never` with `sandbox_mode = danger-full-access`, or the `--dangerously-bypass-approvals-and-sandbox` flag, which Codex itself marks "not recommended"), remove the prompts that keep an agent from doing something destructive. They are occasionally useful in a throwaway, fully-disposable environment — but a permissive setting belongs **only** in your own local, **git-ignored** config (Claude's `.claude/settings.local.json`, your personal `~/.codex/config.toml`), **never** in a `settings.json` or `.codex/config.toml` you commit or share. A committed permissive config silently disarms the guardrails for everyone who clones it. The same caution applies to Codex's `--dangerously-bypass-hook-trust`, which runs a project's hooks without your approval: Codex says it's intended only for automation that already vets hook sources (see the README's Codex section). If you genuinely need one of these, read the warnings in each harness's own docs first (linked above) and set it yourself.

## Reference links

- Claude Code — [permission modes](https://code.claude.com/docs/en/permission-modes) · [permissions](https://code.claude.com/docs/en/permissions) · [settings](https://code.claude.com/docs/en/settings) · [sandboxing](https://code.claude.com/docs/en/sandboxing)
- Codex — [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) · [config basics](https://learn.chatgpt.com/docs/config-file/config-basic) · [agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security) · [rules](https://learn.chatgpt.com/docs/agent-configuration/rules)
