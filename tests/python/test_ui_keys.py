"""The committed UI dictionary: one machine line per curated key, English at the pinned build,
and the name-policy guard."""

import json
from pathlib import Path

from wfj.core import specifiers
from wfj.io import wago
from wfj.io.jsonl_store import Store

BUILD = "1.15.9.69722"
# The dictionary's English comes from two clients. A key Forever provides is restamped
# db2@<forever build>; one Forever does not have keeps its Vanilla stamp (the union merge), and that stamp is
# what `wfj stats --unseen-since` reads to find what the newer client has never had. Both are pinned builds:
# the assertion is that no line carries an unpinned or unknown source, not that there is only ever one.
FOREVER_BUILD = "1.60.1.70170"
ENGLISH_SOURCES = {f"wago@{BUILD}", f"db2@{FOREVER_BUILD}"}
# UI words that are also the exact name of some item or spell (e.g. an item called "Cloth", the spell "Shield").
# They are allowed because the addon never walks the line that reads as the item / spell name and labels are matched
# per widget; any other exact-line collision is reviewed here. A new collision means a deliberate review: add it here.
KNOWN_NAME_COLLISIONS = {
    # Words from the families the served-text inventory added (ADR-052): recipe headers, pet diet words, the recent
    # allies' interaction words. Restricted family keys, matched only on their own widget (Core/UIStrings.lua).
    "Arrows", "Fireworks", "Fish", "Leggings",
    "Cloth", "Complete Quest", "Fire", "Fishing Pole", "Frost", "Leather", "Libram", "Mace", "Mail", "Shadow",
    "Shield", "Shirt", "Speed", "Sword", "Thrown", "Totem",
    "Learning",  # the group finder playstyle, shown only through its own key list (UI/GroupFinder.lua)
    # Stat / resistance labels, the pet command "Attack", the pet tab "Pet", "Reset", "Inactive",
    # "Send Mail". Every one shows on a named window label, a key-restricted widget (`only`) or a help tooltip, none
    # of which is ever an item or spell name line (help tooltips never walk item / spell tooltips; spell names are
    # never hooked in the spellbook).
    "Agility", "Arcane Resistance", "Armor", "Attack", "Fire Resistance", "Frost Resistance", "Inactive", "Intellect",
    "Nature Resistance", "Pet", "Reset", "Send Mail", "Shadow Resistance", "Spirit", "Stamina", "Strength",
    # Two from the Forever client's English, both window labels on a named widget like the entries above:
    # `DEFENSE_TOOLTIP` shows in the character sheet's stat tooltip and `TALENT_SPEC_ACTIVATE` on the talent frame's
    # button. Neither is ever walked as an item or spell name line, so names stay in English.
    "Activate", "Defense",
    # Camelot's stat pane rows, its "General" category header, the power-bar label and the
    # holy resistance hover. Each shows only on a key-restricted widget (UI/Character.lua's `only` lists), so it is
    # never walked as an item or spell name line.
    "Block", "Critical Strike", "Dodge", "Focus", "General", "Haste", "Health", "Holy Resistance", "Parry", "Rage",
    # The ClubFinder applicant menu's "Whisper" entry (MENU_CLUB_FINDER_APPLICANT,
    # clubfinderapplicantlist.lua:75). A menu entry is never an item or spell name line.
    # The talent reset button's menu title (MENU_CLASS_TALENT_FRAME_RESET,
    # blizzard_classtalentsframe.lua:81–84), also a spell's name. A menu entry, shown only through UI/Menus' `only`
    # list, is never an item or spell name line.
    "Reset Talents",
    # Words the Forever windows show that are also an item or spell name. Each renders on a named
    # widget, an `only`-restricted widget (the loss-of-control banner, the combat-text words, the settings rows) or a
    # help tooltip; the item / spell tooltip surface never touches a name line and help tooltips skip item and spell
    # tooltips, so no name is ever matched (names stay in English).
    "Black", "Breath", "Channel", "Common", "Confused", "Create", "Dazed", "Disarmed", "Disruption", "Distracted",
    "Enrage", "Evade", "Flash", "Frozen", "Hex", "Hide", "Interrupt", "Interrupted", "Languages", "Light", "Misfire",
    "Mission Complete", "Obliterate", "Opening", "Pacified", "Pandemic", "Pause", "Possessed", "Quest",
    "Resourcefulness", "Rooted", "Silenced", "Slow", "Summon", "Tracking", "Unknown", "Whisper", "White",
    # The unit menus' "Duel" / "Duel to the Death" (DUEL, DUEL_TO_DEATH) and the spellbook
    # subtext "Shapeshift" (SpellSubtext:768). Each is shown only on a key-restricted widget: a MENU_UNIT_* entry
    # (UI/Menus `only`, the unit's name title never matched) or a spellbook item's SubName (SUBTEXT_KEYS). Spell
    # names are never hooked, so the spells "Duel" and "Shapeshift" stay English.
    "Duel", "Duel to the Death", "Shapeshift",
    # Gamepad labels: the radial's emotes "Angry", "Chicken", "Dance" and the "More Actions"
    # entries "Bind", "Destroy", "Split", named in UI/Gamepad's KEYS / MENU_KEYS and shown only by the gamepad
    # writers, which are handed Blizzard's own globals, never an item or spell name
    "Angry", "Bind", "Chicken", "Dance", "Destroy", "Split",
    # ADR-042: client-table family rows whose English is also an item or spell name: the
    # profession-rank achievements ("Journeyman Engineer" is a spell), the Molten Core survivor titles, "Resurrection",
    # "Camping", "Languages", and the dispel words "Disease" / "Poison". Every family is restricted
    # (UIStrings.isRestrictedKey): found only where a widget names the family, never by the open match, so a name
    # elsewhere is never replaced. test_family_name_collisions_are_restricted_family_keys holds that.
    "Resurrection", "Survivor of the Firelord", "Survivor of the Shadow Flame", "Survivor of the Old God",
    "Survivor of the Damned", "Journeyman Alchemist", "Expert Alchemist", "Artisan Alchemist", "Journeyman Blacksmith",
    "Expert Blacksmith", "Artisan Blacksmith", "Journeyman Engineer", "Expert Engineer", "Artisan Engineer",
    "Disease", "Poison", "Camping",
    # Auction-house category words ("Staves", "Daggers" are also item names) and
    # barber-shop choices ("Void", "Thorns", "Swoop" are also spell names), restricted families like the above.
    "Aegis", "Aquamarine", "Blaze", "Bows", "Brimstone", "Charm", "Cleansed", "Club", "Crossbows", "Daggers",
    "Dynamite", "Eclipse", "Fist Weapons", "Flail", "Flame", "Flame Whirl", "Flames", "Flamethrower", "Flourish",
    "Gold Ring", "Guard", "Guardian", "Guns", "Hammer", "Insight", "Large Fin", "Noble", "One-Handed Axes",
    "One-Handed Maces", "One-Handed Swords", "Polearms", "Revenge", "Ritual", "Sacrifice", "Scorch", "Sear",
    "Shadowflame", "Smoke", "Smokey", "Spears", "Spiked Club", "Spikes", "Staves", "Suffering", "Swoop", "Thorns",
    "Two-Handed Axes", "Two-Handed Maces", "Two-Handed Swords", "Updraft", "Vigilant", "Vigor", "Void", "Wands",
    "War", "Widowmaker", "Wrath", "Zephyr",
    # The swimming tutorial's title (TUTORIAL_TITLE28), also a spell's name. It is an owned key
    # (UIStrings.OWN): out of the by-English index, so no unrestricted match ever answers it; only the popup's title
    # (UI/Tutorial.lua, `only` TUTORIAL_TITLE<n>) shows it
    "Swimming",
    # restricted client-table rows (LockType, SpellFlyout), matched only where a widget names their family: a lock
    # action or a spellbook flyout, never a spell or item name line
    "Beast Tracking", "Comprehend Scroll", "Disarm", "Disarm Trap", "Pick Lock", "Portal", "Stances", "Teleport", "Trap",
}


