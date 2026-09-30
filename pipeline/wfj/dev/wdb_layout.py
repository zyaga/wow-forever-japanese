"""Which pinned quest-cache payload layout reads a cache exactly.

  python -m wfj.dev.wdb_layout predecessors/clients/forever-1.60.1.69913/questcache.wdb

`io/wdb` pins a payload layout per client build and refuses a build it has none for (ADR-020: a changed
layout fails loudly rather than importing misread text). When a new build's cache arrives, this says whether
one of the pinned layouts already reads **every** record of it exactly: the evidence needed to pin that
build in `io/wdb.LAYOUTS`, which is a code change a person makes, not something this tool does.

It reports, per pinned layout, how many records it reads and the first record it cannot, then how many of the
titles we already hold in `data/english/quest` the winning layout reproduces character for character. It
refuses to name a winner unless exactly one layout reads every record: a layout that reads *most* of a cache
is a layout we do not understand.
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path

from wfj.io import wdb
from wfj.io.jsonl_store import Store
from wfj.paths import data_root


def _titles() -> dict[int, str]:
    """The English quest titles already in the store, to check the decode against; empty when none."""
    try:
        rows = Store(data_root(), english=True).load("quest")
    except (OSError, ValueError):
        return {}
    return {r["id"]: r["en"] for r in rows if r.get("field") == "title"}


def read_with(path: Path, lay: wdb.Layout) -> tuple[int, int, str | None]:
    """(records read, records in the file, the first failure) of one layout over one cache."""
    name, buf = wdb._open(path)
    read = total = 0
    first: str | None = None
    for qid, payload in wdb._records(name, buf):
        total += 1
        try:
            wdb.decode_payload(qid, payload, lay)
            read += 1
        except ValueError as e:
            if first is None:
                first = f"quest {qid}: {e}"
    return read, total, first


def main(argv: Sequence[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="python -m wfj.dev.wdb_layout")
    p.add_argument("cache", help="a questcache.wdb")
    a = p.parse_args(list(argv) if argv is not None else None)
    path = Path(a.cache)
    try:
        build, ids = wdb.read_ids(path)
    except wdb.WdbError as e:
        print(f"wdb-layout: {e}", file=sys.stderr)
        return 2
    print(f"{path.name}: build {build}, {len(ids)} records")
    pinned = next((lay for lay in wdb.LAYOUTS if lay.build == build), None)
    print(f"pinned for this build: {'yes, ' + pinned.evidence if pinned else 'no'}")

    exact = []
    for lay in wdb.LAYOUTS:
        read, total, first = read_with(path, lay)
        mark = "reads every record" if read == total else f"reads {read} / {total}"
        print(f"  layout {lay.build}: {mark}")
        if first:
            print(f"      first failure: {first}")
        if read == total:
            exact.append(lay)

    if len(exact) != 1:
        which = ", ".join(str(lay.build) for lay in exact) or "none"
        print(f"\nno single layout reads this cache exactly ({which}); it is not understood yet")
        return 1
    lay = exact[0]
    cache = wdb.read_quests(path, layout=lay)
    known = _titles()
    same = sum(1 for q in cache.quests if known.get(q.id) == q.title)
    seen = sum(1 for q in cache.quests if q.id in known)
    print(f"\nlayout {lay.build} reads every record of build {build} exactly.")
    print(f"  {len(cache.quests)} quests, {len(cache.placeholders)} placeholders")
    print(f"  titles: {same} of {seen} already-held titles reproduce character for character")
    cond = sum(len(q.conditional) for q in cache.quests)
    print(f"  conditional text: {cond} entries (read so the payload adds up, never imported)")
    if lay.build != build:
        print(f"  to use it: add a Layout for build {build} to io/wdb.LAYOUTS, with these numbers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
