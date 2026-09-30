"""What may not appear in the public repository, and how to find it.

Pure functions over text; `wfj public-check` (cmd/public_check.py) walks the tracked files and applies them.

Three families of checks:

- content: paths on the author's machine (home folders, external drives) and tracker ids, plus the private
  rules kept outside the repository (`PrivateRules`): more patterns, and words, names and addresses that
  must not be published. The repository holds the mechanism only; without a rules file those rules are empty.
- comments: a code comment explains why the code is the way it is; it does not record history (people,
  dates, approvals, review findings).
"""

from __future__ import annotations

import bisect
import re
from collections.abc import Iterator, Mapping
from dataclasses import dataclass, field
from typing import Any

# ---------------------------------------------------------------------------------------------- content

CONTENT_PATTERNS: dict[str, re.Pattern[str]] = {
    # A user folder ends at a slash, a quote, a space or the end of the line; the Windows form may be escaped
    # (doubled backslashes) and its case varies.
    "home path": re.compile(
        r"(?:/Us[e]rs/[A-Za-z0-9_.-]+|/home/[a-z_][a-z0-9_-]*)(?:/|(?=[\s\"'`)]|$))"
        r"|(?i:\b[a-z]:\\{1,2}us[e]rs\\{1,2}[^\\\s\"'`]+)",
        re.MULTILINE,
    ),
    "external drive path": re.compile(r"/Vol[u]mes/[^\s/]+"),
    # The project's issue tracker is not the public one; an issue here is `#N`. Any hyphen, dash or space
    # (plain or non-breaking) may sit between the prefix and the number; the addon's own slash-command global
    # (SLASH_ + prefix + 1) is not an id.
    "tracker id": re.compile(r"(?<![A-Za-z0-9])(?<!SLASH_)wfj[-_ \u00a0\u2010-\u2015]?\d+", re.IGNORECASE),
}
# The public rules that also apply to code comments and to file names.
PUBLIC_COMMENT_RULES = ("tracker id",)
PUBLIC_PATH_RULES = ("tracker id",)

PRIVATE_WORD = "private word"
PERSONAL = "personal name or address"


@dataclass(frozen=True)
class PrivateRules:
    """Rules kept outside the repository, so the check does not publish what it looks for.

    `patterns` are further content rules by name. `data_exempt` names the ones that do not apply under
    data/ (a word that is also a name in the game), and `data_masks` match text that is allowed under data/
    and is blanked there before the patterns run. `comment_rules` and `path_rules` name the patterns that
    also apply to code comments and to file names. `words` and `personal` are lower-case words with spaces
    and hyphens removed, 4 to 15 characters, or whole email addresses; `first_names` match capitalised
    words only, outside data/."""

    patterns: Mapping[str, re.Pattern[str]] = field(default_factory=dict)
    data_exempt: frozenset[str] = frozenset()
    data_masks: tuple[re.Pattern[str], ...] = ()
    comment_rules: tuple[str, ...] = ()
    path_rules: tuple[str, ...] = ()
    words: frozenset[str] = frozenset()
    personal: frozenset[str] = frozenset()
    first_names: frozenset[str] = frozenset()

    def __bool__(self) -> bool:
        return bool(self.patterns or self.words or self.personal or self.first_names)


NO_PRIVATE_RULES = PrivateRules()
_RULE_KEYS = ("patterns", "data_exempt", "data_masks", "comment_rules", "path_rules", "words", "personal",
              "first_names")  # fmt: skip


def private_rules(spec: Mapping[str, Any]) -> PrivateRules:
    """The rules a parsed rules file holds. Raises ValueError on a key it does not know, a pattern that
    does not compile, or a rule name that no pattern has."""
    unknown = sorted(set(spec) - {*_RULE_KEYS, "about"})
    if unknown:
        raise ValueError(f"unknown key(s): {', '.join(unknown)}")
    try:
        named = dict(spec.get("patterns", {}))
        patterns = {name: re.compile(src, re.MULTILINE) for name, src in named.items()}
        masks = tuple(re.compile(src) for src in spec.get("data_masks", ()))
    except re.error as e:
        raise ValueError(f"a pattern does not compile: {e}") from e
    taken = sorted(set(patterns) & {*CONTENT_PATTERNS, PRIVATE_WORD, PERSONAL})
    if taken:
        raise ValueError(f"pattern name(s) already in use: {', '.join(taken)}")
    for key in ("data_exempt", "comment_rules", "path_rules"):
        missing = sorted(set(spec.get(key, ())) - set(patterns))
        if missing:
            raise ValueError(f"{key} names no pattern: {', '.join(missing)}")
    return PrivateRules(
        patterns=patterns,
        data_exempt=frozenset(spec.get("data_exempt", ())),
        data_masks=masks,
        comment_rules=tuple(spec.get("comment_rules", ())),
        path_rules=tuple(spec.get("path_rules", ())),
        words=frozenset(_normal(w).lower() for w in spec.get("words", ())),
        personal=frozenset(_normal(w).lower() for w in spec.get("personal", ())),
        first_names=frozenset(w.lower() for w in spec.get("first_names", ())),
    )


