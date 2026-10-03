"""Reader for a collector send: the string the addon's send window packs (ADR-056), or the SavedVariables
file a player attached to the same issue when the string was too long to paste.

String: `WFJC1:` + URL-safe Base64 of zlib-compressed JSON `{v, a, b, e}`: the format version, the addon
version, the builds, and the entries in the dump's own fields (`t, i, f, h, e, b, n, p`; `b` indexes
this `b`).
Every entry goes through the same `check_entry` as a dump file, so a string cannot carry anything a file could
not. Nothing in it is trusted: sizes are capped before decompressing and parsing.
"""

from __future__ import annotations

import base64
import binascii
import http.client
import io
import json
import re
import urllib.request
import zipfile
import zlib
from collections import Counter
from dataclasses import dataclass
from typing import Any

from wfj.io.collector_dump import Dump, check_entry, read_dump
from wfj.io.lua_reader import Table

PREFIX = "WFJC1:"
FORMAT = 1
MAX_TEXT = 70_000  # the paste box holds 60,000; a little room for a pasted line break or two
MAX_JSON = 4 * 1024 * 1024  # the addon's whole dump is capped at about 4 MB of text
MAX_FILE = 25 * 1024 * 1024  # GitHub's attachment limit
MAX_MEMBER = 8 * 1024 * 1024  # the saved file: the addon caps its text at about 4 MB, with room to spare
FILE_NAME = "wowforeverjapanese.lua"
# The issue form's field labels (the `### <label>` headings in the body).
DUMP_LABEL = "Collected English"
# the string is one run of the URL-safe alphabet: it stops at the first other character (a space, a line
# break, a backtick from a code fence), so a note typed after it is never read as part of it
_STRING = re.compile(r"WFJC1:[A-Za-z0-9_=-]*")
# An attachment as GitHub writes it into an issue body; nothing else is ever downloaded.
_ATTACHMENT = re.compile(r"https://github\.com/user-attachments/files/\d+/[A-Za-z0-9._-]+")


class SendError(ValueError):
    """Why a send cannot be read, in words a player can act on."""


@dataclass
class Send:
    dump: Dump
    addon: str  # the addon version that packed it ("" for an attached file)
    source: str  # "string" | "file"


def _table(v: Any) -> Any:
    """JSON → the Lua reader's Table shape `check_entry` reads (lists positional, objects keyed)."""
    if isinstance(v, dict):
        return Table([(k, _table(x)) for k, x in v.items()])
    if isinstance(v, list):
        return Table([(None, _table(x)) for x in v])
    return v


def decode(text: str) -> Send:
    """A send string → its entries, each re-validated. Raises SendError when it cannot be read."""
    s = "".join(text.split())  # a paste may wrap
    if not s.startswith(PREFIX):
        raise SendError(f"the text does not start with {PREFIX}")
    if len(s) > MAX_TEXT:
        raise SendError(f"the text is longer than {MAX_TEXT} characters")
    body = s[len(PREFIX) :]
    try:
        packed = base64.b64decode(body + "=" * (-len(body) % 4), altchars=b"-_", validate=True)
    except (binascii.Error, ValueError):
        raise SendError("the text is not complete (it does not decode)") from None
    try:
        d = zlib.decompressobj()
        raw = d.decompress(packed, MAX_JSON + 1)
        if len(raw) > MAX_JSON or not d.eof:
            raise SendError("the text is not complete (it does not unpack)")
    except zlib.error:
        raise SendError("the text is not complete (it does not unpack)") from None
    try:
        data = json.loads(raw.decode("utf-8"))
    # JSONDecodeError is a ValueError, and so is an int too long to read
    except (UnicodeDecodeError, ValueError, RecursionError):
        raise SendError("the text is not complete (it does not read)") from None
    if not isinstance(data, dict):
        raise SendError("the text does not read")
    if data.get("v") != FORMAT:
        raise SendError(f"the text is in a format this pipeline does not read (v = {data.get('v')!r})")
    builds = data.get("b") if isinstance(data.get("b"), list) else []
    entries = data.get("e") if isinstance(data.get("e"), list) else []
    out = Dump(FORMAT, [], Counter())
    keyed = [(_key(e), e) for e in entries]
    seen = Counter(k for k, _ in keyed)
    for key, raw_entry in keyed:
        if seen[key] > 1:  # the addon packs each key once: every copy is dropped, and reported
            out.rejected["duplicate_key"] += 1
            continue
        try:
            table = _table(raw_entry)
        except RecursionError:
            out.rejected["bad_key"] += 1
            continue
        entry, reason = check_entry(key, table, builds)
        if entry is None:
            out.rejected[reason] += 1
        else:
            out.entries.append(entry)
    out.entries.sort(key=lambda en: (en.type_, str(en.id_), en.field))
    addon = data.get("a") if isinstance(data.get("a"), str) else ""
    return Send(out, addon, "string")


