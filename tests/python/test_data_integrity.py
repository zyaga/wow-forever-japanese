"""Facts about the committed `data/` after the lineage import (mirrors the real-shard tests). Numbers are
floors from a past run; a data PR that moves them must update this file knowingly."""


import re

import pytest

from wfj.core import decisions, paragraphs, readings
from wfj.io.jsonl_store import Store


def _quest_lines(root):
    return Store(root / "data").load("quest")


def _by(lines):
    return {(ln["id"], ln["field"]): ln for ln in lines}


def test_no_craftjapanizer_translator_remains(root):
    lines = _quest_lines(root)
    assert lines
    assert all(ln["provenance"].get("translator") != "CraftJapanizer" for ln in lines)
    for ln in lines:
        for c in ln["conflicts"]:
            assert c["provenance"].get("translator") != "CraftJapanizer"


def test_lineage_sources_present_and_only_human(root):
    lines = _quest_lines(root)
    srcs = {ln["provenance"]["source"].split("@")[0] for ln in lines}
    assert {"cqjt", "qjp", "cjq"} <= srcs
    # imported lines are human; a hand correction and a model draft (`draft-<name>-sg<N>@<date>` with its model)
    # are the only other classes
    variants = [v for ln in lines for v in [ln, *ln["conflicts"]]]
    classes = {v["provenance"]["class"] for v in variants}
    assert classes <= {"human", "correction", "machine"} and "human" in classes
    draft = re.compile(r"^draft-[a-z0-9-]+-sg\d+@\d{4}-\d{2}-\d{2}$")
    for v in variants:
        if v["provenance"]["class"] == "machine":
            assert draft.match(v["provenance"]["source"]) and v["provenance"].get("model"), v["provenance"]
    assert not any(ln["provenance"].get("translator") == "unknown" for ln in lines if ln["provenance"]["source"].startswith(("qjp", "cjq")))


# the one seed gossip line, drafted before the style guide existed (ADR-017); every later gossip draft is styled
PRE_STYLE_GOSSIP_SOURCES = {"draft-gossip-shadowglen"}


def test_every_gossip_machine_draft_names_its_style_version(root):
    """ADR-023: a gossip draft's source is `draft-<name>-sg<N>@<date>`, as for quest progress / completion."""
    draft = re.compile(r"^draft-[a-z0-9-]+-sg\d+@\d{4}-\d{2}-\d{2}$")
    lines = Store(root / "data").load("gossip")
    machine = [v["provenance"] for ln in lines for v in [ln, *ln["conflicts"]] if v["provenance"]["class"] == "machine"]
    assert len(machine) >= 4400  # 4,456 machine gossip variants when this floor was set
    for p in machine:
        if p["source"].split("@", 1)[0] in PRE_STYLE_GOSSIP_SOURCES:
            continue
        assert draft.match(p["source"]) and p.get("model"), p


# the screen test lines, drafted before the style guide covered books (ADR-022)
PRE_STYLE_BOOK_SOURCES = {"draft-books-screens"}


@pytest.mark.parametrize("type_", ["book"])
def test_every_book_machine_draft_names_its_style_version(root, type_):
    """A book draft's source is `draft-<name>-sg<N>@<date>` with a model."""
    draft = re.compile(r"^draft-[a-z0-9-]+-sg\d+@\d{4}-\d{2}-\d{2}$")
    lines = Store(root / "data").load(type_)
    machine = [v["provenance"] for ln in lines for v in [ln, *ln["conflicts"]] if v["provenance"]["class"] == "machine"]
    assert machine
    for p in machine:
        if p["source"].split("@", 1)[0] in PRE_STYLE_BOOK_SOURCES:
            continue
        assert draft.match(p["source"]) and p.get("model"), p


def test_truncated_descriptions_are_rejected_not_shipped(root):
    by = _by(_quest_lines(root))
    truncated = [ln for ln in by.values() if any(r.startswith("truncated") for r in ln["reasons"])]
    # every truncated line was drafted whole; its ruled hand-written text stays in `conflicts`
    assert truncated == []
    # quest 1452 ("ヒック!" for a six-paragraph English) had no complete variant in the two files; its truncated
    # hand-written text is ruled `reject` and a whole-line machine draft ships
    l1452 = by[(1452, "description")]
    assert l1452["status"] == "trusted" and l1452["provenance"]["class"] == "machine"
    assert decisions.hand_written_all_rejected(l1452)


