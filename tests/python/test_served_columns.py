"""`make served-columns`: every text column the client serves is found from the bytes, hotfixes and caches
included, and a build's changes are listed against the committed inventory."""

from __future__ import annotations

import struct
from pathlib import Path

import pytest
from db2_fixture import wdc5

from wfj.dev import served_columns as sc
from wfj.io import client_tables, db2, dbcache


def test_dense_text_fields_are_the_string_columns():
    buf, _ = wdc5(
        [[(1, [1, "Frost", 7, ""]), (2, [2, "Fire", 9, ""])]],
        {1, 3},
        field_count=4,
    )
    # field 3 is a string field with no text on any row: not text yet
    assert db2.text_fields(buf) == frozenset({1})


def test_a_number_that_lands_inside_a_string_is_not_text():
    buf, _ = wdc5([[(1, [1, "Frostbolt"]), (2, [2, "Fire"])]], {1}, field_count=2)
    # field 0 holds the ids 1 and 2: read as offsets they would point into the string table, not at a string
    assert 0 not in db2.text_fields(buf)


def test_sparse_leading_strings():
    buf, _ = wdc5(
        [[(5, ["Rank 1", "Hurls a fireball.", 3]), (6, ["", "Burning.", 4])]],
        {0, 1},
        field_count=3,
        sparse=True,
    )
    assert db2.text_fields(buf) == frozenset({0, 1})


def test_sparse_string_after_a_number_is_found_by_the_search():
    buf, _ = wdc5(
        [[(5, [70000, "Shield Wall", 3]), (6, [80000, "Recklessness", 4])]],
        {1},
        field_count=3,
        sparse=True,
    )
    assert db2.text_fields(buf) == frozenset({1})


def test_a_table_with_no_rows_has_no_text():
    buf, _ = wdc5([[]], set(), field_count=2)
    assert db2.text_fields(buf) == frozenset()


def test_real_itemsubclass_text_fields_match_its_column_map(root: Path):
    buf = (root / "tests" / "fixtures" / "db2" / "ItemSubClass.db2").read_bytes()
    declared = client_tables.TABLES["ItemSubClass"].string_fields
    assert db2.text_fields(buf, name="ItemSubClass") == declared


def _hotfix(status: int, data: bytes, order: int = 0) -> dbcache.Hotfix:
    return dbcache.Hotfix(push_id=1, status=status, data=data, order=order)


def test_table_columns_apply_hotfix_rows():
    buf, _ = wdc5([[(1, ["Frost", 3]), (2, ["Fire", 4])]], {0}, field_count=2)
    fixes = {
        3: _hotfix(dbcache.VALID, b"Arcane\0" + struct.pack("<I", 5)),  # a new row
        2: _hotfix(dbcache.REMOVED, b""),  # a removed row
    }
    [col] = sc.table_columns("school", buf, [], fixes)
    assert (col.key, col.rows, col.text, col.distinct) == ("school.f0", 2, 2, 2)
    assert col.line() == "school.f0  rows=2  text=2  distinct=2"


class FakeArchive:
    def __init__(self, files: dict[int, bytes]):
        self.files = files

    def ships(self, fdid: int) -> bool:
        return fdid in self.files

    def read_file(self, fdid: int):
        return self.files[fdid], []


def test_inventory_lists_text_columns_unreadable_tables_and_unnamed_hotfixes():
    good, _ = wdc5([[(1, ["Frost", 3])]], {0}, field_count=2, table_hash=0x11)
    numbers, _ = wdc5([[(1, [7, 3])]], set(), field_count=2, table_hash=0x22)
    archive = FakeArchive({10: good, 11: numbers, 12: b"junk"})
    cache = dbcache.HotfixCache(70170, {0x99: {1: _hotfix(dbcache.VALID, b"x\0")}})
    tables = {"school": 10, "numbers": 11, "broken": 12, "notshipped": 13}
    lines, counts = sc.inventory(archive, tables, cache)
    assert lines == [
        "broken.*  unreadable: broken: magic b'junk' is not b'WDC5'",
        "hash-00000099.*  hotfix-only: rows=1",
        "school.f0  rows=1  text=1  distinct=1",
    ]
    assert counts == {"tables": 3, "with_text": 1, "unreadable": 1}


def test_db2_files_from_the_listfile(tmp_path: Path):
    lf = tmp_path / "listfile.csv"
    lf.write_text(
        "1990283;dbfilesclient/spellname.db2\n12;interface/addons/x.lua\nabc;dbfilesclient/bad.db2\n",
        encoding="utf-8",
    )
    assert sc.db2_files(lf) == {"spellname": 1990283}


def test_wdb_records_counts_every_cache(tmp_path: Path):
    head = b"TSQW" + struct.pack("<I", 70170) + b"SUne" + b"\0" * 12
    body = struct.pack("<II", 7, 3) + b"abc" + struct.pack("<II", 9, 0) + struct.pack("<II", 0, 0)
    (tmp_path / "questcache.wdb").write_bytes(head + body)
    (tmp_path / "npccache.wdb").write_bytes(head + struct.pack("<II", 0, 0))
    (tmp_path / "pagetextcache.wdb").write_bytes(head + struct.pack("<II", 5, 99))
    assert sc.wdb_lines(tmp_path) == [
        "wdb-npccache.*  records=0",
        "wdb-pagetextcache.*  unreadable: pagetextcache.wdb: records run past the end of the file",
        "wdb-questcache.*  records=2",
    ]


def test_changes_name_what_a_build_added_dropped_and_moved():
    previous = {"a.f0": "rows=1  text=1  distinct=1", "b.f0": "rows=2  text=2  distinct=2"}
    current = {"a.f0": "rows=3  text=3  distinct=3", "c.f1": "rows=1  text=1  distinct=1"}
    assert sc.changes(previous, current) == [
        "new      c.f1  rows=1  text=1  distinct=1",
        "gone     b.f0  rows=2  text=2  distinct=2",
        "changed  a.f0  rows=1  text=1  distinct=1  ->  rows=3  text=3  distinct=3",
    ]


def test_the_committed_inventory_reads_back(root: Path):
    path = root / "pipeline" / "served_columns.txt"
    columns = sc.read_inventory(path)
    assert sc.inventory_build(path)
    assert columns["spell.f2"].startswith("rows=")  # the auras are a served column
    assert "wdb-questcache.*" in columns


@pytest.mark.parametrize("bad", [b"", b"\0" * 30])
def test_wdb_records_refuses_a_file_that_is_not_a_cache(tmp_path: Path, bad: bytes):
    path = tmp_path / "x.wdb"
    path.write_bytes(bad)
    with pytest.raises(ValueError):
        sc.wdb_records(path)
