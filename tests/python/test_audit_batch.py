"""`dev/audit_batch`: the shipped hand-written lines cut beside their English, and the verdicts the
model writes on them checked before anything becomes a decisions list or a word list."""

import json

import pytest

from wfj.core import readings
from wfj.dev import audit_batch
from wfj.io.jsonl_store import Store

HUMAN = {"class": "human", "translator": "Tammy", "source": "cqjt@3446c82", "imported": "2026-09-13"}
MACHINE = {"class": "machine", "model": "m", "source": "draft-q-sg9@2026-09-23", "imported": "2026-09-23"}
JA = "狼を倒せ"
WORDS = [["狼", "おおかみ", "狼", "おおかみ", "wolf"], ["倒せ", "たおせ", "倒す", "たおす", "kill"]]


def _line(id_, field="title", status="trusted", prov=HUMAN, ja=JA):
    return {"id": id_, "field": field, "ja": ja, "status": status, "checks": [], "provenance": dict(prov),
            "english": {"hash": "0", "src": "wdb"}, "reasons": [], "conflicts": []}


def _en(id_, field="title", en="Kill the wolf"):
    return {"id": id_, "field": field, "en": en, "hash": "0", "src": "wdb"}


def _data(d):
    Store(d).save("quest", [
        _line(1), _line(2, status="stale"), _line(3, status="unaligned"), _line(4, status="rejected"),
        _line(5, prov=MACHINE), _line(6),  # 6 has no English
    ])
    Store(d, english=True).save("quest", [_en(i) for i in range(1, 6)])


def test_cut_takes_only_shipped_hand_written_lines_with_english(tmp_path):
    _data(tmp_path)
    rows, no_english = audit_batch.audit_rows(tmp_path, "quest")
    assert [r["id"] for r in rows] == [1, 2, 3] and no_english == 1
    assert rows[0] == {"type": "quest", "id": 1, "field": "title", "class": "human", "ja": JA,
                       "ja_hash": readings.ja_hash(JA), "en": "Kill the wolf"}


def test_cut_reuses_words_written_for_the_same_japanese_only(tmp_path):
    _data(tmp_path)
    known = {("quest", 1, "title", readings.ja_hash(JA)): WORDS, ("quest", 2, "title", "stale-hash"): WORDS}
    rows, _ = audit_batch.audit_rows(tmp_path, "quest", known)
    assert rows[0]["words"] == WORDS and "words" not in rows[1]


def test_cut_writes_parts_of_the_size_asked(tmp_path):
    _data(tmp_path)
    audit_batch.cut(tmp_path, "quest", 2, tmp_path / "out", "q", [])
    assert [len(audit_batch.load_jsonl(tmp_path / "out" / n)) for n in ("q01.jsonl", "q02.jsonl")] == [2, 1]


def test_an_item_row_carries_the_spell_text_its_english_includes(tmp_path):
    Store(tmp_path).save("item", [_line(9, field="description", ja="食べる")])
    Store(tmp_path, english=True).save("item", [_en(9, "description", "$@spelldesc434 Well fed.")])
    Store(tmp_path, english=True).save("spell", [_en(434, "description", "Restores $o1 health.")])
    rows, _ = audit_batch.audit_rows(tmp_path, "item")
    assert rows[0]["included"] == {"434": "Restores $o1 health."}


def _part(type_="quest", ja=JA):
    return {"type": type_, "id": 1, "field": "title" if type_ == "quest" else "description", "class": "human",
            "ja": ja, "ja_hash": readings.ja_hash(ja), "en": "Kill the wolf"}


def _v(part, **kw):
    return {k: part[k] for k in audit_batch.ROW_KEYS} | kw


