"""The WDC5 reader: real tables cut from Classic Era 1.15.9.69722 and synthetic ones."""

import csv
import struct
from pathlib import Path

import pytest
from db2_fixture import wdc5

from wfj.io import db2


def _wago(root: Path, name: str) -> list[dict[str, str]]:
    with (root / "tests/fixtures/db2/wago" / f"{name}.csv").open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def _signed(v: int, bits: int = 32) -> int:
    return v - (1 << bits) if v >= 1 << (bits - 1) else v


def test_real_itemsubclass_matches_wago(root: Path):
    """Inline id, string table, signed bitpacked, pallet and common-data fields, a partial relationship map."""
    t = db2.read((root / "tests/fixtures/db2/ItemSubClass.db2").read_bytes(), frozenset({0, 1}), name="ItemSubClass")
    assert t.layout_hash == 0x1E67DB87
    rows = _wago(root, "ItemSubClass")
    assert len(t.rows) == len(rows) == 72
    for w in rows:
        r = t.rows[int(w["ID"])]
        assert (r[0], r[1]) == (w["DisplayName_lang"], w["VerboseName_lang"])
        assert (r[3], r[4]) == (int(w["ClassID"]), int(w["SubClassID"]))
        assert r[5] == int(w["AuctionHouseSortOrder"])  # common data
        assert r[7] == int(w["Flags"])  # pallet
        assert r[9] == int(w["WeaponSwingSize"])  # common data
    assert t.relation[2] == 1 and 1 not in t.relation  # the map covers 71 of 72 records


def test_real_questv2_matches_wago(root: Path):
    """Id list, a copy table and a signed bitpacked field."""
    t = db2.read((root / "tests/fixtures/db2/QuestV2.db2").read_bytes(), name="QuestV2")
    rows = _wago(root, "QuestV2")
    assert {i: r[0] for i, r in t.rows.items()} == {int(w["ID"]): int(w["UniqueBitFlag"]) for w in rows}


def test_dense_strings_across_two_sections():
    buf, _ = wdc5([[(10, ["alpha", 7]), (11, ["", 8])], [(20, ["beta", -1])]], {0}, field_count=2)
    t = db2.read(buf, frozenset({0}))
    assert {i: (r[0], _signed(r[1])) for i, r in t.rows.items()} == {
        10: ("alpha", 7),
        11: ("", 8),
        20: ("beta", -1),
    }


def test_sparse_inline_strings_padding_and_copies():
    buf, _ = wdc5(
        [[(5, ["a", "line one\nline two", 42]), (6, ["", "", 0])]],
        {0, 1},
        field_count=3,
        sparse=True,
        copies=[(9, 5)],
    )
    t = db2.read(buf, frozenset({0, 1}))
    assert t.rows == {5: ("a", "line one\nline two", 42), 6: ("", "", 0), 9: ("a", "line one\nline two", 42)}


def test_encrypted_section_is_skipped_and_counted():
    buf, spans = wdc5([[(1, ["kept"])], [(2, ["secret"]), (3, ["also"])]], {0}, field_count=1)
    start, end = spans[1]
    t = db2.read(buf[:start] + bytes(end - start) + buf[end:], frozenset({0}), [(start, end, "0123456789abcdef")])
    assert t.rows == {1: ("kept",)}
    assert [(s.section, s.records, s.key_name) for s in t.skipped] == [(1, 2, "0123456789abcdef")]


def test_bad_magic():
    with pytest.raises(db2.Db2Error, match="magic b'WDC3'"):
        db2.read(b"WDC3" + bytes(300))


def test_version_other_than_5():
    buf, _ = wdc5([[(1, [1])]], field_count=1, version=6)
    with pytest.raises(db2.Db2Error, match="version 6"):
        db2.read(buf)


def test_duplicate_id_is_reported():
    buf, _ = wdc5([[(1, [1])], [(1, [2])]], field_count=1)
    with pytest.raises(db2.Db2Error, match="id 1 appears twice"):
        db2.read(buf)


def test_copy_onto_an_existing_id_is_reported():
    buf, _ = wdc5([[(1, [1]), (2, [2])]], field_count=1, copies=[(2, 1)])
    with pytest.raises(db2.Db2Error, match="copied id 2 appears twice"):
        db2.read(buf)


def test_string_offset_past_the_tables():
    buf, _ = wdc5([[(1, ["x"])]], {0}, field_count=1)
    rec_at = db2.HEADER.size + db2.SECTION.size + 4 + 24
    bad = buf[:rec_at] + struct.pack("<I", 10_000) + buf[rec_at + 4 :]
    with pytest.raises(db2.Db2Error, match="points past the string tables"):
        db2.read(bad, frozenset({0}))


def test_undeclared_sparse_string_is_caught():
    """A sparse string field read as an int leaves bytes over: the record does not fit."""
    buf, _ = wdc5([[(1, ["hello world", 3])]], {0}, field_count=2, sparse=True)
    with pytest.raises(db2.Db2Error, match="sparse record"):
        db2.read(buf, frozenset())


def test_sections_disagreeing_with_the_header():
    buf, _ = wdc5([[(1, [1]), (2, [2])]], field_count=1)
    bad = bytearray(buf)
    struct.pack_into("<I", bad, 136, 3)  # header record count
    with pytest.raises(db2.Db2Error, match="sections hold 2 records, header 3"):
        db2.read(bytes(bad))


def test_section_past_the_end_of_the_file():
    buf, _ = wdc5([[(1, [1]), (2, [2])]], field_count=1)
    with pytest.raises(db2.Db2Error, match="runs past the file"):
        db2.read(buf[:-4])


