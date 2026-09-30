"""Validate rule 7 leaves the keys in Core/UIStrings.lua's OWN table out of its one-Japanese-per-English
comparison, and reads that table from the addon (no second copy)."""

from pathlib import Path

from wfj.cmd import validate
from wfj.core.hashing import key
from wfj.core.model import english_line
from wfj.core.normalize import normalize_v1
from wfj.io.jsonl_store import Store

ADDON = Path(__file__).resolve().parents[2] / "addon" / "WoWForeverJapanese"
MACHINE = {"class": "machine", "model": "m", "critic": "c", "source": "draft-ui@2026-09-25", "imported": "2026-09-25"}


def _en(id_, text):
    return english_line(id_, "text", text, key(normalize_v1(text)), "wago@1.60.1.69913")


def _shipped(id_, text, ja):
    return {"id": id_, "field": "text", "ja": ja, "status": "trusted", "checks": [], "provenance": MACHINE,
            "english": {"hash": key(normalize_v1(text)), "src": "wago@1.60.1.69913"}}


def _stores(tmp_path, rows):
    d = tmp_path / "data"
    d.mkdir()
    Store(d, english=True).save("ui", [_en(k, en) for k, en, _ in rows])
    Store(d).save("ui", [_shipped(k, en, ja) for k, en, ja in rows])
    return Store(d), Store(d, english=True)


ROWS = [("INVTYPE_CLOAK", "Back", "背中"), ("AUCTION_HOUSE_BACK_BUTTON", "Back", "戻る")]


def test_an_owned_key_is_not_ambiguous(tmp_path):
    store, english = _stores(tmp_path, ROWS)
    assert validate.rule_ui(store, english, own={"AUCTION_HOUSE_BACK_BUTTON"}) == []


def test_two_keys_not_owned_are_still_ambiguous(tmp_path):
    store, english = _stores(tmp_path, [*ROWS, ("BACK", "Back", "戻る")])
    problems = validate.rule_ui(store, english, own={"AUCTION_HOUSE_BACK_BUTTON"})
    assert problems == ["ui ambiguous: BACK, INVTYPE_CLOAK share the English 'Back' with different Japanese"]
    assert validate.rule_ui(store, english) != []


def test_ui_own_reads_the_addon_table(tmp_path):
    core = tmp_path / "Core"
    core.mkdir()
    (core / "UIStrings.lua").write_text(
        "UIStrings.OWN = {\n  BACK = true, AVAILABLE = true, -- a comment\n  SCORE_DAMAGE_DONE = true,\n}\n",
        encoding="utf-8",
    )
    assert validate.ui_own(tmp_path) == {"BACK", "AVAILABLE", "SCORE_DAMAGE_DONE"}


def test_the_shipped_addon_has_an_own_table():
    assert isinstance(validate.ui_own(ADDON), set)


def test_every_owned_key_is_listed_and_asked_for_by_a_surface():
    """An owned key never answers an unrestricted match, so a surface must name it (an `only` list, a menu
    tag's keys or a tooltip owner's keys), else it would never show."""
    root = ADDON.parents[1]
    own = validate.ui_own(ADDON)
    listed = {ln.strip() for ln in (root / "pipeline/ui_keys.txt").read_text(encoding="utf-8").splitlines()
              if ln.strip() and not ln.startswith("#")}
    ui = "\n".join(p.read_text(encoding="utf-8") for p in sorted((ADDON / "UI").glob("*.lua")))
    for k in sorted(own):
        assert k in listed, k
        # LossOfControl builds its list from the family's suffixes ("PACIFYSILENCE")
        names = [k, k.removeprefix("LOSS_OF_CONTROL_DISPLAY_")]
        assert any(f'"{x}"' in ui for x in names), f"{k}: no surface names it"
    assert {"SCORE_DAMAGE_DONE", "AUCTION_HOUSE_BACK_BUTTON", "AVAILABLE", "LEAVE_VEHICLE", "BACK"} <= own


def test_no_dialog_shows_an_owned_key():
    """UI/Popups finds a dialog's key by its English (Index:keyOf): an owned key there would get the other key's
    Japanese. No StaticPopupDialogs definition names one (the `popups` inventory)."""
    root = ADDON.parents[1]
    popups = {ln.split()[1] for ln in (root / "pipeline/ui_inventory.txt").read_text(encoding="utf-8").splitlines()
              if ln.startswith("popups ")}
    assert popups and not popups & validate.ui_own(ADDON)
