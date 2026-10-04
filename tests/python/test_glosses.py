"""The word popup's meanings (ADR-039): written in the reading records, numbered once in the generated meaning
table, cross-checked against JMdict locally. The entry · validate · generate · the JMdict cross-check."""

import json
from pathlib import Path

import pytest

from wfj.cmd import generate
from wfj.cmd import glosses as cmd
from wfj.core import glosses, readings
from wfj.emit import schema
from wfj.io.jsonl_store import Store

# a synthetic file in JMdict's (jmdict-simplified) shape: made-up ids and meanings, no JMdict data
FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "jmdict" / "jmdict-mini.json"
MACHINE = {"class": "machine", "model": "m", "source": "readings@test-batch", "imported": "2026-09-25"}
HUMAN = {"class": "human", "translator": "Az", "source": "cqjt@3446c82", "imported": "2026-09-13"}
JA = "森で倒して調査した。ここにいる。"
WORDS = [
    ["森", "もり"],
    ["倒して", "たおして", "倒す", "たおす", "defeat"],
    ["調査した", "ちょうさした", "調査する", "ちょうさする", "investigated"],
    ["いる", "いる", "いる", "いる", "to be (here)"],
]


# ── the entry ──────────────────────────────────────────────────────────────


def test_an_entry_may_carry_its_dictionary_form_and_meaning():
    assert readings.word_problems(JA, WORDS) == []


@pytest.mark.parametrize(
    ("entry", "problem"),
    [
        (["倒して", "たおして", "倒す", "たおす"], "must be [word, reading]"),
        (["倒して", "たおして", "倒す", "たおす", ""], "one trimmed line"),
        (["倒して", "たおして", "倒す", "たおす", "a|b"], "without '|'"),
        (["倒して", "たおして", "倒す", "たおす", "a\tb"], "without '|'"),
        (["倒して", "たおして", "倒す", "たおす", "a\rb"], "control characters"),
        (["倒して", "たおして", "倒す", "たおす", "x" * 61], "61 characters"),
        (["倒して", "たおして", "Taosu", "たおす", "defeat"], "dictionary form"),
        (["倒して", "たおして", "倒す", "taosu", "defeat"], "is not kana"),
        (["いる", "いる"], "a kana word needs itself as reading and a meaning"),
        (["いる", "いた", "いる", "いる", "to be"], "a kana word needs itself"),
    ],
)
def test_a_bad_entry_is_refused(entry, problem):
    ja = "倒していた。いる。"
    assert any(problem in p for p in readings.word_problems(ja, [entry])), readings.word_problems(ja, [entry])


# ── generate ───────────────────────────────────────────────────────────────


def _line(id_, field, ja):
    return {"id": id_, "field": field, "ja": ja, "status": "trusted", "checks": [], "provenance": dict(HUMAN),
            "english": {"hash": "0123456789abcdef", "src": "wdb@1.60.1.69913"}, "reasons": [], "conflicts": []}


@pytest.fixture
def data(tmp_path, monkeypatch):
    d = tmp_path / "data"
    d.mkdir()
    (d / "SCHEMA").write_text("1\n")
    Store(d).save("quest", [_line(456, "description", JA), _line(457, "description", "森で倒して帰る。")])
    Store(d / "reading").save("quest", [
        readings.record(456, "description", JA, WORDS, dict(MACHINE)),
        readings.record(457, "description", "森で倒して帰る。",
                        [["森", "もり"], ["倒して", "たおして", "倒す", "たおす", "defeat"]], dict(MACHINE)),
    ])
    monkeypatch.setattr(cmd, "data_root", lambda start=None: d)
    return d


def test_generate_numbers_each_meaning_once_and_points_the_rows_at_it(data):
    store = Store(data)
    planned = generate.plan(store, [])
    table = planned[schema.gloss_relpath(0)]
    # sorted, 1-based, each distinct meaning once (倒して → defeat is used by two lines)
    assert '  [1] = "いる\\tいる\\tto be (here)",' in table
    assert '  [2] = "倒す\\tたおす\\tdefeat",' in table
    assert '  [3] = "調査する\\tちょうさする\\tinvestigated",' in table
    assert "[4]" not in table
    rows = planned["Data/Reading/Reading_quest_0000.lua"]
    assert '["quest:456"] = { description = "森=もり 倒して=たおして=2 調査した=ちょうさした=3 いる=いる=1" },' in rows
    assert '["quest:457"] = { description = "森=もり 倒して=たおして=2" },' in rows
    assert "gloss = 3 }" in planned["Data/Meta.lua"]
    assert generate.plan(store, []) == planned  # byte-identical rerun
    files = generate.toc_files(planned)
    assert files[-1] == schema.gloss_relpath(0)  # after the readings
    assert schema.TOC_ORDER[-2:] == ("reading", "gloss")


