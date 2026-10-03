"""Alignment: the English names and numbers inside a Japanese line must exist in its English scope.

No model. `latin_names` finds Latin-script runs (joined into multi-word names when the next token is
capitalized), drops allowlisted game words and runs shorter than 3 letters; `numbers` collects digit
runs after full-width folding, ignoring digits glued to Latin letters (Mk2, N1).
"""

from __future__ import annotations

import re
import unicodedata
from collections import Counter
from collections.abc import Mapping
from dataclasses import dataclass, field

NAME_RUN = re.compile(r"[A-Za-z][A-Za-z'’\-]{2,}")
PLACEHOLDER = re.compile(r"\{(?:name|class|race)\}")
# A whole run; "Mk12" yields nothing, not "2". An ENGLISH ordinal is that number: "40th level" reads as
# 40 to a player, so a Japanese "40" there is not a number the Japanese invented.
NUMBER = re.compile(r"(?<![A-Za-z0-9])\d+(?![A-Za-z0-9])")
_ORDINAL = re.compile(r"(?<![A-Za-z0-9])(\d+)(?:st|nd|rd|th)\b", re.I)

# The stored Japanese of an item / spell description may carry `$N<k>`, which the addon replaces
# with the k-th number of the line the client is actually showing (`Align.fill` / `Align.values`, in
# reading order). That is what keeps a translation right when the value differs by rank, level or talent:
# a baked number is refused by `Align.check` the moment the client's value moves.
FILL = re.compile(r"\$N(\d+)")
# A server code that resolves to ONE number, so it occupies one slot: `$s1`, `$o2`, `$d`, `$h`, `$w1`,
# `$m1`, `$a1`, `$t1`, `$q1`, `$M1`, a cross-spell `$1279976s1`, a divided `$/10;s2`, and a named variable
# `$<minDam>` / `$<mult>` (582 of those in the corpus), and each prints a number like the rest.
VALUE_CODE = re.compile(r"\$<[^>]+>|\$(?:/\d+;)?\d*[a-zA-Z]\d*")
# A server code that resolves to a DURATION, a value whose unit the client chooses (`$d`, `$d1`, a
# cross-spell `$7922d`). These are the slots a draft must write `$D<k>` for, never a number plus a unit
# it named itself: `Align.check` cannot catch a wrong unit, because the number matches and the unit is
# Japanese text it never reads.
DURATION_CODE = re.compile(r"\$\d*d\d*(?![a-zA-Z])")
# Arithmetic: the client computes it and prints the one number it comes to, however many codes are inside.
# A trailing `.N` is Blizzard's precision, not a second value: `${$s1}.1%` prints `2.5%`, one number, and
# `Align.values` reads `2.5` as one token. Counting the `.1` as its own slot would tell drafters to
# write `$N1.$N2`, which fills two values into a line that has one.
SUM = re.compile(r"\$\{[^{}]*\}(?:\.\d)?")
# Codes that print a WORD, never a number: pluralisation `$lsecond:seconds;`, a gender branch `$g a:b;`
# (normally resolved out by `normalize_v1` before a template is stored; handled here in case one survives),
# and `$z`, the player's home location: `Returns you to $z.` names a town, and counting it as a value would
# send a drafter's `$N<k>` looking for a number that is never there (8 lines use it).
WORD_CODE = re.compile(r"\$[lLgG][^;]*;|\$[zZ](?![a-zA-Z0-9])")
# An inline spell icon (ADR-043). `expand_inclusions` turns each `$@spellicon<id>` into `$I<k>` (its
# order in the line), and the Japanese carries the same `$I<k>`; the addon copies the k-th `|T…|t` texture
# escape of the live line there. It prints a picture, never a number, so it is masked like a word code.
ICON = re.compile(r"\$I(\d+)")
# what `_count` / `_tokens` / `_residue` mask before reading values: word codes and icons
_NOT_VALUE = re.compile(f"{WORD_CODE.pattern}|{ICON.pattern}")
# A template this module will NOT count slots for. A conditional shows one branch or the other, and the
# branches print different numbers of values; `$@spelldesc123` splices another spell's whole description in.
# How many numbers either prints is unknowable from the template, so saying so is the honest answer,
# never a guess a drafter would trust. The untranslated Forever corpus held 176 conditional and 1,504
# inclusion rows against ~27,000 that count exactly, so `translate_batch` leaves these out, except a
# conditional whose branches read the same apart from their numbers, counted as one.
UNCOUNTABLE = re.compile(r"\$\?|\$@")
# A NAME-LIST TAIL (ADR-033). Languages (1293657) and Armor Proficiency (1293712) end in a chain of
# `$?s<id>[<line break>$@spellname<id>][]`: one line per spell the player knows, each printing that spell's
# NAME. The chain is the description's trailing run; everything before it (the head) is an ordinary template.
# The names are live English (names stay in English), so the Japanese is the head's translation followed
# by `$T`: the addon copies the live lines from the first line break on, byte for byte (`Align.check`,
# Core/Align.lua).
NAME_LIST_TAIL = re.compile(r"(?:\$\?s\d+\[(?:\r\n|\n)\$@spellname\d+\]\[\])+\Z")
TAIL = "$T"

MIN_LEN = 3


