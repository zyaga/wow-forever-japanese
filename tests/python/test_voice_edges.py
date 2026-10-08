"""The voice pipeline's edges: refused inputs and failure paths of the engine and upload clients, the readers,
the profile and roster checks, the pack table and the level table."""

from __future__ import annotations

import io
import json
import sqlite3
import subprocess
import urllib.error
from types import SimpleNamespace

import pytest
from test_voice_ship import _raw

from wfj import cli
from wfj.cmd import voice_ship, voice_store
from wfj.core import casting, voice
from wfj.core import voice_packs as vp
from wfj.emit import voice_pack
from wfj.io import aivis, curseforge, forever_vo, vmangos

# ---- the engine client -------------------------------------------------------------------------------------


def _engine(answers):
    """An engine whose HTTP calls answer from `answers` ({path: bytes}) and record what was asked."""
    e = aivis.Engine("http://127.0.0.1:1/")
    e.asked = []

    def call(method, path, params=None, body=None):
        e.asked.append((method, path, params, body))
        return answers[path]

    e._call = call
    return e


def test_the_engine_refuses_odd_answers():
    assert aivis.Engine("http://x/").url == "http://x"
    with pytest.raises(aivis.EngineError, match="/version: unexpected answer ''"):
        _engine({"/version": b'""'}).version()
    with pytest.raises(aivis.EngineError, match=r"/synthesis: not a WAV file \(3 bytes\)"):
        _engine({"/audio_query": b"{}", "/synthesis": b"MP3"}).synthesize("あ", 1, 0.9)


def test_the_engine_finds_a_styles_model_and_sets_the_pace_on_the_query():
    speakers = json.dumps([{"speaker_uuid": "u1", "styles": [{"id": 1}]},
                           {"speaker_uuid": "u2", "styles": [{"id": 2}, {"id": 3}]}]).encode()
    e = _engine({"/speakers": speakers, "/audio_query": b'{"accent_phrases": []}', "/synthesis": b"RIFFxx"})
    assert e.model_of(3) == "u2"
    with pytest.raises(aivis.EngineError, match="style 9 is not installed"):
        e.model_of(9)
    assert e.synthesize("あ", 3, 0.8, -0.05, 1.1) == b"RIFFxx"
    assert e.asked[-1] == ("POST", "/synthesis", {"speaker": 3},
                           {"accent_phrases": [], "speedScale": 0.8, "pitchScale": -0.05, "intonationScale": 1.1})


def test_an_engine_that_does_not_answer_is_an_engine_error(monkeypatch):
    def refuse(req, timeout):
        raise urllib.error.URLError("connection refused")

    monkeypatch.setattr(aivis.urllib.request, "urlopen", refuse)
    with pytest.raises(aivis.EngineError, match="GET /version: .*connection refused"):
        aivis.Engine("http://127.0.0.1:1").version()


# ---- the upload client -------------------------------------------------------------------------------------


class _Answer:
    def __init__(self, raw: bytes):
        self.raw = raw

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def read(self):
        return self.raw


def _http_error(code, body=b""):
    return urllib.error.HTTPError("https://x", code, "err", {}, io.BytesIO(body))


def test_game_versions_send_the_token_and_name_http_failures(monkeypatch):
    seen = []

    def ok(req, timeout):
        seen.append((req.full_url, req.get_header("X-api-token")))
        return io.BytesIO(b'[{"id": 1}]')

    monkeypatch.setattr(curseforge.urllib.request, "urlopen", ok)
    assert curseforge.game_versions("t0k") == [{"id": 1}]
    assert seen == [(f"{curseforge.SITE}/api/game/wow/versions", "t0k")]
    for exc, message in ((_http_error(403), "HTTP 403"), (urllib.error.URLError("no route"), "no route")):
        def fail(req, timeout, exc=exc):
            raise exc

        monkeypatch.setattr(curseforge.urllib.request, "urlopen", fail)
        with pytest.raises(curseforge.CurseForgeError, match=message):
            curseforge.game_versions("t0k")


