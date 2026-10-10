"""`wfj voice cast|plan|generate|status|record-hashes` as commands, the character's spoken error lines and
the pack tables' variants and aliases, against a fake engine and encoder."""

from __future__ import annotations

import json
import os
import subprocess
from types import SimpleNamespace

import pytest
from test_voice import CFG, SRC, _fake_encode, _store, _wav

from wfj.cmd import voice_make
from wfj.core import voice
from wfj.core.hashing import key as hash_key
from wfj.core.normalize import normalize_v1
from wfj.io.jsonl_store import Store

TOML = """engine = "http://fake"
speed_scale = 0.9
narrator = "m"
book_narrator = "m"

[roster.m]
model = "M"
style = 11
licence = "ACML 1.0"

[roster.f]
model = "F"
style = 22
licence = "ACML 1.0"

[roster.old]
model = "F"
style = 22
speed = 0.85
pitch = -0.05
licence = "CC0"

[[cast]]
name = "female"
when = { gender = "female" }
voices = ["f"]

[[cast]]
name = "male"
when = { gender = "male" }
voices = ["m"]
"""
PLAYER_CAST = [
    {"name": "undead", "when": {"archetype": "undead"}, "voices": ["old"]},
    {"name": "tauren, female", "when": {"race": "tauren", "gender": "female"}, "voices": ["f"]},
]


class FakeEngine:
    def __init__(self, url="http://fake"):
        self.url = url
        self.calls: list[tuple] = []

    def version(self):
        return "1.2.0"

    def synthesize(self, text, style, speed, pitch=0.0, intonation=1.0):
        self.calls.append((text, style, speed, pitch, intonation))
        return _wav()


def _errors(data):
    """Two spoken error lines: one that speaks an on-screen message, one with Japanese of its own."""
    Store(data).save("ui", [
        {"id": "ERR_OUT_OF_RANGE", "field": "text", "ja": "遠すぎる。", "status": "trusted"},
        {"id": "ERR_UNSHIPPED", "field": "text", "ja": "", "status": "trusted"},
    ])
    voice_make._write(data / "voice" / "error-messages.jsonl", [
        {"ui": "ERR_OUT_OF_RANGE"}, {"ui": "ERR_UNSHIPPED"}])
    voice_make._write(data / "voice" / "errors.jsonl", [
        {"kind": "outofrange", "ui": "ERR_OUT_OF_RANGE"}, {"kind": "nomana", "ja": "マナが足りない。"}])
    voice_make._write(data / "voice" / "error-kinds.jsonl", [
        {"voice_id": 1, "kind": "outofrange"}, {"voice_id": 2, "kind": "nomana"}])


@pytest.fixture
def world(tmp_path, monkeypatch):
    data = _store(tmp_path)
    monkeypatch.setattr(voice_make, "data_root", lambda: data)
    cfg = tmp_path / "voice.toml"
    cfg.write_text(TOML, encoding="utf-8")
    return SimpleNamespace(data=data, cfg=cfg, store=tmp_path / "store", tmp=tmp_path)


# ---- config and players ----------------------------------------------------------------------------------


def test_a_broken_config_lists_its_problems(tmp_path):
    bad = tmp_path / "voice.toml"
    bad.write_text('narrator = "zz"\nbook_narrator = "zz"\n[roster.m]\nmodel = "M"\nstyle = "x"\n', encoding="utf-8")
    with pytest.raises(ValueError, match=r"^voice\.toml: roster m: style must be.*narrator voice 'zz'"):
        voice_make.load_config(bad)


def test_players_of_reads_race_sex_pairs():
    assert voice_make.players_of(None) == [] and voice_make.players_of("") == []
    assert len(voice_make.players_of("all")) == len(voice_make.PLAYER_RACES) * 2
    assert voice_make.players_of("tauren-f,human-m") == [("tauren", "f"), ("human", "m")]
    with pytest.raises(ValueError, match="--players 'elf-m'"):
        voice_make.players_of("elf-m")
    with pytest.raises(ValueError, match="--players 'orc-x'"):
        voice_make.players_of("orc-x")


