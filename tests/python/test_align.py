from wfj.core import align
from wfj.core.align import (
    allowlist_problems,
    check_names,
    check_numbers,
    english_number_words,
    latin_names,
    load_allowlist,
    numbers,
)

AL = load_allowlist("Health  # stat\nMana  # stat\nHorde  # faction\n")


def test_latin_names_multiword_and_allowlist():
    ja = "Silverwind RefugeにいるSenani Thunderheartは、Sharptalon's Clawを見た。Healthを回復。{name}!"
    assert latin_names(ja, AL) == ["Silverwind Refuge", "Senani Thunderheart", "Sharptalon's Claw"]
    assert latin_names("Hordeの兵士", AL) == []
    assert latin_names("Mk2 の ab cd", AL) == []  # < 3 letters after digits; short runs dropped


def test_check_names_quest_scope_and_word_fallback():
    scope = (
        "Bring Sharptalon's Claw to Senani Thunderheart at Splintertree Post, Ashenvale. Sharptalon's Claw"
    )
    checked, missing = check_names("Silverwind RefugeにいるSenani Thunderheart", scope, AL)
    assert checked == ["Silverwind Refuge", "Senani Thunderheart"] and missing == ["Silverwind Refuge"]
    # a multi-word join that the English writes in another order still passes word by word
    checked, missing = check_names("Post Splintertreeへ", scope, AL)
    assert missing == []


def test_numbers_fold_and_ignore_glued_digits():
    assert numbers("Kobold Verminを１０匹殺し、Mk2を3つ") == {"10": 1, "3": 1}
    checked, missing = check_numbers("6つのバルコニー", "a room with six balconies")
    assert checked == ["6"] and missing == []
    checked, missing = check_numbers("Kobold Verminを8匹", "Kill 10 Kobold Vermin")
    assert missing == ["8"]


def test_english_number_words():
    assert english_number_words("twenty-five silver and two hundred gold, a dozen eggs") == [
        "25",
        "20",
        "200",
        "12",
    ]


def test_allowlist_justification_required():
    assert allowlist_problems("Health  # stat\n") == []
    assert allowlist_problems("Health\n") == ["line 1: no justification"]
    assert allowlist_problems("Mana  #   \n") == ["line 1: no justification"]


# The value-slot count behind `$N<k>`, the addon's placeholder for a number the client fills in.
def test_value_slots_counts_what_the_client_will_print():
    assert align.value_slots("Restores $s1 health.") == 1
    assert align.value_slots("Restores $o1 health over $d.  Must remain seated while eating.") == 2
    assert align.value_slots("Backstab, causing $s2% weapon damage plus $s1 to the target.") == 2
    assert align.value_slots("Charge an enemy, generate $/10;s2 Rage, and Stun it for $7922d.") == 2
    assert align.value_slots("Gives $s1 additional armor to party members within $a1 yards.") == 2
    assert align.value_slots("A simple line with no codes at all.") == 0
    assert align.value_slots("Teaches Frost Ward (Rank 5).") == 1  # a literal the template already shows
    assert align.value_slots("Requires Level 5 and deals $s1 damage.") == 2
    assert align.value_slots("") == 0


def test_value_slots_refuses_to_guess_only_where_the_template_cannot_say():
    """A conditional shows one branch or the other and they print different numbers of values; `$@spelldesc`
    splices another spell's whole description in. Neither can be counted, so the answer is None rather than a guess."""
    for en in (
        "$?j1g[Increases ground speed by $j1g%. ][]",
        "Absorbs $s1 Fire damage$?s11094[ and grants a $s2% chance][]. Lasts $d.",
        "$@spelldesc12627",
        "$@spelldesc434 If you spend at least 10 seconds eating you gain $s1.",
    ):
        assert align.value_slots(en) is None, en
        assert align.duration_slots(en) is None, en


def test_the_countable_codes_are_counted_rather_than_refused():
    """Arithmetic prints the one number it comes to, however many codes are inside it; pluralisation prints
    a word and no number. Both are counted, not refused."""
    ice = "Ice shards pelt the area doing ${$1279976m1*$d*$<frostdamage>} Frost damage over $d."
    assert align.value_slots(ice) == 2  # the sum, then the duration
    assert align.duration_slots(ice) == 1
    assert align.value_slots("Coats a weapon with poison that lasts for ${$m1/60} minutes.") == 1
    assert align.value_slots("Causes ${$m2*$<d>} to ${$M2*$<d>} Frost damage.") == 1  # a range: one value
    assert align.value_slots("$1279976s1 Frost damage every $t3 $lsecond:seconds;.") == 2
    assert align.value_slots("Greetings, $gsir:madam;. Deals $s1 damage.") == 1


