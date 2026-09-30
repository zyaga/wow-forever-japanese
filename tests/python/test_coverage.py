"""`make coverage`: docs/operations/coverage.md measures what ships from the served English."""

from pathlib import Path

from wfj.dev import coverage


def test_nothing_to_translate_classes():
    why = coverage.nothing_to_translate("quest", "Kill 10 boars.", "<UNUSED> Test")
    assert why == "placeholder quest (never shown)"
    assert coverage.nothing_to_translate("quest", "Kill 10 boars.", "The Boar Hunt") is None
    assert coverage.nothing_to_translate("book", "Missing Text", None)
    assert coverage.nothing_to_translate("book", '<HTML><BODY><IMG src="x"/></BODY></HTML>', None)
    assert coverage.nothing_to_translate("book", "01101 10010", None)
    assert coverage.nothing_to_translate("book", "A page of prose.", None) is None


def test_the_committed_report_is_current(root: Path):
    # every data change re-runs `make coverage`: the committed doc matches the store (the date line aside)
    committed = (root / "docs" / "operations" / "coverage.md").read_text(encoding="utf-8")
    fresh = coverage.render(coverage.measure(root / "data"), "X")
    strip = lambda text: [ln for ln in text.splitlines() if not ln.startswith("> **Generated**")]  # noqa: E731
    assert strip(committed) == strip(fresh), "run `make coverage` and commit docs/operations/coverage.md"
