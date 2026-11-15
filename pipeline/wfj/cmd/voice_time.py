"""wfj voice time: when each voice line's sentences and words are spoken, and where to cut it (ADR-090).

  wfj voice time [--store DIR] [--archive DIR] [--work DIR] [--limit N] [--modal [--max-dollars D]]

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


def archive_index(archive: Path | None) -> dict[str, list[Path]]:
    """Every WAV in the archive by its file name (the name its run gave it), newest first: a line read again
    from the same text, voice and seed (a retake) has the same name in another run folder."""
    index: dict[str, list[Path]] = {}
    if archive is not None and archive.is_dir():
        for p in archive.glob("*/wav/*.wav"):
            index.setdefault(p.name, []).append(p)
    for takes in index.values():
        takes.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return index


def wav_seconds(path: Path) -> float:
    with wave.open(str(path)) as w:
        return w.getnframes() / w.getframerate()


def take_of(takes: Sequence[Path], seconds: float | None) -> Path | None:
    """The take the recorded file was made from: the one as long as the record says (to 0.05 s), else the
    newest."""
    if not takes:
        return None
    if seconds is not None:
        for p in takes:
            if abs(wav_seconds(p) - float(seconds)) <= 0.05:
                return p
    return takes[0]


def archive_source(archive: Path | None, store: Path, work: Path) -> Source:
    """The archived WAV when there is one, else the stored MP3 decoded to a WAV in the work folder."""
    index = archive_index(archive)

    def source(rec: dict[str, Any], text: str) -> tuple[Path, float] | None:
        name = wav_name(rec["fingerprint"], text)
        take = take_of(index.get(name or "", []), rec.get("seconds"))
        if take is not None:
            return take, 0.0
        mp3 = voice_make.audio_file(store, rec["file"])
        if not mp3.is_file():
            return None
        # named by the file's hash: a line voiced again is decoded afresh, never answered from the old audio
        out = work / "decoded" / f"{rec['file']}-{str(rec.get('sha256', ''))[:12]}.wav"
        if not out.is_file():
            out.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(mp3), "-ac", "1", "-c:a", "pcm_s16le",
                            str(out)], check=True)
        with mp3.open("rb") as f:
            return out, mp3_frames.lead(f.read(4))

    return source


MODAL_PYTHON = "build/modal/venv/bin/python"


def model_align(work: Path, log: Callable[[str], None] = print, *, modal: bool = False,
                max_dollars: float | None = None) -> Align:
    """Both models over the jobs, each with its own interpreter, or on Modal's cards (`io/align_modal.py`);
    their answers are kept in the work folder."""
    main = voice_make._main_checkout()  # noqa: SLF001 - the venvs live in the main checkout, like the Qwen engine's
    reazon = Path(os.environ.get("ALIGN_REAZON_PY") or main / REAZON_PYTHON)
    qwen = Path(os.environ.get("ALIGN_QWEN_PY") or main / QWEN_PYTHON)
    scripts = Path(__file__).resolve().parents[1] / "dev"

    def align(jobs: Sequence[Job]) -> tuple[dict[str, dict[int, float]], dict[str, list[voice_timing.Word]]]:
        kept_rz, kept_qw = beside(jobs)
        jobs = [j for j in jobs if j["stem"] not in kept_rz or j["stem"] not in kept_qw]
        if not jobs:
            return kept_rz, kept_qw
        rz, qw = run_models(jobs)
        keep_beside(jobs, rz, qw)
        return {**rz, **kept_rz}, {**qw, **kept_qw}

    def run_models(jobs: Sequence[Job]) -> tuple[dict[str, dict[int, float]],
                                                  dict[str, list[voice_timing.Word]]]:
        for python in () if modal else (reazon, qwen):
            if not python.is_file():
                raise ValueError(f"{python}: no aligner interpreter (docs/operations/voice.md, 'Timing')")
        work.mkdir(parents=True, exist_ok=True)
        listed = work / "jobs.jsonl"
        drop_other_recordings(work, jobs)
        listed.write_text("".join(dumps({"stem": j["stem"], "wav": str(j["wav"]), "text": j["text"]}) + "\n"
                                  for j in jobs), encoding="utf-8")
        if modal:
            script = Path(__file__).resolve().parents[1] / "io" / "align_modal.py"
            cmd = [str(main / MODAL_PYTHON), str(script), str(listed), str(work)]
            log(f"voice time: align_modal.py over {len(jobs)} line(s)")
            # a run that stopped or left lines untimed still hands back what it answered
            subprocess.run([*cmd, *(["--max-dollars", str(max_dollars)] if max_dollars else [])], check=False)
            return read_answers(work, jobs)
        for python, script, out in ((reazon, "align_reazon.py", "reazon.jsonl"),
                                    (qwen, "align_qwen.py", "qwen.jsonl")):
            log(f"voice time: {script} over {len(jobs)} line(s)")
            cmd = [str(python), "-I", str(scripts / script), str(listed), str(work / out)]
            subprocess.run(cmd, check=True)
        return read_answers(work, jobs)

    return align


BESIDE = ("align-reazon.jsonl", "align-qwen.jsonl")  # the models' answers kept in a WAV's run folder


def _run_of(job: Job) -> tuple[Path, str] | None:
    """The archived run folder a job's WAV sits in, and the WAV's name without .wav; None for another source
    (a decoded MP3)."""
    wav = Path(job["wav"])
    return (wav.parent.parent, wav.stem) if wav.parent.name == "wav" else None


def beside(jobs: Sequence[Job]) -> tuple[dict[str, dict[int, float]], dict[str, list[voice_timing.Word]]]:
    """The answers already kept beside the jobs' WAVs (a cloned-voice run times its lines on the cards as it
    reads them; a timing run keeps what it made), by stem: a WAV is never timed twice."""
    rz: dict[str, dict[int, float]] = {}
    qw: dict[str, list[voice_timing.Word]] = {}
    read: dict[Path, tuple[dict, dict]] = {}
    for j in jobs:
        where = _run_of(j)
        if where is None:
            continue
        run, key = where
        if run not in read:
            got: list[dict] = [{}, {}]
            for n, name in enumerate(BESIDE):
                path = run / name
                for row in read_jsonl(path) if path.is_file() else []:
                    got[n][row["key"]] = row.get("chars", row.get("words"))
            read[run] = (got[0], got[1])
        chars, words = read[run][0].get(key), read[run][1].get(key)
        if chars and words:
            rz[j["stem"]] = {int(k): float(v) for k, v in chars.items()}
            qw[j["stem"]] = [(int(a), int(b), float(s), float(e)) for a, b, s, e in words]
    return rz, qw


def keep_beside(jobs: Sequence[Job], rz: Mapping[str, Mapping[int, float]],
                qw: Mapping[str, Sequence[voice_timing.Word]]) -> None:
    """Appends the answers just made beside each archived WAV they were made from."""
    by_run: dict[Path, list[tuple[str, Job]]] = {}
    for j in jobs:
        where = _run_of(j)
        if where and j["stem"] in rz and j["stem"] in qw:
            by_run.setdefault(where[0], []).append((where[1], j))
    for run, items in by_run.items():
        with (run / BESIDE[0]).open("a", encoding="utf-8") as a, \
                (run / BESIDE[1]).open("a", encoding="utf-8") as b:
            for key, j in items:
                a.write(dumps({"key": key, "chars": {str(k): v for k, v in rz[j["stem"]].items()}}) + "\n")
                b.write(dumps({"key": key, "words": [list(w) for w in qw[j["stem"]]]}) + "\n")


def drop_other_recordings(work: Path, jobs: Sequence[Job]) -> list[str]:
    """Drops from the work folder's answers every line whose source changed since they were made (a line
    voiced again since): they belong to another recording, and the models answer it afresh. → the stems."""
    listed = work / "jobs.jsonl"
    before = {r["stem"]: r["wav"] for r in read_jsonl(listed)} if listed.is_file() else {}
    changed = {j["stem"] for j in jobs if j["stem"] in before and before[j["stem"]] != str(j["wav"])}
    for name in ("reazon.jsonl", "qwen.jsonl"):
        path = work / name
        if changed and path.is_file():
            kept = [r for r in read_jsonl(path) if r["stem"] not in changed]
            path.write_text("".join(dumps(r) + "\n" for r in kept), encoding="utf-8")
    return sorted(changed)


def read_answers(work: Path, jobs: Sequence[Job] | None = None) -> tuple[dict[str, dict[int, float]],
                                                                       dict[str, list[voice_timing.Word]]]:
    """The models' answers in the work folder by stem; with `jobs`, only those made from each job's own WAV
    (an answer from an older recording of a line, or with no recording named, is left out)."""
    want = {j["stem"]: str(j["wav"]) for j in jobs} if jobs is not None else None

    def mine(line: dict[str, Any]) -> bool:
        return want is None or (line["stem"] in want and want[line["stem"]] == line.get("wav"))

    rz: dict[str, dict[int, float]] = {}
    qw: dict[str, list[voice_timing.Word]] = {}
    for line in read_jsonl(work / "reazon.jsonl") if (work / "reazon.jsonl").is_file() else []:
        if mine(line):
            rz[line["stem"]] = {int(k): float(v) for k, v in line["chars"].items()}
    for line in read_jsonl(work / "qwen.jsonl") if (work / "qwen.jsonl").is_file() else []:
        if mine(line):
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
                              "kept": [],
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
        kept = got["sentences"] - 1 - len(got["cuts"])
        report["unconfirmed"] += kept
        if kept:
            report["kept"].append((stem, kept))
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
    if r.get("kept"):
        lines += ["", "## Sentences kept together (a break with no confirmed pause)",
                  *[f"- {s}: {n}" for s, n in r["kept"]]]
    return "\n".join(lines) + "\n"


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj voice time")
    p.add_argument("--config", default="voice.toml")
    p.add_argument("--store", default=None, help="the audio store (default: the main checkout's build/voice)")
    p.add_argument("--archive", default=os.environ.get("VOICE_WAV_ARCHIVE"), help="the WAV archive")
    p.add_argument("--work", default=None, help=f"the models' answers (default: <main checkout>/{WORK_DIR})")
    p.add_argument("--limit", type=int, default=None, help="time only the first N lines (a trial)")
    p.add_argument("--modal", action="store_true", help="run both models on Modal's cards (align_modal.py)")
    p.add_argument("--max-dollars", type=float, default=None, help="with --modal: stop before passing this")
    a = p.parse_args(list(argv))
    root = data_root()
    store = voice_make.store_dir(a.store)
    work = Path(a.work) if a.work else voice_make._main_checkout() / WORK_DIR  # noqa: SLF001
    try:
        cfg = voice_make.load_config(Path(a.config))
        with voice_make.run_lock():
            archive = Path(a.archive) if a.archive else None
            align = model_align(work, modal=a.modal, max_dollars=a.max_dollars)
            r = time_records(root, cfg, source=archive_source(archive, store, work), align=align,
                             limit=a.limit)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as e:
        print(f"voice time: {e}", file=sys.stderr)
        return 1
    work.mkdir(parents=True, exist_ok=True)
    (work / "report.md").write_text(report_text(r), encoding="utf-8")
    print(report_text(r), end="")
    print(f"voice time: report in {work / 'report.md'}")
    if r["failed"]:  # the lines timed are written; the audio still syncs, and the gate test names the rest
        print(f"voice time: {len(r['failed'])} line(s) not timed, listed in the report", file=sys.stderr)
    return 0
