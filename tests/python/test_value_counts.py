"""An item or spell line filled from the live tooltip ships how many numbers its English prints, so the addon
can leave the tooltip English when the client's line has gained or lost one."""

import re

from wfj.cmd import generate
from wfj.core import align
from wfj.emit import lua_writer, schema
from wfj.io.jsonl_store import Store
from wfj.paths import data_root

SRC = "db2@1.60.1.70009"
H = "0123456789abcdef"
# the template gained a number in front: the chance
OLD_EN = "You have a chance to reduce the cost of your next spell by $m1%. Stacks up to $s3 times. Lasts $d."
NEW_EN = ("You have a ${$s2*100}% chance to reduce the cost of your next spell by $m1%. "
          "Stacks up to $s3 times. Lasts $d.")
OLD_JA = "一定の確率で次の呪文のコストを$N1%軽減します。最大$N2回まで重なります。効果時間は$D1です。"
NEW_JA = "$N1%の確率で次の呪文のコストを$N2%軽減します。最大$N3回まで重なります。効果時間は$D1です。"


def _line(id_, ja, status="unaligned", field="description"):
    return {"id": id_, "field": field, "ja": ja, "status": status, "checks": [], "reasons": [],
            "conflicts": [], "english": {"hash": H, "src": SRC},
            "provenance": {"class": "machine", "model": "m", "source": "draft-s01", "imported": "2026-09-27"}}


def _english(tmp_path, rows):
    data = tmp_path / "data"
    Store(data, english=True).save("spell", [
        {"id": i, "field": f, "en": en, "hash": H, "src": SRC} for (i, f), en in rows.items()])
    return Store(data, english=True)


def test_a_filled_line_ships_the_count_of_its_english(tmp_path):
    store = _english(tmp_path, {
        (1, "description"): NEW_EN, (2, "description"): "Restores $s1 health.",
        (2, "aura"): "Restoring $s1 health every $t1 sec.", (3, "description"): "Opens the way.",
        (5, "description"): "Deals $s1 damage and $@spelldesc6", (6, "description"): "heals for $s1 over $d.",
    })
    lines = [
        _line(1, NEW_JA), _line(2, "体力を$N1回復します。"), _line(2, "$N2秒ごとに体力を$N1回復。", field="aura"),
        _line(3, "道を開きます。"),            # nothing filled in: held to an English with no number
        _line(4, "体力を$N1回復します。"),       # no English in the store: no count
        _line(5, "$N1のダメージを与え、$D1かけて$N2回復します。"),  # another spell's text is counted in
    ]
    got = generate.value_counts("spell", lines, store)
    assert got == {(1, "description"): 4, (2, "description"): 1, (2, "aura"): 2, (3, "description"): 0,
                   (5, "description"): 3}
    rows = lua_writer.rows("spell", lines, values=got)
    assert rows[1][-2:] == ['"um"', "4"]                 # the aura has none: left off
    assert rows[2][-3:] == ['"uu"', "1", "2"]
    assert rows[3][-2:] == ['"um"', "0"]  # a client line that gained a number no longer passes
    assert rows[4][-1] == '"um"'  # no count: the row is as it always was
    assert rows[4] == lua_writer.rows("spell", lines)[4]


def test_a_count_for_the_second_field_only_keeps_its_place(tmp_path):
    store = _english(tmp_path, {(2, "description"): "Opens the way.", (2, "aura"): "Heals $s1."})
    lines = [_line(2, "道を開きます。"), _line(2, "$N1回復。", field="aura")]
    rows = lua_writer.rows("spell", lines, values=generate.value_counts("spell", lines, store))
    assert rows[2][-3:] == ['"uu"', "0", "1"]


def test_a_stale_line_numbered_for_other_english_never_fits(tmp_path):
    """The English changed and the Japanese is still the old one: its second placeholder would now take the
    first value's neighbour. It ships a count no line has until it is drafted again."""
    store = _english(tmp_path, {(1, "description"): NEW_EN, (2, "description"): NEW_EN})
    lines = [_line(1, OLD_JA, "stale"), _line(2, NEW_JA, "stale")]
    got = generate.value_counts("spell", lines, store)
    assert got == {(1, "description"): generate.NEVER_FITS, (2, "description"): 4}
    assert generate.NEVER_FITS < 0
    # the same Japanese against the English it was written for fits
    old = _english(tmp_path / "old", {(1, "description"): OLD_EN})
    assert generate.value_counts("spell", [_line(1, OLD_JA, "stale")], old) == {(1, "description"): 3}


def test_a_branch_line_and_an_uncountable_template_get_no_count(tmp_path):
    store = _english(tmp_path, {
        (1, "description"): "Deals $s1$?s2[ and $s3][]. Lasts $d.",
        (2, "description"): "$?a1[Deals $s1 damage.][Heals $s1 and $s2.]",
    })
    lines = [_line(1, "$N1$?s2[と$N2][]。$D1。"), _line(2, "$N1のダメージ。")]
    assert align.value_slots("$?a1[Deals $s1 damage.][Heals $s1 and $s2.]") is None
    assert generate.value_counts("spell", lines, store) == {}


def test_only_items_and_spells_carry_a_count_and_the_addon_twin_agrees():
    assert {t for t, s in schema.SLOTS.items() if "values" in s} == {"item", "spell"}
    const = (data_root().parent / "addon/WoWForeverJapanese/Core/Const.lua").read_text(encoding="utf-8")
    for t in ("item", "spell"):
        s = schema.SLOTS[t]
        assert s["values"] == s["status"] == 2 * len(s["fields"]) + 1
        m = re.search(rf"^  {t} = \{{ fields = .*, status = (\d+), values = (\d+) \}},$", const, re.M)
        assert m and int(m.group(1)) == s["status"] and int(m.group(2)) == s["values"], t


def test_no_shipped_line_is_numbered_past_its_english():
    """Over the real data: a line that is not stale never asks for a value its English does not print, and
    every count is the one `align` reads off the template."""
    root = data_root()
    english = Store(root, english=True)
    for type_ in ("item", "spell"):
        lines = Store(root).load(type_)
        counts = generate.value_counts(type_, lines, english)
        assert counts, type_
        by = {(ln["id"], ln["field"]): ln for ln in lines}
        past = [k for k, n in counts.items()
                if by[k]["status"] != "stale" and max(align.fill_indices(by[k]["ja"]), default=0) > n]
        assert past == [], f"{type_}: {past[:5]}"
        # a gated line with no placeholder may be held to an English that prints no number
        assert all(n == generate.NEVER_FITS or n >= 0 for n in counts.values())