def test_a_player_is_cast_like_an_adult_of_their_race():
    cfg = {**CFG, "cast": PLAYER_CAST}
    assert voice_make.player_voice(cfg, "tauren", "f") == "f"
    assert voice_make.player_voice(cfg, "scourge", "m") == "old"  # a Forsaken speaks as the undead
    assert voice_make.player_voice(cfg, "human", "m") == "m"  # no row: the narrator


def test_error_lines_speak_shipped_messages_and_their_own_japanese(world):
    _errors(world.data)
    assert voice_make.error_lines(world.data) == {"e-ERR_OUT_OF_RANGE": "遠すぎる。", "e-nomana": "マナが足りない。"}
    cfg = {**CFG, "cast": PLAYER_CAST}
    jobs = voice_make.error_jobs(world.data, cfg, [("tauren", "f"), ("human", "m")])
    assert [(j.stem, j.voice) for j in jobs] == [
        ("e-ERR_OUT_OF_RANGE-tauren-f", "f"), ("e-nomana-tauren-f", "f"),
        ("e-ERR_OUT_OF_RANGE-human-m", "m"), ("e-nomana-human-m", "m")]


def test_the_error_table_holds_files_in_step_per_race_and_sex(world):
    _errors(world.data)
    cfg = {**CFG, "cast": PLAYER_CAST}
    players = [("tauren", "f")]
    assert voice_make.error_table(world.data, cfg, players) == {}  # nothing made yet
    voice_make.generate(world.data, "all", cfg, world.store, FakeEngine(), _fake_encode, log=lambda *_: None,
                        players=players)
    assert voice_make.error_table(world.data, cfg, players) == {
        "kinds": {1: "outofrange", 2: "nomana"},
        "voices": {"tauren-f": {
            "ERR_OUT_OF_RANGE": ("e-ERR_OUT_OF_RANGE-tauren-f.mp3", 0.5),
            "nomana": ("e-nomana-tauren-f.mp3", 0.5),
            "outofrange": ("e-ERR_OUT_OF_RANGE-tauren-f.mp3", 0.5),  # the kind speaks its message's file
        }},
    }


# ---- generate and the pack tables ------------------------------------------------------------------------


def test_generate_saves_its_record_as_it_goes(world, monkeypatch):
    monkeypatch.setattr(voice_make, "RECORD_EVERY", 1)
    logged = []
    engine = FakeEngine()
    r = voice_make.generate(world.data, "all", CFG, world.store, engine, _fake_encode, log=logged.append)
    assert r["made"] == 3 and r["files"] == 3 and r["seconds_made"] == pytest.approx(1.5)
    assert logged == ["voice generate: 1/3", "voice generate: 2/3", "voice generate: 3/3"]
    assert len(engine.calls) == 3


def test_a_file_gone_from_the_store_is_made_again(world):
    voice_make.generate(world.data, "all", CFG, world.store, FakeEngine(), _fake_encode, log=lambda *_: None)
    voice_make.audio_file(world.store, "456-completion").unlink()
    engine = FakeEngine()
    r = voice_make.generate(world.data, "all", CFG, world.store, engine, _fake_encode, log=lambda *_: None)
    assert r["made"] == 1 and [c[0] for c in engine.calls] == ["よくやった。"]


def test_pack_tables_name_a_mixed_creatures_two_voices_and_play_a_female_wording(world):
    female_en = "Welcome, $Gsir:madam;."
    Store(world.data, english=True).save("gossip", [
        {"id": "0123456789abcdef", "field": "text", "en": female_en, "hash": "0123456789abcdef", "src": "x@1"}])
    voice_make._write(world.data / "voice" / "speakers.jsonl", [
        {"key": "456-description", "speaker": 2079, "others": [1992], "provenance": SRC},
        {"key": "g-0123456789abcdef", "speaker": "narrator", "provenance": SRC},
    ])
    voice_make._write(world.data / "voice" / "voices.jsonl", [
        {"creature": 1992, "voice": "f", "row": "x", "female": "old", "female_row": "y", "provenance": SRC},
        {"creature": 2079, "voice": "m", "row": "male", "provenance": SRC},
    ])
    voice_make.generate(world.data, "all", CFG, world.store, FakeEngine(), _fake_encode, log=lambda *_: None)
    lines, creatures, left_out = voice_make.pack_tables(world.data, CFG, "all")
    assert creatures == {2079: "m", 1992: ("f", "old")}
    assert sorted(lines["456-description"]["variants"]) == ["f", "old"]
    fkey = voice.gossip_key(hash_key(normalize_v1("Welcome, madam.")))
    assert lines[fkey] is lines["g-0123456789abcdef"] and left_out == []


