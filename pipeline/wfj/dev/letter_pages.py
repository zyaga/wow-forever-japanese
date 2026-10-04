"""`make letter-pages`: list the book pages a letter shows → pipeline/letter_pages.txt.

The client stores a book page and a letter page the same way (one page text, chained by its next page), so the
store cannot tell them apart. A page counts as a letter page when the item that opens it is named like one
(Letter, Note, Orders, Report, …). Pages opened by a world object (a book on a shelf, a plaque, a headstone),
by any other item, or by nothing the tables name are book pages. The list feeds the counts `make coverage`
writes into the README and the CurseForge description.

Inputs (read-only): the item table (`ItemSparse.csv`, its `PageID` column) and the VMaNGOS database
(`item_template.page_text` and `page_text.next_page`).
"""

from __future__ import annotations

import argparse
import csv
import re
import sqlite3
import sys
from collections.abc import Sequence
from pathlib import Path

LETTER = re.compile(
    r"\b(letters?|notes?|missive|message|orders?|reports?|memo|memorandum|dispatch|plea|request|instructions|"
    r"decree|envelope|documents?|docket|deed|response|invitation|summons|warrant|notice|announcement|"
    r"certificate|list|correspondence)\b",
    re.I,
)

HEADER = """\
# Book pages a letter shows, written by `make letter-pages` (pipeline/wfj/dev/letter_pages.py).
# Do not edit by hand. `<page id>  # <the item that opens it>` per line. Every other page is a book page.
"""


def item_starts(item_sparse: Path, db: sqlite3.Connection) -> dict[int, str]:
    """First page → the name of the item that opens it."""
    csv.field_size_limit(sys.maxsize)
    starts: dict[int, str] = {}
    with item_sparse.open(encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            page = int(row.get("PageID") or 0)
            if page:
                starts.setdefault(page, row["Display_lang"])
    for name, page in db.execute("SELECT name, page_text FROM item_template WHERE page_text > 0"):
        starts.setdefault(page, name)
    return starts


def letter_pages(starts: dict[int, str], next_page: dict[int, int]) -> dict[int, str]:
    """Every page of a chain whose opening item is named like a letter."""
    out: dict[int, str] = {}
    for first, name in starts.items():
        if not LETTER.search(name):
            continue
        page, seen = first, set()
        while page and page not in seen:
            seen.add(page)
            out.setdefault(page, name)
            page = next_page.get(page, 0)
    return out


def render(pages: dict[int, str]) -> str:
    return HEADER + "".join(f"{p}  # {pages[p]}\n" for p in sorted(pages))


def read(path: Path) -> set[int]:
    if not path.exists():
        return set()
    ids = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        head = line.split("#", 1)[0].strip()
        if head:
            ids.add(int(head))
    return ids


def main(argv: Sequence[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wfj.dev.letter_pages", description=__doc__.split("\n", 1)[0])
    ap.add_argument("item_sparse", type=Path)
    ap.add_argument("mangos", type=Path)
    a = ap.parse_args(argv)
    db = sqlite3.connect(f"file:{a.mangos}?mode=ro", uri=True)
    next_page = dict(db.execute("SELECT entry, next_page FROM page_text"))
    sys.stdout.write(render(letter_pages(item_starts(a.item_sparse, db), next_page)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
