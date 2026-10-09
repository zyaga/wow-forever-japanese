"""Voice casting (ADR-062): profiles from the client tables, the casting pass, the cast rows and overrides."""

from __future__ import annotations

import json
from pathlib import Path

from wfj.cmd import voice_audition, voice_make
from wfj.core import casting
from wfj.io import creature_tables, tables_stamp
from wfj.io.creature_tables import Display

ROOT = Path(__file__).resolve().parents[2]
CLIENT, VM = "client@1.60.1.70235", "vmangos@13b49dc"
DISPLAYS = {
    1: Display("male", "tauren"), 2: Display("female", "tauren"), 3: Display("none", None),
    4: Display("male", "scourge"), 5: Display("none", None),
}


def _creature(*displays: int, type_: int = 7, leader: bool = False) -> dict:
    return {"name": "x", "subname": "", "type": type_, "rank": 0, "leader": leader, "displays": list(displays)}


# ---- what the tables say ---------------------------------------------------------------------------------


def test_race_and_gender_come_from_the_client_first():
    assert casting.facts(_creature(1), DISPLAYS, CLIENT, VM, 1) == {
        "gender": ("male", CLIENT), "race": ("tauren", CLIENT)}


def test_a_creature_shown_as_both_genders_is_mixed():
    assert casting.facts(_creature(1, 2), DISPLAYS, CLIENT, VM, None)["gender"] == ("mixed", CLIENT)
    assert casting.facts(_creature(3, 1), DISPLAYS, CLIENT, VM, None)["gender"] == ("male", CLIENT)


def test_the_database_fills_what_the_client_lacks():
    f = casting.facts(_creature(999, type_=2), DISPLAYS, CLIENT, VM, 1)
    assert f == {"gender": ("female", VM), "race": ("dragonkin", VM), "archetype": ("dragon", VM)}
    assert casting.facts(_creature(1, leader=True), DISPLAYS, CLIENT, VM, None)["role"] == ("leader", VM)
    assert casting.facts(None, DISPLAYS, CLIENT, VM, None) == {}


def test_a_forsaken_model_is_undead():
    assert casting.facts(_creature(4), DISPLAYS, CLIENT, VM, None)["archetype"] == ("undead", CLIENT)


# ---- profiles: build and the casting pass ----------------------------------------------------------------


def _facts():
    return {10: {"race": ("tauren", CLIENT), "gender": ("male", CLIENT)}, 11: {}}


def test_build_writes_table_values_with_their_source():
    rows = casting.build([11, 10], _facts(), [], "2026-10-06")
    assert [r["creature"] for r in rows] == [10, 11]
    assert rows[0]["race"] == "tauren" and rows[0]["provenance"]["race"] == {"source": CLIENT, "imported": "2026-10-06"}
    assert rows[1] == {"creature": 11, "provenance": {}}


def test_the_pass_fills_gaps_and_never_replaces_a_table_value():
    rows = casting.build([10, 11], _facts(), [], "2026-10-06")
    drafts = [{"creature": 10, "age": "elder", "archetype": "none", "race": "orc", "reason": "says わし"},
              {"creature": 11, "age": "young", "archetype": "ghost", "race": "other", "gender": "female", "reason": "r"}]
    rows, problems = casting.merge_machine(rows, drafts, "m", "casting-1", "2026-10-06")
    assert rows[0]["race"] == "tauren" and rows[0]["age"] == "elder"
    assert problems == ["creature 10: race kept 'tauren' (draft says 'orc')"]
    assert rows[1]["provenance"]["age"] == {"source": "machine", "model": "m", "batch": "casting-1", "reason": "r",
                                            "imported": "2026-10-06"}
    assert casting.problems(rows) == []


