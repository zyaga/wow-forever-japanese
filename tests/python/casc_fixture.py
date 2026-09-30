"""Build a minimal local archive in a temp folder: `.build.info`, a build config, one index, one data
file, an encoding file and a root, in the layouts `wfj.io.casc` reads (verified on Classic Era 1.15.9.69722).
Files are stored as BLTE: one `N` frame, or (for `chunks`) a chunk table whose frames are `N`, or `E` where the
chunk is listed as encrypted."""

from __future__ import annotations

import hashlib
import struct
from pathlib import Path

from wfj.io import casc

PRODUCT = "wow_test"
VERSION = "1.15.9.99999"
ENC_KEY_NAME = bytes.fromhex("0123456789abcdef")


def blte_single(data: bytes) -> bytes:
    return b"BLTE" + struct.pack(">I", 0) + b"N" + data


def blte_chunks(data: bytes, cuts: list[int], encrypted: set[int] = frozenset()) -> bytes:
    """Chunks split at `cuts` (byte offsets); chunk numbers in `encrypted` become `E` frames."""
    bounds = [0, *cuts, len(data)]
    frames, table = [], b""
    for n in range(len(bounds) - 1):
        part = data[bounds[n] : bounds[n + 1]]
        if n in encrypted:
            frame = b"E" + bytes([8]) + ENC_KEY_NAME[::-1] + b"\4\0\0\0\0S" + b"\x99" * len(part)
        else:
            frame = b"N" + part
        frames.append(frame)
        table += struct.pack(">II", len(frame), len(part)) + hashlib.md5(frame).digest()
    header_size = 12 + len(table)
    return b"BLTE" + struct.pack(">I", header_size) + b"\x0f" + len(frames).to_bytes(3, "big") + table + b"".join(frames)


def build(
    root: Path,
    files: dict[str, bytes],
    *,
    blobs: dict[str, bytes] | None = None,
    build_info_rows: list[tuple[str, str, str]] | None = None,
    index_version: int = 7,
    offset_bits: int = 30,
    named: bool = True,
    blank_headers: bool = False,
) -> Path:
    """An install at `root` holding `files` ({client path: bytes}); `blobs` overrides a file's stored BLTE blob.
    FileDataIDs are 1000, 1001, … in path order. `build_info_rows`: (product, version, Active). `named=False`
    writes a root without name hashes. `blank_headers=True` zeroes each archive entry's 30-byte header, the
    way the Forever beta client writes them: the payload still follows at +30. Returns root."""
    blobs = blobs or {}
    data_dir = root / "Data" / "data"
    data_dir.mkdir(parents=True)
    stored: list[tuple[bytes, bytes]] = []  # (ekey, blob)
    content: dict[bytes, tuple[bytes, int]] = {}  # ckey → (ekey, size)

    def put(raw: bytes, blob: bytes | None = None) -> tuple[bytes, bytes]:
        blob = blob if blob is not None else blte_single(raw)
        ckey, ekey = hashlib.md5(raw).digest(), hashlib.md5(blob).digest()
        stored.append((ekey, blob))
        content[ckey] = (ekey, len(raw))
        return ckey, ekey

    names = sorted(files)
    fdids = {p: 1000 + n for n, p in enumerate(names)}
    ckeys = {p: put(files[p], blobs.get(p))[0] for p in names}

    root_file = b"TSFM" + struct.pack("<IIIII", 24, 2, len(names), len(names) if named else 0, 0)
    root_file += struct.pack("<IIIIB", len(names), casc.LOCALE_ENUS, 0 if named else casc.NO_NAME_HASH, 0, 0)
    prev = -1
    for p in names:
        root_file += struct.pack("<I", fdids[p] - prev - 1)
        prev = fdids[p]
    root_file += b"".join(ckeys[p] for p in names)
    if named:
        root_file += b"".join(struct.pack("<Q", casc.name_hash(p)) for p in names)
    root_ckey, _ = put(root_file)

    page = b""
    for ck in sorted(content):
        ek, size = content[ck]
        page += b"\1" + size.to_bytes(5, "big") + ck + ek
    page = page.ljust(4096, b"\0")
    first = sorted(content)[0]
    encoding = b"EN\1\x10\x10" + struct.pack(">HHII", 4, 4, 1, 0) + b"\0" + struct.pack(">I", 0)
    encoding += first + hashlib.md5(page).digest() + page
    enc_ckey, enc_ekey = put(encoding)

    data, entries = b"", []
    for ekey, blob in stored:
        header = (b"\0" * 30 if blank_headers
                  else ekey[::-1] + struct.pack("<I", 30 + len(blob)) + b"\0" * 10)
        entries.append((ekey[:9], len(data), 30 + len(blob)))
        data += header + blob
    (data_dir / "data.000").write_bytes(data)
    idx_header = struct.pack("<HBBBBBBQ", index_version, 0, 0, 4, 5, 9, offset_bits, 1 << 30)
    body = b"".join(k + off.to_bytes(5, "big") + struct.pack("<I", size) for k, off, size in sorted(entries))
    idx = struct.pack("<II", len(idx_header), 0) + idx_header
    idx += b"\0" * (-len(idx) % 16) + struct.pack("<II", len(body), 0) + body
    (data_dir / "0000000001.idx").write_bytes(idx)

    build_key = hashlib.md5(b"build config").hexdigest()
    cfg = root / "Data" / "config" / build_key[:2] / build_key[2:4]
    cfg.mkdir(parents=True)
    (cfg / build_key).write_text(
        f"# Build Configuration\n\nroot = {root_ckey.hex()}\nencoding = {enc_ckey.hex()} {enc_ekey.hex()}\n",
        encoding="utf-8",
    )
    rows = build_info_rows if build_info_rows is not None else [(PRODUCT, VERSION, "1")]
    lines = ["Branch!STRING:0|Active!DEC:1|Build Key!HEX:16|Version!STRING:0|Product!STRING:0"]
    lines += [f"us|{active}|{build_key}|{ver}|{prod}" for prod, ver, active in rows]
    (root / ".build.info").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return root


def build_key_of(root: Path) -> str:
    return next((root / "Data" / "config").glob("*/*/*")).name
