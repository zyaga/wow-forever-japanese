"""Japanese names (ADR-077): one line per distinct English name, keyed by the hash of the normalized English.

    {"id": "<16 hex>", "en": "Orgrimmar", "ids": {"area": [1637]}, "prose": true, "ja": "オーグリマー",
     "reading": "おーぐりまー", "free": false, "status": "trusted",
     "provenance": {"class": "machine", "source": "hearthstone@256589", "imported": "YYYY-MM-DD"}}

`ids` lists the game ids that carry the name, per kind; `prose` says the name was seen inside shipped
Japanese prose (a run of Latin letters). One line per English name makes one Japanese per name everywhere.
`free` marks a name translated rather than spelled out word by word, which the one-spelling check skips.
The word glossary (`words.jsonl`) holds English proper-noun words with their Japanese; a word whose `check`
is true must appear, in its Japanese form, in every name that contains it.
Pure: no disk.
"""

from __future__ import annotations

import re
from collections.abc import Iterable, Mapping
from typing import Any

from wfj.core import model
from wfj.core.hashing import key as hash_key
from wfj.core.normalize import normalize_for

KINDS = ("unit", "item", "spell", "object", "area", "faction", "map")
STATUSES = ("missing", "trusted")
KEYS = ("id", "en", "ids", "prose", "ja", "reading", "free", "status", "provenance")
WORD_KEYS = ("en", "ja", "check", "provenance")
_ASCII_LETTER = re.compile(r"[A-Za-z]")
_READING = re.compile(r"^[ぁ-ゖー・]+$")
KATAKANA = re.compile(r"^[ァ-ヺー・]+$")
_WORD_SPLIT = re.compile(r"[ \-]+")

# Markup a shipped line can hold, removed before its Latin runs are read: player tokens, server codes,
# colour and link escapes, texture escapes.
_MARKUP = re.compile(
    r"\{[a-z]+\}|\$[0-9]*[A-Za-z][0-9]*|\|c[0-9A-Fa-f]{8}|\|r|\|H[^|]*\|h|\|h|\|T[^|]*\|t|\|n"
)
# A name in prose: Latin letters, digits and the punctuation names carry (Zul'Gurub, Un'Goro, C.O.R.E.),
# words joined by single spaces.
LATIN_RUN = re.compile(r"[A-Za-z][A-Za-z0-9'’.&-]*(?: [A-Za-z0-9][A-Za-z0-9'’.&-]*)*")
_TRAILING = ".'’-&"
_TRAILING_NUMBER = re.compile(r"(?: [0-9][0-9.,]*)+$")  # a count after a name ("Stranglethorn raptor 10")
_GLUED_NUMBER = re.compile(r"(?<=[a-z'’.])[0-9][0-9.,]*$")  # a count written onto it ("mageweave cloth60枚")
_STOPWORDS = frozenset({"of", "the", "a", "an", "and", "to", "in", "on", "for", "at", "from", "with"})


def norm(en: str) -> str:
    """The English name as the hash reads it: the client-template canon (no player tokens)."""
    return normalize_for("item", en)


def name_id(en: str) -> str:
    return hash_key(norm(en))


def hiragana(text: str) -> str:
    """Katakana to hiragana; the long-vowel mark, the middle dot and everything else unchanged."""
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in text)


def has_latin(text: str) -> bool:
    return bool(_ASCII_LETTER.search(text))


def trim_run(raw: str) -> str:
    """The name in a run of Latin letters: a count after it (" 10", "60" written onto it) and edge
    punctuation left out. The collector and the kana builder read names this one way."""
    run = _TRAILING_NUMBER.sub("", raw).rstrip(_TRAILING).strip()
    return _GLUED_NUMBER.sub("", run)


def latin_runs(ja: str) -> list[str]:
    """The English names inside a shipped Japanese line, in order (repeats kept)."""
    out = []
    for m in LATIN_RUN.finditer(_MARKUP.sub(" ", ja)):
        run = trim_run(m.group(0))
        if run and has_latin(run):
            out.append(run)
    return out


def words_of(en: str) -> list[str]:
    """The words of an English name the glossary is matched on: split on spaces and hyphens, a possessive
    "'s" and edge punctuation dropped."""
    out = []
    for raw in _WORD_SPLIT.split(en):
        w = raw.strip(',:;!?()"').rstrip(".")
        if w.endswith(("'s", "’s")):
            w = w[:-2]
        if w:
            out.append(w)
    return out


def new_line(en: str, today: str) -> dict[str, Any]:
    n = norm(en)
    return {
        "id": hash_key(n),
        "en": n,
        "ids": {},
        "prose": False,
        "ja": "",
        "reading": "",
        "free": False,
        "status": "missing",
        "provenance": {"class": "machine", "source": f"names-collect@{today}", "imported": today},
    }


def ordered(line: Mapping[str, Any]) -> dict[str, Any]:
    out = {k: line[k] for k in KEYS}
    out["ids"] = {k: sorted(set(line["ids"][k])) for k in KINDS if line["ids"].get(k)}
    return out


