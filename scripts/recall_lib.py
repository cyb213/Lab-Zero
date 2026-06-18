#!/usr/bin/env python3
"""
Generalized recall engine — shared config + path resolution.

Imported by recall-index.py and recall-search.py so the embedding model,
dimensions, and source tag are guaranteed identical across index and search.
A drift between them silently returns garbage (review I1/I2), so they live in
ONE place: the resolved config.

Config file: `recall.config.json` at the workspace root. Every field is
optional; DEFAULTS below reproduce the conventions. `root: "."` resolves to
`git rev-parse --show-toplevel` at runtime.

Isolation (review C1 — the tripwire): the Claude Code auto-memory namespace
is DERIVED at runtime from the resolved root, never read from a persisted
literal. A guard refuses to run if an explicit override resolves to a
namespace key that does not match THIS workspace's derived key — so a config
copied from another workspace can never make this one index a foreign
memory namespace.

CLI:
    recall_lib.py --env       # print resolved config as shell `export` lines
    recall_lib.py --json      # print resolved config as JSON (debug)
"""

import datetime
import json
import os
import subprocess
import sys
from glob import glob
from pathlib import Path

CONFIG_NAME = "recall.config.json"

DEFAULTS = {
    "root": ".",
    "source": "lab",
    "db": "memory/index.db",
    "state_file": "memory/index-state.json",
    "trail": "memory/recall-trail.jsonl",
    "misses": "memory/recall-misses.jsonl",
    "index_globs": ["Log/**/*.md", "Sessions/**/*.md", "Source/**/*.md", "CLAUDE.md"],
    "id_search_dirs": ["Log", "Sessions", "Source"],
    "skip_dir_parts": ["__pycache__", ".git", "node_modules", "venv", ".venv", ".venv-build"],
    "skip_prefixes": [],
    # Full alternation actually used by the ID short-circuit (review I3): T-784,
    # D-302, S204, S13a, T783, "session 199". Generalize per-workspace if needed.
    "codename_regex": r"\b[TDS]-[0-9]+[a-z]?\b|\b[TDS][0-9]+[a-z]?\b|\bsession[[:space:]]+[0-9]+\b",
    # index/search INVARIANTS — must match between the two scripts or KNN is garbage.
    "model_name": "all-MiniLM-L6-v2",
    "dims": 384,
    # "runtime" → derive the CC namespace from the resolved root; "none" → skip
    # auto-memory entirely. `auto_memory_dir` is an explicit override (rare).
    "auto_memory": "runtime",
    "auto_memory_dir": None,
    # Workspace tracking files the git drift-gate requires to carry "session N"
    # on a new session-note commit. Default = the full four-file convention;
    # a lighter workspace (e.g. the Lab) overrides with fewer.
    "tracking_files": ["Log/STATUS.md", "Log/TASKS.md", "Log/PLAN.md", "Log/DECISIONS.md"],
}


