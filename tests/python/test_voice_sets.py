"""Cloned game voice sets (ADR-074): Spoken's set per NPC, the set catalogue and references, the clone cast,
the fingerprint, the Qwen3-TTS engine, generation, the gender check and the listening page."""

from __future__ import annotations

import gzip
import json
import subprocess
import sys
import wave
from pathlib import Path

import pytest
from test_voice import CFG, SRC, _fake_encode, _store, _wav

from wfj.cmd import voice_make, voice_sets_page
from wfj.cmd import voice_sets as vs
from wfj.core import casting, voice, voice_sets
from wfj.io.qwen import LineFailed, Qwen, QwenBusy, QwenError

ROOT = Path(__file__).resolve().parents[2]
FAKE_WORKER = Path(__file__).with_name("fake_qwen.py")
TODAY = "2026-11-06"


# ---- set names --------------------------------------------------------------------------------------------


def test_set_names_parse_with_the_display_tables_race_names():
    assert voice_sets.parse("nightelfmalewarriornpc") == ("nightelf", "male", "warrior")
    assert voice_sets.parse("undeadfemalemagicnpc") == ("scourge", "female", "magic")
    assert voice_sets.parse("skybourneelfmale3776npc") == ("skyborne", "male", "3776")
    assert voice_sets.parse("kinganduinwrynn") is None
    assert voice_sets.parse("murlocnpc") is None
    assert voice_sets.voice_id("humanmalestandardnpc") == "qhumanmalestandard"


# ---- Spoken's assignment -----------------------------------------------------------------------------------


def _corpus(*lines):
    return {"lines": [dict(npcType="creature", **ln) for ln in lines]}


def test_each_npc_takes_the_voice_most_of_its_spoken_lines_use_per_gender():
    corpus = _corpus(
        {"npcId": 1, "voice": "human-male-standard"}, {"npcId": 1, "voice": "human-male-standard"},
        {"npcId": 1, "voice": "human-male-official"},
        {"npcId": 2, "voice": "scourge-female-magic"},
        {"npcId": 3, "voice": "human-male-warrior"}, {"npcId": 3, "voice": "human-female-warrior"},
        {"npcId": 4, "voice": "skybourneelf-male-3776"},
        {"npcId": 5, "voice": "narrator-male"}, {"npcId": 6, "voice": "model-32"},
    )
    corpus["lines"].append({"npcType": "gameobject", "npcId": 7, "voice": "human-male-standard"})
    got = vs.spoken_sets(corpus)
    assert got == {
        1: {"male": "humanmalestandardnpc"},
        2: {"female": "undeadfemalemagicnpc"},
        3: {"male": "humanmalewarriornpc", "female": "humanfemalewarriornpc"},
        4: {"male": "skybourneelfmale3776npc"},
    }


def test_an_npc_spoken_lists_with_a_set_but_no_lines_takes_that_set_and_lines_still_win():
    corpus = {
        "lines": [{"npcType": "creature", "npcId": 1, "voice": "human-male-standard"}],
        "npcs": [
            {"npcType": "creature", "npcId": 1, "voice": "human-male-warrior"},  # its lines win
            {"npcType": "creature", "npcId": 5, "voice": "nightelf-female-standard"},
            {"npcType": "creature", "npcId": 6, "voice": "narrator-male"},  # no game set
            {"npcType": "creature", "npcId": 7, "voice": "model-32"},
            {"npcType": "gameobject", "npcId": 8, "voice": "human-male-standard"},
        ],
    }
    assert vs.spoken_sets(corpus) == {
        1: {"male": "humanmalestandardnpc"},
        5: {"female": "nightelffemalestandardnpc"},
    }


def test_creature_rows_keep_their_date_while_unchanged_and_skip_npcs_with_no_set():
    sets = {1: {"male": "humanmalestandardnpc"}}
    first = vs.creature_rows({1, 2}, sets, "spoken@3219d17", [], "2026-11-01")
    assert first == [{"creature": 1, "male": "humanmalestandardnpc",
                      "provenance": {"source": "spoken@3219d17", "imported": "2026-11-01"}}]
    assert vs.creature_rows({1}, sets, "spoken@3219d17", first, TODAY) == first
    moved = vs.creature_rows({1}, {1: {"male": "humanmaleofficialnpc"}}, "spoken@3219d17", first, TODAY)
    assert moved[0]["provenance"]["imported"] == TODAY


def test_run_creatures_writes_the_table_from_a_corpus_file(tmp_path, monkeypatch):
    data = _store(tmp_path)
    corpus = tmp_path / "corpus.json.gz"
    with gzip.open(corpus, "wt", encoding="utf-8") as f:
        json.dump(_corpus({"npcId": 2079, "voice": "nightelf-male-standard"}), f)
    assert vs.run_creatures(data, corpus, "3219d17badfe", TODAY) == 0
    rows = vs._rows(data / "voice" / vs.CREATURE_SETS)
    assert rows == [{"creature": 2079, "male": "nightelfmalestandardnpc",
                     "provenance": {"source": "spoken@3219d17", "imported": TODAY}}]


# ---- clips, catalogue and references ----------------------------------------------------------------------


