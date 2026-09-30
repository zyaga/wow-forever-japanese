"""The English of a line as a drafter reads it (`model_english`). Pure. Lives in `core` so `generate` (a
branch line's English is split into variants there) and the batch tools read one canon; re-exported by
`wfj.dev.translate_batch`."""

from __future__ import annotations

import re

PARA = "\n\n"
_BREAKS = re.compile(r"[ \t]*(?:\$[Bb][ \t]*)+")
# a client template's `$b<k>` is a value (points per combo point: `a $b1% chance`), not a break
_CLIENT_BREAKS = re.compile(r"[ \t]*(?:\$[Bb](?!\d)[ \t]*)+")
_SPACES = re.compile(r"[ \t]+")
_TOKENS = (("$N", "{name}"), ("$n", "{name}"), ("$C", "{class}"), ("$c", "{class}"), ("$R", "{race}"),
           ("$r", "{race}"))

def model_english(raw: str, *, player_tokens: bool = True) -> str:
    """The English as a drafter sees it: `$B` runs → a paragraph break, `$N/$C/$R` → `{name}/{class}/{race}`
    (the tokens the addon expands), space runs collapsed. `$G male:female;` stays literal: the Japanese is
    written gender-neutral instead (the addon cannot expand a Japanese pair).

    `player_tokens=False` for a CLIENT template, whose `$n` / `$c` / `$r` are values the client fills in and
    not the player: `within $r yards` is a radius, `$n balls of lightning` a count. It matches the
    canon the English was hashed under (`import_english._client_hash`), so what the drafter reads is what the
    store holds, and those codes are then counted as the value slots they are. There a `$b<k>`
    is a value too (`a $b1% chance`), so only a `$b` with no digit after it is a break."""
    s = (_BREAKS if player_tokens else _CLIENT_BREAKS).sub(PARA, raw)
    if player_tokens:
        for token, placeholder in _TOKENS:
            s = s.replace(token, placeholder)
    s = _SPACES.sub(" ", s)
    return PARA.join(p.strip() for p in s.split(PARA) if p.strip())