@pytest.mark.parametrize(("kw", "message"), [
    ({"verdict": "fine"}, "verdict must be"),
    ({"verdict": "match"}, "words missing"),
    ({"verdict": "match", "words": [w[:2] for w in WORDS]}, "5-item form"),
    ({"verdict": "correct", "kind": "typo", "problem": "p", "words": WORDS}, "corrected `ja`"),
    ({"verdict": "correct", "kind": "typo", "problem": "p", "ja": JA, "words": WORDS}, "unchanged"),
    ({"verdict": "correct", "kind": "nope", "problem": "p", "ja": "狼を倒す", "words": WORDS}, "kind must be"),
    ({"verdict": "redraft", "kind": "meaning"}, "names its problem"),
    ({"verdict": "redraft", "kind": "meaning", "problem": "p", "words": WORDS}, "none are owed"),
])
def test_a_bad_quest_verdict_is_named(kw, message):
    part = _part()
    assert any(message in x for x in audit_batch.verdict_problems(part, _v(part, **kw)))


def test_good_verdicts_pass_and_words_are_checked_against_the_corrected_japanese():
    part = _part()
    assert audit_batch.verdict_problems(part, _v(part, verdict="match", words=WORDS)) == []
    fixed = [["狼", "おおかみ", "狼", "おおかみ", "wolf"], ["倒す", "たおす", "倒す", "たおす", "kill"]]
    ok = _v(part, verdict="correct", kind="typo", problem="p", ja="狼を倒す", words=fixed)
    assert audit_batch.verdict_problems(part, ok) == []
    assert audit_batch.verdict_problems(part, {**ok, "words": WORDS})  # words for the old text are refused


def test_item_rows_never_carry_words_and_a_row_out_of_order_is_named():
    part = _part("item")
    assert audit_batch.verdict_problems(part, _v(part, verdict="match")) == []
    assert audit_batch.verdict_problems(part, _v(part, verdict="match", words=WORDS))
    assert "does not match" in audit_batch.verdict_problems(part, {**_v(part, verdict="match"), "id": 2})[0]


def _write(p, rows):
    p.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


def test_report_writes_decisions_and_word_lists_only_when_every_part_passes(tmp_path):
    a, b = _part(), {**_part(), "id": 2}
    _write(tmp_path / "q01.jsonl", [a, b])
    _write(tmp_path / "q01.verdicts.jsonl", [_v(a, verdict="match", words=WORDS),
                                             _v(b, verdict="redraft", kind="other_text", problem="quest 9")])
    assert audit_batch.report(tmp_path, tmp_path / "r.md") == 0
    dec = audit_batch.load_jsonl(tmp_path / "audit.decisions.jsonl")
    assert dec == [{"type": "quest", "id": 2, "field": "title", "decision": "redraft", "note": "other_text: quest 9"}]
    assert audit_batch.load_jsonl(tmp_path / "audit.words.jsonl")[0]["words"] == WORDS
    assert "| quest | title | 2 | 1 | 0 | 1 |" in (tmp_path / "r.md").read_text(encoding="utf-8")
    (tmp_path / "audit.decisions.jsonl").unlink()
    _write(tmp_path / "q01.verdicts.jsonl", [_v(a, verdict="match", words=WORDS)])  # a row missing
    assert audit_batch.report(tmp_path, None) == 1
    assert not (tmp_path / "audit.decisions.jsonl").exists()


def test_a_line_audited_in_two_parts_is_refused(tmp_path):
    a = _part()
    for n in ("q01", "q02"):
        _write(tmp_path / f"{n}.jsonl", [a])
        _write(tmp_path / f"{n}.verdicts.jsonl", [_v(a, verdict="match", words=WORDS)])
    pairs, problems, _ = audit_batch.check_dir(tmp_path)
    assert len(pairs) == 1 and "audited twice" in problems[0]