def test_clip_files_find_greetings_farewells_and_vendor_lines_only(tmp_path):
    lf = tmp_path / "listfile.csv"
    lf.write_text("\n".join([
        "1;sound/creature/humanmalestandardnpc/humanmalestandardnpcgreetings01.ogg",
        "2;sound/creature/humanmalestandardnpc/humanmalestandardnpcpissed01.ogg",
        "3;sound/creature/humanmalestandardnpc/humanmalestandardnpcvendor02.ogg",
        "4;sound/creature/gnomemalezanynpc/gnomemalezanyfarewell03.ogg",
        "5;sound/creature/humanmalestandardnpc/humanmalestandardnpcgreetings01.ogg.meta",
        "6;sound/creature/murloc/mmurlocattacka.ogg",
    ]) + "\n")
    assert vs.clip_files(lf) == {
        "gnomemalezanynpc": [(4, "gnomemalezanyfarewell03")],
        "humanmalestandardnpc": [(1, "humanmalestandardnpcgreetings01"), (3, "humanmalestandardnpcvendor02")],
    }


def test_numbered_sets_take_the_greeting_and_farewell_kits_of_their_npc_sounds_row():
    rows = {3776: ([10, 11, 12, 0],)}
    kits = {10: [101, 100], 11: [110], 12: [120]}
    got = vs.numbered_clips(rows, kits, ["skybourneelfmale3776npc", "humanmalestandardnpc"])
    assert got == {"skybourneelfmale3776npc": [
        (100, "skybourneelfmale3776npcgreeting01"), (101, "skybourneelfmale3776npcgreeting02"),
        (110, "skybourneelfmale3776npcfarewell01")]}


def test_a_transcript_in_a_fantasy_language_stays_out_of_full_copies():
    words = {"safe", "travel", "be", "with", "you", "elune"}
    assert vs.plain_english("Safe travels!", words)
    assert vs.plain_english("Elune be with you.", words)
    assert not vs.plain_english("Ishnu Dal Diyeb.", words)
    assert not vs.plain_english("", words)


def test_the_catalogue_keeps_a_fixed_transcript_and_takes_new_clips_from_the_model():
    files = {"humanmalestandardnpc": [(1, "humanmalestandardnpcgreetings01"), (2, "humanmalestandardnpcfarewell01")]}
    fixed = {"name": "humanmalestandardnpcgreetings01", "file": 1, "en": "Hello there!", "full": True,
             "provenance": {"source": "machine", "model": "m", "batch": "fix", "reason": "r", "imported": TODAY}}
    old = [{"set": "humanmalestandardnpc", "clips": [fixed]}]
    rows = vs.catalogue_rows(files, {"humanmalestandardnpcfarewell01": "Safe travels."}, old, "whisper-small",
                             "client@1", TODAY, {"safe", "travels"})
    assert rows[0]["gender"] == "male"
    assert rows[0]["clips"][0] == fixed
    new = rows[0]["clips"][1]
    assert (new["en"], new["full"], new["provenance"]["model"]) == ("Safe travels.", True, "whisper-small")


def _clip(path: Path, seconds: float) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(_wav(seconds, 24000))


def _row():
    return {"set": "orcfemalestandardnpc", "gender": "female", "clips": [
        {"name": "a", "file": 1, "en": "Speak, friend.", "full": True},
        {"name": "b", "file": 2, "en": "Zug zug!", "full": False},
    ]}


def test_a_reference_joins_the_clips_and_a_full_copy_uses_only_plain_english_ones(tmp_path):
    clips = tmp_path / "clips"
    _clip(clips / "orcfemalestandardnpc" / "a.wav", 0.5)
    _clip(clips / "orcfemalestandardnpc" / "b.wav", 1.0)
    voice_ref, text = vs.reference(_row(), "voice", clips, tmp_path / "refs")
    assert text is None
    with wave.open(str(voice_ref)) as w:
        assert w.getnframes() / w.getframerate() == pytest.approx(0.5 + 1.0 + 2 * vs.GAP)
    full_ref, text = vs.reference(_row(), "full", clips, tmp_path / "refs")
    assert text == "Speak, friend."
    with wave.open(str(full_ref)) as w:
        assert w.getnframes() / w.getframerate() == pytest.approx(0.5 + vs.GAP)
    assert vs.ref_hash(_row(), "voice") != vs.ref_hash(_row(), "full")


def test_a_set_with_no_clip_for_the_mode_or_an_uncut_clip_is_refused(tmp_path):
    row = {"set": "x", "clips": [{"name": "a", "file": 1, "en": "Zug!", "full": False}]}
    with pytest.raises(ValueError, match="no clip"):
        vs.reference(row, "full", tmp_path, tmp_path / "refs")
    with pytest.raises(ValueError, match="not cut"):
        vs.reference(row, "voice", tmp_path, tmp_path / "refs")


# ---- roster, fingerprint and cast --------------------------------------------------------------------------


def test_picked_sets_become_cloned_roster_voices_and_kept_sets_do_not():
    cat = {"orcfemalestandardnpc": _row()}
    got = voice_make.set_voices({"orcfemalestandardnpc": {"pick": "full"}, "humanmalestandardnpc": {"pick": "keep"}},
                                cat)
    assert list(got) == ["qorcfemalestandard"]
    v = got["qorcfemalestandard"]
    assert (v["engine"], v["set"], v["mode"], v["licence"]) == ("qwen", "orcfemalestandardnpc", "full", "Apache-2.0")
    assert v["ref"] == vs.ref_hash(_row(), "full")
    assert not casting.roster_problems(got, [], "qorcfemalestandard", "qorcfemalestandard")
    assert casting.roster_problems({"q": {"engine": "qwen", "set": "x", "mode": "loud", "licence": "Apache-2.0"}},
                                   [], "q", "q")


