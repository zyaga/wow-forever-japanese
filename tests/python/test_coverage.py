"""`make coverage`: docs/operations/coverage.md measures what ships from the served English."""

from pathlib import Path

from wfj.dev import coverage


def test_nothing_to_translate_classes():
    why = coverage.nothing_to_translate("quest", "Kill 10 boars.", "<UNUSED> Test")
    assert why == "placeholder quest (never shown)"
    assert coverage.nothing_to_translate("quest", "Kill 10 boars.", "The Boar Hunt") is None
    assert coverage.nothing_to_translate("book", "Missing Text", None)
    assert coverage.nothing_to_translate("book", '<HTML><BODY><IMG src="x"/></BODY></HTML>', None)
    assert coverage.nothing_to_translate("book", "01101 10010", None)
    assert coverage.nothing_to_translate("book", "A page of prose.", None) is None


def test_the_committed_report_is_current(root: Path):
    # every data change re-runs `make coverage`: the committed doc matches the store (the date line aside)
    committed = (root / "docs" / "operations" / "coverage.md").read_text(encoding="utf-8")
    fresh = coverage.render(coverage.measure(root / "data"), "X")
    strip = lambda text: [ln for ln in text.splitlines() if not ln.startswith("> **Generated**")]  # noqa: E731
    assert strip(committed) == strip(fresh), "run `make coverage` and commit docs/operations/coverage.md"


def _store(tmp_path: Path):
    from wfj.io.jsonl_store import Store

    data = tmp_path / "data"
    (tmp_path / "pipeline").mkdir()
    for names in ("objective_names.txt", "area_names.txt"):
        (tmp_path / "pipeline" / names).write_text("", encoding="utf-8")
    english = [
        {"id": 133, "field": "description", "en": "Hurls a fireball.", "hash": "a", "src": "db2@1.60.1.70170"},
        # an aura nothing in a player's spellbook grants (a world buff): still served, still counted
        {"id": 7353, "field": "aura", "en": "Increased Spirit.", "hash": "b", "src": "db2@1.60.1.70170"},
        {"id": 9000, "field": "aura", "en": "Old English.", "hash": "c", "src": "wago@1.15.9.69722"},
    ]
    Store(data, english=True).save("spell", english)
    ja = {"id": 133, "field": "description", "ja": "火の玉を投げつけます。", "status": "unaligned"}
    Store(data).save("spell", [ja])
    return data, Store


def test_every_served_spell_line_counts_and_an_uncounted_one_is_a_gap(tmp_path: Path):
    data, _ = _store(tmp_path)
    m = coverage.measure(data)
    spell = m["types"]["spell"]
    assert spell["english"] == 3  # no list narrows the denominator
    assert spell["shipped"] == 1
    # the world-buff aura has no Japanese and no reason: a gap; the Classic Era line waits on a re-pull
    assert coverage.gaps(m) == {"spell": 1}


def test_a_stated_reason_is_not_a_gap(tmp_path: Path):
    data, store = _store(tmp_path)
    rejected = {"id": 7353, "field": "aura", "ja": "x", "status": "rejected", "reasons": ["ruled_reject"]}
    store(data).save("spell", [*store(data).load("spell"), rejected])
    assert coverage.gaps(coverage.measure(data)) == {}


def test_no_served_text_is_left_without_japanese_or_a_reason(root: Path):
    gaps = coverage.gaps(coverage.measure(root / "data"))
    assert not gaps, f"served lines with no Japanese and no stated reason: {gaps} (docs/operations/coverage.md)"


def test_make_coverage_refuses_an_inventory_from_another_build(capsys):
    assert coverage.main(["--build", "0.0.0.0"]) == 1
    assert "run `make served-columns`" in capsys.readouterr().out


def test_an_interface_line_off_the_key_list_needs_a_reason():
    keys, excluded = {"QUEST_LOG", "CustomizationChoice:1"}, {"CAA_SAMPLE_SPELLNAME"}
    assert coverage.ui_left_out("CAA_SAMPLE_SPELLNAME", keys, excluded) == coverage.UI_EXCLUDED
    assert coverage.ui_left_out("CustomizationChoice:54525", keys, excluded) == coverage.UI_FAMILY_LEFT_OUT
    # a GlobalString neither shipped nor excluded is a gap
    assert coverage.ui_left_out("NEW_STRING_THIS_BUILD", keys, excluded) is None


def test_a_spell_once_off_the_visible_list_ships_its_japanese(root: Path):
    # coverage counts every served spell line, so a buff no level-1 character sees (Campfire Nearby) ships its
    # Japanese in the generated data the addon loads
    shard = (root / "addon/WoWForeverJapanese/Data/Spell/Spell_1283.lua").read_text(encoding="utf-8")
    line = next(ln for ln in shard.splitlines() if "[1283391]" in ln)
    assert "キャンプファイア" in line
