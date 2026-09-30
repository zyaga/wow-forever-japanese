"""`wfj import draft` merges machine drafts into a store and never edits a hand-written variant."""

import json
from pathlib import Path

import pytest

from wfj.cmd import import_ as imp
from wfj.cmd import import_draft
from wfj.io.jsonl_store import Store

HUMAN = {"class": "human", "translator": "Tammy", "source": "cqjt@3446c82", "imported": "2026-09-13"}
CORRECTION = {
    "class": "correction",
    "translator": "Az",
    "source": "correction@2026-09-14",
    "imported": "2026-09-14",
    "corrects": "qjp@0.5.8",
}


def _line(id_, field, ja, prov, conflicts=()):
    return {
        "id": id_,
        "field": field,
        "ja": ja,
        "status": "trusted",
        "checks": [],
        "provenance": dict(prov),
        "english": None,
        "reasons": [],
        "conflicts": list(conflicts),
    }


@pytest.fixture
def data(tmp_path, monkeypatch):
    d = tmp_path / "data"
    d.mkdir()
    (d / "SCHEMA").write_text("1\n")
    monkeypatch.setattr(import_draft, "data_root", lambda start=None: d)
    return d


def _styled(tmp_path: Path) -> None:
    """Every quest field a drafter writes is styled: title / objectives / description joined
    progress / completion, so a draft of one needs a style guide and a `-sg<N>` name."""
    d = tmp_path / "docs" / "content"
    d.mkdir(parents=True, exist_ok=True)
    (d / "translation-style-guide.md").write_text("version: sg3\n")


def _draft(tmp_path: Path, rows, name="draft.jsonl") -> Path:
    p = tmp_path / name
    p.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    return p


def _run(file: Path, type_="quest", date="2026-09-14", name="quest-sg3", critic="critic-model-1"):
    argv = ["draft", type_, str(file), "--model", "draft-model-1", "--date", date, "--name", name]
    if critic:
        argv += ["--critic", critic]
    return imp.run(argv)


def _by(d: Path, type_="quest") -> dict:
    return {(ln["id"], ln["field"]): ln for ln in Store(d).load(type_)}


def test_the_four_merges_and_their_counts(data, tmp_path, capsys):
    _styled(tmp_path)
    Store(data).save(
        "quest",
        [
            _line(1, "title", "同じ題", HUMAN),
            _line(2, "title", "人の題", HUMAN),
            _line(3, "title", "訂正の題", CORRECTION),
        ],
    )
    first = _draft(tmp_path, [
        {"id": 1, "field": "title", "ja": "同じ題"},  # identical to the human text → unchanged
        {"id": 2, "field": "title", "ja": "機械の題"},  # beside a human line → appended variant
        {"id": 3, "field": "title", "ja": "機械の訂正題"},  # beside a correction → appended variant
        {"id": 4, "field": "title", "ja": "新しい題"},  # absent → added
    ])
    assert _run(first) == 0
    out = capsys.readouterr().out
    assert "added 1 · unchanged 1 · replaced 0 · appended 2" in out
    by = _by(data)
    assert by[(1, "title")]["provenance"] == HUMAN and by[(1, "title")]["conflicts"] == []
    assert by[(2, "title")]["ja"] == "人の題" and by[(2, "title")]["provenance"] == HUMAN
    assert by[(3, "title")]["ja"] == "訂正の題" and by[(3, "title")]["provenance"] == CORRECTION
    added = by[(4, "title")]
    assert added["status"] == "pending"
    assert added["provenance"] == {
        "class": "machine",
        "model": "draft-model-1",
        "critic": "critic-model-1",
        "source": "draft-quest-sg3@2026-09-14",
        "imported": "2026-09-14",
    }

    # a newer draft with the same name replaces the model's own variants, still never the human ones
    second = _draft(tmp_path, [
        {"id": 2, "field": "title", "ja": "直した機械の題"},
        {"id": 4, "field": "title", "ja": "直した新しい題"},
    ], name="second.jsonl")
    assert _run(second, date="2026-09-20") == 0
    assert "added 0 · unchanged 0 · replaced 2 · appended 0" in capsys.readouterr().out
    by = _by(data)
    assert by[(2, "title")]["provenance"] == HUMAN
    assert [c["ja"] for c in by[(2, "title")]["conflicts"]] == ["直した機械の題"]
    assert by[(2, "title")]["conflicts"][0]["provenance"]["source"] == "draft-quest-sg3@2026-09-20"
    assert by[(4, "title")]["ja"] == "直した新しい題"

    # a draft under another name is another model pass: appended, the first stays
    third = _draft(tmp_path, [{"id": 4, "field": "title", "ja": "別の下書き"}], name="third.jsonl")
    assert _run(third, name="audit-sg3", critic=None) == 0
    by = _by(data)
    assert [c["provenance"]["source"] for c in by[(4, "title")]["conflicts"]] == ["draft-audit-sg3@2026-09-14"]
    assert "critic" not in by[(4, "title")]["conflicts"][0]["provenance"]


