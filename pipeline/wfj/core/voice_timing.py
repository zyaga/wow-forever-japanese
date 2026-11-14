"""Where a voice line's sentences are, where its recording is cut into one file per sentence, and when
each part of its Japanese is spoken (ADR-090). Pure: the models' times and the samples come in as data.

Two models time every recording. ReazonSpeech gives a start per character of the text the engine read;
Qwen's aligner gives a start and an end per word. A cut is made in the middle of the pause before a
sentence only where both agree the earlier sentence has ended and the next has not begun, so a file
never starts or ends inside a word.

The timing string is what the addon reads: the shipped Japanese, in order, as parts of n characters,
each with the hundredths of a second since the part before it started ("n:dt"), or "n:-" for a part
nobody says (a stage direction the voice skips, a blank line)."""

from __future__ import annotations

import difflib
import math
import re
from collections.abc import Mapping, Sequence

# a sentence ends at a run of full stops, question or exclamation marks (and the closing brackets
# after them), or at a line break
_END = re.compile(r"[。！？!?]+[」』）)]*|\n+")
# what a sentence cannot start with: spaces, punctuation, opening brackets, the long-vowel mark
_NOT_START = re.compile(r"[\s。！？!?」』）)、・「『（(…ー〜~.,]")
# a player token the addon fills in: never split across two parts
_TOKEN = re.compile(r"\{[A-Za-z]+\}|<[A-Za-z]+/[A-Za-z]+>|\$N\d+|\$\d+w|\$[bB]")

PAUSE_FLOOR = 0.05  # a 10 ms frame is quiet under this share of the line's loud frames
MIN_PAUSE = 0.10  # seconds: a shorter quiet stretch is a consonant, not a pause
MIN_CUT_PAUSE = 0.15  # seconds: the shortest pause a file may be cut in
CONFIRM = 0.08  # seconds: Qwen's time step; a word may touch the cut by this much
LOOK_BACK = 0.40  # seconds: a sentence's first sound may come this long after its pause ends

# first character and end (exclusive) in the engine text, then start and end in seconds
Word = tuple[int, int, float, float]


def sentence_starts(text: str) -> list[int]:
    """The index of each sentence's first spoken character."""
    out, last = [], 0
    for end in [m.end() for m in _END.finditer(text)] + [len(text)]:
        for i in range(last, end):
            if not _NOT_START.match(text[i]):
                out.append(i)
                break
        last = end
    return out


def pauses(samples: Sequence[int], rate: int) -> list[tuple[float, float]]:
    """The quiet stretches between sounds, in seconds: 10 ms frames under PAUSE_FLOOR of the line's
    loud frames (its 95th percentile), at least MIN_PAUSE long. Silence before the first sound and
    after the last is left out."""
    hop = max(1, rate // 100)
    frames = []
    for i in range(0, len(samples) - hop + 1, hop):
        chunk = samples[i:i + hop]
        frames.append(math.sqrt(sum(v * v for v in chunk) / len(chunk)))
    if not frames:
        return []
    loud = sorted(frames)[int(len(frames) * 0.95)] or 1.0
    floor = loud * PAUSE_FLOOR
    out, start, heard = [], None, False
    for i, level in enumerate(frames):
        if level < floor:
            if start is None:
                start = i
        else:
            if start is not None and heard and (i - start) / 100 >= MIN_PAUSE:
                out.append((start / 100, i / 100))
            start, heard = None, True
    return out


def _first_at(times: Mapping[int, float], i: int, end: int) -> float | None:
    for x in range(i, end):
        if x in times:
            return times[x]
    return None


def cuts(text: str, rz: Mapping[int, float], qwen: Sequence[Word], quiet: Sequence[tuple[float, float]],
         duration: float) -> list[float]:
    """The times to cut the recording at: one per sentence that starts after a pause both models
    agree on."""
    if not qwen:
        return []
    out: list[float] = []
    for i in sentence_starts(text)[1:]:
        before = [w for w in qwen if w[0] < i]
        after = [w for w in qwen if w[0] >= i]
        if not before or not after:
            continue
        # the next sentence's first sound: the earlier of the two models' starts for it
        t = min(after, key=lambda w: w[0])[2]
        heard = _first_at(rz, i, len(text))
        if heard is not None:
            t = min(t, heard)
        inside = [p for p in quiet if p[0] - 0.1 <= t <= p[1]]
        ending = [p for p in quiet if t - LOOK_BACK <= p[1] <= t + 0.05]
        pause = inside[0] if inside else (max(ending, key=lambda p: p[1]) if ending else None)
        if pause is None or pause[1] - pause[0] < MIN_CUT_PAUSE:
            continue
        cut = round((pause[0] + pause[1]) / 2, 3)
        if max(w[3] for w in before) > cut + CONFIRM or min(w[2] for w in after) < cut - CONFIRM:
            continue
        if 0 < cut < duration and (not out or cut > out[-1]):
            out.append(cut)
    return out


def _engine_map(ja: str, text: str) -> tuple[dict[int, int | None], dict[int, str]]:
    """Where each character of the shipped Japanese is in the engine's text (None: never said), and
    how it got there ("equal", "replace" for a name read in katakana, "unsaid")."""
    engine: dict[int, int | None] = {}
    kind: dict[int, str] = {}
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, ja, text, autojunk=False).get_opcodes():
        said = op == "equal" or (op == "replace" and text[j1:j2].strip() != "")
        for i in range(i1, i2):
            engine[i] = (j1 + i - i1 if op == "equal" else j1) if said else None
            kind[i] = op if said else "unsaid"
    for i, ch in enumerate(ja):
        if ch.isspace():
            engine[i], kind[i] = None, "unsaid"
    return engine, kind


