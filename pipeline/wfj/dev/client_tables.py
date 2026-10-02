"""Extract the client tables from a local install into wago.tools-shaped CSVs (ADR-021).

    python -m wfj.dev.client_tables --wow "<World of Warcraft>" --product wow_classic_era --out <dir>
        [--tables ItemSparse SpellName …] [--against <dir of wago CSVs>] [--hotfixes <DBCache.bin>]
        [--expect-build 1.60.1.69913]

Reads `.build.info` and `Data/` of the install, never writes there (an --out inside it is refused), and makes
no network call. Writes all selected tables or none: a failed table leaves --out as it was; the written tables
are stamped `db2@<build>` in --out/tables-source.txt. `--hotfixes` applies the client's hotfix cache
(Cache/ADB/<locale>/DBCache.bin, read only) over the archive rows; a missing file means none. Prints the build
as `<version>.<build>`, rows, hotfixes and encrypted skips per table. `--against` compares every written
column, parsed as the importers read it (and through the importer's own reader where one covers the table),
with the wago.tools CSVs of the same build and exits 1 on any difference. `--expect-build` refuses, before
anything is written, an install of another build (a client's folder is pinned to one build, and the
tables of a build the client no longer runs cannot be extracted again)."""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
from pathlib import Path

from wfj.io import casc, client_tables, dbcache, tables_stamp

SHOW_DIFFERENCES = 20


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wfj.dev.client_tables", description=__doc__.split("\n\n")[0])
    ap.add_argument(
        "--wow", required=True, type=Path, help="the World of Warcraft folder holding .build.info"
    )
    ap.add_argument(
        "--product", default="wow_classic_era", help=".build.info product (default wow_classic_era)"
    )
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--tables", nargs="+", help=f"subset of {list(client_tables.TABLES)}")
    ap.add_argument("--against", type=Path, help="dir of wago.tools CSVs of the same build to compare with")
    ap.add_argument("--hotfixes", type=Path, help="the client's Cache/ADB/<locale>/DBCache.bin (read only)")
    ap.add_argument("--expect-build", help="refuse an install of any other build (e.g. 1.60.1.69913)")
    args = ap.parse_args(argv)
    if args.out.resolve().is_relative_to(args.wow.resolve()):  # never write in the game folder
        print(f"client-tables: --out {args.out} is inside the game folder {args.wow}", file=sys.stderr)
        return 1
    try:
        tables = client_tables.select(args.tables)
        archive = casc.LocalArchive(args.wow, args.product)
        hotfixes = _hotfixes(args.hotfixes, archive)
    except (casc.CascError, client_tables.TableError, dbcache.DbcacheError) as e:
        print(f"client-tables: {e}", file=sys.stderr)
        return 1
    print(f"build: {archive.info.version} ({archive.info.product})")
    if args.expect_build and archive.info.version != args.expect_build:
        print(
            f"client-tables: the install is build {archive.info.version}, --out is pinned to "
            f"{args.expect_build}; nothing written (a new build gets its own pin and folder)",
            file=sys.stderr,
        )
        return 1
    if args.hotfixes:
        print(
            f"hotfixes: {args.hotfixes}" if hotfixes else f"hotfixes: none (no cache file at {args.hotfixes})"
        )
    # all or nothing: CSVs go to a temp folder and move into --out only when every table succeeded, so a
    # failed run never leaves a mix of this build's files and an older build's
    args.out.mkdir(parents=True, exist_ok=True)
    failed = False
    with tempfile.TemporaryDirectory(prefix=".client-tables-", dir=args.out) as tmp:
        written = []
        for table in tables:
            try:
                ex = client_tables.extract(archive, table, hotfixes)
            except client_tables.TableAbsent as e:
                # a table only some builds ship: a fact about the build, not a failed run
                print(f"{table.name}: {e}".replace(f"{table.name}: {table.name}: ", f"{table.name}: "))
                continue
            except client_tables.TableError as e:
                print(f"client-tables: {e}", file=sys.stderr)
                failed = True
                continue
            out = Path(tmp) / f"{table.name}.csv"
            client_tables.write_csv(ex, out)
            written.append(out)
            print(f"{table.name}: {len(ex.rows)} rows")
            for s in ex.skipped:
                print(f"  encrypted: section {s.section}, {s.records} records skipped (key {s.key_name})")
            if ex.copies_hidden:
                print(f"  encrypted: {ex.copies_hidden} copied rows hidden (source in a skipped section)")
            if ex.hotfixed:
                h = ex.hotfixed
                print(
                    f"  hotfixes: {h['replaced']} rows replaced, {h['added']} added, {h['removed']} removed"
                )
            for note in ex.notes:
                print(f"  {note}")
            if args.against:
                failed |= not _compare(table, out, args.against / f"{table.name}.csv", ex.prehotfix)
        if failed:
            print(f"client-tables: failed; nothing written to {args.out}", file=sys.stderr)
            return 1
        # unstamp these tables first, so a run cut off mid-move leaves them unstamped (refused), never
        # under an older source's stamp
        tables_stamp.clear(args.out, [out.stem for out in written])
        for out in written:
            shutil.move(str(out), args.out / out.name)
        # the imports check this stamp against their --src / --build; written once every CSV is in
        # place
        tables_stamp.write(args.out, [out.stem for out in written], f"db2@{archive.info.version}")
    print(f"wrote {len(written)} tables → {args.out} (stamped db2@{archive.info.version})")
    return 0


