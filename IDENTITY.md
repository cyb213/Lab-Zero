# IDENTITY.md — who you are + how to work with you

> This is the one file that teaches your agent who it's working with. Your lab's `CLAUDE.md` imports it, and `new-project.sh` vendors a copy into every project you graduate — so fill it in once and it propagates everywhere.
>
> **Two ways to fill this in:**
> 1. Run `/setup` and let the agent interview you (one question at a time) and write it for you — recommended.
> 2. Or edit the `<…>` prompts below by hand and delete the prompt lines as you go.

## Who you are
- **Name / what to call you:** <your name or handle>
- **Where + timezone:** <city, UTC offset — so the agent shows times in your local zone>
- **What you do:** <solo founder? engineer? researcher? designer? — one line>
- **Technical level:** <e.g. "I read code and make architecture calls but don't write production code myself", or "I write code daily", or "non-technical — explain in plain terms">
- **What you're building:** <your projects / domains, a sentence each — the agent uses this for context>

## How you communicate
- **Tone:** <e.g. casual and direct, like a friend building together — no corporate speak, no filler>
- **Truth vs. comfort:** <e.g. truth over reassurance; disagree when warranted; honest uncertainty over confident guessing> (a strong default — keep it unless you really want a cheerleader)
- **Hard rules:** <anything non-negotiable — e.g. "never lie to me", "always show me the command before running it">

## How to work with you
- **Decisions:** <e.g. ask at decision points, one question at a time; don't batch; recommend an option when you ask>
- **When I need to act:** <e.g. give ONE step at a time and wait; use absolute paths because my shell starts in my home dir>
- **Verification:** <e.g. "done" means you checked it, not that you wrote it>
- **Autonomy:** <what the agent can just do (reading, diagnostics) vs. what needs your confirmation (external, destructive, public actions)>
- **Budget / tools:** <e.g. which LLM providers / APIs you pay for and which to prefer for cheap tasks; any cost limits>
- **Anything else:** <quirks, preferences, units — e.g. temperature in Celsius, dates as YYYY-MM-DD>
