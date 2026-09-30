"""wfj toc-check <addon.toc> <clients.toml>: the TOC's ## Interface must equal [forever].interface.

Also asserts the fields every build needs (## Version, ## SavedVariables) and warns while
## X-Curse-Project-ID is empty (filling it in is a manual step; empty is a warning, not a failure).
"""

from __future__ import annotations

import sys
import tomllib
from collections.abc import Sequence
from pathlib import Path

REQUIRED = ("Interface", "Title", "Version", "SavedVariables")


def parse_toc(path: Path) -> tuple[dict[str, str], list[str]]:
    return parse_toc_text(path.read_text(encoding="utf-8-sig"))


def parse_toc_text(text: str) -> tuple[dict[str, str], list[str]]:
    """The TOC's `## Key: value` fields and its file list (forward slashes), comments skipped."""
    meta: dict[str, str] = {}
    files: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("##"):
            k, _, v = line[2:].partition(":")
            meta[k.strip()] = v.strip()
        elif not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return meta, files


def check(toc_path: Path, clients_path: Path) -> list[str]:
    """Return a list of problems (empty = ok). Warnings are printed, not returned."""
    meta, _ = parse_toc(toc_path)
    clients = tomllib.loads(clients_path.read_text(encoding="utf-8"))
    problems = [f"missing ## {k}" for k in REQUIRED if not meta.get(k)]
    expected = str(clients["forever"]["interface"])
    if meta.get("Interface") and meta["Interface"] != expected:
        problems.append(
            f"## Interface is {meta['Interface']}, clients.toml [forever].interface is {expected}"
        )
    if not meta.get("X-Curse-Project-ID"):
        print("toc-check: warning: ## X-Curse-Project-ID is empty (manual)", file=sys.stderr)
    return problems


def run(argv: Sequence[str]) -> int:
    if len(argv) != 2:
        print("usage: wfj toc-check <addon.toc> <clients.toml>", file=sys.stderr)
        return 1
    problems = check(Path(argv[0]), Path(argv[1]))
    for p in problems:
        print(f"toc-check: {p}", file=sys.stderr)
    if problems:
        return 1
    print("toc-check: ok")
    return 0
