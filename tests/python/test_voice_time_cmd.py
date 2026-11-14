"""wfj voice time: every recorded voice file is timed by two speech models and given its cuts and timing
(ADR-090). The models and the source WAVs are stand-ins here; the real ones run with their own interpreters."""

from __future__ import annotations

import math
import wave
from pathlib import Path

import pytest
from test_voice import CFG, _gen, _store, engine  # noqa: F401 (engine is a fixture)

from wfj.cmd import voice_make, voice_time
from wfj.core import mp3_frames
from wfj.io.qwen import line_key

JA = "よく来たな。話を聞いてくれ。"
RZ = {0: 0.10, 1: 0.20, 2: 0.30, 3: 0.40, 4: 0.50, 6: 1.30, 7: 1.40, 8: 1.50, 9: 1.60, 10: 1.70}
QW = [(0, 2, 0.10, 0.28), (2, 5, 0.30, 0.60), (6, 8, 1.30, 1.48), (8, 13, 1.50, 2.00)]


def recording(path: Path, rate: int = 8000) -> Path:
    """Speech 0 to 0.7 s, a pause to 1.2 s, speech to 2.2 s."""
    tone = lambda a, b: [int(8000 * math.sin(2 * math.pi * 220 * i / rate)) for i in range(int((b - a) * rate))]  # noqa: E731
    pcm = tone(0, 0.7) + [0] * int(0.5 * rate) + tone(1.2, 2.2)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(int(v).to_bytes(2, "little", signed=True) for v in pcm))
    return path


@pytest.fixture
def made(tmp_path, engine):  # noqa: F811
    data = _store(tmp_path, ja456=JA)
    _gen(data, tmp_path / "voice", engine)
    audio = voice_make.audio_record(data)
    for rec in audio.values():
        rec["seconds"] = 2.2  # as long as the stand-in recording
    voice_make._write(data / "voice" / voice_make.AUDIO, [audio[k] for k in sorted(audio)])
    return data


def sources(tmp_path, lead=0.0, missing=()):
    wav = recording(tmp_path / "line.wav")
    return lambda rec, _text: None if rec["file"] in missing else (wav, lead)


def answers(stems, rz=None, qw=None):
    return lambda jobs: ({j["stem"]: dict(rz or RZ) for j in jobs if j["stem"] in stems},
                         {j["stem"]: list(qw or QW) for j in jobs if j["stem"] in stems})


def all_stems(data):
    return set(voice_make.audio_record(data))


def test_every_recorded_line_is_timed_and_cut_and_marked_with_its_fingerprint(made, tmp_path):
    r = voice_time.time_records(made, CFG, source=sources(tmp_path), align=answers(all_stems(made)),
                                log=lambda *_: None)
    assert r["timed"] == 3 and not r["failed"]
    rec = voice_make.audio_record(made)["456-description"]
    assert rec["timing_of"] == rec["fingerprint"]
    assert rec["cuts"] == [0.95]
    assert sum(int(p.split(":")[0]) for p in rec["timing"].split()) == len(JA)


def test_a_second_run_finds_nothing_left_and_a_remade_line_is_timed_again(made, tmp_path):
    voice_time.time_records(made, CFG, source=sources(tmp_path), align=answers(all_stems(made)),
                            log=lambda *_: None)
    assert voice_time.to_time(made, CFG) == []
    audio = voice_make.audio_record(made)
    audio["456-description"]["timing_of"] = "an older recording"
    voice_make._write(made / "voice" / voice_make.AUDIO, [audio[k] for k in sorted(audio)])
    assert [j["stem"] for j in voice_time.to_time(made, CFG)] == ["456-description"]


def test_a_line_with_no_source_or_no_answer_fails_and_keeps_its_record(made, tmp_path):
    r = voice_time.time_records(made, CFG, source=sources(tmp_path, missing={"456-completion"}),
                                align=answers(all_stems(made) - {"g-0123456789abcdef"}), log=lambda *_: None)
    failed = {s for s, _ in r["failed"]}
    assert failed == {"456-completion", "g-0123456789abcdef"}
    audio = voice_make.audio_record(made)
    assert "timing" not in audio["456-completion"] and "timing" not in audio["g-0123456789abcdef"]


