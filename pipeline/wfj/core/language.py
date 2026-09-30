"""Is this Japanese? Some CJK and no simplified-only character; Latin-only prose is not a translation."""

from __future__ import annotations

import re

KANA = re.compile(r"[぀-ヿ]")
KANJI = re.compile(r"[一-鿿]")
# Characters that exist in simplified Chinese but not in Japanese orthography (from the audit).
# Only characters that do NOT exist in Japanese orthography (着 将 几 么 are Japanese, so they stay out).
SIMPLIFIED_ONLY = set(
    "见说们这务应让还为车东转张书门话讨论请击败经动进发问给两种产业电听战对关样"
    "时长开从过达头图术级队处单实龙灵亚严丽义乐习乡买亲仅价众优传伤侠"
)
PROSE_FIELDS = {"description", "objectives", "completion", "progress", "text"}


def has_simplified(text: str) -> bool:
    return any(c in SIMPLIFIED_ONLY for c in text)


def is_japanese(text: str, field: str) -> bool:
    """Japanese = some CJK (kana or kanji) and no simplified-only character. Prose that is Latin-only is
    not a translation; a Latin-only *title* (a proper noun) renders identically to the English and passes."""
    if not text.strip() or has_simplified(text):
        return False
    if KANA.search(text) or KANJI.search(text):
        return True
    return field not in PROSE_FIELDS
