"""Enchantment stat-line drafts (ADR-016): one draft row per `SpellItemEnchantment:<id>` key, built
from a phrase table so every line with the same words reads the same in Japanese.

    python -m wfj.dev.enchant_drafts <SpellItemEnchantment.csv> pipeline/ui_enchant_phrases.tsv > draft.jsonl

`phrases.tsv`: `<English words>\t<Japanese label>` per line (`#` comments), e.g.
`Fire Spell Damage\t炎呪文ダメージ`. A stat line "+3 Fire Spell Damage" becomes "炎呪文ダメージ +3": label
before the signed number, one space (the dictionary convention: ITEM_MOD_STAMINA "スタミナ %c%d"). The
phrase table (committed: pipeline/ui_enchant_phrases.tsv) is machine-drafted UI text; the rows are imported
with `wfj import draft ui … --name ui-enchant` and carry machine provenance.
A stat line whose words are not in the table fails the run (named), so no row is silently skipped.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from wfj.io import wago

_LINE = re.compile(r"([+-]\d+) (.+)")


def read_phrases(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip() or raw.startswith("#"):
            continue
        en, sep, ja = raw.partition("\t")
        if not sep or not en.strip() or not ja.strip():
            raise ValueError(f"{path.name}:{n}: need '<English>\\t<Japanese>'")
        if en in out:
            raise ValueError(f"{path.name}:{n}: {en!r} listed twice")
        out[en] = ja.strip()
    return out


def drafts(enchantments: dict[str, str], phrases: dict[str, str]) -> list[dict[str, str]]:
    rows, missing = [], set()
    for key in sorted(enchantments, key=lambda k: int(k.split(":")[1])):
        m = _LINE.fullmatch(enchantments[key])
        if not m:
            raise ValueError(f"{key}: {enchantments[key]!r} is not a stat line")
        amount, words = m.groups()
        if words not in phrases:
            missing.add(words)
            continue
        rows.append({"id": key, "field": "text", "ja": f"{phrases[words]} {amount}"})
    if missing:
        raise ValueError(f"no phrase for: {', '.join(sorted(missing))}")
    return rows


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    for row in drafts(wago.read_enchantments(Path(argv[0])), read_phrases(Path(argv[1]))):
        print(json.dumps(row, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