def test_complete_lineage_variants_replaced_truncated_ones(root):
    by = _by(_quest_lines(root))
    # a correction of the complete layer keeps that layer's lineage (`corrects` names its source)
    replaced = [
        ln
        for (i, f), ln in by.items()
        if f == "description"
        and ln["status"] in ("trusted", "stale")
        and (ln["provenance"].get("corrects") or ln["provenance"]["source"]).startswith(("qjp", "cjq"))
        and any(c["provenance"].get("translator") == "questjapanizer-wiki" for c in ln["conflicts"])
    ]
    # 473 at first (completeness ranks before source); some have since been redrafted because their Japanese
    # was broken or an audit found them wrong
    assert len(replaced) >= 400
    # quest 26: the QuestJapanizer-2009 row (Tammy) won over the truncated wiki copy
    l26 = by[(26, "description")]
    assert l26["status"] == "trusted" and l26["provenance"]["source"].startswith("qjp@")
    assert l26["provenance"]["translator"] == "Tammy" and "tiebreak" not in l26["checks"]
    assert paragraphs.count(l26["ja"]) >= 2


def test_every_trusted_description_is_complete(root):
    by = _by(_quest_lines(root))
    english = {ln["id"]: ln["en"] for ln in Store(root / "data", english=True).load("quest") if ln["field"] == "description"}
    trusted = [ln for (i, f), ln in by.items() if f == "description" and ln["status"] in ("trusted", "stale") and i in english]
    assert len(trusted) >= 1100  # 1,133 when this floor was set (after the structural rule for the relabelled layer)
    multi = [ln for ln in trusted if paragraphs.count_english(english[ln["id"]]) >= 2]
    assert all("length" in ln["checks"] for ln in multi)
    # the relabelled wiki layer is first-paragraph-only by construction: none of its one-paragraph copies ships
    # against a multi-paragraph English (the structural rule)
    assert not [ln for ln in multi if paragraphs.count(ln["ja"]) == 1 and paragraphs.first_paragraph_only(ln["provenance"])]
    # quest 6: the complete qjp variant outranks the long-but-partial cqjt copy
    l6 = by[(6, "description")]
    assert l6["status"] == "trusted" and l6["provenance"]["source"].startswith("qjp@") and paragraphs.count(l6["ja"]) == 2
    # quest 404: the `翻訳　Forsaken` credit is stripped and becomes the translator
    l404 = by[(404, "description")]
    assert "翻訳" not in l404["ja"] and l404["provenance"]["translator"] == "Forsaken"
    assert sum(1 for ln in trusted if "\n\n" in ln["ja"]) >= 850  # 896 multi-paragraph descriptions when this floor was set


def test_generated_shard_carries_paragraph_breaks(root):
    shard = (root / "addon/WoWForeverJapanese/Data/Quest/Quest_0000.lua").read_text(encoding="utf-8")
    row = next(line for line in shard.splitlines() if line.strip().startswith("[26] ="))
    assert "\\n\\n" in row  # Lua-escaped newlines inside the description slot


# ---- hand corrections -----------------------------------------------------------------------------------------


def _corrections(lines):
    return [(ln, v) for ln in lines for v in [ln, *ln["conflicts"]] if v["provenance"].get("class") == "correction"]


def test_quest_456_ships_its_corrected_complete_translation(root):
    l456 = _by(_quest_lines(root))[(456, "description")]
    prov = l456["provenance"]
    assert l456["status"] == "trusted" and prov["class"] == "correction"
    assert prov["translator"] == "Az" and prov["corrects"] == "qjp@0.5.8" and prov["source"].startswith("correction@")
    assert paragraphs.count(l456["ja"]) == 3 and "Thistle Boar" in l456["ja"] and "Thistle bore" not in l456["ja"]
    shard = (root / "addon/WoWForeverJapanese/Data/Quest/Quest_0000.lua").read_text(encoding="utf-8")
    row = next(line for line in shard.splitlines() if line.strip().startswith("[456] ="))
    assert "Thistle Boar" in row


