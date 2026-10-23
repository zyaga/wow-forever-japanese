"""What the tests that follow the pinned Forever build read from this machine: the build the Makefile pins, and the
main checkout's predecessors/ folder (gitignored, so a worktree has none of its own and CI has none at all)."""

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def forever_build(root: Path = ROOT) -> str:
    makefile = (root / "Makefile").read_text(encoding="utf-8")
    m = re.search(r"^forever_BUILD\s*:=\s*(\S+)", makefile, re.MULTILINE)
    assert m, "no `forever_BUILD := <build>` line in the Makefile"
    return m.group(1)


def predecessors(root: Path = ROOT) -> Path | None:
    """The main checkout's predecessors/, found through the git common dir, or None outside a git checkout."""
    try:
        common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=root,
                                capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    return Path(common).parent / "predecessors"
