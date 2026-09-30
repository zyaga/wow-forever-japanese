"""Stat words in item and spell tooltips: the Japanese the interface uses for them.

The character sheet and the stat lines of an item say アーマー, 体力, スタミナ (the UI dictionary's
`STAT_ARMOR`, `HEALTH`, `SPELL_STAT3_NAME` …), so a tooltip sentence on the same screen uses the same words
(`docs/content/translation-style-guide.md`, "Settled interface terms"). A stat word inside a name stays
English: `Mana Shield`, `Elixir of Agility`, `Spirit of Zandalar`. A name is told apart by its neighbours:
a stat word joined to another Latin word by a space or a hyphen is part of that name.
"""

from __future__ import annotations

import re

# English → the interface's Japanese, in the style guide table's order
STAT_WORDS: dict[str, str] = {
    "armor": "アーマー",
    "health": "体力",
    "mana": "マナ",
    "stamina": "スタミナ",
    "strength": "筋力",
    "agility": "敏捷性",
    "intellect": "知力",
    "spirit": "精神",
    "rage": "怒り",
    "energy": "エネルギー",
}
# Other Japanese spellings a line must not use for the word in its stat sense: the human corpus's ヘルス, and
# the words a draft reaches for instead of the interface's. Only spellings that never carry another sense
# in a tooltip belong here (健康 is "healthy", 防御力 is the Defense skill, 精霊 a spirit creature).
NOT_SPELLINGS: dict[str, tuple[str, ...]] = {
    "health": ("ヘルス",),
    "intellect": ("知性",),
    "energy": ("気力", "エナジー"),
}
_KATAKANA = "\u30a1-\u30f6\u30fc"

# A Latin run as the name check reads one (`align.NAME_RUN`, without its minimum length)
_RUN = re.compile(r"[A-Za-z][A-Za-z'’\-]*")
# a Latin word right before the run, joined to it by one space, hyphen or line break (`Mana Shield`, `of
# Agility`; a name wraps onto the next line in a tooltip)
_JOINED_BEFORE = re.compile(r"[A-Za-z'’](?:[ \n]+|-)\Z")
_JOINED_AFTER = re.compile(r"(?:[ \n]+|-)[A-Za-z]")
# Client escapes whose letters are no words: a texture or link path (`|TInterface\Icons\Spell_Holy_Mana:0|t`),
# and a colour code, which is glued to the word it colours (`|cffffffffStamina|r`)
_ESCAPE = re.compile(r"\|T.*?\|t|\|H.*?\|h|\|c[0-9A-Fa-f]{8}|\|r")
_POSSESSIVE = re.compile(r"['’]s\Z", re.I)


def _word(run: str) -> str | None:
    w = _POSSESSIVE.sub("", run).casefold()
    for base in (w, w.removesuffix("s"), w.removesuffix("ies") + "y" if w.endswith("ies") else ""):
        if base in STAT_WORDS:
            return base
    return None


def spans(ja: str) -> list[tuple[int, int, str]]:
    """`(start, end, word)` of every stat word a line keeps in English letters on its own."""
    # escapes are blanked with a character that is neither Latin nor a join, so offsets stay the same
    text = _ESCAPE.sub(lambda m: "\0" * len(m.group(0)), ja)
    out = []
    for m in _RUN.finditer(text):
        word = _word(m.group(0))
        if word is None:
            continue
        if _JOINED_BEFORE.search(text[: m.start()]) or _JOINED_AFTER.match(text, m.end()):
            continue
        out.append((m.start(), m.end(), word))
    return out