def test_a_stale_reading_takes_its_meanings_with_it(data):
    Store(data).save("quest", [_line(456, "description", "変わった。"), _line(457, "description", "森で倒して帰る。")])
    planned = generate.plan(Store(data), [])
    table = planned[schema.gloss_relpath(0)]
    assert '[1] = "倒す\\tたおす\\tdefeat"' in table and "investigated" not in table


def test_the_meaning_table_is_split_per_thousand():
    assert schema.gloss_relpath(0) == "Data/Gloss/Gloss_0000.lua"
    assert (glosses.shard_of(1), glosses.shard_of(1000), glosses.shard_of(1001)) == (0, 0, 1)


# ── stable meaning numbers (ADR-060) ──────────────────────────────────────


def _generate(data):
    """generate's plan and numbers file, as `wfj generate` writes them."""
    store, report = Store(data), {}
    planned = generate.plan(store, [], report)
    generate.write_numbers(store, report["meaning_numbers"])
    return planned


def _numbers(data):
    return (data / "reading" / glosses.NUMBERS_FILE).read_text(encoding="utf-8")


def _gloss_rows(planned):
    return [ln for ln in planned[schema.gloss_relpath(0)].splitlines() if ln.startswith("  [")]


def _add_forest(data):
    """A meaning that sorts before 調査する (numbered 3): sorted numbering would have moved it to 4."""
    recs = Store(data / "reading").load("quest")
    for rec in recs:
        if rec["id"] == 457:
            rec["words"][0] = ["森", "もり", "森", "もり", "forest"]
    Store(data / "reading").save("quest", recs)


def test_with_no_numbers_file_the_numbers_are_the_sorted_ones_and_the_file_is_written(data):
    planned = _generate(data)
    assert _numbers(data) == (
        "1\tいる\tいる\tto be (here)\n2\t倒す\tたおす\tdefeat\n3\t調査する\tちょうさする\tinvestigated\n"
    )
    assert generate.write_numbers(Store(data), _numbers(data)) == 0  # nothing new: not written again
    assert _generate(data) == planned


def test_a_new_meaning_takes_the_next_number_and_changes_only_what_uses_it(data):
    before = _generate(data)
    _add_forest(data)
    after = _generate(data)
    assert _numbers(data).splitlines()[-1] == "4\t森\tもり\tforest"  # sorts before 調査する, numbered last
    assert _gloss_rows(after) == _gloss_rows(before) + ['  [4] = "森\\tもり\\tforest",']
    changed = {rel for rel in after if after[rel] != before.get(rel)}
    assert changed == {schema.gloss_relpath(0), "Data/Reading/Reading_quest_0000.lua", "Data/Meta.lua"}
    rows = after["Data/Reading/Reading_quest_0000.lua"].splitlines()
    old_rows = before["Data/Reading/Reading_quest_0000.lua"].splitlines()
    assert [r for r in rows if "quest:457" not in r] == [r for r in old_rows if "quest:457" not in r]
    assert '  ["quest:457"] = { description = "森=もり=4 倒して=たおして=2" },' in rows


def test_a_meaning_no_line_uses_keeps_its_number_and_ships_nowhere(data):
    _generate(data)
    Store(data).save("quest", [_line(456, "description", "変わった。"), _line(457, "description", "森で倒して帰る。")])
    planned = _generate(data)
    assert _gloss_rows(planned) == ['  [2] = "倒す\\tたおす\\tdefeat",']
    assert "gloss = 1 }" in planned["Data/Meta.lua"]  # the shipped meanings, not the file's lines
    assert len(_numbers(data).splitlines()) == 3  # いる and 調査する keep their lines
    _add_forest(data)
    assert '[4] = "森' in _generate(data)[schema.gloss_relpath(0)]  # never 1 or 3
    Store(data).save("quest", [_line(456, "description", JA), _line(457, "description", "森で倒して帰る。")])
    planned = _generate(data)
    assert '  [1] = "いる\\tいる\\tto be (here)",' in _gloss_rows(planned)  # back under its old number
    assert len(_numbers(data).splitlines()) == 4


