"""Generate vectors/align_vectors.{jsonl,lua}: the shared contract between core/align.py and Core/Align.lua.

Each row: {id, op, text, scope?, allowlist, expected}. `op` ∈ names · checkNames · numbers · numberWords ·
variantKey · values · valuesLoose · wordedSlots · grantedHead · grantedCount. `expected` is the Python result
(numbers: sorted multiset as a list; variantKey: the key of the English template in `scope`, which the Lua
side must compute from the rendered live line in `text`; values / valuesLoose: what the addon reads off the
live line in `text`; wordedSlots: the Japanese in `text` ready for a worded duration in `$D1`; grantedHead:
the head of the Japanese in `text` against the live line in `scope`; grantedCount: the count of that head's
value slots, as a string; the last three are "" when there is none). Both suites iterate every row.
Usage: python -m wfj.dev.gen_align_vectors [out_dir]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from wfj.core import align
from wfj.emit.lua_writer import lua_string

AL = ["health", "mana", "horde", "stamina"]

# Two granted abilities whose heading prints values (spells 401417 and 412510), as the client prints them
# for a character without the ability: the heading, the ability's name, its icon and nothing after it
TEMPORAL_JA = ("$D1かけて体力を$N1回復し、$D2の間Temporal Beaconを付与します。\r\n\n"
               "Temporal Beacon\r\n$I1\r\n"
               "対象の時空間の位置を記録します。Arcaneダメージの$N4%が変換されます。")
TEMPORAL_LIVE = ("Heals the target for 450 health over 12 sec and applies Temporal Beacon for 60 sec. "
                 "\r\n\r\nTemporal Beacon\r\n|T237538:24|t\r\n")
PARTY_JA = ("対象のプレイヤーから$N1ヤード以内にいる、そのプレイヤーのパーティーメンバー全員を"
            "$D1かけて体力を$N2回復し、それぞれに$D2の間Temporal Beaconを付与します。\r\n\n"
            "Temporal Beacon\r\n$I1\r\n"
            "対象の時空間の位置を記録します。Arcaneダメージの$N5%が変換されます。")
PARTY_LIVE = ("Heals all of target player's party members within 40 yards of target player for 300 health "
              "over 12 sec and applies Temporal Beacon to each target for 30 sec.\r\n\r\n"
              "Temporal Beacon\r\n|T237538:24|t")
WYVERN_JA = "Wyvern Strikeのアビリティを得ます：\n\n$I1\n$N1のダメージを与えます。"

CASES: list[tuple[str, str, str, str | None]] = [
    # id, op, text, scope
    ("names-01", "names", "Silverwind RefugeにいるSenani Thunderheartは、Sharptalon's Clawを見た。", None),
    ("names-02", "names", "Healthを回復。Manaも。Hordeの兵士。", None),
    ("names-03", "names", "Mk2 の ab cd と Kul'Tiras", None),
    ("names-04", "names", "{name}と{class}は Northshire Abbeyへ", None),
    ("names-05", "names", "Sharptalon’s Claw と Deathstalker Quinn", None),
    ("names-06", "names", "Splintertree Post, Ashenvale", None),
    ("names-07", "names", "Twilight's Hammer と twilight's hammer", None),
    ("names-08", "names", "ワインWineとワイン", None),
    ("names-09", "names", "Thunder Bluffの Cairne Bloodhoof", None),
    ("names-10", "names", "Restores 61 health over 18 sec. Must remain seated while eating.", None),
    (
        "check-01",
        "checkNames",
        "Silverwind RefugeにいるSenani Thunderheart",
        "Bring Sharptalon's Claw to Senani Thunderheart at Splintertree Post, Ashenvale.",
    ),
    ("check-02", "checkNames", "Post Splintertreeへ", "Bring it to Splintertree Post, Ashenvale."),
    ("check-03", "checkNames", "Chef Grualと話して下さい", "Speak with Chef Grual in Goldshire."),
    ("check-04", "checkNames", "Chef Grualと話して下さい", "Speak with Grual in Goldshire."),
    ("check-05", "checkNames", "Healthを回復", "Restores 61 health over 18 sec."),
    ("check-06", "checkNames", "Kul'Tirasの船", "The ships of Kul Tiras"),
    ("check-07", "checkNames", "Hakkarの祭壇", "the altar of Hakkari"),
    ("check-08", "checkNames", "Durnholde Keepへ", "Go to Durnholde."),
    ("numbers-01", "numbers", "Kobold Verminを１０匹殺し、Mk2を3つ", None),
    ("numbers-02", "numbers", "18秒間でhealthを61回復。回復中は座っている必要があります。", None),
    ("numbers-03", "numbers", "1,200ダメージと18.5秒", None),
    ("numbers-04", "numbers", "N1とN2は数ではない。５０ゴールド。", None),
    ("numbers-05", "numbers", "2abc 3 4x 55 66", None),
    ("numbers-06", "numbers", "Use: Restores 61 health over 18 sec. 3 3 3", None),
    ("numbers-07", "numbers", "Mk12を使え、abc12と34xyz、over 18sec.", None),
    ("numbers-08", "numbers", "Deals 12abc damage and 120 more", None),
    ("words-01", "numberWords", "twenty-five silver and two hundred gold, a dozen eggs", None),
    ("words-02", "numberWords", "Kill six Kobold Vermin and one Kobold Worker", None),
    ("words-03", "numberWords", "one thousand years; Single target; NINE lives", None),
    ("words-04", "numberWords", "Restores 61 health over 18 sec.", None),
    ("words-05", "numberWords", "thirteen-fourteen fifty two", None),
    ("words-06", "numberWords", "one2 and 3three and ten thousand and twenty five", None),
    ("words-07", "numberWords", "Hundred one-time a single", None),
    # variantKey: text = the live line as the client renders it, scope = the English template it came from
    ("key-01", "variantKey", "Increases all damage you deal by 4%.",
     "Increases all damage you deal by $s1%."),
    ("key-02", "variantKey", "Increases the damage you deal with physical attacks in all forms by 4%.",
     "Increases the damage you deal with physical attacks in all forms by $s1%."),
    ("key-03", "variantKey", "The Enrage ability instantly generates an additional 5 Rage.",
     "The Enrage ability instantly generates an additional $/10;17080s1 Rage."),
    ("key-04", "variantKey", "Immune to snare and root effects.\r\nMovement speed increased by 50%.",
     "Immune to snare and root effects.\r\nMovement speed increased by 50%."),
    ("key-05", "variantKey", "3 trophies gathered as victories while Dueling to the Death.",
     "$w trophies gathered as victories while Dueling to the Death."),
    ("key-06", "variantKey", "Absorbs 1,230 Fire damage for 30 sec.", "Absorbs $s1 Fire damage for $d."),
    ("key-07", "variantKey", "Causes 14 to 22 Fire damage every 3 sec.",
     "Causes $s1 to $s2 Fire damage every $t1 sec."),
    ("key-08", "variantKey", "Deals 2.5% damage over 2 min and lasts 1 hr 30 min.",
     "Deals ${$s1/4}.1% damage over $d and lasts $1d."),
    ("key-09", "variantKey", "|Tinterface\\icons\\x:0|t Quick Draw: 25 damage.",
     "$I1 Quick Draw: $s1 damage."),
    ("key-10", "variantKey", "|cFFFFFFFFRequires Cat Form|r  Increases damage by 5.",
     "|cFFFFFFFFRequires Cat Form|r  Increases damage by $s1."),
    ("key-11", "variantKey",
     "Each melee attack or non-instant spell cast has a chance of causing Clearcasting.",
     "Each melee attack or non-instant spell cast has a chance of causing Clearcasting."),
    ("key-12", "variantKey", "Heals a friendly target for 120 to 140.",
     "Heals a friendly target for ${$<healpower>*$436517m1/100} to ${$<healpower>*$436517M1/100}."),
    ("key-13", "variantKey", "Stacks up to 5. Lasts 2 min, then 3 sec.",
     "Stacks up to $m2. Lasts $d, then 3 sec."),
    ("key-14", "variantKey", "Restores 61 health over 18 sec.  Must remain seated.",
     "Restores 61 health over 18 sec.  Must remain seated."),
    # an item's trigger line without its trigger word, against the spell description it prints: the shape key
    # Data/SpellShapes.lua is written with (core/spell_shapes.py)
    ("key-15", "variantKey", "Restores 3 mana per 5 sec.", "Restores $s1 mana per 5 sec."),
    ("key-16", "variantKey", "Stuns target Worgen for 4 sec.", "Stuns target Worgen for $d."),
    ("key-17", "variantKey", "Increases healing done by spells and effects by up to 22.",
     "Increases healing done by spells and effects by up to $s1."),
    # values: the live line read strictly; valuesLoose: with the glued and signed shapes
    ("values-01", "values", "Deals 1,200 damage over 18.5 sec. to 3 targets", None),
    ("values-02", "values", "Causes 14 to 22 Fire damage with the Mk2.", None),
    ("values-03", "values", "Deal 294 Physical damage and stun for1.5 sec. Trolls take 2 times as much.",
     None),
    ("values-04", "values", "Consuming a brand deals -24 to -21 Shadow damage.", None),
    ("loose-01", "valuesLoose",
     "Deal 294 Physical damage and stun for1.5 sec. Trolls take 2 times as much damage and stun duration.",
     None),
    ("loose-02", "valuesLoose",
     "Unleash stored chronomantic energy to instantly heal a friendly target for 79to 118.", None),
    ("loose-03", "valuesLoose",
     "Inflicts140 Nature damage per 2 sec. Deaks 2 times as much damage to Trolls.", None),
    ("loose-04", "valuesLoose",
     "Blasts a target for 19 to 37 Nature damage. Mechanical targets take 2x damage.", None),
    ("loose-05", "valuesLoose",
     "A malfunction has occurred. Every 2s arcane energy is released dealing damage to players in a nearby "
     "area.", None),
    ("loose-06", "valuesLoose", "Consuming a brand deals -24 to -21 Shadow damage.", None),
    ("loose-07", "valuesLoose", "Mk2 and Mace2H and 247x128 and G00 DV-1B3 and NG-5 and 30sec and AQ40",
     None),
    ("loose-08", "valuesLoose", "Heals for 5 to -3, then 10-20, then -4 to 9 and x2.", None),
    ("loose-09", "valuesLoose", "Deals 1,200 damage over 18.5 sec. to 3 targets", None),
    # wordedSlots: the Japanese ready for a worded duration in $D1
    ("worded-01", "wordedSlots", "攻撃者に$N1のNatureダメージを与えます。$D1持続します。", None),
    ("worded-02", "wordedSlots", "敵を焼いてArcaneダメージを与え、さらに$D1かけて追加のダメージを与えます。",
     None),
    ("worded-03", "wordedSlots", "$D1の間、近くの敵すべてを攻撃し、$D2ごとに$N2を与えます。", None),
    ("worded-04", "wordedSlots", "$D1ごとにArcaneダメージを受けています。", None),
    ("worded-05", "wordedSlots", "$D1後に$N1のShadowダメージを与えます。", None),
    ("worded-06", "wordedSlots", "$D2ごとに$N1、$D1にわたって回復します。", None),
    # grantedHead: text = the Japanese, scope = the live line
    ("grant-01", "grantedHead", "Wyvern Strikeのアビリティを得ます：\n\n$I1\n$N1のダメージを与えます。",
     "Gain the Wyvern Strike ability:\r\n\r\n|T135125:24|t\r\n"),
    ("grant-02", "grantedHead", "胸部にBurnoutのルーンを刻みます：\n\n$I1\nクリティカル率が$N1%上昇します。",
     "Engrave your chest with the Burnout rune:\r\n\r\n|T236207:24|t\r\n"),
    ("grant-03", "grantedHead", "Wyvern Strikeのアビリティを得ます：\n\n$I1\n$N1のダメージを与えます。",
     "Gain the Wyvern Strike ability:\r\n\r\n|T135125:24|t\r\nDeals 40 damage."),
    ("grant-04", "grantedHead", "$I1 Quick Draw：$N1のダメージ。", "|T1:24|t"),
    ("grant-05", "grantedHead", "$N1個のアビリティを得ます：\n\n$I1\n本文。",
     "Gain 2 abilities:\r\n\r\n|T1:24|t"),
    ("grant-06", "grantedHead", "アビリティを得ます：\n\n$I1\n本文。",
     "Gain the ability:\r\n\r\n|T1:24|t |T2:24|t"),
    # a heading with values of its own (spells 401417 and 412510): its slots come first in the line
    ("grant-07", "grantedHead", TEMPORAL_JA, TEMPORAL_LIVE),
    ("grant-08", "grantedHead", PARTY_JA, PARTY_LIVE),
    ("grant-09", "grantedHead", "$N1個を得ます：\n\n$I2\n本文。\n\n$I1\n本文。", "Gain 2:\r\n\r\n|T1:24|t"),
    # grantedCount: the count of the heading's value slots ("" for no heading or no slot)
    ("grant-count-01", "grantedCount", TEMPORAL_JA, TEMPORAL_LIVE),
    ("grant-count-02", "grantedCount", PARTY_JA, PARTY_LIVE),
    ("grant-count-03", "grantedCount", WYVERN_JA, "Gain the Wyvern Strike ability:\r\n\r\n|T135125:24|t\r\n"),
    ("grant-count-04", "grantedCount", "$N1と$N1の$D1を得ます：\n\n$I1\n本文。",
     "Gain 2 for 2 sec:\r\n\r\n|T1:24|t"),
    ("grant-count-05", "grantedCount", TEMPORAL_JA, TEMPORAL_LIVE + "Records the target's location."),
    # a number the Japanese writes as a literal ("さらに1%") still counts: the heading prints three values
    ("grant-count-06", "grantedCount", "$N1%減り、さらに1%、$N3ごとに減ります。\n\n$I1\n本文。",
     "Takes 30% less, an additional 1% for every 12.\r\n\r\n|T132362:24|t\r\n"),
]


def build() -> list[dict]:
    al = set(AL)
    rows = []
    for id_, op, text, scope in CASES:
        if op == "names":
            expected: object = align.latin_names(text, al)
        elif op == "checkNames":
            expected = align.check_names(text, scope or "", al)[1]
        elif op == "numbers":
            expected = sorted(align.numbers(text).elements(), key=lambda s: (len(s), s))
        elif op == "numberWords":
            expected = align.english_number_words(text)
        elif op == "variantKey":
            expected = align.variant_key(scope or "")
        elif op in ("values", "valuesLoose"):
            expected = align.live_values(text, loose=op == "valuesLoose")
        elif op == "wordedSlots":
            expected = align.worded_slots(text, {1}) or ""
        elif op == "grantedHead":
            expected = align.granted_head(text, scope or "") or ""
        elif op == "grantedCount":
            head = align.granted_head(text, scope or "")
            count = align.granted_count(head) if head else None
            expected = str(count) if count else ""
        else:
            raise ValueError(op)
        row = {"id": id_, "op": op, "text": text, "scope": scope, "allowlist": AL, "expected": expected}
        rows.append(row)
    return rows


def to_lua(rows: list[dict]) -> str:
    lines = [
        "-- GENERATED by pipeline/wfj/dev/gen_align_vectors.py from align_vectors.jsonl. Do not edit.",
        "return { cases = {",
    ]
    al = ", ".join(lua_string(a) for a in AL)
    for r in rows:
        scope = lua_string(r["scope"]) if r["scope"] is not None else "nil"
        # a key is one string; every other op expects a list
        if isinstance(r["expected"], str):
            exp = lua_string(r["expected"])
        else:
            exp = "{ " + ", ".join(lua_string(e) for e in r["expected"]) + " }"
        lines.append(
            f"  {{ id = {lua_string(r['id'])}, op = {lua_string(r['op'])}, text = {lua_string(r['text'])}, "
            f"scope = {scope}, allowlist = {{ {al} }}, expected = {exp} }},"
        )
    lines.append("} }")
    return "\n".join(lines) + "\n"


def write(out_dir: Path) -> None:
    rows = build()
    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "align_vectors.jsonl").open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    (out_dir / "align_vectors.lua").write_text(to_lua(rows), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    out = Path(args[0]) if args else Path(__file__).resolve().parents[3] / "vectors"
    write(out)
    print(f"wrote {out / 'align_vectors.jsonl'} + .lua ({len(CASES)} cases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
