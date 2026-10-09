"""The local AivisSpeech Engine over HTTP (stdlib only): its version and one line's WAV.

The engine runs on this machine (`build/aivis/`); nothing here reaches the network beyond the configured URL.
A line is made in two calls, as the engine's own API documents: `POST /audio_query` turns the text into a
query (readings, accents, pauses), and `POST /synthesis` renders that query, after the pace is set on it.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


class EngineError(RuntimeError):
    """The engine is not answering, or answered with an error."""


class Engine:
    def __init__(self, url: str, timeout: float = 600.0):
        self.url = url.rstrip("/")
        self.timeout = timeout

    def _call(self, method: str, path: str, params: dict[str, Any] | None = None, body: Any = None) -> bytes:
        url = f"{self.url}{path}"
        if params:
            url += "?" + urllib.parse.urlencode(params)
        data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
        if method == "POST" and data is None:
            data = b""
        headers = {"Content-Type": "application/json"}
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                return r.read()
        except (urllib.error.URLError, OSError) as e:
            raise EngineError(f"{method} {path}: {e}") from e

    def version(self) -> str:
        v = json.loads(self._call("GET", "/version"))
        if not isinstance(v, str) or not v:
            raise EngineError(f"/version: unexpected answer {v!r}")
        return v

    def speakers(self) -> list[dict[str, Any]]:
        return json.loads(self._call("GET", "/speakers"))

    def model_of(self, style: int) -> str:
        """The model (speaker uuid) a style id belongs to: part of a file's fingerprint."""
        for sp in self.speakers():
            if any(st.get("id") == style for st in sp.get("styles", [])):
                return str(sp.get("speaker_uuid"))
        raise EngineError(f"style {style} is not installed in the engine")

    def synthesize(
        self, text: str, style: int, speed: float, pitch: float = 0.0, intonation: float = 1.0
    ) -> bytes:
        """One line's WAV in a voice style, at a pace, pitch shift and intonation strength (the engine's
        `speedScale`, `pitchScale` and `intonationScale` on the query)."""
        query = json.loads(self._call("POST", "/audio_query", {"text": text, "speaker": style}))
        query["speedScale"] = speed
        query["pitchScale"] = pitch
        query["intonationScale"] = intonation
        wav = self._call("POST", "/synthesis", {"speaker": style}, query)
        if wav[:4] != b"RIFF":
            raise EngineError(f"/synthesis: not a WAV file ({len(wav)} bytes)")
        return wav
