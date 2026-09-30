"""Format specifiers: the Japanese UI template takes exactly the English template's arguments."""

import pytest

from wfj.core import specifiers


def test_parse_plain_positional_and_literal_percent():
    assert specifiers.parse("%c%d Stamina") == [(1, "c"), (2, "d")]
    assert specifiers.parse("%.3g sec cast") == [(1, ".3g")]
    assert specifiers.parse("%2$s は %1$d") == [(2, "s"), (1, "d")]
    assert specifiers.parse("100%% sure") == []
    assert specifiers.parse("%.f and %5.f") == [(1, ".f"), (2, "5.f")]  # matches the Lua twin
    with pytest.raises(ValueError):
        specifiers.parse("%s and %2$s")


@pytest.mark.parametrize(
    "en, ja",
    [
        ("Accept", "受諾"),
        ("Durability %d / %d", "耐久度 %d / %d"),
        ("%s - %s Damage", "%1$s～%2$s ダメージ"),
        ("Requires %s - %s", "%2$sの%1$sが必要"),
        ("%.1f damage per second", "毎秒 %.1f ダメージ"),
    ],
)
def test_same_arguments(en, ja):
    assert specifiers.mismatch(en, ja) is None


@pytest.mark.parametrize(
    "en, ja, detail",
    [
        ("Durability %d / %d", "耐久度 %d", "en[%1$d %2$d] ja[%1$d]"),
        ("%.1f damage per second", "毎秒 %.2f ダメージ", "en[%1$.1f] ja[%1$.2f]"),
        ("%s - %s Damage", "%2$d～%1$s", "en[%1$s %2$s] ja[%1$s %2$d]"),
        ("Accept", "受諾%s", "en[none] ja[%1$s]"),
        ("%s x", "%s と %2$s", "ja mixes plain and positional specifiers"),
    ],
)
def test_different_arguments(en, ja, detail):
    assert specifiers.mismatch(en, ja) == detail


def test_a_space_flag_running_into_a_word_is_prose():
    # as in OPTION_TOOLTIP_RENDER_SCALE: "Render scale above 100% is for supersampled anti-aliasing"
    assert specifiers.parse("Render scale above 100% is for SSAA.") == []
    assert specifiers.mismatch("Render scale above 100% is for SSAA.", "100%を超える値はSSAA用です。") is None
    assert specifiers.parse("% d left") == [(1, " d")]  # a real space-flag specifier still parses