def test_a_line_timed_from_its_mp3_is_moved_back_onto_the_recordings_clock(made, tmp_path):
    lead = mp3_frames.LEAD
    shifted = {k: v + lead for k, v in RZ.items()}
    words = [(a, b, s + lead, e + lead) for a, b, s, e in QW]
    r = voice_time.time_records(made, CFG, source=sources(tmp_path, lead=lead),
                                align=answers(all_stems(made), shifted, words), log=lambda *_: None)
    assert len(r["decoded"]) == 3
    first = voice_make.audio_record(made)["456-description"]["timing"].split()[0]
    assert first.endswith(":10")  # 0.10 s, as if timed from the WAV


def test_a_line_the_models_disagree_on_is_listed_to_listen_to(made, tmp_path):
    far = {k: v + 0.5 for k, v in RZ.items()}
    r = voice_time.time_records(made, CFG, source=sources(tmp_path), align=answers(all_stems(made), far),
                                log=lambda *_: None)
    assert ("456-description", 4) in r["doubt"]
    text = voice_time.report_text(r)
    assert "456-description: 4 words apart" in text and "Lines timed: 3 of 3" in text


def test_an_archived_wav_is_found_by_the_name_its_remote_run_gave_it(tmp_path):
    fp = "a9a07c4b766705bb|qtaurenmaleelder|qwen|taurenmaleeldernpc|voice|6b31d4aaeafd|t0.5s852483275|f9acd76f617b5dc6"
    name = line_key("こんにちは。", Path("taurenmaleeldernpc-voice-6b31d4aaeafd.wav"), "voice", 852483275, 0.5)
    assert voice_time.wav_name(fp, "こんにちは。") == f"{name}.wav"
    (tmp_path / "arch" / "run1" / "wav").mkdir(parents=True)
    wav = recording(tmp_path / "arch" / "run1" / "wav" / f"{name}.wav")
    find = voice_time.archive_source(tmp_path / "arch", tmp_path / "store", tmp_path / "work")
    assert find({"file": "x", "fingerprint": fp}, "こんにちは。") == (wav, 0.0)
    assert find({"file": "x", "fingerprint": fp}, "別の文。") is None  # not archived and no MP3 stored


def test_a_voice_made_without_a_cloned_set_has_no_archive_name():
    assert voice_time.wav_name("abc|m|11|0.9|0|1", "テキスト") is None


def test_the_voice_rounds_end_with_the_timing_step():
    make = (Path(__file__).resolve().parents[2] / "Makefile").read_text(encoding="utf-8")
    for target in ("voice-generate:", "voice-run:"):
        recipe = make.split(target, 1)[1].split("\n\n", 1)[0]
        assert "voice time" in recipe, f"{target} does not time what it made"


def test_the_gate_finds_untimed_retimed_short_and_badly_cut_lines(made, tmp_path):
    assert set(voice_time.problems(made, CFG)["untimed"]) == all_stems(made)
    voice_time.time_records(made, CFG, source=sources(tmp_path), align=answers(all_stems(made)),
                            log=lambda *_: None)
    assert not any(voice_time.problems(made, CFG).values())
    audio = voice_make.audio_record(made)
    audio["456-description"]["timing_of"] = "an older recording"
    audio["456-completion"]["timing"] = "1:0"
    audio["g-0123456789abcdef"]["cuts"] = [5.0, 2.0]
    voice_make._write(made / "voice" / voice_make.AUDIO, [audio[k] for k in sorted(audio)])
    got = voice_time.problems(made, CFG)
    assert got["other recording"] == ["456-description"]
    assert got["short timing"] == ["456-completion"]
    assert got["bad cuts"] == ["g-0123456789abcdef"]
