"""ADR-036: readings. The record checks, staleness, the batch import and the generated shards."""

import json
import re

import pytest

from wfj.cmd import generate
from wfj.cmd import readings as cmd
from wfj.core import readings
from wfj.emit import lua_writer, schema
from wfj.io.jsonl_store import Store

HUMAN = {
    "class": "human",
    "translator": "Az",
    "source": "cqjt@3446c82",
    "imported": "2026-09-13",
}
MACHINE = {
    "class": "machine",
    "model": "reading-model-1",
    "source": "readings@test-batch",
    "imported": "2026-09-25",
}
CORRECTION = {
    "class": "correction",
    "translator": "reviewer",
    "source": "correction@2026-09-25",
    "imported": "2026-09-25",
    "corrects": "readings@test-batch",
}
JA = "私は森の仕事を少し手伝った。Conservator Ilthalaineに報告しなさい。"
GOSSIP_KEY = "db152bcd2f85b3f0"
GOSSIP_JA = "ああ、Shadowglenの美しさはいつも私の心を喜ばせる！"
WORDS = [
    ["私", "わたし"],
    ["森", "もり"],
    ["仕事", "しごと"],
    ["少し", "すこし"],
    ["手伝った", "てつだった"],
    ["報告", "ほうこく"],
]


def _line(id_, field, ja, status="trusted"):
    return {
        "id": id_,
        "field": field,
        "ja": ja,
        "status": status,
        "checks": [],
        "provenance": dict(HUMAN),
        "english": {"hash": "0123456789abcdef", "src": "wdb@1.60.1.69913"},
        "reasons": [],
        "conflicts": [],
    }


@pytest.fixture
def data(tmp_path, monkeypatch):
    d = tmp_path / "data"
    d.mkdir()
    (d / "SCHEMA").write_text("1\n")
    Store(d).save(
        "quest",
        [_line(456, "description", JA), _line(456, "title", "自然界のバランス")],
    )
    Store(d).save("gossip", [_line(GOSSIP_KEY, "text", GOSSIP_JA)])
    monkeypatch.setattr(cmd, "data_root", lambda start=None: d)
    return d


def _rec(id_=456, field="description", ja=JA, words=WORDS, prov=MACHINE):
    return readings.record(id_, field, ja, words, dict(prov))


def _check(recs, type_="quest", japanese=None):
    return readings.check(
        type_,
        recs,
        japanese or {(456, "description"): JA, (456, "title"): "自然界のバランス"},
    )


# ── record shape ──────────────────────────────────────────────────────


def test_a_good_record_is_current():
    result = _check([_rec()])
    assert result == {"problems": [], "stale": [], "current": [_rec()]}


@pytest.mark.parametrize(
    "change, needle",
    [
        (lambda r: r.pop("ja_hash"), "missing keys ['ja_hash']"),
        (lambda r: r.update(extra=1), "unexpected keys ['extra']"),
        (lambda r: r.pop("provenance"), "missing keys ['provenance']"),
        (
            lambda r: r.update(
                provenance={
                    "class": "human",
                    "translator": "x",
                    "source": "a@bcde",
                    "imported": "2026-09-25",
                }
            ),
            "provenance.class 'human'",
        ),
        (
            lambda r: r.update(
                provenance={
                    "class": "machine",
                    "source": "readings@test-batch",
                    "imported": "2026-09-25",
                }
            ),
            "machine provenance needs model",
        ),
        (lambda r: r.update(field="aura"), "field 'aura' not in"),
        (lambda r: r.update(id=0), "id must be a positive int"),
        (lambda r: r.update(ja_hash="xyz"), "ja_hash must be 16 hex chars"),
    ],
)
def test_malformed_records_are_rejected(change, needle):
    rec = _rec()
    change(rec)
    problems = _check([rec])["problems"]
    assert any(needle in p for p in problems), problems


def test_a_record_for_a_line_that_stopped_shipping_is_stale_not_an_error():
    # a rejected / withdrawn line must not stop `make data`; its reading waits, unshipped
    result = _check([_rec(id_=457)])
    assert result == {"problems": [], "stale": [(457, "description")], "current": []}


def test_a_duplicate_record_is_reported_not_resolved():
    problems = _check([_rec(), _rec()])["problems"]
    assert problems == ["reading quest 456/description: duplicate record"]


def test_gossip_ids_are_16_hex_keys():
    japanese = {(GOSSIP_KEY, "text"): GOSSIP_JA}
    good = readings.record(
        GOSSIP_KEY, "text", GOSSIP_JA, [["美しさ", "うつくしさ"]], dict(MACHINE)
    )
    assert _check([good], "gossip", japanese)["current"] == [good]
    bad = dict(good, id=456)
    assert (
        "gossip id must be a 16-hex key"
        in _check([bad], "gossip", japanese)["problems"][0]
    )


# ── staleness ─────────────────────────────────────────────────────────


def test_a_reading_for_changed_japanese_is_stale_and_not_generated(data):
    Store(data / "reading").save("quest", [_rec()])
    Store(data).save(
        "quest",
        [
            _line(456, "description", JA.replace("少し", "少々")),
            _line(456, "title", "自然界のバランス"),
        ],
    )
    store = Store(data)
    japanese = readings.shipped_japanese(store.load("quest"))
    result = readings.check("quest", Store(data / "reading").load("quest"), japanese)
    assert (
        result["stale"] == [(456, "description")]
        and result["current"] == []
        and result["problems"] == []
    )
    planned = generate.plan(store, [])
    assert not any(p.startswith("Data/Reading/") for p in planned)


# ── word checks ───────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "words, needle",
    [
        (
            [["森", "もり"], ["私", "わたし"]],
            "not found in the Japanese after the previous word",
        ),  # out of order
        ([["林", "はやし"]], "not found in the Japanese"),
        ([["に", "に"]], "has no kanji"),
        ([["私", "watashi"]], "is not kana"),
        ([["私", "わたし1"]], "is not kana"),
        ([["私", ""]], "must be non-empty"),
        ([["", "わたし"]], "must be non-empty"),
        ([["Ilthalaine報告", "ほうこく"]], "holds an ASCII character"),
        ([["私"]], "must be [word, reading]"),
        ([], "non-empty list"),
    ],
)
def test_word_rules(words, needle):
    problems = readings.word_problems(JA, words)
    assert any(needle in p for p in problems), problems


def test_a_word_with_a_digit_or_a_space_is_rejected():  # the packed row separates words with " " and "="
    assert any(
        "ASCII" in p for p in readings.word_problems("7匹倒せ", [["7匹", "ななひき"]])
    )
    assert any(
        "ASCII" in p for p in readings.word_problems("少 し", [["少 し", "すこし"]])
    )


def test_katakana_and_long_vowel_readings_are_kana():
    assert readings.word_problems("東京タワーへ", [["東京", "トーキョー"]]) == []


# ── import (word-check rejections, a correction is kept) ───────────────────────────


def _batch(tmp_path, rows):
    p = tmp_path / "batch.jsonl"
    p.write_text(
        "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows),
        encoding="utf-8",
    )
    return p


def _row(words=WORDS, ja=JA, id_=456, field="description", type_="quest"):
    return {
        "type": type_,
        "id": id_,
        "field": field,
        "ja": ja,
        "ja_hash": readings.ja_hash(ja),
        "words": words,
    }


def _import(batch, name="test-batch"):
    return cmd.run(
        [
            "import",
            str(batch),
            "--model",
            "reading-model-1",
            "--batch",
            name,
            "--date",
            "2026-09-25",
        ]
    )


def test_export_lists_lines_without_a_current_reading(data, tmp_path):
    ids = tmp_path / "ids.txt"
    ids.write_text("456  # The Balance of Nature\n")
    out = tmp_path / "out.jsonl"
    assert (
        cmd.run(["export", "--type", "quest", "--ids", str(ids), "--out", str(out)])
        == 0
    )
    rows = [json.loads(x) for x in out.read_text(encoding="utf-8").splitlines()]
    assert [(r["id"], r["field"]) for r in rows] == [
        (456, "title"),
        (456, "description"),
    ]
    assert rows[1]["ja"] == JA and rows[1]["ja_hash"] == readings.ja_hash(JA)
    Store(data / "reading").save("quest", [_rec()])
    assert (
        cmd.run(["export", "--type", "quest", "--ids", str(ids), "--out", str(out)])
        == 0
    )
    assert [
        json.loads(x)["field"] for x in out.read_text(encoding="utf-8").splitlines()
    ] == ["title"]


