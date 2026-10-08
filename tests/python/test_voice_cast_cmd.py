"""`wfj voice profiles build|export|import`: the speaker profiles the casting reads, from the client tables,
the database and the casting pass's drafts."""

from __future__ import annotations

import datetime
import json
import sqlite3
from types import SimpleNamespace

import pytest
import voice_fixture as vf

from wfj.cmd import voice_cast
from wfj.core import voice

G = voice.gossip_key
RULED = {"source": "maintainer", "imported": "2026-10-01"}


@pytest.fixture
def world(tmp_path, monkeypatch):
    data = vf.make_data(tmp_path)
    vf.write_rows(data / "voice" / "speakers.jsonl", [
        {"key": "456-description", "speaker": 2079, "others": [1992], "provenance": vf.SRC},
        {"key": "456-completion", "speaker": 2079, "provenance": vf.SRC},
        {"key": "457-completion", "speaker": 5555, "provenance": vf.SRC},
        {"key": "459-description", "speaker": "narrator", "provenance": vf.SRC},
        {"key": G(voice.gossip_id(vf.HELLO)), "speaker": 3597, "provenance": vf.SRC},
        {"key": G(voice.gossip_id(vf.GREETING)), "speaker": 9000, "provenance": vf.SRC},
    ])
    vf.write_rows(data / "voice" / "profiles.jsonl", [
        {"creature": 2079, "age": "adult", "archetype": "none", "provenance": {"age": RULED, "archetype": RULED}},
    ])
    monkeypatch.setattr(voice_cast, "data_root", lambda: data)
    return SimpleNamespace(data=data, db=vf.make_speaker_db(tmp_path / "mangos.sqlite"),
                           client=vf.make_client(tmp_path / "client"), tmp=tmp_path)


def _profiles(world):
    return {r["creature"]: r for r in voice_cast._rows(world.data / "voice" / "profiles.jsonl")}


def _build(world):
    return voice_cast.run_profiles(["build", "--vmangos", str(world.db), "--commit", "sha",
                                    "--client", str(world.client)])


def test_speaking_names_every_creature_main_or_other(world):
    assert voice_cast.speaking(world.data) == {2079, 1992, 5555, 3597, 9000}
    assert voice_cast.speaking(world.tmp) == set()  # no speakers table yet


def test_build_takes_the_tables_and_keeps_a_ruling(world):
    rows, stats = voice_cast.build(world.data, world.db, "sha", world.client, "2026-10-08")
    by = {r["creature"]: r for r in rows}
    client, vm = "client@1.60.1.70245", "vmangos@sha"
    assert [r["creature"] for r in rows] == [1992, 2079, 3597, 5555, 9000]
    assert (by[2079]["race"], by[2079]["gender"], by[2079]["age"]) == ("nightelf", "male", "adult")
    assert by[2079]["provenance"]["race"] == {"source": client, "imported": "2026-10-08"}
    assert by[2079]["provenance"]["age"] == RULED
    assert by[1992]["gender"] == "female" and by[1992]["provenance"]["gender"]["source"] == vm
    assert by[5555] == {"creature": 5555, "provenance": {}}  # the database lacks it
    assert {f: by[9000][f] for f in ("race", "gender", "archetype", "role")} == {
        "race": "dragonkin", "gender": "none", "archetype": "dragon", "role": "leader"}
    assert stats == {
        "speakers": 5, "not in the database": 1, "race from the tables": 3, "gender from the tables": 4,
        "age from the tables": 0, "archetype from the tables": 1, "role from the tables": 1,
        "still need judgement": 4,
    }


def test_the_build_command_writes_profiles_and_prints_the_numbers(world, capsys):
    assert _build(world) == 0
    assert sorted(_profiles(world)) == [1992, 2079, 3597, 5555, 9000]
    out = capsys.readouterr().out.splitlines()
    assert out[0] == "voice profiles: 5 speakers → data/voice/profiles.jsonl"
    assert "voice profiles: not in the database: 1" in out and "voice profiles: still need judgement: 4" in out


