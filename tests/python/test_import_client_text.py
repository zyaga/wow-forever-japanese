"""`wfj import english client-text` (item / spell tooltip and buff English) and the `--src`
label of the client-table imports."""

from pathlib import Path

import pytest

from wfj.cmd.import_ import run
from wfj.core.hashing import key
from wfj.core.model import english_line, validate_line
from wfj.core.normalize import normalize_v1
from wfj.io import tables_stamp
from wfj.io.jsonl_store import Store

BUILD = "1.15.9.69722"


def _data(tmp_path: Path, monkeypatch) -> Path:
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    return data


def _csvs(tmp_path: Path) -> tuple[Path, Path, Path, Path]:
    item = tmp_path / "ItemSparse.csv"
    item.write_text(
        "ID,Description_lang,Display_lang\n"
        '117,,"Tough Jerky"\n'
        '5000,"A worn old ring.\\nIt hums.","Ring"\n'
        '6000,"Flavour only","Trinket"\n'
        '7000,,"Nothing"\n'
    )
    spell = tmp_path / "Spell.csv"
    spell.write_text(
        "ID,NameSubtext_lang,Description_lang,AuraDescription_lang\n"
        '433,,"Restores $o1 health over $d.","Restoring $o1 health."\n'
        '500,,"Equip: +5 Stamina.",\n'
        '501,,"Use: Heals $s1.",\n'
        "502,,,\n"
    )
    effect = tmp_path / "ItemEffect.csv"
    effect.write_text(
        "ID,LegacySlotIndex,TriggerType,SpellID,ParentItemID\n"
        "10,0,0,433,117\n"
        "21,1,0,501,5000\n"  # slot 1
        "20,0,0,500,5000\n"  # slot 0: first
        "22,1,0,500,5000\n"  # a second effect in slot 1: after effect 21
        "30,0,0,9999,117\n"  # no such spell: counted, and item 117 gets no partial tooltip English
        "31,0,0,433,8888\n"  # no such item: counted
        "32,0,0,502,7000\n"  # a spell with no description: nothing to join
        "33,0,0,0,117\n"  # no spell: ignored
        "40,0,6,9998,6000\n"  # learn spell: not in the tooltip; even an unknown spell is not counted
        "41,1,7,433,6000\n"  # loot tracker: not joined
        "42,0,2,501,7000\n"  # chance on hit: joined
        "43,1,5,500,7000\n"  # use without delay: joined
    )
    names = tmp_path / "SpellName.csv"
    names.write_text("ID,Name_lang\n433,Food\n500,Stamina\n")
    _stamp(tmp_path, "wago")
    return item, spell, effect, names


def _stamp(folder: Path, src: str) -> None:
    """The CSVs' source stamp, as make wago-fetch / make tables-extract write it."""
    tables = ("ItemSparse", "Spell", "ItemEffect", "SpellName", "GlobalStrings", "ItemSubClass")
    tables_stamp.write(folder, tables, f"{src}@{BUILD}")


def _run(item, spell, effect, src="wago") -> int:
    return run(["english", "client-text", str(item), str(spell), str(effect), "--build", BUILD, "--src", src])


def test_spell_and_item_tooltip_lines(tmp_path, monkeypatch, capsys):
    data = _data(tmp_path, monkeypatch)
    item, spell, effect, _ = _csvs(tmp_path)
    assert _run(item, spell, effect) == 0
    out = capsys.readouterr().out
    eng = Store(data, english=True)
    spells = {(ln["id"], ln["field"]): ln for ln in eng.load("spell")}
    items = {(ln["id"], ln["field"]): ln for ln in eng.load("item")}
    assert spells[(433, "description")]["en"] == "Restores $o1 health over $d."  # raw template
    assert spells[(433, "aura")]["en"] == "Restoring $o1 health."
    assert (500, "aura") not in spells and (502, "description") not in spells  # empty text: no line
    assert (117, "description") not in items  # one of its effects names an unknown spell: no partial English
    # (slot, effect id) order, then the flavour text
    assert items[(5000, "description")]["en"] == "Equip: +5 Stamina.\nUse: Heals $s1.\nEquip: +5 Stamina.\nA worn old ring.\nIt hums."
    assert items[(6000, "description")]["en"] == "Flavour only"
    assert items[(7000, "description")]["en"] == "Use: Heals $s1.\nEquip: +5 Stamina."  # trigger types 2, 5
    assert 8888 not in {i for i, _ in items}
    assert "item effects not in the tooltip, not joined: type 6: 1, type 7: 1" in out
    for (id_, f), ln in {**spells, **items}.items():
        assert ln["src"] == f"wago@{BUILD}" and ln["hash"] == key(normalize_v1(ln["en"]))
        assert validate_line("spell" if (id_, f) in spells else "item", ln, english=True) == []
    assert "item effects not written: 1 name no known spell (1 items left without tooltip English), 1 no known item" in out


