"""Word meanings (ADR-039): what the word popup shows under a word's reading.

The meanings live in the reading records themselves: an entry [word, reading, dictionary form, its reading,
meaning] is written by the model with the sentence in front of it, so the meaning is the one that sentence
uses (倒して in "Nightsaberを倒して" → 倒す, "defeat"). This module builds the generated meaning table
(each distinct (dictionary form, its reading, meaning) stored once, numbered, and pointed at from the packed
reading rows) and the local JMdict cross-check that flags a dictionary form the dictionary does not know.
JMdict is only read on a local machine; nothing from it ships. Pure: no disk.

The numbers are kept in `data/reading/meaning-numbers.tsv` (ADR-060) so a meaning keeps its number when others
are added or dropped: a new meaning takes the next number after the highest ever given, a meaning no reading
uses any more keeps its line (and ships nowhere), and a number is never given to another meaning.
"""

from __future__ import annotations

from collections.abc import Iterable
from typing import Any

SEP = "\t"  # the generated meaning row's field separator (never inside a field: readings.meaning_problems)
PER_FILE = 1000  # meanings per generated file

Meaning = tuple[str, str, str]  # (dictionary form, its reading, meaning)


def meanings_of(records: Iterable[dict[str, Any]]) -> Iterable[Meaning]:
    for rec in records:
        for entry in rec["words"]:
            if len(entry) == 5:
                yield (entry[2], entry[3], entry[4])


NUMBERS_FILE = "meaning-numbers.tsv"  # beside the reading types in data/reading/


def number(
    records: Iterable[dict[str, Any]], known: dict[Meaning, int]
) -> tuple[dict[Meaning, int], dict[Meaning, int]]:
    """(every distinct meaning the records use → its number, every numbered meaning → its number).
    `known` is the numbers file; a meaning it lacks gets the next number after the highest in it, the new
    ones in sorted order, so the result is deterministic. With no file the numbers are 1… in sorted order."""
    used = sorted(set(meanings_of(records)))
    every = dict(known)
    nxt = max(known.values(), default=0) + 1
    for m in used:
        if m not in every:
            every[m] = nxt
            nxt += 1
    return {m: every[m] for m in used}, every


def parse_numbers(text: str) -> tuple[dict[Meaning, int], list[str]]:
    """The numbers file (`n<TAB>dictionary form<TAB>its reading<TAB>meaning` per line) → (meaning → number,
    problems). A bad line, a number given twice or a meaning listed twice is a problem, never resolved
    here."""
    out: dict[Meaning, int] = {}
    seen: set[int] = set()
    problems: list[str] = []
    # only "\n" ends a line: str.splitlines would also split a meaning holding U+2028 or U+0085
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    for i, line in enumerate(lines, 1):
        fields = line.split(SEP)
        n_ok = fields[0].isascii() and fields[0].isdigit()
        if len(fields) != 4 or not n_ok or int(fields[0]) < 1 or not all(fields[1:]):
            problems.append(f"{NUMBERS_FILE}:{i}: not `n<TAB>dictionary form<TAB>its reading<TAB>meaning`")
            continue
        n, m = int(fields[0]), (fields[1], fields[2], fields[3])
        if n in seen:
            problems.append(f"{NUMBERS_FILE}:{i}: number {n} is given twice")
        elif m in out:
            problems.append(f"{NUMBERS_FILE}:{i}: meaning already numbered {out[m]}")
        else:
            seen.add(n)
            out[m] = n
    return out, problems


def numbers_text(every: dict[Meaning, int]) -> str:
    """The numbers file, one line per meaning, by number."""
    return "".join(f"{n}{SEP}{row_text(m)}\n" for m, n in sorted(every.items(), key=lambda kv: kv[1]))


def row_text(m: Meaning) -> str:
    return SEP.join(m)


def shard_of(n: int) -> int:
    """Meanings 1–1000 → 0, 1001–2000 → 1, …"""
    return (n - 1) // PER_FILE


# ── the JMdict cross-check (local only) ──────────────────────────────────────


class Dictionary:
    """The spellings JMdict knows (jmdict-simplified JSON): (kanji form, its kana) pairs and kana forms."""

    def __init__(self, jmdict: dict[str, Any]):
        self.version = str(jmdict.get("version", "?"))
        self.pairs: set[tuple[str, str]] = set()
        self.kana: set[str] = set()
        for w in jmdict["words"]:
            for kn in w["kana"]:
                self.kana.add(kn["text"])
                for k in w["kanji"]:
                    if "*" in kn["appliesToKanji"] or k["text"] in kn["appliesToKanji"]:
                        self.pairs.add((k["text"], kn["text"]))

    def knows(self, lemma: str, lemma_reading: str) -> bool:
        # the batch rules write a noun + する verb as 調査する; JMdict lists the noun (調査, marked vs)
        if lemma.endswith("する") and lemma_reading.endswith("する") and len(lemma) > 2:
            lemma, lemma_reading = lemma[:-2], lemma_reading[:-2]
        if lemma == lemma_reading:
            return lemma in self.kana
        return (lemma, lemma_reading) in self.pairs


def unknown(dictionary: Dictionary, records: Iterable[dict[str, Any]]) -> dict[tuple[str, str], int]:
    """(dictionary form, its reading) the dictionary does not know → how many words use it. Most are game
    compounds (大族長) and fine; a misspelt or invented form shows up here too."""
    out: dict[tuple[str, str], int] = {}
    for lemma, lemma_reading, _meaning in meanings_of(records):
        if not dictionary.knows(lemma, lemma_reading):
            out[(lemma, lemma_reading)] = out.get((lemma, lemma_reading), 0) + 1
    return out
