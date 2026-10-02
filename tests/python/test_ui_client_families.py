"""The client-table text families (ADR-042): the tables' column maps, the family reader and its filter, the
wago-ui import from a client folder and the curated key block."""

import re
import shutil
from pathlib import Path

import pytest

from wfj.cmd import check, import_english, served
from wfj.cmd import import_ as imp
from wfj.core.model import UI_FAMILIES, validate_line
from wfj.io import client_tables, wago
from wfj.io.jsonl_store import Store

BUILD = "1.60.1.70170"
TEXT_TABLES = (
    "Faction", "Achievement", "Achievement_Category", "SkillLineCategory", "SkillLine", "EmotesTextData",
    "HolidayDescriptions", "CurrencyTypes", "CurrencyCategory", "SpellDispelType", "CreatureType", "QuestSort",
    # the second set of family tables
    "ChrCustomizationCategory", "ChrCustomizationOption", "ChrCustomizationChoice", "ChrCustomizationReq",
    "PVPScoreboardColumnHeader", "GroupFinderCategory", "GroupFinderActivityGrp", "GroupFinderActivity",
    "UiWidgetStringSource", "ItemNameDescription",
    # the tables the served-text inventory found shown on Forever (ADR-051)
    "CriteriaTree", "RenownRewards", "SharedString", "TradeSkillCategory", "MailTemplate", "QuestInfo", "AreaPOI",
    "AreaPOIState", "PetLoyalty", "Map", "Difficulty", "UiEventToast", "BroadcastText", "ItemPetFood", "Exhaustion",
    "ItemSubClassMask", "RolodexType", "FriendshipReputation", "MapDifficulty", "MapDifficultyXCondition",
)


def _en(id_, text):
    return {"id": id_, "field": "text", "en": text, "hash": "0" * 16, "src": f"db2@{BUILD}"}


def test_the_family_tables_are_pinned_text_only_with_evidence():
    assert set(wago.FAMILY_TABLES) == set(TEXT_TABLES)
    for name in TEXT_TABLES:
        t = client_tables.TABLES[name]
        assert t.text_only, name  # a hotfix is read as leading strings: no number column
        assert all(c.source == client_tables.ID or c.text for c in t.columns), name
        for layout in t.layouts:  # every other build's map says what verified it
            assert re.search(r"\d+\.\d+\.\d+\.\d+", layout.verified) and "PENDING" not in layout.verified, name


def test_the_text_columns_are_the_verified_fields():
    cols = {name: {c.name: c.source for c in client_tables.TABLES[name].columns if c.text} for name in TEXT_TABLES}
    assert cols["Faction"] == {"Description_lang": 1}  # Name_lang (0) is a name: declared unwritten
    assert 0 in client_tables.TABLES["Faction"].unwritten_strings
    assert cols["Achievement"] == {"Description_lang": 0, "Title_lang": 1, "Reward_lang": 2}
    assert cols["SkillLine"] == {"Description_lang": 2}
    assert cols["CurrencyTypes"] == {"Description_lang": 1}
    assert cols["EmotesTextData"] == {"Text_lang": 0}


def test_the_model_repeats_the_family_names_of_the_reader():
    assert tuple(wago.TEXT_FAMILIES) == UI_FAMILIES


def test_the_makefile_lists_the_same_tables(root):
    mk = (root / "Makefile").read_text("utf-8")
    listed = re.search(r"^FAMILY_TABLES\s*:=\s*(.*)$", mk, re.M).group(1).split()
    assert listed == list(wago.FAMILY_TABLES)
    assert re.search(r"^FAMILY_CLIENTS\s*:=\s*forever\s*$", mk, re.M)


def test_served_checks_the_family_tables_stamps():
    assert set(wago.FAMILY_TABLES) <= set(served.UI_TABLES)


@pytest.mark.parametrize("key", ["FactionDescription:69", "EmoteText:1", "CreatureType:7", "SkillCategory:11",
                                 "AchievementTitle:62353"])
def test_family_keys_validate(key):
    assert validate_line("ui", _en(key, "x"), english=True) == []


@pytest.mark.parametrize("key", ["FactionDescription:", "Faction:69", "EmoteText:x", "CreatureType:1:2",
                                 "creaturetype:7", "Emote:1"])
