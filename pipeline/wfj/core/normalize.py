"""normalize_v1: the single text canon shared with the addon (ADR-005).

The Lua twin is addon/WoWForeverJapanese/Core/Normalize.lua. Every step here has a
byte-identical counterpart there; vectors/hash_vectors.jsonl is the contract.

Steps, in order:
 1. Unicode NFC  (Python only: WoW text is NFC already; the client cannot normalize.
    Inputs that are not NFC are canonicalised here so the repo side never depends on it.)
 2. Strip WoW markup: |H…|h<label>|h → label · |T…|t → '' · |cXXXXXXXX → '' · |r → '' · |n → newline
 3. $B / $b → newline
 4. Full-width digits → ASCII digits
 5. Blizzard placeholders: $N/$n → {name} · $C/$c → {class} · $R/$r → {race} · $G<a>:<b>; / $g → <a> (trimmed)
    Only for text the SERVER writes (quests, gossip, books), where those codes really
    are the player. In a CLIENT template (an item or spell tooltip) the same letters are value codes the
    client fills with numbers: `Fear all Demons within $r yards` is a radius, `surrounded by $n balls of
    lightning` is a count. `player_tokens=False` leaves them alone. The gender code is resolved
    either way; it means the same thing in both.
 6. Client-side only (player given): whole-word, exact-case replacement of the player's
    name / class / race by the same placeholders (tokens shorter than 3 code points are never replaced)
 7. Collapse every run of ASCII whitespace to one space; strip ASCII spaces at both ends
    (Unicode whitespace such as U+3000 / U+00A0 is preserved everywhere; both sides agree)
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass

NORM_VERSION = "v1"
MIN_TOKEN_LEN = 3  # code points (the Lua twin counts UTF-8 lead bytes)

_RE_LINK = re.compile(r"\|H[^|]*\|h(.*?)\|h", re.S)
_RE_TEX = re.compile(r"\|T[^|]*\|t")
_RE_COLOR = re.compile(r"\|c[0-9A-Fa-f]{8}")
# A branch is trimmed: the client shows `$g lad : lass;?` as "lad?" (traced in game, ADR-059), so the spaces a
# source writes around a branch are not part of the text.
_RE_GENDER = re.compile(r"\$[Gg]\s*([^:;]*?)\s*:[^;]*;")
_RE_GENDER_BOTH = re.compile(r"\$[Gg][^:;]*:\s*([^;]*?)\s*;")  # the second (female) branch, female_variant only
_RE_WS = re.compile(r"[ \t\r\n\f\v]+")
_FW_DIGITS = {ord(c): str(i) for i, c in enumerate("０１２３４５６７８９")}
_PLACEHOLDERS = (
    ("$N", "{name}"), ("$n", "{name}"),
    ("$C", "{class}"), ("$c", "{class}"),
    ("$R", "{race}"), ("$r", "{race}"),
)


@dataclass(frozen=True)
class Player:
    name: str = ""
    class_: str = ""
    race: str = ""


def _is_letter(ch: str) -> bool:
    return ch.isascii() and ch.isalpha()


def replace_word(text: str, token: str, placeholder: str) -> str:
    """Replace whole-word, exact-case occurrences of token. Boundaries are ASCII letters:
    "Reyn's" → "{name}'s" (apostrophe is not a letter); "Marketplace" keeps "Mark"."""
    if len(token) < MIN_TOKEN_LEN:  # code points
        return text
    out, i, n, t = [], 0, len(text), len(token)
    while i < n:
        j = text.find(token, i)
        if j < 0:
            out.append(text[i:])
            break
        before_ok = j == 0 or not _is_letter(text[j - 1])
        after_ok = j + t >= n or not _is_letter(text[j + t])
        out.append(text[i:j])
        if before_ok and after_ok:
            out.append(placeholder)
        else:
            out.append(token)
        i = j + t
    return "".join(out)


def normalize_v1(raw: str, player: Player | None = None, *, player_tokens: bool = True) -> str:
    """The canon (see the module docstring). `player_tokens=False` skips step 5's `$N`/`$C`/`$R` mapping,
    for a client template whose `$n` / `$c` / `$r` are values the client fills in rather than the player.
    The addon never needs it: by the time it sees an item or spell line the client has already
    resolved every code, so no live text reaches `Core/Normalize.lua` with one in it, which is why the Lua
    twin has no counterpart and `vectors/hash_vectors.jsonl` still covers the whole contract."""
    s = unicodedata.normalize("NFC", raw)
    s = _RE_LINK.sub(r"\1", s)
    s = _RE_TEX.sub("", s)
    s = _RE_COLOR.sub("", s)
    s = s.replace("|r", "")
    s = s.replace("|n", "\n")
    s = s.replace("$B", "\n").replace("$b", "\n")
    s = s.translate(_FW_DIGITS)
    s = _RE_GENDER.sub(r"\1", s)
    if player_tokens:
        for token, ph in _PLACEHOLDERS:
            s = s.replace(token, ph)
    if player is not None:
        for token, ph in ((player.name, "{name}"), (player.class_, "{class}"), (player.race, "{race}")):
            if token:
                s = replace_word(s, token, ph)
    return _RE_WS.sub(" ", s).strip(" ")  # ASCII space only: the Lua twin cannot strip Unicode whitespace


# A quest line whose Japanese is filled from the live values (`Collect $1oa Moss` → `$N1`) is hashed
# with every number masked, on both sides: here the server's count code and any digit run become `#`, and
# the addon masks the digit runs of the live line the same way (`Collector.fingerprints(…, masked)`). The
# count then cannot make the live check fail, and a rewording still does. ASCII digits only, as Lua's `%d`.
# a server code led by a digit (`$1oa`, `$1997w`) or a number, `1,000` and `2.5` included, is ONE `#`
_RE_VALUES = re.compile(r"\$[0-9]+[A-Za-z]*|[0-9](?:[0-9.,]*[0-9])?")


def mask_values(norm: str) -> str:
    """A normalized text with every number (a server count code or a digit run) replaced by `#`."""
    return _RE_VALUES.sub("#", norm)


# The types whose English is a CLIENT template: there `$n` / `$c` / `$r` are values the client fills in
# (`within $r yards` is a radius), not the player. One place decides it, so the hash, the batch
# English and every check read the same text.
CLIENT_TYPES = frozenset({"item", "spell", "ui"})


def normalize_for(type_: str, raw: str) -> str:
    """`normalize_v1` with the canon for `type_`: a client template keeps its `$n` / `$c` / `$r`."""
    return normalize_v1(raw, player_tokens=type_ not in CLIENT_TYPES)


def female_variant(raw: str) -> str | None:
    """The English as the client shows it to a female character: every `$G<male>:<female>;` resolved
    to its second branch, written literally. None when the text has no gender code. normalize_v1
    of the result is the key the addon computes from a female character's live English; normalize_v1
    itself keeps the first branch, and the Lua twin needs no counterpart: the client resolves the code
    before the addon sees it."""
    if not _RE_GENDER_BOTH.search(raw):
        return None
    # markup first, in normalize_v1's order: a link or texture carries a `:` that would split the code
    s = _RE_TEX.sub("", _RE_LINK.sub(r"\1", raw))
    s = _RE_COLOR.sub("", s).replace("|r", "")
    return _RE_GENDER_BOTH.sub(lambda m: m.group(1), s)