def test_an_aivis_fingerprint_is_unchanged_and_a_cloned_one_names_its_set_mode_and_reference():
    m = CFG["roster"]["m"]
    assert voice.fingerprint("abc", "m", m) == "abc|m|11|0.9|0|1"
    q = {"engine": "qwen", "set": "humanmalestandardnpc", "mode": "voice", "ref": "r1"}
    assert voice.fingerprint("abc", "qhumanmalestandard", q) == "abc|qhumanmalestandard|qwen|humanmalestandardnpc|voice|r1"
    assert voice.fingerprint("abc", "qhumanmalestandard", {**q, "mode": "full"}) != voice.fingerprint(
        "abc", "qhumanmalestandard", q)


ROSTER = {"qhumanmalestandard": {}, "qhumanfemalestandard": {}, "qorcmaleguard": {}}
SETS = {
    1: {"male": "humanmalestandardnpc"},
    2: {"male": "humanmalestandardnpc", "female": "humanfemalestandardnpc"},
    3: {"male": "orcmaleguardnpc"},
    4: {"female": "humanfemalestandardnpc"},
    5: {"male": "dwarfmaleguardnpc"},  # its set is kept on AivisSpeech: no roster voice
}
CAST = {c: {"voice": "m", "row": "male"} for c in (1, 2, 3, 5, 6)} | {4: {"voice": "f", "row": "female"}}


def test_npcs_of_a_cloned_pack_speak_with_their_set_and_everyone_else_keeps_their_cast():
    homes = {1: "P1", 2: "P1", 3: "P2", 4: "P1", 5: "P1", 6: "P1"}
    got = voice_sets.clone_cast(CAST, SETS, homes, ["P1"], ROSTER)
    assert got[1] == {"voice": "qhumanmalestandard", "row": "set humanmalestandardnpc"}
    assert got[2] == {"voice": "qhumanmalestandard", "row": "set humanmalestandardnpc",
                      "female": "qhumanfemalestandard", "female_row": "set humanfemalestandardnpc"}
    assert got[3] == CAST[3]  # its home pack is not cloned yet
    assert got[4] == {"voice": "qhumanfemalestandard", "row": "set humanfemalestandardnpc"}
    assert got[5] == CAST[5]  # kept on its AivisSpeech cast
    assert got[6] == CAST[6]  # no game voice set
    assert voice_sets.clone_cast(CAST, SETS, homes, ["P1"], ROSTER, pinned=[1])[1] == CAST[1]


def test_home_pack_is_the_lowest_band_of_an_npcs_quests(tmp_path):
    from wfj.cmd import voice
    from wfj.core import voice_packs as vp

    data = _store(tmp_path)
    voice.write_rows(data / "voice" / "speakers.jsonl", [
        {"key": "10-description", "speaker": 1, "provenance": SRC},
        {"key": "20-completion", "speaker": 1, "provenance": SRC},
        {"key": "20-description", "speaker": 2, "provenance": SRC},
        {"key": "g-0123456789abcdef", "speaker": 3, "provenance": SRC},
    ])
    table = vp.load(ROOT / "pipeline" / "voice-packs.toml")
    homes = vs.home_packs(data, table, {10: 15, 20: 3})
    assert homes[1] == homes[2] == table.packs[0].folder
    assert homes[3] == table.packs[0].folder  # talk only: the first band
    assert vs.home_packs(data, table, {10: 15, 20: 35})[1] == table.packs[1].folder


# ---- gender ----------------------------------------------------------------------------------------------


def test_a_speaker_cast_to_a_voice_of_the_other_gender_is_reported_unless_spoken_set_it():
    roster = {"m": {"model": "M"}, "f": {"model": "F"}, "n": {"model": "N"},
              "qhumanfemalestandard": {"engine": "qwen", "set": "humanfemalestandardnpc"},
              "qgnomemalezany": {"engine": "qwen", "set": "gnomemalezanynpc"}}
    genders = voice_sets.voice_genders(roster, {"M": "male", "F": "female", "N": "other"})
    assert genders == {"m": "male", "f": "female", "qhumanfemalestandard": "female", "qgnomemalezany": "male"}
    profiles = {1: {"gender": "female"}, 2: {"gender": "male"}, 3: {"gender": "male"}, 4: {"gender": "mixed"},
                5: {"gender": "female"}, 6: {"gender": "mixed"}}
    spoken = {3: {"female": "humanfemalestandardnpc"}}
    cast = {1: {"voice": "m", "row": "x"}, 2: {"voice": "n", "row": "x"},
            3: {"voice": "qhumanfemalestandard", "row": "set humanfemalestandardnpc"}, 4: {"voice": "f", "row": "x"},
            5: {"voice": "qgnomemalezany", "row": "set gnomemalezanynpc"},  # a cast rule, not Spoken: checked
            6: {"voice": "m", "row": "x", "female": "qgnomemalezany"}}
    assert voice_sets.gender_problems(cast, profiles, genders, roster, spoken) == [
        "voice voices 1: a female speaker cast to m, a male voice",
        "voice voices 5: a female speaker cast to qgnomemalezany, a male voice",
        "voice voices 6: its female variant qgnomemalezany is a male voice"]


