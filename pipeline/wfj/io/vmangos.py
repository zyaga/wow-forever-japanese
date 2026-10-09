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


def read_quest_levels(path: Path) -> dict[int, int]:
    """quest id → `QuestLevel` of its highest-patch row (the voice packs' level bands; the client's own quest
    cache wins where it has the quest). A level under 1 means none."""
    db = _connect(path, {"quest_template": ("entry", "patch", "QuestLevel")})
    try:
        rows = _query(db, path,
            "SELECT q.entry, q.QuestLevel FROM quest_template q"
            " JOIN (SELECT entry, MAX(patch) AS patch FROM quest_template GROUP BY entry) m"
            " ON q.entry = m.entry AND q.patch = m.patch",
        )
    finally:
        db.close()
    return {int(e): int(lv) for e, lv in rows if lv is not None and int(lv) >= 1}


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


# Who says a line, for voice over: the quest start / end relations, each creature's gossip menu greeting and
# its display's gender. Several `patch` rows of one entry are collapsed to the highest patch.
_SPEAKER_NEEDS = {
    "creature_questrelation": ("id", "quest"),
    "creature_involvedrelation": ("id", "quest"),
    "gameobject_questrelation": ("id", "quest"),
    "creature_template": ("entry", "patch", "gossip_menu_id", "display_id1"),
    "gossip_menu": ("entry", "text_id"),
    "npc_text": ("ID", *_NPC_TEXT_SLOTS),
    "broadcast_text": ("entry", "male_text", "female_text"),
    "quest_greeting": ("entry", "type", "content_default"),
    "creature_display_info_addon": ("display_id", "build", "gender"),
}


def _relations(db: sqlite3.Connection, path: Path, table: str, quests: set[int]) -> dict[int, list[int]]:
    ids = ",".join(str(int(q)) for q in sorted(quests)) or "NULL"
    sql = f"SELECT DISTINCT quest, id FROM {table} WHERE quest IN ({ids}) ORDER BY quest, id"
    rows = _query(db, path, sql)
    out: dict[int, list[int]] = {}
    for quest, id_ in rows:
        out.setdefault(int(quest), []).append(int(id_))
    return out


def read_quest_speakers(
    path: Path, quests: set[int]
) -> tuple[dict[int, list[int]], set[int], dict[int, list[int]]]:
    """For `quests`: (creature starters by quest, quests an object starts, creature enders by quest). Creature
    ids sorted and distinct (a relation repeated per patch range counts once)."""
    db = _connect(path, _SPEAKER_NEEDS)
    try:
        starters = _relations(db, path, "creature_questrelation", quests)
        objects = set(_relations(db, path, "gameobject_questrelation", quests))
        enders = _relations(db, path, "creature_involvedrelation", quests)
    finally:
        db.close()
    return starters, objects, enders


def read_creature_lines(path: Path, creatures: set[int]) -> list[tuple[int, str]]:
    """(creature id, English) for the gossip window greeting of each creature's gossip menu (every text of the
    menu, male and female wording) and its quest window greeting; sorted, distinct, empty text skipped."""
    db = _connect(path, _SPEAKER_NEEDS)
    ids = ",".join(str(int(c)) for c in sorted(creatures)) or "NULL"
    slots = " UNION ".join(f"SELECT ID, {c} AS b FROM npc_text WHERE {c} <> 0" for c in _NPC_TEXT_SLOTS)
    try:
        menus = _query(db, path,
            "SELECT DISTINCT t.entry, b.male_text, b.female_text FROM creature_template t"
            " JOIN (SELECT entry, MAX(patch) AS patch FROM creature_template GROUP BY entry) m"
            " ON t.entry = m.entry AND t.patch = m.patch"
            " JOIN gossip_menu g ON g.entry = t.gossip_menu_id AND t.gossip_menu_id <> 0"
            f" JOIN ({slots}) n ON n.ID = g.text_id"
            " JOIN broadcast_text b ON b.entry = n.b"
            f" WHERE t.entry IN ({ids})",
        )
        greetings = _query(db, path,
            f"SELECT entry, content_default FROM quest_greeting WHERE type = 0 AND entry IN ({ids})",
        )
    finally:
        db.close()
    out = {(int(c), t) for c, *texts in menus for t in texts if isinstance(t, str) and t.strip()}
    out |= {(int(c), t) for c, t in greetings if isinstance(t, str) and t.strip()}
    return sorted(out)


