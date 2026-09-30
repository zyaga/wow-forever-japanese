import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "pipeline"))


@pytest.fixture(scope="session")
def root() -> Path:
    return ROOT


@pytest.fixture(scope="session")
def vectors(root: Path) -> list[dict]:
    with (root / "vectors" / "hash_vectors.jsonl").open(encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


@pytest.fixture(scope="session")
def plan_report(root: Path) -> tuple[dict[str, str], dict]:
    """The committed store's plan and its report, computed once: planning the whole store takes seconds, and
    every test that needs it asserts on the same committed data. Tests read the plan; the ones that write
    apply it to a copy of the addon folder."""
    from wfj.cmd import generate
    from wfj.io.jsonl_store import Store

    report: dict = {}
    planned = generate.plan(Store(root / "data"), generate.vectors_rows(root / "data"), report)
    return planned, report


@pytest.fixture(scope="session")
def planned(plan_report) -> dict[str, str]:
    return plan_report[0]


def make_vmangos_db(
    path: Path, quests=(), npc_texts=(), broadcasts=(), options=(), greetings=(), pages=()
) -> Path:
    """A minimal VMaNGOS world database: only the tables and columns `io/vmangos` reads.
    quests: (entry, patch, RequestItemsText, OfferRewardText); npc_texts: (ID, [BroadcastTextID0..]);
    broadcasts: (entry, male_text, female_text); options: option_text; greetings: content_default.
    pages: (entry, text, next_page)."""
    import sqlite3

    db = sqlite3.connect(path)
    db.execute("CREATE TABLE quest_template (entry INT, patch INT, Title TEXT, RequestItemsText TEXT, OfferRewardText TEXT)")
    db.execute("CREATE TABLE npc_text (ID INT, " + ", ".join(f"BroadcastTextID{i} INT" for i in range(8)) + ")")
    db.execute("CREATE TABLE broadcast_text (entry INT, male_text TEXT, female_text TEXT)")
    db.execute("CREATE TABLE gossip_menu_option (menu_id INT, option_text TEXT)")
    db.execute("CREATE TABLE quest_greeting (entry INT, content_default TEXT)")
    db.execute("CREATE TABLE page_text (entry INT, text TEXT, next_page INT)")
    db.executemany("INSERT INTO page_text VALUES (?, ?, ?)", pages)
    db.executemany("INSERT INTO quest_template VALUES (?, ?, '', ?, ?)", quests)
    for id_, slots in npc_texts:
        db.execute("INSERT INTO npc_text VALUES (?" + ", ?" * 8 + ")", (id_, *(list(slots) + [0] * 8)[:8]))
    db.executemany("INSERT INTO broadcast_text VALUES (?, ?, ?)", broadcasts)
    db.executemany("INSERT INTO gossip_menu_option VALUES (1, ?)", [(o,) for o in options])
    db.executemany("INSERT INTO quest_greeting VALUES (1, ?)", [(g,) for g in greetings])
    db.commit()
    db.close()
    return path


@pytest.fixture
def vmangos_db(tmp_path: Path):
    return lambda name="mangos.sqlite", **kw: make_vmangos_db(tmp_path / name, **kw)