# ---- the engine ------------------------------------------------------------------------------------------


def test_the_qwen_client_reads_a_line_and_reports_a_worker_error(tmp_path, monkeypatch):
    log = tmp_path / "requests.jsonl"
    monkeypatch.setenv("FAKE_QWEN_LOG", str(log))
    with Qwen(Path(sys.executable), worker=FAKE_WORKER, lock=tmp_path / "lock") as q:
        assert q.version == "0.0.test"
        wav = q.synthesize("こんにちは。", tmp_path / "ref.wav", None, "voice")
        assert wav[:4] == b"RIFF"
        with pytest.raises(LineFailed, match="asked to fail"):  # one line failed; the worker goes on
            q.synthesize("FAIL", tmp_path / "ref.wav", "Hi.", "full")
    req = json.loads(log.read_text().splitlines()[0])
    assert (req["text"], req["mode"], req["ref_text"]) == ("こんにちは。", "voice", None)


def test_only_one_run_may_hold_the_engine_and_it_runs_at_low_priority(tmp_path):
    from wfj.io import qwen

    assert qwen.NICE[0] == "nice" and int(qwen.NICE[-1]) > 0
    with Qwen(Path(sys.executable), worker=FAKE_WORKER, lock=tmp_path / "lock"), pytest.raises(QwenBusy):
        Qwen(Path(sys.executable), worker=FAKE_WORKER, lock=tmp_path / "lock").__enter__()
    with pytest.raises(QwenError, match="voice-qwen-setup"):
        Qwen(tmp_path / "no-python", lock=tmp_path / "lock").__enter__()


def test_generate_makes_cloned_voices_through_qwen_without_starting_aivisspeech(tmp_path, monkeypatch):
    data = _store(tmp_path)
    clips = tmp_path / "clips"
    _clip(clips / "nightelfmalestandardnpc" / "a.wav", 0.5)
    vs._write(data / "voice" / vs.SETS, [{"set": "nightelfmalestandardnpc", "gender": "male", "clips": [
        {"name": "a", "file": 1, "en": "Greetings.", "full": True}]}])
    cfg = json.loads(json.dumps(CFG))
    cfg["roster"].update(voice_make.set_voices({"nightelfmalestandardnpc": {"pick": "voice"}},
                                               vs.catalogue(data)))
    voice.jobs  # noqa: B018 - the cast below sends only 2079's line to the cloned voice
    from wfj.cmd import voice as cmd
    cmd.write_rows(data / "voice" / "voices.jsonl", [
        {"creature": 1992, "voice": "f", "row": "female", "provenance": SRC},
        {"creature": 2079, "voice": "qnightelfmalestandard", "row": "set nightelfmalestandardnpc", "provenance": SRC},
    ])
    voice_make._write(data / "voice" / "audio.jsonl", [])
    log = tmp_path / "requests.jsonl"
    monkeypatch.setenv("FAKE_QWEN_LOG", str(log))

    class NoEngine:
        url = "http://127.0.0.1:9"

        def synthesize(self, *a):
            return _wav()

    started = []
    monkeypatch.setattr(voice_make, "running", lambda *a, **k: started.append(1) or _Ctx("9.9"))
    cfg_narrow = {**cfg}
    r = voice_make.generate(
        data, "all", cfg_narrow, tmp_path / "store", NoEngine(), _fake_encode, log=lambda *_: None,
        qwen=lambda: Qwen(Path(sys.executable), worker=FAKE_WORKER, lock=tmp_path / "lock"), clips=clips)
    assert r["made"] == 3
    rec = voice_make.audio_record(data)["456-description"]
    assert rec["provenance"]["source"] == "qwen3-tts@0.0.test"
    # the line says the player's stand-in, so the engine's text is not the spoken line: its hash is recorded
    ja_h, said = rec["fingerprint"].split("|")[0], rec["fingerprint"].split("|")[-1]
    assert len(rec["fingerprint"].split("|")) == 7
    assert rec["fingerprint"] == voice.fingerprint(ja_h, "qnightelfmalestandard",
                                                   cfg["roster"]["qnightelfmalestandard"], said)
    assert voice_make.audio_record(data)["456-completion"]["provenance"]["source"] == "aivis@9.9"
    assert json.loads(log.read_text())["mode"] == "voice"
    assert (clips / voice_make.REFS_DIR).is_dir()  # references stay beside the clips, never in the store
    assert not (tmp_path / "store" / voice_make.REFS_DIR).exists()


def test_a_line_the_engine_cannot_read_is_left_to_make_and_the_run_goes_on(tmp_path, monkeypatch):
    data = _store(tmp_path)
    voice_make._write(data / "voice" / "audio.jsonl", [])
    real = voice_make._synth

    def synth(text, settings, *rest):
        if settings is CFG["roster"]["f"]:
            raise LineFailed("Qwen3-TTS: ValueError: the reading ran on")
        return real(text, settings, *rest)

    class Engine:
        url = "http://127.0.0.1:9"

        def synthesize(self, *a):
            return _wav()

    monkeypatch.setattr(voice_make, "_synth", synth)
    monkeypatch.setattr(voice_make, "running", lambda *a, **k: _Ctx("9.9"))
    said = []
    r = voice_make.generate(data, "all", {**CFG},
                            tmp_path / "store", Engine(), _fake_encode, log=said.append)
    rec = voice_make.audio_record(data)
    assert r["made"] == len(rec) and r["made"] < r["files"]  # the others were made and recorded
    assert any("left to make next run" in m for m in said)


