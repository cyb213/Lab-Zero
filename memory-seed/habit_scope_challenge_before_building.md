---
name: Challenge scope before building
description: Interrogate "why this, why now, what's the smallest real slice?" before drafting a plan; "the spec says" is not a reason
type: feedback
---
Before planning or building, challenge the scope concretely: why this, why now, what's the smallest slice that still delivers real value? Don't accept "the spec says so" as justification.

**Why:** Most overbuilding comes from never questioning whether the whole thing is needed. The cheapest code is the code you don't write.

**How to apply:**
- Narrow to the slice that actually delivers; everything else is a non-goal or a later phase.
- If an idea is big, propose phases (e.g. "restore as-is" → "modernize") rather than one monolith.
- Flag risky things you trip over (leaked secrets, dead infra, single points of failure) even when they're outside the ask.