def test_other_forms_are_refused(key):
    assert validate_line("ui", _en(key, "x"), english=True)


def _csv(path: Path, header: str, rows: list[str]) -> Path:
    path.write_text(header + "\n" + "\n".join(rows) + "\n", encoding="utf-8")
    return path


def test_read_family_keeps_player_text_and_drops_developer_rows(tmp_path):
    p = _csv(tmp_path / "Faction.csv", "ID,Description_lang", [
        '69,"The Alliance capital is populated by Night Elves.  Ruled by Tyrande."',
        "2721,[DNT] Used for Naxxramas NPCs",
        "5,",
        "6,OLD",
        '7,"Two lines\\nhere"',
    ])
    assert wago.read_family(p, "FactionDescription") == {
        "FactionDescription:69": "The Alliance capital is populated by Night Elves.  Ruled by Tyrande.",
        "FactionDescription:7": "Two lines\nhere",
    }
    q = _csv(tmp_path / "Achievement.csv", "ID,Description_lang,Title_lang,Reward_lang",
             ["1,Do it.,Hidden: Rank 3 (hidden),", "2,Win.,Duels won,"])
    assert wago.read_family(q, "AchievementTitle") == {"AchievementTitle:2": "Duels won"}
    assert wago.read_family(q, "AchievementDescription") == {"AchievementDescription:1": "Do it.",
                                                            "AchievementDescription:2": "Win."}


def test_read_families_needs_every_table(tmp_path):
    with pytest.raises(ValueError, match="missing"):
        wago.read_families(tmp_path)


@pytest.fixture
def data(root, tmp_path, monkeypatch):
    d = tmp_path / "data"
    d.mkdir()
    (d / "SCHEMA").write_text("1\n")
    (tmp_path / "pipeline").mkdir()
    (tmp_path / "pipeline" / "allowlist.txt").write_text((root / "pipeline/allowlist.txt").read_text("utf-8"))
    for mod in (import_english, check):
        monkeypatch.setattr(mod, "data_root", lambda start=None: d)
    return d


def _family_folder(root: Path, tmp_path: Path) -> Path:
    tables = tmp_path / "tables"
    shutil.copytree(root / "tests/fixtures/wago", tables)
    stamps = ["# <table> <src>@<build>"]
    for name in ("GlobalStrings", "SpellItemEnchantment", "SpellName", "ItemSparse"):
        stamps.append(f"{name} db2@{BUILD}")
    for table in {t for t, _ in wago.TEXT_FAMILIES.values()}:
        header = "ID," + ",".join(sorted({c for t, c in wago.TEXT_FAMILIES.values() if t == table}))
        _csv(tables / f"{table}.csv", header, [])
        stamps.append(f"{table} db2@{BUILD}")
    _csv(tables / "Faction.csv", "ID,Description_lang", ['69,"The Alliance capital is populated by Night Elves."',
                                                         "2721,Used for Naxxramas NPCs"])
    _csv(tables / "EmotesTextData.csv", "ID,Text_lang", ["2,%s waves at you."])
    _csv(tables / "CreatureType.csv", "ID,Name_lang", ["7,Humanoid"])
    # the item subclasses' names (ItemSubClassName): the long one, else the short one
    _csv(tables / "ItemSubClass.csv", "DisplayName_lang,VerboseName_lang,ClassID,SubClassID",
         ["Staff,Staves,2,10", "Potions,,0,1", "Wand(OBSOLETE),,6,0"])
    stamps.append(f"ItemSubClass db2@{BUILD}")
    (tables / "tables-source.txt").write_text("\n".join(stamps) + "\n", encoding="utf-8")
    return tables


def test_wago_ui_imports_only_the_listed_family_keys(root, data, tmp_path):
    tables = _family_folder(root, tmp_path)
    keys = tmp_path / "ui_keys.txt"
    keys.write_text("ACCEPT\nFactionDescription:69  # The Alliance capital …\nEmoteText:2\nCreatureType:7\n",
                    encoding="utf-8")
    argv = ["english", "wago-ui", str(tables / "GlobalStrings.excerpt.csv"), str(tables / "ItemSubClass.excerpt.csv"),
            "--families", str(tables), "--keys", str(keys), "--build", BUILD, "--src", "db2"]
    assert imp.run(argv) == 0
    lines = {ln["id"]: ln for ln in Store(data, english=True).load("ui")}
    assert lines["FactionDescription:69"]["en"] == "The Alliance capital is populated by Night Elves."
    assert lines["EmoteText:2"]["en"] == "%s waves at you."
    assert lines["CreatureType:7"]["src"] == f"db2@{BUILD}"
    assert "FactionDescription:2721" not in lines  # a developer row: never listed, never imported


