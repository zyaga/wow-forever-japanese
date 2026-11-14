"""The checks a run of the aligners on rented cards makes on every batch it brings back (ADR-090): a wrong
batch stops the run before it costs more."""

from __future__ import annotations

from wfj.core import align_checks

CHARS = {"0": 0.10, "1": 0.20, "2": 0.30, "4": 1.00, "5": 1.10}
WORDS = [[0, 2, 0.08, 0.28], [2, 4, 0.32, 0.90], [4, 6, 0.96, 1.40]]
ROW = ("a", CHARS, WORDS, "")
SECONDS = {"a": 1.5, "b": 1.5, "c": 1.5}


def test_a_good_batch_passes():
    assert align_checks.check([ROW], SECONDS, {"a": CHARS}, {"a": WORDS}) == ""


def test_models_that_disagree_stop_the_run():
    far = [[0, 2, 0.60, 0.80], [2, 4, 0.90, 1.00], [4, 6, 1.40, 1.45]]
    assert "agree on" in align_checks.check([("a", CHARS, far, "")], SECONDS, {}, {})


def test_an_answer_unlike_the_macs_stops_the_run():
    late = {k: v + 0.05 for k, v in CHARS.items()}
    assert "ReazonSpeech differs" in align_checks.check([("a", late, WORDS, "")], SECONDS, {"a": CHARS}, {})
    one_step = [[0, 2, 0.16, 0.28], *WORDS[1:]]  # Qwen one 80 ms step off on one word: passes
    assert align_checks.check([("a", CHARS, one_step, "")], SECONDS, {}, {"a": WORDS}) == ""
    missing = WORDS[:1]
    assert "Qwen differs" in align_checks.check([("a", CHARS, missing, "")], SECONDS, {}, {"a": WORDS})


def test_times_out_of_order_or_past_the_recording_stop_the_run():
    back = {**CHARS, "5": 0.50}
    assert "out of order" in align_checks.check([("a", back, WORDS, "")], SECONDS, {}, {})
    assert "out of order" in align_checks.check([ROW], {"a": 1.0}, {}, {})


def test_a_few_empty_lines_pass_and_more_stop_the_run():
    empty = [(s, None, None, "boom") for s in "bc"]
    assert align_checks.check([ROW, *empty], SECONDS, {}, {}) == ""
    assert "no answer" in align_checks.check([ROW, *empty, ("d", {}, WORDS, "")], {**SECONDS, "d": 1.5}, {}, {})
