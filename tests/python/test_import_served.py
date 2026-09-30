"""`wfj import english served` drops English for ids the target client (Forever) does not serve."""

import shutil
from pathlib import Path

import pytest

from wfj.cmd.import_ import run
from wfj.core.hashing import key
from wfj.core.model import english_line, entry
from wfj.core.normalize import normalize_v1
from wfj.io import wago
from wfj.io.jsonl_store import Store

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"
FOREVER_WDB = FIXTURES / "wdb-forever" / "questcache.wdb"  # build 69913: quests 1665 …, objective 465191 (92596)
ERA_WDB = FIXTURES / "wdb" / "questcache.wdb"  # build 69722: quest 498 holds objectives 381177, 381178
FOREVER = "db2@1.60.1.69913"
ERA = "wago@1.15.9.69722"
MACHINE = {"class": "machine", "model": "m", "source": "draft-x-sg4@2026-09-20", "imported": "2026-09-20"}


def _en(id_, field, en, src):
    return english_line(id_, field, en, key(normalize_v1(en)), src)


def _keys_file(tmp_path: Path, keys=("ACCEPT", "SpellItemEnchantment:9")) -> Path:
    p = tmp_path / "ui_keys.txt"
    p.write_text("# the curated ui keys\n" + "".join(f"{k}\n" for k in keys))
    return p


def _client(tmp_path: Path, questv2=(1000, 498), items=(25,), spells=(17,), stamp=FOREVER) -> Path:
    d = tmp_path / "forever"
    d.mkdir()
    (d / "QuestV2.csv").write_text("ID,UniqueBitFlag\n" + "".join(f"{i},0\n" for i in questv2))
    (d / "ItemSparse.csv").write_text("ID,Display_lang\n" + "".join(f"{i},Item {i}\n" for i in items))
    (d / "SpellName.csv").write_text("ID,Name_lang\n" + "".join(f"{i},Spell {i}\n" for i in spells))
    shutil.copy(FOREVER_WDB, d / "questcache.wdb")
    (d / "tables-source.txt").write_text(
        "# stamp\n" + "".join(f"{t} {stamp}\n" for t in ("ItemSparse", "QuestV2", "SpellName", "GlobalStrings", "ItemSubClass",
                                              "SpellItemEnchantment", "Spell", *wago.FAMILY_TABLES))
    )
    return d


