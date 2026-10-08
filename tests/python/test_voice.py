"""`wfj voice`: who speaks each line, the text the engine reads, the files and the pack (ADR-061)."""

from __future__ import annotations

import json
import shutil
import sqlite3
import subprocess
import threading
import wave
import zipfile
from http.server import BaseHTTPRequestHandler, HTTPServer
from io import BytesIO
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import pytest

from wfj.cmd import package_check, voice_make
from wfj.cmd import voice as cmd
from wfj.cmd.validate import rule_voice
from wfj.core import voice
from wfj.core.hashing import key as hash_key
from wfj.core.normalize import normalize_v1
from wfj.emit import voice_pack
from wfj.emit.lua_writer import lua_string
from wfj.io import vmangos
from wfj.io.aivis import Engine
from wfj.io.jsonl_store import Store

ROOT = Path(__file__).resolve().parents[2]
SRC = {"source": "vmangos@13b49dc", "imported": "2026-10-06"}


# ---- the database readers -------------------------------------------------------------------------------


def make_db(path: Path) -> Path:
    db = sqlite3.connect(path)
    for t in ("creature_questrelation", "creature_involvedrelation", "gameobject_questrelation"):
        db.execute(f"CREATE TABLE {t} (id INT, quest INT, patch_min INT, patch_max INT)")
    db.execute("CREATE TABLE creature_template (entry INT, patch INT, gossip_menu_id INT, display_id1 INT)")
    db.execute("CREATE TABLE gossip_menu (entry INT, text_id INT, script_id INT, condition_id INT)")
    db.execute("CREATE TABLE npc_text (ID INT, " + ", ".join(f"BroadcastTextID{i} INT" for i in range(8)) + ")")
    db.execute("CREATE TABLE broadcast_text (entry INT, male_text TEXT, female_text TEXT)")
    db.execute("CREATE TABLE quest_greeting (entry INT, type INT, content_default TEXT)")
    db.execute("CREATE TABLE creature_display_info_addon (display_id INT, build INT, gender INT)")
    rel = [
        ("creature_questrelation", 100, 1), ("creature_questrelation", 100, 1),  # one relation per patch range
        ("creature_questrelation", 101, 2), ("creature_questrelation", 102, 2),  # two starters
        ("creature_involvedrelation", 103, 1), ("creature_involvedrelation", 100, 2),
        ("gameobject_questrelation", 900, 3),
    ]
    for table, id_, quest in rel:
        db.execute(f"INSERT INTO {table} VALUES (?, ?, 0, 10)", (id_, quest))
    db.executemany(
        "INSERT INTO creature_template VALUES (?, ?, ?, ?)",
        [(100, 0, 0, 1000), (100, 1, 7, 1000), (101, 0, 0, 1001), (102, 0, 0, 1002), (103, 0, 0, 1003),
         (200, 0, 8, 1000)],
    )
    db.executemany("INSERT INTO gossip_menu VALUES (?, ?, 0, 0)", [(7, 70), (8, 80)])
    db.execute("INSERT INTO npc_text VALUES (70, 700, 0, 0, 0, 0, 0, 0, 0)")
    db.execute("INSERT INTO npc_text VALUES (80, 0, 800, 0, 0, 0, 0, 0, 0)")
    db.executemany(
        "INSERT INTO broadcast_text VALUES (?, ?, ?)",
        [(700, "Hello, traveller.", "Hello, traveller."), (800, "Trainer words.", "")],
    )
    db.execute("INSERT INTO quest_greeting VALUES (103, 0, 'A greeting.')")
    db.execute("INSERT INTO quest_greeting VALUES (103, 1, 'An object greeting.')")
    db.executemany(
        "INSERT INTO creature_display_info_addon VALUES (?, ?, ?)",
        [(1000, 0, 1), (1000, 5875, 0), (1001, 0, 1), (1002, 0, 0), (1003, 0, 2)],
    )
    db.commit()
    db.close()
    return path


def test_quest_relations_are_distinct_and_sorted(tmp_path):
    starters, objects, enders = vmangos.read_quest_speakers(make_db(tmp_path / "m.sqlite"), {1, 2, 3})
    assert starters == {1: [100], 2: [101, 102]}
    assert objects == {3}
    assert enders == {1: [103], 2: [100]}


