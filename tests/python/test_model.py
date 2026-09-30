from wfj.core.model import FIELDS, english_line, entry, provenance, validate_line

PROV = provenance("human", "cqjt@3446c82", "2026-09-13", translator="Tammy", origins=["cqjt@3446c82#1"])


def test_entry_valid():
    assert validate_line("quest", entry(2, "title", "x", prov=PROV)) == []
    assert (
        validate_line("item", entry(117, "description", "x", prov=PROV, extra={"short": "s"})) == []
    )


def test_key_order_is_fixed():
    assert list(entry(2, "title", "x", prov=PROV)) == [
        "id",
        "field",
        "ja",
        "status",
        "checks",
        "provenance",
        "english",
        "reasons",
        "conflicts",
    ]


def test_validate_negatives():
    bad = entry(2, "title", "x", prov=PROV)
    bad["status"] = "nope"
    assert any("status" in p for p in validate_line("quest", bad))
    bad = entry(2, "nofield", "x", prov=PROV)
    assert any("field" in p for p in validate_line("quest", bad))
    bad = entry("2", "title", "x", prov=PROV)
    assert any("id" in p for p in validate_line("quest", bad))
    bad = entry(2, "title", "x", prov=provenance("human", "cqjt@3446c82", "2026-09-13"))
    assert any("translator" in p for p in validate_line("quest", bad))
    bad = entry(2, "title", "x", prov=provenance("human", "bad source", "2026-09-13", translator="t"))
    assert any("source" in p for p in validate_line("quest", bad))
    bad = entry(2, "title", "x", prov=PROV)
    bad["conflicts"] = [{"ja": "y"}]
    assert any("conflict" in p for p in validate_line("quest", bad))
    bad = entry(2, "title", "x", prov=PROV)
    bad["surprise"] = 1
    assert any("unexpected" in p for p in validate_line("quest", bad))
    assert validate_line("nope", {}) == ["unknown type 'nope'"]


def test_english_line_valid_and_negatives():
    ok = english_line(2, "title", "Sharptalon's Claw", "0" * 16, "pfquest@7786596")
    assert validate_line("quest", ok, english=True) == []
    assert (
        validate_line(
            "item", english_line(117, "name", "Tough Jerky", "a" * 16, "wago@1.15.9.69722"), english=True
        )
        == []
    )
    bad = dict(ok, hash="xyz")
    assert any("hash" in p for p in validate_line("quest", bad, english=True))
    bad = dict(ok, en="")
    assert any("en" in p for p in validate_line("quest", bad, english=True))


def test_gossip_ids_are_keys():
    assert validate_line("gossip", entry("0123456789abcdef", "text", "x", prov=PROV)) == []
    assert any("gossip id" in p for p in validate_line("gossip", entry(5, "text", "x", prov=PROV)))


def test_fields_table_shape():
    assert FIELDS["quest"] == ["title", "objectives", "description", "progress", "completion"]


def test_fix_report_provenance_fields():
    """ADR-045: `report` (the issue number) on correction / machine, `model` on a correction."""
    corr = {"class": "correction", "translator": "Kaori", "source": "correction@2026-09-28", "imported": "2026-09-28",
            "corrects": "cqjt@3446c82", "report": 12}
    mach = {"class": "machine", "model": "m", "source": "report-12-sg9@2026-09-28", "imported": "2026-09-28", "report": 12}
    assert validate_line("quest", entry(2, "title", "x", prov=corr)) == []
    assert validate_line("quest", entry(2, "title", "x", prov=corr | {"model": "model-x"})) == []
    assert validate_line("quest", entry(2, "title", "x", prov=mach)) == []
    for bad, why in (
        (corr | {"report": 0}, "positive int"),
        (corr | {"report": "12"}, "positive int"),
        (corr | {"report": True}, "positive int"),
        (PROV | {"report": 12}, "only on correction or machine"),
        (corr | {"model": ""}, "model must be a non-empty string"),
        (corr | {"model": 5}, "model must be a non-empty string"),
    ):
        assert any(why in p for p in validate_line("quest", entry(2, "title", "x", prov=bad))), bad
