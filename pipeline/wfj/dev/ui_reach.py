"""Where the Forever (camelot) client can show a UI string: every non-comment reference to a key in the
files the client loads, with the addon and its load state, so an exclusion's reason can cite the file and
line that keeps the string off the screen, or be found to rest on nothing.

    python -m wfj.dev.ui_reach <Interface/AddOns> KEY [KEY …]
    python -m wfj.dev.ui_reach <Interface/AddOns> --keys <file with one key per line>

Output: one `<key>\\t<addon>\\t<state>\\t<path>:<line>\\t<the line, trimmed>` per reference, sorted, and
`<key>\\t-\\t-\\t-\\t(no reference in any loaded file)` for a key no loaded file names (a tooltip line the C
client writes, or a chat line). `state` is `login` or `lod` (`wfj.dev.client_addons`); a file an addon the
client does not load (`gated`, `glue`) is never listed, so a reference here is one the client can reach.
Comments (`--`, `<!-- -->`) are stripped before the scan; the name match is `ui_inventory`'s.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from wfj.dev import client_addons
from wfj.dev.ui_inventory import _NAMES, _strip_comments, file_index, resolve
from wfj.io import wago

_XML_COMMENT = re.compile(r"<!--.*?-->", re.S)


def _strip(text: str, rel: str) -> str:
    """The file without its comments, line structure kept (an XML comment spanning lines leaves its line
    breaks so line numbers still count)."""
    if rel.endswith(".xml"):
        return _XML_COMMENT.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    return _strip_comments(text)


def references(addons: Path, keys: set[str]) -> list[tuple[str, str, str, str, str]]:
    """(key, addon, state, path:line, line) for every reference to one of `keys` in a loaded file."""
    index = file_index(addons)
    out: list[tuple[str, str, str, str, str]] = []
    for addon, state, files in client_addons.sweep(addons, index):
        for rel in files:
            if not rel.endswith((".lua", ".xml")):
                continue
            raw = resolve(index, rel).read_text(encoding="utf-8", errors="ignore")
            for n, line in enumerate(_strip(raw, rel).splitlines(), 1):
                found = {next(g for g in m.groups() if g) for m in _NAMES.finditer(line)}
                for key in found & keys:
                    out.append((key, addon, state, f"{rel}:{n}", " ".join(line.split())))
    return sorted(out)


def main(argv: list[str]) -> int:
    if len(argv) < 2 or (argv[1] == "--keys" and len(argv) < 3):
        print(__doc__, file=sys.stderr)
        return 2
    addons = Path(argv[0])
    keys = set(wago.read_keys(Path(argv[2]))) if argv[1] == "--keys" else set(argv[1:])
    rows = references(addons, keys)
    seen = {r[0] for r in rows}
    for row in rows:
        print("\t".join(row))
    for key in sorted(keys - seen):
        print(f"{key}\t-\t-\t-\t(no reference in any loaded file)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
