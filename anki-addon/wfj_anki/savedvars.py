"""Reads one saved table out of a World of Warcraft SavedVariables file.

The client writes the file as Lua assignments: `Name = { ... }`, one after another. Only what the client
writes is understood: tables, strings, numbers, true, false and nil, `["key"] = value` and `[n] = value`
entries, values with no key (a list), and `--` comments. Anything else ends the read with nothing, never with
an error: the file belongs to the game, and a half-written or damaged one must not stop Anki.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

_TOKEN = re.compile(
    r"""
    (?P<space>\s+|--[^\n]*)
  | (?P<string>"(?:[^"\\]|\\.|\\\n)*")
  | (?P<number>-?(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?))
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<punct>[{}\[\]=,;])
    """,
    re.VERBOSE | re.DOTALL,
)

_ESCAPES = {
    "n": "\n",
    "r": "\r",
    "t": "\t",
    "a": "\a",
    "b": "\b",
    "f": "\f",
    "v": "\v",
    "\\": "\\",
    '"': '"',
    "'": "'",
    "\n": "\n",
}
_ESCAPE = re.compile(r"\\(\d{1,3}|.)", re.DOTALL)
_WORDS = {"true": True, "false": False, "nil": None}


class _Damaged(Exception):
    pass


def _unescape(body: str) -> str:
    if "\\" not in body:
        return body
    # a decimal escape is one byte of the text's UTF-8, so the string is put back together as bytes
    out = bytearray()
    at = 0
    for match in _ESCAPE.finditer(body):
        out += body[at : match.start()].encode("utf-8")
        code = match.group(1)
        if code.isdigit():
            out.append(int(code) % 256)
        else:
            out += _ESCAPES.get(code, code).encode("utf-8")
        at = match.end()
    out += body[at:].encode("utf-8")
    return out.decode("utf-8", errors="replace")


class _Reader:
    def __init__(self, text: str, start: int):
        self.text = text
        self.pos = start

    def token(self) -> tuple[str, str]:
        while True:
            match = _TOKEN.match(self.text, self.pos)
            if not match:
                raise _Damaged
            self.pos = match.end()
            kind = match.lastgroup or ""
            if kind != "space":
                return kind, match.group(kind)

    def peek(self) -> tuple[str, str]:
        at = self.pos
        try:
            return self.token()
        finally:
            self.pos = at

    def value(self) -> Any:
        kind, text = self.token()
        if kind == "string":
            return _string(text)
        if kind == "number":
            return _number(text)
        if kind == "name" and text in _WORDS:
            return _WORDS[text]
        if (kind, text) == ("punct", "{"):
            return self.table()
        raise _Damaged

    def table(self) -> Any:
        keyed: dict[Any, Any] = {}
        count = 0  # values with no key take 1, 2, 3 ... as Lua gives them
        while True:
            kind, text = self.peek()
            if (kind, text) == ("punct", "}"):
                self.token()
                break
            if (kind, text) == ("punct", "["):
                self.token()
                key = self.value()
                self._expect("]")
                self._expect("=")
                keyed[key] = self.value()
            elif kind == "name" and text not in _WORDS:
                self.token()
                self._expect("=")
                keyed[text] = self.value()
            else:
                count += 1
                keyed[count] = self.value()
            kind, text = self.peek()
            if kind == "punct" and text in ",;":
                self.token()
        if (
            keyed
            and all(isinstance(k, int) and not isinstance(k, bool) for k in keyed)
            and sorted(keyed) == list(range(1, len(keyed) + 1))
        ):
            return [keyed[i] for i in range(1, len(keyed) + 1)]
        return keyed

    def _expect(self, punct: str) -> None:
        if self.token() != ("punct", punct):
            raise _Damaged


def _string(token: str) -> str:
    return _unescape(token[1:-1])


def _number(token: str) -> int | float:
    try:
        if token.lower().lstrip("-").startswith("0x"):
            return int(token, 16)
        return int(token)
    except ValueError:
        return float(token)


def parse(text: str, name: str) -> Any:
    """The value assigned to the global `name` in a SavedVariables file's text, or None."""
    match = re.search(rf"^{re.escape(name)}[ \t]*=", text, re.MULTILINE)
    if not match:
        return None
    try:
        return _Reader(text, match.end()).value()
    except (_Damaged, RecursionError, ValueError):
        return None


def read(path: Path | str, name: str) -> Any:
    """The value of the global `name` in the file at `path`, or None when the file or the value cannot be
    read."""
    try:
        text = Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    return parse(text, name)