def test_a_ruling_survives_a_rebuild_and_the_pass():
    ruled = {"creature": 10, "race": "tauren", "gender": "male", "age": "adult",
             "provenance": {"race": {"source": CLIENT, "imported": "2026-10-01"},
                            "gender": {"source": CLIENT, "imported": "2026-10-01"},
                            "age": {"source": "maintainer", "imported": "2026-10-02"}}}
    rows = casting.build([10], _facts(), [ruled], "2026-10-06")
    assert rows[0]["age"] == "adult" and rows[0]["provenance"]["race"]["imported"] == "2026-10-01"
    rows, problems = casting.merge_machine(rows, [{"creature": 10, "age": "elder", "reason": "r"}], "m", "b", "d")
    assert rows[0]["age"] == "adult" and problems


def test_drafts_with_bad_values_are_refused():
    rows = casting.build([11], _facts(), [], "2026-10-06")
    _, problems = casting.merge_machine(rows, [{"creature": 11, "age": "ancient", "reason": "r"},
                                               {"creature": 99, "age": "adult", "reason": "r"},
                                               {"creature": 11, "age": "adult"}], "m", "b", "2026-10-06")
    assert any("age 'ancient'" in p for p in problems)
    assert "draft for unknown creature 99" in problems and "creature 11: no reason" in problems


def test_validate_checks_profiles():
    bad = [{"creature": 1, "race": "Martian", "age": "adult", "provenance": {"race": {"source": "machine",
            "model": "m", "batch": "b", "reason": "r", "imported": "2026-10-06"}}},
           {"creature": 1, "provenance": {}}]
    problems = casting.problems(bad)
    assert any("lowercase race" in p for p in problems)
    assert any("1 age: no provenance" in p for p in problems)
    assert "voice profiles 1: duplicate" in problems


def test_the_committed_profiles_are_complete():
    rows = voice_make._rows(ROOT / "data" / "voice" / "profiles.jsonl")
    assert casting.problems(rows) == []
    assert casting.missing_age(rows) == []


# ---- casting ---------------------------------------------------------------------------------------------


ROWS = [
    {"name": "ghost", "when": {"archetype": "ghost"}, "voices": ["g"]},
    {"name": "empty", "when": {"race": "tauren"}, "voices": []},
    {"name": "elder", "when": {"age": "elder"}, "voices": ["e1", "e2"]},
    {"name": "female", "when": {"gender": "female"}, "voices": ["f"]},
    {"name": "male", "when": {"gender": ["male", "none"]}, "voices": ["m"]},
]


def _p(c, **kw):
    return {"creature": c, **kw}


def test_first_matching_row_with_voices_wins():
    got = casting.cast([_p(1, archetype="ghost", age="elder", gender="male"), _p(2, race="tauren", gender="male"),
                        _p(3, gender="female", age="adult"), _p(4)], ROWS, "n", {})
    assert {c: v["row"] for c, v in got.items()} == {1: "ghost", 2: "male", 3: "female", 4: "narrator"}
    assert got[4]["voice"] == "n"


def test_a_creature_keeps_its_voice_and_neighbours_spread():
    elders = [_p(c, age="elder") for c in range(100, 140)]
    once = casting.cast(elders, ROWS, "n", {})
    again = casting.cast(list(reversed(elders)), ROWS, "n", {})
    assert once == again
    assert {v["voice"] for v in once.values()} == {"e1", "e2"}


def test_mixed_gender_is_cast_twice_and_an_override_wins():
    got = casting.cast([_p(5, gender="mixed", age="adult"), _p(6, gender="female")], ROWS, "n", {6: "m"})
    assert got[5] == {"voice": "m", "row": "male", "female": "f", "female_row": "female"}
    assert got[6] == {"voice": "m", "row": "override"}


def test_roster_problems():
    roster = {"m": {"style": 1, "licence": "ACML 1.0"}, "Bad!": {"style": "x", "licence": "custom"}}
    rows = [{"name": "a", "when": {"age": "old"}, "voices": ["m", "zz"]}, {"name": "a", "voices": "m"}]
    problems = casting.roster_problems(roster, rows, "m", "nope")
    for want in ("roster 'Bad!'", "style must be", "licence must be", "narrator voice 'nope'", "voice 'zz'",
                 "age 'old'", "needs a unique name", "voices must be a list"):
        assert any(want in p for p in problems), want


