"""Format specifiers in Blizzard UI strings (ADR-014). Pure.

A UI template such as `ITEM_MIN_LEVEL = "Requires Level %d"` is filled by the client with `format()`. The
addon matches the live line against the English template and fills the Japanese template with the captured
values, so the Japanese must carry exactly the same arguments: the same count, each with the same conversion.
Word order may move an argument, written as a positional specifier (`%2$s`). `%%` is a literal percent sign.
"""

from __future__ import annotations

import re

# `%.f` is valid (Lua twin agrees). A lone space flag whose conversion runs straight into a letter
# ("above 100% is for") is prose, not a specifier; the Lua twin (Core/UIStrings.parse) agrees.
SPEC = re.compile(r"%(?:(\d+)\$)?((?! [sdcfgi][A-Za-z])[-+ #0]*\d*(?:\.\d*)?[sdcfgi])|%%")


def parse(text: str) -> list[tuple[int, str]]:
    """Arguments as (1-based argument index, conversion with its flags and precision), in reading order.

    A plain specifier takes the next argument; `%N$` names argument N. Raises ValueError when a string mixes
    both styles (the client's `format` cannot fill that reliably)."""
    out: list[tuple[int, str]] = []
    plain = positional = 0
    for m in SPEC.finditer(text):
        if m.group(0) == "%%":
            continue
        if m.group(1):
            positional += 1
            out.append((int(m.group(1)), m.group(2)))
        else:
            plain += 1
            out.append((plain, m.group(2)))
    if plain and positional:
        raise ValueError("mixes plain and positional specifiers")
    return out


def signature(text: str) -> list[tuple[int, str]]:
    """The argument set of a template, independent of reading order."""
    return sorted(parse(text))


def mismatch(en: str, ja: str) -> str | None:
    """None when the Japanese template takes exactly the English template's arguments, else a short reason
    (used as `specifiers_changed:<reason>`)."""
    try:
        want = signature(en)
    except ValueError as exc:
        return f"en {exc}"
    try:
        got = signature(ja)
    except ValueError as exc:
        return f"ja {exc}"
    if want == got:
        return None

    def show(sig: list[tuple[int, str]]) -> str:
        return " ".join(f"%{i}${c}" for i, c in sig) or "none"

    return f"en[{show(want)}] ja[{show(got)}]"