def split_tail(en: str) -> tuple[str, bool]:
    """(the head, whether a name-list tail was peeled off). The tail is peeled only when the chain is the
    description's trailing run, the head before it is not empty, and the head is ONE line: the addon cuts the
    live description at its first line break (`Align.splitTail`, Core/Align.lua), so a head that is itself
    several lines could not be matched against it. Apprentice / Journeyman Riding (33388, 33391) end in the
    same chain after a three-line head, and stay uncountable."""
    m = NAME_LIST_TAIL.search(en or "")
    if m is None or m.start() == 0:
        return en or "", False
    head = en[: m.start()]
    if "\n" in head or "\r" in head:
        return en, False
    return head, True


def tail_problems(en: str, ja: str) -> list[str]:
    """A Japanese line's `$T` against its English: `tail_missing` (the English has a name-list tail and the
    Japanese does not end in `$T`), `tail_unexpected` (a `$T` with no tail), `tail_misplaced` (a `$T` that is
    not the line's one last token), `tail_empty` (the Japanese is nothing but `$T`, which would render a blank
    head), `tail_chain` (the Japanese writes a chain element itself: a `$?` or `$@`, which the addon would
    show raw). `[]` when the line is right."""
    has_tail = split_tail(en)[1]
    n = (ja or "").count(TAIL)
    out: list[str] = []
    if UNCOUNTABLE.search(ja or ""):
        out.append("tail_chain")
    if (ja or "").strip() == TAIL:
        out.append("tail_empty")
    if has_tail and n == 0:
        out.append("tail_missing")
    elif not has_tail and n:
        out.append("tail_unexpected")
    elif n and (n > 1 or not ja.endswith(TAIL)):
        out.append("tail_misplaced")
    return out


def load_allowlist(text: str) -> set[str]:
    """`term  # justification` per line; blank and `#` lines ignored. Terms compare case-insensitively."""
    out = set()
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        term = line.split("#", 1)[0].strip()
        if term:
            out.add(term.casefold())
    return out


def allowlist_problems(text: str) -> list[str]:
    """Lines without a justification."""
    bad = []
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "#" not in line or not line.split("#", 1)[1].strip():
            bad.append(f"line {n}: no justification")
    return bad


def fold_digits(text: str) -> str:
    return "".join(unicodedata.normalize("NFKC", c) if "０" <= c <= "９" else c for c in text)


def latin_names(text: str, allowlist: set[str]) -> list[str]:
    """Distinct candidate names in order of first appearance; multi-word when tokens are space-joined
    and the following token starts with a capital (Senani Thunderheart, Sharptalon's Claw)."""
    text = PLACEHOLDER.sub(" ", text)
    tokens = [(m.start(), m.end(), m.group(0)) for m in NAME_RUN.finditer(text)]
    names: list[str] = []
    i = 0
    while i < len(tokens):
        start, end, tok = tokens[i]
        words = [tok]
        j = i + 1
        while j < len(tokens) and tokens[j][0] == end + 1 and text[end] == " " and tokens[j][2][0].isupper():
            words.append(tokens[j][2])
            end = tokens[j][1]
            j += 1
        name = " ".join(words).strip("'’-")
        if len(name) >= MIN_LEN and name.casefold() not in allowlist and name not in names:
            names.append(name)
        i = j
    return names


def _present(name: str, scope: str) -> bool:
    return name.casefold() in scope


def check_names(ja: str, scope_text: str, allowlist: set[str]) -> tuple[list[str], list[str]]:
    """Returns (checked, missing). A multi-word name missing as a whole is retried word by word so
    'Northshire Abbeyの' style joins and reordered names don't reject; only words still missing count."""
    scope = unicodedata.normalize("NFC", scope_text).casefold()
    checked: list[str] = []
    missing: list[str] = []
    for name in latin_names(ja, allowlist):
        checked.append(name)
        if _present(name, scope):
            continue
        parts = [
            w for w in name.split(" ") if len(w.strip("'’-")) >= MIN_LEN and w.casefold() not in allowlist
        ]
        gaps = [w for w in parts if not _present(w, scope)]
        if gaps:
            missing.append(name if len(parts) == 1 else " ".join(gaps))
    return checked, missing


_WORDS = {
    "zero": 0,
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    "ten": 10,
    "eleven": 11,
    "twelve": 12,
    "thirteen": 13,
    "fourteen": 14,
    "fifteen": 15,
    "sixteen": 16,
    "seventeen": 17,
    "eighteen": 18,
    "nineteen": 19,
    "twenty": 20,
    "thirty": 30,
    "forty": 40,
    "fifty": 50,
    "sixty": 60,
    "seventy": 70,
    "eighty": 80,
    "ninety": 90,
    "hundred": 100,
    "thousand": 1000,
    "dozen": 12,
    "single": 1,
}
_WORD_RE = re.compile(r"\b(" + "|".join(_WORDS) + r")(?:[- ](" + "|".join(_WORDS) + r"))?\b", re.I)


def english_number_words(text: str) -> list[str]:
    """Digits for English number words ("three", "twenty-five", "two hundred") so a Japanese "3" aligns."""
    out: list[str] = []
    for m in _WORD_RE.finditer(text):
        a, b = _WORDS[m.group(1).lower()], (_WORDS[m.group(2).lower()] if m.group(2) else None)
        if b is None:
            out.append(str(a))
        elif b in (100, 1000):
            out.append(str(a * b))
        else:
            out.append(str(a + b))
            out.append(str(a))
    return out


