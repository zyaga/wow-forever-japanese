"""WFJ_SHARD=k/n (tests/python/conftest.py): the shares of a split run cover every test once, and a test file
is never split."""

import os
import re
import subprocess
import sys
from pathlib import Path

import pytest

FILES = {
    "test_big.py": "import pytest\n\n@pytest.mark.parametrize('n', range(5))\ndef test_n(n):\n    pass\n",
    "test_mid.py": "def test_a():\n    pass\n\ndef test_b():\n    pass\n",
    "test_small.py": "def test_only():\n    pass\n",
}


def _collected(root: Path, tmp_path: Path, shard: str | None) -> tuple[int, list[str], str]:
    tests = tmp_path / "tests"
    tests.mkdir(exist_ok=True)
    (tests / "conftest.py").write_text((root / "tests/python/conftest.py").read_text(encoding="utf-8"))
    for name, text in FILES.items():
        (tests / name).write_text(text, encoding="utf-8")
    env = {k: v for k, v in os.environ.items() if k != "WFJ_SHARD"} | ({"WFJ_SHARD": shard} if shard else {})
    r = subprocess.run([sys.executable, "-m", "pytest", "--collect-only", "-q", "-p", "no:cacheprovider", "-p",
                        "no:xdist", str(tests)], cwd=tmp_path, env=env, capture_output=True, text=True, check=False)
    return r.returncode, re.findall(r"^\S+\.py::\S+$", r.stdout, re.M), r.stdout + r.stderr


def test_the_shares_cover_every_test_once_and_keep_a_file_whole(root: Path, tmp_path: Path):
    _, everything, _ = _collected(root, tmp_path, None)
    assert len(everything) == 8
    shares = [_collected(root, tmp_path, f"{k}/2")[1] for k in (1, 2)]
    assert sorted(shares[0] + shares[1]) == sorted(everything)
    for share in shares:
        files = {t.split("::")[0] for t in share}
        assert all(t in share for t in everything if t.split("::")[0] in files)
    # dealt out largest first: the two biggest files never land in one share
    big, mid = (next(i for i, s in enumerate(shares) if any(name in t for t in s)) for name in ("test_big", "test_mid"))
    assert big != mid


@pytest.mark.parametrize("shard", ["0/2", "3/2", "x/2", "2", "1/0"])
def test_a_share_outside_the_run_is_refused(root: Path, tmp_path: Path, shard):
    code, _, said = _collected(root, tmp_path, shard)
    assert code != 0
    assert "WFJ_SHARD is k/n" in said
