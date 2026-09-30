"""Which capitalised English words are names a translation must keep in English letters: the
`name_missing` check of `wfj.dev.translate_lint`.

Glossary terms (`pipeline/translation_glossary.tsv`: titles and common nouns such as `the Captain`, races,
classes) are translated, so exempt, except directly before or after a capitalised name word (`Captain
Althea`, `Murloc Warrior`, `Dark Lady`, `Lion's Pride Inn`), or before one through other glossary words (`Arch
Druid Hamuul`), where they are part of the name. A profession name is kept but is not a name word for a title
after it (`Skinning Trainer` → `Skinningのトレーナー`). A place or group word joined to a capitalised word by
`of (the)` makes one name (`Temple of the Moon`), a person title does not (`the King of Stormwind`);
`FIXED_NAMES` (`Duke of Shards`) always are. A word that starts a sentence is not read as a name, except a
glossary word or a profession name (`Tailoring you say?`).
"""

from __future__ import annotations

import re

from wfj.core import align

_SENTENCE_END = ".!?…:;\n\"'“”‘’-\u2013\u2014<>)"
_OPENERS = " \t\r(["  # `\r`: book pages break lines with `\n\r`
# A client template's conditional puts its prose inside brackets: `$?j1g[Increases ground speed
# by $j1g%. ][]`. That prose starts a sentence, so its first word is not a name; stripping the `[` alone
# leaves the condition `$?j1g`, which ends in a letter and reads as mid-sentence. Only the bracket form
# is treated this way: a code that merely precedes a word (`Deals $s1 Fire damage`) must NOT make the
# word after it a sentence start, or the name check would stop seeing names mid-sentence.
_CONDITION_OPEN = re.compile(r"\$[^\s\[\]]*\[$")
_STAGE = re.compile(r"<[^<>/]*>|\*[^*]*\*")  # `<Sob>`, `<You are well versed …>`, `*cough*`
_POSSESSIVE = re.compile(r"['’](?:s|ll|d)$")  # `Kazzak's`, `Malin'll`, `Elling'd`
GENDER_CODE = re.compile(r"\$[Gg][^:;$]*:[^;$]*;")  # `$Gsir:madam;`, `$G Sir : Ma'am;`: one neutral draft
# A plural code prints one of its two words: `$LFire:Fires;` is "Fire" or "Fires", the client's
# choice, not a name the Japanese has to keep in English letters. Stripped like a gender code, or `LFire`
# reads as a capitalised word and every `$L<Capitalised>:…;` row fails `name_missing` for good.
PLURAL_CODE = re.compile(r"\$[lL][^:;$]*:[^;$]*;")
# `Orgrimmar--somethin'`, `Scourge-driven`, `A-number-one`: two words; an en or em dash splits too
_DASH = re.compile(r"-+|[\u2013\u2014]")
# Profession (skill) names: kept in English, but not a name a following title belongs to (`Skinning Trainer` →
# `Skinningのトレーナー`). `Aid` is the last word of `First Aid`.
SKILLS = frozenset({
    "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "Aid", "Fishing", "Herbalism",
    "Leatherworking", "Mining", "Skinning", "Tailoring",
})
# Place and group words: next to `of (the)` and a capitalised word they make one name that stays in English
# letters (`Temple of the Moon`, `Bank of Orgrimmar`, `Brotherhood of the Light`). A person title with `of`
# stays translatable (`the King of Stormwind` → `Stormwindの王`). Case-folded singulars.
PLACES = frozenset({
    "temple", "bank", "council", "inn", "guardian", "brotherhood", "kingdom", "township", "cathedral",
    "church", "order", "guild", "hall", "crusade", "legion", "circle", "league", "society",
})
# Fixed names built from glossary words: every word stays in English letters (the abyssal elemental lords).
FIXED_NAMES = ("Duke of Shards", "Duke of Cynders", "Duke of Fathoms", "Duke of Zephyrs")



def exempt_words(glossary: dict[str, str]) -> set[str]:
    """Every word of every glossary term (a two-word term exempts both words)."""
    return {w for term in glossary for w in term.split()}


def forms(word: str) -> set[str]:
    """The word and its possible singulars (`Gnolls` → `gnoll`, `Dwarves` → `dwarf`), case-folded."""
    w = word.casefold()
    forms = {w, w.removesuffix("s"), w.removesuffix("es")}
    if w.endswith("ves"):
        forms.add(w[:-3] + "f")
    return {f for f in forms if f}


def _exempt(word: str, exempt: set[str]) -> bool:
    """A glossary word, or its plural (`Taurens`, `Gnomes`, `Dwarves`, `Elves`), or a hyphenated word led by
    one (`Light-burning`)."""
    return bool((forms(word) | forms(word.split("-", 1)[0])) & exempt)


def _capitalised(word: str) -> bool:
    return word[:1].isupper() and not word.isupper()


_ROMAN = re.compile(r"[IVXLC]+")


