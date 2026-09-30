"""VMaNGOS world database (SQLite snapshot) → server-sent English.

Source: the `vmangos/core` release `db_latest`, asset `db-sqlite-<sha>.zip` → `sqlite-dump/mangos.sqlite`
(schema verified on `db-13b49dc`). Only text the client shows in a quest or gossip window is read:
- `quest_template` (one row per `entry` and content `patch`; the highest patch is the 1.12 text):
  `RequestItemsText` → the progress panel (`GetProgressText`), `OfferRewardText` → the turn-in panel
  (`GetRewardText`), checked on quests 5 and 6.
- gossip: `broadcast_text.male_text` / `female_text` referenced by `npc_text.BroadcastTextID0..7` (the NPC's
  greeting in the gossip window), `gossip_menu_option.option_text` (its option lines) and
  `quest_greeting.content_default` (the quest window's greeting prose).
- NPC speech: the rest of `broadcast_text` (the chat window's says / yells / emotes, boss emotes,
  bubbles), imported as gossip lines (the same hash keying).
- `page_text` (book pages: `entry`, `text`, `next_page`). The trainer greeting table is not read: Forever's
  trainer UI has no greeting.
Text is returned verbatim; normalization and hashing belong to the importer.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

QUEST_COLUMNS = {"RequestItemsText": "progress", "OfferRewardText": "completion"}
_NPC_TEXT_SLOTS = [f"BroadcastTextID{i}" for i in range(8)]
_NEEDS = {
    "quest_template": ("entry", "patch", *QUEST_COLUMNS),
    "npc_text": tuple(_NPC_TEXT_SLOTS),
    "broadcast_text": ("entry", "male_text", "female_text"),
    "gossip_menu_option": ("option_text",),
    "quest_greeting": ("content_default",),
}


class VmangosError(ValueError):
    """The file is not a VMaNGOS world database this reader understands."""


def _connect(path: Path, needs: dict[str, tuple[str, ...]] | None = None) -> sqlite3.Connection:
    """A read-only connection after checking the tables and columns the caller reads (default: the quest and
    gossip tables)."""
    if not path.is_file():
        raise VmangosError(f"{path}: not a file")
    try:
        db = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    except sqlite3.Error as e:
        raise VmangosError(f"{path.name}: {e}") from e
    try:
        for table, columns in (needs or _NEEDS).items():
            have = {row[1] for row in db.execute(f"PRAGMA table_info({table})")}
            if not have:
                raise VmangosError(f"{path.name}: no table {table!r} (not a VMaNGOS world database?)")
            missing = [c for c in columns if c not in have]
            if missing:
                raise VmangosError(f"{path.name}: {table} lacks column(s) {', '.join(missing)}")
    except sqlite3.DatabaseError as e:
        db.close()
        raise VmangosError(f"{path.name}: {e}") from e
    except VmangosError:
        db.close()
        raise
    return db


def _query(db: sqlite3.Connection, path: Path, sql: str) -> list[tuple]:
    try:
        return db.execute(sql).fetchall()
    except sqlite3.Error as e:
        raise VmangosError(f"{path.name}: {e}") from e


def read_quests(path: Path) -> list[tuple[int, str, str]]:
    """(quest id, field, English) for every quest whose highest-patch row has the text; empty text skipped.
    Sorted by (id, field order)."""
    db = _connect(path)
    try:
        rows = _query(db, path,
            "SELECT q.entry, q.RequestItemsText, q.OfferRewardText FROM quest_template q"
            " JOIN (SELECT entry, MAX(patch) AS patch FROM quest_template GROUP BY entry) m"
            " ON q.entry = m.entry AND q.patch = m.patch ORDER BY q.entry",
        )
    finally:
        db.close()
    out = []
    for entry, progress, completion in rows:
        for field, en in (("progress", progress), ("completion", completion)):
            if isinstance(en, str) and en.strip():
                out.append((int(entry), field, en))
    return out


def read_gossip(path: Path) -> list[str]:
    """The distinct non-empty gossip strings, sorted (the importer keys them)."""
    db = _connect(path)
    # slot value 0 = no text in that slot
    referenced = " UNION ".join(f"SELECT {c} FROM npc_text WHERE {c} <> 0" for c in _NPC_TEXT_SLOTS)
    try:
        rows = _query(db, path,
            f"SELECT male_text FROM broadcast_text WHERE entry IN ({referenced})"
            f" UNION SELECT female_text FROM broadcast_text WHERE entry IN ({referenced})"
            " UNION SELECT option_text FROM gossip_menu_option"
            " UNION SELECT content_default FROM quest_greeting",
        )
    finally:
        db.close()
    return sorted({t for (t,) in rows if isinstance(t, str) and t.strip()})


def read_speech(path: Path) -> list[str]:
    """NPC speech: every other `broadcast_text` row (says, yells, emotes, whispers, boss emotes the
    scripts and the core's boss scripts send as CHAT_MSG_MONSTER_* / RAID_BOSS_*), male and female text; the
    distinct non-empty strings, sorted. Keyed like gossip (the hash of the English): the client shows the
    server's text."""
    db = _connect(path)
    try:
        rows = _query(
            db, path, "SELECT male_text FROM broadcast_text UNION SELECT female_text FROM broadcast_text"
        )
    finally:
        db.close()
    return sorted({t for (t,) in rows if isinstance(t, str) and t.strip()})


def read_books(path: Path) -> list[tuple[int, str]]:
    """`page_text`: (page entry, English) for every non-empty page, sorted by entry. A book's pages
    chain through `next_page`; each page is its own line, keyed by its entry."""
    db = _connect(path, {"page_text": ("entry", "text", "next_page")})
    try:
        rows = _query(db, path, "SELECT entry, text FROM page_text ORDER BY entry")
    finally:
        db.close()
    return [(int(e), t) for e, t in rows if isinstance(t, str) and t.strip()]