def test_creature_lines_read_the_gossip_menu_and_creature_greetings(tmp_path):
    lines = vmangos.read_creature_lines(make_db(tmp_path / "m.sqlite"), {100, 103, 200})
    assert lines == [(100, "Hello, traveller."), (103, "A greeting."), (200, "Trainer words.")]


def test_gender_comes_from_the_latest_display_build(tmp_path):
    genders = vmangos.read_creature_genders(make_db(tmp_path / "m.sqlite"), {100, 101, 103, 999})
    assert genders == {100: 0, 101: 1, 103: 2}


# ---- who speaks ------------------------------------------------------------------------------------------


def test_quest_speakers_follow_start_and_end():
    keys = ["1-description", "1-progress", "1-completion", "2-description", "3-description", "4-description"]
    got, problems = voice.quest_speakers(keys, {1: [100], 2: [101, 102]}, {3}, {1: [103]})
    assert got == {
        "1-description": 100, "1-progress": 103, "1-completion": 103,
        "2-description": 101, "3-description": "narrator", "4-description": "narrator",
    }
    assert problems == ["2-description: creatures [101, 102], took 101", "4-description: no creature in the database, narrator"]


def test_gossip_speakers_prefer_the_collector_and_report_missing():
    k1, k2 = voice.gossip_id("Hello, traveller."), voice.gossip_id("Trainer words.")
    lines = [(100, "Hello, traveller."), (103, "Hello, traveller."), (200, "Trainer words."), (200, "Untranslated.")]
    got, report = voice.gossip_speakers(lines, {k1: [103]}, {k1, k2})
    assert got == {f"g-{k1}": 103, f"g-{k2}": 200}
    assert report["conflict"] == []
    assert report["missing"] == [f"g-{voice.gossip_id('Untranslated.')} (creature 200)"]
    got, report = voice.gossip_speakers(lines, {}, {k1, k2})
    assert got[f"g-{k1}"] == 100
    assert report["conflict"] == [f"g-{k1}: creatures [100, 103], took 100"]


def test_gossip_key_is_the_importers():
    assert voice.gossip_id("Greetings,  $C.") == hash_key(normalize_v1("Greetings,  $C."))


# ---- validate --------------------------------------------------------------------------------------------


def _rows(tmp_path, speakers, voices):
    data = tmp_path / "data"
    (data / "voice").mkdir(parents=True)
    cmd.write_rows(data / "voice" / "speakers.jsonl", speakers)
    cmd.write_rows(data / "voice" / "voices.jsonl", voices)
    return data


def test_validate_accepts_good_tables(tmp_path):
    data = _rows(
        tmp_path,
        [{"key": "456-description", "speaker": 2079, "provenance": SRC},
         {"key": "5842-description", "speaker": "narrator", "provenance": SRC},
         {"key": "g-0123456789abcdef", "speaker": 2079, "provenance": {"source": "collector@1.60.1.70205", "imported": "2026-10-06"}}],
        [{"creature": 2079, "voice": "aidacalm", "row": "male", "provenance": SRC}],
    )
    assert rule_voice(data) == []


def test_validate_rejects_bad_tables(tmp_path):
    data = _rows(
        tmp_path,
        [{"key": "456-description", "speaker": 2079, "provenance": SRC},
         {"key": "456-description", "speaker": 3000, "provenance": SRC},
         {"key": "456-objectives", "speaker": True, "provenance": SRC},
         {"key": "g-xyz", "speaker": 2079}],
        [{"creature": 2079, "voice": "Robot!", "provenance": SRC},
         {"creature": 2079, "voice": "male", "row": "m", "provenance": {"source": "nope", "imported": "today"}}],
    )
    problems = rule_voice(data)
    for want in ("duplicate", "bad key '456-objectives'", "speaker must be", "bad key 'g-xyz'",
                 "provenance must be an object", "voice must be a roster voice id", "row must name the cast row",
                 "creature 3000 has no voice row",
                 "voice voices 2079: duplicate", "source must be name@version", "imported must be a date"):
        assert any(want in p for p in problems), want


