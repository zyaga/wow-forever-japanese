"""Extract interface files (FrameXML, Blizzard_* addons) from a local install (ADR-021's read path).

    python -m wfj.dev.client_ui --wow "<World of Warcraft>" --product wow_classic_beta --out <dir> \
        [--files Interface/FrameXML/QuestFrame.lua …] [--list <file of paths>] [--listfile <id;path csv>]

Reads `.build.info` and `Data/` of the install and writes only into `--out` (refused inside the install), the
same read-only contract as `wfj.dev.client_tables`. Each requested path is resolved through the archive's root
by name hash and, when the root carries no names (as on the Forever beta build), through the `--listfile`
id;path CSV instead (the community listfile). A path neither can resolve is reported `missing`, not raised;
content the client has not downloaded reports `not downloaded`. Prints the build, then one line
per file (path, FileDataID, bytes, or `missing`), and exits 1 when no file at all could be resolved; that
answer ("this client's root names nothing we asked for") is itself the finding.

The default list covers the surfaces the addon hooks: quest frame and log, gossip, item text, trainer, the
tooltip, the game menu and the always-visible windows.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from wfj.io import casc

DEFAULT_FILES = (
    "Interface/FrameXML/QuestFrame.lua",
    "Interface/FrameXML/QuestFrame.xml",
    "Interface/FrameXML/QuestLogFrame.lua",
    "Interface/FrameXML/GossipFrame.lua",
    "Interface/FrameXML/GossipFrame.xml",
    "Interface/FrameXML/ItemTextFrame.lua",
    "Interface/FrameXML/ItemTextFrame.xml",
    "Interface/FrameXML/GameTooltip.lua",
    "Interface/FrameXML/GameTooltip.xml",
    "Interface/FrameXML/GameMenuFrame.lua",
    "Interface/FrameXML/MailFrame.lua",
    "Interface/FrameXML/MerchantFrame.lua",
    "Interface/FrameXML/SpellBookFrame.lua",
    "Interface/FrameXML/FriendsFrame.lua",
    "Interface/FrameXML/RaidFrame.lua",
    "Interface/FrameXML/PaperDollFrame.lua",
    "Interface/AddOns/Blizzard_TrainerUI/Blizzard_TrainerUI.lua",
    "Interface/AddOns/Blizzard_TalentUI/Blizzard_TalentUI.lua",
    "Interface/AddOns/Blizzard_UIPanels_Game/Classic/ItemTextFrame.lua",
    "Interface/AddOns/Blizzard_UIPanels_Game/Classic/QuestFrame.lua",
)


def inside(out: Path, wow: Path) -> bool:
    """True when `out` is the install or sits under it. Compared case-folded: this project's game drive is a
    case-insensitive volume, so a miscased --out would otherwise slip past the guard.
    `os.path.normcase` is a no-op outside Windows, so the fold is explicit; refusing a path that only differs
    in case on a case-sensitive volume is the safe direction."""
    def parts(p: Path) -> list[str]:
        return [x.casefold() for x in p.resolve().parts]
    o, w = parts(out), parts(wow)
    return o[: len(w)] == w


def read_listfile(path: Path) -> dict[str, int]:
    """`<FileDataID>;<path>` per line → {lower-case path: id}, the community listfile's shape."""
    out: dict[str, int] = {}
    with path.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            fid, _, name = line.partition(";")
            name = name.strip().lower()
            if name and fid.strip().isdigit():
                out[name] = int(fid)
    return out


def safe_target(out: Path, path: str) -> Path | None:
    """Where `path` may be written under `out`, or None when it escapes. The requested paths come from a
    third-party listfile, so an absolute path, a drive letter or a `..` component must never place a write
    outside `--out`, and never inside the game install (pipeline tooling only reads the game folder)."""
    cleaned = path.replace("\\", "/").strip()
    if not cleaned or cleaned.startswith("/") or re.match(r"^[A-Za-z]:", cleaned):
        return None
    if any(part in ("..", "") for part in cleaned.split("/")[:-1]) or cleaned.endswith("/"):
        return None
    target = (out / cleaned).resolve()
    return target if target.is_relative_to(out.resolve()) else None


def extract(
    wow: Path, product: str, out: Path, files: list[str], listfile: dict[str, int] | None = None
) -> list[tuple[str, int | None, int | None]]:
    """(path, FileDataID, bytes) per requested file; FileDataID None when neither the root nor the listfile
    names it, bytes None when the client has not downloaded that content."""
    if inside(out, wow):
        raise SystemExit(f"client_ui: --out {out} is inside the install; write somewhere else")
    archive = casc.LocalArchive(wow, product)
    out.mkdir(parents=True, exist_ok=True)
    rows: list[tuple[str, int | None, int | None]] = []
    for path in files:
        try:
            fdid = archive.file_data_id(path)
        except Exception:  # a root without this name: the finding, not a crash
            fdid = 0
        if not fdid and listfile:
            fdid = listfile.get(path.lower(), 0)
        if not fdid:
            rows.append((path, None, None))
            continue
        try:
            data, _ = archive.read_file(fdid)
        except Exception as e:  # encrypted or absent content: report, keep going
            print(f"{path}: fdid {fdid} unreadable ({type(e).__name__})", file=sys.stderr)
            rows.append((path, fdid, None))
            continue
        # keep the client's own layout (several flavours share one basename), but never outside --out
        target = safe_target(out, path)
        if target is None:
            print(f"{path}: refused: the path escapes --out", file=sys.stderr)
            rows.append((path, fdid, None))
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        rows.append((path, fdid, len(data)))
    return rows


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wfj.dev.client_ui", description=__doc__.split("\n\n")[0])
    ap.add_argument("--wow", required=True, type=Path, help="the folder holding .build.info")
    ap.add_argument("--product", default="wow_classic_beta")
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--files", nargs="*", default=None)
    ap.add_argument("--list", type=Path, help="a file of interface paths, one per line")
    ap.add_argument("--listfile", type=Path, help="an id;path CSV, for a client whose root carries no names")
    args = ap.parse_args(argv)
    files = list(args.files or ())
    if args.list:
        files += [ln.strip() for ln in args.list.read_text(encoding="utf-8").splitlines() if ln.strip()]
    files = files or list(DEFAULT_FILES)
    info = casc.read_build_info(args.wow, args.product)
    print(f"client_ui: {args.product} {info.version}")
    listfile = read_listfile(args.listfile) if args.listfile else None
    rows = extract(args.wow, args.product, args.out, files, listfile)
    for path, fdid, size in rows:
        state = "missing" if fdid is None else f"fdid {fdid} · {size if size else 'not downloaded'}"
        print(f"{path}: {state}")
    got = [r for r in rows if r[2]]
    print(f"client_ui: {len(got)} of {len(rows)} files extracted → {args.out}")
    return 0 if got else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
