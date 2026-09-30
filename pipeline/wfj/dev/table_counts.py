"""Row counts of the client tables behind the `no-content` windows, from a local install.

    python -m wfj.dev.table_counts --wow "<client folder>" [--product wow_classic_beta]
        [--hotfixes <Cache/ADB/enUS/DBCache.bin>] [--tables WeeklyRewardChestThreshold …]

A `no-content` disposition (pipeline/forever_addon_dispositions.txt) rests on the window's own tables being
empty on this build (the Forever window sweep in docs/research/, §5). This re-runs that check per
build: for each table it prints the archive's record count and the hotfix cache's valid rows for it, and
flags a table that has rows. `TraitSubTree` answers the hero-talent question (a Forever class with hero
talents has rows there).

Reads `.build.info`, the archive and the hotfix cache, never writes (pipeline tooling only reads the
game folder, ADR-021) and makes no network call. Exit 0 when every table was read; 1 when one is
missing from the archive or unreadable (the table list names tables the check needs, so a missing one is a
finding, not a pass). `make forever-table-counts`.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from wfj.io import casc, db2, dbcache

# The sweep §5 tables, and TraitSubTree (hero talents), with their FileDataIDs: the root of this client
# carries no name hashes for them, so the id is the lookup (from the wowdev community listfile; the same
# list gives ItemSparse 1572924, the id client_tables pins). Order is the report's.
TABLES: dict[str, int] = {
    "WeeklyRewardChestThreshold": 3580962,
    "WeeklyRewardChestActivityTier": 5390446,
    "GarrType": 1333161,
    "GarrFollower": 949906,
    "GarrMission": 967962,
    "GarrBuilding": 929747,
    "GarrPlot": 937634,
    "GarrClassSpec": 981570,
    "GarrTalentTree": 1361030,
    "AdventureMapPOI": 1267070,
    "Covenant": 3384973,
    "Soulbind": 3488583,
    "AnimaCable": 3286805,
    "RenownRewards": 3743117,
    "AzeriteEssence": 2829665,
    "AzeritePower": 1846044,
    "AzeriteItem": 1846048,
    "AzeriteEmpoweredItem": 1846046,
    "Artifact": 1007934,
    "ArtifactPower": 1007937,
    "BattlePetSpecies": 841622,
    "BattlePetBreedState": 801579,
    "ResearchBranch": 1133729,
    "ResearchProject": 1134090,
    "ResearchSite": 1134091,
    "ResearchField": 1133711,
    "AlliedRace": 1710672,
    "RuneforgeLegendaryAbility": 3500241,
    "Contribution": 1587153,
    "DelvesSeason": 5920079,
    "TraitSubTree": 5534447,
}


def count(archive: casc.LocalArchive, name: str, hotfixes: dbcache.HotfixCache | None) -> tuple[int, int]:
    """(archive records, valid hotfix rows) of one table; CascError / Db2Error when it cannot be read."""
    fdid = archive.file_data_id(f"DBFilesClient\\{name}.db2", fallback=TABLES.get(name))
    buf, _gaps = archive.read_file(fdid)
    header = db2.read_header(buf, name)
    fixes = 0
    if hotfixes is not None:
        fixes = sum(1 for h in hotfixes.by_table.get(header.table_hash, {}).values() if h.replaces)
    return header.record_count, fixes


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wfj.dev.table_counts", description=__doc__.split("\n\n")[0])
    ap.add_argument("--wow", required=True, type=Path, help="the client folder holding .build.info")
    ap.add_argument(
        "--product", default="wow_classic_beta", help=".build.info product (default wow_classic_beta)"
    )
    ap.add_argument("--hotfixes", type=Path, help="the client's Cache/ADB/<locale>/DBCache.bin (read only)")
    ap.add_argument(
        "--tables", nargs="+", default=list(TABLES), help="tables to count (default: the sweep's)"
    )
    args = ap.parse_args(argv)
    try:
        archive = casc.LocalArchive(args.wow, args.product)
        cache = dbcache.read(args.hotfixes) if args.hotfixes and args.hotfixes.is_file() else None
    except (casc.CascError, dbcache.DbcacheError) as e:
        print(f"table-counts: {e}", file=sys.stderr)
        return 1
    print(f"build: {archive.info.version} ({archive.info.product})")
    print(f"hotfixes: {args.hotfixes if cache else 'none'}")
    failed = False
    for name in args.tables:
        try:
            rows, fixes = count(archive, name, cache)
        except (casc.CascError, db2.Db2Error) as e:
            print(f"{name}: unreadable ({e})")
            failed = True
            continue
        flag = "  ← has rows" if rows or fixes else ""
        print(f"{name}: {rows} rows, {fixes} hotfix rows{flag}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
