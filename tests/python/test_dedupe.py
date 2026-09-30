from wfj.core.dedupe import Candidate, promote, resolve, variants

P = {"class": "human", "translator": "a", "source": "cqjt@1234567", "imported": "2026-09-13"}


def _line(ja, *conflicts, ruling=None):
    ln = {
        "id": 1,
        "field": "description",
        "ja": ja,
        "status": "pending",
        "checks": [],
        "provenance": P,
        "english": None,
        "reasons": [],
        "conflicts": [dict(c) for c in conflicts],
    }
    if ruling:
        ln["ruling"] = ruling
    return ln


def test_single_variant_wins():
    assert resolve(variants(_line("a")), lambda c: False) == 0


def test_exactly_one_passing_wins_else_none():
    line = _line("bad", {"ja": "good", "provenance": P}, {"ja": "bad2", "provenance": P})
    assert resolve(variants(line), lambda c: c.ja == "good") == 1
    assert resolve(variants(line), lambda c: False) is None
    assert resolve(variants(line), lambda c: c.ja.startswith("bad")) is None


def test_human_ruling_overrides_rules():
    r = {"ruling": "accept", "by": "maintainer", "date": "2026-09-13"}
    line = _line("x", {"ja": "y", "provenance": P, "ruling": r})
    assert resolve(variants(line), lambda c: c.ja == "x") == 1
    rej = {"ruling": "reject", "by": "maintainer", "date": "2026-09-13"}
    line = _line("x", {"ja": "y", "provenance": P, "ruling": rej})
    assert resolve(variants(line), lambda c: True) == 0  # y rejected by a person, x is the only passer


def test_promote_keeps_displaced_variant():
    line = _line("old", {"ja": "new", "provenance": {**P, "translator": "b"}, "extra": {"short": "s"}})
    line["extra"] = {"short": "old-short"}
    new = promote(line, 1)
    assert new["ja"] == "new" and new["provenance"]["translator"] == "b" and new["extra"] == {"short": "s"}
    assert new["conflicts"][0] == {"ja": "old", "provenance": P, "extra": {"short": "old-short"}}
    assert promote(line, 0) is line
    assert isinstance(variants(line)[0], Candidate)