# ---- the commands ----------------------------------------------------------------------------------------


def test_the_cast_command_writes_voices_and_counts_rows(world, capsys):
    voice_make._write(world.data / "voice" / "profiles.jsonl", [
        {"creature": 1992, "gender": "female", "provenance": {}},
        {"creature": 2079, "gender": "male", "provenance": {}},
        {"creature": 3000, "provenance": {}},
    ])
    assert voice_make.run(["cast", "--config", str(world.cfg)]) == 0
    rows = {r["creature"]: (r["voice"], r["row"]) for r in voice_make._rows(world.data / "voice" / "voices.jsonl")}
    assert rows == {1992: ("f", "female"), 2079: ("m", "male"), 3000: ("m", "narrator")}
    out = capsys.readouterr().out.splitlines()
    assert out[0] == "voice cast: 3 creatures → data/voice/voices.jsonl"
    assert sorted(out[1:]) == ["voice cast:     1  female", "voice cast:     1  male", "voice cast:     1  narrator"]


def test_the_plan_command_prints_what_would_be_made(world, capsys):
    assert voice_make.run(["plan", "--config", str(world.cfg)]) == 0
    out = capsys.readouterr().out.splitlines()
    assert out[0].startswith("voice plan (all): 3 files; to make 3 new + 0 changed, 24 characters, about 0.0 h")
    assert "voice plan: cast row female: 1" in out and "voice plan: cast row narrator: 1" in out
    assert "voice plan: voice m: 2" in out and "voice plan: voice f: 1" in out


def test_the_plan_command_refuses_unknown_players(world, capsys):
    assert voice_make.run(["plan", "--config", str(world.cfg), "--players", "elf-m"]) == 1
    assert capsys.readouterr().err.startswith("voice plan: --players 'elf-m'")


def _fake_lame(monkeypatch):
    """The encoder writes its output file; the real lame is not run."""
    def run(args, check):
        assert args[: len(voice_make.LAME)] == list(voice_make.LAME) and check
        with open(args[-1], "wb") as f:
            f.write(b"MP3")
        return subprocess.CompletedProcess(args, 0)

    fake = SimpleNamespace(run=run, CalledProcessError=subprocess.CalledProcessError)
    monkeypatch.setattr(voice_make, "subprocess", fake)
    monkeypatch.setattr(voice_make, "Engine", FakeEngine)


def test_the_generate_command_makes_files_into_a_store_checkout(world, monkeypatch, capsys):
    _fake_lame(monkeypatch)
    (world.store / ".git").mkdir(parents=True)
    no_engine = str(world.store / "no-engine")  # the fake engine answers; nothing is started
    assert voice_make.run(["generate", "--config", str(world.cfg), "--store", str(world.store),
                           "--engine-run", no_engine]) == 0
    assert capsys.readouterr().out.startswith("voice generate: made 3 of 3 files in ")
    assert voice_make.audio_file(world.store, "456-description").read_bytes() == b"MP3"
    assert not list((world.store / "audio").glob("*.wav"))  # the WAV handed to the encoder is removed
    assert voice_make.audio_record(world.data)["456-description"]["provenance"]["source"] == "aivis@1.2.0"


def test_the_generate_command_refuses_a_store_that_is_not_a_checkout(world, monkeypatch, capsys):
    _fake_lame(monkeypatch)
    assert voice_make.run(["generate", "--config", str(world.cfg), "--store", str(world.store),
                           "--engine-run", str(world.store / "no-engine")]) == 1
    err = capsys.readouterr().err
    assert err.startswith("voice generate: 3 file(s) to make, but ") and "git clone" in err


