"""Client tables from the local archive → wago-shaped CSVs, and the comparison."""

import re
import struct
from dataclasses import replace
from pathlib import Path

import pytest
from casc_fixture import PRODUCT, VERSION, blte_chunks, build
from db2_fixture import wdc5

from wfj.dev import client_tables as cli
from wfj.io import casc, client_tables, tables_stamp, wago

HEADERS = {
    "ItemSparse": ["ID", "Description_lang", "Display_lang"],
    "SpellName": ["ID", "Name_lang"],
    "Spell": ["ID", "NameSubtext_lang", "Description_lang", "AuraDescription_lang"],
    "GlobalStrings": ["BaseTag", "TagText_lang"],
    "ItemSubClass": ["DisplayName_lang", "VerboseName_lang", "ClassID", "SubClassID"],  # VerboseName: the long subclass name
    "SpellItemEnchantment": ["ID", "Name_lang"],
    "QuestV2": ["ID", "UniqueBitFlag"],
    "ItemEffect": ["ID", "LegacySlotIndex", "TriggerType", "SpellID", "ParentItemID"],
    # Forever's item -> item-effect join, which Classic Era does not ship (an `optional` table)
    "ItemXItemEffect": ["ID", "ItemEffectID", "ItemID"],
    # the client-table text families (ADR-042)
    "Faction": ["ID", "Description_lang"],
    "Achievement": ["ID", "Description_lang", "Title_lang", "Reward_lang"],
    "Achievement_Category": ["ID", "Name_lang"],
    "SkillLineCategory": ["ID", "Name_lang"],
    "SkillLine": ["ID", "Description_lang"],
    "EmotesTextData": ["ID", "Text_lang"],
    "HolidayDescriptions": ["ID", "Description_lang"],
    "CurrencyTypes": ["ID", "Description_lang"],
    "CurrencyCategory": ["ID", "Name_lang"],
    "SpellDispelType": ["ID", "Name_lang"],
    "CreatureType": ["ID", "Name_lang"],
    "QuestSort": ["ID", "SortName_lang"],
    "ChrCustomizationCategory": ["ID", "CategoryName_lang"],
    "ChrCustomizationOption": ["ID", "Name_lang"],
    "ChrCustomizationChoice": ["ID", "Name_lang"],
    "ChrCustomizationReq": ["ID", "ReqSource_lang"],
    "PVPScoreboardColumnHeader": ["ID", "Name_lang", "Tooltip_lang"],
    "GroupFinderCategory": ["ID", "Name_lang"],
    "GroupFinderActivityGrp": ["ID", "Name_lang"],
    "GroupFinderActivity": ["ID", "FullName_lang", "ShortName_lang"],
    "UiWidgetStringSource": ["ID", "Value_lang"],
    "ItemNameDescription": ["ID", "Description_lang"],
    "CriteriaTree": ["ID", "Description_lang"],
    "RenownRewards": ["ID", "Name_lang", "Description_lang", "ToastDescription_lang"],
    "SharedString": ["ID", "String_lang"],
    "TradeSkillCategory": ["ID", "Name_lang"],
    "MailTemplate": ["ID", "Body_lang"],
    "QuestInfo": ["ID", "InfoName_lang"],
    "AreaPOI": ["ID", "Description_lang"],
    "AreaPOIState": ["ID", "Description_lang"],
    "PetLoyalty": ["ID", "Name_lang"],
    "Map": ["ID", "PvpLongDescription_lang"],
    "Difficulty": ["ID", "Name_lang"],
    "UiEventToast": ["ID", "SubIcon_lang"],
    "BroadcastText": ["ID", "Text_lang"],
    "ItemPetFood": ["ID", "Name_lang"],
    "Exhaustion": ["ID", "Name_lang"],
    "ItemSubClassMask": ["ID", "Name_lang"],
    "RolodexType": ["ID", "Description_lang", "Field_11_2_5_62687_001_lang"],
    "FriendshipReputation": ["ID", "Description_lang", "StandingModified_lang"],
    "MapDifficulty": ["ID", "Message_lang"],
    "MapDifficultyXCondition": ["ID", "FailureDescription_lang"],
}


def _install(root: Path, tmp_path: Path) -> Path:
    """An install holding the two real tables cut from 1.15.9.69722."""
    files = {
        f"DBFilesClient\\{n}.db2": (root / "tests/fixtures/db2" / f"{n}.db2").read_bytes()
        for n in ("ItemSubClass", "QuestV2")
    }
    return build(tmp_path / "wow", files)