def test_a_second_voice_run_refuses_while_one_holds_the_record(tmp_path, monkeypatch):
    monkeypatch.setattr(voice_make, "_main_checkout", lambda: tmp_path)
    with voice_make.run_lock(), pytest.raises(ValueError, match="one runs at a time"), voice_make.run_lock():
        pass
    with voice_make.run_lock():  # let go when the first run ends
        pass


def test_a_whole_game_run_drops_records_of_files_no_line_uses():
    jobs = [voice.Job(stem="1-description", key="1-description", voice="m")]
    audio = {"1-description": {}, "1-description_old": {}}
    voice_make._drop_unused(audio, jobs, "shadowglen", voice_make.players_of("all"))
    assert set(audio) == {"1-description", "1-description_old"}  # a narrower run never drops anything
    voice_make._drop_unused(audio, jobs, "all", [("human", "m")])
    assert set(audio) == {"1-description", "1-description_old"}
    voice_make._drop_unused(audio, jobs, "all", voice_make.players_of("all"))
    assert set(audio) == {"1-description"}


class _Ctx:
    def __init__(self, v):
        self.v = v

    def __enter__(self):
        return self.v

    def __exit__(self, *a):
        return False


# ---- the listening page ----------------------------------------------------------------------------------


def test_the_page_saves_only_known_picks_and_apply_writes_them_into_voice_toml(tmp_path):
    saved = tmp_path / "picks.json"
    voice_sets_page.save_pick(saved, json.dumps({"set": "orcfemalestandardnpc", "pick": "voice",
                                                 "decided": True}).encode())
    for bad in ({"set": "nope", "pick": "voice"}, {"set": "orcmaleguardnpc", "pick": "loud"},
                {"set": "orcmaleguardnpc", "pick": "keep"}):
        with pytest.raises(ValueError):
            voice_sets_page.save_pick(saved, json.dumps(bad).encode())
    assert json.loads(saved.read_text()) == {"orcfemalestandardnpc": {"pick": "voice", "decided": True}}
    cfg = tmp_path / "voice.toml"
    cfg.write_text((ROOT / "pipeline" / "voice.toml").read_text(encoding="utf-8"), encoding="utf-8")
    assert voice_sets_page.apply(cfg, saved) == 0
    assert '[sets.orcfemalestandardnpc]\npick = "voice"\ndecided = true\n' in cfg.read_text(encoding="utf-8")
    assert voice_sets_page.current_picks(cfg, tmp_path / "none.json")["orcfemalestandardnpc"] == {
        "pick": "voice", "decided": True}


def test_the_page_has_a_row_with_every_take_and_the_pick_controls_per_set():
    rows = [{"set": "orcfemalestandardnpc", "race": "orc", "gender": "female", "flavour": "standard", "npcs": 3}]
    files = {"orcfemalestandardnpc": {"game": "g.mp3", "voice": "v.mp3", "full": "f.mp3"}}
    html_text = voice_sets_page.page(rows, {"orcfemalestandardnpc": {"pick": "voice", "decided": True}}, files)
    for want in ('src="g.mp3"', 'src="v.mp3"', 'src="f.mp3"', 'value="voice" checked',
                 'data-set="orcfemalestandardnpc" checked'):
        assert want in html_text
    assert 'value="keep"' not in html_text  # every set is cloned: there is no other voice to keep
    undecided = voice_sets_page.page(rows, {}, files)
    assert 'value="full" checked' in undecided  # an undecided female set follows the default rule


# ---- the committed data and config -------------------------------------------------------------------------


def test_the_committed_sets_and_picks_agree():
    from wfj.paths import data_root

    cfg = voice_make.load_config(ROOT / "pipeline" / "voice.toml")
    cat = vs.catalogue(data_root())
    used = {s for r in vs._rows(data_root() / "voice" / vs.CREATURE_SETS) for g in voice_sets.GENDERS
            if (s := r.get(g))}
    assert used <= set(cat), sorted(used - set(cat))
    assert set(cfg["sets"]) == set(cat)
    for s, row in cat.items():
        assert voice_sets.parse(s) and row["clips"], s
        assert all(c["en"] is not None and c.get("provenance") for c in row["clips"]), s
    from wfj.core import voice_packs as vp

    table = vp.load(ROOT / "pipeline" / "voice-packs.toml")
    assert set(cfg["cloned_packs"]) == {p.folder for p in table.packs}  # every pack: no other voice ships


def test_no_game_audio_is_tracked_in_the_repository():
    tracked = subprocess.run(["git", "ls-files", "*.ogg", "*.wav"], cwd=ROOT, capture_output=True, text=True,
                             check=True).stdout.split()
    assert not [t for t in tracked if not t.startswith("tests/")], tracked


