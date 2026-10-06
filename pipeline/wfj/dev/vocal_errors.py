"""The character's spoken error lines: which kind of error each game voice id is, from a local install.

    python -m wfj.dev.vocal_errors --wow "<World of Warcraft>" --product wow_classic_beta \\
        --listfile <community listfile> --out data/voice/error-kinds.jsonl

The error frame plays `C_Sound.PlayVocalErrorSound(voiceID)` for an error the game voices
[verified: forever 1.60.1.70170 blizzard_uierrorsframe/mainline/uierrorsframe.lua:150-152]. `VocalUISounds`
gives, per voice id (`VocalUIEnum`) and race, a male and a female sound kit; `SoundKitEntry` lists a kit's
files, and every file is named `<race><sex>_err_<kind>NN.ogg`. So a voice id's kind is read from its files'
names: the same for every race. A voice id whose files name two kinds is one combined kind
(`cantequiplevel-cantequipskill`); one with no file is left out and listed. Read-only, through
`io/casc.py` (ADR-021)."""

from __future__ import annotations

import argparse
import datetime
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

from wfj.io import casc, db2

VOCAL_UI_SOUNDS, SOUND_KIT_ENTRY = 1267067, 1237435
_KIND = re.compile(r"_err_([a-z0-9_]+?)\d*\.ogg$")


def kinds(archive: casc.LocalArchive, listfile: Path) -> tuple[dict[int, str], list[str]]:
    """voice id → kind, and the problems (ids with no file or with two kinds)."""
    def table(fdid: int, name: str) -> db2.Db2Table:
        buf, gaps = archive.read_file(fdid)
        return db2.read(buf, frozenset(), gaps, name)

    vocal, entries = table(VOCAL_UI_SOUNDS, "VocalUISounds"), table(SOUND_KIT_ENTRY, "SoundKitEntry")
    files: dict[int, list[int]] = defaultdict(list)
    for rid, row in entries.rows.items():
        files[entries.relation.get(rid, row[0])].append(row[1])
    names = {}
    with listfile.open(encoding="utf-8") as f:
        for line in f:
            fid, _, path = line.strip().partition(";")
            if "errormessages/" in path:
                names[int(fid)] = path.rsplit("/", 1)[1]
    found: dict[int, set[str]] = defaultdict(set)
    for enum, _race, _cls, kits in vocal.rows.values():
        for kit in kits:
            for fid in files.get(kit, []):
                m = _KIND.search(names.get(fid, ""))
                if m:
                    found[enum].add(m.group(1))
    out, problems = {}, []
    for enum in sorted({row[0] for row in vocal.rows.values()}):
        k = found.get(enum, set())
        # a voice id whose files say two things ("level too low", "skill too low") gets one line for both
        if k:
            out[enum] = "-".join(sorted(k))
        else:
            problems.append(f"voice id {enum}: no file")
    return out, problems


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wfj.dev.vocal_errors", description=__doc__.split("\n\n")[0])
    ap.add_argument("--wow", required=True, type=Path)
    ap.add_argument("--product", default="wow_classic_beta")
    ap.add_argument("--listfile", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    a = ap.parse_args(argv)
    archive = casc.LocalArchive(a.wow, a.product)
    build = casc.read_build_info(a.wow, a.product).version
    got, problems = kinds(archive, a.listfile)
    prov = {"source": f"client@{build}", "imported": datetime.date.today().isoformat()}
    rows = [{"voice_id": e, "kind": k, "provenance": prov} for e, k in sorted(got.items())]
    a.out.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    print(f"vocal errors: {len(rows)} voice ids, {len(set(got.values()))} kinds → {a.out}")
    for p in problems:
        print(f"vocal errors: left out {p}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
