---
name: setup
description: First-run personalization for a freshly cloned Lab — interview the user one question at a time and write their IDENTITY.md, so the agent knows who it's working with. Use on first run, when IDENTITY.md still has placeholders, or when the user says "/setup", "set up my lab", or "personalize this".
---

# Personalize this Lab (first-run setup)

The user just cloned this Lab and needs to make it theirs. Your job: interview them and write a complete `IDENTITY.md`. Dogfood the working style this whole system teaches — **one question at a time, plain language, no batching.**

## Before you start
- Read the current `IDENTITY.md` — it's the fill-in template, and its sections are exactly what you're filling.
- If it's already filled (no `<…>` placeholders left), tell the user it looks done and ask if they want to revise a specific section instead of redoing it.
- Briefly tell the user what's about to happen: "I'll ask you a handful of short questions, then write your IDENTITY.md. Ready?"

## The interview (one question at a time — wait for each answer)
Walk these in order. Ask ONE, wait, then the next. Keep each question short and jargon-free. If an answer is rich, reflect it back in a tight phrase and move on; if it's thin, ask one gentle follow-up.

1. **What should I call you?** (name or handle)
2. **Where are you + what timezone?** (so times show in your local zone)
3. **What do you do, and what are you building?** (role + the projects/domains you work on)
4. **How technical are you?** (do you write code, read it, or prefer plain-language explanations? — this changes how I explain things)
5. **How do you want me to talk to you?** (tone — casual/direct? formal? and: do you want hard truth even when it's unwelcome, or a gentler touch?)
6. **How should I handle decisions?** (ask you at every fork, or run with sensible defaults and only ask on big calls?)
7. **What needs your sign-off before I do it?** (e.g. anything that spends money, deploys, deletes, or is public)
8. **Any tools/budget I should know about?** (which AI/API providers you pay for and want used for cheap tasks; any cost limits)
9. **Any hard rules or quirks?** (non-negotiables, units like Celsius/Fahrenheit, date formats, pet peeves)

## Write IDENTITY.md
- Fill every section of `IDENTITY.md` with their answers, in their voice where possible. Remove all `<…>` prompt lines.
- Keep it tight and concrete — this file is read at the start of every session, so signal beats length.
- Don't invent preferences they didn't state; if a section has no input, write a sensible neutral default and note it's a default they can change.

## After writing
1. Show the user the finished `IDENTITY.md` and ask if anything's off (let them correct — one round).
2. Reindex so recall picks up the new identity: `bash scripts/recall.sh reindex --force`.
3. Point them at next steps: "You're set. Got an idea to work on? Say `/kickoff` and we'll shape it."

## Notes
- This writes the user's personal layer; it does not touch the machinery.
- If they'd rather fill it in by hand, that's fine — point them at `IDENTITY.md` and stop.
