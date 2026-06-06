---
name: Commit every session with changes
description: Commit (and push if there's a remote) at the end of every session that changed anything
type: feedback
---
End every session that touched files with a commit — and a push if a remote is configured. Don't leave work uncommitted across sessions.

**Why:** Uncommitted work is invisible to recall, unrecoverable if the machine dies, and a source of "wait, did that get saved?" confusion next session.

**How to apply:**
- Use a clear message: what shipped + any decision reference.
- Run a quick secret-scan over the staged diff before pushing (tokens, keys, passwords).
- If on the default branch and the change is substantial, branch first.