def test_the_committed_voice_tables_validate(root):
    assert rule_voice(root / "data") == []


# ---- the text the engine reads ---------------------------------------------------------------------------


def test_player_tokens_become_the_neutral_word():
    assert voice.speech_text("よくやってくれた、{name}。", "k") == "よくやってくれた、冒険者。"
    assert voice.speech_text("若き{class}よ", "k") == "若き冒険者よ"
    assert voice.speech_text("お若い{race}さん", "k") == "お若い冒険者さん"


def test_a_stage_direction_is_not_read():
    assert voice.speech_text("飲んで。\n\n<Iverronが解毒剤を飲む>\n\nありがとう。", "k") == "飲んで。\n\n\n\nありがとう。"


def test_numbers_are_filled_from_the_english_as_the_addon_fills_them():
    assert voice.live_values("Kill Kobold Vermin, 2 of em.") == ["2"]
    assert voice.live_values("train under SI:7, 1,200 to 1,500 yards away") == ["7", "1200～1500"]
    assert voice.live_values("include:$B$B1.  Murdering") == ["1"]  # $B is a line break, not a letter
    assert voice.live_values("OOX-17/TN and level60") == ["17"]
    assert voice.speech_text("Kobold Verminを$N1体倒せ。", "k", ["2"]) == "Kobold Verminを2体倒せ。"
    assert voice.speech_text("Elixirを$N1個求める", "k") == "Elixirを何個か求める"  # only the game knows it
    assert voice.speech_text("あと$2113w日以内だ", "k") == "あと数日以内だ"
    assert voice.text_hash("あ", ["2"]) != voice.text_hash("あ", ["3"]) != voice.text_hash("あ")


def test_a_line_that_is_all_stage_direction_is_read_without_its_brackets():
    assert voice.speech_text("<色あせたインクで書かれたメモだ。>", "k") == "色あせたインクで書かれたメモだ。"


@pytest.mark.parametrize("ja", ["{foo}です", "<he/she>が", "|cffffffff白|r", "<>"])
def test_other_markup_fails_with_the_key(ja):
    with pytest.raises(voice.VoiceError, match="^3522-completion: "):
        voice.speech_text(ja, "3522-completion")


def test_every_line_with_a_speaker_reads():
    # the whole game: a line the engine would refuse stops the full run, so it fails here first
    lines = voice_make.shipped_lines(ROOT / "data")
    values = voice_make.line_values(ROOT / "data", lines)
    bad = []
    for row in cmd.read_rows(ROOT / "data" / "voice" / "speakers.jsonl"):
        try:
            voice.speech_text(lines[row["key"]], row["key"], values.get(row["key"], ()))
        except (voice.VoiceError, KeyError) as e:
            bad.append(str(e))
    assert bad == []


# ---- the hash matches what the addon ships ---------------------------------------------------------------


def _planned_row(planned, relpath, head):
    return next(ln for ln in planned[relpath].splitlines() if ln.startswith(head))


def test_ja_hash_is_over_the_japanese_generate_ships(planned):
    lines = cmd.shipped_lines(ROOT / "data", "shadowglen")
    quest_row = _planned_row(planned, "Data/Quest/Quest_0000.lua", "  [456] = {")
    assert lua_string(lines["456-description"]) in quest_row
    gossip = next(r["key"] for r in cmd.read_rows(ROOT / "data" / "voice" / "speakers.jsonl") if r["key"].startswith("g-"))
    gk = gossip[2:]
    gossip_row = _planned_row(planned, f"Data/Gossip/Gossip_{gk[:2]}.lua", f'  ["{gk}"] = {{')
    assert gossip_row.startswith(f'  ["{gk}"] = {{ {lua_string(lines[gossip])},')
    assert voice.ja_hash(lines[gossip]) == hash_key(lines[gossip])


# ---- generation, against a stub engine -------------------------------------------------------------------


def _wav(seconds=0.5, rate=24000):
    buf = BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"\x00\x00" * int(seconds * rate))
    return buf.getvalue()


