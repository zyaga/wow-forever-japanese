"""wfj voice time: when each voice line's sentences and words are spoken, and where to cut it (ADR-090).

  wfj voice time [--store DIR] [--archive DIR] [--work DIR] [--limit N]

For every recorded voice file that has no timing yet, or was timed from another recording (its fingerprint
changed), two speech models listen to it: ReazonSpeech for every character, Qwen's aligner for every word
(`dev/align_reazon.py`, `dev/align_qwen.py`, run with their own interpreters, ALIGN_REAZON_PY and
ALIGN_QWEN_PY). The line's record gets its cuts (seconds, where `wfj voice pack` snips it into one file per
sentence), its timing string (when each part of its Japanese is spoken) and `timing_of` (the fingerprint it
was timed from). No audio is written. A run that stops resumes: the models' answers are kept per line in the
work folder, and records are written as lines finish.

The source is the line's uncompressed WAV in the archive (`VOICE_WAV_ARCHIVE`), found by the name its remote
run gave it; a line with none is timed from its stored MP3, decoded, with its times moved back by the MP3's
lead so every line is timed on the same clock."""

from __future__ import annotations

import argparse
import datetime
import os
import subprocess
import sys
import wave
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path
from typing import Any

from wfj.cmd import voice_make
from wfj.core import mp3_frames, voice, voice_timing
from wfj.io.jsonl_store import dumps, read_jsonl
from wfj.io.qwen import line_key
from wfj.paths import data_root

WORK_DIR = "build/voice-time"
REAZON_PYTHON = "build/tts-venv/bin/python"
QWEN_PYTHON = "build/aligner-venv/bin/python"
DISAGREE = 0.30  # seconds: a word the two models place this far apart is in doubt
DISAGREE_WORDS = 2  # a line with more such words is listed for a listen
SAVE_EVERY = 2000  # lines between two writes of the audio record (the models' answers are on disk already)

Job = dict[str, Any]  # stem, key, text (the engine read), ja (shipped), fingerprint, wav, lead
Source = Callable[[dict[str, Any], str], tuple[Path, float] | None]
Align = Callable[[Sequence[Job]], tuple[dict[str, dict[int, float]], dict[str, list[voice_timing.Word]]]]


def in_step(root: Path, cfg: dict[str, Any]) -> list[Job]:
    """Every recorded file in step with its line: its stem, key, the text the engine read, the shipped
    Japanese and the fingerprint."""
    lines = voice_make.shipped_lines(root)
    jobs = voice_make.file_jobs(root, cfg, "all", lines, voice_make.players_of("all"))
    audio = voice_make.audio_record(root)
    state, values, texts = voice_make.step_state(root, cfg, jobs, lines, audio)
    off = set(state["missing"]) | set(state["stale"])
    out = []
    for j in jobs:
        rec = audio.get(j.stem)
        if rec is None or j.stem in off:
            continue
        text = texts.get(j.key) or voice.speech_text(lines[j.key], j.key, values.get(j.key, ()))
        out.append({"stem": j.stem, "key": j.key, "text": text, "ja": lines[j.key],
                    "fingerprint": rec["fingerprint"], "timing_of": rec.get("timing_of")})
    return out


def to_time(root: Path, cfg: dict[str, Any]) -> list[Job]:
    """The recorded files in step with their line whose timing is missing or from another recording."""
    return [j for j in in_step(root, cfg) if j.pop("timing_of") != j["fingerprint"]]


def problems(root: Path, cfg: dict[str, Any]) -> dict[str, list[str]]:
    """What keeps the voice from shipping in sentences: files in step with their line but not timed, timed
    from another recording, whose timing does not cover the shipped Japanese, or whose cuts are out of
    order or outside the recording. Empty lists when every file is ready."""
    lines = voice_make.shipped_lines(root)
    jobs = voice_make.file_jobs(root, cfg, "all", lines, voice_make.players_of("all"))
    audio = voice_make.audio_record(root)
    out: dict[str, list[str]] = {"untimed": [], "other recording": [], "short timing": [], "bad cuts": []}
    for j in jobs:
        rec = audio.get(j.stem)
        if rec is None:
            continue  # no audio at all: test_audio_in_step reports it
        if "timing" not in rec:
            out["untimed"].append(j.stem)
            continue
        if rec.get("timing_of") != rec["fingerprint"]:
            out["other recording"].append(j.stem)
        if sum(int(p.split(":")[0]) for p in rec["timing"].split()) != len(lines[j.key]):
            out["short timing"].append(j.stem)
        cuts = rec.get("cuts") or []
        if cuts != sorted(set(cuts)) or any(not 0 < c < float(rec["seconds"]) for c in cuts):
            out["bad cuts"].append(j.stem)
    return out


def wav_name(fingerprint: str, text: str) -> str | None:
    """The name a remote run gave this recording's WAV, from what its fingerprint says it was made from
    (set, copy mode, reference, temperature and seed): see io/qwen.line_key."""
    f = fingerprint.split("|")
    if len(f) < 7 or f[2] != "qwen" or not f[6].startswith("t") or "s" not in f[6]:
        return None
    temperature, seed = f[6][1:].split("s", 1)
    ref = Path(f"{f[3]}-{f[4]}-{f[5]}.wav")
    return line_key(text, ref, f[4], int(seed) if seed else None,
                    float(temperature) if temperature else None) + ".wav"


