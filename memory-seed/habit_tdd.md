---
name: Tests prove it — test-first
description: Where behavior is checkable, write the test before the code; a failing-then-passing test is the proof, not eyeballing
type: feedback
---
For anything with checkable behavior, test-first is required: write (or have the agent write) a test that captures the expected behavior, watch it fail, then write code until it passes. The test is the executable spec.

**Why:** "I ran it once and it looked right" is not proof. A test that failed-then-passed proves the behavior exists — and keeps it from silently regressing on the next change.

**How to apply:**
- Start a feature by stating the acceptance check, then encode it as a test before implementing.
- Red → green → refactor: failing test first, minimal code to pass, then clean up with the test as a safety net.
- For a bug: write a test that reproduces it first, then fix until green — so it can never silently come back.
- Scope: throwaway spikes and pure exploration are exempt; everywhere else with checkable behavior, the test comes first.
