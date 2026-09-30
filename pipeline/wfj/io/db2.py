"""WDC5 client tables (`DBFilesClient/*.db2`) → rows by id (ADR-021).

A DB2 file names no columns; `io/client_tables.py` says which field is which. Layout verified on
Classic Era 1.15.9.69722 against wago.tools' CSVs of the same build (all eight tables the pipeline reads):

- header, 204 bytes: `WDC5`, u32 version (5), 128-byte schema string, then u32 record count, field count,
  record size, string table size, table hash, layout hash, min id, max id, locale; u16 flags, u16 id index;
  u32 total field count, bitpacked data offset, lookup column count, field storage info size, common data
  size, pallet data size, section count;
- section headers, 40 bytes each: u64 TACT key name, u32 file offset, record count, string table size,
  records end, id list size, relationship data size, offset map id count, copy table count;
- field structures (i16 bits = 32 - value, u16 byte offset) × field count; field storage info (24 bytes: u16
  offset bits, u16 size bits, u32 additional data size, u32 storage type, u32 × 3 values) × total field count;
  pallet data; common data;
- per section at its offset: records, string table, id list, copy table, offset map ((u32 offset, u16 size)
  per record, sparse tables only), relationship map (u32 count, min, max, then (foreign id, record index)
  pairs), offset map ids.

Storage types: 0 none, 1 bitpacked, 2 common data, 3 pallet, 4 pallet array, 5 bitpacked signed. A string
field holds a u32 offset from its own position in the concatenation of every section's records into the
concatenation of every section's string table (offset 0: the empty string). A sparse table (flag 0x1:
ItemSparse, Spell) stores each record at its offset map entry with its fields back to back (strings inline
and NUL-terminated, other fields at their storage width, the record zero-padded to a multiple of 4), and
takes its ids from the offset map id list.

A section whose bytes the archive could not decrypt (an encrypted frame overlaps it, or it has a TACT key and
is zero-filled in the file) is skipped and counted, never read as zeros; a copy-table row whose source sits
in a skipped section is counted as hidden. Copies resolve after every section is read; a self-copy is ignored.
Encrypted bytes inside the header blocks (pallet, common data), secondary-key tables (flag 0x2) and anything
else the reader does not understand raise Db2Error naming the table.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field

MAGIC = b"WDC5"
HEADER = struct.Struct("<4sI128s9IHH7I")
SECTION = struct.Struct("<Q8I")
STORAGE = struct.Struct("<HHIIIII")
FLAG_SPARSE = 0x1
FLAG_SECONDARY_KEY = 0x2
NONE, BITPACKED, COMMON, PALLET, PALLET_ARRAY, BITPACKED_SIGNED = range(6)


class Db2Error(ValueError):
    """The bytes are not a DB2 table this reader understands."""


@dataclass(frozen=True)
class Storage:
    offset_bits: int
    size_bits: int
    additional: int
    kind: int
    v1: int
    v2: int
    v3: int
    element_bits: int  # from the field structure; an unpacked array holds size_bits // element_bits values


@dataclass
class Skipped:
    section: int
    key_name: str
    records: int


@dataclass
class Db2Table:
    layout_hash: int
    table_hash: int
    field_count: int
    rows: dict[int, tuple] = field(default_factory=dict)
    # field index → foreign id per row id, when the table stores that field in its relationship map
    relation: dict[int, int] = field(default_factory=dict)
    skipped: list[Skipped] = field(default_factory=list)
    copies_hidden: int = 0  # copy-table rows whose source sits in a skipped section


def _u32(buf: bytes, at: int) -> int:
    return struct.unpack_from("<I", buf, at)[0]


@dataclass(frozen=True)
class Header:
    record_count: int
    field_count: int
    record_size: int
    table_hash: int
    layout_hash: int
    flags: int
    id_index: int
    total_fields: int
    storage_size: int
    common_size: int
    pallet_size: int
    section_count: int


def read_header(buf: bytes, name: str = "db2") -> Header:
    """The fixed header only: enough to check a table's layout hash before decoding any row."""
    if len(buf) < HEADER.size or buf[:4] != MAGIC:
        raise Db2Error(f"{name}: magic {buf[:4]!r} is not {MAGIC!r}")
    h = HEADER.unpack_from(buf, 0)
    if h[1] != 5:
        raise Db2Error(f"{name}: WDC5 version {h[1]} is not 5")
    return Header(h[3], h[4], h[5], h[7], h[8], h[12], h[13], h[14], h[17], h[18], h[19], h[20])