def test_export_class_keeps_only_lines_whose_shipped_variant_has_that_class(data, tmp_path):
    # one quest id mixes a human and a machine field; --class splits them
    title = _line(456, "title", "自然界のバランス")
    title["provenance"] = {"class": "machine", "model": "draft-model-1", "source": "draft@test"}
    Store(data).save("quest", [_line(456, "description", JA), title])
    ids = tmp_path / "ids.txt"
    ids.write_text("456\n")
    out = tmp_path / "out.jsonl"

    def fields(*extra):
        assert cmd.run(["export", "--type", "quest", "--ids", str(ids), "--out", str(out), *extra]) == 0
        return [json.loads(x)["field"] for x in out.read_text(encoding="utf-8").splitlines()]

    assert fields("--class", "machine") == ["title"]
    assert fields("--class", "human") == ["description"]
    assert fields("--class", "correction") == []
    assert fields() == ["title", "description"]
    with pytest.raises(SystemExit):
        cmd.run(["export", "--type", "quest", "--ids", str(ids), "--out", str(out), "--class", "robot"])


def test_import_writes_good_rows_and_rejects_bad_ones(data, tmp_path, capsys):
    rows = [
        _row(),
        _row(words=[["バランス", "ばらんす"]], ja="自然界のバランス", field="title"),
    ]
    assert _import(_batch(tmp_path, rows)) == 1
    out = capsys.readouterr().out
    assert "rejected quest 456/title: word 1 'バランス': has no kanji" in out
    stored = Store(data / "reading").load("quest")
    assert stored == [_rec()]  # the good row, with the batch's provenance


def test_import_rejects_rows_written_for_changed_japanese(data, tmp_path, capsys):
    row = _row()
    row["ja_hash"] = readings.ja_hash(JA + "!")
    assert _import(_batch(tmp_path, [row])) == 1
    assert "written for Japanese that has since changed" in capsys.readouterr().out
    assert Store(data / "reading").load("quest") == []


def test_machine_never_replaces_a_correction(data, tmp_path, capsys):
    corrected = _rec(words=[["私", "わたくし"]], prov=CORRECTION)
    Store(data / "reading").save("quest", [corrected])
    assert _import(_batch(tmp_path, [_row()])) == 0
    assert "kept the correction reading" in capsys.readouterr().out
    assert Store(data / "reading").load("quest") == [corrected]


def test_machine_replaces_machine(data, tmp_path):
    Store(data / "reading").save("quest", [_rec(words=[["私", "わたくし"]])])
    assert _import(_batch(tmp_path, [_row()])) == 0
    assert Store(data / "reading").load("quest") == [_rec()]


def test_dry_run_writes_nothing(data, tmp_path):
    batch = _batch(tmp_path, [_row()])
    assert (
        cmd.run(
            [
                "import",
                str(batch),
                "--model",
                "m-1",
                "--batch",
                "test-batch",
                "--dry-run",
            ]
        )
        == 0
    )
    assert Store(data / "reading").load("quest") == []


# ── generate ──────────────────────────────────────────────────────────


def test_generate_emits_reading_shards_in_the_toc_and_is_deterministic(data):
    gossip = readings.record(
        GOSSIP_KEY, "text", GOSSIP_JA, [["美しさ", "うつくしさ"]], dict(MACHINE)
    )
    Store(data / "reading").save("quest", [_rec()])
    Store(data / "reading").save("gossip", [gossip])
    store = Store(data)
    planned = generate.plan(store, [])
    quest = planned["Data/Reading/Reading_quest_0000.lua"]
    assert 'WFJ.Data.add("reading", {' in quest
    assert (
        '["quest:456"] = { description = "私=わたし 森=もり 仕事=しごと 少し=すこし'
        in quest
    )
    assert (
        '["gossip:db152bcd2f85b3f0"] = { text = "美しさ=うつくしさ" },'
        in (planned["Data/Reading/Reading_gossip_db.lua"])
    )
    assert "reading = 2, gloss = 0 }" in planned["Data/Meta.lua"]  # glosses counted after readings
    assert generate.plan(store, []) == planned  # byte-identical rerun
    files = generate.toc_files(planned)
    assert files[-2:] == [
        "Data/Reading/Reading_gossip_db.lua",
        "Data/Reading/Reading_quest_0000.lua",
    ]


def test_generate_refuses_a_malformed_reading(data):
    Store(data / "reading").save("quest", [_rec(words=[["林", "はやし"]])])
    with pytest.raises(ValueError, match="invalid data/reading/ records"):
        generate.plan(Store(data), [])


def test_the_reading_prefix_is_a_generated_folder():
    assert (
        schema.FILE_PREFIX["reading"] == "Reading" and schema.TOC_ORDER[-2:] == ("reading", "gloss")
    )
    assert lua_writer.reading_text("quest", 0, []).endswith(
        'WFJ.Data.add("reading", {\n})\n'
    )


# ── one call site ─────────────────────────────────────────────────────


def test_the_span_call_has_exactly_one_call_site_in_the_addon(root):
    """A span that splits a character makes the client exit (ADR-036): only UI/Readings.lua's guarded
    spanAreas may call it. Comments are ignored."""
    import re

    sites = []
    for path in sorted((root / "addon/WoWForeverJapanese").rglob("*.lua")):
        code = re.sub(r"--[^\n]*", "", path.read_text(encoding="utf-8"))
        n = code.count("CalculateScreenAreaFromCharacterSpan")
        if n:
            sites.append(
                (path.relative_to(root / "addon/WoWForeverJapanese").as_posix(), n)
            )
    # one call (pcall(fs.CalculateScreenAreaFromCharacterSpan, …)) and one capability check in `eligible`
    assert sites == [("UI/Readings.lua", 2)]


def test_validate_prints_how_many_lines_have_readings(data, capsys):
    from wfj.cmd import validate

    Store(data / "reading").save("quest", [_rec()])
    assert validate.rule_readings(Store(data)) == []
    out = capsys.readouterr().out
    assert "validate: readings: 1 of 2 shipped quest lines have one" in out
    assert "validate: readings: 0 of 1 shipped gossip lines have one" in out


# ── the shipped sample stays covered ─────────────────────────────────


def _ids(path):
    return [
        ln.split("#", 1)[0].strip()
        for ln in path.read_text(encoding="utf-8").splitlines()
    ]


@pytest.mark.parametrize("type_", ["quest", "gossip"])
def test_the_shadowglen_sample_is_fully_covered(root, type_):
    """Every shipped field of the Shadowglen sample that holds a kanji has a current reading. A retranslation of
    one of these lines that forgets its readings fails here (stale readings only print in validate)."""
    import re

    data = root / "data"
    wanted = {
        i if type_ == "gossip" else int(i)
        for i in _ids(root / f"tests/fixtures/readings/shadowglen-{type_}.ids")
        if i
    }
    japanese = readings.shipped_japanese(Store(data).load(type_))
    current = {
        (r["id"], r["field"])
        for r in readings.check(type_, Store(data / "reading").load(type_), japanese)[
            "current"
        ]
    }
    kanji = re.compile(r"[㐀-䶿一-鿿々]")
    missing = sorted(
        (str(i), f)
        for (i, f), ja in japanese.items()
        if i in wanted and kanji.search(ja) and (i, f) not in current
    )
    assert missing == []
    assert len(wanted) == (18 if type_ == "quest" else 12)


def test_export_lowercases_gossip_keys_and_warns_on_unknown_ids(data, tmp_path, capsys):
    ids = tmp_path / "g.ids"
    ids.write_text("DB152BCD2F85B3F0\n0000000000000000\n")
    out = tmp_path / "g.jsonl"
    assert (
        cmd.run(["export", "--type", "gossip", "--ids", str(ids), "--out", str(out)])
        == 0
    )
    assert [
        json.loads(x)["id"] for x in out.read_text(encoding="utf-8").splitlines()
    ] == [GOSSIP_KEY]
    assert (
        "warning: gossip 0000000000000000 has no shipped Japanese"
        in capsys.readouterr().out
    )


