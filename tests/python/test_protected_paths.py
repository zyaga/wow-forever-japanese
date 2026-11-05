"""Surfaces the addon leaves as the client writes them because its text or initializer would land on a path that ends
in a protected call (ADR-058, ADR-069). Edit Mode lays out its windows by measuring their text and then moves the
action bars; a unit right-click menu checks each entry's IsEnabled (CheckInteractDistance, protected in combat) in the
same pass as the element initializers. No addon source may reach either. UI/TaintWatch only reads (issecurevariable),
so its scan roots may name Edit Mode."""

import re
from pathlib import Path

ADDON = Path("addon/WoWForeverJapanese")
READ_ONLY = {"UI/TaintWatch.lua"}
EDIT_MODE = re.compile(
    r"EditModeManagerFrame|EditModeSystemSettingsDialog|EditModeSettingDropdownMixin|EditModeLayoutDialog"
    r"|EditModeImportLayout|EditModeUnsavedChangesDialog|MENU_EDIT_MODE_|CooldownViewer\.Selection|\.Selection\b"
)
UNIT_MENU = re.compile(r"MENU_UNIT_|WFJ\.MenusUnit")


def _sources(root: Path):
    for p in sorted((root / ADDON).rglob("*.lua")):
        rel = p.relative_to(root / ADDON).as_posix()
        if rel.startswith("Data/") or rel in READ_ONLY:
            continue
        yield rel, p.read_text(encoding="utf-8")


def _code(text: str) -> str:
    """The Lua without its comments: a comment may cite Blizzard's Edit Mode source."""
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", "", text, flags=re.S)
    return "\n".join(line.split("--", 1)[0] for line in text.splitlines())


def test_no_source_touches_edit_mode(root):
    hits = [rel for rel, text in _sources(root) if EDIT_MODE.search(_code(text))]
    assert not hits


def test_no_source_registers_a_unit_menu(root):
    hits = [rel for rel, text in _sources(root) if UNIT_MENU.search(_code(text))]
    assert not hits
    assert not (root / ADDON / "UI/MenusUnit.lua").exists()
    assert not (root / ADDON / "UI/EditMode.lua").exists()


def test_the_toc_loads_neither(root):
    toc = (root / ADDON / "WoWForeverJapanese.toc").read_text(encoding="utf-8")
    assert "UI\\EditMode.lua" not in toc and "UI\\MenusUnit.lua" not in toc
