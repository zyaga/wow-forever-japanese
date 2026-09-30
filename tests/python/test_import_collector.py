"""`wfj import english collector`: the round-trip fixture, the merge rules, and the curated
importers keeping collector lines."""

from pathlib import Path

from test_collector_dump import dump, entry, gossip

from wfj.cmd.import_ import run
from wfj.core.hashing import key
from wfj.core.model import english_line, validate_line
from wfj.core.normalize import normalize_v1
from wfj.core.paragraphs import count_english
from wfj.io.jsonl_store import Store


def _data_dir(tmp_path: Path, monkeypatch) -> Path:
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    return tmp_path / "data"


def _snapshot(data: Path) -> dict[str, bytes]:
    return {str(p.relative_to(data)): p.read_bytes() for p in sorted((data / "english").rglob("*.jsonl"))}


def _write(tmp_path: Path, text: str, name: str = "WoWForeverJapanese.lua") -> str:
    p = tmp_path / name
    p.write_text(text, encoding="utf-8")
    return str(p)


def test_fixture_round_trip(root, tmp_path: Path, monkeypatch, capsys):
    data = _data_dir(tmp_path, monkeypatch)
    fx = root / "tests/fixtures/collector/WoWForeverJapanese.lua"
    assert run(["english", "collector", str(fx)]) == 0
    english = Store(data, english=True)
    lines = {(t, ln["id"], ln["field"]): ln for t in ("quest", "item", "spell", "unit") for ln in english.load(t)}
    assert len(lines) == 9  # quest 2's title and objectives ship with their English hash: known, never recorded
    for (t, _, _), ln in lines.items():
        assert ln["src"] == "collector@1.15.9.69722"
        assert ln["hash"] == key(normalize_v1(ln["en"]))
        assert validate_line(t, ln, english=True) == []
    assert ("quest", 2, "objectives") not in lines and ("quest", 2, "title") not in lines
    assert lines[("unit", 3100, "name")]["en"] == "Senani Thunderheart"
    assert lines[("quest", 2, "completion")]["en"] == "$N, your aim is true. The $C of the $R is welcome."
    # paragraphs in pfQuest's form, so the completeness rule counts them the same way
    assert count_english(lines[("quest", 2, "description")]["en"]) == 2
    assert count_english(lines[("item", 117, "description")]["en"]) == 2
    # two talk windows; the shared "Goodbye." carries both NPCs
    gossip_lines = {ln["en"]: ln for ln in english.load("gossip")}
    assert len(gossip_lines) == 3  # one of the four ships Japanese
    assert gossip_lines["Goodbye."]["npcs"] == [68, 295]
    assert gossip_lines["Welcome to the Lion's Pride, $N. Even a $C needs a warm bed."]["npcs"] == [295]
    for ln in gossip_lines.values():
        assert ln["id"] == ln["hash"] == key(normalize_v1(ln["en"]))
        assert validate_line("gossip", ln, english=True) == []
    out = capsys.readouterr().out
    assert "rejected: none" in out and "12 entries" in out  # one gossip line ships, so it is not recorded
    before = _snapshot(data)
    assert run(["english", "collector", str(fx)]) == 0  # re-import: byte no-op
    assert _snapshot(data) == before


def test_merge_rules_added_unchanged_replaced_differs(tmp_path: Path, monkeypatch, capsys):
    data = _data_dir(tmp_path, monkeypatch)
    english = Store(data, english=True)
    same = "Sharptalon's Claw"
    english.save(
        "quest",
        [
            english_line(2, "title", same, key(normalize_v1(same)), "pfquest@7786596"),
            english_line(2, "objectives", "Old objectives.", key(normalize_v1("Old objectives.")), "pfquest@7786596"),
            english_line(3, "progress", "Earlier.", key(normalize_v1("Earlier.")), "collector@1.15.8.1"),
        ],
    )
    text = dump(
        entry("quest", 2, "title", same),  # unchanged
        entry("quest", 2, "objectives", "New objectives."),  # differs from pfQuest → kept
        entry("quest", 3, "progress", "Later."),  # replaces an earlier collector line
        entry("quest", 4, "completion", "Done."),  # added
        entry("quest", 5, "title", "T", h="0000000000000000"),  # rejected
    )
    assert run(["english", "collector", _write(tmp_path, text)]) == 0
    by = {(ln["id"], ln["field"]): ln for ln in english.load("quest")}
    assert by[(2, "title")]["src"] == "pfquest@7786596"
    assert by[(2, "objectives")]["en"] == "Old objectives."
    assert by[(3, "progress")]["en"] == "Later." and by[(3, "progress")]["src"] == "collector@1.15.9.69722"
    assert by[(4, "completion")]["en"] == "Done."
    assert (5, "title") not in by
    out = capsys.readouterr().out
    assert "quest       1         1        1       1" in out
    assert "rejected: hash_mismatch 1" in out
    assert "quest 2 objectives (kept pfquest@7786596)" in out