class StubEngine:
    def __init__(self):
        self.calls: list[tuple] = []
        self.server = HTTPServer(("127.0.0.1", 0), self._handler())
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.server.server_port}"

    def _handler(self):
        stub = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def _send(self, body: bytes, kind="application/json"):
                self.send_response(200)
                self.send_header("Content-Type", kind)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                if self.path == "/version":
                    self._send(b'"1.2.0"')
                else:
                    self._send(json.dumps([{"speaker_uuid": "uuid-m", "styles": [{"id": 11}]},
                                           {"speaker_uuid": "uuid-f", "styles": [{"id": 22}]}]).encode())

            def do_POST(self):
                u = urlparse(self.path)
                q = {k: v[0] for k, v in parse_qs(u.query).items()}
                body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
                if u.path == "/audio_query":
                    stub.calls.append(("query", q["text"], int(q["speaker"])))
                    self._send(json.dumps({"accent_phrases": [], "speedScale": 1.0}).encode())
                else:
                    b = json.loads(body)
                    stub.calls.append(("synthesis", int(q["speaker"]), b["speedScale"], b["pitchScale"],
                                       b["intonationScale"]))
                    self._send(_wav(), "audio/wav")

        return H

    def close(self):
        self.server.shutdown()


@pytest.fixture
def engine():
    e = StubEngine()
    yield e
    e.close()


CFG = {
    "speed_scale": 0.9, "narrator": "m", "book_narrator": "m", "cast": [],
    "roster": {
        "m": {"model": "M", "style": 11, "speed": 0.9, "pitch": 0.0, "intonation": 1.0, "licence": "ACML 1.0"},
        "f": {"model": "F", "style": 22, "speed": 0.9, "pitch": 0.0, "intonation": 1.0, "licence": "ACML 1.0"},
        "old": {"model": "F", "style": 22, "speed": 0.85, "pitch": -0.05, "intonation": 1.0, "licence": "CC0"},
    },
    "credits": {"engine": "AivisSpeech Engine"},
}


def _store(tmp_path, ja456="御機嫌よう、{name}。"):
    data = tmp_path / "data"
    (data).mkdir(exist_ok=True)
    (data / "SCHEMA").write_text("1\n")
    q = [
        {"id": 456, "field": "description", "ja": ja456, "status": "trusted"},
        {"id": 456, "field": "completion", "ja": "よくやった。", "status": "trusted"},
        {"id": 456, "field": "title", "ja": "題", "status": "trusted"},
    ]
    (data / "quest").mkdir(exist_ok=True)
    (data / "quest" / "quest-0000.jsonl").write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in q))
    g = [{"id": "0123456789abcdef", "field": "text", "ja": "ようこそ。", "status": "trusted"}]
    (data / "gossip").mkdir(exist_ok=True)
    (data / "gossip" / "gossip-01.jsonl").write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in g))
    cmd.write_rows(data / "voice" / "speakers.jsonl", [
        {"key": "456-completion", "speaker": 1992, "provenance": SRC},
        {"key": "456-description", "speaker": 2079, "provenance": SRC},
        {"key": "g-0123456789abcdef", "speaker": "narrator", "provenance": SRC},
    ])
    cmd.write_rows(data / "voice" / "voices.jsonl", [
        {"creature": 1992, "voice": "f", "row": "female", "provenance": SRC},
        {"creature": 2079, "voice": "m", "row": "male", "provenance": SRC},
        {"creature": 3000, "voice": "old", "row": "elder, female", "provenance": SRC},
    ])
    return data


def _fake_encode(wav, out):
    out.write_bytes(b"MP3" + wav[:16])


def _gen(data, store, engine, cfg=CFG):
    return voice_make.generate(data, "all", cfg, store, Engine(engine.url), _fake_encode, log=lambda *_: None)


def _audio(data):
    return voice_make.audio_record(data)