# A correction that no longer passes the rules against newer English does not ship (the rules decide status).
# Quest 592's completion correction is one paragraph of VMaNGOS's two-paragraph OfferRewardText. Because it
# ships nothing, it is one of the held-back completion lines: it is ruled `reject` and a machine draft covering
# the whole text ships in its place. The correction is kept, with its ruling, and is still checked below for
# shape and attribution.
HELD_BACK_COMPLETION = {(592, "completion")}


def test_every_correction_is_attributed_and_ships(root):
    found = _corrections(_quest_lines(root))
    assert len(found) >= 31  # 31 hand-read name corrections when this floor was set
    for line, v in found:
        p = v["provenance"]
        assert p.get("translator") and p.get("corrects") and p.get("note"), (line["id"], line["field"])
        assert p["source"].startswith("correction@")
        # the correction names the variant it corrects: same source AND translator, so the structural
        # first-paragraph rule judges it by the real layer (a misattributed correction cannot bypass it)
        imported = [c["provenance"] for c in line["conflicts"] if c["provenance"].get("class") != "correction"]
        assert any(q["source"] == p["corrects"] and q.get("translator") == p["translator"] for q in imported), (
            line["id"],
            line["field"],
        )
        # a correction ruled `reject` no longer ships: the line ships its redraft or a newer correction instead
        if decisions.is_rejected(v) and (line["id"], line["field"]) not in HELD_BACK_COMPLETION:
            assert line["status"] in ("trusted", "stale") and line["ja"] != v["ja"], (line["id"], line["field"])
            continue
        if (line["id"], line["field"]) in HELD_BACK_COMPLETION:
            assert decisions.is_rejected(v), (line["id"], line["field"])  # the reject ruling is on it
            assert line["provenance"]["class"] == "machine" and line["status"] == "trusted", (
                line["id"],
                line["field"],
                line["status"],
            )
            continue
        # a correction that passes the rules ranks first, so the line ships it
        assert line["provenance"].get("class") == "correction" and line["status"] in ("trusted", "stale"), (
            line["id"],
            line["field"],
            line["status"],
            line["reasons"],
        )


def test_progress_and_completion_ship_with_their_own_vmangos_hash(root):
    """ADR-019: a shipped progress / completion line whose quest has VMaNGOS English for that
    field records that line's hash and source, and the generated row's completion h1 slot carries its first 32 bits."""
    english = {(ln["id"], ln["field"]): ln for ln in Store(root / "data", english=True).load("quest")}
    shipped = [
        ln for ln in _quest_lines(root)
        if ln["field"] in ("progress", "completion") and ln["status"] in ("trusted", "stale")
    ]
    own = [ln for ln in shipped if (ln["id"], ln["field"]) in english]
    assert len(own) >= 1500
    for ln in own:
        if ln["status"] == "trusted":
            en = english[(ln["id"], ln["field"])]
            assert ln["english"] == {"hash": en["hash"], "src": en["src"]}, (ln["id"], ln["field"])
            # VMaNGOS, or Forever's own turn-in text a client recorded in game (ADR-053) or forever-vo's players
            # recorded (ADR-055)
            assert en["src"].startswith(("vmangos@", "collector@1.60.", "forever-vo@")), (
                ln["id"], ln["field"], en["src"])
    by = _by(_quest_lines(root))
    h = by[(33, "completion")]["english"]["hash"]
    shard = (root / "addon/WoWForeverJapanese/Data/Quest/Quest_0000.lua").read_text(encoding="utf-8")
    row = next(line for line in shard.splitlines() if line.startswith("  [33] = {"))
    assert row.rstrip(",").rsplit(", ", 2)[-2] == f"0x{h[:8]}"  # slot 10: completion h1


