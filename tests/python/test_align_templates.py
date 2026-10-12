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
    ("$@spellaura12 x", "missing_included_spell:12"),
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
    # a level table whose top branch is a code prints the same wording on every branch: the pre-draft check
    # reads the three as one (the Japanese side still sees the literal branches shadowed by the code)
    table = "grants $?$PL<24[6]?$PL<38[11][$1230172s1] Strength for $d."
    assert _pairs(table) == [] and not align.never_shown(_pairs(table), 3)


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


# the templates the first pass could not place: spellaura, angle ids, $@null, expandkey, a whitespace else,
# the widened name-list tail, and variant keys --------------------------------------------------------------

BOSS = {
    (437479, "description"): "Balnazzar unleashes a swarm, causing $s1 Shadow damage every $t1 sec for $d.",
    (437479, "aura"): "Inflicting $s1 Shadow damage every $t1 sec to allies within $437480A1 yards.",
    (1243081, "description"): "Inflicts $S1 Shadow damage to the current enemy target.",
    (1302929, "description"): "Expanded by the client.",
    (1296663, "name"): "Swords",
}


def test_spellaura_splices_the_included_spells_aura_text():
    x = align.expand_inclusions("$@spellaura437479", BOSS)
    assert x.text == BOSS[(437479, "aura")]
    assert align.included_spells("$@spellaura437479", BOSS) == [(437479, "aura")]


def test_an_id_in_angle_brackets_is_the_same_id_for_every_inclusion():
    assert align.expand_inclusions("$@spelldesc<1243081>\r\n", BOSS).text == BOSS[(1243081, "description")] + "\r\n"
    assert align.expand_inclusions("$@spellaura<437479>", BOSS).text == BOSS[(437479, "aura")]
    assert align.expand_inclusions("$@spellname<1296663>!", BOSS).text == "Swords!"
    assert align.included_spells("$@spelldesc<1243081> $@spellicon<7>", BOSS) == [(1243081, "description")]


def test_a_bare_spellaura_still_names_its_reason():
    assert align.expand_inclusions("$@spellaura x", BOSS) == align.Expansion(None, "unsupported_code:$@spellaura")


def test_null_splices_nothing():
    assert align.expand_inclusions("$@null\r\n$@null", BOSS).text == "\r\n"
    assert align.expand_inclusions("Gain $@null$s1.", BOSS).text == "Gain $s1."
    assert align.expand_inclusions("$@null5", BOSS).reason == "unsupported_code:$@null"  # not a 5
    assert align.included_spells("$@null", BOSS) == []


EXPANDKEY = ("You have $sk43/$<sc> skill in $@spellname1296663.\r\n\r\nLevel $PL target:\r\nHit: ${$<hdp>}.1%\r\n"
             "$@expandkey[\r\nLevel ${$PL+1} target:\r\nHit: ${$<hdp1>}.1%\r\n\r\n$@spelldesc1302929\r\n]")


def test_expandkey_is_a_branch_with_an_empty_else():
    x = align.expand_inclusions(EXPANDKEY, BOSS)
    assert x.reason is None and "$@" not in x.text and "$?expandkey[" in x.text
    b = align.branching(x.text)
    assert b.reason is None
    assert [v.shape for v in b.variants] == ["6/0", "4/0"]
    assert b.variants[1].en == "You have $sk43/$<sc> skill in Swords.\r\n\r\nLevel $PL target:\r\nHit: ${$<hdp>}.1%\r\n"
    texts, bad = align.ja_variants("Swordsのスキルは$N1/$N2。\r\n\r\nレベル$N3：\r\n命中：$N4%\r\n$?expandkey[\r\n"
                                   "レベル$N5：\r\n命中：$N6%\r\n\r\nExpanded。\r\n][]", b)
    assert bad == [] and len(texts) == 2 and texts[1].endswith("命中：$N4%\r\n")


def test_whitespace_between_a_branch_and_its_else_reads_as_the_else():
    en = "$?a443369[Heals for $s1.]\r\n\r\n[Stores energy for $d. Heals for $s1.]"
    b = align.branching(en)
    assert b.reason is None
    assert [v.en for v in b.variants] == ["Heals for $s1.", "Stores energy for $d. Heals for $s1."]
    ja = "$?a443369[$N1回復する。]\r\n\r\n[$D1の間エネルギーを蓄える。$N3回復する。]"
    assert align.ja_variants(ja, b) == (["$N1回復する。", "$D1の間エネルギーを蓄える。$N2回復する。"], [])
    assert align.ja_variants("$?a443369[$N1回復する。][$D1の間蓄える。$N3回復する。]", b)[1] == []
    # text other than whitespace before the bracket is no else: the bracket is stray
    assert align.parse_branches("$?a1[A] then [B]") is None
    assert align.branching("$?a1[A] then [B]").reason == "unclosed_branch"


def test_a_line_break_between_a_condition_and_its_bracket_is_still_the_conditional():
    b = align.branching("Known:\r\n$?pc1\r\n[A $s1][]")
    assert [v.en for v in b.variants] == ["Known:\r\nA $s1", "Known:\r\n"]


RIDING = ("Allows you to ride basic ground mounts that require a riding skill of 75.\r\n\r\nKnown abilities:"
          "$?s824[\r\n$@spellname824][]$?s18995[\r\n$@spellname18995][]")
TOTEMS = ("Provide the Shaman with earth enchanted totems. \r\n\r\nYou currently have access to:\r\n$?pc166190\r\n"
          "[$@spellicon8075$@spellname8075][]\r\n$?pc166245\r\n[$@spellicon2484 \r\n$@spellname2484][]\r\n\r\n")