def test_upload_streams_multipart_and_returns_the_file_id(monkeypatch, tmp_path):
    z = tmp_path / "pack.zip"
    z.write_bytes(b"PK" * 10)
    sent = {}

    def ok(req, timeout):
        body = b"".join(req.data)
        sent.update(url=req.full_url, length=int(req.get_header("Content-length")), body=body,
                    kind=req.get_header("Content-type"))
        return _Answer(b'{"id": 42}')

    monkeypatch.setattr(curseforge, "CHUNK", 4)
    monkeypatch.setattr(curseforge.urllib.request, "urlopen", ok)
    assert curseforge.upload(7, z, {"displayName": "x"}, "t0k") == 42
    assert sent["url"] == f"{curseforge.SITE}/api/projects/7/upload-file"
    assert sent["length"] == len(sent["body"]) and b"PK" * 10 in sent["body"]
    assert b'name="metadata"\r\n\r\n{"displayName": "x"}' in sent["body"]
    assert sent["kind"].startswith("multipart/form-data; boundary=wfj")
    monkeypatch.setattr(curseforge.urllib.request, "urlopen", lambda req, timeout: _Answer(b"uploaded"))
    assert curseforge.upload(7, z, {}, "t0k") == 0  # an answer with no id still means it went up


def test_a_refused_upload_names_the_status_and_the_refused_relation(monkeypatch, tmp_path):
    z = tmp_path / "pack.zip"
    z.write_bytes(b"PK")
    body = (b'{"errorCode":1018,"errorMessage":"Invalid slug in project relations: \\u0027voice-a\\u0027 does not'
            b' exist, is not accessible, or belongs to an unrelated root category."}')

    def refuse(req, timeout):
        raise _http_error(400, body)

    monkeypatch.setattr(curseforge.urllib.request, "urlopen", refuse)
    with pytest.raises(curseforge.CurseForgeError, match="upload of pack.zip to project 7: HTTP 400") as e:
        curseforge.upload(7, z, {}, "t0k")
    assert e.value.refused == "voice-a"

    def unreachable(req, timeout):
        raise urllib.error.URLError("timed out")

    monkeypatch.setattr(curseforge.urllib.request, "urlopen", unreachable)
    with pytest.raises(curseforge.CurseForgeError, match="upload of pack.zip to project 7: timed out"):
        curseforge.upload(7, z, {}, "t0k")


# ---- the readers -------------------------------------------------------------------------------------------


def test_the_database_reader_refuses_what_it_cannot_read(tmp_path):
    junk = tmp_path / "junk.sqlite"
    junk.write_bytes(b"this is not a database at all, just bytes" * 40)
    with pytest.raises(vmangos.VmangosError, match="junk.sqlite: "):
        vmangos.read_quest_levels(junk)
    db = tmp_path / "m.sqlite"
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE quest_template (entry INT, patch INT)")
    con.commit()
    con.close()
    with pytest.raises(vmangos.VmangosError, match="quest_template lacks column"):
        vmangos.read_quest_levels(db)
    with pytest.raises(vmangos.VmangosError, match="m.sqlite: "):
        vmangos._query(sqlite3.connect(db), db, "SELECT nothing FROM nowhere")


def _levels_db(path):
    con = sqlite3.connect(path)
    con.execute("CREATE TABLE quest_template (entry INT, patch INT, QuestLevel INT)")
    con.executemany("INSERT INTO quest_template VALUES (?, ?, ?)",
                    [(1, 0, 5), (2, 0, 7), (2, 1, 8), (4, 0, 0), (5, 0, None)])
    con.commit()
    con.close()
    return path


def test_quest_levels_take_the_cache_over_the_database(tmp_path, monkeypatch):
    db = _levels_db(tmp_path / "m.sqlite")
    assert vmangos.read_quest_levels(db) == {1: 5, 2: 8}  # the highest patch; no level under 1
    cache = SimpleNamespace(quests=[SimpleNamespace(id=1, level=None), SimpleNamespace(id=2, level=0),
                                    SimpleNamespace(id=3, level=12)])
    monkeypatch.setattr(voice_ship.wdb, "read_quests", lambda path: cache)
    assert voice_ship.quest_levels(tmp_path / "cache.wdb", db) == {1: 5, 3: 12}
    assert voice_ship.quest_levels(None, db) == {1: 5, 2: 8}


def test_the_levels_command_writes_the_table(tmp_path, monkeypatch, capsys):
    db = _levels_db(tmp_path / "m.sqlite")
    monkeypatch.setattr(voice_ship.wdb, "read_quests", lambda path: SimpleNamespace(quests=[]))
    out = tmp_path / "levels.txt"
    assert voice_store.run(["levels", "--wdb", "c.wdb", "--vmangos", str(db), "--out", str(out)]) == 0
    assert voice_store.read_levels(out) == {1: 5, 2: 8}
    assert capsys.readouterr().out == f"voice levels: 2 quests → {out}\n"


