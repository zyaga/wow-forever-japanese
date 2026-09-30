"""Pipeline halves of the UI markup work: markup and plural grammar in check, adjacent captures in
validate, enchantment stat lines and key families in the English import, the enchantment draft generator, and the
inventory's dynamic families."""

import json
from pathlib import Path

import pytest

from wfj.cmd import check, import_english, validate
from wfj.cmd import import_ as imp
from wfj.core import markup
from wfj.core.hashing import key
from wfj.core.model import english_line, validate_line
from wfj.core.normalize import normalize_v1
from wfj.core.status import Scope, decide
from wfj.dev import enchant_drafts, ui_inventory
from wfj.io import wago
from wfj.io.jsonl_store import Store

BUILD = "1.15.9.69722"
MACHINE = {"class": "machine", "model": "draft-model-1", "critic": "critic-model-1",
           "source": "draft-ui-markup@2026-09-14", "imported": "2026-09-14"}


def _ui(id_, ja, status="pending", english=None):
    return {"id": id_, "field": "text", "ja": ja, "status": status, "checks": [], "provenance": dict(MACHINE),
            "english": english, "reasons": [], "conflicts": []}


def _en(id_, en):
    return english_line(id_, "text", en, key(normalize_v1(en)), f"wago@{BUILD}")


def _shipped(id_, en, ja):
    return _ui(id_, ja, status="trusted", english={"hash": key(normalize_v1(en)), "src": f"wago@{BUILD}"})


def _scope(en):
    return Scope(kind="ui", fields={"text": normalize_v1(en)}, hashes={"text": key(normalize_v1(en))},
                 raw={"text": en}, src=f"wago@{BUILD}")


# ---- markup and plural grammar --------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "en, ja, status, reason",
    [
        ("|cffffffff%d|r |4Guild Member:Guild Members;", "|cffffffff%d|r 人のギルドメンバー", "trusted", None),
        ("%d |4Day:Days;", "%d日", "trusted", None),  # the plural group is dropped, the specifier stays
        ("%d |4Day:Days;", "%d |4日:日;", "trusted", None),  # a kept group is well-formed
        ("|cffffffff%d|r members", "%d 人", "rejected", "markup_changed"),  # colour dropped
        ("|cffffffff%d|r members", "|cffff0000%d|r 人", "rejected", "markup_changed"),  # colour altered
        ("Line one\nLine two", "一行目 二行目", "rejected", "markup_changed"),  # line break dropped
        ("%d |4Day:Days;", "%d |4日", "rejected", "markup_changed"),  # malformed group
        ("%d |4Day:Days;", "日", "rejected", "specifiers_changed"),
        ("(%s)", "(%s)", "trusted", None),  # no words to translate: no kana required
        ("%s (|cffffffff%d|r)", "%s (|cffffffff%d|r)", "trusted", None),  # colour codes are not words
        ("(%s) Found", "(%s) Found", "rejected", "not_japanese"),
    ],
)
def test_markup_rule_in_check(en, ja, status, reason):
    d = decide(_ui("K", ja), _scope(en), set(), key(normalize_v1(en)))
    assert d.status == status, d.reasons
    if reason:
        assert any(r.startswith(reason) for r in d.reasons), d.reasons


def test_shared_english_differing_only_in_colour_is_not_ambiguous(tmp_path):
    d = tmp_path / "data"
    d.mkdir()
    Store(d, english=True).save("ui", [_en("ITEM_LEVEL", "Level %d"), _en("TRAINER_REQ_LEVEL", "Level |cffffffff%d|r")])
    Store(d).save("ui", [_shipped("ITEM_LEVEL", "Level %d", "レベル %d"),
                         _shipped("TRAINER_REQ_LEVEL", "Level |cffffffff%d|r", "レベル |cffffffff%d|r")])
    assert validate.rule_ui(Store(d), Store(d, english=True)) == []


def test_markup_tokens_ignore_colour_case_and_count_breaks():
    assert markup.mismatch("|cFFFFFFFFa|r", "|cffffffffあ|r") is None
    assert markup.tokens("a\nb\nc")["\n"] == 2
    assert markup.plural_groups("%d |4Hr:Hrs; %d |4Min:Mins;") == 2
    assert markup.plural_malformed("|4a:b")


# ---- adjacent captures keep their order ----------------------------------------------------------------------


