import json
import re
from pathlib import Path

from wfj.cmd.import_ import run
from wfj.cmd.import_predecessor import Collector, import_items, import_quests, import_spells
from wfj.core.model import FIELDS, validate_line
from wfj.io.jsonl_store import Store

FX = "tests/fixtures/predecessor"


def _read(root, name):
    return (root / FX / name).read_text(encoding="utf-8")


def test_quest_fixture_counts_and_provenance(root):
    col = import_quests(_read(root, "QuestLogData.excerpt.lua"), "cqjt@3446c82", "2026-09-13")
    ids = {i for i, _ in col.lines}
    assert len(ids) == 32  # 35 entries; ids 123, 184, 6385 are real corpus duplicates
    line = col.lines[(2, "title")]
    assert line["ja"] == "Sharptalonの鉤爪" and line["status"] == "pending"
    assert line["provenance"] == {
        "class": "human",
        "translator": "Tammy",
        "source": "cqjt@3446c82",
        "imported": "2026-09-13",
        "origins": ["cqjt@3446c82#1"],
    }
    assert (2, "progress") not in col.lines  # empty fields are omitted


def test_identical_duplicates_collapse(root):
    col = import_quests(_read(root, "QuestLogData.excerpt.lua"), "cqjt@3446c82", "2026-09-13")
    line = col.lines[(123, "description")]
    assert line["conflicts"] == [] and len(line["provenance"]["origins"]) == 2


def test_conflicting_duplicates_recorded(root):
    col = import_quests(_read(root, "QuestLogData.excerpt.lua"), "cqjt@3446c82", "2026-09-13")
    conflicted = [f for f in FIELDS["quest"] if (184, f) in col.lines and col.lines[(184, f)]["conflicts"]]
    assert conflicted, "184 has differing duplicate text in at least one field"
    line = col.lines[(184, conflicted[0])]
    assert len(line["provenance"]["origins"]) == 1 and line["provenance"]["origins"][0].startswith(
        "cqjt@3446c82#"
    )
    assert line["conflicts"][0]["ja"] != line["ja"]
    assert line["conflicts"][0]["provenance"]["class"] == "human"


def test_first_occurrence_wins():
    col = Collector()
    p = {"class": "human", "translator": "a", "source": "cqjt@1234567", "imported": "2026-09-13"}
    col.add(1, "title", "first", p, "o1")
    col.add(1, "title", "second", p, "o2")
    col.add(1, "title", " first ", p, "o3")
    assert col.lines[(1, "title")]["ja"] == "first"
    assert [c["ja"] for c in col.lines[(1, "title")]["conflicts"]] == ["second"]
    assert col.lines[(1, "title")]["provenance"]["origins"] == ["o1", "o3"]


def test_item_value_substitution_and_escapes(root):
    col = import_items(_read(root, "ItemData.excerpt.lua"), "ctjt@84db736", "2026-09-13")
    assert col.lines[(118, "description")]["ja"] == "【使用】Healthを70-90回復します。\n(クールダウン1分)"
    assert "\n" in col.lines[(117, "description")]["ja"]
    assert col.lines[(117, "description")]["provenance"]["translator"] == "WoWJapanizer"


def test_spell_short_text_kept_as_extra(root):
    col = import_spells(_read(root, "SpellData.excerpt.lua"), "ctjt@84db736", "2026-09-13")
    assert col.lines[(17, "description")]["extra"] == {"short": "$N1ダメージ吸収。"}
    assert "extra" not in col.lines[(53, "description")]


def test_every_fixture_line_validates(root):
    for type_, fn, name in (
        ("quest", import_quests, "QuestLogData.excerpt.lua"),
        ("item", import_items, "ItemData.excerpt.lua"),
        ("spell", import_spells, "SpellData.excerpt.lua"),
    ):
        col = fn(_read(root, name), "cqjt@3446c82", "2026-09-13")
        for line in col.lines.values():
            assert validate_line(type_, line) == [], (type_, line["id"], line["field"])


def _fixture_repos(root, tmp_path: Path):
    q = tmp_path / "quest-repo"
    q.mkdir()
    (q / "QuestLogData.lua").write_text(_read(root, "QuestLogData.excerpt.lua"), encoding="utf-8")
    t = tmp_path / "tooltip-repo"
    (t / "Data/Item").mkdir(parents=True)
    (t / "Data/Spell").mkdir(parents=True)
    (t / "Data/Item/ItemData.lua").write_text(_read(root, "ItemData.excerpt.lua"), encoding="utf-8")
    (t / "Data/Spell/SpellData.lua").write_text(_read(root, "SpellData.excerpt.lua"), encoding="utf-8")
    return q, t