def test_unchanged_import_writes_nothing(tmp_path: Path, monkeypatch):
    data = _data_dir(tmp_path, monkeypatch)
    Store(data, english=True).save(
        "quest", [english_line(2, "title", "T", key(normalize_v1("T")), "pfquest@7786596")]
    )
    shard = data / "english/quest/quest-0000.jsonl"
    mtime = shard.stat().st_mtime_ns
    assert run(["english", "collector", _write(tmp_path, dump(entry("quest", 2, "title", "T")))]) == 0
    assert shard.stat().st_mtime_ns == mtime


def test_bad_version_exits_1(tmp_path: Path, monkeypatch, capsys):
    _data_dir(tmp_path, monkeypatch)
    assert run(["english", "collector", _write(tmp_path, dump(entry("quest", 2, "title", "T"), version=2))]) == 1
    assert "version" in capsys.readouterr().err


def test_pfquest_keeps_collector_lines_it_does_not_provide(root, tmp_path: Path, monkeypatch):
    data = _data_dir(tmp_path, monkeypatch)
    text = dump(entry("quest", 2, "progress", "Did you get it?"), entry("quest", 2, "title", "Collector title"),
                entry("quest", 99999, "title", "A Forever Quest"))
    assert run(["english", "collector", _write(tmp_path, text)]) == 0
    fx = root / "tests/fixtures/pfquest/quests.excerpt.lua"
    assert run(["english", "pfquest", str(fx), "--commit", "7786596"]) == 0
    by = {(ln["id"], ln["field"]): ln for ln in Store(data, english=True).load("quest")}
    assert by[(2, "progress")]["src"].startswith("collector@")  # pfQuest has no progress: kept
    assert by[(99999, "title")]["src"].startswith("collector@")
    assert by[(2, "title")]["src"] == "pfquest@7786596"  # pfQuest provides it: replaced
    assert by[(2, "title")]["en"] == "Sharptalon's Claw"


def test_wago_keeps_collector_descriptions(root, tmp_path: Path, monkeypatch):
    data = _data_dir(tmp_path, monkeypatch)
    text = dump(entry("item", 117, "description", "Use: Restores 61 health over 18 sec."),
                entry("spell", 17, "description", "Absorbs 44 damage."))
    assert run(["english", "collector", _write(tmp_path, text)]) == 0
    fx = root / "tests/fixtures/wago"
    assert run(["english", "wago-ids", str(fx / "ItemSparse.excerpt.csv"), str(fx / "SpellName.excerpt.csv"),
                "--build", "1.15.9.69722"]) == 0
    items = {(ln["id"], ln["field"]): ln for ln in Store(data, english=True).load("item")}
    spells = {(ln["id"], ln["field"]): ln for ln in Store(data, english=True).load("spell")}
    assert items[(117, "description")]["src"].startswith("collector@")
    assert items[(117, "name")]["en"] == "Tough Jerky"
    assert spells[(17, "description")]["src"].startswith("collector@")


def test_curated_importers_refuse_to_wipe_their_lines_with_nothing(tmp_path: Path, monkeypatch):
    from wfj.cmd.import_english import merge_source

    old = [english_line(2, "title", "T", key("T"), "pfquest@7786596")]
    try:
        merge_source("quest", old, [], "pfquest")
    except ValueError as e:
        assert "zero lines" in str(e)
    else:
        raise AssertionError("expected a refusal")
    assert merge_source("quest", [], [], "pfquest") == []