def test_adjacent_captures_reordered():
    en = "Level %d %s %s"
    assert validate.adjacent_captures_reordered(en, "レベル%d %s %s") is None
    assert validate.adjacent_captures_reordered(en, "%2$s %3$s レベル%1$d") is None  # the adjacent pair keeps order
    assert validate.adjacent_captures_reordered(en, "レベル%1$d %3$s %2$s") == "%2$ %3$"
    # separated by words, not only whitespace: free to move
    assert validate.adjacent_captures_reordered("%s of %s", "%2$sの%1$s") is None
    # declared kinds: a number (no kind) or one dictionary word beside a word cannot swallow it
    assert validate.adjacent_captures_reordered("%s %s Damage", "%2$sダメージ %1$s", {2: "word"}) is None
    assert validate.adjacent_captures_reordered("Level %d %s %s", "%3$s %2$s", {2: "text", 3: "text"}) == "%2$ %3$"


def test_ui_arg_kinds_are_read_from_the_addon(root):
    kinds = validate.ui_arg_kinds(root / "addon/WoWForeverJapanese")
    # Forever's PLAYER_LEVEL is "Level %s |c%s%s %s|r" (level, colour, race, class), all four text captures
    assert kinds["PLAYER_LEVEL"] == {1: "text", 2: "text", 3: "text", 4: "text"}
    assert kinds["SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL"] == {2: "word"}


def test_validate_rule_ui_reports_markup_and_reordered_captures(tmp_path):
    d = tmp_path / "data"
    d.mkdir()
    Store(d, english=True).save("ui", [_en("PLAYER_LEVEL", "Level %d %s %s"), _en("GUILD_TOTAL",
                                       "|cffffffff%d|r |4Guild Member:Guild Members;")])
    Store(d).save("ui", [_shipped("PLAYER_LEVEL", "Level %d %s %s", "レベル%1$d %3$s %2$s"),
                         _shipped("GUILD_TOTAL", "|cffffffff%d|r |4Guild Member:Guild Members;", "%d 人")])
    problems = validate.rule_ui(Store(d), Store(d, english=True), {"PLAYER_LEVEL": {2: "text", 3: "text"}})
    assert not any("ambiguous" in p for p in problems)
    assert "ui GUILD_TOTAL: markup differs from the English (en[|cffffffffx1 |rx1] ja[none])" in problems
    assert "ui PLAYER_LEVEL: adjacent_captures_reordered (%2$ %3$)" in problems


# ---- enchantments, key families, ids --------------------------------------------------------------------------


def test_enchantment_ids_validate():
    assert validate_line("ui", _en("SpellItemEnchantment:256", "+5 Fire Resistance"), english=True) == []
    for bad in ("SpellItemEnchantment:", "SpellItemEnchantment:x", "SpellItemEnchantment:1:2"):
        assert validate_line("ui", _en(bad, "+5 Fire Resistance"), english=True), bad


def test_read_enchantments_keeps_only_stat_lines(root):
    table = wago.read_enchantments(root / "tests/fixtures/wago/SpellItemEnchantment.excerpt.csv")
    assert table == {
        "SpellItemEnchantment:28": "+4 All Resistances",
        "SpellItemEnchantment:256": "+5 Fire Resistance",
        "SpellItemEnchantment:257": "+10 Fire Resistance",
        "SpellItemEnchantment:900": "+3 Fire Spell Damage",
        "SpellItemEnchantment:901": "+3 Fire Spell Damage",
        "SpellItemEnchantment:1001": "+1 to all attributes",
    }  # "Rockbiter 3" / "Crusader" are names; "+2 Stamina +2 Spirit" is a composite


def test_expand_keys_families():
    table = {"ItemSubClass:1:0": "Bag", "ItemSubClass:1:10": "Quiver", "ItemSubClass:1:2": "Herb Bag",
             "ItemSubClass:2:0": "Axe", "ACCEPT": "Accept"}
    assert wago.expand_keys(["ACCEPT", "ItemSubClass:1:*"], table) == [
        "ACCEPT", "ItemSubClass:1:0", "ItemSubClass:1:2", "ItemSubClass:1:10"]
    with pytest.raises(ValueError, match="no key with that prefix"):
        wago.expand_keys(["ItemSubClass:9:*"], table)


def test_global_strings_line_breaks_are_real_newlines(tmp_path):
    p = tmp_path / "GlobalStrings.csv"
    p.write_text('ID,BaseTag,TagText_lang,Flags\n1,ARMOR_TOOLTIP,"Decreases damage.\\nAgainst level %d",1\n',
                 encoding="utf-8")
    assert wago.read_global_strings(p)["ARMOR_TOOLTIP"] == "Decreases damage.\nAgainst level %d"


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


