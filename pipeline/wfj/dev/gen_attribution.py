"""Generate ATTRIBUTION.md: every translator whose Japanese is in `data/`, and the notices their work
came with.

Usage: python -m wfj.dev.gen_attribution [--corpus QuestLogData.lua] [--out ATTRIBUTION.md]

The translator list is the union of three sets, so a credit is never dropped: the tags on the hand-written
lines in `data/` (shipped or not, since the repository publishes both), the tags the file already lists, and,
with `--corpus`, the per-entry Translator tags of an earlier addon's quest data. The output is committed;
tests/python/test_attribution.py fails when `data/` holds a translator the file does not list.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from wfj.core import decisions, fix_report
from wfj.io.jsonl_store import Store
from wfj.paths import data_root

_RE_TAG = re.compile(r'\["Translator"\]\s*=\s*"((?:[^"\\]|\\.)*)"')

LINEAGE = """\
## Lineage

The hand-written Japanese translations were made for **WoWJapanizer**, **QuestJapanizer** and
**CraftJapanizer_Quest** (milai and the translators listed above), 2012. They reached this project through:

1. **WoWpoPolsku-Quests** (Platine, wowpopolsku.pl): the addon architecture the later forks used (GPLv2).
2. **Classic Quest Chinese Translator** (luckycat_tv) and **Tooltips Translator - Chinese** (qqytqqyt): the
   merge of the Japanese text into the WoWpoPolsku runtime (GPLv2).
3. **Classic Quest Japanese Translator** (Crynok / Zyaga) and **Classic Tooltip Japanese Translator** (Zyaga):
   earlier addons for WoW Classic (GPLv2).

QuestJapanizer's and CraftJapanizer_Quest's own releases were read directly for the lines the chain above had
cut short.

## License of the Japanese translations

WoWJapanizer, QuestJapanizer and CraftJapanizer_Quest are published on CurseForge under the BSD License, using
the three-clause template with its year and owner left blank. Its text, as the license requires:

> Copyright (c) \\<YEAR>, \\<OWNER>
> All rights reserved.
>
> Redistribution and use in source and binary forms, with or without modification, are permitted provided that
> the following conditions are met:
>
> 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the
>    following disclaimer.
> 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the
>    following disclaimer in the documentation and/or other materials provided with the distribution.
> 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or
>    promote products derived from this software without specific prior written permission.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
> WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
> PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY
> DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
> LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
> INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
> TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
> ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The translators are credited by the tags they used. Their credit here does not mean they endorse this project.

## Upstream notices

The earlier addons for WoW Classic (GPLv2, CurseForge), as declared in their own files:

