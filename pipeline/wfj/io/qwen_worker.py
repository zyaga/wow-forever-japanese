"""The Qwen3-TTS worker: clones a game voice set and reads Japanese in it (ADR-074).

Run by `io/qwen.py` with the Python of the Qwen3-TTS environment (`make voice-qwen-setup`), never imported by
the pipeline: it is the only code that needs PyTorch. `qwen_modal.py` runs the same `load` and `speak` on
rented GPUs, so a line reads the same wherever it is made. One JSON request per stdin line, one JSON answer
per stdout line:

    → {"text": "...", "ref_wav": "/path/ref.wav", "ref_text": "..." | null, "mode": "voice" | "full",
       "out": "/path/line.wav"}
    ← {"ok": true} | {"ok": false, "error": "..."}

The first line it writes is {"ready": true, "version": <qwen-tts version>, "model": <model id>}. A voice-only
copy uses the speaker embedding alone (no transcript); a full copy also continues the clips and their words.
Paragraphs (a blank line between) are read one at a time and joined with a short pause, which keeps long quest
texts at an even pace. The GPU memory a line used is handed back after it.
"""

from __future__ import annotations

import json
import sys
import time
from typing import Any

MODEL = "Qwen/Qwen3-TTS-12Hz-1.7B-Base"
PARAGRAPH_GAP = 0.6  # seconds
TOKENS_PER_SECOND = 12  # the model's speech tokens (12 Hz)
CHARS_PER_SECOND = 5.88  # measured speaking rate of the picked voices


def token_cap(texts: list[str]) -> int:
    """The most speech tokens a call may make: twice the longest text's expected length plus 3 s. Without
    it a line the model fails to end runs to the library's 2,048 tokens (about 170 s) and holds its call."""
    longest = max(len(t) for t in texts)
    return int(TOKENS_PER_SECOND * (2 * longest / CHARS_PER_SECOND + 3))


def ran_on(samples: Any, rate: int, cap: int) -> bool:
    """A paragraph that filled its cap did not end by itself: it is not kept."""
    return len(samples) / rate >= 0.97 * cap / TOKENS_PER_SECOND


def load(device: str) -> Any:
    """The model on `device` (mps, cuda or cpu), in bfloat16."""
    import torch
    from qwen_tts import Qwen3TTSModel

    return Qwen3TTSModel.from_pretrained(MODEL, device_map=device, dtype=torch.bfloat16,
                                         attn_implementation="sdpa")


def speak(model: Any, prompts: dict, text: str, ref_wav: str, ref_text: str | None,
          mode: str) -> tuple[Any, int]:
    """(samples, sample rate) of one line read in a reference's voice; `prompts` caches each reference's
    clone prompt between lines."""
    import numpy as np

    prompt = _prompt(model, prompts, ref_wav, ref_text, mode)
    parts, rate = [], 24000
    for para in (p for p in text.split("\n\n") if p.strip()):
        cap = token_cap([para])
        wavs, rate = model.generate_voice_clone(text=para, language="Japanese",
                                                voice_clone_prompt=prompt, max_new_tokens=cap)
        if ran_on(wavs[0], rate, cap):
            raise ValueError(f"the reading ran on past {cap // TOKENS_PER_SECOND} s: {para[:30]}")
        parts += [wavs[0], np.zeros(int(rate * PARAGRAPH_GAP), dtype=wavs[0].dtype)]
    if not parts:
        raise ValueError("no text to read")
    return np.concatenate(parts[:-1]), rate


def _prompt(model: Any, prompts: dict, ref_wav: str, ref_text: str | None, mode: str) -> Any:
    key = (ref_wav, mode)
    if key not in prompts:
        prompts[key] = model.create_voice_clone_prompt(ref_audio=ref_wav, ref_text=ref_text,
                                                       x_vector_only_mode=mode == "voice")
    return prompts[key]