def classify(en: str, names: list[str]) -> tuple[set[str], set[str]]:
    """`(free, named)`: the stat words an English template uses on their own, as a stat (`Increases Stamina
    by $s1`, `the Stamina of the wearer`, `Stamina-boosting food`), and the ones it uses inside a name:
    joined by `of` to a capitalised word (`Elixir of Agility`, `Rage of the Suzerain`), next to a name word
    (`Arcane Intellect`, `Light's Vigil's Mana`) or before a capitalised word (`Mana Shield`, `Strength
    Increased`). Judged per occurrence, so a word can be in both (`Restores Mana. Mana Shield absorbs.`).
    `names` are the name words the lint read in the English (`lint_names.english_names`)."""
    names_ = {n.casefold() for n in names}
    text = _ESCAPE.sub(lambda m: "\0" * len(m.group(0)), en)
    words = [(m.start(), m.end(), _POSSESSIVE.sub("", m.group(0))) for m in _RUN.finditer(text)]

    def joined(a: int, b: int) -> bool:  # words a and b are neighbours: only spaces or line breaks between
        if not 0 <= a < b < len(words):
            return False
        gap = text[words[a][1]: words[b][0]]
        return gap != "" and gap.strip(" \n") == ""

    def word(k: int) -> str:
        return words[k][2] if 0 <= k < len(words) else ""

    def capitalised(k: int) -> bool:
        return word(k)[:1].isupper()

    free: set[str] = set()
    named: set[str] = set()
    for i, (_, _, run) in enumerate(words):
        head, _, tail = run.partition("-")  # `Stamina-boosting`: a lower-case tail is no name
        stat = _word(run) or (_word(head) if tail[:1].islower() else None)
        if stat is None:
            continue
        before = word(i - 1) if joined(i - 1, i) else ""
        after = word(i + 1) if joined(i, i + 1) else ""
        # `X of Stat` / `X of the Stat` with X capitalised; `Stat of Y` / `Stat of the Y` with Y capitalised
        in_name = before.casefold() == "of" and capitalised(i - 2) and joined(i - 2, i - 1)
        if before.casefold() == "the" and word(i - 2).casefold() == "of" and capitalised(i - 3):
            in_name = True
        if after.casefold() == "of":
            far = i + 3 if word(i + 2).casefold() == "the" else i + 2
            in_name = in_name or capitalised(far)
        in_name = in_name or before.casefold() in names_ or after[:1].isupper()
        (named if in_name else free).add(stat)
    return free, named


def free_in_english(en: str, names: list[str]) -> set[str]:
    """The stat words an English template uses on their own, as a stat (`classify`)."""
    return classify(en, names)[0]


def find(ja: str) -> list[str]:
    """The stat words a Japanese line keeps in English letters on their own, as lower-case English, in
    order."""
    return [word for _, _, word in spans(ja)]


def settle(ja: str) -> str:
    """The line with every stat word it keeps in English letters on its own replaced by its Japanese."""
    out, at = [], 0
    for start, end, word in spans(ja):
        out += [ja[at:start], STAT_WORDS[word]]
        at = end
    return "".join(out) + ja[at:]


def _spelling(other: str) -> re.Pattern[str]:
    """The spelling as a whole word: a katakana spelling is not read inside a longer katakana word
    (ヘルスストーン is the Healthstone, not ヘルス)."""
    if re.fullmatch(f"[{_KATAKANA}]+", other):
        return re.compile(f"(?<![{_KATAKANA}]){re.escape(other)}(?![{_KATAKANA}])")
    return re.compile(re.escape(other))


def spelling_spans(ja: str) -> list[tuple[int, int, str]]:
    """`(start, end, word)` of every other spelling (`NOT_SPELLINGS`) a line uses, in order."""
    out = [(m.start(), m.end(), word) for word, spellings in NOT_SPELLINGS.items()
           for other in spellings for m in _spelling(other).finditer(ja)]
    return sorted(out)


def settle_spellings(ja: str) -> str:
    """The line with every other spelling (`NOT_SPELLINGS`, ヘルス) replaced by the settled Japanese."""
    out, at = [], 0
    for start, end, word in spelling_spans(ja):
        out += [ja[at:start], STAT_WORDS[word]]
        at = end
    return "".join(out) + ja[at:]


def not_spellings(ja: str) -> list[str]:
    """The other Japanese spellings (`NOT_SPELLINGS`) a line uses, each once."""
    return list(dict.fromkeys(ja[a:b] for a, b, _ in spelling_spans(ja)))