def test_check_names_each_failing_row_and_a_missing_verdicts_file(tmp_path, capsys):
    a = _part()
    _write(tmp_path / "q01.jsonl", [a, {**a, "id": 2}])
    assert audit_batch.check_part(tmp_path / "q01.jsonl") == 1
    assert "no verdicts file" in capsys.readouterr().out
    _write(tmp_path / "q01.verdicts.jsonl", [_v(a, verdict="match", words=WORDS), _v({**a, "id": 2}, verdict="match")])
    assert audit_batch.check_part(tmp_path / "q01.jsonl") == 1
    out = capsys.readouterr().out
    assert "row 2 quest/2/title: words missing" in out and "1 failed" in out
    _write(tmp_path / "q01.verdicts.jsonl", [_v(a, verdict="match", words=WORDS), _v({**a, "id": 2}, verdict="match", words=WORDS)])
    assert audit_batch.check_part(tmp_path / "q01.jsonl") == 0


def test_a_part_with_no_verdicts_stops_the_report_unless_partial(tmp_path):
    a = _part()
    _write(tmp_path / "q01.jsonl", [a])
    _write(tmp_path / "q01.verdicts.jsonl", [_v(a, verdict="match", words=WORDS)])
    _write(tmp_path / "q02.jsonl", [{**a, "id": 2}])
    assert audit_batch.report(tmp_path, None) == 1
    assert not (tmp_path / "audit.decisions.jsonl").exists()
    assert audit_batch.report(tmp_path, None, partial=True) == 0


# ---- UI strings -----------------------------------------------------------------------------------

UI_EN = {"CLOSE": "Close", "CLOSE_WINDOW": "Close", "FREE": "Free", "BACK": "Back", "BACK_BUTTON": "Back",
         "OLD": "Old"}
UI_JA = {"CLOSE": "閉じる", "CLOSE_WINDOW": "閉じる", "FREE": "無料", "BACK": "背中", "BACK_BUTTON": "戻る",
         "OLD": "古い"}
UI_INV = {"CLOSE": {"popups"}, "CLOSE_WINDOW": {"character"}, "BACK_BUTTON": {"auction"}}


def _ui_data(d):
    lines = [_line(k, field="text", prov=MACHINE, ja=ja) for k, ja in UI_JA.items()]
    lines[-1]["status"] = "rejected"  # OLD is not shipped
    Store(d).save("ui", lines)
    Store(d, english=True).save("ui", [_en(k, field="text", en=en) for k, en in UI_EN.items()])
    core = d / "addon" / "Core"
    core.mkdir(parents=True)
    (core / "UIStrings.lua").write_text("UIStrings.OWN = {\n  BACK_BUTTON = true,\n}\n", encoding="utf-8")
    return audit_batch.audit_ui.ui_rows(d, addon=d / "addon", inventory=UI_INV)


def test_ui_cut_is_one_row_per_pair_with_its_keys_and_screens(tmp_path):
    rows, no_english = _ui_data(tmp_path)
    assert no_english == 0 and [r["id"] for r in rows] == ["BACK", "BACK_BUTTON", "CLOSE", "FREE"]
    close = rows[2]
    assert close == {"type": "ui", "id": "CLOSE", "field": "text", "keys": ["CLOSE", "CLOSE_WINDOW"],
                     "surfaces": ["character", "popups"], "own": False, "ja": "閉じる",
                     "ja_hash": readings.ja_hash("閉じる"), "en": "Close", "en_width": 5, "ja_width": 6, "warn": [],
                     "siblings": []}
    assert rows[1]["own"] and rows[1]["keys"] == ["BACK_BUTTON"]  # an owned key is its own row
    assert rows[3]["surfaces"] == []  # FREE has no screen


def test_ui_cut_carries_lint_warnings(tmp_path):
    lines = [_line("OK", field="text", prov=MACHINE, ja="よろしいです")]
    Store(tmp_path).save("ui", lines)
    Store(tmp_path, english=True).save("ui", [_en("OK", field="text", en="OK")])
    (tmp_path / "Core").mkdir()
    (tmp_path / "Core" / "UIStrings.lua").write_text("UIStrings.OWN = {\n}\n", encoding="utf-8")
    rows, _ = audit_batch.audit_ui.ui_rows(tmp_path, addon=tmp_path, inventory={})
    assert rows[0]["warn"] == ["too_wide:12/6", "register:です"]


