"""`wfj voice generate` starts the AivisSpeech Engine when it has work and none answers, and stops what it
started however the run ends; an engine someone else started is used and left alone."""

from __future__ import annotations

import os
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

import pytest
from test_voice import CFG, _fake_encode, _store

from wfj.cmd import voice_make
from wfj.io import aivis
from wfj.io.aivis import Engine, EngineError

FAKE = Path(__file__).with_name("fake_aivis.py")


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def _gone(pid: int, within: float = 5.0) -> bool:
    end = time.time() + within
    while time.time() < end:
        if not _alive(pid):
            return True
        time.sleep(0.05)
    return False


class FakeRun:
    """An executable `run` that starts the fake engine; `pid` is the engine's once it has started."""

    def __init__(self, tmp_path: Path, mode: str = "serve", name: str = "run"):
        self.path = tmp_path / name
        self.pidfile = tmp_path / f"{name}.pid"
        self.path.write_text(
            f'#!/bin/sh\nFAKE_AIVIS_PIDFILE="{self.pidfile}" FAKE_AIVIS_MODE={mode} exec "{sys.executable}" "{FAKE}" "$@"\n'
        )
        self.path.chmod(0o755)

    @property
    def started(self) -> bool:
        return self.pidfile.is_file()

    @property
    def pid(self) -> int:
        return int(self.pidfile.read_text())


@pytest.fixture
def url():
    return f"http://127.0.0.1:{_free_port()}"


@pytest.fixture
def reap():
    pids: list[int] = []
    yield pids
    for pid in pids:
        if _alive(pid):
            os.kill(pid, signal.SIGKILL)


def _generate(data, store, url, run, encode=_fake_encode):
    return voice_make.generate(data, "all", CFG, store, Engine(url), encode, log=lambda *_: None, engine_run=run)


def test_work_and_no_engine_starts_it_makes_the_files_and_stops_it(tmp_path, url, reap):
    data = _store(tmp_path)
    run = FakeRun(tmp_path)
    r = _generate(data, tmp_path / "voice", url, run.path)
    reap.append(run.pid)
    assert r["made"] == 3
    assert _gone(run.pid)


def test_a_failure_mid_run_still_stops_the_engine(tmp_path, url, reap):
    data = _store(tmp_path)
    run = FakeRun(tmp_path)

    def broken(wav, out):
        raise RuntimeError("encoder broke")

    with pytest.raises(RuntimeError, match="encoder broke"):
        _generate(data, tmp_path / "voice", url, run.path, encode=broken)
    reap.append(run.pid)
    assert _gone(run.pid)


@pytest.mark.parametrize("sig", [signal.SIGTERM, signal.SIGHUP])
def test_a_stop_signal_to_the_run_stops_the_engine(tmp_path, url, reap, sig):
    run = FakeRun(tmp_path)
    code = (
        "import sys, time\nfrom pathlib import Path\nfrom wfj.io.aivis import Engine, running\n"
        f"with running(Engine({url!r}), Path({str(run.path)!r}), log=lambda *_: None):\n"
        "    print('up', flush=True)\n    time.sleep(60)\n"
    )
    child = subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.PIPE, text=True)
    try:
        assert child.stdout.readline().strip() == "up"
        reap.append(run.pid)
        child.send_signal(sig)
        child.wait(timeout=20)
    finally:
        if child.poll() is None:
            child.kill()
    assert _gone(run.pid)


def test_a_hangup_the_run_ignores_stays_ignored(tmp_path, url, reap):
    run = FakeRun(tmp_path)
    code = (
        "import signal, time\nfrom pathlib import Path\nfrom wfj.io.aivis import Engine, running\n"
        "signal.signal(signal.SIGHUP, signal.SIG_IGN)\n"
        f"with running(Engine({url!r}), Path({str(run.path)!r}), log=lambda *_: None):\n"
        "    print('up', flush=True)\n    time.sleep(60)\n"
    )
    child = subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.PIPE, text=True)
    try:
        assert child.stdout.readline().strip() == "up"
        reap.append(run.pid)
        child.send_signal(signal.SIGHUP)  # under nohup: the run goes on
        time.sleep(0.5)
        assert child.poll() is None
        assert _alive(run.pid)
        child.send_signal(signal.SIGTERM)
        child.wait(timeout=20)
    finally:
        if child.poll() is None:
            child.kill()
    assert _gone(run.pid)


def test_an_engine_already_answering_is_used_and_left_running(tmp_path, url, reap):
    data = _store(tmp_path)
    mine = FakeRun(tmp_path, name="mine")
    port = url.rsplit(":", 1)[1]
    subprocess.Popen([str(mine.path), "--host", "127.0.0.1", "--port", port])
    end = time.time() + 10
    while not mine.started and time.time() < end:
        time.sleep(0.05)
    reap.append(mine.pid)
    run = FakeRun(tmp_path)
    r = _generate(data, tmp_path / "voice", url, run.path)
    assert r["made"] == 3
    assert not run.started  # nothing launched
    assert _alive(mine.pid)


def test_nothing_to_make_starts_no_engine(tmp_path, url, reap):
    data = _store(tmp_path)
    first = FakeRun(tmp_path, name="first")
    _generate(data, tmp_path / "voice", url, first.path)
    reap.append(first.pid)
    assert _gone(first.pid)
    run = FakeRun(tmp_path)
    r = _generate(data, tmp_path / "voice", url, run.path)
    assert r["made"] == 0
    assert not run.started


def test_an_engine_that_exits_before_answering_fails_the_run_naming_it(tmp_path, url):
    run = FakeRun(tmp_path, mode="exit")
    with pytest.raises(EngineError, match=str(run.path)), aivis.running(Engine(url), run.path, log=lambda *_: None):
        pass


def test_an_engine_that_never_answers_fails_the_run_and_is_stopped(tmp_path, url, reap):
    run = FakeRun(tmp_path, mode="silent")
    with (
        pytest.raises(EngineError, match=str(run.path)),
        aivis.running(Engine(url), run.path, wait=0.5, log=lambda *_: None),
    ):
        pass
    reap.append(run.pid)
    assert _gone(run.pid)


def test_no_engine_to_start_keeps_the_refusal_saying_how_to_start_it(tmp_path, url):
    data = _store(tmp_path)
    with pytest.raises(EngineError, match=r"3 file\(s\) to make.*AivisSpeech Engine"):
        _generate(data, tmp_path / "voice", url, tmp_path / "missing" / "run")


def test_the_engine_is_the_main_checkouts_unless_given(tmp_path, monkeypatch):
    assert voice_make.engine_run_path("x") == Path("x")
    repo = tmp_path / "repo"
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    monkeypatch.chdir(repo)
    assert voice_make.engine_run_path(None) == repo.resolve() / "build" / "aivis" / "macOS-arm64" / "run"


def test_the_command_passes_the_engine_path_to_generate(tmp_path, monkeypatch):
    seen = {}

    def fake_generate(*args, **kw):
        seen.update(kw)
        return {"made": 0, "files": 0, "chars_made": 0, "seconds_made": 0.0, "elapsed": 0.0, "audio": {}}

    monkeypatch.setattr(voice_make, "generate", fake_generate)
    monkeypatch.setattr(voice_make, "load_config", lambda _: CFG | {"engine": "http://127.0.0.1:9"})
    _store(tmp_path)
    monkeypatch.chdir(tmp_path)
    voice_make.run(["generate", "--store", str(tmp_path / "voice"), "--engine-run", str(tmp_path / "e")])
    assert seen["engine_run"] == tmp_path / "e"
