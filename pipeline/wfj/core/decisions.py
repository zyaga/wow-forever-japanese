"""Human decisions that survive regeneration (ADR-012). Pure.

`make data` rebuilds the imported text of data/ from the pinned inputs; that is how pipeline fixes land.
What a person authored is not reproducible from any input, so it is carried across the rebuild instead:

- a **correction**: a variant whose `provenance.class` is `correction` (a hand fix, e.g. a misspelled name);
- a **ruled variant**: any variant carrying a `ruling` (a person picked or excluded it);
- a **machine draft**: a variant whose `provenance.class` is `machine` (ADR-014), drafted by a model
  outside the pinned inputs, so no rebuild can reproduce it.

`carried(lines)` lists them; `cmd/import_predecessor.Collector.carry` puts them back into a rebuilt store.
"""

from __future__ import annotations

import copy
import unicodedata
from typing import Any

from wfj.core import dedupe

CORRECTION = "correction"
MACHINE = "machine"
HAND_WRITTEN = ("human", CORRECTION)


def is_correction(provenance: dict[str, Any]) -> bool:
    return provenance.get("class") == CORRECTION


def is_machine(provenance: dict[str, Any]) -> bool:
    return provenance.get("class") == MACHINE


def is_hand_written(provenance: dict[str, Any]) -> bool:
    """A person wrote it: an imported, named translator (`human`) or a hand fix here (`correction`)."""
    return provenance.get("class") in HAND_WRITTEN


def variant_dicts(line: dict[str, Any]) -> list[dict[str, Any]]:
    """The line's own variant and its `conflicts`, as the stored dicts (edits land in the line)."""
    return [line, *(line.get("conflicts") or [])]


def hand_written_variants(line: dict[str, Any]) -> list[dict[str, Any]]:
    """The line's `human` / `correction` variants, as the stored dicts."""
    return [v for v in variant_dicts(line) if is_hand_written(v["provenance"])]


def is_rejected(variant: dict[str, Any]) -> bool:
    ruling = variant.get("ruling")
    return isinstance(ruling, dict) and ruling.get("ruling") == "reject"


def is_accepted(variant: dict[str, Any]) -> bool:
    """The variant carries `ruling: accept` (it wins over any unruled draft, core/status)."""
    ruling = variant.get("ruling")
    return isinstance(ruling, dict) and ruling.get("ruling") == "accept"


def hand_written_all_rejected(line: dict[str, Any]) -> bool:
    """Every hand-written variant on the line carries `ruling: reject`: the explicit, logged decision a
    machine line needs before it replaces a human translation, written on the text a person set aside rather
    than on the text let in (for example quest completion lines whose only hand-written translations are
    rejected by the rules, so the line ships nothing). False when the line has no hand-written variant at
    all."""
    hand = [c for c in dedupe.variants(line) if is_hand_written(c.provenance)]
    return bool(hand) and all(is_rejected({"ruling": c.ruling}) for c in hand)


def exact(ja: str) -> str:
    """The comparison for corrections: NFC only. Whitespace and paragraph breaks are significant: restoring
    `\n\n` is a real correction (the completeness rule counts paragraphs)."""
    return unicodedata.normalize("NFC", ja)


def carried(lines: list[dict[str, Any]]) -> list[tuple[Any, str, dict[str, Any]]]:
    """Every correction, every machine draft and every ruled variant in `lines`, as (id, field, variant) with
    variant = {ja, provenance[, extra][, ruling]} (deep copies). Sorted canonically (by id, field,
    corrections before ruled imports, `reject` rulings last, source, text), so the carry order never depends
    on where a previous `check` promoted a variant, a rejected variant never becomes a line ahead of the
    variants it was rejected against, and a rebuild is byte-stable."""
    out: list[tuple[Any, str, dict[str, Any]]] = []
    for line in lines:
        for c in dedupe.variants(line):
            if not (is_correction(c.provenance) or is_machine(c.provenance) or c.ruling):
                continue
            v: dict[str, Any] = {"ja": c.ja, "provenance": copy.deepcopy(c.provenance)}
            if c.extra:
                v["extra"] = copy.deepcopy(c.extra)
            if c.ruling:
                v["ruling"] = copy.deepcopy(c.ruling)
            out.append((line["id"], line["field"], v))

    def key(item: tuple[Any, str, dict[str, Any]]) -> tuple:
        id_, field, v = item
        correction_first = 0 if is_correction(v["provenance"]) else 1
        reject_last = 1 if is_rejected(v) else 0
        source = str(v["provenance"].get("source", ""))
        return (str(id_).zfill(12), field, correction_first, reject_last, source, v["ja"])

    return sorted(out, key=key)
