"""`wfj voice speakers`: who speaks each line, built from the database, the collector, captures, the quest
cache and book signatures, and the verbs `wfj voice` hands to its other modules."""

from __future__ import annotations

import datetime
import json
import sqlite3
from pathlib import Path
from types import SimpleNamespace

import pytest
import voice_fixture as vf

from wfj.cmd import voice as cmd
from wfj.core import voice

TODAY = "2026-10-08"


@pytest.fixture
def world(tmp_path, monkeypatch):
    data = vf.make_data(tmp_path)
    db = vf.make_speaker_db(tmp_path / "mangos.sqlite")
    monkeypatch.setattr(cmd, "data_root", lambda: data)
    return SimpleNamespace(data=data, db=db, tmp=tmp_path)


def _captures(folder: Path, *entries: dict) -> Path:
    (folder / "captures").mkdir(parents=True)
    (folder / "captures" / "a.json").write_text(json.dumps({"origin": "a", "quests": list(entries)}))
    return folder


def _fake_cache(monkeypatch, *quests):
    cache = SimpleNamespace(build=70245, quests=[SimpleNamespace(id=q, conditional=c) for q, c in quests])
    monkeypatch.setattr(cmd.wdb, "read_quests", lambda _path: cache)


def _by_key(rows):
    return {r["key"]: (r["speaker"], r["provenance"]["source"]) for r in rows}


def test_the_whole_game_reads_quests_gossip_conditional_text_and_books(world, monkeypatch):
    _fake_cache(monkeypatch, (456, ((1, 0, vf.COND), (2, 777, vf.OTHER_COND), (3, 0, ""))), (999, ((1, 5, "x"),)))
    cap = _captures(world.tmp / "fvo", {"event": "accept", "questID": 459, "npc": 1992})
    rows, report = cmd.build_tables(world.data, world.db, "sha", "all", TODAY, Path("cache.wdb"), (cap, "abc"))
    g = voice.gossip_key
    assert _by_key(rows) == {
        "456-completion": (2079, "vmangos@sha"),
        "456-description": (2079, "vmangos@sha"),
        "457-completion": (1992, "vmangos@sha"),
        "457-description": (2079, "vmangos@sha"),
        "459-description": (1992, "forever-vo@abc"),  # the database lacks the quest; a capture names its giver
        f"b-{vf.SIGNED}": (6906, "book-signature@sha"),
        f"b-{vf.UNSIGNED}": ("narrator", "book@narrator"),
        g(voice.gossip_id(vf.GREETING)): (9000, "vmangos@sha"),
        g(voice.gossip_id(vf.HELLO)): (3597, vf.COLLECTOR),
        g(voice.gossip_id(vf.CAPTURED)): (6906, vf.COLLECTOR),  # only the collector heard it
        g(voice.gossip_id(vf.COND)): (2079, "wdb@70245"),  # no giver in the cache: the quest's starter
        g(voice.gossip_id(vf.OTHER_COND)): (777, "wdb@70245"),
    }
    assert [r["key"] for r in rows] == sorted(r["key"] for r in rows)
    assert all(r["provenance"]["imported"] == TODAY for r in rows)
    assert report["quest"] == [] and report["conflict"] == [] and report["missing"] == []
    assert report["conditional"] == sorted(
        [f"{g(voice.gossip_id(vf.COND))}: 2079", f"{g(voice.gossip_id(vf.OTHER_COND))}: 777"])


def test_a_scope_reads_only_its_quests_and_creatures_and_lists_english_with_no_japanese(world):
    rows, report = cmd.build_tables(world.data, world.db, "sha", "shadowglen", TODAY)
    assert sorted(_by_key(rows)) == ["456-completion", "456-description", "457-completion", "457-description",
                                     "459-description", voice.gossip_key(voice.gossip_id(vf.HELLO))]
    assert _by_key(rows)["459-description"] == ("narrator", "vmangos@sha")
    assert report["quest"] == ["459-description: no creature in the database, narrator"]
    assert report["missing"] == ["458-description"]  # English in scope, no Japanese shipped
    assert "conditional" not in report


def test_a_line_several_creatures_say_names_the_others(world):
    db = sqlite3.connect(world.db)
    db.execute("INSERT INTO creature_involvedrelation VALUES (2080, 456, 0, 10)")
    db.commit()
    db.close()
    rows, report = cmd.build_tables(world.data, world.db, "sha", "shadowglen", TODAY)
    row = next(r for r in rows if r["key"] == "456-completion")
    assert row["speaker"] == 2079 and row["others"] == [2080]
    assert list(row) == ["key", "speaker", "others", "provenance"]
    assert "456-completion: creatures [2079, 2080], took 2079" in report["quest"]


def test_book_readers_skip_pages_with_a_speaker_and_need_a_cast_signer(world):
    assert cmd.book_readers(world.data, world.db, set()) == {f"b-{vf.SIGNED}": 6906,
                                                             f"b-{vf.UNSIGNED}": voice.NARRATOR}
    assert cmd.book_readers(world.data, world.db, {f"b-{vf.UNSIGNED}"}) == {f"b-{vf.SIGNED}": 6906}
    vf.write_rows(world.data / "voice" / "voices.jsonl", [])  # Baelog no longer cast: the narrator reads it
    assert cmd.book_readers(world.data, world.db, set())[f"b-{vf.SIGNED}"] == voice.NARRATOR