_EMAIL = re.compile(r"(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")
# Candidate words are collected once per text and compared with the sets above.
_LETTERS = re.compile(r"(?<![A-Za-z])[A-Za-z]{4,15}(?![A-Za-z])")
_ALNUM = re.compile(r"(?<![A-Za-z0-9])[A-Za-z0-9]{4,15}(?![A-Za-z0-9])")
# Two adjacent words joined by a space or a hyphen; the lookahead keeps overlapping pairs.
_PAIRS = re.compile(r"(?<![A-Za-z0-9])(?=([A-Za-z0-9]{1,14}[ -][A-Za-z0-9]{1,14})(?![A-Za-z0-9]))")
_CAPITALISED = re.compile(r"(?<![A-Za-z])[A-Z][a-z]{3,14}(?![A-Za-z])")


def _normal(word: str) -> str:
    return word.replace(" ", "").replace("-", "")


def listed_words(
    text: str, rules: Mapping[str, frozenset[str]], *, capitalised: frozenset[str] = frozenset()
) -> set[tuple[str, str]]:
    """(word as written, rule) for every candidate word or word pair in `text` that is in a rule's set;
    `capitalised` is checked against capitalised words only."""
    out: set[tuple[str, str]] = set()
    if any(rules.values()):
        words = set(_LETTERS.findall(text)) | set(_ALNUM.findall(text)) | set(_PAIRS.findall(text))
        for word in words:
            norm = _normal(word).lower()
            if 4 <= len(norm) <= 15:
                out.update((word, rule) for rule, listed in rules.items() if norm in listed)
    if capitalised:
        out.update((w, PERSONAL) for w in set(_CAPITALISED.findall(text)) if w.lower() in capitalised)
    return out


def _word_at(word: str) -> re.Pattern[str]:
    edge = "A-Za-z" if word.isalpha() else "A-Za-z0-9"
    return re.compile(rf"(?<![{edge}]){re.escape(word)}(?![{edge}])")


def _rule_order(rules: PrivateRules) -> dict[str, int]:
    return {r: i for i, r in enumerate([*CONTENT_PATTERNS, *rules.patterns, PRIVATE_WORD, PERSONAL])}


@dataclass(frozen=True)
class Hit:
    line: int
    rule: str
    text: str


def content_hits(
    text: str, *, in_data: bool = False, first_name: bool = True, rules: PrivateRules = NO_PRIVATE_RULES
) -> Iterator[Hit]:
    """Every line of `text` that holds something the public repository may not carry, in line order.

    `first_name=False` skips the first names (a credits page may name someone else who shares a common
    first name); the other personal words still apply."""
    scan = text
    if in_data:
        for mask in rules.data_masks:
            scan = mask.sub("masked", scan)
    newlines: list[int] = []

    def line_of(offset: int) -> int:
        if not newlines:
            newlines.extend(m.start() for m in re.finditer("\n", scan))
            newlines.append(len(scan))
        return bisect.bisect_left(newlines, offset) + 1

    found: set[tuple[int, str]] = set()
    for rule, pat in (*CONTENT_PATTERNS.items(), *rules.patterns.items()):
        if in_data and rule in rules.data_exempt:
            continue
        for m in pat.finditer(scan):
            found.add((line_of(m.start()), rule))
    for m in _EMAIL.finditer(scan):
        if m.group(0).lower() in rules.personal:
            found.add((line_of(m.start()), PERSONAL))
    capitalised = rules.first_names if first_name and not in_data else frozenset()
    words = listed_words(scan, {PRIVATE_WORD: rules.words, PERSONAL: rules.personal}, capitalised=capitalised)
    for word, rule in words:
        offsets = [m.start() for m in _word_at(word).finditer(scan)] or [0]
        found.update((line_of(o), rule) for o in offsets)
    # Split on "\n" only, as line_of counts: splitlines also breaks at other separators and would shift
    # the shown text.
    lines = scan.split("\n") if found else []
    order = _rule_order(rules)
    for n, rule in sorted(found, key=lambda x: (x[0], order[x[1]])):
        yield Hit(n, rule, "(not shown)" if rule == PERSONAL else lines[n - 1].strip()[:160])


