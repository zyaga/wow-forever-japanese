"""`dev/ui_lint`: a UI draft checked against the style guide's interface-text rules before it is imported;
format problems fail, width and register on short labels only warn."""

import io
import json

import pytest

from wfj.dev import ui_inventory, ui_lint
from wfj.io.jsonl_store import Store

ENGLISH = {
    "ACCEPT": "Accept",
    "LEVEL_FMT": "Level %d",
    "RED_WORD": "|cffff0000Danger|r",
    "WRAP": "Close\nWindow",
    "PAREN": "(%s)",
    "ERR_SHORT": "Invalid name",
    "LONG_HELP": "Drag an item here to sell it to the vendor.",
    "OK": "OK",
    "ASK": "Leave group?",
}
INVENTORY = {"ACCEPT": {"popups"}, "ERR_SHORT": {"errors"}}


def _lint(rows):
    return {k: (bad, warn) for k, bad, warn in ui_lint.lint_rows(rows, ENGLISH, INVENTORY)}


def _row(key, ja):
    return {"id": key, "field": "text", "ja": ja}


def test_a_good_label_passes_with_no_warning():
    assert _lint([_row("ACCEPT", "受諾")]) == {"ACCEPT": ([], [])}


def test_unknown_key_fails():
    assert _lint([_row("NOT_A_KEY", "何か")])["NOT_A_KEY"] == (["unknown_key"], [])


def test_duplicate_key_fails_on_the_second_row():
    out = ui_lint.lint_rows([_row("ACCEPT", "受諾"), _row("ACCEPT", "承諾")], ENGLISH, INVENTORY)
    assert [bad for _, bad, _ in out] == [[], ["duplicate"]]


def test_not_japanese_fails_and_a_wordless_template_is_exempt():
    assert _lint([_row("ACCEPT", "Accept")])["ACCEPT"][0] == ["not_japanese"]
    assert _lint([_row("ACCEPT", "这是")])["ACCEPT"][0] == ["not_japanese"]  # simplified-only characters
    assert _lint([_row("PAREN", "（%s）")])["PAREN"] == ([], [])


def test_a_line_ruled_to_stay_english_is_not_not_japanese():
    row = _row("OK", "OK") | {"ruling": {"ruling": "accept", "by": "maintainer"}}
    assert _lint([row])["OK"] == ([], [])


def test_specifiers_must_match():
    assert _lint([_row("LEVEL_FMT", "レベル%d")])["LEVEL_FMT"] == ([], [])
    bad = _lint([_row("LEVEL_FMT", "レベル%s")])["LEVEL_FMT"][0]
    assert len(bad) == 1 and bad[0].startswith("specifiers:")


def test_markup_must_match():
    assert _lint([_row("RED_WORD", "|cffff0000危険|r")])["RED_WORD"] == ([], [])
    bad = _lint([_row("RED_WORD", "危険")])["RED_WORD"][0]
    assert len(bad) == 1 and bad[0].startswith("markup:")
    bad = _lint([_row("WRAP", "ウィンドウを閉じる")])["WRAP"][0]
    assert len(bad) == 1 and bad[0].startswith("markup:")


def test_display_width_counts_full_width_as_two():
    assert ui_lint.display_width("Accept") == 6
    assert ui_lint.display_width("受諾") == 4
    assert ui_lint.display_width("ｱ") == 1  # half-width katakana
    assert ui_lint.display_width("レベル65") == 8


@pytest.mark.parametrize(("en", "limit"), [("Accept", 8), ("OK", 6), ("Abandon Quest", 17)])
def test_width_limit_is_english_times_one_and_a_quarter_with_a_floor(en, limit):
    assert ui_lint.width_limit(en) == limit


def test_width_warns_only_over_the_limit():
    assert _lint([_row("ACCEPT", "受け入れ")])["ACCEPT"] == ([], [])  # width 8, limit 8: at the limit
    assert _lint([_row("ACCEPT", "受け入れる")])["ACCEPT"] == ([], ["too_wide:10/8"])


