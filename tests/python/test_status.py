import pytest

from wfj.core.align import load_allowlist
from wfj.core.status import Scope, decide

AL = load_allowlist("Health  # stat\n")
P = {"class": "human", "translator": "a", "source": "cqjt@1234567", "imported": "2026-09-13"}
QUEST = Scope(
    "quest",
    {
        "title": "Sharptalon's Claw",
        "objectives": "Bring Sharptalon's Claw to Senani Thunderheart at Splintertree Post.",
        "description": "Kill 10 Kobold Vermin. Six balconies.",
    },
    "pfquest@1",
)
ITEM = Scope("item", {"name": "Tough Jerky"}, "wago@1")


def line(ja, field="description", **kw):
    ln = {
        "id": 2,
        "field": field,
        "ja": ja,
        "status": "pending",
        "checks": [],
        "provenance": P,
        "english": None,
        "reasons": [],
        "conflicts": [],
    }
    ln.update(kw)
    return ln


CASES = [
    ("no scope", line("x"), None, "h", "rejected", ["no_english_id"], []),
    ("empty scope", line("x"), Scope("quest"), "h", "rejected", ["no_english_id"], []),
    ("chinese", line("见鬼去吧"), QUEST, "h", "rejected", ["not_japanese"], []),
    ("latin-only prose", line("Kill things"), QUEST, "h", "rejected", ["not_japanese"], []),
    (
        "trusted names+numbers",
        line("Kobold Verminを10匹倒し、Senani Thunderheartへ。バルコニーは6つ。"),
        QUEST,
        "h",
        "trusted",
        [],
        ["names", "numbers"],
    ),
    (
        "name missing",
        line("Silverwind RefugeのSenani Thunderheart"),
        QUEST,
        "h",
        "rejected",
        ["alignment_failed:Silverwind Refuge"],
        ["names"],
    ),
    (
        "number missing",
        line("Kobold Verminを8匹"),
        QUEST,
        "h",
        "rejected",
        ["numbers_changed:8"],
        ["names", "numbers"],
    ),
    ("nothing to check ships trusted", line("北へ向かえ。"), QUEST, "h", "trusted", [], []),
    (
        "completion: names yes, numbers not checked",
        line("Kobold Verminを99匹", field="completion"),
        QUEST,
        "h",
        "trusted",
        [],
        ["names"],
    ),
    (
        "item → unaligned, no name check",
        line("Stranglethorn Valeで祝福を受ける"),
        ITEM,
        "h",
        "unaligned",
        [],
        [],
    ),
    ("item chinese", line("见鬼"), ITEM, "h", "rejected", ["not_japanese"], []),
    (
        "stale on hash change",
        line("北へ向かえ。", english={"hash": "old", "src": "pfquest@0"}),
        QUEST,
        "new",
        "stale",
        [],
        [],
    ),
    (
        "same hash not stale",
        line("北へ向かえ。", english={"hash": "new", "src": "pfquest@0"}),
        QUEST,
        "new",
        "trusted",
        [],
        [],
    ),
    (
        "numbers changed beats stale",
        line("Kobold Verminを8匹", english={"hash": "old", "src": "pfquest@0"}),
        QUEST,
        "new",
        "rejected",
        ["numbers_changed:8"],
        ["names", "numbers"],
    ),
]


@pytest.mark.parametrize("name,ln,scope,cur,status,reasons,checks", CASES, ids=[c[0] for c in CASES])
def test_decision_table(name, ln, scope, cur, status, reasons, checks):
    d = decide(ln, scope, AL, cur)
    assert (d.status, d.reasons, d.checks) == (status, reasons, checks)


def test_conflict_ruling_by_rules_and_by_person():
    conflicted = line(
        "Silverwind RefugeのSenani Thunderheart", conflicts=[{"ja": "Senani Thunderheartへ", "provenance": P}]
    )
    d = decide(conflicted, QUEST, AL, "h")
    assert d.status == "trusted" and d.winner == 1
    both_bad = line("Silverwind Refugeへ", conflicts=[{"ja": "Darnassusへ", "provenance": P}])
    d = decide(both_bad, QUEST, AL, "h")
    assert d.status == "rejected" and d.reasons == ["duplicate_conflict"] and d.winner == 0
    ruled = line(
        "Silverwind Refuge",
        conflicts=[
            {
                "ja": "Darnassusへ",
                "provenance": P,
                "ruling": {"ruling": "accept", "by": "maintainer", "date": "2026-09-13"},
            }
        ],
    )
    d = decide(ruled, QUEST, AL, "h")
    assert d.winner == 1 and d.status == "rejected" and d.reasons == ["alignment_failed:Darnassus"]


def test_a_named_colour_code_is_markup_not_words():
    # the gossip option's quest prepend has no word of its own; its Japanese carries none either
    from wfj.core import status

    assert status._no_words("|cnPURE_BLUE_COLOR:%s|r %s")
    assert not status._no_words("|cnNORMAL_FONT_COLOR:Copy Layout|r")
    assert status._no_words("(%s)") and not status._no_words(None)


def test_dots_only_english_may_stay_dots_only(tmp_path):
    # check agrees with the draft lint: a quest line whose English is "..." may be "……"
    from wfj.cmd.check import build_scopes
    from wfj.io.jsonl_store import Store

    en = Store(tmp_path, english=True)
    en.save("quest", [{"id": 2, "field": "progress", "en": "...", "hash": "000c2356b6a1e74a", "src": "vmangos@1"},
                      {"id": 2, "field": "completion", "en": "Well done.", "hash": "1111111111111111",
                       "src": "vmangos@1"}])
    scope = build_scopes(en, "quest")[2]
    assert scope.dotted == frozenset({"progress"})
    d = decide(line("……", "progress"), scope, AL, "000c2356b6a1e74a")
    assert "not_japanese" not in d.reasons and d.status == "trusted"
    assert decide(line("……", "completion"), scope, AL, "1111111111111111").reasons == ["not_japanese"]


def test_an_item_line_that_is_only_a_name_ships_in_english_letters_only_under_a_ruling():
    accept = {"ruling": "accept", "by": "maintainer", "date": "2026-10-01"}
    assert decide(line("Umbrinoth"), ITEM, AL, "h").reasons == ["not_japanese"]
    d = decide(line("Umbrinoth", ruling=accept), ITEM, AL, "h")
    assert "not_japanese" not in d.reasons
