"""wfj names collect|hearthstone|export|import|respell|check: Japanese names
(ADR-078; docs/architecture/data-model.md).

collect [--vmangos DB] [--tables DIR] [--date YYYY-MM-DD]
    Every English name the game shows gets a `data/name` line: item, spell and unit names from
    `data/english`, creature, object, area, faction and map names and creature titles from the VMaNGOS
    database when given, item name suffixes ("of the Monkey") and flight point names from the client tables
    in DIR (ItemNameDescription.csv, TaxiNodes.csv) when given, and every run of Latin letters in shipped
    quest, gossip, book, objective, area, item and spell Japanese and the voiced error lines. New names
    come in `missing`; ids are only added; nothing is removed or rewritten.
hearthstone JAJP.json ENUS.json --build BUILD [--date YYYY-MM-DD]
    Hearthstone's official Japanese (HearthstoneJSON card files, a build-time input): a missing name whose
    English is a card's name and whose Japanese is katakana takes that Japanese (class human, source
    hearthstone@BUILD); word pairs from card names that split into the same number of words go into the
    glossary. A `human` or `correction` name is never touched.
export --out DIR [--size N] [--hearthstone DIR]
    The missing names as batch files of N rows: {"id", "en", "kinds", "prose", "hints", "hearthstone",
    "parts"} (parts: a flight point's places, each [English, Japanese, reading] or null);
    a hint is [word, Japanese, "name" (keep it) | "word" (the usual Japanese of an ordinary word)].
    --skip FILE leaves out the ids of a batch still being drafted. --redo [--redo-ids FILE]: a fix round
    instead, the drafted machine names that spell a checked glossary word another way and the ids in FILE,
    each with its "current" [Japanese, reading] and the "problem".
import BATCH.jsonl --model MODEL --batch NAME [--date YYYY-MM-DD] [--dry-run]
    Rows {"id", "ja", "reading", "free", "words"} fill missing or machine names; `words` ([[English,
    Japanese]]) adds glossary words. A row with a problem is rejected with its reason.
export-words --out DIR [--size N]
    The capitalised words of missing names that are neither in the glossary nor ordinary English (the game's
    prose never writes them in lower case), each with up to three names that carry it: {"en", "count",
    "examples"}. Drafting them first keeps one spelling per word across every name batch.
import-words BATCH.jsonl --model MODEL --batch NAME [--date YYYY-MM-DD] [--dry-run]
    Rows {"en", "ja"} (a row whose "ja" is empty is a word that is not a name: a tag or a numeral, skipped)
    add checked glossary words; a word already in the glossary is kept and reported. --hint-only adds them
    unchecked: ordinary words with more than one sense (Chest, Iron) are offered as hints, not enforced.
check
    Every name and word line's shape, and the one-spelling check. `validate` runs the same.
export-respell --out DIR [--size N]
    The words with no katakana spelling that a translated name is built from, each once in lower case:
    {"en", "count", "examples"}. The round that spells every name from its English starts here.
import-respell BATCH.jsonl --model MODEL --batch NAME [--date YYYY-MM-DD] [--dry-run]
    Rows {"en", "ja"}: a word's translated Japanese is replaced by its katakana and a word with no line gets
    one. A spelling that is not katakana, or that differs from the katakana a word already has, is refused.
    --replace (a fix round) lets a row change the katakana a word has; a word a person wrote is kept.
learn-spellings [--dry-run]
    A word with no katakana spelling takes it from a name that is already spelled out, when that name has
    as many parts as words. Run before export-respell, so only the words no name spells are drafted.
respell [--date YYYY-MM-DD] [--dry-run]
    Every name a person did not write is written again from the spellings of its words, its reading with it
    (`wfj.core.respell`); a name that already equals its spelling does not change. A name a person wrote and
    a name with nothing to spell stay as they are. Nothing is written while any name has a word with no
    spelling.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import re
import sys
from collections import Counter, defaultdict
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from wfj.cmd.readings import read_batch
from wfj.core import names
from wfj.core import respell as spell
from wfj.emit.lua_writer import shipped
from wfj.io import vmangos
from wfj.io.jsonl_store import Store, dumps
from wfj.io.names_store import load_lines, load_words, save_lines, save_words
from wfj.paths import data_root

PROSE_TYPES = ("quest", "gossip", "book", "objective", "area", "item", "spell")
ENGLISH_NAMES = ("item", "spell", "unit")  # data/english types whose `name` field is a name kind too
_BATCH_RE = re.compile(r"^[0-9A-Za-z._-]{4,64}$")
_JA_SPLIT = re.compile(r"[・　 ]+")
_JA_EDGE = "！？!?。、「」『』（）()…"
# a part that is a phrase or holds markup rather than a word's Japanese
_JA_ODD = re.compile(r"[\x00-\x7f！？。、「」『』（）：]")


def english_names(root: Path) -> dict[str, dict[str, set[int]]]:
    """{English name: {kind: ids}} from data/english item, spell and unit names."""
    out: dict[str, dict[str, set[int]]] = defaultdict(lambda: defaultdict(set))
    english = Store(root, english=True)
    for kind in ENGLISH_NAMES:
        for ln in english.load(kind):
            if ln["field"] == "name" and ln["en"].strip():
                out[ln["en"]][kind].add(int(ln["id"]))
    return out


def prose_lines(root: Path) -> dict[str, str]:
    """{line key: shipped Japanese} for the text names are read from (prose and tooltips), and the voiced
    error lines."""
    from wfj.cmd.voice_make import error_lines

    store = Store(root)
    out = {
        f"{t}:{ln['id']}:{ln['field']}": ln["ja"] for t in PROSE_TYPES for ln in store.load(t) if shipped(ln)
    }
    out.update(error_lines(root))
    return out


def prose_names(root: Path) -> set[str]:
    return {run for ja in prose_lines(root).values() for run in names.latin_runs(ja)}


def table_names(folder: Path) -> dict[str, dict[int, str]]:
    """{kind: {id: English}} from a client's table folder: the item name suffixes (ItemNameDescription rows
    the client writes after an item's name, "of the Monkey") and the flight point names (TaxiNodes, without
    the "Quest Path" rows a flight master never lists). A table the folder lacks gives nothing."""
    out: dict[str, dict[int, str]] = {"suffix": {}, "taxi": {}}
    for kind, table, column, keep in (
        ("suffix", "ItemNameDescription", "Description_lang", lambda en: en.startswith("of ")),
        ("taxi", "TaxiNodes", "Name_lang", lambda en: not en.startswith("Quest Path")),
    ):
        path = folder / f"{table}.csv"
        if path.is_file():
            with path.open(encoding="utf-8", newline="") as f:
                for row in csv.DictReader(f):
                    en = row[column].strip()
                    if en and keep(en):
                        out[kind][int(row["ID"])] = en
    return out


def collect(root: Path, db: Path | None, today: str, tables: Path | None = None) -> dict[str, int]:
    seen = english_names(root)
    counts = {f"english {k}": sum(1 for v in seen.values() if k in v) for k in ENGLISH_NAMES}
    sources = []
    if db is not None:
        sources.append(("vmangos", vmangos.read_names(db)))
    if tables is not None:
        sources.append(("tables", table_names(tables)))
    for source, by_kind in sources:
        for kind, rows in by_kind.items():
            for i, en in rows.items():
                seen.setdefault(en, defaultdict(set))[kind].add(i)
            counts[f"{source} {kind}"] = len(set(rows.values()))
    prose = prose_names(root)
    counts["prose"] = len(prose)
    lines, added = names.merge(load_lines(root), seen, prose, today)
    save_lines(root, lines)
    counts["new lines"] = added
    counts["lines"] = len(lines)
    counts["missing"] = sum(1 for ln in lines if ln["status"] == "missing")
    return counts


def read_cards(path: Path) -> dict[int, str]:
    with path.open(encoding="utf-8") as f:
        cards = json.load(f)
    return {int(c["dbfId"]): c["name"] for c in cards if c.get("dbfId") and isinstance(c.get("name"), str)}


def hearthstone_pairs(ja_path: Path, en_path: Path) -> list[tuple[str, str]]:
    """(English card name, Japanese card name) for every card both files name."""
    ja, en = read_cards(ja_path), read_cards(en_path)
    return [(en[i], ja[i]) for i in sorted(ja.keys() & en.keys()) if en[i].strip() and ja[i].strip()]


def hearthstone_words(pairs: Sequence[tuple[str, str]]) -> tuple[dict[str, Counter[str]], list[str]]:
    """{English word: Counter(Japanese forms)} from card names whose English words (stop words aside) and
    Japanese parts (split on ・ and spaces) are as many; the conflicting words are reported."""
    forms: dict[str, Counter[str]] = defaultdict(Counter)
    for en, ja in pairs:
        ws = [w for w in names.words_of(en) if not names.stopword(w)]
        parts = [p.strip(_JA_EDGE) for p in _JA_SPLIT.split(ja) if p.strip(_JA_EDGE)]
        if len(ws) != len(parts) or len(ws) < 1:
            continue
        for w, p in zip(ws, parts, strict=True):
            if w[:1].isupper() and not _JA_ODD.search(p):
                forms[w][p] += 1
    conflicts = [
        f"{w}: {', '.join(f'{p} ×{n}' for p, n in c.most_common())}"
        for w, c in sorted(forms.items())
        if len(c) > 1
    ]
    return forms, conflicts


def common_words(root: Path) -> set[str]:
    """Every word the game's English prose writes in lower case: an ordinary English word, not a name, so the
    glossary does not hold its spelling to every name ("Green", "Deep")."""
    english = Store(root, english=True)
    out: set[str] = set()
    for type_ in ("quest", "gossip", "book"):
        for ln in english.load(type_):
            out.update(re.findall(r"\b[a-z][a-z']+\b", ln["en"]))
    return out


def apply_hearthstone(root: Path, pairs: Sequence[tuple[str, str]], build: str, today: str) -> dict[str, int]:
    common = common_words(root)
    prov = {"class": "human", "source": f"hearthstone@{build}", "imported": today}
    whole: dict[str, Counter[str]] = defaultdict(Counter)
    for en, ja in pairs:
        whole[names.norm(en)][ja] += 1
    lines = load_lines(root)
    filled = 0
    for ln in lines:
        c = whole.get(ln["en"])
        if ln["status"] != "missing" or not c:
            continue
        ja = c.most_common(1)[0][0]
        if names.KATAKANA.match(ja):
            ln.update(ja=ja, reading=names.hiragana(ja), status="trusted", provenance=dict(prov))
            filled += 1
    save_lines(root, lines)
    forms, conflicts = hearthstone_words(pairs)
    words = {w["en"]: w for w in load_words(root)}
    added = 0
    for w, c in sorted(forms.items()):
        if w in words:
            continue
        ja, n = c.most_common(1)[0]
        steady = n >= 2 and n / sum(c.values()) >= 0.8
        if steady and w.lower() not in common and names.KATAKANA.match(ja):
            # only a name Hearthstone spells the same way again and again; a one-off pair is too often a
            # card's own phrase ("アライアンスのために") to hold every name to it
            words[w] = {"en": w, "ja": ja, "check": True, "provenance": dict(prov)}
            added += 1
    save_words(root, words.values())
    for line in conflicts:
        print(f"names hearthstone: word with several forms, kept the most frequent: {line}", file=sys.stderr)
    return {"names filled": filled, "words added": added, "word conflicts": len(conflicts)}


def redo_rows(root: Path, ids: set[str]) -> dict[str, str]:
    """{name id: why it is drafted again} for the machine names a fix round redoes: every one that spells a
    checked glossary word another way, and the ids asked for."""
    glossary = names.checked_glossary(load_words(root))
    lines = load_lines(root)
    out = {i: "asked to align with the rest" for i in ids}
    for ln in lines:
        bad = names.misspelled(ln, glossary) if ln["provenance"]["class"] == "machine" else []
        if bad:
            out[ln["id"]] = "; ".join(f"{w} is {ja}" for w, ja in bad)
    for group in names.case_groups(lines):
        same = " / ".join(f"{ln['en']} {ln['ja']}" for ln in group)
        for ln in group:
            if ln["provenance"]["class"] == "machine":
                out[ln["id"]] = (out.get(ln["id"], "") + "; " if ln["id"] in out else "") + (
                    f"one name in other case, read one way: {same} (or free if this one is an ordinary word)"
                )
    return out


def draft_provenance(model_id: str, kind: str, batch: str, today: str) -> dict[str, str]:
    """The provenance of a model-drafted batch row (`draft-<kind>-<batch>@<date>`, ADR-014)."""
    if not _BATCH_RE.match(batch):
        raise ValueError(f"--batch {batch!r}: 4 to 64 of letters, digits, . _ -")
    return {
        "class": "machine",
        "model": model_id,
        "source": f"draft-{kind}-{batch}@{today}",
        "imported": today,
    }


def write_batches(out: Path, rows: Sequence[dict[str, Any]], size: int, stem: str) -> int:
    """`<stem>-NNN.jsonl` files of `size` rows each."""
    out.mkdir(parents=True, exist_ok=True)
    for n, start in enumerate(range(0, len(rows), size)):
        text = "".join(dumps(r) + "\n" for r in rows[start : start + size])
        (out / f"{stem}-{n:03d}.jsonl").write_text(text, encoding="utf-8")
    return len(rows)


def export(
    root: Path,
    out: Path,
    size: int,
    hs: Path | None,
    skip: set[str] = frozenset(),
    redo: dict[str, str] | None = None,
) -> int:
    whole: dict[str, str] = {}
    if hs is not None:
        for en, ja in hearthstone_pairs(hs / "jaJP.json", hs / "enUS.json"):
            if not names.has_latin(ja):  # a card Hearthstone left in English is no Japanese
                whole.setdefault(names.norm(en), ja)
    words = {w["en"]: w for w in load_words(root)}
    lines = load_lines(root)
    by_id = {ln["id"]: ln for ln in lines}
    rows = []
    for ln in lines:
        if ln["id"] in skip or (ln["id"] not in redo if redo is not None else ln["status"] != "missing"):
            continue
        row: dict[str, Any] = {
            "id": ln["id"],
            "en": ln["en"],
            "kinds": {k: len(v) for k, v in ln["ids"].items()},
            "prose": ln["prose"],
            # [word, Japanese, "name"] must be kept; [word, Japanese, "word"] is the usual Japanese of an
            # ordinary word, to change when its sense here differs
            "hints": [
                [w, words[w]["ja"], "name" if words[w]["check"] else "word"]
                for w in dict.fromkeys(names.words_of(ln["en"]))
                if w in words
            ],
        }
        if ln["en"] in whole:
            row["hearthstone"] = whole[ln["en"]]
        if "taxi" in ln["ids"]:
            # a flight point is places joined by ", ": each part's own line, so it reads as the part alone
            parts = [by_id.get(names.name_id(p)) for p in ln["en"].split(", ")]
            row["parts"] = [[p["en"], p["ja"], p["reading"]] if p else None for p in parts]
        if redo is not None:
            row["current"] = [ln["ja"], ln["reading"]]
            row["problem"] = redo[ln["id"]]
        rows.append(row)
    return write_batches(out, rows, size, "batch")


def import_batch(
    root: Path, path: Path, model_id: str, batch: str, today: str, dry_run: bool
) -> tuple[int, list[str]]:
    prov = draft_provenance(model_id, "names", batch, today)
    lines = {ln["id"]: ln for ln in load_lines(root)}
    words = {w["en"]: w for w in load_words(root)}
    rejected: list[str] = []
    written = 0
    for row in read_batch(path):
        ln = lines.get(row.get("id")) if isinstance(row.get("id"), str) else None
        if ln is None:
            rejected.append(f"{row.get('id')}: no such name")
            continue
        if ln["provenance"]["class"] in ("human", "correction"):
            rejected.append(f"{ln['en']!r}: has a {ln['provenance']['class']} Japanese, kept")
            continue
        new = dict(
            ln,
            ja=row.get("ja", ""),
            reading=row.get("reading", ""),
            free=row.get("free", False),
            status="trusted",
            provenance=dict(prov),
        )
        bad = names.line_problems(new)
        if bad:
            rejected.append(f"{ln['en']!r}: {'; '.join(bad)}")
            continue
        lines[ln["id"]] = new
        written += 1
        for pair in row.get("words") or ():
            if not (isinstance(pair, list) and len(pair) == 2):
                rejected.append(f"{ln['en']!r}: word {pair!r} is not [English, Japanese]")
                continue
            w = {"en": pair[0], "ja": pair[1], "check": True, "provenance": dict(prov)}
            wrong = names.word_problems(w)
            if wrong:
                rejected.append(f"{ln['en']!r}: word {pair!r}: {'; '.join(wrong)}")
            elif pair[0] in words:
                # a glossary word stays as it is: a hint-only word must not turn into a checked one
                if words[pair[0]]["ja"] != pair[1]:
                    rejected.append(f"word {pair[0]!r}: already {words[pair[0]]['ja']!r}, not {pair[1]!r}")
            else:
                words[pair[0]] = w
    if not dry_run:
        save_lines(root, lines.values())
        save_words(root, words.values())
    return written, rejected


def glossary_candidates(root: Path, *, vocabulary: int = 0) -> dict[str, list[str]]:
    """{word: names that carry it} for the capitalised words of missing names with no glossary entry that the
    game's prose never writes in lower case. `vocabulary` N > 0: instead every word with no entry, ordinary
    English included, that N or more names carry (gear, ranks, spell words: one Japanese each everywhere)."""
    common = set() if vocabulary else common_words(root)
    have = {w["en"] for w in load_words(root)}
    out: dict[str, list[str]] = defaultdict(list)
    for ln in load_lines(root):
        if ln["status"] != "missing" and not vocabulary:
            continue
        for w in dict.fromkeys(names.words_of(ln["en"])):
            if (
                w[:1].isalpha()
                and w.isascii()
                and (vocabulary or w[:1].isupper())
                and w.lower() not in common
                and w not in have
                and not names.stopword(w)
                and " " not in w
            ):
                out[w].append(ln["en"])
    if vocabulary:
        out = defaultdict(list, {w: ns for w, ns in out.items() if len(ns) >= vocabulary})
    return out


def export_words(root: Path, out: Path, size: int, vocabulary: int = 0) -> int:
    cands = glossary_candidates(root, vocabulary=vocabulary)
    rows = [{"en": w, "count": len(ns), "examples": ns[:5]} for w, ns in sorted(cands.items())]
    return write_batches(out, rows, size, "words")


def import_words(
    root: Path, path: Path, model_id: str, batch: str, today: str, dry_run: bool, hint_only: bool = False
) -> tuple[int, list[str]]:
    prov = draft_provenance(model_id, "names", batch, today)
    words = {w["en"]: w for w in load_words(root)}
    rejected: list[str] = []
    written = 0
    for row in read_batch(path):
        en, ja = row.get("en"), row.get("ja", "")
        if not ja:
            continue
        w = {"en": en, "ja": ja, "check": not hint_only, "provenance": dict(prov)}
        bad = names.word_problems(w)
        if bad:
            rejected.append(f"word {en!r}: {'; '.join(bad)}")
        elif en in words:  # kept as it is, checked or a hint
            if words[en]["ja"] != ja:
                rejected.append(f"word {en!r}: already {words[en]['ja']!r}, kept")
        else:
            words[en] = w
            written += 1
    if not dry_run:
        save_words(root, words.values())
    return written, rejected


def prose_readings(root: Path) -> dict[str, set[str]]:
    """{word with kanji: its readings} from every reading record (quest, NPC, interface and book text), as
    written and in its dictionary form. Names are held to them: a word reads one way."""
    out: dict[str, set[str]] = defaultdict(set)
    rstore = Store(root / "reading")
    for type_ in ("quest", "gossip", "ui", "book"):
        for rec in rstore.load(type_):
            for w in rec.get("words") or ():
                for word, reading in zip(w[0:4:2], w[1:4:2], strict=False):
                    if word != reading:
                        out[word].add(reading)
    return out


def problems(root: Path) -> list[str]:
    lines, words = load_lines(root), load_words(root)
    out = [f"name {ln.get('en')!r}: {p}" for ln in lines for p in names.line_problems(ln)]
    # duplicates are reported, never resolved silently (a merge that kept both sides of a shard)
    ids = Counter(ln.get("id") for ln in lines)
    out += [f"name {i}: {n} lines with one id" for i, n in sorted(ids.items()) if n > 1]
    twice = Counter(w.get("en") for w in words)
    out += [f"name word {en!r}: listed {n} times" for en, n in sorted(twice.items(), key=str) if n > 1]
    seen: dict[str, str] = {}
    for w in words:
        out.extend(f"name word: {p}" for p in names.word_problems(w))
        folded = str(w.get("en")).casefold()
        if w.get("check") and folded in seen and seen[folded] != w.get("ja"):
            out.append(
                f"name word {w['en']!r}: written twice (case aside), as {seen[folded]!r} and {w.get('ja')!r}"
            )
        if w.get("check"):
            seen.setdefault(folded, w.get("ja"))
    if not out:
        out.extend(f"name spelling: {p}" for p in names.spelling_problems(lines, words))
        out.extend(f"name case: {p}" for p in names.case_problems(lines))
        out.extend(f"name reading: {p}" for p in names.reading_problems(lines, prose_readings(root).get))
    return out


def _spellings(words: Sequence[dict[str, Any]]) -> dict[str, str]:
    """{casefolded word: its katakana} for every word that is spelled out. A word is one word whatever its
    case."""
    out: dict[str, str] = {}
    for w in words:
        if names.KATAKANA.match(w["ja"]):
            out.setdefault(w["en"].casefold(), w["ja"])
    return out


def _respelled(line: dict[str, Any]) -> bool:
    """A name that is left as it is: one a person wrote. A name already in katakana is still put together
    again: Japanese writes some of its own words in katakana (サソリ), and those are translations too."""
    return line["provenance"]["class"] in ("human", "correction")


def learn_spellings(root: Path, dry_run: bool) -> tuple[int, list[str]]:
    """Words take their spelling from the names that are already spelled out: a katakana name with as many
    parts as words gives each of its words a spelling (ザンダー・グッドビアード: Xandar, Goodbeard). Only a
    word with no katakana spelling takes one. A name whose part differs from the spelling its word already
    has is returned: that name will be written again from the word's spelling."""
    words = {w["en"]: w for w in load_words(root)}
    known = _spellings(list(words.values()))
    learned = 0
    differ: list[str] = []
    for ln in load_lines(root):
        if ln["status"] != "trusted" or not names.KATAKANA.match(ln["ja"]):
            continue
        ws, parts = spell.words(ln["en"]), ln["ja"].split("・")
        if len(ws) != len(parts) or " " in "".join(ws):
            continue
        for w, part in zip(ws, parts, strict=True):
            have = known.get(w.casefold())
            if have is None:
                same = [k for k in words if k.casefold() == w.casefold()]
                for k in same or [w]:
                    words[k] = {"en": k, "ja": part, "check": True, "provenance": dict(ln["provenance"])}
                known[w.casefold()] = part
                learned += 1
            elif have != part:
                differ.append(f"{ln['en']!r}: {w!r} is {part!r} here, {have!r} as a word")
    if not dry_run:
        save_words(root, words.values())
    return learned, differ


