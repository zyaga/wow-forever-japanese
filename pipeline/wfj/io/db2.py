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


def text_fields(
    buf: bytes, encrypted: list[tuple[int, int, str]] | None = None, name: str = "db2"
) -> frozenset[int]:
    """The fields that hold text, found from the bytes alone (no column map): which columns of a table carry
    text.

    A dense table's field is text when it is unpacked and 32 bits wide, at least one row holds a non-zero
    value, and every non-zero value points at the start of a NUL-terminated UTF-8 string in the string tables
    (the byte before it is a NUL). A sparse table's strings are inline, so its text fields are the one
    assignment of string or number to each 32-bit field under which every record parses to exactly its size;
    more than one such assignment raises rather than picking one. Skipped sections are left out, as `read`
    leaves them out."""
    try:
        return _text_fields(buf, encrypted or [], name)
    except Db2Error:
        raise
    except (struct.error, IndexError, ValueError, OverflowError) as e:
        raise Db2Error(f"{name}: truncated or corrupt ({type(e).__name__}: {e})") from e


def _readable_sections(
    buf: bytes, h: Header, sections: list[tuple], encrypted: list[tuple[int, int, str]]
) -> list[tuple[int, tuple, int]]:
    """(section number, section, records before it) for every section `_read_section` would not skip."""
    out, record_base, sparse = [], 0, bool(h.flags & FLAG_SPARSE)
    for sn, sec in enumerate(sections):
        key, offset, count, str_size, records_end, id_size, _rel, _maps, _copies = sec
        records_size = records_end - offset if sparse else count * h.record_size
        end = offset + records_size + str_size + id_size
        hit = any(e[0] < end and offset < e[1] for e in encrypted)
        zeroed = key != 0 and not any(buf[offset : offset + records_size + str_size + id_size])
        if not (hit or zeroed):
            out.append((sn, sec, record_base))
        record_base += count
    return out


def _text_fields(buf: bytes, encrypted: list[tuple[int, int, str]], name: str) -> frozenset[int]:
    h = read_header(buf, name)
    if h.record_count == 0:
        return frozenset()
    if h.flags & FLAG_SECONDARY_KEY:
        raise Db2Error(f"{name}: secondary-key table (flags {h.flags:#x}) is not implemented")
    sections, storages, _pallet, _common = _header_blocks(buf, h, encrypted, name)
    readable = _readable_sections(buf, h, sections, encrypted)
    if h.flags & FLAG_SPARSE:
        return _sparse_text_fields(buf, readable, storages, name)
    rs = h.record_size
    strings = b"".join(buf[s[1] + s[2] * rs : s[1] + s[2] * rs + s[3]] for s in sections)
    total = h.record_count * rs
    candidates = {
        fn for fn, s in enumerate(storages) if s.kind == NONE and s.size_bits == 32 and s.element_bits == 32
    }
    used: set[int] = set()
    for _sn, sec, base in readable:
        offset, count = sec[1], sec[2]
        for r in range(count):
            if not candidates:
                return frozenset()
            bits = int.from_bytes(buf[offset + r * rs : offset + (r + 1) * rs], "little")
            shift = (base + r) * rs - total
            for fn in list(candidates):
                s = storages[fn]
                v = (bits >> s.offset_bits) & 0xFFFFFFFF
                if not v:
                    continue
                at = shift + s.offset_bits // 8 + v
                if not 0 <= at < len(strings) or (at and strings[at - 1]) or not _is_cstring(strings, at):
                    candidates.discard(fn)
                else:
                    used.add(fn)
    return frozenset(candidates & used)


def _is_cstring(data: bytes, at: int) -> bool:
    end = data.find(b"\0", at)
    if end < 0:
        return False
    try:
        data[at:end].decode("utf-8")
    except UnicodeDecodeError:
        return False
    return True


_CONTROL = frozenset(range(32)) - {9, 10, 13}


def _is_text(raw: bytes) -> bool:
    """UTF-8 with no control character but tab and line breaks: what an inline string holds, and what the
    bytes of a number read as a string almost never are. Only the sparse guess needs it; a dense string is
    already proven by every value pointing at the start of a string (one Forever camera name carries a stray
    0x03)."""
    if _CONTROL.intersection(raw):
        return False
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return True