def test_generate_reads_each_line_in_its_voice_at_the_set_pace(tmp_path, engine):
    data = _store(tmp_path)
    r = _gen(data, tmp_path / "voice", engine)
    assert r["made"] == 3
    queries = [c for c in engine.calls if c[0] == "query"]
    assert ("query", "御機嫌よう、冒険者。", 11) in queries
    assert ("query", "よくやった。", 22) in queries
    assert ("query", "ようこそ。", 11) in queries
    assert {c[2:] for c in engine.calls if c[0] == "synthesis"} == {(0.9, 0.0, 1.0)}
    e = _audio(data)["456-description"]
    assert e["ja_hash"] == hash_key("御機嫌よう、{name}。")
    assert (e["key"], e["voice"], e["seconds"], e["provenance"]["source"]) == ("456-description", "m", 0.5, "aivis@1.2.0")
    assert e["fingerprint"] == voice.fingerprint(e["ja_hash"], "m", CFG["roster"]["m"])
    assert (tmp_path / "voice" / "456-description.mp3").is_file()
    status = json.loads((tmp_path / "voice" / "status.json").read_text())
    assert (status["done"], status["total"], status["finished"]) == (3, 3, True)


def test_a_rerun_remakes_only_what_changed(tmp_path, engine):
    data = _store(tmp_path)
    out = tmp_path / "voice"
    _gen(data, out, engine)
    engine.calls.clear()
    assert _gen(data, out, engine)["made"] == 0
    assert not [c for c in engine.calls if c[0] in ("query", "synthesis")]
    _store(tmp_path, ja456="こんにちは、{name}。")
    _audio_rows = cmd.read_rows(data / "voice" / "audio.jsonl")
    assert _gen(data, out, engine)["made"] == 1
    # recasting one voice remakes only the lines read in it: the female voice's settings change
    slower = {**CFG, "roster": {**CFG["roster"], "f": {**CFG["roster"]["f"], "speed": 0.8}}}
    assert _gen(data, out, engine, slower)["made"] == 1
    assert _audio_rows  # the record was written before the second run


def test_a_line_several_differently_cast_creatures_say_gets_a_file_per_voice(tmp_path, engine):
    data = _store(tmp_path)
    cmd.write_rows(data / "voice" / "speakers.jsonl", [
        {"key": "456-description", "speaker": 2079, "others": [1992, 3000], "provenance": SRC},
    ])
    _gen(data, tmp_path / "voice", engine)
    assert sorted(_audio(data)) == ["456-description", "456-description_f", "456-description_old"]
    assert {c[2:] for c in engine.calls if c[0] == "synthesis"} == {(0.9, 0.0, 1.0), (0.85, -0.05, 1.0)}
    lines, creatures, left_out = voice_make.pack_tables(data, CFG, "all")
    assert lines["456-description"]["variants"] == {"f": ("456-description_f.mp3", 0.5),
                                                    "old": ("456-description_old.mp3", 0.5)}
    assert creatures == {1992: "f", 2079: "m", 3000: "old"} and left_out == []


def test_plan_counts_what_generate_would_make(tmp_path, engine):
    data = _store(tmp_path)
    p = voice_make.plan(data, CFG, "all")
    assert (p["files"], p["missing"], p["stale"]) == (3, 3, 0)
    _gen(data, tmp_path / "voice", engine)
    _store(tmp_path, ja456="変わった、{name}。")
    p = voice_make.plan(data, CFG, "all")
    assert (p["missing"], p["stale"], dict(p["by_voice"])) == (0, 1, {"m": 1})


def test_in_step_reports_missing_and_stale_files():
    lines = {"1-description": "あ", "1-progress": "い"}
    jobs = [voice.Job("1-description", "1-description", "m"), voice.Job("1-progress", "1-progress", "m")]
    audio = {"1-description": {"fingerprint": voice.fingerprint(hash_key("古い"), "m", CFG["roster"]["m"])}}
    assert voice.in_step(jobs, lines, CFG["roster"], audio) == {"missing": ["1-progress"], "stale": ["1-description"]}