def export_respell(root: Path, out: Path, size: int) -> int:
    """The words with no katakana spelling that a translated name is built from, each once (lower case), with
    how many names carry it and a few of them."""
    known = _spellings(load_words(root))
    carried: dict[str, list[str]] = defaultdict(list)
    for ln in load_lines(root):
        if ln["status"] != "trusted" or _respelled(ln):
            continue
        for w in spell.assemble(ln["en"], known.get)[2]:
            carried[w.casefold()].append(ln["en"])
    rows = [{"en": w, "count": len(ns), "examples": sorted(ns)[:5]} for w, ns in sorted(carried.items())]
    return write_batches(out, rows, size, "respell")


def import_respell(  # noqa: PLR0913 - one batch file, its provenance, and the two ways to run it
    root: Path, path: Path, model_id: str, batch: str, today: str, dry_run: bool, replace: bool = False
) -> tuple[int, list[str]]:
    """Takes drafted spellings ({"en", "ja"}): a word's translated Japanese is replaced by its katakana and a
    word with no line gets one. A spelling that is not katakana, or that differs from the katakana a word
    already has, is refused: a word is spelled one way. `replace` (a fix round) lets a row change the
    katakana a word has, never a word a person wrote."""
    prov = draft_provenance(model_id, "names", batch, today)
    words = {w["en"]: w for w in load_words(root)}
    known = _spellings(list(words.values()))
    rejected: list[str] = []
    written = 0
    for row in read_batch(path):
        en, ja = row.get("en"), row.get("ja")
        if not isinstance(en, str) or not en or " " in en:
            rejected.append(f"word {en!r}: not one English word")
        elif not isinstance(ja, str) or not names.KATAKANA.match(ja):
            rejected.append(f"word {en!r}: {ja!r} is not katakana")
        elif known.get(en.casefold(), ja) != ja and not replace:
            rejected.append(f"word {en!r}: already {known[en.casefold()]!r}, not {ja!r}")
        elif known.get(en.casefold()) != ja:
            same = [k for k in words if k.casefold() == en.casefold()]
            if any(words[k]["provenance"]["class"] in ("human", "correction") for k in same):
                rejected.append(f"word {en!r}: written by a person, kept")
                continue
            for k in same or [en]:
                words[k] = {"en": k, "ja": ja, "check": True, "provenance": dict(prov)}
            known[en.casefold()] = ja
            written += 1
    if not dry_run:
        save_words(root, words.values())
    return written, rejected


