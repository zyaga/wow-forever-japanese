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
                                     voice.gossip_key(voice.gossip_id(vf.HELLO))]
    assert report["quest"] == ["459-description: nobody named, not voiced"]  # no row: never the narrator
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
    assert out[:3] == ["voice speakers: 5 lines, 3 creatures,", "voice speakers: 0 narrator lines",
                       "voice speakers: 0 lines with several speakers"]
    assert "voice speakers: quest: 459-description: nobody named, not voiced" in out
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


def _spoken(folder: Path, *lines: dict) -> Path:
    import gzip

    folder.mkdir(parents=True, exist_ok=True)
    path = folder / "corpus.json.gz"
    with gzip.open(path, "wt", encoding="utf-8") as f:
        json.dump({"schemaVersion": 1, "lines": list(lines), "npcs": []}, f)
    return path


def test_a_quest_line_is_spoken_by_the_creature_spoken_names_for_it(world, monkeypatch):
    """Spoken's corpus names who says each quest line it voices. Where it names a creature, that creature
    speaks the line here too, whatever the database or a capture says; an object, an item or no line at all
    leaves the line to the other sources."""
    _fake_cache(monkeypatch)
    cap = _captures(world.tmp / "fvo", {"event": "accept", "questID": 459, "npc": 1992})
    corpus = _spoken(
        world.tmp / "spoken",
        {"lineId": "q:457:accept", "source": "accept", "questId": 457, "npcId": 1992, "npcType": "creature"},
        {"lineId": "q:457:accept:f", "source": "accept", "questId": 457, "npcId": 1992, "npcType": "creature"},
        {"lineId": "q:457:complete", "source": "complete", "questId": 457, "npcId": 1992, "npcType": "creature"},
        {"lineId": "q:456:accept", "source": "accept", "questId": 456, "npcId": 50, "npcType": "gameobject"},
        {"lineId": "q:456:complete", "source": "complete", "questId": 456, "npcId": 60, "npcType": "item"},
        {"lineId": "q:459:accept", "source": "accept", "questId": 459, "npcId": 2079, "npcType": "creature"},
        {"lineId": "g:1", "source": "gossip", "questId": None, "npcId": 9000, "npcType": "creature"},
    )
    rows, _ = cmd.build_tables(
        world.data, world.db, "sha", "all", TODAY, Path("cache.wdb"), (cap, "abc"), (corpus, "0123456789abcdef")
    )
    by = _by_key(rows)
    assert by["457-description"] == (1992, "spoken@0123456")  # the database said 2079
    assert by["457-completion"] == (1992, "vmangos@sha")  # the same creature: nothing to change
    assert by["456-description"] == (2079, "vmangos@sha")  # Spoken names an object: the database's giver stays
    assert by["456-completion"] == (2079, "vmangos@sha")  # Spoken names an item
    assert by["459-description"] == (2079, "spoken@0123456")  # a capture said 1992; Spoken's creature wins
    without, _ = cmd.build_tables(world.data, world.db, "sha", "all", TODAY, Path("cache.wdb"), (cap, "abc"))
    assert _by_key(without)["457-description"] == (2079, "vmangos@sha")


def test_spoken_names_one_creature_per_quest_line_or_none(tmp_path):
    from wfj.io import spoken

    corpus = _spoken(
        tmp_path,
        {"source": "accept", "questId": 1, "npcId": 10, "npcType": "creature"},
        {"source": "progress", "questId": 1, "npcId": 11, "npcType": "creature"},
        {"source": "complete", "questId": 1, "npcId": 12, "npcType": "creature"},
        {"source": "followup", "questId": 1, "npcId": 13, "npcType": "creature"},
        {"source": "accept", "questId": 2, "npcId": 20, "npcType": "creature"},
        {"source": "accept", "questId": 2, "npcId": 21, "npcType": "creature"},  # two creatures: no answer
        {"source": "accept", "questId": 3, "npcId": 30, "npcType": "gameobject"},
        {"source": "gossip", "questId": None, "npcId": 40, "npcType": "creature"},
    )
    assert spoken.read_quest_speakers(corpus) == {(1, "description"): 10, (1, "progress"): 11, (1, "completion"): 12}


# ---- a quest line nobody names ----------------------------------------------------------------------------

