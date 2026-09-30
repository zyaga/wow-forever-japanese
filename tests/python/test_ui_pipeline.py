"""The `ui` type through the pipeline: ids, English import, check rules, generate, validate, the
report by provenance class."""

from pathlib import Path

import pytest

from wfj.cmd import check, generate, import_english, validate
from wfj.cmd import import_ as imp
from wfj.core import report
from wfj.core.hashing import key
from wfj.core.model import english_line, validate_line
from wfj.core.normalize import normalize_v1
from wfj.core.status import Scope, decide
from wfj.emit import lua_writer, schema
from wfj.io import wago
from wfj.io.jsonl_store import Store, shard_name

BUILD = "1.15.9.69722"
MACHINE = {
    "class": "machine",
    "model": "draft-model-1",
    "critic": "critic-model-1",
    "source": "draft-ui@2026-09-14",
    "imported": "2026-09-14",
}


def _ui(id_, ja, status="pending", english=None, prov=MACHINE):
    return {
        "id": id_,
        "field": "text",
        "ja": ja,
        "status": status,
        "checks": [],
        "provenance": dict(prov),
        "english": english,
        "reasons": [],
        "conflicts": [],
    }


def _en(id_, en):
    return english_line(id_, "text", en, key(normalize_v1(en)), f"wago@{BUILD}")


# ---- ids, shards, the English import ----------------------------------------------------------------------


@pytest.mark.parametrize("id_", ["ACCEPT", "ITEM_MOD_STAMINA", "INVTYPE_2HWEAPON", "ItemSubClass:4:1"])
def test_ui_ids_that_validate(id_):
    assert validate_line("ui", _ui(id_, "受諾")) == []
    assert validate_line("ui", _en(id_, "Accept"), english=True) == []


@pytest.mark.parametrize("id_", ["accept", "1ACCEPT", "ItemSubClass:4", "ItemSubClass:a:1", 7, "Quest Log"])
def test_ui_ids_that_do_not(id_):
    assert any("ui id" in p for p in validate_line("ui", _ui(id_, "受諾")))


def test_ui_shards_by_upper_cased_first_character():
    assert shard_name("ui", "ACCEPT") == "ui-A.jsonl"
    assert shard_name("ui", "ItemSubClass:4:1") == shard_name("ui", "ITEM_SOULBOUND") == "ui-I.jsonl"
    assert shard_name("gossip", "ab12cd34ef567890") == "gossip-ab.jsonl"  # unchanged for gossip
    assert schema.shard_relpath("ui", "I") == "Data/UI/UI_I.lua"


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


def _keys(tmp_path: Path, *keys: str) -> Path:
    p = tmp_path / "ui_keys.txt"
    p.write_text("# quest frame\n" + "\n".join(keys) + "\n\n", encoding="utf-8")
    return p


def test_wago_ui_imports_exactly_the_listed_keys(root, data, tmp_path, capsys):
    fx = root / "tests/fixtures/wago"
    keys = _keys(tmp_path, "ACCEPT", "ITEM_MIN_LEVEL  # a template", "ItemSubClass:4:1")
    argv = ["english", "wago-ui", str(fx / "GlobalStrings.excerpt.csv"), str(fx / "ItemSubClass.excerpt.csv")]
    assert imp.run([*argv, "--keys", str(keys), "--build", BUILD]) == 0
    lines = {ln["id"]: ln for ln in Store(data, english=True).load("ui")}
    assert set(lines) == {"ACCEPT", "ITEM_MIN_LEVEL", "ItemSubClass:4:1"}
    assert lines["ITEM_MIN_LEVEL"]["en"] == "Requires Level %d"
    assert lines["ItemSubClass:4:1"]["en"] == "Cloth"
    assert lines["ACCEPT"] == _en("ACCEPT", "Accept")
    assert "english ui: 3 keys" in capsys.readouterr().out

    # a key the tables do not have fails naming it, and nothing changes
    before = {p: p.read_bytes() for p in (data / "english/ui").glob("*.jsonl")}
    missing = _keys(tmp_path, "ACCEPT", "NOT_A_GLOBAL_STRING")
    assert imp.run([*argv, "--keys", str(missing), "--build", BUILD]) == 1
    assert "NOT_A_GLOBAL_STRING" in capsys.readouterr().err
    assert {p: p.read_bytes() for p in (data / "english/ui").glob("*.jsonl")} == before


def test_key_list_rejects_duplicates(tmp_path):
    with pytest.raises(ValueError, match="listed twice"):
        wago.read_keys(_keys(tmp_path, "ACCEPT", "ACCEPT"))


# ---- check rules ---------------------------------------------------------------------------------------------


