"""Templates that include another spell's text, and templates that branch (ADR-043).

`expand_inclusions` · the slot model is unchanged for every template it counted · `branching` /
`ja_variants` · `indistinguishable` · `included_spells`."""

from pathlib import Path

import pytest

from wfj.core import align
from wfj.io.jsonl_store import Store

SPELLS = {
    (434, "description"): "Restores $o1 health over $d.  Must remain seated while eating.",
    (434, "name"): "Food",
    (1243969, "description"): "Reduces the chance of an ambush by $s1%.",
    (5, "description"): "Includes $@spelldesc6.",
    (6, "description"): "Includes $@spelldesc5.",
    (7, "aura"): "Well Fed.",
}


# expand_inclusions ---------------------------------------------------------------------------------------------


def test_two_inclusions_are_spliced_in_where_they_stand():
    en = "$@spelldesc434 If you spend at least 10 seconds eating you gain $s2%. $@spelldesc1243969"
    x = align.expand_inclusions(en, SPELLS)
    assert x.reason is None
    assert x.text == ("Restores $o1 health over $d.  Must remain seated while eating. If you spend at least 10 "
                      "seconds eating you gain $s2%. Reduces the chance of an ambush by $s1%.")
    # the spliced line counts: $o1, $d, 10 (a duration: "10 seconds" is not a unit the addon reads), $s2, $s1
    assert align.value_slots(x.text) == 5


def test_nested_inclusions_names_tooltips_and_icons():
    spells = {**SPELLS, (8, "description"): "Grants $@spelltooltip7 $@spellicon434 $@spellname434 $@spelldesc434"}
    x = align.expand_inclusions("Use: $@spelldesc8 Then $@spellicon7.", spells)
    assert x.text == ("Use: Grants Well Fed. $I1 Food Restores $o1 health over $d.  Must remain seated while "
                      "eating. Then $I2.")
    assert align.icon_indices(x.text) == [1, 2]


@pytest.mark.parametrize(("en", "reason"), [
    ("$@spelldesc399963 More.", "missing_included_spell:399963"),
    ("$@spelldesc5", "inclusion_cycle:5"),
    ("Controlled by $@auracaster.", "unsupported_code:$@auracaster"),
    ("$@spellaura12 x", "unsupported_code:$@spellaura"),
])
def test_what_cannot_be_expanded_says_why(en, reason):
    assert align.expand_inclusions(en, SPELLS) == align.Expansion(None, reason)


def test_depth_is_bounded():
    chain = {(i, "description"): f"$@spelldesc{i + 1}" for i in range(100, 110)}
    assert align.expand_inclusions("$@spelldesc100", chain).reason == "inclusion_depth"


def test_included_spells_lists_every_spliced_spell_nested_ones_too():
    spells = {**SPELLS, (8, "description"): "Grants $@spelltooltip7 and $@spelldesc434 $@spellname434"}
    assert align.included_spells("$@spelldesc8 $@spellicon9 $@spelldesc404", spells) == [
        (8, "description"), (7, "aura"), (434, "description"), (434, "name"), (404, "description")]


# the slot model ------------------------------------------------------------------------------------------------


def test_an_icon_is_never_a_value():
    assert align.value_slots("Gain $I1 Quick Draw: $s1 damage.") == 1
    assert align.slot_problems("Gain $I1 Quick Draw: $s1 damage.", "$I1 Quick Draw：$N1のダメージ。") == []


def test_no_english_template_holds_an_icon_placeholder():
    """The one input the slot model now reads differently is `$I<k>`; no English template writes one, so every
    template it counted before counts the same (the whole-corpus parity run is in /test)."""
    root = Path(__file__).resolve().parents[2] / "data"
    for type_ in ("item", "spell"):
        for ln in Store(root, english=True).load(type_):
            assert not align.ICON.search(ln["en"]), (type_, ln["id"], ln["field"])


# branching / ja_variants ---------------------------------------------------------------------------------------

FIRE_WARD = ("Absorbs $s1 Fire damage$?s11094[ and grants a $s2% chance to reflect Fire spells and effects][]."
             "  Lasts $d.")


def test_fire_ward_splits_into_a_clause_and_no_clause():
    b = align.branching(FIRE_WARD)
    assert b.reason is None and (b.slots, b.durations) == (3, 1)
    with_clause, without = b.variants
    assert (with_clause.values, with_clause.durations, with_clause.shape) == ((1, 2, 3), (1,), "3/1")
    assert (without.values, without.durations, without.shape) == ((1, 3), (1,), "2/1")
    assert without.en == "Absorbs $s1 Fire damage. Lasts $d."


def test_japanese_variants_are_renumbered_to_their_own_reading_order():
    b = align.branching(FIRE_WARD)
    ja = "$N1の炎ダメージを吸収する$?s11094[。さらに$N2%の確率で炎の呪文と効果を反射する][]。効果時間は$D1。"
    texts, bad = align.ja_variants(ja, b)
    assert bad == []
    assert texts == ["$N1の炎ダメージを吸収する。さらに$N2%の確率で炎の呪文と効果を反射する。効果時間は$D1。",
                     "$N1の炎ダメージを吸収する。効果時間は$D1。"]
    # a value that follows the conditional moves down in the variant without the clause
    b2 = align.branching("Absorbs $s1$?s1[ and $s2%][]. Heals $s3.")
    texts2, _ = align.ja_variants("$N1吸収$?s1[、$N2%][]。$N3回復。", b2)
    assert texts2 == ["$N1吸収、$N2%。$N3回復。", "$N1吸収。$N2回復。"]