def test_run_predecessor_end_to_end_and_idempotent(root, tmp_path: Path, monkeypatch, capsys):
    q, t = _fixture_repos(root, tmp_path)
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    args = [
        "predecessor",
        "--quest-repo",
        str(q),
        "--tooltip-repo",
        str(t),
        "--commit-quest",
        "3446c82",
        "--commit-tooltip",
        "84db736",
        "--date",
        "2026-09-13",
    ]
    assert run(args) == 0
    out = capsys.readouterr().out
    assert "quest" in out and "conflicts" in out
    first = {p.relative_to(tmp_path): p.read_bytes() for p in (tmp_path / "data").rglob("*.jsonl")}
    assert first
    assert run(args) == 0
    second = {p.relative_to(tmp_path): p.read_bytes() for p in (tmp_path / "data").rglob("*.jsonl")}
    assert first == second
    lines = Store(tmp_path / "data").load("quest")
    assert all(validate_line("quest", ln) == [] for ln in lines)
    assert (
        json.loads((tmp_path / "data/quest/quest-0000.jsonl").read_text(encoding="utf-8").splitlines()[0])[
            "id"
        ]
        == 2
    )


def test_committed_data_validates(root):
    """The real import (skipped if data/ is empty on this checkout): every line validates, every source tag is a
    pinned short SHA / build, and English shards validate too."""
    import re as _re

    store = Store(root / "data")
    # predecessor repos (git sha) + the lineage sources (release version / data-pack date) + hand corrections
    # (the day they were written) + model drafts (draft name with its style version, import day)
    src_re = _re.compile(
        r"^(cqjt|ctjt)@[0-9a-f]{7,40}$|^qjp@\d+(\.\d+)*$|^cjq@\d{10}$|^correction@\d{4}-\d{2}-\d{2}$"
        r"|^draft-[a-z0-9-]+-sg\d+@\d{4}-\d{2}-\d{2}$"
    )
    total = 0
    for type_ in ("quest", "item", "spell"):
        for line in store.load(type_):
            assert validate_line(type_, line) == [], (type_, line["id"], line["field"])
            assert src_re.match(line["provenance"]["source"]), line["provenance"]["source"]
            for c in line["conflicts"]:
                assert src_re.match(c["provenance"]["source"])
            total += 1
    english = Store(root / "data", english=True)
    # progress / completion (vmangos) · Blizzard's cached title / objectives / description (wdb)
    # the Forever client's own tables (db2@<its build>) and its quest cache (wdb@<its build>). Two
    # clients coexist by design: the union merge restamps what Forever provides and leaves the rest on its
    # Vanilla stamp, which is what `wfj stats --unseen-since` reads. The quest cache is the one source held at
    # TWO pinned builds, because Forever's server answers under a third of the quest ids Classic Era's did
    # (`schema.MULTI_VERSION_SOURCES`). Every source is still a PINNED build; that is what this asserts.
    pinned = {
        "pfquest@7786596", "wago@1.15.9.69722", "vmangos@13b49dc", "wdb@1.15.9.69722",
        "wdb@1.60.1.70170", "db2@1.60.1.70170",  # Forever's pinned build
        "forever-vo@025070f",  # forever-vo's captures at a pinned commit (ADR-055)
    }
    # Additive (ADR-050): a line an earlier Forever build served keeps that build's stamp
    # and English the Forever client showed in game, recorded by the collector (ADR-053)
    earlier_forever = re.compile(r"^(wdb|db2|collector)@1\.60\.1\.\d+$")
    for type_ in ("quest", "item", "spell"):
        for line in english.load(type_):
            assert validate_line(type_, line, english=True) == [], (type_, line["id"], line["field"])
            assert line["src"] in pinned or earlier_forever.match(line["src"]), line["src"]
            total += 1
    if total:
        assert total > 100000


def test_git_head_refuses_non_git_dir(tmp_path: Path):
    """A non-git copy must be imported with explicit --commit-* flags, never as cqjt@unknown."""
    import pytest

    from wfj.cmd.import_predecessor import git_head

    with pytest.raises(ValueError, match="not a git checkout"):
        git_head(tmp_path)


def test_conflict_keeps_extra_and_empty_save_refused(tmp_path: Path):
    from wfj.io.jsonl_store import Store

    col = Collector()
    p = {"class": "human", "translator": "a", "source": "cqjt@1234567", "imported": "2026-09-13"}
    col.add(1, "description", "x", p, "o1")
    col.add(1, "description", "y", p, "o2", extra={"short": "s"})
    assert col.lines[(1, "description")]["conflicts"][0]["extra"] == {"short": "s"}
    store = Store(tmp_path)
    store.save("spell", col.lines.values())
    import pytest

    with pytest.raises(ValueError, match="zero lines"):
        store.save("spell", [])
    store.save("spell", [], allow_empty=True)
    assert not list((tmp_path / "spell").glob("*.jsonl"))
