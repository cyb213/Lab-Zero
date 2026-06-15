---
name: lab-plan
description: Run a structured planning session — interview the sources of truth, draft, adversarial review (3 reviewers), approve, update docs. Use when building a new feature or phase that touches more than ~2 files.
---

# Planning Session Protocol

You are running a structured planning session. Follow every step in order. Do not skip steps. Do not combine steps.

## Arguments

`$ARGUMENTS` — short name for the plan (e.g. "browser-automation", "auth-rework").

## Pre-flight

1. Read `Log/STATUS.md` — current project state.
2. Read `Log/DECISIONS.md` (if it exists) — what's already decided.
3. Read the most recent file in `Sessions/` — pick up context.
4. Read the relevant `Source/` genome docs (INTENT / SPEC / USER-STORIES) for the area this plan touches.

## Step 1: Create the plan file

Create `Log/plans/YYYY-MM-DD_<short-name>.md` (copy `Log/plans/TEMPLATE.md` if present) using today's date and the argument. Set status to `draft`.

## Step 2: Sources of Truth (SoT) interview

This is an **active interview driven by you**, not a passive file review. For each source of truth relevant to this plan:

1. Read the source file.
2. Create an **annotation file** at `Log/plans/<plan-name>-sot-notes.md` with your findings and open questions.
3. Present findings to the user with specific questions — do NOT ask verbally without the annotation file.
4. Record the user's answers in the annotation file.

Sources to check (pick the relevant ones):
- `Source/INTENT.md` / `Source/SPEC.md` — what the project intends + specifies for this area.
- Existing implementation — what's already built (grep/glob the codebase).
- `CLAUDE.md` — constraints and protocols.
- `Log/DECISIONS.md` — prior decisions that constrain this plan.

## Step 3: Draft the plan

Fill in the plan file with:
- **Problem statement** — what this solves, why now.
- **Design** — architecture, tradeoffs, why this approach wins.
- **Tasks** — numbered task table with estimates and dependencies.
- **Risks** — what could go wrong, rollback plan.
- **Verification** — specific, checkable acceptance criteria.

Set status to `review`. Tell the user the plan is ready.

## Step 4: Adversarial review

After the user approves the draft for review (or immediately if they say "go"):

Spawn **3 reviewer agents in parallel** (Agent tool), each with a focused, adversarial domain. Tell each to be skeptical and concrete, and to ground every finding in the actual files (read them) — not vibes:

1. **Feasibility** — can each task be built with the available tools, patterns, and dependencies? Are the estimates realistic?
2. **Risk** — what breaks? Failure modes, data loss, security gaps, regression potential, isolation violations.
3. **Scope** — does the plan match the problem statement? Flag overengineering, scope creep, and under-scoping.

Each dispatch prompt includes: the plan file path; the relevant `Source/` + `Log/STATUS.md` + `Log/DECISIONS.md` paths; any source files the plan proposes to change (so findings are grounded); and an instruction to return structured findings — area/task, issue, severity (critical/important/minor), suggested fix.

### Consolidation
After all three return:
1. Collect findings into one numbered list.
2. Categorize: critical (must fix) / important (should fix) / minor.
3. Apply critical + important fixes to the plan.
4. Present the consolidated findings and changes to the user.

## Step 5: Approval

Present the final plan to the user. Wait for explicit approval before proceeding.

## Step 6: Post-approval documentation

Once approved, **immediately** (in the same response):
1. Set plan status to `approved`.
2. Add a decision entry to `Log/DECISIONS.md` (if used) with the plan reference.
3. Update `Log/STATUS.md` with the new plan.
4. Update `Log/TASKS.md` / `Log/PLAN.md` if the plan creates new phases or tasks.
5. Update the session note in `Sessions/`.

Do not proceed to implementation in this session unless the user explicitly asks.