def test_server_only_text_keeps_its_translation_floor(root):
    """ADR-023: the committed store keeps quest progress and gossip essentially fully translated and the machine
    completion lines present, the held-back ones included. Counts when the floors were set:
    - quest progress: 2,679 of 2,681 lines with English ship `trusted` (all machine);
    - gossip: 4,446 of 4,532 keys with English ship `trusted` (all machine; 78 bare labels are never drafted);
    - quest completion: 2,096 `machine` / `trusted` lines, 734 of them on held-back lines.
    The served step drops the English of quest ids Forever does not list, so those lines do not count. The floors
    sit a little under the counts so ordinary corrections and re-drafts don't trip them; a data PR that drops
    below one must say why and move the floor knowingly."""
    english = Store(root / "data", english=True)
    data = Store(root / "data")
    quest_en = {(ln["id"], ln["field"]) for ln in english.load("quest")}
    gossip_en = {(ln["id"], ln["field"]) for ln in english.load("gossip")}
    quest = data.load("quest")

    def trusted(lines, keys, field):
        return [
            ln for ln in lines
            if ln["field"] == field and ln["status"] == "trusted" and (ln["id"], ln["field"]) in keys
        ]

    progress = trusted(quest, quest_en, "progress")
    assert len(progress) >= 2650, len(progress)
    assert len(progress) >= len({k for k in quest_en if k[1] == "progress"}) - 20

    gossip = trusted(data.load("gossip"), gossip_en, "text")
    assert len(gossip) >= 4350, len(gossip)
    assert len(gossip) >= len(gossip_en) - 150

    machine = [ln for ln in quest if ln["field"] == "completion" and ln["status"] == "trusted"
               and ln["provenance"]["class"] == "machine"]
    assert len(machine) >= 2050, len(machine)
    ruled = [ln for ln in machine if decisions.hand_written_all_rejected(ln)]
    assert len(ruled) >= 725, len(ruled)


def test_gendered_quest_fields_ship_h1f_and_keyed_aliases_as_measured(root, plan_report):
    """ADR-024: the shipped quest fields whose English has a `$G` code carry the female-variant h1: 145 rows,
    154 fields across them; quest 8234's completion is one of them. 189 shipped gossip lines (NPC speech
    included) and 10 book pages get a gender alias; none is dropped or ambiguous. A data PR that moves these
    counts updates them knowingly."""
    from wfj.cmd import generate
    from wfj.emit import lua_writer

    data = root / "data"
    planned, report = plan_report
    female = generate.female_fields(Store(data, english=True).load("quest"))
    masked = generate.masked_fields(Store(data, english=True).load("quest"))  # as the real build does
    rows = lua_writer.rows("quest", _quest_lines(root), female, masked)
    gendered = [r for r in rows.values() if len(r) == 16]
    assert len(gendered) == 145
    assert sum(1 for r in gendered for v in r[11:] if v != "nil") == 154
    assert rows[8234][-1] == "0xf0af4ecb"  # completion h1f
    # 10 shipped book pages whose English has a `$G` code get an alias too
    assert report["aliases"] == {"gossip": 189, "book": 10}
    assert all(keys == [] for keys in report["dropped"].values())
    assert all(hashes == [] for hashes in report["ambiguous"].values())
    shard = planned["Data/Quest/Quest_0008.lua"]
    row = next(line for line in shard.splitlines() if line.startswith("  [8234] = {"))
    assert row.endswith("nil, nil, nil, nil, 0xf0af4ecb },")


def test_books_keep_their_translation_floor(root):
    """1,195 of 1,257 book pages ship Japanese when this floor was set (trainer greetings are not stored).
    The 62 pages left are 30 bare labels (`Missing Text`), 23 picture-only pages, 6 lint limits and 3 ruled
    pages. A data PR that moves these numbers updates them knowingly."""
    data = Store(root / "data")
    books = [ln for ln in data.load("book") if ln["status"] == "trusted"]
    assert len(books) >= 1190
    assert len(Store(root / "data", english=True).load("book")) - len(books) <= 65
    assert not (root / "data" / "trainer_greeting").exists()
    assert not (root / "data" / "english" / "trainer_greeting").exists()


# the date of the ruling on the audit of the hand-written lines
AUDIT_RULING_DATE = "2026-09-26"


def test_every_rejected_hand_written_line_with_english_is_accounted_for(root):
    """Every line with English and hand-written text that ships nothing was read and corrected, accepted or
    redrafted. What is left stays English by an existing rule (the tooltip audit's rulings). Tiger's Fury
    ("Requires Cat Form" in white or red) ships as branch variants."""
    from wfj.core import decisions

    left = []
    for type_ in ("quest", "item", "spell", "gossip", "book", "ui", "objective", "unit"):
        english = {(e["id"], e["field"]) for e in Store(root / "data", english=True).load(type_)}
        for ln in Store(root / "data").load(type_):
            if ln["status"] == "rejected" and (ln["id"], ln["field"]) in english and decisions.hand_written_variants(ln):
                left.append((type_, ln["id"], ln["field"]))
    # quest titles that are only a name ship that name (8678 "Proudhorn the Elder", 8830 with its siblings)
    # tooltip lines the audit ruled wrong whose English is only a name, or whose template still cannot be
    # drafted, ship the English, each ruled by the audit. Tiger's Fury (5217) ships: its red variant shows
    # Japanese, the white one English.
    audit = left
    assert ("spell", 5217, "description") not in left and 0 < len(audit) <= 40
    for type_, id_, field in audit:
        ln = next(x for x in Store(root / "data").load(type_) if x["id"] == id_ and x["field"] == field)
        assert all(
            v["ruling"]["ruling"] == "reject" and v["ruling"]["date"] == AUDIT_RULING_DATE
            for v in decisions.hand_written_variants(ln)
        )
        assert type_ in ("item", "spell")