def path_hits(path: str, *, rules: PrivateRules = NO_PRIVATE_RULES) -> list[str]:
    """Rules a tracked file's own path breaks (a tracker id or a private word in a file name)."""
    hits = [name for name in PUBLIC_PATH_RULES if CONTENT_PATTERNS[name].search(path)]
    hits += [name for name in rules.path_rules if rules.patterns[name].search(path)]
    if listed_words(path, {PRIVATE_WORD: rules.words}):
        hits.append(PRIVATE_WORD)
    return hits


# --------------------------------------------------------------------------------------------- comments

COMMENT_PATTERNS: dict[str, re.Pattern[str]] = {
    "person": re.compile(r"\b(?:the )?maintainer\b", re.IGNORECASE),
    # A date in a file name (a dated research note the comment points to) is a reference, not history.
    "date": re.compile(r"(?<![/\w-])20\d\d-\d\d-\d\d\b(?!-\w)"),
    "approval": re.compile(r"\bapproved\b|\bsign-?off\b", re.IGNORECASE),
    # Labels a reader cannot resolve: a numbered result of an earlier check, or the severity code given to
    # it (a letter and a number, alone in brackets or before a colon; upper case only, since a lower-case
    # one is the name of a hash here).
    "review finding": re.compile(
        r"(?i:\bfinding \d+|\breview round\b|\bPR review\b)"
        r"|\((?:QA |pass-\d+ )?[BHML]\d{1,2}\)"
        r"|(?<![\w.,/])(?:QA )?[BHML]\d{1,2}(?:/[BHML]\d{1,2})*:(?!\w)"
    ),
    "ruling label": re.compile(r"\bruling [A-Z]\b"),
}


def history_hits(comment: str, *, rules: PrivateRules = NO_PRIVATE_RULES) -> list[str]:
    """The history rules a comment breaks: the private patterns that apply to comments, then the rules
    above. The person rule also matches a first name of the private rules, capitalised only."""
    hits = [name for name in PUBLIC_COMMENT_RULES if CONTENT_PATTERNS[name].search(comment)]
    hits += [name for name in rules.comment_rules if rules.patterns[name].search(comment)]
    named = bool(listed_words(comment, {}, capitalised=rules.first_names))
    for rule, pat in COMMENT_PATTERNS.items():
        if pat.search(comment) or (rule == "person" and named):
            hits.append(rule)
    return hits


def _lua_long_bracket(src: str, i: int) -> int:
    """Level of a long bracket `[==[` opening at src[i], or -1."""
    j = i + 1
    while j < len(src) and src[j] == "=":
        j += 1
    return j - i - 1 if j < len(src) and src[j] == "[" else -1


def lua_comments(src: str) -> Iterator[tuple[int, str]]:
    """(line, text) for every comment in Lua source; strings are skipped, so `"--"` inside one is not one."""
    i, line, n = 0, 1, len(src)
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
        elif c in "\"'":
            i += 1
            while i < n and src[i] != c and src[i] != "\n":
                if src[i] == "\\":
                    # A backslash before a newline continues the string on the next line.
                    line += src[i + 1 : i + 2] == "\n"
                    i += 2
                else:
                    i += 1
            i += 1
        elif c == "[" and _lua_long_bracket(src, i) >= 0:
            level = _lua_long_bracket(src, i)
            end = src.find("]" + "=" * level + "]", i)
            end = n if end < 0 else end + level + 2
            line += src.count("\n", i, end)
            i = end
        elif src.startswith("--", i):
            start_line = line
            if src[i + 2 : i + 3] == "[" and _lua_long_bracket(src, i + 2) >= 0:
                level = _lua_long_bracket(src, i + 2)
                end = src.find("]" + "=" * level + "]", i)
                end = n if end < 0 else end + level + 2
            else:
                end = src.find("\n", i)
                end = n if end < 0 else end
            body = src[i:end]
            line += body.count("\n")
            yield start_line, body
            i = end
        else:
            i += 1


