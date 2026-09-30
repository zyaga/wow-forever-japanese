"""The generate command on the real store and on synthetic edges (including the vectors twin)."""

import shutil
from pathlib import Path

import pytest

from wfj.cmd import generate
from wfj.dev import gen_vectors
from wfj.emit import schema
from wfj.io.jsonl_store import Store

ADDON = "addon/WoWForeverJapanese"


def _addon_copy(root: Path, tmp_path: Path) -> Path:
    dst = tmp_path / "WoWForeverJapanese"
    shutil.copytree(root / ADDON, dst, ignore=shutil.ignore_patterns("Fonts"))
    return dst


def test_plan_on_the_committed_store_matches_disk(root, planned):
    assert "Data/Meta.lua" in planned and "Data/Vectors.lua" in planned
    for rel, text in planned.items():
        assert (root / ADDON / rel).read_text(encoding="utf-8") == text, rel
    assert generate.generated_on_disk(root / ADDON) == set(planned)
    toc = (root / ADDON / generate.TOC_NAME).read_text(encoding="utf-8")
    assert generate.toc_with_block(toc, generate.toc_files(planned)) == toc


def test_apply_twice_is_a_no_op_and_reaps_stale_shards(root, tmp_path, planned):
    addon = _addon_copy(root, tmp_path)
    stray = addon / "Data/Quest/Quest_9999.lua"
    stray.write_text("-- stray\n", encoding="utf-8")
    keep = addon / "Data/Gossip/.gitkeep"
    assert keep.exists()
    first = generate.apply(planned, addon)
    assert first["deleted"] == ["Data/Quest/Quest_9999.lua"] and not stray.exists() and keep.exists()
    second = generate.apply(planned, addon)
    assert (
        second["written"] == [] and second["deleted"] == [] and len(second["unchanged"]) == len(planned) + 1
    )


def test_toc_block_rewrite_and_missing_markers(root):
    toc = (root / ADDON / generate.TOC_NAME).read_text(encoding="utf-8")
    files = ["Data/Meta.lua", "Data/Vectors.lua", "Data/Quest/Quest_0000.lua"]
    new = generate.toc_with_block(toc, files)
    lines = new.splitlines()
    b, e = lines.index(schema.TOC_BEGIN), lines.index(schema.TOC_END)
    assert lines[b + 1 : e] == ["Data\\Meta.lua", "Data\\Vectors.lua", "Data\\Quest\\Quest_0000.lua"]
    assert lines[b - 1] == "Core\\Data.lua" and lines[e + 1] == "Core\\Lookup.lua"
    assert generate.toc_with_block(new, files) == new
    with pytest.raises(ValueError, match="exactly one generated block"):
        generate.toc_with_block("## Interface: 1\nMain.lua\n", files)


def test_toc_files_order_is_meta_vectors_then_shards_by_type(root):
    planned = {
        "Data/Spell/Spell_0000.lua": "",
        "Data/Quest/Quest_0001.lua": "",
        "Data/Meta.lua": "",
        "Data/Item/Item_0000.lua": "",
        "Data/Quest/Quest_0000.lua": "",
        "Data/Vectors.lua": "",
        "Data/Gossip/Gossip_ab.lua": "",
    }
    assert generate.toc_files(planned) == [
        "Data/Meta.lua",
        "Data/Vectors.lua",
        "Data/Quest/Quest_0000.lua",
        "Data/Quest/Quest_0001.lua",
        "Data/Item/Item_0000.lua",
        "Data/Spell/Spell_0000.lua",
        "Data/Gossip/Gossip_ab.lua",
    ]


def test_vectors_lua_is_the_busted_twin_with_another_head(root):
    twin = (root / "vectors/hash_vectors.lua").read_text(encoding="utf-8")
    shipped = (root / ADDON / "Data/Vectors.lua").read_text(encoding="utf-8")
    head, _, body = twin.partition("\n")
    assert shipped == head + "\nlocal _, WFJ = ...\n" + body.replace(
        "return {", generate.VECTORS_HEAD + " {", 1
    )
    assert gen_vectors.to_lua(generate.vectors_rows(root / "data")) == twin


