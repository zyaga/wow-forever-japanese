"""Forever window sweep: every Blizzard addon in a Forever client UI extract, whether the `camelot`
game type loads it, and the files it loads, read from the client's own TOCs, so the window list is found
mechanically, never from a candidate list.

    python -m wfj.dev.client_addons <Interface/AddOns> > pipeline/forever_addons.txt     (make forever-addons)
    python -m wfj.dev.client_addons --titles <Interface/AddOns> [ADDON …]
    python -m wfj.dev.client_addons --files  <Interface/AddOns> ADDON …

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
- an XML file's `<Include file>` and `<Script file>` are followed, relative to that XML.

The default output is one `<addon> <state> <files>` line per addon, sorted: state is `gated` (the header keeps
camelot out), `glue`, `lod` (LoadOnDemand) or `login`; files is the size of the camelot load set found in the
extract. `--titles` lists every `SetTitle(` call site in the load sets as
`<addon> <site> <argument>  # line <n>`. `<site>` is `<path>@<function>`: the named function
the call is in, `main` outside any, with `~<k>` added for the k-th call when one function
makes more than one. A site keeps its name when lines above it move.
`--files` prints an addon's load set. pipeline/forever_addon_dispositions.txt gives every `login` / `lod`
addon a disposition; tests/python/test_forever_windows.py holds the two files together.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from wfj.dev.ui_inventory import file_index

MATCH = frozenset({"camelot", "mainline"})
STATES = ("gated", "glue", "login", "lod")
_TAG = re.compile(r"\[(\w+)(?:\s+([^\]]*))?\]")
_HEADER = re.compile(r"^##\s*([\w-]+)\s*:\s*(.*?)\s*$")
_INCLUDE = re.compile(r'<(?:Include|Script)\s+file\s*=\s*"([^"]+)"', re.I)
_FILE = re.compile(r"(\S+\.(?:lua|xml))", re.I)
_SET_TITLE = re.compile(r"[:.]SetTitle\(\s*([^;\n]*?)\s*\)\s*;?\s*(?:--.*)?$")
# A named function's first line: `function A.b:c(`, `local function d(`, `e.f = function(`.
_FUNCTION = re.compile(r"^\s*(?:local\s+)?function\s+([\w.:]+)\s*\(|^\s*([\w.:]+)\s*=\s*function\s*\(")
_TOP_END = re.compile(r"^end\b")
_PATH_TOKENS = {"family": "Mainline", "game": "Camelot"}


def _types(arg: str) -> set[str]:
    return {t.casefold() for t in re.split(r"[,\s]+", arg or "") if t}


def gate(tags: list[tuple[str, str]]) -> str:
    """'load', 'gated' or 'glue' for one set of (tag, argument) conditions."""
    for name, arg in tags:
        n = name.casefold()
        if n == "allowload" and arg.strip().casefold() == "glue":
            return "glue"
        if n == "allowloadgametype" and not (_types(arg) & MATCH):
            return "gated"
        if n == "excludeloadgametype" and _types(arg) & MATCH:
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


def state(toc: Path) -> str:
    head = headers(toc)
    verdict = gate(head)
    if verdict != "load":
        return verdict
    lod = any(k.casefold() == "loadondemand" and v.strip() == "1" for k, v in head)
    return "lod" if lod else "login"


def _expand(index: dict[str, Path], rel: str, seen: list[str]) -> None:
    key = rel.casefold()
    if key in seen or key not in index:
        return
    seen.append(key)
    if not key.endswith(".xml"):
        return
    text = index[key].read_text(encoding="utf-8-sig", errors="ignore")
    base = key.rsplit("/", 1)[0]
    for m in _INCLUDE.finditer(text):
        parts: list[str] = []
        for part in f"{base}/{m.group(1)}".replace("\\", "/").split("/"):
            if part == "..":
                if parts:
                    parts.pop()
            elif part not in ("", "."):
                parts.append(part)
        _expand(index, "/".join(parts), seen)


def load_set(index: dict[str, Path], addon: str, toc: Path) -> list[str]:
    """The casefolded paths (relative to AddOns) camelot loads for `addon`, in load order, that the extract
    has."""
    seen: list[str] = []
    for raw in toc.read_text(encoding="utf-8-sig", errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        tags = [(m.group(1), m.group(2) or "") for m in _TAG.finditer(line)]
        if gate([t for t in tags if t[0].casefold() not in _PATH_TOKENS]) != "load":
            continue
        path = _TAG.sub(lambda m: _PATH_TOKENS.get(m.group(1).casefold(), "") if m.group(2) is None else "",
                        line)
        if m := _FILE.match(path.strip().replace("\\", "/")):
            _expand(index, f"{addon}/{m.group(1)}", seen)
    return seen


def sweep(addons: Path, index: dict[str, Path] | None = None) -> list[tuple[str, str, list[str]]]:
    index = file_index(addons) if index is None else index
    rows = []
    for addon, toc in sorted(tocs(index).items()):
        st = state(toc)
        rows.append((addon, st, load_set(index, addon, toc) if st in ("login", "lod") else []))
    return rows


def titles(addons: Path, only: set[str] | None = None) -> list[tuple[str, str, int, str, str]]:
    """(addon, path, line, SetTitle argument, site) for every `SetTitle(` call in the in-game load sets.

    The site names the call by its path and the named function it is in: an anonymous
    function counts as part of the named one around it, and a top-level `end` closes it.
    `~<k>` is added when that function holds more than one call.
    """
    index = file_index(addons)
    out = []
    for addon, _, files in sweep(addons, index):
        if only and addon not in only:
            continue
        for rel in files:
            if not rel.endswith(".lua"):
                continue
            text = index[rel].read_text(encoding="utf-8-sig", errors="ignore")
            found, function = [], "main"
            for n, line in enumerate(text.splitlines(), 1):
                if m := _FUNCTION.match(line):
                    if not line.startswith((" ", "\t")) or function == "main":
                        function = m.group(1) or m.group(2)
                elif _TOP_END.match(line):
                    function = "main"
                if "GameTooltip_SetTitle" in line or "Tooltip:SetTitle" in line:
                    continue
                if m := _SET_TITLE.search(line.rstrip()):
                    found.append((n, m.group(1), function))
            per = {}
            for _, _, function in found:
                per[function] = per.get(function, 0) + 1
            seen = {}
            for n, arg, function in found:
                seen[function] = seen.get(function, 0) + 1
                site = f"{rel}@{function}" + (f"~{seen[function]}" if per[function] > 1 else "")
                out.append((addon, rel, n, arg, site))
    return out


def main(argv: list[str]) -> int:
    mode = "sweep"
    if argv[:1] and argv[0] in ("--titles", "--files"):
        mode, argv = argv[0][2:], argv[1:]
    if not argv or (mode == "files" and len(argv) < 2):
        print(__doc__, file=sys.stderr)
        return 2
    addons, names = Path(argv[0]), {a.casefold() for a in argv[1:]}
    if mode == "titles":
        for addon, _, n, arg, site in titles(addons, names or None):
            print(f"{addon} {site} {arg}  # line {n}")
    elif mode == "files":
        for addon, _, files in sweep(addons):
            if addon in names:
                print("\n".join(files))
    else:
        print("# GENERATED by `python -m wfj.dev.client_addons` from the Forever (camelot) UI extract's "
              "TOCs.")
        for addon, st, files in sweep(addons):
            print(f"{addon} {st} {len(files)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
