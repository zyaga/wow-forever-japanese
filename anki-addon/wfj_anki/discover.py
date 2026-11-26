"""Finds the game's folders: where World of Warcraft is, which of its clients hold the addon's saved file, and
where
a word's screenshot and sound files sit. Paths in, paths out: nothing here opens a file."""

from __future__ import annotations

import string
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

GAME = "World of Warcraft"
SAVED_NAME = "WoWForeverJapanese.lua"
ADDON_PREFIX = "WoWForeverJapanese"
_NEVER = ':<>"[]'  # characters no screenshot or sound file of the game's has in its name


@dataclass(frozen=True)
class SavedFile:
    client: Path  # the client folder (`_forever_`): the Screenshots and Interface folders are in it
    path: Path


def default_roots(system: str, home: Path, volumes: Path = Path("/Volumes")) -> list[Path]:
    """Where the game usually is on this system (`system` as platform.system() names it)."""
    if system == "Darwin":
        roots = [Path("/Applications") / GAME, home / "Applications" / GAME]
        if volumes.is_dir():
            for drive in sorted(volumes.iterdir()):
                roots += [drive / GAME, drive / "Games" / GAME]
        return roots
    if system == "Windows":
        roots = []
        for letter in string.ascii_uppercase[2:]:
            drive = Path(f"{letter}:/")
            roots += [
                drive / "Program Files (x86)" / GAME,
                drive / "Program Files" / GAME,
                drive / GAME,
                drive / "Games" / GAME,
            ]
        return roots
    # a Windows game run through Wine: the two usual prefixes
    inside = Path("drive_c") / "Program Files (x86)" / GAME
    return [home / "Games" / "world-of-warcraft" / inside, home / ".wine" / inside]


def clients(root: Path) -> list[Path]:
    """The client folders under `root`: `root` itself when it is one, else its `_name_` folders."""
    if (root / "WTF").is_dir():
        return [root]
    try:
        inside = sorted(p for p in root.iterdir() if p.is_dir())
    except OSError:
        return []
    return [p for p in inside if p.name.startswith("_") and p.name.endswith("_") and (p / "WTF").is_dir()]


def game(client: Path) -> str:
    """Which game a client folder is, from its name: `_classic_era_` is "classic-era". Empty for a folder that
    is not named the way the launcher names them."""
    name = client.name
    if len(name) > 2 and name.startswith("_") and name.endswith("_"):
        return name.strip("_").replace("_", "-").lower()
    return ""


def saved_files(root: Path) -> list[SavedFile]:
    """Every account's copy of the addon's saved file, in every client under `root`."""
    found = []
    for client in clients(root):
        accounts = client / "WTF" / "Account"
        try:
            names = sorted(p for p in accounts.iterdir() if p.is_dir())
        except OSError:
            continue
        for account in names:
            path = account / "SavedVariables" / SAVED_NAME
            if path.is_file():
                found.append(SavedFile(client, path))
    return found


def find(folder: str, system: str, home: Path, volumes: Path = Path("/Volumes")) -> list[SavedFile]:
    """The saved files to read: under the folder the player chose, or under the first usual place that has
    any."""
    if folder.strip():
        return saved_files(Path(folder.strip()).expanduser())
    for root in default_roots(system, home, volumes):
        found = saved_files(root)
        if found:
            return found
    return []


def signature(files: list[SavedFile]) -> tuple[tuple[str, int, int], ...]:
    """What tells one state of the saved files from the next: each file's path, size and modified time."""
    out = []
    for f in files:
        try:
            stat = f.path.stat()
        except OSError:
            continue
        out.append((str(f.path), stat.st_size, stat.st_mtime_ns))
    return tuple(out)


def screenshot(client: Path, name: str) -> Path | None:
    """Where a screenshot of that file name is, or None for a name that is not a plain file name."""
    # a colon would name a drive on Windows, and so a file outside the folder; the others would break out of
    # the field's markup
    if not name or name in (".", "..") or any(c in name for c in _NEVER):
        return None
    if name != PurePosixPath(name.replace("\\", "/")).name:
        return None
    return client / "Screenshots" / name


def sound(client: Path, relative: str) -> Path | None:
    """Where a voice pack's sound file is, from `<pack folder>/Sound/<file>`; None for anything else, so a
    saved
    file can never name a file outside the addon's own pack folders."""
    parts = PurePosixPath(relative.replace("\\", "/")).parts
    if len(parts) != 3 or parts[1] != "Sound" or not parts[0].startswith(ADDON_PREFIX):
        return None
    if any(p in ("", ".", "..") or any(c in p for c in _NEVER) for p in parts):
        return None
    return client / "Interface" / "AddOns" / parts[0] / "Sound" / parts[2]
