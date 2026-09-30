"""JSONL shard store for `data/`: one object per line, 1,000-id shards, deterministic.

Layout: <root>/<type>/<type>-NNNN.jsonl (NNNN = id // 1000, zero-padded 4) for numeric ids;
gossip shards by the first two hex chars of the key; ui by the key's first character, upper-cased.
English lines live under <root>/english/<type>/.
Lines are sorted by (id, field order). Loading and re-saving an unchanged store is a byte no-op.
"""

from __future__ import annotations

import json
from collections.abc import Iterable
from pathlib import Path
from typing import Any

from wfj.core.model import SHARD_WIDTH, field_index

SHARD = SHARD_WIDTH


def shard_name(type_: str, id_: int | str) -> str:
    if type_ == "ui":  # UI string key: first character, upper-cased (no case-only twins on macOS)
        return f"{type_}-{str(id_)[:1].upper()}.jsonl"
    if isinstance(id_, str):  # gossip key
        return f"{type_}-{id_[:2]}.jsonl"
    return f"{type_}-{id_ // SHARD:04d}.jsonl"


def _sort_key(type_: str, english: bool):
    def key(line: dict[str, Any]):
        id_ = line["id"]
        return (
            (0, id_) if isinstance(id_, int) else (1, id_),
            field_index(type_, line["field"], english=english),
        )

    return key


def dumps(line: dict[str, Any]) -> str:
    return json.dumps(line, ensure_ascii=False, separators=(", ", ": "))


class Store:
    def __init__(self, root: Path, *, english: bool = False):
        self.root = Path(root) / "english" if english else Path(root)
        self.english = english

    def dir(self, type_: str) -> Path:
        return self.root / type_

    def load(self, type_: str) -> list[dict[str, Any]]:
        d = self.dir(type_)
        lines: list[dict[str, Any]] = []
        if not d.is_dir():
            return lines
        for path in sorted(d.glob(f"{type_}-*.jsonl")):
            with path.open(encoding="utf-8") as f:
                lines.extend(json.loads(raw) for raw in f if raw.strip())
        lines.sort(key=_sort_key(type_, self.english))
        return lines

    def save(
        self, type_: str, lines: Iterable[dict[str, Any]], *, allow_empty: bool = False
    ) -> dict[str, int]:
        """Write all shards for `type_` from scratch (removing stale shards). Returns lines per shard.

        Refuses to replace existing shards with nothing unless `allow_empty`; an empty import
        (wrong column, empty source table) must not silently wipe a type.
        """
        d = self.dir(type_)
        d.mkdir(parents=True, exist_ok=True)
        by_shard: dict[str, list[dict[str, Any]]] = {}
        for line in sorted(lines, key=_sort_key(type_, self.english)):
            by_shard.setdefault(shard_name(type_, line["id"]), []).append(line)
        if not by_shard and not allow_empty and any(d.glob(f"{type_}-*.jsonl")):
            raise ValueError(
                f"refusing to replace existing {type_} shards with zero lines (pass allow_empty)"
            )
        for stale in d.glob(f"{type_}-*.jsonl"):
            if stale.name not in by_shard:
                stale.unlink()
        counts: dict[str, int] = {}
        for name, shard_lines in sorted(by_shard.items()):
            text = "".join(dumps(line) + "\n" for line in shard_lines)
            path = d / name
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                path.write_text(text, encoding="utf-8")
            counts[name] = len(shard_lines)
        return counts
