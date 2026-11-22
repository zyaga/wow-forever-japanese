"""pipeline/name_surfaces.txt: every widget that holds a name has a line saying what the addon does with it
while Japanese names are on, and no game name is left without its Japanese."""

from __future__ import annotations

import re
from pathlib import Path

MARKS = {"japanese", "todo", "english"}
REASONS = {"player-typed", "text-box", "secret", "not-a-game-name"}
# a box the player types in: covered by the list's one line for every such box
_BOX = re.compile(r"(EditBox|SearchBox|searchBox|InputBox|NameEdit|NameBox|HexBox|GoldBox|Edit|Password)\"?$")
_NEVER = re.compile(r"NEVER_TOUCH\s*=\s*\{(.*?)\}", re.S)
_ENTRY = re.compile(r'"([^"]+)"')


def rows(root: Path) -> list[tuple[str, str, str, str]]:
    out = []
    for n, line in enumerate((root / "pipeline" / "name_surfaces.txt").read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        assert len(parts) >= 3, f"line {n}: needs a module, a widget and a mark"
        out.append((parts[0], parts[1], parts[2], parts[3] if len(parts) > 3 else ""))
    return out


def test_every_line_names_a_module_and_carries_a_known_mark(root):
    addon = root / "addon" / "WoWForeverJapanese"
    for module, widget, mark, _ in rows(root):
        assert module == "UI/*" or (addon / module).is_file(), f"{module}: no such module"
        assert widget.strip(), module
        word, _, reason = mark.partition(" ")
        assert word in MARKS, f"{module} {widget}: unknown mark {mark!r}"
        if word == "english":
            assert reason in REASONS, f"{module} {widget}: english needs a reason, one of {sorted(REASONS)}"
        else:
            assert reason == "", f"{module} {widget}: {word} takes no reason"


def test_every_module_that_keeps_a_name_widget_off_limits_has_a_line(root):
    listed = {module for module, _, _, _ in rows(root)}
    assert "UI/*" in listed  # the one line for every box the player types in
    missing = []
    for path in sorted((root / "addon" / "WoWForeverJapanese" / "UI").glob("*.lua")):
        found = _NEVER.search(path.read_text(encoding="utf-8"))
        entries = _ENTRY.findall(found.group(1)) if found else []
        named = [e for e in entries if not _BOX.search(e)]
        if named and f"UI/{path.name}" not in listed:
            missing.append(f"UI/{path.name}: {named[:3]}")
    assert missing == [], f"modules with name widgets and no line in pipeline/name_surfaces.txt: {missing}"


def test_no_game_name_is_left_without_its_japanese(root):
    todo = [f"{module}: {widget}" for module, widget, mark, _ in rows(root) if mark == "todo"]
    assert todo == [], f"{len(todo)} name widgets not shown in Japanese yet: {todo[:8]}"
