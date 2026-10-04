"""Generate the shared normalize/hash vectors (canonical JSONL + a Lua twin for busted).

Usage: python -m wfj.dev.gen_vectors <vectors-dir>
Both files are committed; tests/python/test_vectors.py fails if a regeneration differs.
"""

from __future__ import annotations

import json
import sys
import unicodedata
from pathlib import Path

from wfj.core.hashing import hash32x2, key_from_pair
from wfj.core.normalize import Player, normalize_v1
from wfj.emit.lua_writer import vectors_text

P = Player(name="Reyn", class_="Hunter", race="Night Elf")
BIG = ("The mighty hippogryph Sharptalon has been slain. " * 90)[:4200]

CASES: list[tuple[str, str, Player | None]] = [
    ("ascii-01", "Kill 10 Kobold Vermin and report to Marshal McBride.", None),
    ("ascii-02", "Bring Sharptalon's Claw to Senani Thunderheart at Splintertree Post, Ashenvale.", None),
    ("ascii-03", "Hello there.", None),
    ("ascii-04", "Hello there", None),
    ("ja-01", "大いなるヒポグリフSharptalonは倒され、死んだ獣の鉤爪が勝利の証となった。", None),
    ("ja-02", "Kobold Verminを10匹殺して、Marshal McBrideへ報告してください。", None),
    ("color-01", "|cffffd100Quest|r text here", None),
    ("color-02", "|cff00ff00Use:|r Restores 70 to 90 health.", None),
    ("color-03", "no |r stray reset", None),
    ("tex-01", "Icon |TInterface\\Icons\\INV_Misc_Bag_08:16|t then text", None),
    ("link-01", "Bring |Hitem:2589::::::::1:::::|h[Linen Cloth]|h to me.", None),
    ("link-02", "See |Hquest:2:5|h[Sharptalon's Claw]|h for details.", None),
    ("newline-01", "First line|nSecond line", None),
    ("brk-01", "Paragraph one.$BParagraph two.", None),
    ("brk-02", "lower $b break", None),
    ("ph-01", "Greetings, $N.", None),
    ("ph-02", "greetings, $n.", None),
    ("ph-03", "A fine $C you are.", None),
    ("ph-04", "a fine $c you are.", None),
    ("ph-05", "Welcome, $R.", None),
    ("ph-06", "welcome, $r.", None),
    ("ph-07", "$N the $C of the $R", None),
    ("gender-01", "Well met, $Gsir:madam;.", None),
    ("gender-02", "Well met, $gsir:madam;.", None),
    ("gender-03", "A favor for me, $g lad : lass;?", None),
    ("gender-04", "Ye want to go, $Gboyo :lass;!", None),
    ("gender-05", "Hello, $g\u00a0lad : lass;.", None),
    ("fwdigit-01", "Kill １０ Kobold Vermin", None),
    ("fwdigit-02", "０１２３４５６７８９ and 0123456789", None),
    ("ws-01", "  leading and trailing  ", None),
    ("ws-02", "many    spaces\tand\ttabs", None),
    ("ws-03", "crlf\r\nline\r\nbreaks", None),
    ("ws-04", "newline\n\n\nruns", None),
    ("ws-05", "\n", None),
    ("ws-06", "\u3000leading ideographic space", None),
    ("ws-07", "trailing nbsp\u00a0", None),
    ("ws-08", "a\u2028b\u2028", None),
    ("ws-09", "inner\u00a0nbsp kept", None),
    ("empty-01", "", None),
    ("big-01", BIG, None),
    ("nfc-01", "Café au lait", None),
    ("mixed-01", "|cffffd100$N|r, kill １０ |Hunit:x|h[Kobold Vermin]|h$Bthen return.", None),
    ("player-01", "Well done, Reyn. Return to me.", P),
    ("player-02", "Reyn's claw is yours, Hunter.", P),
    ("player-03", "The Marketplace is closed, Mark.", Player(name="Mark")),
    ("player-04", "A hunter walks in. Hunter, greetings.", P),
    ("player-05", "Night Elf lands are north. NIGHT ELF is not.", P),
    ("player-06", "Al is short. Alliance stands.", Player(name="Al")),
    ("player-07", "Reyn Reyn Reyn", P),
    ("player-08", "AndreynReyn Reyn-Reyn (Reyn)", P),
    ("player-09", "Lé Lé and Léo", Player(name="Lé")),
    ("player-10", "太郎 goes; 太郎丸 stays.", Player(name="太郎")),
    ("player-11", "Ärzte heal. Ärzte!", Player(name="Ärzte")),
]


def build() -> list[dict]:
    rows = []
    for cid, raw_in, player in CASES:
        # Vectors carry NFC input only: the Lua twin cannot normalize composition, so the contract
        # is "identical output for NFC input". Non-NFC input is covered by test_normalize.py::test_nfc.
        raw = unicodedata.normalize("NFC", raw_in)
        norm = normalize_v1(raw, player)
        h1, h2 = hash32x2(norm)
        row = {
            "id": cid,
            "raw": raw,
            "player": None,
            "norm": norm,
            "h1": h1,
            "h2": h2,
            "key": key_from_pair(h1, h2),
        }
        if player is not None:
            row["player"] = {"name": player.name, "class": player.class_, "race": player.race}
        rows.append(row)
    return rows


def to_lua(rows: list[dict], head: str = "return") -> str:
    return vectors_text(rows, head)


def write(out_dir: Path) -> None:
    rows = build()
    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "hash_vectors.jsonl").open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    (out_dir / "hash_vectors.lua").write_text(to_lua(rows), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    out = Path(args[0]) if args else Path(__file__).resolve().parents[3] / "vectors"
    write(out)
    print(f"wrote {out / 'hash_vectors.jsonl'} and .lua ({len(CASES)} cases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
