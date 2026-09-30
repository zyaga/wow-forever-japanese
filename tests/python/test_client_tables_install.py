"""Proof on a real install: every client table extracted from the local archive equals wago.tools'
export of the same build. Runs only where both are present. CI has no game:

    WFJ_WOW_DIR="<World of Warcraft folder>" WFJ_WAGO_DIR=<dir of wago CSVs at that build> \\
        [WFJ_WOW_PRODUCT=wow_classic_era] pytest tests/python/test_client_tables_install.py

With WFJ_HOTFIXES=<client folder>/Cache/ADB/enUS/DBCache.bin as well, every hotfix record of the tables
that declare field types decodes to exactly its size: the first check of the declared-type layout on a real
cache (the layout is built from wowdev/DBCD and WoWDBDefs).
"""

import os
from pathlib import Path

import pytest

from wfj.io import casc, client_tables, dbcache

WOW = os.environ.get("WFJ_WOW_DIR")
WAGO = os.environ.get("WFJ_WAGO_DIR")
HOTFIXES = os.environ.get("WFJ_HOTFIXES")
needs_wago = pytest.mark.skipif(not (WOW and WAGO), reason="needs WFJ_WOW_DIR and WFJ_WAGO_DIR")


@pytest.fixture(scope="module")
def archive() -> casc.LocalArchive:
    return casc.LocalArchive(Path(WOW), os.environ.get("WFJ_WOW_PRODUCT", "wow_classic_era"))


@needs_wago
@pytest.mark.parametrize("name", list(client_tables.TABLES))
def test_table_matches_wago(archive: casc.LocalArchive, name: str, tmp_path: Path):
    table = client_tables.TABLES[name]
    ex = client_tables.extract(archive, table)
    assert ex.skipped == []
    out = tmp_path / f"{name}.csv"
    client_tables.write_csv(ex, out)
    theirs = Path(WAGO) / f"{name}.csv"
    n_ours, n_theirs, diffs = client_tables.compare(table, out, theirs)
    assert (n_ours, diffs[:5]) == (n_theirs, [])
    assert client_tables.compare_readers(table, out, theirs) == []


@pytest.mark.skipif(not (WOW and HOTFIXES), reason="needs WFJ_WOW_DIR and WFJ_HOTFIXES")
@pytest.mark.parametrize("name", [n for n, t in client_tables.TABLES.items() if t.record])
def test_real_hotfixes_decode_by_declared_types(archive: casc.LocalArchive, name: str):
    table = client_tables.TABLES[name]
    ex = client_tables.extract(archive, table, dbcache.read(Path(HOTFIXES)))  # a record that does not fit raises
    assert ex.rows
