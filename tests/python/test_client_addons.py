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


def _sweep(tmp_path: Path) -> dict[str, tuple[str, list[str]]]:
    return {addon: (state, files) for addon, state, files in client_addons.sweep(_tree(tmp_path))}


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