def _keys(root: Path) -> list[str]:
    return wago.read_keys(root / "pipeline/ui_keys.txt")


# The draft batches the dictionary is made of (each line's `provenance.source` names one).
DRAFT_SOURCES = {"draft-ui",
                 # the served-text round: every string the loaded Forever files name, in seven parts
                 *(f"draft-served-ui-{i}" for i in range(7)),
                 "draft-ui-compare", "draft-ui-appearance",  # the comparison tooltip and its appearance lines
                 "draft-ui-tracker", "draft-ui-wrap",  # the tracker's finished-quest lines; a popup's line break
                 "draft-ui-level1", "draft-ui-hud", "draft-ui-enchant", "draft-ui-beta-forever-bags",
                 "draft-ui-beta-forever-collisions",
                 "draft-ui-beta-duration-float",  # Forever prints SPELL_DURATION_* as %.1f, not %.2f
                 "draft-ui-retarget",  # the camelot surfaces' keys
                 "draft-ui-auras-remaining",  # the buff tooltip's time-remaining line
                 "draft-ui-windows",  # every other window the Forever client loads
                 "draft-ui-followups",  # the reworded Forever lines, menus, textures, Communities
                 "draft-ui-errors",  # the UI errors frame's ERR_* / SPELL_FAILED_* keys
                 "draft-ui-dialogs",  # the dialogs, owned words and window follow-ups
                 "draft-ui-menus",  # menus, HelpTip callouts and composite lines
                 "draft-ui-build70009",  # the keys new on 1.60.1.70009 and the lines it reworded
                 "draft-ui-tables",  # the client-table text families (ADR-042)
                 "draft-ui-tables2",  # barber shop, AH, PvP, group finder, widgets (ADR-042)
                 "draft-ui-meanings",  # a broken line the word-meanings pass found, re-translated
                 "draft-ui-leftovers",  # six labels rejected as not Japanese (PvP, 2v2, 3v3, Battle Tag, SSAO)
                 "draft-ui-tutorials",  # the tutorial popup and the tutorial pointer arrows
                 "draft-ui-review",  # lines the interface text review corrected against their windows
                 "draft-ui-review-role",  # the "role" lines brought to the settled term
                 "draft-repull70170-ui-sg12",  # the keys new on 1.60.1.70170 and the lines it reworded
                 # the last interface lines, the tooltip owner / socket / trade lines and the unit lines the
                 # tooltip line kinds surfaced
                 "draft-repull70170-lastui-sg12", "draft-repull70170-kinds-sg12", "draft-repull70170-unitlines-sg12",
                 "draft-ui-stat-changes"}  # the short stat names of the comparison's stat change lines


