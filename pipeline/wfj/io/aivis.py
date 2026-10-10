"""The local AivisSpeech Engine over HTTP (stdlib only): its version and one line's WAV.

The engine runs on this machine (`build/aivis/`); nothing here reaches the network beyond the configured URL.
A line is made in two calls, as the engine's own API documents: `POST /audio_query` turns the text into a
query (readings, accents, pauses), and `POST /synthesis` renders that query, after the pace is set on it.
"""

from __future__ import annotations

import contextlib
import fcntl
import json
import signal
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Iterator
from pathlib import Path
from typing import Any


class EngineError(RuntimeError):
    """The engine is not answering, or answered with an error."""


class EngineDown(EngineError):
    """No engine answers and there is none to start."""


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


def _stop(_signum: int, _frame: Any) -> None:
    raise SystemExit(1)


# a probe gets a short timeout: something that accepts on the port and never replies must not hold the start
# for the engine's synthesis timeout
PROBE_TIMEOUT = 2.0


def _answers(engine: Engine) -> str | None:
    """The engine's version, or None when nothing answers yet."""
    try:
        probe = engine
        if type(engine) is Engine:
            probe = Engine(engine.url, timeout=min(engine.timeout, PROBE_TIMEOUT))
        return probe.version()
    except (EngineError, ValueError):
        return None


def _users_lock(url: str) -> Any:
    """A lock file per engine address. Every run using the engine holds it shared; the run that started the
    engine takes it exclusive before stopping it, so it waits for the other runs to finish first."""
    where = urllib.parse.urlsplit(url)
    name = f"wfj-aivis-{where.hostname or '127.0.0.1'}-{where.port or 10101}.lock"
    path = Path(tempfile.gettempdir()) / name
    return path.open("a")


@contextlib.contextmanager
def _signals_stop() -> Iterator[None]:
    """SIGTERM and SIGHUP end the run through `finally` (they would otherwise end Python without it, leaving
    the engine up). A signal already ignored (a run under nohup ignores SIGHUP) stays ignored. Only the main
    thread can set handlers; elsewhere the caller's handling stands."""
    if threading.current_thread() is not threading.main_thread():
        yield
        return
    stops = [s for s in (signal.SIGTERM, signal.SIGHUP) if signal.getsignal(s) != signal.SIG_IGN]
    previous = {s: signal.signal(s, _stop) for s in stops}
    try:
        yield
    finally:
        for s, handler in previous.items():
            signal.signal(s, handler)


@contextlib.contextmanager
def _teardown_shielded() -> Iterator[None]:
    """A second stop signal while the engine is being stopped would skip the stop: hold them off till done."""
    if threading.current_thread() is not threading.main_thread():
        yield
        return
    previous = {s: signal.signal(s, signal.SIG_IGN) for s in (signal.SIGTERM, signal.SIGHUP)}
    try:
        yield
    finally:
        for s, handler in previous.items():
            signal.signal(s, handler)


def _stop_engine(proc: subprocess.Popen[bytes], log: Callable[[str], None]) -> None:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        log("stopped the AivisSpeech Engine")


@contextlib.contextmanager
def running(
    engine: Engine, command: Path | None, wait: float = 120.0, log: Callable[[str], None] = print
) -> Iterator[str]:
    """The engine answering for the length of the block, which gets its version. One already answering is
    used and left running; otherwise `command` (the engine's `run`) is started on the engine's host and port
    and stopped when the block ends, however it ends, once no other run is using it."""
    with _users_lock(engine.url) as lock, _signals_stop():
        fcntl.flock(lock, fcntl.LOCK_SH)
        version = _answers(engine)
        if version:
            yield version
            return
        if command is None or not command.is_file():
            raise EngineDown(f"nothing answers at {engine.url} and there is no engine at {command}")
        where = urllib.parse.urlsplit(engine.url)
        # its own session, so closing the terminal reaches only this process, which then stops the engine
        proc = subprocess.Popen(
            [str(command), "--host", where.hostname or "127.0.0.1", "--port", str(where.port or 10101)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            log(f"started the AivisSpeech Engine ({command})")
            deadline = time.monotonic() + wait
            while not (version := _answers(engine)):
                if proc.poll() is not None:
                    raise EngineError(f"{command} exited with {proc.returncode} before answering")
                if time.monotonic() > deadline:
                    raise EngineError(f"{command} did not answer within {wait:.0f} s")
                time.sleep(0.2)
            yield version
        finally:
            with _teardown_shielded():
                if proc.poll() is None:
                    # wait for every other run using this engine to end, then stop it
                    try:
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError:
                        log("waiting for another voice run using the engine to finish before stopping it")
                        fcntl.flock(lock, fcntl.LOCK_EX)
                _stop_engine(proc, log)