def test_lines_by_speaker_are_longest_first_and_shipped_only(world):
    got = voice_cast._lines_by_speaker(world.data)
    assert got[2079] == ["御機嫌よう、{name}。森を守ってくれ。", "よくやった。"]
    assert got[1992] == ["御機嫌よう、{name}。森を守ってくれ。"]
    assert got[3597] == ["ようこそ、旅の方。"] and got[5555] == ["ありがとう。"]


def test_export_writes_parts_of_the_speakers_that_need_judgement(world):
    _build(world)
    out = world.tmp / "pass"
    assert voice_cast.export(world.data, world.db, out, 2) == 4
    assert sorted(p.name for p in out.iterdir()) == ["part-01.jsonl", "part-02.jsonl"]
    items = [json.loads(ln) for p in sorted(out.iterdir()) for ln in p.read_text().splitlines()]
    by = {i["creature"]: i for i in items}
    assert list(by) == [1992, 3597, 5555, 9000]  # 2079's age and archetype are ruled
    assert by[3597] == {"creature": 3597, "name": "Mardant Strongoak", "title": "Druid Trainer",
                        "type": "humanoid", "known": {"race": "nightelf", "gender": "male"},
                        "lines": ["ようこそ、旅の方。"]}
    assert (by[5555]["name"], by[5555]["type"], by[5555]["lines"]) == ("Collector Seen", "unknown", ["ありがとう。"])
    assert by[9000]["type"] == "dragonkin"
    assert by[9000]["known"] == {"race": "dragonkin", "gender": "none", "archetype": "dragon", "role": "leader"}


def test_the_export_command_says_how_many(world, capsys):
    _build(world)
    capsys.readouterr()
    out = world.tmp / "pass"
    assert voice_cast.run_profiles(["export", "--vmangos", str(world.db), "--out", str(out)]) == 0
    assert capsys.readouterr().out == f"voice profiles: 4 speakers to judge → {out}\n"
    assert [p.name for p in out.iterdir()] == ["part-01.jsonl"]


def _drafts(path, *rows):
    vf.write_rows(path, list(rows))
    return str(path)


def test_import_fills_ages_and_fails_while_one_is_owed(world, capsys):
    _build(world)
    capsys.readouterr()
    first = _drafts(world.tmp / "d1.jsonl",
                    {"creature": 1992, "age": "young", "reason": "speaks lightly"},
                    {"creature": 3597, "age": "elder", "reason": "a trainer of long years"},
                    {"creature": 5555, "age": "adult", "reason": "plain speech"},
                    {"creature": 42, "age": "adult", "reason": "r"})
    argv = ["import", "--drafts", first, "--model", "m1", "--batch", "casting-1"]
    assert voice_cast.run_profiles(argv) == 1
    out = capsys.readouterr().out.splitlines()
    assert out == ["voice profiles: draft for unknown creature 42",
                   "voice profiles: 1 problem(s); 1 speaker(s) still owed an age"]
    p = _profiles(world)
    today = datetime.date.today().isoformat()
    assert p[1992]["age"] == "young" and p[1992]["provenance"]["age"] == {
        "source": "machine", "model": "m1", "batch": "casting-1", "reason": "speaks lightly", "imported": today}
    second = _drafts(world.tmp / "d2.jsonl", {"creature": 9000, "age": "elder", "reason": "an old dragon"})
    assert voice_cast.run_profiles(["import", "--drafts", second, "--model", "m1", "--batch", "casting-2"]) == 0
    assert "0 speaker(s) still owed an age" in capsys.readouterr().out
    assert voice_cast.import_drafts(world.data, [], "m", "b", today) == []


def test_missing_client_tables_fail_with_how_to_make_them(world, capsys):
    (world.client / "ChrRaces.csv").unlink()
    assert _build(world) == 1
    err = capsys.readouterr().err
    assert err.startswith("voice profiles: ") and "ChrRaces.csv: run make tables-extract" in err


def test_a_database_without_creature_columns_fails(world, tmp_path, capsys):
    bad = vf.make_speaker_db(tmp_path / "bad.sqlite")
    db = sqlite3.connect(bad)
    db.execute("DROP TABLE creature_template")
    db.commit()
    db.close()
    argv = ["build", "--vmangos", str(bad), "--commit", "sha", "--client", str(world.client)]
    assert voice_cast.run_profiles(argv) == 1
    assert "no table 'creature_template'" in capsys.readouterr().err