# Every shipped quest, gossip and UI line with something to annotate (no `|`, which the reading box refuses) has
# a current reading, and every word in it carries all five items with a meaning (docs/systems/readings.md). A
# batch that adds or changes such a line writes its word list in the same round.
@pytest.mark.parametrize("type_", ["quest", "gossip", "ui"])
def test_meanings_complete(root, type_):
    every = Store(root / "data").load(type_)
    lines = [ln for ln in every if readings.shipped(ln)]
    owed = {
        (ln["id"], ln["field"]) for ln in lines if readings.annotatable(ln["ja"]) and "|" not in ln["ja"]
    }
    japanese = readings.shipped_japanese(every)
    current = {
        (r["id"], r["field"]): r
        for r in readings.check(type_, Store(root / "data" / "reading").load(type_), japanese)["current"]
    }
    missing = sorted(owed - current.keys(), key=str)
    assert not missing, f"{len(missing)} {type_} line(s) have no current reading: {missing[:10]}"
    short = [
        k for k in sorted(owed, key=str) if any(len(w) != 5 or not w[4] for w in current[k]["words"])
    ]
    assert not short, f"{len(short)} {type_} reading(s) hold a word without a meaning: {short[:10]}"


# A word's meaning never carries its line's whole English line (core/meanings.py): the addon ships no English
# line of the game's text.
def test_no_meaning_copies_a_whole_english_line(root):
    from wfj.core import meanings as scan

    hits = []
    for type_ in sorted(readings.TYPES):
        japanese = readings.shipped_japanese(Store(root / "data").load(type_))
        english = {(e["id"], e["field"]): e.get("en", "") for e in Store(root / "data", english=True).load(type_)}
        for rec in readings.check(type_, Store(root / "data" / "reading").load(type_), japanese)["current"]:
            key = (rec["id"], rec["field"])
            en = english.get(key)
            if not en or scan.one_word_label({"type": type_, "ja": japanese[key], "words": rec["words"]}):
                continue
            hits += [(type_, *key, w[0]) for w in rec["words"] if len(w) == 5 and scan.copies(w[4], en)]
    assert not hits, f"{len(hits)} meaning(s) copy a whole English line: {hits[:10]}"


@pytest.mark.parametrize("type_", ["item", "spell"])
def test_no_shipped_tooltip_asks_for_more_slots_than_its_english_prints(root, type_):
    """A `$N<k>` or `$D<k>` past what the template prints can never be filled, so the line falls back to English
    for every player (two placeholders around one range the client prints as `14 to 16`, say). Shipped tooltip
    rows stay within `align.value_slots` / `align.duration_slots` of their current English."""
    from wfj.core import align
    from wfj.core.report import SHIPPED

    english = {(ln["id"], ln["field"]): ln["en"] for ln in Store(root / "data", english=True).load(type_)}
    over = []
    for ln in Store(root / "data").load(type_):
        en = english.get((ln["id"], ln["field"]))
        if ln["status"] not in SHIPPED or en is None:
            continue
        slots, durations = align.value_slots(en), align.duration_slots(en)
        if slots is None:
            continue
        n = max((int(m) for m in re.findall(r"\$N(\d+)", ln["ja"])), default=0)
        d = max((int(m) for m in re.findall(r"\$D(\d+)", ln["ja"])), default=0)
        if n > slots or (durations is not None and d > durations):
            over.append((ln["id"], ln["field"], n, slots, d, durations))
    assert not over, f"{len(over)} shipped {type_} line(s) ask for a slot the English never prints: {over[:10]}"