def numbers(text: str, *, english: bool = False) -> Counter[str]:
    c = Counter(NUMBER.findall(fold_digits(PLACEHOLDER.sub(" ", text))))
    if english:
        c.update(english_number_words(text))
        c.update(_ORDINAL.findall(text))  # "40th level" is 40 on screen
    return c


def check_numbers(ja: str, scope_text: str) -> tuple[list[str], list[str]]:
    """Returns (checked, missing): every digit run in the Japanese must exist in the scope (multiset)."""
    want, have = numbers(ja), numbers(scope_text, english=True)
    checked = sorted(want.elements(), key=lambda s: (len(s), s))
    missing = sorted((want - have).elements(), key=lambda s: (len(s), s))
    return checked, missing


def fill_indices(ja: str) -> list[int]:
    """The `$N<k>` indices a Japanese line uses, in reading order."""
    return [int(m) for m in FILL.findall(ja or "")]


# A literal the client shows as one number, read exactly as `Align.values` reads it: a maximal run of
# digits, `.` and `,` holding a digit, not glued to a letter. `1,200` and `0.15` are ONE value, and `...16,
# 23` is two; counting them otherwise would tell a draft to use slots the live line does not have.
LITERAL = re.compile(r"(?<![A-Za-z0-9.,$])[\d.,]*\d[\d.,]*(?![A-Za-z0-9.,])")
# The unit words of the duration strings a spell's `$d` prints: the English of `UIStrings.SPELL_DURATIONS`
# (INT_SPELL_DURATION_*, SPELL_DURATION_*, *_ABBR), both forms of each `|4one:many;`, which is exactly what
# `Align.durations` accepts. A number written in front of one is a duration to the addon, which copies every
# such phrase in reading order, so it takes a `$D<k>` index whether or not it came from `$d`. `test_align`
# checks this list against those strings so the two cannot drift apart. "lasts for 30 minutes" is not one:
# the friends-list forms are not a spell's, and the addon does not read them there.
DURATION_UNITS = ("sec", "Sec", "min", "Min", "hour", "hrs", "Hr", "day", "days", "Day", "Days")
UNIT = re.compile(r"\s+(?:" + "|".join(sorted(DURATION_UNITS, key=len, reverse=True)) + r")(?![A-Za-z])")
# a quest count code (`Collect $1oa Moss`) is one code: `VALUE_CODE` alone would stop at `$1o`
_QUEST_COUNT = re.compile(r"\$\d+oa(?![A-Za-z])")
_SLOT = re.compile("|".join(f"(?P<{k}>{r.pattern})" for k, r in (
    ("sum", SUM), ("counter", re.compile(r"\$\d+[wW](?![0-9])")), ("count", _QUEST_COUNT),
    ("code", VALUE_CODE),
    ("literal", LITERAL))))


@dataclass(frozen=True)
class Slot:
    """One number the client prints, in reading order. `kind`: `literal` (the English already shows it),
    `code` (a server code), `sum` (arithmetic) or `counter` (`$<n>w`, carried as the code). `duration`: the
    live line shows it as a duration phrase, so it also has a `$D` index. `client_unit`: a `$d` code; the
    client picks its unit, so only `$D<k>` may stand for it (ADR-028)."""

    kind: str
    duration: bool
    client_unit: bool


# A talent conditional `$?<cond>[A][B]` with no nested bracket. `<cond>` is an aura / spell / power
# test (`a14748`, `s18769`, `$p456322`).
_CONDITIONAL = re.compile(r"\$\?\$?[A-Za-z]+\d+\[([^\[\]]*)\]\[([^\[\]]*)\]")


# stands in for a literal that differs between branches: a code (`VALUE_CODE`), never a duration code
BRANCH_VALUE = "$v0"


def _tokens(branch: str) -> list[tuple[str, str]]:
    """A branch's value tokens as (kind, text), word codes (`$lsecond:seconds;`, `$g…;`) skipped."""
    masked = _NOT_VALUE.sub(lambda m: " " * len(m.group()), branch)
    return [(m.lastgroup or "literal", m.group()) for m in _SLOT.finditer(masked)]


def _residue(branch: str) -> str:
    """The branch verbatim with every value replaced by `#` (words, word codes, colour markup and line
    breaks kept, so only the numbers may differ), and a range `# to #` read as one value,
    as `slots` joins it."""
    parts, at = [], 0
    for m in _NOT_VALUE.finditer(branch):
        parts += [_SLOT.sub("#", branch[at:m.start()]), m.group()]
        at = m.end()
    parts.append(_SLOT.sub("#", branch[at:]))
    return "".join(parts).replace("# to #", "#")


_GLUE = re.compile(r"[A-Za-z0-9.,$]")