def test_registry_headers_are_wago_names():
    assert {n: [c.name for c in t.columns] for n, t in client_tables.TABLES.items()} == HEADERS


def test_cli_writes_csvs_the_importers_read(root: Path, tmp_path: Path, capsys):
    wow = _install(root, tmp_path)
    out = tmp_path / "out"
    assert cli.main(["--wow", str(wow), "--product", PRODUCT, "--out", str(out), "--tables", "ItemSubClass", "QuestV2"]) == 0
    printed = capsys.readouterr().out
    assert f"build: {VERSION} ({PRODUCT})" in printed
    assert "ItemSubClass: 72 rows" in printed
    assert "1 rows without" not in printed  # ItemSubClass writes no parent column
    # no temp folder left; the written tables stamped db2@<build>
    assert sorted(p.name for p in out.iterdir()) == ["ItemSubClass.csv", "QuestV2.csv", "tables-source.txt"]
    assert tables_stamp.read(out) == {"ItemSubClass": f"db2@{VERSION}", "QuestV2": f"db2@{VERSION}"}
    # VerboseName_lang is written too (the auction house's long subclass names)
    assert (out / "ItemSubClass.csv").read_text().splitlines()[0] == "DisplayName_lang,VerboseName_lang,ClassID,SubClassID"
    subclasses = wago.read_item_subclasses(out / "ItemSubClass.csv")
    assert subclasses == wago.read_item_subclasses(root / "tests/fixtures/db2/wago/ItemSubClass.csv")
    assert subclasses["ItemSubClass:1:0"] == "Bag"


def test_expect_build_refuses_another_build_before_writing(root: Path, tmp_path: Path, capsys):
    """A client's folder is pinned to one build; an install of another build writes nothing there."""
    wow = _install(root, tmp_path)
    out = tmp_path / "out"
    out.mkdir()
    (out / "QuestV2.csv").write_text("pinned\n")
    args = ["--wow", str(wow), "--product", PRODUCT, "--out", str(out), "--tables", "QuestV2"]
    assert cli.main([*args, "--expect-build", "1.0.0.1"]) == 1
    assert f"the install is build {VERSION}, --out is pinned to 1.0.0.1" in capsys.readouterr().err
    assert [p.name for p in out.iterdir()] == ["QuestV2.csv"] and (out / "QuestV2.csv").read_text() == "pinned\n"
    assert cli.main([*args, "--expect-build", VERSION]) == 0


def test_against_passes_on_the_same_build(root: Path, tmp_path: Path, capsys):
    wow = _install(root, tmp_path)
    args = ["--wow", str(wow), "--product", PRODUCT, "--out", str(tmp_path / "out"), "--tables", "ItemSubClass", "QuestV2"]
    assert cli.main([*args, "--against", str(root / "tests/fixtures/db2/wago")]) == 0
    printed = capsys.readouterr().out
    assert "against ItemSubClass.csv: 72 rows ours · 72 rows wago · 0 rows differ" in printed
    assert "importer reader: 0 keys differ" in printed


def test_against_fails_and_names_the_difference(root: Path, tmp_path: Path, capsys):
    wow = _install(root, tmp_path)
    theirs = tmp_path / "wago"
    theirs.mkdir()
    text = (root / "tests/fixtures/db2/wago/ItemSubClass.csv").read_text()
    (theirs / "ItemSubClass.csv").write_text(text.replace("\nBag,", "\nBagz,", 1))
    args = ["--wow", str(wow), "--product", PRODUCT, "--out", str(tmp_path / "out"), "--tables", "ItemSubClass"]
    assert cli.main([*args, "--against", str(theirs)]) == 1
    printed = capsys.readouterr().out
    assert "1 rows differ" in printed
    assert "ItemSubClass (1, 0) DisplayName_lang: ours 'Bag' · wago 'Bagz'" in printed
    assert "importer reader: 1 keys differ ['ItemSubClass:1:0']" in printed


