"""The Forever window sweep resolves, from the client's own TOCs, which Blizzard addons the `camelot`
game type loads and with which files. Every gating rule is pinned on a small TOC tree written the way a client_ui
extract names it (lowercased paths)."""

import io
from contextlib import redirect_stdout
from pathlib import Path

from wfj.dev import client_addons

TREE = {
    # [Family] / [Game] expansion, line gating, the XML include walk
    "blizzard_panels/blizzard_panels.toc": (
        "## Title: Panels\n"
        "Shared\\Always.lua\n"
        "[Family]\\Frame.xml\n"
        "[Game]\\Frame.lua [AllowLoadGameType camelot]\n"
        "Vanilla\\Old.lua [AllowLoadGameType vanilla, tbc]\n"
        "Mainline\\Retail.lua [AllowLoadGameType standard]\n"
        "Mainline\\Both.lua [AllowLoadGameType standard, camelot]\n"
        "[Family]\\NotHere.lua [AllowLoadGameType mainline] [ExcludeLoadGameType camelot]\n"
        "Glue\\Login.lua [AllowLoad glue]\n"
        "Shared\\Missing.lua\n"
        "[Game]\\Only.lua [AllowLoadGameType standard]\n"
    ),
    "blizzard_panels/shared/always.lua": "self:SetTitle(PANEL_TITLE);\n",
    "blizzard_panels/mainline/frame.xml": '<Ui><Script file="Frame.lua"/><Include file="..\\Shared\\Inc.xml"/></Ui>',
    "blizzard_panels/mainline/frame.lua": "GameTooltip_SetTitle(GameTooltip, NOT_A_WINDOW_TITLE);\n",
    "blizzard_panels/shared/inc.xml": "<Ui/>",
    "blizzard_panels/camelot/frame.lua": 'frame:SetTitle(format(OTHER, "x")) -- built\n',
    "blizzard_panels/vanilla/old.lua": "",
    "blizzard_panels/mainline/retail.lua": "",
    "blizzard_panels/mainline/both.lua": "",
    "blizzard_panels/mainline/nothere.lua": "",
    "blizzard_panels/glue/login.lua": "",
    "blizzard_panels/standard/only.lua": "window:SetTitle(RETAIL_TITLE)\n",
    # header states
    "blizzard_ondemand/blizzard_ondemand.toc": "## LoadOnDemand: 1\nMain.lua\n",
    "blizzard_ondemand/main.lua": "",
    "blizzard_login/blizzard_login.toc": "## AllowLoad: Glue\nMain.lua\n",
    "blizzard_login/main.lua": "",
    "blizzard_both/blizzard_both.toc": "## AllowLoad: Both\nMain.lua\n",
    "blizzard_both/main.lua": "",
    "blizzard_retail/blizzard_retail.toc": "## AllowLoadGameType: standard\n## LoadOnDemand: 1\nMain.lua\n",
    "blizzard_retail/main.lua": "",
    "blizzard_journal/blizzard_journal.toc": "## AllowLoadGameType: standard, classic\nMain.lua\n",
    "blizzard_journal/main.lua": "",
    "blizzard_excluded/blizzard_excluded.toc": "## ExcludeLoadGameType: camelot\nMain.lua\n",
    # the _Mainline TOC wins over the plain one
    "blizzard_two/blizzard_two.toc": "Plain.lua\n",
    "blizzard_two/blizzard_two_mainline.toc": "## LoadOnDemand: 1\nMainline.lua\n",
    "blizzard_two/plain.lua": "",
    "blizzard_two/mainline.lua": "",
}


def _tree(tmp_path: Path) -> Path:
    addons = tmp_path / "interface" / "addons"
    for rel, body in TREE.items():
        f = addons / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(body, encoding="utf-8")
    return addons


def _sweep(tmp_path: Path, **game) -> dict[str, tuple[str, list[str]]]:
    return {addon: (state, files) for addon, state, files in client_addons.sweep(_tree(tmp_path), **game)}