def _one_branch(en: str) -> str | None:
    """`en` with each conditional replaced by one branch, when both branches read the same apart from their
    numbers: `absorbing $?a14748[${$s1*(1+$14748s1/100)}][$s1] damage` prints one value either way, so the
    Japanese is right for both. `None` when any conditional's branches differ in anything else (words, a word
    code, colour, line breaks), in how many values they print or in which of those are durations: Fire Ward's
    `$?s11094[ and grants a $s2% chance…][]` adds a clause for one player only, and no wording is right both
    ways; Tiger's Fury's white and red "Requires Cat Form" says whether the requirement is met. Also
    `None` when a branch's number touches the text outside it (`Rank$?a1[2][3]`), which the client reads as
    part of a word. The branch kept is the one with fewer literal values."""
    def pick(m: re.Match[str]) -> str:
        a, b = m.group(1), m.group(2)
        sa, sb = _count(a), _count(b)
        if sa is None or sb is None or _residue(a) != _residue(b):
            raise ValueError
        if [(x.duration, x.client_unit) for x in sa] != [(x.duration, x.client_unit) for x in sb]:
            raise ValueError
        before = m.string[m.start() - 1] if m.start() else ""
        after = m.string[m.end()] if m.end() < len(m.string) else ""
        for branch in (a, b):
            if branch and ((branch[0].isdigit() and _GLUE.fullmatch(before or " ")) or
                           (branch[-1].isdigit() and _GLUE.fullmatch(after or " "))):
                raise ValueError
        literals = lambda s: sum(x.kind == "literal" for x in s)  # noqa: E731
        kept, other = (a, b) if literals(sa) <= literals(sb) else (b, a)
        if a == b:
            return kept
        # a number written into a branch (`$?a415096[20%][30%]`) is right for one player only, so where the
        # branches' numbers differ it is a value the client fills in and needs its placeholder; a number
        # both branches write alike stays a literal. The numbers inside a `${…}` sum or a code are part of
        # that value.
        theirs = _tokens(other)
        n = iter(range(len(_tokens(kept))))

        def swap(t: re.Match[str]) -> str:
            k = next(n)
            differs = len(theirs) != len(_tokens(kept)) or theirs[k][1] != t.group()
            return BRANCH_VALUE if t.lastgroup == "literal" and differs else t.group()

        masked = _NOT_VALUE.sub(lambda w: "\0" * len(w.group()), kept)
        out, at = [], 0
        for t in _SLOT.finditer(masked):
            out += [kept[at:t.start()], swap(t)]
            at = t.end()
        return "".join(out) + kept[at:]

    try:
        out = _CONDITIONAL.sub(pick, en)
    except ValueError:
        return None
    return None if UNCOUNTABLE.search(out) else out


def slots(en: str) -> list[Slot] | None:
    """The numbers the client will print for this English template, in reading order, or `None` when that
    cannot be known from the template alone (`UNCOUNTABLE`). `$N<k>` indexes all of them; `$D<k>` indexes the
    ones with `duration` set, the same two orders `Align.values` and `Align.durations` read the live
    line in. A conditional whose branches read the same apart from their numbers counts as one branch
    (`_one_branch`). A name-list tail prints names, never a number: only the head is counted."""
    en = split_tail(en or "")[0]
    if UNCOUNTABLE.search(en):
        one = _one_branch(en)
        if one is None:
            return None
        en = one
    return _count(en)


def _count(en: str) -> list[Slot] | None:
    if UNCOUNTABLE.search(en):
        return None
    rest = _NOT_VALUE.sub(" ", en)
    out: list[Slot] = []
    last_end = -1
    for m in _SLOT.finditer(rest):
        kind = m.lastgroup or "literal"
        if kind == "count":
            kind = "code"
        client_unit = kind == "code" and DURATION_CODE.fullmatch(m.group()) is not None
        duration = client_unit or UNIT.match(rest, m.end()) is not None
        if out and rest[last_end:m.start()] == " to ":
            # a range the client prints as one value, "14 to 22": `Align.values` joins it
            prev = out.pop()
            kind = "code" if "code" in (prev.kind, kind) or "sum" in (prev.kind, kind) else prev.kind
            out.append(Slot(kind, prev.duration or duration, prev.client_unit or client_unit))
        else:
            out.append(Slot(kind, duration, client_unit))
        last_end = m.end()
    return out


def value_slots(en: str) -> int | None:
    """How many numbers the client will print for this English template (`slots`), or `None`."""
    s = slots(en)
    return None if s is None else len(s)


def duration_slots(en: str) -> int | None:
    """How many durations the live line will show for this template (a `$d` code, or any number the English
    writes in front of a duration unit), or `None`. A draft indexes them with `$D<k>`; the addon copies the
    phrase, with the unit the client chose, out of the live line."""
    s = slots(en)
    return None if s is None else sum(1 for x in s if x.duration)


def duration_indices(ja: str) -> list[int]:
    """The `$D<k>` indices a Japanese line uses, in reading order."""
    return [int(m) for m in re.findall(r"\$D(\d+)", ja or "")]


# A quest's server counter is carried into the Japanese AS THE CODE (`$1997w`), so the client fills it
# there too; it is not a slot a drafter has to write a placeholder for. It still occupies a position in the
# live line's numbers, so `value_slots` keeps counting it.
COUNTER = re.compile(r"\$\d+[wW](?![0-9])")


def code_slots(en: str) -> int | None:
    """How many of a template's value slots come from a CODE rather than a literal the English already shows.
    Those are the ones the Japanese cannot state for itself (`Collect $1oa Lady's Tear Moss.` shows a count
    only the client knows), so each needs a `$N<k>` or `$D<k>`. A literal (`Kill 7 Nightsabers`) may be
    written as a literal instead, and a `$<n>w` counter is carried as the code. `None` when uncountable."""
    s = slots(en)
    return None if s is None else sum(1 for x in s if x.kind in ("code", "sum"))


