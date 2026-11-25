"""Builds the add-on file Anki installs: a zip of the add-on's folder, its files at the top, as AnkiWeb asks.

    python anki-addon/tools/package.py <out file> --version <x.y.z>

Only the files the add-on runs are packed, with the repository's licence beside them; the version is written
into the manifest.
"""

from __future__ import annotations

import argparse
import json
import zipfile
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "wfj_anki"
LICENSE = Path(__file__).resolve().parents[2] / "LICENSE"
PACKED = {".py", ".json", ".md", ".html", ".css"}
VERSION_MARK = "@project-version@"


def files() -> list[Path]:
    return sorted(
        p
        for p in SOURCE.rglob("*")
        if p.is_file() and p.suffix in PACKED and "__pycache__" not in p.parts and p.name != "meta.json"
    )


def build(out: Path, version: str) -> list[str]:
    out.parent.mkdir(parents=True, exist_ok=True)
    names = []
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in [LICENSE, *files()]:
            name = "LICENSE" if path == LICENSE else path.relative_to(SOURCE).as_posix()
            data = path.read_bytes()
            if name == "manifest.json":
                manifest = json.loads(data.decode("utf-8").replace(VERSION_MARK, version))
                data = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
            # a fixed time, so the same tree always gives the same file
            archive.writestr(
                zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0)), data, zipfile.ZIP_DEFLATED
            )
            names.append(name)
    return names


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("out", type=Path)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    names = build(args.out, args.version)
    print(f"{args.out}: {len(names)} files, version {args.version}")


if __name__ == "__main__":
    main()