def test_two_runs_give_the_same_files_and_the_same_numbers(data):
    _add_forest(data)
    first, text = _generate(data), _numbers(data)
    assert (_generate(data), _numbers(data)) == (first, text)


@pytest.mark.parametrize(
    ("text", "problem"),
    [
        ("1\tいる\tいる\n", "not `n<TAB>"),
        ("x\tいる\tいる\tto be\n", "not `n<TAB>"),
        ("0\tいる\tいる\tto be\n", "not `n<TAB>"),
        ("1\tいる\t\tto be\n", "not `n<TAB>"),
        ("1\tいる\tいる\tto be\n1\t倒す\tたおす\tdefeat\n", "number 1 is given twice"),
        ("1\tいる\tいる\tto be\n2\tいる\tいる\tto be\n", "meaning already numbered 1"),
        ("\u00b2\tいる\tいる\tto be\n", "not `n<TAB>"),
    ],
)
def test_a_bad_numbers_file_is_refused_never_resolved(data, text, problem):
    _, problems = glosses.parse_numbers(text)
    assert any(problem in p for p in problems), problems
    (data / "reading" / glosses.NUMBERS_FILE).write_text(text, encoding="utf-8")
    with pytest.raises(ValueError, match=glosses.NUMBERS_FILE):
        generate.plan(Store(data), [], {})


def test_only_a_newline_ends_a_numbers_line():
    # a meaning may hold a character str.splitlines treats as a line end
    every = {("森", "もり", "a\u2028b"): 1, ("いる", "いる", "c\u0085d"): 2}
    assert glosses.parse_numbers(glosses.numbers_text(every)) == (every, [])


def test_a_byte_order_mark_is_read_past(data):
    _generate(data)
    path = data / "reading" / glosses.NUMBERS_FILE
    path.write_bytes(b"\xef\xbb\xbf" + path.read_bytes())
    assert len(generate.load_numbers(Store(data))[0]) == 3


def test_validate_reads_the_numbers_file_and_never_writes_it(data):
    from wfj.cmd import validate

    store, report = Store(data), {}
    generate.plan(store, [], report)
    path = data / "reading" / glosses.NUMBERS_FILE
    assert any("missing" in p for p in validate.rule_numbers(store, report["meaning_numbers"]))
    assert not path.exists()
    generate.write_numbers(store, report["meaning_numbers"])
    assert validate.rule_numbers(store, report["meaning_numbers"]) == []
    _add_forest(data)
    generate.plan(store, [], report)
    before = path.read_bytes()
    assert validate.rule_numbers(store, report["meaning_numbers"]) == [
        f"regenerate: 1 meanings have no number in {glosses.NUMBERS_FILE}; run `make generate`"
    ]
    assert path.read_bytes() == before


# ── the local JMdict cross-check ──────────────────────────────────────


def test_the_check_lists_dictionary_forms_jmdict_does_not_know(data):
    dictionary = glosses.Dictionary(json.loads(FIXTURE.read_text(encoding="utf-8")))
    records = Store(data / "reading").load("quest")
    # 調査する is looked up as 調査 (a noun + する); いる and 倒す are known; the fixture has no 森
    assert glosses.unknown(dictionary, records) == {}
    records[0]["words"].append(["帰る", "かえる", "帰還する", "きかんする", "return"])
    assert glosses.unknown(dictionary, records) == {("帰還する", "きかんする"): 1}
    lines = cmd.report(records, dictionary, 10)
    assert lines[0] == "glosses: 5 of 7 words carry a meaning · 4 distinct meanings"
    assert lines[-1].strip() == "1× 帰還する (きかんする)"


def test_the_repo_never_commits_jmdict(root):
    assert not list(root.glob("data/**/jmdict*.json"))
    assert not (root / "data" / "gloss").exists()
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))  # the only JMdict-shaped file: synthetic
    assert fixture["version"].endswith("synthetic")
    assert {g["text"] for e in fixture["words"] for s in e["sense"] for g in s["gloss"]} == {"synthetic"}
