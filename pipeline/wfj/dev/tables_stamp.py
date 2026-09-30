"""The source stamp of client-table CSVs: write, clear or check it from make.

    python -m wfj.dev.tables_stamp write --dir <folder> --src wago --build 1.15.9.69722 ItemSparse SpellName …
    python -m wfj.dev.tables_stamp clear --dir <folder> ItemSparse SpellName …
    python -m wfj.dev.tables_stamp check --src wago --build 1.15.9.69722 <folder>/ItemSparse.csv …

`make wago-fetch` clears the stamp of the tables it fetches before moving the downloads in, writes it after;
`make import` / `make import-english` run `check` in their preflight, so a missing or other stamp stops the
target before any import step writes.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from wfj.io import tables_stamp


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wfj.dev.tables_stamp", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="action", required=True)
    w = sub.add_parser("write")
    w.add_argument("--dir", required=True, type=Path)
    w.add_argument("--src", required=True, choices=("wago", "db2"))
    w.add_argument("--build", required=True)
    w.add_argument("tables", nargs="+")
    c = sub.add_parser("clear")
    c.add_argument("--dir", required=True, type=Path)
    c.add_argument("tables", nargs="+")
    k = sub.add_parser("check")
    k.add_argument("--src", required=True)
    k.add_argument("--build", required=True)
    k.add_argument("csvs", nargs="+", type=Path)
    a = ap.parse_args(argv)
    try:
        if a.action == "write":
            tables_stamp.write(a.dir, a.tables, f"{a.src}@{a.build}")
            print(f"tables-stamp: {len(a.tables)} tables {a.src}@{a.build} → {a.dir / tables_stamp.FILE}")
        elif a.action == "clear":
            tables_stamp.clear(a.dir, a.tables)
        else:
            tables_stamp.check(a.csvs, a.src, a.build)
    except (OSError, ValueError) as e:
        print(f"tables-stamp: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
