"""What the engine reads for a line. It is the line as `voice.speech_text` gives it, with four changes that
keep the engine from saying a word wrong. None of them changes what the player sees.

- An English name is said in its Japanese spelling: the engine guesses at Latin letters.
- A space right before a kanji is taken out: the engine's text splitter breaks such a kanji into pieces it has
  no sound for, and the word comes out wrong.
- The stand-in for the player's name is written in kana.
- A listed single kanji is written in kana where it stands alone as a word. Alone it is read one way (金 かね)
  and inside a compound another (金貨 きんか), and the engine reaches for the compound's reading.
Pure: no disk.
"""

from __future__ import annotations

import re
from collections.abc import Callable, Collection, Sequence

from wfj.core import kana, voice

PLAYER_KANA = "ぼうけんしゃ"
_SPACE_BEFORE_KANJI = re.compile(r"[ 　]+(?=[㐀-䶿一-鿿々〆])")


def _alone_in_kana(text: str, words: Sequence[Sequence[str]], listed: Collection[tuple[str, str]]) -> str:
    """`text` with each listed (word, reading) of the line's reading words written as its reading. The words
    are found left to right, as the reading record lists them, so 金 inside 金貨 is never taken for 金."""
    out, at = [], 0
    for w in words:
        surface, reading = w[0], w[1]
        i = text.find(surface, at)
        if i < 0:
            continue  # a word the spoken line no longer holds (a stage direction, a token)
        out.append(text[at:i])
        out.append(reading if (surface, reading) in listed else surface)
        at = i + len(surface)
    out.append(text[at:])
    return "".join(out)


def voice_text(  # noqa: PLR0913 - the line, its numbers, its reading words and the two tables it is read by
    ja: str,
    key: str,
    values: Sequence[str],
    words: Sequence[Sequence[str]],
    name: Callable[[str], str | None],
    kana_words: Collection[tuple[str, str]],
) -> tuple[str, list[str]]:
    """(the text the engine reads, the English names with no Japanese). `words` are the line's reading words;
    `name` gives an English name's Japanese as it is said; `kana_words` are the (kanji, reading) said in kana
    where they stand alone."""
    text = _alone_in_kana(voice.speech_text(ja, key, values), words, kana_words)
    text = text.replace(voice.PLAYER_WORD, PLAYER_KANA)
    text, missing = kana.replace_names(text, name)
    return _SPACE_BEFORE_KANJI.sub("", text), missing
