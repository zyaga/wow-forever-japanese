"""The private rules of `wfj public-check`: where the file is, and reading it.

The file is kept outside the repository, so the repository does not publish what the check looks for. It is
found through $WFJ_PRIVATE_RULES, or as `info/public-check-private.json` in the repository's git folder (the
folder git never publishes, shared by every worktree). A checkout without one runs the public rules only.
"""

from __future__ import annotations

import json
import os
import subprocess
from functools import cache
from pathlib import Path

from wfj.core.public_text import NO_PRIVATE_RULES, PrivateRules, private_rules

ENV = "WFJ_PRIVATE_RULES"
NAME = "public-check-private.json"


def git_info_dir(repo: Path) -> Path | None:
    """`info/` of the git folder every worktree of `repo` shares; None outside a git repository."""
    done = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "--git-common-dir"], capture_output=True, check=False
    )
    if done.returncode != 0:
        return None
    common = Path(done.stdout.decode("utf-8", errors="replace").strip())
    return (common if common.is_absolute() else Path(repo) / common) / "info"


def rules_path(repo: Path) -> Path | None:
    """Where the private rules are expected for `repo`: $WFJ_PRIVATE_RULES when set, else the git folder."""
    named = os.environ.get(ENV, "")
    if named:
        return Path(named)
    info = git_info_dir(repo)
    return info / NAME if info else None


@cache
def _read(path: Path, _mtime: float) -> PrivateRules:
    try:
        return private_rules(json.loads(path.read_text(encoding="utf-8")))
    except (ValueError, TypeError, AttributeError) as e:
        raise SystemExit(f"public-check: the private rules file {path} cannot be read: {e}") from e


def load(repo: Path) -> PrivateRules:
    """The private rules for `repo`, or no rules when there is no file. A file that cannot be read stops the
    run: a broken rules file must never pass as "nothing found"."""
    path = rules_path(repo)
    if path is None or not path.is_file():
        return NO_PRIVATE_RULES
    return _read(path, path.stat().st_mtime)