# ── a wrong reading is fixed as a correction ───────────────────


def test_correction_mode_writes_a_correction_that_names_what_it_corrects(data, tmp_path):
    Store(data / "reading").save("quest", [_rec(words=[["私", "わたくし"]] + WORDS[1:])])
    argv = ["import", str(_batch(tmp_path, [_row()])), "--correction", "--by", "reviewer",
            "--date", "2026-09-25", "--note", "私 is わたし here"]
    assert cmd.run(argv) == 0
    [rec] = Store(data / "reading").load("quest")
    assert rec["words"] == WORDS
    assert rec["provenance"] == {
        "class": "correction",
        "translator": "reviewer",
        "source": "correction@2026-09-25",
        "imported": "2026-09-25",
        "note": "私 is わたし here",
        "corrects": "readings@test-batch",
    }
    assert readings.check("quest", [rec], {(456, "description"): JA})["problems"] == []


def test_correction_mode_rejects_a_line_with_no_reading_yet(data, tmp_path, capsys):
    argv = ["import", str(_batch(tmp_path, [_row()])), "--correction", "--by", "reviewer"]
    assert cmd.run(argv) == 1
    assert "no reading to correct" in capsys.readouterr().out
    assert Store(data / "reading").load("quest") == []


def test_correction_mode_needs_by(data, tmp_path):
    with pytest.raises(SystemExit, match="--by"):
        cmd.run(["import", str(_batch(tmp_path, [_row()])), "--correction"])


def test_validate_lists_the_lines_still_owed_a_reading(data, capsys):
    # a kanji line with no reading is listed; a colour-coded one is marked as the known exception
    from wfj.cmd import validate

    Store(data).save(
        "quest",
        [_line(456, "description", JA), _line(456, "title", "|cffff0000赤|rい石"), _line(457, "title", "はい")],
    )
    Store(data / "reading").save("quest", [_rec()])
    validate.rule_readings(Store(data))
    out = capsys.readouterr().out
    assert "validate: readings: 1 quest lines hold an escape sequence (no readings)" in out
    # the escape line is not owed; 457's kana-only title is (its kana words carry meanings)
    assert "validate: readings: 1 quest lines with words to annotate have none: 457/title" in out
    import shutil

    shutil.rmtree(data / "reading" / "quest")
    validate.rule_readings(Store(data))
    assert (
        "validate: readings: 2 quest lines with words to annotate have none: 456/description, 457/title"
        in capsys.readouterr().out
    )


def test_a_stale_correction_does_not_block_a_new_reading(data, tmp_path):
    # a correction written for older Japanese protects nothing once the line changed
    stale = readings.record(456, "description", "昔の文。", [["昔", "むかし"], ["文", "ぶん"]], dict(CORRECTION))
    Store(data / "reading").save("quest", [stale])
    assert _import(_batch(tmp_path, [_row()])) == 0
    assert Store(data / "reading").load("quest") == [_rec()]


# ── readings-flow cleanups ─────────────────────────────────────────


def test_words_for_a_non_shipped_variant_get_their_own_reason(data, tmp_path, capsys):
    line = _line(456, "description", JA)
    line["conflicts"] = [{"ja": "森の話だ。", "provenance": dict(MACHINE)}]
    Store(data).save("quest", [line, _line(456, "title", "自然界のバランス")])
    row = _row(words=[["森", "もり"], ["話", "はなし"]], ja="森の話だ。")
    assert _import(_batch(tmp_path, [row])) == 1
    assert "written for a variant that does not ship" in capsys.readouterr().out


def test_a_second_same_day_correction_keeps_what_the_first_corrected(data, tmp_path):
    first = _rec(words=[["私", "わたくし"]] + WORDS[1:], prov=CORRECTION)  # corrects readings@test-batch
    Store(data / "reading").save("quest", [first])
    argv = ["import", str(_batch(tmp_path, [_row()])), "--correction", "--by", "reviewer", "--date", "2026-09-25"]
    assert cmd.run(argv) == 0
    [rec] = Store(data / "reading").load("quest")
    assert rec["provenance"]["corrects"] == "readings@test-batch"


# ── the corpus rollout: English in the batch, nothing-to-annotate lines, the ui type ─────────────


def _english(d, type_, id_, field, en):
    Store(d, english=True).save(
        type_, [{"id": id_, "field": field, "en": en, "hash": "0123456789abcdef", "src": "wdb@1.60.1.69913"}]
    )


def _export(tmp_path, type_, ids_text):
    ids = tmp_path / f"{type_}.ids"
    ids.write_text(ids_text)
    out = tmp_path / f"{type_}.out.jsonl"
    assert cmd.run(["export", "--type", type_, "--ids", str(ids), "--all", "--out", str(out)]) == 0
    return [json.loads(x) for x in out.read_text(encoding="utf-8").splitlines()]


def test_export_carries_the_lines_english_when_it_has_one(data, tmp_path):
    # `en` is the line's current English, and absent for a line without one
    _english(data, "quest", 456, "description", "I helped a little in the forest.")
    rows = _export(tmp_path, "quest", "456\n")
    by_field = {r["field"]: r for r in rows}
    assert by_field["description"]["en"] == "I helped a little in the forest."
    assert "en" not in by_field["title"]


def test_import_ignores_the_english_column(data, tmp_path):
    # a row with `en` imports exactly as the same row without it
    with_en = _row() | {"en": "I helped a little in the forest."}
    assert _import(_batch(tmp_path, [with_en])) == 0
    assert Store(data / "reading").load("quest") == [_rec()]


def test_export_leaves_out_lines_with_nothing_to_annotate(data, tmp_path):
    # an English-only title has no word; a kana-only line keeps its place (kana words carry meanings)
    Store(data).save(
        "quest",
        [
            _line(456, "description", JA),
            _line(456, "title", "Dolanaar Delivery"),
            _line(457, "title", "ありがとう"),
        ],
    )
    rows = _export(tmp_path, "quest", "456\n457\n")
    assert [(r["id"], r["field"]) for r in rows] == [(456, "description"), (457, "title")]
    assert readings.annotatable("ありがとう") and readings.annotatable("森")
    assert not readings.annotatable("Dolanaar Delivery") and not readings.annotatable("%d/%d")


def test_export_leaves_out_lines_holding_an_escape_sequence(data, tmp_path):
    # the reading box refuses a line with a colour code or `|n`, so such a line is never exported for words
    Store(data).save("ui", [_line("PLAIN", "text", "報酬を選択"), _line("COLOURED", "text", "|cffff0000報酬|r"),
                            _line("BROKEN", "text", "報酬を|n選択")])
    rows = _export(tmp_path, "ui", "PLAIN\nCOLOURED\nBROKEN\n")
    assert [r["id"] for r in rows] == ["PLAIN"]


def test_validate_prints_the_words_without_a_meaning(data, capsys):
    # a 2-item word is counted per type until a batch gives it a meaning
    from wfj.cmd import validate

    Store(data / "reading").save("quest", [_rec()])
    validate.rule_readings(Store(data))
    assert "validate: readings: 6 quest words have no meaning" in capsys.readouterr().out
    meant = [w + [w[0] if w[0] != "手伝った" else "手伝う", w[1] if w[0] != "手伝った" else "てつだう", "x"]
             for w in WORDS]
    Store(data / "reading").save("quest", [_rec(words=meant)])
    validate.rule_readings(Store(data))
    assert "quest words have no meaning" not in capsys.readouterr().out


UI_JA = "以下の報酬から1つ選択できます:"
UI_WORDS = [
    ["以下", "いか", "以下", "いか", "the following"],
    ["報酬", "ほうしゅう", "報酬", "ほうしゅう", "rewards"],
    ["選択できます", "せんたくできます", "選択する", "せんたくする", "can choose"],
]