def respell(root: Path, today: str, dry_run: bool) -> dict[str, int]:
    """Every translated name is written again from the spellings of its words (its reading with it). Nothing
    is written while any name has a word with no spelling."""
    known = _spellings(load_words(root))
    lines = load_lines(root)
    counts = {"respelled": 0, "kept": 0, "nothing to spell": 0, "word with no spelling": 0}
    out = []
    for ln in lines:
        if ln["status"] != "trusted" or _respelled(ln):
            counts["kept"] += 1
            out.append(ln)
            continue
        ja, reading, missing = spell.assemble(ln["en"], known.get)
        if missing:
            counts["word with no spelling"] += 1
            out.append(ln)
        elif ja is None:
            counts["nothing to spell"] += 1
            out.append(ln)
        elif (ja, reading) == (ln["ja"], ln["reading"]) and not ln["free"]:
            counts["kept"] += 1
            out.append(ln)
        else:
            counts["respelled"] += 1
            prov = {"class": "machine", "source": f"respell@{today}", "imported": today}
            out.append(dict(ln, ja=ja, reading=reading, free=False, provenance=prov))
    if counts["word with no spelling"]:
        counts["respelled"] = 0
    elif not dry_run:
        save_lines(root, out)
    return counts


def _parser(today: str) -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="wfj names")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("collect")
    c.add_argument("--vmangos")
    c.add_argument("--tables", help="a client's table folder (ItemNameDescription.csv, TaxiNodes.csv)")
    c.add_argument("--date", default=today)
    h = sub.add_parser("hearthstone")
    h.add_argument("ja")
    h.add_argument("en")
    h.add_argument("--build", required=True)
    h.add_argument("--date", default=today)
    e = sub.add_parser("export")
    e.add_argument("--out", required=True)
    e.add_argument("--size", type=int, default=1000)
    e.add_argument("--hearthstone")
    e.add_argument("--skip", action="append", default=[], help="a batch file whose ids are being drafted")
    e.add_argument(
        "--redo",
        action="store_true",
        help="a fix round: drafted names that spell a checked word another way, and --redo-ids",
    )
    e.add_argument("--redo-ids", help="a file of name ids (one per line) to draft again")
    i = sub.add_parser("import")
    i.add_argument("batch_file")
    i.add_argument("--model", required=True)
    i.add_argument("--batch", required=True)
    i.add_argument("--date", default=today)
    i.add_argument("--dry-run", action="store_true")
    ew = sub.add_parser("export-words")
    ew.add_argument("--out", required=True)
    ew.add_argument("--size", type=int, default=1000)
    ew.add_argument(
        "--vocabulary", type=int, default=0, help="every word N or more names carry, ordinary words too"
    )
    iw = sub.add_parser("import-words")
    iw.add_argument("batch_file")
    iw.add_argument("--model", required=True)
    iw.add_argument("--batch", required=True)
    iw.add_argument("--date", default=today)
    iw.add_argument("--dry-run", action="store_true")
    iw.add_argument(
        "--hint-only",
        action="store_true",
        help="ordinary words with several senses: a hint for drafting, not held to every name",
    )
    er = sub.add_parser("export-respell")
    er.add_argument("--out", required=True)
    er.add_argument("--size", type=int, default=1000)
    ir = sub.add_parser("import-respell")
    ir.add_argument("batch_file")
    ir.add_argument("--model", required=True)
    ir.add_argument("--batch", required=True)
    ir.add_argument("--date", default=today)
    ir.add_argument("--dry-run", action="store_true")
    ir.add_argument("--replace", action="store_true", help="a fix round: may change a katakana spelling")
    rs = sub.add_parser("respell")
    rs.add_argument("--date", default=today)
    rs.add_argument("--dry-run", action="store_true")
    ls = sub.add_parser("learn-spellings")
    ls.add_argument("--dry-run", action="store_true")
    sub.add_parser("check")
    return p


