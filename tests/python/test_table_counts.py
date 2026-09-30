"""wfj.dev.table_counts: the no-content windows' tables and TraitSubTree, counted per build from the
local archive and the hotfix cache, read only."""

from pathlib import Path

import pytest

from wfj.dev import table_counts
from wfj.io import casc, db2, dbcache

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "db2"


class FakeArchive:
    """Serves one fixture DB2 by FileDataID; a path with no name hash falls back to the id, as the Forever root
    does."""

    def __init__(self, files: dict[int, bytes]):
        self.files = files

    def file_data_id(self, path: str, fallback: int | None = None) -> int:
        if fallback in self.files:
            return fallback
        raise casc.CascError(f"root: {path} names 0 enUS files ([])")

    def read_file(self, fdid: int):
        return self.files[fdid], []


def test_the_table_list_holds_the_sweep_tables_and_trait_subtree():
    assert {"WeeklyRewardChestThreshold", "GarrType", "AlliedRace", "DelvesSeason", "TraitSubTree"} <= set(
        table_counts.TABLES
    )
    assert all(isinstance(i, int) and i > 0 for i in table_counts.TABLES.values())


def test_a_table_is_counted_by_its_file_data_id_with_its_hotfix_rows():
    buf = (FIXTURES / "ItemSubClass.db2").read_bytes()
    header = db2.read_header(buf, "fixture")
    fdid = table_counts.TABLES["TraitSubTree"]
    archive = FakeArchive({fdid: buf})
    assert table_counts.count(archive, "TraitSubTree", None) == (header.record_count, 0)
    cache = dbcache.HotfixCache(
        70009,
        {header.table_hash: {1: dbcache.Hotfix(5, dbcache.VALID, b"x"), 2: dbcache.Hotfix(6, dbcache.VALID, b"")}},
    )
    assert table_counts.count(archive, "TraitSubTree", cache) == (header.record_count, 1)  # a deletion is no row


def test_a_table_the_archive_lacks_is_a_failure_not_a_pass():
    with pytest.raises(casc.CascError):
        table_counts.count(FakeArchive({}), "TraitSubTree", None)


def test_no_install_exits_1(tmp_path):
    assert table_counts.main(["--wow", str(tmp_path)]) == 1
