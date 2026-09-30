"""The client's hotfix cache (`Cache/ADB/<locale>/DBCache.bin`) → table row changes (ADR-021).

The server patches client tables after a build ships; the client keeps those rows here, never in the archive.
Layout verified on Classic Era 1.15.9.69722 (1,384 entries, the file consumed exactly):

- header, 44 bytes: magic `XFTH`, u32 version (9), u32 build, 32-byte hash;
- entries: magic `XFTH`, i32 region, i32 push id, u32 unique id, u32 table hash (the DB2 header's), u32 record
  id, u32 data size, u8 status + 3 bytes, then the record data.

Entries are applied in (push id, file order) order and the last entry of a record decides it (the stated rule
for duplicates): status 1 with data replaces the row; any other entry (2 removed, 3 invalidated, 4
not public, or status 1 without data) removes it. This follows wowdev/DBCD's hotfix reader (HotfixReader.cs,
DefaultProcessor); the client's own ordering is not verified. Record data holds the fields back to back with
strings NUL-terminated. A table's leading string fields can be read without the field types
(`leading_strings`); the rest needs each field's declared type, which the DB2 file does not carry for packed
fields (its field structure holds 0 bits there): `decode_fields` takes them from the table's column map.
The layout follows wowdev/DBCD's hotfix reader (DBCD.IO/Readers/HTFXReader.cs, HTFXRow.GetFields,
commit 2d50ae2): the fields in definition order at their declared sizes, a non-inline id left out (the entry's
record id is the id), a non-inline relation read from the data like any field, and absent when the build has
no relationship map. A record that does not fit raises, so a wrong layout stops the table instead of writing
shifted values.

Checked on Forever 1.60.1.69913's own cache: 27,428 entries read to the end; ItemEffect
(whose Forever record has no relation) and ItemXItemEffect decode exactly. ItemSubClass and QuestV2 have had
no hotfix in any cache seen. All 812 multi-entry records there are in push-id order in the file, so the
ordering rule above is consistent with it but not proven. Read-only; a file this reader does not understand
raises DbcacheError."""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

MAGIC = b"XFTH"
VERSION = 9
HEADER_SIZE = 44
ENTRY = struct.Struct("<4siiIIIIB3x")
VALID, REMOVED = 1, 2
STATUSES = (1, 2, 3, 4)


class DbcacheError(ValueError):
    """The file is not a hotfix cache this reader understands."""


@dataclass(frozen=True)
class Hotfix:
    push_id: int
    status: int
    data: bytes
    order: int = 0  # position in the file: the tie-break between equal push ids

    @property
    def replaces(self) -> bool:
        return self.status == VALID and bool(self.data)


@dataclass
class HotfixCache:
    build: int
    by_table: dict[int, dict[int, Hotfix]]  # table hash → record id → the entry that decides it


def read(path: Path) -> HotfixCache:
    try:
        buf = Path(path).read_bytes()
    except OSError as e:
        raise DbcacheError(f"{path}: {e.strerror or e}") from e
    name = Path(path).name
    if len(buf) < HEADER_SIZE or buf[:4] != MAGIC:
        raise DbcacheError(f"{name}: not a hotfix cache (magic {buf[:4]!r})")
    version, build = struct.unpack_from("<II", buf, 4)
    if version != VERSION:
        raise DbcacheError(f"{name}: version {version} is not {VERSION}")
    cache = HotfixCache(build, {})
    at, order = HEADER_SIZE, 0
    while at < len(buf):
        if at + ENTRY.size > len(buf):
            raise DbcacheError(f"{name}: entry at byte {at} is cut short")
        magic, _, push, _, table, record, size, status = ENTRY.unpack_from(buf, at)
        if magic != MAGIC:
            raise DbcacheError(f"{name}: entry at byte {at} has magic {magic!r}")
        if status not in STATUSES:
            raise DbcacheError(f"{name}: entry at byte {at} has unknown status {status}")
        at += ENTRY.size
        if at + size > len(buf):
            raise DbcacheError(f"{name}: record {record} of table {table:08x} runs past the end of the file")
        rows = cache.by_table.setdefault(table, {})
        entry = Hotfix(push, status, buf[at : at + size], order)
        prior = rows.get(record)
        if prior is None or (push, order) > (prior.push_id, prior.order):
            rows[record] = entry
        order += 1
        at += size
    return cache


def leading_strings(data: bytes, count: int) -> list[str]:
    """The first `count` NUL-terminated UTF-8 strings of a record (ValueError when the data holds fewer)."""
    out, at = [], 0
    for n in range(count):
        end = data.find(b"\0", at)
        if end < 0:
            raise ValueError(f"string {n} has no terminator")
        out.append(data[at:end].decode("utf-8"))
        at = end + 1
    return out


# Declared field types (WoWDBDefs' `<8>`, `<u16>`, …; `str` a string / locstring): byte size, signed.
TYPES: dict[str, tuple[int, bool]] = {
    "i8": (1, True),
    "u8": (1, False),
    "i16": (2, True),
    "u16": (2, False),
    "i32": (4, True),
    "u32": (4, False),
}


def decode_fields(data: bytes, types: tuple[str, ...]) -> list[str | int]:
    """Every field of a hotfix record, in order: `str` NUL-terminated UTF-8, integers little-endian at their
    declared size and sign. The record must be used up: at most 3 zero bytes may follow (alignment padding);
    anything else raises ValueError naming the byte count, since fields read at the wrong size would shift
    every later value."""
    out: list[str | int] = []
    at = 0
    for n, t in enumerate(types):
        if t == "str":
            end = data.find(b"\0", at)
            if end < 0:
                raise ValueError(f"string field {n} has no terminator")
            out.append(data[at:end].decode("utf-8"))
            at = end + 1
            continue
        size, signed = TYPES[t]
        if at + size > len(data):
            raise ValueError(f"field {n} ({t}) runs past the {len(data)}-byte record")
        out.append(int.from_bytes(data[at : at + size], "little", signed=signed))
        at += size
    # Zero bytes may only pad the record out to a 4-byte boundary (as a sparse DB2 record is): a field read
    # too small leaves a longer or unaligned tail and stops here instead of shifting every later value.
    if len(data) not in (at, (at + 3) & ~3) or any(data[at:]):
        raise ValueError(f"record of {len(data)} bytes, its {len(types)} fields use {at}")
    return out
