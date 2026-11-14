"""Qwen3-ForcedAligner's start and end for every word of a voice line's engine text (ADR-090), for
`wfj voice time`.

Run only with the aligner's interpreter (ALIGN_QWEN_PY, build/aligner-venv with qwen-asr): never imported by
the pipeline.
  python align_qwen.py <jobs.jsonl> <out.jsonl>
jobs: {"stem", "wav", "text"} per line; out: {"stem", "words": [[first, end, start, end], ...]} per line
(first and end are character indexes in the text, start and end seconds), appended, so a run that stops
resumes where it was. ALIGN_DEVICE=cpu keeps the GPU free (several times slower).

The model, Qwen/Qwen3-ForcedAligner-0.6B (Apache-2.0), splits Japanese into words with nagisa and times each
in 80 ms steps; a word it drops (punctuation) is simply not in the list."""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

import soundfile
import torch
from qwen_asr.inference.qwen3_forced_aligner import Qwen3ForcedAligner

MODEL = "Qwen/Qwen3-ForcedAligner-0.6B"


def main(jobs_path: str, out_path: str) -> int:
    device = os.environ.get("ALIGN_DEVICE") or ("mps" if torch.backends.mps.is_available() else "cpu")
    done = set()
    if Path(out_path).is_file():
        done = {json.loads(line)["stem"] for line in Path(out_path).read_text(encoding="utf-8").splitlines()
                if line.strip()}
    listed = Path(jobs_path).read_text(encoding="utf-8").splitlines()
    jobs = [json.loads(line) for line in listed if line.strip()]
    jobs = [j for j in jobs if j["stem"] not in done]
    if not jobs:
        return 0
    aligner = Qwen3ForcedAligner.from_pretrained(MODEL, dtype=torch.float32, device_map=device)
    started, heard = time.time(), 0.0
    with Path(out_path).open("a", encoding="utf-8") as out:
        for n, job in enumerate(jobs, 1):
            a, sr = soundfile.read(job["wav"], dtype="float32")
            if a.ndim > 1:
                a = a.mean(1)
            heard += len(a) / sr
            text = job["text"]
            words: list[list[float]] = []
            try:
                items = aligner.align(audio=(a, sr), text=text, language="Japanese")[0]
            except Exception as e:  # noqa: BLE001 - one line the model cannot take is reported, the run goes on
                print(f"align qwen: {job['stem']}: {e}", flush=True)
                items = []
            pos = 0
            for it in items:
                i = text.find(it.text, pos) if it.text else -1
                if i < 0:
                    continue
                pos = i + len(it.text)
                words.append([i, pos, round(float(it.start_time), 3), round(float(it.end_time), 3)])
            out.write(json.dumps({"stem": job["stem"], "words": words}) + "\n")
            out.flush()
            if n % 100 == 0 or n == len(jobs):
                rate = heard / max(1e-6, time.time() - started)
                print(f"align qwen: {n}/{len(jobs)} lines, {rate:.0f}x real time", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
