"""The client's hotfix cache, DBCache.bin: reading it and applying it to the client tables."""

import struct
from pathlib import Path

import pytest
from casc_fixture import PRODUCT, build
from db2_fixture import wdc5

from wfj.dev import client_tables as cli
from wfj.io import casc, client_tables, dbcache

SPELLNAME_HASH = 0x46C66698  # SpellName's table hash on 1.15.9.69722


def cache(entries, build_no=99999, version=9) -> bytes:
    """entries: (table hash, record id, push id, status, data)."""
    out = b"XFTH" + struct.pack("<II", version, build_no) + bytes(32)
    for table, record, push, status, data in entries:
        out += b"XFTH" + struct.pack("<iiIIIIB3x", 81, push, 0, table, record, len(data), status) + data
    return out


def test_the_last_entry_of_a_record_decides_it(tmp_path: Path):
    """Applied in (push id, file order) order, as DBCD's hotfix reader: valid with data replaces; any other entry
    (removed, invalidated, not public, valid without data) removes."""
    p = tmp_path / "DBCache.bin"
    p.write_bytes(cache([
        (SPELLNAME_HASH, 1, 10, 1, b"Old\0"),
        (SPELLNAME_HASH, 1, 12, 1, b"New\0"),
        (SPELLNAME_HASH, 1, 11, 1, b"Middle\0"),
        (SPELLNAME_HASH, 2, 10, 2, b""),
        (SPELLNAME_HASH, 3, 10, 1, b"valid first\0"),
        (SPELLNAME_HASH, 3, 20, 3, b""),  # a later invalidation withdraws it
        (SPELLNAME_HASH, 4, -1, 1, b"cached A\0"),
        (SPELLNAME_HASH, 4, -1, 1, b"cached B\0"),  # equal push ids: the later entry in the file wins
        (SPELLNAME_HASH, 5, 10, 1, b""),  # valid without data: removes
        (SPELLNAME_HASH, 6, 10, 4, b"not public\0"),
        (0x12345678, 1, 10, 1, b"another table\0"),
    ]))
    c = dbcache.read(p)
    assert c.build == 99999
    rows = c.by_table[SPELLNAME_HASH]
    assert rows[1].replaces and rows[1].data == b"New\0"
    assert rows[4].replaces and rows[4].data == b"cached B\0"
    assert [r for r in sorted(rows) if not rows[r].replaces] == [2, 3, 5, 6]


@pytest.mark.parametrize(
    "blob, message",
    [
        (b"NOPE" + bytes(40), "not a hotfix cache"),
        (cache([], version=8), "version 8 is not 9"),
        (cache([(SPELLNAME_HASH, 1, 1, 1, b"x\0")])[:-1], "runs past the end"),
        (cache([(SPELLNAME_HASH, 1, 1, 7, b"")]), "unknown status 7"),
    ],
)
def test_malformed_caches_stop(tmp_path: Path, blob, message):
    p = tmp_path / "DBCache.bin"
    p.write_bytes(blob)
    with pytest.raises(dbcache.DbcacheError, match=message):
        dbcache.read(p)


def test_leading_strings():
    assert dbcache.leading_strings(b"a\0b\0\x01\0\0\0", 2) == ["a", "b"]
    with pytest.raises(ValueError, match="string 1 has no terminator"):
        dbcache.leading_strings(b"a\0b", 2)


def _install(tmp_path: Path) -> Path:
    buf, _ = wdc5(
        [[(1, ["Fireball"]), (2, ["Frostbolt"]), (3, ["Arcane Missiles"])]],
        {0}, field_count=1, layout_hash=0x782EE721, table_hash=SPELLNAME_HASH,
    )
    return build(tmp_path / "wow", {"DBFilesClient\\SpellName.db2": buf})


def test_hotfixes_replace_add_and_remove_rows(tmp_path: Path, capsys):
    wow = _install(tmp_path)
    fix = tmp_path / "DBCache.bin"
    fix.write_bytes(cache([
        (SPELLNAME_HASH, 1, 5, 1, b"Fireball (hotfixed)\0"),
        (SPELLNAME_HASH, 2, 5, 2, b""),
        (SPELLNAME_HASH, 9, 5, 1, b"Brand New Spell\0"),
    ]))
    out = tmp_path / "out"
    args = ["--wow", str(wow), "--product", PRODUCT, "--out", str(out), "--tables", "SpellName", "--hotfixes", str(fix)]
    assert cli.main(args) == 0
    printed = capsys.readouterr().out
    assert f"hotfixes: {fix}" in printed
    assert "hotfixes: 1 rows replaced, 1 added, 1 removed" in printed
    assert (out / "SpellName.csv").read_text() == (
        "ID,Name_lang\n1,Fireball (hotfixed)\n3,Arcane Missiles\n9,Brand New Spell\n"
    )