def test_ui_readings_import_validate_and_generate(data, tmp_path, capsys):
    # a ui record keyed by its UI string key goes through the batch path and generates a ui:<KEY> row
    from wfj.cmd import validate

    Store(data).save("ui", [_line("REWARD_CHOICES", "text", UI_JA)])
    rows = _export(tmp_path, "ui", "REWARD_CHOICES\n")
    assert [(r["type"], r["id"], r["field"]) for r in rows] == [("ui", "REWARD_CHOICES", "text")]
    row = rows[0] | {"words": UI_WORDS}
    assert _import(_batch(tmp_path, [row])) == 0
    assert [r["id"] for r in Store(data / "reading").load("ui")] == ["REWARD_CHOICES"]
    assert (data / "reading" / "ui" / "ui-R.jsonl").is_file()
    assert validate.rule_readings(Store(data)) == []
    assert "validate: readings: 1 of 1 shipped ui lines have one" in capsys.readouterr().out
    text = generate.plan(Store(data), [])[schema.reading_relpath("ui", "R")]
    assert '["ui:REWARD_CHOICES"] = { text = "以下=いか=' in text


def test_a_bad_ui_key_is_refused():
    rec = readings.record("not a key!", "text", UI_JA, UI_WORDS, dict(MACHINE))
    assert "ui id must be a UI string key" in readings.record_problems("ui", rec)
    good = readings.record("REWARD_CHOICES", "text", UI_JA, UI_WORDS, dict(MACHINE))
    assert readings.record_problems("ui", good) == []


def _non_window(root):
    import re

    src = (root / "addon/WoWForeverJapanese/UI/Readings.lua").read_text(encoding="utf-8")
    body = src[src.index("View.NON_WINDOW = {") : src.index("}", src.index("View.NON_WINDOW = {"))]
    return set(re.findall(r'\["([a-z.]+)"\] = true', body)) | set(re.findall(r"\b([a-z]+) = true", body))


def test_every_non_window_surface_is_one_the_addon_registers(root):
    """Each NON_WINDOW entry names a surface some UI module uses: a literal ("tracker",
    "help.tips") or a module's `SURFACE` constant plus a literal suffix (MicroMenu's `SURFACE .. ".xpbar"`),
    so the list cannot rot into names that match nothing. Every other surface is a window by rule."""
    import re

    names = _non_window(root)
    assert {"tracker", "errors", "combattext", "zonetext", "alerts", "unitframes", "help"} <= names
    ui = {p.name: p.read_text(encoding="utf-8") for p in (root / "addon/WoWForeverJapanese/UI").glob("*.lua")}
    literals = {m for text in ui.values() for m in re.findall(r'"([a-z][a-z0-9]*(?:\.[a-z0-9]+)*)"', text)}
    composed = set()
    for text in ui.values():
        base = re.search(r'^local SURFACE = "([a-z.]+)"', text, re.M)
        if base:
            composed |= {base.group(1) + s for s in re.findall(r'SURFACE \.\. "(\.[a-z0-9]+)"', text)}
    missing = sorted(n for n in names if n not in literals and n not in composed)
    assert missing == []


# Every surface the addon registers is classified: a window (word cards allowed on its
# plain-text labels) or non-window (UI/Readings NON_WINDOW, a surface naming "tooltip", or one UI/TooltipLines
# follows). A new surface fails here until someone puts it in WINDOW_SURFACES or NON_WINDOW. Surfaces built at run
# time from a variable (a module's `surface` parameter, UI/Tooltip's "tooltip.<frame>") are not resolvable here; the
# "tooltip" rule and the prose surfaces cover the ones that exist today.
WINDOW_SURFACES = frozenset({
    # surfaces named through LabelTree.show, Kit.new and the `show` alias
    "communities.applicants", "communities.benefits", "communities.clubfinder", "communities.dialogs",
    "communities.frame", "scripterrors", "splash",
    "achievement", "addonlist", "addonlist.static", "auctionhouse", "bags", "bank", "bank.static",
    "barbershop", "battlefieldmap", "blackmarket", "blackmarket.static", "calendar", "channels", "character",
    "character.static", "character.title", "chatconfig", "chatconfig.static", "chromietime", "cinematic",
    "clickbinding", "coinpickup", "collections", "colorpicker", "communities", "communities.benefits.log",
    "communities.static", "crafting", "currency", "dialogueui.book", "currencytransfer", "customerorders", "deathrecap",
    "dressup", "dressup.side", "dressup.slots", "equipmentflyout", "eventtrace", "eventtrace.rows",
    "eventtrace.static", "flightmap", "flightmap.static", "friends", "friends.social", "friends.static", "gamemenu",
    "gamepadedit", "gossip.chrome", "gossip.chrome.static", "groupfinder", "grouploot", "guildbank",
    "guildcontrol", "guildinvite", "guildregistrar", "guildrename", "helpframe", "inspect", "instanceabandon",
    "iteminteraction", "itemsocketing", "itemsocketing.static", "itemupgrade", "legacy", "statistics", "loot",
    "loothistory", "macro", "mail", "mail.static", "maplegend", "merchant", "merchant.static", "mountjournal",
    "obliterumforge.static", "partypose", "petition", "petjournal", "playerchoice", "playerchoice.options",
    "playerspells", "popups", "professions", "professions.book", "pvpmatch", "pvprank", "questframe.greeting",
    "questframe.reputation", "questframe.spellheaders", "questframe.timer", "questmap.list", "questmap.storytip", "questmap.title", "quickjoin",
    "quickkeybind", "raid", "raid.static", "raidmanager", "readycheck", "recruitafriend", "reportframe",
    "recentallies", "reputation", "reputation.static", "scrappingmachine.static", "settingspanel", "settingspanel.static",
    "settingstutorials", "skills", "spellbook.static", "spellsearch", "stable", "stacksplit",
    "subscriptioninterstitial", "tabard", "talents.static", "taxi", "texttospeech", "texttospeech.static",
    "timemanager", "trade", "trainer", "trainer.static", "transmog", "tutorial", "wardrobe", "worldmap",
    # the surfaces a window's names are shown under, beside its dictionary words
    "currency.names", "grouploot.items", "obliterumforge", "questframe.items", "questframe.npc", "questmap.items",
    "scrappingmachine", "talents.trees", "wardrobe.names",
    "worldmap.static",
})

# Every form that hands a surface to Labels / Render: the Labels functions, UI/LabelTree, the Communities kit, Render,
# UI/TooltipLines, and a module's `local show = WFJ.Labels.show` alias (matched only where the alias is declared).
_SURFACE_CALL = re.compile(
    r"(?:Labels\.(?:show|showAll|title|dropdown|showArgs)|LabelTree\.show|Kit\.new|Render\.show|"
    r"TooltipLines\.follow)\(\s*([^,)]+)"
)
_SHOW_ALIAS = re.compile(r"^\s*local show = WFJ\.Labels\.show\s*$", re.M)
_ALIAS_CALL = re.compile(r"(?<![\w.:])show\(\s*([^,)]+)")
_SURFACE_NAME = re.compile(r"[a-z][a-z0-9]*(?:\.[a-zA-Z0-9]+)*")


def _resolve(expr, env):
    vals = []
    for x in (p.strip() for p in expr.split("..")):
        if re.fullmatch(r'"[^"]*"', x):
            vals.append(x[1:-1])
        elif x in env:
            vals.append(env[x])
        else:
            return None
    v = "".join(vals)
    return v if _SURFACE_NAME.fullmatch(v) else None


def _registered_surfaces(root, unresolved=None):
    """→ ({surface: [module, …]}, {surfaces UI/TooltipLines.follow is given}); `unresolved` (a list) collects
    the call sites whose surface is a variable (module:expression)"""
    found, followed = {}, set()
    for path in sorted((root / "addon/WoWForeverJapanese/UI").glob("*.lua")):
        src = path.read_text(encoding="utf-8")
        env = {}
        for _ in range(4):  # constants built from other constants (`SURFACE .. ".static"`)
            for m in re.finditer(r"^\s*(?:local\s+)?([A-Za-z_][\w.]*)\s*=\s*(.+?)\s*(?:--.*)?$", src, re.M):
                v = _resolve(m.group(2), env)
                if v:
                    env[m.group(1)] = v
        calls = list(_SURFACE_CALL.finditer(src))
        if _SHOW_ALIAS.search(src):
            calls += list(_ALIAS_CALL.finditer(src))
        for m in calls:
            v = _resolve(m.group(1), env)
            if v:
                found.setdefault(v, []).append(path.name)
                if m.group(0).startswith("TooltipLines"):
                    followed.add(v)
            elif unresolved is not None:
                unresolved.append(f"{path.name}:{m.group(1).strip()}")
    return found, followed


