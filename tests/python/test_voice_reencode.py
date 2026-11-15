"""wfj voice reencode: every recorded voice file made again in the current encode from its archived WAV, and
its record brought up to the new file (ADR-091). The encoder is a stand-in here."""

from __future__ import annotations

from pathlib import Path

import pytest
from test_voice import CFG, _gen, _store, engine  # noqa: F401 (engine is a fixture)

from wfj.cmd import voice_make, voice_reencode
from wfj.core import mp3_frames

NEW = bytes([0xFF, 0xF3, 0x84, 0xC0]) + bytes(188)  # one MPEG-2 layer III frame, 24 kHz, 64 kbps, mono


def fake_encode(wav: bytes, out: Path) -> None:
    out.write_bytes(NEW * 10)


@pytest.fixture
def old(tmp_path, engine):  # noqa: F811
    """A record made before the current encode: no `encode` on its rows."""
    data = _store(tmp_path)
    _gen(data, tmp_path / "voice", engine)
    audio = voice_make.audio_record(data)
    for rec in audio.values():
        rec.pop("encode", None)
    voice_make._write(data / "voice" / voice_make.AUDIO, [audio[k] for k in sorted(audio)])
    return data


def wav(tmp_path):
    path = tmp_path / "line.wav"
    path.write_bytes(b"RIFF")
    return lambda _job: path


def test_a_new_take_is_recorded_in_the_current_encode(tmp_path, engine):  # noqa: F811
    data = _store(tmp_path)
    _gen(data, tmp_path / "voice", engine)
    assert {r["encode"] for r in voice_make.audio_record(data).values()} == {voice_make.ENCODE}
    assert voice_make.ENCODE == "mp3 24000 64" and "64" in voice_make.LAME and "24" in voice_make.LAME


def test_every_old_file_is_made_again_from_its_wav_and_its_record_follows(old, tmp_path):
    store = tmp_path / "new-store"
    r = voice_reencode.reencode(old, CFG, store, wav(tmp_path), encode=fake_encode, log=lambda *_: None)
    assert r["made"] == len(voice_make.audio_record(old)) and not r["no wav"]
    before = voice_make.audio_record(old)
    assert voice_reencode.write_records(old, store) == len(before)
    after = voice_make.audio_record(old)
    for stem, rec in after.items():
        assert rec["encode"] == voice_make.ENCODE
        assert rec["bytes"] == len(NEW) * 10 and rec["sha256"] == voice_make.file_sha(voice_make.audio_file(store, stem))
        assert (rec["seconds"], rec["fingerprint"]) == (before[stem]["seconds"], before[stem]["fingerprint"])
    assert voice_reencode.old_encodes(old) == []


def test_a_stopped_run_keeps_the_files_it_made_and_a_line_with_no_wav_is_listed(old, tmp_path):
    store = tmp_path / "new-store"
    first = voice_reencode.reencode(old, CFG, store, wav(tmp_path), encode=fake_encode, limit=1,
                                    log=lambda *_: None)
    assert first["made"] == 1
    stems = set(voice_make.audio_record(old))
    done = {s for s in stems if voice_make.audio_file(store, s).is_file()}
    lost = min(stems - done)
    calls = []
    line = wav(tmp_path)(None)
    again = voice_reencode.reencode(old, CFG, store, lambda j: None if j["stem"] == lost else line,
                                    encode=lambda w, o: calls.append(o), log=lambda *_: None)
    assert (again["kept"], again["no wav"], again["made"]) == (1, [lost], len(stems) - 2)
    assert len(calls) == again["made"]


def test_records_are_written_only_for_files_in_the_current_encode(old, tmp_path):
    store = tmp_path / "new-store"
    stem = min(voice_make.audio_record(old))
    out = voice_make.audio_file(store, stem)
    out.parent.mkdir(parents=True)
    out.write_bytes(bytes([0xFF, 0xF3, 0x40, 0xC0]) + bytes(100))  # 22.05 kHz 32 kbps: the old encode
    assert voice_reencode.write_records(old, store) == 0
    assert len(voice_reencode.old_encodes(old)) == len(voice_make.audio_record(old))


def test_the_lead_follows_the_files_sample_rate():
    assert mp3_frames.header(NEW) == (24000, 64)
    assert mp3_frames.lead(NEW) == mp3_frames.LEAD[24000] == 0.051
    assert mp3_frames.lead(bytes([0xFF, 0xF3, 0x40, 0xC0])) == mp3_frames.LEAD[22050] == 0.055
