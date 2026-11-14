"""Both speech aligners on rented GPUs (Modal), with the code and package versions the Mac runs (ADR-090).

    build/modal/venv/bin/python pipeline/wfj/io/align_modal.py JOBS OUT_DIR [--limit N] [--max-dollars D]

JOBS is the job list `wfj voice time` writes (one line per file: stem, wav, text). Each WAV is packed
losslessly as FLAC (the same samples, about half the bytes) into OUT_DIR/flac and uploaded once to a Modal
volume before any card starts, so no card waits, billed, on the upload. Then a Qwen aligner card times each
batch's words and hands the batch to a ReazonSpeech card inside Modal. The answers are appended to
OUT_DIR/reazon.jsonl and OUT_DIR/qwen.jsonl in the format `dev/align_reazon.py` and `dev/align_qwen.py` write,
so `wfj voice time` reads them as if the Mac had run them; a rerun sends only the lines missing from either.

Cost guard: after the first batches the run projects its cost from the card time it measured (each card's
time doubled for start-up and idle) and stops before it would pass --max-dollars, as it stops at any point
the spend so far passes it; --max-minutes stops it outright. Stopping ends the app, so every card stops.

A cloned-voice run (`qwen_modal.py`) includes this app and times each line on the cards right after reading it
(`answers`), while its WAV is still there. Run with the Modal client's own environment (`build/modal/venv`),
never imported by the pipeline."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import modal

HERE = Path(__file__).resolve().parent
DEV = HERE.parent / "dev"
GPU = os.environ.get("WFJ_MODAL_GPU", "L40S")
CARDS = int(os.environ.get("WFJ_MODAL_CONTAINERS", "10"))  # the account's limit: half for each model
BATCH = 100  # lines per call: about 1,000 seconds of speech
PRICE = 1.95 / 3600  # dollars per L40S card-second (Modal, measured on the voice runs' bill)
VOLUME = "wfj-align-audio"  # the uploaded FLAC, read by the cards at /audio
volume = modal.Volume.from_name(VOLUME, create_if_missing=True)
# the weights the Mac's runs read, by revision
REAZON = ("reazon-research/japanese-wav2vec2-large-rs35kh", "2162c9edb97f362f7623d6b3a2e417458e879bca")
QWEN = ("Qwen/Qwen3-ForcedAligner-0.6B", "c7cbfc2048c462b0d63a45797104fc9db3ad62b7")


def _fetch(model: tuple[str, str]) -> str:
    return (f"python -c \"from huggingface_hub import snapshot_download; "
            f"snapshot_download('{model[0]}', revision='{model[1]}')\"")


# the package versions of build/tts-venv and build/aligner-venv
reazon_image = (
    modal.Image.debian_slim(python_version="3.12")
    .pip_install("torch==2.14.1", "torchaudio==2.11.0", "transformers==5.2.0", "huggingface_hub==1.33.0",
                 "pykakasi==2.3.0", "soundfile==0.14.0", "numpy")
    .run_commands(_fetch(REAZON))
    .env({"HF_HUB_OFFLINE": "1", "TRANSFORMERS_VERBOSITY": "error"})
    .add_local_file(DEV / "align_reazon.py", "/root/align_reazon.py")
)
qwen_image = (
    modal.Image.debian_slim(python_version="3.12")
    .pip_install("qwen-asr==0.0.6", "torch==2.15.0", "transformers==4.57.6", "accelerate==1.12.0",
                 "nagisa==0.2.11", "soundfile==0.14.0", "librosa==1.0.1", "huggingface_hub")
    .run_commands(_fetch(QWEN))
    .env({"HF_HUB_OFFLINE": "1", "TRANSFORMERS_VERBOSITY": "error"})
    .add_local_file(DEV / "align_qwen.py", "/root/align_qwen.py")
)
app = modal.App("wfj-align")

Item = tuple[str, bytes | str, str]  # a key, the audio (bytes, or its path on the volume), the text read


def _samples(data: bytes | str):  # noqa: ANN202 - numpy is not installed where this file is read locally
    import io

    import soundfile

    a, sr = soundfile.read(data if isinstance(data, str) else io.BytesIO(data), dtype="float32")
    return (a.mean(1) if a.ndim > 1 else a), sr


@app.cls(gpu=GPU, image=reazon_image, timeout=900, scaledown_window=30, volumes={"/audio": volume},
         max_containers=max(1, CARDS // 2))
class Reazon:
    @modal.enter()
    def setup(self) -> None:
        sys.path.insert(0, "/root")
        import align_reazon

        self.mod = align_reazon
        self.state = align_reazon.load("cuda")

    @modal.method()
    def align(self, items: list[Item]) -> tuple[list[tuple[str, dict | None, str]], float]:
        """([(key, {character index: seconds} or None, error)], the card seconds it took)"""
        started = time.time()
        out = []
        for key, data, text in items:
            try:
                a, sr = _samples(data)
                out.append((key, self.mod.align(self.state, a, sr, text), ""))
            except Exception as e:  # noqa: BLE001 - one line the model cannot take is reported, the rest go on
                out.append((key, None, str(e)))
        return out, time.time() - started


@app.cls(gpu=GPU, image=qwen_image, timeout=900, scaledown_window=30, volumes={"/audio": volume},
         max_containers=max(1, CARDS // 2))
class Qwen:
    @modal.enter()
    def setup(self) -> None:
        sys.path.insert(0, "/root")
        import align_qwen

        self.mod = align_qwen
        self.aligner = align_qwen.load("cuda")

    @modal.method()
    def both(self, items: list[Item]) -> tuple[list[tuple[str, dict | None, list | None, str]], float]:
        """([(key, ReazonSpeech's characters or None, Qwen's words or None, error)], card seconds): the batch
        goes on to a ReazonSpeech card inside Modal while this card times the words."""
        started = time.time()
        rz = Reazon().align.spawn(items)
        words: dict[str, tuple[list | None, str]] = {}
        for key, data, text in items:
            try:
                a, sr = _samples(data)
                words[key] = (self.mod.align(self.aligner, a, sr, text), "")
            except Exception as e:  # noqa: BLE001
                words[key] = (None, str(e))
        chars, rz_seconds = rz.get()
        out = []
        for key, c, error in chars:
            w, werr = words[key]
            out.append((key, c, w, "; ".join(x for x in (error, werr) if x)))
        return out, time.time() - started + rz_seconds


def answers(items: list[Item]) -> list[tuple[str, dict | None, list | None, str]]:
    """Both models' answers for a batch, from inside another function of an app that includes this one."""
    return Qwen().both.remote(items)[0]


