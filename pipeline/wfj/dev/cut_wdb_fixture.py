"""Cut a committed quest-cache fixture from a real `questcache.wdb`, per build: the header,
the chosen records byte for byte, the zero terminator, plus the expected decode as JSON.

  python -m wfj.dev.cut_wdb_fixture <questcache.wdb> ../tests/fixtures/wdb            # Classic Era
  python -m wfj.dev.cut_wdb_fixture <questcache.wdb> ../tests/fixtures/wdb-forever    # Forever

The build in the file's header picks the record set, one per pinned layout in `io/wdb.LAYOUTS`, chosen so
every part of that layout is exercised by some record. A pinned layout with no fixture is a layout CI does
not check, which is the whole point of committing these.
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

from wfj.io.wdb import HEADER_SIZE, RECORD_HEADER, read_ids, read_quests

# Classic Era 1.15.9.69722. 170: two objectives, `$b` / `$g a : b;` · 498: objective descriptions ("Rescue
# Drull") · 247: empty objectives and description · 25: an area description · 172: text pfQuest has for
# another quest · 490: `<UNUSED>` placeholder.
CLASSIC_IDS = (170, 498, 247, 25, 172, 490)

# Forever 1.60.1.69913: one record per part of that layout. 84399: none of the new lists · 6843: no
# objectives at all · 5679 / 1665: the 12-byte list before the objectives, 1 and 3 entries · 91900: the
# 4-byte list after them · 92596: a conditional-text entry in the first array · 94978: one in the second
# (and an area description) · 93165 / 76160: an objective's own inner list, 12 entries and 1 · 95771: an area
# description with no objectives · 92709: an objective with text of its own · 802: an `<UNUSED>` placeholder.
FOREVER_IDS = (802, 1665, 5679, 6843, 76160, 84399, 91900, 92596, 92709, 93165, 94978, 95771)

IDS_BY_BUILD = {69722: CLASSIC_IDS, 69913: FOREVER_IDS}


def cut(src: Path, out_dir: Path) -> None:
    build, _ = read_ids(src)
    if build not in IDS_BY_BUILD:
        known = ", ".join(str(b) for b in IDS_BY_BUILD)
        raise SystemExit(f"cut-wdb-fixture: no record set for build {build} (have: {known})")
    buf = src.read_bytes()
    records: dict[int, bytes] = {}
    off = HEADER_SIZE
    while True:
        qid, length = RECORD_HEADER.unpack_from(buf, off)
        if qid == 0 and length == 0:
            break
        records[qid] = buf[off : off + RECORD_HEADER.size + length]
        off += RECORD_HEADER.size + length
    body = b"".join(records[i] for i in IDS_BY_BUILD[build])
    out_dir.mkdir(parents=True, exist_ok=True)
    fixture = out_dir / "questcache.wdb"
    fixture.write_bytes(buf[:HEADER_SIZE] + body + struct.pack("<II", 0, 0))
    cache = read_quests(fixture)
    expected = {
        "build": cache.build,
        "placeholders": cache.placeholders,
        "quests": [vars(q) for q in cache.quests],
    }
    (out_dir / "expected.json").write_text(json.dumps(expected, ensure_ascii=False, indent=1) + "\n", "utf-8")


if __name__ == "__main__":
    cut(Path(sys.argv[1]), Path(sys.argv[2]))