def test_fill_indices_reads_the_placeholders_in_order():
    assert align.fill_indices("$N2秒かけて体力を$N1回復します。") == [2, 1]
    assert align.fill_indices("体力を61回復します。") == []
    assert align.fill_indices(None) == []
    assert align.fill_indices("$N10") == [10]


def test_duration_slots_counts_the_values_whose_unit_the_client_chooses():
    assert align.duration_slots("Restores $o1 health over $d.") == 1
    assert align.duration_slots("Lasts $d.") == 1
    assert align.duration_slots("Stun for $7922d and slow for $d1.") == 2
    assert align.duration_slots("Restores $o1 over $d.  Lasts $d.") == 2
    assert align.duration_slots("Deals $s1 damage.") == 0
    assert align.duration_slots("Gives $s1 armor within $a1 yards.") == 0
    assert align.duration_slots("Deals ${$m1*2} over $d.") == 1  # the sum is not a duration; `$d` is
    assert align.duration_slots("Absorbs $s1$?a1[ more][]. Lasts $d.") is None  # a branch: unknowable
    assert align.duration_slots("") == 0


def test_a_duration_is_also_a_value_slot():
    """`$N` indexes every number in reading order, the duration's included; `$D` indexes only durations."""
    assert align.value_slots("Restores $o1 health over $d.") == 2
    assert align.duration_slots("Restores $o1 health over $d.") == 1
    assert align.duration_indices("$D1かけて$N1回復。") == [1]
    assert align.duration_indices("体力を61回復します。") == []
    assert align.duration_indices(None) == []


def test_a_precision_suffix_is_not_a_second_value():
    """`${$s1}.1%` is Blizzard's 'print this to one decimal place'. It renders `2.5%`: ONE number,
    which `Align.values` reads as one token. Counting the `.1` as its own slot told drafters to write
    `$N1.$N2`, filling two values into a line that has one."""
    assert align.value_slots("Improves your critical strike chance by ${$s1}.1%.") == 1
    assert align.value_slots("Reduces the cast time by ${$m1/-1000}.1 sec.") == 1
    assert align.value_slots("Increasing damage by ${$m1/100}.2% and health by ${$m2/100}.2%.") == 2
    assert align.value_slots("Coats a weapon with poison for ${$m1/60} minutes.") == 1
    # a number the client prints in front of a unit is a duration phrase to `Align.durations` too
    assert align.duration_slots("Reduces the cast time by ${$m1/-1000}.1 sec for $d.") == 2


def test_a_named_variable_is_a_value_slot():
    """`$<minDam>` / `$<mult>` print a number like any other code (582 of them in the corpus). Not
    counting them left a drafter's `$N<k>` pointing past the end of the line."""
    assert align.value_slots("Deals $<minDam> to $<maxDam> damage plus $s1.") == 2  # the range, then $s1
    assert align.value_slots("Ice shards doing ${$1279976m1*$d*$<frostdamage>} Frost damage over $d.") == 2


def test_an_english_ordinal_is_the_number_it_reads_as():
    """"Only 40th level or higher" reads as 40 on screen, so a Japanese `40` is not invented."""
    assert align.numbers("Only 40th level or higher players", english=True)["40"] == 1
    assert align.check_numbers("レベル40以上", "Only 40th level or higher players")[1] == []
    assert align.numbers("Only 40th level", english=False)["40"] == 0  # the Japanese side is unchanged


def test_slots_read_the_live_line_the_way_the_addon_does():
    # one value for a decimal or a thousands literal, as `Align.values` reads it
    assert align.value_slots("Reduces cooldown by 0.15 sec.") == 1
    assert align.value_slots("Absorbs 1,200 damage.") == 1
    # a duration written into the text takes a `$D` index before the `$d` that follows it
    en = "Regenerate $s1 health every 5 sec for $d."
    assert align.duration_slots(en) == 2
    assert [(s.kind, s.duration, s.client_unit) for s in align.slots(en)] == [
        ("code", False, False), ("literal", True, False), ("code", True, True)]


