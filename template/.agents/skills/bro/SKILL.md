---
name: bro
description: Re-explain your own previous answer in plain language, for when it didn't land. Use when the user types /bro, or says the last answer was too dense, too jargon-heavy, or asks for it simpler. Re-expresses what was already said; never answers something new.
---

<!--
  Derived from the MIT-licensed /bro skill by Hermes Agent + Luka.
  https://github.com/luchasarie/bro-skill  ·  Copyright (c) 2026 Hermes Agent + Luka.
  The text below was rewritten for Lab Zero; the idea, the contract, and the name are theirs.

  Permission is hereby granted, free of charge, to any person obtaining a copy of this
  software and associated documentation files (the "Software"), to deal in the Software
  without restriction, including without limitation the rights to use, copy, modify, merge,
  publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
  to whom the Software is furnished to do so, subject to the following conditions: the above
  copyright notice and this permission notice shall be included in all copies or substantial
  portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
  FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
  CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
  USE OR OTHER DEALINGS IN THE SOFTWARE.

  Rules 2 and 3 below intentionally restate the communication norm in the constitution. That
  is not drift — this skill fires at the moment of maximum pressure against exactness, so
  those two guards must be local. Do not "deduplicate" them.
-->

# /bro — say it again, simpler

The user asked for your last answer in plainer words. It did not land: too dense, too much jargon,
too formal, or just too long.

**Your job is to re-explain YOUR OWN most recent message.** That is the whole job.

## The contract

1. **Re-explain, don't re-answer.** Never answer a new question. Never add information that was not
   in the original. Never use a tool — everything you need is already on screen. If you find
   yourself reaching for a tool, you have misread the job.
2. **Facts are untouchable.** Every path, command, filename, flag, number, version, URL, and name
   survives **exactly** as written. You simplify the explanation around the facts, never the facts
   themselves. A "simpler" answer that rounds a version or shortens a path is a wrong answer.
3. **Every real caveat survives.** If the original carried uncertainty, a risk, or a "this only
   works when X", it stays. Dropping a caveat to sound cleaner is the one failure this skill must
   never produce.
4. **Simpler, not shorter.** Take the space real clarity needs. Cut preamble, hedging, and
   ceremony — never substance.
5. **Flatten the structure.** Drop headers. Turn tables into plain sentences. Keep a short list only
   if the original genuinely had parts.
6. **Answer in the language of the message you are re-explaining**, whatever language the request
   came in.
7. **Voice.** Default to casual and direct — "ok so basically…", "the point is…". A touch of
   personality is the point; don't turn it into a meme. If the reader declared a different register
   in their identity file, that wins.
8. **If you now think the original was wrong, say so instead.** Do not re-explain a mistake more
   clearly and more confidently — that launders it at the exact moment the reader is about to act.
   Name the part you doubt in a line or two and stop. Correcting yourself outranks staying in scope.
   You still don't reach for a tool: flag the doubt, don't go verify it.
9. **Nothing to simplify?** If you have no previous message here, say so plainly and stop. If your
   previous message was itself a `/bro` re-explanation, don't simplify it again — say it is already
   the plain version and ask which part is still unclear.
