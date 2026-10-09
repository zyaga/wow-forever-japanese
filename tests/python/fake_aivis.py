"""A stand-in for the AivisSpeech Engine's `run`, for the tests that start and stop the engine.

Takes the engine's `--host` and `--port`, writes its pid to $FAKE_AIVIS_PIDFILE, then by $FAKE_AIVIS_MODE:
`serve` (default) answers /version, /audio_query and /synthesis, `exit` quits at once, `silent` never
listens.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import time
import wave
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


def _wav() -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes(b"\0\0" * 2205)
    return buf.getvalue()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def _send(self, body: bytes) -> None:
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._send(b'"1.2.0"' if self.path == "/version" else b"[]")

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if self.path.startswith("/audio_query"):
            self._send(json.dumps({"accent_phrases": [], "speedScale": 1.0}).encode())
        else:
            self._send(_wav())


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=10101)
    a = p.parse_args()
    Path(os.environ["FAKE_AIVIS_PIDFILE"]).write_text(str(os.getpid()))
    mode = os.environ.get("FAKE_AIVIS_MODE", "serve")
    if mode == "exit":
        raise SystemExit(3)
    if mode == "silent":
        while True:
            time.sleep(1)
    HTTPServer((a.host, a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