def _hotfixes(path: Path | None, archive: casc.LocalArchive) -> dbcache.HotfixCache | None:
    """The hotfix cache, or None when no path was given or no file is there (a fresh client has none; the
    path is printed so a typo shows). A directory, or a cache of another build than the archive's, is refused.
    """
    if path is None or not path.exists():
        return None
    if not path.is_file():
        raise dbcache.DbcacheError(f"--hotfixes {path} is not a file")
    cache = dbcache.read(path)
    build = int(archive.info.version.rsplit(".", 1)[-1])
    if cache.build != build:
        raise dbcache.DbcacheError(
            f"{path.name} is build {cache.build}, the archive is {archive.info.version}"
        )
    return cache


def _compare(
    table: client_tables.Table,
    ours: Path,
    theirs: Path,
    prehotfix: dict[tuple, dict[str, str | int] | None] | None = None,
) -> bool:
    try:
        n_ours, n_theirs, diffs = client_tables.compare(table, ours, theirs)
        reader_diffs = client_tables.compare_readers(table, ours, theirs)
    except (OSError, ValueError) as e:
        print(f"  against: {e}", file=sys.stderr)
        return False
    # A hotfixed row may differ from an export that lacks the hotfix: excused only where wago still holds the
    # archive's value (a wrong hotfix decode differs from both and fails). Listed apart.
    prehotfix = prehotfix or {}

    def excused(d: client_tables.Difference) -> bool:
        if d.key not in prehotfix:
            return False
        before = prehotfix[d.key]
        return d.theirs == (None if before is None else before[d.column])

    fixed = [d for d in diffs if excused(d)]
    diffs = [d for d in diffs if not excused(d)]
    # the importer's reader sees the same rows: a key whose row difference was excused is excused there too
    excused_rows = {d.key for d in fixed} - {d.key for d in diffs}
    reader_diffs = [k for k in reader_diffs if client_tables.reader_row_key(table, k) not in excused_rows]
    rows = len({d.key for d in diffs})
    print(f"  against {theirs.name}: {n_ours} rows ours · {n_theirs} rows wago · {rows} rows differ")
    skipped = client_tables.skipped_columns(table, theirs)
    if skipped:
        print(f"  not compared (a relation column wago leaves out): {', '.join(skipped)}")
    if fixed:
        print(f"  differ only where a hotfix applied: {len({d.key for d in fixed})} rows")
    for d in diffs[:SHOW_DIFFERENCES]:
        print(f"    {table.name} {d.key} {d.column}: ours {d.ours!r} · wago {d.theirs!r}")
    if len(diffs) > SHOW_DIFFERENCES:
        print(f"    … {len(diffs) - SHOW_DIFFERENCES} more")
    if table.name in client_tables.READERS:
        shown = f" {reader_diffs[:SHOW_DIFFERENCES]}" if reader_diffs else ""
        print(f"  importer reader: {len(reader_diffs)} keys differ{shown}")
    return not diffs and not reader_diffs


if __name__ == "__main__":
    sys.exit(main())
