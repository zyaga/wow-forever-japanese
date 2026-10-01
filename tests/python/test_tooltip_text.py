"""Manual line breaks in tooltip Japanese are joined when generated (ADR-049)."""

from wfj.core import tooltip_text


def test_a_single_break_the_english_lacks_is_joined():
    assert tooltip_text.join_breaks("対象に$N1のNature属性ダメージを\n与えます。", "Causes $s1 Nature damage to the target.") \
        == "対象に$N1のNature属性ダメージを与えます。"


def test_a_paragraph_break_is_kept():
    ja = "Night Watchman's Torchを持っています。\n\n戦闘に入るとこの効果は終了します。"
    assert tooltip_text.join_breaks(ja, "Holding the Night Watchman's Torch.\r\n\r\nThis effect will end if you enter combat.") == ja


def test_a_line_whose_english_has_its_own_single_break_keeps_every_break():
    ja = "聖なる泉の力で対象を打ち据え、$N1のHolyダメージを与えます。\n聖なる泉の力が\n王笏から放たれています。"
    assert tooltip_text.join_breaks(ja, "Smite your target, inflicting $s1 Holy damage.\nThe powers radiate from the scepter.") == ja


def test_no_english_means_no_change():
    assert tooltip_text.join_breaks("a\nb", None) == "a\nb"


def test_joined_copies_only_the_lines_it_changes():
    lines = [{"id": 1, "field": "description", "ja": "a\nb"}, {"id": 2, "field": "description", "ja": "c"}]
    english = {(1, "description"): "x", (2, "description"): "y"}
    out = tooltip_text.joined(lines, english)
    assert out[0] == {"id": 1, "field": "description", "ja": "ab"} and out[0] is not lines[0]
    assert out[1] is lines[1] and lines[0]["ja"] == "a\nb"
