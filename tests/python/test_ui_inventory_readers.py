"""The inventory's readers (dialog definitions, HelpTip callouts, Bindings XML) over a small addon tree, the accept
ruling that keeps a UI line in English letters, and the exclusion hygiene."""

import re
from pathlib import Path

from wfj.core.status import Scope, decide
from wfj.dev import ui_inventory

ROOT = Path(__file__).resolve().parents[2]
STRINGS = {
    "DELETE_ITEM": "Do you want to destroy %s?", "YES": "Yes", "NO": "No", "OKAY": "Okay",
    "INNER_TEXT": "An inserted frame's own text", "CONFIRM_BINDER": "Do you want to make %s your new home?",
    "LINK_TRANSMOG_CUSTOM_SET_HELPTIP": "Share this custom set by linking it in chat or online",
    "SOME_TITLE": "A title", "HIDDEN_TIP": "A retail callout",
    "BINDING_NAME_MOVEFORWARD": "Move Forward", "BINDING_HEADER_MOVEMENT": "Movement Keys",
    "BINDING_NAME_PINGATTACK": "Ping: Attack", "BINDING_HEADER_PING": "Ping System",
}


def _addon(root: Path, name: str, files: dict[str, str], lod: bool = False) -> None:
    d = root / name
    d.mkdir(parents=True)
    toc = ["## Interface: 11508"] + (["## LoadOnDemand: 1"] if lod else []) + list(files)
    (d / f"{name}.toc").write_text("\n".join(toc) + "\n", encoding="utf-8")
    for rel, text in files.items():
        (d / rel).write_text(text, encoding="utf-8")


def _tree(tmp_path: Path) -> Path:
    root = tmp_path / "addons"
    _addon(root, "blizzard_staticpopup_game", {"gamedialogdefs.lua": (
        'StaticPopupDialogs["DELETE_ITEM"] = {\n  text = DELETE_ITEM,\n  button1 = YES,\n  button2 = NO,\n'
        '  insertedFrame = { text = INNER_TEXT },\n  --button3 = HIDDEN_TIP,\n'
        '  OnAccept = function() DeleteCursorItem() end,\n};\n'
        'StaticPopupDialogs["BINDER"] = { text = "", button1 = OKAY };\n'
        'StaticPopupDialogs["BINDER"].text = CONFIRM_BINDER;\n'
    )})
    _addon(root, "blizzard_sharedxmlgame", {"dressupmodelframemixin.lua": (
        "local helpTipInfo = {\n  text = LINK_TRANSMOG_CUSTOM_SET_HELPTIP,\n"
        "  buttonStyle = HelpTip.ButtonStyle.Close,\n  targetPoint = HelpTip.Point.TopEdgeCenter,\n};\n"
        "local other = { text = SOME_TITLE }\nHelpTip:Show(self, helpTipInfo)\n"
    )})
    _addon(root, "blizzard_framexml", {"bindings_camelot.xml": (
        '<Bindings>\n<Binding name="MOVEFORWARD" category="BINDING_HEADER_MOVEMENT">x</Binding>\n</Bindings>\n'
    ), "bindings_standard.xml": '<Binding name="NOT_CAMELOT">x</Binding>\n'})
    _addon(root, "blizzard_pingui", {"bindings.xml": (
        '<Bindings><Binding name="PINGATTACK" header="PING">x</Binding></Bindings>\n'
    ), "pingui.lua": "-- x\n"})
    return root


def _index(root: Path):
    return ui_inventory.file_index(root)


def test_dialog_definitions_give_their_text_and_buttons_only(tmp_path):
    root = _tree(tmp_path)
    found = ui_inventory.popup_keys(root, STRINGS, _index(root))
    assert found == {"DELETE_ITEM", "YES", "NO", "OKAY", "CONFIRM_BINDER"}  # never the inserted frame's text