def test_keyed_zero_filled_section_is_skipped_not_read():
    """A section with a TACT key whose bytes the file already carries as zeros (no E frame): one record would
    otherwise read as row 0."""
    buf, spans = wdc5([[(1, [5])], [(2, [6])]], field_count=1, keys=[0, 0xFEEDFACE])
    start, end = spans[1]
    t = db2.read(buf[:start] + bytes(end - start) + buf[end:])
    assert t.rows == {1: (5,)}
    assert [(s.section, s.key_name) for s in t.skipped] == [(1, "00000000feedface")]


def test_unkeyed_section_is_read_even_when_zero():
    buf, _ = wdc5([[(0, [0])]], field_count=1)
    assert db2.read(buf).rows == {0: (0,)}


def test_encrypted_bytes_in_the_header_blocks_stop():
    buf, spans = wdc5([[(1, [5])]], field_count=1)
    with pytest.raises(db2.Db2Error, match="encrypted bytes inside the header blocks"):
        db2.read(buf, encrypted=[(db2.HEADER.size, spans[0][0], "0123456789abcdef")])


def test_copy_source_in_a_later_section_and_self_copy():
    buf, _ = wdc5([[(1, [5])], [(2, [6])]], field_count=1, copies=[(3, 2), (2, 2)])
    assert db2.read(buf).rows == {1: (5,), 2: (6,), 3: (6,)}


def test_copy_of_a_row_in_a_skipped_section_is_counted_hidden():
    buf, spans = wdc5([[(1, [5])], [(2, [6])]], field_count=1, copies=[(3, 1)])
    start, end = spans[0]
    t = db2.read(buf[:start] + bytes(end - start) + buf[end:], encrypted=[(start, end, "0123456789abcdef")])
    assert t.rows == {2: (6,)}
    assert t.copies_hidden == 1


def test_truncated_header_blocks_name_the_table():
    buf, _ = wdc5([[(1, [5])]], field_count=1)
    with pytest.raises(db2.Db2Error, match="QuestV2: header blocks run past the file"):
        db2.read(buf[: db2.HEADER.size + 8], name="QuestV2")


def test_unguarded_decode_errors_become_a_named_error(monkeypatch):
    """The last line of defence: a struct / index error from any unchecked read names the table."""
    buf, _ = wdc5([[(1, [5])]], field_count=1)

    def short(*a, **k):
        raise struct.error("unpack_from requires a buffer of at least 4 bytes")

    monkeypatch.setattr(db2, "_dense_values", short)
    with pytest.raises(db2.Db2Error, match=r"^T: truncated or corrupt \(error: unpack_from"):
        db2.read(buf, name="T")


def test_secondary_key_tables_are_not_guessed():
    buf, _ = wdc5([[(1, [5])]], field_count=1, extra_flags=0x2)
    with pytest.raises(db2.Db2Error, match="secondary-key table"):
        db2.read(buf)


def test_pallet_array_fields_decode_to_per_row_arrays():
    """Storage type 4: each record holds an index into the pallet, whose entries are `v3` u32 values
    each. No real table the pipeline reads uses it, so this builds one: 1 field, 3 values per entry, 2 entries."""
    count = 3
    pallet = struct.pack("<6I", 1, 2, 3, 70000, 0xFFFFFFFF, 9)  # entry 0: [1, 2, 3] · entry 1: [70000, max, 9]
    field_count, record_size = 1, 1
    rows = [(10, 1), (11, 0), (12, 1)]  # (id, pallet index)
    records = bytes(index for _, index in rows)
    ids = b"".join(struct.pack("<I", i) for i, _ in rows)
    fields = struct.pack("<hH", 0, 0)
    storage = struct.pack("<HHIIIII", 0, 8, len(pallet), db2.PALLET_ARRAY, 0, 0, count)
    head = db2.HEADER.size + db2.SECTION.size + len(fields) + len(storage) + len(pallet)
    section = db2.SECTION.pack(0, head, len(rows), 0, 0, len(ids), 0, 0, 0)
    header = db2.HEADER.pack(
        b"WDC5", 5, b"\0" * 128, len(rows), field_count, record_size, 0, 0, 0x1234, 10, 12, 0, 0x4, 0,
        field_count, 0, 0, 24 * field_count, 0, len(pallet), 1,
    )
    t = db2.read(header + section + fields + storage + pallet + records + ids)
    assert t.rows == {10: ([70000, 0xFFFFFFFF, 9],), 11: ([1, 2, 3],), 12: ([70000, 0xFFFFFFFF, 9],)}


def test_a_pallet_array_index_past_the_pallet_is_an_error():
    pallet = struct.pack("<3I", 1, 2, 3)
    storage = struct.pack("<HHIIIII", 0, 8, len(pallet), db2.PALLET_ARRAY, 0, 0, 3)
    fields = struct.pack("<hH", 0, 0)
    head = db2.HEADER.size + db2.SECTION.size + len(fields) + len(storage) + len(pallet)
    ids = struct.pack("<I", 1)
    section = db2.SECTION.pack(0, head, 1, 0, 0, len(ids), 0, 0, 0)
    header = db2.HEADER.pack(b"WDC5", 5, b"\0" * 128, 1, 1, 1, 0, 0, 0x1234, 1, 1, 0, 0x4, 0, 1, 0, 0, 24, 0,
                             len(pallet), 1)
    with pytest.raises(db2.Db2Error, match="field 0 pallet index 1 is past its 3 values"):
        db2.read(header + section + fields + storage + pallet + b"\x01" + ids)
