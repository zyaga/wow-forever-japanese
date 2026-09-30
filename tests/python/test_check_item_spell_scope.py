"""Item / spell tooltip lines are checked against their own tooltip English once it exists. The move
from the name baseline changes no status; after it, changed tooltip English marks the line stale (it still ships
and is still gated in-game, ADR-007). And what the new hash means for the collector."""

from wfj.cmd.check import build_scopes, check_type
from wfj.core.hashing import key
from wfj.core.model import english_line, entry, provenance
from wfj.core.normalize import normalize_v1
from wfj.io.jsonl_store import Store

WAGO = "wago@1.15.9.69722"
PROV = provenance("human", "ctjt@84db736", "2026-09-13", translator="WoWJapanizer")
NAME = "Tough Jerky"
TEMPLATE = "Restores $o1 health over $d.  Must remain seated while eating."
JA = "18秒間でhealthを61回復。回復中は\n座っている必要があります。"


def _en(id_, field, en):
    return english_line(id_, field, en, key(normalize_v1(en)), WAGO)


def _check(tmp_path, english_lines, prior_hash):
    store = Store(tmp_path, english=True)
    store.save("item", english_lines)
    line = entry(117, "description", JA, prov=PROV)
    line["status"], line["english"] = "unaligned", {"hash": prior_hash, "src": WAGO}
    return check_type([line], build_scopes(store, "item"), set())[0]


def test_baseline_moves_from_the_name_to_the_tooltip_text_without_a_status_change(tmp_path):
    name_hash = key(normalize_v1(NAME))
    out = _check(tmp_path, [_en(117, "name", NAME), _en(117, "description", TEMPLATE)], name_hash)
    assert out["status"] == "unaligned" and out["reasons"] == []
    assert out["english"] == {"hash": key(normalize_v1(TEMPLATE)), "src": WAGO}


def test_without_tooltip_english_the_name_stays_the_scope(tmp_path):
    name_hash = key(normalize_v1(NAME))
    out = _check(tmp_path, [_en(117, "name", NAME)], name_hash)
    assert out["status"] == "unaligned" and out["english"] == {"hash": name_hash, "src": WAGO, "of": "name"}


def test_a_changed_tooltip_text_marks_the_line_stale_and_it_stays_stale(tmp_path):
    old = key(normalize_v1("Restores $o1 health over $d."))
    out = _check(tmp_path, [_en(117, "name", NAME), _en(117, "description", TEMPLATE)], old)
    assert out["status"] == "stale" and out["reasons"] == []
    assert out["english"] == {"hash": old, "src": WAGO}  # sticky: the hash it was translated against
    store = Store(tmp_path, english=True)
    again = check_type([out], build_scopes(store, "item"), set())[0]
    assert again["status"] == "stale" and again["english"]["hash"] == old


def test_a_rename_never_makes_a_name_baselined_line_stale(tmp_path):
    """Names are never in the Japanese: a baseline taken from the name moves with it, and moves to the
    tooltip text when that arrives, whatever the name did meanwhile."""
    old_name = {"hash": key(normalize_v1(NAME)), "src": WAGO, "of": "name"}
    store = Store(tmp_path, english=True)
    store.save("item", [_en(117, "name", "Tougher Jerky")])
    line = entry(117, "description", JA, prov=PROV)
    line["status"], line["english"] = "unaligned", old_name
    out = check_type([line], build_scopes(store, "item"), set())[0]
    assert out["status"] == "unaligned" and out["english"]["hash"] == key(normalize_v1("Tougher Jerky"))
    # renamed AND tooltip English arriving in the same build
    store.save("item", [_en(117, "name", "Tougher Jerky"), _en(117, "description", TEMPLATE)])
    line["english"] = old_name
    out = check_type([line], build_scopes(store, "item"), set())[0]
    assert out["status"] == "unaligned" and out["english"] == {"hash": key(normalize_v1(TEMPLATE)), "src": WAGO}


def test_a_rejected_line_stays_rejected_whatever_its_english(tmp_path):
    store = Store(tmp_path, english=True)
    store.save("item", [_en(117, "name", NAME), _en(117, "description", TEMPLATE)])
    line = entry(117, "description", "English text, not Japanese", prov=PROV)
    line["english"] = {"hash": "0" * 16, "src": WAGO}
    out = check_type([line], build_scopes(store, "item"), set())[0]
    assert out["status"] == "rejected"


def test_collector_known_check_matches_only_a_template_without_variables(vectors):
    """The addon's collector skips a rendered line whose h1 equals the shipped h1; the Lua and Python hashes
    agree on the shared vectors (test_vectors). With tooltip English as the baseline, a description with no `$`
    variable hashes like its rendered line (not recorded again); a template with variables does not."""
    from wfj.emit.lua_writer import h1_literal

    # the shipped h1 is the first 32 bits of the key the Lua side recomputes on the same vectors (test_vectors)
    assert vectors and all(h1_literal(r["key"]) == f"0x{r['h1']:08x}" for r in vectors)
    plain_template = "Teleports the caster to Stormwind."
    rendered_plain = "Teleports the caster to Stormwind."  # what the tooltip prints: no value to fill
    assert h1_literal(key(normalize_v1(plain_template))) == h1_literal(key(normalize_v1(rendered_plain)))
    rendered = "Restores 61 health over 18 sec.  Must remain seated while eating."
    assert h1_literal(key(normalize_v1(TEMPLATE))) != h1_literal(key(normalize_v1(rendered)))


