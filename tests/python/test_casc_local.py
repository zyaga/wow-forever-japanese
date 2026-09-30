"""The local archive reader."""

import os
import socket
from pathlib import Path

import pytest
from casc_fixture import PRODUCT, VERSION, blte_chunks, build, build_key_of

from wfj.io import casc

PATH = "DBFilesClient\\Thing.db2"


def test_hashlittle2_published_vectors():
    # lookup3.c driver5: hashlittle2("", 0, 0) and "Four score and seven years ago"
    assert casc.hashlittle2(b"") == (0xDEADBEEF, 0xDEADBEEF)
    assert casc.hashlittle2(b"Four score and seven years ago") == (0x17770551, 0xCE7226E6)


def test_name_hash_of_a_real_client_path():
    # 1.15.9.69722's root resolves this hash to ItemSubClass.db2 (FileDataID 1261604), verified on that build
    assert casc.name_hash("DBFilesClient\\ItemSubClass.db2") == 0xAEEF62D8195A6E68
    assert casc.name_hash("dbfilesclient/itemsubclass.db2") == 0xAEEF62D8195A6E68


def test_file_by_path_and_build_version(tmp_path: Path):
    wow = build(tmp_path, {PATH: b"table bytes", "Other\\File.txt": b"other"})
    a = casc.LocalArchive(wow, PRODUCT)
    assert a.info.version == VERSION
    fdid = a.file_data_id(PATH)
    assert a.read_file(fdid) == (b"table bytes", [])
    assert a.read_file(a.file_data_id("Other\\File.txt"))[0] == b"other"


def test_missing_product_names_what_is_there(tmp_path: Path):
    wow = build(tmp_path, {PATH: b"x"})
    with pytest.raises(casc.CascError, match=r"no product 'wow_forever' \(have \['wow_test'\]\)"):
        casc.LocalArchive(wow, "wow_forever")


def test_product_listed_twice(tmp_path: Path):
    wow = build(tmp_path / "a", {PATH: b"x"})
    key = build_key_of(wow)
    (wow / ".build.info").write_text(
        "Build Key!HEX:16|Version!STRING:0|Product!STRING:0\n"
        f"{key}|{VERSION}|{PRODUCT}\n{key}|{VERSION}|{PRODUCT}\n"
    )
    with pytest.raises(casc.CascError, match="listed 2 times"):
        casc.LocalArchive(wow, PRODUCT)


def test_unknown_path(tmp_path: Path):
    a = casc.LocalArchive(build(tmp_path, {PATH: b"x"}), PRODUCT)
    with pytest.raises(casc.CascError, match="names 0 enUS files"):
        a.file_data_id("DBFilesClient\\Missing.db2")


def test_index_version_other_than_7(tmp_path: Path):
    wow = build(tmp_path, {PATH: b"x"}, index_version=8)
    with pytest.raises(casc.CascError, match="index version 8"):
        casc.LocalArchive(wow, PRODUCT)


def test_data_header_naming_another_key(tmp_path: Path):
    wow = build(tmp_path, {PATH: b"table bytes"})
    data = wow / "Data" / "data" / "data.000"
    buf = bytearray(data.read_bytes())
    # corrupt the reversed key of every entry header whose blob is the table (search the plain frame)
    at = buf.index(b"Ntable bytes") - 8 - 30
    buf[at] ^= 0xFF
    buf[at + 15] ^= 0xFF
    data.write_bytes(bytes(buf))
    a = casc.LocalArchive(wow, PRODUCT)
    with pytest.raises(casc.CascError, match="header names key"):
        a.read_file(a.file_data_id(PATH))


def test_encrypted_frames_are_zero_filled_and_reported(tmp_path: Path):
    raw = b"AAAABBBBCCCC"
    wow = build(tmp_path, {PATH: raw}, blobs={PATH: blte_chunks(raw, [4, 8], encrypted={1})})
    a = casc.LocalArchive(wow, PRODUCT)
    buf, gaps = a.read_file(a.file_data_id(PATH))
    assert buf == b"AAAA\0\0\0\0CCCC"
    assert gaps == [(4, 8, "0123456789abcdef")]


