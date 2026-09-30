"""BLTE, the block container every file in the client's local archive is stored in (ADR-021).

`BLTE` magic, a big-endian u32 header size, then either one frame (header size 0) or a chunk table: a flag
byte, a big-endian u24 chunk count, and per chunk the compressed size u32, decompressed size u32 and the MD5
of the frame (checked). Each frame starts with a mode byte: `N` plain, `Z` zlib, `E` encrypted. Verified
on Classic Era 1.15.9.69722 (encoding, root and the eight DB2 tables use `N` and `Z` only).

An encrypted frame raises `EncryptedBlock` so a caller that can do without it (DB2 sections) skips it; any
other mode or a size that does not match raises `BlteError`. Nothing here guesses."""

from __future__ import annotations

import hashlib
import struct
import zlib

MAGIC = b"BLTE"
CHUNK_ENTRY = struct.Struct(">II16s")


class BlteError(ValueError):
    """The bytes are not a BLTE blob this reader understands."""


class EncryptedBlock(BlteError):
    """A frame is encrypted (mode `E`); `key_name` is the 8-byte key name as hex."""

    def __init__(self, key_name: str):
        super().__init__(f"encrypted frame (key {key_name})")
        self.key_name = key_name


def _frame(data: bytes, expected: int | None) -> bytes:
    if not data:
        raise BlteError("empty frame")
    mode, body = data[:1], data[1:]
    if mode == b"N":
        out = body
    elif mode == b"Z":
        try:
            out = zlib.decompress(body)
        except zlib.error as e:
            raise BlteError(f"zlib frame: {e}") from e
    elif mode == b"E":
        key_len = body[0] if body else 0
        raise EncryptedBlock(body[1 : 1 + key_len][::-1].hex())
    else:
        raise BlteError(f"frame mode {mode!r} is not implemented (N, Z, E)")
    if expected is not None and len(out) != expected:
        raise BlteError(f"frame decodes to {len(out)} bytes, table says {expected}")
    return out


def frames(blob: bytes) -> list[tuple[int, bytes]]:
    """The raw frames of a blob as (decompressed size or -1, frame bytes), for callers that skip encrypted
    frames one by one."""
    if len(blob) < 8 or blob[:4] != MAGIC:
        raise BlteError(f"not BLTE (magic {blob[:4]!r})")
    header_size = struct.unpack_from(">I", blob, 4)[0]
    if header_size == 0:
        return [(-1, blob[8:])]
    if header_size > len(blob) or len(blob) < 12:
        raise BlteError(f"header size {header_size} runs past the blob ({len(blob)} bytes)")
    count = int.from_bytes(blob[9:12], "big")
    if 12 + count * CHUNK_ENTRY.size != header_size:
        raise BlteError(f"{count} chunks do not fill a header of {header_size} bytes")
    out, at = [], header_size
    for n in range(count):
        csize, dsize, md5 = CHUNK_ENTRY.unpack_from(blob, 12 + n * CHUNK_ENTRY.size)
        if at + csize > len(blob):
            raise BlteError(f"chunk {n} runs past the blob")
        data = blob[at : at + csize]
        if hashlib.md5(data).digest() != md5:  # a chunk read while the client rewrites it, or corrupt
            raise BlteError(f"chunk {n} does not match its checksum")
        out.append((dsize, data))
        at += csize
    if at != len(blob):
        raise BlteError(f"{len(blob) - at} bytes after the last chunk")
    return out


def decode(blob: bytes) -> bytes:
    """The whole file. Raises EncryptedBlock on the first encrypted frame."""
    return b"".join(_frame(data, None if size < 0 else size) for size, data in frames(blob))


def decode_frame(size: int, data: bytes) -> bytes:
    """One frame from `frames`."""
    return _frame(data, None if size < 0 else size)
