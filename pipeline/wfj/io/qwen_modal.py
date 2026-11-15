"""Reads exported cloned-voice lines on rented GPUs (Modal), with the same model and worker code (ADR-074).

    WFJ_MODAL_GPU=L40S WFJ_MODAL_CONTAINERS=10 \\
        build/modal/venv/bin/python pipeline/wfj/io/qwen_modal.py RUN_DIR [--limit N]

RUN_DIR is written by `wfj voice export`: jobs.jsonl (one line per file: key, text, reference, mode),
refs/ (the joined set references) and refs.json (their transcripts). Each GPU container loads Qwen3-TTS once
with `qwen_worker.load` and reads its lines with `qwen_worker.speak`, exactly as the local engine does; the
WAVs come back to RUN_DIR/wav/<key>.wav, where `wfj voice generate --prepared RUN_DIR` encodes and records
them. A rerun reads only the lines with no WAV yet. Each line read is also timed on the cards
(`align_modal.py`), from its WAV kept on the volume, and the answers are written beside the WAVs
(RUN_DIR/align-reazon.jsonl, align-qwen.jsonl), where `wfj voice time` finds them. Run with the Modal client's
own environment (`build/modal/venv`), never imported by the pipeline.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

import modal

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import align_modal  # noqa: E402 - beside this file, here and on the cards

QWEN_TTS = "0.1.1"  # the version `make voice-qwen-setup` pins
MODEL_REVISION = "fd4b254389122332181a7c3db7f27e918eec64e3"  # the weights local runs read: both sound alike
GPU = os.environ.get("WFJ_MODAL_GPU", "L40S")
BATCH = int(os.environ.get("WFJ_MODAL_BATCH", "15"))  # lines per call: small, so every card stays busy
PARAGRAPHS = int(os.environ.get("WFJ_MODAL_PARAGRAPHS", "24"))  # paragraphs the GPU reads in one model call

image = (
    modal.Image.debian_slim(python_version="3.12")
    .pip_install(f"qwen-tts=={QWEN_TTS}", "soundfile", "numpy", "huggingface_hub")
    .run_commands(
        "python -c \"from huggingface_hub import snapshot_download; "
        f"snapshot_download('Qwen/Qwen3-TTS-12Hz-1.7B-Base', revision='{MODEL_REVISION}')\""
    )
    .add_local_file(HERE / "qwen_worker.py", "/root/qwen_worker.py")
    .add_local_file(HERE / "align_modal.py", "/root/align_modal.py")
)
app = modal.App("wfj-voice", image=image)
app.include(align_modal.app)  # the aligners time each line from its WAV on the volume, as it is read


@app.cls(gpu=GPU, timeout=3600, max_containers=int(os.environ.get("WFJ_MODAL_CONTAINERS", "10")),
         volumes={"/audio": align_modal.volume})
class Reader:
    @modal.enter()
    def setup(self) -> None:
        sys.path.insert(0, "/root")
        import qwen_worker

        self.worker = qwen_worker
        self.model = qwen_worker.load("cuda")
        self.prompts: dict = {}
        self.refs: dict[str, str] = {}

    @modal.method()
    def read(self, refs: dict[str, bytes], lines: list[dict],
             run: str = "") -> list[tuple[str, bytes | None, str]]:
        """[(key, WAV bytes or None, error)] for a batch of lines; `refs` carries the references they use.
        With `run`, each WAV is also kept on the volume (runs/<run>/<key>.wav) for the aligners."""
        import io

        import soundfile as sf

        for name, data in refs.items():
            if name not in self.refs:
                path = f"/tmp/{name}"
                Path(path).write_bytes(data)
                self.refs[name] = path
        reqs = [{**ln, "ref_wav": self.refs[ln["ref"]]} for ln in lines]
        out = []
        read = self.worker.speak_many(self.model, self.prompts, reqs, PARAGRAPHS)
        for ln, got in zip(lines, read, strict=True):
            if isinstance(got, str):
                out.append((ln["key"], None, got))
                continue
            buf = io.BytesIO()
            sf.write(buf, got[0], got[1], format="WAV", subtype="PCM_16")
            out.append((ln["key"], buf.getvalue(), ""))
            if run:
                kept = Path(f"/audio/runs/{run}/{ln['key']}.wav")
                kept.parent.mkdir(parents=True, exist_ok=True)
                kept.write_bytes(buf.getvalue())
        self.worker.free("cuda")
        if run:
            align_modal.volume.commit()
        return out


def batches(run: Path, limit: int | None) -> list[tuple[dict[str, bytes], list[dict]]]:
    """The lines with no WAV yet, in batches that each carry the references they use."""
    wav = run / "wav"
    texts = json.loads((run / "refs.json").read_text(encoding="utf-8"))
    todo = [j for j in map(json.loads, (run / "jobs.jsonl").read_text(encoding="utf-8").splitlines())
            if not (wav / f"{j['key']}.wav").is_file()]
    if limit:
        todo = todo[:limit]
    # one voice's lines together, so a card's calls stay full; within a voice the longest first
    from qwen_worker import send_order

    todo = send_order(todo)
    out = []
    for n in range(0, len(todo), BATCH):
        part = [{**j, "ref_text": texts.get(j["ref"])} for j in todo[n : n + BATCH]]
        refs = {r: (run / "refs" / r).read_bytes() for r in {j["ref"] for j in part}}
        out.append((refs, part))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(prog="qwen_modal", description=__doc__.split("\n\n")[0])
    ap.add_argument("run", type=Path)
    ap.add_argument("--limit", type=int, default=None, help="only this many lines (a test run)")
    a = ap.parse_args()
    work = batches(a.run, a.limit)
    lines = sum(len(b[1]) for b in work)
    print(f"qwen_modal: {lines} lines in {len(work)} batches on {GPU}", flush=True)
    if not work:
        return 0
    (a.run / "wav").mkdir(exist_ok=True)
    try:
        return _read_and_time(a, work, lines)
    finally:
        try:
            align_modal.volume.remove_file(f"/runs/{a.run.name}", recursive=True)
        except Exception as e:  # noqa: BLE001 - only space left on the volume; the run's answers are kept
            print(f"qwen_modal: could not clear runs/{a.run.name} from the volume: {e}", file=sys.stderr)


def _read_and_time(a: argparse.Namespace, work: list, lines: int) -> int:
    """Reads every batch on the cards, keeps its WAVs, and has the aligners time each line it read."""
    started, done, failed = time.time(), 0, 0
    texts = {ln["key"]: ln["text"] for _, part in work for ln in part}
    timing = []  # the aligners' calls, one per batch read: they start as cards come free
    with modal.enable_output(), app.run():
        # one batch that fails as a whole (the call limit, a crash) is counted and the others still come back
        calls = [(refs, part, a.run.name) for refs, part in work]
        for result in Reader().read.starmap(calls, order_outputs=False, return_exceptions=True):
            if isinstance(result, BaseException):
                failed += 1
                print(f"qwen_modal: a batch failed: {result}", file=sys.stderr, flush=True)
                continue
            read = []
            for key, data, error in result:
                if data is None:
                    failed += 1
                    print(f"qwen_modal: {key}: {error}", file=sys.stderr, flush=True)
                    continue
                tmp = a.run / "wav" / f"{key}.part"
                tmp.write_bytes(data)
                tmp.replace(a.run / "wav" / f"{key}.wav")
                done += 1
                read.append((key, f"/audio/runs/{a.run.name}/{key}.wav", texts[key]))
            if read:
                timing.append(align_modal.Qwen().both.spawn(read))
            took = time.time() - started
            print(f"qwen_modal: {done}/{lines} read, {failed} failed, {took:.0f} s", flush=True)
        timed = keep_answers(a.run, timing)
        print(f"qwen_modal: {timed}/{done} lines timed beside their WAVs", flush=True)
    return 1 if failed else 0


def keep_answers(run: Path, calls: list) -> int:
    """The aligners' answers for the lines read, beside their WAVs (`wfj voice time` reads them there, so a
    line is timed once, while its WAV is on the cards) → how many lines were timed. A line they could not time
    is timed later by `wfj voice time`."""
    timed = 0
    with (run / "align-reazon.jsonl").open("a", encoding="utf-8") as rz, \
            (run / "align-qwen.jsonl").open("a", encoding="utf-8") as qw:
        for call in calls:
            try:
                rows, _ = call.get()
            except Exception as e:  # noqa: BLE001 - the WAVs are home; the timing step does these lines
                print(f"qwen_modal: a timing batch failed: {e}", file=sys.stderr, flush=True)
                continue
            for key, chars, words, error in rows:
                if chars is None or words is None:
                    print(f"qwen_modal: {key}: not timed ({error})", file=sys.stderr, flush=True)
                    continue
                rz.write(json.dumps({"key": key, "chars": chars}) + "\n")
                qw.write(json.dumps({"key": key, "words": words}) + "\n")
                timed += 1
    return timed


if __name__ == "__main__":
    raise SystemExit(main())
