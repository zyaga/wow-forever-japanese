"""A minimal WDC5 writer for tests: 32-bit uncompressed fields only, dense or sparse, one or more
sections, id lists and copy tables. Real-format coverage comes from the real fixtures in tests/fixtures/db2 and
the install proof; this writer builds the cases a small real table does not have (sparse records, encrypted
sections, malformed bytes)."""

from __future__ import annotations

import struct

from wfj.io import db2


def wdc5(
    sections: list[list[tuple[int, list[int | str]]]],
    string_fields: set[int] = frozenset(),
    *,
    field_count: int,
    sparse: bool = False,
    copies: list[tuple[int, int]] = (),
    layout_hash: int = 0x1234ABCD,
    version: int = 5,
    keys: list[int] | None = None,
    extra_flags: int = 0,
    table_hash: int = 0,
) -> tuple[bytes, list[tuple[int, int]]]:
    """(file bytes, [(start, end) of each section's bytes]). Rows are (id, values); strings go in
    `string_fields`. `copies` go into the last section. `keys`: each section's TACT key name (0 = none)."""
    record_size = 4 * field_count
    all_rows = [r for s in sections for r in s]
    total_records = len(all_rows) * record_size
    fields = b"".join(struct.pack("<hH", 0, 4 * n) for n in range(field_count))
    storage = b"".join(struct.pack("<HHIIIII", 32 * n, 32, 0, 0, 0, 0, 0) for n in range(field_count))
    head_size = db2.HEADER.size + len(sections) * db2.SECTION.size + len(fields) + len(storage)

    bodies, headers, at, record_base = [], [], head_size, 0
    string_sizes: list[int] = []  # per section, for offsets into the concatenated string tables
    for sn, rows in enumerate(sections):
        section_copies = list(copies) if sn == len(sections) - 1 else []
        start = at
        if sparse:
            records, offset_map = b"", []
            for _, values in rows:
                rec = b""
                for fn, v in enumerate(values):
                    rec += v.encode() + b"\0" if fn in string_fields else struct.pack("<I", v & 0xFFFFFFFF)
                rec += b"\0" * (-len(rec) % 4)
                offset_map.append((at + len(records), len(rec)))
                records += rec
            strings = b""
        else:
            records, strings = b"", b""
            str_pos = {}
            for r, (_, values) in enumerate(rows):
                for fn, v in enumerate(values):
                    if fn in string_fields:
                        if not v:
                            records += struct.pack("<I", 0)
                            continue
                        if v not in str_pos:
                            str_pos[v] = sum(string_sizes) + len(strings)
                            strings += v.encode() + b"\0"
                        field_pos = (record_base + r) * record_size + 4 * fn
                        records += struct.pack("<I", str_pos[v] + total_records - field_pos)
                    else:
                        records += struct.pack("<I", v & 0xFFFFFFFF)
            offset_map = []
        string_sizes.append(len(strings))
        ids = b"".join(struct.pack("<I", i) for i, _ in rows)
        copy = b"".join(struct.pack("<II", new, old) for new, old in section_copies)
        omap = b"".join(struct.pack("<IH", o, s) for o, s in offset_map)
        map_ids = ids if sparse else b""
        body = records + strings + ids + copy + omap + map_ids
        headers.append(
            db2.SECTION.pack(
                (keys or [0] * len(sections))[sn], start, len(rows), len(strings), start + len(records) if sparse else 0, len(ids), 0,
                len(offset_map), len(section_copies),
            )
        )
        bodies.append(body)
        at += len(body)
        record_base += len(rows)
    ids_all = [i for i, _ in all_rows] or [0]
    header = db2.HEADER.pack(
        b"WDC5", version, b"\0" * 128, len(all_rows), field_count, record_size,
        0, table_hash, layout_hash, min(ids_all), max(ids_all), 0, ((0x1 | 0x4) if sparse else 0x4) | extra_flags, 0,
        field_count, 0, 0, 24 * field_count, 0, 0, len(sections),
    )
    buf = header + b"".join(headers) + fields + storage + b"".join(bodies)
    spans, at = [], head_size
    for body in bodies:
        spans.append((at, at + len(body)))
        at += len(body)
    return buf, spans