def test_check_and_validate_ignore_collector_english(root, tmp_path: Path, monkeypatch):
    """Importing a dump changes nothing check/validate see: a collector item
    description does not replace the name hash, and collector quest progress/completion do not replace the
    description hash, open number checks, or add Vanilla ids."""
    import shutil

    from wfj.cmd import check, validate

    data = _data_dir(tmp_path, monkeypatch)
    src = root / "data"
    for sub in ("item", "quest", "english/item", "english/quest"):
        (data / sub).mkdir(parents=True, exist_ok=True)
        for f in ("item-0000.jsonl", "quest-0000.jsonl"):
            if (src / sub / f).is_file():
                shutil.copy(src / sub / f, data / sub / f)
    english = Store(data, english=True)
    before = {t: check.build_scopes(english, t) for t in ("item", "quest")}
    vanilla = check.vanilla_ids(english)
    ref_before = validate.rule_referential(Store(data), english)
    text = dump(
        entry("item", 25, "description", "Use: A line no client table gives us."),  # 25: no description English
        entry("quest", 2, "completion", "Well done, $N."),
        entry("quest", 2, "progress", "Did you get 10 of them?"),
        entry("quest", 999, "description", "A Forever-only quest."),
    )
    assert run(["english", "collector", _write(tmp_path, text)]) == 0
    assert any(ln["src"].startswith("collector@") for ln in english.load("item"))
    after = {t: check.build_scopes(english, t) for t in ("item", "quest")}
    for t in ("item", "quest"):
        assert {i: (s.fields, s.hashes) for i, s in after[t].items()} == {
            i: (s.fields, s.hashes) for i, s in before[t].items()
        }
    assert check.vanilla_ids(english) == vanilla
    assert validate.rule_referential(Store(data), english) == ref_before


def test_truncated_dump_is_refused_with_one_line(tmp_path: Path, monkeypatch, capsys):
    """A truncated SavedVariables file → `wfj import:` error, exit 1, nothing written."""
    data = _data_dir(tmp_path, monkeypatch)
    assert run(["english", "collector", _write(tmp_path, 'WFJ_Collector = {["version"] = ')]) == 1
    assert "wfj import: line 1: unexpected end of input" in capsys.readouterr().err
    assert _snapshot(data) == {}


def test_gossip_lines_union_npcs_and_reimport_is_a_no_op(tmp_path: Path, monkeypatch, capsys):
    """Gossip English lands keyed by the gossip key with `npcs`; a second dump unions the NPC ids."""
    data = _data_dir(tmp_path, monkeypatch)
    first = _write(tmp_path, dump(gossip("Goodbye.", n=[6740]), gossip("Let me browse your goods.", n=[6740])))
    assert run(["english", "collector", first]) == 0
    english = Store(data, english=True)
    lines = {ln["en"]: ln for ln in english.load("gossip")}
    bye = lines["Goodbye."]
    assert bye["id"] == bye["hash"] == key(normalize_v1("Goodbye."))
    assert bye["npcs"] == [6740] and bye["src"] == "collector@1.15.9.69722"
    assert validate_line("gossip", bye, english=True) == []
    assert (data / "english/gossip" / f"gossip-{bye['id'][:2]}.jsonl").is_file()
    assert "gossip lines that gained an NPC: 0" in capsys.readouterr().out
    before = _snapshot(data)
    assert run(["english", "collector", first]) == 0
    assert _snapshot(data) == before

    second = _write(tmp_path, dump(gossip("Goodbye.", n=[1423, 6740])), name="second.lua")
    assert run(["english", "collector", second]) == 0
    assert {ln["en"]: ln for ln in english.load("gossip")}["Goodbye."]["npcs"] == [1423, 6740]
    out = capsys.readouterr().out
    assert "gossip lines that gained an NPC: 1" in out


def test_npcs_are_allowed_only_on_gossip_english():
    """`npcs` is a gossip-only, sorted, unique list of positive ints."""
    k = key(normalize_v1("Goodbye."))
    assert validate_line("gossip", english_line(k, "text", "Goodbye.", k, "collector@1.15.9.69722", npcs=[5, 3]),
                         english=True) == []
    assert english_line(k, "text", "Goodbye.", k, "collector@1.15.9.69722", npcs=[5, 3, 5])["npcs"] == [3, 5]
    assert "npcs" not in english_line(2, "title", "T", key("T"), "pfquest@7786596")
    bad = english_line(k, "text", "Goodbye.", k, "collector@1.15.9.69722")
    for n in ([], [3, 2], [0], [True], ["7"], [2, 2], [2**31]):
        bad["npcs"] = n
        assert any("npcs" in p for p in validate_line("gossip", bad, english=True)), n
    quest = english_line(2, "title", "T", key("T"), "pfquest@7786596")
    quest["npcs"] = [1]
    assert any("unexpected keys" in p for p in validate_line("quest", quest, english=True))