def test_plan_refuses_invalid_or_hashless_lines(root, tmp_path):
    """A hand-edited store never becomes Lua; the error names the record."""
    from wfj.core.model import entry, provenance

    prov = provenance("human", "cqjt@3446c82", "2026-09-13", translator="T", origins=["cqjt@3446c82#1"])
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n", encoding="utf-8")
    ln = entry(1, "title", "一", prov=prov)
    ln["status"] = "trusted"  # shipped but english is still null
    Store(data).save("quest", [ln], allow_empty=True)
    with pytest.raises(ValueError, match="quest 1/title: shipped without english"):
        generate.plan(Store(data), generate.vectors_rows(root / "data"))
    ln["status"] = "bogus"
    Store(data).save("quest", [ln], allow_empty=True)
    with pytest.raises(ValueError, match="invalid data/ lines"):
        generate.plan(Store(data), generate.vectors_rows(root / "data"))


def test_whitespace_only_ja_never_ships():
    from wfj.emit import lua_writer

    assert not lua_writer.shipped({"status": "trusted", "ja": "   \n"})
    assert lua_writer.shipped({"status": "trusted", "ja": " x "})


def test_duplicate_toc_markers_are_refused(root, planned):
    toc = (root / ADDON / generate.TOC_NAME).read_text(encoding="utf-8")
    twice = toc + f"{schema.TOC_BEGIN}\n{schema.TOC_END}\n"
    with pytest.raises(ValueError, match="exactly one generated block"):
        generate.toc_with_block(twice, ["Data/Meta.lua"])
    spaced = toc.replace(schema.TOC_END, schema.TOC_END + " ", 1)
    assert (
        generate.toc_with_block(spaced, generate.toc_files(planned))
        != ""
    )


def test_apply_leaves_non_generated_files_under_data_alone(root, tmp_path, planned):
    """Only <Type>_*.lua, Meta.lua and Vectors.lua are generator-owned."""
    addon = _addon_copy(root, tmp_path)
    (addon / "Data/Quest/README.md").write_text("mine\n", encoding="utf-8")
    (addon / "Data/Quest/notes").mkdir()
    (addon / "Data/Quest/notes/keep.txt").write_text("keep\n", encoding="utf-8")
    result = generate.apply(planned, addon)
    assert result["deleted"] == []
    assert (addon / "Data/Quest/README.md").exists() and (addon / "Data/Quest/notes/keep.txt").exists()
    assert "Data/Quest/README.md" not in generate.generated_on_disk(addon)


def test_apply_aborts_before_writing_when_the_toc_has_no_block(root, tmp_path, planned):
    addon = _addon_copy(root, tmp_path)
    toc = addon / generate.TOC_NAME
    toc.write_text(toc.read_text(encoding="utf-8").replace(schema.TOC_BEGIN + "\n", ""), encoding="utf-8")
    shard = addon / "Data/Quest/Quest_0000.lua"
    shard.write_text("-- tampered\n", encoding="utf-8")
    with pytest.raises(ValueError, match="exactly one generated block"):
        generate.apply(planned, addon)
    assert shard.read_text(encoding="utf-8") == "-- tampered\n"


def test_english_only_types_leave_the_generated_addon_data_unchanged(root, tmp_path, planned):
    """Area, objective, book and trainer-greeting English are stored only: generate
    plans byte-identical files (Meta.lua included) with or without them. The copy is the committed store
    until the English is added, so its plan before that is the committed plan."""
    from wfj.core.hashing import key
    from wfj.core.model import english_line
    from wfj.core.normalize import normalize_v1

    data = tmp_path / "data"
    shutil.copytree(root / "data", data)
    shutil.copytree(root / "vectors", tmp_path / "vectors")
    (tmp_path / "pipeline").mkdir()  # a branch line's variants are checked against the allowlist
    shutil.copy(root / "pipeline" / "allowlist.txt", tmp_path / "pipeline" / "allowlist.txt")
    eng = Store(data, english=True)

    def line(id_, field, en, src):
        return english_line(id_, field, en, key(normalize_v1(en)), src)

    eng.save("objective", [line(999001, "text", "Rescue a test", "wdb@1.15.9.69722")])
    # appended to the committed English, not replacing it: shipped book lines need their English
    eng.save("book", [*eng.load("book"), line(999002, "text", "A test page.", "vmangos@13b49dc")])
    # area English with no Japanese area line generates nothing either
    eng.save("area", [*eng.load("area"), line(999003, "text", "Scout a test", "wdb@1.15.9.69722")])
    assert generate.plan(Store(data), generate.vectors_rows(data)) == planned