def test_replacing_a_draft_drops_the_ruling_that_judged_the_old_text(data, tmp_path, capsys):
    _styled(tmp_path)
    # an `accept` on a draft beside a human line must not carry over to new, unreviewed text
    ruled = {"ja": "機械の題", "provenance": {"class": "machine", "model": "m", "source": "draft-quest-sg3@2026-09-14",
                                            "imported": "2026-09-14"},
             "ruling": {"ruling": "accept", "by": "maintainer", "date": "2026-09-15"}}
    Store(data).save("quest", [_line(2, "title", "人の題", HUMAN, conflicts=[ruled])])
    assert _run(_draft(tmp_path, [{"id": 2, "field": "title", "ja": "新しい機械の題"}]), date="2026-09-20") == 0
    assert "replaced 1 · appended 0 · rulings dropped 1" in capsys.readouterr().out
    variant = _by(data)[(2, "title")]["conflicts"][0]
    assert variant["ja"] == "新しい機械の題"
    assert "ruling" not in variant
    assert _by(data)[(2, "title")]["provenance"] == HUMAN


@pytest.mark.parametrize(
    "rows, type_, needle",
    [
        ([{"id": 1, "field": "title"}], "quest", "exactly {id, field, ja}"),
        ([{"id": 1, "field": "title", "ja": " "}], "quest", "non-empty"),
        ([{"id": 1, "field": "nope", "ja": "題"}], "quest", "field 'nope'"),
        ([{"id": "1", "field": "title", "ja": "題"}], "quest", "must be an integer"),
        ([{"id": 1, "field": "title", "ja": "題"}, {"id": 1, "field": "title", "ja": "題2"}], "quest", "duplicate"),
        ([{"id": 1, "field": "title", "ja": "題"}], "questz", "unknown type"),
    ],
)
def test_invalid_drafts_are_refused_and_nothing_is_written(data, tmp_path, capsys, rows, type_, needle):
    _styled(tmp_path)
    Store(data).save("quest", [_line(9, "title", "人の題", HUMAN)])
    before = {p: p.read_bytes() for p in (data / "quest").glob("*.jsonl")}
    assert _run(_draft(tmp_path, rows), type_=type_) == 1
    assert needle in capsys.readouterr().err
    assert {p: p.read_bytes() for p in (data / "quest").glob("*.jsonl")} == before


@pytest.mark.parametrize(("type_", "row"), [
    ("quest", {"id": 1, "field": "progress", "ja": "もう済んだか?"}),
    ("quest", {"id": 1, "field": "completion", "ja": "よくやった。"}),
    ("gossip", {"id": "0123456789abcdef", "field": "text", "ja": "こんにちは。"}),
    ("book", {"id": 15, "field": "text", "ja": "こんにちは、Morgan。"}),
])
def test_server_only_text_is_imported_only_under_the_current_style_version(data, tmp_path, capsys, type_, row):
    # ADR-023: the version is checked at import too, not only when translate_batch writes the file
    draft = _draft(tmp_path, [row])
    assert _run(draft, type_=type_, name="gossip-sg3", critic=None) == 1  # no style guide in this repo
    assert "style guide" in capsys.readouterr().err
    (data.parent / "docs" / "content").mkdir(parents=True)
    (data.parent / "docs" / "content" / "translation-style-guide.md").write_text("version: sg3\n")
    for bad in ("gossip", "gossip-sg2", "gossip-sg3x"):
        assert _run(draft, type_=type_, name=bad, critic=None) == 1
        assert "-sg3" in capsys.readouterr().err
    assert _run(draft, type_=type_, name="kind-sg3", critic=None) == 0
    assert Store(data).load(type_)[0]["provenance"]["source"] == "draft-kind-sg3@2026-09-14"