def test_parsed_comparison_ignores_escaping_and_number_format(tmp_path: Path):
    table = client_tables.TABLES["SpellName"]
    (tmp_path / "a.csv").write_text('ID,Name_lang\n1,"two\\nlines"\n2,x\n')
    (tmp_path / "b.csv").write_text('ID,Name_lang,Extra\n01,"two\nlines",9\n2,"x "\n')
    assert client_tables.compare(table, tmp_path / "a.csv", tmp_path / "b.csv") == (2, 2, [])
    (tmp_path / "c.csv").write_text("ID,Name_lang\n1,two lines\n")
    n_a, n_c, diffs = client_tables.compare(table, tmp_path / "a.csv", tmp_path / "c.csv")
    assert [(d.key, d.column) for d in diffs] == [((1,), "Name_lang"), ((2,), "ID"), ((2,), "Name_lang")]


def test_write_csv_escapes_line_breaks_like_wago(tmp_path: Path):
    table = client_tables.TABLES["GlobalStrings"]
    ex = client_tables.Extracted(table, ["BaseTag", "TagText_lang"], [["TWO_LINES", "first\nsecond"]], [])
    client_tables.write_csv(ex, tmp_path / "GlobalStrings.csv")
    assert "first\\nsecond" in (tmp_path / "GlobalStrings.csv").read_text()
    assert wago.read_global_strings(tmp_path / "GlobalStrings.csv") == {"TWO_LINES": "first\nsecond"}


def test_layout_hash_change_stops_with_both_hashes(root: Path, tmp_path: Path):
    a = casc.LocalArchive(_install(root, tmp_path), PRODUCT)
    moved = replace(client_tables.TABLES["QuestV2"], layout_hash=0xDEADBEEF)
    with pytest.raises(client_tables.TableError, match="layout hash c6faa9aa/1f, column map verified on deadbeef/1f"):
        client_tables.extract(a, moved)


def test_field_count_change_stops(root: Path, tmp_path: Path):
    a = casc.LocalArchive(_install(root, tmp_path), PRODUCT)
    with pytest.raises(client_tables.TableError, match="layout hash c6faa9aa/1f, column map verified on c6faa9aa/2f"):
        client_tables.extract(a, replace(client_tables.TABLES["QuestV2"], field_count=2))


def test_rows_outside_the_relationship_map_get_parent_0_and_a_note(root: Path, tmp_path: Path):
    """As wago.tools writes it: ItemSubClass's map covers 71 of 72 records."""
    a = casc.LocalArchive(_install(root, tmp_path), PRODUCT)
    table = client_tables.Table(
        "ItemSubClass", 1261604, 0x1E67DB87, 11, (client_tables.Column("ID", "id"), client_tables.Column("P", "parent"))
    )
    ex = client_tables.extract(a, table)
    assert ex.rows[0] == [1, 0] and ex.rows[1] == [2, 1]
    assert ex.notes == ["1 rows without a P (written as 0)"]


def test_encrypted_section_is_reported_and_other_rows_written(root: Path, tmp_path: Path, capsys):
    buf, spans = wdc5([[(1, [5])], [(2, [6])]], field_count=1, layout_hash=0xC6FAA9AA)
    path = "DBFilesClient\\QuestV2.db2"
    blob = blte_chunks(buf, [spans[1][0]], encrypted={1})
    wow = build(tmp_path / "wow", {path: buf}, blobs={path: blob})
    out = tmp_path / "out"
    assert cli.main(["--wow", str(wow), "--product", PRODUCT, "--out", str(out), "--tables", "QuestV2"]) == 0
    assert "encrypted: section 1, 1 records skipped (key 0123456789abcdef)" in capsys.readouterr().out
    assert (out / "QuestV2.csv").read_text() == "ID,UniqueBitFlag\n1,5\n"


def test_unknown_table_and_missing_product_exit_1(root: Path, tmp_path: Path, capsys):
    wow = _install(root, tmp_path)
    assert cli.main(["--wow", str(wow), "--out", str(tmp_path / "o"), "--tables", "Nope"]) == 1
    assert cli.main(["--wow", str(wow), "--product", "wow_forever", "--out", str(tmp_path / "o")]) == 1
    err = capsys.readouterr().err
    assert "unknown table ['Nope']" in err and "no product 'wow_forever'" in err


STATIC = ("wfj/io/casc.py", "wfj/io/blte.py", "wfj/io/db2.py", "wfj/io/client_tables.py", "wfj/dev/client_tables.py")


