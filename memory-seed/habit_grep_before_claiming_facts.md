---
name: Grep before claiming facts — don't guess
description: Never guess paths, URLs, ports, hostnames, or config values; search the workspace and memory first, then ask if absent
type: feedback
---
Don't guess concrete facts — paths, URLs, ports, hostnames, config keys, command flags. Search first (grep the workspace, run recall), and if it's genuinely not found, ask rather than invent.

**Why:** A confidently-stated wrong path or port sends the user down a dead end and is hard to catch because it *sounds* authoritative.

**How to apply:**
- Run `bash scripts/recall.sh "<query>"` and grep the source-of-truth files before stating a fact.
- If the fact isn't recorded anywhere, say so and ask — don't fill the gap with a plausible guess.
- Be resourceful first (read, grep, check), then ask if still stuck.
