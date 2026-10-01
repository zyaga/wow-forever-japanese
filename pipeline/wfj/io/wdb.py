"""The client's quest cache, `Cache/WDB/enUS/questcache.wdb` → quest English (ADR-020).

The client writes the cache on a full exit (not a logout) with the text the server sent for every quest it
asked about. The **framing** is the same on every build seen so far:

- header, 24 bytes: magic `TSQW`, build u32, locale (`SUne` = enUS reversed), then three u32 we do not read;
- records: `[quest id u32][length u32][payload]`, then an 8-byte zero terminator.

The **payload layout is per build** and pinned in `LAYOUTS` with the evidence it was derived from (the
standard ADR-027 sets for the client tables). A payload the decoder does not consume exactly is an error,
never a guess: a changed layout on a new client build fails loudly here, and an unknown build is refused
before any payload is read (`wfj.dev.wdb_layout` reports which pinned layout, if any, reads a new build's
cache exactly, so it can be pinned).

Every layout has the same shape. A fixed part holds the counts; then, in order: a list of `pre_list` 12-byte
entries, the objectives, a list of `post_list` 4-byte entries, the conditional-text arrays, a 12-byte block
holding the byte lengths of nine strings (MSB first, 9·12·12·9·10·8·10·8·11 bits, then `pad_bits`), and the
nine strings back to back with no NUL: title, objectives (log description), description, area description,
portrait giver text / name, portrait turn-in text / name, completion log. An objective is 43 bytes plus four
per entry of its own inner list, then its description's length byte, a flag byte whose low 7 bits are zero,
and the description.

The text is Blizzard's raw template (`$B`, `$N`, `$G a : b;`); normalization and hashing belong to the
importer.
"""

from __future__ import annotations

import re
import struct
from collections.abc import Iterator
from dataclasses import dataclass, field, replace
from pathlib import Path

MAGIC = b"TSQW"
LOCALE_ENUS = b"SUne"
HEADER_SIZE = 24
RECORD_HEADER = struct.Struct("<II")

STRING_BITS = (9, 12, 12, 9, 10, 8, 10, 8, 11)
BITS_BYTES = 12
QUEST_ID_AT = 0  # the payload names its own quest; an objective record names its QuestObjective the same way
OBJECTIVE_FIXED = 41  # an objective's fixed part, before its inner list's entries
OBJECTIVE_SIZE = 43  # with an empty inner list: the fixed part, the description length, the flag byte
CONDITIONAL_HEAD = 10  # a conditional-text entry: two u32, then a 12-bit length and 4 bits of padding

# A quest the client holds as a stub, measured on the full 1.15.9.69722 scan (63 of 4,217 records; none has a
# translation): a leading `<TAG>` in any case (`<UNUSED>`, `<TEST> HEY MISTER WILSON!`, `<nyi> <TXT>…`), a
# leading `[…]` (`[Never used]`, `[DNT] Holiday Quests Tracker`), or a title that is only `REUSE`. Real titles
# with the word "Test" ("Test of Lore") are quests and stay.
PLACEHOLDER_TITLE = re.compile(r"^\s*(?:<[A-Za-z]+>|\[[^\]]*\])|^\s*reuse\s*$", re.IGNORECASE)

MAX_COUNT = 64  # no list measured on either build comes near this; a wilder count means we misread the layout


class WdbError(ValueError):
    """The file is not a quest cache this reader understands."""


@dataclass(frozen=True)
class Layout:
    """Where one client build puts the payload's parts, and what it was verified against.

    Offsets are into the payload. `bits_at` pins the string-length block at a fixed offset (1.15.9: it sits
    *before* the objectives); `None` means it follows the variable parts, wherever those end. A `*_count_at`
    of `None` means that build has no such list. `zero_u32_at` are u32 that were zero on every record
    measured, so a non-zero one is a layout we have not seen and is refused."""

    build: int
    evidence: str
    objective_count_at: int
    objectives_at: int
    bits_at: int | None
    pad_bits: int
    zero_u32_at: tuple[int, ...] = ()
    pre_list_count_at: int | None = None
    post_list_count_at: int | None = None
    conditional_counts_at: tuple[int, ...] = ()
    objective_list_count_at: int | None = None

    @property
    def fixed_part(self) -> int:
        """The bytes every payload must hold before anything variable starts."""
        ends = [self.objectives_at, self.objective_count_at + 4]
        if self.bits_at is not None:
            ends.append(self.bits_at + BITS_BYTES)
        for at in (self.pre_list_count_at, self.post_list_count_at, *self.conditional_counts_at):
            if at is not None:
                ends.append(at + 4)
        ends += [at + 4 for at in self.zero_u32_at]
        return max(ends)


