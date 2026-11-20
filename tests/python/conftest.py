import fcntl
import json
import os
import pickle
import re
import subprocess
import sys
from collections import Counter
from collections.abc import Callable
from pathlib import Path
from typing import TypeVar

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "pipeline"))

T = TypeVar("T")


def shared(folder: Path, name: str, produce: Callable[[], T]) -> T:
    """`produce()`, computed once per test run. The tests run in parallel worker processes (pytest-xdist) and a
    session fixture is per process, so a whole-store result would be computed again in every worker. The first
    worker computes it under a lock in `folder`, the run's temp folder every worker shares, and the others read
    it from there. Outside a parallel run it is simply computed."""
    if os.environ.get("PYTEST_XDIST_WORKER") is None:
        return produce()
    path = folder / f"{name}.pickle"
    with (folder / f"{name}.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)  # held until the file closes: the others wait for the first result
        if path.exists():
            return pickle.loads(path.read_bytes())
        value = produce()
        path.write_bytes(pickle.dumps(value, protocol=pickle.HIGHEST_PROTOCOL))
        return value


@pytest.fixture(scope="session")
def run_folder(tmp_path_factory) -> Path:
    """The temp folder all the workers of one run share."""
    return tmp_path_factory.getbasetemp().parent


def pytest_collection_modifyitems(config, items):
    """WFJ_SHARD=k/n keeps the k-th of n shares of the test files, so n runs with k = 1..n cover every test once
    and the suite can be spread over n machines. Files are dealt out by how many tests they hold, largest
    first, so no share gets all the big files. A file is never split: its module fixtures run once."""
    shard = os.environ.get("WFJ_SHARD")
    if not shard:
        return
    match = re.fullmatch(r"(\d+)/(\d+)", shard)
    k, n = (int(part) for part in match.groups()) if match else (0, 0)
    if not 1 <= k <= n:
        raise pytest.UsageError(f"WFJ_SHARD is k/n with 1 <= k <= n, got {shard}")
    files = [item.nodeid.split("::", 1)[0] for item in items]
    counts = Counter(files)
    order = sorted(counts, key=lambda f: (-counts[f], f))
    mine = {f for i, f in enumerate(order) if i % n == k - 1}
    kept = [item for item, f in zip(items, files, strict=True) if f in mine]
    dropped = [item for item, f in zip(items, files, strict=True) if f not in mine]
    if dropped:
        config.hook.pytest_deselected(items=dropped)
        items[:] = kept


@pytest.fixture(scope="session")
def root() -> Path:
    return ROOT


@pytest.fixture(scope="session")
def vectors(root: Path) -> list[dict]:
    with (root / "vectors" / "hash_vectors.jsonl").open(encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


@pytest.fixture(scope="session")
def plan_report(root: Path, run_folder: Path) -> tuple[dict[str, str], dict]:
    """The committed store's plan and its report, computed once per run: planning the whole store takes
    seconds, and every test that needs it asserts on the same committed data. Tests read the plan; the ones
    that write apply it to a copy of the addon folder."""
    from wfj.cmd import generate
    from wfj.io.jsonl_store import Store

    def produce() -> tuple[dict[str, str], dict]:
        report: dict = {}
        planned = generate.plan(Store(root / "data"), generate.vectors_rows(root / "data"), report)
        return planned, report

    return shared(run_folder, "plan_report", produce)


@pytest.fixture(scope="session")
def store_coverage(root: Path, run_folder: Path) -> dict:
    """`wfj.dev.coverage.measure` of the committed store, computed once per run."""
    from wfj.dev import coverage

    return shared(run_folder, "store_coverage", lambda: coverage.measure(root / "data"))


@pytest.fixture(scope="session")
def planned(plan_report) -> dict[str, str]:
    return plan_report[0]


def make_vmangos_db(
    path: Path, quests=(), npc_texts=(), broadcasts=(), options=(), greetings=(), pages=()
) -> Path:
    """A minimal VMaNGOS world database: only the tables and columns `io/vmangos` reads.
    quests: (entry, patch, RequestItemsText, OfferRewardText); npc_texts: (ID, [BroadcastTextID0..]);
    broadcasts: (entry, male_text, female_text); options: option_text; greetings: content_default.
    pages: (entry, text, next_page)."""
    import sqlite3

    db = sqlite3.connect(path)
    db.execute("CREATE TABLE quest_template (entry INT, patch INT, Title TEXT, RequestItemsText TEXT, OfferRewardText TEXT)")
    db.execute("CREATE TABLE npc_text (ID INT, " + ", ".join(f"BroadcastTextID{i} INT" for i in range(8)) + ")")
    db.execute("CREATE TABLE broadcast_text (entry INT, male_text TEXT, female_text TEXT)")
    db.execute("CREATE TABLE gossip_menu_option (menu_id INT, option_text TEXT)")
    db.execute("CREATE TABLE quest_greeting (entry INT, content_default TEXT)")
    db.execute("CREATE TABLE page_text (entry INT, text TEXT, next_page INT)")
    db.executemany("INSERT INTO page_text VALUES (?, ?, ?)", pages)
    db.executemany("INSERT INTO quest_template VALUES (?, ?, '', ?, ?)", quests)
    for id_, slots in npc_texts:
        db.execute("INSERT INTO npc_text VALUES (?" + ", ?" * 8 + ")", (id_, *(list(slots) + [0] * 8)[:8]))
    db.executemany("INSERT INTO broadcast_text VALUES (?, ?, ?)", broadcasts)
    db.executemany("INSERT INTO gossip_menu_option VALUES (1, ?)", [(o,) for o in options])
    db.executemany("INSERT INTO quest_greeting VALUES (1, ?)", [(g,) for g in greetings])
    db.commit()
    db.close()
    return path


@pytest.fixture
def vmangos_db(tmp_path: Path):
    return lambda name="mangos.sqlite", **kw: make_vmangos_db(tmp_path / name, **kw)


# ── a git repo for the commands that read one ─────────────────────────────────


def git(repo: Path, *args: str) -> str:
    """Run git in `repo` with a fixed identity and return its output."""
    return subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args], cwd=repo, check=True, capture_output=True, text=True
    ).stdout


@pytest.fixture(name="git")
def git_fixture():
    return git


@pytest.fixture
def git_repo(tmp_path, monkeypatch):
    """A fresh repo on `main` in tmp_path, the given files committed, the given tags set, and the cwd there.
    Returns a maker: `git_repo({"CHANGELOG.md": text}, tags=["v0.8.0"])`."""

    def make(files: dict[str, str], tags=()) -> Path:
        git(tmp_path, "init", "-q", "-b", "main")
        for name, text in files.items():
            path = tmp_path / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        git(tmp_path, "add", ".")
        git(tmp_path, "commit", "-qm", "init")
        for tag in tags:
            git(tmp_path, "tag", tag)
        monkeypatch.chdir(tmp_path)
        return tmp_path

    return make