@pytest.mark.skipif(shutil.which("lame") is None, reason="lame is not installed")
def test_mp3_is_mono_22khz_32kbps_without_a_xing_frame(tmp_path):
    out = tmp_path / "x.mp3"
    voice_make.to_mp3(_wav(1.0), out)
    b = out.read_bytes()
    i = b.find(b"\xff")
    while not (b[i] == 0xFF and b[i + 1] & 0xE0 == 0xE0):
        i = b.find(b"\xff", i + 1)
    h = int.from_bytes(b[i:i + 4], "big")
    version, layer = (h >> 19) & 3, (h >> 17) & 3
    assert (version, layer) == (2, 1)  # MPEG-2, Layer III
    assert (h >> 12) & 0xF == 4  # 32 kbps in the MPEG-2 Layer III table
    assert (h >> 10) & 3 == 0  # 22.05 kHz in MPEG-2
    assert (h >> 6) & 3 == 3  # mono
    assert b"Xing" not in b[:2048] and b"Info" not in b[:2048]
    assert not (tmp_path / "x.wav").exists()


# ---- the pack ----------------------------------------------------------------------------------------------


def test_pack_holds_only_lines_whose_japanese_still_matches(tmp_path, engine):
    data = _store(tmp_path)
    _gen(data, tmp_path / "voice", engine)
    _store(tmp_path, ja456="変わった、{name}。")
    lines, _, left_out = voice_make.pack_tables(data, CFG, "all")
    assert left_out == ["456-description"] and "456-description" not in lines
    assert lines["456-completion"] == {"file": "456-completion.mp3", "hash": hash_key("よくやった。"), "seconds": 0.5,
                                       "variants": {}}


def test_register_and_toc_text():
    reg = voice_pack.register_text(
        {"g-0a": {"file": "g-0a.mp3", "hash": "fedcba9876543210", "seconds": 3.25, "variants": {}},
         "456-description": {"file": "456-description.mp3", "hash": "0123456789abcdef", "seconds": 21.4,
                             "variants": {"old": ("456-description_old.mp3", 20.0)}}},
        {3000: "old", 11: ("m", "f")},
    )
    assert reg == (
        "-- Generated by wfj voice pack. Do not edit.\n"
        "-- A main addon too old to read packs has no register function: the pack then stays silent.\n"
        "if not WoWForeverJapanese_RegisterVoice then return end\n"
        "WoWForeverJapanese_RegisterVoice({\n"
        "  format = 2,\n"
        '  folder = "WoWForeverJapanese_Voice",\n'
        "  lines = {\n"
        '    ["456-description"] = { "456-description.mp3", "0123456789abcdef", 21.4,'
        ' v = { ["old"] = { "456-description_old.mp3", 20.0 } } },\n'
        '    ["g-0a"] = { "g-0a.mp3", "fedcba9876543210", 3.2 },\n'
        "  },\n"
        "  creatures = {\n"
        '    [11] = { "m", "f" },\n'
        '    [3000] = "old",\n'
        "  },\n"
        "})\n"
    )
    toc = voice_pack.toc_text("11508", {"engine": "E", "models": "A, B", "licence": "L"})
    assert "## Interface: 11508\n" in toc and "## Dependencies: WoWForeverJapanese\n" in toc
    assert toc.endswith("\nRegister.lua\n")


def test_the_release_zip_refuses_the_voice_pack(tmp_path):
    z = tmp_path / "r.zip"
    with zipfile.ZipFile(z, "w") as zf:
        zf.writestr("WoWForeverJapanese/WoWForeverJapanese.toc", "## Version: v1.0.0\n## X-Curse-Project-ID: 1\n")
        zf.writestr("WoWForeverJapanese_Voice/Register.lua", "")
    problems = package_check.check(z, "1.0.0", {"WoWForeverJapanese/WoWForeverJapanese.toc"})
    assert "top-level entry other than WoWForeverJapanese/: WoWForeverJapanese_Voice" in problems


def test_store_ignores_the_voice_folder(tmp_path):
    data = _store(tmp_path)
    assert [ln["id"] for ln in Store(data).load("gossip")] == ["0123456789abcdef"]


