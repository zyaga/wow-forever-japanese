"""The client-table CSVs carry a source stamp, and the imports refuse a CSV whose stamp is missing or
names another source or build."""

from pathlib import Path

import pytest

from wfj.cmd.import_ import run
from wfj.dev import tables_stamp as stamp_cli
from wfj.io import tables_stamp
from wfj.io.jsonl_store import Store

BUILD = "1.15.9.69722"


def _data(tmp_path: Path, monkeypatch) -> Path:
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    return data


def _names(folder: Path) -> tuple[Path, Path]:
    folder.mkdir(exist_ok=True)
    item = folder / "ItemSparse.csv"
    item.write_text('ID,Description_lang,Display_lang\n117,,"Tough Jerky"\n')
    spell = folder / "SpellName.csv"
    spell.write_text("ID,Name_lang\n433,Food\n")
    return item, spell


def _wago_ids(item: Path, spell: Path, src: str = "wago", build: str = BUILD) -> int:
    return run(["english", "wago-ids", str(item), str(spell), "--build", build, "--src", src])


def test_a_stamped_csv_imports(tmp_path, monkeypatch):
    data = _data(tmp_path, monkeypatch)
    item, spell = _names(tmp_path / "inputs")
    tables_stamp.write(tmp_path / "inputs", ["ItemSparse", "SpellName"], f"wago@{BUILD}")
    assert _wago_ids(item, spell) == 0
    assert {ln["src"] for ln in Store(data, english=True).load("item")} == {f"wago@{BUILD}"}


@pytest.mark.parametrize(
    "stamps, src, build, message",
    [
        (None, "wago", BUILD, "no source stamp for ItemSparse in"),
        ({"ItemSparse": f"wago@{BUILD}"}, "wago", BUILD, "no source stamp for SpellName"),
        ({"ItemSparse": f"db2@{BUILD}", "SpellName": f"db2@{BUILD}"}, "wago", BUILD, f"stamped db2@{BUILD}, the import was told --src wago"),
        ({"ItemSparse": "wago@1.15.8.1", "SpellName": "wago@1.15.8.1"}, "wago", BUILD, "stamped wago@1.15.8.1"),
    ],
)
def test_a_missing_or_other_stamp_is_refused_and_nothing_written(tmp_path, monkeypatch, capsys, stamps, src, build, message):
    data = _data(tmp_path, monkeypatch)
    item, spell = _names(tmp_path / "inputs")
    for table, label in (stamps or {}).items():
        tables_stamp.write(tmp_path / "inputs", [table], label)
    assert _wago_ids(item, spell, src, build) == 1
    err = capsys.readouterr().err
    assert message in err and "make tables-extract (db2) or make wago-fetch (wago)" in err
    assert Store(data, english=True).load("item") == []


def test_csvs_from_two_folders_are_checked_each_against_its_own_stamp(tmp_path, monkeypatch, capsys):
    _data(tmp_path, monkeypatch)
    item, _ = _names(tmp_path / "a")
    _, spell = _names(tmp_path / "b")
    tables_stamp.write(tmp_path / "a", ["ItemSparse"], f"wago@{BUILD}")
    tables_stamp.write(tmp_path / "b", ["SpellName"], f"db2@{BUILD}")
    assert _wago_ids(item, spell) == 1
    assert f"SpellName.csv: stamped db2@{BUILD}" in capsys.readouterr().err


def test_a_wago_fetch_after_an_extraction_restamps_those_tables_wago(tmp_path, monkeypatch, capsys):
    """`make tables-extract` then `make wago-fetch` into the same folder. The CSVs are wago's
    now, so an import told db2 is refused; told wago, it imports."""
    _data(tmp_path, monkeypatch)
    inputs = tmp_path / "inputs"
    item, spell = _names(inputs)
    tables_stamp.write(inputs, ["ItemSparse", "SpellName", "QuestV2"], f"db2@{BUILD}")  # tables-extract
    assert stamp_cli.main(["write", "--dir", str(inputs), "--src", "wago", "--build", BUILD, "ItemSparse", "SpellName"]) == 0
    assert tables_stamp.read(inputs) == {
        "ItemSparse": f"wago@{BUILD}", "SpellName": f"wago@{BUILD}", "QuestV2": f"db2@{BUILD}",
    }
    assert _wago_ids(item, spell, "db2") == 1
    assert f"stamped wago@{BUILD}, the import was told --src db2" in capsys.readouterr().err
    assert _wago_ids(item, spell, "wago") == 0


