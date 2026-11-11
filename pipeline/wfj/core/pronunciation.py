"""How an English word is said, for the English word card.

The source is the CMU Pronouncing Dictionary: each word as a row of phones with a stress digit on its vowels
(`defeat D IH0 F IY1 T`). The card shows it respelled the way Japanese-English dictionaries do (i for the
vowel
of "sit", e for "bed", əːr for "bird"), which is the spelling its readers know and, unlike the international
letters for those three vowels, is drawn in full by the addon's font. Pure: no disk.
"""

from __future__ import annotations

# vowel phone → letters, with primary or secondary stress and without
VOWELS_STRESSED = {
    "AA": "ɑ",
    "AE": "æ",
    "AH": "ʌ",
    "AO": "ɔː",
    "AW": "au",
    "AY": "ai",
    "EH": "e",
    "ER": "əːr",
    "EY": "ei",
    "IH": "i",
    "IY": "iː",
    "OW": "ou",
    "OY": "ɔi",
    "UH": "u",
    "UW": "uː",
}
VOWELS_UNSTRESSED = VOWELS_STRESSED | {"AH": "ə", "ER": "ər", "IY": "i"}
CONSONANTS = {
    "B": "b",
    "CH": "tʃ",
    "D": "d",
    "DH": "ð",
    "F": "f",
    "G": "g",
    "HH": "h",
    "JH": "dʒ",
    "K": "k",
    "L": "l",
    "M": "m",
    "N": "n",
    "NG": "ŋ",
    "P": "p",
    "R": "r",
    "S": "s",
    "SH": "ʃ",
    "T": "t",
    "TH": "θ",
    "V": "v",
    "W": "w",
    "Y": "j",
    "Z": "z",
    "ZH": "ʒ",
}
# every letter above is in the bundled font (tests/python/test_pronunciation.py holds the list to it)
FONT_SAFE = frozenset("abdefghijklmnoprstuvwzæðŋɑɔəʃʌʒθːˈˌ")

# consonant runs an English syllable can open with; anything longer or other splits before its last consonant
_ONSETS = frozenset(
    """
    P_L P_R B_L B_R T_R D_R K_L K_R G_L G_R F_L F_R TH_R SH_R S_P S_T S_K S_M S_N S_L S_W T_W D_W K_W
    S_P_L S_P_R S_T_R S_K_R S_K_W P_Y B_Y F_Y K_Y M_Y HH_Y V_Y
    """.split()  # noqa: SIM905
)
_STRESS = {"1": "ˈ", "2": "ˌ"}


def _onset_length(run: list[str]) -> int:
    """How many of the consonants before a vowel belong to its syllable."""
    for n in range(min(3, len(run)), 1, -1):
        if "_".join(run[-n:]) in _ONSETS:
            return n
    return 1 if run and run[-1] != "NG" else 0


def spell(phones: list[str]) -> str | None:
    """The word's spelling from its phones, or None when one is not a phone this table knows. A word of one
    syllable takes no stress mark; a longer one takes ˈ (and ˌ) where the stressed syllable begins."""
    parts: list[str] = []  # the spelled phones, in order
    marks: dict[int, str] = {}  # index into parts → the stress mark that goes before it
    run_start = 0  # where the consonants since the last vowel begin
    vowels = 0
    for phone in phones:
        base, digit = (phone[:-1], phone[-1]) if phone[-1:].isdigit() else (phone, "")
        if digit:
            if base not in VOWELS_STRESSED:
                return None
            vowels += 1
            if digit in _STRESS:
                run = [p.rstrip("012") for p in phones[run_start : len(parts)]]
                # the consonants that open the word all belong to its first syllable, whatever they are
                onset = len(run) if run_start == 0 else _onset_length(run)
                marks[len(parts) - onset] = _STRESS[digit]
            parts.append((VOWELS_STRESSED if digit != "0" else VOWELS_UNSTRESSED)[base])
            run_start = len(parts)
        else:
            if base not in CONSONANTS:
                return None
            parts.append(CONSONANTS[base])
    if vowels == 0:
        return None
    if vowels == 1:
        marks = {}
    return "".join(marks.get(i, "") + p for i, p in enumerate(parts))


def parse(text: str) -> dict[str, str]:
    """{word: spelling} from the dictionary's text: `word PH PH …` per line, `word(2)` a second way to say it
    (the first is kept), `#` a comment."""
    out: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or line.startswith(";;;"):
            continue
        word, *phones = line.split()
        if "(" in word or word in out or not phones:
            continue
        spelled = spell(phones)
        if spelled is not None:
            out[word.lower()] = spelled
    return out


_SOURCE = "# source: CMU Pronouncing Dictionary (cmusphinx/cmudict) @ {version}; respelled by wfj"


def table(words: dict[str, str], version: str) -> str:
    """`data/`'s pronunciation table: a line naming the source and its pinned version, then one line per
    word (the word, a tab, its spelling), by word."""
    return (
        "\n".join([_SOURCE.format(version=version), *(f"{w}\t{s}" for w, s in sorted(words.items()))]) + "\n"
    )


def parse_table(text: str) -> tuple[dict[str, str], str]:
    """(words, version) of a table `table` wrote. A table with no source line has version ""."""
    words: dict[str, str] = {}
    version = ""
    for line in text.splitlines():
        if line.startswith("#"):
            if "@" in line:
                version = line.split("@", 1)[1].split(";", 1)[0].strip()
            continue
        word, _, spelled = line.partition("\t")
        if word and spelled:
            words[word] = spelled
    return words, version
