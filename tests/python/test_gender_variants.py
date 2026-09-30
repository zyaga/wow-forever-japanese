"""ADR-024: the female variant of a `$G` English, the quest h1f slots and the keyed gender aliases."""

from pathlib import Path

from wfj.cmd import generate
from wfj.core.hashing import key
from wfj.core.model import english_line, entry
from wfj.core.normalize import female_variant, normalize_v1
from wfj.emit import lua_writer, schema
from wfj.io.jsonl_store import Store

PROV = {"class": "machine", "model": "model-x", "source": "draft-t@2026-09-16", "imported": "2026-09-16"}
SRC = "vmangos@13b49dc"
GOSSIP_EN = "May Cenarius watch over you, $g brother : sister;.$B$BI am Tajarri."
QUEST_EN = "I bid you welcome, $Gbrother:sister;. Take this, $gboy:girl;."


def _k(en: str) -> str:
    return key(normalize_v1(en))


# ── the female variant of a $G English ───────────────────────────────────────


def test_female_variant_is_none_without_a_gender_code():
    assert female_variant("Hello, $N. Well met, $C.") is None
    assert female_variant("") is None
    assert female_variant("Price: $5 : none;") is None  # `$5` is not a gender code


def test_female_variant_resolves_every_code_to_its_second_branch():
    assert female_variant(QUEST_EN) == "I bid you welcome, sister. Take this, girl."
    assert female_variant("$Glad:lass; and $ghe:she;") == "lass and she"
    assert female_variant("you, $g brother : sister;.") == "you,  sister."  # branch spaces kept (client trimming unverified: checklist 18)


def test_female_variant_strips_markup_before_splitting_the_code():
    # a link carries a `:`; normalize_v1 strips it before its gender step, so the variant must too
    raw = "Take $G|Hitem:6948|h[Hearthstone]|h:the stone;."
    assert normalize_v1(raw) == "Take [Hearthstone]."
    assert female_variant(raw) == "Take the stone."


def test_female_variant_normalizes_like_the_literal_female_text():
    assert normalize_v1(female_variant(QUEST_EN)) == normalize_v1("I bid you welcome, sister. Take this, girl.")
    literal = "May Cenarius watch over you,  sister.$B$BI am Tajarri."
    assert normalize_v1(female_variant(GOSSIP_EN)) == normalize_v1(literal)
    assert _k(female_variant(GOSSIP_EN)) != _k(GOSSIP_EN)  # the male key keeps the first branch


def test_female_index_maps_the_english_hash_to_the_female_key():
    lines = [
        english_line(3099, "progress", QUEST_EN, _k(QUEST_EN), SRC),
        english_line(1, "title", "No code here", _k("No code here"), SRC),
        english_line(2, "title", "$Ghe:he;", _k("$Ghe:he;"), SRC),  # same text both ways → no variant
    ]
    assert generate.female_index(lines) == ({_k(QUEST_EN): _k(female_variant(QUEST_EN))}, [])


def test_female_index_reports_a_hash_whose_texts_disagree():
    # "$Gsir:madam;" and "$Gsir:lady;" both normalize to "sir" but differ for a female character
    a, b = "Hello, $Gsir:madam;.", "Hello, $Gsir:lady;."
    assert _k(a) == _k(b)
    index, ambiguous = generate.female_index([english_line(_k(a), "text", a, _k(a), SRC),
                                              english_line(_k(b), "text", b, _k(b), SRC)])
    assert index == {} and ambiguous == [_k(a)]


def test_female_fields_are_per_field_so_a_literal_line_sharing_the_hash_gets_none():
    gendered = "$gHello there, handsome.:Oh my!;"
    literal = "Hello there, handsome."
    assert _k(gendered) == _k(literal)  # quests 8897 / 8898
    fields = generate.female_fields([english_line(8897, "progress", gendered, _k(gendered), SRC),
                                     english_line(8898, "progress", literal, _k(literal), SRC)])
    assert fields == {(8897, "progress"): (_k(gendered), _k("Oh my!"))}
    rows = lua_writer.rows("quest", [_quest(8897, "progress", "やあ", _k(gendered)),
                                     _quest(8898, "progress", "やあ", _k(literal))], fields)
    assert len(rows[8897]) == 16 and len(rows[8898]) == 11


# ── the quest h1f slots ──────────────────────────────────────────────────────


def _quest(id_, field, ja, h, of=None):
    line = entry(id_, field, ja, status="trusted", prov=PROV)
    line["english"] = {"hash": h, "src": SRC, **({"of": of} if of else {})}
    return line


