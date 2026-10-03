"""Every text column the client serves, from a local install: the inventory coverage is measured against.

    python -m wfj.dev.served_columns --wow "<World of Warcraft>" --product wow_classic_beta \
        --listfile <community listfile> [--hotfixes <Cache/ADB/enUS/DBCache.bin>] \
        [--previous pipeline/served_columns.txt] > served_columns.txt

Coverage is measured over what the client actually ships, never over a list someone chose: every DB2 table
in the local archive, every text
column in each one, and the rows the hotfix cache adds. Each column then needs a line in
`pipeline/served_dispositions.txt` saying which surface covers it or why it is left out
(`tests/python/test_served_inventory.py`), so a table or column a new build adds fails the gate until someone
decides what it is.

- **Tables.** The archive root of the Forever client carries no file names, so the DB2 files are found
  through the community listfile (`<FileDataID>;<path>`, every `dbfilesclient/*.db2` it names). A listed
  file the build does not ship is skipped; one it ships but this reader cannot read is written as
  `unreadable` with the reason, so it still needs a disposition.
- **Text columns.** Found from the bytes (`io/db2.text_fields`): no column map is needed, so a column a build
  adds is found the same way as an old one. A column empty on every row is not text yet; if a later build
  fills it, it appears as a new column.
- **Server caches.** The text the server sends rather than the archive (quests, NPC text, book pages,
  creature and object names) lands in the client's `Cache/WDB/<locale>/*.wdb`. With `--wdb`, each cache is
  written as `wdb-<name>.*` with its record count, so it needs a disposition like a table does.
- **Hotfixes.** A valid hotfix row whose table keeps every text field first is read as its leading strings and
  counted with the archive rows (a hotfix replaces the archive row with the same id). A table hash the
  archive does not name is written as `hotfix-only`, with its row count.

The output is one line per column, sorted: `<table>.f<field>  rows=<n>  text=<non-empty>  distinct=<n>`. It is
committed, like `ui_inventory.txt`, so the gate needs no game install; `make served-columns` regenerates it
for each build. With `--previous`, what changed since the committed file is printed to stderr: the columns a
build added or dropped and the ones whose counts moved.

Reads `.build.info`, the archive and the hotfix cache, never writes to the game folder (ADR-021) and makes no
network call.
"""

from __future__ import annotations

import argparse
import re
import struct
import sys
from dataclasses import dataclass
from pathlib import Path

from wfj.io import casc, db2, dbcache

_DB2_PATH = re.compile(r"^dbfilesclient/([^/]+)\.db2$")
_LINE = re.compile(r"^(\S+)\s+(.*)$")


@dataclass(frozen=True)
class Column:
    key: str  # "<table>.f<field>"
    rows: int
    text: int  # non-empty values
    distinct: int

    def line(self) -> str:
        return f"{self.key}  rows={self.rows}  text={self.text}  distinct={self.distinct}"


def db2_files(listfile: Path) -> dict[str, int]:
    """{lower-case table name: FileDataID} for every `dbfilesclient/*.db2` the listfile names."""
    out: dict[str, int] = {}
    with listfile.open(encoding="utf-8", errors="replace") as f:
        for raw in f:
            fid, _, path = raw.strip().partition(";")
            m = _DB2_PATH.match(path.lower())
            if m and fid.isdigit():
                out[m.group(1)] = int(fid)
    return out


def table_columns(
    name: str, buf: bytes, encrypted: list[tuple[int, int, str]], fixes: dict[int, dbcache.Hotfix]
) -> list[Column]:
    """The text columns of one table, the hotfix rows applied where they can be read without a column map."""
    fields = sorted(db2.text_fields(buf, encrypted, name))
    if not fields:
        return []
    rows = dict(db2.read(buf, frozenset(fields), encrypted, name).rows)
    leading = fields == list(range(len(fields)))
    for rid, fix in fixes.items():
        if not fix.replaces:
            rows.pop(rid, None)
        elif leading:
            values = dbcache.leading_strings(fix.data, len(fields))
            rows[rid] = tuple(values) + (None,) * (max(fields) + 1 - len(values))
    out = []
    for fn in fields:
        values = [r[fn] for r in rows.values() if isinstance(r[fn], str) and r[fn]]
        out.append(Column(f"{name}.f{fn}", len(rows), len(values), len(set(values))))
    return out


def inventory(
    archive: casc.LocalArchive, tables: dict[str, int], hotfixes: dbcache.HotfixCache | None
) -> tuple[list[str], dict[str, int]]:
    """(lines, counts) for every listed table the build ships: its text columns, or `unreadable`."""
    lines: list[str] = []
    counts = {"tables": 0, "with_text": 0, "unreadable": 0}
    named_hashes: set[int] = set()
    for name, fdid in sorted(tables.items()):
        if not archive.ships(fdid):
            continue
        counts["tables"] += 1
        try:
            buf, encrypted = archive.read_file(fdid)
            header = db2.read_header(buf, name)
            named_hashes.add(header.table_hash)
            fixes = hotfixes.by_table.get(header.table_hash, {}) if hotfixes else {}
            columns = table_columns(name, buf, encrypted, fixes)
        except (casc.CascError, db2.Db2Error, ValueError) as e:
            counts["unreadable"] += 1
            lines.append(f"{name}.*  unreadable: {str(e).replace(chr(10), ' ')}")
            continue
        if columns:
            counts["with_text"] += 1
        lines += [c.line() for c in columns]
    for table_hash, fixes in sorted((hotfixes.by_table if hotfixes else {}).items()):
        valid = sum(1 for h in fixes.values() if h.replaces)
        if table_hash not in named_hashes and valid:
            lines.append(f"hash-{table_hash:08x}.*  hotfix-only: rows={valid}")
    return sorted(lines), counts


