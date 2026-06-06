---
name: Wrapping a session is actions, not a summary
description: A session wrap is verified mechanical actions (commit pushed, tracking updated, recall reindexed) — writing a tidy summary is not a wrap
type: feedback
---
Closing a session is a sequence of verified actions: ground state against git, update the tracking files, scan for leaked secrets, commit (and push), reindex recall. Writing a neat "shipped X, next Y" paragraph is NOT a wrap.

**Why:** A tidy summary fires a false "done" signal while the real actions stay untouched. Do the actions, confirm each fired, then report what fired.

**How to apply:**
- Treat tracking files as hypotheses; git and the filesystem are ground truth.
- Verify each wrap action actually happened (committed, not just staged; pushed, not just committed).
- Don't invent next-session scope — document state (done / blocked / decisions-needed) and let the user choose the next move.