def test_slot_problems_need_the_placeholder_that_points_at_the_slot():
    en = "Restores $o1 health over $d."
    assert align.slot_problems(en, "$D1かけて体力を$N1回復します。") == []
    # a bare count would pass this: two placeholders for two codes, but $o1 dropped and $d shown as a bare number
    assert align.slot_problems(en, "$D1かけて体力を$N2回復します。") == ["slot_missing:N1", "duration_as_value:N2"]
    assert align.slot_problems(en, "$N2秒かけて体力を$N1回復します。") == ["duration_as_value:N2", "duration_missing:D1"]
    # the written "5 sec" is duration 1, so the `$d` is duration 2
    en = "Regenerate $s1 health every 5 sec for $d."
    assert align.slot_problems(en, "$D2の間、5秒ごとに体力を$N1回復します。") == []
    assert align.slot_problems(en, "$D1の間、5秒ごとに体力を$N1回復します。") == ["duration_missing:D2"]
    # a literal may be written out; a counter is carried as the code
    assert align.slot_problems("Kill 7 Nightsabers.", "Nightsaberを7体倒す。") == []
    assert align.slot_problems("Slay $1997w Wolves.", "Wolfを$1997w体倒す。") == []
    assert align.slot_problems("Absorbs $s1$?a1[ more][].", "x") is None


def test_duration_units_are_the_units_of_every_duration_string_the_addon_reads():
    """`UNIT` must name exactly what `Align.durations` accepts: the English of the keys in
    `UIStrings.SPELL_DURATIONS`, both forms of each `|4one:many;`, or `$D<k>` indices disagree with the addon."""
    import json
    import re
    from pathlib import Path

    root = Path(__file__).resolve().parents[2]
    lua = (root / "addon/WoWForeverJapanese/Core/UIStringKeys.lua").read_text(encoding="utf-8")
    block = re.search(r"UIStrings\.SPELL_DURATIONS = \{(.*?)\}", lua, re.S).group(1)
    keys = set(re.findall(r'"([A-Z_]+)"', block))
    english = {}
    for path in (root / "data/english/ui").glob("*.jsonl"):
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                row = json.loads(line)
                if row["id"] in keys:
                    english[row["id"]] = row["en"]
    assert set(english) == keys
    units = set()
    for en in english.values():
        rest = re.sub(r"%[\d.]*[df]\s*", "", en)
        for one, many in re.findall(r"\|4([^:;]+):([^;]+);", rest):
            units |= {one, many}
        units |= set(re.sub(r"\|4[^;]*;", "", rest).split())
    assert units == set(align.DURATION_UNITS)
    # and each is read as a duration after a number
    for u in units:
        assert align.duration_slots(f"Lasts 30 {u}.") == 1, u
    assert align.duration_slots("Lasts for 30 minutes.") == 0  # text the English wrote, not a `$d`


def test_a_literal_is_read_as_the_addon_reads_it():
    assert align.value_slots("Grants 16, 23 or 40 Stamina.") == 3
    assert align.value_slots("...16, 23...") == 2
    assert align.value_slots("Cooldown reduced by 0.15 sec and 1,200 health.") == 2
    assert align.value_slots("Rank Mk2 and 18sec") == 0  # glued to letters: not a value


def test_a_range_is_one_value_as_the_addon_reads_it():
    """Fireball's `$s1` prints `14 to 22`; `Align.values` joins "A to B" into one value, so a
    template that writes the range with two codes or two literals counts it once too."""
    assert align.value_slots("Causes $s1 to $s2 damage and $o2 over $d.") == 3
    assert align.value_slots("Increases Rage by 20 to 40.") == 1
    assert [s.duration for s in align.slots("Stuns for 5 to 10 sec.")] == [True]


