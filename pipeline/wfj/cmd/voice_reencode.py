"""wfj voice reencode: every recorded voice file made again in the current encode from its archived WAV
(voice_make.LAME, ADR-091).

  wfj voice reencode [--store DIR] [--archive DIR] [--workers N] [--limit N]

A file whose record names another encode is levelled and encoded again from the line's uncompressed WAV in the
archive (`VOICE_WAV_ARCHIVE`), into the store, and the record's bytes, sha256 and encode follow. No model runs
and no WAV is written. The timing stays as it is: it is on the recording's clock, and the packs move it by the
lead of the file they ship.

The files are made first, without the voice run lock, so they can be made while another voice run
holds it; a file already in the current encode is kept, so a run that stops resumes. The records are then
written under the lock; while another run holds it they are left for the next reencode, which finds the
files made and only writes the records. A record with no archived WAV is listed and left as it is: it needs
voicing again."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from collections.abc import Callable, Sequence
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from wfj.cmd import voice_make, voice_time
from wfj.core import mp3_frames
from wfj.paths import data_root

WORKERS = 4  # encodes at once: light enough to run beside the timing models
Encode = Callable[[bytes, Path], None]


def current(path: Path) -> bool:
    """Whether the stored file is already in the current encode (read from its first frame)."""
    if not path.is_file():
        return False
    with path.open("rb") as f:
        try:
            return mp3_frames.header(f.read(4)) == (voice_make.RATE, voice_make.KBPS)
        except mp3_frames.Mp3Error:
            return False


def reencode(root: Path, cfg: dict[str, Any], store: Path, wav_of: Callable[[dict[str, Any]], Path | None], *,
             encode: Encode = voice_make.to_levelled_mp3, workers: int = WORKERS, limit: int | None = None,
             log: Callable[[str], None] = print) -> dict[str, Any]:
    """Makes every file not in the current encode from its WAV (`wav_of` a line → its archived WAV, or None)
    → {"made", "kept", "no wav": [stems]}. Writes files only."""
    audio = voice_make.audio_record(root)
    todo, no_wav, kept = [], [], 0
    for j in voice_time.in_step(root, cfg):
        if audio[j["stem"]].get("encode") == voice_make.ENCODE:
            continue
        out = voice_make.audio_file(store, j["stem"])
        if current(out):
            kept += 1
            continue
        wav = wav_of(j)
        if wav is None:
            no_wav.append(j["stem"])
            continue
        todo.append((wav, out))
    todo = todo[:limit]
    made = 0

    def one(item: tuple[Path, Path]) -> None:
        wav, out = item
        out.parent.mkdir(parents=True, exist_ok=True)
        encode(wav.read_bytes(), out)

    with ThreadPoolExecutor(max_workers=workers) as pool:
        for _ in pool.map(one, todo):
            made += 1
            if made % 500 == 0:
                log(f"voice reencode: {made}/{len(todo)}")
    return {"made": made, "kept": kept, "no wav": no_wav}


def write_records(root: Path, store: Path) -> int:
    """Every record not in the current encode whose stored file is, brought up to that file → how many.
    Run under the voice run lock: it rewrites the audio record."""
    audio = voice_make.audio_record(root)
    done = 0
    for stem, rec in audio.items():
        path = voice_make.audio_file(store, stem)
        if rec.get("encode") == voice_make.ENCODE or not current(path):
            continue
        rec.update(bytes=path.stat().st_size, sha256=voice_make.file_sha(path), encode=voice_make.ENCODE)
        done += 1
    if done:
        voice_make._write(root / "voice" / voice_make.AUDIO, [audio[k] for k in sorted(audio)])  # noqa: SLF001
    return done


def old_encodes(root: Path) -> list[str]:
    """The recorded files not in the current encode."""
    return sorted(s for s, r in voice_make.audio_record(root).items() if r.get("encode") != voice_make.ENCODE)


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj voice reencode")
    p.add_argument("--config", default="voice.toml")
    p.add_argument("--store", default=None, help="the audio store (default: the main checkout's build/voice)")
    p.add_argument("--archive", default=os.environ.get("VOICE_WAV_ARCHIVE"), help="the WAV archive")
    p.add_argument("--workers", type=int, default=WORKERS)
    p.add_argument("--limit", type=int, default=None, help="make only the first N files (a trial)")
    a = p.parse_args(list(argv))
    root = data_root()
    store = voice_make.store_dir(a.store)
    try:
        cfg = voice_make.load_config(Path(a.config))
        index = voice_time.archive_index(Path(a.archive) if a.archive else None)
        audio = voice_make.audio_record(root)

        def wav_of(j: dict[str, Any]) -> Path | None:
            takes = index.get(voice_time.wav_name(j["fingerprint"], j["text"]) or "", [])
            return voice_time.take_of(takes, audio[j["stem"]].get("seconds"))

        r = reencode(root, cfg, store, wav_of, workers=a.workers, limit=a.limit)
        print(f"voice reencode: {r['made']} made, {r['kept']} already in the current encode")
        if r["no wav"]:
            print(f"voice reencode: {len(r['no wav'])} with no archived WAV (voice them again): "
                  + ", ".join(r["no wav"]))
        try:
            with voice_make.run_lock():
                print(f"voice reencode: {write_records(root, store)} record(s) written")
        except ValueError:
            print("voice reencode: another voice run holds the audio record; run this again after it to "
                  "write the records (the files are made)")
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as e:
        print(f"voice reencode: {e}", file=sys.stderr)
        return 1
    return 0
