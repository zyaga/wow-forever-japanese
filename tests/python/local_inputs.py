"""Inputs only the maintainer's machine has: the Forever client folder and UI extract under predecessors/, which stay
out of the public repository. They are found the way the Makefile finds them (a worktree reads the main checkout's
predecessors/) at the build the Makefile pins (`forever_BUILD`). CI has none of them, so there a test that needs one
skips; anywhere else a missing input fails, so the machine that can run the test never skips it unseen."""

import os
import re
import subprocess
from pathlib import Path

import pytest


def forever_build(root: Path) -> str:
    """The Forever build the Makefile pins (`forever_BUILD := …`)."""
    m = re.search(r"^forever_BUILD\s*:?=\s*(\S+)", (root / "Makefile").read_text(encoding="utf-8"), re.MULTILINE)
    assert m, "Makefile: no forever_BUILD"
    return m.group(1)


def predecessors(root: Path) -> Path:
    """The checkout's predecessors/, or the main checkout's when this checkout (a worktree) has none."""
    own = root / "predecessors"
    if own.exists():
        return own
    try:
        common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=root,
                                capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return own
    return Path(common).parent / "predecessors"


def forever_ui(root: Path) -> Path:
    """The pinned build's UI extract (`interface/addons`), or `WFJ_FOREVER_UI` when set."""
    if "WFJ_FOREVER_UI" in os.environ:
        return Path(os.environ["WFJ_FOREVER_UI"])
    return predecessors(root) / f"forever-ui-{forever_build(root)}" / "interface" / "addons"


def forever_client(root: Path) -> Path:
    """The pinned build's client folder (table CSVs, quest cache)."""
    return predecessors(root) / "clients" / f"forever-{forever_build(root)}"


def need(path: Path, what: str) -> Path:
    """`path` when it exists. Missing: skip on CI, fail anywhere else with where it was looked for."""
    if path.exists():
        return path
    if os.environ.get("CI"):
        pytest.skip(f"{what}: not on CI")
    pytest.fail(f"{what} is missing at {path}: link predecessors/ into this checkout or the main one "
                f"(docs/operations/local-setup.md), or set the override variable")