def _git_toplevel(start):
    try:
        out = subprocess.run(
            ["git", "-C", str(start), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
        )
        return out.stdout.strip()
    except Exception:
        return None


def find_root(start=None):
    """Resolve the workspace root: env override → nearest recall.config.json → git toplevel → cwd."""
    start = start or os.environ.get("RECALL_ROOT") or os.getcwd()
    p = Path(start).resolve()
    for d in [p, *p.parents]:
        if (d / CONFIG_NAME).exists():
            return d
    top = _git_toplevel(start)
    return Path(top).resolve() if top else p


def path_to_namespace_key(abs_root):
    """CC memory namespace key = abspath with every '/', '.', '_' mapped to '-'.

    Verified live against ~/.claude/projects/:
        /home/alice/.lab       -> -home-alice--lab        (the '/.' yields '--')
        /home/alice/work/proj  -> -home-alice-work-proj   ('_' also -> '-')
    """
    return str(abs_root).translate(str.maketrans({"/": "-", ".": "-", "_": "-"}))


def derive_auto_memory_dir(abs_root):
    """Return (memory_dir, key) for the workspace's own CC namespace."""
    key = path_to_namespace_key(abs_root)
    return os.path.expanduser(f"~/.claude/projects/{key}/memory"), key


def _fail(msg, code):
    print(f"[recall] {msg}", file=sys.stderr)
    sys.exit(code)


def load(start=None):
    """Load + resolve config into a dict with absolute paths and a vetted auto-memory dir."""
    root = find_root(start)

    cfg = dict(DEFAULTS)
    cfgfile = Path(root) / CONFIG_NAME
    if cfgfile.exists():
        try:
            user = json.loads(cfgfile.read_text())
        except Exception as e:
            _fail(f"bad {CONFIG_NAME}: {e}", 2)
        cfg.update({k: v for k, v in user.items() if v is not None})

    # Honor an explicit `root` field; otherwise the discovered dir is the root.
    if cfg.get("root") not in (".", "", None):
        r = cfg["root"]
        root = Path(r).resolve() if os.path.isabs(r) else (Path(root) / r).resolve()
    abs_root = Path(root).resolve()

    # ── Auto-memory namespace: DERIVE, never trust a persisted literal (C1) ──
    auto_dir = None
    auto_key = None
    mode = cfg.get("auto_memory")
    if cfg.get("auto_memory_dir"):  # explicit override
        auto_dir = os.path.expanduser(cfg["auto_memory_dir"])
        auto_key = Path(auto_dir).parent.name
    elif mode == "runtime":
        auto_dir, auto_key = derive_auto_memory_dir(abs_root)
    elif mode in ("none", False, None):
        auto_dir = None

    # Isolation guard (C1): an override must still match THIS workspace's derived
    # key (catches a config copied/stamped from another workspace).
    if cfg.get("auto_memory_dir") and auto_key:
        derived = path_to_namespace_key(abs_root)
        if auto_key != derived:
            _fail(
                f"ISOLATION GUARD: auto_memory_dir key '{auto_key}' != derived '{derived}' "
                f"for root {abs_root}. A config was copied without re-deriving. Refusing.",
                3,
            )

    def absify(rel):
        return rel if os.path.isabs(rel) else str(abs_root / Path(rel))

    cfg["root"] = str(abs_root)
    cfg["db"] = absify(cfg["db"])
    cfg["state_file"] = absify(cfg["state_file"])
    cfg["trail"] = absify(cfg["trail"])
    cfg["misses"] = absify(cfg["misses"])
    cfg["auto_memory_dir"] = auto_dir
    cfg["auto_memory_key"] = auto_key
    return cfg


def discover_files(cfg):
    """Resolve index_globs + (vetted) auto-memory dir into a sorted list of abs paths."""
    root = cfg["root"]
    skip_parts = set(cfg["skip_dir_parts"])
    skip_prefixes = tuple(cfg["skip_prefixes"])
    seen = set()

    for pattern in cfg["index_globs"]:
        for match in glob(str(Path(root) / pattern), recursive=True):
            if not os.path.isfile(match):
                continue
            rel = os.path.relpath(match, root)
            if set(Path(rel).parts) & skip_parts:
                continue
            norm = rel.replace(os.sep, "/")
            if any(norm.startswith(p) for p in skip_prefixes):
                continue
            seen.add(os.path.abspath(match))

    auto = cfg.get("auto_memory_dir")
    if auto:
        if os.path.isdir(auto):
            for match in glob(f"{auto}/**/*.md", recursive=True):
                if os.path.isfile(match):
                    seen.add(os.path.abspath(match))
        else:
            # C1 guard rail (a): be loud, don't silently index nothing. A brand-new
            # workspace may legitimately have no namespace yet — warn, don't crash.
            print(
                f"[recall] note: auto-memory dir not found ({auto}); "
                f"indexing workspace files only.",
                file=sys.stderr,
            )
    return sorted(seen)


def file_to_relpath(cfg, abs_path):
    """Render an abs path to a stable, human-friendly citation form."""
    root = cfg["root"]
    auto = cfg.get("auto_memory_dir")
    if abs_path.startswith(root + os.sep):
        return abs_path[len(root) + 1 :]
    if auto and abs_path.startswith(auto + os.sep):
        return f"auto-memory/{abs_path[len(auto) + 1 :]}"
    return abs_path


# ── B1: correction→memory loop (reader + review high-water-mark + glob self-heal) ──
# recall_stop_handler.py appends correction candidates to recall-misses.jsonl; these
# close the loop. The detector is deliberately noisy, so the AGENT (the /review-corrections
# skill) is the filter — this layer just lists what's pending and records what was reviewed.
def last_review_ts(trail_path):
    """The most-recent corrections-review high-water-mark (`through_ts`), or '' if none.

    /review-corrections appends {"event":"corrections_reviewed","through_ts":TS} to the
    trail after each pass (the trail, so log rotation protects one file's markers and the
    misses log stays pure miss-events)."""
    last = ""
    try:
        with open(trail_path, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if rec.get("event") == "corrections_reviewed":
                    tts = rec.get("through_ts")
                    if isinstance(tts, str) and tts:
                        last = tts
    except OSError:
        pass
    return last


def pending_misses(cfg):
    """Correction candidates not yet reviewed: miss entries whose `ts` is strictly AFTER
    the last review high-water-mark. ISO-8601 'Z' timestamps compare lexicographically."""
    through = last_review_ts(cfg["trail"])
    out = []
    try:
        with open(cfg["misses"], "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if rec.get("event") != "miss":
                    continue
                if not through or str(rec.get("ts", "")) > through:
                    out.append(rec)
    except OSError:
        pass
    return out


def write_review_mark(cfg, through_ts):
    """Append the review high-water-mark to the trail. Advance to the LAST candidate the
    skill actually DECIDED on (not wall-clock 'now') so an interrupted pass leaves the rest
    pending — no-recycle must not become no-review. Best-effort."""
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    entry = {"ts": ts, "event": "corrections_reviewed", "through_ts": str(through_ts)}
    try:
        os.makedirs(os.path.dirname(cfg["trail"]), exist_ok=True)
        with open(cfg["trail"], "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        return False
    return True


def ensure_learned_glob(cfg, learned_glob="memory/LEARNED.md"):
    """Idempotently add `learned_glob` to the workspace config's `index_globs` so a promoted
    memory/LEARNED.md gets indexed by recall. Operates on the RAW config file (never the
    resolved cfg, which carries absolute paths + derived keys). Returns True if it wrote a
    change, False if already present / no writable config.

    R4: recall.config.json is personal-not-machinery, so update.sh can't deliver this glob
    to an existing consumer — /review-corrections self-heals before its first portable promote.
    """
    cfgfile = Path(cfg["root"]) / CONFIG_NAME
    try:
        raw = json.loads(cfgfile.read_text())
    except Exception:
        return False
    globs = raw.get("index_globs")
    if not isinstance(globs, list):
        globs = list(DEFAULTS["index_globs"])
    if learned_glob in globs:
        return False
    globs.append(learned_glob)
    raw["index_globs"] = globs
    try:
        cfgfile.write_text(json.dumps(raw, indent=2) + "\n")
    except OSError:
        return False
    return True


def _print_env(cfg):
    """Emit shell `export` lines for recall.sh to `eval`."""

    def q(v):
        return "'" + str(v).replace("'", "'\\''") + "'"

    print(f"export RECALL_ROOT={q(cfg['root'])}")
    print(f"export RECALL_DB={q(cfg['db'])}")
    print(f"export RECALL_TRAIL={q(cfg['trail'])}")
    print(f"export RECALL_MISSES={q(cfg['misses'])}")
    print(f"export RECALL_SOURCE={q(cfg['source'])}")
    print(f"export RECALL_CODENAME_REGEX={q(cfg['codename_regex'])}")
    print(f"export RECALL_ID_SEARCH_DIRS={q(' '.join(cfg['id_search_dirs']))}")
    print(f"export RECALL_TRACKING_FILES={q(' '.join(cfg['tracking_files']))}")


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--pending-count" in args:            # B1: the session-start nudge reads this
        print(len(pending_misses(load())))
    elif "--ensure-learned-glob" in args:    # B1: /review-corrections glob self-heal (R4)
        print("changed" if ensure_learned_glob(load()) else "unchanged")
    elif "--mark-reviewed" in args:          # B1: advance the review high-water-mark
        i = args.index("--mark-reviewed")
        ts = args[i + 1] if i + 1 < len(args) else ""
        if not ts:
            _fail("--mark-reviewed requires a through_ts argument", 2)
        write_review_mark(load(), ts)
        print(f"[recall] marked corrections reviewed through {ts}")
    elif "--misses" in args:                 # B1: pending correction candidates (D1 reader)
        conf = load()
        pend = pending_misses(conf)
        if "--json" in args:
            print(json.dumps(pend, ensure_ascii=False, indent=2))
        elif not pend:
            print("[recall] no pending correction candidates.")
        else:
            print(f"[recall] {len(pend)} pending correction candidate(s) since last review "
                  f"(run /review-corrections to triage):\n")
            for n, rec in enumerate(pend, 1):
                txt = " ".join((rec.get("last_user", "") or "").split())
                if len(txt) > 200:
                    txt = txt[:197] + "…"
                print(f"{n}. [{rec.get('ts', '')}] {txt}")
    elif "--json" in args:
        print(json.dumps({k: v for k, v in load().items()}, indent=2))
    else:  # default + --env
        _print_env(load())