PALADIN = ("Fill the Paladin with various divine enhancements. \r\n\r\nYou currently have access to:\r\n"
           "$?pc166120[$@spellicon21082 $@spellname21082][]\r\n$?pc166138[|cFFFFFFFF$@spellicon25742 $@spellname20287|r][]")
LANGUAGES = "You are fluent in the following languages:$?s668[\r\n$@spellname668][]$?s669[\r\n$@spellname669][]"


@pytest.mark.parametrize(("en", "head"), [
    (RIDING, "Allows you to ride basic ground mounts that require a riding skill of 75.\r\n\r\nKnown abilities:"),
    (TOTEMS, "Provide the Shaman with earth enchanted totems. \r\n\r\nYou currently have access to:"),
    (PALADIN, "Fill the Paladin with various divine enhancements. \r\n\r\nYou currently have access to:"),
    (LANGUAGES, "You are fluent in the following languages:"),
])
def test_an_icon_or_name_list_after_a_multi_line_head_is_a_tail(en, head):
    assert align.split_tail(en) == (head, True)
    assert align.value_slots(en) == (1 if en is RIDING else 0)


def test_what_is_not_a_tail():
    # a head holding a conditional of its own, a branch with prose, an empty head, a chain that is not trailing
    assert align.split_tail("$?s1[A][B] Known:$?s824[\r\n$@spellname824][]")[1] is False
    assert align.split_tail("Known:$?s824[\r\nYou know $@spellname824][]")[1] is False
    assert align.split_tail("$?s824[\r\n$@spellname824][]")[1] is False
    assert align.split_tail("Known:$?s824[\r\n$@spellname824][] and more.")[1] is False
    assert align.split_tail("Known:$?s824[\r\n$@spellname824][$@spellname825]")[1] is False
    # an element that prints no name or icon is no list
    for empty in ("", " ", "|cFFFFFFFF|r"):
        assert align.split_tail(f"Known:$?s824[{empty}][]")[1] is False


def test_a_tail_draft_keeps_the_heads_line_breaks():
    ja_ok = "基本的な地上マウントに乗れます。\r\n\r\n習得済み：$T"
    assert align.tail_problems(RIDING, ja_ok) == []
    assert align.tail_problems(RIDING, "基本的な地上マウントに乗れます。\n\n習得済み：$T") == []  # a bare \n counts alike
    assert align.tail_problems(RIDING, "基本的な地上マウントに乗れます。習得済み：$T") == ["tail_breaks"]
    assert align.tail_problems(RIDING, "基本的な地上マウントに乗れます。\r\n\r\n\r\n習得済み：$T") == ["tail_breaks"]
    assert align.tail_problems(LANGUAGES, "次の言語：$T") == []


# variant keys --------------------------------------------------------------------------------------------------


def test_a_variant_key_is_the_wording_with_its_values_masked():
    a = align.variant_key("Increases all damage you deal by $s1%.")
    b = align.variant_key("Increases the damage you deal with physical attacks in all forms by $s1%.")
    assert a != b and len(a) == 16
    # a value, a sum, a duration with its unit word, a range, an icon and a code all mask alike
    assert align.variant_key("Deals $s1 damage") == align.variant_key("Deals ${$s1*2}.1 damage")
    assert align.variant_key("Lasts $d.") == align.variant_key("Lasts 30 sec.")
    assert align.variant_key("Causes $s1 to $s2 Fire damage") == align.variant_key("Causes 14 Fire damage")
    assert align.variant_key("$I1 Fire: $s1") == align.variant_key("Fire: 5")
    assert align.variant_key("Hit  $s1\r\n") == align.variant_key("Hit 5")  # normalized whitespace
    # the masked wording is what the key hashes
    from wfj.core.hashing import key as hash_key
    from wfj.core.normalize import normalize_v1
    assert a == hash_key(normalize_v1("Increases all damage you deal by #%.", player_tokens=False))


def test_a_variant_holding_a_word_code_has_no_key():
    assert align.variant_key("Returns you to $z.") is None
    assert align.variant_key("Lasts $s1 $lsecond:seconds;.") is None
    assert align.variant_key("Deals $s1 damage.") is not None


def test_variant_keys_are_the_lines_keys_or_none():
    b = align.branching("$?s436895[Increases all damage you deal by $s1%.][Increases the damage you deal by $s1%.]")
    keys = align.variant_keys(b.variants)
    assert keys and len(keys) == 2 and keys[0] != keys[1]
    same = align.branching("Gain $?a1[$s1][$s2] armor.")  # masked alike: no key tells them apart
    assert align.variant_keys(same.variants) is None
    word = align.branching("$?a1[Returns you to $z.][Returns you home.]")
    assert align.variant_keys(word.variants) is None


def test_the_pre_draft_check_reads_masked_equal_variants_as_one():
    """1218700 prints one of two codes: the same wording either way, so nothing is shadowed."""
    b = align.branching("Your Evocation grants you $?a1218232|a1224428[$1218701s1%][$1218701s2%] damage, lasting $1218701d.")
    texts = [v.en for v in b.variants]
    assert align.indistinguishable(texts, texts, [v.shape for v in b.variants], set(), english=True) == []
    # two wordings still shadow each other (the Japanese side is unchanged)
    assert _pairs("$?s1[Increases all damage by $s1%.][Increases the damage by $s1%.]") == [(0, 1), (1, 0)]
