"""Row shape, escaping, sharding inputs, Meta text: the pure writer."""

import re

import pytest

from wfj.core.model import entry, provenance
from wfj.emit import lua_writer, schema

PROV = provenance("human", "cqjt@3446c82", "2026-09-13", translator="T", origins=["cqjt@3446c82#1"])


def line(type_, id_, field, ja, status="trusted", h="d311f9a5c36057a2"):
    ln = entry(id_, field, ja, prov=PROV)
    ln["status"] = status
    ln["english"] = {"hash": h, "src": "pfquest@7786596"} if status != "rejected" else None
    return ln


def test_lua_string_escapes():
    assert lua_writer.lua_string('a"b\\c\nd\re\tf\x01g\x7f') == '"a\\"b\\\\c\\nd\\re\\tf\\001g\\127"'
    assert lua_writer.lua_string("日本語 [x] |cff00ff00v|r") == '"日本語 [x] |cff00ff00v|r"'


def test_h1_literal_is_first_32_bits():
    assert lua_writer.h1_literal("d311f9a5c36057a2") == "0xd311f9a5"
    assert lua_writer.h1_literal("0000000100000000") == "0x00000001"


def test_quest_rows_golden():
    lines = [
        line("quest", 2, "title", "Sharptalonの鉤爪"),
        line("quest", 2, "objectives", "目的", "stale", "0badf00d00000000"),
        line("quest", 2, "description", "説明"),
        line("quest", 2, "completion", "完了"),
        line("quest", 3, "title", "x", "rejected"),
        line("quest", 4, "description", ""),  # empty ja never ships
        line("quest", 5, "title", "五"),
    ]
    rows = lua_writer.rows("quest", lines)
    assert list(rows) == [2, 5]
    assert rows[2] == [
        '"Sharptalonの鉤爪"',
        '"目的"',
        '"説明"',
        "nil",
        '"完了"',
        "0xd311f9a5",
        "0x0badf00d",
        "0xd311f9a5",
        "nil",
        "0xd311f9a5",
        '".s.m."',
    ]
    assert rows[5] == [
        '"五"',
        "nil",
        "nil",
        "nil",
        "nil",
        "0xd311f9a5",
        "nil",
        "nil",
        "nil",
        "nil",
        '".mmmm"',
    ]
    text = lua_writer.shard_text("quest", 0, rows)
    row2 = (
        '  [2] = { "Sharptalonの鉤爪", "目的", "説明", nil, "完了", '
        '0xd311f9a5, 0x0badf00d, 0xd311f9a5, nil, 0xd311f9a5, ".s.m." },'
    )
    assert text.splitlines()[1:4] == ["local _, WFJ = ...", 'WFJ.Data.add("quest", {', row2]
    assert text.endswith(
        '  [5] = { "五", nil, nil, nil, nil, 0xd311f9a5, nil, nil, nil, nil, ".mmmm" },\n})\n'
    )
    assert "data/quest/quest-0000.jsonl" in text.splitlines()[0]


def test_item_spell_and_gossip_rows():
    items = lua_writer.rows(
        "item", [line("item", 117, "description", "使用：回復", "unaligned", "aabbccdd00000000")]
    )
    assert items == {117: ['"使用：回復"', "0xaabbccdd", '"u"']}
    # a spell row is text, text, h1, h1, status; `aura` is a second field
    spells = lua_writer.rows("spell", [line("spell", 17, "description", "盾", "unaligned")])
    assert spells == {17: ['"盾"', "nil", "0xd311f9a5", "nil", '"um"']}
    both = lua_writer.rows(
        "spell",
        [
            line("spell", 17, "description", "盾", "unaligned"),
            line("spell", 17, "aura", "吸収", "unaligned", "aabbccdd00000000"),
        ],
    )
    assert both == {17: ['"盾"', '"吸収"', "0xd311f9a5", "0xaabbccdd", '"uu"']}
    g = line("gossip", "0123456789abcdef", "text", "こんにちは")
    assert lua_writer.keyed_rows("gossip", [g]) == {"0123456789abcdef": ['"こんにちは"', '"."']}
    assert '  ["0123456789abcdef"] = { "こんにちは", "." },' in lua_writer.keyed_text(
        "gossip", "01", lua_writer.keyed_rows("gossip", [g])
    )


def test_duplicate_lines_raise_instead_of_last_wins():
    two = [line("quest", 9, "title", "甲"), line("quest", 9, "title", "乙")]
    with pytest.raises(ValueError, match="duplicate quest line 9/title"):
        lua_writer.rows("quest", two)
    g = line("gossip", "0123456789abcdef", "text", "a")
    with pytest.raises(ValueError, match="duplicate gossip line"):
        lua_writer.keyed_rows("gossip", [g, dict(g)])


def test_meta_text_is_content_only():
    text = lua_writer.meta_text(
        1, {"pfquest": ["7786596"], "wago": ["1.15.9.69722"]}, {"quest": 2468, "item": 2664, "spell": 1009}
    )
    assert 'english = { pfquest = "7786596", wago = "1.15.9.69722" }' in text
    # the objective type joins the numeric-id types (counted after spell), then area
    assert ("counts = { quest = 2468, item = 2664, spell = 1009, objective = 0, area = 0, gossip = 0, book = 0,"
            " ui = 0, reading = 0, gloss = 0 }") in text  # lines with readings, then glosses, last
    assert 'objective = { "text" }, area = { "text" }' in text
    assert 'quest = { "title", "objectives", "description", "progress", "completion" }' in text
    assert not re.search(r"\d{4}-\d{2}-\d{2}|\d{2}:\d{2}|/Users|/home|C:\\\\", text)


def test_meta_text_joins_a_source_served_by_two_clients():
    """`wdb` is pinned at both builds when a union import keeps each client's quests (ADR-020)."""
    text = lua_writer.meta_text(1, {"wdb": ["1.60.1.69913", "1.15.9.69722"]}, {})
    assert 'english = { wdb = "1.15.9.69722+1.60.1.69913" }' in text  # sorted, not insertion order


def test_toc_block_uses_backslashes():
    block = lua_writer.toc_block(["Data/Meta.lua", "Data/Quest/Quest_0000.lua"])
    assert block == [schema.TOC_BEGIN, "Data\\Meta.lua", "Data\\Quest\\Quest_0000.lua", schema.TOC_END]


def test_escape_fixture_matches_writer(root):
    ja = 'He said "hi"\\ok\n[tag] |cffff0000red|r\ttab\x01end\r'
    rows = lua_writer.rows(
        "quest",
        [
            line("quest", 1, "title", ja),
            line("quest", 1, "description", "改行\nあり", "stale", "0badf00d12345678"),
            line("quest", 2, "objectives", "[[]]"),
        ],
    )
    expected = lua_writer.shard_text("quest", 0, rows)
    assert (root / "tests/fixtures/lua/escape_fixture.lua").read_text(encoding="utf-8") == expected