def merge(
    lines: Iterable[Mapping[str, Any]],
    seen: Mapping[str, Mapping[str, Iterable[int]]],
    prose: Iterable[str],
    today: str,
) -> tuple[list[dict[str, Any]], int]:
    """Lines with every collected name present: `seen` is {English: {kind: ids}}, `prose` the names read in
    prose. Ids and the prose flag are only added; a line is never removed and its Japanese never changed.
    Returns (lines, how many lines were new)."""
    by_id = {ln["id"]: ordered(ln) for ln in lines}
    added = 0

    def line_for(en: str) -> dict[str, Any] | None:
        nonlocal added
        if not norm(en):
            return None
        i = name_id(en)
        if i not in by_id:
            by_id[i] = new_line(en, today)
            added += 1
        return by_id[i]

    for en, kinds in seen.items():
        ln = line_for(en)
        if ln is None:
            continue
        for kind, ids in kinds.items():
            if kind not in KINDS:
                raise ValueError(f"unknown name kind {kind!r}")
            ln["ids"][kind] = sorted(set(ln["ids"].get(kind, ())) | {int(i) for i in ids})
    for en in prose:
        ln = line_for(en)
        if ln is not None:
            ln["prose"] = True
    return [ordered(by_id[i]) for i in sorted(by_id)], added


def _provenance_problems(prov: Any) -> list[str]:
    if not isinstance(prov, dict):
        return ["provenance missing"]
    return model.base_provenance_problems(prov, "provenance")


def line_problems(line: Any) -> list[str]:
    if not isinstance(line, dict) or tuple(line) != KEYS:
        return [f"keys must be {KEYS}"]
    en = line["en"]
    out = []
    if not isinstance(en, str) or not en or norm(en) != en:
        out.append(f"en {en!r} is not a normalized name")
    elif line["id"] != hash_key(en):
        out.append(f"id {line['id']} is not the hash of {en!r}")
    ids = line["ids"]
    if not isinstance(ids, dict) or any(
        k not in KINDS or not v or v != sorted(set(v)) or not all(isinstance(i, int) for i in v)
        for k, v in ids.items()
    ):
        out.append(f"ids {ids!r}: kinds of {KINDS}, each a sorted list of distinct ints")
    if not ids and line["prose"] is not True:
        out.append("no game id and not seen in prose")
    if not isinstance(line["free"], bool) or not isinstance(line["prose"], bool):
        out.append("prose and free are true or false")
    status, ja, reading = line["status"], line["ja"], line["reading"]
    if status not in STATUSES:
        out.append(f"status {status!r}")
    elif status == "missing":
        if ja or reading:
            out.append("a missing line has no Japanese")
    else:
        if not isinstance(ja, str) or not ja.strip():
            out.append("no Japanese")
        elif _ASCII_LETTER.search(ja):
            out.append(f"Japanese {ja!r} holds Latin letters")
        if not isinstance(reading, str) or not _READING.match(reading):
            out.append(f"reading {reading!r} is not hiragana")
        elif isinstance(ja, str) and KATAKANA.match(ja) and reading != hiragana(ja):
            out.append(f"reading {reading!r} is not the hiragana of {ja!r}")
    return out + _provenance_problems(line["provenance"])


def word_problems(word: Any) -> list[str]:
    if not isinstance(word, dict) or tuple(word) != WORD_KEYS:
        return [f"keys must be {WORD_KEYS}"]
    out = []
    if not isinstance(word["en"], str) or not word["en"] or " " in word["en"]:
        out.append(f"word {word['en']!r} is not one English word")
    if not isinstance(word["ja"], str) or not word["ja"] or _ASCII_LETTER.search(word["ja"]):
        out.append(f"word {word['en']!r}: Japanese {word['ja']!r}")
    if not isinstance(word["check"], bool):
        out.append(f"word {word['en']!r}: check is true or false")
    return out + _provenance_problems(word["provenance"])


def checked_glossary(words: Iterable[Mapping[str, Any]]) -> dict[str, tuple[str, str]]:
    """{word: (its Japanese, that Japanese in hiragana)} for the glossary words every name is held to."""
    return {w["en"]: (w["ja"], hiragana(w["ja"])) for w in words if w["check"]}


def misspelled(line: Mapping[str, Any], glossary: Mapping[str, tuple[str, str]]) -> list[tuple[str, str]]:
    """[(word, its Japanese)] for each checked word of a drafted name whose Japanese is in neither the name's
    Japanese nor its reading. Hearthstone's own whole names and `free` names are held to nothing."""
    if line["status"] != "trusted" or line["free"] or line["provenance"]["source"].startswith("hearthstone@"):
        return []
    have = hiragana(line["ja"]) + "\x00" + line["reading"]
    return [(w, glossary[w][0]) for w in words_of(line["en"]) if w in glossary and glossary[w][1] not in have]


def spelling_problems(lines: Iterable[Mapping[str, Any]], words: Iterable[Mapping[str, Any]]) -> list[str]:
    """Names that spell a checked glossary word some other way."""
    glossary = checked_glossary(words)
    return [
        f"{ln['en']!r} → {ln['ja']!r}: {w!r} is {ja!r} everywhere else"
        for ln in lines
        for w, ja in misspelled(ln, glossary)
    ]


def stopword(word: str) -> bool:
    return word.lower() in _STOPWORDS