@pytest.mark.parametrize("rel", STATIC)
def test_no_write_no_network_static(root: Path, rel: str):
    """The extraction code has no network import and opens nothing for writing except the CSV writer's
    output (write_text on the --out path in client_tables.write_csv)."""
    src = (root / "pipeline" / rel).read_text(encoding="utf-8")
    assert not re.search(r"^\s*(import|from)\s+(socket|urllib|http|requests|ssl)\b", src, re.M)
    assert not re.search(r"""open\([^)]*["'][wax+]""", src)
    writes = re.findall(r"\.(write_bytes|write_text|unlink|rename|mkdir|rmdir|touch)\(", src)
    allowed = {"wfj/io/client_tables.py": ["write_text"], "wfj/dev/client_tables.py": ["mkdir"]}  # --out only
    assert writes == allowed.get(rel, [])


def test_layout_change_is_reported_before_rows_are_decoded(tmp_path: Path):
    """A sparse table whose fields moved would fail decoding first; the layout message must win."""
    buf, _ = wdc5([[(1, ["a", 7, "b"])]], {0, 2}, field_count=3, sparse=True, layout_hash=0xAAAAAAAA)
    wow = build(tmp_path / "wow", {"DBFilesClient\\Spell.db2": buf})
    a = casc.LocalArchive(wow, PRODUCT)
    with pytest.raises(client_tables.TableError, match="layout hash aaaaaaaa/3f, column map verified on e3d134fb/3f"):
        client_tables.extract(a, client_tables.TABLES["Spell"])


def test_a_failed_table_writes_nothing_and_keeps_the_old_files(root: Path, tmp_path: Path, capsys):
    good, _ = wdc5([[(1, [5])]], field_count=1, layout_hash=0xC6FAA9AA)
    bad, _ = wdc5([[(1, [5])]], field_count=1, layout_hash=0x1E67DB87)  # ItemSubClass hash, 1 field
    wow = build(tmp_path / "wow", {"DBFilesClient\\QuestV2.db2": good, "DBFilesClient\\ItemSubClass.db2": bad})
    out = tmp_path / "out"
    out.mkdir()
    (out / "QuestV2.csv").write_text("old build\n")
    tables_stamp.write(out, ["QuestV2"], "wago@1.15.9.69722")
    args = ["--wow", str(wow), "--product", PRODUCT, "--out", str(out), "--tables", "ItemSubClass", "QuestV2"]
    assert cli.main(args) == 1
    assert "layout hash 1e67db87/1f, column map verified on 1e67db87/11f" in capsys.readouterr().err
    assert sorted(p.name for p in out.iterdir()) == ["QuestV2.csv", "tables-source.txt"]
    assert (out / "QuestV2.csv").read_text() == "old build\n"
    assert tables_stamp.read(out) == {"QuestV2": "wago@1.15.9.69722"}  # the old stamp stays with the old CSV


def test_out_inside_the_game_folder_is_refused(root: Path, tmp_path: Path, capsys):
    wow = _install(root, tmp_path)
    assert cli.main(["--wow", str(wow), "--product", PRODUCT, "--out", str(wow / "Data" / "csv")]) == 1
    assert "inside the game folder" in capsys.readouterr().err
    assert not (wow / "Data" / "csv").exists()


def test_extractor_run_is_read_only_and_offline(root: Path, tmp_path: Path, monkeypatch):
    """The whole extractor is read-only and offline: extract, decode, write CSVs outside the install."""
    import os
    import socket

    wow = _install(root, tmp_path)
    past = 1_000_000_000_000_000_000
    for p in wow.rglob("*"):
        if p.is_file():
            os.utime(p, ns=(past, past))
    before = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in wow.rglob("*") if p.is_file()}

    def no_socket(*a, **k):
        raise AssertionError("network access")

    monkeypatch.setattr(socket, "socket", no_socket)
    out = tmp_path / "out"
    assert cli.main(["--wow", str(wow), "--product", PRODUCT, "--out", str(out), "--tables", "ItemSubClass", "QuestV2"]) == 0
    assert {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in wow.rglob("*") if p.is_file()} == before
    assert sorted(p.name for p in out.iterdir()) == ["ItemSubClass.csv", "QuestV2.csv", "tables-source.txt"]