def _ui_part():
    return {"type": "ui", "id": "CLOSE", "field": "text", "keys": ["CLOSE", "CLOSE_WINDOW"],
            "surfaces": ["popups"], "own": False, "ja": "閉じる", "ja_hash": "h", "en": "Close"}


def _uv(**kw):
    return {"type": "ui", "id": "CLOSE", "field": "text", "ja_hash": "h", "context": "screen"} | kw


@pytest.mark.parametrize("v", [
    _uv(verdict="match"),
    _uv(verdict="correct", kind="context_sense", problem="p", ja="閉"),
    _uv(verdict="redraft", kind="too_long", problem="p"),
    _uv(verdict="split", kind="context_sense", problem="p", own={"CLOSE_WINDOW": "閉"}, ja="閉じる"),
    _uv(verdict="split", kind="context_sense", problem="p", own={"CLOSE": "閉", "CLOSE_WINDOW": "閉める"}),
])
def test_ui_verdicts_that_pass(v):
    assert audit_batch.verdict_problems(_ui_part(), v) == []


@pytest.mark.parametrize(("v", "problem"), [
    (_uv(verdict="match", context="key"), "context is `screen`"),
    (_uv(verdict="match", context=None), "context must be one of"),
    (_uv(verdict="match", words=[]), "carries no `words`"),
    (_uv(verdict="match", ja="閉"), "a match carries no new `ja`"),
    (_uv(verdict="match", unsure=True, problem="two senses"), "`unsure` goes only on a match judged from the key"),
    (_uv(verdict="correct", kind="context_sense", problem="p"), "carries the new `ja`"),
    (_uv(verdict="correct", kind="context_sense", problem="p", ja="閉じる"), "is unchanged"),
    (_uv(verdict="correct", kind="context_sense", problem="p", ja="Close"), "fails not_japanese"),
    (_uv(verdict="correct", kind="nope", problem="p", ja="閉"), "kind must be one of"),
    (_uv(verdict="correct", kind="too_long", ja="閉"), "names its problem"),
    (_uv(verdict="redraft", kind="too_long", problem="p", ja="閉"), "a redraft carries no `ja`"),
    (_uv(verdict="split", kind="context_sense", problem="p"), "names its keys in `own`"),
    (_uv(verdict="split", kind="context_sense", problem="p", own={"NOT_MINE": "閉"}, ja="閉じる"), "not one of the row's keys"),
    (_uv(verdict="split", kind="context_sense", problem="p", own={"CLOSE": "閉"}), "carries `ja` for the keys"),
    (_uv(verdict="split", kind="context_sense", problem="p", own={"CLOSE": "閉", "CLOSE_WINDOW": "閉"}, ja="閉じる"), "names every key carries no `ja`"),
    (_uv(verdict="correct", kind="too_long", problem="p", ja="閉", own={"CLOSE": "閉"}), "only a split carries `own`"),
])
def test_ui_verdicts_that_fail(v, problem):
    got = audit_batch.verdict_problems(_ui_part(), v)
    assert any(problem in p for p in got), got


def test_a_correct_on_a_numbered_row_must_fit_its_english_slots():
    part = _ui_part() | {"id": "WidgetText:14849", "keys": ["WidgetText:14849"], "en": "Defeat enemies to advance.",
                         "ja": "敵を倒すと進行します。"}
    v = _uv(verdict="correct", kind="context_sense", problem="p", ja="敵を%9999w体倒すと進行します。", id="WidgetText:14849")
    got = audit_batch.verdict_problems(part, v)
    assert any("fails numbered:" in p for p in got), got
    v["ja"] = "敵を倒して進行します。"
    assert audit_batch.verdict_problems(part, v) == []


