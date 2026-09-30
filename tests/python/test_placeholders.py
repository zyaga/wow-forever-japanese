"""The pipeline's player-token vocabulary: the report, the validate rule and Lua/Python parity."""

import re

from wfj.cmd import validate
from wfj.core import placeholders, report
from wfj.core.model import entry, provenance
from wfj.io.jsonl_store import Store

PROV = provenance("human", "cqjt@3446c82", "2026-09-13", translator="T", origins=["cqjt@3446c82#1"])


def _line(id_, ja, status="trusted", field="description"):
    ln = entry(id_, field, ja, prov=PROV)
    ln["status"] = status
    return ln


def test_tokens_and_unknown():
    ja = "御機嫌よう、{name}。若き{class}よ、{race}の<lad/lass>。{foo}{Name}"
    assert placeholders.tokens(ja) == ["{name}", "{class}", "{race}", "{foo}", "{Name}", "<a/b>"]
    assert placeholders.unknown(ja) == ["{foo}", "{Name}"]  # case-sensitive, as the addon is
    assert placeholders.tokens("<Sirraは手紙を読んだ。><mage>") == []  # an emote and a single <word> are not tokens
    assert placeholders.tokens(None) == [] and placeholders.unknown(None) == []


def test_unknown_catches_every_form_the_addon_leaves_literal():
    # brace forms the addon's {[A-Za-z]+} never expands
    assert placeholders.unknown("{name1}{ name }{player_name}{名前}") == ["{name1}", "{ name }", "{player_name}", "{名前}"]
    # gender pairs the addon cannot pick from (it would show both forms)
    assert placeholders.unknown("<閣下/ご婦人>と<Mr./Ms.>と<Sir/Ma'am>") == ["<閣下/ご婦人>", "<Mr./Ms.>", "<Sir/Ma'am>"]
    assert placeholders.unknown("<lad/lass>と<priest/priestess>と<Sirraは手紙を読んだ。>") == []


def test_the_name_check_strips_every_known_token(root):
    """A known token must never be read as a Latin name by the alignment checks (pipeline and runtime gate)."""
    from wfj.core import align

    for word in placeholders.KNOWN:
        assert align.PLACEHOLDER.fullmatch("{" + word + "}"), word
    lua = (root / "addon/WoWForeverJapanese/Core/Align.lua").read_text(encoding="utf-8")
    strip = re.search(r"local function stripPlaceholders\(text\)(.*?)\nend", lua, re.S)
    assert strip, "stripPlaceholders not found in Core/Align.lua"
    for word in placeholders.KNOWN:
        assert '"{' + word + '}"' in strip.group(1), word


def test_report_counts_tokens_in_shipped_lines_only():
    lines = [
        _line(1, "{name}と{name}"),
        _line(2, "{class}の<priest/priestess>", status="stale"),
        _line(3, "{race}", status="rejected"),  # not shipped: not counted
        _line(4, "{foo}", status="unaligned"),
    ]
    t = report.tally({"quest": lines})
    assert t["placeholders"]["quest"] == {"{name}": 2, "{class}": 1, "<a/b>": 1, "{foo}": 1}
    assert "quest placeholders in shipped lines: {name}=2 {class}=1 <a/b>=1 {foo}=1" in report.render(t)
    assert report.tally({"item": [_line(5, "説明")]})["placeholders"]["item"] == {}
    assert "item placeholders" not in report.render(report.tally({"item": [_line(5, "説明")]}))


def test_validate_rule_fails_on_a_shipped_unknown_token_only(tmp_path):
    data = tmp_path / "data"
    data.mkdir()
    Store(data).save(
        "quest",
        [_line(7, "御機嫌よう、{foo}。"), _line(8, "{bar}", status="rejected"), _line(9, "{name}")],
        allow_empty=True,
    )
    problems = validate.rule_placeholders(Store(data))
    assert problems == [
        "placeholders: quest 7/description ships unknown token(s) {foo}; known: {name}, {class}, {race}"
    ]
    Store(data).save("quest", [_line(10, "<閣下/ご婦人>"), _line(11, None)], allow_empty=True)  # null ja: no crash
    assert validate.rule_placeholders(Store(data)) == [
        "placeholders: quest 10/description ships unknown token(s) <閣下/ご婦人>; known: {name}, {class}, {race}"
    ]


def test_committed_store_ships_no_unknown_token(root):
    assert validate.rule_placeholders(Store(root / "data")) == []


def test_lua_and_python_know_the_same_tokens(root):
    src = (root / "addon/WoWForeverJapanese/Core/Placeholders.lua").read_text(encoding="utf-8")
    m = re.search(r"Placeholders\.KNOWN\s*=\s*\{([^}]*)\}", src)
    assert m, "Placeholders.KNOWN not found in Core/Placeholders.lua"
    lua_known = tuple(re.findall(r'"([A-Za-z]+)"', m.group(1)))
    assert lua_known == placeholders.KNOWN