def test_helptip_scan_finds_a_callout_table_and_nothing_else(tmp_path, monkeypatch):
    root = _tree(tmp_path)
    monkeypatch.setattr(ui_inventory, "_hidden_addons", set)
    assert ui_inventory.helptip_keys(root, STRINGS, _index(root)) == {"LINK_TRANSMOG_CUSTOM_SET_HELPTIP"}
    monkeypatch.setattr(ui_inventory, "_hidden_addons", lambda: {"blizzard_sharedxmlgame"})
    assert ui_inventory.helptip_keys(root, STRINGS, _index(root)) == set()  # a no-content addon is skipped


def test_bindings_reader_takes_camelot_and_a_loaded_addons_bindings(tmp_path, monkeypatch):
    root = _tree(tmp_path)
    monkeypatch.setattr(ui_inventory, "_hidden_addons", set)
    found = ui_inventory.binding_keys(root, STRINGS, _index(root))
    assert found == {"BINDING_NAME_MOVEFORWARD", "BINDING_HEADER_MOVEMENT", "BINDING_NAME_PINGATTACK",
                     "BINDING_HEADER_PING"}


def test_the_dressing_room_callout_is_listed_and_shown_by_helptips():
    listed = (ROOT / "pipeline/ui_keys.txt").read_text(encoding="utf-8")
    assert re.search(r"^LINK_TRANSMOG_CUSTOM_SET_HELPTIP\b", listed, re.M)
    lua = (ROOT / "addon/WoWForeverJapanese/UI/HelpTips.lua").read_text(encoding="utf-8")
    assert '"LINK_TRANSMOG_CUSTOM_SET_HELPTIP"' in lua


def _ui_line(ja, ruling=None):
    line = {"id": "NEW_CAPS", "field": "text", "ja": ja, "status": "pending", "checks": [],
            "provenance": {"class": "machine", "model": "m", "source": "draft-ui@1", "imported": "2026-09-25"}}
    if ruling:
        line["ruling"] = ruling
    return line


def test_an_accept_ruling_keeps_a_ui_line_in_english_letters():
    scope = Scope(kind="ui", fields={"text": "NEW"}, raw={"text": "NEW"})
    assert decide(_ui_line("NEW"), scope, set(), None).reasons == ["not_japanese"]
    ruled = _ui_line("NEW", {"ruling": "accept", "by": "maintainer", "date": "2026-09-25"})
    assert decide(ruled, scope, set(), None).status == "trusted"


def test_no_exclusion_disposition_or_title_cites_the_missing_needs_file():
    for rel in ("pipeline/ui_exclusions.txt", "pipeline/forever_addon_dispositions.txt", "pipeline/forever_titles.txt"):
        assert "needs.md" not in (ROOT / rel).read_text(encoding="utf-8"), rel


def test_the_click_binding_composite_ships_as_its_wordless_english():
    # "%s-%s" has no word of its own, so its Japanese is the same text; check passes it as wordless
    import json

    line = next(json.loads(ln) for ln in (ROOT / "data/ui/ui-C.jsonl").read_text(encoding="utf-8").splitlines()
                if '"CLICK_BINDINGS_BINDING_TEXT_FORMAT"' in ln)
    assert line["ja"] == "%s-%s" and line["status"] == "trusted"


def test_every_countdown_unit_word_has_a_shipped_line():
    # UI/Popups puts a countdown's unit word in as its Japanese; a unit with no shipped line leaves the
    # whole countdown English (the busted spec stubs the rows, so it cannot see this)
    import json

    lua = (ROOT / "addon/WoWForeverJapanese/UI/Popups.lua").read_text(encoding="utf-8")
    units = re.findall(r'"([A-Z]+)"', re.search(r"local UNITS = \{([^}]*)\}", lua).group(1))
    assert units == ["SECONDS", "MINUTES"]
    lines = {}
    for path in (ROOT / "data/ui").glob("*.jsonl"):
        for ln in path.read_text(encoding="utf-8").splitlines():
            d = json.loads(ln)
            lines[d["id"]] = d
    for unit in units:
        assert lines[unit]["status"] == "trusted", unit