def python_comments(src: str) -> Iterator[tuple[int, str]]:
    """(line, text) for every `#` comment and every docstring in Python source."""
    import ast
    import io
    import tokenize

    for tok in tokenize.generate_tokens(io.StringIO(src).readline):
        if tok.type == tokenize.COMMENT:
            yield tok.start[0], tok.string
    for node in ast.walk(ast.parse(src)):
        if isinstance(node, ast.Module | ast.ClassDef | ast.FunctionDef | ast.AsyncFunctionDef):
            body = node.body
            if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant):
                value = body[0].value.value
                if isinstance(value, str):
                    yield body[0].lineno, value


def hash_comments(src: str, *, trailing: bool = True, skip: str = "") -> Iterator[tuple[int, str]]:
    """(line, text) for every `#` comment in a shell, YAML, TOML or Makefile style file.

    `trailing=False` counts only lines that start with `#` (list files, where a `#` later on is data). A
    trailing `#` counts only after whitespace and outside quotes, so `${#x}`, `"#tag"` and `url#part` are not
    comments. Lines starting with `skip` (a TOC's `##` metadata) are not comments."""
    for n, line in enumerate(src.split("\n"), 1):
        stripped = line.lstrip()
        if skip and stripped.startswith(skip):
            continue
        if stripped.startswith("#"):
            yield n, stripped
            continue
        if not trailing:
            continue
        quote = ""
        for i, c in enumerate(line):
            if quote:
                quote = "" if c == quote else quote
            elif c in "\"'":
                quote = c
            elif c == "#" and i and line[i - 1] in " \t":
                yield n, line[i:]
                break


# -------------------------------------------------------------------------------------------- markdown


def fenced_lines(lines: list[str]) -> list[bool]:
    """For each Markdown line, whether it is a code fence (``` or ~~~) or inside one. A fence closes on a line
    of the same character at least as long as the one that opened it."""
    out, opener = [], ""
    for line in lines:
        stripped = line.lstrip()
        char = stripped[:1]
        run = len(stripped) - len(stripped.lstrip(char)) if char in "`~" and char else 0
        if not opener and run >= 3:
            opener = char * run
            out.append(True)
        elif opener and run >= len(opener) and stripped[0] == opener[0] and not stripped[run:].strip():
            opener = ""
            out.append(True)
        else:
            out.append(bool(opener))
    return out


# ----------------------------------------------------------------------------------------------- images

_PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
_PNG_TEXT_CHUNKS = {b"tEXt", b"iTXt", b"zTXt", b"eXIf"}
# JPEG markers with no length field: TEM, the restart markers, SOI and EOI.
_JPEG_STANDALONE = {0x01, *range(0xD0, 0xDA)}


def image_metadata(data: bytes) -> list[str]:
    """The metadata blocks a PNG or JPEG carries that can hold text (camera, software, dates, locations):
    PNG tEXt / iTXt / zTXt / eXIf chunks, JPEG APP1 (Exif, XMP) and COM segments. Other formats: none."""
    found: list[str] = []
    if data.startswith(_PNG_SIGNATURE):
        i = len(_PNG_SIGNATURE)
        while i + 8 <= len(data):
            size = int.from_bytes(data[i : i + 4], "big")
            kind = data[i + 4 : i + 8]
            if kind in _PNG_TEXT_CHUNKS:
                found.append(kind.decode("ascii"))
            if kind == b"IEND":
                break
            i += 12 + size
    elif data.startswith(b"\xff\xd8"):
        i = 2
        while i + 2 <= len(data) and data[i] == 0xFF:
            marker = data[i + 1]
            if marker == 0xFF:  # fill byte before a marker
                i += 1
                continue
            if marker in _JPEG_STANDALONE:
                i += 2
                continue
            if marker == 0xDA:  # start of scan: only image data follows
                break
            if marker == 0xE1:
                found.append("APP1")
            elif marker == 0xFE:
                found.append("COM")
            i += 2 + int.from_bytes(data[i + 2 : i + 4], "big")
    return sorted(set(found))
