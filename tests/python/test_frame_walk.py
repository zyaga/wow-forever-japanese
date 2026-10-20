"""A frame's regions and children are listed only through UI/Frames.lua.

GetRegions / GetChildren return every part as a separate value, and past the Lua
stack's limit the client raises "stack overflow" inside the call. UI/Frames.lua
counts first and guards the call; any other direct call can overflow again.
"""

import re

CALL = re.compile(r":(GetRegions|GetChildren)\(\)")


def _code(line):
    """The line without its trailing Lua comment (no string in the addon holds '--' before a call)."""
    return line.split("--", 1)[0]


def test_only_frames_lists_regions_and_children(root):
    addon = root / "addon" / "WoWForeverJapanese"
    hits = []
    for path in sorted(addon.rglob("*.lua")):
        rel = path.relative_to(addon).as_posix()
        if rel == "UI/Frames.lua" or rel.startswith("Data/"):
            continue
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if CALL.search(_code(line)):
                hits.append(f"{rel}:{n}")
    assert hits == []
