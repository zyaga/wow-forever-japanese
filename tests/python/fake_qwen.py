"""A stand-in for the Qwen3-TTS worker (`wfj/io/qwen_worker.py`) for the tests: same pipe protocol, no model.

It answers each request with a short silent WAV, or with an error when the text is "FAIL". Each request is
appended to $FAKE_QWEN_LOG as a JSON line, so a test can see what the pipeline asked for.
"""

from __future__ import annotations

import json
import os
import sys
import wave


def main() -> int:
    print(json.dumps({"ready": True, "version": "0.0.test", "model": "fake"}), flush=True)
    log = os.environ.get("FAKE_QWEN_LOG")
    for raw in sys.stdin:
        req = json.loads(raw)
        if log:
            with open(log, "a", encoding="utf-8") as f:
                f.write(json.dumps(req, ensure_ascii=False) + "\n")
        if req["text"] == "FAIL":
            print(json.dumps({"ok": False, "error": "ValueError: asked to fail"}), flush=True)
            continue
        with wave.open(req["out"], "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(24000)
            w.writeframes(b"\0\0" * 12000)
        print(json.dumps({"ok": True}), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