def test_a_scope_holds_its_quests_and_its_npcs_talk_only():
    rows = [
        {"key": "456-description", "speaker": "narrator"},
        {"key": "456-completion", "speaker": 2079},
        {"key": "999-description", "speaker": 1},
        {"key": "g-0123456789abcdef", "speaker": 2079},
        {"key": "g-fedcba9876543210", "speaker": "narrator"},
        {"key": "b-0123456789abcdef", "speaker": "narrator"},
        {"key": "g-1111111111111111", "speaker": 5, "others": [3597]},
    ]
    keys = [r["key"] for r in cmd.in_scope(rows, "shadowglen")]
    assert keys == ["456-completion", "456-description", "g-0123456789abcdef", "g-1111111111111111"]



def test_audio_in_step():
    """The gate: every voiced line of the committed data has a recorded audio file made from the Japanese it
    ships, in the voice its speaker is cast in, with the roster's current settings (data/voice/audio.jsonl).
    A pull request that adds or changes a voiced line, or recasts a voice, without remaking its audio fails
    here. Remake with `make voice-generate` (docs/operations/voice.md)."""
    data = ROOT / "data"
    cfg = voice_make.load_config(ROOT / "pipeline" / "voice.toml")
    lines = voice_make.shipped_lines(data)
    jobs = voice_make.file_jobs(data, cfg, "all", lines, voice_make.players_of("all"))
    assert len(jobs) > 10_000  # the whole game, not an empty scope
    state = voice.in_step(jobs, lines, cfg["roster"], voice_make.audio_record(data),
                          voice_make.line_values(data, lines))
    missing, stale = state["missing"], state["stale"]
    assert not missing, f"{len(missing)} voiced line(s) have no audio, e.g. {missing[:5]}: run make voice-generate"
    assert not stale, (f"{len(stale)} audio file(s) were made from other Japanese or another voice, "
                       f"e.g. {stale[:5]}: run make voice-generate")


def test_a_round_with_nothing_to_voice_needs_no_engine_and_work_without_one_refuses(tmp_path, engine):
    """The voice step at the end of a batch import or a fix report: in step, it never calls the engine; with
    lines to remake and no engine answering, it refuses with how to start it."""
    from wfj.io.aivis import EngineError

    data = _store(tmp_path)
    dead = Engine("http://127.0.0.1:9")  # nothing listens here
    with pytest.raises(EngineError, match=r"3 file\(s\) to make.*start the AivisSpeech Engine"):
        voice_make.generate(data, "all", CFG, tmp_path / "voice", dead, _fake_encode, log=lambda *_: None)
    _gen(data, tmp_path / "voice", engine)  # everything made
    r = voice_make.generate(data, "all", CFG, tmp_path / "voice", dead, _fake_encode, log=lambda *_: None)
    assert r["made"] == 0  # in step: the dead engine was never asked
    _store(tmp_path, ja456="変わった、{name}。")  # a translation changed one voiced line
    with pytest.raises(EngineError, match=r"1 file\(s\) to make"):
        voice_make.generate(data, "all", CFG, tmp_path / "voice", dead, _fake_encode, log=lambda *_: None)


# ---- book and letter pages ------------------------------------------------------------------------------


def test_a_page_is_signed_by_its_last_line_when_that_is_only_a_name():
    assert voice.book_signature("Hello Morgan,$B$BBusiness is brisk.$B$B-Baelog") == "Baelog"
    assert voice.book_signature("Dear friend,\n\nCome quickly.\n\n- Windan Shay") == "Windan Shay"
    assert voice.book_signature("Report.\nMagistrate Solomon") == "Magistrate Solomon"
    assert voice.book_signature("Mor'zul,$B$BIt is done.$B-Mor'zul Bloodbringer") == "Mor'zul Bloodbringer"
    assert voice.book_signature("The war began long ago and it has not ended.") is None  # prose, not a name
    assert voice.book_signature("Stalvan Mistmantle") is None  # a page that is only a name: a title
    assert voice.book_signature("The end.\nand so it goes on") is None


