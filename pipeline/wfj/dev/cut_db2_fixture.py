"""Copy real DB2 tables out of a local install into the test fixtures (ADR-021).

    python -m wfj.dev.cut_db2_fixture --wow "<World of Warcraft>" --product wow_classic_era \\
        --out ../tests/fixtures/db2 ItemSubClass QuestV2

Only small tables belong in the repo: `tests/fixtures/db2/` holds ItemSubClass (pallet, common data, signed
bitpacked fields, an inline id, a partial relationship map, a string table) and QuestV2 (an id list and a copy
table), with wago.tools' CSVs of the same build beside them in `wago/`. Sparse tables and encrypted sections
are covered by the synthetic writer in `tests/python/db2_fixture.py`. Reads the install only.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from wfj.io import casc, client_tables


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wfj.dev.cut_db2_fixture")
    ap.add_argument("--wow", required=True, type=Path)
    ap.add_argument("--product", default="wow_classic_era")
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("tables", nargs="+")
    args = ap.parse_args(argv)
    archive = casc.LocalArchive(args.wow, args.product)
    args.out.mkdir(parents=True, exist_ok=True)
    for table in client_tables.select(args.tables):
        buf, gaps = archive.read_file(archive.file_data_id(table.path))
        if gaps:
            print(f"{table.name}: has encrypted frames; not a fixture", file=sys.stderr)
            return 1
        (args.out / f"{table.name}.db2").write_bytes(buf)
        print(f"{table.name}.db2: {len(buf)} bytes (build {archive.info.version})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
