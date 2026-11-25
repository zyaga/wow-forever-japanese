"""The word lists a chat line's word card reads (docs/systems/chat-tools.md).

Two general lists are made from the shipped readings, so every word the game text has a card for has one in
chat too: a Japanese word with the reading and meaning it is used with most, and an English word with the
dictionary form of the Japanese word used for it most. A third list is written by hand for chat, in
`data/chat/`: chat words in both languages and the phrase book's phrases.
"""

from __future__ import annotations

import json
import re
import zlib
from collections import Counter
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from wfj.core import model
from wfj.core.glosses import Meaning

MAX_CHARS = 12  # the longest Japanese word the addon looks for in a chat line (Core/ChatWords MAX_CHARS)
JA_SHARDS = 12  # files the Japanese list is spread over
EN_SHARDS = 4

_JAPANESE = re.compile(r"^[々〆぀-ヿ㐀-鿿０-ｚ]+$")
_ONE_KANA = re.compile(r"^[぀-ヿ]$")
_ENGLISH = re.compile(r"^[a-z][a-z']*$")


def japanese_rows(records: Iterable[dict[str, Any]], meanings: dict[Meaning, int]) -> dict[str, str]:
    """{Japanese word: "reading" or "reading=n"}: for each word of the reading records, the reading and
    meaning number it carries most often, a pair with a meaning before any pair without one. A single kana,
    a word with anything but Japanese characters, a word longer than the addon looks for, and a kana word
    with no meaning (its card would show nothing) are left out."""
    seen: dict[str, Counter[tuple[str, int | None]]] = {}
    for rec in records:
        for entry in rec["words"]:
            word, reading = entry[0], entry[1]
            if not _JAPANESE.match(word) or _ONE_KANA.match(word) or len(word) > MAX_CHARS:
                continue
            n = meanings.get((entry[2], entry[3], entry[4])) if len(entry) == 5 else None
            seen.setdefault(word, Counter())[(reading, n)] += 1
    out: dict[str, str] = {}
    for word, pairs in seen.items():
        # most used first; equal counts in a fixed order, so the file never depends on the order of the data
        ranked = sorted(pairs.items(), key=lambda kv: (-kv[1], kv[0][0], kv[0][1] or 0))
        with_meaning = [pair for pair, _ in ranked if pair[1] is not None]
        reading, n = with_meaning[0] if with_meaning else ranked[0][0]
        if n is None and reading == word:
            continue
        out[word] = reading if n is None else f"{reading}={n}"
    return out


def english_rows(records: Iterable[dict[str, Any]], meanings: dict[Meaning, int]) -> dict[str, str]:
    """{English word: "dictionary form=its reading=n"}: for each English word of the records' English word
    card rows, the Japanese word used for it most, in its dictionary form (kill is 倒す, not the 倒し of one
    sentence). A row that points past its line's words, or at a word with no meaning, is skipped."""
    seen: dict[str, Counter[tuple[str, str, int]]] = {}
    for rec in records:
        words = rec["words"]
        for pair in (rec.get("english") or "").split():
            word, _, place = pair.rpartition("=")
            if not _ENGLISH.match(word) or not place.isdigit() or not 1 <= int(place) <= len(words):
                continue
            entry = words[int(place) - 1]
            n = meanings.get((entry[2], entry[3], entry[4])) if len(entry) == 5 else None
            if n is not None:
                seen.setdefault(word, Counter())[(entry[2], entry[3], n)] += 1
    out: dict[str, str] = {}
    for word, uses in seen.items():
        (ja, reading, n), _ = min(uses.items(), key=lambda kv: (-kv[1], kv[0]))
        out[word] = f"{ja}={reading}={n}"
    return out


def shard_of(word: str, shards: int) -> int:
    """The file a word's row is in: from the word alone, so a new word changes one file."""
    return zlib.crc32(word.encode("utf-8")) % shards


def shards(rows: dict[str, str], count: int) -> dict[int, dict[str, str]]:
    out: dict[int, dict[str, str]] = {}
    for word, row in rows.items():
        out.setdefault(shard_of(word, count), {})[word] = row
    return out


# ── the hand-written chat list (data/chat/) ──────────────────────────────────

FOLDER = "chat"
WORDS_JA = "words-ja.jsonl"
WORDS_EN = "words-en.jsonl"
PHRASES = "phrases.jsonl"
DOTS = ("·", "・")  # the phrase mark, in either language


