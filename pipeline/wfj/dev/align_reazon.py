"""ReazonSpeech's start for every character a voice line's engine read (ADR-090), for `wfj voice time`.

Run only with the PyTorch interpreter (ALIGN_REAZON_PY, build/tts-venv): never imported by the pipeline.
  python align_reazon.py <jobs.jsonl> <out.jsonl>
jobs: {"stem", "wav", "text"} per line; out: {"stem", "chars": {index: seconds}} per line, appended, so a run
that stops resumes where it was. ALIGN_DEVICE=cpu keeps the GPU free (several times slower).

The model, reazon-research/japanese-wav2vec2-large-rs35kh (Apache-2.0), hears characters; torchaudio's
forced_align fits the known text to what it hears. A character the model has no token for is spelt in
hiragana by pykakasi and timed by its first kana."""

from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path

import pykakasi
import soundfile
import torch
import torchaudio.functional as F
from huggingface_hub import snapshot_download
from transformers import Wav2Vec2FeatureExtractor, Wav2Vec2ForCTC

MODEL = "reazon-research/japanese-wav2vec2-large-rs35kh"
RATE = 16000
LEAD_IN = 0.5  # seconds of silence before the line: the model's first frames are unreliable without it
LATE = 0.05  # seconds: the model marks a character's start this much late (measured on comma pauses)
SKIP = re.compile(r"[\s。、！？!?「」『』（）()・…〜~,.\-—–:;]")


def targets(text: str, vocab: dict[str, int], kks: pykakasi.kakasi) -> tuple[list[int], list[int]]:
    ids, owner, i = [], [], 0
    while i < len(text):
        ch = text[i]
        if SKIP.match(ch):
            i += 1
            continue
        if ch in vocab:
            ids.append(vocab[ch])
            owner.append(i)
            i += 1
            continue
        j = i
        while j < len(text) and not SKIP.match(text[j]) and text[j] not in vocab:
            j += 1
        for part in kks.convert(text[i:j]):
            for k in part["hira"]:
                if k in vocab:
                    ids.append(vocab[k])
                    owner.append(i)
        i = j
    return ids, owner


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
    model = Wav2Vec2ForCTC.from_pretrained(MODEL).to(device).eval()
    fe = Wav2Vec2FeatureExtractor.from_pretrained(MODEL)
    vocab = json.loads((Path(snapshot_download(MODEL)) / "vocab.json").read_text(encoding="utf-8"))
    kks = pykakasi.kakasi()
    started, heard = time.time(), 0.0
    with Path(out_path).open("a", encoding="utf-8") as out:
        for n, job in enumerate(jobs, 1):
            a, sr = soundfile.read(job["wav"], dtype="float32")
            if a.ndim > 1:
                a = a.mean(1)
            seconds = len(a) / sr
            heard += seconds
            a16 = F.resample(torch.from_numpy(a), sr, RATE)
            padded = torch.nn.functional.pad(a16, (int(LEAD_IN * RATE), 0))
            iv = fe(padded.numpy(), sampling_rate=RATE, return_tensors="pt").input_values.to(device)
            with torch.inference_mode():
                lp = torch.log_softmax(model(iv).logits.float().cpu(), -1)
            ids, owner = targets(job["text"], vocab, kks)
            chars: dict[str, float] = {}
            if ids:
                step = (len(padded) / RATE) / lp.shape[1]
                ali, scores = F.forced_align(lp, torch.tensor([ids], dtype=torch.int32), blank=0)
                for k, span in enumerate(F.merge_tokens(ali[0], scores[0].exp())):
                    t = min(seconds, max(0.0, span.start * step - LEAD_IN - LATE))
                    chars.setdefault(str(owner[k]), round(t, 3))
            out.write(json.dumps({"stem": job["stem"], "chars": chars}) + "\n")
            out.flush()
            if n % 100 == 0 or n == len(jobs):
                rate = heard / max(1e-6, time.time() - started)
                print(f"align reazon: {n}/{len(jobs)} lines, {rate:.0f}x real time", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
