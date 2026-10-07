"""Which voice pack holds each line, and what a pack's version is (ADR-062; the table is
pipeline/voice-packs.toml).

Pure: the inputs are the pack table, the pack keys, each quest's level and who speaks each line. A line's
pack depends only on that line's own key, its quest's level or its speakers' quests, never on which other
lines exist or their order, so adding lines never moves the ones already shipped.
"""

from __future__ import annotations

import datetime
import hashlib
import json
import re
import tomllib
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

PREFIX = "WoWForeverJapanese_Voice"  # Core/Voice accepts a pack only in a folder named so
MB = 1_000_000  # decimal: the stricter reading of the 500 MB upload limit
_FOLDER = re.compile(r"^WoWForeverJapanese_Voice[A-Za-z0-9_]*$")
_SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
_QUEST = re.compile(r"^(\d+)-(description|progress|completion)$")


@dataclass(frozen=True)
class Project:
    folder: str
    title: str
    slug: str
    project_id: int
    holds: str
    levels: tuple[int, int] | None = None  # None: the entry, or the pack that takes what has no band


@dataclass(frozen=True)
class Table:
    entry: Project
    packs: tuple[Project, ...]  # bands in level order, the pack with no band last
    cap_mb: int
    warn_mb: int

    @property
    def other(self) -> Project:
        return self.packs[-1]

    def by_folder(self, folder: str) -> Project:
        for p in self.packs:
            if p.folder == folder:
                return p
        raise KeyError(folder)


def _project(row: Mapping[str, Any], where: str) -> Project:
    for k in ("folder", "title", "slug", "holds"):
        if not isinstance(row.get(k), str) or not row[k]:
            raise ValueError(f"{where}: `{k}` is missing")
    if not _FOLDER.match(row["folder"]):
        raise ValueError(
            f"{where}: folder {row['folder']!r} must start with {PREFIX} and hold letters, digits, _"
        )
    if not _SLUG.match(row["slug"]):
        raise ValueError(f"{where}: slug {row['slug']!r} is not a CurseForge slug")
    pid = row.get("project_id", 0)
    if not isinstance(pid, int) or pid < 0:
        raise ValueError(f"{where}: project_id must be a whole number (0 until the project exists)")
    levels = row.get("levels")
    if levels is not None:
        if not (isinstance(levels, list) and len(levels) == 2 and all(isinstance(n, int) for n in levels)):
            raise ValueError(f"{where}: levels must be [lowest, highest]")
        if not 1 <= levels[0] <= levels[1]:
            raise ValueError(f"{where}: levels {levels} are not a band")
        levels = (levels[0], levels[1])
    return Project(row["folder"], row["title"], row["slug"], pid, row["holds"], levels)


def parse(raw: Mapping[str, Any]) -> Table:
    """The table, checked: one entry, bands that follow each other with no gap or overlap, then exactly one
    pack with no band, last; folders and slugs distinct."""
    entry = _project(raw.get("entry") or {}, "[entry]")
    if entry.levels is not None:
        raise ValueError("[entry]: the entry holds no audio and takes no levels")
    packs = tuple(_project(r, f"pack {n + 1}") for n, r in enumerate(raw.get("pack") or []))
    if len(packs) < 2:
        raise ValueError("the table needs at least one band and the pack with no band")
    if packs[-1].levels is not None or any(p.levels is None for p in packs[:-1]):
        raise ValueError("every pack but the last has a band; the last, with no band, takes the rest")
    for a, b in zip(packs[:-2], packs[1:-1], strict=True):
        assert a.levels and b.levels
        if b.levels[0] != a.levels[1] + 1:
            raise ValueError(
                f"{b.folder}: its band must start at {a.levels[1] + 1}, right after {a.folder}'s"
            )
    for what in ("folder", "slug"):
        seen = [getattr(p, what) for p in (entry, *packs)]
        dup = sorted({v for v in seen if seen.count(v) > 1})
        if dup:
            raise ValueError(f"the same {what} twice: {', '.join(dup)}")
    cap, warn = raw.get("cap_mb"), raw.get("warn_mb")
    if not (isinstance(cap, int) and isinstance(warn, int) and 0 < warn < cap):
        raise ValueError("cap_mb and warn_mb must be whole numbers with warn_mb under cap_mb")
    return Table(entry, packs, cap, warn)