def _sparse_text_fields(
    buf: bytes, readable: list[tuple[int, tuple, int]], storages: list[Storage], name: str
) -> frozenset[int]:
    records: list[bytes] = []
    for sn, sec, _base in readable:
        index_at = sec[4] + sec[3]  # records end, then the string table
        _ids, _copied, offset_map, _rel = _section_index(buf, sn, sec, index_at, True, name)
        records += [buf[at : at + size] for at, size in offset_map]
    if not records:
        return frozenset()
    widths = []
    for fn, s in enumerate(storages):
        if s.element_bits <= 0 or s.element_bits % 8 or s.size_bits % s.element_bits:
            raise Db2Error(f"{name}: sparse field {fn}: {s.size_bits} bits in elements of {s.element_bits}")
        widths.append(s.size_bits // 8)
    may_be_text = [s.size_bits == 32 and s.element_bits == 32 for s in storages]
    # The sparse tables seen so far keep every string field first (Spell 0-2, ItemSparse 0-4): try those
    # layouts before the search, which a table with many fields can make too slow.
    leading = [
        frozenset(range(k))
        for k in range(len(widths) + 1)
        if all(may_be_text[:k]) and _sparse_fits(records, widths, frozenset(range(k)))
    ]
    if len(leading) > 1:
        raise Db2Error(f"{name}: more than one string layout fits every record")
    if leading:
        return leading[0]
    # otherwise solve on a sample first (fast pruning), then check each answer against every record
    sample = records[:: max(1, len(records) // 200)]
    found: list[frozenset[int]] = []
    for answer in _sparse_assignments(sample, widths, may_be_text, name):
        if _sparse_fits(records, widths, answer):
            found.append(answer)
            if len(found) > 1:
                raise Db2Error(f"{name}: more than one string layout fits every record")
    if not found:
        raise Db2Error(f"{name}: no string layout fits every record")
    return found[0]


def _sparse_assignments(records, widths, may_be_text, name, budget=2_000_000):
    """Every set of string fields under which each sampled record parses to exactly its padded size. A state
    (field, every record's position) that has failed once is not walked again, and a branch stops as soon as a
    record has fewer bytes left than the remaining fields need at their narrowest (a string is at least 1)."""
    n = len(widths)
    least = [0] * (n + 1)
    for fn in range(n - 1, -1, -1):
        least[fn] = least[fn + 1] + (1 if may_be_text[fn] else widths[fn])
    failed: set[tuple[int, tuple[int, ...]]] = set()
    nodes = 0

    def walk(fn, pos, chosen):
        nonlocal nodes
        nodes += 1
        if nodes > budget:
            raise Db2Error(f"{name}: string layout search gave up after {budget} steps")
        state = (fn, tuple(pos))
        if state in failed or any(p + least[fn] > len(rec) for rec, p in zip(records, pos, strict=True)):
            return
        hit = False
        if fn == n:
            fits = zip(records, pos, strict=True)
            if all(len(rec) == (p + 3) & ~3 and not any(rec[p:]) for rec, p in fits):
                hit = True
                yield frozenset(chosen)
        else:
            for answer in walk(fn + 1, [p + widths[fn] for p in pos], chosen):
                hit = True
                yield answer
            ends = _string_ends(records, pos) if may_be_text[fn] else None
            if ends is not None:
                for answer in walk(fn + 1, ends, chosen + [fn]):
                    hit = True
                    yield answer
        if not hit:
            failed.add(state)

    yield from walk(0, [0] * len(records), [])


def _string_ends(records: list[bytes], pos: list[int]) -> list[int] | None:
    """Where each record's string starting at its position ends (past the NUL), or None when one is not a
    NUL-terminated UTF-8 string."""
    ends = []
    for rec, p in zip(records, pos, strict=True):
        end = rec.find(b"\0", p)
        if end < 0 or not _is_text(rec[p:end]):
            return None
        ends.append(end + 1)
    return ends


def _sparse_fits(records: list[bytes], widths: list[int], text: frozenset[int]) -> bool:
    for rec in records:
        p = 0
        for fn, w in enumerate(widths):
            if fn in text:
                end = rec.find(b"\0", p)
                if end < 0 or not _is_text(rec[p:end]):
                    return False
                p = end + 1
            else:
                p += w
            if p > len(rec):
                return False
        if len(rec) != (p + 3) & ~3 or any(rec[p:]):
            return False
    return True
