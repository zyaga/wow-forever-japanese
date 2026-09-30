"""Cut the committed test fixtures from the real source files (raw text slices, formatting preserved).

Usage: python -m wfj.dev.cut_fixtures --quest-repo P --tooltip-repo P --pfquest quests.lua \
           --item-csv ItemSparse.csv --spell-csv SpellName.csv --out ../tests/fixtures
The chosen ids are fixed below so the fixtures (and the tests that name ids) are reproducible.
"""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path

# 123 = duplicated with identical text; 184 = duplicated with differing text (real cases in the corpus).
QUEST_IDS = [
    "2",
    "5",
    "6",
    "7",
    "8",
    "9",
    "10",
    "11",
    "12",
    "13",
    "14",
    "15",
    "17",
    "18",
    "19",
    "20",
    "21",
    "22",
    "23",
    "24",
    "25",
    "26",
    "27",
    "28",
    "29",
    "30",
    "31",
    "32",
    "33",
    "35",
    "123",
    "184",
    # extra translators so the fixture carries ≥ 5 distinct Translator tags:
    "1258",
    "2039",
    "6385",
]
assert len(QUEST_IDS) == len(set(QUEST_IDS)), (
    "QUEST_IDS must not repeat an id (it would fabricate a duplicate)"
)
ITEM_IDS = [
    "117",
    "118",
    "159",
    "414",
    "422",
    "724",
    "728",
    "733",
    "737",
    "744",
    "858",
    "929",
    "1179",
    "1205",
    "1645",
    "1708",
    "2589",
    "2592",
    "3927",
    "4536",
]
SPELL_IDS = [
    "17",
    "53",
    "66",
    "71",
    "81",
    "99",
    "100",
    "116",
    "118",
    "120",
    "122",
    "130",
    "133",
    "136",
    "139",
    "143",
    "145",
    "168",
    "172",
    "185",
]
PFQUEST_IDS = [1, 2, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 22, 23]
WAGO_ITEM_IDS = {
    "25",
    "117",
    "118",
    "159",
    "414",
    "422",
    "724",
    "728",
    "733",
    "737",
    "744",
    "858",
    "929",
    "1179",
    "1205",
    "1645",
    "1708",
    "2589",
    "2592",
    "3927",
}
WAGO_SPELL_IDS = {
    "17",
    "53",
    "66",
    "71",
    "81",
    "99",
    "100",
    "116",
    "118",
    "120",
    "122",
    "130",
    "133",
    "136",
    "139",
    "143",
    "145",
    "168",
    "172",
    "185",
}


def cut_quest(text: str, ids: list[str]) -> str:
    head = text[: text.index('    ["')]
    blocks = []
    for id_ in ids:
        pattern = r"    \[\"" + re.escape(id_) + r"\"\] = \{\n(?:        .*\n)*?    \},?\n"
        if not re.search(pattern, text):
            print(f"cut_fixtures: quest id {id_} not found in source, skipped")
        for m in re.finditer(pattern, text):
            b = m.group(0)
            blocks.append(b if b.rstrip("\n").endswith(",") else b.rstrip("\n") + ",\n")
    return head + "".join(blocks) + "}\n"


def cut_lines(text: str, ids: list[str]) -> str:
    first, rest = text.split("\n", 1)
    wanted = []
    for id_ in ids:
        for line in rest.splitlines():
            if line.startswith(f'["{id_}"]='):
                wanted.append(line)
    return first + "\n" + "\n".join(wanted) + "\n}\n"


def cut_pfquest(text: str, ids: list[int]) -> str:
    head = text[: text.index("  [")]
    blocks = []
    for id_ in ids:
        m = re.search(r"  \[" + str(id_) + r"\] = \{\n(?:    .*\n)*?  \},\n", text)
        if m:
            blocks.append(m.group(0))
    return head + "".join(blocks) + "}\n"


def cut_csv(path: Path, ids: set[str]) -> str:
    with path.open(encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    keep = [rows[0]] + [r for r in rows[1:] if r[0] in ids]
    import io

    buf = io.StringIO()
    csv.writer(buf, lineterminator="\n").writerows(keep)
    return buf.getvalue()


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser()
    for opt in ("--quest-repo", "--tooltip-repo", "--pfquest", "--item-csv", "--spell-csv", "--out"):
        p.add_argument(opt, required=True)
    a = p.parse_args(argv)
    out = Path(a.out)
    (out / "predecessor").mkdir(parents=True, exist_ok=True)
    (out / "pfquest").mkdir(parents=True, exist_ok=True)
    (out / "wago").mkdir(parents=True, exist_ok=True)
    q = Path(a.quest_repo) / "QuestLogData.lua"
    (out / "predecessor/QuestLogData.excerpt.lua").write_text(
        cut_quest(q.read_text(encoding="utf-8-sig"), QUEST_IDS), encoding="utf-8"
    )
    it = Path(a.tooltip_repo) / "Data/Item/ItemData.lua"
    (out / "predecessor/ItemData.excerpt.lua").write_text(
        cut_lines(it.read_text(encoding="utf-8-sig"), ITEM_IDS), encoding="utf-8"
    )
    sp = Path(a.tooltip_repo) / "Data/Spell/SpellData.lua"
    (out / "predecessor/SpellData.excerpt.lua").write_text(
        cut_lines(sp.read_text(encoding="utf-8-sig"), SPELL_IDS), encoding="utf-8"
    )
    (out / "pfquest/quests.excerpt.lua").write_text(
        cut_pfquest(Path(a.pfquest).read_text(encoding="utf-8-sig"), PFQUEST_IDS), encoding="utf-8"
    )
    (out / "wago/ItemSparse.excerpt.csv").write_text(
        cut_csv(Path(a.item_csv), WAGO_ITEM_IDS), encoding="utf-8"
    )
    (out / "wago/SpellName.excerpt.csv").write_text(
        cut_csv(Path(a.spell_csv), WAGO_SPELL_IDS), encoding="utf-8"
    )
    print(f"fixtures written to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