# Classic Era: all 485 records of a 1–500 scan, then all 4,217 of the full scan, consumed exactly. Forever
# 69913: all 1,965 records of the cache consumed exactly, and 1,233 of the 1,245 titles already held
# reproduce character for character; the 12 that differ are Forever's own edits
# (`WANTED:` for `Wanted:`, an id reused for a different quest), not mis-slicing. How the Forever offsets were
# derived: the Forever quest-cache layout research in docs/research/.
LAYOUTS: tuple[Layout, ...] = (
    Layout(
        build=69722,
        evidence="Classic Era 1.15.9.69722, 4,217 of 4,217 records",
        objective_count_at=448,
        objectives_at=504,
        bits_at=492,
        pad_bits=0,
        zero_u32_at=(480, 484, 488),
    ),
    Layout(
        build=69913,
        evidence="Forever beta 1.60.1.69913, 1,965 of 1,965 records",
        objective_count_at=436,
        objectives_at=488,
        bits_at=None,
        pad_bits=32,
        zero_u32_at=(480, 484),
        pre_list_count_at=64,
        post_list_count_at=448,
        conditional_counts_at=(472, 476),
        objective_list_count_at=33,
    ),
    # 1.60.1.70009 and 1.60.1.70124 bumped only the build: dev/wdb_layout read every record of each full
    # scan with the 69913 offsets (70009: 2,231 of 2,231, 2,164 quests, 67 placeholders, 16 conditional
    # entries, 2,091 of 2,101 held titles reproducing; 70124: 2,325 of 2,325, then every record of the
    # 2,356-record cache after the sweep), and layout 69722 reads none. One definition, re-pinned per build
    # with its own evidence.
)
_FOREVER_69913 = LAYOUTS[-1]
LAYOUTS = (
    *LAYOUTS,
    replace(_FOREVER_69913, build=70009, evidence="Forever beta 1.60.1.70009, 2,231 of 2,231 records"),
    replace(_FOREVER_69913, build=70124, evidence="Forever beta 1.60.1.70124, 2,325 of 2,325 records"),
)


@dataclass(frozen=True)
class WdbQuest:
    id: int
    title: str
    objectives: str
    description: str
    area: str = ""  # the area description: an exploration objective's text
    # (QuestObjective id, text) per objective with its own text ("Rescue Drull"), in record order
    objective_texts: tuple[tuple[int, str], ...] = ()
    # (PlayerCondition id, quest-giver id, text) per conditional-text entry, in record order. Forever
    # serves a variant of a quest's text per condition. Read so the payload is accounted for, and reported;
    # **not imported**: an entry is keyed by its condition, and that key is not designed yet.
    conditional: tuple[tuple[int, int, str], ...] = ()


@dataclass
class WdbCache:
    build: int
    quests: list[WdbQuest] = field(default_factory=list)  # sorted by id, placeholders excluded
    placeholders: list[int] = field(default_factory=list)  # ids dropped by PLACEHOLDER_TITLE, sorted
    layout: Layout | None = None  # the layout the records were read with


def _u32(buf: bytes, at: int) -> int:
    return struct.unpack_from("<I", buf, at)[0]


def _string_lengths(block: bytes, pad_bits: int) -> list[int]:
    bits = int.from_bytes(block, "big")
    total = BITS_BYTES * 8
    out, used = [], 0
    for width in STRING_BITS:
        used += width
        out.append((bits >> (total - used)) & ((1 << width) - 1))
    tail = bits & ((1 << (total - used)) - 1)
    if tail != pad_bits:
        raise ValueError(f"the bits after the string lengths are {tail}, this build's are {pad_bits}")
    return out


def _count(payload: bytes, at: int | None, what: str) -> int:
    """A list's length, refused when it is past anything a build has used (we would be misreading)."""
    if at is None:
        return 0
    if at + 4 > len(payload):
        raise ValueError(f"{what} at {at} runs past the payload")
    n = _u32(payload, at)
    if n > MAX_COUNT:
        raise ValueError(f"{what} at {at} is {n}, past the {MAX_COUNT} any build has used")
    return n


