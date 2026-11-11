"""English word cards: which English word of a line goes with which Japanese word of its translation.

A reading entry carries the meaning of its Japanese word as that sentence uses it (倒して → "defeat"). Turned
around, that says which English word of the line the Japanese word stands for, so a player reading the English
can point at "defeat" and see 倒して. Nothing is written by a model here: the pairs are read off the
meanings the readings already hold.

The addon is handed, per line, only the set of English words that found a Japanese word, lower-cased and
sorted, each with the place of that Japanese word in the line's reading row. Never the sentence, never its
order. Pure: no disk.
"""

from __future__ import annotations

import re

# A word, as the addon reads the live line: a run of ASCII letters and apostrophes.
TOKEN = re.compile(r"[A-Za-z']+")
# A code the client fills in before the player sees the line ($N, $Gsir:madam;, %s, |cff…): never a word.
CODE = re.compile(r"\$[A-Za-z]\w*(?::[^;]*)?;?|%\d*\$?[a-z]|\|c[0-9a-fA-F]{8}|\|[rnTtHh]")

# Words that carry no meaning of their own in a phrase: a phrase is matched by the words left over. A meaning
# that is only one of these ("you", "more") still matches that word itself.
FUNCTION_WORDS = frozenset(
    """a an the and or but of to in on at for with from by as is are was were be been being am do does did
    have has had will would shall should can could may might must not no it its this that these those there here
    i you he she we they me him her us them my your his our their what which who whom whose when where why how
    all any some many much more most few less so than too very just only also then now if into onto out up down
    over under again off about above below between through during before after while because until unless back
    away around along across toward towards one's oneself something someone""".split()
)

# Words that take no card by design: Japanese has no word for an article, and the bare forms of be, have and do
# and the commonest prepositions only mean something with the words around them. Coverage is counted without them.
NO_CARD = frozenset(
    """a an the to of in on at for as by than off upon is are was were be been being am 's
    have has had having do does did doing""".split()
)

_SUFFIXES = ("ing", "ies", "ed", "es", "s", "ly", "d")


def base(word: str) -> str:
    """A contraction's first word (`you're` → `you`, `let's` → `let`); any other word as it is. The addon
    falls back to it when the whole word has no card."""
    head, apostrophe, _ = word.partition("'")
    return head if apostrophe and head else word


def tokens(text: str) -> list[str]:
    """The words of `text` as the addon finds them on screen."""
    return [t for t in TOKEN.findall(text) if t.strip("'")]


def stem(word: str) -> str:
    """A crude stem, enough to bring `kills`, `killed` and `killing` to `kill`. Lower-case in, lower-case
    out; a word too short to lose its ending is left whole."""
    w = word.lower().strip("'")
    for suffix in _SUFFIXES:
        if w.endswith(suffix) and len(w) - len(suffix) >= 3:
            w = w[: -len(suffix)]
            if suffix == "ies":
                w += "y"
            elif len(w) >= 4 and w[-1] == w[-2] and w[-1] not in "aeiousl":  # running → runn → run
                w = w[:-1]
            break
    return w[:-1] if len(w) >= 4 and w.endswith("e") else w  # hope / hoping, come / coming


def line_words(en: str) -> list[str]:
    """The line's words that can take a card, lower-cased, in order. A capitalised word in the middle of a
    sentence is a name (names stay English and get no card); a sentence's first word is not."""
    text = CODE.sub(" ", en)
    out: list[str] = []
    for m in TOKEN.finditer(text):
        word = m.group()
        if not word.strip("'"):
            continue
        if word[0].isupper() and word != "I":
            before = text[: m.start()].rstrip(" \"'“‘(")
            if before and before[-1] not in ".!?:\n":
                continue
        out.append(word.lower())
    return out


_BRACKETED = re.compile(r"\s*([^()]+?)\s*\(([^()]*)\)\s*")


def _senses(meaning: str) -> list[tuple[str, bool]]:
    """(sense, whether it is the meaning's own wording) in the order they are tried: the meaning as the
    sentence uses it, then the plainer one in brackets after it ("kill (defeat)"). Brackets anywhere else
    mark words the sentence leaves unsaid ("if (you) can"): the phrase is read whole, without them."""
    m = _BRACKETED.fullmatch(meaning)
    if not m:
        # a meaning wholly in brackets ("(that)") is a word the Japanese leaves unsaid: a hint, like any bracket
        whole = meaning.strip().startswith("(") and meaning.strip().endswith(")")
        return [(re.sub(r"[()]", " ", meaning).strip(), not whole)]
    return [(m.group(1), True), (m.group(2).strip(), False)]


def _match(sense: str, own: bool, by_stem: dict[str, list[str]], taken: set[str]) -> list[str]:
    """The line's words one sense of a meaning stands for, or none."""
    words = [w.lower() for w in tokens(sense)]
    if not words:
        return []
    content = [w for w in words if w not in FUNCTION_WORDS]
    if not content:
        # a meaning that is one function word stands for that word itself: only in the meaning's own wording
        # (a bracketed "(with)" is a hint, not what the word means), and never a word that takes no card
        if not own or len(words) != 1 or words[0] in NO_CARD:
            return []
        found = by_stem.get(stem(words[0]), [])
        return [w for w in found if w == words[0] and w not in taken]
    # every content word of a phrase must be in the line; the phrase then stands on its last one
    for w in content:
        if stem(w) not in by_stem:
            return []
    return [w for w in by_stem[stem(content[-1])] if w not in taken]


def invert(en: str, words: list[list[str]]) -> dict[str, int]:
    """{English word of the line, lower-cased: the 1-based place of its Japanese word in `words`}.
    `words` are a reading record's entries; one without a meaning (two items) pairs with nothing. A line word
    goes to the first Japanese word that claims it."""
    by_stem: dict[str, list[str]] = {}
    for w in dict.fromkeys(line_words(en)):
        by_stem.setdefault(stem(w), []).append(w)
    out: dict[str, int] = {}
    taken: set[str] = set()
    for place, entry in enumerate(words, start=1):
        if len(entry) < 5 or not entry[4]:
            continue
        for sense, own in _senses(entry[4]):
            found = _match(sense, own, by_stem, taken) if sense else []
            if found:
                for w in found:
                    out[w] = place
                    taken.add(w)
                break
    return out


def pack(pairs: dict[str, int]) -> str:
    """The addon's row: "word=n word=n …", by word. Sorting is what keeps the sentence out of the file."""
    return " ".join(f"{w}={n}" for w, n in sorted(pairs.items()))
