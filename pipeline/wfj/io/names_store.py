"""`data/name/`: the name lines, sharded by the first two hex characters of the key like gossip
(`name-3f.jsonl`), sorted by key, and the word glossary `data/name/words.jsonl` sorted by word.
Loading and re-saving an unchanged store is a byte no-op."""

from __future__ import annotations

from collections.abc import Iterable
from pathlib import Path
from typing import Any

from wfj.io.jsonl_store import dumps, read_jsonl, shard_name


def name_dir(root: Path) -> Path:
    return root / "name"


def load_lines(root: Path) -> list[dict[str, Any]]:
    out = [ln for path in sorted(name_dir(root).glob("name-*.jsonl")) for ln in read_jsonl(path)]
    return sorted(out, key=lambda ln: str(ln.get("id")) if isinstance(ln, dict) else "")


def _write_if_changed(path: Path, text: str) -> None:
    if not path.is_file() or path.read_text(encoding="utf-8") != text:
        path.write_text(text, encoding="utf-8")


def save_lines(root: Path, lines: Iterable[dict[str, Any]]) -> None:
    """Every shard written from scratch; a shard no line falls in any more is removed. Refuses to empty the
    store, as `Store.save` does: a run that loaded nothing must not wipe it."""
    d = name_dir(root)
    shards: dict[str, list[str]] = {}
    for ln in sorted(lines, key=lambda ln: ln["id"]):
        shards.setdefault(shard_name("name", ln["id"]), []).append(dumps(ln) + "\n")
    if not shards and any(d.glob("name-*.jsonl")):
        raise ValueError("refusing to replace the name store with zero lines")
    d.mkdir(parents=True, exist_ok=True)
    for stale in d.glob("name-*.jsonl"):
        if stale.name not in shards:
            stale.unlink()
    for name, rows in shards.items():
        _write_if_changed(d / name, "".join(rows))


def load_words(root: Path) -> list[dict[str, Any]]:
    return read_jsonl(name_dir(root) / "words.jsonl")


def save_words(root: Path, words: Iterable[dict[str, Any]]) -> None:
    path = name_dir(root) / "words.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    _write_if_changed(
        path, "".join(dumps(w) + "\n" for w in sorted(words, key=lambda w: (w["en"].lower(), w["en"])))
    )