def test_wago_ui_imports_enchantment_and_subclass_families(root, data, tmp_path, capsys):
    fx = root / "tests/fixtures/wago"
    keys = tmp_path / "ui_keys.txt"
    keys.write_text("ACCEPT\nItemSubClass:1:*\nSpellItemEnchantment:*\n", encoding="utf-8")
    argv = ["english", "wago-ui", str(fx / "GlobalStrings.excerpt.csv"), str(fx / "ItemSubClass.excerpt.csv"),
            "--enchantments", str(fx / "SpellItemEnchantment.excerpt.csv"), "--keys", str(keys), "--build", BUILD]
    assert imp.run(argv) == 0
    lines = {ln["id"]: ln["en"] for ln in Store(data, english=True).load("ui")}
    assert lines["ItemSubClass:1:1"] == "Soul Bag"
    assert lines["SpellItemEnchantment:900"] == "+3 Fire Spell Damage"
    assert "SpellItemEnchantment:803" not in lines and "SpellItemEnchantment:1000" not in lines
    assert "english ui: 9 keys" in capsys.readouterr().out
    # a family listed twice (or a key inside a listed family) is refused, nothing written
    keys.write_text("ItemSubClass:1:*\nItemSubClass:1:0\n", encoding="utf-8")
    assert imp.run(argv) == 1
    assert "listed twice after expanding families" in capsys.readouterr().err


def test_enchant_drafts_follow_the_phrase_table(root, tmp_path):
    table = wago.read_enchantments(root / "tests/fixtures/wago/SpellItemEnchantment.excerpt.csv")
    phrases = tmp_path / "phrases.tsv"
    phrases.write_text("# words\tlabel\nAll Resistances\t全耐性\nFire Resistance\t炎耐性\n"
                       "Fire Spell Damage\t炎呪文ダメージ\nto all attributes\t全能力値\n", encoding="utf-8")
    rows = enchant_drafts.drafts(table, enchant_drafts.read_phrases(phrases))
    assert rows[0] == {"id": "SpellItemEnchantment:28", "field": "text", "ja": "全耐性 +4"}
    assert {r["id"]: r["ja"] for r in rows}["SpellItemEnchantment:901"] == "炎呪文ダメージ +3"
    assert json.dumps(rows, ensure_ascii=False)
    phrases.write_text("Fire Resistance\t炎耐性\n", encoding="utf-8")
    with pytest.raises(ValueError, match="no phrase for: All Resistances, Fire Spell Damage, to all attributes"):
        enchant_drafts.drafts(table, enchant_drafts.read_phrases(phrases))


# ---- the inventory's dynamic families -------------------------------------------------------------------------


def test_dynamic_family_expands_against_global_strings(tmp_path):
    strings = {f"SPELL_STAT{i}_NAME": n for i, n in enumerate(["Strength", "Agility", "Stamina", "Intellect",
                                                               "Spirit"], 1)}
    strings |= {"SPELL_STAT6_NAME": "", "SPELL_STATS": "Stats", "ACCEPT": "Accept"}
    assert ui_inventory.dynamic_keys("character", strings) == {f"SPELL_STAT{i}_NAME" for i in range(1, 6)}
    assert ui_inventory.dynamic_keys("gamemenu", strings) == set()


def test_inventory_scans_window_files_and_families(tmp_path):
    addons = tmp_path / "AddOns"
    for rel in ui_inventory.FOREVER_WINDOWS["skills"]:
        f = addons / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text('<Button text="ALL"/>\nSkillFrameCancelButton:SetText(CLOSE)\nlocal x = NUM_SKILLS\n',
                     encoding="utf-8")
    strings = {"ALL": "All", "CLOSE": "Close", "SPELL_STAT1_NAME": "Strength"}
    # text="ALL" and a bare CLOSE are global strings; NUM_SKILLS is not; a family key never appears in the files
    assert ui_inventory.window_keys(addons, ui_inventory.FOREVER_WINDOWS["skills"], strings) == {"ALL", "CLOSE"}
    assert ui_inventory.dynamic_keys("character", strings) == {"SPELL_STAT1_NAME"}


def test_committed_inventory_lists_every_surface(root):
    surfaces = set()
    for raw in (root / "pipeline/ui_inventory.txt").read_text(encoding="utf-8").splitlines():
        if raw and not raw.startswith("#"):
            surfaces.add(raw.split()[0])
    assert surfaces == set(ui_inventory.FOREVER_WINDOWS)
    assert Path(root / "pipeline/ui_inventory.txt").read_text(encoding="utf-8").startswith("# GENERATED")