def test_a_pack_credits_the_clone_engine_for_its_cloned_files_and_aivisspeech_for_the_rest():
    from wfj.cmd import voice_ship

    cfg = {"credits": {"engine": "AivisSpeech", "clone_engine": "Qwen3-TTS"}, "roster": {
        "m": {"model": "M", "licence": "ACML 1.0"},
        "qa": {"engine": "qwen", "set": "humanmalestandardnpc", "licence": "Apache-2.0"}}}
    audio = {"a": {"voice": "m"}, "b": {"voice": "qa"}}
    both = voice_ship._credits(cfg, audio, ["a.mp3", "b.mp3"])
    assert both == {"engine": "AivisSpeech; Qwen3-TTS",
                    "models": "M, voices modelled on the game's own NPC voice sets",
                    "licence": "voice models ACML 1.0; speech engine Apache-2.0; the game's NPC recordings the"
                               " voices are modelled on belong to Blizzard Entertainment"}
    assert voice_ship._credits(cfg, audio, ["b.mp3"])["engine"] == "Qwen3-TTS"
    assert voice_ship._credits(cfg, audio, ["a.mp3"])["engine"] == "AivisSpeech"


# ---- speed -----------------------------------------------------------------------------------------------


def test_slow_is_one_engine_in_the_background_and_fast_is_several_at_full_speed(tmp_path):
    assert voice_make.speed_of("slow") == (1, True)
    assert voice_make.speed_of("fast") == (voice_make.FAST_WORKERS, False)
    assert voice_make.FAST_WORKERS > 1
    f = tmp_path / "speed"
    assert voice_make.read_speed(f) == "slow"  # the default while nothing is set
    f.write_text("fast\n")
    assert voice_make.read_speed(f) == "fast"
    f.write_text("warp\n")
    assert voice_make.read_speed(f) == "slow"


class _FakeEngine:
    made: list = []

    def __init__(self, n):
        self.n, self.tier, self.open = n, None, False

    def __enter__(self):
        self.open = True
        return self

    def __exit__(self, *a):
        self.open = False

    def background(self, on):
        self.tier = on


def test_a_run_follows_the_speed_asked_for_between_lines():
    """Fast for the first lines, then slow: the extra engines stop, the first one stays and goes to the
    background tier, and every line is read once."""
    import collections

    engines: list[_FakeEngine] = []

    def qwen():
        engines.append(_FakeEngine(len(engines)))
        return engines[-1]

    done: list[int] = []

    def speed():  # fast for the first four lines, then slow
        return (3, False) if len(done) < 4 else (1, True)

    voice_make._cloned_lines(collections.deque(range(8)), qwen, lambda j, q: (j, q.n),
                             lambda j, n: done.append(j), speed, lambda m: None)
    assert sorted(done) == list(range(8))
    assert len(engines) == 3
    assert engines[0].tier is True  # the engine that holds the lock ended in the background tier
    assert not any(e.open for e in engines)


# ---- batched reading (the remote run) --------------------------------------------------------------------

class _FakeModel:
    """Each paragraph reads as its length in samples of the value of its voice's number."""

    def __init__(self, fail_over: int = 99):
        self.calls, self.fail_over = [], fail_over

    def create_voice_clone_prompt(self, ref_audio, ref_text, x_vector_only_mode):
        return [{"voice": int(Path(ref_audio).stem), "x": x_vector_only_mode}]

    def generate_voice_clone(self, text, language, voice_clone_prompt, max_new_tokens=2048):
        import numpy as np

        texts = text if isinstance(text, list) else [text]
        prompts = voice_clone_prompt if isinstance(voice_clone_prompt, list) else voice_clone_prompt
        self.calls.append(len(texts))
        if len(texts) > self.fail_over:
            raise RuntimeError("CUDA out of memory")
        items = prompts if len(prompts) == len(texts) else prompts * len(texts)
        return [np.full(len(t), it["voice"], dtype=np.int16) for t, it in zip(texts, items, strict=True)], 10


def test_a_batch_reads_each_paragraph_in_its_lines_voice_and_keeps_each_lines_order():
    pytest.importorskip("numpy")  # the worker's own environment has it; the pipeline's does not
    from wfj.io import qwen_worker

    lines = [{"text": "aaaaa\n\nbb", "ref_wav": "/r/1.wav", "mode": "voice"},
             {"text": "c", "ref_wav": "/r/2.wav", "mode": "full", "ref_text": "Hi."}]
    model = _FakeModel()
    got = qwen_worker.speak_many(model, {}, lines, batch=2)
    assert model.calls == [2, 1]
    first, rate = got[0]
    gap = int(rate * qwen_worker.PARAGRAPH_GAP)
    assert list(first) == [1] * 5 + [0] * gap + [1] * 2  # "aaaaa" then "bb", in that order
    assert list(got[1][0]) == [2]
    # the same as reading each line alone
    assert list(qwen_worker.speak(_FakeModel(), {}, lines[0]["text"], "/r/1.wav", None, "voice")[0]) == list(first)


def test_a_call_that_runs_out_of_memory_is_split_until_it_fits():
    pytest.importorskip("numpy")
    from wfj.io import qwen_worker

    lines = [{"text": f"{'x' * n}", "ref_wav": f"/r/{n}.wav", "mode": "voice"} for n in (1, 2, 3)]
    model = _FakeModel(fail_over=1)
    got = qwen_worker.speak_many(model, {}, lines, batch=3)
    assert [list(a) for a, _ in got] == [[1], [2, 2], [3, 3, 3]]
    assert model.calls == [3, 1, 2, 1, 1]  # 3 too many, then halves: 1 fits, 2 too many, then 1 and 1


