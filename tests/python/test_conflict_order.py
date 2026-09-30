"""`check` stores `conflicts` in one canonical order, so a line reaches the same bytes whatever
history produced it (a fresh rebuild, or a promotion after a draft import), and the order never changes what
ships."""

import copy
import json

from wfj.cmd.check import build_scopes, check_type
from wfj.core import dedupe
from wfj.core.align import load_allowlist
from wfj.io.jsonl_store import Store

HUMAN = {
    "class": "human",
    "translator": "questjapanizer-wiki",
    "source": "cqjt@3446c82",
    "imported": "2026-09-13",
}
CORRECTION = {
    "class": "correction",
    "translator": "questjapanizer-wiki",
    "source": "correction@2026-09-14",
    "imported": "2026-09-14",
    "corrects": "cqjt@3446c82",
    "note": "misspelling",
}
MACHINE = {
    "class": "machine",
    "model": "draft-model-1",
    "source": "draft-completion-sg3@2026-09-15",
    "imported": "2026-09-15",
}


def _v(ja, prov):
    return {"ja": ja, "provenance": dict(prov)}


def test_order_is_hand_written_then_machine_then_source_translator_text():
    m, h, c = _v("m", MACHINE), _v("h", HUMAN), _v("c", CORRECTION)
    other = _v("o", {"class": "unknown-class", "source": "a"})
    h2 = _v("a", HUMAN)
    assert dedupe.canonical_conflicts([other, m, c, h, h2]) == [h2, h, c, m, other]


def test_same_variants_through_two_histories_check_to_the_same_bytes():
    """Quest 592 completion as it happened: a fresh rebuild holds the human line with the correction and the
    machine draft as conflicts; the committed history had the correction promoted first, the draft appended,
    then the draft promoted. Both check to identical lines."""
    rejected = {"ruling": "reject", "by": "maintainer", "date": "2026-09-15", "note": "held back"}
    base = {"id": 592, "field": "completion", "status": "pending", "checks": [], "english": None}
    base["reasons"] = []
    rebuild = {
        **base,
        "ja": "ついにZannzil",
        "provenance": dict(HUMAN),
        "conflicts": [
            {**_v("ついにZanzil", CORRECTION), "ruling": rejected},
            _v("やり遂げた", MACHINE),
        ],
        "ruling": rejected,
    }
    history = {
        **base,
        "ja": "ついにZanzil",
        "provenance": dict(CORRECTION),
        "conflicts": [
            {**_v("ついにZannzil", HUMAN), "ruling": rejected},
            _v("やり遂げた", MACHINE),
        ],
        "ruling": rejected,
    }
    # `check` promotes the winning draft (index 2 in both) and stores the canonical order
    promoted_a = dedupe.promote(rebuild, 2)
    promoted_b = dedupe.promote(history, 2)
    assert promoted_a["conflicts"] != promoted_b["conflicts"]  # the order each history leaves behind
    for ln in (promoted_a, promoted_b):
        ln["conflicts"] = dedupe.canonical_conflicts(ln["conflicts"])
    assert json.dumps(promoted_a, ensure_ascii=False) == json.dumps(promoted_b, ensure_ascii=False)


def test_check_stores_the_canonical_order():
    line = {
        "id": 1, "field": "title", "ja": "a", "status": "pending", "checks": [], "provenance": dict(HUMAN),
        "english": None, "reasons": [], "conflicts": [_v("m", MACHINE), _v("c", CORRECTION)],
    }
    (out,) = check_type([line], {}, set())
    assert [c["ja"] for c in out["conflicts"]] == ["c", "m"]


def test_order_changes_nothing_that_ships_on_the_real_data(root):
    """Every multi-variant line of the committed data, with its conflicts reversed, checks to exactly the line
    the committed order checks to: the order decides nothing (winner, status, reasons)."""
    store, english = Store(root / "data"), Store(root / "data", english=True)
    allowlist = load_allowlist((root / "pipeline/allowlist.txt").read_text(encoding="utf-8"))
    checked = 0
    for type_ in ("quest", "item", "spell"):
        scopes = build_scopes(english, type_)
        lines = [ln for ln in store.load(type_) if len(ln.get("conflicts") or []) >= 2]
        expected = check_type(copy.deepcopy(lines), scopes, allowlist)
        permuted = []
        for ln in copy.deepcopy(lines):
            ln["conflicts"] = list(reversed(ln["conflicts"]))
            permuted.append(ln)
        got = check_type(permuted, scopes, allowlist)
        for e, g in zip(expected, got, strict=True):
            for key in ("ja", "provenance", "status", "reasons", "checks", "english", "ruling"):
                assert e.get(key) == g.get(key), (type_, e["id"], e["field"], key)
            same = json.dumps(e, ensure_ascii=False) == json.dumps(g, ensure_ascii=False)
            assert same, (e["id"], e["field"])
            checked += 1
    assert checked >= 50  # 49 quest + 1 spell lines when this floor was set


def test_variants_alike_but_for_a_ruling_still_sort_one_way():
    """The whole variant is the last key, so the order never falls back to history."""
    a = {**_v("x", HUMAN), "ruling": {"ruling": "reject", "by": "maintainer", "date": "2026-09-16"}}
    b = _v("x", HUMAN)
    assert dedupe.canonical_conflicts([a, b]) == dedupe.canonical_conflicts([b, a])