def load(path: Path) -> Table:
    with path.open("rb") as f:
        return parse(tomllib.load(f))


def band(table: Table, level: int | None) -> Project:
    """The pack whose band holds `level`; no level, a level under 1 (the cache's 0) or past the last band: the
    pack with no band."""
    if level is not None:
        for p in table.packs[:-1]:
            assert p.levels
            if p.levels[0] <= level <= p.levels[1]:
                return p
    return table.other


def creature_quests(speakers: Iterable[Mapping[str, Any]]) -> dict[int, set[int]]:
    """creature → the quests it speaks a field of (it starts or ends them), from data/voice/speakers.jsonl."""
    out: dict[int, set[int]] = {}
    for r in speakers:
        m = _QUEST.match(r["key"])
        if not m:
            continue
        for c in (r["speaker"], *r.get("others", ())):
            if isinstance(c, int):
                out.setdefault(c, set()).add(int(m.group(1)))
    return out


def assign(
    table: Table,
    key: str,
    quest_level: Mapping[int, int],
    speakers: Mapping[str, Mapping[str, Any]],
    quests_of: Mapping[int, set[int]],
) -> Project:
    """The pack of one line key (an error line's key starts with `e-`)."""
    m = _QUEST.match(key)
    if m:
        return band(table, quest_level.get(int(m.group(1))))
    if key.startswith("g-"):
        row = speakers.get(key) or {}
        who = [c for c in (row.get("speaker"), *row.get("others", ())) if isinstance(c, int)]
        levels = [
            lv
            for c in who
            for q in quests_of.get(c, ())
            if (lv := quest_level.get(q)) is not None and lv >= 1
        ]
        found = [band(table, lv) for lv in sorted(levels)]
        return next((p for p in found if p is not table.other), table.packs[0])
    return table.other  # books and letters, error lines


def content_hash(rows: Iterable[Mapping[str, Any]], register: str, interface: str) -> str:
    """A pack's content: its files' audio records, its Register.lua and the client interface it is built for.
    The same lines in any order hash the same."""
    h = hashlib.sha256()
    for line in sorted(json.dumps(r, sort_keys=True, ensure_ascii=False) for r in rows):
        h.update(line.encode("utf-8") + b"\n")
    h.update(register.encode("utf-8"))
    h.update(interface.encode("utf-8"))
    return h.hexdigest()


def entry_hash(table: Table, interface: str) -> str:
    """The entry changes only when the set of packs (or the interface) does."""
    names = "\n".join(f"{p.folder} {p.slug}" for p in table.packs)
    return hashlib.sha256(f"{names}\n{interface}".encode()).hexdigest()


def version(day: datetime.date, digest: str) -> str:
    return f"{day:%Y.%m.%d}-{digest[:8]}"


_ASSET = re.compile(r"^(WoWForeverJapanese_Voice[A-Za-z0-9_]*)-(\d{4}\.\d{2}\.\d{2}-([0-9a-f]{8}))\.zip$")


def asset_name(folder: str, ver: str) -> str:
    return f"{folder}-{ver}.zip"


def released(asset_names: Iterable[str]) -> dict[str, str]:
    """folder → version, from a GitHub release's asset names (the bundle of everything is not one of them)."""
    out = {}
    for name in asset_names:
        m = _ASSET.match(name)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def changed(digest: str, previous: str | None) -> bool:
    """A pack changed when its content hash differs from the last release's version of it (or it is new)."""
    return previous is None or previous.rsplit("-", 1)[1] != digest[:8]