def _objectives(payload: bytes, off: int, count: int, lay: Layout) -> tuple[int, list[tuple[int, str]]]:
    """(offset after the objectives, the ones carrying text of their own). An objective is its fixed part plus
    its inner list's entries, then the description length, the flag byte and the description; with an empty
    inner list that is the 43-byte 1.15.9 record exactly."""
    texts: list[tuple[int, str]] = []
    for n in range(count):
        if off + OBJECTIVE_FIXED > len(payload):
            raise ValueError(f"objective {n} runs past the payload")
        inner = (
            _count(payload, off + lay.objective_list_count_at, f"objective {n}'s list count")
            if lay.objective_list_count_at is not None
            else 0
        )
        at = off + OBJECTIVE_FIXED + 4 * inner
        if at + 2 > len(payload):
            raise ValueError(f"objective {n} runs past the payload")
        if payload[at + 1] & 0x7F:
            raise ValueError(f"objective {n} flag byte {payload[at + 1]:#04x} has unknown bits")
        text_len, start = payload[at], at + 2
        if start + text_len > len(payload):
            raise ValueError(f"objective {n} text runs past the payload")
        if text_len:
            try:
                text = payload[start : start + text_len].decode("utf-8")
            except UnicodeDecodeError as e:
                raise ValueError(f"objective {n} text is not UTF-8 ({e.reason})") from e
            oid = _u32(payload, off + QUEST_ID_AT)
            if text.strip() and not oid:  # no QuestObjective id to key it by
                raise ValueError(f"objective {n} has text but QuestObjective id 0")
            texts.append((oid, text))
        off = start + text_len
    return off, texts


def _conditional(payload: bytes, off: int, count: int) -> tuple[int, list[tuple[int, int, str]]]:
    """(offset after the conditional-text arrays, their entries). One entry is a PlayerCondition id, a
    quest-giver id, a 12-bit text length with 4 bits of padding, then the text."""
    out: list[tuple[int, int, str]] = []
    for n in range(count):
        if off + CONDITIONAL_HEAD > len(payload):
            raise ValueError(f"conditional text {n} runs past the payload")
        packed = struct.unpack_from(">H", payload, off + 8)[0]
        if packed & 0xF:
            raise ValueError(f"conditional text {n}: the 4 bits after its length are {packed & 0xF}, not 0")
        length, start = packed >> 4, off + CONDITIONAL_HEAD
        if start + length > len(payload):
            raise ValueError(f"conditional text {n} runs past the payload")
        try:
            text = payload[start : start + length].decode("utf-8")
        except UnicodeDecodeError as e:
            raise ValueError(f"conditional text {n} is not UTF-8 ({e.reason})") from e
        out.append((_u32(payload, off), _u32(payload, off + 4), text))
        off = start + length
    return off, out


def decode_payload(qid: int, payload: bytes, lay: Layout) -> WdbQuest:
    """One record, read against `lay`. `ValueError` when the payload does not fit that layout exactly."""
    if len(payload) < lay.fixed_part:
        raise ValueError(f"payload of {len(payload)} bytes is shorter than the fixed part ({lay.fixed_part})")
    if _u32(payload, QUEST_ID_AT) != qid:
        raise ValueError(f"payload names quest {_u32(payload, QUEST_ID_AT)}")
    for at in lay.zero_u32_at:
        if _u32(payload, at):
            raise ValueError(f"the u32 at {at} is not zero (a layout not seen on build {lay.build})")

    off = lay.objectives_at + 12 * _count(payload, lay.pre_list_count_at, "the 12-byte list count")
    count = _count(payload, lay.objective_count_at, "the objective count")
    off, texts = _objectives(payload, off, count, lay)
    off += 4 * _count(payload, lay.post_list_count_at, "the 4-byte list count")
    off, conditional = _conditional(
        payload, off, sum(_count(payload, at, "a conditional-text count") for at in lay.conditional_counts_at)
    )

    bits_at = off if lay.bits_at is None else lay.bits_at
    if bits_at + BITS_BYTES > len(payload):
        raise ValueError(f"the string-length block at {bits_at} runs past the payload")
    lengths = _string_lengths(payload[bits_at : bits_at + BITS_BYTES], lay.pad_bits)
    at = off + BITS_BYTES if lay.bits_at is None else off
    if at + sum(lengths) != len(payload):
        raise ValueError(f"strings end at {at + sum(lengths)}, payload has {len(payload)} bytes")
    strings = []
    for n, length in enumerate(lengths):
        try:
            strings.append(payload[at : at + length].decode("utf-8"))
        except UnicodeDecodeError as e:
            raise ValueError(f"string {n} is not UTF-8 ({e.reason})") from e
        at += length
    return WdbQuest(qid, strings[0], strings[1], strings[2], strings[3], tuple(texts), tuple(conditional))