def slot_problems(en: str, ja: str) -> list[str] | None:
    """Every code slot of the English must be carried by the placeholder that points at IT, not merely by
    the right number of placeholders. `$D1かけて体力を$N2回復` for `Restores $o1 health over $d` has two
    placeholders for two codes, yet drops `$o1` and shows the duration's number as the health.
    → reasons, `[]` when every code slot is carried; `None` when the template is uncountable.

    - `slot_missing:N<k>`: the k-th value is a code or sum and the Japanese has neither `$N<k>` nor, for a
      duration, its `$D<j>`;
    - `duration_as_value:N<k>`: `$N<k>` on a `$d`: the number without the unit the client chose (ADR-028);
    - `duration_missing:D<j>`: a `$d` whose `$D<j>` is absent."""
    s = slots(en)
    if s is None:
        return None
    ns, ds = set(fill_indices(ja)), set(duration_indices(ja))
    out: list[str] = []
    j = 0
    for k, x in enumerate(s, 1):
        if x.duration:
            j += 1
        if x.client_unit:
            if k in ns:
                out.append(f"duration_as_value:N{k}")
            if j not in ds:
                out.append(f"duration_missing:D{j}")
        elif x.kind in ("code", "sum") and k not in ns and not (x.duration and j in ds):
            out.append(f"slot_missing:N{k}")
    return out


# ---------------------------------------------------------------------------------------------------------
# Templates (ADR-043) that include another spell's text, and templates that branch.
#
# INCLUSIONS. `$@spelldesc<id>` splices spell <id>'s description into the line the client shows, rendered with
# that spell's own values (`$@spelltooltip<id>`: its aura text; `$@spellname<id>`: its name). The line a
# player reads is therefore the spliced text, and so is the line `Align.values` reads in game, so the draft
# translates the spliced English (`expand_inclusions`) and counts its slots like any other template. An inline
# icon (`$@spellicon<id>`) becomes `$I<k>`, which the addon fills with the k-th `|T…|t` escape of the live
# line.
#
# BRANCHES. `$?<cond>[A][B]` (and chains `$?c1[A]?c2[B][C]`) print one branch, chosen by the client. The
# Japanese keeps the same skeleton; `generate` ships one Japanese per branch combination (a *variant*), each
# renumbered to its own reading order, with its *shape* (`<values>/<durations>`, what `Align.values` and
# `Align.durations` read off a live line showing that variant). The addon shows the one variant that fits
# the live line and nothing when none or several do (`Align.checkVariants`). It never evaluates the
# condition itself.

INCLUSION = re.compile(r"\$@([A-Za-z]+)(\d+)")
_INCLUDED_FIELD = {"spelldesc": "description", "spelltooltip": "aura", "spellname": "name"}
MAX_INCLUDE_DEPTH = 4
MAX_VARIANTS = 16


@dataclass(frozen=True)
class Expansion:
    """`text`: the template with every inclusion spliced in, or None; `reason` says why not."""

    text: str | None
    reason: str | None = None


class _Stop(Exception):
    pass


def expand_inclusions(en: str, spell_english: Mapping[tuple[int, str], str]) -> Expansion:
    """`en` with `$@spelldesc<id>` / `$@spelltooltip<id>` replaced by that spell's description / aura English
    (recursively, `MAX_INCLUDE_DEPTH` deep), `$@spellname<id>` by its English name, and each `$@spellicon<id>`
    by `$I1`, `$I2`… in reading order. `spell_english` maps (spell id, field) → raw English. A spell the
    tables lack, a cycle, too deep a chain or any other `$@` code (`$@auracaster`: the caster's name) →
    `Expansion(None, reason)`: the line stays English, listed with that reason."""
    icons = 0

    def walk(text: str, depth: int, seen: frozenset[int]) -> str:
        nonlocal icons
        out: list[str] = []
        at = 0
        for m in INCLUSION.finditer(text):
            out.append(text[at:m.start()])
            at = m.end()
            code, sid = m.group(1).lower(), int(m.group(2))
            if code == "spellicon":
                icons += 1
                out.append(f"$I{icons}")
                continue
            field_name = _INCLUDED_FIELD.get(code)
            if field_name is None:
                raise _Stop(f"unsupported_code:$@{m.group(1)}")
            if sid in seen:
                raise _Stop(f"inclusion_cycle:{sid}")
            if depth >= MAX_INCLUDE_DEPTH:
                raise _Stop("inclusion_depth")
            sub = spell_english.get((sid, field_name))
            if sub is None or not sub.strip():
                raise _Stop(f"missing_included_spell:{sid}")
            out.append(sub.strip() if field_name == "name" else walk(sub, depth + 1, seen | {sid}))
        out.append(text[at:])
        return "".join(out)

    try:
        text = walk(en or "", 0, frozenset())
    except _Stop as e:
        return Expansion(None, str(e))
    left = re.search(r"\$@[A-Za-z]*", text)
    if left:
        return Expansion(None, f"unsupported_code:{left.group()}")
    return Expansion(text)