@pytest.fixture
def data(tmp_path, monkeypatch) -> Path:
    root = tmp_path / "data"
    root.mkdir()
    (root / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    eng = Store(root, english=True)
    eng.save("quest", [
        _en(1000, "title", "Listed in QuestV2", "wdb@1.15.9.69722"),  # QuestV2 only → kept
        _en(1665, "title", "Bartleby's Mug", "wdb@1.60.1.69913"),  # the Forever cache only → kept
        _en(802, "title", "A placeholder the cache answered", "pfquest@7786596"),  # cached placeholder → kept
        _en(9999, "title", "Era only", "wdb@1.15.9.69722"),  # neither → removed
        _en(9999, "progress", "Era only, VMaNGOS", "vmangos@13b49dc"),
    ])
    eng.save("objective", [
        _en(465191, "text", "Forever objective", "wdb@1.60.1.69913"),  # quest 92596, cached on Forever
        _en(381177, "text", "Era objective", "wdb@1.15.9.69722"),  # quest 498, via the Era cache
        _en(777, "text", "No cache maps me", "wdb@1.15.9.69722"),  # unmapped → kept
    ])
    eng.save("area", [  # keyed by the quest id, kept with its quest
        _en(1000, "text", "Scout the listed quest", "wdb@1.15.9.69722"),
        _en(9999, "text", "Scout the Era-only quest", "wdb@1.15.9.69722"),
    ])
    eng.save("item", [_en(25, "name", "Worn Shortsword", FOREVER), _en(25, "description", "Old", ERA),
                      _en(26, "name", "Era item", ERA)])
    eng.save("spell", [_en(17, "name", "Power Word: Shield", FOREVER), _en(18, "aura", "Era aura", ERA)])
    eng.save("ui", [_en("ACCEPT", "text", "Accept", FOREVER), _en("SpellItemEnchantment:9", "text", "+1", ERA)])
    eng.save("book", [_en(5, "text", "A page.", "vmangos@13b49dc")])
    k = key(normalize_v1("Hello."))
    eng.save("gossip", [english_line(k, "text", "Hello.", k, "vmangos@13b49dc")])
    Store(root).save("quest", [entry(9999, "title", "エラのみ", prov=MACHINE)])
    Store(root).save("item", [entry(26, "description", "説明", prov=MACHINE)])
    return root


def _run(d: Path, *extra: str, era: bool = True, keys: Path | None = None) -> int:
    args = [str(d / "QuestV2.csv"), str(d / "questcache.wdb"), str(d / "ItemSparse.csv"), str(d / "SpellName.csv")]
    keys = keys if keys is not None else _keys_file(d.parent)
    return run(["english", "served", *args, "--keys", str(keys),
                *(["--map-cache", str(ERA_WDB)] if era else []), *extra])


def _ids(data: Path, kind: str) -> set:
    return {ln["id"] for ln in Store(data, english=True).load(kind)}


def _snapshot(root: Path) -> dict:
    return {p: p.read_bytes() for p in sorted(root.rglob("*.jsonl"))}


def test_each_kind_keeps_only_what_forever_serves(data, tmp_path, capsys):
    d = _client(tmp_path)
    assert _run(d) == 0
    out = capsys.readouterr().out
    assert _ids(data, "quest") == {802, 1000, 1665}
    assert _ids(data, "objective") == {465191, 381177, 777}
    assert _ids(data, "area") == {1000}
    assert "served area: kept 1 lines, removed 1 (1 ids)" in out
    assert [(ln["id"], ln["field"]) for ln in Store(data, english=True).load("item")] == [
        (25, "name"), (25, "description")]  # every field of a served id stays, whichever client wrote it
    assert _ids(data, "spell") == {17}
    assert _ids(data, "ui") == {"ACCEPT"}
    assert "served quest: kept 3 lines, removed 2 (1 ids)" in out
    assert "served objective: 1 ids no quest cache maps to a quest, kept" in out


def test_an_objective_goes_with_its_quest(data, tmp_path):
    d = _client(tmp_path, questv2=(1000,))  # quest 498 no longer listed
    assert _run(d) == 0
    assert _ids(data, "objective") == {465191, 777}


def test_without_the_era_cache_an_era_objective_is_unmapped_and_kept(data, tmp_path):
    d = _client(tmp_path, questv2=(1000,))
    assert _run(d, era=False) == 0
    assert _ids(data, "objective") == {465191, 381177, 777}


def test_books_gossip_and_japanese_are_untouched(data, tmp_path):
    book, gossip = data / "english" / "book", data / "english" / "gossip"
    before = {**_snapshot(book), **_snapshot(gossip)}
    japanese = {p: b for p, b in _snapshot(data).items() if "english" not in p.parts}
    assert _run(_client(tmp_path)) == 0
    assert {**_snapshot(book), **_snapshot(gossip)} == before
    assert {p: b for p, b in _snapshot(data).items() if "english" not in p.parts} == japanese


def test_idempotent(data, tmp_path, capsys):
    d = _client(tmp_path)
    assert _run(d) == 0
    once = _snapshot(data)
    capsys.readouterr()
    assert _run(d) == 0
    assert _snapshot(data) == once
    assert "removed 0" in capsys.readouterr().out


def test_dry_run_writes_nothing(data, tmp_path, capsys):
    before = _snapshot(data)
    assert _run(_client(tmp_path), "--dry-run") == 0
    assert _snapshot(data) == before
    assert "dry run" in capsys.readouterr().out


@pytest.mark.parametrize("missing", ["QuestV2.csv", "questcache.wdb", "ItemSparse.csv", "SpellName.csv"])
def test_a_missing_forever_file_refuses(data, tmp_path, capsys, missing):
    d = _client(tmp_path)
    (d / missing).unlink()
    before = _snapshot(data)
    assert _run(d) == 1
    assert missing in capsys.readouterr().err
    assert _snapshot(data) == before


def test_an_unstamped_or_mismatched_table_refuses(data, tmp_path, capsys):
    d = _client(tmp_path)
    (d / "tables-source.txt").write_text(f"QuestV2 {FOREVER}\nItemSparse {FOREVER}\nSpellName {ERA}\n")
    before = _snapshot(data)
    assert _run(d) == 1
    assert "different stamps" in capsys.readouterr().err
    (d / "tables-source.txt").write_text(f"QuestV2 {FOREVER}\nItemSparse {FOREVER}\n")
    assert _run(d) == 1
    assert "no source stamp" in capsys.readouterr().err
    assert _snapshot(data) == before


def test_a_cache_of_another_build_refuses(data, tmp_path, capsys):
    d = _client(tmp_path, stamp="db2@1.60.1.70000")
    assert _run(d) == 1
    assert "build 69913" in capsys.readouterr().err


def test_a_kind_that_would_lose_every_line_refuses(data, tmp_path, capsys):
    before = _snapshot(data)
    assert _run(_client(tmp_path, spells=(99999,))) == 1
    assert "every spell line" in capsys.readouterr().err
    assert _snapshot(data) == before


def test_collector_english_is_never_dropped(tmp_path, data):
    """A collector dump is not replayed by `make import`, so its English could not be rebuilt."""
    eng = Store(data, english=True)
    eng.save("item", [*eng.load("item"), _en(4242, "name", "Seen in game", "collector@1.60.1.70001")])
    assert _run(_client(tmp_path)) == 0
    assert 4242 in _ids(data, "item")
    assert 26 not in _ids(data, "item")


def test_a_ui_table_at_another_build_refuses(tmp_path, data, capsys):
    """ui English is kept by the stamp, so every table it comes from must carry the same one."""
    d = _client(tmp_path)
    stamp = d / "tables-source.txt"
    stamp.write_text(stamp.read_text().replace(f"GlobalStrings {FOREVER}", "GlobalStrings db2@1.60.1.70001"))
    before = _snapshot(data)
    assert _run(d) == 1
    assert "ui source tables" in capsys.readouterr().err
    assert _snapshot(data) == before


def test_a_ui_key_that_left_the_curated_list_loses_its_english(tmp_path, data):
    """The dictionary is `ui_keys.txt`: under the union merge a dropped key would otherwise keep its English."""
    eng = Store(data, english=True)
    eng.save("ui", [*eng.load("ui"), _en("CANCEL", "text", "Cancel", FOREVER)])
    assert _run(_client(tmp_path), keys=_keys_file(tmp_path, keys=("CANCEL",))) == 0
    assert _ids(data, "ui") == {"CANCEL"}