def layout_for(build: int) -> Layout:
    """The layout pinned for a client build. An unknown build is refused (ADR-020): a changed layout fails
    loudly rather than importing misread text."""
    for lay in LAYOUTS:
        if lay.build == build:
            return lay
    known = ", ".join(str(lay.build) for lay in LAYOUTS)
    raise WdbError(
        f"build {build} has no pinned payload layout (pinned: {known}). Verify and pin it in io/wdb.LAYOUTS "
        "first: `python -m wfj.dev.wdb_layout <cache>` reports which pinned layout, if any, reads every "
        "record of it exactly"
    )


def _open(path: Path) -> tuple[str, bytes]:
    """(file name, bytes) of a cache whose header this reader recognises."""
    try:
        buf = Path(path).read_bytes()
    except OSError as e:
        raise WdbError(f"{path}: {e.strerror or e}") from e
    name = Path(path).name
    if len(buf) < HEADER_SIZE or buf[:4] != MAGIC:
        raise WdbError(f"{name}: not a quest cache (magic {buf[:4]!r}, want {MAGIC!r})")
    if buf[8:12] != LOCALE_ENUS:
        raise WdbError(f"{name}: locale {buf[8:12][::-1]!r} is not enUS")
    return name, buf


def _records(name: str, buf: bytes) -> Iterator[tuple[int, bytes]]:
    """(quest id, payload) per record. The framing only: a payload is not decoded here, which is what lets
    `read_ids` answer on a build whose payload layout is not pinned yet."""
    seen: set[int] = set()
    off = HEADER_SIZE
    while True:
        if off + RECORD_HEADER.size > len(buf):
            raise WdbError(f"{name}: ends at byte {len(buf)} without the zero terminator")
        qid, length = RECORD_HEADER.unpack_from(buf, off)
        off += RECORD_HEADER.size
        if qid == 0 and length == 0:
            break
        if off + length > len(buf):
            raise WdbError(f"{name}: quest {qid}: record of {length} bytes runs past the end of the file")
        if qid in seen:  # a duplicate is reported, never resolved silently
            raise WdbError(f"{name}: quest {qid} is cached twice")
        seen.add(qid)
        yield qid, buf[off : off + length]
        off += length
    if off != len(buf):
        raise WdbError(f"{name}: {len(buf) - off} bytes after the zero terminator")


def read_ids(path: Path) -> tuple[int, list[int]]:
    """(build, the quest ids the cache holds, sorted). Reads the framing, never a payload: this answers on a
    client build whose payload layout is not pinned yet, which is what a rescan list needs. Every id
    here was answered by the server, so a rescan asks for the rest."""
    name, buf = _open(path)
    return _u32(buf, 4), sorted(qid for qid, _ in _records(name, buf))


def read_quests(path: Path, layout: Layout | None = None) -> WdbCache:
    """Every quest in the cache, read against the layout pinned for its build (`layout` overrides that, for
    `wfj.dev.wdb_layout`). Raises `WdbError` naming the file (and the quest id) on anything unexpected."""
    name, buf = _open(path)
    build = _u32(buf, 4)
    lay = layout or layout_for(build)
    cache = WdbCache(build=build, layout=lay)
    for qid, payload in _records(name, buf):
        try:
            quest = decode_payload(qid, payload, lay)
        except ValueError as e:
            raise WdbError(f"{name}: quest {qid}: {e}") from e
        if PLACEHOLDER_TITLE.match(quest.title):
            cache.placeholders.append(qid)
        else:
            cache.quests.append(quest)
    cache.quests.sort(key=lambda q: q.id)
    cache.placeholders.sort()
    return cache