def test_src_label_and_a_relabel_changes_only_src(tmp_path, monkeypatch):
    data = _data(tmp_path, monkeypatch)
    item, spell, effect, _ = _csvs(tmp_path)
    assert _run(item, spell, effect) == 0
    before = {(ln["id"], ln["field"]): ln for ln in Store(data, english=True).load("spell")}
    _stamp(tmp_path, "db2")  # the same CSVs as a client extraction would stamp them
    assert _run(item, spell, effect, src="db2") == 0
    after = {(ln["id"], ln["field"]): ln for ln in Store(data, english=True).load("spell")}
    assert after.keys() == before.keys()  # the db2 lines replace the wago lines: none lingers
    for k in after:
        assert after[k]["src"] == f"db2@{BUILD}" and after[k]["hash"] == before[k]["hash"]


def test_names_and_tooltip_text_do_not_wipe_each_other(tmp_path, monkeypatch):
    data = _data(tmp_path, monkeypatch)
    item, spell, effect, names = _csvs(tmp_path)
    assert _run(item, spell, effect) == 0
    assert run(["english", "wago-ids", str(item), str(names), "--build", BUILD]) == 0
    assert _run(item, spell, effect) == 0
    fields = {(ln["id"], ln["field"]) for ln in Store(data, english=True).load("spell")}
    assert {(433, "name"), (433, "description"), (433, "aura"), (500, "name")} <= fields


def test_wago_ids_default_label_is_wago(tmp_path, monkeypatch):
    data = _data(tmp_path, monkeypatch)
    item, _, _, names = _csvs(tmp_path)
    assert run(["english", "wago-ids", str(item), str(names), "--build", BUILD]) == 0
    assert {ln["src"] for ln in Store(data, english=True).load("item")} == {f"wago@{BUILD}"}


@pytest.mark.parametrize("which", ["spell", "effect", "item"])
def test_an_empty_table_is_refused_and_nothing_written(tmp_path, monkeypatch, capsys, which):
    """A cut-short table would shrink every tooltip baseline."""
    data = _data(tmp_path, monkeypatch)
    item, spell, effect, _ = _csvs(tmp_path)
    assert _run(item, spell, effect) == 0
    before = {t: Store(data, english=True).load(t) for t in ("spell", "item")}
    path = {"spell": spell, "effect": effect, "item": item}[which]
    path.write_text(path.read_text().splitlines()[0] + "\n")
    assert _run(item, spell, effect) == 1
    err = capsys.readouterr().err
    assert "no rows" in err or "no item effects" in err
    assert {t: Store(data, english=True).load(t) for t in ("spell", "item")} == before


def test_an_item_listed_twice_is_an_error(tmp_path, monkeypatch, capsys):
    _data(tmp_path, monkeypatch)
    item, spell, effect, _ = _csvs(tmp_path)
    item.write_text(item.read_text() + '6000,"Again","Trinket"\n')
    assert _run(item, spell, effect) == 1
    assert "item 6000 listed twice" in capsys.readouterr().err


def test_a_spell_listed_twice_is_an_error(tmp_path, monkeypatch, capsys):
    _data(tmp_path, monkeypatch)
    item, spell, effect, _ = _csvs(tmp_path)
    spell.write_text(spell.read_text() + '433,,"again",\n')
    assert _run(item, spell, effect) == 1
    assert "spell 433 listed twice" in capsys.readouterr().err


@pytest.mark.parametrize("line", [english_line(1, "aura", "x", "0" * 16, "db2@1.15.9.69722")])
def test_the_model_accepts_the_new_fields(line):
    assert validate_line("spell", line, english=True) == []


