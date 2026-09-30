from pathlib import Path

from wfj.cmd.import_ import run
from wfj.core.hashing import key
from wfj.core.model import validate_line
from wfj.core.normalize import normalize_v1
from wfj.io.jsonl_store import Store


def _data_dir(tmp_path: Path, monkeypatch):
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    return tmp_path / "data"


def test_pfquest_lines_and_hashes(root, tmp_path: Path, monkeypatch):
    data = _data_dir(tmp_path, monkeypatch)
    fx = root / "tests/fixtures/pfquest/quests.excerpt.lua"
    assert run(["english", "pfquest", str(fx), "--commit", "7786596"]) == 0
    lines = Store(data, english=True).load("quest")
    assert {ln["id"] for ln in lines} == {
        1,
        2,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        17,
        18,
        19,
        20,
        21,
        22,
        23,
    }
    by = {(ln["id"], ln["field"]): ln for ln in lines}
    assert by[(2, "title")]["en"] == "Sharptalon's Claw"
    assert by[(2, "objectives")]["en"].startswith("Bring Sharptalon's Claw")
    for ln in lines:
        assert ln["src"] == "pfquest@7786596"
        assert ln["hash"] == key(normalize_v1(ln["en"]))
        assert validate_line("quest", ln, english=True) == []
    assert not any(ln["field"] in ("progress", "completion") for ln in lines)


def test_wago_names(root, tmp_path: Path, monkeypatch):
    data = _data_dir(tmp_path, monkeypatch)
    fx = root / "tests/fixtures/wago"
    assert (
        run(
            [
                "english",
                "wago-ids",
                str(fx / "ItemSparse.excerpt.csv"),
                str(fx / "SpellName.excerpt.csv"),
                "--build",
                "1.15.9.69722",
            ]
        )
        == 0
    )
    items = {ln["id"]: ln for ln in Store(data, english=True).load("item")}
    spells = {ln["id"]: ln for ln in Store(data, english=True).load("spell")}
    assert items[117]["en"] == "Tough Jerky" and items[117]["field"] == "name"
    assert spells[17]["en"] == "Power Word: Shield"
    assert all(ln["src"] == "wago@1.15.9.69722" for ln in items.values())
    assert all(validate_line("item", ln, english=True) == [] for ln in items.values())
    assert items[117]["hash"] == key(normalize_v1("Tough Jerky"))


def test_wago_column_override_and_missing_column(root, tmp_path: Path, monkeypatch):
    _data_dir(tmp_path, monkeypatch)
    fx = root / "tests/fixtures/wago"
    assert (
        run(
            [
                "english",
                "wago-ids",
                str(fx / "ItemSparse.excerpt.csv"),
                str(fx / "SpellName.excerpt.csv"),
                "--build",
                "x",
                "--name-col",
                "Nope",
            ]
        )
        == 1
    )