def _card_starts(ja: str, cards: Sequence[str]) -> set[int]:
    out, cursor = set(), 0
    for word in cards:
        i = ja.find(word, cursor)
        if i >= 0:
            out.add(i)
            cursor = i + len(word)
    return out


def _bounds(ja: str, engine: Mapping[int, int | None], kind: Mapping[int, str], starts: Mapping[int, float],
            cards: Sequence[str]) -> list[int]:
    inside_token, token_start = set(), set()
    for m in _TOKEN.finditer(ja):
        token_start.add(m.start())
        inside_token.update(range(m.start() + 1, m.end()))
    card_start = _card_starts(ja, cards)
    out = []
    for i in range(len(ja)):
        if i in inside_token:
            continue
        unsaid = kind[i] == "unsaid"
        changed = i > 0 and unsaid != (kind[i - 1] == "unsaid")
        new_word = kind[i] == "equal" and engine[i] in starts
        new_block = kind[i] == "replace" and kind.get(i - 1) != "replace"
        if i == 0 or changed or i in token_start or i in card_start or new_word or new_block:
            out.append(i)
    return [*out, len(ja)]


def timing(ja: str, text: str, rz: Mapping[int, float], qwen: Sequence[Word], cards: Sequence[str]) -> str:
    """The timing string of the shipped Japanese `ja`, read by the engine as `text`. A part starts at
    each word Qwen found, each word card word (`cards`, the line's word list in order), each player
    token, and wherever the text turns from said to unsaid; it is timed by Qwen where a word starts
    there, else by ReazonSpeech (never before the Qwen word it falls in)."""
    starts = {w[0]: w[2] for w in qwen}
    begins = sorted(starts)
    engine, kind = _engine_map(ja, text)

    def time_of(i: int) -> float | None:
        j = engine.get(i)
        if j is None:
            return None
        if j in starts:
            return starts[j]
        held = None
        for b in begins:
            if b > j:
                break
            held = starts[b]
        heard = _first_at(rz, j, len(text))
        if held is not None and heard is not None:
            return max(held, heard)
        return heard if heard is not None else held

    bounds = _bounds(ja, engine, kind, starts, cards)
    parts, clock = [], 0
    for a, b in zip(bounds, bounds[1:], strict=False):
        t = None if kind[a] == "unsaid" else time_of(a)
        if t is None:
            parts.append(f"{b - a}:-")
            continue
        cs = max(clock, round(t * 100))
        parts.append(f"{b - a}:{cs - clock}")
        clock = cs
    return " ".join(parts)