def test_a_missing_cache_means_no_hotfixes(tmp_path: Path, capsys):
    wow = _install(tmp_path)
    args = ["--wow", str(wow), "--product", PRODUCT, "--out", str(tmp_path / "out"), "--tables", "SpellName",
            "--hotfixes", str(tmp_path / "absent.bin")]
    assert cli.main(args) == 0
    assert f"hotfixes: none (no cache file at {tmp_path / 'absent.bin'})" in capsys.readouterr().out


def test_a_hotfix_path_that_is_a_folder_is_refused(tmp_path: Path, capsys):
    wow = _install(tmp_path)
    args = ["--wow", str(wow), "--product", PRODUCT, "--out", str(tmp_path / "out"), "--hotfixes", str(tmp_path)]
    assert cli.main(args) == 1
    assert "is not a file" in capsys.readouterr().err


def test_a_cache_of_another_build_is_refused(tmp_path: Path, capsys):
    wow = _install(tmp_path)
    fix = tmp_path / "DBCache.bin"
    fix.write_bytes(cache([], build_no=12345))
    args = ["--wow", str(wow), "--product", PRODUCT, "--out", str(tmp_path / "out"), "--hotfixes", str(fix)]
    assert cli.main(args) == 1
    assert "DBCache.bin is build 12345, the archive is 1.15.9.99999" in capsys.readouterr().err


QUESTV2_HASH, ITEMEFFECT_HASH, ITEMSUBCLASS_HASH = 0x3AC83109, 0x11111111, 0x22222222


def _numbers_install(tmp_path: Path) -> Path:
    """QuestV2, ItemEffect and ItemSubClass as the fixture writer builds them (32-bit plain fields)."""
    quest, _ = wdc5([[(1, [5]), (2, [6])]], field_count=1, layout_hash=0xC6FAA9AA, table_hash=QUESTV2_HASH)
    effect, _ = wdc5(
        [[(10, [1, 0, 0, 0, 0, 0, 111, 0, 0])]], field_count=9, layout_hash=0x1BF9CF3A, table_hash=ITEMEFFECT_HASH
    )
    sub, _ = wdc5(
        [[(1, ["Axe", "", 1, 1, 2, 0, 0, 0, 0, 0, 0])]],
        {0, 1},
        field_count=11,
        layout_hash=0x1E67DB87,
        table_hash=ITEMSUBCLASS_HASH,
    )
    return build(
        tmp_path / "wow",
        {
            "DBFilesClient\\QuestV2.db2": quest,
            "DBFilesClient\\ItemEffect.db2": effect,
            "DBFilesClient\\ItemSubClass.db2": sub,
        },
    )


def _effect(slot, trigger, spell, parent, charges=-1) -> bytes:
    """An ItemEffect hotfix record at its declared sizes (WoWDBDefs 1BF9CF3A), ParentItemID last."""
    return struct.pack("<BBhiiHiHii", slot, trigger, charges, 0, 0, 0, spell, 0, 0, parent)


