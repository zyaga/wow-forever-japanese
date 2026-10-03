"""align: SECTIONED lines (a heading, then optional paragraphs each found by its opening words)."""

from wfj.core import align
from wfj.emit import lua_writer

EN = ("Gained the following camp benefits:\r\n\r\n"
      "$?a1[Tent: You rest. Once per $1d.\r\n\r\n][]"
      "$?a2[Mana Well: Restores $2w1 Mana every $2t seconds.\r\n\r\n][]"
      "$?a3[Lodestone: Attack Power increased by $3w1.\r\n\r\n][]"
      "$?a4[Faction Banner: Spirit increased by $4w1.][]")
JA = ("以下のキャンプの恩恵を得た：\n\n"
      "$?a1[Tent：休息した。$D1に一度。\n\n][]"
      "$?a2[Mana Well：$N3秒ごとにマナを$N2回復する。\n\n][]"
      "$?a3[Lodestone：攻撃力が$N4上昇。\n\n][]"
      "$?a4[Faction Banner：精神が$N5上昇。][]")


def test_too_many_combinations_of_whole_paragraphs_become_sections():
    assert not align.branching(EN).sectioned  # 4 parts, 16 combinations: the ordinary variants still serve it
    many = EN.replace("$?a4[Faction Banner: Spirit increased by $4w1.][]",
                      "$?a4[Faction Banner: Spirit increased by $4w1.\r\n\r\n][]$?a5[Camp Chair: Crit up $5w1.][]")
    b = align.branching(many)
    assert b.reason is None and b.sectioned
    assert [v.shape for v in b.variants] == ["0/0", "1/1", "2/0", "1/0", "1/0", "1/0"]
    texts, bad = align.ja_variants(JA.replace("$?a4[Faction Banner：精神が$N5上昇。][]",
                                              "$?a4[Faction Banner：精神が$N5上昇。\n\n][]$?a5[Camp Chair：$N6。][]"), b)
    assert bad == []
    assert texts[2].endswith("Mana Well：$N2秒ごとにマナを$N1回復する。\n\n")  # renumbered to its own values


def test_a_part_without_opening_words_or_a_heading_with_a_code_is_not_sectioned():
    no_words = "Head:\r\n\r\n" + "".join(f"$?a{i}[$1w{i} more.\r\n\r\n][]" for i in range(1, 6))
    assert align.branching(no_words).reason == "too_many_variants"
    coded = "Head $1d:\r\n\r\n" + "".join(f"$?a{i}[Part {i}: up by $1w{i}.\r\n\r\n][]" for i in range(1, 6))
    assert align.branching(coded).reason == "too_many_variants"


def test_sections_ship_as_their_own_lua_slot():
    lit = lua_writer.variants_literal({"head": "見出し", "hkey": "00ff", "sections": [
        {"n": 6, "key": "abcd", "ja": "Tent：休息", "shape": "1/1"}]})
    assert lit == ('{ sections = { head = "見出し", hkey = "00ff", '
                   '{ n = 6, key = "abcd", ja = "Tent：休息", shape = "1/1" } } }')


def test_an_opening_that_begins_another_opening_ships_nothing():
    from wfj.cmd.generate import _sections
    parts = ["Tent: You rest $1d.", "Tent: You rest well $2w1.", "Banner: Up $3w1.", "Well: Up $4w1.", "Chair: Up $5w1."]
    en = "Head:\r\n\r\n" + "".join(f"$?a{i}[{p}\r\n\r\n][]" for i, p in enumerate(parts, 1))
    b = align.branching(en)
    assert b.sectioned
    texts = ["見出し\n\n"] + [f"見出し\n\n部分{i}\n\n" for i in range(1, len(b.variants))]
    assert _sections(b, texts) == "sections_indistinguishable"
    other = align.branching(en.replace("Tent: You rest well", "Lodge: You rest well"))
    assert isinstance(_sections(other, texts), dict)


def test_a_heading_with_a_number_ships_nothing():
    from wfj.cmd.generate import _sections
    parts = ["Tent: Rest $1d.", "Banner: Up $2w1.", "Well: Up $3w1.", "Chair: Up $4w1.", "Pot: Up $5w1."]
    en = "Gained 5 camp benefits:\r\n\r\n" + "".join(f"$?a{i}[{p}\r\n\r\n][]" for i, p in enumerate(parts, 1))
    b = align.branching(en)
    assert b.sectioned
    texts = ["見出し5\n\n"] + [f"見出し5\n\n部分{i}\n\n" for i in range(1, len(b.variants))]
    assert _sections(b, texts) == "sections_head_has_values"