def test_a_call_holds_few_long_paragraphs_or_many_short_ones():
    pytest.importorskip("numpy")
    from wfj.io import qwen_worker

    lines = [{"text": "x" * n, "ref_wav": "/r/1.wav", "mode": "voice"} for n in (900, 900, 10, 10, 10)]
    model = _FakeModel()
    qwen_worker.speak_many(model, {}, lines, batch=24, chars=1500)
    assert model.calls == [3, 1, 1]  # the three short ones together; padded to 900, two long ones would not fit


# ---- the remote round (make voice-generate) ----------------------------------------------------------------


def _run_with_wavs(tmp_path, n=2):
    run = tmp_path / "build" / "voice-remote" / "2026-11-06-140000"
    (run / "wav").mkdir(parents=True)
    (run / "refs").mkdir()
    (run / "refs" / "r.wav").write_bytes(_wav())
    for k in range(n):
        (run / "wav" / f"k{k}.wav").write_bytes(_wav(0.1 * (k + 1)))
    (run / "jobs.jsonl").write_text("".join(json.dumps({"key": f"k{k}"}) + "\n" for k in range(n)))
    (run / "manifest.json").write_text('{"version": "0.1.1"}')
    return run


def test_the_archive_keeps_every_wav_checked_and_leaves_the_local_run(tmp_path):
    run = _run_with_wavs(tmp_path)
    dest = voice_make.archive_run(run, tmp_path / "archive")
    assert sorted(p.name for p in (dest / "wav").iterdir()) == ["k0.wav", "k1.wav"]
    assert (dest / "jobs.jsonl").is_file() and (dest / "manifest.json").is_file()
    assert not (dest / "refs").exists()  # the game's own clips stay on this machine
    sums = (dest / "SHA256SUMS").read_text().splitlines()
    assert sums[0] == f"{voice_make.file_sha(run / 'wav' / 'k0.wav')}  wav/k0.wav"
    assert (run / "wav" / "k0.wav").is_file()  # nothing deleted
    assert voice_make.prepared_missing(run) == 0