def included_spells(en: str, spell_english: Mapping[tuple[int, str], str]) -> list[tuple[int, str]]:
    """Every (spell id, field) `en` splices in, nested inclusions too, in first-seen order: the English a
    change to which must make the line stale (`check`). A spell the tables lack is listed as well."""
    out: list[tuple[int, str]] = []

    def walk(text: str, depth: int) -> None:
        for m in INCLUSION.finditer(text):
            field_name = _INCLUDED_FIELD.get(m.group(1).lower())
            key = (int(m.group(2)), field_name or "")
            if field_name is None or key in out:
                continue
            out.append(key)
            sub = spell_english.get(key)
            if sub and field_name != "name" and depth < MAX_INCLUDE_DEPTH:
                walk(sub, depth + 1)

    walk(en or "", 0)
    return out


def icon_indices(text: str) -> list[int]:
    """The `$I<k>` indices a line uses, in reading order."""
    return [int(k) for k in ICON.findall(text or "")]


@dataclass(frozen=True)
class _Cond:
    """One conditional: `conds[i]` guards `branches[i]`; the last branch is the else (possibly empty)."""

    id: int
    conds: tuple[str, ...]
    branches: tuple[tuple, ...]  # each a sequence of str | _Cond


_CHAIN = re.compile(r"\?([^\s\[\]?]+)\[")
_OPEN = re.compile(r"\$\?([^\s\[\]]+)\[")


def parse_branches(text: str) -> tuple | None:
    """`text` as a sequence of plain strings and conditionals, or None when a bracket does not close or stands
    where no conditional puts one (a `[` inside a branch, a `]` outside every branch)."""
    counter = [0]

    def seq(i: int, nested: bool) -> tuple[list, int]:
        out: list = []
        buf: list[str] = []
        while i < len(text):
            if nested and text[i] == "]":
                break
            if text[i] == "]" or (nested and text[i] == "["):
                raise _Stop("stray bracket")  # `[` inside a branch, `]` outside one: not a shape read here
            m = _OPEN.match(text, i)
            if m:
                if buf:
                    out.append("".join(buf))
                    buf = []
                node, i = cond(m)
                out.append(node)
                continue
            buf.append(text[i])
            i += 1
        else:
            if nested:
                raise _Stop("unclosed")
        if buf:
            out.append("".join(buf))
        return out, i

    def cond(m: re.Match[str]) -> tuple[_Cond, int]:
        node_id = counter[0]
        counter[0] += 1
        conds, branches = [m.group(1)], []
        body, i = seq(m.end(), True)
        branches.append(tuple(body))
        i += 1  # the "]"
        while True:
            c = _CHAIN.match(text, i)
            if not c:
                break
            conds.append(c.group(1))
            body, i = seq(c.end(), True)
            branches.append(tuple(body))
            i += 1
        if i < len(text) and text[i] == "[":
            body, i = seq(i + 1, True)
            branches.append(tuple(body))
            i += 1
        else:
            branches.append(())
        return _Cond(node_id, tuple(conds), tuple(branches)), i

    try:
        out, _ = seq(0, False)
    except _Stop:
        return None
    return tuple(out)


def _skeleton(parts: tuple) -> tuple:
    return tuple((p.conds, tuple(_skeleton(b) for b in p.branches)) for p in parts if isinstance(p, _Cond))


def _combos(parts: tuple) -> list[tuple[frozenset[tuple[int, int]], str]]:
    """Every branch combination of `parts`: (the chosen (conditional id, branch) pairs, the text)."""
    results: list[tuple[frozenset[tuple[int, int]], str]] = [(frozenset(), "")]
    for p in parts:
        if isinstance(p, str):
            results = [(c, t + p) for c, t in results]
            continue
        opts = [
            (frozenset({(p.id, bi)}) | c2, t2)
            for bi, br in enumerate(p.branches)
            for c2, t2 in _combos(br)
        ]
        results = [(c | oc, t + ot) for c, t in results for oc, ot in opts]
        if len(results) > MAX_VARIANTS:
            raise _Stop("too_many_variants")
    return results


def _segments(parts: tuple, path: frozenset[tuple[int, int]] = frozenset()
              ) -> list[tuple[str, frozenset[tuple[int, int]]]]:
    """The template's text in reading order, every branch included, each piece with the choices it needs."""
    out: list[tuple[str, frozenset[tuple[int, int]]]] = []
    for p in parts:
        if isinstance(p, str):
            out.append((p, path))
        else:
            for bi, br in enumerate(p.branches):
                out += _segments(br, path | {(p.id, bi)})
    return out


@dataclass(frozen=True)
class Variant:
    """One branch combination: `choice` the (conditional id, branch) pairs, `en` its English, `values` /
    `durations` the whole-template `$N` / `$D` indices it prints in reading order, `shape` what a live line
    showing it reads as (`<values>/<durations>`)."""

    choice: frozenset[tuple[int, int]]
    en: str
    values: tuple[int, ...]
    durations: tuple[int, ...]
    icons: tuple[int, ...] = ()  # the whole-template `$I` indices it shows; `en` is renumbered to 1..k

    @property
    def shape(self) -> str:
        return f"{len(self.values)}/{len(self.durations)}"


