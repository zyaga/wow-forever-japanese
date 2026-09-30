"""Readings (ADR-036): the whole-word readings shown when a player hovers a Japanese word.

One record per shipped Japanese line, stored apart from the translation under `data/reading/<type>/`:

    {"id": 456, "field": "description", "ja_hash": "<16 hex>",
     "words": [["御機嫌よう", "ごきげんよう"], ["倒して", "たおして", "倒す", "たおす", "defeat"], …],
     "provenance": {"class": "machine", "model": "…", "source": "readings@<batch>", "imported": "YYYY-MM-DD"}}

`words` are in reading order; each is found in the Japanese after the previous one. An entry may also
carry the word's dictionary form, its reading and its meaning in this sentence (the word popup). The
Japanese itself is never copied or changed. `ja_hash` is the hash of the exact Japanese the words were
written for: when the translation changes, the reading is stale: reported by `validate`, left out of the
generated Lua.
Pure: no disk.
"""

from __future__ import annotations

import re
from typing import Any

from wfj.core import model
from wfj.core.hashing import key as hash_key
from wfj.emit.lua_writer import shipped

# The types whose text the addon can show readings on: quest window / quest map fields, gossip greetings,
# the UI dictionary (ADR-041), hoverable where a plain-text window label shows one of its strings, and
# book / letter pages (ADR-044), stored by page id, shipped under the page's English hash.
TYPES: dict[str, list[str]] = {
    "quest": model.FIELDS["quest"],
    "gossip": model.FIELDS["gossip"],
    "ui": model.FIELDS["ui"],
    "book": model.FIELDS["book"],
}
KEYS = ("id", "field", "ja_hash", "words", "provenance")
PROVENANCE_CLASSES = ("machine", "correction")

# CJK ideographs (unified + extension A) and the repeat mark 々: what makes a word need a reading.
_KANJI = re.compile(r"[㐀-䶿一-鿿々]")
# hiragana, katakana, the long-vowel mark
_KANA = re.compile(r"^[ぁ-ゖァ-ヺー]+$")
_ASCII = re.compile(r"[\x00-\x7f]")
_HEX16 = re.compile(r"^[0-9a-f]{16}$")


def needs_reading(ja: str) -> bool:
    """The Japanese holds a kanji: a line that should carry readings."""
    return _KANJI.search(ja) is not None


# Kana that never make a word of their own: the particles and copula the batch rules
# leave out. A line whose only kana are these, between names or placeholders ("TyrandeとRemulos", "%sの%s"),
# has nothing to annotate.
_BARE = frozenset(
    ["は", "が", "を", "に", "で", "と", "の", "へ", "も", "や", "か", "よ", "ね", "な"]
    + ["から", "まで", "だ", "です", "ー"]
)
_KANA_RUN = re.compile(r"[ぁ-ゖァ-ヺー]+")


def holds_escape(ja: str) -> bool:
    """A line with a WoW escape sequence (`|c` colour, `|n`, a texture): the reading box refuses it, so it
    takes no readings and is never owed one."""
    return "|" in ja


def annotatable(ja: str) -> bool:
    """The Japanese holds a kanji, or a run of kana that is more than a bare particle: a line a word
    list can annotate. An English-only line (a quest title that stays a name), or names joined by a particle,
    has nothing: the export leaves it out and validate does not count it owed."""
    if _KANJI.search(ja):
        return True
    return any(run not in _BARE for run in _KANA_RUN.findall(ja))


_HTML = re.compile(r"<html", re.IGNORECASE)


def html_page(type_: str, ja: str) -> bool:
    """A book page written as HTML (ADR-044) keeps the client's SimpleHTML, which cannot say where a
    word sits, so it never shows the word card: no reading is written for it and it is never owed one."""
    return type_ == "book" and _HTML.search(ja) is not None


def ja_hash(ja: str) -> str:
    """The hash that pins a reading to its Japanese: the addon's hash primitive over the text as stored."""
    return hash_key(ja)


