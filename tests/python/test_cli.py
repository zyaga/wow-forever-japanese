import subprocess
import sys

from wfj.cli import VERBS, main


def test_help_lists_every_verb(root):
    out = subprocess.run(
        [sys.executable, "-m", "wfj", "--help"],
        cwd=root / "pipeline",
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    for verb in ("import", "check", "generate", "validate", "stats", "toc-check"):
        assert verb in out


def test_every_verb_has_a_handler():
    assert all(callable(handler) for _, handler in VERBS.values())


def test_no_verb_prints_help_and_exits_0(capsys):
    assert main([]) == 0
    assert "toc-check" in capsys.readouterr().out