def titles_before_names(en: str, names: list[str], exempt: set[str]) -> list[str]:
    """Glossary title words standing directly in front of one of `names` in a title-case line
    (`Baron Aquanis`, `Arch Druid Hamuul`): part of the name, so they stay in English letters. Title
    case capitalises every word, so this reads from the listed names back, one word at a time, while the word
    is a glossary word."""
    out: list[str] = []
    for name in names:
        if _ROMAN.fullmatch(name):  # `Volume II`: a numeral, not a name a title word belongs to
            continue
        for m in re.finditer(r"(?<![A-Za-z'’\-])" + re.escape(name) + r"(?![A-Za-z])", en):
            start = m.start()
            while w := re.search(r"([A-Za-z][A-Za-z'’\-]*) $", en[:start]):
                word = w.group(1)
                if word == "The" or not _capitalised(word) or not _exempt(word, exempt):
                    break
                out.append(word)
                start = w.start(1)
    return out


def english_names(en: str, exempt: set[str]) -> list[str]:
    """Capitalised words that do not start a sentence, in order. Not names: `I'm` / `I'll` …, shouted
    all-caps words, `The`, words in a `<…>` stage direction, glossary words and their plurals used alone (a
    glossary word directly before a capitalised non-glossary word is part of that name); a possessive `'s`
    and a contracted `'ll` / `'d` are dropped."""
    stripped = PLURAL_CODE.sub(" ", GENDER_CODE.sub(" ", align.PLACEHOLDER.sub(" ", en)))
    text = _DASH.sub("\n", _STAGE.sub("\n", stripped))
    fixed = [(m.start(), m.end()) for n in FIXED_NAMES for m in re.finditer(re.escape(n), text)]
    out: list[str] = []
    for m in align.NAME_RUN.finditer(text):
        word = _POSSESSIVE.sub("", m.group(0)).strip("'’-")
        if (
            not _capitalised(word)
            or word[:2] in ("I'", "I’")
            or word == "The"
            or word in out
        ):
            continue
        if (
            _exempt(word, exempt)
            and not _before_name(text, m.end(), exempt)
            and not _after_name(text, m.start(), exempt)
            and not _of_name(text, m.start(), m.end(), word)
            and not any(a <= m.start() < b for a, b in fixed)
        ):
            continue
        if _sentence_start(text, m.start()) and not _checked_first(word, exempt):
            continue
        out.append(word)
    return out


def _sentence_start(text: str, start: int) -> bool:
    if _CONDITION_OPEN.search(text[:start].rstrip(" \t\r")):
        return True
    before = text[:start].rstrip(_OPENERS)
    return not before or before[-1] in _SENTENCE_END


def _checked_first(word: str, exempt: set[str]) -> bool:
    """A capitalised word that starts a sentence is usually not a name (`Say`, `Our`, `Six`), so it is not
    checked, except a glossary word or a profession name, which is checked there like anywhere else: a
    glossary word reaching here leads a name (`Captain Althea rides.`), and a skill name stays in English
    letters (`Tailoring you say?`)."""
    return _exempt(word, exempt) or _skill(word)


def _before_name(text: str, end: int, exempt: set[str]) -> bool:
    """The word ending at `end` is directly followed (one space) by a capitalised word that is not itself
    a glossary word, reading through a run of capitalised glossary words: `Captain Althea`, `Murloc Warrior`,
    `Arch Druid Hamuul`, not `the Captain to`, `Night Elf`, `the Arch Druid wants`."""
    while m := re.match(r" ([A-Za-z][A-Za-z'’\-]*)", text[end:]):
        nxt = _POSSESSIVE.sub("", m.group(1)).strip("'’-")
        if not _capitalised(nxt) or nxt == "The":
            return False
        if not _exempt(nxt, exempt):
            return True
        end += m.end()
    return False


def _after_name(text: str, start: int, exempt: set[str]) -> bool:
    """The word starting at `start` directly follows (one space) a capitalised word that is not itself a
    glossary word or a profession name: `Dark Lady`, `Lion's Pride Inn`, not `the Lady`, `The Inn`,
    `Night Elf`, `Skinning Trainer`. A word that starts a sentence is capitalised because it starts one, so
    it is no name to belong to either: `Say Captain…`, `Our Alchemist's…`, `Six Lieutenants…`."""
    if m := re.search(r"([A-Za-z][A-Za-z'’\-]*) $", text[:start]):
        prev = _POSSESSIVE.sub("", m.group(1)).strip("'’-")
        if not _capitalised(prev) or prev == "The" or _exempt(prev, exempt) or prev in SKILLS:
            return False
        return not _sentence_start(text, m.start(1))
    return False


def _skill(word: str) -> bool:
    """A profession (skill) name, or its plural: `Tailoring`, `Mining`."""
    return bool(forms(_POSSESSIVE.sub("", word)) & {s.casefold() for s in SKILLS})


def _place(word: str) -> bool:
    return bool(forms(_POSSESSIVE.sub("", word)) & PLACES)


def _of_name(text: str, start: int, end: int, word: str) -> bool:
    """The word is one side of `<word> of (the) <Capitalised>` or `<Capitalised> of (the) <word>` where either
    side is a place or group word: `Temple of the Moon`, `Bank of Orgrimmar`, `Brotherhood of the Light`, not
    `the King of Stormwind`."""
    if m := re.match(r"(?:['’]s)? of (?:the )?([A-Za-z][A-Za-z'’\-]*)", text[end:]):
        other = m.group(1)
        if _capitalised(other) and other != "The" and (_place(word) or _place(other)):
            return True
    if m := re.search(r"([A-Za-z][A-Za-z'’\-]*) of (?:the )?$", text[:start]):
        other = m.group(1)
        if _capitalised(other) and other != "The" and (_place(word) or _place(other)):
            return True
    return False
