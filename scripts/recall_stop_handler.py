#!/usr/bin/env python3
"""
Stop-hook handler — read the Stop event JSON on stdin, detect a user correction
in the last user message of the transcript, append it to the misses log.

A real module (not a heredoc) so the event can arrive on stdin cleanly: the
event is read from stdin rather than interpolated into the Python source (which
would break on a triple-quote sequence in the transcript and be an injection
hazard). Correction detection is the full pattern list in
correction_detect.is_correction(). Best-effort: failure -> 0.
"""

import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import recall_lib  # noqa: E402
from correction_detect import is_correction  # noqa: E402


def _last_user_text(tp):
    """Final user message text from a Claude Code transcript JSONL."""
    last = ""
    try:
        with open(tp, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if rec.get("type") != "user":
                    continue
                content = rec.get("message", {}).get("content", "")
                if isinstance(content, list):
                    parts = [
                        c.get("text", "")
                        for c in content
                        if isinstance(c, dict) and c.get("type") == "text"
                    ]
                    text = "\n".join(p for p in parts if p)
                elif isinstance(content, str):
                    text = content
                else:
                    text = ""
                if text:
                    last = text  # keep updating; final = last user msg
    except Exception:
        pass
    return last


def main():
    raw = sys.stdin.read()
    try:
        evt = json.loads(raw.strip() or "{}")
    except Exception:
        return 0

    cfg = recall_lib.load()
    misses_path = cfg["misses"]

    tp = evt.get("transcript_path") or evt.get("transcriptPath") or ""
    if tp:
        last = _last_user_text(tp)
    else:
        msg = evt.get("user_message") or evt.get("last_user_message") or ""
        last = msg if isinstance(msg, str) else ""

    if not last or not is_correction(last):
        return 0

    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    entry = {"ts": ts, "event": "miss", "last_user": last[:500], "transcript_path": tp}
    try:
        os.makedirs(os.path.dirname(misses_path), exist_ok=True)
        with open(misses_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