@dataclass(frozen=True)
class Branching:
    """A branch template: its `variants`, the whole-template `slots` / `durations` counts (every branch's
    values, reading order: the numbering a draft's `$N<k>` / `$D<k>` use), the skeleton. `reason` (and no
    variants) when it cannot be written: `unclosed_branch`, `too_many_variants`, `branch_slots_unclear` (a
    branch's values read differently alone than in the line: a number glued across a bracket)."""

    variants: tuple[Variant, ...] = ()
    slots: int = 0
    durations: int = 0
    skeleton: tuple = ()
    reason: str | None = None
    code_values: tuple[int, ...] = field(default=())
    # a SECTIONED line (see `_sectioned_combos`): its variants are the heading alone, then the heading with
    # each optional paragraph, in order; the addon shows it paragraph by paragraph (`Align.sections`)
    sectioned: bool = False


def has_branches(en: str) -> bool:
    return _OPEN.search(en or "") is not None


def branching(en: str) -> Branching:
    """The branch combinations of a template with at least one `$?` conditional (see the section comment)."""
    parts = parse_branches(en or "")
    if parts is None:
        return Branching(reason="unclosed_branch")
    sectioned = False
    try:
        combos = _combos(parts)
    except _Stop as e:
        combos = _sectioned_combos(parts) if str(e) == "too_many_variants" else None
        if combos is None:
            return Branching(reason=str(e))
        sectioned = True
    segs = _segments(parts)
    counted: list[tuple[frozenset[tuple[int, int]], list[Slot]]] = []
    for text, path in segs:
        s = _count(text)
        if s is None:
            return Branching(reason="branch_slots_unclear")
        counted.append((path, s))
    full: list[tuple[frozenset[tuple[int, int]], Slot]] = [(path, x) for path, s in counted for x in s]
    d_of: list[int | None] = []
    j = 0
    for _, x in full:
        if x.duration:
            j += 1
            d_of.append(j)
        else:
            d_of.append(None)
    variants: list[Variant] = []
    for choice, raw in combos:
        # an empty branch leaves two spaces where the English had one on each side (`$d. $?s1[…][] Must`),
        # which the paragraph count reads as a break; the variant is read as the drafter reads English
        text = _SPACE_RUN.sub(" ", raw)
        active = [k for k, (path, _) in enumerate(full, 1) if path <= choice]
        own = _count(text)
        if own is None or [(x.kind, x.duration, x.client_unit) for x in own] != [
            (full[k - 1][1].kind, full[k - 1][1].duration, full[k - 1][1].client_unit) for k in active
        ]:
            return Branching(reason="branch_slots_unclear")
        durs = tuple(d for k in active if (d := d_of[k - 1]) is not None)
        if not text.strip():
            # the whole line sits in a conditional and this branch is empty: the client prints no line, the
            # tooltip surface refuses an empty one, and an empty Japanese would pass the gate on every line
            continue
        icons = tuple(icon_indices(text))
        imap = {k: i for i, k in enumerate(icons, 1)}
        text = ICON.sub(lambda m, imap=imap: f"$I{imap[int(m.group(1))]}", text)
        variants.append(Variant(choice, text, tuple(active), durs, icons))
    code_values = tuple(k for k, (_, x) in enumerate(full, 1) if x.kind in ("code", "sum"))
    return Branching(tuple(variants), len(full), j, _skeleton(parts), None, code_values, sectioned)


# SECTIONED lines. A heading paragraph followed by optional paragraphs, each its own `$?<cond>[<paragraph>][]`
# with an empty else (the Camp Benefits aura: "Tent: …", "Mana Well: …", one per camp item the player has),
# has 2^n combinations: too many to ship, and many show the same values, so the addon could not tell them
# apart. Each optional paragraph begins with words of its own before its first value ("Tent: You received"),
# so the addon recognises it by those words (their hash, never the English) and shows it on its own. Such a
# line is drafted like any branch line; its variants are the heading alone, then the heading with each
# paragraph alone.
SECTION_PREFIX_MIN = 6
_BREAK_END = re.compile(r"(?:\r?\n|\$[Bb]){2,}$")


def _sectioned_combos(parts: tuple) -> list[tuple[frozenset[tuple[int, int]], str]] | None:
    """The heading-alone and heading-plus-one-paragraph combinations of a SECTIONED template, or None when
    the template does not have that shape: a heading with no code, then conditionals each with exactly one
    non-empty branch that is one whole paragraph (it ends in a paragraph break and holds no conditional) and
    begins with words before its first code."""
    if not parts or not isinstance(parts[0], str) or "$" in parts[0] or not _BREAK_END.search(parts[0]):
        return None
    conds = []
    for p in parts[1:]:
        if isinstance(p, str):
            if p.strip():
                return None
            continue
        branch = p.branches[0] if len(p.branches) == 2 and not p.branches[1] else ()
        if len(branch) != 1 or not isinstance(branch[0], str):
            return None
        if len(section_prefix(branch[0])) < SECTION_PREFIX_MIN:
            return None
        conds.append(p)
    # every paragraph but the last ends in a break: the next one starts a paragraph of its own
    if any(not _BREAK_END.search(c.branches[0][0]) for c in conds[:-1]):
        return None
    if len(conds) < 2:
        return None
    off = frozenset((c.id, 1) for c in conds)
    out = [(off, parts[0])]
    for c in conds:
        out.append(((off - {(c.id, 1)}) | {(c.id, 0)}, parts[0] + c.branches[0][0]))
    return out