def test_a_signed_page_is_read_by_its_writer_and_any_other_by_the_narrator():
    pages = {"b-1": "Text.$B-Baelog", "b-2": "Text.$B-Gryan Stoutmantle", "b-3": "Text.$B-Twins",
             "b-4": "No signature here at all.", "b-5": "Text.$B-Nobody Cast"}
    names = {"Baelog": [6906], "Gryan Stoutmantle": [234, 9999], "Twins": [1, 2], "Nobody Cast": [77]}
    cast = {6906, 234, 1, 2}  # 9999 is not cast; Twins: two cast creatures share the name
    assert voice.book_speakers(pages, names, cast) == {
        "b-1": 6906, "b-2": 234, "b-3": voice.NARRATOR, "b-4": voice.NARRATOR, "b-5": voice.NARRATOR}


def test_book_pages_are_keyed_by_their_english_hash_and_html_pages_stay_silent(tmp_path):
    data = _store(tmp_path)
    english = [
        {"id": 15, "field": "text", "en": "Hello Morgan,$B$B-Baelog", "hash": "aaaaaaaaaaaaaaaa", "src": "x@1"},
        {"id": 16, "field": "text", "en": "<HTML><BODY><P>A map.</P></BODY></HTML>", "hash": "bbbbbbbbbbbbbbbb",
         "src": "x@1"},
    ]
    Store(data, english=True).save("book", english)
    Store(data).save("book", [
        {"id": "aaaaaaaaaaaaaaaa", "field": "text", "ja": "モーガンへ。", "status": "trusted",
         "english": {"hash": "aaaaaaaaaaaaaaaa"}},
        {"id": "bbbbbbbbbbbbbbbb", "field": "text", "ja": "<HTML><BODY><P>地図。</P></BODY></HTML>",
         "status": "trusted", "english": {"hash": "bbbbbbbbbbbbbbbb"}},
    ])
    lines = voice_make.shipped_lines(data)
    assert lines["b-aaaaaaaaaaaaaaaa"] == "モーガンへ。"  # b-<the page's English hash>, the key UI/ItemText uses
    assert "b-bbbbbbbbbbbbbbbb" not in lines  # an HTML page keeps the client's layout and is not voiced


def test_a_machine_without_the_audio_store_runs_a_round_with_nothing_voiced(tmp_path, engine):
    """A contributor's clone has no audio store: a round that leaves every voiced line in step needs neither
    store nor engine; work to do refuses with how to get the store."""
    data = _store(tmp_path)
    _gen(data, tmp_path / "voice", engine)  # the maintainer's store, every file made and recorded
    elsewhere = tmp_path / "no-store"
    dead = Engine("http://127.0.0.1:9")
    r = voice_make.generate(data, "all", CFG, elsewhere, dead, _fake_encode, log=lambda *_: None, checkout=True)
    assert r["made"] == 0 and not elsewhere.exists()
    _store(tmp_path, ja456="変わった、{name}。")
    with pytest.raises(ValueError, match=r"1 file\(s\) to make, but .* is not a checkout.*git clone"):
        voice_make.generate(data, "all", CFG, elsewhere, engine, _fake_encode, log=lambda *_: None,
                            checkout=True)


def test_store_sync_if_changed_leaves_the_pin_and_the_remote_alone_when_nothing_is_new(tmp_path):
    from wfj.cmd import voice_store

    remote, store, pin = tmp_path / "remote.git", tmp_path / "store", tmp_path / "pin.txt"
    subprocess.run(["git", "init", "-q", "--bare", str(remote)], check=True)
    subprocess.run(["git", "init", "-q", "-b", "main", str(store)], check=True)
    for k, v in (("user.name", "Zyaga"), ("user.email", "zyaga@users.noreply.github.com")):
        subprocess.run(["git", "-C", str(store), "config", k, v], check=True)
    subprocess.run(["git", "-C", str(store), "remote", "add", "origin", str(remote)], check=True)
    (store / "a.mp3").write_bytes(b"a")
    assert voice_store.has_changes(store)
    voice_store.sync(store, pin, "a")
    assert not voice_store.has_changes(store) and not voice_store.has_changes(tmp_path / "absent")
    pin.write_text(voice_store.PIN_HEAD + "b" * 40 + "\n")  # this branch pins other audio than the store's HEAD
    assert voice_store.run(["store-sync", "--if-changed", "--store", str(store), "--pin", str(pin)]) == 0
    assert voice_store.read_pin(pin) == "b" * 40  # nothing new: the pin stays