def speak_many(model: Any, prompts: dict, lines: list[dict], batch: int,
               chars: int = 3000) -> list[tuple[Any, int] | str]:
    """Each line's (samples, rate), or its error, read several paragraphs per model call: the GPU reads a
    call in about the time of its longest paragraph. Every paragraph of a call is padded to its longest, so a
    call holds at most `batch` paragraphs and at most `chars` padded characters (count times the longest):
    long quest texts go in small calls and short lines in large ones.
    A call that runs out of memory is freed and split in half until it fits. Each paragraph is read in its
    own line's voice, and a line's paragraphs are joined in order as `speak` joins them."""
    import numpy as np

    paras = [(i, k, p) for i, ln in enumerate(lines)
             for k, p in enumerate(x for x in ln["text"].split("\n\n") if x.strip())]
    paras.sort(key=lambda t: len(t[2]))  # like lengths together: less padding
    calls: list[list[tuple[int, int, str]]] = [[]]
    for t in paras:
        cur = calls[-1]
        if cur and (len(cur) >= batch or (len(cur) + 1) * len(t[2]) > chars):  # sorted: t is the longest
            calls.append([])
        calls[-1].append(t)
    got: dict[int, dict[int, Any]] = {}
    errors: dict[int, str] = {}
    rate = 24000
    todo = [c for c in calls if c]
    while todo:
        part = todo.pop(0)
        try:
            items = [_prompt(model, prompts, lines[i]["ref_wav"], lines[i].get("ref_text"),
                             lines[i]["mode"])[0] for i, _, _ in part]
            cap = token_cap([p for _, _, p in part])
            wavs, rate = model.generate_voice_clone(text=[p for _, _, p in part],
                                                    language=["Japanese"] * len(part),
                                                    voice_clone_prompt=items, max_new_tokens=cap)
        except Exception as e:  # noqa: BLE001 - out of memory: free it and read the call in halves
            free_all()
            if len(part) > 1 and "out of memory" in str(e).lower():
                half = len(part) // 2
                todo[:0] = [part[:half], part[half:]]
                continue
            for i, _, _ in part:
                errors[i] = f"{type(e).__name__}: {e}"
            continue
        for (i, k, p), w in zip(part, wavs, strict=True):
            if ran_on(w, rate, cap):
                errors[i] = f"ValueError: the reading ran on past {cap // TOKENS_PER_SECOND} s: {p[:30]}"
            got.setdefault(i, {})[k] = w
    out: list[tuple[Any, int] | str] = []
    for i in range(len(lines)):
        if i in errors:
            out.append(errors[i])
            continue
        pieces = [got[i][k] for k in sorted(got.get(i, {}))]
        if not pieces:
            out.append("no text to read")
            continue
        gap = np.zeros(int(rate * PARAGRAPH_GAP), dtype=pieces[0].dtype)
        out.append((np.concatenate([x for w in pieces for x in (w, gap)][:-1]), rate))
    return out


def free_all() -> None:
    """Hands back whatever GPU memory PyTorch holds, on whichever device it is."""
    import gc

    import torch

    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
    elif torch.backends.mps.is_available():
        torch.mps.empty_cache()


def free(device: str) -> None:
    """PyTorch keeps freed GPU buffers cached and grows to the longest line read so far; handing them back
    after each line keeps an engine near the model's own size, so several fit side by side."""
    import torch

    if device == "mps":
        torch.mps.empty_cache()
    elif device == "cuda":
        torch.cuda.empty_cache()


def main() -> int:
    answer = sys.stdout
    sys.stdout = sys.stderr  # the libraries print while loading; only answers go to the real stdout
    import importlib.metadata

    import soundfile as sf
    import torch

    started = time.time()
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    model = load(device)

    def say(obj: dict) -> None:
        answer.write(json.dumps(obj, ensure_ascii=False) + "\n")
        answer.flush()

    say({"ready": True, "version": importlib.metadata.version("qwen-tts"), "model": MODEL,
         "load": round(time.time() - started, 1)})
    prompts: dict[tuple[str, str], object] = {}
    for raw in sys.stdin:
        if not raw.strip():
            continue
        try:
            req = json.loads(raw)
            audio, rate = speak(model, prompts, req["text"], req["ref_wav"], req.get("ref_text"), req["mode"])
            sf.write(req["out"], audio, rate, subtype="PCM_16")
            say({"ok": True})
        except Exception as e:  # noqa: BLE001 - every failure is answered, the worker keeps serving
            say({"ok": False, "error": f"{type(e).__name__}: {e}"})
        finally:
            free(device)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
