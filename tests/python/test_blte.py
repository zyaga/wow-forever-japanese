"""BLTE frames."""

import hashlib
import struct
import zlib

import pytest
from casc_fixture import ENC_KEY_NAME, blte_chunks, blte_single

from wfj.io import blte


def test_single_plain_frame():
    assert blte.decode(blte_single(b"hello")) == b"hello"


def test_chunked_plain_and_zlib():
    z = b"Z" + zlib.compress(b"world")
    table = struct.pack(">II", 6, 5) + hashlib.md5(b"Nhello").digest()
    table += struct.pack(">II", len(z), 5) + hashlib.md5(z).digest()
    blob = b"BLTE" + struct.pack(">I", 12 + len(table)) + b"\x0f" + (2).to_bytes(3, "big") + table
    blob += b"Nhello" + z
    assert blte.decode(blob) == b"helloworld"


def test_encrypted_frame_signals_with_key_name():
    blob = blte_chunks(b"abcdefgh", [4], encrypted={1})
    with pytest.raises(blte.EncryptedBlock) as e:
        blte.decode(blob)
    assert e.value.key_name == ENC_KEY_NAME.hex()
    frames = blte.frames(blob)
    assert blte.decode_frame(*frames[0]) == b"abcd"
    assert frames[1][0] == 4  # the size the caller zero-fills


def test_unknown_mode_is_an_error():
    with pytest.raises(blte.BlteError, match="mode b'4'"):
        blte.decode(b"BLTE" + struct.pack(">I", 0) + b"4xxxx")


def test_bad_magic():
    with pytest.raises(blte.BlteError, match="not BLTE"):
        blte.decode(b"NOPE\0\0\0\0N")


def test_size_mismatch_is_an_error():
    table = struct.pack(">II", 6, 9) + hashlib.md5(b"Nhello").digest()
    blob = b"BLTE" + struct.pack(">I", 12 + len(table)) + b"\x0f" + (1).to_bytes(3, "big") + table + b"Nhello"
    with pytest.raises(blte.BlteError, match="table says 9"):
        blte.decode(blob)


def test_trailing_bytes_after_chunks_are_an_error():
    blob = blte_chunks(b"abcd", []) + b"junk"
    with pytest.raises(blte.BlteError, match="after the last chunk"):
        blte.frames(blob)


def test_chunk_checksum_mismatch_is_an_error():
    """A chunk read while the client rewrites it: right length, wrong bytes."""
    blob = bytearray(blte_chunks(b"abcdefgh", [4]))
    blob[-1] ^= 0x01
    with pytest.raises(blte.BlteError, match="chunk 1 does not match its checksum"):
        blte.decode(bytes(blob))
