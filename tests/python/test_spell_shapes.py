"""The spell an item's tooltip line prints, by the line's shape (core/spell_shapes.py → Data/SpellShapes.lua)."""

import re

from wfj.cmd import generate
from wfj.core import spell_shapes
from wfj.emit import lua_writer

MANA = "Restores $s1 mana per 5 sec."
HEAL = "Increases healing done by spells and effects by up to $s1."
HEAL_JA = ("呪文と効果による回復量が最大$N1増加します。", "unaligned")


def test_a_shape_maps_to_its_lowest_spell_when_every_spell_of_it_ships_the_same_japanese():
    english = {9314: HEAL, 7675: HEAL, 446470: HEAL}
    shipped = {9314: HEAL_JA, 7675: HEAL_JA, 446470: HEAL_JA}
    assert spell_shapes.table(english, shipped, [HEAL]) == {spell_shapes.shape_key(HEAL): 7675}


def test_a_shape_two_spells_word_differently_or_one_spell_does_not_ship_is_left_out():
    english = {1: MANA, 2: "Restores $s1 mana per $t1 sec."}
    differ = {1: ("$D1ごとにマナを$N1回復します。", "unaligned"), 2: ("$N2秒ごとにマナを$N1回復します。", "unaligned")}
    assert spell_shapes.table(english, differ, [MANA]) == {}
    status = {1: ("$D1ごとにマナを$N1回復します。", "unaligned"), 2: ("$D1ごとにマナを$N1回復します。", "trusted")}
    assert spell_shapes.table(english, status, [MANA]) == {}
    assert spell_shapes.table({1: HEAL, 2: HEAL}, {1: HEAL_JA}, [HEAL]) == {}


def test_only_shapes_an_item_prints_are_kept():
    english = {1: HEAL, 2: MANA}
    shipped = {1: HEAL_JA, 2: ("$D1ごとにマナを$N1回復します。", "unaligned")}
    assert set(spell_shapes.table(english, shipped, ["Use: nothing like it", f"{HEAL}\n\"A flavour line.\""])) == {
        spell_shapes.shape_key(HEAL)}


def test_an_item_window_is_any_run_of_whole_lines_so_a_spell_with_breaks_of_its_own_is_found():
    windows = spell_shapes.item_windows(["A one.\nB two.\r\nB three.\nC four."])
    assert {"A one.", "B two.\r\nB three.", "C four.", "A one.\nB two.\r\nB three.\nC four."} <= windows
    assert "B two." in windows  # a line of a longer spell is a window too; its spell has to equal it whole


def test_a_template_with_text_the_client_splices_in_or_chooses_has_no_shape():
    assert spell_shapes.shape_key("Gain the Quick Draw ability:\r\n\r\n$@spelldesc398196") is None
    assert spell_shapes.shape_key("$?s436895[Increases all damage by $s1%.][Nothing.]") is None
    # a value and a literal number of the same wording share a shape; their Japanese decides
    assert spell_shapes.shape_key(MANA) == spell_shapes.shape_key("Restores 5 mana per 5 sec.")


def test_spell_inputs_take_shipped_description_lines_only():
    lines = [
        {"id": 1, "field": "description", "ja": "回復。", "status": "unaligned"},
        {"id": 2, "field": "description", "ja": "", "status": "unaligned"},
        {"id": 3, "field": "aura", "ja": "効果。", "status": "unaligned"},
    ]
    english = [{"id": 1, "field": "description", "en": "Heals."}, {"id": 3, "field": "aura", "en": "Aura."}]
    assert spell_shapes.spell_inputs(lines, english) == ({1: "Heals."}, {1: ("回復。", "unaligned")})


def test_the_table_is_written_as_keys_only_sorted():
    text = lua_writer.spell_shapes_text({"ffff000011112222": 7, "0000aaaabbbbcccc": 7675})
    assert text == "\n".join([
        lua_writer.HEADER.format(src="data/"),
        "local _, WFJ = ...",
        "WFJ.Data.spellShapes = {",
        '  ["0000aaaabbbbcccc"] = 7675,',
        '  ["ffff000011112222"] = 7,',
        "}",
    ]) + "\n"


def test_the_spliced_in_spells_table_is_ids_only_and_names_what_each_spell_splices_in(root):
    text = lua_writer.spell_includes_text({1319309: [24907, 24932], 17: [3]})
    assert text == "\n".join([
        lua_writer.HEADER.format(src="data/"),
        "local _, WFJ = ...",
        "WFJ.Data.spellIncludes = {",
        "  [17] = { 3 },",
        "  [1319309] = { 24907, 24932 },",
        "}",
    ]) + "\n"
    # the shipped file: Druidic Auras prints two auras' text, Metamorphosis three spells' descriptions
    shipped = (root / "addon/WoWForeverJapanese/Data/SpellIncludes.lua").read_text(encoding="utf-8")
    assert "  [1319309] = { 24907, 24932 },\n" in shipped
    assert "  [403789] = { 403828, 412788, 412789 },\n" in shipped
    assert all(re.fullmatch(r"  \[\d+\] = \{ \d+(, \d+)* \},|}", line) for line in shipped.splitlines()[3:])


def test_the_shipped_table_names_the_healing_spell_and_holds_no_english(planned):
    text = planned["Data/SpellShapes.lua"]
    assert f'  ["{spell_shapes.shape_key(HEAL)}"] = 7675,' in text
    body = text.split("\n", 3)[3]
    assert all(re.fullmatch(r'  \["[0-9a-f]{16}"\] = \d+,|}', line) for line in body.splitlines())
    files = generate.toc_files(planned)
    assert files.index("Data/SpellShapes.lua") == files.index("Data/Displays.lua") + 1