def _scope(en):
    return Scope(kind="ui", fields={"text": normalize_v1(en)}, hashes={"text": key(normalize_v1(en))},
                 raw={"text": en}, src=f"wago@{BUILD}")


@pytest.mark.parametrize(
    "en, ja, status, reason",
    [
        ("Accept", "受諾", "trusted", None),
        ("Requires Level %d", "必要レベル: %d", "trusted", None),
        ("%c%d %s Resistance", "%c%d %s耐性", "trusted", None),
        ("%s - %s Damage", "%1$s～%2$s ダメージ", "trusted", None),
        ("Durability %d / %d", "耐久度 %d", "rejected", "specifiers_changed"),
        ("Accept", "受諾 %s", "rejected", "specifiers_changed"),
        ("Accept", "Accept", "rejected", "not_japanese"),
    ],
)
def test_ui_status_rules(en, ja, status, reason):
    d = decide(_ui("K", ja), _scope(en), set(), key(normalize_v1(en)))
    assert d.status == status
    if reason:
        assert d.reasons and d.reasons[0].startswith(reason)


def test_ui_no_english_and_stale(data):
    Store(data, english=True).save("ui", [_en("ACCEPT", "Accept")])
    Store(data).save("ui", [_ui("ACCEPT", "受諾"), _ui("DECLINE", "辞退")])
    assert check.run([]) == 0
    by = {ln["id"]: ln for ln in Store(data).load("ui")}
    assert by["ACCEPT"]["status"] == "trusted"
    assert by["ACCEPT"]["english"] == {"hash": key("Accept"), "src": f"wago@{BUILD}"}
    assert (by["DECLINE"]["status"], by["DECLINE"]["reasons"]) == ("rejected", ["no_english_id"])
    Store(data, english=True).save("ui", [_en("ACCEPT", "Accept Quest")])  # the client's English changed
    assert check.run([]) == 0
    assert {ln["id"]: ln for ln in Store(data).load("ui")}["ACCEPT"]["status"] == "stale"


# ---- generate + validate -------------------------------------------------------------------------------------


def _shipped(id_, en, ja):
    return _ui(id_, ja, status="trusted", english={"hash": key(normalize_v1(en)), "src": f"wago@{BUILD}"})


def test_generate_writes_ui_shards_and_meta_counts(root, tmp_path):
    d = tmp_path / "data"
    d.mkdir()
    (d / "SCHEMA").write_text("1\n")
    Store(d).save("ui", [_shipped("ACCEPT", "Accept", "受諾"), _shipped("ItemSubClass:4:1", "Cloth", "布"),
                         _shipped("ITEM_MIN_LEVEL", "Requires Level %d", "必要レベル: %d"),
                         _ui("DECLINE", "辞退", status="rejected")])
    planned = generate.plan(Store(d), generate.vectors_rows(root / "data"))
    assert planned["Data/UI/UI_A.lua"] == (
        "-- GENERATED by `wfj generate` from data/ui/ui-A.jsonl. Do not edit: `wfj validate` regenerates and "
        "diffs it.\n"
        "local _, WFJ = ...\n"
        'WFJ.Data.add("ui", {\n'
        f'  ["ACCEPT"] = {{ "受諾", {lua_writer.h1_literal(key("Accept"))}, "." }},\n'
        "})\n"
    )
    assert '["ITEM_MIN_LEVEL"]' in planned["Data/UI/UI_I.lua"] and '["ItemSubClass:4:1"]' in planned["Data/UI/UI_I.lua"]
    assert "DECLINE" not in "".join(planned.values())
    assert "ui = 3" in planned["Data/Meta.lua"]
    assert generate.toc_files(planned)[-2:] == ["Data/UI/UI_A.lua", "Data/UI/UI_I.lua"]
    addon = tmp_path / "addon"
    (addon / "Data").mkdir(parents=True)
    (addon / generate.TOC_NAME).write_text(f"## Title: x\n{schema.TOC_BEGIN}\n{schema.TOC_END}\n", encoding="utf-8")
    generate.apply(planned, addon)
    assert generate.apply(planned, addon)["written"] == []  # deterministic


def test_validate_ui_rule(tmp_path):
    d = tmp_path / "data"
    d.mkdir()
    Store(d, english=True).save("ui", [_en("SPEED", "Speed"), _en("SPEED_X", "Speed"), _en("ITEM_MIN_LEVEL",
                                       "Requires Level %d"), _en("ItemSubClass:2:0", "Axe"),
                                       _en("ItemSubClass:2:1", "Axe")])
    Store(d).save("ui", [
        _shipped("SPEED", "Speed", "速度"),
        _shipped("SPEED_X", "Speed", "スピード"),  # same English, other Japanese → ambiguous
        _shipped("ITEM_MIN_LEVEL", "Requires Level %d", "必要レベル"),  # dropped %d
        _shipped("ItemSubClass:2:0", "Axe", "斧"),  # same English, same Japanese → fine
        _shipped("ItemSubClass:2:1", "Axe", "斧"),
    ])
    problems = validate.rule_ui(Store(d), Store(d, english=True))
    assert problems == [
        "ui ITEM_MIN_LEVEL: specifiers differ from the English (en[%1$d] ja[none])",
        "ui ambiguous: SPEED, SPEED_X share the English 'Speed' with different Japanese",
    ]