def read(
    buf: bytes,
    string_fields: frozenset[int] = frozenset(),
    encrypted: list[tuple[int, int, str]] | None = None,
    name: str = "db2",
) -> Db2Table:
    """Every readable row. `string_fields`: field indices holding string offsets. `encrypted`: (start, end,
    key name) byte ranges the archive could not decrypt; a section overlapping one is skipped. Truncated or
    corrupt bytes raise Db2Error naming the table, never a bare struct / index error."""
    try:
        return _read(buf, string_fields, encrypted or [], name)
    except Db2Error:
        raise
    except (struct.error, IndexError, ValueError, OverflowError) as e:
        raise Db2Error(f"{name}: truncated or corrupt ({type(e).__name__}: {e})") from e


@dataclass
class _Fields:
    """What decoding a record takes besides its own bytes: the field layout and the shared data blocks."""

    storages: list[Storage]
    string_fields: frozenset[int]
    pallet: bytes
    pallet_at: list[int]
    common_maps: list[dict[int, int] | None]
    strings: bytes  # every section's string table, concatenated in section order (dense tables only)
    name: str

    def fill_common(self, values: list, rid: int) -> tuple:
        for fn, cm in enumerate(self.common_maps):
            if cm is not None:
                values[fn] = cm.get(rid, self.storages[fn].v1)
        return tuple(values)


def _read(
    buf: bytes, string_fields: frozenset[int], encrypted: list[tuple[int, int, str]], name: str
) -> Db2Table:
    h = read_header(buf, name)
    field_count = h.field_count
    if h.flags & FLAG_SECONDARY_KEY:
        raise Db2Error(f"{name}: secondary-key table (flags {h.flags:#x}) is not implemented")
    if h.total_fields != field_count or h.storage_size != 24 * field_count:
        raise Db2Error(
            f"{name}: {field_count} fields but {h.total_fields} total / {h.storage_size // 24} storage infos"
        )
    sections, storages, pallet, common = _header_blocks(buf, h, encrypted, name)
    pallet_at = _pallet_offsets(storages, h.pallet_size, name)
    common_maps = _common_maps(storages, common, h.common_size, name)
    _check_sections(h, sections, storages, name)
    record_size = h.record_size
    # string tables of every section concatenated in section order, skipped ones included (dense tables only)
    strings = b"".join(
        buf[sec[1] + sec[2] * record_size : sec[1] + sec[2] * record_size + sec[3]] for sec in sections
    )
    f = _Fields(storages, string_fields, pallet, pallet_at, common_maps, strings, name)
    table = Db2Table(h.layout_hash, h.table_hash, field_count)
    copies_all: list[tuple[int, int]] = []
    record_base = 0
    for sn, section in enumerate(sections):
        copies_all += _read_section(buf, h, sn, section, encrypted, f, table, record_base)
        record_base += section[2]
    _resolve_copies(table, copies_all, f)
    return table