def test_number_columns_take_their_sign_from_the_declared_type(tmp_path: Path):
    """A packed value is cut to its declared size and signed only if the type is; a number column
    in a table that declares no field types is refused rather than guessed."""
    buf, _ = wdc5([[(1, [0xFFFFFFFF]), (2, [5])]], field_count=1, layout_hash=0xC6FAA9AA)
    a = casc.LocalArchive(build(tmp_path / "wow", {"DBFilesClient\\QuestV2.db2": buf}), PRODUCT)
    quest = client_tables.TABLES["QuestV2"]
    assert client_tables.extract(a, quest).rows == [[1, -1], [2, 5]]  # i32
    assert client_tables.extract(a, replace(quest, record=("u8",))).rows == [[1, 255], [2, 5]]
    assert client_tables.extract(a, replace(quest, record=("i8",))).rows == [[1, -1], [2, 5]]
    with pytest.raises(client_tables.TableError, match="UniqueBitFlag is a number column but the table declares"):
        client_tables.extract(a, replace(quest, record=()))


def test_the_real_item_subclass_fixture_reads_its_8_bit_ids(root: Path, tmp_path: Path):
    """The 1.15.9.69722 cut: ClassID / SubClassID are declared `<8>` and packed; the declared-type read keeps the
    values wago.tools writes."""
    a = casc.LocalArchive(_install(root, tmp_path), PRODUCT)
    ex = client_tables.extract(a, client_tables.TABLES["ItemSubClass"])
    got = {(r[2], r[3]) for r in ex.rows}  # VerboseName_lang is column 1
    theirs = client_tables.read_parsed(client_tables.TABLES["ItemSubClass"], root / "tests/fixtures/db2/wago/ItemSubClass.csv")
    assert got == set(theirs)


def test_carriage_returns_and_literal_backslash_n_round_trip_as_wago_parses_them(tmp_path: Path):
    """The stated convention: a line break is written as the two characters `\\n` and read back as
    a break, so a text that holds a literal backslash-n reads back as a break too (lossy, as wago.tools' own
    export). A carriage return stays inside the quoted cell. Our file and wago's parse to the same values, so the
    comparison stays exact."""
    table = client_tables.TABLES["GlobalStrings"]
    rows = [["CR", "a\rb"], ["LITERAL", "C:\\new"], ["BREAK", "one\ntwo"]]
    ex = client_tables.Extracted(table, ["BaseTag", "TagText_lang"], rows, [])
    ours = tmp_path / "GlobalStrings.csv"
    client_tables.write_csv(ex, ours)
    parsed = client_tables.read_parsed(table, ours)
    assert parsed[("CR",)]["TagText_lang"] == "a\rb"
    assert parsed[("LITERAL",)]["TagText_lang"] == "C:\new"  # the backslash-n became a break
    assert parsed[("BREAK",)]["TagText_lang"] == "one\ntwo"
    wago_csv = tmp_path / "wago.csv"
    wago_csv.write_text('BaseTag,TagText_lang\nCR,"a\rb"\nLITERAL,C:\\new\nBREAK,one\\ntwo\n', newline="")
    assert client_tables.compare(table, ours, wago_csv) == (3, 3, [])


@pytest.mark.parametrize(
    "table, text, key",
    [
        ("GlobalStrings", "BaseTag,TagText_lang\nOKAY,Okay\n OKAY ,Okay\n", "('OKAY',)"),
        ("ItemSubClass", "DisplayName_lang,VerboseName_lang,ClassID,SubClassID\nBag,,1,0\nBag,, 1 ,0\n", "(1, 0)"),
    ],
)
def test_keys_that_collide_after_parsing_raise(tmp_path: Path, table, text, key):
    """parse_value strips text and reads ints, so the key does too; a collision is an error, never
    two rows or a merge."""
    path = tmp_path / f"{table}.csv"
    path.write_text(text)
    with pytest.raises(client_tables.TableError, match=re.escape(f"row {key} listed twice")):
        client_tables.read_parsed(client_tables.TABLES[table], path)


