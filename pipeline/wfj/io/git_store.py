"""`data/english/<type>` as it was at a git ref (for `stats --delta`). Read-only; the git repo is the
database (ADR-006)."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any


def _git(repo: Path, *args: str) -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(repo), *args], capture_output=True, encoding="utf-8", check=True
        ).stdout
    except FileNotFoundError as e:
        raise ValueError("git is not available") from e
    except subprocess.CalledProcessError as e:
        raise ValueError(f"git {' '.join(args)}: {(e.stderr or '').strip() or e}") from e


def load_english_at(repo: Path, ref: str, types: tuple[str, ...]) -> dict[str, list[dict[str, Any]]]:
    """{type: English lines} at REF for each type (a type with no shards there is an empty list). An unknown
    ref raises ValueError before anything is read."""
    return load_lines_at(repo, ref, types, english=True)


def load_lines_at(
    repo: Path, ref: str, types: tuple[str, ...], *, english: bool
) -> dict[str, list[dict[str, Any]]]:
    """{type: lines} at REF from `data/english/<type>/` (english) or `data/<type>/` (the translation
    lines, for the status shift)."""
    if ref.startswith("-"):
        raise ValueError(f"not a git ref: {ref!r}")
    try:
        _git(repo, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    except ValueError as e:
        raise ValueError(f"unknown git ref {ref!r}") from e
    out: dict[str, list[dict[str, Any]]] = {}
    for type_ in types:
        folder = f"data/english/{type_}/" if english else f"data/{type_}/"
        tree = _git(repo, "ls-tree", "-r", "-z", "--name-only", ref, "--", folder)
        listing = tree.split("\0")
        lines: list[dict[str, Any]] = []
        for path in sorted(p for p in listing if p.endswith(".jsonl")):
            blob = _git(repo, "show", f"{ref}:{path}")
            lines.extend(json.loads(raw) for raw in blob.splitlines() if raw.strip())
        out[type_] = lines
    return out
