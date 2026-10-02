"""The client's local archive (`World of Warcraft/Data`) → file bytes by path or FileDataID (ADR-021).

Read-only. Layout verified on Classic Era 1.15.9.69722 (`wow_classic_era`):

- `.build.info` (next to `Data/`): `|`-separated rows with `Name!TYPE:n` headers; the product's row gives
  `Build Key` and `Version`.
- `Data/config/<k[0:2]>/<k[2:4]>/<k>`: the build config, `key = value` lines; `encoding` and `root` name the
  encoding file (content key, encoded key) and the root file (content key).
- `Data/data/<bucket:02x><version:08x>.idx`: one index per bucket, the highest version wins. Header `u32 size,
  u32 hash, size bytes` (version 7, 9-byte keys, 5-byte offsets, 4-byte sizes), padded to 16; then `u32
  entries size, u32 hash` and 18-byte entries: key (first 9 bytes of the encoded key), big-endian u40 (archive
  number << 30 | offset), little-endian u32 size.
- `Data/data/data.<nnn>`: at the offset, a 30-byte header (the encoded key reversed, u32 size incl. header,
  flags, checksums) then the BLTE blob. Some clients leave that header **zeroed** (the Forever beta
  does), and
  the blob still follows at +30: a blank header is unwritten, not wrong, and `read_file` verifies the decoded
  bytes against their content key instead (ADR-026).
- encoding (`EN`, version 1): content key → encoded key, in 4 KiB pages indexed by each page's first key.
- root (`TSFM`, version 2, 24-byte header): blocks of `u32 count, u32 locale flags, u32 + u32 + u8 content
  flags`, then count FileDataID deltas, count content keys, count name hashes (absent when content flag
  0x10000000 is set). A name hash is Jenkins `hashlittle2` of the upper-cased path with backslashes.

Anything else raises CascError naming what did not match.
"""

from __future__ import annotations

import bisect
import hashlib
import struct
from dataclasses import dataclass
from pathlib import Path

from wfj.io import blte

INDEX_VERSION = 7
INDEX_ENTRY = 18
LOCAL_HEADER = 30
LOCALE_ENUS = 0x2
# Root content flags (wowdev.wiki TACT, "Root", content_flags): the regional variants set aside when a file
# has several enUS content keys.
LOW_VIOLENCE = 0x80
DO_NOT_LOAD = 0x100
NO_NAME_HASH = 0x10000000
ROOT_MAGIC = b"TSFM"


class CascError(ValueError):
    """The archive is not laid out the way this reader understands."""


@dataclass(frozen=True)
class BuildInfo:
    product: str
    version: str  # "1.15.9.69722"
    build_key: str


def read_build_info(wow: Path, product: str) -> BuildInfo:
    path = Path(wow) / ".build.info"
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as e:
        raise CascError(f"{path}: {e.strerror or e}") from e
    if not lines:
        raise CascError(f"{path}: empty")
    names = [h.split("!", 1)[0] for h in lines[0].split("|")]
    found = []
    for line in lines[1:]:
        if not line.strip():
            continue
        row = dict(zip(names, line.split("|"), strict=False))
        if row.get("Product") == product:
            found.append(row)
    if not found:
        have = sorted({dict(zip(names, ln.split("|"), strict=False)).get("Product", "") for ln in lines[1:]})
        raise CascError(f"{path.name}: no product {product!r} (have {have})")
    if len(found) > 1:  # several branches of one product: the active one, when exactly one is
        active = [r for r in found if r.get("Active") == "1"]
        if len(active) != 1:
            raise CascError(
                f"{path.name}: product {product!r} listed {len(found)} times ({len(active)} active)"
            )
        found = active
    row = found[0]
    return BuildInfo(product, row.get("Version", ""), row.get("Build Key", ""))


def _config(data: Path, key: str) -> dict[str, list[str]]:
    path = data / "config" / key[0:2] / key[2:4] / key
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as e:
        raise CascError(f"config {key}: {e.strerror or e}") from e
    out: dict[str, list[str]] = {}
    for line in text.splitlines():
        if line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.split()
    return out


def _rot(x: int, k: int) -> int:
    return ((x << k) | (x >> (32 - k))) & 0xFFFFFFFF


