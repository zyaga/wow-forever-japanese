"""Surfaces the addon leaves as the client writes them, and paths it never runs code in, because its text or its code
would land on a path that ends in a protected call (ADR-058, ADR-069, ADR-088). Edit Mode lays out its windows by
measuring their text and then moves the action bars: no addon source may reach it. A menu sets each entry's click and
hover scripts in the same function that runs the entry's initializers, so an initializer of the addon leaves every
pick from that menu tainted: no addon source adds one, or registers a Menu.ModifyMenu callback (menus are written once
shown, UI/Menus). UI/TaintWatch only reads (issecurevariable), so its scan roots may name Edit Mode."""

import re
from pathlib import Path

from test_forever_only import _addon_lua

READ_ONLY = {"UI/TaintWatch.lua"}
EDIT_MODE = re.compile(
    r"EditModeManagerFrame|EditModeSystemSettingsDialog|EditModeSettingDropdownMixin|EditModeLayoutDialog"
    r"|EditModeImportLayout|EditModeUnsavedChangesDialog|MENU_EDIT_MODE_|EDIT_MODE_HELPTIPS_|\.Selection\b"
)
MENU_INITIALIZER = re.compile(r"[:.]AddInitializer\b|[:.]AddResetter\b|\bModifyMenu\b")


def _code(text: str) -> str:
    """The Lua without its comments (a comment may cite Blizzard's Edit Mode source); strings are kept, because a
    menu tag is a string."""
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", "", text, flags=re.S)
    return "\n".join(line.split("--", 1)[0] for line in text.splitlines())


def _hits(root: Path, pattern: re.Pattern[str]) -> list[str]:
    addon = root / "addon/WoWForeverJapanese"
    return [path.relative_to(addon).as_posix() for path, text in _addon_lua(root)
            if path.relative_to(addon).as_posix() not in READ_ONLY and pattern.search(_code(text))]


def test_no_source_touches_edit_mode(root):
    assert not _hits(root, EDIT_MODE)
    assert not (root / "addon/WoWForeverJapanese/UI/EditMode.lua").exists()


def test_no_source_adds_a_menu_initializer(root):
    assert not _hits(root, MENU_INITIALIZER)


def test_the_menu_initializer_pattern_catches_each_form():
    for sample in ("desc:AddInitializer(fn)", "d.AddResetter(d, fn)", "Menu.ModifyMenu(tag, fn)",
                   'Compat.declare(S, "m", { "Menu.ModifyMenu" })'):
        assert MENU_INITIALIZER.search(_code(sample)), sample
    assert not MENU_INITIALIZER.search(_code("-- the client runs desc:AddInitializer"))


# UpdateScrollChildRect called from addon code runs the scroll frame's range scripts under this addon's taint. On the
# quest log's details pane that is the likely start of the taint that reached QuestMapFrame_ShowQuestDetails, the map
# and the tracker, where Share and the map's quest pins were refused in combat (ADR-077). The book window and the tutorial popup size
# their own scroll child from the range, and neither scroll frame feeds the quest map or the tracker.
SCROLL_REFIT = re.compile(r"UpdateScrollChildRect")
SCROLL_REFIT_ALLOWED = {"UI/ItemText.lua", "UI/Tutorial.lua"}


def test_no_source_runs_a_scroll_frames_scripts(root):
    assert sorted(set(_hits(root, SCROLL_REFIT)) - SCROLL_REFIT_ALLOWED) == []


# ScrollBox:FullUpdate called from addon code runs the client's list code under this addon's taint. Gamepad navigation
# reads the list's extents before it selects the next row of a scroll list and refuses to act when it does not run
# secure; with the call in place a controller could not move between an NPC talk window's options, and without it it
# can (ADR-086). The description boxes that UI/Labels re-fits hold text only, with no row to move to.
# Only this one method is checked.
LIST_RELAYOUT = re.compile(r"\bFullUpdate\b")
LIST_RELAYOUT_ALLOWED = {"UI/Labels.lua"}


def test_no_source_calls_a_client_lists_full_update(root):
    assert sorted(set(_hits(root, LIST_RELAYOUT)) - LIST_RELAYOUT_ALLOWED) == []
