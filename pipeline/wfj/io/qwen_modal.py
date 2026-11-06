"""Reads exported cloned-voice lines on rented GPUs (Modal), with the same model and worker code (ADR-074).

    WFJ_MODAL_GPU=L40S WFJ_MODAL_CONTAINERS=10 \\
        build/modal/venv/bin/python pipeline/wfj/io/qwen_modal.py RUN_DIR [--limit N]

RUN_DIR is written by `wfj voice remote export`: jobs.jsonl (one line per file: key, text, reference, mode),
refs/ (the joined set references) and refs.json (their transcripts). Each GPU container loads Qwen3-TTS once
with `qwen_worker.load` and reads its lines with `qwen_worker.speak`, exactly as the local engine does; the
WAVs come back to RUN_DIR/wav/<key>.wav, where `wfj voice generate --prepared RUN_DIR` encodes and records
them. A rerun reads only the lines with no WAV yet. Run with the Modal client's own environment
(`build/modal/venv`), never imported by the pipeline.
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
QWEN_TTS = "0.1.1"  # the version `make voice-qwen-setup` pins
GPU = os.environ.get("WFJ_MODAL_GPU", "L40S")
BATCH = int(os.environ.get("WFJ_MODAL_BATCH", "15"))  # lines per call: small, so every card stays busy
PARAGRAPHS = int(os.environ.get("WFJ_MODAL_PARAGRAPHS", "24"))  # paragraphs the GPU reads in one model call

image = (
    modal.Image.debian_slim(python_version="3.12")
    .pip_install(f"qwen-tts=={QWEN_TTS}", "soundfile", "numpy", "huggingface_hub")
    .run_commands(
        "python -c \"from huggingface_hub import snapshot_download; "
        "snapshot_download('Qwen/Qwen3-TTS-12Hz-1.7B-Base')\""
    )
    .add_local_file(HERE / "qwen_worker.py", "/root/qwen_worker.py")
)
app = modal.App("wfj-voice", image=image)


@app.cls(gpu=GPU, timeout=3600, max_containers=int(os.environ.get("WFJ_MODAL_CONTAINERS", "10")))
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
    def read(self, refs: dict[str, bytes], lines: list[dict]) -> list[tuple[str, bytes | None, str]]:
        """[(key, WAV bytes or None, error)] for a batch of lines; `refs` carries the references they use."""
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
        self.worker.free("cuda")
        return out


def batches(run: Path, limit: int | None) -> list[tuple[dict[str, bytes], list[dict]]]:
    """The lines with no WAV yet, in batches that each carry the references they use."""
    wav = run / "wav"
    texts = json.loads((run / "refs.json").read_text(encoding="utf-8"))
    todo = [j for j in map(json.loads, (run / "jobs.jsonl").read_text(encoding="utf-8").splitlines())
            if not (wav / f"{j['key']}.wav").is_file()]
    if limit:
        todo = todo[:limit]
    # longest lines first: they start on the first free cards instead of piling up at the end, and the short
    # ones fill the gaps while the long ones finish
    todo.sort(key=lambda j: (-len(j["text"]), j["key"]))
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
    started, done, failed = time.time(), 0, 0
    with modal.enable_output(), app.run():
        for result in Reader().read.starmap(work, order_outputs=False):
            for key, data, error in result:
                if data is None:
                    failed += 1
                    print(f"qwen_modal: {key}: {error}", file=sys.stderr, flush=True)
                    continue
                tmp = a.run / "wav" / f"{key}.part"
                tmp.write_bytes(data)
                tmp.replace(a.run / "wav" / f"{key}.wav")
                done += 1
            took = time.time() - started
            print(f"qwen_modal: {done}/{lines} read, {failed} failed, {took:.0f} s", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
