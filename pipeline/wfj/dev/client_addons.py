"""Forever window sweep: every Blizzard addon in a Forever client UI extract, whether the `camelot`
game type loads it, and the files it loads, read from the client's own TOCs, so the window list is found
mechanically, never from a candidate list.

    python -m wfj.dev.client_addons <Interface/AddOns> > pipeline/forever_addons.txt     (make forever-addons)
    python -m wfj.dev.client_addons --titles <Interface/AddOns> [ADDON …]
    python -m wfj.dev.client_addons --files  <Interface/AddOns> ADDON …
    python -m wfj.dev.client_addons --game standard <Interface/AddOns>                   (make retail-addons)

`--game` (first, before any mode) names the game type whose load sets are resolved: `camelot` (Forever, the
default) or `standard` (retail). Both are members of the `mainline` family; `[Game]` is `Standard` on retail.

`<Interface/AddOns>` is a `wfj.dev.client_ui` extract whose path list includes the addons' `.toc` files
(lowercased paths are fine: everything resolves through a casefold index).

Forever is game type `camelot`, a member of the `mainline` family (ADR-029):
- `[Family]` in a path is `Mainline`, `[Game]` is `Camelot`;
- a TOC line, or a `## AllowLoadGameType:` header, loads when it names `camelot` or `mainline`; an
  `ExcludeLoadGameType` naming either drops it. `standard` and `classic` do not include camelot: the client's
  TOCs write `[AllowLoadGameType standard, camelot]` where both are meant
  (the Forever window sweep in docs/research/);
- `## AllowLoad: Glue` (header) and `[AllowLoad glue]` (line) are the login screens, where no addon runs;
- `<Addon>_Mainline.toc` is read in preference to `<Addon>.toc`;
- an XML file's `<Include file>` and `<Script file>` are followed: beside that XML file, else from the addon's folder.

The default output is one `<addon> <state> <files>` line per addon, sorted: state is `gated` (the header keeps
camelot out), `glue`, `lod` (LoadOnDemand) or `login`; files is the size of the camelot load set found in the
extract. `--titles` lists every `SetTitle(` call site in the load sets as `<addon> <path>:<line> <argument>`.
`--files` prints an addon's load set. pipeline/forever_addon_dispositions.txt gives every `login` / `lod`
addon a disposition; tests/python/test_forever_windows.py holds the two files together.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from wfj.dev.ui_inventory import file_index

# game type → (the folder `[Game]` names in a path, the client as the generated list's first line names it).
# Each is a member of the mainline family.
GAMES = {"camelot": ("Camelot", "Forever (camelot)"), "standard": ("Standard", "retail (standard)")}
DEFAULT_GAME = "camelot"
STATES = ("gated", "glue", "login", "lod")
_TAG = re.compile(r"\[(\w+)(?:\s+([^\]]*))?\]")
_HEADER = re.compile(r"^##\s*([\w-]+)\s*:\s*(.*?)\s*$")
_INCLUDE = re.compile(r'<(?:Include|Script)\s+file\s*=\s*"([^"]+)"', re.I)
_FILE = re.compile(r"(\S+\.(?:lua|xml))", re.I)
_SET_TITLE = re.compile(r"[:.]SetTitle\(\s*([^;\n]*?)\s*\)\s*;?\s*(?:--.*)?$")


def _types(arg: str) -> set[str]:
    return {t.casefold() for t in re.split(r"[,\s]+", arg or "") if t}


def gate(tags: list[tuple[str, str]], game: str = "camelot") -> str:
    """'load', 'gated' or 'glue' for one set of (tag, argument) conditions, as the `game` type reads them."""
    match = {game, "mainline"}  # a condition means this game type by its own name or its family's
    for name, arg in tags:
        n = name.casefold()
        if n == "allowload" and arg.strip().casefold() == "glue":
            return "glue"
        if n == "allowloadgametype" and not (_types(arg) & match):
            return "gated"
        if n == "excludeloadgametype" and _types(arg) & match:
            return "gated"
        if n == "allowloadtextlocale" and "enus" not in _types(arg):
            return "gated"
    return "load"


def tocs(index: dict[str, Path]) -> dict[str, Path]:
    """{addon folder (casefolded): its TOC}, `_Mainline.toc` first."""
    found: dict[str, Path] = {}
    for key in sorted(index):
        parts = key.split("/")
        if len(parts) != 2 or not parts[1].endswith(".toc"):
            continue
        addon, name = parts
        if name == f"{addon}_mainline.toc" or (name == f"{addon}.toc" and addon not in found):
            found[addon] = index[key]
    return found


def headers(toc: Path) -> list[tuple[str, str]]:
    out = []
    for raw in toc.read_text(encoding="utf-8-sig", errors="ignore").splitlines():
        if m := _HEADER.match(raw.strip()):
            out.append((m.group(1), m.group(2)))
    return out


def state(toc: Path, game: str = "camelot") -> str:
    head = headers(toc)
    verdict = gate(head, game)
    if verdict != "load":
        return verdict
    lod = any(k.casefold() == "loadondemand" and v.strip() == "1" for k, v in head)
    return "lod" if lod else "login"


def _resolve(base: str, named: str) -> str:
    """`named` as written in a file of the folder `base`, with its `..` and `.` segments worked out."""
    parts: list[str] = []
    for part in f"{base}/{named}".replace("\\", "/").split("/"):
        if part == "..":
            if parts:
                parts.pop()
        elif part not in ("", "."):
            parts.append(part)
    return "/".join(parts)


def _expand(index: dict[str, Path], rel: str, seen: list[str]) -> None:
    key = rel.casefold()
    if key in seen or key not in index:
        return
    seen.append(key)
    if not key.endswith(".xml"):
        return
    text = index[key].read_text(encoding="utf-8-sig", errors="ignore")
    base, addon = key.rsplit("/", 1)[0], key.split("/", 1)[0]
    for m in _INCLUDE.finditer(text):
        beside = _resolve(base, m.group(1))
        # the client also finds a path written from the addon's folder (Mainline\ItemButtonTemplate.xml names
        # its script as Mainline\ItemButtonTemplate.lua)
        _expand(index, beside if beside.casefold() in index else _resolve(addon, m.group(1)), seen)


def load_set(index: dict[str, Path], addon: str, toc: Path, game: str = "camelot") -> list[str]:
    """The casefolded paths (relative to AddOns) the `game` type loads for `addon`, in load order, that the
    extract has."""
    folders = {"family": "Mainline", "game": GAMES[game][0]}
    seen: list[str] = []
    for raw in toc.read_text(encoding="utf-8-sig", errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        tags = [(m.group(1), m.group(2) or "") for m in _TAG.finditer(line)]
        if gate([t for t in tags if t[0].casefold() not in folders], game) != "load":
            continue
        path = _TAG.sub(lambda m: folders.get(m.group(1).casefold(), "") if m.group(2) is None else "", line)
        if m := _FILE.match(path.strip().replace("\\", "/")):
            _expand(index, f"{addon}/{m.group(1)}", seen)
    return seen


def sweep(addons: Path, index: dict[str, Path] | None = None,
          game: str = "camelot") -> list[tuple[str, str, list[str]]]:
    index = file_index(addons) if index is None else index
    rows = []
    for addon, toc in sorted(tocs(index).items()):
        st = state(toc, game)
        rows.append((addon, st, load_set(index, addon, toc, game) if st in ("login", "lod") else []))
    return rows


def loaded_files(source: Path, game: str) -> list[Path]:
    """The files of a client UI extract the `game` type loads in game, in load order. `source` is the
    extract's root or its `interface/addons` folder. A client can ship the source of a whole window it never
    loads, so a name found only outside this list is not in that client."""
    addons = source / "interface" / "addons"
    if not addons.is_dir():
        addons = source
    index = file_index(addons)
    return [index[rel] for _addon, _state, files in sweep(addons, index, game) for rel in files]


def titles(addons: Path, only: set[str] | None = None,
           game: str = "camelot") -> list[tuple[str, str, int, str]]:
    """(addon, path, line, SetTitle argument) for every `SetTitle(` call in the in-game load sets."""
    index = file_index(addons)
    out = []
    for addon, _, files in sweep(addons, index, game):
        if only and addon not in only:
            continue
        for rel in files:
            if not rel.endswith(".lua"):
                continue
            text = index[rel].read_text(encoding="utf-8-sig", errors="ignore")
            for n, line in enumerate(text.splitlines(), 1):
                if "GameTooltip_SetTitle" in line or "Tooltip:SetTitle" in line:
                    continue
                if m := _SET_TITLE.search(line.rstrip()):
                    out.append((addon, rel, n, m.group(1)))
    return out


def main(argv: list[str]) -> int:
    mode, game = "sweep", "camelot"
    if argv[:1] == ["--game"]:
        if len(argv) < 2 or argv[1] not in GAMES:
            print(f"client_addons: --game takes one of {', '.join(sorted(GAMES))}", file=sys.stderr)
            return 2
        game, argv = argv[1], argv[2:]
    if argv[:1] and argv[0] in ("--titles", "--files"):
        mode, argv = argv[0][2:], argv[1:]
    if not argv or (mode == "files" and len(argv) < 2):
        print(__doc__, file=sys.stderr)
        return 2
    if argv[0].startswith("--"):
        print(f"client_addons: {argv[0]} where the AddOns folder goes (--game comes first, then the mode)",
              file=sys.stderr)
        return 2
    addons, names = Path(argv[0]), {a.casefold() for a in argv[1:]}
    if not addons.is_dir() or not tocs(file_index(addons)):
        print(f"client_addons: no Blizzard addon under {addons}: is it an extract's interface/addons folder?",
              file=sys.stderr)
        return 2
    if mode == "titles":
        for addon, rel, n, arg in titles(addons, names or None, game):
            print(f"{addon} {rel}:{n} {arg}")
    elif mode == "files":
        for addon, _, files in sweep(addons, game=game):
            if addon in names:
                print("\n".join(files))
    else:
        flag = "" if game == DEFAULT_GAME else f" --game {game}"
        print(f"# GENERATED by `python -m wfj.dev.client_addons{flag}` from the {GAMES[game][1]} UI "
              "extract's TOCs.")
        for addon, st, files in sweep(addons, game=game):
            print(f"{addon} {st} {len(files)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