def _non_window_rule(names, followed):
    def non_window(surface):
        if surface in followed or "tooltip" in surface:
            return True
        parts = surface.split(".")
        return any(".".join(parts[: i + 1]) in names for i in range(len(parts)))

    return non_window


def test_every_registered_surface_is_classified(root):
    found, followed = _registered_surfaces(root)
    non_window = _non_window_rule(_non_window(root), followed)
    assert len(found) > 150  # the resolver still sees the modules
    unclassified = sorted(s for s in found if not non_window(s) and s not in WINDOW_SURFACES)
    assert unclassified == [], "classify each: WINDOW_SURFACES here, or NON_WINDOW in UI/Readings.lua"
    both = sorted(s for s in WINDOW_SURFACES if non_window(s))
    assert both == []
    gone = sorted(WINDOW_SURFACES - set(found))
    assert gone == [], "surfaces no module registers any more"


# The call sites whose surface is a variable (a module's `surface` parameter, a pane's field): the classifier cannot
# read them. Each is reviewed: they pass a surface named elsewhere (QuestFrame / QuestMap panes, the Communities kit,
# Collections paging, DamageMeter sessions, the help tooltip lines Calendar, MapPins and QuestMap's title tooltip write, the gossip and book prose surfaces, UI/Tooltip's
# "tooltip.<frame>", Labels / LabelTree / Render / TooltipLines internals). A NEW one fails here: resolve it to a literal or constant, or review it and add it to this list.
REVIEWED_VARIABLE_SURFACES = frozenset({
    "Calendar.lua:help.SURFACE",
    # a time in a help tooltip's right column: UI/HelpTooltip passes its own surface to the owner's `show`
    "Calendar.lua:surface",
    "TimeManager.lua:surface",
    "Character.lua:surface",  # a stat tooltip's composite line: the same `show` of UI/HelpTooltip's own surface
    "MapPins.lua:help.SURFACE",
    "Collections.lua:surface",
    "CommunitiesKit.lua:surface",
    "DamageMeter.lua:surface",
    "GroupFinder.lua:surface",  # a finder menu's entries: UI/Menus passes its own surface, classified there
    "NameLabels.lua:surface",  # the helper for a name on a widget: each caller passes its own, classified here
    "DialogueUI.lua:S.title",  # Dialogue UI's quest title: its quest window's surfaces, read from its S table
    "DialogueUI.lua:el.surface",
    "Gossip.lua:SURFACE",
    "IconPicker.lua:how.surface",  # the name-and-icon popup: each owner window names its own surface
    "IconPicker.lua:surface",
    "ItemText.lua:SURFACE",
    "LabelTree.lua:f.surface",
    "LabelTree.lua:surface",
    "Labels.lua:surface",
    "QuestFrame.lua:panel.surface",
    "QuestMap.lua:help.SURFACE",
    "QuestMap.lua:pane.info",
    "QuestMap.lua:pane.surface",
    "QuestMap.lua:surface",
    "Render.lua:surface",
    "Tooltip.lua:surface",
    "TooltipLines.lua:f.surface",
    "TooltipLines.lua:surface",
})


def test_no_new_surface_named_by_a_variable(root):
    """A module that names its surface through a variable cannot hide from the
    classification above."""
    unresolved: list[str] = []
    _registered_surfaces(root, unresolved)
    assert sorted(set(unresolved) - REVIEWED_VARIABLE_SURFACES) == []


def test_tooltip_line_surfaces_are_never_windows(root):
    """The surfaces whose labels are GameTooltip lines under a name without "tooltip"."""
    found, followed = _registered_surfaces(root)
    non_window = _non_window_rule(_non_window(root), followed)
    for s in ("quickjoin.tip", "deathrecap.tip", "communities.benefits.rewardtip", "auctionhouse.token", "gamepad",
              "recruitafriend.activity"):
        assert s in found and non_window(s), s
    assert non_window("questmap.trackerlabels")  # the tracker headers (a table-driven call, not resolvable here)


@pytest.mark.parametrize(
    "ja, expected",
    [
        ("TyrandeとRemulos", False),  # names joined by a particle
        ("%sの%s", False),
        ("Soulgrinder へ", False),
        ("Icebane Breastplateだ。", False),
        ("え？", True),  # an interjection is a word
        ("ありがとう", True),
        ("森", True),
        ("Dolanaar Delivery", False),
    ],
)
def test_annotatable_ignores_bare_particles(ja, expected):
    assert readings.annotatable(ja) is expected


def test_a_ui_key_with_a_trailing_newline_is_refused():
    # the key pattern must match the whole id
    rec = readings.record("REWARD_CHOICES\n", "text", UI_JA, UI_WORDS, dict(MACHINE))
    assert "ui id must be a UI string key" in readings.record_problems("ui", rec)


BOOK_JA = "この悪魔の鎧は古い。"
BOOK_WORDS = [
    ["悪魔", "あくま", "悪魔", "あくま", "demon"],
    ["鎧", "よろい", "鎧", "よろい", "plates (armor)"],
    ["古い", "ふるい", "古い", "ふるい", "old"],
]


def _book(id_, ja, en_hash, status="trusted"):
    return _line(id_, "text", ja, status) | {"english": {"hash": en_hash, "src": "vmangos@13b49dc"}}


def test_book_readings_import_validate_and_generate_under_the_english_hash(data, tmp_path, capsys):
    # a book record keyed by page id goes through the batch path; the generated row is keyed by the
    # page's English hash (the addon finds a page by its live English), in the shard of that hash
    from wfj.cmd import validate

    Store(data).save("book", [_book(12, BOOK_JA, "ab12cd34ef567890")])
    rows = _export(tmp_path, "book", "12\n")
    assert [(r["type"], r["id"], r["field"]) for r in rows] == [("book", 12, "text")]
    assert _import(_batch(tmp_path, [rows[0] | {"words": BOOK_WORDS}])) == 0
    assert [r["id"] for r in Store(data / "reading").load("book")] == [12]
    assert validate.rule_readings(Store(data)) == []
    assert "validate: readings: 1 of 1 shipped book lines have one" in capsys.readouterr().out
    planned = generate.plan(Store(data), [])
    text = planned[schema.reading_relpath("book", "ab")]
    assert '["book:ab12cd34ef567890"] = { text = "悪魔=あくま=' in text
    assert not any("book:12" in v for k, v in planned.items() if k.startswith("Data/Reading/"))


def test_book_pages_sharing_one_english_ship_the_lowest_pages_reading(data, tmp_path):
    # two pages with one English share one Japanese row (lua_writer.keyed_rows, the lowest page id's
    # text), so only that page's reading ships under the key
    Store(data).save("book", [_book(12, BOOK_JA, "ab12cd34ef567890"), _book(30, BOOK_JA, "ab12cd34ef567890")])
    other = [["鎧", "よろい", "鎧", "よろい", "armor"]]
    rows = [_row(BOOK_WORDS, BOOK_JA, 12, "text", "book"), _row(other, BOOK_JA, 30, "text", "book")]
    assert _import(_batch(tmp_path, rows)) == 0
    text = generate.plan(Store(data), [])[schema.reading_relpath("book", "ab")]
    assert text.count('["book:ab12cd34ef567890"]') == 1
    assert "悪魔=あくま=" in text


def test_a_book_reading_for_a_page_with_no_japanese_is_refused(data, tmp_path, capsys):
    # the page must ship Japanese
    assert _import(_batch(tmp_path, [_row(BOOK_WORDS, BOOK_JA, 99, "text", "book")])) == 1
    assert "no shipped Japanese" in capsys.readouterr().out