def hashlittle2(data: bytes, pc: int = 0, pb: int = 0) -> tuple[int, int]:
    """Bob Jenkins' lookup3 `hashlittle2` → (pc, pb)."""
    m = 0xFFFFFFFF
    length = len(data)
    a = b = c = (0xDEADBEEF + length + pc) & m
    c = (c + pb) & m
    at = 0
    while length > 12:
        a = (a + struct.unpack_from("<I", data, at)[0]) & m
        b = (b + struct.unpack_from("<I", data, at + 4)[0]) & m
        c = (c + struct.unpack_from("<I", data, at + 8)[0]) & m
        a = (a - c) & m
        a ^= _rot(c, 4)
        c = (c + b) & m
        b = (b - a) & m
        b ^= _rot(a, 6)
        a = (a + c) & m
        c = (c - b) & m
        c ^= _rot(b, 8)
        b = (b + a) & m
        a = (a - c) & m
        a ^= _rot(c, 16)
        c = (c + b) & m
        b = (b - a) & m
        b ^= _rot(a, 19)
        a = (a + c) & m
        c = (c - b) & m
        c ^= _rot(b, 4)
        b = (b + a) & m
        length -= 12
        at += 12
    if length == 0:
        return c, b
    tail = data[at:] + b"\0" * (12 - length)
    a = (a + struct.unpack_from("<I", tail, 0)[0]) & m
    b = (b + struct.unpack_from("<I", tail, 4)[0]) & m
    c = (c + struct.unpack_from("<I", tail, 8)[0]) & m
    c ^= b
    c = (c - _rot(b, 14)) & m
    a ^= c
    a = (a - _rot(c, 11)) & m
    b ^= a
    b = (b - _rot(a, 25)) & m
    c ^= b
    c = (c - _rot(b, 16)) & m
    a ^= c
    a = (a - _rot(c, 4)) & m
    b ^= a
    b = (b - _rot(a, 14)) & m
    c ^= b
    c = (c - _rot(b, 24)) & m
    return c, b


def name_hash(path: str) -> int:
    """The root's 64-bit name hash of a client path (`DBFilesClient\\ItemSparse.db2`)."""
    pc, pb = hashlittle2(path.replace("/", "\\").upper().encode("ascii"))
    return (pc << 32) | pb


