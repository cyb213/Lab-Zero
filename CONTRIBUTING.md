# Contributing to Lab Zero

> Thanks for looking. This page sets honest expectations. The short version: **this repo is a build output**, so the usual fork-it-and-open-a-PR-here flow doesn't apply — there's a different, deliberate up-path. Here's how it actually works.

## This repo is a build output

`Lab-Zero` is the **published output of a private factory**. Each release is assembled by a build script and copied in wholesale — the repo is overwritten on every release, not hand-edited. So if you edit a file here and open a pull request against it, even a perfect change gets **clobbered by the next release**. That isn't a rejection of your work — it's that this isn't the source tree, so there's nothing here for a PR to stick to.

(Forking is still welcome — it's MIT, and the README invites it. Clone it, run it, make it yours. The build-output caveat is only about sending changes *back upstream through this repo*.)

## Bugs, ideas, questions → open an issue

If something's broken, confusing, or missing, **open an issue**. That's the right channel for everything that isn't a code change you've already made locally:

- Bug reports, feature ideas, and questions about how it works are all welcome as issues.
- There's no Discussions tab (it's turned off) — use issues for those too.
- No SLA: issues get read, but opening one isn't a promise of a fix, a merge, or a reply on any timeline. Saying so up front rather than implying otherwise.

## To propose an engine or machinery change → `contribute.sh`

If you've improved the **machinery** in your own cloned Lab — the recall engine, a skill, a script, the project template — and want to send it upstream, there's a shipped helper for exactly that. Run it inside your clone:

```sh
bash contribute.sh --help
```

It extracts a **machinery-only** diff of your local changes versus upstream, runs a fail-closed leak audit over it, and writes a reviewable patch plus a table showing where each change routes back in the factory. Read its `--help` and its printed output yourself — the script documents what it does and where each hunk goes; don't rely on a copy of that here.

### What never gets contributed

Your **personal layer** — your identity file, your memories, your projects, your session logs — and the **`memory-seed/`** directory are excluded *by construction*. The up-path only ever touches generic machinery; it won't pick up your personal data even if you point it that way.

### Two guarantees that are NOT the same thing

Don't conflate these — they protect different things, to different strengths:

- **The published release is personal-data-free by a hard guarantee.** It's built from an *allowlist*: only approved, generic files are ever copied into it. Anything not on the list simply never ships. That's what makes "zero personal data" hold on every release.
- **A contributor's outbound patch is only TRIPWIRE-screened.** The leak audit in `contribute.sh` catches the *obvious* slips — your name in a comment, an absolute home path, a token-shaped string. A clean audit is **not** proof your patch is free of personal data, and it says **nothing** about whether the change is wanted upstream. **You** must read every changed line before you send it. The audit stops the dumb mistakes; it doesn't replace your own review.

## License

Contributions are offered under the repo's license — see [LICENSE](LICENSE).
