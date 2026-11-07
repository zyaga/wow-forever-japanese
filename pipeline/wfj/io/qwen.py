"""The Qwen3-TTS engine for cloned game voice sets (ADR-074; docs/operations/voice.md).

The model and PyTorch live in their own environment (`make voice-qwen-setup`, `build/qwen/venv` of the main
checkout); the pipeline stays on the standard library and talks to `qwen_worker.py` over a pipe. The worker
runs at low priority (`nice`) unless a run is asked to go at full speed, and only one run may hold the
engine at a time; a run may start several workers side by side.
"""

from __future__ import annotations

import fcntl
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import IO, Any

WORKER = Path(__file__).with_name("qwen_worker.py")
VERSION = "0.1.1"  # qwen-tts, as `make voice-qwen-setup` and qwen_modal.py pin it
NICE = ("nice", "-n", "10")
LOCK = Path(tempfile.gettempdir()) / "wfj-qwen.lock"


class QwenError(RuntimeError):
    pass


class QwenBusy(QwenError):
    pass


class LineFailed(QwenError):
    """The worker could not read one line (it ran on, or ran out of memory); the worker itself goes on."""


class NotRead(QwenError):
    """A line a remote run has no WAV for yet: left for the next run, not an error of this one."""


class Qwen:
    """`with Qwen(python) as q: q.synthesize(...)`. Entering takes the one-run lock and starts the worker;
    leaving stops it."""

    def __init__(self, python: Path, worker: Path = WORKER, log: Path | None = None, lock: Path | None = LOCK,
                 nice: bool = True):
        """`lock` None: an extra worker of a run that already holds the lock. `nice` False: start at normal
        priority (a generation run sets each worker's tier itself, see `background`)."""
        self.python, self.worker, self.log, self.lock_path, self.nice = python, worker, log, lock, nice
        self.version = ""
        self._proc: subprocess.Popen[str] | None = None
        self._lock: IO[str] | None = None
        self._err: IO[str] | None = None

    def __enter__(self) -> Qwen:
        if not self.python.is_file():
            raise QwenError(f"no Qwen3-TTS environment at {self.python}: run make voice-qwen-setup")
        if self.lock_path is not None:
            self._lock = self.lock_path.open("a")
            try:
                fcntl.flock(self._lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as e:
                self._lock.close()
                self._lock = None
                raise QwenBusy("another voice run is making cloned voices; one runs at a time") from e
        self._err = self.log.open("a", encoding="utf-8") if self.log else None
        try:
            self._proc = subprocess.Popen(
                [*(NICE if self.nice else ()), str(self.python), "-I", str(self.worker)],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self._err or subprocess.DEVNULL,
                text=True,
            )
            hello = self._read()
        except BaseException:
            self.__exit__(None, None, None)  # the lock and the log are let go when the worker never starts
            raise
        if not hello.get("ready"):
            self.__exit__(None, None, None)
            raise QwenError(f"the Qwen3-TTS worker did not start: {hello}")
        self.version = str(hello.get("version", ""))
        return self

    def background(self, on: bool) -> None:
        """Moves the worker into macOS's background tier (efficiency cores, throttled I/O) or out of it, while
        it runs: how a run slows down while the machine is in use and speeds up when it is not."""
        if self._proc and self._proc.poll() is None and shutil.which("taskpolicy"):  # macOS only
            subprocess.run(["taskpolicy", "-b" if on else "-B", "-p", str(self._proc.pid)], check=False,
                           capture_output=True)

    def _read(self) -> dict[str, Any]:
        assert self._proc and self._proc.stdout
        line = self._proc.stdout.readline()
        if not line:
            raise QwenError(f"the Qwen3-TTS worker stopped (exit {self._proc.poll()}); see {self.log}")
        return json.loads(line)

    def synthesize(self, text: str, ref_wav: Path, ref_text: str | None, mode: str) -> bytes:
        """One line's WAV in a set's voice."""
        assert self._proc and self._proc.stdin
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "line.wav"
            req = {"text": text, "ref_wav": str(ref_wav), "ref_text": ref_text, "mode": mode, "out": str(out)}
            self._proc.stdin.write(json.dumps(req, ensure_ascii=False) + "\n")
            self._proc.stdin.flush()
            reply = self._read()
            if not reply.get("ok"):
                raise LineFailed(f"Qwen3-TTS: {reply.get('error')}")
            return out.read_bytes()

    def __exit__(self, *_exc: object) -> None:
        if self._proc:
            if self._proc.stdin:
                self._proc.stdin.close()
            try:
                self._proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                self._proc.kill()
                self._proc.wait()
            if self._proc.stdout:
                self._proc.stdout.close()
            self._proc = None
        if self._err:
            self._err.close()
            self._err = None
        if self._lock:
            fcntl.flock(self._lock, fcntl.LOCK_UN)
            self._lock.close()
            self._lock = None


def line_key(text: str, ref_wav: Path, mode: str) -> str:
    """The name a line's WAV has in a remote run: what was read, from which reference, in which mode."""
    import hashlib

    return hashlib.sha256(f"{ref_wav.name}|{mode}|{text}".encode()).hexdigest()[:24]


class Prepared:
    """Stands in for `Qwen` when the lines were read elsewhere (`qwen_modal.py`): hands back the WAV a remote
    run made for each line. Same interface, no model, no lock."""

    def __init__(self, run: Path):
        self.run = run
        manifest = run / "manifest.json"
        self.version = ""
        if manifest.is_file():
            self.version = json.loads(manifest.read_text(encoding="utf-8"))["version"]

    def __enter__(self) -> Prepared:
        return self

    def __exit__(self, *_exc: object) -> None:
        return None

    def background(self, on: bool) -> None:  # noqa: ARG002 - the same call as Qwen's; nothing runs here
        return None

    def synthesize(self, text: str, ref_wav: Path, ref_text: str | None, mode: str) -> bytes:  # noqa: ARG002
        path = self.run / "wav" / f"{line_key(text, ref_wav, mode)}.wav"
        if not path.is_file():
            raise NotRead(f"{path.name}: not read in the remote run {self.run} (run qwen_modal.py again)")
        return path.read_bytes()