def test_a_conditional_whose_branches_read_the_same_counts_as_one_branch():
    """Power Word: Shield, seen in game: a talent conditional whose branches differ only in their numbers
    prints the same values either way, so it is counted, and the checks that were blind to it now see it."""
    shield = ("Draws on the soul of the party member to shield them, absorbing "
              "$?a14748[${$s1*(1+$14748s1/100)}][$s1] damage.  Lasts $d.  Once shielded, the target cannot be "
              "shielded again for $6788d.")
    assert [(s.kind, s.duration) for s in align.slots(shield)] == [("sum", False), ("code", True), ("code", True)]
    assert align.duration_slots(shield) == 2
    # the in-game line: the duration is written as `$N2` with its unit, and neither `$D` is there
    assert align.slot_problems(shield, "$N2のダメージを吸収します。$N1秒間持続します。") == [
        "duration_as_value:N2", "duration_missing:D1", "duration_missing:D2",
    ]
    # a range in one branch against one value in the other: one value either way
    assert align.value_slots("Deals $?s18769[${$m1*2} to ${$M1*2}][$s1] Fire damage.") == 1
    # a sum's own digits and precision stay inside the one value
    stance = "Increases threat by $?a12792[${($7376s3+100)*($12792s1/100+1)-100)}.1%][$7376s3%]."
    assert [s.kind for s in align.slots(stance)] == ["sum"]
    # a number both branches write alike stays a literal; only the one that differs is a value
    assert [s.kind for s in align.slots("Heals $?a1[$s1 every 5 sec][$s2 every 5 sec].")] == ["code", "literal"]
    # identical word codes in both branches are the same words
    assert align.value_slots("Lasts $?a1[$s1 $lsec:secs;][$s2 $lsec:secs;].") == 1


def test_a_number_written_into_a_branch_is_a_value_the_client_fills():
    """`$?a415096[20%][30%]` is 20 for one player and 30 for another, so the Japanese may not write
    either: it is a code slot, not a literal."""
    s = align.slots("Each jump reduces the damage by $?a415096[20%][30%].  Affects $x1 total targets.")
    assert [x.kind for x in s] == ["code", "code"]
    assert align.slot_problems("Reduces by $?a1[20%][30%].", "20%減少します。") == ["slot_missing:N1"]


def test_branches_that_differ_in_words_stay_uncountable():
    """Only the numbers may differ. A clause one branch adds (Fire Ward), or wording that differs
    (Entangling Roots), has no Japanese that is right both ways."""
    for en in (
        "You may $?s17245[have up to ${$17245m1+1} $ltarget:targets;][only have 1 target] Rooted at a time.",
        "Increases damage by $s1% for $d$?s417046[, and instantly grants $417046s1 Energy][].",
        "Stuns for $?a1[$d][5 sec and slows].",
        "$?a1[$?a2[x][y]][z] $s1",  # nested: not read
        # only the numbers may differ, not the colour (Tiger's Fury: red = requirement
        # unmet), a word code, or line breaks; and a branch number glued to the text outside is part of a word
        "$?a768[|CFFFFFFFFRequires Cat Form|R][|CFFFF2020Requires Cat Form|R] $s1.",
        "Lasts $s1 $?a1[$lsecond:seconds;][$lminute:minutes;].",
        "Heals $?a1[$ghim:her;][$gher:him;] for $s1.",
        "Deals $s1 damage.$?a1[\r\n\r\n][ ]Lasts $d.",
        "Range $?a1[20][30]yd and $s1 damage.",
        "Rank$?a1[2][3] deals $s1 damage.",
    ):
        assert align.value_slots(en) is None, en


# A name-list tail. Languages (1293657) as the client's Spell table writes it.
_LANGUAGES = (
    "You are fluent in the following languages:"
    "$?s668[\r\n$@spellname668][]$?s669[\r\n$@spellname669][]$?s7340[\r\n$@spellname7340][]"
)


def test_a_trailing_spellname_chain_is_a_name_list_tail():
    head, tail = align.split_tail(_LANGUAGES)
    assert tail is True and head == "You are fluent in the following languages:"
    # the head is an ordinary template: counted (no number), so the row is drafted, not dropped
    assert align.value_slots(_LANGUAGES) == 0
    armor = "You are proficient in the use of $s1 armor types:$?s9078[\r\n$@spellname9078][]"
    assert align.split_tail(armor) == ("You are proficient in the use of $s1 armor types:", True)
    assert align.value_slots(armor) == 1


def test_a_multi_line_head_is_a_tail_too():
    """The addon cuts the live description at the line break after the head's own breaks, so a head of
    several lines matches against it: Apprentice Riding (33388) ends in the same chain after a three-line
    head and is a tail row like Languages."""
    riding = ("Allows you to ride basic ground mounts that require a riding skill of 75.\r\n\r\nKnown abilities:"
              "$?s33388[\r\n$@spellname33388][]")
    head = "Allows you to ride basic ground mounts that require a riding skill of 75.\r\n\r\nKnown abilities:"
    assert align.split_tail(riding) == (head, True)
    assert align.value_slots(riding) == 1
    assert align.tail_problems(riding, "乗れるようになります。\r\n\r\n習得済み：$T") == []


