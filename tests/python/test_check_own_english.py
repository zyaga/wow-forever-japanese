"""ADR-019: quest progress / completion are checked and stale-tracked against their own English."""

from wfj.cmd.check import build_scopes, check_type, english_ref
from wfj.core.hashing import key
from wfj.core.model import english_line, entry, provenance
from wfj.core.normalize import normalize_v1
from wfj.io.jsonl_store import Store

PF, VM = "pfquest@7786596", "vmangos@13b49dc"
PROV = provenance("human", "cqjt@3446c82", "2026-09-13", translator="Tammy")
DESC = "Kill the wolves near Northshire Abbey and bring me their meat."
COMPLETION = "You've been busy!  I can't wait to cook up that wolf meat."
COMPLETION_JA = "よく頑張ったな！狼肉を料理するのが待ちきれないよ。"


def _en(id_, field, en, src):
    return english_line(id_, field, en, key(normalize_v1(en)), src)


def _english(tmp_path, completion=COMPLETION, with_vmangos=True):
    store = Store(tmp_path, english=True)
    lines = [_en(33, "title", "Wolves Across the Border", PF), _en(33, "description", DESC, PF)]
    if with_vmangos:
        lines.append(_en(33, "completion", completion, VM))
    store.save("quest", lines)
    return build_scopes(store, "quest")


def _check(scopes, lines):
    return {ln["field"]: ln for ln in check_type(lines, scopes, set())}


def _lines(completion_ja=COMPLETION_JA, completion_english=None):
    desc = entry(33, "description", "Northshire Abbeyの近くの狼を倒して肉を持ってきてくれ。", prov=PROV)
    comp = entry(33, "completion", completion_ja, prov=PROV)
    comp["english"] = completion_english
    return [desc, comp]


def test_completion_uses_own_vmangos_hash_and_src(tmp_path):
    scopes = _english(tmp_path)
    out = _check(scopes, _lines())
    assert out["completion"]["status"] == "trusted"
    assert out["completion"]["english"] == {"hash": key(normalize_v1(COMPLETION)), "src": VM}
    assert out["description"]["english"] == {"hash": key(normalize_v1(DESC)), "src": PF}
    assert english_ref(scopes[33], "completion") == (key(normalize_v1(COMPLETION)), VM, None)


def test_completion_without_vmangos_falls_back(tmp_path):
    scopes = _english(tmp_path, with_vmangos=False)
    out = _check(scopes, _lines())
    assert out["completion"]["english"] == {"hash": key(normalize_v1(DESC)), "src": PF, "of": "description"}


def test_pfquest_fallback_baseline_rebaselined_not_stale(tmp_path):
    scopes = _english(tmp_path)
    prior = {"hash": key(normalize_v1(DESC)), "src": PF}  # what a completion line carried before it had its own English
    out = _check(scopes, _lines(completion_english=prior))
    assert out["completion"]["status"] == "trusted"
    assert out["completion"]["english"] == {"hash": key(normalize_v1(COMPLETION)), "src": VM}


def test_vmangos_completion_change_marks_only_completion_stale(tmp_path):
    scopes = _english(tmp_path)
    first = _check(scopes, _lines())
    changed = _english(tmp_path / "later", completion="You've been very busy!  I can't wait to cook that meat.")
    again = _check(changed, [first["description"], first["completion"]])
    assert again["completion"]["status"] == "stale"
    assert again["completion"]["english"] == first["completion"]["english"]  # sticky: the checked hash is kept
    assert again["description"]["status"] == "trusted"
    # a stale line from a vmangos baseline is never re-baselined
    assert _check(changed, [again["description"], again["completion"]])["completion"]["status"] == "stale"


def test_completion_numbers_checked_against_own_english(tmp_path):
    scopes = _english(tmp_path)
    out = _check(scopes, _lines(completion_ja="よく頑張ったな！狼肉を12個料理するのが待ちきれないよ。"))
    assert out["completion"]["status"] == "rejected"
    assert "numbers_changed:12" in out["completion"]["reasons"]


def test_completion_truncation_checked(tmp_path):
    long_en = (
        "You've been busy!  I can't wait to cook up that wolf meat, it will feed the whole abbey for a week."
        "$B$BI have some things here you might want - take your pick, and come back when you are hungry again."
    )
    scopes = _english(tmp_path, completion=long_en)
    out = _check(scopes, _lines(completion_ja="よく頑張ったな！"))
    assert out["completion"]["status"] == "rejected"
    assert any(r.startswith("truncated:1/2") for r in out["completion"]["reasons"])


def test_title_only_quest_joined_fallback_ignores_progress_completion(tmp_path):
    """A quest whose pfQuest entry has only a title keeps the joined-scope hash when completion English arrives."""
    store = Store(tmp_path, english=True)
    store.save("quest", [_en(926, "title", "Flawed Power Stone", PF)])
    before = english_ref(build_scopes(store, "quest")[926], "description")
    store.save("quest", [_en(926, "title", "Flawed Power Stone", PF), _en(926, "completion", COMPLETION, VM)])
    after = english_ref(build_scopes(store, "quest")[926], "description")
    assert after == before


def test_fallback_hash_is_marked_of_and_ships_no_h1(tmp_path):
    """A quest field checked against another field's English records `of`, and generate writes no
    h1 for it; the addon's live check never compares this field's live English with another field's hash."""
    from wfj.emit.lua_writer import rows

    scopes = _english(tmp_path, with_vmangos=False)
    out = _check(scopes, _lines())
    assert out["completion"]["english"] == {"hash": key(normalize_v1(DESC)), "src": PF, "of": "description"}
    assert "of" not in out["description"]["english"]
    row = rows("quest", [out["description"], out["completion"]])[33]
    assert row[5 + 2] != "nil" and row[5 + 4] == "nil"  # description h1 shipped; completion h1 not
    title_only = Store(tmp_path / "t", english=True)
    title_only.save("quest", [_en(926, "title", "Flawed Power Stone", PF)])
    line = entry(926, "description", "説明", prov=PROV)
    got = check_type([line], build_scopes(title_only, "quest"), set())[0]
    assert got["english"]["of"] == "joined"


def test_quest_with_only_vmangos_english_rejects_title_objectives_description(tmp_path):
    """No title / objectives / description English → nothing to check them against."""
    store = Store(tmp_path, english=True)
    store.save("quest", [_en(77, "completion", COMPLETION, VM)])
    scopes = build_scopes(store, "quest")
    assert english_ref(scopes[77], "description") == (None, None, None)
    title = entry(77, "title", "狼肉", prov=PROV)
    comp = entry(77, "completion", COMPLETION_JA, prov=PROV)
    out = {ln["field"]: ln for ln in check_type([title, comp], scopes, set())}
    assert out["title"]["status"] == "rejected" and out["title"]["reasons"] == ["no_english_id"]
    assert out["title"]["english"] is None
    assert out["completion"]["status"] == "trusted"