def test_hotfixes_to_number_columns_apply(tmp_path: Path, capsys):
    """QuestV2 UniqueBitFlag, ItemEffect LegacySlotIndex / SpellID / ParentItemID and ItemSubClass
    ClassID / SubClassID are decoded from the hotfix record by declared types; removals count."""
    wow = _numbers_install(tmp_path)
    sub = b"Two-Handed Axes\0" + b"\0" + struct.pack("<ibbBbiibb", 7, 1, 1, 0, 0, 0, 0, 0, 0)
    fix = tmp_path / "DBCache.bin"
    fix.write_bytes(cache([
        (QUESTV2_HASH, 1, 5, 1, struct.pack("<i", 7)),
        (QUESTV2_HASH, 2, 5, 2, b""),
        (ITEMEFFECT_HASH, 10, 5, 1, _effect(2, 0, 222, 19019)),
        (ITEMSUBCLASS_HASH, 7, 5, 1, sub),
    ]))
    out = tmp_path / "out"
    args = ["--wow", str(wow), "--product", PRODUCT, "--out", str(out), "--tables", "QuestV2", "ItemEffect",
            "ItemSubClass", "--hotfixes", str(fix)]
    assert cli.main(args) == 0
    printed = capsys.readouterr().out
    assert "NOT APPLIED" not in printed
    assert "hotfixes: 1 rows replaced, 0 added, 1 removed" in printed  # QuestV2
    assert "hotfixes: 0 rows replaced, 1 added, 0 removed" in printed  # ItemSubClass
    assert (out / "QuestV2.csv").read_text() == "ID,UniqueBitFlag\n1,7\n"
    assert (out / "ItemEffect.csv").read_text() == (
        "ID,LegacySlotIndex,TriggerType,SpellID,ParentItemID\n10,2,0,222,19019\n"
    )
    assert (out / "ItemSubClass.csv").read_text() == (
        # VerboseName_lang is written too (empty in both records)
        "DisplayName_lang,VerboseName_lang,ClassID,SubClassID\nAxe,,1,2\nTwo-Handed Axes,,1,1\n"
    )


@pytest.mark.parametrize(
    "data, message",
    [
        (_effect(2, 0, 222, 19019)[:-1], "field 9 \\(i32\\) runs past the 27-byte record"),
        (_effect(2, 0, 222, 19019) + b"\0\0\0\0", "record of 32 bytes, its 10 fields use 28"),
        (_effect(2, 0, 222, 19019) + b"\x01", "record of 29 bytes"),
        # Charges read as 2 bytes when the record holds 4 (30 bytes, 2 zero bytes past an aligned
        # 28) must stop, not decode SpellID / ParentItemID shifted
        (struct.pack("<BBiiiHiHii", 0, 1, 0, 0, 0, 0, 12345, 0, 0, 19019), "record of 30 bytes, its 10 fields use 28"),
    ],
)
def test_a_hotfix_record_that_does_not_fit_its_declared_fields_stops_the_table(tmp_path: Path, data, message):
    """Safety net: a wrong layout never writes shifted values: the table stops, naming the row."""
    a = casc.LocalArchive(_numbers_install(tmp_path), PRODUCT)
    fix = tmp_path / "DBCache.bin"
    fix.write_bytes(cache([(ITEMEFFECT_HASH, 10, 5, 1, data)]))
    with pytest.raises(client_tables.TableError, match=f"ItemEffect: hotfix of row 10: {message}"):
        client_tables.extract(a, client_tables.TABLES["ItemEffect"], dbcache.read(fix))


FOREVER_ITEMEFFECT_LAYOUT = 0x4CA77678  # 1.60.1.69913: the same nine fields, no relationship map (ADR-027)


def _forever_effect_install(tmp_path: Path) -> Path:
    effect, _ = wdc5(
        [[(97156, [1, 1, 0, -1, -1, 0, 18799, 0, 0])]],
        field_count=9,
        layout_hash=FOREVER_ITEMEFFECT_LAYOUT,
        table_hash=ITEMEFFECT_HASH,
    )
    return build(tmp_path / "wow", {"DBFilesClient\\ItemEffect.db2": effect})


def test_a_forever_itemeffect_hotfix_has_no_relation_and_writes_parent_0(tmp_path: Path):
    """Forever's ItemEffect has no relationship map, so its hotfix record is the nine fields alone: 24
    bytes, as both ItemEffect entries in 1.60.1.69913's own DBCache.bin are. ParentItemID is 0, as for its archive
    rows (the item comes from ItemXItemEffect)."""
    a = casc.LocalArchive(_forever_effect_install(tmp_path), PRODUCT)
    fix = tmp_path / "DBCache.bin"
    record = _effect(1, 1, 18799, 0)[:-4]  # the real 97156 entry: nine fields, no ParentItemID
    assert len(record) == 24
    fix.write_bytes(cache([(ITEMEFFECT_HASH, 97156, 112078, 1, record), (ITEMEFFECT_HASH, 100060, 112078, 1,
                                                                        _effect(0, 1, 19786, 0)[:-4])]))
    ex = client_tables.extract(a, client_tables.TABLES["ItemEffect"], dbcache.read(fix))
    assert ex.hotfixed == {"replaced": 1, "added": 1, "removed": 0}
    assert ex.rows == [[97156, 1, 1, 18799, 0], [100060, 0, 1, 19786, 0]]


