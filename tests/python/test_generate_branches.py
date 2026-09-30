"""ADR-043: a shipped item / spell line whose Japanese keeps `$?` conditionals ships as a table of
variants, each renumbered to its own reading order, with its shape; every other line is emitted as before."""

import pytest

from wfj.cmd import generate
from wfj.emit import lua_writer
from wfj.io.jsonl_store import Store

SRC = "db2@1.60.1.70009"
EN = "Absorbs $s1 Fire damage$?s11094[ and grants a $s2% chance to reflect Fire spells][]. Lasts $d."
JA = "$N1のFireダメージを吸収する$?s11094[。さらに$N2%の確率でFire呪文を反射する][]。効果時間は$D1。"


def _line(ja, id_=543):
    return {"id": id_, "field": "description", "ja": ja, "status": "unaligned", "checks": [], "reasons": [],
            "conflicts": [], "english": {"hash": "0123456789abcdef", "src": SRC},
            "provenance": {"class": "machine", "model": "m", "source": "draft-s01", "imported": "2026-09-27"}}


@pytest.fixture
def root(tmp_path):
    data = tmp_path / "data"
    (tmp_path / "pipeline").mkdir()
    (tmp_path / "pipeline" / "allowlist.txt").write_text("health  # a stat\n", encoding="utf-8")
    Store(data, english=True).save("spell", [
        {"id": 543, "field": "description", "en": EN, "hash": "0123456789abcdef", "src": SRC},
        {"id": 5217, "field": "description", "hash": "0123456789abcdef", "src": SRC,
         "en": "$?a768[|CFFFFFFFFRequires Cat Form|R][|CFFFF2020Requires Cat Form|R] Deals $s1."},
    ])
    return data


def test_a_branch_line_ships_its_variants_and_shapes(root):
    lines = [_line(JA), _line("$N1のダメージ。", 10)]
    got, refused = generate.branch_variants("spell", lines, Store(root, english=True))
    assert refused == {}
    assert got == {(543, "description"): [
        ("$N1のFireダメージを吸収する。さらに$N2%の確率でFire呪文を反射する。効果時間は$D1。", "3/1"),
        ("$N1のFireダメージを吸収する。効果時間は$D1。", "2/1"),
    ]}
    rows = lua_writer.rows("spell", lines, branches=got)
    assert rows[543][0] == ('{ "$N1のFireダメージを吸収する。さらに$N2%の確率でFire呪文を反射する。効果時間は$D1。", '
                           '"$N1のFireダメージを吸収する。効果時間は$D1。", shape = { "3/1", "2/1" } }')
    assert rows[10] == lua_writer.rows("spell", [_line("$N1のダメージ。", 10)])[10]  # an ordinary line: unchanged


def test_a_branch_line_that_cannot_ship_shows_english_and_never_breaks_the_build(root):
    """A branch line whose English moved on (stale), whose Japanese no longer fits,
    whose variants none could ever show, or with an empty variant is refused (reported, not raised) and ships
    nothing (the English with the missing marker)."""
    english = Store(root, english=True)
    bad = {
        "stale": {**_line(JA), "status": "stale"},
        "branch_skeleton": _line("$N1吸収$?s1[x][y]$?s2[x][y]。$D1。"),
        "branches_indistinguishable": {**_line("$?a768[攻撃][攻撃する] $N1のダメージ。"), "id": 5217},
    }
    for reason, ln in bad.items():
        shipped, refused = generate.branch_variants("spell", [ln], english)
        assert shipped == {} and refused == {(ln["id"], "description"): reason}, reason
    lines = [{**_line(JA), "status": "stale"}, _line("$N1のダメージ。", 10)]
    shipped, refused = generate.branch_variants("spell", lines, english)
    rows = lua_writer.rows("spell", [ln for ln in lines if (ln["id"], ln["field"]) not in refused], branches=shipped)
    assert 543 not in rows and 10 in rows