def test_header_states(tmp_path):
    rows = _sweep(tmp_path)
    assert rows["blizzard_panels"][0] == "login"
    assert rows["blizzard_ondemand"][0] == "lod"
    assert rows["blizzard_login"][0] == "glue"
    assert rows["blizzard_both"][0] == "login"  # AllowLoad: Both is not glue
    assert rows["blizzard_retail"][0] == "gated"  # standard does not include camelot
    assert rows["blizzard_journal"][0] == "gated"  # nor does classic
    assert rows["blizzard_excluded"][0] == "gated"
    assert all(files == [] for state, files in rows.values() if state in ("gated", "glue"))


def test_the_camelot_load_set(tmp_path):
    files = _sweep(tmp_path)["blizzard_panels"][1]
    assert files == [
        "blizzard_panels/shared/always.lua",
        "blizzard_panels/mainline/frame.xml",  # [Family] → Mainline
        "blizzard_panels/mainline/frame.lua",  # <Script file>, relative to the XML
        "blizzard_panels/shared/inc.xml",  # <Include file> with a ..\ segment
        "blizzard_panels/camelot/frame.lua",  # [Game] → Camelot
        "blizzard_panels/mainline/both.lua",  # a list naming camelot beside standard
    ]  # load order kept; vanilla, standard-only, excluded, glue and absent files never appear


def test_the_mainline_toc_is_preferred(tmp_path):
    assert _sweep(tmp_path)["blizzard_two"] == ("lod", ["blizzard_two/mainline.lua"])


def test_gate_matches_the_mainline_family_only():
    assert client_addons.gate([("AllowLoadGameType", "mainline")]) == "load"
    assert client_addons.gate([("AllowLoadGameType", "vanilla, Camelot")]) == "load"
    assert client_addons.gate([("AllowLoadGameType", "standard, classic, wowhack")]) == "gated"
    assert client_addons.gate([("ExcludeLoadGameType", "mainline")]) == "gated"
    assert client_addons.gate([("AllowLoad", "Game")]) == "load"
    assert client_addons.gate([("allowload", "GLUE")]) == "glue"
    assert client_addons.gate([]) == "load"


def test_titles_lists_window_set_title_sites_only(tmp_path):
    found = client_addons.titles(_tree(tmp_path))
    assert found == [
        ("blizzard_panels", "blizzard_panels/shared/always.lua", 1, "PANEL_TITLE"),
        ("blizzard_panels", "blizzard_panels/camelot/frame.lua", 1, 'format(OTHER, "x")'),
    ]  # a tooltip's SetTitle is not a window title


def test_main_output_and_usage(tmp_path):
    addons = _tree(tmp_path)
    out = io.StringIO()
    with redirect_stdout(out):
        assert client_addons.main([str(addons)]) == 0
    lines = out.getvalue().splitlines()
    assert lines[0].startswith("# GENERATED")
    assert "blizzard_panels login 6" in lines and "blizzard_retail gated 0" in lines
    assert lines[1:] == sorted(lines[1:])
    out = io.StringIO()
    with redirect_stdout(out):
        assert client_addons.main(["--files", str(addons), "Blizzard_Two"]) == 0
    assert out.getvalue().split() == ["blizzard_two/mainline.lua"]
    assert client_addons.main([]) == 2 and client_addons.main(["--files", str(addons)]) == 2


def test_header_states_for_the_standard_game_type(tmp_path):
    rows = _sweep(tmp_path, game="standard")
    assert rows["blizzard_retail"] == ("lod", ["blizzard_retail/main.lua"])
    assert rows["blizzard_journal"] == ("login", ["blizzard_journal/main.lua"])  # a list naming standard
    assert rows["blizzard_excluded"][0] == "login"  # only camelot is excluded
    assert rows["blizzard_login"][0] == "glue"
    assert rows["blizzard_two"] == ("lod", ["blizzard_two/mainline.lua"])  # standard is in the mainline family


def test_the_standard_load_set(tmp_path):
    files = _sweep(tmp_path, game="standard")["blizzard_panels"][1]
    assert files == [
        "blizzard_panels/shared/always.lua",
        "blizzard_panels/mainline/frame.xml",
        "blizzard_panels/mainline/frame.lua",
        "blizzard_panels/shared/inc.xml",
        "blizzard_panels/mainline/retail.lua",  # gated standard
        "blizzard_panels/mainline/both.lua",
        "blizzard_panels/mainline/nothere.lua",  # mainline, and only camelot is excluded
        "blizzard_panels/standard/only.lua",  # [Game] → Standard
    ]  # the camelot-only line and its Camelot folder never appear


