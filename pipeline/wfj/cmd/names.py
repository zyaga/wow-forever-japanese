"""wfj names collect|hearthstone|export|import|check: Japanese names (ADR-077; docs/architecture/data-model.md).

  collect [--vmangos DB] [--date YYYY-MM-DD]
      Every English name the game shows gets a `data/name` line: item, spell and unit names from
      `data/english`, creature, object, area, faction and map names from the VMaNGOS database when given, and
      every run of Latin letters in shipped quest, gossip, book, objective and area Japanese and the voiced
      error lines. New names come in `missing`; ids are only added; nothing is removed or rewritten.
  hearthstone JAJP.json ENUS.json --build BUILD [--date YYYY-MM-DD]
      Hearthstone's official Japanese (HearthstoneJSON card files, a build-time input): a missing name whose
      English is a card's name and whose Japanese is katakana takes that Japanese (class human, source
      hearthstone@BUILD); word pairs from card names that split into the same number of words go into the
      glossary. A `human` or `correction` name is never touched.
  export --out DIR [--size N] [--hearthstone DIR]
      The missing names as batch files of N rows: {"id", "en", "kinds", "prose", "hints", "hearthstone"};
      a hint is [word, Japanese, "name" (keep it) | "word" (the usual Japanese of an ordinary word)].
      --skip FILE leaves out the ids of a batch still being drafted.
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
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from collections import Counter, defaultdict
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from wfj.core import names
from wfj.emit.lua_writer import shipped
from wfj.io import vmangos
from wfj.io.jsonl_store import Store, dumps
from wfj.io.names_store import load_lines, load_words, save_lines, save_words
from wfj.paths import data_root

PROSE_TYPES = ("quest", "gossip", "book", "objective", "area")
ENGLISH_NAMES = {"item": "item", "spell": "spell", "unit": "unit"}
_BATCH_RE = re.compile(r"^[0-9A-Za-z._-]{4,64}$")
_JA_SPLIT = re.compile(r"[・　 ]+")
_KATAKANA = re.compile(r"^[ァ-ヺー・]+$")
_JA_EDGE = "！？!?。、「」『』（）()…"
# a part that is a phrase or holds markup rather than a word's Japanese
_JA_ODD = re.compile(r"[\x00-\x7f！？。、「」『』（）：]")


def english_names(root: Path) -> dict[str, dict[str, set[int]]]:
    """{English name: {kind: ids}} from data/english item, spell and unit names."""
    out: dict[str, dict[str, set[int]]] = defaultdict(lambda: defaultdict(set))
    english = Store(root, english=True)
    for type_, kind in ENGLISH_NAMES.items():
        for ln in english.load(type_):
            if ln["field"] == "name" and ln["en"].strip():
                out[ln["en"]][kind].add(int(ln["id"]))
    return out


def prose_lines(root: Path) -> dict[str, str]:
    """{line key: shipped Japanese} for the prose names are read from, and the voiced error lines."""
    from wfj.cmd.voice_make import error_lines

    store = Store(root)
    out = {
        f"{t}:{ln['id']}:{ln['field']}": ln["ja"] for t in PROSE_TYPES for ln in store.load(t) if shipped(ln)
    }
    out.update(error_lines(root))
    return out


def prose_names(root: Path) -> set[str]:
    return {run for ja in prose_lines(root).values() for run in names.latin_runs(ja)}


def collect(root: Path, db: Path | None, today: str) -> dict[str, int]:
    seen = english_names(root)
    counts = {f"english {k}": sum(1 for v in seen.values() if k in v) for k in ENGLISH_NAMES.values()}
    if db is not None:
        for kind, rows in vmangos.read_names(db).items():
            for i, en in rows.items():
                seen.setdefault(en, defaultdict(set))[kind].add(i)
            counts[f"vmangos {kind}"] = len(set(rows.values()))
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
        for w, p in zip(ws, parts):
            if w[:1].isupper() and not _JA_ODD.search(p):
                forms[w][p] += 1
    conflicts = [
        f"{w}: {', '.join(f'{p} ×{n}' for p, n in c.most_common())}" for w, c in sorted(forms.items())
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
        if _KATAKANA.match(ja):
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
        if steady and w.lower() not in common and _KATAKANA.match(ja):
            # only a name Hearthstone spells the same way again and again; a one-off pair is too often a
            # card's own phrase ("アライアンスのために") to hold every name to it
            words[w] = {"en": w, "ja": ja, "check": True, "provenance": dict(prov)}
            added += 1
    save_words(root, words.values())
    for line in conflicts:
        print(f"names hearthstone: word with several forms, kept the most frequent: {line}", file=sys.stderr)
    return {"names filled": filled, "words added": added, "word conflicts": len(conflicts)}


def export(root: Path, out: Path, size: int, hs: Path | None, skip: set[str] = frozenset()) -> int:
    whole: dict[str, str] = {}
    if hs is not None:
        for en, ja in hearthstone_pairs(hs / "jaJP.json", hs / "enUS.json"):
            if not names._ASCII_LETTER.search(ja):  # a card Hearthstone left in English is no Japanese
                whole.setdefault(names.norm(en), ja)
    words = {w["en"]: w for w in load_words(root)}
    rows = []
    for ln in load_lines(root):
        if ln["status"] != "missing" or ln["id"] in skip:
            continue
        row: dict[str, Any] = {
            "id": ln["id"],
            "en": ln["en"],
            "kinds": {k: len(v) for k, v in ln["ids"].items()},
            "prose": ln["prose"],
            # [word, Japanese, "name"] must be kept; [word, Japanese, "word"] is the usual Japanese of an
            # ordinary word, to change when its sense here differs
            "hints": [[w, words[w]["ja"], "name" if words[w]["check"] else "word"]
                      for w in dict.fromkeys(names.words_of(ln["en"])) if w in words],
        }
        if ln["en"] in whole:
            row["hearthstone"] = whole[ln["en"]]
        rows.append(row)
    out.mkdir(parents=True, exist_ok=True)
    for n, start in enumerate(range(0, len(rows), size)):
        (out / f"batch-{n:03d}.jsonl").write_text(
            "".join(dumps(r) + "\n" for r in rows[start : start + size]), encoding="utf-8"
        )
    return len(rows)


def import_batch(
    root: Path, path: Path, model_id: str, batch: str, today: str, dry_run: bool
) -> tuple[int, list[str]]:
    if not _BATCH_RE.match(batch):
        raise ValueError(f"--batch {batch!r}: 4 to 64 of letters, digits, . _ -")
    prov = {"class": "machine", "model": model_id, "source": f"draft-names-{batch}@{today}", "imported": today}
    lines = {ln["id"]: ln for ln in load_lines(root)}
    words = {w["en"]: w for w in load_words(root)}
    rejected: list[str] = []
    written = 0
    with path.open(encoding="utf-8") as f:
        rows = [json.loads(raw) for raw in f if raw.strip()]
    for row in rows:
        ln = lines.get(row.get("id"))
        if ln is None:
            rejected.append(f"{row.get('id')}: no such name")
            continue
        if ln["provenance"]["class"] in ("human", "correction"):
            rejected.append(f"{ln['en']!r}: has a {ln['provenance']['class']} Japanese, kept")
            continue
        new = dict(ln, ja=row.get("ja", ""), reading=row.get("reading", ""), free=bool(row.get("free", False)),
                   status="trusted", provenance=dict(prov))
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
            if names.word_problems(w):
                rejected.append(f"{ln['en']!r}: word {pair!r}: {'; '.join(names.word_problems(w))}")
            elif pair[0] in words and words[pair[0]]["check"] and words[pair[0]]["ja"] != pair[1]:
                rejected.append(f"word {pair[0]!r}: already {words[pair[0]]['ja']!r}, not {pair[1]!r}")
            elif pair[0] not in words or not words[pair[0]]["check"]:
                words[pair[0]] = w  # an unchecked Hearthstone pair is only a guess; the drafted word replaces it
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
            if (w[:1].isalpha() and w.isascii() and (vocabulary or w[:1].isupper()) and w.lower() not in common
                    and w not in have and not names.stopword(w) and " " not in w):
                out[w].append(ln["en"])
    if vocabulary:
        out = defaultdict(list, {w: ns for w, ns in out.items() if len(ns) >= vocabulary})
    return out


def export_words(root: Path, out: Path, size: int, vocabulary: int = 0) -> int:
    cands = glossary_candidates(root, vocabulary=vocabulary)
    rows = [{"en": w, "count": len(ns), "examples": ns[:5]} for w, ns in sorted(cands.items())]
    out.mkdir(parents=True, exist_ok=True)
    for n, start in enumerate(range(0, len(rows), size)):
        (out / f"words-{n:03d}.jsonl").write_text(
            "".join(dumps(r) + "\n" for r in rows[start : start + size]), encoding="utf-8"
        )
    return len(rows)


def import_words(
    root: Path, path: Path, model_id: str, batch: str, today: str, dry_run: bool, hint_only: bool = False
) -> tuple[int, list[str]]:
    if not _BATCH_RE.match(batch):
        raise ValueError(f"--batch {batch!r}: 4 to 64 of letters, digits, . _ -")
    prov = {"class": "machine", "model": model_id, "source": f"draft-names-{batch}@{today}", "imported": today}
    words = {w["en"]: w for w in load_words(root)}
    rejected: list[str] = []
    written = 0
    with path.open(encoding="utf-8") as f:
        rows = [json.loads(raw) for raw in f if raw.strip()]
    for row in rows:
        en, ja = row.get("en"), row.get("ja", "")
        if not ja:
            continue
        w = {"en": en, "ja": ja, "check": not hint_only, "provenance": dict(prov)}
        bad = names.word_problems(w)
        if bad:
            rejected.append(f"word {en!r}: {'; '.join(bad)}")
        elif en in words and words[en]["check"]:
            if words[en]["ja"] != ja:
                rejected.append(f"word {en!r}: already {words[en]['ja']!r}, kept")
        else:
            words[en] = w
            written += 1
    if not dry_run:
        save_words(root, words.values())
    return written, rejected


def problems(root: Path) -> list[str]:
    lines, words = load_lines(root), load_words(root)
    out = [f"name {ln.get('en')!r}: {p}" for ln in lines for p in names.line_problems(ln)]
    seen: set[str] = set()
    for w in words:
        out.extend(f"name word: {p}" for p in names.word_problems(w))
        if w.get("en") in seen:
            out.append(f"name word {w['en']!r} twice")
        seen.add(w.get("en"))
    if not out:
        out.extend(f"name spelling: {p}" for p in names.spelling_problems(lines, words))
    return out


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj names")
    sub = p.add_subparsers(dest="cmd", required=True)
    today = dt.date.today().isoformat()
    c = sub.add_parser("collect")
    c.add_argument("--vmangos")
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
    i = sub.add_parser("import")
    i.add_argument("batch_file")
    i.add_argument("--model", required=True)
    i.add_argument("--batch", required=True)
    i.add_argument("--date", default=today)
    i.add_argument("--dry-run", action="store_true")
    ew = sub.add_parser("export-words")
    ew.add_argument("--out", required=True)
    ew.add_argument("--size", type=int, default=1000)
    ew.add_argument("--vocabulary", type=int, default=0, help="every word N or more names carry, ordinary words too")
    iw = sub.add_parser("import-words")
    iw.add_argument("batch_file")
    iw.add_argument("--model", required=True)
    iw.add_argument("--batch", required=True)
    iw.add_argument("--date", default=today)
    iw.add_argument("--dry-run", action="store_true")
    iw.add_argument("--hint-only", action="store_true",
                    help="ordinary words with several senses: a hint for drafting, not held to every name")
    sub.add_parser("check")
    a = p.parse_args(list(argv))
    root = data_root()
    try:
        if a.cmd == "collect":
            counts = collect(root, Path(a.vmangos) if a.vmangos else None, a.date)
            print("names collect: " + ", ".join(f"{k} {v}" for k, v in counts.items()))
        elif a.cmd == "hearthstone":
            if not re.match(r"^\d{4,}$", a.build):
                raise ValueError(f"--build {a.build!r}: the HearthstoneJSON build number")
            counts = apply_hearthstone(root, hearthstone_pairs(Path(a.ja), Path(a.en)), a.build, a.date)
            print("names hearthstone: " + ", ".join(f"{k} {v}" for k, v in counts.items()))
        elif a.cmd == "export":
            skip = {json.loads(r)["id"] for f in a.skip for r in Path(f).read_text(encoding="utf-8").splitlines() if r}
            n = export(root, Path(a.out), a.size, Path(a.hearthstone) if a.hearthstone else None, skip)
            print(f"names export: {n} missing names → {a.out}")
        elif a.cmd == "export-words":
            n = export_words(root, Path(a.out), a.size, a.vocabulary)
            print(f"names export-words: {n} words → {a.out}")
        elif a.cmd == "import-words":
            n, rejected = import_words(root, Path(a.batch_file), a.model, a.batch, a.date, a.dry_run, a.hint_only)
            for r in rejected:
                print(f"names import-words: {r}", file=sys.stderr)
            print(f"names import-words: {n} words written, {len(rejected)} kept or rejected"
                  + (" (dry run)" if a.dry_run else ""))
        elif a.cmd == "import":
            n, rejected = import_batch(root, Path(a.batch_file), a.model, a.batch, a.date, a.dry_run)
            for r in rejected:
                print(f"names import: rejected {r}", file=sys.stderr)
            print(f"names import: {n} names written, {len(rejected)} rejected" + (" (dry run)" if a.dry_run else ""))
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
