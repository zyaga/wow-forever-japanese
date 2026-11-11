"""`wfj english-cards`: the numbers behind the English word cards, and their pronunciation table.

    wfj english-cards report [--top N]        how many of each surface's English words get a card, and the
                                              words that most often get none (candidates for the common list)
    wfj english-cards pron <dict> --version V  write data/english/pronunciation.tsv from the CMU Pronouncing
                                              Dictionary file, for the words a card can show

The card rows themselves are written by `wfj generate`; nothing here ships by itself.
"""

from __future__ import annotations

import argparse
from collections import Counter
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from wfj.cmd import generate
from wfj.core import english_cards, pronunciation, readings
from wfj.io.jsonl_store import Store
from wfj.paths import data_root


def card_records(store: Store) -> dict[str, list[dict[str, Any]]]:
    """Per card surface, the current reading records with their English word card row (`english`) and the
    line's English (`en`), for the lines that have both a reading and English."""
    english_store = Store(store.root, english=True)
    out: dict[str, list[dict[str, Any]]] = {}
    for type_ in readings.TYPES:
        lines = store.load(type_)
        result = readings.check(type_, generate.reading_store_of(store).load(type_), readings.shipped_japanese(lines))
        current = readings.addon_keyed(type_, result["current"], lines)
        en: dict[tuple[Any, str], str] = {}
        for ln in english_store.load(type_):
            key = ln.get("hash") if type_ == "book" else ln["id"]
            if key is not None and isinstance(ln.get("en"), str):
                en.setdefault((key, ln["field"]), ln["en"])
        recs = []
        for rec in current:
            text = en.get((rec["id"], rec["field"]))
            if text:
                row = english_cards.pack(english_cards.invert(text, rec["words"]))
                recs.append(rec | {"english": row, "en": text})
        out[type_] = recs
    return out


def coverage(store: Store) -> dict[str, Any]:
    """{surface: {lines, words, carded}} and `missed` (a Counter of the words with no card). `words` counts
    every word of a line a card could stand on, each time it occurs: names and codes are left out, and so are
    the words that take no card by design (`english_cards.NO_CARD`). `carded` are those the line's row or the
    common list covers, a contraction through its first word."""
    common = generate.load_common_words(Store(store.root, english=True).root)
    by_type: dict[str, dict[str, int]] = {}
    missed: Counter[str] = Counter()
    for type_, recs in card_records(store).items():
        lines = words = carded = 0
        covered = lambda w, row: w in row or w in common  # noqa: E731
        for rec in recs:
            row = {pair.rpartition("=")[0] for pair in rec["english"].split()}
            line_words = english_cards.line_words(rec["en"])
            if not line_words:
                continue
            lines += 1
            for w in line_words:
                if w in english_cards.NO_CARD or english_cards.base(w) in english_cards.NO_CARD:
                    continue
                words += 1
                if covered(w, row) or covered(english_cards.base(w), row):
                    carded += 1
                else:
                    missed[w] += 1
        by_type[type_] = {"lines": lines, "words": words, "carded": carded}
    return {"surfaces": by_type, "missed": missed}


def used_words(store: Store) -> set[str]:
    """Every English word a card can show: the rows' words and the common list's."""
    used = set(generate.load_common_words(Store(store.root, english=True).root))
    for recs in card_records(store).values():
        for rec in recs:
            used.update(pair.rpartition("=")[0] for pair in rec["english"].split())
    return used


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj english-cards", description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("report", help="card coverage per surface and the words that most often get none")
    r.add_argument("--top", type=int, default=40)
    r.add_argument("--data", type=Path, default=None, help="a data/ dir (default: this repo's)")
    pr = sub.add_parser("pron", help="write the pronunciation table from the CMU Pronouncing Dictionary file")
    pr.add_argument("dictionary", type=Path, help="cmudict.dict")
    pr.add_argument("--version", required=True, help="the dictionary's pinned commit")
    pr.add_argument("--data", type=Path, default=None, help="a data/ dir (default: this repo's)")
    args = p.parse_args(list(argv))
    store = Store(args.data or data_root())
    if args.cmd == "report":
        result = coverage(store)
        for type_, c in result["surfaces"].items():
            share = c["carded"] / c["words"] if c["words"] else 0.0
            print(f"english-cards: {type_}: {c['lines']} lines, {c['carded']} of {c['words']} words carded ({share:.1%})")
        total = sum(result["missed"].values())
        print(f"english-cards: {total} word occurrences with no card; most frequent:")
        for w, n in result["missed"].most_common(args.top):
            print(f"  {n}\t{w}")
        return 0
    said = pronunciation.parse(args.dictionary.read_text(encoding="utf-8", errors="replace"))
    used = used_words(store)
    rows = {w: said[w] for w in used if w in said}
    path = Store(store.root, english=True).root / generate.PRONUNCIATION
    path.write_text(pronunciation.table(rows, args.version), encoding="utf-8")
    print(f"english-cards: {len(rows)} of {len(used)} card words have a pronunciation → {path}")
    return 0