def record(
    id_: int | str, field: str, ja: str, words: list[list[str]], prov: dict[str, Any]
) -> dict[str, Any]:
    """A reading record in key order (deterministic JSONL)."""
    pairs = [list(w) for w in words]
    return {"id": id_, "field": field, "ja_hash": ja_hash(ja), "words": pairs, "provenance": prov}


MEANING_MAX = 60  # the popup wraps a meaning inside its width; longer is a batch mistake
# control characters (a tab separates the generated row's fields) and "|" (starts a WoW escape)
_MEANING_BAD = re.compile(r"[\x00-\x1f\x7f|]")


def word_problems(ja: str, words: Any) -> list[str]:
    """Problems with `words` against the Japanese they annotate (empty = fine). An entry is
    [word, reading] or, for the word popup, [word, reading, dictionary form, its reading, meaning]:
    the dictionary form of the whole word as the sentence uses it (食べている → 食べる) and a short English
    meaning for this sentence. Every word must sit in `ja` after the previous one, hold no ASCII character
    (names stay English; and the generated row packs words with " " and "="), and carry a
    kana-only reading. A word holds a kanji, or is all kana with itself as its reading and a meaning
    (it is listed for the popup only)."""
    if not isinstance(words, list) or not words:
        return ["words must be a non-empty list of [word, reading] entries"]
    p: list[str] = []
    cursor = 0
    for n, entry in enumerate(words, 1):
        if not (isinstance(entry, list) and len(entry) in (2, 5) and all(isinstance(x, str) for x in entry)):
            p.append(f"word {n}: must be [word, reading] or [word, reading, dict. form, reading, meaning]")
            continue
        word, reading = entry[0], entry[1]
        if not word or not reading:
            p.append(f"word {n}: word and reading must be non-empty")
            continue
        if _ASCII.search(word):
            p.append(f"word {n} {word!r}: holds an ASCII character (names get no reading)")
        if not _KANJI.search(word) and not (_KANA.match(word) and reading == word and len(entry) == 5):
            p.append(f"word {n} {word!r}: has no kanji; a kana word needs itself as reading and a meaning")
        if not _KANA.match(reading):
            p.append(f"word {n} {word!r}: reading {reading!r} is not kana")
        if len(entry) == 5:
            p += [f"word {n} {word!r}: {x}" for x in meaning_problems(entry[2], entry[3], entry[4])]
        at = ja.find(word, cursor)
        if at < 0:
            p.append(f"word {n} {word!r}: not found in the Japanese after the previous word")
        else:
            cursor = at + len(word)
    return p


def meaning_problems(lemma: str, lemma_reading: str, meaning: str) -> list[str]:
    """A word's dictionary form, its reading and its meaning in the sentence."""
    p: list[str] = []
    if not lemma or _ASCII.search(lemma) or _MEANING_BAD.search(lemma):
        p.append(f"dictionary form {lemma!r} must be non-empty Japanese")
    if not _KANA.match(lemma_reading):
        p.append(f"dictionary form reading {lemma_reading!r} is not kana")
    if not meaning.strip() or meaning != meaning.strip() or _MEANING_BAD.search(meaning):
        p.append(f"meaning {meaning!r} must be one trimmed line without '|' or control characters")
    elif len(meaning) > MEANING_MAX:
        p.append(f"meaning is {len(meaning)} characters (max {MEANING_MAX})")
    return p


def provenance_problems(prov: Any) -> list[str]:
    if not isinstance(prov, dict):
        return ["provenance must be an object"]
    if prov.get("class") not in PROVENANCE_CLASSES:
        return [f"provenance.class {prov.get('class')!r} not in {PROVENANCE_CLASSES}"]
    return model.provenance_problems(prov, "provenance")


