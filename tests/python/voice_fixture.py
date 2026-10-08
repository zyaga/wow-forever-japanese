"""A small world for the voice commands: a VMaNGOS database with the speaker and creature tables, a data
folder with shipped quest, gossip and book lines, and the client's creature display tables."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path

from wfj.core import voice
from wfj.io import creature_tables, tables_stamp
from wfj.io.jsonl_store import Store

SRC = {"source": "vmangos@13b49dc", "imported": "2026-10-06"}
HELLO, GREETING, CAPTURED = "Hello, traveller.", "A greeting.", "Captured line."
COND, OTHER_COND = "Cond text.", "Other cond."
SIGNED, UNSIGNED = "a" * 16, "b" * 16
COLLECTOR = "collector@1.60.1.70205"

# each row: entry, name, title, creature type, racial leader flag, gossip menu and first display
CREATURES = [
    (2079, "Conservator Ilthalaine", "", 7, 0, 0, 1001),
    (1992, "Tarindrella", "", 7, 0, 0, 1002),
    (3597, "Mardant Strongoak", "Druid Trainer", 7, 0, 7, 1001),
    (9000, "Old Dragon", "", 2, 1, 0, 1003),
    (6906, "Baelog", "", 7, 0, 0, 1001),
]


def make_speaker_db(path: Path) -> Path:
    """Quest 456 and 457 start at 2079; 456 ends at 2079, 457 at 1992; an object starts 458; 3597 has a
    gossip menu and 9000 a quest window greeting."""
    db = sqlite3.connect(path)
    for t in ("creature_questrelation", "creature_involvedrelation", "gameobject_questrelation"):
        db.execute(f"CREATE TABLE {t} (id INT, quest INT, patch_min INT, patch_max INT)")
    db.execute(
        "CREATE TABLE creature_template (entry INT, patch INT, name TEXT, subname TEXT, type INT, rank INT,"
        " racial_leader INT, gossip_menu_id INT, display_id1 INT, display_id2 INT, display_id3 INT,"
        " display_id4 INT)"
    )
    db.execute("CREATE TABLE gossip_menu (entry INT, text_id INT, script_id INT, condition_id INT)")
    db.execute("CREATE TABLE npc_text (ID INT, " + ", ".join(f"BroadcastTextID{i} INT" for i in range(8)) + ")")
    db.execute("CREATE TABLE broadcast_text (entry INT, male_text TEXT, female_text TEXT)")
    db.execute("CREATE TABLE quest_greeting (entry INT, type INT, content_default TEXT)")
    db.execute("CREATE TABLE creature_display_info_addon (display_id INT, build INT, gender INT)")
    for table, id_, quest in [
        ("creature_questrelation", 2079, 456), ("creature_questrelation", 2079, 457),
        ("creature_involvedrelation", 2079, 456), ("creature_involvedrelation", 1992, 457),
        ("gameobject_questrelation", 900, 458),
    ]:
        db.execute(f"INSERT INTO {table} VALUES (?, ?, 0, 10)", (id_, quest))
    db.executemany(
        "INSERT INTO creature_template VALUES (?, 0, ?, ?, ?, 0, ?, ?, ?, 0, 0, 0)", CREATURES
    )
    db.execute("INSERT INTO gossip_menu VALUES (7, 70, 0, 0)")
    db.execute("INSERT INTO npc_text VALUES (70, 700, 0, 0, 0, 0, 0, 0, 0)")
    db.execute("INSERT INTO broadcast_text VALUES (700, ?, ?)", (HELLO, HELLO))
    db.execute("INSERT INTO quest_greeting VALUES (9000, 0, ?)", (GREETING,))
    db.executemany(
        "INSERT INTO creature_display_info_addon VALUES (?, 0, ?)", [(1001, 0), (1002, 1), (1003, 2)]
    )
    db.commit()
    db.close()
    return path


def make_client(folder: Path) -> Path:
    """Display 1001 is a male night elf character model; the client knows no other display."""
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "CreatureDisplayInfo.csv").write_text("ID,ModelID,ExtendedDisplayInfoID,Gender\n1001,5,10,0\n")
    (folder / "CreatureDisplayInfoExtra.csv").write_text("ID,DisplayRaceID,DisplaySexID\n10,4,0\n")
    (folder / "ChrRaces.csv").write_text("ID,ClientFileString\n4,NightElf\n")
    tables_stamp.write(folder, creature_tables.TABLES, "db2@1.60.1.70245")
    return folder


def write_rows(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


def _ja(id_, field, ja, **kw):
    return {"id": id_, "field": field, "ja": ja, "status": "trusted", **kw}


def _en(id_, field, en, src="vmangos@13b49dc", **kw):
    return {"id": id_, "field": field, "en": en, "src": src, **kw}


def make_data(tmp_path: Path) -> Path:
    """A data folder: quests 456, 457 and 459 ship Japanese, 458 has English only; gossip, two book pages
    (one signed by Baelog) and Baelog cast to a voice."""
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    store, english = Store(data), Store(data, english=True)
    store.save("quest", [
        _ja(456, "description", "御機嫌よう、{name}。森を守ってくれ。"),
        _ja(456, "completion", "よくやった。"),
        _ja(456, "title", "題"),
        _ja(457, "description", "狼を$N1頭倒せ。"),
        _ja(457, "completion", "ありがとう。"),
        _ja(459, "description", "祠に祈れ。"),
    ])
    english.save("quest", [
        _en(457, "description", "Kill 7 wolves."),
        _en(458, "description", "Read the sign."),
    ])
    store.save("gossip", [
        _ja(voice.gossip_id(t), "text", ja)
        for t, ja in ((HELLO, "ようこそ、旅の方。"), (GREETING, "挨拶だ。"), (CAPTURED, "見たぞ。"),
                      (COND, "条件の文。"), (OTHER_COND, "別の条件の文。"))
    ])
    english.save("gossip", [
        _en(voice.gossip_id(HELLO), "text", HELLO, src=COLLECTOR, npcs=[3597]),
        _en(voice.gossip_id(CAPTURED), "text", CAPTURED, src=COLLECTOR, npcs=[6906]),
    ])
    english.save("book", [
        _en(15, "text", "Hello Morgan,$B$B-Baelog", hash=SIGNED),
        _en(16, "text", "No signature here at all.", hash=UNSIGNED),
    ])
    store.save("book", [
        _ja(SIGNED, "text", "モーガンへ。", english={"hash": SIGNED}),
        _ja(UNSIGNED, "text", "署名のない頁。", english={"hash": UNSIGNED}),
    ])
    english.save("unit", [_en(5555, "name", "Collector Seen", src=COLLECTOR)])
    write_rows(data / "voice" / "voices.jsonl", [
        {"creature": 6906, "voice": "m", "row": "male", "provenance": SRC},
    ])
    return data