def test_the_committed_voice_toml_loads():
    cfg = voice_make.load_config(ROOT / "pipeline" / "voice.toml")
    assert cfg["narrator"] in cfg["roster"]


# ---- the client tables and the audition ------------------------------------------------------------------


def test_creature_tables_read_race_and_sex(tmp_path):
    (tmp_path / "CreatureDisplayInfo.csv").write_text(
        "ID,ModelID,ExtendedDisplayInfoID,Gender\n1,5,10,0\n2,6,0,2\n3,7,11,0\n")
    (tmp_path / "CreatureDisplayInfoExtra.csv").write_text("ID,DisplayRaceID,DisplaySexID\n10,6,0\n11,4,1\n")
    (tmp_path / "ChrRaces.csv").write_text("ID,ClientFileString\n4,NightElf\n6,Tauren\n")
    tables_stamp.write(tmp_path, creature_tables.TABLES, "db2@1.60.1.70235")
    displays, src = creature_tables.read(tmp_path)
    assert src == "client@1.60.1.70235"
    assert displays == {1: Display("male", "tauren"), 2: Display("none", None), 3: Display("female", "nightelf")}


def test_creature_tables_refuse_mixed_builds(tmp_path):
    for t in creature_tables.TABLES:
        (tmp_path / f"{t}.csv").write_text("ID\n")
    tables_stamp.write(tmp_path, creature_tables.TABLES[:2], "db2@1")
    tables_stamp.write(tmp_path, creature_tables.TABLES[2:], "db2@2")
    try:
        creature_tables.read(tmp_path)
    except ValueError as e:
        assert "not stamped from one build" in str(e)
    else:
        raise AssertionError("mixed builds were accepted")


def test_audition_names_match_with_or_without_their_bracketed_tail():
    table = {"猩々博士（雑談ボイス）": "ACML 1.0", "morioki": "ACML 1.0"}
    assert voice_audition.lookup(table, "猩々博士 (雑談ボイス)") == "ACML 1.0"
    assert voice_audition.lookup(table, "morioki") == "ACML 1.0"
    assert voice_audition.lookup(table, "unknown") is None
    assert voice_audition.kind_gender("elder, female") == "female"
    assert voice_audition.kind_gender("ghost") == "any" and voice_audition.kind_gender("orc, male") == "male"


def test_every_catalogue_voice_has_an_allowed_licence():
    lic = voice_audition.licences()
    assert len(lic) == 40 and set(lic.values()) == {"ACML 1.0", "CC0"}


def test_audition_apply_writes_roster_and_rows(tmp_path):
    folder = tmp_path / "audition"
    folder.mkdir()
    (folder / "voices.json").write_text(json.dumps([
        {"id": "v11", "name": "morioki", "style": 11, "style_name": "ノーマル", "pitch": 0.0, "speed": None,
         "intonation": 1.0, "try": ""},
        {"id": "v12older", "name": "morioki", "style": 11, "style_name": "ノーマル", "pitch": -0.05, "speed": 0.85,
         "intonation": 1.0, "try": "older"},
    ], ensure_ascii=False))
    (folder / "picks.json").write_text(json.dumps({"female": ["v11", "v12older"], "narrator": ["v11"]}))
    cfg = tmp_path / "voice.toml"
    cfg.write_text('engine = "x"\nspeed_scale = 0.9\nnarrator = "old"\nbook_narrator = "old"\n'
                   '[roster.old]\nmodel = "M"\nstyle = 1\nlicence = "ACML 1.0"\n\n'
                   "# Cast rows, first match wins.\n\n"
                   '[[cast]]\nname = "female"\nwhen = { gender = "female" }\nvoices = []\n\n[credits]\nengine = "E"\n')
    assert voice_audition.apply(cfg, tmp_path) == 0
    got = voice_make.load_config(cfg)
    assert got["cast"][0]["voices"] == ["v11", "v12older"]
    assert got["narrator"] == "v11"
    assert got["roster"]["v12older"]["pitch"] == -0.05 and got["roster"]["v12older"]["speed"] == 0.85