def test_a_bad_name_is_refused(data, tmp_path, capsys):
    assert _run(_draft(tmp_path, [{"id": 1, "field": "title", "ja": "題"}]), name="Bad Name") == 1
    assert "--name" in capsys.readouterr().err


# ── --reverify ───────────────────────────────────────────────────────────────────────────────────────────────

UI_OLD = {"hash": "1111111111111111", "src": "wago@1.15.9.69722"}
UI_NOW = {"hash": "2222222222222222", "src": "db2@1.60.1.69913"}
UI_MACHINE = {"class": "machine", "model": "m", "source": "draft-ui-first@2026-09-14", "imported": "2026-09-14"}


def _ui_store(d: Path, english_ids=("A", "B", "C")) -> None:
    stale = {**_line("A", "text", "旧", UI_MACHINE), "status": "stale", "english": dict(UI_OLD)}
    other = {**_line("B", "text", "別", UI_MACHINE), "english": dict(UI_OLD)}
    Store(d).save("ui", [stale, other])
    Store(d, english=True).save(
        "ui", [{"id": i, "field": "text", "en": i, "hash": UI_NOW["hash"], "src": UI_NOW["src"]} for i in english_ids]
    )


def _run_ui(file: Path, reverify: bool, name="ui-second"):
    argv = ["draft", "ui", str(file), "--model", "m", "--date", "2026-09-19", "--name", name]
    return imp.run(argv + (["--reverify"] if reverify else []))


def test_reverify_records_the_current_english_on_every_named_line(data, tmp_path, capsys):
    _ui_store(data)
    rows = [{"id": "A", "field": "text", "ja": "旧"}, {"id": "C", "field": "text", "ja": "新"}]  # unchanged · added
    assert _run_ui(_draft(tmp_path, rows), reverify=True) == 0
    by = _by(data, "ui")
    assert by[("A", "text")]["english"] == UI_NOW  # a stale line keeps its Japanese and is judged fresh next check
    assert by[("A", "text")]["provenance"] == UI_MACHINE  # unchanged text: its provenance is untouched
    assert by[("C", "text")]["english"] == UI_NOW
    assert by[("B", "text")]["english"] == UI_OLD  # a line the draft does not name is never touched
    assert "re-verified 2" in capsys.readouterr().out


def test_without_reverify_the_english_is_untouched(data, tmp_path, capsys):
    _ui_store(data)
    assert _run_ui(_draft(tmp_path, [{"id": "A", "field": "text", "ja": "旧"}]), reverify=False) == 0
    assert _by(data, "ui")[("A", "text")]["english"] == UI_OLD
    assert "re-verified" not in capsys.readouterr().out


def test_reverify_refuses_a_row_with_no_english_and_writes_nothing(data, tmp_path, capsys):
    _ui_store(data, english_ids=("A",))
    before = Store(data).load("ui")
    rows = [{"id": "A", "field": "text", "ja": "旧"}, {"id": "Z", "field": "text", "ja": "無"}]
    assert _run_ui(_draft(tmp_path, rows), reverify=True) == 1
    assert "no English" in capsys.readouterr().err
    assert Store(data).load("ui") == before


def test_reverify_refuses_a_type_it_does_not_list(data, tmp_path, capsys):
    # gossip is keyed by its English hash, so a rewording is a new key, never a stale line
    _styled(tmp_path)
    argv = ["draft", "gossip", str(_draft(tmp_path, [{"id": "0123456789abcdef", "field": "text", "ja": "話"}])),
            "--model", "m", "--date", "2026-09-19", "--name", "gossip-sg3", "--reverify"]
    assert imp.run(argv) == 1
    assert "only, not 'gossip'" in capsys.readouterr().err