@dataclass
class ChatList:
    words_ja: dict[str, tuple[str, str]]  # word → (reading, meaning)
    words_en: dict[str, str]  # lower-case word → its Japanese
    phrases: list[dict[str, Any]]  # {id, topic, en, ja}, by id


def _rows(path: Path) -> Iterable[tuple[str, dict[str, Any]]]:
    if not path.is_file():
        return
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        where = f"{path.name}:{n}"
        try:
            rec = json.loads(line)
        except json.JSONDecodeError as e:
            raise ValueError(f"{where}: not JSON ({e.msg})") from e
        if not isinstance(rec, dict):
            raise ValueError(f"{where}: a line is one JSON object")
        if not isinstance(rec.get("provenance"), dict) or not rec["provenance"]:
            raise ValueError(f"{where}: provenance is required")
        # the checks every store's provenance passes: its class, its source, its date, a machine line's model
        problems = model.provenance_problems(rec["provenance"], where)
        if problems:
            raise ValueError(f"{where}: provenance: {problems[0]}")
        yield where, rec


def _texts(where: str, rec: dict[str, Any], *fields: str) -> list[str]:
    out = []
    for f in fields:
        value = rec.get(f)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{where}: {f} is required")
        if "\t" in value or "\n" in value:
            raise ValueError(f"{where}: {f} holds a tab or a line break")
        out.append(value)
    return out


def load(root: Path) -> ChatList | None:
    """The chat list under `<root>/chat/`, checked: every row has its fields and provenance, no word and no
    phrase is listed twice, an English word is lower case, a phrase holds no phrase mark, and no phrase's
    English or Japanese starts with another's (the addon reads a marked phrase from its first character).
    → None when the folder does not exist."""
    folder = root / FOLDER
    if not folder.is_dir():
        return None
    words_ja: dict[str, tuple[str, str]] = {}
    for where, rec in _rows(folder / WORDS_JA):
        word, reading, meaning = _texts(where, rec, "word", "reading", "meaning")
        if word in words_ja:
            raise ValueError(f"{where}: {word!r} is listed twice")
        words_ja[word] = (reading, meaning)
    words_en: dict[str, str] = {}
    for where, rec in _rows(folder / WORDS_EN):
        word, ja = _texts(where, rec, "word", "ja")
        if word != word.lower():
            raise ValueError(f"{where}: {word!r} is not lower case")
        if word in words_en:
            raise ValueError(f"{where}: {word!r} is listed twice")
        words_en[word] = ja
    phrases: list[dict[str, Any]] = []
    ids: set[int] = set()
    said: dict[str, str] = {}  # a phrase's text as the addon compares it → where it is
    for where, rec in _rows(folder / PHRASES):
        topic, en, ja = _texts(where, rec, "topic", "en", "ja")
        id_ = rec.get("id")
        if not isinstance(id_, int) or isinstance(id_, bool) or id_ < 1:
            raise ValueError(f"{where}: id is a whole number from 1")
        if any(dot in en + ja for dot in DOTS):
            raise ValueError(f"{where}: a phrase holds the phrase mark (a middle dot)")
        if id_ in ids or en.lower() in said or ja in said:
            raise ValueError(f"{where}: phrase {id_} ({en!r}) is listed twice")
        ids.add(id_)
        said[en.lower()] = where
        said[ja] = where
        phrases.append({"id": id_, "topic": topic, "en": en, "ja": ja})
    texts = sorted(said)
    # sorted: a text that starts another is right before one it starts
    for a, b in zip(texts, texts[1:], strict=False):
        if b.startswith(a):
            raise ValueError(f"{said[b]}: {b!r} starts with the phrase {a!r} ({said[a]})")
    phrases.sort(key=lambda p: p["id"])
    return ChatList(words_ja, words_en, phrases)


def game_english_clashes(chat: ChatList, game_english: Iterable[str]) -> list[str]:
    """The phrases, and the chat words of several words, that are a whole line of the game's own English
    (compared without case or outer spaces). One word is never a clash: single English words may ship."""
    lines = {line.strip().lower() for line in game_english if isinstance(line, str)}
    out = [f"phrase {p['id']}: {p['en']}" for p in chat.phrases if p["en"].strip().lower() in lines]
    out += [f"word: {w}" for w in sorted(chat.words_en) if " " in w and w in lines]
    return out