def test_a_row_with_no_screen_is_judged_from_the_key_and_may_be_unsure():
    part = _ui_part() | {"surfaces": []}
    assert audit_batch.verdict_problems(part, _uv(verdict="match", context="key")) == []
    assert audit_batch.verdict_problems(part, _uv(verdict="match", context="key", unsure=True, problem="Close = near?")) == []
    assert any("says why" in p for p in audit_batch.verdict_problems(part, _uv(verdict="match", context="key", unsure=True)))
    assert any("context is `key`" in p for p in audit_batch.verdict_problems(part, _uv(verdict="match")))


def test_split_is_refused_on_a_quest_row():
    part = {"type": "quest", "id": 1, "field": "title", "ja_hash": "h", "ja": JA, "en": "Kill the wolf"}
    v = {"type": "quest", "id": 1, "field": "title", "ja_hash": "h", "verdict": "split", "kind": "meaning", "problem": "p"}
    assert audit_batch.verdict_problems(part, v) == ["a split is for UI rows only"]


def test_ui_report_writes_the_draft_the_redraft_ids_and_the_splits(tmp_path):
    parts = [
        _ui_part(),
        {"type": "ui", "id": "FREE", "field": "text", "keys": ["FREE"], "surfaces": [], "own": False,
         "ja": "無料", "ja_hash": "f", "en": "Free"},
        {"type": "ui", "id": "OPEN", "field": "text", "keys": ["OPEN", "OPEN_BAG"], "surfaces": ["bags"],
         "own": False, "ja": "開く", "ja_hash": "o", "en": "Open"},
        {"type": "ui", "id": "SAVE", "field": "text", "keys": ["SAVE"], "surfaces": ["settings"],
         "own": False, "ja": "保存", "ja_hash": "s", "en": "Save"},
    ]
    verdicts = [
        _uv(verdict="correct", kind="register", problem="p", ja="閉"),
        {"type": "ui", "id": "FREE", "field": "text", "ja_hash": "f", "verdict": "correct", "context": "key",
         "kind": "context_sense", "problem": "an empty slot", "ja": "空き"},
        {"type": "ui", "id": "OPEN", "field": "text", "ja_hash": "o", "verdict": "split", "context": "screen",
         "kind": "context_sense", "problem": "p", "own": {"OPEN_BAG": "開ける"}, "ja": "開く"},
        {"type": "ui", "id": "SAVE", "field": "text", "ja_hash": "s", "verdict": "redraft", "context": "screen",
         "kind": "too_long", "problem": "p"},
    ]
    audit_batch.write_jsonl(tmp_path / "u01.jsonl", parts)
    audit_batch.write_jsonl(tmp_path / "u01.verdicts.jsonl", verdicts)
    assert audit_batch.report(tmp_path, tmp_path / "r.md") == 0
    draft = [json.loads(x) for x in (tmp_path / "audit.ui-draft.jsonl").read_text(encoding="utf-8").splitlines()]
    assert draft == [{"id": "CLOSE", "field": "text", "ja": "閉"}, {"id": "CLOSE_WINDOW", "field": "text", "ja": "閉"},
                     {"id": "FREE", "field": "text", "ja": "空き"}, {"id": "OPEN_BAG", "field": "text", "ja": "開ける"}]
    assert (tmp_path / "audit.ui-redraft.ids").read_text(encoding="utf-8") == "SAVE\n"
    assert [json.loads(x) for x in (tmp_path / "audit.ui-split.jsonl").read_text(encoding="utf-8").splitlines()] == [
        {"id": "OPEN_BAG", "en": "Open", "ja": "開ける", "surfaces": ["bags"]}]
    base = [json.loads(x) for x in (tmp_path / "audit.ui-base.jsonl").read_text(encoding="utf-8").splitlines()]
    assert base == [{"id": "CLOSE", "ja_hash": "h"}, {"id": "CLOSE_WINDOW", "ja_hash": "h"},
                    {"id": "FREE", "ja_hash": "f"}, {"id": "OPEN_BAG", "ja_hash": "o"}]
    assert (tmp_path / "audit.decisions.jsonl").read_text(encoding="utf-8") == ""  # UI rows are not decisions
    text = (tmp_path / "r.md").read_text(encoding="utf-8")
    assert "Judged by screen 3 · by key 1" in text and "| (no screen) | 1 | 0 | 1 | 0 | 0 |" in text


