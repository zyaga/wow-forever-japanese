"""Surfaces the addon leaves as the client writes them because its text or initializer would land on a path that ends
in a protected call (ADR-058, ADR-069). Edit Mode lays out its windows by measuring their text and then moves the
action bars; a unit right-click menu checks each entry's IsEnabled (CheckInteractDistance, protected in combat) in the
same pass as the element initializers. No addon source may reach either. UI/TaintWatch only reads (issecurevariable),
so its scan roots may name Edit Mode."""

import re
from pathlib import Path

from test_forever_only import _addon_lua

READ_ONLY = {"UI/TaintWatch.lua"}
EDIT_MODE = re.compile(
    r"EditModeManagerFrame|EditModeSystemSettingsDialog|EditModeSettingDropdownMixin|EditModeLayoutDialog"
    r"|EditModeImportLayout|EditModeUnsavedChangesDialog|MENU_EDIT_MODE_|EDIT_MODE_HELPTIPS_|\.Selection\b"
)
UNIT_MENU = re.compile(r"MENU_UNIT_|WFJ\.MenusUnit")


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


def test_no_source_registers_a_unit_menu(root):
    assert not _hits(root, UNIT_MENU)
    assert not (root / "addon/WoWForeverJapanese/UI/MenusUnit.lua").exists()


# UpdateScrollChildRect called from addon code runs the scroll frame's range scripts under this addon's taint. On the
# quest log's details pane that is the likely start of the taint that reached QuestMapFrame_ShowQuestDetails, the map
# and the tracker, where Share and the map's quest pins were refused in combat (ADR-077). The book window and the tutorial popup size
# their own scroll child from the range, and neither scroll frame feeds the quest map or the tracker.
SCROLL_REFIT = re.compile(r"UpdateScrollChildRect")
SCROLL_REFIT_ALLOWED = {"UI/ItemText.lua", "UI/Tutorial.lua"}


def test_no_source_runs_a_scroll_frames_scripts(root):
    assert sorted(set(_hits(root, SCROLL_REFIT)) - SCROLL_REFIT_ALLOWED) == []