def flac(wav: Path, out: Path) -> None:
    """The WAV packed losslessly (the same samples, about half the bytes)."""
    if out.is_file():
        return
    part = out.with_suffix(".part")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-c:a", "flac", "-f", "flac", str(part)],
                   check=True)
    part.replace(out)


def done_in(out: Path) -> set[str]:
    both = []
    for name in ("reazon.jsonl", "qwen.jsonl"):
        path = out / name
        rows = path.read_text(encoding="utf-8").splitlines() if path.is_file() else []
        both.append({json.loads(x)["stem"] for x in rows if x.strip()})
    return both[0] & both[1]


def upload(jobs: list[dict], packed: Path) -> None:
    """Packs every job's WAV as FLAC and uploads the ones the volume does not hold yet. No card runs."""
    from concurrent.futures import ThreadPoolExecutor

    packed.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(lambda j: flac(Path(j["wav"]), packed / f"{j['stem']}.flac"), jobs))
    try:
        there = {Path(e.path).name for e in volume.listdir("/flac")}
    except Exception:  # noqa: BLE001 - a new volume has no /flac yet
        there = set()
    todo = [j for j in jobs if f"{j['stem']}.flac" not in there]
    size = sum((packed / f"{j['stem']}.flac").stat().st_size for j in todo)
    print(f"align_modal: uploading {len(todo)} files, {size / 1e9:.1f} GB", flush=True)
    for n in range(0, len(todo), 500):
        with volume.batch_upload(force=True) as b:
            for j in todo[n:n + 500]:
                b.put_file(str(packed / f"{j['stem']}.flac"), f"/flac/{j['stem']}.flac")
        print(f"align_modal: uploaded {min(n + 500, len(todo))}/{len(todo)}", flush=True)


def main() -> int:
    ap = argparse.ArgumentParser(prog="align_modal", description=__doc__.split("\n\n")[0])
    ap.add_argument("jobs", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--limit", type=int, default=None, help="only this many lines (a trial)")
    ap.add_argument("--max-dollars", type=float, default=15.0, help="stop before the cards cost more")
    ap.add_argument("--max-minutes", type=float, default=45.0, help="stop the cards after this long")
    a = ap.parse_args()
    done = done_in(a.out)
    jobs = [j for j in map(json.loads, a.jobs.read_text(encoding="utf-8").splitlines())
            if j["stem"] not in done][: a.limit]
    print(f"align_modal: {len(jobs)} lines on {GPU}", flush=True)
    if not jobs:
        return 0
    a.out.mkdir(parents=True, exist_ok=True)
    upload(jobs, a.out / "flac")
    batches = [([(j["stem"], f"/audio/flac/{j['stem']}.flac", j["text"]) for j in jobs[n:n + BATCH]],)
               for n in range(0, len(jobs), BATCH)]
    started, timed, failed, card_seconds, seen = time.time(), 0, 0, 0.0, 0
    stop = ""
    with (a.out / "reazon.jsonl").open("a", encoding="utf-8") as rz_out, \
            (a.out / "qwen.jsonl").open("a", encoding="utf-8") as qw_out, \
            modal.enable_output(), app.run():
        for result in Qwen().both.starmap(batches, order_outputs=False, return_exceptions=True):
            seen += 1
            if isinstance(result, BaseException):
                failed += BATCH
                print(f"align_modal: a batch failed: {result}", file=sys.stderr, flush=True)
            else:
                rows, seconds = result
                card_seconds += seconds
                for stem, chars, words, error in rows:
                    if chars is None or words is None:
                        failed += 1
                        print(f"align_modal: {stem}: {error}", file=sys.stderr, flush=True)
                        continue
                    rz_out.write(json.dumps({"stem": stem, "chars": chars}) + "\n")
                    qw_out.write(json.dumps({"stem": stem, "words": words}) + "\n")
                    timed += 1
                rz_out.flush()
                qw_out.flush()
            # billed time: each card's working seconds, doubled for start-up and idle (Modal bills both)
            spent = 2 * card_seconds * PRICE
            projected = spent * len(batches) / seen
            minutes = (time.time() - started) / 60
            print(f"align_modal: {timed}/{len(jobs)} timed, {failed} failed, {minutes:.1f} min, "
                  f"about ${spent:.2f} so far, ${projected:.2f} projected", flush=True)
            if seen >= 3 and projected > a.max_dollars:
                stop = f"projected ${projected:.2f} is over --max-dollars {a.max_dollars}"
            elif spent > a.max_dollars:
                stop = f"spent about ${spent:.2f}, over --max-dollars {a.max_dollars}"
            elif minutes > a.max_minutes:
                stop = f"{minutes:.0f} minutes, over --max-minutes {a.max_minutes}"
            if stop:
                break
    if stop:
        print(f"align_modal: stopped, {stop}; every card is stopped. Run again to go on.", file=sys.stderr)
        return 2
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