def test_a_classic_era_itemeffect_record_on_the_forever_layout_stops(tmp_path: Path):
    """The 28-byte Classic Era record (with ParentItemID) does not fit Forever's nine fields; the
    table stops rather than dropping four bytes."""
    a = casc.LocalArchive(_forever_effect_install(tmp_path), PRODUCT)
    fix = tmp_path / "DBCache.bin"
    fix.write_bytes(cache([(ITEMEFFECT_HASH, 97156, 5, 1, _effect(1, 1, 18799, 19019))]))
    with pytest.raises(client_tables.TableError, match="hotfix of row 97156: record of 28 bytes, its 9 fields use 24"):
        client_tables.extract(a, client_tables.TABLES["ItemEffect"], dbcache.read(fix))


def test_decode_fields_sizes_signs_strings_and_padding():
    data = b"Axe\0" + struct.pack("<bBhHiI", -1, 255, -2, 65535, -3, 4_000_000_000) + b"\0\0"
    assert dbcache.decode_fields(data, ("str", "i8", "u8", "i16", "u16", "i32", "u32")) == [
        "Axe", -1, 255, -2, 65535, -3, 4_000_000_000,
    ]
    with pytest.raises(ValueError, match="string field 0 has no terminator"):
        dbcache.decode_fields(b"Axe", ("str",))
    # zero padding only up to the next 4-byte boundary: 5 bytes used → 8 ok, 12 refused
    assert dbcache.decode_fields(b"Ab\0\x07\0\0\0\0", ("str", "u16")) == ["Ab", 7]
    with pytest.raises(ValueError, match="record of 12 bytes, its 2 fields use 5"):
        dbcache.decode_fields(b"Ab\0\x07\0" + bytes(7), ("str", "u16"))


def test_against_excuses_a_hotfixed_row_only_where_wago_holds_the_archive_value(tmp_path: Path, capsys):
    wow = _install(tmp_path)
    fix = tmp_path / "DBCache.bin"
    fix.write_bytes(cache([(SPELLNAME_HASH, 1, 5, 1, b"Fireball (hotfixed)\0")]))
    wago = tmp_path / "wago"
    wago.mkdir()
    base = ["--wow", str(wow), "--product", PRODUCT, "--out", str(tmp_path / "out"), "--tables", "SpellName",
            "--hotfixes", str(fix), "--against", str(wago)]
    (wago / "SpellName.csv").write_text("ID,Name_lang\n1,Fireball\n2,Frostbolt\n3,Arcane Missiles\n")
    assert cli.main(base) == 0  # wago lacks the hotfix: excused, listed apart
    assert "differ only where a hotfix applied: 1 rows" in capsys.readouterr().out
    (wago / "SpellName.csv").write_text("ID,Name_lang\n1,Fireball (fixed)\n2,Frostbolt\n3,Arcane Missiles\n")
    assert cli.main(base) == 1  # differs from both the archive and our decode: a failure
    assert "1 rows differ" in capsys.readouterr().out


def test_every_table_can_take_its_hotfixes():
    """A table either writes only its id and leading strings, or declares every field's type (plus the
    non-inline relation when it writes one); no table is left pre-hotfix."""
    for name, t in client_tables.TABLES.items():
        if not t.record:
            assert t.text_only, name
            continue
        parent = any(c.source == client_tables.PARENT for c in t.columns)
        assert len(t.record) == t.field_count + parent, name
        assert all(ty == "str" for n, ty in enumerate(t.record) if n in t.string_fields), name
        assert set(t.record) <= {"str", *dbcache.TYPES}, name
        # a build's own record is the fields plus the relation of a table that writes one, except a
        # build seen to have no relationship map, which declares the fields alone. Only Forever's ItemEffect
        # (every section's relationship_data_size 0, its hotfix records 24 bytes on 1.60.1.69913) is one.
        for alt in t.layouts:
            if alt.record is None:
                continue
            relationless = parent and len(alt.record) == alt.field_count
            assert len(alt.record) == alt.field_count + parent or relationless, (name, hex(alt.layout_hash))
            assert not relationless or (name, alt.layout_hash) == ("ItemEffect", 0x4CA77678), (name, hex(alt.layout_hash))
            assert set(alt.record) <= {"str", *dbcache.TYPES}, (name, hex(alt.layout_hash))
    assert {n for n, t in client_tables.TABLES.items() if t.record} == {
        "QuestV2", "ItemEffect", "ItemSubClass", "ItemXItemEffect"
    }
