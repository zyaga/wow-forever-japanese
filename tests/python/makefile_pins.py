"""The Forever build the Makefile pins, for tests that follow it instead of naming a build themselves."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def forever_build(root: Path = ROOT) -> str:
    makefile = (root / "Makefile").read_text(encoding="utf-8")
    return re.search(r"^forever_BUILD\s*:=\s*(\S+)", makefile, re.MULTILINE).group(1)