def test_a_remote_round_exports_reads_on_modal_and_archives(tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(voice_make, "_main_checkout", lambda: tmp_path)
    monkeypatch.setattr(voice_make.Path, "home", lambda: tmp_path)
    (tmp_path / ".modal.toml").write_text("")
    (tmp_path / "build" / "modal" / "venv" / "bin").mkdir(parents=True)
    (tmp_path / "build" / "modal" / "venv" / "bin" / "python").write_text("")

    def export(root, cfg, scope, store, out, players):
        assert players == [("human", "m")]  # the character's error lines go to the remote run too
        made = _run_with_wavs(tmp_path, 3)
        made.rename(out)
        return 3

    def fake_run(args, env, check):
        calls.append((args[-1], env["WFJ_MODAL_CONTAINERS"]))

    monkeypatch.setattr(voice_make, "export_remote", export)
    monkeypatch.setattr(voice_make.subprocess, "run", fake_run)
    run = voice_make.remote_round(tmp_path, {}, "all", tmp_path / "store", tmp_path / "archive", [("human", "m")])
    assert run is not None and calls == [(str(run), "1")]
    assert (tmp_path / "archive" / run.name / "SHA256SUMS").is_file()


def test_a_remote_round_with_nothing_cloned_to_make_reads_nothing(tmp_path, monkeypatch):
    monkeypatch.setattr(voice_make, "_main_checkout", lambda: tmp_path)
    monkeypatch.setattr(voice_make, "export_remote", lambda *a: 0)
    assert voice_make.remote_round(tmp_path, {}, "all", tmp_path, None) is None


def test_a_line_the_model_does_not_end_is_cut_at_its_cap_and_reported():
    pytest.importorskip("numpy")
    import numpy as np

    from wfj.io import qwen_worker

    class RunOn(_FakeModel):
        def generate_voice_clone(self, text, language, voice_clone_prompt, max_new_tokens=2048):
            self.caps = getattr(self, "caps", []) + [max_new_tokens]
            texts = text if isinstance(text, list) else [text]
            # the second line never ends: it fills the whole cap
            out = [np.zeros(len(t) if "never" not in t else max_new_tokens * 1000 // 12, dtype=np.int16)
                   for t in texts]
            return out, 1000

    lines = [{"text": "short", "ref_wav": "/r/1.wav", "mode": "voice"},
             {"text": "never ends", "ref_wav": "/r/1.wav", "mode": "voice"}]
    model = RunOn()
    got = qwen_worker.speak_many(model, {}, lines, batch=24)
    assert model.caps == [qwen_worker.token_cap(["short", "never ends"])]
    assert model.caps[0] < 2048  # far under the library's default
    assert not isinstance(got[0], str)
    assert "ran on" in got[1]


def test_a_short_paragraph_that_runs_on_beside_a_long_one_is_reported():
    pytest.importorskip("numpy")
    import numpy as np

    from wfj.io import qwen_worker

    long_text = "長" * 300
    short_text = "短い一文です。" * 10

    class Babble(_FakeModel):
        def generate_voice_clone(self, text, language, voice_clone_prompt, max_new_tokens=2048):
            texts = text if isinstance(text, list) else [text]
            # the short paragraph goes on for 60 s: past its own length, still under the long one's cap
            secs = [len(t) / qwen_worker.CHARS_PER_SECOND if t == long_text else 60 for t in texts]
            return [np.zeros(int(s * 1000), dtype=np.int16) for s in secs], 1000

    lines = [{"text": long_text, "ref_wav": "/r/1.wav", "mode": "voice"},
             {"text": short_text, "ref_wav": "/r/1.wav", "mode": "voice"}]
    assert qwen_worker.token_cap([long_text]) / qwen_worker.TOKENS_PER_SECOND > 60
    got = qwen_worker.speak_many(Babble(), {}, lines, batch=24, chars=100000)
    assert not isinstance(got[0], str)
    assert isinstance(got[1], str) and "ran on" in got[1]


def test_levelling_brings_every_take_to_one_loudness_without_changing_its_length():
    import shutil

    if not shutil.which("ffmpeg"):
        pytest.skip("ffmpeg is not installed here")
    import math
    import struct

    def tone(gain: float) -> bytes:
        import io

        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(24000)
            w.writeframes(b"".join(struct.pack("<h", int(gain * 12000 * math.sin(i / 8))) for i in range(48000)))
        return buf.getvalue()

    def mean_db(wav: bytes) -> float:
        import io

        with wave.open(io.BytesIO(wav)) as w:
            frames = w.readframes(w.getnframes())
        samples = struct.unpack(f"<{len(frames) // 2}h", frames)
        return 20 * math.log10(math.sqrt(sum(x * x for x in samples) / len(samples)) / 32768)

    assert voice_make.level_gain(tone(0.0)) == 0.0  # silence is not lifted by +50 dB
    loud, quiet = voice_make.levelled(tone(1.0)), voice_make.levelled(tone(0.1))
    assert abs(mean_db(loud) - mean_db(quiet)) < 1.0
    with wave.open(__import__("io").BytesIO(quiet)) as w:
        assert w.getnframes() == 48000


# ---- every speaker on a game voice set (no other voice) --------------------------------------------------


RULES = [
    {"when": {"race": "skyborne", "gender": "female"}, "set": "skybourneelffemale3773npc"},
    {"when": {"archetype": ["undead", "ghost"], "gender": "female"}, "set": "undeadfemalestandardnpc"},
    {"when": {"archetype": ["undead", "ghost"]}, "set": "undeadmaledarknpc"},
    {"when": {"race": "ogre"}, "set": "orcmaleguardnpc"},
    {"when": {"gender": "female"}, "set": "humanfemalestandardnpc"},
    {"when": {}, "set": "humanmalestandardnpc"},
]


def test_a_speaker_spoken_gives_no_set_takes_its_kinds_rule_per_gender():
    assert voice_sets.rule_sets({"race": "ogre", "gender": "male"}, RULES) == {"male": "orcmaleguardnpc"}
    assert voice_sets.rule_sets({"archetype": "ghost", "gender": "female"}, RULES) == {
        "female": "undeadfemalestandardnpc"}
    assert voice_sets.rule_sets({"race": "human", "gender": "mixed"}, RULES) == {
        "male": "humanmalestandardnpc", "female": "humanfemalestandardnpc"}
    assert voice_sets.rule_sets({"archetype": "dragon", "gender": "none"}, RULES) == {
        "male": "humanmalestandardnpc"}  # a sexless creature speaks with the male set
    assert voice_sets.rule_sets({"creature": 1}, RULES) == {"male": "humanmalestandardnpc"}  # no profile


def test_the_narrator_and_the_players_speak_with_cloned_game_voices():
    cfg = voice_make.load_config(ROOT / "pipeline" / "voice.toml")
    assert cfg["roster"][cfg["narrator"]].get("engine") == "qwen"
    assert cfg["roster"][cfg["book_narrator"]].get("engine") == "qwen"
    for race in voice_make.PLAYER_RACES:
        for sex in voice_make.PLAYER_SEXES:
            assert cfg["roster"][voice_make.player_voice(cfg, race, sex)].get("engine") == "qwen", (race, sex)
    assert voice_make.player_voice(cfg, "scourge", "f") == "qundeadfemaleplayer"
    assert voice_make.player_voice(cfg, "skyborne", "m") == "qskybourneelfmale3776"


def test_no_committed_speaker_is_cast_to_anything_but_a_game_voice_set():
    from wfj.paths import data_root

    cfg = voice_make.load_config(ROOT / "pipeline" / "voice.toml")
    rows = vs._rows(data_root() / "voice" / "voices.jsonl")
    off = [r["creature"] for r in rows if cfg["roster"][r["voice"]].get("engine") != "qwen"
           or (r.get("female") and cfg["roster"][r["female"]].get("engine") != "qwen")]
    assert not off, off[:10]


def test_the_players_own_error_recordings_are_player_sets(tmp_path):
    lf = tmp_path / "listfile.csv"
    lf.write_text("\n".join([
        "1;sound/character/human/maleerrormessages/humanmale_err_outofrange01.ogg",
        "2;sound/character/scourge/scourgefemaleerrormessages/scourgefemale_err_nomana01.ogg",
        "3;sound/character/human/humanvocalmale/humanmalecheer01.ogg",
    ]) + "\n")
    got = vs.clip_files(lf)
    assert got == {"humanmaleplayernpc": [(1, "humanmale_err_outofrange01")],
                   "undeadfemaleplayernpc": [(2, "scourgefemale_err_nomana01")]}