def _run_respell(a: argparse.Namespace, root: Path) -> int:
    dry = " (dry run)" if getattr(a, "dry_run", False) else ""
    if a.cmd == "export-respell":
        n = export_respell(root, Path(a.out), a.size)
        print(f"names export-respell: {n} words with no katakana spelling → {a.out}")
        return 0
    if a.cmd == "import-respell":
        n, rejected = import_respell(
            root, Path(a.batch_file), a.model, a.batch, a.date, a.dry_run, a.replace
        )
        for r in rejected:
            print(f"names import-respell: rejected {r}", file=sys.stderr)
        print(f"names import-respell: {n} words spelled, {len(rejected)} rejected{dry}")
        return 1 if rejected else 0
    if a.cmd == "learn-spellings":
        n, differ = learn_spellings(root, a.dry_run)
        print(f"names learn-spellings: {n} words spelled from names, {len(differ)} names differ{dry}")
        return 0
    counts = respell(root, a.date, a.dry_run)
    print("names respell: " + ", ".join(f"{k} {v}" for k, v in counts.items()) + dry)
    return 1 if counts["word with no spelling"] else 0


def run(argv: Sequence[str]) -> int:
    today = dt.date.today().isoformat()
    a = _parser(today).parse_args(list(argv))
    root = data_root()
    try:
        if a.cmd == "collect":
            counts = collect(
                root, Path(a.vmangos) if a.vmangos else None, a.date, Path(a.tables) if a.tables else None
            )
            print("names collect: " + ", ".join(f"{k} {v}" for k, v in counts.items()))
        elif a.cmd == "hearthstone":
            if not re.match(r"^\d{4,}$", a.build):
                raise ValueError(f"--build {a.build!r}: the HearthstoneJSON build number")
            counts = apply_hearthstone(root, hearthstone_pairs(Path(a.ja), Path(a.en)), a.build, a.date)
            print("names hearthstone: " + ", ".join(f"{k} {v}" for k, v in counts.items()))
        elif a.cmd == "export":
            skip = {
                json.loads(r)["id"]
                for f in a.skip
                for r in Path(f).read_text(encoding="utf-8").splitlines()
                if r
            }
            redo = None
            if a.redo:
                asked = set(Path(a.redo_ids).read_text(encoding="utf-8").split()) if a.redo_ids else set()
                redo = redo_rows(root, asked)
            n = export(root, Path(a.out), a.size, Path(a.hearthstone) if a.hearthstone else None, skip, redo)
            print(f"names export: {n} missing names → {a.out}")
        elif a.cmd == "export-words":
            n = export_words(root, Path(a.out), a.size, a.vocabulary)
            print(f"names export-words: {n} words → {a.out}")
        elif a.cmd == "import-words":
            n, rejected = import_words(
                root, Path(a.batch_file), a.model, a.batch, a.date, a.dry_run, a.hint_only
            )
            for r in rejected:
                print(f"names import-words: {r}", file=sys.stderr)
            print(
                f"names import-words: {n} words written, {len(rejected)} kept or rejected"
                + (" (dry run)" if a.dry_run else "")
            )
        elif a.cmd in ("export-respell", "import-respell", "respell", "learn-spellings"):
            return _run_respell(a, root)
        elif a.cmd == "import":
            n, rejected = import_batch(root, Path(a.batch_file), a.model, a.batch, a.date, a.dry_run)
            for r in rejected:
                print(f"names import: rejected {r}", file=sys.stderr)
            print(
                f"names import: {n} names written, {len(rejected)} rejected"
                + (" (dry run)" if a.dry_run else "")
            )
            return 1 if rejected else 0
        else:
            bad = problems(root)
            for b in bad:
                print(b, file=sys.stderr)
            print(f"names check: {len(bad)} problem(s)")
            return 1 if bad else 0
    except (ValueError, OSError, vmangos.VmangosError) as err:
        print(f"names {a.cmd}: {err}", file=sys.stderr)
        return 1
    return 0
