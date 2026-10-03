"""wago.tools DB2 CSV exports → (id, english name) pairs.

Export URL: https://wago.tools/db2/<Table>/csv?build=<version>&locale=enUS
ItemSparse: columns `ID`, `Display_lang`. SpellName: columns `ID`, `Name_lang`.
GlobalStrings: `BaseTag`, `TagText_lang`. ItemSubClass: `ClassID`, `SubClassID`, `DisplayName_lang` (verified
on 1.15.9.69722): the UI string sources. SpellItemEnchantment: `ID`, `Name_lang`
(verified on 1.15.9.69722): an enchantment's display text, the stat line a random-suffix
or enchanted item prints ("+3 Fire Spell Damage").
GlobalStrings writes a line break as the two characters `\n`; the client's string holds a real newline, so the
reader turns `\n` into one (the English hash must be the hash of what the client holds).
"""

from __future__ import annotations

import csv
import re
from collections.abc import Iterator
from pathlib import Path

DEFAULT_COLUMNS = {"item": ("ID", "Display_lang"), "spell": ("ID", "Name_lang")}


def read_names(path: Path, id_col: str, name_col: str) -> Iterator[tuple[int, str]]:
    with path.open(encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None or id_col not in reader.fieldnames or name_col not in reader.fieldnames:
            raise ValueError(
                f"{path.name}: need columns {id_col!r} and {name_col!r}, have {reader.fieldnames}"
            )
        for row in reader:
            name = (row[name_col] or "").strip()
            if not name:
                continue
            yield int(row[id_col]), name


def read_ids(path: Path) -> set[int]:
    """QuestV2 (`ID`, `UniqueBitFlag`; verified on 1.15.9.69722): the quest ids the client build
    knows, the scan plan and the coverage denominator. Empty table is an error."""
    ids: set[int] = set()
    with path.open(encoding="utf-8", newline="") as f:
        for n, row in enumerate(_reader(f, path, ("ID",)), 2):
            try:
                ids.add(int(row["ID"]))
            except ValueError:
                raise ValueError(f"{path.name}:{n}: ID {row['ID']!r} is not an integer") from None
    if not ids:
        raise ValueError(f"{path.name}: no ids")
    return ids


def _reader(f, path: Path, need: tuple[str, ...]) -> csv.DictReader:
    reader = csv.DictReader(f)
    missing = [c for c in need if reader.fieldnames is None or c not in reader.fieldnames]
    if missing:
        raise ValueError(f"{path.name}: need columns {list(need)}, have {reader.fieldnames}")
    return reader


_ESCAPE = re.compile(r"\\(\d{1,3}|[\\n\"r])")
_CONTROL = {"n": "\n", "r": "\r"}


def _unescape(text: str) -> str:
    """The table writes GlobalStrings Lua-escaped: `\\n` is a line break and `\\\\` one backslash; a
    texture path `|TInterface\\\\GroupFrame\\\\…|t` is `Interface\\GroupFrame\\…` in the client's `_G`.
    One pass, so an escaped backslash before an `n` is never read as a break; `\\"` is a quote. Lua's
    `\\r` and decimal escapes too: the chat header "Say:\\32" is "Say: " in `_G` (CHAT_*_SEND)."""
    def one(m: re.Match[str]) -> str:
        e = m.group(1)
        if e.isdigit():  # Lua's decimal escape is one byte; \256 and up are not escapes at all
            return chr(int(e)) if int(e) <= 255 else "\\" + e
        return _CONTROL.get(e, e)

    return _ESCAPE.sub(one, text)


def read_global_strings(path: Path) -> dict[str, str]:
    """GlobalStrings: {BaseTag: enUS text}. A tag listed twice with different text is a data error."""
    out: dict[str, str] = {}
    with path.open(encoding="utf-8", newline="") as f:
        for row in _reader(f, path, ("BaseTag", "TagText_lang")):
            tag, text = row["BaseTag"], _unescape(row["TagText_lang"] or "")
            if tag in out and out[tag] != text:
                raise ValueError(f"{path.name}: {tag} listed twice with different text")
            out[tag] = text
    return out


def read_item_subclasses(path: Path) -> dict[str, str]:
    """ItemSubClass: {"ItemSubClass:<ClassID>:<SubClassID>": DisplayName_lang}, the `ui` type's key."""
    out: dict[str, str] = {}
    with path.open(encoding="utf-8", newline="") as f:
        for row in _reader(f, path, ("ClassID", "SubClassID", "DisplayName_lang")):
            key = f"ItemSubClass:{int(row['ClassID'])}:{int(row['SubClassID'])}"
            text = row["DisplayName_lang"] or ""
            if key in out and out[key] != text:  # duplicates are reported, never resolved silently
                raise ValueError(f"{path.name}: {key} listed twice with different text")
            out[key] = text
    return out


# A stat line: a signed amount, then words ("+3 Fire Spell Damage", "+1 to all attributes"). Enchantment
# names such as "Crusader" or "Rockbiter 3" are names and never match (names stay in English).
ENCHANT_STAT_LINE = re.compile(r"[+-]\d+ [A-Za-z][A-Za-z' ]*")


def read_enchantments(path: Path) -> dict[str, str]:
    """SpellItemEnchantment: {"SpellItemEnchantment:<ID>": Name_lang} for the rows whose display text is a
    stat line (ENCHANT_STAT_LINE). Every other row is a name or a composite and is not a UI string."""
    out: dict[str, str] = {}
    with path.open(encoding="utf-8", newline="") as f:
        for row in _reader(f, path, ("ID", "Name_lang")):
            text = (row["Name_lang"] or "").strip()
            if ENCHANT_STAT_LINE.fullmatch(text):
                out[f"SpellItemEnchantment:{int(row['ID'])}"] = text
    return out


def read_subtexts(path: Path) -> dict[str, str]:
    """Spell `NameSubtext_lang`: {"SpellSubtext:<ID>": subtext} for every spell with one
    ("Racial", "Rank 1", "Cat"). Which of them are words is the curated key list's decision: a pet family
    or a form name is a name and is never listed (names stay in English)."""
    out: dict[str, str] = {}
    with path.open(encoding="utf-8", newline="") as f:
        for row in _reader(f, path, ("ID", "NameSubtext_lang")):
            text = (row["NameSubtext_lang"] or "").strip()
            if text:
                out[f"SpellSubtext:{int(row['ID'])}"] = text
    return out


# Client-table text families (ADR-042). Family prefix → (table CSV stem, text column). The key is
# `<prefix>:<ID>`; the addon matches the live line by its fingerprint (the English hash), except `EmoteText`,
# whose `%s` slots the chat surface fills (a template fingerprint). Names are never a family: faction, skill,
# holiday, currency and battleground names stay English.
TEXT_FAMILIES: dict[str, tuple[str, str]] = {
    "FactionDescription": ("Faction", "Description_lang"),
    "AchievementTitle": ("Achievement", "Title_lang"),
    "AchievementDescription": ("Achievement", "Description_lang"),
    "AchievementReward": ("Achievement", "Reward_lang"),
    "AchievementCategory": ("Achievement_Category", "Name_lang"),
    "SkillLineDescription": ("SkillLine", "Description_lang"),
    "SkillCategory": ("SkillLineCategory", "Name_lang"),
    "EmoteText": ("EmotesTextData", "Text_lang"),
    "HolidayDescription": ("HolidayDescriptions", "Description_lang"),
    "CurrencyDescription": ("CurrencyTypes", "Description_lang"),
    "CurrencyCategory": ("CurrencyCategory", "Name_lang"),
    "DispelType": ("SpellDispelType", "Name_lang"),
    "CreatureType": ("CreatureType", "Name_lang"),
    "QuestSort": ("QuestSort", "SortName_lang"),
    # character customization, PvP scoreboard, group finder, widget and item-name text
    "CustomizationCategory": ("ChrCustomizationCategory", "CategoryName_lang"),
    "CustomizationOption": ("ChrCustomizationOption", "Name_lang"),
    "CustomizationChoice": ("ChrCustomizationChoice", "Name_lang"),
    "CustomizationSource": ("ChrCustomizationReq", "ReqSource_lang"),
    "PvpColumn": ("PVPScoreboardColumnHeader", "Name_lang"),
    "PvpColumnTooltip": ("PVPScoreboardColumnHeader", "Tooltip_lang"),
    "LfgCategory": ("GroupFinderCategory", "Name_lang"),
    "LfgActivityGroup": ("GroupFinderActivityGrp", "Name_lang"),
    "LfgActivity": ("GroupFinderActivity", "FullName_lang"),
    "WidgetText": ("UiWidgetStringSource", "Value_lang"),
    "ItemNameDescription": ("ItemNameDescription", "Description_lang"),
    # the families the served-text inventory found shown on Forever (ADR-052)
    "CriteriaText": ("CriteriaTree", "Description_lang"),
    "RenownRewardName": ("RenownRewards", "Name_lang"),
    "RenownRewardDescription": ("RenownRewards", "Description_lang"),
    "RenownRewardToast": ("RenownRewards", "ToastDescription_lang"),
    "SharedString": ("SharedString", "String_lang"),
    "TradeSkillCategory": ("TradeSkillCategory", "Name_lang"),
    "MailBody": ("MailTemplate", "Body_lang"),
    "QuestTag": ("QuestInfo", "InfoName_lang"),
    "AreaPoiDescription": ("AreaPOI", "Description_lang"),
    "AreaPoiState": ("AreaPOIState", "Description_lang"),
    "PetLoyalty": ("PetLoyalty", "Name_lang"),
    "PvpLongDescription": ("Map", "PvpLongDescription_lang"),
    "Difficulty": ("Difficulty", "Name_lang"),
    "EventToastText": ("UiEventToast", "SubIcon_lang"),
    "BroadcastText": ("BroadcastText", "Text_lang"),
    "PetFood": ("ItemPetFood", "Name_lang"),
    "RestState": ("Exhaustion", "Name_lang"),
    "ItemSubClassMask": ("ItemSubClassMask", "Name_lang"),
    "RecentAllyType": ("RolodexType", "Description_lang"),
    "RecentAllyInteraction": ("RolodexType", "Field_11_2_5_62687_001_lang"),
    "FriendshipLabel": ("FriendshipReputation", "Description_lang"),
    "FriendshipGain": ("FriendshipReputation", "StandingModified_lang"),
    "InstanceEntryMessage": ("MapDifficulty", "Message_lang"),
    "InstanceEntryFailure": ("MapDifficultyXCondition", "FailureDescription_lang"),
    "PlayerConditionFailure": ("PlayerCondition", "Failure_description_lang"),
    "LockTypeName": ("LockType", "Name_lang"),
    "LockTypeResource": ("LockType", "ResourceName_lang"),
    "LockTypeVerb": ("LockType", "Verb_lang"),
    "FlyoutName": ("SpellFlyout", "Name_lang"),
    "FlyoutDescription": ("SpellFlyout", "Description_lang"),
    "ServerMessage": ("ServerMessages", "Text_lang"),
    "TransmogSituation": ("TransmogSituation", "Name_lang"),
    "TransmogTrigger": ("TransmogSituationTrigger", "Name_lang"),
    "TransmogTriggerDescription": ("TransmogSituationTrigger", "Description_lang"),
    "TransmogSlotOption": ("TransmogOutfitSlotOption", "Name_lang"),
}
FAMILY_TABLES = tuple(dict.fromkeys(t for t, _ in TEXT_FAMILIES.values()))

# Developer text no player is shown: a family row whose English matches is never read. The curated
# key list decides the rest (a name row is simply not listed).
INTERNAL_TEXT = re.compile(
    r"\[(?:DNT|PH)\]|\bDNT\b|\bREUSE\b|\(hidden\)|\bDo Not Display\b|OBSOLETE|^NewItem$"
    r"|^(?:OLD|Unused|Hidden|x)$",
    re.IGNORECASE,
)


def read_family(path: Path, prefix: str) -> dict[str, str]:
    """One text family from its table's CSV: {"<prefix>:<ID>": text} for every row whose text is non-empty
    and not developer text (INTERNAL_TEXT). The CSV writes a line break as `\\n` (the client's string holds
    one)."""
    _, column = TEXT_FAMILIES[prefix]
    out: dict[str, str] = {}
    with path.open(encoding="utf-8", newline="") as f:
        for row in _reader(f, path, ("ID", column)):
            text = (row[column] or "").replace("\\n", "\n").strip()
            if text and not INTERNAL_TEXT.search(text):
                out[f"{prefix}:{int(row['ID'])}"] = text
    return out


def read_item_subclass_names(path: Path) -> dict[str, str]:
    """ItemSubClass `VerboseName_lang`: {"ItemSubClassName:<ClassID>:<SubClassID>": long name} for
    every subclass ("Staves", "One-Handed Axes"; the short name where it has no long one): what
    GetItemSubClassInfo returns, the auction house's category words. (`ItemSubClass:<c>:<s>` is the short
    DisplayName the item tooltip shows.)"""
    out: dict[str, str] = {}
    with path.open(encoding="utf-8", newline="") as f:
        for row in _reader(f, path, ("ClassID", "SubClassID", "DisplayName_lang", "VerboseName_lang")):
            # a subclass with no long name is named by its short one (`Potions`, `Arrow`) [unverified in game]
            text = (row["VerboseName_lang"] or row["DisplayName_lang"] or "").strip()
            if text and not INTERNAL_TEXT.search(text):
                out[f"ItemSubClassName:{int(row['ClassID'])}:{int(row['SubClassID'])}"] = text
    return out


def read_families(folder: Path) -> dict[str, str]:
    """Every family of TEXT_FAMILIES from the table CSVs in a client folder (and the item subclasses'
    long names from its ItemSubClass.csv); a missing CSV raises."""
    out: dict[str, str] = {}
    for prefix, (table, _) in TEXT_FAMILIES.items():
        path = folder / f"{table}.csv"
        if not path.is_file():
            raise ValueError(f"{path}: missing (make tables-extract)")
        out.update(read_family(path, prefix))
    subclasses = folder / "ItemSubClass.csv"
    if not subclasses.is_file():
        raise ValueError(f"{subclasses}: missing (make tables-extract)")
    out.update(read_item_subclass_names(subclasses))
    return out


def expand_keys(keys: list[str], table: dict[str, str]) -> list[str]:
    """A key list entry ending in `:*` (`ItemSubClass:1:*`, `SpellItemEnchantment:*`) stands for every key
    of the table with that prefix, in sorted id order; every other entry is itself."""
    out: list[str] = []
    for key in keys:
        if key.endswith(":*"):
            prefix = key[:-1]

            def order(k: str, n: int = len(prefix)) -> tuple[int, ...]:
                return tuple(int(x) for x in k[n:].split(":"))

            family = sorted((k for k in table if k.startswith(prefix)), key=order)
            if not family:
                raise ValueError(f"{key}: no key with that prefix")
            out.extend(family)
        else:
            out.append(key)
    return out


def read_keys(path: Path) -> list[str]:
    """The curated UI key list: one key per line; `#` starts a comment; blank lines ignored; a duplicate
    raises."""
    keys: list[str] = []
    seen: set[str] = set()
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        key = raw.split("#", 1)[0].strip()
        if not key:
            continue
        if key in seen:  # a `:*` family entry is one line; its expansion is checked by expand_keys' caller
            raise ValueError(f"{path.name}:{n}: {key} listed twice")
        seen.add(key)
        keys.append(key)
    return keys


def _text(row: dict[str, str], col: str) -> str:
    """A CSV text cell as the client holds it: `\\n` written as two characters is a line break."""
    return (row[col] or "").replace("\\n", "\n")


def read_spell_texts(path: Path) -> dict[int, tuple[str, str]]:
    """Spell (`ID`, `Description_lang`, `AuraDescription_lang`, verified on 1.15.9.69722):
    {spell id: (tooltip text, buff / debuff text)}, raw templates (`$s1`, `$d`), empty strings kept."""
    out: dict[int, tuple[str, str]] = {}
    with path.open(encoding="utf-8", newline="") as f:
        for row in _reader(f, path, ("ID", "Description_lang", "AuraDescription_lang")):
            sid = int(row["ID"])
            if sid in out:  # a duplicate is reported, never last-wins
                raise ValueError(f"{path.name}: spell {sid} listed twice")
            out[sid] = (_text(row, "Description_lang"), _text(row, "AuraDescription_lang"))
    if not out:  # a cut-short table would silently shrink every tooltip baseline
        raise ValueError(f"{path.name}: no rows")
    return out


def read_item_descriptions(path: Path) -> dict[int, str]:
    """ItemSparse `Description_lang`: {item id: flavour text} for every item in the table ("" when it
    has none); the keys are the items the table knows."""
    out: dict[int, str] = {}
    with path.open(encoding="utf-8", newline="") as f:
        for row in _reader(f, path, ("ID", "Description_lang")):
            iid = int(row["ID"])
            if iid in out:  # a duplicate is reported, never last-wins
                raise ValueError(f"{path.name}: item {iid} listed twice")
            out[iid] = _text(row, "Description_lang")
    if not out:
        raise ValueError(f"{path.name}: no rows")
    return out


def read_item_effect_items(path: Path) -> dict[int, int]:
    """ItemXItemEffect: effect id → item id. Forever's item→effect join, which lives in its own
    table there: `ItemEffect` carries no relationship map on that build (every section reports
    relationship_data_size 0), so its `ParentItemID` is written 0 and this table is the only way to know
    which item an effect belongs to. Classic Era ships no such table and does the join inline."""
    out: dict[int, int] = {}
    with path.open(encoding="utf-8", newline="") as f:
        for row in _reader(f, path, ("ID", "ItemEffectID", "ItemID")):
            effect, item = int(row["ItemEffectID"]), int(row["ItemID"])
            if effect <= 0 or item <= 0:
                continue
            if out.get(effect, item) != item:  # a duplicate is reported, never last-wins
                raise ValueError(
                    f"{path.name}: effect {effect} is claimed by items {out[effect]} and {item}"
                )
            out[effect] = item
    if not out:
        raise ValueError(f"{path.name}: no item-effect links")
    return out


def read_item_effects(
    path: Path, items: dict[int, int] | None = None
) -> list[tuple[int, int, int, int, int]]:
    """ItemEffect (`ID`, `ParentItemID`, `LegacySlotIndex`, `SpellID`, `TriggerType`, verified on
    1.15.9.69722): (item id, slot, effect id, spell id, trigger type) for every effect
    with an item and a spell, sorted by (item, slot, effect id), the stated order when an item has two
    effects in one slot (item 229966 does).

    `items`: effect id → item id from `ItemXItemEffect`, for a build where `ItemEffect` carries no
    relationship map and its own `ParentItemID` is therefore 0 on every row. When given it is the authority
    for which item an effect belongs to; omitted, the column is used as before."""
    out = []
    with path.open(encoding="utf-8", newline="") as f:
        for row in _reader(f, path, ("ID", "ParentItemID", "LegacySlotIndex", "SpellID", "TriggerType")):
            effect, spell = int(row["ID"]), int(row["SpellID"])
            item = items.get(effect, 0) if items is not None else int(row["ParentItemID"])
            if item <= 0 or spell <= 0:
                continue
            out.append((item, int(row["LegacySlotIndex"]), effect, spell, int(row["TriggerType"])))
    if not out:
        raise ValueError(f"{path.name}: no item effects")
    return sorted(out)