@pytest.mark.parametrize(("ja", "reason"), [
    ("$N1の炎ダメージを吸収する。効果時間は$D1。", "branch_skeleton"),  # the conditional dropped
    ("$N1吸収$?s99[。$N2%反射][]。$D1。", "branch_skeleton"),  # another condition
    ("$N1吸収$?s11094[][。$N2%反射]。$D1。", "branch_index:N2"),  # the clause's value in the wrong branch
])
def test_a_japanese_that_does_not_fit_the_skeleton_is_refused(ja, reason):
    texts, bad = align.ja_variants(ja, align.branching(FIRE_WARD))
    assert texts is None and reason in bad


def test_chains_and_nested_conditionals():
    b = align.branching("Your casts of $?s2060[Greater Heal]?s5185[Healing Touch][Flash Heal] cost $s1 less.")
    assert [v.en for v in b.variants] == ["Your casts of Greater Heal cost $s1 less.",
                                          "Your casts of Healing Touch cost $s1 less.",
                                          "Your casts of Flash Heal cost $s1 less."]
    nested = align.branching("A$?s1[ B$?s2[ C][ D]][ E].")
    assert sorted(v.en for v in nested.variants) == ["A B C.", "A B D.", "A E."]


def test_too_many_variants_and_unclosed_brackets():
    many = " ".join(f"$?s{i}[x{i}][y{i}]" for i in range(5))  # 2**5 = 32 > 16
    assert align.branching(many).reason == "too_many_variants"
    assert align.branching("A $?s1[unclosed").reason == "unclosed_branch"


# indistinguishable ---------------------------------------------------------------------------------------------


def _pairs(en, texts=None):
    b = align.branching(en)
    en_texts = [v.en for v in b.variants]
    shapes = [v.shape for v in b.variants]
    if texts is None:
        return align.indistinguishable(en_texts, en_texts, shapes, set(), english=True)
    return align.indistinguishable(texts, en_texts, shapes, set())


def test_shape_names_and_literals_tell_variants_apart():
    assert _pairs(FIRE_WARD) == []
    signs = "Add this sign to your $?pc923[Orcish Tradeskill Sign][Dwarven Tradeskill Sign] toy for $d."
    assert _pairs(signs) == []
    assert _pairs(signs, ["Orcish Tradeskill Signのおもちゃ。$D1。", "Dwarven Tradeskill Signのおもちゃ。$D1。"]) == []
    assert _pairs("gain $?$PL<24[6]?$PL<38[11][16] Stamina for $d.") == []


def test_a_shadowed_variant_ships_but_a_line_with_nothing_to_show_does_not():
    """Tiger's Fury prints the same words in white or red: the red variant's text passes on the white line too
    (its colour code's letters are in the white one), so the white line shows English (never the red text,
    since both pass there) while the red line still shows Japanese. A level table whose top branch is a code
    (`[$1230172s1]`) is shadowed the same way on its literal branches."""
    cat = "$?a768[|CFFFFFFFFRequires Cat Form|R][|CFFFF2020Requires Cat Form|R]  Increases damage by $s1."
    assert _pairs(cat) == [(0, 1)] and not align.never_shown(_pairs(cat), 2)
    table = "grants $?$PL<24[6]?$PL<38[11][$1230172s1] Strength for $d."
    assert {a for a, _ in _pairs(table)} == {0, 1} and not align.never_shown(_pairs(table), 3)


def test_a_japanese_that_drops_the_name_is_never_shown():
    signs = "Add this sign to your $?pc923[Orcish Tradeskill Sign][Dwarven Tradeskill Sign] toy for $d."
    assert align.never_shown(_pairs(signs, ["オークの看板。$D1。", "ドワーフの看板。$D1。"]), 2)


def test_an_empty_branch_leaves_no_double_space_in_its_variant():
    b = align.branching("Restores $o1 health over $d. $?s446847[In Naxxramas, more.][] Must remain seated.")
    assert b.variants[1].en == "Restores $o1 health over $d. Must remain seated."


def test_a_branch_that_prints_nothing_is_no_variant():
    b = align.branching("$?s1[Gain $s1 armor.][]")
    assert [v.en for v in b.variants] == ["Gain $s1 armor."]
    texts, bad = align.ja_variants("$?s1[防御力が$N1上昇します。][]", b)
    assert texts == ["防御力が$N1上昇します。"] and bad == []


def test_icons_are_renumbered_per_variant():
    """A variant that leaves out an earlier icon still numbers its own icons from 1."""
    b = align.branching("$?s1[$I1 Fire.][Frost.] Then $I2 Heal.")
    assert [(v.en, v.icons) for v in b.variants] == [("$I1 Fire. Then $I2 Heal.", (1, 2)), ("Frost. Then $I1 Heal.", (2,))]
    texts, bad = align.ja_variants("$?s1[$I1 Fire。][Frost。]次に$I2 Heal。", b)
    assert texts == ["$I1 Fire。次に$I2 Heal。", "Frost。次に$I1 Heal。"] and bad == []


def test_a_shadowed_variant_with_an_icon_its_shadower_lacks_is_unsafe():
    """Should the icon not fill on its own line, the other variant would show alone."""
    texts = ["$I1 Fireで$N1回復", "$N1回復"]
    pairs = align.indistinguishable(texts, ["$I1 Fire heals $s1", "Heals $s1"], ["1/0", "1/0"], set())
    assert (0, 1) in pairs and align.unsafe_shadow(pairs, texts)
    assert not align.unsafe_shadow([(1, 0)], texts)


def test_a_stray_bracket_is_not_read_as_a_branch():
    """A stray or nested bracket is never read as a branch."""
    assert align.parse_branches("$?s1[A[1]][B]") is None
    assert align.branching("Deals ] damage $?s1[a][b]").reason == "unclosed_branch"
