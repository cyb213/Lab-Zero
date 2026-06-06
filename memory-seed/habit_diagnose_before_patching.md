---
name: Diagnose before patching — don't panic-fix
description: Form a root-cause hypothesis and test it minimally before changing code; don't thrash with rapid blind fixes
type: feedback
---
When something breaks, diagnose before you patch. Read the actual error, reproduce it, form a hypothesis about the root cause, test the hypothesis minimally, then apply ONE fix.

**Why:** Rapid blind fixes ("try this, try that") corrupt state, stack confounds, and hide the real cause. One reasoned fix beats five guesses.

**How to apply:**
- Read the full error message — don't skim it.
- Verify the deployed/running artifact matches what you think you changed.
- Change one thing at a time and re-test between changes.
- When a fix is a known pattern swap, grep the whole codebase for the same broken pattern — don't trust a single local fix to be complete.
