"""wfj package-check <zip> --version X.Y.Z: the release zip holds exactly the shipped files.

The only folder in the zip is `WoWForeverJapanese/`, and its files are exactly the git-tracked files
under addon/WoWForeverJapanese/ plus LICENSE and ATTRIBUTION.md. The TOC inside the zip carries the
release's version and a CurseForge project id, and never a dependency. A release runs this before
anything is published (docs/operations/release.md).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import zipfile
from collections.abc import Iterable, Sequence
from pathlib import Path, PurePosixPath

from wfj.cmd.release import ReleaseError, version_key
from wfj.cmd.toc_check import parse_toc_text

ADDON = "WoWForeverJapanese"
ADDON_SRC = f"addon/{ADDON}/"
ROOT_FILES = ("LICENSE", "ATTRIBUTION.md")
DEPENDENCY_FIELDS = ("dependencies", "requireddeps", "optionaldeps", "dep")  # compared lower-case


def allowed_files(tracked: Iterable[str]) -> set[str]:
    """Zip paths the package may hold, from the repo's tracked paths. Dotfiles (a `.gitkeep`) never ship:
    the packager leaves them out."""
    tracked = list(tracked)
    for name in ROOT_FILES:
        if f"{ADDON_SRC}{name}" in tracked:  # the packager's move would silently overwrite one with the other
            raise ReleaseError(f"{ADDON_SRC}{name} collides with the root {name} in the package")
    files = {
        f"{ADDON}/{p[len(ADDON_SRC):]}"
        for p in tracked
        if p.startswith(ADDON_SRC) and not any(part.startswith(".") for part in PurePosixPath(p).parts)
    }
    return files | {f"{ADDON}/{name}" for name in ROOT_FILES}


def check(zip_path: Path, version: str, allowed: set[str]) -> list[str]:
    """Problems with the zip (empty = ok)."""
    problems: list[str] = []
    with zipfile.ZipFile(zip_path) as zf:
        names = [n for n in zf.namelist() if not n.endswith("/")]
        tops = sorted({PurePosixPath(n).parts[0] for n in zf.namelist()})
        for top in tops:
            if top != ADDON:
                problems.append(f"top-level entry other than {ADDON}/: {top}")
        present = set(names)
        for name in sorted(present - allowed):
            problems.append(f"not a shipped file: {name}")
        for name in sorted(allowed - present):
            problems.append(f"missing from the zip: {name}")
        toc_name = f"{ADDON}/{ADDON}.toc"
        if toc_name not in present:
            problems.append(f"missing from the zip: {toc_name}")
            return problems
        meta, toc_files = parse_toc_text(zf.read(toc_name).decode("utf-8-sig"))
    for rel in toc_files:
        if f"{ADDON}/{rel}" not in present:
            problems.append(f"the TOC lists a file the zip lacks: {rel}")
    if meta.get("Version") != f"v{version}":
        problems.append(f"## Version is '{meta.get('Version', '')}', expected 'v{version}'")
    project_id = meta.get("X-Curse-Project-ID", "")
    if not (project_id.isascii() and project_id.isdigit()):
        problems.append(f"## X-Curse-Project-ID is '{project_id}': fill in the CurseForge project id")
    for key in meta:
        if key.lower().startswith(DEPENDENCY_FIELDS):
            problems.append(f"## {key}: the addon never depends on another addon")
    return problems


def tracked_files(root: Path) -> list[str]:
    cmd = ["git", "ls-files", "-z", "--", ADDON_SRC, *ROOT_FILES]
    out = subprocess.run(cmd, cwd=root, check=True, capture_output=True, text=True).stdout
    return [p for p in out.split("\0") if p]


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj package-check")
    p.add_argument("zip", type=Path)
    p.add_argument("--version", required=True, help="the release version, without the leading v")
    a = p.parse_args(argv)
    try:
        version_key(a.version)
    except ReleaseError as e:
        print(f"package-check: {e}", file=sys.stderr)
        return 1
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True)
    root = Path(top.stdout.strip())
    try:
        allowed = allowed_files(tracked_files(root))
    except ReleaseError as e:
        print(f"package-check: {e}", file=sys.stderr)
        return 1
    problems = check(a.zip, a.version, allowed)
    for problem in problems:
        print(f"package-check: {problem}", file=sys.stderr)
    if problems:
        return 1
    with zipfile.ZipFile(a.zip) as zf:
        count = sum(1 for n in zf.namelist() if not n.endswith("/"))
    print(f"package-check: ok, {count} files, v{a.version}")
    return 0
