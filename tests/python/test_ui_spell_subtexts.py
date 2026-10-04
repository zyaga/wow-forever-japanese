"""Pipeline half: the Spell table's NameSubtext_lang is read from the client, and the spellbook subtexts
are a `SpellSubtext:<spellID>` key family of the UI dictionary: fingerprint rows, like item subclasses."""

import json
import shutil

import pytest

from wfj.cmd import check, import_english
from wfj.cmd import import_ as imp
from wfj.core.model import validate_line
from wfj.io import client_tables, wago
from wfj.io.jsonl_store import Store

BUILD = "1.15.9.69722"
SPELL_CSV = (
    "ID,NameSubtext_lang,Description_lang,AuraDescription_lang\n"
    "126,Summon,Summons an Eye of Kilrogg.,\n"
    "768,Shapeshift,Shapeshift into cat form.,\n"
    "2481,Racial,,\n"
    "5227,Racial Passive,,\n"
    "411128,Cat,,\n"
    "9999,,No subtext.,\n"
)


def _en(id_, text):
    return {"id": id_, "field": "text", "en": text, "hash": "0" * 16, "src": f"wago@{BUILD}"}


def test_spell_table_reads_the_subtext_column():
    table = client_tables.TABLES["Spell"]
    assert [c.name for c in table.columns] == ["ID", "NameSubtext_lang", "Description_lang", "AuraDescription_lang"]
    # every string field of the layout is now written: none is skipped at the wrong width
    assert 0 not in table.unwritten_strings


def test_subtext_ids_validate():
    assert validate_line("ui", _en("SpellSubtext:5227", "Racial Passive"), english=True) == []
    for bad in ("SpellSubtext:", "SpellSubtext:x", "SpellSubtext:1:2", "spellsubtext:5227"):
        assert validate_line("ui", _en(bad, "Racial"), english=True), bad


def test_read_subtexts_keeps_every_non_empty_subtext(tmp_path):
    p = tmp_path / "Spell.csv"
    p.write_text(SPELL_CSV, encoding="utf-8")
    assert wago.read_subtexts(p) == {
        "SpellSubtext:126": "Summon", "SpellSubtext:768": "Shapeshift", "SpellSubtext:2481": "Racial",
        "SpellSubtext:5227": "Racial Passive", "SpellSubtext:411128": "Cat",
    }


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


def test_wago_ui_imports_only_the_listed_subtexts(root, data, tmp_path):
    tables = tmp_path / "tables"
    shutil.copytree(root / "tests/fixtures/wago", tables)
    (tables / "Spell.csv").write_text(SPELL_CSV, encoding="utf-8")
    stamps = tables / "tables-source.txt"
    stamps.write_text(stamps.read_text("utf-8") + f"Spell wago@{BUILD}\n", encoding="utf-8")
    keys = tmp_path / "ui_keys.txt"
    keys.write_text("ACCEPT\nSpellSubtext:5227  # Racial Passive\nSpellSubtext:2481\n", encoding="utf-8")
    argv = ["english", "wago-ui", str(tables / "GlobalStrings.excerpt.csv"), str(tables / "ItemSubClass.excerpt.csv"),
            "--subtexts", str(tables / "Spell.csv"), "--keys", str(keys), "--build", BUILD]
    assert imp.run(argv) == 0
    lines = {ln["id"]: ln["en"] for ln in Store(data, english=True).load("ui")}
    assert lines["SpellSubtext:5227"] == "Racial Passive"
    assert lines["SpellSubtext:2481"] == "Racial"
    assert "SpellSubtext:411128" not in lines  # a form name: never listed, never imported (names stay in English)


def test_the_repo_lists_no_name_subtext(root):
    """The listed subtexts are prose; pet families, form names and test rows are names and stay English."""
    names = {"Cat", "Bear", "Turtle", "Pig", "Odd Melon", "QASpell", "TEST"}
    listed = [ln.split("#")[0].strip() for ln in (root / "pipeline/ui_keys.txt").read_text("utf-8").splitlines()]
    subtexts = [k for k in listed if k.startswith("SpellSubtext:")]
    assert len(subtexts) == 12
    english = {}
    for f in (root / "data/english/ui").glob("*.jsonl"):
        for raw in f.read_text("utf-8").splitlines():
            row = json.loads(raw)
            english[row["id"]] = row["en"]
    assert {english[k] for k in subtexts}.isdisjoint(names)
    assert {english[k] for k in subtexts} == {
        "Racial", "Racial Passive", "Summon", "Shapeshift", "Tier 1", "Tier 2", "Tier 3", "Tier 4",
        "Level 1", "Level 2", "Level 3", "Level 4",
    }


def test_the_spellbook_writes_no_spell_subtext(root):
    """ADR-058: UI/SpellBook.lua writes nothing into the spell items (Blizzard measures them on the way to the action
    bars), so it lists no SpellSubtext id and no subtext keys; the 12 listed subtexts stay in the data."""
    lua = (root / "addon/WoWForeverJapanese/UI/SpellBook.lua").read_text("utf-8")
    assert "SpellSubtext:" not in lua
    assert "SUBTEXT_KEYS" not in lua
    listed = {ln.split("#")[0].strip() for ln in (root / "pipeline/ui_keys.txt").read_text("utf-8").splitlines()}
    assert len({k for k in listed if k.startswith("SpellSubtext:")}) == 12
