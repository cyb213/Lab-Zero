---
name: discover-skills
description: Periodic sweep of the workspace's curated narrative (session-note titles + git subjects + roadmap/DECISIONS) to surface repeated, formalizable work and propose turning it into skills or scripts. Writes one Reviews/ doc with a verdict per candidate. NOT correction triage (that's /review-corrections) and NOT drift detection (that's /audit) — this finds un-formalized recurring WORK.
disable-model-invocation: true
---

# Discover Skills

You are running a **pattern-discovery sweep**. Repeated, formalizable work hides in a
maturing workspace's history faster than anyone notices it — release flows, deploys,
triage routines, pre-flight checks. This ceremony reads the workspace's own **curated
narrative**, clusters the recurring work-shapes, subtracts what's already a skill or
script, and writes ONE read-only `Reviews/` doc proposing candidates — each with
recurrence evidence and a verdict. **It is propose-only**: it recommends, it never
scaffolds a skill or script itself (that goes through `/lab-plan`).

Run it when the session-start nudge says a sweep is due, or whenever the user asks.

## Not to be confused with

- **`/review-corrections`** triages *correction candidates* the recall Stop hook captured,
  into memory. Different input (a misses log), different output (a memory leaf).
- **`/audit`** finds *drift* — stale claims in tracking/specs vs. live state. Different
  input (existing docs), different output verb (fix the doc).
- **`/discover-skills`** (this) finds *un-formalized recurring work* in the history and
  proposes codifying it. Input = the curated narrative; output = a candidate list.

## The signal — curated narrative ONLY

Read these three portable surfaces (present in every clone — no harness-specific path):

1. **Session-note titles** — `Sessions/YYYY-MM-DD_NNN_<slug>.md` filenames (and their H1s).
   The slug is a human's one-line summary of what that session *did*; recurring slugs are
   the highest-signal layer.
2. **Git commit subjects** — `git log --oneline` (the first line of each commit).
3. **Roadmap + decisions** — the tracking files (`Log/STATUS.md`, `Log/DECISIONS.md`,
   any `Log/PLAN.md`/`Log/TASKS.md`) and any roadmap memory.

**Why only these:** they are a *curated* layer — already summarized by a human, low-noise,
and identical across clones and harnesses. Do **not** mine raw command transcripts in v1:
in a mature workspace that signal is dominated by inspection/commit noise and mostly
re-derives scripts that already exist. *(Future: transcript command-mining pays off more
in a young workspace, before scripts exist — not implemented here.)*

## Worthiness bar — a candidate MUST clear ALL of these

A work-shape is a candidate only if it passes every numbered gate. This bar is the
defence against false-positive noise — apply it strictly; a near-miss is a SKIP.

1. **Recurrence ≥ N.** The same work-shape appears in **≥ N = 3** distinct occurrences
   (separate sessions/commits, not 3 mentions in one note). Count and cite each.
2. **Stable shape.** The steps are roughly the same each time — a repeatable procedure,
   not three superficially-similar one-offs.
3. **Parameterizable.** It varies only in inputs (a version, a path, a target), not in
   its essential logic — so a skill/script could capture it.
4. **The manual version is slow or error-prone.** Doing it by hand wastes time or invites
   mistakes. If it's fast and safe by hand, it's not worth formalizing → SKIP.

If a candidate fails any gate, it does **not** go in the doc as a candidate (record it as
SKIP only if it's a near-miss a reader would otherwise wonder about — see scope discipline).

## Method — per candidate

For every candidate that clears the bar:

1. **Evidence** — cite the recurrence: the count + specific `file:line` / commit-subject /
   session-slug citations that prove it recurs (≥ N).
2. **Already-formalized?** Grep to subtract what exists: `*/skills/*` (every skill dir) and
   `scripts/` (every script). If the work-shape is already a skill or script, it is **not**
   a candidate — record it as SKIP ("already covered by `<name>`") so the result is honest,
   not silently dropped.
3. **Already-ruled?** Derive the candidate's **stable slug** (see below) and grep **every**
   prior `Reviews/*skill-discovery*.md` for that slug. If a prior sweep already ruled it
   (SKIP/SURFACE/DOCUMENT, or it's since been built), do **not** re-propose it.
4. **Verdict** — assign exactly one from the ladder below, with its terminal action.

## Verdict ladder

Each candidate gets exactly one verdict. The verdict is a **recommendation**, never an
auto-build:

- **CODIFY-AS-SKILL** — judgment-laden, multi-step, benefits from an adversarial design
  pass. Terminal action: *"run `/lab-plan <slug>`"* — the proposed skill gets its own
  3-reviewer plan before any build. **Do not write the skill here.**
- **CODIFY-AS-SCRIPT** — mechanical, deterministic, no judgment. Terminal action:
  *"write `scripts/<slug>.sh`"* (human-initiated). **Do not write the script here.**
- **DOCUMENT** — worth capturing as a runbook/checklist, not worth executable machinery.
  Terminal action: *"add a runbook note"*.
- **SKIP** — a near-miss, or already covered by an existing skill/script, or already ruled
  by a prior sweep. Recording the SKIP *is* the discipline — it keeps the next sweep from
  re-surfacing it and proves the bar was applied.
- **SURFACE** — genuinely ambiguous, or a call the user owns (worth formalizing? which
  shape?). List it for the user; do not pick for them.

When torn between CODIFY and SKIP, prefer **SURFACE** — let the user rule. Never inflate a
weak pattern into a build recommendation.

## Stable candidate slug (dedup key)

Each candidate carries a fixed **kebab-case slug** derived from its canonical verb+object
(e.g. a deploy-to-the-consumer flow → `deploy-to-consumer`; a pre-flight sanity routine →
`preflight-sanity-check`). The slug is **stable across sweeps** — derive it the same way
every time so the same work-shape yields the same slug. The doc records it as
`slug: <slug>` on each finding, which makes the output **greppable**: that is exactly how
step 3 of the method subtracts already-ruled candidates. A previously-SKIP'd or
-SURFACE'd slug must not reappear as a fresh candidate in a later sweep.

## Output shape

Write to `Reviews/YYYY-MM-DD_skill-discovery.md` (create `Reviews/` if absent). Use today's
date. This skeleton is the `/audit` shape — same mechanical-evidence + scope discipline:

```markdown
# Skill-Discovery Sweep — <YYYY-MM-DD>

**Session:** N (YYYY-MM-DD)
**Corpus:** <count of session notes / commits scanned, one line>
**Already-formalized (subtracted):** <skills + scripts grepped, so the reader sees the baseline>
**Prior sweeps read (dedup):** <list of Reviews/*skill-discovery* docs whose verdicts were honored, or "none">
**Method:** curated narrative (session titles + git subjects + roadmap/DECISIONS); propose-only.

---

## TL;DR

| Candidate | slug | Recurrence | Verdict |
|---|---|---|---|
| <short name> | `<slug>` | ×N | CODIFY-AS-SKILL / -SCRIPT / DOCUMENT / SKIP / SURFACE |

**Headline:** <1-2 sentences: the strongest candidate, or "no new candidates" if none>

---

## Candidates

### C1. <short title>  [VERDICT]

- **slug:** `<slug>`
- **Recurrence (≥ N):** ×N — <citations: session slugs / commit subjects / file:line>
- **Shape:** <the repeatable steps, one line>
- **Already-formalized?** <grep result: "no script/skill covers it" or "covered by X → SKIP">
- **Why this verdict:** <one line>
- **Terminal action:** <run `/lab-plan <slug>` | write `scripts/<slug>.sh` | runbook | recorded>
```

## Two-pass model

**Pass 1 (default):** read-only. Produce the `Reviews/` doc. Tell the user the headline and
which candidate is strongest. Wait.

**Pass 2 (when the user picks a candidate):** you do **not** build it. You hand it to the
right next ceremony: for CODIFY-AS-SKILL, start `/lab-plan <slug>`; for CODIFY-AS-SCRIPT,
the user initiates writing `scripts/<slug>.sh`. This skill's job ends at the recommendation
— that keeps every new skill behind the `/lab-plan` adversarial gate and this ceremony's
runtime free of any build/release machinery.

## Anti-patterns (must NOT produce)

- A candidate without a recurrence count + citations (≥ N) — vibes are out of scope.
- A candidate that's already a skill/script, proposed as new (you skipped the grep).
- Re-proposing a slug a prior sweep already ruled (you skipped the dedup grep).
- The skill scaffolding a skill or script itself — v1 is propose-only.
- Mining command transcripts — out of scope for v1.
- Inflating count by listing the same session/commit twice.

## Scope discipline (low-noise enforcement)

- **0 candidates is a valid, good result.** Write a one-line "no new candidates this sweep"
  and stop. Do not manufacture noise to justify the run.
- **Per-pass cap ~6 candidates.** If you find more, present the strongest 6 and say a
  follow-up sweep is warranted. A flood of candidates means the bar wasn't applied.
- The false-positive tax is what kills a discovery sweep — bias toward SKIP/SURFACE.

## When to invoke

Good triggers: the session-start nudge says a sweep is due; the user says "discover
skills" / "what should we formalize?"; a stretch of sessions has gone by since the last
sweep. Bad triggers: a brand-new workspace with little history (the nudge's history-floor
gate already suppresses this); mid-session of unrelated work (a sweep is its own session).

## Worked example (illustrative)

Curated narrative over a workspace's history surfaces three recurring shapes:

1. Session titles `ship release vX` appear ×9; commits `release: vX` ×9. Grep: a
   `publish` skill already exists → **SKIP** (`slug: publish-release`, already covered).
2. Session titles mentioning a `deploy to <consumer>` step appear ×6, with a stable
   checklist (back up → rehearse on a clone → run the updater → verify → push → confirm).
   Grep: no script or skill covers the consumer-side deploy. Clears all four gates →
   **CODIFY-AS-SKILL**, `slug: deploy-to-consumer`, terminal action *"run `/lab-plan
   deploy-to-consumer`"*.
3. A "bump the changelog before release" step shows up ×4 but only ever inside the release
   flow above → **SKIP** (`slug: changelog-bump`, sub-step of an existing skill).

TL;DR: one CODIFY-AS-SKILL candidate (`deploy-to-consumer`), two SKIPs recorded. Report:
*"One worth formalizing — the consumer deploy flow runs ~6× by hand with no script.
Want me to `/lab-plan deploy-to-consumer`? The other two are already covered."*
