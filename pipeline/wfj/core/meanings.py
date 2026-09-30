"""A word card's meaning never carries its line's whole English.

The addon ships Japanese plus short English meanings for single words; it never ships a whole line of the
game's English text. A meaning "copies" the line when, compared word by word with case, punctuation and game
tokens ignored, it holds the whole English line of two or more words: as a whole, without its parentheses,
inside parentheses or quotes, or (for three or more words) as a run of words. A one-word UI label may take the
game's own word, since the label is that word.
"""

from __future__ import annotations

import re

TOKEN = re.compile(r"\$[A-Za-z]\d*|%\d*\$?[sd]|\{[a-z]+\}")
BARE = re.compile(r"\$[A-Za-z]\d*|%\d*\$?[sd]|\{[a-z]+\}|[\x00-\x7f]|[、。！？：；「」『』（）・…―ー\s]")


def one_word_label(row: dict) -> bool:
    """A UI row whose Japanese, stripped of placeholders, punctuation and ASCII, is its one listed word."""
    return (
        row["type"] == "ui"
        and len(row["words"]) == 1
        and BARE.sub("", row["ja"]) == BARE.sub("", row["words"][0][0])
    )


def words(s: str) -> list[str]:
    """Lower-cased words of `s`, game tokens and punctuation dropped (an apostrophe joins: don't → dont)."""
    s = TOKEN.sub(" ", s.lower()).replace("'", "").replace("’", "")
    return re.findall(r"[a-z0-9]+", s)


def copies(meaning: str, en: str) -> bool:
    """True when `meaning` carries the whole English line `en` (two or more words)."""
    ew = words(en)
    if len(ew) < 2:
        return False
    parts = [meaning, re.sub(r"\([^)]*\)", " ", meaning)]
    parts += re.findall(r"\(([^)]*)\)", meaning)
    parts += re.findall(r"[\"“]([^\"”]*)[\"”]", meaning)
    if any(words(p) == ew for p in parts):
        return True
    mw = words(meaning)
    if len(ew) >= 3:
        return any(mw[i : i + len(ew)] == ew for i in range(len(mw) - len(ew) + 1))
    return False