def test_quest_row_gains_h1f_slots_only_when_a_field_has_a_female_variant():
    h, plain = _k(QUEST_EN), _k("Kill ten wolves.")
    fem = {(3099, "progress"): (h, _k(female_variant(QUEST_EN)))}
    got = lua_writer.rows("quest", [_quest(3099, "progress", "ようこそ", h), _quest(3099, "title", "狼", plain)], fem)
    row = got[3099]
    assert len(row) == 16
    off = schema.SLOTS["quest"]["female"]
    # Lua slot = field index + off (1-based) → Python index field index + off - 1
    assert row[4 + off - 1] == lua_writer.h1_literal(fem[(3099, "progress")][1])  # progress (field 4) → slot 15
    assert [row[i + off - 1] for i in (1, 2, 3, 5)] == ["nil"] * 4
    assert len(lua_writer.rows("quest", [_quest(7, "title", "狼", plain)], fem)[7]) == 11
    stale = lua_writer.rows("quest", [_quest(3099, "progress", "古い訳", "ab" * 8)], fem)[3099]
    assert len(stale) == 11  # checked against older English: its hash is not the variant's
    without = lua_writer.rows("quest", [_quest(3099, "progress", "ようこそ", h)])[3099]
    assert without == lua_writer.rows("quest", [_quest(3099, "progress", "ようこそ", h)], fem)[3099][:11]


def test_a_field_checked_against_another_fields_english_gets_no_h1f():
    h = _k(QUEST_EN)
    fem = {(33, "completion"): (h, "ab" * 8)}
    row = lua_writer.rows("quest", [_quest(33, "completion", "訳", h, of="description")], fem)[33]
    assert len(row) == 11  # no h1, so no h1f either


# ── the keyed gender aliases ─────────────────────────────────────────────────


def test_gender_aliases_repeat_the_row_under_the_female_key():
    h, fk = _k(GOSSIP_EN), _k(female_variant(GOSSIP_EN))
    rows = {h: ['"ようこそ"', '"."'], "00" * 8: ['"別"', '"."']}
    aliases, dropped = lua_writer.gender_aliases(rows, {h: fk})
    assert aliases == {fk: ['"ようこそ"', '"."']} and dropped == []


def test_gender_alias_conflicts_follow_the_stated_rule():
    a, b, c, d, real = ("a" * 16, "b" * 16, "c" * 16, "d" * 16, "e" * 16)
    rows = {a: ['"一"', '"."'], b: ['"一"', '"."'], c: ['"二"', '"."'], d: ['"三"', '"."'], real: ['"本物"', '"."']}
    # a and b alias to one key with equal rows → one row; c and d alias to one key with different rows → none;
    # a real row under the female key wins.
    aliases, dropped = lua_writer.gender_aliases(rows, {a: "1" * 16, b: "1" * 16, c: "2" * 16, d: "2" * 16, real: a})
    assert aliases == {"1" * 16: ['"一"', '"."']}
    assert dropped == sorted(["2" * 16, a])


def _store(tmp_path: Path) -> Store:
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    eng = Store(data, english=True)
    h = _k(GOSSIP_EN)
    eng.save("gossip", [english_line(h, "text", GOSSIP_EN, h, SRC)])
    eng.save("quest", [english_line(3099, "progress", QUEST_EN, _k(QUEST_EN), SRC)])
    store = Store(data)
    gossip = entry(h, "text", "ケナリウスの加護を。\n\n私はTajarri。", status="trusted", prov=PROV)
    gossip["english"] = {"hash": h, "src": "gossip-key@normalize_v1"}
    store.save("gossip", [gossip])
    store.save("quest", [_quest(3099, "progress", "ようこそ。これを持っていけ。", _k(QUEST_EN))])
    return store


def test_plan_ships_the_alias_in_the_female_keys_shard_and_reports_it(tmp_path: Path):
    store = _store(tmp_path)
    report: dict = {}
    planned = generate.plan(store, [], report)
    h, fk = _k(GOSSIP_EN), _k(female_variant(GOSSIP_EN))
    male = planned[schema.shard_relpath("gossip", h[:2])]
    female = planned[schema.shard_relpath("gossip", fk[:2])]
    assert f'["{h}"] = {{ "ケナリウスの加護を。\\n\\n私はTajarri。", "." }}' in male
    assert f'["{fk}"] = {{ "ケナリウスの加護を。\\n\\n私はTajarri。", "." }}' in female
    assert report == {"aliases": {"gossip": 1, "book": 0},
                      "dropped": {"gossip": [], "book": []},
                      "ambiguous": {"gossip": [], "book": []}}
    assert "gossip = 1" in planned["Data/Meta.lua"]  # Meta counts lines, not alias keys
    quest = planned[schema.shard_relpath("quest", 3)]
    assert lua_writer.h1_literal(_k(female_variant(QUEST_EN))) in quest


def test_gender_report_lines_name_every_dropped_and_ambiguous_key():
    report = {"aliases": {"gossip": 2, "book": 1}, "dropped": {"gossip": ["1" * 16], "book": []},
              "ambiguous": {"gossip": [], "book": ["2" * 16]}}
    assert generate.gender_report_lines(report) == [
        "generate: gender aliases: 3 added · 1 dropped · 1 ambiguous",
        f"  dropped alias gossip:{'1' * 16}",
        f"  ambiguous female variant book:{'2' * 16}",
    ]