def record_problems(type_: str, rec: Any) -> list[str]:
    """Shape problems of one record (the words are checked against the Japanese separately)."""
    if type_ not in TYPES:
        return [f"unknown reading type {type_!r}"]
    if not isinstance(rec, dict):
        return ["a reading record must be an object"]
    p: list[str] = []
    missing = [k for k in KEYS if k not in rec]
    extra = sorted(set(rec) - set(KEYS))
    if missing:
        p.append(f"missing keys {missing}")
    if extra:
        p.append(f"unexpected keys {extra}")
    id_ = rec.get("id")
    if type_ in model.HASH_KEYED:
        if not (isinstance(id_, str) and _HEX16.match(id_)):
            p.append(f"{type_} id must be a 16-hex key")
    elif type_ == "ui":  # the UI dictionary's own key (ADR-014)
        if not (isinstance(id_, str) and model.UI_KEY_RE.fullmatch(id_)):
            p.append("ui id must be a UI string key")
    elif not (isinstance(id_, int) and not isinstance(id_, bool) and id_ > 0):
        p.append("id must be a positive int")
    if rec.get("field") not in TYPES[type_]:
        p.append(f"field {rec.get('field')!r} not in {TYPES[type_]}")
    if not (isinstance(rec.get("ja_hash"), str) and _HEX16.match(rec["ja_hash"])):
        p.append("ja_hash must be 16 hex chars")
    if "provenance" in rec:
        p += provenance_problems(rec["provenance"])
    return p


def shipped_japanese(lines: list[dict[str, Any]]) -> dict[tuple[int | str, str], str]:
    """(id, field) → the Japanese the addon ships for it (the translation store's shipped lines)."""
    return {(ln["id"], ln["field"]): ln["ja"] for ln in lines if shipped(ln)}


def check(
    type_: str, records: list[dict[str, Any]], japanese: dict[tuple[int | str, str], str]
) -> dict[str, Any]:
    """Every record of one type against the shipped Japanese.
    → {"problems": [str], "stale": [(id, field)], "current": [record]}; `current` is what ships. A record
    whose line no longer ships (rejected, withdrawn) counts as stale too: reported, not generated, and it
    comes back when the line ships again with the same Japanese."""
    problems: list[str] = []
    stale: list[tuple[int | str, str]] = []
    current: list[dict[str, Any]] = []
    seen: set[tuple[int | str, str]] = set()
    for rec in records:
        where = f"reading {type_} {rec.get('id') if isinstance(rec, dict) else '?'}/" + (
            f"{rec.get('field')}" if isinstance(rec, dict) else "?"
        )
        shape = record_problems(type_, rec)
        if shape:
            problems += [f"{where}: {x}" for x in shape]
            continue
        k = (rec["id"], rec["field"])
        if k in seen:  # duplicates are reported, never resolved silently
            problems.append(f"{where}: duplicate record")
            continue
        seen.add(k)
        ja = japanese.get(k)
        if ja is None or rec["ja_hash"] != ja_hash(ja):
            stale.append(k)  # the translation changed since the words were written
            continue
        # the addon never covers an HTML page, so its reading would never show
        if html_page(type_, ja):
            problems.append(f"{where}: an HTML book page takes no reading")
            continue
        bad = word_problems(ja, rec["words"])
        if bad:
            problems += [f"{where}: {x}" for x in bad]
            continue
        current.append(rec)
    return {"problems": problems, "stale": stale, "current": current}


def addon_keyed(
    type_: str, records: list[dict[str, Any]], lines: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """The current records of one type as the addon looks them up. Every type but book is keyed in
    the addon as in `data/`. A book page is found by its live English (the client exposes no page id), so its
    reading ships under `english.hash`, the key `lua_writer.keyed_rows` writes the page's Japanese under.
    Pages sharing one English share one Japanese row (the lowest page id's text; a stale page gives way to a
    current one), so only that page's reading ships under the key; the others' readings are valid but unused.
    → the records to ship, book ids replaced by the 16-hex key."""
    if type_ != "book":
        return records
    ship = [ln for ln in lines if shipped(ln) and ln.get("english") and ln["english"].get("hash")]
    current = {str(ln["english"]["hash"]) for ln in ship if ln["status"] != "stale"}
    owner: dict[int, str] = {}
    taken: set[str] = set()
    for ln in sorted(ship, key=lambda ln: ln["id"]):
        key = str(ln["english"]["hash"])
        if key in taken or (ln["status"] == "stale" and key in current):
            continue
        taken.add(key)
        owner[ln["id"]] = key
    return [rec | {"id": owner[rec["id"]]} for rec in records if rec["id"] in owner]