def _header_blocks(
    buf: bytes, h: Header, encrypted: list[tuple[int, int, str]], name: str
) -> tuple[list[tuple], list[Storage], bytes, bytes]:
    """The blocks after the fixed header → (section headers, field storages, pallet data, common data)."""
    field_count = h.field_count
    at = HEADER.size
    blocks_end = at + h.section_count * SECTION.size + field_count * 4 + h.storage_size + h.pallet_size
    blocks_end += h.common_size
    if blocks_end > len(buf):
        raise Db2Error(f"{name}: header blocks run past the file")
    sections = [SECTION.unpack_from(buf, at + n * SECTION.size) for n in range(h.section_count)]
    first_section = min((sec[1] for sec in sections), default=len(buf))
    if any(e[0] < max(first_section, blocks_end) for e in encrypted):
        raise Db2Error(f"{name}: encrypted bytes inside the header blocks (pallet / common data unreadable)")
    at += h.section_count * SECTION.size
    element_bits = [32 - struct.unpack_from("<hH", buf, at + n * 4)[0] for n in range(field_count)]
    at += field_count * 4
    storages = []
    for n in range(field_count):
        st = STORAGE.unpack_from(buf, at + n * STORAGE.size)
        if st[3] > BITPACKED_SIGNED:
            raise Db2Error(f"{name}: field {n} storage type {st[3]} is unknown")
        storages.append(Storage(*st, element_bits=element_bits[n]))
    at += h.storage_size
    pallet = buf[at : at + h.pallet_size]
    common = buf[at + h.pallet_size : at + h.pallet_size + h.common_size]
    return sections, storages, pallet, common


def _pallet_offsets(storages: list[Storage], pallet_size: int, name: str) -> list[int]:
    """Where each field's values start in the pallet data."""
    pallet_at, off = [], 0
    for st in storages:
        pallet_at.append(off)
        off += st.additional if st.kind in (PALLET, PALLET_ARRAY) else 0
    if off != pallet_size:
        raise Db2Error(f"{name}: pallet data of {pallet_size} bytes, fields use {off}")
    return pallet_at


def _common_maps(
    storages: list[Storage], common: bytes, common_size: int, name: str
) -> list[dict[int, int] | None]:
    """Each common-data field's {id: value}; None for every other field."""
    off = 0
    common_maps: list[dict[int, int] | None] = []
    for st in storages:
        if st.kind == COMMON:
            if st.additional % 8:
                raise Db2Error(f"{name}: common data block of {st.additional} bytes is not id/value pairs")
            common_maps.append(
                dict(struct.unpack_from("<II", common, off + k) for k in range(0, st.additional, 8))
            )
            off += st.additional
        else:
            common_maps.append(None)
    if off != common_size:
        raise Db2Error(f"{name}: common data of {common_size} bytes, fields use {off}")
    return common_maps


def _check_sections(h: Header, sections: list[tuple], storages: list[Storage], name: str) -> None:
    """The header facts that hold across sections: an id source, the record total, a sparse layout."""
    field_count = h.field_count
    if not 0 <= h.id_index < field_count and any(sec[5] == 0 and sec[7] == 0 for sec in sections):
        raise Db2Error(f"{name}: id field {h.id_index} is not one of {field_count} fields")

    if sum(sec[2] for sec in sections) != h.record_count:
        raise Db2Error(
            f"{name}: sections hold {sum(sec[2] for sec in sections)} records, header {h.record_count}"
        )
    if h.flags & FLAG_SPARSE and any(st.kind != NONE for st in storages):
        raise Db2Error(
            f"{name}: sparse table with a packed field (storage types {[st.kind for st in storages]})"
        )