def section_prefix(body: str) -> str:
    """The words a section paragraph begins with before its first code: what the addon recognises it by."""
    head = body.split("$", 1)[0]
    return head if re.search(r"[A-Za-z]{2}", head) else ""


def _text_of(parts: tuple, choice: frozenset[tuple[int, int]]) -> str:
    """The text of one branch combination of `parts`."""
    out = []
    for p in parts:
        if isinstance(p, str):
            out.append(p)
            continue
        for bi, br in enumerate(p.branches):
            if (p.id, bi) in choice:
                out.append(_text_of(br, choice))
    return "".join(out)


_PLACE = re.compile(r"\$([NDI])(\d+)")
_SPACE_RUN = re.compile(r"[ \t]{2,}")


def ja_variants(ja: str, b: Branching) -> tuple[list[str] | None, list[str]]:
    """The Japanese of each of `b`'s variants, renumbered (`$N` / `$D` / `$I`) to that variant's own reading
    order. → (texts in
    `b.variants` order, []) or (None, reasons): `branch_skeleton` (not the English's conditionals, in the
    same order, with the same conditions and branch counts), `branch_index:<N|D><k>` (a placeholder for a
    value that variant does not print: written in the wrong branch, or past the whole template)."""
    parts = parse_branches(ja or "")
    if parts is None or _skeleton(parts) != b.skeleton:
        return None, ["branch_skeleton"]
    if b.sectioned:
        texts = {v.choice: _text_of(parts, v.choice) for v in b.variants}
    else:
        try:
            texts = dict(_combos(parts))
        except _Stop:
            return None, ["branch_skeleton"]
    out: list[str] = []
    bad: list[str] = []
    for v in b.variants:
        maps = {
            "N": {k: i for i, k in enumerate(v.values, 1)},
            "D": {k: i for i, k in enumerate(v.durations, 1)},
            "I": {k: i for i, k in enumerate(v.icons, 1)},
        }

        def sub(m: re.Match[str], maps: dict[str, dict[int, int]] = maps) -> str:
            kind, k = m.group(1), int(m.group(2))
            table = maps[kind]
            if k not in table:
                bad.append(f"branch_index:{kind}{k}")
                return m.group()
            return f"${kind}{table[k]}"

        out.append(_PLACE.sub(sub, texts[v.choice]))
    if bad:
        return None, list(dict.fromkeys(bad))
    return out, []


_CAPITALISED = re.compile(r"[A-Z][A-Za-z'’\-]{2,}(?: [A-Z][A-Za-z'’\-]*)*")


def indistinguishable(texts: list[str], scopes: list[str], shapes: list[str], allowlist: set[str],
                      *, english: bool = False) -> list[tuple[int, int]]:
    """Pairs (a, b): `a` is *shadowed* by `b`: with variant `a` on screen (its English `scopes[a]`),
    variant `b`'s text `texts[b]` would pass the addon's gate as well: the same shape (or all shapes alike,
    when the addon does not compare them), no name `b` writes that `a`'s English lacks, and no literal number
    `b` writes that it lacks. Two variants whose text and shape are identical are one. `english=True` reads
    `texts` as English (the pre-draft check `cut` runs): only capitalised runs count as names there, since
    every English word is a Latin run."""
    compare_shapes = len(set(shapes)) > 1
    out: list[tuple[int, int]] = []
    for a in range(len(texts)):
        for b in range(len(texts)):
            if a == b or (texts[a] == texts[b] and shapes[a] == shapes[b]):
                continue
            if compare_shapes and shapes[a] != shapes[b]:
                continue
            if english:
                scope = scopes[a].casefold()
                names = _CAPITALISED.findall(_NOT_VALUE.sub(" ", texts[b]))
                if any(n.casefold() not in scope for n in names):
                    continue
            elif check_names(ICON.sub(" ", texts[b]), scopes[a], allowlist)[1]:
                continue
            if check_numbers(texts[b], SUM.sub(" ", scopes[a]))[1]:
                continue
            out.append((a, b))
    return out


def unsafe_shadow(pairs: list[tuple[int, int]], texts: list[str]) -> bool:
    """A shadowed variant `a` that carries an icon or a duration its shadower `b` lacks: should `a`'s `$I` or
    `$D` fail to fill on its own line (an icon the client does not print as `|T…|t`, a duration the UI strings
    do not know), `b` would pass there alone and show the wrong branch. Such a line is refused."""
    for a, b in pairs:
        if set(ICON.findall(texts[a])) - set(ICON.findall(texts[b])):
            return True
        if set(re.findall(r"\$D(\d+)", texts[a])) - set(re.findall(r"\$D(\d+)", texts[b])):
            return True
    return False


def never_shown(pairs: list[tuple[int, int]], n: int) -> bool:
    """Every one of the `n` variants is shadowed: another passes the gate on its line too, so the addon
    would show nothing for any of them (`Align.checkVariants` wants exactly one). Only then is a branch line
    refused:
    a shadowed variant costs its players the Japanese (they see the English), never the wrong text, and it
    still ships; dropped, the variant that shadows it would pass alone on its line and show the wrong
    branch."""
    return n > 0 and len({a for a, _ in pairs}) == n