def test_only_a_trailing_chain_with_a_head_is_peeled():
    for en in (
        "$?s668[\r\n$@spellname668][]",  # no head: nothing to translate
        "Knows $?s668[\r\n$@spellname668][] and more.",  # not the trailing run
        "Fluent:$?s668[\r\n$@spelldesc668][]",  # an inclusion, not a name
        "Fluent:$?s668[\r\n$@spellname668][x]",  # a second branch prints something
    ):
        assert align.split_tail(en)[1] is False, en
        assert align.value_slots(en) is None, en
    # a line with no tail at all is untouched
    assert align.split_tail("Deals $s1 damage.") == ("Deals $s1 damage.", False)


def test_the_japanese_carries_the_tail_as_one_trailing_marker():
    ok = "次の言語に堪能です：$T"
    assert align.tail_problems(_LANGUAGES, ok) == []
    assert align.tail_problems(_LANGUAGES, "次の言語に堪能です：") == ["tail_missing"]
    assert align.tail_problems("Deals $s1 damage.", "$N1のダメージ。$T") == ["tail_unexpected"]
    assert align.tail_problems(_LANGUAGES, "$T次の言語に堪能です：") == ["tail_misplaced"]
    assert align.tail_problems(_LANGUAGES, "次の言語：$T$T") == ["tail_misplaced"]
    assert align.tail_problems(_LANGUAGES, "$T") == ["tail_empty"]  # no head translated at all
    # a chain element written out by the drafter (altered, dropped or added) is refused
    assert "tail_chain" in align.tail_problems(_LANGUAGES, "次の言語：$?s668[\r\n$@spellname668][]")
    assert "tail_chain" in align.tail_problems(_LANGUAGES, "次の言語：$@spellname668$T")


# A spell the character does not know: the client prints its own words where a duration belongs, leaves out
# the text of an ability the spell grants, and a few templates glue a value to a word. These are the twins of
# the addon's readers (Core/Align.lua); the shared vectors hold the two to the same answers.


def test_a_worded_duration_goes_only_into_a_slot_that_can_take_words():
    # "Lasts until canceled.": the slot is followed by words that read on
    thorns = "攻撃者に$N1のNatureダメージを与えます。$D1持続します。"
    assert align.worded_slots(thorns, {1}) == thorns
    # "over until canceled": the particle written for a number and its unit goes
    burn = "敵を焼いてArcaneダメージを与え、さらに$D1かけて追加のダメージを与えます。"
    assert align.worded_slots(burn, {1}) == "敵を焼いてArcaneダメージを与え、さらに$D1追加のダメージを与えます。"
    # "for until canceled … every 5.2 sec": only the worded slot is looked at
    whirl = "$D1の間、近くの敵すべてを攻撃し、$D2ごとに$N2の追加ダメージを与えます。"
    assert align.worded_slots(whirl, {1}) == whirl
    assert align.worded_slots(whirl, {2}) is None
    for closed in ("$D1ごとにArcaneダメージを受けています。", "$D1後に爆発します。", "$D1以内に唱えます。",
                   "詠唱時間を$D1短縮します。", "$D1"):
        assert align.worded_slots(closed, {1}) is None, closed
    assert [align.worded_context("$D1" + after, 3) for after in ("の間", "かけて", "ごとに")] == [
        "keep", "drop", "closed"]


def test_a_granted_ability_the_client_left_out_keeps_its_heading_and_icon():
    ja = "Wyvern Strikeのアビリティを得ます：\n\n$I1\n対象に$N1のダメージを与えます。"
    assert align.granted_head(ja, "Gain the Wyvern Strike ability:\r\n\r\n|T135125:24|t\r\n") == (
        "Wyvern Strikeのアビリティを得ます：\n\n$I1")
    rune = "胸部にBurnoutのルーンを刻みます：\n\n$I1\n呪文のクリティカル率が$N1%上昇します。"
    assert align.granted_head(rune, "Engrave your chest with the Burnout rune:\r\n\r\n|T236207:24|t\r\n") == (
        "胸部にBurnoutのルーンを刻みます：\n\n$I1")
    # the live line carries the ability's text, or has no icon, or two: the whole check
    assert align.granted_head(ja, "Gain the Wyvern Strike ability:\r\n\r\n|T135125:24|t\r\nDeals 40.") is None
    assert align.granted_head(ja, "Gain the Wyvern Strike ability:") is None
    assert align.granted_head(ja, "Gain the ability:\r\n\r\n|T1:24|t |T2:24|t") is None
    # the Japanese is not a heading, the icon and more text on its own line
    assert align.granted_head("Wyvern Strikeのアビリティを得ます：\n\n$I1", "Gain:\r\n\r\n|T1:24|t") is None
    assert align.granted_head("$I1 Quick Draw：$N1のダメージ。", "x |T1:24|t") is None
    # another icon before `$I1`: not one heading and one icon
    assert align.granted_head("$N1個を得ます：\n\n$I2\n本文。\n\n$I1\n本文。", "Gain 2:\r\n\r\n|T1:24|t") is None
    # a heading with no value slot has no count, as before
    assert align.granted_count(align.granted_head(ja, "Gain the Wyvern Strike ability:\r\n\r\n|T1:24|t") or "") is None