def test_the_floor_lets_a_short_english_take_three_characters():
    assert _lint([_row("OK", "決定")])["OK"] == ([], [])
    assert _lint([_row("OK", "はいはい")])["OK"] == ([], ["too_wide:8/6"])


def test_long_english_sentences_questions_and_messages_get_no_width_check():
    assert _lint([_row("LONG_HELP", "ここにアイテムをドラッグして商人に売却します。")])["LONG_HELP"] == ([], [])
    assert _lint([_row("ASK", "パーティーから抜けますか？")])["ASK"] == ([], [])
    assert _lint([_row("ERR_SHORT", "無効な名前です")])["ERR_SHORT"] == ([], [])


def test_format_strings_are_not_short_labels():
    assert not ui_lint.short_label("Level %d", set())
    assert not ui_lint.short_label("|cffff0000Danger|r", set())


@pytest.mark.parametrize("ja", ["受諾します", "受諾です", "受諾してください", "受諾します。"])
def test_register_warns_on_a_polite_label(ja):
    warn = _lint([_row("ACCEPT", ja)])["ACCEPT"][1]
    assert any(w.startswith("register:") for w in warn)


def test_warnings_do_not_fail():
    out = io.StringIO()
    code = ui_lint.summarize(ui_lint.lint_rows([_row("ACCEPT", "受諾してください")], ENGLISH, INVENTORY), out)
    assert code == 0 and "register:ください" in out.getvalue() and "0 failed" in out.getvalue()


def test_a_failure_sets_the_exit_code():
    out = io.StringIO()
    assert ui_lint.summarize(ui_lint.lint_rows([_row("ACCEPT", "Accept")], ENGLISH, INVENTORY), out) == 1