def test_ui_rows_name_siblings_the_addon_finds_by_the_same_english(tmp_path):
    # "Reagents:" and "Reagents: |n" are one English to the addon (markup set aside): their rows name each other
    Store(tmp_path).save("ui", [_line("LABEL", field="text", prov=MACHINE, ja="素材:"),
                                _line("SPELL", field="text", prov=MACHINE, ja="素材: |n")])
    Store(tmp_path, english=True).save("ui", [_en("LABEL", field="text", en="Reagents:"),
                                              _en("SPELL", field="text", en="Reagents: |n")])
    (tmp_path / "Core").mkdir()
    (tmp_path / "Core" / "UIStrings.lua").write_text("UIStrings.OWN = {\n}\n", encoding="utf-8")
    rows, _ = audit_batch.audit_ui.ui_rows(tmp_path, addon=tmp_path, inventory={})
    assert [(r["id"], r["siblings"]) for r in rows] == [("LABEL", ["SPELL"]), ("SPELL", ["LABEL"])]


def test_a_split_on_a_template_or_one_that_changes_nothing_is_refused():
    template = _ui_part() | {"en": "Close %s", "ja": "%sを閉じる"}
    v = _uv(verdict="split", kind="context_sense", problem="p", own={"CLOSE": "%sを閉"}, ja="%sを閉じる")
    assert any("plain string" in p for p in audit_batch.verdict_problems(template, v))
    noop = _uv(verdict="split", kind="context_sense", problem="p", own={"CLOSE": "閉じる"})
    assert any("changes no key" in p for p in audit_batch.verdict_problems(_ui_part(), noop))


def test_a_ui_only_kind_is_refused_on_a_quest_row():
    part = {"type": "quest", "id": 1, "field": "title", "ja_hash": "h", "ja": JA, "en": "Kill the wolf"}
    v = {"type": "quest", "id": 1, "field": "title", "ja_hash": "h", "verdict": "redraft", "kind": "too_long",
         "problem": "p"}
    assert audit_batch.verdict_problems(part, v) == ["kind too_long is for UI rows only"]


def test_owned_keys_sharing_a_pair_are_each_their_own_row(tmp_path):
    Store(tmp_path).save("ui", [_line(k, field="text", prov=MACHINE, ja="戻る") for k in ("BACK", "BACK_BUTTON", "PLAIN")])
    Store(tmp_path, english=True).save("ui", [_en(k, field="text", en="Back") for k in ("BACK", "BACK_BUTTON", "PLAIN")])
    (tmp_path / "Core").mkdir()
    (tmp_path / "Core" / "UIStrings.lua").write_text("UIStrings.OWN = {\n  BACK = true, BACK_BUTTON = true,\n}\n", encoding="utf-8")
    rows, _ = audit_batch.audit_ui.ui_rows(tmp_path, addon=tmp_path, inventory={})
    assert sorted((r["keys"], r["own"]) for r in rows) == [(["BACK"], True), (["BACK_BUTTON"], True), (["PLAIN"], False)]


def test_the_report_counts_splits_in_its_own_column():
    row = {"type": "ui", "field": "text", "id": "X", "ja": "j", "en": "e", "keys": ["X"], "surfaces": []}
    text = audit_batch.render([(row, {"verdict": "split", "kind": "context_sense", "problem": "p", "own": {}})])
    assert "| ui | text | 1 | 0 | 0 | 0 | 1 |" in text and "| context_sense | 0 | 0 | 1 |" in text
