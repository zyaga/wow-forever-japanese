"""How often each word of the game's text is used (docs/systems/word-status.md).

A Japanese word is its dictionary form with that form's reading; a word listed without one is itself with
its reading. An English word is the lower-cased word of a line's English word card row. Each word carries one
count per kind of text, in `KINDS` order: for Japanese how many times it is used, for English how many lines
list it. The addon ranks the words itself (most used first, ties by key), so a new word changes one file.
"""

from __future__ import annotations

import zlib
from collections.abc import Iterable, Mapping
from pathlib import Path
from typing import Any

KINDS = ("quest", "gossip", "book", "ui", "item", "spell")
JA_SHARDS = 4  # files the Japanese list is spread over
EN_SHARDS = 2
GRAMMAR_FILE = "grammar_words.txt"  # pipeline/: the words that start as Ignored, "word<TAB>reading" a line

Counts = dict[str, list[int]]


def key_of(entry: list[Any]) -> str:
    """A reading entry's word key: "dictionary form<TAB>its reading", or "word<TAB>reading" without one."""
    if len(entry) == 5:
        return f"{entry[2]}\t{entry[3]}"
    return f"{entry[0]}\t{entry[1]}"


def _lines(current: Mapping[str, list[dict[str, Any]]]) -> Iterable[tuple[int, dict[str, Any]]]:
    """(place of its kind in KINDS, record) for each line, once: a line also shipped under another key (a
    female variant, a repeated quest's text) is the same record's word list again, and is not more text. It
    counts for the first kind that holds it."""
    seen: set[int] = set()
    for at, kind in enumerate(KINDS):
        for rec in current.get(kind, []):
            mark = id(rec["words"])
            if mark not in seen:
                seen.add(mark)
                yield at, rec


def japanese_counts(current: Mapping[str, list[dict[str, Any]]]) -> Counts:
    """{word key: uses per kind} over the reading records that ship."""
    out: Counts = {}
    for at, rec in _lines(current):
        for entry in rec["words"]:
            out.setdefault(key_of(entry), [0] * len(KINDS))[at] += 1
    return out


def english_counts(current: Mapping[str, list[dict[str, Any]]], common: Iterable[str] = ()) -> Counts:
    """{English word: lines per kind that list it} over the records' English word card rows, plus every word
    of the common word list (a word no line lists has no count)."""
    out: Counts = {word: [0] * len(KINDS) for word in common}
    for at, rec in _lines(current):
        for pair in (rec.get("english") or "").split():
            out.setdefault(pair.rpartition("=")[0], [0] * len(KINDS))[at] += 1
    return out


def ranked(counts: Counts) -> list[str]:
    """The keys, most used first; equal totals by key."""
    return sorted(counts, key=lambda key: (-sum(counts[key]), key))


def rows(counts: Counts) -> dict[str, str]:
    """{key: "q,g,b,u,i,s"}: the addon's row for each word."""
    return {key: ",".join(str(n) for n in per_kind) for key, per_kind in counts.items()}


def shards(rows_: dict[str, str], count: int) -> dict[int, dict[str, str]]:
    """The rows by file, from the key alone, so a new word changes one file."""
    out: dict[int, dict[str, str]] = {}
    for key, row in rows_.items():
        out.setdefault(zlib.crc32(key.encode("utf-8")) % count, {})[key] = row
    return out


def load_grammar(pipeline_dir: Path, known: Iterable[str]) -> tuple[list[str], list[str]]:
    """→ (the grammar words' keys, problems). A line is "word<TAB>reading"; `#` starts a comment. A key that
    is no word of the frequency list, and a key listed twice, are problems."""
    path = pipeline_dir / GRAMMAR_FILE
    if not path.is_file():
        return [], []
    words, problems = set(known), []
    keys: list[str] = []
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        key = raw.split("#", 1)[0].rstrip()
        if not key:
            continue
        if key.count("\t") != 1:
            problems.append(f"{GRAMMAR_FILE}:{n}: a line is word<TAB>reading")
        elif key in keys:
            problems.append(f"{GRAMMAR_FILE}:{n}: {key!r} is listed twice")
        elif key not in words:
            problems.append(f"{GRAMMAR_FILE}:{n}: {key!r} is not a word of the game's text")
        else:
            keys.append(key)
    return keys, problems