# ---- shipped lines by provenance class -----------------------------------------------------------------------


def test_report_counts_shipped_lines_by_class():
    human = {"class": "human", "translator": "T", "source": "cqjt@3446c82", "imported": "2026-09-13"}
    lines = {
        "ui": [_ui("ACCEPT", "受諾", status="trusted"), _ui("DECLINE", "辞退", status="rejected")],
        "quest": [dict(_ui(2, "題", status="trusted", prov=human), field="title")],
    }
    t = report.tally(lines)
    assert t["classes"] == {"ui": {"machine": 1}, "quest": {"human": 1}}
    text = report.render(t)
    assert "ui shipped by provenance: human 0 · correction 0 · machine 1" in text
    assert "quest shipped by provenance: human 1 · correction 0 · machine 0" in text


# ---- edge cases ------------------------------------------------------------------------------------------------


def test_an_unparseable_english_template_rejects_instead_of_crashing():
    d = decide(_ui("K", "受諾 %s"), _scope("%s and %2$s"), set(), key(normalize_v1("%s and %2$s")))
    assert d.status == "rejected" and d.reasons[0].startswith("specifiers_changed")


def test_item_subclass_duplicates_are_reported(tmp_path):
    p = tmp_path / "ItemSubClass.csv"
    p.write_text("DisplayName_lang,ID,ClassID,SubClassID\nAxe,3,2,0\nHatchet,4,2,0\n", encoding="utf-8")
    with pytest.raises(ValueError, match="listed twice"):
        wago.read_item_subclasses(p)


def test_every_text_capturing_template_declares_its_argument_kinds(root):
    # a `%s` defaults to a number in Core/UIStrings.lua; a key whose `%s` is not numeric must be in
    # UIStrings.ARGS, so an open `%s` never swallows an item name or a prose sentence.
    import re

    lua = (root / "addon/WoWForeverJapanese/Core/UIStringKeys.lua").read_text(encoding="utf-8")
    block = lua.split("UIStrings.ARGS = {", 1)[1].split("\n}\n", 1)[0]
    declared = set(re.findall(r"([A-Z][A-Z0-9_]+) = \{", block))
    numeric = re.compile(r"_COST|DAMAGE_TEMPLATE|ARMOR_TEMPLATE|DPS_TEMPLATE|SPELL_RANGE$|^ITEM_MOD_")
    # Keys whose `%s` the Forever client introduced, each capturing a NUMBER, so the
    # default `CAPTURE.s = NUMBER` in Core/UIStrings.lua is already right and no ARGS entry is needed.
    # Listed explicitly rather than widened into `numeric` above, so the next new template still has to be
    # looked at by a person instead of being swallowed by a broader pattern.
    #   DEFAULT_STAMINA_TOOLTIP        "Increases |cFFFFFFFFHealth|r by %s"
    #   MELEE_ATTACK_POWER_TOOLTIP     "...|cFFFFFFFFMelee Weapon|r damage per second by %s..."
    #   RANGED_ATTACK_POWER_TOOLTIP    "...|cFFFFFFFFRanged Weapon|r damage per second by %s..."
    #   SHIELD_BLOCK_TEMPLATE          "%s Block"
    #   TRAINING_POINTS                "Training Points: %s"
    # The camelot surfaces' number captures: a member count "%s/%s Online", page numbers
    # "Page %s of %s", "%s TP", a percent "+%s%%", and the stat tooltips' "…by %s" (BreakUpLargeNumbers /
    # FormatPercentage output: a number) in the expertise, class / pet melee attack power and spell power tooltips.
    from wfj.cmd import validate as _validate

    chat = _validate.ui_chat_families(root / "addon/WoWForeverJapanese")
    reviewed_numeric = {
        "DEFAULT_STAMINA_TOOLTIP", "MELEE_ATTACK_POWER_TOOLTIP", "RANGED_ATTACK_POWER_TOOLTIP",
        "SHIELD_BLOCK_TEMPLATE", "TRAINING_POINTS",
        "COMMUNITIES_MEMBER_LIST_MEMBER_COUNT_FORMAT", "MERCHANT_PAGE_NUMBER", "TRAINING_POINTS_ABBREV",
        "STAT_ATTACK_SPEED_BASE_TOOLTIP", "CR_EXPERTISE_TOOLTIP", "CR_RANGED_EXPERTISE_TOOLTIP",
        "DRUID_MELEE_ATTACK_POWER_TOOLTIP", "HUNTER_MELEE_ATTACK_POWER_TOOLTIP", "ROGUE_MELEE_ATTACK_POWER_TOOLTIP",
        "MELEE_ATTACK_POWER_PET_HUNTER_TOOLTIP", "MELEE_ATTACK_POWER_PET_WARLOCK_TOOLTIP",
        "MELEE_ATTACK_POWER_SPELL_POWER_TOOLTIP",
        # the guild reputation bar's "Current: %s/%s (%s%%)", BreakUpLargeNumbers values and a
        # percent number (camelot guildrewards.lua:198)
        "GUILD_EXPERIENCE_CURRENT",
        # the Forever windows' number captures: an item level, a quantity (BreakUpLargeNumbers),
        # a blocked amount in combat text, the death recap's seconds and health percent, a points count, a level, and
        # the talent search's "And %s more".
        "AUCTION_HOUSE_NONE_AVAILABLE_FORMAT", "AUCTION_HOUSE_QUANTITY_AVAILABLE_FORMAT", "COMBAT_TEXT_BLOCK_REDUCED",
        "DEATH_RECAP_CURR_HP_TT", "DEATH_RECAP_DEATH_TT", "LEGACY_POINTS_AVAILABLE", "MOUNT_EQUIPMENT_UNLOCK_REQUIREMENT",
        "TALENT_FRAME_SEARCH_PREVIEW_OVERFLOW_FORMAT",
    }
    for ln in Store(root / "data", english=True).load("ui"):
        # an undeclared ERR_* / SPELL_FAILED_* or system chat key takes every `%s` as `text`
        # (Core/UIStrings.lua argKinds)
        if ln["id"].startswith(("ERR_", "SPELL_FAILED_")) or any(p.search(ln["id"]) for p in chat):
            continue
        # ADR-042: a slotted row is never a template; its `%s` are names put back by index:matchSlots and
        # shown as the line wrote them
        if ln["id"].startswith("EmoteText:"):
            continue
        if "%s" in ln["en"] and ln["id"] not in declared and ln["id"] not in reviewed_numeric:
            assert numeric.search(ln["id"]), f"{ln['id']} ({ln['en']!r}) captures text: declare it in UIStrings.ARGS"


