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

from wfj.cmd import package_check
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
    assert [voice.voice_of(genders.get(c)) for c in (100, 101, 103, 999)] == ["male", "female", "narrator", "narrator"]


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
        [{"creature": 2079, "voice": "male", "provenance": SRC}],
    )
    assert rule_voice(data) == []


def test_validate_rejects_bad_tables(tmp_path):
    data = _rows(
        tmp_path,
        [{"key": "456-description", "speaker": 2079, "provenance": SRC},
         {"key": "456-description", "speaker": 3000, "provenance": SRC},
         {"key": "456-objectives", "speaker": True, "provenance": SRC},
         {"key": "g-xyz", "speaker": 2079}],
        [{"creature": 2079, "voice": "robot", "provenance": SRC},
         {"creature": 2079, "voice": "male", "provenance": {"source": "nope", "imported": "today"}}],
    )
    problems = rule_voice(data)
    for want in ("duplicate", "bad key '456-objectives'", "speaker must be", "bad key 'g-xyz'",
                 "provenance must be an object", "voice must be one of", "creature 3000 has no voice row",
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


@pytest.mark.parametrize("ja", ["{foo}です", "<he/she>が", "$N1体", "|cffffffff白|r", "<>"])
def test_other_markup_fails_with_the_key(ja):
    with pytest.raises(voice.VoiceError, match="^3522-completion: "):
        voice.speech_text(ja, "3522-completion")


def test_the_scoped_lines_all_read():
    lines = cmd.shipped_lines(ROOT / "data", "shadowglen")
    for row in cmd.read_rows(ROOT / "data" / "voice" / "speakers.jsonl"):
        voice.speech_text(lines[row["key"]], row["key"])


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
                    stub.calls.append(("synthesis", int(q["speaker"]), json.loads(body)["speedScale"]))
                    self._send(_wav(), "audio/wav")

        return H

    def close(self):
        self.server.shutdown()


@pytest.fixture
def engine():
    e = StubEngine()
    yield e
    e.close()


CFG = {"speed_scale": 0.9, "voices": {"male": {"style": 11, "model": "M"}, "female": {"style": 22, "model": "F"},
                                      "narrator": {"style": 11, "model": "M"}},
       "credits": {"engine": "AivisSpeech Engine", "licence": "ACML 1.0"}}


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
        {"creature": 1992, "voice": "female", "provenance": SRC},
        {"creature": 2079, "voice": "male", "provenance": SRC},
    ])
    return data


def _fake_encode(wav, out):
    out.write_bytes(b"MP3" + wav[:16])


def test_generate_reads_each_line_in_its_voice_at_the_set_pace(tmp_path, engine):
    data = _store(tmp_path)
    r = cmd.generate(data, "shadowglen", CFG, tmp_path / "voice", Engine(engine.url), _fake_encode)
    assert r["made"] == 3
    queries = [c for c in engine.calls if c[0] == "query"]
    assert ("query", "御機嫌よう、冒険者。", 11) in queries
    assert ("query", "よくやった。", 22) in queries
    assert ("query", "ようこそ。", 11) in queries
    assert {c[2] for c in engine.calls if c[0] == "synthesis"} == {0.9}
    m = json.loads((tmp_path / "voice" / "manifest.json").read_text())
    e = m["456-description"]
    assert e["ja_hash"] == hash_key("御機嫌よう、{name}。")
    assert (e["voice"], e["style"], e["model"], e["speed"], e["engine"], e["seconds"]) == ("male", 11, "uuid-m", 0.9, "1.2.0", 0.5)
    assert e["fingerprint"] == voice.fingerprint(e["ja_hash"], "male", 11, 0.9, "1.2.0")
    assert (tmp_path / "voice" / "456-description.mp3").is_file()


def test_a_rerun_remakes_only_what_changed(tmp_path, engine):
    data = _store(tmp_path)
    out = tmp_path / "voice"
    cmd.generate(data, "shadowglen", CFG, out, Engine(engine.url), _fake_encode)
    engine.calls.clear()
    r = cmd.generate(data, "shadowglen", CFG, out, Engine(engine.url), _fake_encode)
    assert (r["made"], r["skipped"]) == (0, 3)
    assert not [c for c in engine.calls if c[0] in ("query", "synthesis")]
    _store(tmp_path, ja456="こんにちは、{name}。")
    r = cmd.generate(data, "shadowglen", CFG, out, Engine(engine.url), _fake_encode)
    assert (r["made"], r["skipped"]) == (1, 2)
    slower = {**CFG, "speed_scale": 0.8}
    r = cmd.generate(data, "shadowglen", slower, out, Engine(engine.url), _fake_encode)
    assert r["made"] == 3


