"""Player fix reports, version 1 (ADR-045; docs/systems/fix-reports.md). Pure.

The addon writes the report text (`Core/ReportText.lua`) and the player pastes it into a GitHub issue; this
module reads it back, writes it (the canonical form both sides must produce byte for byte; the shared cases
are `vectors/report_vectors.*`), and finds the store line each fix is about.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

from wfj.core import model, readings
from wfj.emit.lua_writer import shipped

VERSION = "1"
HEADER = "WFJ-REPORT"
# the types a fix may address, in the order the grammar lists them
TYPES = ("quest", "item", "spell", "gossip", "ui", "book", "objective", "area")
REASONS = ("wrong", "awkward", "typo", "name", "other")
NOTE_MAX = 200  # bytes of UTF-8, before escaping
JA_MAX = 8000  # the longest shipped line is 6,416 bytes (quest 10211 description)
FIXES_MAX = 25  # the addon keeps at most this many pending fixes (Core/Reports.lua, CAP)
ID_DIGITS_MAX = 10  # a game id is a 32-bit number
# the types the addon keys by the 16-hex hash of their English (gossip: the store id; book: the page's)
HEX_KEYED = ("gossip", "book")

_HEX16 = re.compile(r"^[0-9a-f]{16}$")
# the header's version: disjoint classes, so matching stays linear however the line is padded
_HEADER = re.compile(r"^WFJ-REPORT(?:[ \t]+(\S+))?$")
# the addon version and client build: a short token of these characters only; they are echoed in the issue
# comment, so nothing that renders as markdown or HTML; the addon writes `?` when unknown
_ADDON_TOKEN = r"[0-9A-Za-z._@?+-]{1,40}"
_ADDON = re.compile(rf"^addon ({_ADDON_TOKEN}) client ({_ADDON_TOKEN})$")
_END = re.compile(r"^end (\d+)$")
_VALUE = re.compile(r"^(note|ja)(?: (.*))?$", re.S)


class ReportError(ValueError):
    """A report that cannot be read; the message names the line."""


@dataclass
class Fix:
    type: str
    id: int | str
    field: str
    ja_hash: str
    reason: str
    note: str = ""
    ja: str = ""

    def address(self) -> tuple[str, int | str, str]:
        return (self.type, self.id, self.field)

    def as_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {
            "type": self.type,
            "id": self.id,
            "field": self.field,
            "ja_hash": self.ja_hash,
            "reason": self.reason,
        }
        if self.note:
            d["note"] = self.note
        if self.ja:
            d["ja"] = self.ja
        return d


@dataclass
class Report:
    addon: str = "?"
    client: str = "?"
    fixes: list[Fix] = field(default_factory=list)
    version: str = VERSION


def escape(s: str) -> str:
    """`\\` → `\\\\`, newline → `\\n`, carriage return → `\\r`, `|` → `\\x7c`: the report never holds a
    WoW escape character, and no raw CR a browser would turn into a line break (shipped lines hold CRs)."""
    return s.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("|", "\\x7c")


_ESC = re.compile(r"\\(x7c|n|r|\\|.?)", re.S)


def unescape(s: str) -> str:
    def one(m: re.Match[str]) -> str:
        code = m.group(1)
        if code == "\\":
            return "\\"
        if code == "n":
            return "\n"
        if code == "r":
            return "\r"
        if code == "x7c":
            return "|"
        raise ReportError(f"bad escape \\{code}")

    return _ESC.sub(one, s)


def render(report: Report) -> str:
    """The canonical text (the addon's serializer writes exactly this)."""
    out = [f"{HEADER} {report.version}", f"addon {report.addon} client {report.client}"]
    for f in report.fixes:
        out.append(f"fix {f.type} {f.id} {f.field} {f.ja_hash} {f.reason}")
        if f.note:
            out.append(f"note {escape(f.note)}")
        if f.ja:
            out.append(f"ja {escape(f.ja)}")
    out.append(f"end {len(report.fixes)}")
    return "\n".join(out) + "\n"


def _id(type_: str, raw: str, where: str) -> int | str:
    if type_ in HEX_KEYED:
        if not _HEX16.match(raw):
            raise ReportError(f"{where}: a {type_} id is 16 lowercase hex")
        return raw
    if type_ == "ui":
        if not model.UI_KEY_RE.match(raw):
            raise ReportError(f"{where}: {raw!r} is not a UI key")
        return raw
    # ASCII digits only: `isdigit` alone also accepts digits `int` refuses.
    if not (raw.isascii() and raw.isdigit()) or raw.startswith("0") or len(raw) > ID_DIGITS_MAX:
        raise ReportError(f"{where}: a {type_} id is a positive number")
    return int(raw)


def _fix(tokens: list[str], where: str) -> Fix:
    if len(tokens) != 6:
        raise ReportError(f"{where}: a fix line is `fix <type> <id> <field> <hash> <reason>`")
    _, type_, raw_id, field_, h, reason = tokens
    if type_ not in TYPES:
        raise ReportError(f"{where}: unknown type {type_!r}")
    if field_ not in model.FIELDS[type_]:
        raise ReportError(f"{where}: {type_} has no field {field_!r}")
    if not _HEX16.match(h):
        raise ReportError(f"{where}: the hash is 16 lowercase hex")
    if reason not in REASONS:
        raise ReportError(f"{where}: unknown reason {reason!r} (one of {', '.join(REASONS)})")
    return Fix(type_, _id(type_, raw_id, where), field_, h, reason)


def parse(text: str) -> Report:
    """The one report block in `text` (an issue body wraps it in headings and a code fence)."""
    lines = text.replace("\r\n", "\n").split("\n")
    start = _block_start(lines)
    rep = Report()
    seen: dict[tuple[str, int | str, str], int] = {}
    head_done = False
    current: Fix | None = None
    has: set[str] = set()
    for n in range(start + 1, len(lines)):
        where = f"line {n + 1}"
        raw = lines[n].rstrip("\r")
        stripped = raw.strip()
        if not stripped:
            continue
        if not head_done:
            am = _ADDON.match(stripped)
            if not am:
                raise ReportError(f"{where}: expected `addon <version> client <build>` after the header")
            rep.addon, rep.client = am.group(1), am.group(2)
            head_done = True
            continue
        em = _END.match(stripped)
        if em:
            if int(em.group(1)) != len(rep.fixes):
                raise ReportError(
                    f"{where}: the report says {em.group(1)} fix(es) but holds {len(rep.fixes)}; "
                    "the paste was "
                    "cut or edited; copy the report again"
                )
            return rep
        if stripped.startswith("fix "):
            current = _fix(stripped.split(" "), where)
            if current.address() in seen:
                raise ReportError(
                    f"{where}: this line was already reported on line {seen[current.address()]}"
                )
            seen[current.address()] = n + 1
            rep.fixes.append(current)
            if len(rep.fixes) > FIXES_MAX:
                raise ReportError(f"{where}: a report holds at most {FIXES_MAX} fixes; this one holds more")
            has = set()
            continue
        vm = _VALUE.match(raw.lstrip())  # a value keeps its trailing whitespace
        if vm:
            _set_value(current, has, vm.group(1), vm.group(2) or "", where)
            continue
        raise ReportError(f"{where}: unexpected line {stripped[:40]!r}")
    if not head_done:
        raise ReportError("the report stops after its header: the paste was cut; copy the report again")
    raise ReportError("no `end` line: the paste was cut; copy the report again")


def _block_start(lines: list[str]) -> int:
    """The index of the one header line; raises when there is none, more than one, or another version."""
    start = None
    for n, raw in enumerate(lines):
        if raw.strip().startswith(HEADER):
            if start is not None:
                raise ReportError(f"line {n + 1}: a second report starts here; send one report per issue")
            start = n
    if start is None:
        raise ReportError("no report found (the first line is `WFJ-REPORT 1`)")
    m = _HEADER.match(lines[start].strip())
    if not m or m.group(1) != VERSION:
        raise ReportError(f"line {start + 1}: unknown report version (this pipeline reads version {VERSION})")
    return start


def _set_value(current: Fix | None, has: set[str], key: str, value: str, where: str) -> None:
    """Put one `note` / `ja` line on the fix it follows; `has` holds the keys that fix already has."""
    if current is None:
        raise ReportError(f"{where}: `{key}` before any `fix` line")
    if key in has or (key == "note" and "ja" in has):
        raise ReportError(f"{where}: `{key}` repeated or out of order for this fix")
    has.add(key)
    try:
        text_ = unescape(value)
    except ReportError as e:
        raise ReportError(f"{where}: {e}") from None
    if not text_:
        raise ReportError(f"{where}: an empty `{key}` line")
    size = len(text_.encode("utf-8"))
    if key == "note":
        if "\n" in text_ or "\r" in text_:
            raise ReportError(f"{where}: a note is one line")
        if size > NOTE_MAX:
            raise ReportError(f"{where}: the note is over {NOTE_MAX} bytes")
        current.note = text_
    else:
        if size > JA_MAX:
            raise ReportError(f"{where}: the Japanese is over {JA_MAX} bytes")
        current.ja = text_


# --- resolving a fix against the store ------------------------------------------------------------

ALREADY_CHANGED = "already changed"  # the line ships other Japanese than the player saw
NOT_SHIPPING = "not shipping"
NO_LINE = "no such line"


def book_owners(lines: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    """English hash → the book page line the addon ships under it: the lowest page id among the shipped
    pages of that English, a current page before a stale one (the rule `readings.addon_keyed` and the
    generator use)."""
    ship = [ln for ln in lines if shipped(ln) and ln.get("english") and ln["english"].get("hash")]
    current = {str(ln["english"]["hash"]) for ln in ship if ln["status"] != "stale"}
    owners: dict[str, dict[str, Any]] = {}
    for ln in sorted(ship, key=lambda ln: ln["id"]):
        key = str(ln["english"]["hash"])
        if key in owners or (ln["status"] == "stale" and key in current):
            continue
        owners[key] = ln
    return owners


def resolve(
    fix: Fix, lines: list[dict[str, Any]], issue: int | None = None
) -> tuple[dict[str, Any] | None, str | None]:
    """The store line `fix` is about, from its type's lines → (line, None) | (None, skip reason). A line
    this same report (`issue`) already rewrote still matches: its Japanese is ours now, not a later change
    (intake can run again after apply)."""
    if fix.type == "book":
        line = book_owners(lines).get(str(fix.id))
        if line is None:
            return None, NO_LINE
    else:
        line = next((ln for ln in lines if ln["id"] == fix.id and ln["field"] == fix.field), None)
        if line is None:
            return None, NO_LINE
        if not shipped(line):
            return None, NOT_SHIPPING
    if not isinstance(line.get("ja"), str):
        return None, ALREADY_CHANGED
    if readings.ja_hash(line["ja"]) != fix.ja_hash:
        if issue is not None and line.get("provenance", {}).get("report") == issue:
            return line, None
        return None, ALREADY_CHANGED
    return line, None