def _read_section(
    buf: bytes,
    h: Header,
    sn: int,
    section: tuple,
    encrypted: list[tuple[int, int, str]],
    f: _Fields,
    table: Db2Table,
    record_base: int,
) -> list[tuple[int, int]]:
    """Read one section's records into `table`, or record it as skipped → its copy-table rows."""
    name, record_size, sparse = f.name, h.record_size, bool(h.flags & FLAG_SPARSE)
    key, offset, count, str_size, records_end, id_size, rel_size, map_ids, copies = section
    records_size = records_end - offset if sparse else count * record_size
    end = offset + records_size + str_size + id_size + copies * 8 + map_ids * 6 + rel_size + map_ids * 4
    if records_size < 0 or end > len(buf):
        raise Db2Error(f"{name}: section {sn} runs past the file")
    hit = [e for e in encrypted if e[0] < end and offset < e[1]]
    # a keyed section the client holds no key for is skipped: its frames were encrypted (hit), or the file
    # already carries it zero-filled
    zeroed = key != 0 and not any(buf[offset : offset + records_size + str_size + id_size])
    if hit or zeroed:
        table.skipped.append(Skipped(sn, hit[0][2] if hit else f"{key:016x}", count))
        return []
    index_at = offset + records_size + str_size
    ids, copied, offset_map, rel = _section_index(buf, sn, section, index_at, sparse, name)
    total_records_bytes = h.record_count * record_size
    for r in range(count):
        if sparse:
            rec_at, rec_size = offset_map[r]
            if not (offset <= rec_at and rec_at + rec_size <= offset + records_size):
                raise Db2Error(f"{name}: record {r} of section {sn} lies outside its records block")
            values = _sparse_values(buf[rec_at : rec_at + rec_size], f.storages, f.string_fields, name)
        else:
            shift = (record_base + r) * record_size - total_records_bytes
            values = _dense_values(buf, offset + r * record_size, record_size, f, shift)
        rid = ids[r] if ids else values[h.id_index]
        if isinstance(rid, list):
            raise Db2Error(f"{name}: id field {h.id_index} is an array")
        if rid in table.rows:  # a duplicate is reported, never last-wins
            raise Db2Error(f"{name}: id {rid} appears twice")
        table.rows[rid] = f.fill_common(values, rid)
        if r in rel:  # a table may map only some records (ItemSubClass: 71 of 72)
            table.relation[rid] = rel[r]
    return copied


def _section_index(
    buf: bytes, sn: int, section: tuple, at: int, sparse: bool, name: str
) -> tuple[list[int], list[tuple[int, int]], list[tuple[int, int]], dict[int, int]]:
    """The blocks after a section's string table, from `at` → (ids, copy-table rows, offset map,
    {record index: foreign id})."""
    _key, _offset, count, _str_size, _records_end, id_size, rel_size, map_ids, copies = section
    ids = list(struct.unpack_from(f"<{id_size // 4}I", buf, at)) if id_size else []
    if id_size and len(ids) != count:
        raise Db2Error(f"{name}: section {sn} id list has {len(ids)} ids for {count} records")
    at += id_size
    copied = [struct.unpack_from("<II", buf, at + 8 * k) for k in range(copies)]
    at += copies * 8
    offset_map = [struct.unpack_from("<IH", buf, at + 6 * k) for k in range(map_ids)]
    at += map_ids * 6
    rel: dict[int, int] = {}
    if rel_size:
        n_rel = _u32(buf, at)
        if 12 + n_rel * 8 != rel_size:
            raise Db2Error(
                f"{name}: section {sn} relationship map of {rel_size} bytes holds {n_rel} entries"
            )
        for k in range(n_rel):
            foreign, index = struct.unpack_from("<II", buf, at + 12 + 8 * k)
            rel[index] = foreign
        at += rel_size
    if map_ids:
        map_id_list = list(struct.unpack_from(f"<{map_ids}I", buf, at))
        if ids and ids != map_id_list:
            raise Db2Error(f"{name}: section {sn} id list and offset map ids differ")
        ids = map_id_list
    if sparse and len(offset_map) != count:
        raise Db2Error(
            f"{name}: sparse section {sn} has {len(offset_map)} offset map entries for {count} records"
        )
    return ids, copied, offset_map, rel


def _resolve_copies(table: Db2Table, copies_all: list[tuple[int, int]], f: _Fields) -> None:
    """Add the copy-table rows; they resolve after every section is read, since a source may sit in a later
    section."""
    name = f.name
    for new_id, src_id in copies_all:
        if new_id == src_id:
            continue  # a self-copy carries nothing
        if new_id in table.rows:
            raise Db2Error(f"{name}: copied id {new_id} appears twice")
        src = table.rows.get(src_id)
        if src is None:
            if table.skipped:  # its source sits in a section we could not read
                table.copies_hidden += 1
                continue
            raise Db2Error(f"{name}: copy of id {src_id} which does not exist")
        table.rows[new_id] = f.fill_common(list(src), new_id)
        if src_id in table.relation:
            table.relation[new_id] = table.relation[src_id]