def test_numbers_project_the_full_run(tmp_path, engine):
    data = _store(tmp_path)
    r = cmd.generate(data, "shadowglen", CFG, tmp_path / "voice", Engine(engine.url), _fake_encode)
    text = "\n".join(cmd.numbers(r))
    assert "lines 3" in text
    assert "projection, everything (4,650,000 characters)" in text


@pytest.mark.skipif(shutil.which("lame") is None, reason="lame is not installed")
def test_mp3_is_mono_22khz_32kbps_without_a_xing_frame(tmp_path):
    out = tmp_path / "x.mp3"
    cmd.to_mp3(_wav(1.0), out)
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
    out = tmp_path / "voice"
    cmd.generate(data, "shadowglen", CFG, out, Engine(engine.url), _fake_encode)
    _store(tmp_path, ja456="変わった、{name}。")
    lines, stale = cmd.pack_lines(data, "shadowglen", json.loads((out / "manifest.json").read_text()))
    assert stale == ["456-description"]
    assert lines["456-completion"] == ("456-completion.mp3", hash_key("よくやった。"), 0.5)


def test_register_and_toc_text():
    reg = voice_pack.register_text({"g-0a": ("g-0a.mp3", "fedcba9876543210", 3.25), "456-description":
                                    ("456-description.mp3", "0123456789abcdef", 21.4)})
    assert reg == (
        "-- Generated by wfj voice pack. Do not edit.\n"
        "WoWForeverJapanese_RegisterVoice({\n"
        "  format = 1,\n"
        '  folder = "WoWForeverJapanese_Voice",\n'
        "  lines = {\n"
        '    ["456-description"] = { "456-description.mp3", "0123456789abcdef", 21.4 },\n'
        '    ["g-0a"] = { "g-0a.mp3", "fedcba9876543210", 3.2 },\n'
        "  },\n"
        "})\n"
    )
    toc = voice_pack.toc_text("11508", {"engine": "E", "models": "A, B", "licence": "L"})
    assert "## Interface: 11508\n" in toc and "## Dependencies: WoWForeverJapanese\n" in toc
    assert toc.endswith("\nRegister.lua\n")


def test_the_pack_folder(tmp_path, engine, monkeypatch):
    data = _store(tmp_path)
    toc = tmp_path / "addon" / "WoWForeverJapanese"
    toc.mkdir(parents=True)
    (toc / "WoWForeverJapanese.toc").write_text("## Interface: 11508\n## Title: x\n")
    out = tmp_path / "voice"
    cmd.generate(data, "shadowglen", CFG, out, Engine(engine.url), _fake_encode)
    cfg = tmp_path / "voice.toml"
    cfg.write_text(
        'engine = "x"\nspeed_scale = 0.9\n[voices.male]\nmodel = "M"\nstyle = 11\n[voices.female]\nmodel = "F"\n'
        'style = 22\n[voices.narrator]\nmodel = "M"\nstyle = 11\n[credits]\nengine = "E"\nlicence = "L"\n'
    )
    monkeypatch.chdir(tmp_path)
    assert cmd.run(["pack", "--config", str(cfg), "--manifest", str(out / "manifest.json"),
                    "--out", str(tmp_path / "pack")]) == 0
    dest = tmp_path / "pack" / voice_pack.FOLDER
    assert sorted(p.name for p in (dest / "Sound").iterdir()) == [
        "456-completion.mp3", "456-description.mp3", "g-0123456789abcdef.mp3"]
    assert (dest / f"{voice_pack.FOLDER}.toc").read_text().startswith("## Interface: 11508\n")
    assert "F, M" in (dest / "README.txt").read_text()
    luac = shutil.which("luac") or shutil.which("luac5.1")
    if luac:
        subprocess.run([luac, "-p", str(dest / "Register.lua")], check=True)


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