def test_an_html_book_page_is_never_exported_or_owed(data, tmp_path, capsys):
    # an HTML page keeps the client's SimpleHTML, which cannot place a word card
    from wfj.cmd import validate

    html = "<HTML><BODY><P>この悪魔の鎧は古い。</P></BODY></HTML>"
    Store(data).save("book", [_book(12, BOOK_JA, "ab12cd34ef567890"), _book(13, html, "cd12cd34ef567890")])
    assert [r["id"] for r in _export(tmp_path, "book", "12\n13\n")] == [12]
    assert readings.html_page("book", html) and not readings.html_page("quest", html)
    validate.rule_readings(Store(data))
    out = capsys.readouterr().out
    assert "1 book lines with words to annotate have none: 12/text" in out


def test_a_reading_for_an_html_book_page_is_refused(data, tmp_path, capsys):
    # an HTML page keeps the SimpleHTML and never shows a card, so a reading for it is refused
    html = "<HTML><BODY><P>この悪魔の鎧は古い。</P></BODY></HTML>"
    Store(data).save("book", [_book(13, html, "cd12cd34ef567890")])
    assert _import(_batch(tmp_path, [_row(BOOK_WORDS, html, 13, "text", "book")])) == 0
    result = readings.check("book", Store(data / "reading").load("book"), {(13, "text"): html})
    assert result["current"] == [] and "an HTML book page takes no reading" in result["problems"][0]


JOKE = "分かるか? 冗談だよ。わしのつまらん冗談を聞きに来たわけじゃない。"
JOKE_CARD = ["冗談", "じょうだん", "冗談", "じょうだん", "joke"]


def test_a_word_used_twice_with_one_entry_is_found_at_its_second_place():
    words = [["分かる", "わかる", "分かる", "わかる", "get it"], JOKE_CARD, ["聞きに来た", "ききにきた", "聞きに来る", "ききにくる", "came to hear"]]
    assert readings.uncovered_repeats(JOKE, words) == ["冗談"]


def test_fill_repeats_copies_the_card_to_every_place_in_text_order():
    words = [["分かる", "わかる", "分かる", "わかる", "get it"], JOKE_CARD, ["聞きに来た", "ききにきた", "聞きに来る", "ききにくる", "came to hear"]]
    filled = readings.fill_repeats(JOKE, words)
    assert [w[0] for w in filled] == ["分かる", "冗談", "冗談", "聞きに来た"]
    assert filled[2] == JOKE_CARD
    assert readings.uncovered_repeats(JOKE, filled) == [] and readings.word_problems(JOKE, filled) == []
    assert words[1] == JOKE_CARD and len(words) == 3  # the input list is not changed


def test_a_repeat_inside_another_card_needs_no_card_of_its_own():
    ja = "冗談話をした。冗談だ。"
    words = [["冗談話", "じょうだんばなし", "冗談話", "じょうだんばなし", "a joke"], JOKE_CARD]
    assert readings.uncovered_repeats(ja, words) == []
    assert readings.fill_repeats(ja, words) == words


def test_check_reports_a_reading_that_misses_a_repeat():
    """`validate` fails on it: a build cannot ship a word whose second place has no card."""
    result = _check([_rec(ja=JOKE, words=[JOKE_CARD])], japanese={(456, "description"): JOKE})
    assert result["problems"] == ["reading quest 456/description: '冗談' stands again with no card (wfj readings fill-repeats)"]


# ── tooltip text (item, spell) ───────────────────────────────────────────────

TIP_JA = "ホームに設定した場所へ戻ります。"
TIP_WORDS = [["設定した", "せっていした"], ["場所", "ばしょ"], ["戻ります", "もどります"]]


def _machine_line(id_, field, ja):
    return _line(id_, field, ja) | {"provenance": {"class": "machine", "model": "m", "source": "draft-x@2026-09-18",
                                                   "imported": "2026-09-18"}}


@pytest.fixture
def tips(data):
    Store(data).save("item", [_machine_line(6948, "description", TIP_JA), _machine_line(7, "description", "森の木の枝。"),
                              _machine_line(8, "description", "|cffffd100森|rの石。")])
    Store(data).save("spell", [_machine_line(8690, "description", TIP_JA), _machine_line(8690, "aura", "場所を覚えている。")])
    return data


def test_item_and_spell_text_take_readings():
    assert readings.TYPES["item"] == ["description"] and readings.TYPES["spell"] == ["description", "aura"]
    rec = readings.record(6948, "description", TIP_JA, TIP_WORDS, dict(MACHINE))
    assert readings.check("item", [rec], {(6948, "description"): TIP_JA})["current"] == [rec]
    aura = readings.record(8690, "aura", "場所を覚えている。", [["場所", "ばしょ"], ["覚えている", "おぼえている"]], dict(MACHINE))
    assert readings.check("spell", [aura], {(8690, "aura"): "場所を覚えている。"})["current"] == [aura]
    assert "objective" not in readings.TYPES and "area" not in readings.TYPES


def test_words_written_from_the_stored_text_hold_for_the_text_the_addon_ships():
    # a hand-written line keeps its manual break in data; generate ships it joined. The words are checked against
    # the stored text, and the same words stand in the same order in the shipped one.
    from wfj.core import tooltip_text

    stored = "ホームに設定した場所へ\n戻ります。"
    line = _line(6948, "description", stored)  # human provenance: its breaks are joined
    assert readings.word_problems(stored, TIP_WORDS) == []
    shipped = tooltip_text.shipped_ja(line, "Returns you to your home.")
    assert "\n" not in shipped
    assert readings.word_problems(shipped, TIP_WORDS) == []


# A tooltip line is drafted a sentence at a time. Two sentences that differ only by an English name or by which
# number a placeholder stands for are one piece: neither a name nor a placeholder is ever a word.

LEARN = "Elixir of Minor Fortitudeの作り方を習得します。"
LEARN_WORDS = [["作り方", "つくりかた"], ["習得します", "しゅうとくします"]]
LAST = "効果時間は$D1です。"
LAST_WORDS = [["効果時間", "こうかじかん"]]


def _keys(ja):
    return [key for _s, _e, key in readings.pieces(ja)]


def test_a_line_splits_into_sentences_at_full_stops_line_breaks_and_branch_brackets():
    ja = "体力を$N1回復します。食事中は座っている必要があります。\n効果時間は$D1です。"
    assert [ja[s:e] for s, e, _k in readings.pieces(ja)] == [
        "体力を$N1回復します。", "食事中は座っている必要があります。", "効果時間は$D1です。"]
    branch = "筋力が$N4上昇します。$?pc142418[さらに、経験値が$N6%増加します。][]"
    assert [branch[s:e] for s, e, _k in readings.pieces(branch)] == [
        "筋力が$N4上昇します。", "さらに、経験値が$N6%増加します。"]


def test_a_piece_is_the_same_whatever_its_english_names_and_placeholder_numbers():
    assert _keys(LEARN) == _keys("Light Winter Cloakの作り方を習得します。")
    assert _keys("筋力が$N1増加します。") == _keys("筋力が$N4増加します。")
    assert _keys("$D1の間、Frostダメージを与えます。") == _keys("$D2の間、Fireダメージを与えます。")
    # a duration is not a number: the word after it can read differently
    assert _keys("$D1の間") != _keys("$N1の間")
    # a number written out stays: a counter reads by the number before it (3匹 びき, 6匹 ぴき)
    assert _keys("3匹の狼を倒す。") != _keys("6匹の狼を倒す。")
    assert _keys("森の木。") != _keys("森の石。")


def test_the_words_of_a_line_fall_into_its_pieces_by_where_they_stand():
    ja = LEARN + LAST
    words = LEARN_WORDS + LAST_WORDS
    by_piece = readings.piece_words(ja, words)
    assert by_piece == {_keys(LEARN)[0]: LEARN_WORDS, _keys(LAST)[0]: LAST_WORDS}
    # a piece with nothing listed is known too: it is in the line, and its list is empty
    assert readings.piece_words("Frost Nova。" + LAST, LAST_WORDS) == {
        _keys("Frost Nova。")[0]: [], _keys(LAST)[0]: LAST_WORDS}
    # words that do not stand in the line in order give nothing
    assert readings.piece_words(ja, [["海", "うみ"]]) is None