def test_reverify_refuses_a_line_with_a_hand_written_variant(data, tmp_path, capsys):
    _ui_store(data)
    lines = Store(data).load("ui")
    lines[0]["conflicts"].append({"ja": "人", "provenance": dict(HUMAN)})
    Store(data).save("ui", lines)
    assert _run_ui(_draft(tmp_path, [{"id": "A", "field": "text", "ja": "旧"}]), reverify=True) == 1
    assert "hand-written" in capsys.readouterr().err


# ── --reverify for the types a client build rewords ─────────────────────────────────────────────────

Q_OLD, Q_NOW = "Find the lost map.", "Find the lost chart."
FOREVER = "db2@1.60.1.70009"
Q_MACHINE = {"class": "machine", "model": "m", "source": "draft-q-sg3@2026-09-18", "imported": "2026-09-18"}
REJECT = {"ruling": "reject", "by": "maintainer", "date": "2026-09-25", "note": "test ruling"}


def _h(en):
    from wfj.core.hashing import key
    from wfj.core.normalize import normalize_v1

    return key(normalize_v1(en))


def _checked(d: Path, type_: str) -> dict:
    from wfj.cmd.check import build_scopes, check_type

    [out] = check_type(Store(d).load(type_), build_scopes(Store(d, english=True), type_), set())
    return out


def _stale_quest(d: Path, conflicts=()) -> None:
    line = {**_line(7, "objectives", "失われた地図を見つける。", Q_MACHINE, conflicts), "status": "stale",
            "english": {"hash": _h(Q_OLD), "src": "wdb@1.60.1.69913"}}
    Store(d).save("quest", [line])
    Store(d, english=True).save(
        "quest", [{"id": 7, "field": "objectives", "en": Q_NOW, "hash": _h(Q_NOW), "src": "wdb@1.60.1.70009"}]
    )


def _run_quest(tmp_path: Path, reverify: bool) -> int:
    _styled(tmp_path)
    rows = [{"id": 7, "field": "objectives", "ja": "失われた海図を見つける。"}]
    argv = ["draft", "quest", str(_draft(tmp_path, rows)), "--model", "m", "--date", "2026-09-26", "--name", "q-sg3"]
    return imp.run(argv + (["--reverify"] if reverify else []))


def test_reverify_judges_a_redrafted_stale_quest_line_fresh(data, tmp_path):
    _stale_quest(data)
    assert _run_quest(tmp_path, reverify=True) == 0
    out = _checked(data, "quest")
    assert out["english"] == {"hash": _h(Q_NOW), "src": "wdb@1.60.1.70009"}
    assert out["status"] == "trusted" and out["ja"] == "失われた海図を見つける。"


def test_without_reverify_a_redrafted_stale_quest_line_stays_stale(data, tmp_path):
    _stale_quest(data)
    assert _run_quest(tmp_path, reverify=False) == 0
    assert _checked(data, "quest")["status"] == "stale"  # ADR-003's known limit, the case the flag exists for


def test_reverify_allows_a_line_whose_hand_written_variants_are_all_ruled_reject(data, tmp_path):
    _stale_quest(data, conflicts=[{"ja": "人の訳", "provenance": dict(HUMAN), "ruling": dict(REJECT)}])
    assert _run_quest(tmp_path, reverify=True) == 0
    assert _checked(data, "quest")["english"]["hash"] == _h(Q_NOW)


def test_reverify_refuses_a_hand_written_variant_not_ruled_reject(data, tmp_path, capsys):
    _stale_quest(data, conflicts=[{"ja": "人の訳", "provenance": dict(HUMAN)}])
    before = Store(data).load("quest")
    assert _run_quest(tmp_path, reverify=True) == 1
    assert "not ruled reject" in capsys.readouterr().err
    assert Store(data).load("quest") == before


