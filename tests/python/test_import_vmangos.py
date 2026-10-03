"""`wfj import english vmangos`: quest progress / completion and gossip English (ADR-019)."""

from pathlib import Path

import pytest

from wfj.cmd.import_ import run
from wfj.core.hashing import key
from wfj.core.model import english_line, validate_line
from wfj.core.normalize import normalize_v1
from wfj.io.jsonl_store import Store

SRC = "vmangos@13b49dc"
QUESTS = [
    (33, 0, "Hey $N.  I'm getting hungry...", "You've been busy!$B$BTake your pick!"),
    (40, 0, "Old progress", "Old reward"),
    (40, 7, "", "Patched reward"),  # the highest patch is the 1.12 text; its empty progress is not written
    (41, 0, "   ", ""),  # blank text writes nothing
]
NPC_TEXTS = [(1, [10, 11]), (2, [11, 0])]
BROADCASTS = [
    (10, "Greetings, $c.", "Greetings, $c."),
    (11, "Well met, sir.", "Well met, madam."),
    (12, "Never shown in a gossip window.", ""),  # say/yell text: not referenced by npc_text
    (0, "Slot zero is no text.", ""),
]
OPTIONS = ["I want to browse your goods.", "", "Greetings,  $C."]  # the last normalizes like broadcast 10
GREETINGS = ["Hello there, $n.  Busy times."]


def _data(tmp_path: Path, monkeypatch) -> Path:
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    return data


def _db(vmangos_db, **kw):
    base = dict(quests=QUESTS, npc_texts=NPC_TEXTS, broadcasts=BROADCASTS, options=OPTIONS, greetings=GREETINGS)
    return vmangos_db(**{**base, **kw})


def _run(db: Path, commit="13b49dc") -> int:
    return run(["english", "vmangos", str(db), "--commit", commit])


def test_quest_progress_completion_lines(tmp_path, monkeypatch, vmangos_db):
    data = _data(tmp_path, monkeypatch)
    assert _run(_db(vmangos_db)) == 0
    lines = Store(data, english=True).load("quest")
    got = {(ln["id"], ln["field"]): ln for ln in lines}
    assert set(got) == {(33, "progress"), (33, "completion"), (40, "completion")}
    assert got[(33, "progress")]["en"] == "Hey $N.  I'm getting hungry..."  # verbatim
    assert got[(40, "completion")]["en"] == "Patched reward"
    for ln in lines:
        assert ln["src"] == SRC
        assert ln["hash"] == key(normalize_v1(ln["en"]))
        assert validate_line("quest", ln, english=True) == []


def test_gossip_lines_keyed_by_hash(tmp_path, monkeypatch, vmangos_db):
    data = _data(tmp_path, monkeypatch)
    assert _run(_db(vmangos_db)) == 0
    lines = Store(data, english=True).load("gossip")
    texts = {normalize_v1(ln["en"]) for ln in lines}
    assert texts == {
        "Greetings, {class}.", "Well met, sir.", "Well met, madam.", "I want to browse your goods.",
        "Hello there, {name}. Busy times.",
        # every other broadcast text is NPC speech (says, yells, emotes), imported with the gossip lines
        "Never shown in a gossip window.", "Slot zero is no text.",
    }
    for ln in lines:
        assert ln["id"] == ln["hash"] == key(normalize_v1(ln["en"]))
        assert ln["field"] == "text" and ln["src"] == SRC and "npcs" not in ln
        assert validate_line("gossip", ln, english=True) == []
    # two raw forms of one normalized text share a key: the first in sorted order keeps it
    greet = [ln for ln in lines if normalize_v1(ln["en"]) == "Greetings, {class}."]
    assert [g["en"] for g in greet] == ["Greetings,  $C."]


def test_merge_keeps_other_sources_and_gossip_npcs(tmp_path, monkeypatch, vmangos_db):
    data = _data(tmp_path, monkeypatch)
    store = Store(data, english=True)
    pf = english_line(33, "title", "Wolves Across the Border", key(normalize_v1("Wolves Across the Border")), "pfquest@7786596")
    col = english_line(33, "completion", "You've been busy!", key(normalize_v1("You've been busy!")), "collector@1.15.9.69722")
    k = key(normalize_v1("Well met, sir."))
    gossip = english_line(k, "text", "Well met, sir.", k, "collector@1.15.9.69722", npcs=[68, 295])
    store.save("quest", [pf, col])
    store.save("gossip", [gossip])
    assert _run(_db(vmangos_db)) == 0
    quest = {(ln["id"], ln["field"]): ln for ln in store.load("quest")}
    assert quest[(33, "title")] == pf
    assert quest[(33, "completion")] == col  # what a client recorded in game outranks VMaNGOS (ADR-053)
    kept = [ln for ln in store.load("gossip") if ln["id"] == k]
    assert kept == [gossip]  # a key already present keeps its line and its npcs


def test_replaces_earlier_vmangos_line(tmp_path, monkeypatch, vmangos_db):
    data = _data(tmp_path, monkeypatch)
    assert _run(_db(vmangos_db, name="a.sqlite")) == 0
    changed = [(33, 0, "Hey $N.", "A new reward.")]
    assert _run(_db(vmangos_db, name="b.sqlite", quests=changed), commit="deadbee") == 0
    quest = {(ln["id"], ln["field"]): ln for ln in Store(data, english=True).load("quest")}
    assert quest[(33, "completion")]["en"] == "A new reward."
    assert quest[(33, "completion")]["src"] == "vmangos@deadbee"
    assert (40, "completion") not in quest  # the source's lines are replaced as a set