def test_shipped_lines_holds_the_scopes_quest_fields_and_all_gossip():
    data = Path(__file__).resolve().parents[2] / "data"
    lines = cmd.shipped_lines(data, "shadowglen")
    assert "456-description" in lines and "456-title" not in lines
    assert not any(k[0].isdigit() and int(k.split("-")[0]) not in voice.SCOPES["shadowglen"]["quests"]
                   for k in lines)
    assert any(k.startswith("g-") for k in lines)


def test_rows_round_trip_and_a_missing_file_reads_as_nothing(tmp_path):
    rows = [{"key": "1-description", "speaker": "narrator", "provenance": vf.SRC}]
    cmd.write_rows(tmp_path / "a" / "x.jsonl", rows)
    assert cmd.read_rows(tmp_path / "a" / "x.jsonl") == rows
    assert cmd.read_rows(tmp_path / "absent.jsonl") == []
    assert cmd.voice_dir(tmp_path) == tmp_path / "voice"


def test_an_unchanged_row_keeps_its_date():
    old = [{"key": "a", "speaker": 1, "provenance": {"source": "s", "imported": "2000-01-01"}},
           {"key": "b", "speaker": 1, "provenance": {"source": "s", "imported": "2000-01-01"}}]
    new = [{"key": "a", "speaker": 1, "provenance": {"source": "s", "imported": TODAY}},
           {"key": "b", "speaker": 2, "provenance": {"source": "s", "imported": TODAY}},
           {"key": "c", "speaker": 3, "provenance": {"source": "s", "imported": TODAY}}]
    got = cmd._keep_date(new, old, "key")
    assert [r["provenance"]["imported"] for r in got] == ["2000-01-01", TODAY, TODAY]
    assert got[1]["speaker"] == 2


def test_the_speakers_command_writes_the_table_and_prints_its_report(world, capsys):
    today = datetime.date.today().isoformat()
    vf.write_rows(world.data / "voice" / "speakers.jsonl", [
        {"key": "456-description", "speaker": 2079, "provenance": {"source": "vmangos@sha",
                                                                   "imported": "2000-01-01"}},
    ])
    argv = ["speakers", "--vmangos", str(world.db), "--commit", "sha", "--scope", "shadowglen"]
    assert cmd.run(argv) == 0
    rows = cmd.read_rows(world.data / "voice" / "speakers.jsonl")
    dates = {r["key"]: r["provenance"]["imported"] for r in rows}
    assert dates["456-description"] == "2000-01-01" and dates["456-completion"] == today
    out = capsys.readouterr().out.splitlines()
    assert out[:3] == ["voice speakers: 6 lines, 3 creatures,", "voice speakers: 1 narrator lines",
                       "voice speakers: 0 lines with several speakers"]
    assert "voice speakers: quest: 459-description: no creature in the database, narrator" in out
    assert "voice speakers: missing: 458-description" in out


def test_the_speakers_command_reads_the_cache_and_captures_when_given(world, monkeypatch, capsys):
    _fake_cache(monkeypatch, (456, ((1, 0, vf.COND),)))
    cap = _captures(world.tmp / "fvo", {"event": "accept", "questID": 459, "npc": 1992})
    argv = ["speakers", "--vmangos", str(world.db), "--commit", "sha", "--wdb", "cache.wdb",
            "--forever-vo", str(cap), "--forever-vo-commit", "abc"]
    assert cmd.run(argv) == 0
    out = capsys.readouterr().out
    assert f"voice speakers: conditional: g-{voice.gossip_id(vf.COND)}: 2079" in out
    assert "voice speakers: 1 narrator lines" in out  # only the unsigned book page


def test_a_bad_database_fails_with_its_reason(world, capsys):
    assert cmd.run(["speakers", "--vmangos", str(world.tmp / "absent.sqlite"), "--commit", "x"]) == 1
    err = capsys.readouterr().err
    assert err.startswith("voice speakers: ") and "absent.sqlite: not a file" in err


@pytest.mark.parametrize(
    ("argv", "module", "attr", "passed"),
    [
        (["profiles", "build"], "voice_cast", "run_profiles", ["build"]),
        (["audition", "apply"], "voice_audition", "run", ["apply"]),
        (["plan", "--scope", "all"], "voice_make", "run", ["plan", "--scope", "all"]),
        (["levels"], "voice_store", "run", ["levels"]),
        (["pack"], "voice_ship", "run", ["pack"]),
    ],
)
def test_each_verb_goes_to_its_module(monkeypatch, argv, module, attr, passed):
    import importlib

    seen = []
    mod = importlib.import_module(f"wfj.cmd.{module}")
    monkeypatch.setattr(mod, attr, lambda a: seen.append(list(a)) or 7)
    assert cmd.run(argv) == 7
    assert seen == [passed]


def test_in_scope_all_keeps_every_row():
    rows = [{"key": "g-0123456789abcdef", "speaker": "narrator"}, {"key": "1-description", "speaker": 5}]
    assert cmd.in_scope(rows, "all") is rows