ATT = """ns.ATT_QUESTS = {
[457]={1,1.0,1.0,"A",1,nil,{5555},nil,nil,nil,nil,nil,"Named by the database too"},
[459]={1,1.0,1.0,"A",1,nil,{6906},nil,nil,nil,nil,nil,"Only named here"},
}
"""
EXTRA = """ns.QUEST_ENDS = {
[459]={1,1.0,1.0,6906},
}
"""


def _dondata(folder: Path, att: str = ATT, extra: str = EXTRA) -> tuple[Path, Path, str]:
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "ATT_Quests.lua").write_text(att, encoding="utf-8")
    (folder / "Extra_Quests.lua").write_text(extra, encoding="utf-8")
    return folder / "ATT_Quests.lua", folder / "Extra_Quests.lua", "f7693f23ae6646551cb1eb062224a1304151a0aa"


def test_a_quest_line_nobody_names_has_no_row_and_is_reported(world, monkeypatch):
    _fake_cache(monkeypatch)
    rows, report = cmd.build_tables(world.data, world.db, "sha", "all", TODAY)
    assert "459-description" not in _by_key(rows)
    assert "459-description: nobody named, not voiced" in report["quest"]


def test_dondata_names_a_line_only_when_no_other_source_does(world, monkeypatch):
    _fake_cache(monkeypatch)
    rows, report = cmd.build_tables(
        world.data, world.db, "sha", "all", TODAY, dondata_files=_dondata(world.tmp / "dd"))
    by = _by_key(rows)
    assert by["459-description"] == (6906, "dondata@f7693f2")
    assert by["457-description"] == (2079, "vmangos@sha")  # the database names its giver: DonData's 5555 is unused
    assert "459-description: nobody named, not voiced" not in report["quest"]


def test_a_capture_or_spoken_names_a_line_ahead_of_dondata(world, monkeypatch):
    _fake_cache(monkeypatch)
    cap = _captures(world.tmp / "fvo", {"event": "accept", "questID": 459, "npc": 1992})
    rows, _ = cmd.build_tables(
        world.data, world.db, "sha", "all", TODAY, None, (cap, "abc"), None, _dondata(world.tmp / "dd"))
    assert _by_key(rows)["459-description"] == (1992, "forever-vo@abc")
    corpus = _spoken(
        world.tmp / "spoken",
        {"lineId": "q:459:accept", "source": "accept", "questId": 459, "npcId": 2079, "npcType": "creature"},
    )
    rows, _ = cmd.build_tables(
        world.data, world.db, "sha", "all", TODAY, None, None, (corpus, "0123456789abcdef"),
        _dondata(world.tmp / "dd2"))
    assert _by_key(rows)["459-description"] == (2079, "spoken@0123456")  # a line with no row before Spoken


def test_a_quest_dondata_says_an_item_starts_is_the_narrators(world, monkeypatch):
    _fake_cache(monkeypatch)
    att = ATT.replace('[459]={1,1.0,1.0,"A",1,nil,{6906},nil', '[459]={1,1.0,1.0,"A",1,nil,nil,"i"')
    rows, _ = cmd.build_tables(
        world.data, world.db, "sha", "all", TODAY, dondata_files=_dondata(world.tmp / "dd", att))
    assert _by_key(rows)["459-description"] == ("narrator", "dondata@f7693f2")


def test_who_a_players_quest_window_showed_wins_over_every_other_source(world, monkeypatch):
    """The Collector's quest NPCs (data/voice/quest-npcs.jsonl) are what the game itself showed: they name the
    speaker ahead of the database, Spoken, the captures and DonData, and name a line nobody else names."""
    _fake_cache(monkeypatch)
    seen = {"source": "collector@1.60.1.70959", "imported": "2026-11-21"}
    vf.write_rows(world.data / "voice" / "quest-npcs.jsonl", [
        {"quest": 457, "field": "description", "creature": 6906, "sex": "male", "provenance": seen},
        {"quest": 459, "field": "description", "creature": 3597, "provenance": seen},
        {"quest": 999, "field": "description", "creature": 1, "provenance": seen},  # no such shipped line
    ])
    corpus = _spoken(
        world.tmp / "spoken",
        {"lineId": "q:457:accept", "source": "accept", "questId": 457, "npcId": 1992, "npcType": "creature"},
    )
    rows, report = cmd.build_tables(
        world.data, world.db, "sha", "all", TODAY, None, None, (corpus, "0123456789abcdef"),
        _dondata(world.tmp / "dd"))
    by = _by_key(rows)
    assert by["457-description"] == (6906, "collector@1.60.1.70959")  # the database 2079, Spoken 1992
    # the speaker the other sources named is kept as another speaker of the line, not lost
    assert {r["key"]: r.get("others") for r in rows}["457-description"] == [1992]
    assert by["459-description"] == (3597, "collector@1.60.1.70959")  # DonData said 6906
    assert by["457-completion"] == (1992, "vmangos@sha")  # a line the Collector did not see is unchanged
    assert "999-description" not in by
    assert "459-description: nobody named, not voiced" not in report["quest"]


