"""Paragraph breaks and the completeness rule (ADR-011). Pure.

The Japanese corpus never carried a paragraph-break character: WoWJapanizer / CraftJapanizer rows encode a
break as a run of two spaces, QuestJapanizer as four. `normalize_breaks` turns any run of two or more spaces
that follows a sentence terminator into the one canonical encoding, PARA (``\\n\\n``), at import time. The
English side (pfQuest) marks paragraphs with ``$B``; `count_english` reads those from the RAW text (the
normalizer strips them).

`is_truncated` is the rule that keeps a first-paragraph-only translation out of `trusted`: English of two or
more paragraphs, Japanese of one, and the Japanese under TRUNCATED_RATIO of the English length, or, whatever
the paragraphs, a Japanese under TINY_RATIO of the English length (the ``ヒック!`` case). Both constants were
calibrated on the hand-written corpus.
For a layer that is first-paragraph-only by construction (FIRST_PARAGRAPH_ONLY_LAYERS) one Japanese
paragraph against two or more English ones is truncated whatever the ratio: a long first paragraph is still
a first paragraph.
"""

from __future__ import annotations

import re

PARA = "\n\n"
TERMINATORS = "。！？!?」』）)>＞…."  # `>` / `…` / `.` close lines in the corpus too
TRUNCATED_RATIO = 0.22
TINY_RATIO = 0.08
# Provenance layers that are first-paragraph-only BY CONSTRUCTION (the Classic plugin's bulk wiki import kept
# only the text before the first separator, ADR-011): a one-paragraph variant from such a layer against a
# multi-paragraph English is truncated whatever its length. Matched on (source prefix, translator).
FIRST_PARAGRAPH_ONLY_LAYERS: frozenset[tuple[str, str]] = frozenset({("cqjt", "questjapanizer-wiki")})

_BREAK = re.compile(r"(?<=[" + re.escape(TERMINATORS) + r"])[ 　]{2,}(?=\S)")
_ENGLISH_PARA = re.compile(r"(?:\$[bB])+")
# a client template (item / spell tooltip): `$b<k>` is a value (points per combo point), not a break
_CLIENT_PARA = re.compile(r"(?:\$[bB](?!\d))+")
_COLLAPSE = re.compile(r"(?:\n\s*){2,}")


def normalize_breaks(text: str) -> str:
    """Runs of ≥ 2 spaces (ASCII or ideographic) after a sentence terminator become PARA; existing
    newline runs collapse to PARA; other whitespace is untouched."""
    out = _BREAK.sub(PARA, text)
    out = _COLLAPSE.sub(PARA, out)
    return out.strip()


def count(text: str) -> int:
    """Paragraphs in a Japanese value (after normalize_breaks): PARA-separated non-empty runs."""
    return len([p for p in text.split(PARA) if p.strip()]) or (1 if text.strip() else 0)


def count_english(raw_en: str, *, client: bool = False) -> int:
    """Paragraphs in the raw pfQuest English (``$B`` runs separate them). `client` for an item / spell
    template, where a ``$b`` with a digit after it is a value, not a break."""
    splitter = _CLIENT_PARA if client else _ENGLISH_PARA
    return len([p for p in splitter.split(raw_en) if p.strip()]) or (1 if raw_en.strip() else 0)


def first_paragraph_only(provenance: dict) -> bool:
    """True when the variant comes from a layer known to carry only first paragraphs. A `correction` is
    judged by the layer it corrects (`corrects`), so fixing a name never lifts the structural rule."""
    src = str(provenance.get("corrects") or provenance.get("source", "")).split("@", 1)[0]
    return (src, str(provenance.get("translator", ""))) in FIRST_PARAGRAPH_ONLY_LAYERS


def is_truncated(
    ja: str, en_raw: str, en_norm: str, *, structural: bool = False, client: bool = False
) -> tuple[bool, int, int]:
    """→ (truncated?, japanese paragraphs, english paragraphs). `en_norm` is the normalized English the
    checks compare lengths against (markup gone, same footing as `ja`). With `structural` (a variant from a
    FIRST_PARAGRAPH_ONLY layer) one Japanese paragraph against two or more English ones is truncated
    regardless of the length ratio."""
    jp, ep = count(ja), count_english(en_raw, client=client)
    n_ja, n_en = len(ja.strip()), len(en_norm.strip())
    if n_en == 0 or n_ja == 0:
        return False, jp, ep
    ratio = n_ja / n_en
    if ratio < TINY_RATIO:
        return True, jp, ep
    if ep >= 2 and jp == 1 and (structural or ratio < TRUNCATED_RATIO):
        return True, jp, ep
    return False, jp, ep


def completeness(ja: str, en_raw: str, *, client: bool = False) -> int:
    """How many of the English paragraphs the Japanese covers (min of the two counts), the first key of the
    tie-break: a complete variant outranks a partial one from any source."""
    return min(count(ja), count_english(en_raw, client=client))