def test_no_write_capable_call_touches_the_game_folder_at_runtime(root: Path, tmp_path: Path, monkeypatch):
    """The static test above only sees literal `open(..., "w")` modes. This wraps every write-capable
    entry point for a whole extractor run (hotfix cache included) and fails on any call whose path is inside the
    install, whatever the mode expression."""
    import builtins
    import io
    import os
    import shutil

    wow = _install(root, tmp_path)
    cache = wow / "_classic_era_" / "Cache" / "ADB" / "enUS"
    cache.mkdir(parents=True)
    (cache / "DBCache.bin").write_bytes(b"XFTH" + struct.pack("<II", 9, 99999) + bytes(32))
    game = wow.resolve()
    touched: list[str] = []

    def inside(path) -> bool:
        try:
            return Path(os.fsdecode(path)).resolve().is_relative_to(game)
        except (TypeError, ValueError):
            return False

    def guard_open(real):
        def wrapped(file, mode="r", *a, **k):
            if isinstance(mode, str) and set(mode) & set("wax+") and inside(file):
                touched.append(f"open {file} {mode}")
            return real(file, mode, *a, **k)

        return wrapped

    def guard_os_open(real):
        def wrapped(path, flags, *a, **k):
            if flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_APPEND | os.O_TRUNC) and inside(path):
                touched.append(f"os.open {path}")
            return real(path, flags, *a, **k)

        return wrapped

    def guard_path(name):
        real = getattr(Path, name)

        def wrapped(self, *a, **k):
            if inside(self):
                touched.append(f"Path.{name} {self}")
            return real(self, *a, **k)

        return wrapped

    def guard_two_paths(real, name):
        def wrapped(src, dst, *a, **k):
            if inside(src) or inside(dst):
                touched.append(f"{name} {src} {dst}")
            return real(src, dst, *a, **k)

        return wrapped

    monkeypatch.setattr(builtins, "open", guard_open(builtins.open))
    monkeypatch.setattr(io, "open", guard_open(io.open))
    monkeypatch.setattr(os, "open", guard_os_open(os.open))
    for name in ("write_bytes", "write_text", "touch", "unlink", "rename", "replace", "mkdir", "rmdir", "chmod"):
        monkeypatch.setattr(Path, name, guard_path(name))
    for name in ("move", "copy", "copy2", "copyfile", "copytree"):
        monkeypatch.setattr(shutil, name, guard_two_paths(getattr(shutil, name), name))
    out = tmp_path / "out"
    args = ["--wow", str(wow), "--product", PRODUCT, "--out", str(out), "--tables", "ItemSubClass", "QuestV2",
            "--hotfixes", str(cache / "DBCache.bin")]
    assert cli.main(args) == 0
    assert touched == []
    assert (out / "tables-source.txt").exists()  # the guard saw real writes happen, outside the install


def test_the_runtime_guard_catches_a_computed_write_mode(tmp_path: Path, monkeypatch):
    """The guard above is not vacuous: a write with a mode built at runtime is seen."""
    import builtins

    game = tmp_path / "game"
    game.mkdir()
    seen = []
    real = builtins.open

    def wrapped(file, mode="r", *a, **k):
        if set(mode) & set("wax+") and Path(file).resolve().is_relative_to(game.resolve()):
            seen.append(mode)
        return real(file, mode, *a, **k)

    monkeypatch.setattr(builtins, "open", wrapped)
    mode = "".join(["w", "b"])
    with open(game / "x", mode) as f:
        f.write(b"")
    assert seen == ["wb"]


# --- a table verified on more than one build -------------------------------------------------------
# Forever moved four tables' layouts. The mechanism that caught it (refuse an unverified layout rather than
# guess) is the thing that has to keep working, so these pin the map PER BUILD: a future bump cannot quietly
# re-point a column, because the column index for each verified layout is asserted here.

FOREVER = "1.60.1.69913"


@pytest.mark.parametrize(
    ("table", "layout", "fields"),
    [
        ("ItemSparse", 0x6FCC3191, 68),
        ("SpellItemEnchantment", 0x952B72B2, 24),
        ("QuestV2", 0x1854BDB9, 3),
        ("ItemEffect", 0x4CA77678, 9),
    ],
)
def test_the_forever_layouts_are_pinned_with_their_evidence(table, layout, fields):
    t = client_tables.TABLES[table]
    alt = [a for a in t.layouts if a.layout_hash == layout]
    assert alt, f"{table} is not pinned to Forever's layout {layout:08x}"
    assert alt[0].field_count == fields
    # a layout is verified against evidence, never bumped. The citation is part of the pin.
    assert FOREVER in alt[0].verified and "cross-build" in alt[0].verified


