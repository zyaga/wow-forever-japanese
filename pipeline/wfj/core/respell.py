"""A name's Japanese spelled from its English. Every word has one katakana spelling, and a name is put
together from the spellings of its words, so the voice says what the screen shows and a word is written one
way everywhere.

    "Black Dragonflight" → ブラック・ドラゴンフライト      "Hallow's End" → ハロウズ・エンド
    "The Argent Dawn"    → アージェント・ドーン            "Head Shot II" → ヘッド・ショット2

A leading "The" is left out. A possessive keeps its sound (ズ). A digit run stays as digits and a roman
numeral becomes one; both are read as Japanese numbers. A single letter is read by its name (2P → 2ピー). A
tag in brackets is a note to the game's makers and is left out. `&` is アンド, `%` パーセント, `+` is read
ぷらす; a colon and brackets are kept in their full-width form; a slash and a hyphen only separate words.
Pure: no disk.
"""

from __future__ import annotations

import re
from collections.abc import Callable

from wfj.core import kana, names

_TAG = re.compile(r"\[[^\]]*\]|<[^>]*>")
_PIECE = re.compile(r"[^\W\d_](?:[^\W\d_]|['’])*|[0-9]+(?:[.,][0-9]+)*|\S")  # a word: letters of any script
_ROMAN = re.compile(r"^(?=[IVX])X{0,3}(IX|IV|V?I{0,3})$")
_ROMAN_VALUE = {"I": 1, "V": 5, "X": 10}
_LETTER_NAMES = (
    "エー ビー シー ディー イー エフ ジー エイチ アイ ジェー ケー エル エム "
    "エヌ オー ピー キュー アール エス ティー ユー ブイ ダブリュー エックス ワイ ゼット"
)
_LETTER = dict(zip("abcdefghijklmnopqrstuvwxyz", _LETTER_NAMES.split(), strict=True))
_WORD_FOR = {"&": "アンド", "%": "パーセント"}
_KEPT = {":": "：", "(": "（", ")": "）", "!": "！", "?": "？", ",": "、"}
_OPENS = "：（、"  # no dot is written after these, nor before a closing bracket


def _roman(piece: str) -> int | None:
    if not _ROMAN.match(piece):
        return None
    total = 0
    for c, nxt in zip(piece, piece[1:] + " ", strict=True):
        v = _ROMAN_VALUE[c]
        total += -v if _ROMAN_VALUE.get(nxt, 0) > v else v
    return total


def _number_reading(digits: str) -> str:
    """12 → じゅうに; 1,200 → せんにひゃく; a version (1.60.0) is read part by part with てん between."""
    plain = digits.replace(",", "")
    if plain.count(".") > 1:
        return "てん".join(names.hiragana(kana.read_number(p)) for p in plain.split("."))
    return names.hiragana(kana.read_number(plain))


def _pieces(en: str) -> list[tuple[str, str]]:
    """[(kind, text)] of a name, tags left out: `word` (its possessive split off as the next `poss` piece),
    `letter`, `number`, `plus`, `kept` punctuation. Everything else only separates."""
    out: list[tuple[str, str]] = []
    text = _TAG.sub(" ", en)
    for i, m in enumerate(_PIECE.finditer(text)):
        p = m.group()
        # a letter with a full stop on either side is one letter of an abbreviation (I.O.U.), never a numeral
        dotted = text[m.end() : m.end() + 1] == "." or text[max(m.start() - 1, 0) : m.start()] == "."
        if p[0].isdigit():
            out.append(("number", p))
        elif p[0].isalpha():
            word = p.rstrip("'’")
            poss = word.endswith(("'s", "’s"))
            if poss:
                word = word[:-2]
            roman = _roman(word) if i and not dotted else None  # the first word of a name is never a numeral
            if roman is not None and not poss:
                out.append(("number", str(roman)))
            elif len(word) == 1 and word.lower() in _LETTER and (dotted or word.lower() != "a"):
                out.append(("letter", word))
            elif word:
                out.append(("word", word))
            if poss and word:
                out.append(("poss", ""))
        elif p in _WORD_FOR:
            out.append(("spelled", _WORD_FOR[p]))
        elif p == "+":
            out.append(("plus", p))
        elif p in _KEPT:
            out.append(("kept", _KEPT[p]))
    return out


def words(en: str) -> list[str]:
    """The words of a name that need a spelling, in order, as written."""
    return [t for kind, t in _pieces(en) if kind == "word"]


def assemble(en: str, spelling: Callable[[str], str | None]) -> tuple[str | None, str | None, list[str]]:
    """(Japanese, reading, words with no spelling). `spelling` gives a casefolded word's katakana, or None.
    The Japanese and the reading are None when a word has no spelling or the name has nothing to spell."""
    pieces = _pieces(en)
    several = len([k for k, _ in pieces if k == "word"]) > 1
    if several and pieces[0][0] == "word" and pieces[0][1].casefold() == "the":
        pieces = pieces[1:]
    missing = [t for kind, t in pieces if kind == "word" and not spelling(t.casefold())]
    if missing:
        return None, None, list(dict.fromkeys(missing))
    ja: list[str] = []
    reading: list[str] = []
    last = ""  # the kind of the piece written before this one
    for kind, text in pieces:
        if kind in ("word", "letter", "spelled"):
            if kind == "word":
                written = spelling(text.casefold()) or ""
            else:
                written = text if kind == "spelled" else _LETTER[text.lower()]
            dot = "・" if last in ("word", "letter", "spelled", "number", "poss", "closed") else ""
            # a letter written onto a number is one code (2P, 6P): no dot between them
            if kind == "letter" and last == "number":
                dot = ""
            ja.append(dot + written)
            reading.append(dot + names.hiragana(written))
        elif kind == "poss":
            ja.append("ズ")
            reading.append("ず")
        elif kind == "number":
            dot = "・" if last == "number" else ""  # two numbers side by side are two numbers, not one
            ja.append(dot + text)
            reading.append(dot + _number_reading(text))
        elif kind == "plus":
            ja.append("＋")
            reading.append("ぷらす")
        else:  # kept punctuation: written, not read (a dot stands in the reading where words meet across it)
            ja.append(text)
            if text == "：":
                reading.append("・")
        last = "opened" if kind == "kept" and text in _OPENS else "closed" if kind == "kept" else kind
    if not ja:
        return None, None, []
    return "".join(ja), "".join(reading).strip("・"), []