def test_whole_file_encrypted_in_one_frame_is_an_error(tmp_path: Path):
    blob = b"BLTE\0\0\0\0E\x08" + bytes(8) + b"\x04\0\0\0\0S" + b"x" * 4
    wow = build(tmp_path, {PATH: b"xxxx"}, blobs={PATH: blob})
    a = casc.LocalArchive(wow, PRODUCT)
    with pytest.raises(casc.CascError, match="whole file is encrypted"):
        a.read_file(a.file_data_id(PATH))


def test_read_only_and_no_network(tmp_path: Path, monkeypatch):
    """Reading the archive changes no byte or mtime under the install and opens no socket."""
    wow = build(tmp_path, {PATH: b"table bytes"})
    before = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in wow.rglob("*") if p.is_file()}
    past = 1_000_000_000_000_000_000
    for p in before:
        os.utime(p, ns=(past, past))
    before = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in before}

    def no_socket(*a, **k):
        raise AssertionError("network access")

    monkeypatch.setattr(socket, "socket", no_socket)
    a = casc.LocalArchive(wow, PRODUCT)
    a.read_file(a.file_data_id(PATH))
    after = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in wow.rglob("*") if p.is_file()}
    assert after == before


def test_active_row_chosen_when_a_product_has_several(tmp_path: Path):
    wow = build(tmp_path, {PATH: b"x"}, build_info_rows=[(PRODUCT, "1.0.0.1", "0"), (PRODUCT, VERSION, "1")])
    assert casc.LocalArchive(wow, PRODUCT).info.version == VERSION


def test_index_offset_bits_other_than_30(tmp_path: Path):
    with pytest.raises(casc.CascError, match="31 offset bits"):
        casc.LocalArchive(build(tmp_path, {PATH: b"x"}, offset_bits=31), PRODUCT)


def test_truncated_index_names_the_archive(tmp_path: Path):
    wow = build(tmp_path, {PATH: b"x"})
    idx = wow / "Data" / "data" / "0000000001.idx"
    idx.write_bytes(idx.read_bytes()[:20])
    with pytest.raises(casc.CascError, match="truncated or unreadable"):
        casc.LocalArchive(wow, PRODUCT)


def test_root_without_name_hashes_uses_the_fallback_id(tmp_path: Path):
    a = casc.LocalArchive(build(tmp_path, {PATH: b"table"}, named=False), PRODUCT)
    with pytest.raises(casc.CascError, match="names 0 enUS files"):
        a.file_data_id(PATH)
    assert a.file_data_id(PATH, fallback=1000) == 1000
    with pytest.raises(casc.CascError, match="names 0 enUS files"):
        a.file_data_id(PATH, fallback=4242)  # an id the root does not hold is no answer


def _archive_with_root(records) -> casc.LocalArchive:
    """ckey_of over a hand-made root: {FileDataID: [(locale flags, content flags, content key)]}."""
    a = object.__new__(casc.LocalArchive)
    a._root = records
    return a


A, B = b"\xaa" * 16, b"\xbb" * 16
LOW_VIOLENCE, DO_NOT_LOAD, WINDOWS = 0x80, 0x100, 0x8


@pytest.mark.parametrize("flag", [LOW_VIOLENCE, DO_NOT_LOAD])
def test_two_enus_content_keys_resolve_when_one_is_a_set_aside_variant(flag):
    """A LowViolence / DoNotLoad variant (wowdev.wiki TACT root content flags) is set aside."""
    a = _archive_with_root({7: [(0x2, WINDOWS, A), (0x2, WINDOWS | flag, B)]})
    assert a.ckey_of(7) == A


def test_two_enus_content_keys_with_no_rule_to_pick_stop_and_list_both():
    a = _archive_with_root({7: [(0x2, WINDOWS, A), (0x6, 0x10, B), (0x4, 0, b"\xcc" * 16)]})
    with pytest.raises(casc.CascError) as e:
        a.ckey_of(7)
    msg = str(e.value)
    assert "FileDataID 7 has 2 enUS content keys" in msg
    assert f"{A.hex()} (locale 0x2, content 0x8)" in msg and f"{B.hex()} (locale 0x6, content 0x10)" in msg
    assert "cc" * 16 not in msg  # not enUS


def test_a_file_with_no_enus_key_stops():
    with pytest.raises(casc.CascError, match="FileDataID 9 has 0 enUS content keys$"):
        _archive_with_root({9: [(0x4, 0, A)]}).ckey_of(9)