def test_relabelling_names_and_ui_strings_leaves_no_line_of_the_other_label(tmp_path, monkeypatch):
    """For wago-ids and wago-ui: `db2` lines replace `wago` lines (one source family), hashes unchanged."""
    data = _data(tmp_path, monkeypatch)
    item, _, _, names = _csvs(tmp_path)
    gs = tmp_path / "GlobalStrings.csv"
    gs.write_text("BaseTag,TagText_lang\nOKAY,Okay\nCANCEL,Cancel\n")
    sub = tmp_path / "ItemSubClass.csv"
    sub.write_text("DisplayName_lang,ClassID,SubClassID\nBag,1,0\n")
    keys = tmp_path / "ui_keys.txt"
    keys.write_text("OKAY\nCANCEL\n")
    for src in ("wago", "db2"):
        _stamp(tmp_path, src)
        assert run(["english", "wago-ids", str(item), str(names), "--build", BUILD, "--src", src]) == 0
        assert run(["english", "wago-ui", str(gs), str(sub), "--keys", str(keys), "--build", BUILD, "--src", src]) == 0
        eng = Store(data, english=True)
        for t in ("item", "spell", "ui"):
            assert {ln["src"] for ln in eng.load(t)} == {f"{src}@{BUILD}"}, (t, src)
    assert {ln["id"]: ln["hash"] for ln in Store(data, english=True).load("ui")} == {
        "OKAY": key(normalize_v1("Okay")), "CANCEL": key(normalize_v1("Cancel")),
    }


# --- the item -> effect join on a build that has no relationship map -------------------------------
# Forever's ItemEffect carries no relationship map (every section reports relationship_data_size 0), so its
# ParentItemID is written 0 on every row and the join lives in ItemXItemEffect instead. The failure mode this
# guards is the quiet one: taking ParentItemID at face value on that build joins nothing and imports no item
# tooltip English at all.

def _forever_csvs(tmp_path: Path) -> tuple[Path, Path, Path, Path]:
    """The same four CSVs, but with ParentItemID 0 everywhere, as Forever writes them."""
    item, spell, effect, names = _csvs(tmp_path)
    rows = effect.read_text().splitlines()
    header, body = rows[0], rows[1:]
    effect.write_text(
        header + "\n" + "\n".join(",".join(r.split(",")[:-1] + ["0"]) for r in body) + "\n"
    )
    return item, spell, effect, names


def test_item_effects_join_through_itemxitemeffect(tmp_path: Path):
    from wfj.io import wago

    _, _, effect, _ = _forever_csvs(tmp_path)
    link = tmp_path / "ItemXItemEffect.csv"
    link.write_text("ID,ItemEffectID,ItemID\n1,10,117\n2,20,5000\n3,21,5000\n")
    items = wago.read_item_effect_items(link)
    assert items == {10: 117, 20: 5000, 21: 5000}
    joined = wago.read_item_effects(effect, items)
    # only the three linked effects with a real spell resolve; ParentItemID 0 is never consulted
    assert [(i, slot, e, s) for i, slot, e, s, _ in joined] == [
        (117, 0, 10, 433), (5000, 0, 20, 500), (5000, 1, 21, 501)
    ]


def test_without_the_join_a_forever_itemeffect_imports_nothing_and_says_so(tmp_path: Path):
    """The whole point: ParentItemID 0 must fail loudly, not join zero items in silence."""
    from wfj.io import wago

    _, _, effect, _ = _forever_csvs(tmp_path)
    with pytest.raises(ValueError, match="no item effects"):
        wago.read_item_effects(effect)


def test_two_items_claiming_one_effect_is_reported_never_last_wins(tmp_path: Path):
    """A duplicate is resolved by a stated rule or reported, never silently."""
    from wfj.io import wago

    link = tmp_path / "ItemXItemEffect.csv"
    link.write_text("ID,ItemEffectID,ItemID\n1,10,117\n2,10,5000\n")
    with pytest.raises(ValueError, match="claimed by items"):
        wago.read_item_effect_items(link)


def test_an_empty_itemxitemeffect_is_refused(tmp_path: Path):
    from wfj.io import wago

    link = tmp_path / "ItemXItemEffect.csv"
    link.write_text("ID,ItemEffectID,ItemID\n")
    with pytest.raises(ValueError, match="no item-effect links"):
        wago.read_item_effect_items(link)


def test_the_join_is_optional_so_classic_era_is_unchanged(tmp_path: Path):
    """Omitting it must read ParentItemID exactly as before; Classic Era ships no such table."""
    from wfj.io import wago

    _, _, effect, _ = _csvs(tmp_path)
    assert [(i, e, s) for i, _, e, s, _ in wago.read_item_effects(effect)][:3] == [
        (117, 10, 433), (117, 30, 9999), (5000, 20, 500)
    ]


