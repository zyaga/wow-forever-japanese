"""Reading and validating a collector dump (io/collector_dump.py) + parse_assignments."""

import pytest

from wfj.core.hashing import key
from wfj.core.normalize import normalize_v1
from wfj.io.collector_dump import REASONS, read_dump
from wfj.io.lua_reader import Table, parse_assignments


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def entry(t, i, f, e, *, h=None, b=1, k=None, n=None, p=None) -> str:
    h = key(normalize_v1(e)) if h is None else h
    k = k or f"{t}:{i}:{f}"
    i_lua = lua_str(i) if isinstance(i, str) else i
    n_lua = "" if n is None else ' ["n"] = { ' + ", ".join(str(x) for x in n) + " },"
    n_lua += "" if p is None else f' ["p"] = {lua_str(p)},'
    return (
        f'[{lua_str(k)}] = {{ ["t"] = {lua_str(t)}, ["i"] = {i_lua}, ["f"] = {lua_str(f)}, '
        f'["h"] = {lua_str(h)}, ["e"] = {lua_str(e)}, ["b"] = {b},{n_lua} }},'
    )


def gossip(e, *, n=None, **kw) -> str:
    """A gossip entry: keyed by the text's gossip key."""
    g = key(normalize_v1(e))
    return entry("gossip", kw.pop("i", g), "text", e, n=n, **kw)


def dump(*entries: str, version: int = 1, builds: str = '"1.15.9.69722", -- [1]\n') -> str:
    return (
        'WFJ_DB = {\n["schema"] = 1,\n}\n'
        f"WFJ_Collector = {{\n[\"version\"] = {version},\n[\"builds\"] = {{\n{builds}}},\n"
        f'["entries"] = {{\n{chr(10).join(entries)}\n}},\n}}\n'
    )


def test_parse_assignments_reads_every_statement_and_nil():
    got = parse_assignments('A = {\n["x"] = 1,\n}\nB = nil\nC = "s"\n')
    assert isinstance(got["A"], Table) and got["A"].get("x") == 1
    assert got["B"] is None and got["C"] == "s"


def test_both_newline_escapes_parse():
    a = parse_assignments('X = "one\\ntwo"\n')["X"]
    b = parse_assignments('X = "one\\\ntwo"\n')["X"]
    assert a == b == "one\ntwo"


def test_valid_entries_map_npc_to_unit_and_carry_the_build():
    d = read_dump(
        dump(
            entry("quest", 2, "completion", "$N, well done.$B$BGo."),
            entry("npc", 3100, "name", "Senani Thunderheart"),
        )
    )
    assert d.version == 1 and not d.rejected
    by = {(en.type_, en.id_, en.field): en for en in d.entries}
    assert by[("quest", 2, "completion")].en == "$N, well done.$B$BGo."
    assert by[("unit", 3100, "name")].build == "1.15.9.69722"


def test_keyed_builds_array_is_accepted():
    d = read_dump(dump(entry("quest", 1, "title", "T"), builds='[1] = "1.15.9.69722",\n'))
    assert d.entries[0].build == "1.15.9.69722"


@pytest.mark.parametrize(
    ("line", "reason"),
    [
        (entry("quest", 2, "title", "T", k="quest:3:title"), "bad_key"),
        (entry("gossip", 2, "text", "T"), "bad_key"),  # a gossip id is its 16-hex key
        (gossip("Hello there.", i="0000000000000000", k="gossip:0000000000000000:text"), "bad_key"),
        (entry("gossip", key(normalize_v1("T")), "name", "T"), "bad_field"),
        (gossip("Hello there.", n=[0]), "bad_id"),
        (gossip("Hello there.", n=[2**31]), "bad_id"),
        (gossip("Hello there.", n=list(range(1, 34))), "bad_id"),  # over the addon's NPC_CAP
        (entry("quest", 2, "title", "T", n=[5]), "bad_id"),
        (entry("spook", 2, "text", "T"), "bad_kind"),
        (entry("quest", 2, "name", "T"), "bad_field"),
        (entry("quest", 0, "title", "T"), "bad_id"),
        (entry("quest", 2, "title", "こんにちは"), "not_english"),
        (entry("quest", 2, "title", "使用: 攻撃力"), "not_english"),
        (entry("quest", 2, "title", "Hi {name}"), "unknown_placeholder"),
        (entry("quest", 2, "title", "Hi $Gsir:madam;"), "unknown_placeholder"),
        (entry("quest", 2, "title", "T", h="0000000000000000"), "hash_mismatch"),
        (entry("quest", 2, "title", "T", b=2), "no_build"),
        (entry("quest", 2, "title", "$B$B"), "not_english"),
        (entry("quest", 2, "title", "Say 「hi」"), "not_english"),
    ],
)
def test_each_rejection_reason_is_counted(line, reason):
    d = read_dump(dump(line, entry("quest", 5, "title", "Good")))
    assert d.rejected == {reason: 1}
    assert [en.id_ for en in d.entries] == [5]
    assert reason in REASONS


def test_wrong_version_or_no_dump_raise():
    with pytest.raises(ValueError, match="version"):
        read_dump(dump(entry("quest", 1, "title", "T"), version=2))
    with pytest.raises(ValueError, match="no WFJ_Collector"):
        read_dump("WFJ_DB = {\n}\nWFJ_Collector = nil\n")


def test_bad_build_string_and_duplicate_keys_are_rejected():
    d = read_dump(dump(entry("quest", 1, "title", "T"), builds='"1.15 9", -- [1]\n'))
    assert d.rejected == {"no_build": 1} and not d.entries
    twice = dump(entry("quest", 5, "title", "First"), entry("quest", 5, "title", "Second"), entry("quest", 6, "title", "X"))
    d = read_dump(twice)
    assert d.rejected == {"duplicate_key": 2}
    assert [en.id_ for en in d.entries] == [6]


def test_gossip_entries_carry_their_key_and_npc_ids():
    """A gossip entry maps to the gossip English store with its sorted, unique creature ids."""
    d = read_dump(dump(gossip("Goodbye.", n=[6740, 1423, 6740]), gossip("Well met, $N.")))
    assert not d.rejected
    by = {en.en: en for en in d.entries}
    g = by["Goodbye."]
    assert (g.type_, g.field, g.id_, g.hash_) == ("gossip", "text", key(normalize_v1("Goodbye.")), g.id_)
    assert g.npcs == (1423, 6740)
    assert by["Well met, $N."].npcs == ()


def test_a_spell_aura_entry_is_read_as_the_spell_aura_field():
    """The buff / debuff tooltip line is recorded as spell / aura and read into the spell store."""
    d = read_dump(dump(entry("spell", 774, "aura", "Heals 12 damage every 3 seconds.")))
    (e,) = d.entries
    assert (e.type_, e.id_, e.field) == ("spell", 774, "aura")
    assert not d.rejected