def wdb_records(path: Path) -> int:
    """The record count of a client WDB cache: a 24-byte header, then `[id u32][length u32][payload]` records
    up to an id and length of 0 (the quest cache's framing, `io/wdb.py`, which every cache shares)."""
    buf = path.read_bytes()
    if len(buf) < 24 or buf[:1] == b"\0":
        raise ValueError(f"{path.name}: not a WDB cache")
    at, n = 24, 0
    while at + 8 <= len(buf):
        rid, size = struct.unpack_from("<II", buf, at)
        if rid == 0 and size == 0:
            return n
        at += 8 + size
        n += 1
    raise ValueError(f"{path.name}: records run past the end of the file")


def wdb_lines(folder: Path) -> list[str]:
    """`wdb-<name>.*  records=<n>` for every cache in a client's `Cache/WDB/<locale>` folder."""
    out = []
    for path in sorted(folder.glob("*.wdb")):
        try:
            out.append(f"wdb-{path.stem.lower()}.*  records={wdb_records(path)}")
        except (OSError, ValueError) as e:
            out.append(f"wdb-{path.stem.lower()}.*  unreadable: {e}")
    return out


def read_inventory(path: Path) -> dict[str, str]:
    """A committed inventory → {column key: the rest of its line}; `#` lines are comments."""
    out: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("#") or not raw.strip():
            continue
        m = _LINE.match(raw)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def inventory_build(path: Path) -> str | None:
    """The build a committed inventory was taken on (its `# build:` line)."""
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("# build: "):
            return raw.split()[2]
    return None


def changes(previous: dict[str, str], current: dict[str, str]) -> list[str]:
    """What a build changed against the committed inventory: added, gone and changed columns."""
    out = [f"new      {k}  {current[k]}" for k in sorted(current.keys() - previous.keys())]
    out += [f"gone     {k}  {previous[k]}" for k in sorted(previous.keys() - current.keys())]
    out += [
        f"changed  {k}  {previous[k]}  ->  {current[k]}"
        for k in sorted(current.keys() & previous.keys())
        if previous[k] != current[k]
    ]
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wfj.dev.served_columns", description=__doc__.split("\n\n")[0])
    ap.add_argument(
        "--wow", required=True, type=Path, help="the World of Warcraft folder holding .build.info"
    )
    ap.add_argument(
        "--product", default="wow_classic_beta", help=".build.info product (default wow_classic_beta)"
    )
    ap.add_argument("--listfile", required=True, type=Path, help="the community listfile (<id>;<path> lines)")
    ap.add_argument("--hotfixes", type=Path, help="the client's Cache/ADB/<locale>/DBCache.bin (read only)")
    ap.add_argument("--wdb", type=Path, help="the client's Cache/WDB/<locale> folder (read only)")
    ap.add_argument("--previous", type=Path, help="the committed inventory, to print what this build changed")
    args = ap.parse_args(argv)
    try:
        archive = casc.LocalArchive(args.wow, args.product)
        cache = dbcache.read(args.hotfixes) if args.hotfixes else None
        tables = db2_files(args.listfile)
    except (casc.CascError, dbcache.DbcacheError, OSError) as e:
        print(f"served-columns: {e}", file=sys.stderr)
        return 1
    if not tables:
        print(f"served-columns: {args.listfile} names no dbfilesclient/*.db2 file", file=sys.stderr)
        return 1
    lines, counts = inventory(archive, tables, cache)
    if args.wdb:
        lines = sorted(lines + wdb_lines(args.wdb))
    print("# Every text column the client serves. Generated by `make served-columns`; do not edit by hand.")
    print(
        "# Each line needs a disposition in served_dispositions.txt (tests/python/test_served_inventory.py)."
    )
    print(f"# build: {archive.info.version} ({archive.info.product})")
    print(f"# hotfixes: build {cache.build}" if cache else "# hotfixes: none")
    print(
        f"# tables: {counts['tables']} shipped, {counts['with_text']} with text,"
        f" {counts['unreadable']} unreadable"
    )
    for line in lines:
        print(line)
    if args.previous and args.previous.is_file():
        current = {m.group(1): m.group(2) for m in map(_LINE.match, lines) if m}
        delta = changes(read_inventory(args.previous), current)
        print(f"served-columns: {len(delta)} change(s) since {args.previous}", file=sys.stderr)
        for d in delta:
            print(f"  {d}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