def test_every_key_has_one_machine_line_and_its_english(root):
    english = {ln["id"]: ln for ln in Store(root / "data", english=True).load("ui")}
    keys = wago.expand_keys(_keys(root), {k: ln["en"] for k, ln in english.items()})
    lines = {ln["id"]: ln for ln in Store(root / "data").load("ui")}
    assert set(keys) <= set(english) and set(keys) <= set(lines)
    # A key that left the list keeps its English when an earlier Forever build served it (ADR-050: the served
    # record); its machine Japanese stays in data/. Any other unlisted key lost its English (the served step,
    # ADR-034) and its line is `no_english_id`.
    record = root / "pipeline" / "served" / "ui.tsv"
    served = {r.split("\t")[0] for r in record.read_text(encoding="utf-8").splitlines()
              if r and not r.startswith("#")} if record.is_file() else set()
    assert set(english) - set(keys) <= served
    for key in set(lines) - set(keys):
        assert lines[key]["provenance"]["class"] == "machine", key
        if key not in english:
            assert lines[key]["status"] == "rejected" and "no_english_id" in lines[key]["reasons"], key
    batch_models: dict[str, str] = {}
    for key in keys:
        prov = lines[key]["provenance"]
        assert prov["class"] == "machine", key
        # one drafting model per batch: every line of a draft batch names the same model (one batch names the two
        # models its session used, joined by "+", because a line's author was not tracked; ADR-030 §8)
        assert prov["model"], key
        batch = prov["source"].split("@")[0]
        assert batch_models.setdefault(batch, prov["model"]) == prov["model"], (key, batch)
        # a critic is recorded only when a second model reviewed the draft
        assert prov.get("critic") is None or (prov["critic"] and prov["critic"] != prov["model"]), key
        assert prov["source"].split("@")[0] in DRAFT_SOURCES, key
        assert english[key]["src"] in ENGLISH_SOURCES, (key, english[key]["src"])
        # A key whose English the Forever client reworded keeps its Japanese and ships it behind the 要更新 marker
        # (ADR-003) until it is re-drafted: that is the queue, not a fault. The guarantee below still holds: only a `trusted` line is asserted to
        # match its English's specifiers, because a stale one is by definition checked against older English.
        assert lines[key]["status"] in ("trusted", "stale", "rejected"), key
        if lines[key]["status"] == "trusted":
            assert specifiers.mismatch(english[key]["en"], lines[key]["ja"]) is None, key