def test_reimport_byte_noop(tmp_path, monkeypatch, vmangos_db):
    data = _data(tmp_path, monkeypatch)
    db = _db(vmangos_db)
    assert _run(db) == 0
    snap = {p: p.read_bytes() for p in sorted((data / "english").rglob("*.jsonl"))}
    assert _run(db) == 0
    assert {p: p.read_bytes() for p in sorted((data / "english").rglob("*.jsonl"))} == snap


def test_missing_table_errors_writes_nothing(tmp_path, monkeypatch, capsys):
    import sqlite3

    data = _data(tmp_path, monkeypatch)
    bad = tmp_path / "not-vmangos.sqlite"
    sqlite3.connect(bad).execute("CREATE TABLE something (x INT)").connection.commit()
    assert _run(bad) == 1
    err = capsys.readouterr().err.strip().splitlines()
    assert len(err) == 1 and "quest_template" in err[0]
    assert not (data / "english").exists() or not list((data / "english").rglob("*.jsonl"))
    assert _run(tmp_path / "absent.sqlite") == 1


def test_bad_commit_rejected(tmp_path, monkeypatch, vmangos_db, capsys):
    data = _data(tmp_path, monkeypatch)
    assert _run(_db(vmangos_db), commit="latest") == 1
    assert "--commit" in capsys.readouterr().err
    assert not (data / "english").exists() or not list((data / "english").rglob("*.jsonl"))


def test_reimport_keeps_npcs_a_collector_dump_added(tmp_path, monkeypatch, vmangos_db):
    """`import english collector` unions NPC ids onto a vmangos gossip line; a later vmangos
    re-import keeps them."""
    data = _data(tmp_path, monkeypatch)
    db = _db(vmangos_db)
    assert _run(db) == 0
    store = Store(data, english=True)
    k = key(normalize_v1("Well met, sir."))
    lines = store.load("gossip")
    for ln in lines:
        if ln["id"] == k:
            ln["npcs"] = [68, 295]  # what run_collector writes onto a same-hash line
    store.save("gossip", lines)
    assert _run(db) == 0
    got = next(ln for ln in store.load("gossip") if ln["id"] == k)
    assert got["npcs"] == [68, 295] and got["src"] == SRC


def test_empty_gossip_refused_and_nothing_written(tmp_path, monkeypatch, vmangos_db, capsys):
    """A database with no gossip rows never wipes the vmangos gossip lines, and a refused merge
    leaves the quest store untouched too."""
    data = _data(tmp_path, monkeypatch)
    assert _run(_db(vmangos_db, name="a.sqlite")) == 0
    snap = {p: p.read_bytes() for p in sorted((data / "english").rglob("*.jsonl"))}
    empty = _db(vmangos_db, name="b.sqlite", quests=[(33, 0, "Changed.", "Changed.")], npc_texts=[], options=[],
                greetings=[], broadcasts=[])  # no broadcast text either (it is NPC speech now)
    assert _run(empty) == 1
    assert "zero lines" in capsys.readouterr().err
    assert {p: p.read_bytes() for p in sorted((data / "english").rglob("*.jsonl"))} == snap


def test_gossip_hash_collision_is_an_error(tmp_path, monkeypatch, vmangos_db):
    """Two different normalized texts under one key are reported, never resolved silently."""
    import wfj.cmd.import_english as imp

    _data(tmp_path, monkeypatch)
    monkeypatch.setattr(imp, "hash_key", lambda norm: "0" * 16)
    assert _run(_db(vmangos_db)) == 1


def test_path_with_uri_characters(tmp_path, monkeypatch, vmangos_db):
    """A database path containing `#` or `?` opens."""
    data = _data(tmp_path, monkeypatch)
    (tmp_path / "odd#dir?").mkdir()
    db = _db(vmangos_db, name="odd#dir?/mangos.sqlite")
    assert _run(db) == 0
    assert Store(data, english=True).load("quest")


def test_books(tmp_path, monkeypatch, vmangos_db, capsys):
    """page_text as `book` (keyed by page entry). Trainer greetings are not read: no
    `trainer_greeting` English is written, and the snapshot needs no `npc_trainer_greeting` table."""
    data = _data(tmp_path, monkeypatch)
    pages = [(1, "Page one of the tome.", 2), (2, "Page two.", 0), (3, "   ", 0)]
    assert _run(_db(vmangos_db, pages=pages)) == 0
    out = capsys.readouterr().out
    eng = Store(data, english=True)
    books = {ln["id"]: ln for ln in eng.load("book")}
    assert {i: ln["en"] for i, ln in books.items()} == {1: "Page one of the tome.", 2: "Page two."}
    for ln in books.values():
        assert ln["src"] == SRC and ln["field"] == "text"
    assert not (data / "english" / "trainer_greeting").exists()
    assert "english book: 2 pages" in out and "trainer_greeting" not in out


@pytest.mark.parametrize("table", ["page_text"])
def test_a_snapshot_without_books_fails_before_any_write(tmp_path, monkeypatch, capsys, table):
    """Kept strict: every table is required, and a snapshot without books stops the whole import,
    naming the table, before anything is written."""
    import sqlite3

    from conftest import make_vmangos_db

    data = _data(tmp_path, monkeypatch)
    db = make_vmangos_db(tmp_path / "mangos.sqlite", quests=[(1, 0, "Progress", "Done")])
    sqlite3.connect(db).execute(f"DROP TABLE {table}").connection.commit()
    assert _run(db) == 1
    err = capsys.readouterr().err
    assert f"no table {table!r}" in err
    assert not (data / "english").exists() or not list((data / "english").rglob("*.jsonl"))
