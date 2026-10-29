"""What the tests that follow the pinned Forever build read from this machine: the build the Makefile pins, and the
main checkout's predecessors/ folder (gitignored, so a worktree has none of its own and CI has none at all)."""

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def _pin(var: str, root: Path) -> str | None:
    makefile = (root / "Makefile").read_text(encoding="utf-8")
    m = re.search(rf"^{var}[ \t]*:=[ \t]*(\d[\d.]*)", makefile, re.MULTILINE)
    return m.group(1) if m else None


def forever_build(root: Path = ROOT) -> str:
    build = _pin("forever_BUILD", root)
    assert build, "no `forever_BUILD := <build>` line in the Makefile"
    return build


def forever_quest_build(root: Path = ROOT) -> str:
    """The build whose quest cache data/ holds: `forever_QUEST_BUILD` when the Makefile sets one, else the tables'."""
    return _pin("forever_QUEST_BUILD", root) or forever_build(root)


def predecessors(root: Path = ROOT) -> Path | None:
    """The main checkout's predecessors/, found through the git common dir, or None outside a git checkout."""
    try:
        common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=root,
                                capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    return Path(common).parent / "predecessors"