def read_creature_genders(path: Path, creatures: set[int]) -> dict[int, int]:
    """creature id → the gender of its first display at the highest patch (0 male, 1 female, 2 none), from the
    display's latest build row. A creature or display the database lacks is absent."""
    db = _connect(path, _SPEAKER_NEEDS)
    ids = ",".join(str(int(c)) for c in sorted(creatures)) or "NULL"
    try:
        rows = _query(db, path,
            "SELECT t.entry, a.gender FROM creature_template t"
            " JOIN (SELECT entry, MAX(patch) AS patch FROM creature_template GROUP BY entry) m"
            " ON t.entry = m.entry AND t.patch = m.patch"
            " JOIN creature_display_info_addon a ON a.display_id = t.display_id1"
            " JOIN (SELECT display_id, MAX(build) AS build FROM creature_display_info_addon"
            " GROUP BY display_id) d"
            " ON a.display_id = d.display_id AND a.build = d.build"
            f" WHERE t.entry IN ({ids})",
        )
    finally:
        db.close()
    return {int(c): int(g) for c, g in rows}


_CREATURE_NEEDS = {
    "creature_template": (
        "entry", "patch", "name", "subname", "type", "rank", "racial_leader",
        "display_id1", "display_id2", "display_id3", "display_id4",
    ),
}


def read_creatures(path: Path, creatures: set[int] | None = None) -> dict[int, dict[str, object]]:
    """creature id → its highest-patch row: name, subname (title), type (1 beast · 2 dragonkin · 3 demon ·
    4 elemental · 5 giant · 6 undead · 7 humanoid · 8 critter · 9 mechanical · 10 not specified), rank,
    racial_leader and its non-zero display ids in slot order. For voice casting only: the name and title are
    read to judge a speaker, never written to data/. `creatures` None reads every creature."""
    db = _connect(path, _CREATURE_NEEDS)
    where = ""
    if creatures is not None:
        where = " WHERE t.entry IN (" + (",".join(str(int(c)) for c in sorted(creatures)) or "NULL") + ")"
    try:
        rows = _query(db, path,
            "SELECT t.entry, t.name, t.subname, t.type, t.rank, t.racial_leader,"
            " t.display_id1, t.display_id2, t.display_id3, t.display_id4 FROM creature_template t"
            " JOIN (SELECT entry, MAX(patch) AS patch FROM creature_template GROUP BY entry) m"
            " ON t.entry = m.entry AND t.patch = m.patch" + where,
        )
    finally:
        db.close()
    return {
        int(e): {
            "name": name or "", "subname": sub or "", "type": int(typ or 0), "rank": int(rank or 0),
            "leader": bool(leader), "displays": [int(d) for d in ds if d],
        }
        for e, name, sub, typ, rank, leader, *ds in rows
    }


def read_gossip_creatures(path: Path) -> set[int]:
    """Every creature with a gossip menu or a quest window greeting: the speakers of NPC talk."""
    db = _connect(path, _SPEAKER_NEEDS)
    try:
        rows = _query(db, path,
            "SELECT entry FROM creature_template WHERE gossip_menu_id <> 0"
            " UNION SELECT entry FROM quest_greeting WHERE type = 0",
        )
    finally:
        db.close()
    return {int(r[0]) for r in rows}


def read_all_quest_speakers(path: Path) -> tuple[dict[int, list[int]], set[int], dict[int, list[int]]]:
    """read_quest_speakers over every quest the database relates to anyone."""
    db = _connect(path, _SPEAKER_NEEDS)
    try:
        quests = {
            int(r[0])
            for t in ("creature_questrelation", "gameobject_questrelation", "creature_involvedrelation")
            for r in _query(db, path, f"SELECT DISTINCT quest FROM {t}")
        }
    finally:
        db.close()
    return read_quest_speakers(path, quests)