def test_a_line_is_put_together_from_pieces_already_written():
    index = readings.piece_words(LEARN + LAST, LEARN_WORDS + LAST_WORDS)
    other = "Light Winter Cloakの作り方を習得します。\n効果時間は$D2です。"
    assert readings.assemble(other, index) == LEARN_WORDS + LAST_WORDS
    assert readings.word_problems(other, readings.assemble(other, index)) == []
    # one sentence nobody has written: the line waits
    assert readings.assemble(LEARN + "森を守ります。", index) is None
    # a piece with nothing to annotate needs no entry
    assert readings.assemble("Frost Nova\n" + LAST, index) == LAST_WORDS


@pytest.fixture
def sentences(data):
    Store(data).save("item", [
        _machine_line(1, "description", LEARN),
        _machine_line(2, "description", "Light Winter Cloakの作り方を習得します。"),
        _machine_line(3, "description", "Light Winter Cloakの作り方を習得します。\n" + LAST),
        _machine_line(4, "description", "|cffffd100森|rの石。"),
    ])
    Store(data).save("spell", [
        _machine_line(10, "description", "効果時間は$D2です。"),
        _machine_line(10, "aura", "森を守ります。" + LAST),
    ])
    return data


def _export_tips(tmp_path, *extra):
    out = tmp_path / "tips.jsonl"
    assert cmd.run(["export-tooltips", "--out", str(out), *extra]) == 0
    return [json.loads(x) for x in out.read_text(encoding="utf-8").splitlines()]


def _piece_row(ja, words):
    return {"type": "piece", "id": readings.piece_id(ja), "field": "text", "ja": ja,
            "ja_hash": readings.ja_hash(ja), "words": words}


def _import_tips(batch, *extra):
    return cmd.run(["import-tooltips", str(batch), "--model", "reading-model-1", "--batch", "test-batch",
                    "--date", "2026-09-25", *extra])


def test_tooltip_export_writes_each_sentence_nobody_has_written_once(sentences, tmp_path, capsys):
    rows = _export_tips(tmp_path)
    # five lines, three sentences: the recipe line (two names), the duration line, the forest line
    assert [r["ja"] for r in rows] == [LEARN, LAST, "森を守ります。"]
    assert all(r["type"] == "piece" and r["field"] == "text" for r in rows)
    assert rows[0]["id"] == readings.piece_id(LEARN) and rows[0]["ja_hash"] == readings.ja_hash(LEARN)
    assert rows[0]["line"] == "item 1/description" and rows[1]["line"] == "item 3/description"
    printed = capsys.readouterr().out
    assert "3 sentences for 5 lines" in printed and "6 shipped" in printed
    assert "item 4/description: holds an escape sequence" in printed


def test_tooltip_import_builds_every_line_from_its_sentences(sentences, tmp_path, capsys):
    rows = [_piece_row(LEARN, LEARN_WORDS), _piece_row(LAST, LAST_WORDS)]
    assert _import_tips(_batch(tmp_path, rows)) == 0
    item = {(r["id"], r["field"]): r for r in Store(sentences / "reading").load("item")}
    spell = {(r["id"], r["field"]): r for r in Store(sentences / "reading").load("spell")}
    assert item[(1, "description")]["words"] == LEARN_WORDS
    assert item[(2, "description")]["words"] == LEARN_WORDS  # another name, the same sentence
    assert item[(3, "description")]["words"] == LEARN_WORDS + LAST_WORDS
    assert spell[(10, "description")]["words"] == LAST_WORDS  # another placeholder number
    assert (10, "aura") not in spell  # its first sentence is not written yet
    assert item[(3, "description")]["provenance"]["source"] == "readings@test-batch"
    assert item[(3, "description")]["ja_hash"] == readings.ja_hash("Light Winter Cloakの作り方を習得します。\n" + LAST)
    assert "4 lines" in capsys.readouterr().out
    # what is left to draft is the one sentence, once
    assert [r["ja"] for r in _export_tips(tmp_path)] == ["森を守ります。"]


def test_tooltip_import_rejects_a_bad_sentence_and_its_lines_wait(sentences, tmp_path, capsys):
    rows = [_piece_row(LEARN, [["海", "うみ"]]), _piece_row(LAST, LAST_WORDS),
            {**_piece_row(LAST, LAST_WORDS), "ja_hash": "0" * 16}, {"type": "item", "id": 1}]
    assert _import_tips(_batch(tmp_path, rows)) == 1
    printed = capsys.readouterr().out
    assert "rejected row 1" in printed and "rejected row 3" in printed and "rejected row 4" in printed
    item = {(r["id"], r["field"]): r for r in Store(sentences / "reading").load("item")}
    assert set(item) == set()  # every item line holds the recipe sentence
    assert Store(sentences / "reading").load("spell")[0]["words"] == LAST_WORDS


def test_tooltip_import_dry_run_writes_nothing(sentences, tmp_path, capsys):
    assert _import_tips(_batch(tmp_path, [_piece_row(LEARN, LEARN_WORDS)]), "--dry-run") == 0
    assert Store(sentences / "reading").load("item") == []
    assert "rejected 0" in capsys.readouterr().out


def test_a_new_tooltip_made_of_written_sentences_needs_no_drafting(sentences, tmp_path, capsys):
    rows = [_piece_row(LEARN, LEARN_WORDS), _piece_row(LAST, LAST_WORDS)]
    assert _import_tips(_batch(tmp_path, rows)) == 0
    Store(sentences).save("item", [*Store(sentences).load("item"),
                                   _machine_line(5, "description", "Runed Copper Rodの作り方を習得します。効果時間は$D3です。"),
                                   _machine_line(6, "description", "海を渡ります。" + LAST)])
    capsys.readouterr()
    assert cmd.run(["spread", "--dry-run"]) == 0
    assert 5 not in {r["id"] for r in Store(sentences / "reading").load("item")}
    assert cmd.run(["spread"]) == 0
    item = {r["id"]: r for r in Store(sentences / "reading").load("item")}
    assert item[5]["words"] == LEARN_WORDS + LAST_WORDS
    assert 6 not in item  # one sentence is new: it is exported, the rest of the line is not
    assert "1 line" in capsys.readouterr().out
    assert [r["ja"] for r in _export_tips(tmp_path)] == ["海を渡ります。", "森を守ります。"]


def test_a_whole_line_import_feeds_the_sentences_too(sentences, tmp_path):
    whole = "Light Winter Cloakの作り方を習得します。\n" + LAST
    row = _row(words=LEARN_WORDS + LAST_WORDS, ja=whole, id_=3, type_="item")
    assert _import(_batch(tmp_path, [row])) == 0
    item = {(r["id"], r["field"]): r for r in Store(sentences / "reading").load("item")}
    assert item[(1, "description")]["words"] == LEARN_WORDS and item[(2, "description")]["words"] == LEARN_WORDS
    assert Store(sentences / "reading").load("spell")[0]["words"] == LAST_WORDS


def test_a_line_with_its_own_reading_is_left_alone_and_a_correction_is_kept(sentences, tmp_path):
    fixed = [["作り方", "つくりかた"], ["習得します", "しゅうとく"]]
    Store(sentences / "reading").save("item", [readings.record(2, "description",
                                                               "Light Winter Cloakの作り方を習得します。", fixed,
                                                               dict(CORRECTION))])
    assert _import_tips(_batch(tmp_path, [_piece_row(LEARN, LEARN_WORDS), _piece_row(LAST, LAST_WORDS)])) == 0
    item = {(r["id"], r["field"]): r for r in Store(sentences / "reading").load("item")}
    assert item[(2, "description")]["words"] == fixed and item[(2, "description")]["provenance"]["class"] == "correction"