def test_the_same_key_in_two_enus_blocks_is_one_file():
    assert _archive_with_root({7: [(0x2, WINDOWS, A), (0x2, LOW_VIOLENCE, A)]}).ckey_of(7) == A


def test_every_enus_key_set_aside_stops_and_lists_them():
    """Nothing left after LowViolence / DoNotLoad are set aside: no guess."""
    a = _archive_with_root({7: [(0x2, LOW_VIOLENCE, A), (0x2, DO_NOT_LOAD, B)]})
    with pytest.raises(casc.CascError, match="FileDataID 7 has 2 enUS content keys: "):
        a.ckey_of(7)


# --- an archive entry whose header carries no encoded key ------------------------------------------
# The Forever beta client (1.60.1.69893) leaves the 30-byte entry header zeroed and writes the BLTE
# payload at +30 as normal. Reading that as a key mismatch made every DB2 and 3,049 of 4,044 interface
# files look "not downloaded" when the data was on disk all along. A blank header is unwritten,
# not wrong: trust the index, and check the decoded bytes against their content key instead.

def test_a_blank_entry_header_is_read_and_verified_against_its_content_key(tmp_path: Path):
    wow = build(tmp_path / "wow", {PATH: b"table bytes", "Other\\File.txt": b"other"},
                blank_headers=True)
    a = casc.LocalArchive(wow, PRODUCT)
    fdid = a.file_data_id(PATH)
    assert a.read_file(fdid) == (b"table bytes", [])
    assert a.read_file(a.file_data_id("Other\\File.txt"))[0] == b"other"


def test_a_header_naming_a_different_key_still_raises(tmp_path: Path):
    # only a *blank* header is forgiven; a header naming the wrong key is still a real mismatch
    wow = build(tmp_path / "wow", {PATH: b"table bytes"})
    data = wow / "Data" / "data" / "data.000"
    raw = bytearray(data.read_bytes())
    raw[0:16] = bytes(range(1, 17))          # a plausible-looking but wrong key
    data.write_bytes(bytes(raw))
    a = casc.LocalArchive(wow, PRODUCT)
    with pytest.raises(casc.CascError, match="header names key"):
        a.read_file(a.file_data_id(PATH))


def test_a_blank_header_over_the_wrong_bytes_is_caught_by_the_content_key(tmp_path: Path):
    # the header check was only ever a proxy for "the index pointed at the right bytes". With it blank the
    # content key does that job instead, and does it better, since a content key is the MD5 of the content.
    wow = build(tmp_path / "wow", {PATH: b"table bytes"}, blank_headers=True)
    data = wow / "Data" / "data" / "data.000"
    # one byte of the stored content, same length, so every offset and size in the index still holds
    data.write_bytes(data.read_bytes().replace(b"table bytes", b"table bytez", 1))
    a = casc.LocalArchive(wow, PRODUCT)
    with pytest.raises(casc.CascError, match="content key"):
        a.read_file(a.file_data_id(PATH))


def test_a_written_header_is_not_content_checked(tmp_path: Path):
    # the check is for entries the client left blank; a normal archive keeps its existing, cheaper path
    wow = build(tmp_path / "wow", {PATH: b"table bytes"})
    a = casc.LocalArchive(wow, PRODUCT)
    assert a.read_file(a.file_data_id(PATH)) == (b"table bytes", [])
    assert a._unverified == set()


def test_a_blank_header_with_an_encrypted_frame_is_read_without_a_content_check(tmp_path: Path):
    """The accepted hole, pinned so it stays deliberate.

    A content key is the MD5 of the file's content, so a file whose encrypted frames were zero-filled can
    never hash to it; the check has to be skipped there. On the Forever client every header is blank AND
    the big tables carry encrypted frames, so those reads rest on the index alone. That is a real gap
    (ADR-026 Consequences); this test exists so a future change cannot close or widen it by accident.
    """
    wow = build(tmp_path / "wow", {PATH: b"table bytesSECRET!!"},
                blobs={PATH: blte_chunks(b"table bytesSECRET!!", [11], encrypted={1})},
                blank_headers=True)
    a = casc.LocalArchive(wow, PRODUCT)
    data, gaps = a.read_file(a.file_data_id(PATH))
    assert gaps, "the fixture must produce an encrypted frame for this test to mean anything"
    assert a._unverified, "the blank header must have been recorded as unverified"
    assert data.startswith(b"table bytes")   # read succeeded with no content-key check
