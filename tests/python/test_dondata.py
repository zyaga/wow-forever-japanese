"""`wfj.io.dondata`: who gives and takes each quest, read from DonData's two quest files."""

from __future__ import annotations

from pathlib import Path

from wfj.io import dondata

ATT = """-- a header comment
local _, ns = ...
ns.ATT_META = { commit = "abc", quests = 4 }
-- [questID] = { map, x, y, faction, level, prereqs, givers, flags, classes, races, prereqsNeeded, skill, name }
ns.ATT_QUESTS = {
[2]={1440,75.8,69.6,"H",20,{6383},nil,"i",nil,nil,nil,nil,"A claw, with a comma"},
[5]={1431,18.2,56.3,"A",17,{163},{288},nil,nil,nil,nil,nil,"One giver"},
[6]={1429,48.1,42.9,"A",2,nil,{823,824},"r",nil,nil,nil,nil,"Two givers"},
[7]={1429,48.9,41.6,"A",nil,nil,nil,nil,nil,nil,nil,nil,"Nobody named"},
}
ns.ATT_OBJECTIVES = {
[5]={[1]={{262037},{},{}}},
}
"""

EXTRA = """local _, ns = ...
ns.EXTRA_QUESTS = {
[28]={1450,56.2,30.6,"H",16,nil,{11802},nil,{11},{6},nil,nil,"Extra quest","wc"},
}
-- [questID] = { uiMapID, x, y, npcID } where the quest is turned in
ns.QUEST_ENDS = {
[5]={1450,36.5,40.1,272},
[6]={1450,36.5,40.1},
[8]={1429,24.6,58.2,0},
}
ns.EXTRA_GIVERS = {
[7]={3169,3354},
[9]={},
}
ns.EXTRA_ITEM_STARTS = {[184]=true,[373]=true,}
"""


def _read(tmp_path: Path) -> dondata.QuestNpcs:
    (tmp_path / "att.lua").write_text(ATT, encoding="utf-8")
    (tmp_path / "extra.lua").write_text(EXTRA, encoding="utf-8")
    return dondata.read(tmp_path / "att.lua", tmp_path / "extra.lua")


def test_givers_come_from_both_files_and_a_quest_nobody_gives_has_none(tmp_path):
    found = _read(tmp_path)
    assert found.givers == {5: (288,), 6: (823, 824), 7: (3169, 3354), 28: (11802,)}


def test_an_item_start_is_marked_and_never_a_giver(tmp_path):
    found = _read(tmp_path)
    assert found.item_starts == {2, 184, 373}
    assert 2 not in found.givers


def test_a_turn_in_with_no_creature_is_an_object_never_a_creature(tmp_path):
    found = _read(tmp_path)
    assert found.enders == {5: (272,)}
    assert found.object_ends == {6, 8}  # no fourth field, or the id 0


def test_no_text_of_the_files_is_read(tmp_path):
    found = _read(tmp_path)
    flat = repr(found)
    assert "giver" not in flat.lower().replace("givers=", "") and "comma" not in flat


def test_the_source_names_the_first_seven_of_the_commit():
    assert dondata.source("f7693f23ae6646551cb1eb062224a1304151a0aa") == "dondata@f7693f2"
