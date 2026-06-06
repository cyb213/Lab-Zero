#!/usr/bin/env python3
"""
Correction detector — does a user message look like a correction?

The recall-stop hook's earlier 8-pattern bash regex had a low hit rate, so the
full pattern list + SKIP_RE + length guards live here as the single source. The
heuristic flags messages where the user is correcting, redirecting, or stating a
standing preference — the signal the recall feedback loop learns from.

CLI:
    echo "no that's wrong" | correction_detect.py   # exit 0 if correction, 1 if not
"""

import re
import sys

CORRECTION_SIGNALS = [
    r"\bare you (?:drifting|kidding|sure|seeing this)\b",
    r"\bwhy (?:did|are|aren'?t|won'?t|would|should|can'?t) you\b",
    r"\bwhy (?:didn'?t|don'?t|isn'?t|wasn'?t)\b",
    r"\bwhat (?:are you doing|did you do|did you just|the hell)\b",
    r"\bi (?:said|told you|asked|wanted|specified|already|literally)\b",
    r"\bi (?:thought|expected|asked for) (?:we|you)\b",
    r"\b(?:no|nope|wrong|incorrect|that'?s wrong|not quite|not really)\b",
    r"\bstop\b",
    r"\bdon'?t\b",
    r"\b(?:that'?s )?not (?:what|right|correct|the|how)\b",
    r"\byou (?:need to|should) (?:stop|not)\b",
    r"\b(?:are you )?drift(?:ing|ed)\b",
    r"\b(?:wall of text|too long|too verbose|hallucinat)\b",
    r"\b(?:you'?re|are you) (?:making (?:up|stuff)|guessing|assuming)\b",
    r"\b(?:fabric|halluc|confabul)\w*\b",
    r"\b(?:can'?t|cannot) use\b",
    r"\b(?:not|aren'?t) working (?:correctly|properly|right)\b",
    r"\bthis is (?:broken|bad|not (?:good|right|working))\b",
    r"\bwe have a problem\b",
    r"\b(?:agents|v2c|ray|the system) (?:is|are|isn'?t|aren'?t) (?:not |un)?(?:work|broken|reliab|useful)\w*\b",
    r"\b(?:i'?m |i am )?(?:locked out|blocked) (?:by|because|from|until)\b",
    r"\bplease (?:touch|run|restart|chmod|create|delete|setup|enable) [^\s]",
    r"\bcannot proceed (?:until|because|without)\b",
    r"\bfrom now on\b",
    r"\bi (?:only|always|never) (?:use|want|need)\b",
    r"\bi prefer\b",
    r"\bno need to\b",
    r"\b(?:wtf|fuck|shit|damn|jesus|christ)\b",
    r"\b(?:looks ok|looks good|nice|good job|well done)\b",
    r"\byou (?:should have|didn'?t) read\b",
    r"\byou missed\b",
    r"\bwe already (?:decided|covered)\b",
    r"\bthat'?s not what we\b",
    r"\bdid you (?:read|check)\b",
]
CORRECTION_RE = re.compile("|".join(CORRECTION_SIGNALS), re.IGNORECASE)

SKIP_RE = re.compile(
    r"^(?:```|---|\s*\*\*|#|>|\| |\+|-|\d+\.|tags:|status:)",
    re.IGNORECASE,
)


def is_correction(text: str) -> bool:
    """Heuristic — does this user text look like a correction?"""
    if not text or len(text) < 4 or len(text) > 600:
        return False
    t = text.strip()
    if SKIP_RE.match(t):
        return False
    return bool(CORRECTION_RE.search(t))


if __name__ == "__main__":
    sys.exit(0 if is_correction(sys.stdin.read()) else 1)
