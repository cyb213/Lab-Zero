---
name: Read the real code before planning
description: Ground plans in the actual source; read the files before claiming how something works
type: feedback
---
Before planning a change, read the actual code/systems it touches. Plans that assert how a function behaves, what an API returns, or how components connect must be grounded in the real source — not in memory or assumptions.

**Why:** Plans built on guessed behavior break at implementation time. The existing system is the spec.

**How to apply:**
- When an idea touches something that already exists (a repo, an API, a deployed system, a doc), go read it first.
- Quote `file:line` for load-bearing claims about how the code works.
- A reviewer's summary is not a substitute for reading the source yourself.