def archive_index(archive: Path | None) -> dict[str, Path]:
    """Every WAV in the archive by its file name (the name its remote run gave it)."""
    index: dict[str, Path] = {}
    if archive is not None and archive.is_dir():
        for p in archive.glob("*/wav/*.wav"):
            index.setdefault(p.name, p)
    return index


def archive_source(archive: Path | None, store: Path, work: Path) -> Source:
    """The archived WAV when there is one, else the stored MP3 decoded to a WAV in the work folder."""
    index = archive_index(archive)

    def source(rec: dict[str, Any], text: str) -> tuple[Path, float] | None:
        name = wav_name(rec["fingerprint"], text)
        if name and name in index:
            return index[name], 0.0
        mp3 = voice_make.audio_file(store, rec["file"])
        if not mp3.is_file():
            return None
        out = work / "decoded" / f"{rec['file']}.wav"
        if not out.is_file():
            out.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(mp3), "-ac", "1", "-c:a", "pcm_s16le",
                            str(out)], check=True)
        with mp3.open("rb") as f:
            return out, mp3_frames.lead(f.read(4))

    return source


def model_align(work: Path, log: Callable[[str], None] = print) -> Align:
    """Both models over the jobs, each with its own interpreter; their answers are kept in the work folder."""
    main = voice_make._main_checkout()  # noqa: SLF001 - the venvs live in the main checkout, like the Qwen engine's
    reazon = Path(os.environ.get("ALIGN_REAZON_PY") or main / REAZON_PYTHON)
    qwen = Path(os.environ.get("ALIGN_QWEN_PY") or main / QWEN_PYTHON)
    scripts = Path(__file__).resolve().parents[1] / "dev"

    def align(jobs: Sequence[Job]) -> tuple[dict[str, dict[int, float]], dict[str, list[voice_timing.Word]]]:
        for python in (reazon, qwen):
            if not python.is_file():
                raise ValueError(f"{python}: no aligner interpreter (docs/operations/voice.md, 'Timing')")
        work.mkdir(parents=True, exist_ok=True)
        listed = work / "jobs.jsonl"
        listed.write_text("".join(dumps({"stem": j["stem"], "wav": str(j["wav"]), "text": j["text"]}) + "\n"
                                  for j in jobs), encoding="utf-8")
        for python, script, out in ((reazon, "align_reazon.py", "reazon.jsonl"),
                                    (qwen, "align_qwen.py", "qwen.jsonl")):
            log(f"voice time: {script} over {len(jobs)} line(s)")
            cmd = [str(python), "-I", str(scripts / script), str(listed), str(work / out)]
            subprocess.run(cmd, check=True)
        return read_answers(work)

    return align


def read_answers(work: Path) -> tuple[dict[str, dict[int, float]], dict[str, list[voice_timing.Word]]]:
    rz: dict[str, dict[int, float]] = {}
    qw: dict[str, list[voice_timing.Word]] = {}
    for line in read_jsonl(work / "reazon.jsonl") if (work / "reazon.jsonl").is_file() else []:
        rz[line["stem"]] = {int(k): float(v) for k, v in line["chars"].items()}
    for line in read_jsonl(work / "qwen.jsonl") if (work / "qwen.jsonl").is_file() else []:
        qw[line["stem"]] = [(int(a), int(b), float(s), float(e)) for a, b, s, e in line["words"]]
    return rz, qw


def samples(path: Path) -> tuple[Sequence[int], int]:
    """A 16-bit WAV's samples (mono: the first channel) and its rate."""
    import array

    with wave.open(str(path)) as w:
        if w.getsampwidth() != 2:
            raise ValueError(f"{path}: not a 16-bit WAV")
        data = array.array("h", w.readframes(w.getnframes()))
        return data[:: w.getnchannels()], w.getframerate()


def disagreements(rz: Mapping[int, float], qw: Sequence[voice_timing.Word]) -> int:
    """How many of Qwen's words ReazonSpeech starts more than DISAGREE apart."""
    return sum(1 for w in qw if w[0] in rz and abs(rz[w[0]] - w[2]) > DISAGREE)


def time_line(job: Job, rz: Mapping[int, float], qw: Sequence[voice_timing.Word],
              cards: Sequence[str]) -> dict[str, Any]:
    """→ cuts, timing and what the report needs, on the recording's own clock (the MP3's lead taken off)."""
    lead = job.get("lead", 0.0)
    rz = {k: max(0.0, v - lead) for k, v in rz.items()}
    qw = [(a, b, max(0.0, s - lead), max(0.0, e - lead)) for a, b, s, e in qw]
    pcm, rate = samples(Path(job["wav"]))
    quiet = [(max(0.0, a - lead), max(0.0, b - lead)) for a, b in voice_timing.pauses(pcm, rate)]
    cuts = voice_timing.cuts(job["text"], rz, qw, quiet, len(pcm) / rate - lead)
    return {
        "cuts": cuts,
        "timing": voice_timing.timing(job["ja"], job["text"], rz, qw, cards),
        "sentences": len(voice_timing.sentence_starts(job["text"])),
        "disagree": disagreements(rz, qw),
    }