def test_main_reads_a_draft_file(tmp_path, monkeypatch):
    Store(tmp_path / "data", english=True).save(
        "ui", [{"id": "ACCEPT", "field": "text", "en": "Accept", "hash": "0", "src": "db2"}])
    (tmp_path / "data" / "SCHEMA").write_text("", encoding="utf-8")
    # the addon and the inventory come from the same checkout as the data
    (tmp_path / "addon" / "WoWForeverJapanese" / "Core").mkdir(parents=True)
    (tmp_path / "addon" / "WoWForeverJapanese" / "Core" / "UIStrings.lua").write_text("UIStrings.OWN = {\n}\n", encoding="utf-8")
    (tmp_path / "pipeline").mkdir()
    (tmp_path / "pipeline" / "ui_inventory.txt").write_text("popups ACCEPT\n", encoding="utf-8")
    draft = tmp_path / "d.ui.jsonl"
    draft.write_text(json.dumps(_row("ACCEPT", "受諾"), ensure_ascii=False) + "\n", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    assert ui_lint.main([str(draft)]) == 0
    draft.write_text(json.dumps(_row("ACCEPT", "Accept")) + "\n", encoding="utf-8")
    assert ui_lint.main([str(draft)]) == 1


def test_read_inventory_maps_keys_to_their_surfaces(tmp_path):
    p = tmp_path / "inv.txt"
    p.write_text("# GENERATED\nerrors ERR_X\npopups ACCEPT\ntooltip ACCEPT\n", encoding="utf-8")
    assert ui_inventory.read_inventory(p) == {"ERR_X": {"errors"}, "ACCEPT": {"popups", "tooltip"}}


def test_shipped_ui_lines_have_no_failures(root, monkeypatch):
    monkeypatch.chdir(root)
    out = io.StringIO()
    rows = ui_lint.shipped_rows(root / "data")
    english = ui_lint.english_ui(root / "data")
    found = ui_lint.ambiguous([], rows, english, ui_lint.ui_own(root / "addon" / "WoWForeverJapanese"))
    code = ui_lint.summarize(ui_lint.with_ambiguity(ui_lint.lint_rows(rows, english, ui_inventory.read_inventory()), found), out)
    assert code == 0, [ln for ln in out.getvalue().splitlines() if ln.startswith("FAIL")][:20]


def test_a_draft_that_splits_one_english_fails_ambiguous():
    english = {"A": "Reagents:", "B": "Reagents: |n", "C": "Other", "OWNED": "Reagents:"}
    shipped = [{"id": "A", "ja": "触媒:"}, {"id": "B", "ja": "触媒: |n"}, {"id": "C", "ja": "他"},
               {"id": "OWNED", "ja": "素材:"}]
    assert ui_lint.ambiguous([], shipped, english, {"OWNED"}) == {}  # an owned key may differ
    found = ui_lint.ambiguous([{"id": "A", "ja": "素材:"}], shipped, english, {"OWNED"})
    assert found == {"A": "ambiguous:B"}  # only the draft's key is reported
    assert ui_lint.ambiguous([{"id": "A", "ja": "素材:"}, {"id": "B", "ja": "素材: |n"}], shipped, english,
                             {"OWNED"}) == {}
    results = ui_lint.with_ambiguity([("A", [], []), ("C", [], ["w"])], found)
    assert results == [("A", ["ambiguous:B"], []), ("C", [], ["w"])]


def test_shipped_mode_reports_every_key_of_a_split_group():
    english = {"A": "Reagents:", "B": "Reagents: |n"}
    shipped = [{"id": "A", "ja": "素材:"}, {"id": "B", "ja": "触媒: |n"}]
    assert ui_lint.ambiguous([], shipped, english, set()) == {"A": "ambiguous:B", "B": "ambiguous:A"}


def test_malformed_rows_are_reported_not_crashed_on():
    out = _lint([{"id": "ACCEPT", "ja": None}, {"id": 7, "ja": "受諾"}, {"id": "OK", "ja": 3},
                 {"id": "LEVEL_FMT"}, {"id": "PAREN", "ja": "（%s）", "ruling": None}])
    assert out == {"ACCEPT": (["missing_ja"], []), "7": (["bad_row"], []), "OK": (["bad_row"], []),
                   "LEVEL_FMT": (["missing_ja"], []), "PAREN": ([], [])}
    assert ui_lint.ambiguous([{"id": "ACCEPT", "ja": None}], [], ENGLISH, set()) == {}


def test_a_duplicate_is_checked_for_ambiguity_on_its_first_row():
    english = {"A": "Reagents:", "B": "Reagents: |n"}
    shipped = [{"id": "A", "ja": "触媒:"}, {"id": "B", "ja": "触媒: |n"}]
    draft = [{"id": "A", "ja": "触媒:"}, {"id": "A", "ja": "素材:"}]
    assert ui_lint.ambiguous(draft, shipped, english, set()) == {}


def test_moved_refuses_a_key_whose_shipped_line_changed_since_the_review():
    from wfj.core import readings

    shipped = [{"id": "ACCEPT", "ja": "承諾"}, {"id": "OK", "ja": "決定"}]
    base = {"ACCEPT": readings.ja_hash("承諾"), "OK": readings.ja_hash("了解")}
    found = ui_lint.moved([_row("ACCEPT", "受諾"), _row("OK", "確定")], shipped, base)
    assert found == {"OK": f"moved:{base['OK']}"}


def test_a_numbered_row_that_does_not_fit_its_english_fails():
    english = {"WidgetText:14849": "Defeat enemies to advance."}
    found = ui_lint.ambiguous([{"id": "WidgetText:14849", "ja": "敵を%9999w体倒すと進行します。"}], [], english, set())
    assert found["WidgetText:14849"].startswith("numbered:")


def test_an_error_key_is_never_a_short_label_even_with_no_surface():
    assert not ui_lint.short_label("Invalid name", set(), "ERR_INVALID_NAME")
    assert ui_lint.short_label("Invalid name", set(), "SOME_LABEL")


def test_a_duplicate_key_counts_its_group_reason_once():
    results = [("A", [], []), ("A", ["duplicate"], [])]
    assert ui_lint.with_ambiguity(results, {"A": "ambiguous:B"}) == [("A", ["ambiguous:B"], []), ("A", ["duplicate"], [])]


def test_a_group_reason_lands_on_the_row_that_was_judged():
    """A malformed first row has no Japanese to judge; the reason goes on the key's first well-formed row."""
    results = [("A", ["missing_ja"], []), ("A", [], []), ("B", ["bad_row"], [])]
    assert ui_lint.with_ambiguity(results, {"A": "ambiguous:C", "B": "moved:x"}) == [
        ("A", ["missing_ja"], []), ("A", ["ambiguous:C"], []), ("B", ["bad_row", "moved:x"], [])]


def test_a_tooltip_or_help_key_is_not_a_short_label():
    assert not ui_lint.short_label("Time-gated quests", set(), "MAP_LEGEND_REPEATABLE_TOOLTIP")
    assert not ui_lint.short_label("Drag to sell", set(), "VENDOR_HELP")
    assert ui_lint.short_label("Time-gated quests", set(), "MAP_LEGEND_REPEATABLE")


def test_display_width_counts_as_a_cjk_font_draws():
    assert ui_lint.display_width("待機中……") == 10  # the ellipsis is ambiguous-width and draws wide
    assert ui_lint.display_width("→") == 2
    assert ui_lint.display_width("か\u3099") == 2  # a combining voicing mark adds no column
    assert ui_lint.display_width("Level 5") == 7


def test_a_literal_percent_is_not_a_format_argument():
    assert ui_lint.short_label("Bonus 100%", set(), "BONUS")
    assert not ui_lint.short_label("Level %d", set(), "LEVEL_FMT")


def test_shipped_mode_runs_through_main(root, monkeypatch):
    monkeypatch.chdir(root)
    assert ui_lint.main(["--shipped"]) == 0


def test_shipped_and_base_together_are_refused(tmp_path):
    with pytest.raises(SystemExit):
        ui_lint.main(["--shipped", "--base", str(tmp_path / "audit.ui-base.jsonl")])


def test_main_with_a_base_reports_a_moved_key(tmp_path, monkeypatch):
    from wfj.core import readings

    Store(tmp_path / "data", english=True).save(
        "ui", [{"id": "ACCEPT", "field": "text", "en": "Accept", "hash": "0", "src": "db2"}])
    Store(tmp_path / "data").save("ui", [{"id": "ACCEPT", "field": "text", "ja": "承諾", "status": "trusted",
                                          "provenance": {"class": "machine"}, "english": {"hash": "0"}}])
    (tmp_path / "data" / "SCHEMA").write_text("", encoding="utf-8")
    (tmp_path / "addon" / "WoWForeverJapanese" / "Core").mkdir(parents=True)
    (tmp_path / "addon" / "WoWForeverJapanese" / "Core" / "UIStrings.lua").write_text("UIStrings.OWN = {\n}\n", encoding="utf-8")
    (tmp_path / "pipeline").mkdir()
    (tmp_path / "pipeline" / "ui_inventory.txt").write_text("popups ACCEPT\n", encoding="utf-8")
    draft = tmp_path / "d.ui.jsonl"
    draft.write_text(json.dumps(_row("ACCEPT", "受諾"), ensure_ascii=False) + "\n", encoding="utf-8")
    base = tmp_path / "audit.ui-base.jsonl"
    monkeypatch.chdir(tmp_path)
    base.write_text(json.dumps({"id": "ACCEPT", "ja_hash": readings.ja_hash("承諾")}) + "\n", encoding="utf-8")
    assert ui_lint.main([str(draft), "--base", str(base)]) == 0
    base.write_text(json.dumps({"id": "ACCEPT", "ja_hash": readings.ja_hash("了解")}) + "\n", encoding="utf-8")
    assert ui_lint.main([str(draft), "--base", str(base)]) == 1