def test_keys_sharing_one_english_declare_the_same_argument_kinds(root):
    """Core/UIStrings compiles ONE template per distinct English, under whichever of its keys
    sorts first, and that key's UIStrings.ARGS decides how every key of the group captures. Adding a key with
    narrower kinds silently re-captures the line for the others; that is how `KEY_BINDING_NAME_AND_KEY` broke
    `PVP_LEAVE_BUTTON_TIME`'s "Leave Match (30)". Every group must therefore agree."""
    import json
    import re

    args_block = (root / "addon/WoWForeverJapanese/Core/UIStringKeys.lua").read_text(encoding="utf-8")
    args_block = args_block.split("UIStrings.ARGS = {", 1)[1].split("\n}\n", 1)[0]
    declared: dict[str, dict[int, str]] = {}
    for name, body in re.findall(r"\b([A-Z][A-Z0-9_]*)\s*=\s*\{([^}]*)\}", args_block):
        declared[name] = {int(i): kind for i, kind in re.findall(r"\[(\d+)\]\s*=\s*\"(\w+)\"", body)}
    assert len(declared) > 50  # the table was found, not an empty match

    english: dict[str, str] = {}
    for path in sorted((root / "data/english/ui").glob("*.jsonl")):
        for raw in path.read_text(encoding="utf-8").splitlines():
            row = json.loads(raw)
            english[row["id"]] = row["en"]

    groups: dict[str, list[str]] = {}
    for name in declared:
        if name in english:
            groups.setdefault(english[name], []).append(name)
    # Known and accepted: "Requires %s" is shared by ITEM_REQ_SKILL (a `skill` capture) and the
    # spell / form keys (`text`). ITEM_REQ_SKILL sorts first, so the group compiles as `skill`, which is what the
    # item tooltip needs, and the spell lines fall back to their own exact entries.
    REVIEWED = {"Requires %s"}
    disagreeing = []
    for en, keys in groups.items():
        if len(keys) < 2 or en in REVIEWED:
            continue
        first = declared[sorted(keys)[0]]
        for other in sorted(keys)[1:]:
            if declared[other] != first:
                disagreeing.append((en, sorted(keys)[0], other, first, declared[other]))
    assert disagreeing == []