def time_records(root: Path, cfg: dict[str, Any], *, source: Source, align: Align,
                 limit: int | None = None, log: Callable[[str], None] = print) -> dict[str, Any]:
    """Times every file `to_time` lists (the first `limit`), writes the records, → the run's report."""
    jobs = to_time(root, cfg)[:limit]
    audio = voice_make.audio_record(root)
    report: dict[str, Any] = {"timed": 0, "failed": [], "decoded": [], "doubt": [], "unconfirmed": 0,
                              "cut": 0, "boundaries": 0, "todo": len(jobs)}
    ready = []
    for j in jobs:
        got = source(audio[j["stem"]], j["text"])
        if got is None:
            report["failed"].append((j["stem"], "no WAV in the archive and no MP3 in the store"))
            continue
        j["wav"], j["lead"] = got
        if j["lead"]:
            report["decoded"].append(j["stem"])
        ready.append(j)
    if not ready:
        return report
    rz, qw = align(ready)
    words = voice_make.reading_words(root)
    for j in ready:
        stem = j["stem"]
        if stem not in rz or stem not in qw:
            report["failed"].append((stem, "a model gave no answer"))
            continue
        try:
            got = time_line(j, rz[stem], qw[stem], [w[0] for w in words.get(j["key"], [])])
        except (ValueError, OSError, wave.Error) as e:
            report["failed"].append((stem, str(e)))
            continue
        rec = audio[stem]
        rec["cuts"], rec["timing"], rec["timing_of"] = got["cuts"], got["timing"], rec["fingerprint"]
        report["timed"] += 1
        report["boundaries"] += got["sentences"] - 1
        report["cut"] += len(got["cuts"])
        report["unconfirmed"] += got["sentences"] - 1 - len(got["cuts"])
        if got["disagree"] > DISAGREE_WORDS:
            report["doubt"].append((stem, got["disagree"]))
        if report["timed"] % SAVE_EVERY == 0:
            voice_make._write(root / "voice" / voice_make.AUDIO, [audio[k] for k in sorted(audio)])  # noqa: SLF001
            log(f"voice time: {report['timed']}/{len(ready)} timed")
    voice_make._write(root / "voice" / voice_make.AUDIO, [audio[k] for k in sorted(audio)])  # noqa: SLF001
    return report


def report_text(r: dict[str, Any]) -> str:
    """The run report, in Markdown: the counts, then the lines to listen to, the failures and the MP3s."""
    lines = [
        f"# Voice timing run, {datetime.date.today().isoformat()}",
        "",
        f"- Lines timed: {r['timed']} of {r['todo']}",
        f"- Sentence breaks: {r['boundaries']}, cut: {r['cut']}, kept together (no confirmed pause): "
        f"{r['unconfirmed']}",
        f"- Timed from a decoded MP3 (no archived WAV): {len(r['decoded'])}",
        f"- Lines where the two models disagree on more than {DISAGREE_WORDS} words by over "
        f"{int(DISAGREE * 1000)} ms: {len(r['doubt'])}",
        f"- Failed: {len(r['failed'])}",
    ]
    if r["doubt"]:
        lines += ["", "## Lines to listen to", *[f"- {s}: {n} words apart" for s, n in r["doubt"]]]
    if r["failed"]:
        lines += ["", "## Failed", *[f"- {s}: {why}" for s, why in r["failed"]]]
    if r["decoded"]:
        lines += ["", "## Timed from the MP3", *[f"- {s}" for s in r["decoded"]]]
    return "\n".join(lines) + "\n"


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj voice time")
    p.add_argument("--config", default="voice.toml")
    p.add_argument("--store", default=None, help="the audio store (default: the main checkout's build/voice)")
    p.add_argument("--archive", default=os.environ.get("VOICE_WAV_ARCHIVE"), help="the WAV archive")
    p.add_argument("--work", default=None, help=f"the models' answers (default: <main checkout>/{WORK_DIR})")
    p.add_argument("--limit", type=int, default=None, help="time only the first N lines (a trial)")
    a = p.parse_args(list(argv))
    root = data_root()
    store = voice_make.store_dir(a.store)
    work = Path(a.work) if a.work else voice_make._main_checkout() / WORK_DIR  # noqa: SLF001
    try:
        cfg = voice_make.load_config(Path(a.config))
        with voice_make.run_lock():
            archive = Path(a.archive) if a.archive else None
            r = time_records(root, cfg, source=archive_source(archive, store, work), align=model_align(work),
                             limit=a.limit)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as e:
        print(f"voice time: {e}", file=sys.stderr)
        return 1
    work.mkdir(parents=True, exist_ok=True)
    (work / "report.md").write_text(report_text(r), encoding="utf-8")
    print(report_text(r), end="")
    print(f"voice time: report in {work / 'report.md'}")
    return 0 if not r["failed"] else 1
