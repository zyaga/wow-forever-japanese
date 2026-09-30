"""wfj import draft: machine-drafted text merged into any type's store as `machine` variants; never edits a
hand-written one (ADR-014)."""

from __future__ import annotations

import argparse
import datetime as dt
import json
from collections import Counter
from pathlib import Path
from typing import Any

from wfj.cmd.check import current_baseline, scopes_for
from wfj.cmd.import_predecessor import ja_identity
from wfj.core import decisions, style
from wfj.core.model import FIELDS, HASH_KEYED, entry, validate_line
from wfj.core.status import Scope
from wfj.io.jsonl_store import Store
from wfj.paths import data_root


def read_draft(path: Path) -> list[dict[str, Any]]:
    """Draft rows `{"id", "field", "ja"}` from a JSONL file; any other shape raises (nothing is written)."""
    rows = []
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip():
            continue
        row = json.loads(raw)
        if not isinstance(row, dict) or set(row) != {"id", "field", "ja"}:
            raise ValueError(f"{path.name}:{n}: a draft row is exactly {{id, field, ja}}")
        if not isinstance(row["ja"], str) or not row["ja"].strip():
            raise ValueError(f"{path.name}:{n}: ja must be non-empty text")
        rows.append(row)
    return rows


def merge_draft(
    lines: list[dict[str, Any]], rows: list[dict[str, Any]], prov: dict[str, Any], type_: str
) -> tuple[list[dict[str, Any]], Counter]:
    """Machine drafts into a store (ADR-014). Per (id, field): absent → a new `pending` line; a variant with
    the same text (`ja_identity`) → unchanged; a machine variant from the same draft name → replaced (machine
    replaces machine; a ruling on it is dropped and counted `unruled`, since it judged the old text);
    otherwise → appended as a variant. A `human` / `correction` variant is never edited."""
    by = {(ln["id"], ln["field"]): ln for ln in lines}
    name = str(prov["source"]).split("@", 1)[0]
    c: Counter = Counter()
    seen: set[tuple[Any, str]] = set()
    for row in rows:
        k = (row["id"], row["field"])
        if k in seen:  # a duplicate is reported, never resolved last-wins
            raise ValueError(f"draft: duplicate row {type_} {k[0]}/{k[1]}")
        seen.add(k)
        new = entry(row["id"], row["field"], row["ja"], prov=dict(prov))
        problems = validate_line(type_, new)
        if problems:
            raise ValueError(f"draft: {type_} {k[0]}/{k[1]}: {'; '.join(problems)}")
        if k not in by:
            by[k] = new
            c["added"] += 1
            continue
        line = by[k]
        variants = [line, *line["conflicts"]]
        ident = ja_identity(row["ja"])
        if any(ja_identity(v["ja"]) == ident for v in variants):
            c["unchanged"] += 1
            continue
        same_draft = next(
            (
                v
                for v in variants
                if decisions.is_machine(v["provenance"])
                and str(v["provenance"].get("source", "")).split("@", 1)[0] == name
            ),
            None,
        )
        if same_draft is not None:
            same_draft["ja"] = row["ja"]
            same_draft["provenance"] = dict(prov)
            # A ruling was a person's decision about the OLD text; new text is unreviewed (ADR-014).
            if same_draft.pop("ruling", None) is not None:
                c["unruled"] += 1
            c["replaced"] += 1
            continue
        line["conflicts"].append({"ja": row["ja"], "provenance": dict(prov)})
        c["appended"] += 1
    return list(by.values()), c


# the types a client build rewords, so a machine redraft of a stale line is judged fresh
# (ADR-003). Gossip is keyed by its English hash (a rewording is a new key, never stale); books come from
# VMaNGOS, not the client.
REVERIFY_TYPES = ("ui", "quest", "objective", "area", "item", "spell")