def _status(store, **kw):
    store.mkdir(parents=True, exist_ok=True)
    fields = {"scope": "all", "pid": 0, "done": 5, "total": 10, "rate": 12.5, "seconds_left": 7200,
              "finished": False, **kw}
    (store / "status.json").write_text(json.dumps(fields))


def test_status_says_finished_running_or_stopped(tmp_path):
    assert voice_make.status_lines(tmp_path) == [f"voice status: no run recorded in {tmp_path}"]
    _status(tmp_path, finished=True, seconds_left=None)
    assert voice_make.status_lines(tmp_path) == [
        "voice status: finished: 5/10 files (all), 12.5 characters a second"]
    _status(tmp_path, pid=os.getpid())
    assert voice_make.status_lines(tmp_path) == [
        "voice status: running: 5/10 files (all), 12.5 characters a second, about 2.0 h left"]
    _status(tmp_path, pid=2**22 + 12345)  # no such process
    assert voice_make.status_lines(tmp_path)[0].startswith(
        "voice status: stopped (resume with make voice-run): 5/10 files")
    _status(tmp_path, pid="not a pid")
    assert "stopped" in voice_make.status_lines(tmp_path)[0]


def test_the_status_command_prints_the_status(world, capsys):
    _status(world.store, finished=True)
    assert voice_make.run(["status", "--store", str(world.store)]) == 0
    assert capsys.readouterr().out.startswith("voice status: finished: 5/10 files (all)")


def test_the_record_hashes_command_fails_while_a_file_is_missing(world, capsys):
    voice_make.generate(world.data, "all", CFG, world.store, FakeEngine(), _fake_encode, log=lambda *_: None)
    rows = voice_make._rows(world.data / "voice" / voice_make.AUDIO)
    assert voice_make.run(["record-hashes", "--store", str(world.store)]) == 0  # every row has its hash
    assert capsys.readouterr().out == "voice record-hashes: 0 row(s) given their file's sha256\n"
    voice_make._write(world.data / "voice" / voice_make.AUDIO,
                      [{k: v for k, v in r.items() if k != "sha256"} for r in rows])
    voice_make.audio_file(world.store, "456-completion").write_bytes(b"another size")
    assert voice_make.run(["record-hashes", "--store", str(world.store)]) == 1
    io = capsys.readouterr()
    assert io.out == "voice record-hashes: 2 row(s) given their file's sha256\n"
    assert "1 file(s) missing or not the recorded size, left as they are, e.g. 456-completion" in io.err


def test_a_broken_config_fails_the_command(world, capsys):
    world.cfg.write_text('narrator = "zz"\nbook_narrator = "zz"\n', encoding="utf-8")
    assert voice_make.run(["cast", "--config", str(world.cfg)]) == 1
    assert capsys.readouterr().err == (
        "voice cast: voice.toml: narrator voice 'zz' is not in the roster; narrator voice 'zz' is not in the roster\n")


def test_the_store_outside_a_git_checkout_is_beside_data(tmp_path, monkeypatch):
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    monkeypatch.delenv("VOICE_ROOT", raising=False)
    monkeypatch.chdir(tmp_path)
    assert voice_make.store_dir(None) == tmp_path.resolve() / "build" / "voice"


def test_the_store_in_a_git_checkout_is_the_main_checkouts(tmp_path, monkeypatch):
    repo = tmp_path / "repo"
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    monkeypatch.delenv("VOICE_ROOT", raising=False)
    monkeypatch.chdir(repo)
    assert voice_make.store_dir(None) == repo.resolve() / "build" / "voice"


# ---- validate's voice rule -------------------------------------------------------------------------------