def test_gate_takes_the_game_type():
    assert client_addons.gate([("AllowLoadGameType", "standard, classic, wowhack")], "standard") == "load"
    assert client_addons.gate([("AllowLoadGameType", "mainline")], "standard") == "load"
    assert client_addons.gate([("AllowLoadGameType", "vanilla, Camelot")], "standard") == "gated"
    assert client_addons.gate([("ExcludeLoadGameType", "camelot")], "standard") == "load"
    assert client_addons.gate([("ExcludeLoadGameType", "Standard")], "standard") == "gated"


def test_titles_follow_the_game_type(tmp_path):
    found = client_addons.titles(_tree(tmp_path), game="standard")
    assert found == [
        ("blizzard_panels", "blizzard_panels/shared/always.lua", 1, "PANEL_TITLE"),
        ("blizzard_panels", "blizzard_panels/standard/only.lua", 1, "RETAIL_TITLE"),
    ]


def test_main_takes_a_game_type(tmp_path):
    addons = _tree(tmp_path)
    out = io.StringIO()
    with redirect_stdout(out):
        assert client_addons.main(["--game", "standard", str(addons)]) == 0
    lines = out.getvalue().splitlines()
    assert lines[0].startswith("# GENERATED") and "standard" in lines[0] and "camelot" not in lines[0]
    assert "blizzard_panels login 8" in lines and "blizzard_retail lod 1" in lines
    out = io.StringIO()
    with redirect_stdout(out):
        assert client_addons.main(["--game", "standard", "--files", str(addons), "Blizzard_Retail"]) == 0
    assert out.getvalue().split() == ["blizzard_retail/main.lua"]
    assert client_addons.main(["--game", "wrath", str(addons)]) == 2  # a game type the tool has no rules for


def test_the_default_game_type_is_camelot(tmp_path):
    addons = _tree(tmp_path)
    assert client_addons.sweep(addons) == client_addons.sweep(addons, game="camelot")
    out = io.StringIO()
    with redirect_stdout(out):
        client_addons.main([str(addons)])
    assert out.getvalue().splitlines()[0] == (
        "# GENERATED by `python -m wfj.dev.client_addons` from the Forever (camelot) UI extract's TOCs."
    )


def test_main_refuses_a_folder_with_no_addons_and_a_flag_where_the_folder_goes(tmp_path, capsys):
    empty = tmp_path / "nothing"
    empty.mkdir()
    assert client_addons.main([str(empty)]) == 2  # a mistyped path must not print an empty list as if it were one
    assert client_addons.main([str(tmp_path / "absent")]) == 2
    addons = _tree(tmp_path)
    assert client_addons.main(["--titles", "--game", "standard", str(addons)]) == 2  # --game comes first
    captured = capsys.readouterr()
    assert captured.out == "" and "no Blizzard addon" in captured.err and "--game" in captured.err


def test_a_script_an_xml_file_names_from_the_addon_folder_is_followed(tmp_path):
    """The client finds a path an XML file names beside that file, and from the addon's folder when no file is
    there. A file in both places is the one beside the XML file."""
    addons = tmp_path / "interface" / "addons"
    tree = {
        "blizzard_item/blizzard_item.toc": "Mainline\\Template.xml\nMainline\\Both.xml\n",
        # named from the addon's folder: nothing is at mainline/mainline/template.lua
        "blizzard_item/mainline/template.xml": '<Ui><Script file="Mainline\\Template.lua"/></Ui>',
        "blizzard_item/mainline/template.lua": "",
        # in both places
        "blizzard_item/mainline/both.xml": '<Ui><Script file="Both.lua"/><Include file="Gone.xml"/></Ui>',
        "blizzard_item/mainline/both.lua": "",
        "blizzard_item/both.lua": "",
    }
    for rel, body in tree.items():
        f = addons / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(body, encoding="utf-8")
    files = {addon: found for addon, _state, found in client_addons.sweep(addons)}["blizzard_item"]
    assert files == [
        "blizzard_item/mainline/template.xml",
        "blizzard_item/mainline/template.lua",  # from the addon's folder
        "blizzard_item/mainline/both.xml",
        "blizzard_item/mainline/both.lua",  # beside the XML file, never the addon folder's copy
    ]  # a file that is in neither place is not in the load set