def test_store_sync_refuses_a_store_that_is_not_a_checkout(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(voice_store, "data_root", lambda: tmp_path / "data")
    assert voice_store.run(["store-sync", "--store", str(tmp_path / "plain"), "--pin", str(tmp_path / "pin")]) == 1
    assert "is not a checkout of the voice audio repository" in capsys.readouterr().err


def test_store_sync_prints_gits_own_words_when_a_push_fails(tmp_path, monkeypatch, capsys):
    store = tmp_path / "store"
    subprocess.run(["git", "init", "-q", "-b", "main", str(store)], check=True)
    for k, v in (("user.name", "Zyaga"), ("user.email", "zyaga@users.noreply.github.com")):
        subprocess.run(["git", "-C", str(store), "config", k, v], check=True)
    (store / "a.mp3").write_bytes(b"a")
    monkeypatch.setattr(voice_store, "data_root", lambda: tmp_path / "data")
    assert voice_store.run(["store-sync", "--store", str(store), "--pin", str(tmp_path / "pin")]) == 1
    err = capsys.readouterr().err
    assert err.startswith("voice store-sync: ") and "origin" in err  # the store has no remote to push to
    assert not (tmp_path / "pin").exists()


def test_forever_vo_speakers_skip_entries_that_name_no_one(tmp_path):
    (tmp_path / "captures").mkdir()
    (tmp_path / "captures" / "a.json").write_text(json.dumps({"quests": {
        "1": {"event": "accept", "questID": 10, "npc": "2079"},
        "2": {"event": "complete", "questID": 10, "isObject": True},
        "3": {"event": "progress", "questID": 10, "npc": "not a creature"},
        "4": {"event": "progress", "questID": 10},
        "5": {"event": "accept", "questID": "x", "npc": 1},
        "6": {"event": "abandon", "questID": 10, "npc": 1},
        "7": "not a record",
    }}))
    (tmp_path / "captures" / "b.json").write_text(json.dumps({"origin": "b", "quests": [
        {"event": "accept", "questID": 10, "npc": 3000}]}))
    assert forever_vo.read_quest_speakers(tmp_path) == {(10, "completion"): [None], (10, "description"): [2079, 3000]}
    assert forever_vo._build("1.60.1") == 0 and forever_vo._build(70245) == 70245


# ---- the pure rules ----------------------------------------------------------------------------------------


def test_profile_problems_name_each_bad_row():
    ok = {"source": "maintainer", "imported": "2026-10-06"}
    rows = [
        {"creature": True, "provenance": {}},
        {"creature": 2, "provenance": "x"},
        {"creature": 3, "provenance": {"age": ok}},
        {"creature": 4, "race": "martian", "provenance": {"race": {"source": "vmangos@1", "imported": "2026-10-06"}}},
        {"creature": 5, "race": "martian", "provenance": {"race": {"source": "client@1", "imported": "2026-10-06"}}},
        {"creature": 6, "voice": "x", "provenance": {}},
        {"creature": 7, "age": "adult", "provenance": {"age": {"source": "machine", "imported": "2026-10-06"}}},
        {"creature": 8, "age": "adult", "provenance": {"age": {"source": "wowhead", "imported": "2026-10-06"}}},
    ]
    assert casting.problems(rows) == [
        "voice profiles: bad creature True",
        "voice profiles 2: provenance must be an object",
        "voice profiles 3: provenance for age, which is empty",
        "voice profiles 4: race 'martian' is neither a playable race nor a family",
        "voice profiles 6: unknown field(s) voice",
        "voice profiles 7 age: machine provenance lacks model, batch, reason",
        "voice profiles 8 age: provenance source 'wowhead' is not client@…, vmangos@…, machine or maintainer",
    ]  # 5: a race the client's tables gave is taken as read


def test_a_casting_pass_value_stays_while_the_tables_are_silent():
    machine = {"source": "machine", "model": "m", "batch": "b", "reason": "r", "imported": "2026-10-01"}
    rows = casting.build([1], {1: {}}, [{"creature": 1, "age": "elder", "provenance": {"age": machine}}],
                         "2026-10-08")
    assert rows == [{"creature": 1, "age": "elder", "provenance": {"age": machine}}]


def test_a_cast_row_naming_an_unknown_field_is_refused():
    problems = casting.roster_problems({"m": {"style": 1, "licence": "CC0"}},
                                       [{"name": "a", "when": {"mood": "grim"}, "voices": ["m"]}], "m", "m")
    assert problems == ["cast row a: unknown field 'mood'"]


def test_voice_rules_at_their_edges():
    assert voice.live_values("Bring . and 5 more") == ["5"]  # a lone dot is no number
    others: dict = {}
    got, _ = voice.gossip_speakers([(5, "Hi."), (9, "Hi.")], {}, {voice.gossip_id("Hi.")}, others)
    assert got == {f"g-{voice.gossip_id('Hi.')}": 5} and others == {f"g-{voice.gossip_id('Hi.')}": [9]}
    cast = {5: {"voice": "m"}}
    jobs = voice.jobs([{"key": "1-description", "speaker": 5}, {"key": "2-description", "speaker": 5}],
                      cast, "n", "b", {"1-description": "あ"})
    assert [j.stem for j in jobs] == ["1-description"]  # a key that ships no Japanese gets no file
    src = {"source": "vmangos@1", "imported": "2026-10-06"}
    problems = voice.speaker_problems(
        [{"key": "1-description", "speaker": 5, "others": [5], "provenance": src}],
        [{"creature": 0, "voice": "m"}, {"creature": 5, "voice": "m", "row": "r", "provenance": src}])
    assert "voice speakers 1-description: others must be creature ids other than the speaker" in problems
    assert "voice voices: bad creature 0" in problems


def test_the_pack_table_refuses_bad_rows_and_finds_a_folder():
    t = vp.parse(_raw())
    assert t.by_folder("WoWForeverJapanese_VoiceB").slug == "b"
    with pytest.raises(KeyError):
        t.by_folder("WoWForeverJapanese_VoiceZ")
    for change, message in [
        (lambda r: r["pack"][0].pop("title"), r"pack 1: `title` is missing"),
        (lambda r: r["pack"][0].update(slug="Not A Slug"), "is not a CurseForge slug"),
        (lambda r: r["pack"][0].update(levels=[1]), r"levels must be \[lowest, highest\]"),
        (lambda r: r["pack"][0].update(levels=[10, 1]), "are not a band"),
        (lambda r: r.update(pack=r["pack"][-1:]), "at least one band"),
    ]:
        raw = _raw()
        change(raw)
        with pytest.raises(ValueError, match=message):
            vp.parse(raw)


def test_register_text_writes_the_error_table():
    text = voice_pack.register_text({}, {}, {"kinds": {2: "nomana", 1: "outofrange"},
                                             "voices": {"tauren-f": {"nomana": ("e-nomana-tauren-f.mp3", 1.26)}}})
    assert ("  errors = {\n    kinds = {\n      [1] = \"outofrange\",\n      [2] = \"nomana\",\n    },\n"
            "    voices = {\n      [\"tauren-f\"] = {\n        [\"nomana\"] = { \"e-nomana-tauren-f.mp3\", 1.3 },\n"
            "      },\n    },\n  },\n") in text


# ---- the commands' entry points ----------------------------------------------------------------------------


def test_the_toc_must_name_an_interface(tmp_path):
    toc = tmp_path / "addon" / "WoWForeverJapanese" / "WoWForeverJapanese.toc"
    toc.parent.mkdir(parents=True)
    toc.write_text("## Title: x\n", encoding="utf-8")
    with pytest.raises(ValueError, match="no ## Interface line"):
        voice_ship.interface_of(tmp_path / "data")
    toc.write_text("## Interface: 11508\n", encoding="utf-8")
    assert voice_ship.interface_of(tmp_path / "data") == "11508"


def test_placing_a_file_copies_when_a_hard_link_fails(tmp_path, monkeypatch):
    src, dest = tmp_path / "a.mp3", tmp_path / "b.mp3"
    src.write_bytes(b"audio")

    def no_link(a, b):
        raise OSError("cross-device link")

    monkeypatch.setattr(voice_ship.os, "link", no_link)
    voice_ship._place(src, dest)
    assert dest.read_bytes() == b"audio" and not dest.samefile(src)


def test_the_pack_command_reports_a_missing_config(tmp_path, capsys):
    assert voice_ship.run(["pack", "--config", str(tmp_path / "absent.toml")]) == 1
    assert capsys.readouterr().err.startswith("voice pack: ")


def test_the_inputs_verb_says_whether_the_inputs_changed(monkeypatch, capsys, tmp_path):
    monkeypatch.setattr(voice_ship, "run_inputs", lambda: print("changed=true") or 0)
    assert voice_ship.run(["inputs"]) == 0
    assert capsys.readouterr().out == "changed=true\n"


def test_the_cli_hands_a_known_verb_its_arguments_and_refuses_others(monkeypatch):
    seen = []
    monkeypatch.setitem(cli.VERBS, "voice", ("x", lambda rest: seen.append(rest) or 3))
    assert cli.main(["voice", "plan", "--scope", "all"]) == 3
    assert seen == [["plan", "--scope", "all"]]
    with pytest.raises(SystemExit) as e:
        cli.main(["no-such-verb"])
    assert e.value.code == 2