def test_no_listed_english_carries_links_key_markup_or_tokens(root):
    # Colour codes (|c … |r), plural grammar (|4), file textures (|T…|t), atlas textures (|A…|a) and named colours
    # (|cnNAME:) are matched (core/markup.py, Core/UIStrings.lua) and kept verbatim by the markup check. Links (other than the static ones below), key markup and $ tokens are
    # still never a key
    import re

    token_dollar = re.compile(r"(?<!%\d)\$")  # a $N / $B quest token, never the `$` of a `%1$s` positional
    # A link that never changes ( the client prints the same GlobalString every time) is matched as the
    # whole exact line and kept verbatim by the markup check. Only these keys: the speech-to-text and text-to-speech
    # settings' help links and the Recruit-a-Friend description.
    static_links = {"ONLINE_SAFETY_NOTICE", "RAF_NO_RECRUITS_DESC", "SPEECH_TO_TEXT_SUBTEXT", "TEXT_TO_SPEECH_MORE_VOICES"}
    for ln in Store(root / "data", english=True).load("ui"):
        for token in ("|H", "|K"):
            if token == "|H" and ln["id"] in static_links:
                continue
            assert token not in ln["en"], (ln["id"], token)
        # an NPC mail body keeps the client's $N / $B: the mail surface fills them the way the quest surface does
        if not ln["id"].startswith("MailBody:"):
            assert not token_dollar.search(ln["en"]), (ln["id"], "$")


def test_nit_terms_are_consistent(root):
    # one term for Focus, and damage templates put the label before the numbers
    lines = {ln["id"]: ln["ja"] for ln in Store(root / "data").load("ui")}
    focus = {k: v for k, v in lines.items() if k.startswith("FOCUS_COST")}
    assert focus and all("フォーカス" in v and "集中" not in v for v in focus.values()), focus
    for key in ("DAMAGE_TEMPLATE", "PLUS_DAMAGE_TEMPLATE", "SINGLE_DAMAGE_TEMPLATE"):
        assert lines[key].index("ダメージ") < lines[key].index("%"), (key, lines[key])
    for key in ("DAMAGE_TEMPLATE_WITH_SCHOOL", "PLUS_DAMAGE_TEMPLATE_WITH_SCHOOL", "SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL"):
        assert lines[key].index("ダメージ") < lines[key].index("%1$s"), (key, lines[key])  # the school may lead
    assert lines["INVTYPE_HOLDABLE"] != "オフハンド (小物)"


def test_ui_words_that_equal_a_name_are_the_reviewed_list(root):
    names = set()
    for type_ in ("item", "spell"):
        names |= {ln["en"] for ln in Store(root / "data", english=True).load(type_) if ln["field"] == "name"}
    # the dictionary's keys: the English store also keeps keys no longer listed (the import is additive), which
    # ship nothing and are never matched
    english = {ln["id"]: ln["en"] for ln in Store(root / "data", english=True).load("ui")}
    keys = set(wago.expand_keys(_keys(root), english))
    # the short stat names are asked for by key only, by the comparison's stat change lines
    # (Core/UIStrings isStatNameKey), so a name that equals one is never matched by them
    ui = {en for key, en in english.items() if key in keys and not (key.startswith("ITEM_MOD_") and key.endswith("_SHORT"))}
    assert ui & names == KNOWN_NAME_COLLISIONS


# The 38 name-collision words the Forever windows added are only shown through an explicit key list. Each key from
# that window batch with one of those English words is named in some UI module, literally or as a
# `"<PREFIX>" .. <suffix>` it is built from (the loss-of-control, loot quality and report category lists), so none
# depends on a whole-dictionary match that could meet an item or spell name.
WINDOW_COLLISIONS = {
    "Black", "Breath", "Channel", "Common", "Confused", "Create", "Dazed", "Disarmed", "Disruption", "Distracted",
    "Enrage", "Evade", "Flash", "Frozen", "Hex", "Hide", "Interrupt", "Interrupted", "Languages", "Light", "Misfire",
    "Mission Complete", "Obliterate", "Opening", "Pacified", "Pandemic", "Pause", "Possessed", "Quest",
    "Resourcefulness", "Rooted", "Silenced", "Slow", "Summon", "Tracking", "Unknown", "Whisper", "White",
}


