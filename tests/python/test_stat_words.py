"""Stat words in tooltips read like the interface: `core/stat_words` finds the ones a line keeps in English
letters on their own and swaps them, and its Japanese is the UI dictionary's."""

from pathlib import Path

import pytest

from wfj.core import stat_words
from wfj.io.jsonl_store import Store

# the interface key that shows each stat word on the character sheet or an item's stat line
INTERFACE_KEYS = {
    "armor": "STAT_ARMOR", "health": "HEALTH", "mana": "MANA", "stamina": "SPELL_STAT3_NAME",
    "strength": "SPELL_STAT1_NAME", "agility": "SPELL_STAT2_NAME", "intellect": "SPELL_STAT4_NAME",
    "spirit": "SPELL_STAT5_NAME", "rage": "RAGE", "energy": "ENERGY",
}


def test_every_stat_word_is_the_interfaces_japanese(root: Path):
    ui = {ln["id"]: ln for ln in Store(root / "data").load("ui")}
    assert set(INTERFACE_KEYS) == set(stat_words.STAT_WORDS)
    for word, key in INTERFACE_KEYS.items():
        assert ui[key]["status"] == "trusted", key
        assert ui[key]["ja"] == stat_words.STAT_WORDS[word], (word, key)


@pytest.mark.parametrize(
    ("ja", "found", "settled"),
    [
        ("healthを$N1回復します。", ["health"], "体力を$N1回復します。"),
        ("Staminaが$N4上昇します。", ["stamina"], "スタミナが$N4上昇します。"),
        ("StaminaとSpiritが上昇します。", ["stamina", "spirit"], "スタミナと精神が上昇します。"),
        ("Stamina +$N1", ["stamina"], "スタミナ +$N1"),
        ("焼き尽くしたMana1ポイントごとに", ["mana"], "焼き尽くしたマナ1ポイントごとに"),
        ("spiritsが高まる", ["spirit"], "精神が高まる"),
        ("Mana Shieldを唱えます。", [], "Mana Shieldを唱えます。"),
        ("Elixir of Agilityを飲む", [], "Elixir of Agilityを飲む"),
        ("Spirit of Zandalarを得る", [], "Spirit of Zandalarを得る"),
        ("Sunder ArmorのRageコスト", ["rage"], "Sunder Armorの怒りコスト"),
        ("Mana-infusedな結晶", [], "Mana-infusedな結晶"),
        ("Healthstoneを作る", [], "Healthstoneを作る"),
        ("Enrageで", [], "Enrageで"),
    ],
)
def test_find_and_settle(ja, found, settled):
    assert stat_words.find(ja) == found
    assert stat_words.settle(ja) == settled


def test_not_spellings():
    assert stat_words.not_spellings("最大ヘルスが増加") == ["ヘルス"]
    assert stat_words.not_spellings("最大体力が増加") == []


@pytest.mark.parametrize(
    ("ja", "found"),
    [
        ("|TInterface\\Icons\\Spell_Holy_Mana:0|tを回復", []),  # a texture path is no word
        ("|cffffffffStamina|rが上昇", ["stamina"]),  # a colour code is glued to the word it colours
        ("Mana\nShieldを唱える", []),  # a name wrapped onto the next line
        ("真夏の精神(spirit  of Midsummer)", []),  # a name with a double space
        ("精神(spirit \nof Midsummer)", []),  # a space and a line break
        ("Energiesが回復", ["energy"]),
        ("Mana'sコスト", ["mana"]),
    ],
)
def test_escapes_plurals_and_wrapped_names(ja, found):
    assert stat_words.find(ja) == found


@pytest.mark.parametrize(
    ("en", "names", "free"),
    [
        ("Increases Stamina by $s1.", ["Stamina"], {"stamina"}),
        ("Restores $o1 health over $d.", [], {"health"}),
        ("Drink an Elixir of Agility.", ["Elixir", "Agility"], set()),
        ("Calls the Rage of the Suzerain.", ["Rage", "Suzerain"], set()),
        ("Absorbs damage. Mana Shield lasts $d.", ["Mana", "Shield"], set()),
        ("Casts Arcane Intellect on the target.", ["Arcane", "Intellect"], set()),
        ("Strength Increased by $s1.", ["Increased"], set()),
        ("Enchant bracers to increase the Stamina of the wearer by $s1.", ["Stamina"], {"stamina"}),
        ("Increases the amount of Mana awarded by your Life Tap spell.", ["Mana", "Life", "Tap"], {"mana"}),
        ("Lay out a feast that contains Stamina-boosting food.", ["Stamina-boosting"], {"stamina"}),
    ],
)
def test_free_in_english(en, names, free):
    assert stat_words.free_in_english(en, names) == free


def test_settle_spellings():
    assert stat_words.settle_spellings("最大ヘルスが増加") == "最大体力が増加"
    assert stat_words.settle_spellings("ヘルス、アーマー") == "体力、アーマー"
    assert stat_words.settle_spellings("知性が$N1上昇") == "知力が$N1上昇"
    assert stat_words.settle_spellings("気力を回復") == "エネルギーを回復"


def test_a_katakana_spelling_inside_a_longer_word_is_not_read():
    assert stat_words.not_spellings("ヘルスストーンを作る") == []
    assert stat_words.settle_spellings("ヘルスストーンを作る") == "ヘルスストーンを作る"
    assert stat_words.not_spellings("最大ヘルスが増加。ヘルス") == ["ヘルス"]


@pytest.mark.parametrize(
    ("en", "names", "free", "named"),
    [
        ("Restores $s1 Mana. Your Mana Shield absorbs $s2.", ["Mana", "Shield"], {"mana"}, {"mana"}),
        ("Absorbs damage while Mana\nShield lasts.", ["Mana", "Shield"], set(), {"mana"}),
        ("Absorbs damage while Mana  Shield lasts.", ["Mana", "Shield"], set(), {"mana"}),
        ("Drink an Elixir of Agility.", ["Elixir", "Agility"], set(), {"agility"}),
    ],
)
def test_classify_judges_each_occurrence(en, names, free, named):
    assert stat_words.classify(en, names) == (free, named)
