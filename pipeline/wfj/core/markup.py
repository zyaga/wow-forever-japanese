"""Markup tokens in Blizzard UI strings (ADR-016). Pure.

A UI template may carry colour codes (`|cAARRGGBB` … `|r`), line breaks (`\n`, and the escape `|n`),
textures (`|T<path>:<size>…|t`) and plural grammar (`|4singular:plural;`). The client prints
colours, breaks and textures as they are, so the Japanese must keep exactly the same colour tokens, line
breaks and textures (same multiset; a texture verbatim, path and size included). Plural grammar is
English-only: the Japanese may drop a `|4…;` group (the specifier it follows stays,
`specifiers.mismatch`), and one it keeps must be well-formed.
A link (`|H…|h<label>|h`) is kept verbatim too, as one token: only a static one is listed (the
code-of-conduct notice's URL; tests/python/test_ui_keys.py). An atlas texture (`|A<atlas>…|a`) is
kept verbatim like a file texture, and a named colour opener (`|cnNAME:`) is counted like a hex one,
its name verbatim; a bare `|cn` or an unclosed `|A…` is a token too, as written. `|K` and `$` tokens stay out
of the dictionary by curation.
"""

from __future__ import annotations

import re
from collections import Counter

HTML_TAG = re.compile(r"<\s*(/?)\s*([A-Za-z0-9]+)([^>]*)>")
LINK = re.compile(r"\|H[^|]*\|h.*?\|h", re.S)
# A malformed named-colour opener (`|cn` with no `NAME:`) or an atlas with no closing `|a` is still a
# token, counted as written: a Japanese that drops or breaks one differs from the
# English.
TOKEN = re.compile(
    r"\|c[0-9a-fA-F]{8}|\|cn[A-Za-z0-9_]+:|\|cn|\|r|\n|\|n|\|T[^|]*\|t|\|A[^|]*\|a|\|A[^|]*"
)
VERBATIM = ("|T", "|A", "|cn")  # textures, atlases and named colours are counted as written
PLURAL = re.compile(r"\|4[^:;|]*:[^;|]*;")
ADJACENT_GAP = re.compile(r"\s*")


def tokens(text: str) -> Counter:
    """Links, textures, atlases and named colour openers (verbatim), hex colour tokens (with their 8 hex
    digits, lower-cased) and line breaks, counted."""
    links = LINK.findall(text)  # a whole link, verbatim; the colours inside it are part of it
    rest = LINK.sub("", text)
    return Counter(links) + Counter(t if t.startswith(VERBATIM) else t.lower() for t in TOKEN.findall(rest))


def plural_malformed(text: str) -> bool:
    """True when a `|4` does not start a well-formed `|4singular:plural;` group."""
    return text.count("|4") != len(PLURAL.findall(text))


def plural_groups(text: str) -> int:
    return len(PLURAL.findall(text))


def mismatch(en: str, ja: str) -> str | None:
    """None when the Japanese keeps the English's colour tokens and line breaks and any plural group it
    carries is well-formed, else a short reason (used as `markup_changed:<reason>`)."""
    if plural_malformed(ja):
        return "ja malformed |4 group"
    want, got = tokens(en), tokens(ja)
    if want == got:
        return None

    def show(c: Counter) -> str:
        return " ".join(f"{t.encode('unicode_escape').decode()}x{n}" for t, n in sorted(c.items())) or "none"

    return f"en[{show(want)}] ja[{show(got)}]"


def html_tags(text: str) -> list[str]:
    """The HTML tags of a book page in order, as `<name attrs>` with the name upper-cased and the
    attributes whitespace-collapsed; `<BR/>` and `<BR></BR>` stay distinct, as the English wrote them."""
    return [
        f"<{close}{name.upper()}{' ' + ' '.join(attrs.split()) if attrs.strip() else ''}>"
        for close, name, attrs in HTML_TAG.findall(text)
    ]


def is_html_page(text: str) -> bool:
    """A book page the client renders as HTML: it starts with `<HTML`. Plain pages may carry
    bracketed prose such as `<illegible text>`, which is not markup."""
    return text.lstrip().upper().startswith("<HTML")


def html_mismatch(en: str, ja: str) -> str | None:
    """None when the English is not an HTML page, or the Japanese carries the same tags in the same order;
    else the first difference (used as `markup_changed:html:<reason>`). A book page's SimpleHTML renders the
    tags, so a Japanese that drops or reorders one would show broken markup."""
    if not is_html_page(en):
        return None
    want = html_tags(en)
    got = html_tags(ja)
    if want == got:
        return None
    for i, (w, g) in enumerate(zip(want, got, strict=False)):
        if w != g:
            return f"tag {i + 1}: en {w} ja {g}"
    return f"en {len(want)} tags ja {len(got)}"
