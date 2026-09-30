"""Player tokens in the Japanese corpus. Pure.

The human quest corpus keeps the predecessor's tokens literally in `ja`; the addon expands them when the
Japanese is applied (`Core/Placeholders.lua`). Tokens stay literal in `data/`. This module is the pipeline's
view of the same vocabulary: what counts as a token, which ones the addon knows, and which are unknown
(validate).

- `{word}`: `name`, `class`, `race` are known; anything else between braces (`{foo}`, `{name1}`, `{ name }`,
  `{名前}`) is unknown: the addon leaves it literal
- `<a/b>`: an English gender word pair (ASCII words), expanded by the player's sex; any other `<x/y>` pair
  (`<閣下/ご婦人>`, `<Mr./Ms.>`) is not expanded and would show both forms
"""

from __future__ import annotations

import re

KNOWN: tuple[str, ...] = ("name", "class", "race")
_BRACES = re.compile(r"\{([^{}\n]*)\}")
_PAIR = re.compile(r"<([A-Za-z]+)/([A-Za-z]+)>")
_ANY_PAIR = re.compile(r"<[^<>/\n]+/[^<>/\n]+>")


def tokens(ja: str | None) -> list[str]:
    """Every token in `ja`, as a display key: `{name}`, `{foo}` … or `<a/b>` for an ASCII gender pair."""
    ja = ja or ""
    return [f"{{{w}}}" for w in _BRACES.findall(ja)] + ["<a/b>"] * len(_PAIR.findall(ja))


def unknown(ja: str | None) -> list[str]:
    """What the addon would render literally: brace tokens outside KNOWN, and `<x/y>` pairs it cannot
    expand."""
    ja = ja or ""
    bad = [f"{{{w}}}" for w in _BRACES.findall(ja) if w not in KNOWN]
    bad += [m for m in _ANY_PAIR.findall(ja) if not _PAIR.fullmatch(m)]
    return bad