def test_a_granted_abilitys_heading_with_values_is_held_to_its_own_slots():
    # spells 401417 and 412510 as the client prints them for a character without Temporal Beacon
    temporal = ("$D1かけて体力を$N1回復し、$D2の間Temporal Beaconを付与します。\r\n\nTemporal Beacon\r\n$I1\r\n"
                "対象の時空間の位置を記録します。術者が与えたArcaneダメージの$N4%が変換されます。")
    live = ("Heals the target for 450 health over 12 sec and applies Temporal Beacon for 60 sec. \r\n\r\n"
            "Temporal Beacon\r\n|T237538:24|t\r\n")
    head = align.granted_head(temporal, live)
    assert head == "$D1かけて体力を$N1回復し、$D2の間Temporal Beaconを付与します。\r\n\nTemporal Beacon\r\n$I1"
    assert align.granted_count(head) == 3
    # 450, 12 and 60, the heading's three slots in its order (the addon reads the line with its icon taken out)
    assert align.live_values(live.split("|T")[0]) == ["450", "12", "60"]
    party = ("対象のプレイヤーから$N1ヤード以内にいる、そのプレイヤーのパーティーメンバー全員を$D1かけて体力を$N2回復し、"
             "それぞれに$D2の間Temporal Beaconを付与します。\r\n\nTemporal Beacon\r\n$I1\r\n本文の$N5%。")
    party_live = ("Heals all of target player's party members within 40 yards of target player for 300 health over"
                  " 12 sec and applies Temporal Beacon to each target for 30 sec.\r\n\r\nTemporal Beacon\r\n"
                  "|T237538:24|t")
    assert align.granted_count(align.granted_head(party, party_live) or "") == 4
    # a slot used twice is one value
    assert align.granted_count("$N1と$N1の$D1を得ます：\n\n$I1") == 2


def test_the_loose_reading_takes_a_glued_value_and_never_a_names_number():
    lines = {
        "Deal 294 Physical damage and stun for1.5 sec. Trolls take 2 times as much damage and stun duration.":
            (["294", "2"], ["294", "1.5", "2"]),
        "Unleash stored chronomantic energy to instantly heal a friendly target for 79to 118.":
            (["118"], ["79", "118"]),
        "Inflicts140 Nature damage per 2 sec. Deaks 2 times as much damage to Trolls.":
            (["2", "2"], ["140", "2", "2"]),
        "Blasts a target for 19 to 37 Nature damage. Mechanical targets take 2x damage.":
            (["19～37"], ["19～37", "2"]),
        "A malfunction has occurred. Every 2s arcane energy is released dealing damage to players in a nearby "
        "area.": ([], ["2"]),
        "Consuming a brand deals -24 to -21 Shadow damage.": (["24", "21"], ["-24～-21"]),
    }
    for text, (strict, loose) in lines.items():
        assert align.live_values(text) == strict, text
        assert align.live_values(text, loose=True) == loose, text
    # a name's number is no shape the loose reading takes
    for name in ("Mk2", "Mace2H", "247x128", "G00 DV-1B3", "AQ40", "x2", "30sec", "Field Repair Bot 74A"):
        text = f"Deals 5 damage with the {name}."
        assert align.live_values(text, loose=True) == align.live_values(text) == ["5"], name
    # and a line with nothing glued reads the same both ways
    plain = "Deals 1,200 damage over 18.5 sec. to 3 targets, then 14 to 22 more."
    assert align.live_values(plain, loose=True) == align.live_values(plain) == ["1200", "18.5", "3", "14～22"]
