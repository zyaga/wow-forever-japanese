"""Reader for the Lua *table literals* the predecessor addons and pfQuest ship their data in.

Not a Lua parser. It understands exactly: `NAME = { ... }` (with optional `["x"]["y"]` index
chain on the left) or, via `parse_assignments`, a sequence of `NAME = <value>` statements
(SavedVariables), nested tables, `[key] = value` / `["key"] = value` / `name = value` /
positional entries, string literals with the Lua 5.1 escapes, numbers, `nil`, `true`/`false`,
and `--` line comments. Duplicate keys are PRESERVED (returned in file order) because the
predecessor quest file relies on them. Anything else raises `LuaSyntaxError` with a line number.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

_ESCAPES = {
    "n": "\n",
    "t": "\t",
    "r": "\r",
    "a": "\a",
    "b": "\b",
    "f": "\f",
    "v": "\v",
    "\\": "\\",
    '"': '"',
    "'": "'",
}


class LuaSyntaxError(ValueError):
    pass


@dataclass
class Table:
    """A Lua table literal as an ordered list of (key, value); key is None for positional entries."""

    items: list[tuple[Any, Any]]

    def positional(self) -> list[Any]:
        return [v for k, v in self.items if k is None]

    def get(self, key: Any, default: Any = None) -> Any:
        for k, v in self.items:
            if k == key:
                return v
        return default

    def named(self) -> dict[Any, Any]:
        return {k: v for k, v in self.items if k is not None}


class _Parser:
    def __init__(self, text: str):
        self.s = text
        self.i = 0
        self.line = 1

    def error(self, msg: str) -> LuaSyntaxError:
        return LuaSyntaxError(f"line {self.line}: {msg}")

    def skip(self) -> None:
        s, n = self.s, len(self.s)
        while self.i < n:
            c = s[self.i]
            if c == "\n":
                self.line += 1
                self.i += 1
            elif c in " \t\r﻿":
                self.i += 1
            elif s.startswith("--", self.i):
                while self.i < n and s[self.i] != "\n":
                    self.i += 1
            else:
                break

    def expect(self, ch: str) -> None:
        self.skip()
        if not self.s.startswith(ch, self.i):
            raise self.error(f"expected {ch!r}, got {self.s[self.i : self.i + 10]!r}")
        self.i += len(ch)

    def peek(self, ch: str) -> bool:
        self.skip()
        return self.s.startswith(ch, self.i)

    def string(self) -> str:
        q = self.s[self.i]
        if q not in "\"'":
            raise self.error("expected string")
        self.i += 1
        out: list[str] = []
        s, n = self.s, len(self.s)
        while True:
            if self.i >= n:
                raise self.error("unterminated string")
            c = s[self.i]
            if c == q:
                self.i += 1
                return "".join(out)
            if c == "\\":
                self.i += 1
                e = s[self.i]
                if e in _ESCAPES:
                    out.append(_ESCAPES[e])
                    self.i += 1
                elif e.isdigit():
                    j = self.i
                    while j < n and j - self.i < 3 and s[j].isdigit():
                        j += 1
                    out.append(chr(int(s[self.i : j])))
                    self.i = j
                elif e == "\n":
                    out.append("\n")
                    self.line += 1
                    self.i += 1
                else:
                    # Lua 5.1 keeps the character after an unknown escape (5.2+ would error).
                    out.append(e)
                    self.i += 1
            else:
                if c == "\n":
                    self.line += 1
                out.append(c)
                self.i += 1

    def word(self) -> str:
        j = self.i
        while j < len(self.s) and (self.s[j].isalnum() or self.s[j] == "_"):
            j += 1
        w = self.s[self.i : j]
        self.i = j
        return w

    def value(self) -> Any:
        self.skip()
        c = self.s[self.i]
        if c == "{":
            return self.table()
        if c in "\"'":
            return self.string()
        if c.isdigit() or c == "-":
            j = self.i + 1
            while j < len(self.s) and (self.s[j].isdigit() or self.s[j] in ".eE+-"):
                j += 1
            txt = self.s[self.i : j]
            self.i = j
            return float(txt) if any(x in txt for x in ".eE") else int(txt)
        w = self.word()
        if w == "nil":
            return None
        if w == "true":
            return True
        if w == "false":
            return False
        raise self.error(f"unexpected {w or c!r}")

    def table(self) -> Table:
        self.expect("{")
        items: list[tuple[Any, Any]] = []
        while True:
            self.skip()
            if self.peek("}"):
                self.i += 1
                return Table(items)
            key: Any
            if self.peek("["):
                self.i += 1
                key = self.value()
                self.expect("]")
                self.expect("=")
                items.append((key, self.value()))
            else:
                save_i, save_line = self.i, self.line
                w = self.word()
                self.skip()
                if (
                    w
                    and not w[0].isdigit()
                    and w not in ("nil", "true", "false")
                    and self.s.startswith("=", self.i)
                ):
                    self.i += 1
                    items.append((w, self.value()))
                else:
                    self.i, self.line = save_i, save_line
                    items.append((None, self.value()))
            self.skip()
            if self.peek(",") or self.peek(";"):
                self.i += 1

    def assignment(self) -> tuple[str, Table]:
        """`NAME[...]... = { ... }`: returns (name, table)."""
        self.skip()
        name = self.word()
        if not name:
            raise self.error("expected a name")
        while self.s.startswith(".", self.i):  # `CraftJapanizer_Quest.Data = {`
            self.i += 1
            part = self.word()
            if not part:
                raise self.error("expected a name after '.'")
            name = f"{name}.{part}"
        while self.peek("["):
            self.i += 1
            self.value()
            self.expect("]")
        self.expect("=")
        t = self.value()
        if not isinstance(t, Table):
            raise self.error("expected a table literal")
        self.skip()
        if self.i != len(self.s):
            raise self.error(f"trailing content {self.s[self.i : self.i + 20]!r}")
        return name, t

    def assignments(self) -> dict[str, Any]:
        """Any number of top-level `NAME = <value>` statements (a SavedVariables file) → {name: value}."""
        out: dict[str, Any] = {}
        while True:
            self.skip()
            if self.i >= len(self.s):
                return out
            name = self.word()
            if not name or name[0].isdigit():
                raise self.error(f"expected a name, got {self.s[self.i : self.i + 20]!r}")
            self.expect("=")
            out[name] = self.value()


def parse_assignment(text: str) -> tuple[str, Table]:
    p = _Parser(text)
    try:
        return p.assignment()
    except IndexError:  # the parser indexes the next character without a bounds check: a truncated file
        raise p.error("unexpected end of input") from None


def parse_assignments(text: str) -> dict[str, Any]:
    """Every `NAME = <value>` in a file (`WFJ_DB = {…}`, `WFJ_Collector = {…}`); values may be nil."""
    p = _Parser(text)
    try:
        return p.assignments()
    except IndexError:  # as in parse_assignment
        raise p.error("unexpected end of input") from None


def as_int_id(key: Any) -> int:
    """Predecessor keys are strings (`["117"]`); pfQuest keys are ints. Both become ints."""
    if isinstance(key, int) and not isinstance(key, bool):
        return key
    if isinstance(key, str) and key.isdigit():
        return int(key)
    raise LuaSyntaxError(f"not a numeric id: {key!r}")
