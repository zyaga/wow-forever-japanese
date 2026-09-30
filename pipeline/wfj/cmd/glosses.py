"""wfj glosses check: cross-check the word popup's dictionary forms against JMdict (ADR-039).

  check --jmdict FILE [--readings DIR] [--top N]
      Reads every reading record (data/reading/, or DIR laid out the same way) and prints how many words
      carry a meaning, how many distinct meanings there are, and the dictionary forms JMdict does not know
      (most used first). Most of those are game compounds and fine; a misspelt or invented dictionary form
      shows up there too. Local only: JMdict (jmdict-simplified English JSON) is never committed or shipped.
"""

from __future__ import annotations

import argparse
import json
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from wfj.cmd.readings import reading_store
from wfj.core import glosses, readings
from wfj.io.jsonl_store import Store
from wfj.paths import data_root


def report(records: list[dict[str, Any]], dictionary: glosses.Dictionary, top: int) -> list[str]:
    words = sum(len(r["words"]) for r in records)
    with_meaning = sum(1 for _ in glosses.meanings_of(records))
    unknown = glosses.unknown(dictionary, records)
    lines = [
        f"glosses: {with_meaning} of {words} words carry a meaning · "
        f"{len(glosses.table(records))} distinct meanings",
        f"  dictionary forms JMdict {dictionary.version} does not know: {len(unknown)} "
        "(most used first, usually game compounds):",
    ]
    ranked = sorted(unknown.items(), key=lambda kv: (-kv[1], kv[0]))[:top]
    lines += [f"    {n:5d}× {lemma} ({lemma_reading})" for (lemma, lemma_reading), n in ranked]
    return lines


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj glosses")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="the word popup's dictionary forms against JMdict (local only)")
    c.add_argument("--jmdict", required=True, type=Path, help="jmdict-simplified English JSON")
    c.add_argument("--readings", type=Path, default=None, help="a data/reading/ dir (default: this repo's)")
    c.add_argument("--top", type=int, default=30)
    a = p.parse_args(list(argv))
    root = a.readings or reading_store(data_root()).root
    store = Store(root)
    records = [r for t in readings.TYPES for r in store.load(t)]
    dictionary = glosses.Dictionary(json.loads(a.jmdict.read_text(encoding="utf-8")))
    for line in report(records, dictionary, a.top):
        print(line)
    return 0
