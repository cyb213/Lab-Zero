---
name: audit
description: Drift audit for tracking files, specs, plans, or citations against live state. Produces one Reviews/ doc with mechanically-verified findings, two-pass (inventory then apply).
disable-model-invocation: true
---

# Drift Audit Protocol

You are running a drift audit. Output: ONE doc in `Reviews/` with mechanically-verified findings. Two passes: inventory first, fixes second.

## Arguments

`$ARGUMENTS` — required scope. One of:

- `tracking` → the tracking files (`Log/STATUS.md`, and `Log/TASKS.md` / `Log/PLAN.md` / `Log/DECISIONS.md` if used)
- `specs` → `Source/*.md` (INTENT/SPEC/USER-STORIES/…) and any `Spec/*.md`
- `plans` → `Log/plans/*.md` status fields vs reality
- `citations` → file:line citations in the last ~20 `Sessions/` files + last ~5 `Reviews/` files
- A literal file/directory path → audit only that

**If `$ARGUMENTS` is empty: refuse.** Tell the user to pick a scope. Do not default to "audit everything" — that's how audits balloon.

## Two-pass model

**Pass 1 (default):** read-only inventory. Produce the `Reviews/` doc. Do not edit any audited file. Tell the user the doc is ready, with the headline drift and the ranked short view (see scope discipline). Wait for their go-ahead.

**Pass 2 (when the user says "go fix"):** apply the fixes for the findings the user saw in the short view; ask before applying anything outside the short view. Pass 2 never acts on a lead — a lead becomes a finding only after a fresh Pass 1 verifies it. Mark findings ✅ FIXED inline in the audit doc. Update tracking files. Reindex if any indexed file changed.

Audit fixes ship clean — do not bundle them with unrelated work in the same commit.

## Severity rubric

- **HIGH** — claim that **misleads the user if read uncorrected**. Stale "deferred"/"not built" labels on shipped work. Cross-file disagreement. Phantom items (a named entity that no longer exists). Broken citations in load-bearing places (CLAUDE.md, Source/, plan files). Asymmetric cost: telling the user something is undone when it's shipped is the worst failure mode.
- **MED** — factually stale but won't mislead a careful reader. Overtaken-by-newer-work but not contradicted. Citation drift in non-load-bearing prose.
- **LOW** — cosmetic, format, cross-reference duplication, count-line freshness. Group a cluster (3+) as one finding. A lone LOW stays in the inventory; it usually drops from the short view.

## Methodology (per candidate finding)

For every finding, do at least one mechanical verification step:

1. **Read** the claim — quote exact text + `file:line` citation.
2. **Verify mechanically** with at least one of: read the target file; `grep` for the symbol; `ls`/`find` for the path; look up the decision ID; check `git log --oneline` for the SHA; check live state (file mtime, a running service, etc.).
3. **Cite the verification** — `file:line` for the source that proves the claim wrong (not just the claim source).
4. **Propose a concrete Pass 2 fix** — specific replacement text or action, not "needs updating."

If you cannot verify it mechanically in one of those steps, it is not a finding. Record it under `Unverified leads` with what you suspected and where you looked. No vibes, no "looks off," no "feels stale" as findings.

## Output shape

Write to `Reviews/YYYY-MM-DD_<scope>-drift-audit-pass1.md` (create `Reviews/` if absent). Use today's date.

```markdown
# <Scope> Drift Audit — Pass 1 (read-only inventory)

**Session:** N (YYYY-MM-DD)
**Scope:** <files audited, one line>
**Cross-checked against:** <sources used for verification>
**Trigger:** <what prompted this; the user quote if any>
**Methodology:** Pass 1 is read-only inventory; Pass 2 ships fixes after the user eyeballs.

---

## TL;DR

| Surface | Findings | Highest severity |
|---|---|---|
| <file> | N | HIGH/MED/LOW |

**Headline:** <1-2 sentence summary of the worst class of drift, or "clean — checked <files + checks run>" if N=0>

---

## <Surface 1> drift

### N1. <short title>  [SEVERITY]

[file:line](relative/path#Lline): `quoted text from the claim`

Reality:
- Bullet of mechanical verification with citation [other-file:line](path#L)

**Pass 2 fix:** specific replacement text or specific action.

## Unverified leads

- <what you suspected> — looked in: <files / commands>; not confirmed because <reason>.

## Not in the short view

- N7. <title> — <one-line reason: LOW, single occurrence / collapsed into N3 / …>
```

## Anti-patterns (must NOT produce)

- Findings without `file:line` on **both** sides — the claim AND the verification.
- Vibes findings ("looks stale," "seems off," "probably wrong").
- Re-flagging prior-audit findings unless you can show regression with a fresh citation.
- Prose-style or markdown-format nits.
- Opinions about past decisions. Audit facts, not judgment.
- Findings without a concrete Pass 2 fix.
- Same drift duplicated across surfaces as separate findings — collapse to one, note "also at X".

## Scope discipline (report all, filter later)

1. **Inventory everything.** Every verified finding goes in the doc, at every severity. Don't cap the count while you look — a cap quietly hides the tail.
2. **Then rank and filter** for the short view you give the user: highest severity first. In the doc's `Not in the short view` section, list every dropped item with a one-line reason.

- **If >12 HIGH findings:** the scope is probably too broad. Finish the inventory in the doc, show the top 8 in the short view, and propose a narrower next pass.
- **If 0 findings:** that's a valid result. Write a one-line "clean" entry and name what you checked (files and checks run). Do not manufacture noise.
- **Many findings in one file** (roughly 8+): the file probably needs a rewrite rather than a fix list — say so, alongside the full list.

## Pass 2 execution

When the user says "go fix":

1. Apply each fix as a targeted edit to the file. No drive-by changes to unrelated lines.
2. Flip each finding header to `### N1. <title>  ✅ FIXED  [SEVERITY]` with a one-line note of the actual edit.
3. Update tracking files (bump `> Updated:` with a session note; add a DECISIONS.md entry if a decision was made; update STATUS.md if framing changed).
4. Reindex recall after the doc is committed: `bash scripts/recall.sh reindex`.
5. Commit. The pre-commit drift hook gates the tracking-file rule if this is a session-end commit.

## When to invoke

Good triggers: the user says "audit X" / "check for drift in X"; pre-release sanity sweep before a demo or handoff; after a long stretch with no audit; after the user catches a single stale claim (likely a cluster — run the relevant scope).

Bad triggers: "just to be safe" with no specific suspicion; mid-session of unrelated work (audits should be their own session unless trivially small).