# --- union merge, for a second client that ships fewer ids -----------------------------------------
# Replacing the set is right while one client is the truth. Across two clients it deletes the English for
# every id the newer one lacks, and a translation whose English is gone stops shipping: measured on the real
# tables, item descriptions fell 2,664 -> 1,910 shipping with 302 newly `no_english_id`. Union keeps them,
# and their unchanged `src` is what lets `--unseen-since` find them again later.

def test_union_keeps_a_line_the_new_source_does_not_provide():
    from wfj.cmd.import_english import _merge_fields

    existing = [
        {"id": 1, "field": "description", "en": "old one", "src": "wago@1.15.9.69722"},
        {"id": 2, "field": "description", "en": "vanilla only", "src": "wago@1.15.9.69722"},
    ]
    new = [{"id": 1, "field": "description", "en": "forever one", "src": "db2@1.60.1.69913"}]

    replaced = _merge_fields("item", existing, new, ("description",))
    assert {ln["id"] for ln in replaced} == {1}, "replace drops the id the new source lacks"

    union = _merge_fields("item", existing, new, ("description",), union=True)
    assert {ln["id"] for ln in union} == {1, 2}
    by_id = {ln["id"]: ln for ln in union}
    assert by_id[1]["en"] == "forever one" and by_id[1]["src"] == "db2@1.60.1.69913"
    # the kept line keeps its own stamp; this is the marker --unseen-since reads
    assert by_id[2]["src"] == "wago@1.15.9.69722"


def test_union_still_refuses_to_merge_zero_lines():
    """The guard that stops an empty read from emptying the corpus stays in both modes."""
    from wfj.cmd.import_english import _merge_fields

    existing = [{"id": 1, "field": "description", "en": "x", "src": "wago@1.15.9.69722"}]
    with pytest.raises(ValueError, match="zero lines"):
        _merge_fields("item", existing, [], ("description",), union=True)


def test_union_does_not_touch_other_fields_or_other_sources():
    from wfj.cmd.import_english import _merge_fields

    existing = [
        {"id": 1, "field": "name", "en": "a name", "src": "wago@1.15.9.69722"},
        {"id": 1, "field": "description", "en": "old", "src": "wago@1.15.9.69722"},
        {"id": 9, "field": "description", "en": "from pfquest", "src": "pfquest@abc"},
    ]
    new = [{"id": 1, "field": "description", "en": "new", "src": "db2@1.60.1.69913"}]
    out = _merge_fields("item", existing, new, ("description",), union=True)
    assert {(ln["id"], ln["field"], ln["en"]) for ln in out} == {
        (1, "name", "a name"), (1, "description", "new"), (9, "description", "from pfquest"),
    }


def test_unseen_since_counts_what_a_source_has_never_provided():
    from wfj.core import report

    english = {
        "item": [
            {"id": 1, "field": "description", "src": "db2@1.60.1.69913"},
            {"id": 2, "field": "description", "src": "wago@1.15.9.69722"},
            {"id": 3, "field": "description", "src": "wago@1.15.9.69722"},
        ],
        # a type this source never provides is left out entirely, not reported as 100% unseen
        "gossip": [{"id": 7, "field": "text", "src": "vmangos@abc"}],
    }
    lines = {
        "item": [
            {"id": 2, "field": "description", "status": "trusted"},
            {"id": 3, "field": "description", "status": "rejected"},
        ],
        "gossip": [],
    }
    out = report.unseen_since(english, lines, "db2@1.60.1.69913")
    assert "gossip" not in out
    assert out["item"] == (3, 2, 1)  # 3 lines, 2 unseen, 1 of those shipping


def test_unseen_since_matches_a_bare_source_name_too():
    from wfj.core import report

    english = {"item": [
        {"id": 1, "field": "description", "src": "db2@1.60.1.69913"},
        {"id": 2, "field": "description", "src": "db2@1.60.1.70000"},
        {"id": 3, "field": "description", "src": "wago@1.15.9.69722"},
    ]}
    lines = {"item": []}
    assert report.unseen_since(english, lines, "db2")["item"] == (3, 1, 0)
    # pinned to one build, the other build's line counts as unseen, which is how a build-to-build
    # comparison is made
    assert report.unseen_since(english, lines, "db2@1.60.1.69913")["item"] == (3, 2, 0)