@pytest.mark.parametrize(
    "argv_tail, csvs",
    [
        (["client-text", "ItemSparse.csv", "Spell.csv", "ItemEffect.csv"], ("ItemSparse", "Spell", "ItemEffect")),
        (["wago-ui", "GlobalStrings.csv", "ItemSubClass.csv", "--keys", "keys.txt"], ("GlobalStrings", "ItemSubClass")),
    ],
)
def test_client_text_and_wago_ui_check_the_stamp_too(tmp_path, monkeypatch, capsys, argv_tail, csvs):
    _data(tmp_path, monkeypatch)
    for name in csvs:
        (tmp_path / f"{name}.csv").write_text("x\n")
    (tmp_path / "keys.txt").write_text("OKAY\n")
    args = ["english", argv_tail[0], *[str(tmp_path / a) if a.endswith((".csv", ".txt")) else a for a in argv_tail[1:]]]
    assert run([*args, "--build", BUILD]) == 1
    assert f"no source stamp for {csvs[0]}" in capsys.readouterr().err


@pytest.mark.parametrize("text, message", [("ItemSparse\n", "not `<table> <src>@<build>`"),
                                           ("A wago@1\nA wago@1\n", "A stamped twice")])
def test_a_malformed_stamp_is_an_error(tmp_path, text, message):
    (tmp_path / tables_stamp.FILE).write_text(text)
    with pytest.raises(ValueError, match=message):
        tables_stamp.read(tmp_path)


def test_the_table_is_the_file_name_up_to_the_first_dot():
    assert tables_stamp.table_of(Path("x/ItemSparse.excerpt.csv")) == "ItemSparse"


def test_clear_drops_only_the_named_tables(tmp_path):
    tables_stamp.write(tmp_path, ["ItemSparse", "QuestV2"], f"db2@{BUILD}")
    tables_stamp.clear(tmp_path, ["ItemSparse"])
    assert tables_stamp.read(tmp_path) == {"QuestV2": f"db2@{BUILD}"}
    tables_stamp.clear(tmp_path, ["Nope"])  # nothing to drop: unchanged
    assert tables_stamp.read(tmp_path) == {"QuestV2": f"db2@{BUILD}"}


def test_a_fetch_cut_off_between_the_move_and_the_new_stamp_is_refused_not_mislabelled(tmp_path, monkeypatch, capsys):
    """The old `db2` stamp is cleared before wago's CSVs move in, so an interrupted run leaves them
    unstamped; the import refuses instead of taking wago text as db2."""
    _data(tmp_path, monkeypatch)
    inputs = tmp_path / "inputs"
    item, spell = _names(inputs)
    tables_stamp.write(inputs, ["ItemSparse", "SpellName"], f"db2@{BUILD}")
    assert stamp_cli.main(["clear", "--dir", str(inputs), "ItemSparse", "SpellName"]) == 0
    # (the move happens here; the run stops before `write`)
    assert _wago_ids(item, spell, "db2") == 1
    assert "no source stamp for ItemSparse" in capsys.readouterr().err


def test_the_check_command_the_preflight_runs(tmp_path, capsys):
    item, spell = _names(tmp_path / "inputs")
    tables_stamp.write(tmp_path / "inputs", ["ItemSparse", "SpellName"], f"wago@{BUILD}")
    assert stamp_cli.main(["check", "--src", "wago", "--build", BUILD, str(item), str(spell)]) == 0
    assert stamp_cli.main(["check", "--src", "db2", "--build", BUILD, str(item), str(spell)]) == 1
    assert f"stamped wago@{BUILD}, the import was told --src db2" in capsys.readouterr().err
