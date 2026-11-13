"""The client's creature cache, `Cache/WDB/enUS/creaturecache.wdb` → each creature's display ids (ADR-088).

The client writes the cache on a full exit with what the server answered about every creature it asked about,
and empties it on every new client build. The voice panel's head needs only the display ids (the models the
creature is drawn with); names and titles are never read from here.

Framing, as in the quest cache: a 24-byte header (magic `BOMW`, build u32, locale `SUne` = enUS reversed,
three u32 we do not read), then records `[creature id u32][length u32][payload]`, then an 8-byte zero
terminator.

The payload layout is pinned per build, with its evidence, like the quest cache's (`io/wdb.LAYOUTS`):

- a bit-packed block, most significant bit first: title 11, title alt 11, cursor name 6, a leader flag 1, then
  for each of four names the name 11 and the name alt 11 (117 bits, `bits_bytes` bytes);
- the eight name strings back to back (each length counts its NUL);
- `fixed` bytes of fixed fields;
- the display list: count u32, total probability f32, then per display: display id u32, scale f32,
  probability f32;
- more fixed fields, then the title, title alt and cursor name strings.

1.60.1.70938: all 469 records of the client's full cache read this way, every display list adds up, and for
the 421 creatures VMaNGOS also has, 410 first displays are one of VMaNGOS's four (the other 11 are models
Forever replaced).
"""

from __future__ import annotations

import math
import struct
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

MAGIC = b"BOMW"
LOCALE_ENUS = b"SUne"
HEADER_SIZE = 24
RECORD_HEADER = struct.Struct("<II")
DISPLAY = struct.Struct("<Iff")
MAX_DISPLAYS = 8  # no creature measured has more than four; a wilder count means the layout was misread


class CreatureCacheError(ValueError):
    """The file is not a creature cache this reader understands."""


@dataclass(frozen=True)
class Layout:
    build: int
    bits_bytes: int  # the bit-packed lengths block
    head_bits: tuple[int, ...]  # the fields before the names: title, title alt, cursor name, leader flag
    name_bits: int  # each of the eight name lengths
    fixed: int  # bytes between the names and the display list


LAYOUTS: tuple[Layout, ...] = (
    Layout(build=70938, bits_bytes=15, head_bits=(11, 11, 6, 1), name_bits=11, fixed=26),
)


def layout_for(build: int) -> Layout:
    """The layout pinned for a client build. An unknown build is refused: a changed layout fails loudly rather
    than shipping misread display ids."""
    for lay in LAYOUTS:
        if lay.build == build:
            return lay
    known = ", ".join(str(lay.build) for lay in LAYOUTS)
    raise CreatureCacheError(
        f"build {build} has no pinned creature layout (pinned: {known}). Check that every record of the new "
        "cache reads with a pinned layout and that its displays agree with VMaNGOS, then pin it in "
        "io/creature_cache.LAYOUTS"
    )


def _name_lengths(payload: bytes, lay: Layout) -> list[int]:
    if len(payload) < lay.bits_bytes:
        raise ValueError(f"payload of {len(payload)} bytes is shorter than its lengths block")
    value = int.from_bytes(payload[: lay.bits_bytes], "big")
    pos = lay.bits_bytes * 8 - sum(lay.head_bits)
    lengths = []
    for _ in range(8):
        pos -= lay.name_bits
        lengths.append((value >> pos) & ((1 << lay.name_bits) - 1))
    return lengths


def _display_list_offset(payload: bytes, lay: Layout) -> int:
    """Where the display list starts in a record's payload."""
    return lay.bits_bytes + sum(_name_lengths(payload, lay)) + lay.fixed


def decode_displays(payload: bytes, lay: Layout) -> list[int]:
    """The record's display ids in the cache's order. Raises ValueError when the list does not check."""
    at = _display_list_offset(payload, lay)
    if at + 8 > len(payload):
        raise ValueError("display list runs past the record")
    count, total = struct.unpack_from("<If", payload, at)
    if count > MAX_DISPLAYS or at + 8 + count * DISPLAY.size > len(payload):
        raise ValueError(f"display list of {count} entries does not fit the record")
    entries = [DISPLAY.unpack_from(payload, at + 8 + k * DISPLAY.size) for k in range(count)]
    got = sum(e[2] for e in entries)
    if not math.isfinite(got) or not math.isfinite(total) or abs(got - total) > 1e-3:
        raise ValueError(f"display list probabilities sum to {got}, not its total {total}")
    return [int(e[0]) for e in entries if e[0]]


def _open(path: Path) -> tuple[str, bytes]:
    try:
        buf = Path(path).read_bytes()
    except OSError as e:
        raise CreatureCacheError(f"{path}: {e.strerror or e}") from e
    name = Path(path).name
    if len(buf) < HEADER_SIZE or buf[:4] != MAGIC:
        raise CreatureCacheError(f"{name}: not a creature cache (magic {buf[:4]!r}, want {MAGIC!r})")
    if buf[8:12] != LOCALE_ENUS:
        raise CreatureCacheError(f"{name}: locale {buf[8:12][::-1]!r} is not enUS")
    return name, buf


def _records(name: str, buf: bytes) -> Iterator[tuple[int, bytes]]:
    seen: set[int] = set()
    off = HEADER_SIZE
    while True:
        if off + RECORD_HEADER.size > len(buf):
            raise CreatureCacheError(f"{name}: ends at byte {len(buf)} without the zero terminator")
        cid, length = RECORD_HEADER.unpack_from(buf, off)
        off += RECORD_HEADER.size
        if cid == 0 and length == 0:
            break
        if off + length > len(buf):
            raise CreatureCacheError(f"{name}: creature {cid}: record of {length} bytes runs past the end")
        if cid in seen:  # a duplicate is reported, never resolved silently
            raise CreatureCacheError(f"{name}: creature {cid} is cached twice")
        seen.add(cid)
        yield cid, buf[off : off + length]
        off += length
    if off != len(buf):
        raise CreatureCacheError(f"{name}: {len(buf) - off} bytes after the zero terminator")


def read_build(path: Path) -> int:
    """The client build in the cache's header. Reads no record, so a build whose layout is not pinned yet can
    still be copied before the next client build empties the cache."""
    _, buf = _open(path)
    return struct.unpack_from("<I", buf, 4)[0]


def read_displays(path: Path) -> tuple[int, dict[int, list[int]]]:
    """(build, creature id → its display ids) for every creature in the cache, read against the layout pinned
    for its build."""
    name, buf = _open(path)
    build = struct.unpack_from("<I", buf, 4)[0]
    lay = layout_for(build)
    out: dict[int, list[int]] = {}
    for cid, payload in _records(name, buf):
        try:
            out[cid] = decode_displays(payload, lay)
        except ValueError as e:
            raise CreatureCacheError(f"{name}: creature {cid}: {e}") from e
    return build, out