def test_reverify_refuses_a_row_that_loses_to_a_variant_ruled_accept(data, tmp_path, capsys):
    # an accepted older draft keeps winning, so stamping the new English would ship the old
    # Japanese unmarked; the import stops and writes nothing
    _stale_quest(data)
    lines = Store(data).load("quest")
    lines[0]["ruling"] = {"ruling": "accept", "by": "maintainer", "date": "2026-09-20", "note": "earlier ruling"}
    lines[0]["provenance"] = {**lines[0]["provenance"], "source": "draft-old-sg3@2026-09-10"}  # another draft name
    Store(data).save("quest", lines)
    before = Store(data).load("quest")
    assert _run_quest(tmp_path, reverify=True) == 1
    assert "lose to a variant ruled accept" in capsys.readouterr().err
    assert Store(data).load("quest") == before


SPELL_TEXT_OLD, SPELL_TEXT = "Heals the target for $s1.", "Heals a friendly target for $s1."


def _spell(d: Path, with_description: bool) -> None:
    line = {**_line(139, "description", "対象を$N1回復する。", Q_MACHINE), "status": "stale",
            "english": {"hash": _h(SPELL_TEXT_OLD), "src": "db2@1.60.1.69913"}}
    Store(d).save("spell", [line])
    en = [{"id": 139, "field": "name", "en": "Renew", "hash": _h("Renew"), "src": FOREVER}]
    if with_description:
        en.append({"id": 139, "field": "description", "en": SPELL_TEXT, "hash": _h(SPELL_TEXT), "src": FOREVER})
    Store(d, english=True).save("spell", en)


def _run_spell(tmp_path: Path) -> int:
    rows = [{"id": 139, "field": "description", "ja": "味方を$N1回復する。"}]
    argv = ["draft", "spell", str(_draft(tmp_path, rows)), "--model", "m", "--date", "2026-09-26", "--name", "s-sg3"]
    return imp.run(argv + ["--reverify"])


def test_reverify_stamps_a_spell_line_with_its_own_tooltip_english(data, tmp_path):
    _spell(data, with_description=True)
    assert _run_spell(tmp_path) == 0
    assert _by(data, "spell")[(139, "description")]["english"] == {"hash": _h(SPELL_TEXT), "src": FOREVER}


def test_reverify_stamps_of_when_the_line_is_judged_against_another_field(data, tmp_path):
    # the baseline `check` itself would record: the name's hash, with `of: name`
    _spell(data, with_description=False)
    assert _run_spell(tmp_path) == 0
    assert _by(data, "spell")[(139, "description")]["english"] == {"hash": _h("Renew"), "src": FOREVER, "of": "name"}


def test_reverify_records_what_check_records(data, tmp_path):
    _spell(data, with_description=True)
    assert _run_spell(tmp_path) == 0
    stamped = _by(data, "spell")[(139, "description")]["english"]
    assert _checked(data, "spell")["english"] == stamped


def test_global_strings_are_unescaped_once(tmp_path):
    """The table writes GlobalStrings Lua-escaped (backslash-n a break, a doubled backslash one backslash,
    backslash-quote a quote) in one pass, so an escaped backslash before an `n` is never read as a break."""
    import csv

    from wfj.io import wago

    bs = "\\"
    rows = [("A", f"One{bs}nTwo"), ("B", f"|TInterface{bs}{bs}GroupFrame{bs}{bs}Icon:16|t"),
            ("C", f"C:{bs}{bs}new"), ("D", f'Assign {bs}"%s{bs}" now')]
    p = tmp_path / "GlobalStrings.csv"
    with p.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["ID", "BaseTag", "TagText_lang", "Flags"])
        for n, (tag, text) in enumerate(rows, 1):
            w.writerow([n, tag, text, 0])
    got = wago.read_global_strings(p)
    assert got["A"] == "One\nTwo"
    assert got["B"] == f"|TInterface{bs}GroupFrame{bs}Icon:16|t"
    assert got["C"] == f"C:{bs}new"  # an escaped backslash before an n: a backslash and a letter
    assert got["D"] == 'Assign "%s" now'  # an escaped quote is a quote, as the client's _G has it
