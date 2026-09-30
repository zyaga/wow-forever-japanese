"""Repo paths shared by the commands."""

from __future__ import annotations

from pathlib import Path


def data_root(start: Path | None = None) -> Path:
    """Repo `data/` directory: walk up from cwd until a dir containing `data/SCHEMA`."""
    p = (start or Path.cwd()).resolve()
    for cand in (p, *p.parents):
        if (cand / "data" / "SCHEMA").is_file():
            return cand / "data"
    raise SystemExit("wfj: cannot find data/SCHEMA above the current directory")


def allowlist_path(root: Path) -> Path:
    return root.parent / "pipeline" / "allowlist.txt"