def _dense_values(buf: bytes, rec_at: int, record_size: int, f: _Fields, string_shift: int) -> list:
    name = f.name
    bits = int.from_bytes(buf[rec_at : rec_at + record_size], "little")
    values: list = []
    for fn, s in enumerate(f.storages):
        v = _value(bits, s, fn, f.pallet, f.pallet_at[fn], name)
        if fn in f.string_fields:
            if s.kind != NONE or isinstance(v, list):
                raise Db2Error(f"{name}: string field {fn} is packed or an array")
            if v:  # 0: the empty string
                at = string_shift + s.offset_bits // 8 + v
                if not 0 <= at < len(f.strings):
                    raise Db2Error(f"{name}: field {fn} points past the string tables")
                v = _cstring(f.strings, at, name)
            else:
                v = ""
        values.append(v)
    return values


def _sparse_values(rec: bytes, storages, string_fields, name):
    values: list = []
    at = 0
    for fn, s in enumerate(storages):
        if fn in string_fields:
            end = rec.find(b"\0", at)
            if end < 0:
                raise Db2Error(f"{name}: inline string of field {fn} has no terminator")
            try:
                values.append(rec[at:end].decode("utf-8"))
            except UnicodeDecodeError as e:
                raise Db2Error(f"{name}: inline string of field {fn} is not UTF-8") from e
            at = end + 1
            continue
        width = s.element_bits
        if width <= 0 or width % 8 or s.size_bits % width:
            raise Db2Error(f"{name}: sparse field {fn}: {s.size_bits} bits in elements of {width}")
        n = s.size_bits // width
        size = width // 8
        if at + n * size > len(rec):
            raise Db2Error(f"{name}: sparse field {fn} runs past its record")
        items = [int.from_bytes(rec[at + k * size : at + (k + 1) * size], "little") for k in range(n)]
        values.append(items[0] if n == 1 else items)
        at += n * size
    # a sparse record is padded with zero bytes to a multiple of 4
    if len(rec) != (at + 3) & ~3 or any(rec[at:]):
        raise Db2Error(f"{name}: sparse record of {len(rec)} bytes, fields use {at}")
    return values


def _value(bits: int, s: Storage, fn: int, pallet: bytes, pallet_at: int, name: str):
    if s.size_bits == 0:
        return 0 if s.kind != COMMON else None
    raw = (bits >> s.offset_bits) & ((1 << s.size_bits) - 1)
    if s.kind == NONE:
        width = s.element_bits
        if width <= 0 or s.size_bits % width:
            raise Db2Error(f"{name}: field {fn}: {s.size_bits} bits is not a multiple of {width}")
        if s.size_bits == width:
            return raw
        return [(raw >> (k * width)) & ((1 << width) - 1) for k in range(s.size_bits // width)]
    if s.kind == BITPACKED:
        return raw
    if s.kind == BITPACKED_SIGNED:
        return raw - (1 << s.size_bits) if raw >> (s.size_bits - 1) else raw
    if s.kind == COMMON:
        return None  # filled from the common data by id
    count = 1 if s.kind == PALLET else s.v3  # PALLET_ARRAY holds `count` values per entry
    if (raw + 1) * count * 4 > s.additional:
        raise Db2Error(f"{name}: field {fn} pallet index {raw} is past its {s.additional // 4} values")
    items = [_u32(pallet, pallet_at + (raw * count + k) * 4) for k in range(count)]
    return items[0] if count == 1 else items


def _cstring(strings: bytes, at: int, name: str) -> str:
    end = strings.find(b"\0", at)
    if end < 0:
        raise Db2Error(f"{name}: string at {at} has no terminator")
    try:
        return strings[at:end].decode("utf-8")
    except UnicodeDecodeError as e:
        raise Db2Error(f"{name}: string at {at} is not UTF-8") from e