class LocalArchive:
    """One product's view of the shared local archive. Opens game files for reading only."""

    def __init__(self, wow: Path, product: str):
        try:
            self._open(wow, product)
        except CascError:
            raise
        except (struct.error, IndexError, ValueError, OSError) as e:  # truncated files, a rotated index
            raise CascError(
                f"local archive at {wow}: truncated or unreadable ({type(e).__name__}: {e})"
            ) from e

    def _open(self, wow: Path, product: str) -> None:
        self.wow = Path(wow)
        self.data = self.wow / "Data"
        self.info = read_build_info(self.wow, product)
        build = _config(self.data, self.info.build_key)
        try:
            self._encoding_ekey = bytes.fromhex(build["encoding"][1])
            self._root_ckey = bytes.fromhex(build["root"][0])
        except (KeyError, IndexError, ValueError) as e:
            raise CascError(f"build config {self.info.build_key}: no encoding / root key ({e})") from e
        self._unverified: set[bytes] = set()  # ekeys read from an entry whose header was blank
        self._index = self._read_indices()
        self._encoding = self.read_ekey(self._encoding_ekey)
        self._pages = self._encoding_pages()
        self._root = self._read_root(self.read_ckey(self._root_ckey))

    # --- index + data -------------------------------------------------------------------------------
    def _read_indices(self) -> dict[bytes, tuple[int, int, int]]:
        best: dict[int, tuple[int, Path]] = {}
        for p in (self.data / "data").glob("*.idx"):
            try:
                bucket, version = int(p.name[:2], 16), int(p.name[2:10], 16)
            except ValueError:
                continue
            if bucket not in best or version > best[bucket][0]:
                best[bucket] = (version, p)
        if not best:
            raise CascError(f"{self.data / 'data'}: no .idx files")
        out: dict[bytes, tuple[int, int, int]] = {}
        for _, p in sorted(best.values()):
            buf = p.read_bytes()
            size = struct.unpack_from("<I", buf, 0)[0]
            version, _, _, size_b, off_b, key_b, offset_bits = struct.unpack_from("<HBBBBBB", buf, 8)
            if (version, size_b, off_b, key_b, offset_bits) != (INDEX_VERSION, 4, 5, 9, 30):
                raise CascError(
                    f"{p.name}: index version {version} ({size_b}/{off_b}/{key_b}, {offset_bits} offset bits)"
                    " is not 7 (4/5/9, 30)"
                )
            at = (8 + size + 15) & ~15
            entries = struct.unpack_from("<I", buf, at)[0]
            at += 8
            if entries % INDEX_ENTRY or at + entries > len(buf):
                raise CascError(f"{p.name}: entries block of {entries} bytes does not fit")
            for e in range(at, at + entries, INDEX_ENTRY):
                key = buf[e : e + 9]
                off = int.from_bytes(buf[e + 9 : e + 14], "big")
                out.setdefault(key, (off >> 30, off & 0x3FFFFFFF, struct.unpack_from("<I", buf, e + 14)[0]))
        return out

    def read_blob(self, ekey: bytes) -> bytes:
        """The BLTE blob stored under an encoded key."""
        hit = self._index.get(ekey[:9])
        if hit is None:
            raise CascError(f"encoded key {ekey.hex()} is not in the local index (not downloaded?)")
        archive, offset, size = hit
        path = self.data / "data" / f"data.{archive:03d}"
        try:
            with path.open("rb") as f:
                f.seek(offset)
                buf = f.read(size)
        except OSError as e:
            raise CascError(f"{path.name}: {e.strerror or e}") from e
        if len(buf) != size or size < LOCAL_HEADER:
            raise CascError(f"{path.name}@{offset}: entry of {size} bytes is cut short")
        # The 30-byte entry header repeats the encoded key. The client does not always write it: on the
        # Forever beta (1.60.1.69893) the whole header is zeroed and the BLTE payload follows at +30 as
        # normal; the data is present and correct. Treating a blank header as a mismatch would read most
        # interface files and every DB2 as "not downloaded". A blank header is *unwritten*, not *wrong*:
        # trust the index, and verify the decoded bytes against their content key instead (read_file),
        # the stronger check this one only stood in for.
        head = buf[:16][::-1]
        if any(head) and head[:9] != ekey[:9]:
            raise CascError(f"{path.name}@{offset}: header names key {head.hex()}, want {ekey.hex()}")
        if not any(head):
            self._unverified.add(ekey[:9])
        return buf[LOCAL_HEADER:]

    def read_ekey(self, ekey: bytes) -> bytes:
        try:
            return blte.decode(self.read_blob(ekey))
        except blte.BlteError as e:
            raise CascError(f"encoded key {ekey.hex()}: {e}") from e

    # --- encoding -----------------------------------------------------------------------------------
    def _encoding_pages(self) -> list[bytes]:
        enc = self._encoding
        if enc[:2] != b"EN" or enc[2] != 1:
            raise CascError(f"encoding: magic {enc[:3]!r} is not EN version 1")
        self._ck, self._ek = enc[3], enc[4]
        page_kb = struct.unpack_from(">H", enc, 5)[0]
        count = struct.unpack_from(">I", enc, 9)[0]
        spec_size = struct.unpack_from(">I", enc, 18)[0]
        at = 22 + spec_size
        self._page_at = at + count * (self._ck + 16)
        self._page_size = page_kb * 1024
        firsts = [enc[at + n * (self._ck + 16) : at + n * (self._ck + 16) + self._ck] for n in range(count)]
        if firsts != sorted(firsts):
            raise CascError("encoding: page index is not sorted")
        if self._page_at + count * self._page_size > len(enc):
            raise CascError("encoding: pages run past the file")
        return firsts

    def ekey_of(self, ckey: bytes) -> bytes:
        n = bisect.bisect_right(self._pages, ckey) - 1
        if n >= 0:
            page_at = self._page_at + n * self._page_size
            page = self._encoding[page_at : page_at + self._page_size]
            at, step = 0, 6 + self._ck
            while at + step <= len(page) and page[at]:
                keys = page[at]
                if page[at + 6 : at + step] == ckey:
                    return page[at + step : at + step + self._ek]
                at += step + self._ek * keys
        raise CascError(f"content key {ckey.hex()} is not in the encoding file")

    def read_ckey(self, ckey: bytes) -> bytes:
        return self.read_ekey(self.ekey_of(ckey))

    # --- root ---------------------------------------------------------------------------------------
    def _read_root(self, root: bytes) -> dict[int, list[tuple[int, int, bytes]]]:
        """FileDataID → [(locale flags, content flags, content key)]; sets `_by_name` (name hash →
        [(FileDataID, locale, content, content key)])."""
        if root[:4] != ROOT_MAGIC:
            raise CascError(f"root: magic {root[:4]!r} is not {ROOT_MAGIC!r}")
        header_size, version = struct.unpack_from("<II", root, 4)
        if version != 2 or header_size != 24:
            raise CascError(f"root: version {version} / header {header_size} is not 2 / 24")
        by_fdid: dict[int, list[tuple[int, int, bytes]]] = {}
        by_name: dict[int, list[tuple[int, int, int, bytes]]] = {}
        at = header_size
        while at < len(root):
            if at + 17 > len(root):
                raise CascError(f"root: block header at {at} is cut short")
            count, locale, f1, f2 = struct.unpack_from("<IIII", root, at)
            content = f1 | f2 | (root[at + 16] << 17)
            at += 17
            named = not content & NO_NAME_HASH
            end = at + count * (4 + 16 + (8 if named else 0))
            if end > len(root):
                raise CascError(f"root: block of {count} records at {at} runs past the file")
            fdid = -1
            deltas = struct.unpack_from(f"<{count}I", root, at)
            ck_at = at + 4 * count
            nh_at = ck_at + 16 * count
            for n in range(count):
                fdid += deltas[n] + 1
                rec = (locale, content, root[ck_at + 16 * n : ck_at + 16 * (n + 1)])
                by_fdid.setdefault(fdid, []).append(rec)
                if named:
                    by_name.setdefault(struct.unpack_from("<Q", root, nh_at + 8 * n)[0], []).append(
                        (fdid, *rec)
                    )
            at = end
        self._by_name = by_name
        return by_fdid

    def file_data_id(self, path: str, fallback: int | None = None) -> int:
        """FileDataID of an enUS client path; CascError when the root has no single answer. `fallback`: the id
        to use when the root carries no name hash for the path (a root may drop them), if the root holds it.
        """
        hits = {rec[0] for rec in self._by_name.get(name_hash(path), []) if rec[1] & LOCALE_ENUS}
        if (
            not hits
            and fallback is not None
            and any(r[0] & LOCALE_ENUS for r in self._root.get(fallback, []))
        ):
            return fallback
        if len(hits) != 1:
            raise CascError(f"root: {path} names {len(hits)} enUS files ({sorted(hits)})")
        return hits.pop()

    def ships(self, fdid: int) -> bool:
        """Whether the root holds an enUS file for this FileDataID."""
        return any(r[0] & LOCALE_ENUS for r in self._root.get(fdid, []))

    def ckey_of(self, fdid: int) -> bytes:
        """The enUS content key of a file. When enUS root blocks give the file several content keys (not seen
        on 1.15.9.69722), the variants flagged LowViolence or DoNotLoad are set aside; exactly one
        left is the file, otherwise CascError lists every key with its locale and content flags (a
        duplicate is never picked silently)."""
        recs = [r for r in self._root.get(fdid, []) if r[0] & LOCALE_ENUS]
        keys = {r[2] for r in recs}
        if len(keys) == 1:
            return keys.pop()
        kept = {r[2] for r in recs if not r[1] & (LOW_VIOLENCE | DO_NOT_LOAD)}
        if len(keys) > 1 and len(kept) == 1:
            return kept.pop()
        listed = "; ".join(f"{r[2].hex()} (locale {r[0]:#x}, content {r[1]:#x})" for r in sorted(recs))
        detail = f": {listed}" if recs else ""
        raise CascError(f"root: FileDataID {fdid} has {len(keys)} enUS content keys{detail}")

    def read_file(self, fdid: int) -> tuple[bytes, list[tuple[int, int, str]]]:
        """A file's bytes and the (start, end, key name) ranges of its encrypted frames, which are zero-filled
        so the offsets of everything after them hold. A single-frame file that is encrypted has no known size
        and raises.

        When the archive entry carried no encoded key in its header (see read_blob), the decoded bytes are
        checked against their content key: a content key is the MD5 of the file's content, so this proves
        the index pointed at the right bytes far better than the header field ever did. It is skipped for a
        file with encrypted frames, whose zero-filled gaps cannot hash to the original."""
        ekey = self.ekey_of(self.ckey_of(fdid))
        blob = self.read_blob(ekey)
        out, gaps, at = [], [], 0
        try:
            for size, data in blte.frames(blob):
                try:
                    chunk = blte.decode_frame(size, data)
                except blte.EncryptedBlock as e:
                    if size < 0:
                        raise CascError(
                            f"FileDataID {fdid}: whole file is encrypted (key {e.key_name})"
                        ) from e
                    chunk = bytes(size)
                    gaps.append((at, at + size, e.key_name))
                out.append(chunk)
                at += len(chunk)
        except blte.BlteError as e:
            raise CascError(f"FileDataID {fdid}: {e}") from e
        data = b"".join(out)
        if not gaps and ekey[:9] in self._unverified:
            ckey = self.ckey_of(fdid)
            got = hashlib.md5(data, usedforsecurity=False).digest()
            if got != ckey:
                raise CascError(
                    f"FileDataID {fdid}: content hashes to {got.hex()}, but its content key is "
                    f"{ckey.hex()}: the index pointed at the wrong bytes"
                )
        return data, gaps
