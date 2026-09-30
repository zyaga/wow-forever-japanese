import pytest

from wfj.io.lua_reader import LuaSyntaxError, Table, as_int_id, parse_assignment, parse_assignments


def test_escapes_decoded_and_markup_preserved():
    name, t = parse_assignment(r"""X={["1"]={"a\"b\nc\\d|cffffd100e|r \65 \z",nil},}""")
    assert name == "X"
    assert t.items[0][1].positional()[0] == 'a"b\nc\\d|cffffd100e|r A z'


def test_duplicate_keys_preserved_in_order():
    _, t = parse_assignment(
        'T = {\n  ["7"] = { ["Title"] = "first" },\n  ["7"] = { ["Title"] = "second" },\n}'
    )
    assert [k for k, _ in t.items] == ["7", "7"]
    assert [v.get("Title") for _, v in t.items] == ["first", "second"]


def test_value_tables_and_nil():
    _, t = parse_assignment('ItemData={["118"]={"x $N1 y",{N1="70-90", N2="1"}},["119"]={"z",nil},}')
    pos = t.items[0][1].positional()
    assert pos[0] == "x $N1 y" and isinstance(pos[1], Table) and pos[1].named() == {"N1": "70-90", "N2": "1"}
    assert t.items[1][1].positional() == ["z", None]


def test_index_chain_and_int_keys_and_comments():
    _, t = parse_assignment(
        'pfDB["quests"]["enUS"] = { -- header\n  [2] = { ["T"] = "Sharptalon\\\'s Claw" }, -- c\n}'
    )
    assert t.items[0][0] == 2 and t.items[0][1].get("T") == "Sharptalon's Claw"


def test_errors_carry_line_numbers():
    with pytest.raises(LuaSyntaxError, match="line 2"):
        parse_assignment('X={\n["1"]={"unterminated}')
    with pytest.raises(LuaSyntaxError, match="trailing"):
        parse_assignment("X={} Y={}")


def test_as_int_id():
    assert as_int_id("117") == 117 and as_int_id(2) == 2
    with pytest.raises(LuaSyntaxError):
        as_int_id("abc")


def test_fixture_excerpts_parse(root):
    fx = root / "tests" / "fixtures"
    _, q = parse_assignment((fx / "predecessor/QuestLogData.excerpt.lua").read_text(encoding="utf-8"))
    assert len(q.items) == 35 and [k for k, _ in q.items].count("184") == 2
    _, i = parse_assignment((fx / "predecessor/ItemData.excerpt.lua").read_text(encoding="utf-8"))
    assert i.get("118").positional()[1].named() == {"N1": "70-90"}
    _, s = parse_assignment((fx / "predecessor/SpellData.excerpt.lua").read_text(encoding="utf-8"))
    assert s.get("17").positional()[2].startswith("$N1")
    _, p = parse_assignment((fx / "pfquest/quests.excerpt.lua").read_text(encoding="utf-8"))
    assert p.get(2).get("O").startswith("Bring Sharptalon's Claw")


@pytest.mark.parametrize(
    "text",
    ['X={["1"]=', 'X={["1"]={"a"', "X={", 'X={["1"]="a\\'],
)
def test_truncated_input_is_a_syntax_error_not_an_index_error(text):
    """A truncated file raises the reader's own error, so `wfj import` prints its
    one-line message instead of a traceback."""
    with pytest.raises(LuaSyntaxError, match="unexpected end of input"):
        parse_assignment(text)
    with pytest.raises(LuaSyntaxError, match="unexpected end of input"):
        parse_assignments(text)