def test_item_subclass_names_take_the_long_name_else_the_short_one(root, tmp_path):
    tables = _family_folder(root, tmp_path)
    names = wago.read_item_subclass_names(tables / "ItemSubClass.csv")
    assert names == {"ItemSubClassName:2:10": "Staves", "ItemSubClassName:0:1": "Potions"}  # OBSOLETE left out


def test_wago_ui_refuses_family_tables_of_another_build(root, data, tmp_path):
    tables = _family_folder(root, tmp_path)
    stamps = tables / "tables-source.txt"
    stamps.write_text(stamps.read_text("utf-8").replace("Faction db2@", "Faction wago@"), encoding="utf-8")
    keys = tmp_path / "ui_keys.txt"
    keys.write_text("FactionDescription:69\n", encoding="utf-8")
    argv = ["english", "wago-ui", str(tables / "GlobalStrings.excerpt.csv"), str(tables / "ItemSubClass.excerpt.csv"),
            "--families", str(tables), "--keys", str(keys), "--build", BUILD, "--src", "db2"]
    assert imp.run(argv) != 0  # refused, naming Faction.csv's stamp
    assert Store(data, english=True).load("ui") == []  # nothing written


# --- the curated block: the committed key list and English ---------------------------------------------------------

NAMES = {  # names stay in English: a heading that is only a name is never listed
    "Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior", "Alchemy",
    "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Herbalism", "Fishing", "Cooking",
    "First Aid", "Eastern Kingdoms", "Kalimdor", "Darkmoon Faire", "Lunar Festival", "Midsummer", "Ahn'Qiraj War",
    "Nightmare Incursions", "Blackrock Eruption", "The High Order", "Night Elf", "Human", "Dwarf", "Gnome", "Orc",
    "Troll", "Tauren", "Undead",
}
# "Undead" is also a creature type: CreatureType:6 is listed, and the addon keeps the race English by the slot kind
# (TOOLTIP_UNIT_LEVEL_RACE*) and by never taking the creature-type templates on a player's tooltip (UI/TooltipUnit)
NAME_EXEMPT = {"CreatureType:6"}


def _block(root):
    keys, inside = [], False
    for line in (root / "pipeline/ui_keys.txt").read_text("utf-8").splitlines():
        if line.startswith(("# ── text held in client tables", "# ── More client-table text")):
            inside = True
        elif line.startswith("# ── "):  # the next block
            inside = False
        key = line.split("#", 1)[0].strip()
        if inside and ":" in key:  # the family keys (the barber shop's three global strings are listed with them)
            keys.append(key)
    return keys


def _english(root):
    out = {}
    for f in (root / "data/english/ui").glob("*.jsonl"):
        for line in f.read_text("utf-8").splitlines():
            if line.strip():
                import json
                d = json.loads(line)
                out[d["id"]] = d
    return out


def test_every_block_key_is_a_family_key_with_forever_english(root):
    keys = _block(root)
    assert len(keys) > 2000
    english = _english(root)
    for key in keys:
        assert key.split(":")[0] in (*UI_FAMILIES, "ItemSubClassName"), key
        assert english[key]["src"].startswith("db2@1.60.1."), key


def test_no_small_family_key_is_a_name(root):
    english = _english(root)
    small = ("AchievementCategory", "CurrencyCategory", "SkillCategory", "QuestSort", "CreatureType", "DispelType")
    for key in _block(root):
        if key.split(":")[0] in small and key not in NAME_EXEMPT:
            assert english[key]["en"] not in NAMES, key


def test_one_key_per_english_per_family(root):
    english = _english(root)
    seen = set()
    for key in _block(root):
        pair = (key.split(":")[0], english[key]["en"])
        assert pair not in seen, key
        seen.add(pair)
