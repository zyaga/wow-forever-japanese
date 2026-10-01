"""Manual line breaks in hand-written tooltip Japanese are joined when generated (ADR-049)."""

from wfj.core import tooltip_text

HUMAN = {"class": "human", "translator": "t", "source": "x", "imported": "2026-01-01"}
MACHINE = {"class": "machine", "model": "m", "source": "draft-x", "imported": "2026-01-01"}


def test_a_single_break_the_english_lacks_is_joined():
    assert tooltip_text.join_breaks("対象に$N1のNature属性ダメージを\n与えます。", "Causes $s1 Nature damage to the target.") \
        == "対象に$N1のNature属性ダメージを与えます。"


def test_a_paragraph_break_is_kept_and_carriage_returns_go():
    en = "Holding the Night Watchman's Torch.\r\n\r\nThis effect will end if you enter combat."
    assert tooltip_text.join_breaks("Torchを持って\r\nいます。\r\n\r\n戦闘に入ると終了します。", en) \
        == "Torchを持っています。\n\n戦闘に入ると終了します。"


def test_a_line_whose_english_has_its_own_single_break_keeps_every_break():
    ja = "$N1のHolyダメージを与えます。\n聖なる泉の力が\n王笏から放たれています。"
    assert tooltip_text.join_breaks(ja, "Smite, inflicting $s1 Holy damage.\nThe powers radiate from the scepter.") == ja


def test_two_latin_words_a_break_kept_apart_get_a_space():
    assert tooltip_text.join_breaks("Foreman Thistlenettle\nExplorers' Leagueのメンバー", "Foreman Thistlenettle, Explorers' League member") \
        == "Foreman Thistlenettle Explorers' Leagueのメンバー"


def test_no_english_means_no_join_but_carriage_returns_still_go():
    assert tooltip_text.join_breaks("a\r\nb", None) == "a\nb"


def test_a_machine_line_keeps_its_breaks_and_loses_its_carriage_returns():
    line = {"id": 1, "field": "description", "ja": "- Linen Cloth\r\n×$N1\n- Light Leather ×$N2", "provenance": MACHINE}
    assert tooltip_text.shipped_ja(line, "Fill the crate: $@spelldesc1") == "- Linen Cloth\n×$N1\n- Light Leather ×$N2"


def test_joined_copies_only_the_lines_it_changes():
    lines = [{"id": 1, "field": "description", "ja": "あ\nい", "provenance": HUMAN},
             {"id": 2, "field": "description", "ja": "う", "provenance": HUMAN}]
    english = {(1, "description"): "x", (2, "description"): "y"}
    out = tooltip_text.joined(lines, english)
    assert out[0]["ja"] == "あい" and out[0] is not lines[0] and lines[0]["ja"] == "あ\nい"
    assert out[1] is lines[1]
