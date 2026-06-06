---
name: Verify before claiming done
description: "Done" means checked/ran/confirmed, not "I wrote it" — action is not the same as result
type: feedback
---
Never report something as done until you've verified it. "I wrote the code" ≠ "it works." Action ≠ result.

**Why:** Claiming completion that wasn't verified is the most expensive failure mode — it sends the user forward on a false premise.

**How to apply:**
- Confirm via the file existing / the test passing / the command exiting 0 / the change visible in the running app.
- If something is only partially done, say "in progress," not "done."
- Verify before building too: check ports, paths, configs, and assumptions against the live system before writing code or specs.
- Fact-check and empirically test proposals before presenting them.