def reverify(
    lines: list[dict[str, Any]], rows: list[dict[str, Any]], scopes: dict[int | str, Scope], type_: str
) -> int:
    """A draft is written against the English the store holds now, so every line the draft names
    (added, replaced or unchanged) records that English as the one it was checked against: `check` then
    judges it fresh instead of keeping a stale line's old hash (ADR-003's audit pass, done by the tool
    rather than a hand edit). The baseline is `check.current_baseline`: the English `check` judges
    the line against, `of` included, so a quest / item / spell field judged against another field is stamped
    exactly as a fresh `check` would. A row with no English to judge it against is refused (nothing is
    written).
    → the number of lines re-stamped"""
    if type_ not in REVERIFY_TYPES:
        raise ValueError(f"draft: --reverify is for {', '.join(REVERIFY_TYPES)} only, not {type_!r}")
    current: dict[tuple[Any, str], dict[str, str] | None] = {}
    for r in rows:
        scope = scopes.get(r["id"])
        base = current_baseline(scope, r["field"]) if scope and not scope.empty else None
        current[(r["id"], r["field"])] = base
    by = {(ln["id"], ln["field"]): ln for ln in lines}
    missing = [k for k, base in current.items() if base is None]
    if missing:
        shown = ", ".join(f"{i}/{f}" for i, f in missing[:10])
        raise ValueError(f"draft: --reverify: no English for {len(missing)} row(s) ({shown})")
    # a hand-written variant was checked by a person against the English it records: re-stamping it would mark
    # that Japanese fresh against new English nobody re-read. The exception: every hand-written variant is
    # ruled `reject`, so none of them can win, and the stamp only judges the machine redraft replacing them
    hand = [k for k in current if k in by and decisions.hand_written_variants(by[k])
            and not decisions.hand_written_all_rejected(by[k])]
    if hand:
        shown = ", ".join(f"{i}/{f}" for i, f in hand[:10])
        raise ValueError(
            f"draft: --reverify: {len(hand)} row(s) have a hand-written variant not ruled reject ({shown})"
        )
    # the stamp says the line was checked against this English, so it must only land
    # where the drafted text is the one that ships. A variant ruled `accept` (a decision on other text) wins
    # over any draft, so a row whose Japanese is not that variant's would re-stamp a line that keeps shipping
    # the old text, unmarked. Move the ruling first, then re-verify.
    drafted = {(r["id"], r["field"]): r["ja"] for r in rows}
    outranked = [
        k for k in current
        if k in by
        and any(
            decisions.is_accepted(v) and v.get("ja") != drafted[k]
            for v in decisions.variant_dicts(by[k])
        )
    ]
    if outranked:
        shown = ", ".join(f"{i}/{f}" for i, f in outranked[:10])
        raise ValueError(
            f"draft: --reverify: {len(outranked)} row(s) lose to a variant ruled accept ({shown})"
        )
    n = 0
    for k, base in current.items():
        if by[k].get("english") != base:
            n += 1
        by[k]["english"] = dict(base)  # type: ignore[arg-type]  # None was refused above
    return n


def run_draft(a: argparse.Namespace) -> int:
    if a.type not in FIELDS:
        raise ValueError(f"draft: unknown type {a.type!r} (one of {', '.join(FIELDS)})")
    if not style.DRAFT_NAME.match(a.name):
        raise ValueError(f"draft: --name must be lowercase letters, digits and dashes, got {a.name!r}")
    date = dt.date.fromisoformat(a.date).isoformat()
    prov: dict[str, Any] = {"class": decisions.MACHINE, "model": a.model}
    if a.critic:
        prov["critic"] = a.critic
    prov["source"] = f"draft-{a.name}@{date}"
    prov["imported"] = date
    rows = read_draft(Path(a.file))
    if a.type not in (*HASH_KEYED, "ui"):
        for row in rows:  # numeric-id types: the JSON id must be an integer, never a numeric string
            if not isinstance(row["id"], int) or isinstance(row["id"], bool):
                raise ValueError(f"draft: {a.type} id {row['id']!r} must be an integer")
    root = data_root()
    styled = style.STYLED_FIELDS.get(a.type, frozenset())
    if any(row["field"] in styled for row in rows):
        # server-only text is drafted under the style guide: the name records its version (ADR-023)
        style.check_name(a.name, style.guide_version(root.parent))
    store = Store(root)
    merged, c = merge_draft(store.load(a.type), rows, prov, a.type)
    if getattr(a, "reverify", False):
        c["reverified"] = reverify(merged, rows, scopes_for(Store(root, english=True), store, a.type), a.type)
    store.save(a.type, merged)
    print(
        f"draft {a.type} ({prov['source']}, model {a.model}, critic {a.critic or '-'}): "
        f"added {c['added']} · unchanged {c['unchanged']} · replaced {c['replaced']} · "
        f"appended {c['appended']}" + (f" · rulings dropped {c['unruled']}" if c["unruled"] else "")
        + (f" · re-verified {c['reverified']}" if getattr(a, "reverify", False) else "")
    )
    return 0
