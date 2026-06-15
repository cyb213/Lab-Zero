---
name: new-project
description: Graduate an idea from your lab into its own full-rig project workspace under ~/Projects/<slug> (stamped from the lab template — recall engine, hooks, git drift-gate, vendored identity, seeded memory, genome skeletons). Use when the user says "graduate X", "spin up a project for X", or "/new-project".
---

# Graduate a project from the lab

Stamps a self-contained workspace from your lab's `template/` via `new-project.sh`. Do NOT hand-create the structure — run the script; it's the maintained source.

## Step 0 — Gather the essentials (ask one at a time if missing)
- **slug** — lowercase, hyphenated (e.g. `my-app`). Becomes the dir + recall `source`.
- **display name** — human name (e.g. "My App").
- **one-line purpose** — what it is / why it exists (goes into the registry + CLAUDE.md + INTENT prompt).
- **full genome?** — default is INTENT + SPEC only; pass `--full` to also scaffold USER-STORIES / INCEPTION / ARCHITECTURE-OPEN-QUESTIONS (only when the project clearly warrants them).

## Step 1 — Confirm, then stamp
Show the user the exact command and confirm (it creates a new repo + a memory namespace — an external action). Run it from your lab's root:

```bash
bash new-project.sh <slug> --name "<Display Name>" --purpose "<one-liner>"   # add --full if agreed
```

The script: clean-copies the template; vendors the lab's identity file as `identity/IDENTITY.md`; substitutes placeholders; sets `source=<slug>`; creates `.venv` + installs `sqlite-vec`; seeds the portable memories into the project's CC namespace; `git init` + installs the drift-gate + initial commit; reindexes recall; registers the project in your lab's `Projects-REGISTRY.md`.

## Step 2 — Verify the stamp (don't assume)
```bash
DEST=~/Projects/<slug>
ls "$DEST"/{CLAUDE.md,recall.config.json,Source/INTENT.md,Source/SPEC.md}
"$DEST"/.venv/bin/python "$DEST"/tests/test_recall.py   # expect 10/10
( cd "$DEST" && bash scripts/recall.sh "how should I handle uncertainty" )   # a seeded memory is recallable
( cd "$DEST" && git log --oneline -1 && ls -la .git/hooks/pre-commit )       # commit + gate symlink
grep -n "<slug>" Projects-REGISTRY.md                                         # registered
```

## Step 3 — Fill the genome (the point of graduating)
Open `Source/INTENT.md` + `Source/SPEC.md` and fill them WITH the user (interview, one question at a time) — or at least seed them from what they've already said about the idea. A graduated project with empty genome docs isn't done. Then update `Log/STATUS.md` for session 1 and let the user drive the first build slice.

## Notes
- Identity is **vendored** (a copy). To propagate a later identity change, a future `lab sync <slug>` re-pulls it (not built yet).
- The project is fully walled: its own repo, its own memory namespace. It never reads/writes the lab or any other workspace.
- For a structural dry-run with NO side effects (no venv/seed/git/registry): `new-project.sh <slug> --root /tmp --no-venv --no-seed --no-git --no-reindex`.
