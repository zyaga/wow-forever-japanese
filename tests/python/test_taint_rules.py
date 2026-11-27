"""Rules that keep the addon's writes off the client's own tables (docs/architecture/principles.md, "Taint").

A value the addon writes on a table the client's code reads makes that code run in the addon's name, and the
client then refuses protected actions (casting from the action bars, selling to a vendor) for the rest of the
session. The window test's `touch` part finds such a write in the running game; these checks find the known shapes
in the source, before a build reaches the game.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

ADDON = Path(__file__).resolve().parents[2] / "addon" / "WoWForeverJapanese"

# Fields the client's layout code reads off every child of a layout frame (blizzard_sharedxml/layoutframe.lua).
LAYOUT_FIELDS = ("ignoreInLayout", "layoutIndex", "expand", "align", "topPadding", "bottomPadding", "leftPadding",
                 "rightPadding", "fixedWidth", "fixedHeight", "minimumWidth", "minimumHeight")
_LAYOUT_WRITE = re.compile(r"\.(" + "|".join(LAYOUT_FIELDS) + r")\s*=[^=]")
# `x.Method = wrap(x.Method)`: a method of a frame replaced by the addon's own function. A post-hook
# (hooksecurefunc) is the way to follow a client call.
_METHOD_REPLACED = re.compile(r"^\s*(?!WFJ\b)([A-Za-z_][\w.]*)\.([A-Z]\w*)\s*=\s*[\w.:]+\([^\n]*\b\1\.\2\b")
# The global `_`: a write without `local` taints a name the client's own code uses as a throwaway.
_UNDERSCORE = re.compile(r"^\s*_\s*(,\s*[A-Za-z_]\w*\s*)*=[^=]")
# A frame's script called directly runs the client's handler in the addon's name.
_SCRIPT_CALLED = re.compile(r":GetScript\([^)]*\)\s*\(")
# Client calls that open, close or drive a window or the chat box. The addon may hook them; it never calls them.
DRIVERS = ("ShowUIPanel", "HideUIPanel", "ToggleUIPanel", "ToggleFrame", "CloseAllWindows", "CloseSpecialWindows",
           "StaticPopup_Show", "StaticPopup_Hide", "ChatFrame_OpenChat", "ChatEdit_ActivateChat",
           "ChatEdit_InsertLink", "ToggleCharacter", "ToggleSpellBook", "OpenAllBags", "ToggleAllBags",
           "CloseDropDownMenus", "ToggleDropDownMenu")
_DRIVER_CALLED = re.compile(r"(?<![\w.\"])(" + "|".join(DRIVERS) + r")\s*\(")


def code_lines(text: str):
    """(line number, code) for each line of Lua, comments left out."""
    for number, line in enumerate(text.split("\n"), 1):
        code = line.split("--", 1)[0]
        if code.strip():
            yield number, code


def problems(text: str) -> list[str]:
    out = []
    for number, code in code_lines(text):
        if _LAYOUT_WRITE.search(code):
            out.append(f"{number}: a field the client's layout code reads is written")
        if _METHOD_REPLACED.search(code):
            out.append(f"{number}: a frame's method is replaced")
        if _UNDERSCORE.search(code) and not code.lstrip().startswith("local"):
            out.append(f"{number}: the global _ is written")
        if _SCRIPT_CALLED.search(code):
            out.append(f"{number}: a frame's script is called directly")
        if _DRIVER_CALLED.search(code):
            out.append(f"{number}: a client call that drives a window or the chat box is called")
    return out


def addon_files() -> list[Path]:
    return sorted(p for folder in ("Core", "UI") for p in (ADDON / folder).glob("*.lua"))


def test_no_addon_file_breaks_a_taint_rule():
    found = [f"{path.relative_to(ADDON)}:{line}" for path in addon_files()
             for line in problems(path.read_text(encoding="utf-8"))]
    assert found == []


@pytest.mark.parametrize(("lua", "said"), [
    ("cover.ignoreInLayout = true", "layout code reads"),
    ("frame.layoutIndex = 3", "layout code reads"),
    ("frame.ShouldDisplayMessageType = Errors.wrapShould(frame.ShouldDisplayMessageType)", "method is replaced"),
    ("_ = frame:GetSize()", "global _ is written"),
    ("_, height = frame:GetSize()", "global _ is written"),
    ('button:GetScript("OnClick")(button, "LeftButton")', "script is called directly"),
    ("ShowUIPanel(CharacterFrame)", "drives a window"),
    ('if open then StaticPopup_Show("CONFIRM") end', "drives a window"),
])
def test_a_planted_violation_is_caught(lua, said):
    assert any(said in line for line in problems(lua))


@pytest.mark.parametrize("lua", [
    "local _, height = frame:GetSize()",
    "for _, name in ipairs(names) do end",
    "if cover.ignoreInLayout == true then end",
    "-- cover.ignoreInLayout = true was the cause",
    'hooksecurefunc("ShowUIPanel", onShow)',
    'local CALLED = { "ShowUIPanel", "HideUIPanel" }',
    "payload.names = joined(payload.names, extra)",
    "db.bytes = db.bytes - size",
    "WFJ.UIStrings = WFJ.UIStrings or {}",
])
def test_what_the_rules_allow_is_not_reported(lua):
    assert problems(lua) == []