def test_another_wording_of_a_quest_offer_follows_the_offers_own_speaker(world, monkeypatch):
    """A quest's offer may have another wording for a class or race, keyed by its English. When the cache names
    no giver for it, it is said by whoever says the quest's own offer, after every source: never the narrator
    because the database lacks the quest."""
    g = voice.gossip_key
    key = g(voice.gossip_id(vf.COND))
    _fake_cache(monkeypatch, (459, ((1, 0, vf.COND),)))  # quest 459: no giver in the cache, none in the database
    rows, _ = cmd.build_tables(world.data, world.db, "sha", "all", TODAY, Path("cache.wdb"))
    assert key not in _by_key(rows)  # nobody names the quest's giver: not voiced
    rows, _ = cmd.build_tables(
        world.data, world.db, "sha", "all", TODAY, Path("cache.wdb"), dondata_files=_dondata(world.tmp / "dd"))
    assert _by_key(rows)[key] == (6906, "wdb@70245")  # DonData names the offer's NPC: the other wording is theirs
    att = ATT.replace('[459]={1,1.0,1.0,"A",1,nil,{6906},nil', '[459]={1,1.0,1.0,"A",1,nil,nil,"i"')
    rows, _ = cmd.build_tables(
        world.data, world.db, "sha", "all", TODAY, Path("cache.wdb"), dondata_files=_dondata(world.tmp / "dd2", att))
    assert _by_key(rows)[key] == ("narrator", "wdb@70245")  # an item starts it: the narrator's, as the offer is


def test_several_npcs_seen_for_one_quest_line_all_speak_it_and_a_known_main_speaker_stays(world, monkeypatch):
    _fake_cache(monkeypatch)
    seen = {"source": "collector@1.60.1.70959", "imported": "2026-11-21"}
    vf.write_rows(world.data / "voice" / "quest-npcs.jsonl", [
        {"quest": 457, "field": "description", "creature": 6906, "provenance": seen},
        {"quest": 457, "field": "description", "creature": 2079, "provenance": seen},  # the database's giver too
        {"quest": 459, "field": "description", "creature": 3597, "provenance": seen},
        {"quest": 459, "field": "description", "creature": 1992, "provenance": seen},
        {"quest": 456, "field": "description"},  # a row with no creature is skipped, not a crash
    ])
    rows, _ = cmd.build_tables(world.data, world.db, "sha", "all", TODAY)
    by = {r["key"]: (r["speaker"], r.get("others"), r["provenance"]["source"]) for r in rows}
    assert by["457-description"] == (2079, [6906], "collector@1.60.1.70959")  # the main speaker it had is one seen
    assert by["459-description"] == (1992, [3597], "collector@1.60.1.70959")  # nobody before: the lowest id leads
    assert by["456-description"] == (2079, None, "vmangos@sha")


def test_a_wording_several_quests_share_is_said_by_all_their_npcs_or_by_nobody(world, monkeypatch):
    """Two quests may show the same other wording of their offers. It is one line with one key, so it is voiced
    only when every quest that shows it has a named speaker: otherwise the window of the quest nobody names
    would play another quest's NPC."""
    g = voice.gossip_key
    key = g(voice.gossip_id(vf.COND))
    _fake_cache(monkeypatch, (456, ((1, 0, vf.COND),)), (459, ((1, 0, vf.COND),)))
    rows, _ = cmd.build_tables(world.data, world.db, "sha", "all", TODAY, Path("cache.wdb"))
    assert key not in _by_key(rows)  # quest 459's offer has nobody named
    rows, _ = cmd.build_tables(
        world.data, world.db, "sha", "all", TODAY, Path("cache.wdb"), dondata_files=_dondata(world.tmp / "dd"))
    by = {r["key"]: (r["speaker"], r.get("others")) for r in rows}
    assert by[key] == (2079, [6906])  # quest 456's giver leads; quest 459's is its other speaker