def test_a_branch_line_takes_the_words_of_every_bracket(sentences, tmp_path):
    branch = "筋力が$N4上昇します。$?pc142418[さらに、経験値が$N6%増加します。][]"
    Store(sentences).save("item", [_machine_line(7, "description", branch)])
    rows = _export_tips(tmp_path)
    assert [r["ja"] for r in rows][:2] == ["筋力が$N4上昇します。", "さらに、経験値が$N6%増加します。"]
    words = [[["筋力", "きんりょく"], ["上昇します", "じょうしょうします"]],
             [["さらに", "さらに", "さらに", "さらに", "furthermore"], ["経験値", "けいけんち"],
              ["増加します", "ぞうかします"]]]
    batch = _batch(tmp_path, [_piece_row(rows[0]["ja"], words[0]), _piece_row(rows[1]["ja"], words[1])])
    assert _import_tips(batch) == 0
    rec = Store(sentences / "reading").load("item")[0]
    assert rec["words"] == words[0] + words[1]
    assert readings.word_problems(branch, rec["words"]) == []


def _texts(ja):
    return [ja[s:e] for s, e, _k in readings.pieces(ja)]


def test_a_choice_inside_a_sentence_does_not_cut_it():
    # each bracket holds a part of the sentence, not a sentence: the sentence stays whole
    home = "$?pc923[Orgrimmar][Stormwind]へ戻ります。一度だけ使えます。"
    assert _texts(home) == ["$?pc923[Orgrimmar][Stormwind]へ戻ります。", "一度だけ使えます。"]
    level = "筋力を$?$PL<24[少し][大きく]上昇させます。"
    assert _texts(level) == [level]
    assert _keys("$?pc923[Orgrimmar][Stormwind]へ戻ります。") == _keys("$?pc7[Thunder Bluff][Ironforge]へ戻ります。")
    # brackets that hold whole sentences are still cut apart, and the empty one gives nothing
    whole = "筋力が上昇します。$?pc142418[さらに、経験値が増加します。][]"
    assert _texts(whole) == ["筋力が上昇します。", "さらに、経験値が増加します。"]
    # a name in plain brackets is part of its sentence
    assert _texts("[マクブライド元帥の書類]を読みます。") == ["[マクブライド元帥の書類]を読みます。"]


def test_a_mark_inside_brackets_or_quotes_does_not_end_the_sentence():
    assert _texts("強力な一撃（注意！反動あり）を放ちます。次の文。") == ["強力な一撃（注意！反動あり）を放ちます。", "次の文。"]
    assert _texts("「待て！」と叫びます。") == ["「待て！」と叫びます。"]
    assert _texts("本当ですか？はい。") == ["本当ですか？", "はい。"]


def test_a_number_no_counter_follows_is_not_part_of_the_sentence():
    assert _keys("(QuestID:5805)を始めます。") == _keys("(QuestID:5841)を始めます。")
    assert _keys("クエスト：Welcome!(QuestID:5805)を始めます。") == _keys("クエスト：The Collector(QuestID:123)を始めます。")
    assert _keys("確率が10%上昇します。") == _keys("確率が25%上昇します。")
    # a counter or a unit right after the number still counts
    assert _keys("3匹の狼を倒す。") != _keys("6匹の狼を倒す。")
    assert _keys("10分間持続します。") != _keys("3分間持続します。")


QUEST_STORED = "クエスト：The Collector(QuestID:\n123)を始めます。"
QUEST_SHIPPED = "クエスト：The Collector(QuestID:123)を始めます。"
QUEST_WORDS = [["クエスト", "クエスト", "クエスト", "クエスト", "quest"], ["始めます", "はじめます"]]


@pytest.fixture
def wrapped(data):
    """Hand-written lines whose manual breaks fall inside a sentence; their English has no break."""
    Store(data).save("item", [
        _line(1307, "description", QUEST_STORED),
        _line(2794, "description", "クエスト：An Old History Book\n(QuestID:337)を始めます。"),
        _line(10360, "description", "このペットの呼び出し方を\n習得する。"),
    ])
    Store(data, english=True).save("item", [
        {"id": id_, "field": "description", "en": en, "hash": "0123456789abcdef", "src": "db2@1.60.1.70938"}
        for id_, en in ((1307, "Begins the quest The Collector."), (2794, "Begins the quest An Old History Book."),
                        (10360, "Teaches you how to summon this companion."))
    ])
    return data


def test_tooltip_sentences_are_cut_from_the_text_as_it_ships(wrapped, tmp_path):
    rows = _export_tips(tmp_path)
    # the breaks are joined in what ships, so no sentence is cut at one, and the two quest lines are one sentence
    assert [r["ja"] for r in rows] == [QUEST_SHIPPED, "このペットの呼び出し方を習得する。"]
    assert rows[0]["ja_hash"] == readings.ja_hash(QUEST_SHIPPED)
    learn = [["呼び出し方", "よびだしかた"], ["習得する", "しゅうとくする"]]
    batch = _batch(tmp_path, [_piece_row(QUEST_SHIPPED, QUEST_WORDS), _piece_row(rows[1]["ja"], learn)])
    assert _import_tips(batch) == 0
    item = {r["id"]: r for r in Store(wrapped / "reading").load("item")}
    assert item[1307]["words"] == QUEST_WORDS and item[2794]["words"] == QUEST_WORDS
    # a word that stands across the manual break is found: the record is for the shipped text
    assert item[10360]["words"] == learn
    assert item[1307]["ja_hash"] == readings.ja_hash(QUEST_SHIPPED)
    assert item[1307]["ja_hash"] != readings.ja_hash(QUEST_STORED)


def test_a_reading_for_a_hand_wrapped_line_is_current_validates_and_ships(wrapped, tmp_path, capsys):
    learn = [["呼び出し方", "よびだしかた"], ["習得する", "しゅうとくする"]]
    batch = _batch(tmp_path, [_piece_row(QUEST_SHIPPED, QUEST_WORDS),
                              _piece_row("このペットの呼び出し方を習得する。", learn)])
    assert _import_tips(batch) == 0
    capsys.readouterr()
    from wfj.cmd import validate

    assert validate.rule_readings(Store(wrapped)) == []
    printed = capsys.readouterr().out
    assert "3 of 3 shipped item lines have one" in printed and "stale item" not in printed
    planned = generate.plan(Store(wrapped), [])
    shard = planned["Data/Reading/Reading_item_0010.lua"]
    assert '["item:10360"] = { description = "呼び出し方=よびだしかた' in shard
    assert _export_tips(tmp_path) == []


def test_a_sentence_with_nothing_to_list_is_written_as_an_empty_list(sentences, tmp_path, capsys):
    Store(sentences).save("item", [_machine_line(8, "description", "AncientsからのGift。\n" + LAST),
                                   _machine_line(9, "description", "AncientsからのGift。")])
    rows = _export_tips(tmp_path)
    assert rows[0]["ja"] == "AncientsからのGift。"
    batch = _batch(tmp_path, [_piece_row("AncientsからのGift。", []), _piece_row(LAST, LAST_WORDS)])
    assert _import_tips(batch) == 0
    assert "rejected 0" in capsys.readouterr().out
    item = {r["id"]: r for r in Store(sentences / "reading").load("item")}
    assert item[8]["words"] == LAST_WORDS
    assert 9 not in item  # a line with no word at all has no record
    # the empty sentence is written: it is not exported again
    assert "AncientsからのGift。" not in [r["ja"] for r in _export_tips(tmp_path)]


def test_tooltip_text_ships_no_english_word_card_rows(tips):
    from wfj.cmd import english_cards

    Store(tips / "reading").save("item", [readings.record(6948, "description", TIP_JA, TIP_WORDS, dict(MACHINE))])
    assert "item" not in english_cards.card_records(Store(tips)) and "spell" not in english_cards.card_records(Store(tips))


def test_generate_emits_item_and_spell_reading_shards(tips):
    Store(tips / "reading").save("item", [readings.record(6948, "description", TIP_JA, TIP_WORDS, dict(MACHINE))])
    Store(tips / "reading").save("spell", [readings.record(8690, "description", TIP_JA, TIP_WORDS, dict(MACHINE))])
    planned = generate.plan(Store(tips), [])
    files = {rel: text for rel, text in planned.items() if "Reading_item" in rel or "Reading_spell" in rel}
    assert sorted(files) == ["Data/Reading/Reading_item_0006.lua", "Data/Reading/Reading_spell_0008.lua"]
    assert '["item:6948"] = { description = "' in files["Data/Reading/Reading_item_0006.lua"]
    assert '["spell:8690"] = { description = "' in files["Data/Reading/Reading_spell_0008.lua"]