def test_questv2s_flag_column_is_per_build_not_global():
    """The one column Forever actually moved. Its id became an inline field 0, so UniqueBitFlag is field 1
    there and field 0 on Classic Era: 99.9% against the oracle, with fields 0 and 2 at 0.0%."""
    t = client_tables.TABLES["QuestV2"]
    assert [c.source for c in t.columns if c.name == "UniqueBitFlag"] == [0]
    forever = [a for a in t.layouts if a.layout_hash == 0x1854BDB9][0]
    assert forever.columns is not None, "Forever's QuestV2 must override the column map"
    assert [c.source for c in forever.columns if c.name == "UniqueBitFlag"] == [1]


def test_a_layout_that_moved_no_column_says_so_by_overriding_nothing():
    """ItemSparse lost six fields and SpellItemEnchantment gained two, but no text column moved. Leaving
    `columns` as None is the assertion that nothing moved; it must not be quietly re-stated."""
    for name in ("ItemSparse", "SpellItemEnchantment", "ItemEffect"):
        for alt in client_tables.TABLES[name].layouts:
            assert alt.columns is None, f"{name}: {alt.layout_hash:08x} restates its columns"


def test_an_unverified_layout_names_every_verified_one(root: Path, tmp_path: Path):
    """The refusal has to tell a reader what HAS been verified, or the next person cannot tell whether the
    map is wrong or merely unproven on this build."""
    a = casc.LocalArchive(_install(root, tmp_path), PRODUCT)
    with pytest.raises(client_tables.TableError) as e:
        client_tables.extract(a, replace(client_tables.TABLES["QuestV2"], layout_hash=0xDEADBEEF))
    msg = str(e.value)
    assert "deadbeef/1f" in msg and "1854bdb9/3f" in msg  # its own and its Forever alternate
    assert "needs re-verifying" in msg


# --- a table only some builds ship ----------------------------------------------------------------

def test_an_optional_table_absent_from_the_root_is_reported_not_a_failure(root: Path, tmp_path: Path, capsys):
    """Classic Era names no enUS content for ItemXItemEffect because it does the join inline. Before this,
    adding the table broke the Classic Era pull entirely (client_tables is all-or-nothing)."""
    wow = _install(root, tmp_path)
    out = tmp_path / "out"
    assert cli.main(["--wow", str(wow), "--product", PRODUCT, "--out", str(out),
                     "--tables", "QuestV2", "ItemXItemEffect"]) == 0
    printed = capsys.readouterr().out
    assert "ItemXItemEffect: not shipped on this build" in printed
    assert (out / "QuestV2.csv").exists()
    assert not (out / "ItemXItemEffect.csv").exists()


def test_only_absence_is_forgiven_for_an_optional_table(root: Path, tmp_path: Path):
    """A table that IS there and will not read still fails the run; otherwise an encrypted or truncated
    table would quietly read as "this build doesn't have it"."""
    files = {"DBFilesClient\\ItemXItemEffect.db2": b"not a db2 at all"}
    wow = build(tmp_path / "wow2", files)
    a = casc.LocalArchive(wow, PRODUCT)
    with pytest.raises(client_tables.TableError):
        client_tables.extract(a, client_tables.TABLES["ItemXItemEffect"])


def test_compare_skips_only_a_relation_column_the_other_export_leaves_out(tmp_path: Path):
    """Forever's ItemEffect has no parent relation: ours writes ParentItemID 0, wago.tools drops the column.
    The other columns are still compared; a missing record column is still an error."""
    table = client_tables.TABLES["ItemEffect"]
    ours, theirs = tmp_path / "ours.csv", tmp_path / "theirs.csv"
    ours.write_text("ID,LegacySlotIndex,TriggerType,SpellID,ParentItemID\n1,0,0,100,0\n2,0,1,200,0\n")
    theirs.write_text("ID,LegacySlotIndex,TriggerType,Charges,SpellID\n1,0,0,0,100\n2,0,1,0,201\n")
    assert client_tables.skipped_columns(table, theirs) == ["ParentItemID"]
    n_ours, n_theirs, diffs = client_tables.compare(table, ours, theirs)
    assert (n_ours, n_theirs) == (2, 2)
    assert [(d.key, d.column, d.ours, d.theirs) for d in diffs] == [((2,), "SpellID", 200, 201)]
    theirs.write_text("ID,LegacySlotIndex,TriggerType\n1,0,0\n")  # a record column gone: not skipped
    with pytest.raises(client_tables.TableError, match="no column"):
        client_tables.compare(table, ours, theirs)