def test_area_rows_ship_as_text_h1_status_in_their_own_shards_and_toc_slot(root, tmp_path):
    """A shipped area line generates `Data/Area/Area_NNNN.lua` rows `{ ja, h1, status }` keyed by
    the quest id, listed in the TOC after the objective shards; Meta counts and lays out the type."""
    import re

    from wfj.core.hashing import key
    from wfj.core.model import english_line, entry
    from wfj.core.normalize import normalize_v1
    from wfj.emit import lua_writer

    en = "Scout through the Fargodeep Mine"
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n", encoding="utf-8")
    Store(data, english=True).save("area", [english_line(62, "text", en, key(normalize_v1(en)), "wdb@1.60.1.70009")])
    ln = entry(62, "text", "Fargodeep Mineを偵察する", prov={"class": "machine", "model": "m",
                                                          "source": "draft-area-sg9@2026-09-27", "imported": "2026-09-27"})
    ln["status"], ln["english"] = "trusted", {"hash": key(normalize_v1(en)), "src": "wdb@1.60.1.70009"}
    Store(data).save("area", [ln])
    Store(data).save("objective", [{**ln, "id": 380001}])
    planned = generate.plan(Store(data), generate.vectors_rows(root / "data"))
    shard = planned["Data/Area/Area_0000.lua"]
    h1 = lua_writer.h1_literal(key(normalize_v1(en)))
    assert 'WFJ.Data.add("area", {' in shard
    assert f'[62] = {{ "Fargodeep Mineを偵察する", {h1}, "." }},' in shard
    files = generate.toc_files(planned)
    assert files.index("Data/Objective/Objective_0380.lua") < files.index("Data/Area/Area_0000.lua")
    meta = planned["Data/Meta.lua"]
    assert "area = 1" in meta and 'area = { "text" }' in meta
    # the addon's hand-written twin (Core/Const.lua) lays area out exactly as schema.SLOTS does
    const = (root / ADDON / "Core/Const.lua").read_text(encoding="utf-8")
    for t in ("objective", "area"):
        m = re.search(rf"^  {t} = \{{ fields = \{{ \"text\" \}}, hash = (\d+), status = (\d+) \}},$", const, re.M)
        assert m, t
        assert schema.SLOTS[t] == {"fields": ["text"], "hash": int(m.group(1)), "status": int(m.group(2))}


def test_the_committed_area_english_is_the_former_quest_area(root):
    """The 217 quest-cache area lines live under data/english/area (field text, keyed by quest id);
    no quest `area` line remains."""
    from wfj.core.hashing import key
    from wfj.core.normalize import normalize_v1

    english = Store(root / "data", english=True)
    area = english.load("area")
    assert len(area) == 217 and len({ln["hash"] for ln in area}) == 202
    assert {ln["field"] for ln in area} == {"text"}
    assert {ln["src"] for ln in area} == {"wdb@1.15.9.69722", "wdb@1.60.1.70009"}
    assert all(ln["hash"] == key(normalize_v1(ln["en"])) for ln in area)
    assert not [ln for ln in english.load("quest") if ln["field"] == "area"]
    titles = {ln["id"] for ln in english.load("quest") if ln["field"] == "title"}
    assert {ln["id"] for ln in area} <= titles  # every area line belongs to a quest the store knows


def test_the_committed_store_is_planned_once_per_session(root):
    """Planning the committed store takes seconds; the `planned` fixture in conftest.py does it once, and every
    test that needs the committed plan takes it from there."""
    committed_plan = "generate.plan(" + 'Store(root / "data")'  # joined so this file does not match itself
    for path in sorted((root / "tests/python").glob("test_*.py")):
        assert committed_plan not in path.read_text(encoding="utf-8"), path.name