- Classic Quest Japanese Translator: `## Author: Crynok / Zyaga` · `-- Author: Crynok and Zyaga` ·
  `-- Credit to: qytqqyt and Platine https://wowpopolsku.pl` · Notes: "Data gathered from mod
  \"WoWJapanizer\" and merged with \"Classic Quest Chinese Translator\" by luckycat_tv which was based
  upon WoWpoPolsku-Quests (https://wowpopolsku.pl)."
- Classic Tooltip Japanese Translator: `## Author: Zyaga` · `-- Credit to: qytqqyt` · Notes: "This is
  a modified version of \"Tooltips Translator - Chinese\" by qytqqyt."

## English source text

The English text in `data/english/` is Blizzard Entertainment's. It is kept to align and hash the
translations and is never shipped in the addon. It was read from the Forever client's own tables and quest
cache, the Classic Era quest cache, wago.tools DB2 exports (`ItemSparse`, `SpellName`), and:

- pfQuest (`db/enUS/quests.lua`, https://github.com/shagu/pfQuest), under the MIT License (below);
- the VMaNGOS world database (https://github.com/vmangos/core, release `db_latest`, snapshot `db-13b49dc`),
  GPL-2.0: quest progress and completion text, gossip and book pages.

## pfQuest license

> MIT License
>
> Copyright (c) 2017-2021 Eric Mauser (Shagu)
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
> associated documentation files (the "Software"), to deal in the Software without restriction, including
> without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
> following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial
> portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
> LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
> EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
> AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
> OR OTHER DEALINGS IN THE SOFTWARE.

## This project

WoW Forever Japanese ships its own code and translations under GPL-2.0-or-later (see `LICENSE`); every
translated line keeps its provenance in `data/` (`provenance.translator`). The English text in `data/english/`
is Blizzard Entertainment's and is not licensed by this project. The bundled font is IPA UI Gothic under the
IPA Font License v1.0 (see `addon/WoWForeverJapanese/Fonts/`). Details: `docs/legal/licensing.md`.
"""

# Tags that name a project or a community, not a person.
LABELS = ("CraftJapanizer", "WoWJapanizer", "questjapanizer-wiki")
LABEL_NOTE = """\
`CraftJapanizer`, `WoWJapanizer` and `questjapanizer-wiki` are not people: they mark lines those projects
published with no translator's tag of their own.
"""
_LISTED = re.compile(r"^- (.+)$", re.M)
_TRANSLATORS = re.compile(r"^## Translators.*?(?=^## |\Z)", re.M | re.S)


def _sorted(tags: set[str]) -> list[str]:
    tags.discard("")
    return sorted(tags, key=lambda t: (t.casefold(), t))


def translators(lua_text: str) -> list[str]:
    """The Translator tags of an earlier addon's quest data."""
    return _sorted({t.strip() for t in _RE_TAG.findall(lua_text)})


def data_translators(root: Path) -> list[str]:
    """The translator of every hand-written variant in `data/`, the line's own and its `conflicts`. A player
    credited through a fix report is left to the Correctors section."""
    tags: set[str] = set()
    store = Store(root)
    for type_ in fix_report.TYPES:
        for line in store.load(type_):
            for v in decisions.hand_written_variants(line):
                prov = v["provenance"]
                if "report" not in prov:
                    tags.add(prov["translator"])
    return _sorted(tags)


def listed_translators(text: str) -> list[str]:
    """The tags an ATTRIBUTION.md already lists under Translators."""
    m = _TRANSLATORS.search(text)
    return _sorted(set(_LISTED.findall(m.group(0)))) if m else []


CORRECTORS = "## Correctors"
_SECTION = re.compile(r"^## Correctors.*?(?=^## )", re.M | re.S)


def correctors_section(entries: dict[str, list[int]]) -> str:
    """The players (ADR-045) whose own Japanese a fix report brought in, with their report (issue)
    numbers; empty when there are none."""
    if not entries:
        return ""
    lines = [f"{CORRECTORS} (players whose fixes ship, with their fix reports)", ""]
    for name in sorted(entries, key=lambda t: (t.casefold(), t)):
        lines.append(f"- {name}: " + ", ".join(f"#{n}" for n in entries[name]))
    return "\n".join(lines) + "\n\n"


def with_correctors(text: str, entries: dict[str, list[int]]) -> str:
    """`text` with its Correctors section (before Lineage) set to `entries`; every other section unchanged."""
    text = _SECTION.sub("", text)
    at = text.find("## Lineage")
    section = correctors_section(entries)
    if not section or at < 0:
        return text
    return text[:at] + section + text[at:]


def render(tags: list[str]) -> str:
    lines = ["# Attribution", "", f"## Translators ({len(tags)} tags, as recorded in the corpus)", ""]
    lines += [f"- {t}" for t in tags]
    if any(t in LABELS for t in tags):
        lines += ["", LABEL_NOTE.rstrip("\n")]
    lines += ["", LINEAGE]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="gen_attribution")
    p.add_argument("--corpus", type=Path, help="an earlier addon's QuestLogData.lua, for its Translator tags")
    p.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[3] / "ATTRIBUTION.md")
    p.add_argument("--data", type=Path, default=None, help="the data/ folder (default: this repository's)")
    a = p.parse_args(argv)
    out = a.out
    before = out.read_text(encoding="utf-8") if out.is_file() else ""
    tags = set(data_translators(a.data or data_root())) | set(listed_translators(before))
    if a.corpus:
        tags |= set(translators(a.corpus.read_text(encoding="utf-8-sig")))
    # the Correctors section is written by `wfj report apply` from data/; a regeneration keeps it
    kept = _SECTION.search(before)
    text = render(_sorted(tags))
    if kept:
        at = text.find("## Lineage")
        # render always writes Lineage; without it the kept section goes at the end rather than being lost
        if at >= 0:
            text = text[:at] + kept.group(0) + text[at:]
        else:
            text = text.rstrip("\n") + "\n\n" + kept.group(0)
    out.write_text(text, encoding="utf-8")
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
