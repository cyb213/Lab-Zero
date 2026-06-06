---
name: kickoff
description: Shape a raw idea into a clear, INTENT-ready brief by interviewing the user one question at a time — reading any existing code/systems the idea touches as ground truth before asking — so it's ready to graduate via /new-project. Use when the user has a new idea to think through ("let's brainstorm X", "kick off an idea", "help me shape X", "I have an idea for…"), or /kickoff.
---

# Kick off a new idea

Turn a raw idea into a shaped brief that `/new-project` can graduate. The point is to *think it through with the user* — not to rush to scaffolding. Interview, ground in reality, converge on the genome (one-liner / problem / who-for / success / non-goals / constraints / open questions).

This is the front half of **"interview now, codify after."** It pairs with [`/new-project`](../new-project/SKILL.md): kickoff shapes the idea → new-project stamps it + drops the brief into `Source/INTENT.md`.

## The method (how to run the interview)
Follow the user's working rules (`identity/IDENTITY.md`): **one question at a time, plain language, ask at genuine decision points, never batch.** Write progressive notes to the session note as you go.

1. **Start open.** Ask for the idea in their own words + what triggered it. Don't pitch a plan back. One question, then listen.
2. **Read the ground truth BEFORE interrogating.** The moment the idea touches anything that already exists — a repo, an API, a deployed system, a doc — go *read it* instead of asking the user to recall details they may not hold. Get access (e.g. a repo invite), clone read-only *outside* the workspace, map it. **The existing code is the spec.** Most follow-up questions should be answered by what you read, not by the user. But read only **enough to write a credible INTENT** — what it is, the shape of the contract, the load-bearing facts — *not* an exhaustive audit. Full endpoint maps, data verification, and deploy planning are *project* work (see "Where kickoff ends").
3. **Reflect back, let them correct.** Play back what you understood as tight structured bullets and surface the load-bearing assumption ("so the contract is frozen — yes?"). Let them fix the framing before you go deeper.
4. **Drive to the genome, one decision at a time.** Walk the unknowns in dependency order — scope first, then the load-bearing facts (is the data alive? does the dependency exist? who controls X? what's the smallest real first slice?). Surface findings as you go; recommend, don't decide for them.
5. **Verify empirically, don't assume.** If you can check a claim — connect read-only, ping an endpoint, grep, resolve DNS — check it. "Verify before claiming" applies to discovery, not just delivery.
6. **Converge.** When you can fill these cleanly, the idea is shaped:
   - **One-liner** — what it is, for whom.
   - **Problem** — what's broken / missing today.
   - **Who it's for** — the user + the target audience.
   - **Success** — concrete, checkable "done."
   - **Non-goals** — the scope fence.
   - **Constraints / why-now** — host / stack / budget / deadlines / privacy + timing.
   - **Open questions** — unknowns to resolve, and *who* unblocks each.

## Scope discipline
- Challenge scope concretely ("why this, why now, what's the smallest slice that's still real?") — don't accept "the spec says." Narrow to the slice that actually delivers; the rest is a non-goal or a later phase.
- If the idea is big, propose **phases** (e.g. "restore as-is" → "modernize") rather than one monolith.
- Flag anything risky you trip over (leaked secrets, dead infra, single points of failure) even if it's outside the ask.

## Where kickoff ends — graduate early, don't over-run
Kickoff is finished the moment the idea is shaped enough to name a **slug + one-line purpose + a credible INTENT**. At that point: **graduate, then stop.** Deep recon, planning, and building happen *inside* `~/Projects/<slug>` — that workspace is self-sufficient (its own `CLAUDE.md` context, `/wrap` `/plan` `/audit`, drift-gate, recall, seeded memory). Doing the project's work from the lab front-loads it into the wrong workspace and bloats the lab session. **Graduate early; hand off; let the user continue *in the project*.**

## Output + handoff
- Capture progressively in `Sessions/YYYY-MM-DD_NNN_<slug>.md` (the lab's record). The brief's sections map 1:1 to `Source/INTENT.md` (+ contract/constraints → `SPEC.md`).
- When it's shaped enough to name a **slug + one-line purpose** and the INTENT is clear, **offer to graduate** with `/new-project` — don't auto-run it (graduating creates a repo + a memory namespace; confirm the exact command first). After graduating, **the work moves to the project** — don't keep recon-ing or building in the lab.
- **Not every idea graduates.** If it's not ready, or not worth building, say so and stop at the brief — that's a valid outcome.

## Notes
- This skill *shapes* — a read / think / converge activity. It does **not** build or scaffold; graduation + building come after.
- The discipline that makes it work: reading the real systems an idea touches up front — rather than quizzing the user — is what makes the genome accurate.