def test_validate_flags_a_cast_out_of_step_with_the_config(world, capsys):
    from wfj.cmd.validate import rule_voice

    assert rule_voice(world.data, world.cfg) == [
        "voice voices: 3 creature(s) not cast as voice.toml casts them now (e.g. [1992, 2079, 3000]); "
        "run make voice-cast"]  # no profiles yet: nobody would be cast as the table says
    assert capsys.readouterr().out == "validate: voice: 3 files; 0 in step, 0 stale, 3 not made\n"
    ruled = {"source": "maintainer", "imported": "2026-10-08"}
    voice_make._write(world.data / "voice" / "profiles.jsonl", [
        {"creature": 1992, "gender": "female", "provenance": {"gender": ruled}},
        {"creature": 2079, "gender": "male", "provenance": {"gender": ruled}},
    ])
    cfg = voice_make.load_config(world.cfg)
    voice_make._write(world.data / "voice" / "voices.jsonl", voice_make.cast_rows(world.data, cfg, "2026-10-08"))
    voice_make.generate(world.data, "all", cfg, world.store, FakeEngine(), _fake_encode, log=lambda *_: None)
    assert rule_voice(world.data, world.cfg) == []
    assert capsys.readouterr().out == "validate: voice: 3 files; 3 in step, 0 stale, 0 not made\n"


def test_validate_reports_a_broken_config(world):
    from wfj.cmd.validate import rule_voice

    world.cfg.write_text('narrator = "zz"\nbook_narrator = "zz"\n', encoding="utf-8")
    assert rule_voice(world.data, world.cfg) == [
        "voice: voice.toml: narrator voice 'zz' is not in the roster; narrator voice 'zz' is not in the roster"]


# ---- the coverage page's voice section -------------------------------------------------------------------


def test_the_coverage_page_counts_voiced_files_and_silent_lines_by_reason(world):
    from wfj.dev import coverage

    assert coverage.voice_coverage(world.data) == {}  # no voice.toml beside data/: no section
    (world.tmp / "pipeline").mkdir()
    (world.tmp / "pipeline" / "voice.toml").write_text(TOML, encoding="utf-8")
    store, english = Store(world.data), Store(world.data, english=True)
    store.save("quest", [*store.load("quest"),
                         {"id": 457, "field": "description", "ja": "話し手のいない依頼。", "status": "trusted"}])
    store.save("gossip", [*store.load("gossip"),
                          {"id": "fedcba9876543210", "field": "text", "ja": "記録の行。", "status": "trusted"}])
    english.save("gossip", [{"id": "fedcba9876543210", "field": "text", "en": "Return to the camp.",
                             "hash": "fedcba9876543210", "src": "wdb@70245"}])
    store.save("book", [
        {"id": "aaaaaaaaaaaaaaaa", "field": "text", "ja": "署名のない頁。", "status": "trusted",
         "english": {"hash": "aaaaaaaaaaaaaaaa"}},
        {"id": "bbbbbbbbbbbbbbbb", "field": "text", "ja": "<HTML><BODY><P>地図。</P></BODY></HTML>",
         "status": "trusted", "english": {"hash": "bbbbbbbbbbbbbbbb"}},
    ])
    voice_make.generate(world.data, "all", CFG, world.store, FakeEngine(), _fake_encode, log=lambda *_: None)
    _store(world.tmp, ja456="変わった、{name}。")  # one voiced line changed after its file was made
    store.save("quest", [*store.load("quest"),
                         {"id": 457, "field": "description", "ja": "話し手のいない依頼。", "status": "trusted"}])
    got = coverage.voice_coverage(world.data)
    assert got["kinds"] == {"description": {"files": 1, "stale": 1, "lines": 1},
                            "completion": {"files": 1, "in_step": 1, "lines": 1},
                            "g": {"files": 1, "in_step": 1, "lines": 1}}
    assert got["narrator"] == {"g": 1} and got["shared"] == 0
    assert got["silent"] == {"No speaker found for the quest": 1,
                             "A quest log line (the completion text the tracker shows)": 1,
                             "Book and letter pages: no speaker": 1,
                             "HTML book page (keeps the client's layout)": 1}
    page = "\n".join(coverage._render_voice({**got, "silent": {}}))
    assert "| Quest offer | 1 | 1 | 0 | 1 | 0 | 0 |" in page
    assert page.endswith("### Silent lines\n\nShipped Japanese the voice does not read, by reason.\n\nNone.")