def test_area_english_is_its_own_scope_and_never_joins_the_quest_scope(tmp_path):
    """Area text is its own type keyed by the quest id, checked in its
    own scope; the quest scope (names, numbers, the joined hash) never sees it, and quest `area` is no field."""
    from wfj.core.model import ENGLISH_FIELDS, validate_line

    store = Store(tmp_path, english=True)
    title, area = "Stonetalon Standstill", "Scout the gazebo"
    store.save("quest", [english_line(25, "title", title, key(normalize_v1(title)), WAGO)])
    store.save("area", [english_line(25, "text", area, key(normalize_v1(area)), "wdb@1.15.9.69722")])
    assert set(build_scopes(store, "quest")[25].fields) == {"title"}
    scope = build_scopes(store, "area")[25]
    assert scope.kind == "area" and scope.fields == {"text": area} and scope.hashes == {"text": key(normalize_v1(area))}
    assert "area" not in ENGLISH_FIELDS["quest"]
    bad = english_line(25, "area", area, key(normalize_v1(area)), "wdb@1.15.9.69722")
    assert any("not in" in p for p in validate_line("quest", bad, english=True))


MACHINE = {"class": "machine", "model": "m", "source": "draft-tooltip-x-sg9@2026-09-19", "imported": "2026-09-19"}
REDRAFT = "$D1かけてhealthを$N1回復します。食事中は座っている必要があります。"
REJECT = {"ruling": "reject", "by": "maintainer", "date": "2026-09-19", "note": "baked number"}


def test_a_machine_redraft_taking_over_a_stale_line_keeps_the_stale_baseline(tmp_path):
    """Known limit (ADR-003): the baseline is the line's, and a machine variant records no English hash, so
    `check` cannot tell a draft cut from the current English from an older one. A redraft that takes over a stale
    line therefore stays stale, with the old baseline, until the draft's English is recorded."""
    old = key(normalize_v1("Restores $o1 health over $d."))
    store = Store(tmp_path, english=True)
    store.save("item", [_en(117, "name", NAME), _en(117, "description", TEMPLATE)])
    line = entry(117, "description", JA, prov=PROV)
    line["ruling"] = dict(REJECT)
    line["conflicts"] = [{"ja": REDRAFT, "provenance": MACHINE}]
    line["status"], line["english"] = "stale", {"hash": old, "src": WAGO}
    out = check_type([line], build_scopes(store, "item"), set())[0]
    assert out["ja"] == REDRAFT and out["provenance"]["class"] == "machine"
    assert out["status"] == "stale" and out["english"]["hash"] == old


def test_a_machine_line_that_already_won_still_goes_stale_when_its_english_changes(tmp_path):
    """A machine line whose English changed after it was drafted is stale like any other (ADR-003)."""
    old = key(normalize_v1("Restores $o1 health over $d."))
    store = Store(tmp_path, english=True)
    store.save("item", [_en(117, "name", NAME), _en(117, "description", TEMPLATE)])
    line = entry(117, "description", REDRAFT, prov=MACHINE)
    line["status"], line["english"] = "unaligned", {"hash": old, "src": WAGO}
    out = check_type([line], build_scopes(store, "item"), set())[0]
    assert out["status"] == "stale" and out["english"]["hash"] == old


def test_a_hand_written_variant_taking_over_keeps_the_stale_baseline(tmp_path):
    """A hand-written variant taking over inherits the line's baseline too."""
    old = key(normalize_v1("Restores $o1 health over $d."))
    store = Store(tmp_path, english=True)
    store.save("item", [_en(117, "name", NAME), _en(117, "description", TEMPLATE)])
    line = entry(117, "description", REDRAFT, prov=MACHINE)
    line["conflicts"] = [{"ja": "$D1かけてhealthを$N1回復。", "provenance": provenance(
        "correction", "corrections@x", "2026-09-19", translator="a reviewer")}]
    line["status"], line["english"] = "stale", {"hash": old, "src": WAGO}
    out = check_type([line], build_scopes(store, "item"), set())[0]
    assert out["provenance"]["class"] == "correction"
    assert out["status"] == "stale" and out["english"]["hash"] == old


def test_a_change_to_an_included_spell_marks_the_line_stale(tmp_path):
    """The line a player reads splices spell 434's text in, so the baseline records that spell's
    hash (`english.includes`), and a change to it makes the line stale like a change to its own English."""
    from wfj.cmd.check import Included

    en = "$@spelldesc434 Well fed."
    store = Store(tmp_path, english=True)
    store.save("item", [_en(117, "description", en)])
    store.save("spell", [_en(434, "description", TEMPLATE)])
    line = entry(117, "description", JA, prov=PROV)
    line["status"], line["english"] = "unaligned", {"hash": key(normalize_v1(en)), "src": WAGO}
    out = check_type([line], build_scopes(store, "item"), set(), Included(store))[0]
    assert out["status"] == "unaligned"  # recorded, not yet a change
    assert out["english"]["includes"] == {"434.description": key(normalize_v1(TEMPLATE))}
    again = check_type([out], build_scopes(store, "item"), set(), Included(store))[0]
    assert again["status"] == "unaligned" and again["english"] == out["english"]
    store.save("spell", [_en(434, "description", "Restores $o1 health over $d.")])
    changed = check_type([out], build_scopes(store, "item"), set(), Included(store))[0]
    assert changed["status"] == "stale" and changed["english"] == out["english"]  # sticky
    # a template that includes nothing records no `includes`
    store.save("item", [_en(117, "description", TEMPLATE)])
    plain = check_type([line | {"english": None}], build_scopes(store, "item"), set(), Included(store))[0]
    assert plain["status"] == "unaligned" and "includes" not in plain["english"]