def test_window_name_collision_keys_are_named_in_a_ui_module(root):
    import re

    assert WINDOW_COLLISIONS <= KNOWN_NAME_COLLISIONS
    source = "\n".join(p.read_text(encoding="utf-8") for p in (root / "addon/WoWForeverJapanese/UI").glob("*.lua"))
    # a key-building prefix: `"<PREFIX>" ..`, at least four characters (record-key prefixes such as "L" .. i are not)
    prefixes = {p for p in re.findall(r'"([A-Z][A-Z0-9_]*)"\s*\.\.', source) if len(p) >= 4}
    english = {ln["id"]: ln["en"] for ln in Store(root / "data", english=True).load("ui")}
    lines = {ln["id"]: ln for ln in Store(root / "data").load("ui")}
    # Reviewed exceptions: a whole-dictionary row walk that only ever shows Blizzard's own strings.
    #   COMBATLOG_FILTER_STRING_UNKNOWN_UNITS: the combat-log source check boxes, whose labels come from Blizzard's
    #   filter tables (`text = COMBATLOG_FILTER_STRING_UNKNOWN_UNITS`, blizzard_chatframe/mainline/
    #   chatconfigframe.lua:374, 426, 758), never a unit's or a spell's name.
    #   CHANNEL, OPENING: the chat configuration's message-type rows, whose labels are `_G[type]` for the types in
    #   Blizzard's own tables (blizzard_chatframe/mainline/chatconfigframe.lua:229, 281).
    #   WHISPER: the same rows, and a text-to-speech box: UI/TextToSpeech builds its `only` set at run time from the
    #   client's TEXT_TO_SPEECH_CHAT_TYPES (blizzard_chatframe/mainline/texttospeechframeconstants.lua:1).
    reviewed = {"COMBATLOG_FILTER_STRING_UNKNOWN_UNITS", "CHANNEL", "WHISPER", "OPENING"}
    unnamed = []
    for key, en in english.items():
        if key in reviewed:
            continue
        source_ = lines.get(key, {}).get("provenance", {}).get("source", "")
        if en not in WINDOW_COLLISIONS or not source_.startswith("draft-ui-windows@"):
            continue
        if f'"{key}"' in source or re.search(rf"\b{key}\s*=", source):
            continue
        if any(key.startswith(prefix) for prefix in prefixes):
            continue
        unnamed.append(key)
    assert unnamed == []


def test_key_list_is_the_curated_file(root):
    text = (root / "pipeline/ui_keys.txt").read_text(encoding="utf-8")
    assert "never a key whose English is a name" in text
    assert len(_keys(root)) == len(set(_keys(root)))
    assert json.dumps(_keys(root))  # plain strings


def test_family_name_collisions_are_restricted_family_keys(root):
    """ADR-042: every client-table family key whose English is also an item or spell name is a restricted
    family key (Core/UIStrings.lua RESTRICTED_PREFIXES), so the open match can never meet that name."""
    import re

    lua = (root / "addon/WoWForeverJapanese/Core/UIStrings.lua").read_text(encoding="utf-8")
    block = lua[lua.index("local RESTRICTED_PREFIXES"): lua.index("function UIStrings.isRestrictedKey")]
    restricted = set(re.findall(r'"\^(\w+):"', block))
    from wfj.core.model import RESTRICTED_FAMILIES

    assert restricted == set(RESTRICTED_FAMILIES)
    # every restricted family is a fingerprint family too (the addon's two lists kept in step)
    fp = lua[lua.index("local FINGERPRINT_PREFIXES"): lua.index("function UIStrings.isFingerprintKey")]
    assert restricted <= set(re.findall(r'"\^(\w+):"', fp))
    names = set()
    for type_ in ("item", "spell"):
        names |= {ln["en"] for ln in Store(root / "data", english=True).load(type_) if ln["field"] == "name"}
    for ln in Store(root / "data", english=True).load("ui"):
        family = ln["id"].split(":")[0]
        if ln["en"] in names and family in RESTRICTED_FAMILIES:
            assert family in restricted, ln["id"]
