"""`data/name/`: the name lines, sharded by the first two hex characters of the key like gossip
(`name-3f.jsonl`), sorted by key, and the word glossary `data/name/words.jsonl` sorted by word.
Loading and re-saving an unchanged store is a byte no-op."""

from __future__ import annotations

import json
from collections.abc import Iterable
from pathlib import Path
from typing import Any

from wfj.io.jsonl_store import dumps


def name_dir(root: Path) -> Path:
    return root / "name"


def _read(path: Path) -> list[dict[str, Any]]:
    with path.open(encoding="utf-8") as f:
        return [json.loads(raw) for raw in f if raw.strip()]


def load_lines(root: Path) -> list[dict[str, Any]]:
    d = name_dir(root)
    out: list[dict[str, Any]] = []
    for path in sorted(d.glob("name-*.jsonl")) if d.is_dir() else ():
        out.extend(_read(path))
    return sorted(out, key=lambda ln: ln["id"])


def save_lines(root: Path, lines: Iterable[dict[str, Any]]) -> None:
    d = name_dir(root)
    d.mkdir(parents=True, exist_ok=True)
    shards: dict[str, list[str]] = {}
    for ln in sorted(lines, key=lambda ln: ln["id"]):
        shards.setdefault(f"name-{ln['id'][:2]}.jsonl", []).append(dumps(ln) + "\n")
    for stale in d.glob("name-*.jsonl"):
        if stale.name not in shards:
            stale.unlink()
    for name, rows in shards.items():
        text = "".join(rows)
        path = d / name
        if not path.is_file() or path.read_text(encoding="utf-8") != text:
            path.write_text(text, encoding="utf-8")


def load_words(root: Path) -> list[dict[str, Any]]:
    path = name_dir(root) / "words.jsonl"
    return _read(path) if path.is_file() else []


def save_words(root: Path, words: Iterable[dict[str, Any]]) -> None:
    path = name_dir(root) / "words.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    text = "".join(dumps(w) + "\n" for w in sorted(words, key=lambda w: (w["en"].lower(), w["en"])))
    if not path.is_file() or path.read_text(encoding="utf-8") != text:
        path.write_text(text, encoding="utf-8")