def _key(e: Any) -> str:
    """The dump key `<t>:<i>:<f>` of a packed entry (a JSON number the client wrote as 12.0 is the id 12)."""
    if not isinstance(e, dict):
        return ""
    i = e.get("i")
    if isinstance(i, float) and i.is_integer():
        i = int(i)
    return f"{e.get('t')}:{i}:{e.get('f')}"


def find(body: str, sections: dict[str, str]) -> tuple[str | None, str | None]:
    """An issue body → (the send string, the attachment link): the form's field first, then anywhere."""
    field = sections.get(DUMP_LABEL, "")
    for text in (field, body):
        m = _STRING.search(text)
        if m:
            return m.group(0), None
    for text in (field, body):
        m = _ATTACHMENT.search(text)
        if m:
            return None, m.group(0)
    return None, None


def _lua_text(name: str, blob: bytes) -> str:
    """The SavedVariables text out of an attachment: a zip holding it, or the file renamed to .txt / .lua."""
    if name.lower().endswith(".zip"):
        try:
            with zipfile.ZipFile(io.BytesIO(blob)) as z:
                member = _member(z)
                if member.file_size > MAX_MEMBER:
                    raise SendError("the file in the zip is too large")
                blob = z.read(member)
        except (zipfile.BadZipFile, RuntimeError, NotImplementedError, zlib.error, EOFError):
            # not a zip, an encrypted member, a compression method Python lacks, a broken stream
            raise SendError("the attachment is not a zip file that opens") from None
    return blob.decode("utf-8-sig", errors="replace")


def _member(z: zipfile.ZipFile) -> zipfile.ZipInfo:
    """The SavedVariables file in a zip: WoWForeverJapanese.lua by name (a player may zip the whole folder),
    else the one .lua / .txt file it holds. macOS's resource-fork copies are skipped."""

    def junk(m: zipfile.ZipInfo) -> bool:
        base = m.filename.rsplit("/", 1)[-1]
        return m.is_dir() or m.filename.startswith("__MACOSX/") or base.startswith("._")

    files = [m for m in z.infolist() if not junk(m)]
    named = [m for m in files if m.filename.rsplit("/", 1)[-1].lower() == FILE_NAME]
    if named:
        return named[0]
    texts = [m for m in files if m.filename.lower().endswith((".lua", ".txt"))]
    if len(texts) == 1:
        return texts[0]
    raise SendError("the zip holds no WoWForeverJapanese.lua")


def fetch_attachment(url: str) -> bytes:
    """Downloads one GitHub attachment (only `_ATTACHMENT` links), at most MAX_FILE bytes."""
    if not _ATTACHMENT.fullmatch(url):
        raise SendError("the attachment link is not a GitHub attachment")
    req = urllib.request.Request(url, headers={"User-Agent": "wfj-collector"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:  # noqa: S310 - the scheme and host are fixed above
            blob: bytes = r.read(MAX_FILE + 1)
    except (OSError, http.client.HTTPException) as e:  # URLError, timeouts and a cut-off download included
        raise SendError(f"the attachment could not be downloaded ({type(e).__name__})") from None
    if len(blob) > MAX_FILE:
        raise SendError("the attachment is too large")
    return blob


def read_file(url: str, blob: bytes) -> Send:
    """An attached SavedVariables file (zipped or renamed) → its dump, read as a dump file is."""
    try:
        dump = read_dump(_lua_text(url.rsplit("/", 1)[-1], blob))
    except ValueError as e:
        if isinstance(e, SendError):
            raise
        raise SendError(f"the attached file does not read: {e}") from None
    return Send(dump, "", "file")
