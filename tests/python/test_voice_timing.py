"""Where a voice line's sentences start and end, where it is cut into one file per sentence, and when each part of
its Japanese is spoken (ADR-090). Pure: the two models' times and the recording's pauses come in as numbers."""

from __future__ import annotations

import array
import math

from wfj.core import voice_timing as vt

TEXT = "よく来たな。話を聞いてくれ。"
# ReazonSpeech: one start per character of the engine text (the 。 is never timed)
RZ = {0: 0.10, 1: 0.20, 2: 0.30, 3: 0.40, 4: 0.50, 6: 1.30, 7: 1.40, 8: 1.50, 9: 1.60, 10: 1.70, 11: 1.80, 12: 1.90}
# Qwen: words as (first, end, start, end) in the engine text
QW = [(0, 2, 0.10, 0.28), (2, 5, 0.30, 0.60), (6, 8, 1.30, 1.48), (8, 13, 1.50, 2.00)]
PAUSES = [(0.70, 1.20)]


def parts(m: str) -> list[tuple[int, str]]:
    return [(int(n), dt) for n, dt in (p.split(":") for p in m.split())]


def starts(m: str) -> list[float | None]:
    out, clock = [], 0
    for _, dt in parts(m):
        if dt == "-":
            out.append(None)
        else:
            clock += int(dt)
            out.append(clock / 100)
    return out


# ── sentences ──────────────────────────────────────────────────────────────


def test_a_sentence_starts_at_its_first_spoken_character_after_a_full_stop_or_a_line_break():
    assert vt.sentence_starts("よく来たな。話を聞いてくれ。") == [0, 6]
    assert vt.sentence_starts("「行け！」\n\nそうだ") == [1, 7]
    assert vt.sentence_starts("本当か?素晴らしい") == [0, 4]


def test_a_run_of_marks_is_one_end_and_marks_alone_are_no_sentence():
    assert vt.sentence_starts("なに！？……。\n") == [0]


# ── pauses ─────────────────────────────────────────────────────────────────


def tone(seconds: float, rate: int, amp: int = 8000) -> list[int]:
    return [int(amp * math.sin(2 * math.pi * 220 * i / rate)) for i in range(int(seconds * rate))]


def test_a_pause_is_a_quiet_stretch_of_at_least_the_minimum_length():
    rate = 8000
    samples = array.array("h", tone(0.5, rate) + [0] * int(0.3 * rate) + tone(0.5, rate) + [0] * int(0.05 * rate)
                          + tone(0.5, rate))
    found = vt.pauses(samples, rate)
    assert len(found) == 1  # the 50 ms gap is too short to count
    start, end = found[0]
    assert abs(start - 0.5) < 0.02 and abs(end - 0.8) < 0.02


# ── cuts ───────────────────────────────────────────────────────────────────


def test_a_line_is_cut_in_the_middle_of_the_pause_before_each_sentence():
    assert vt.cuts(TEXT, RZ, QW, PAUSES, 2.2) == [0.95]


def test_no_cut_where_a_word_of_the_first_sentence_runs_past_the_cut():
    late = [(0, 2, 0.10, 0.28), (2, 5, 0.30, 1.10), (6, 8, 1.30, 1.48), (8, 13, 1.50, 2.00)]
    assert vt.cuts(TEXT, RZ, late, PAUSES, 2.2) == []


def test_no_cut_where_the_next_sentence_starts_before_the_cut():
    early = [(0, 2, 0.10, 0.28), (2, 5, 0.30, 0.60), (6, 8, 0.80, 1.48), (8, 13, 1.50, 2.00)]
    assert vt.cuts(TEXT, RZ, early, PAUSES, 2.2) == []


def test_no_cut_at_a_pause_shorter_than_the_minimum():
    assert vt.cuts(TEXT, RZ, QW, [(1.15, 1.25)], 2.2) == []


def test_no_cut_without_a_second_model_to_confirm_it():
    assert vt.cuts(TEXT, RZ, [], PAUSES, 2.2) == []


def test_cuts_rise_and_stay_inside_the_recording():
    text = "あ。い。う。"
    rz = {0: 0.1, 2: 1.1, 4: 2.1}
    qw = [(0, 1, 0.1, 0.4), (2, 3, 1.1, 1.4), (4, 5, 2.1, 2.4)]
    pauses = [(0.5, 1.0), (1.5, 2.0)]
    got = vt.cuts(text, rz, qw, pauses, 2.6)
    assert got == sorted(got) and len(got) == 2 and all(0 < c < 2.6 for c in got)


# ── timing ─────────────────────────────────────────────────────────────────


def test_the_timing_covers_every_character_of_the_shipped_japanese_in_order():
    m = vt.timing(TEXT, TEXT, RZ, QW, ["来た", "話", "聞いて"])
    assert sum(n for n, _ in parts(m)) == len(TEXT)


def test_a_part_starts_at_each_word_of_the_second_model_and_each_word_card_word():
    m = vt.timing(TEXT, TEXT, RZ, QW, ["聞いて"])
    lengths = [n for n, _ in parts(m)]
    # よく | 来たな。 | 話を | 聞いてくれ。  : 聞 starts a word card word inside Qwen's 聞いてくれ
    assert lengths == [2, 4, 2, 6]


def test_qwen_times_come_first_and_reazonspeech_fills_a_word_card_start_inside_a_qwen_word():
    m = vt.timing(TEXT, TEXT, RZ, QW, ["聞いて"])
    assert starts(m) == [0.10, 0.30, 1.30, 1.50]
    rz = {**RZ, 8: 1.62}
    m2 = vt.timing(TEXT, TEXT, rz, [(0, 2, 0.10, 0.28), (2, 5, 0.30, 0.60), (6, 13, 1.30, 2.00)], ["聞いて"])
    assert starts(m2)[-1] == 1.62


def test_times_never_go_backwards():
    m = vt.timing(TEXT, TEXT, RZ, [(0, 2, 0.10, 0.28), (2, 5, 0.30, 0.60), (6, 8, 0.20, 0.40)], [])
    got = [s for s in starts(m) if s is not None]
    assert got == sorted(got)


def test_a_stage_direction_the_voice_skips_and_blank_lines_are_unspoken():
    ja = "ふむ...\n\n<Kaltunkは笑った>\n\nきっとうまくゆく。"
    text = "ふむ...\n\n\n\nきっとうまくゆく。"
    rz = {0: 0.2, 1: 0.3, 9: 1.5, 10: 1.6}
    qw = [(0, 2, 0.2, 0.5), (9, 12, 1.5, 1.9), (12, 16, 1.9, 2.4)]
    m = vt.timing(ja, text, rz, qw, [])
    ps, st = parts(m), starts(m)
    assert sum(n for n, _ in ps) == len(ja)
    direction = ja.index("<")
    at, spoken_inside = 0, False
    for (n, _), s in zip(ps, st, strict=True):
        if at <= direction < at + n:
            spoken_inside = s is not None
        at += n
    assert not spoken_inside


def test_an_english_name_takes_the_time_its_katakana_is_spoken():
    ja = "Gornekに報告に行け。"
    text = "ゴーネクに報告に行け。"
    rz = {0: 0.2, 4: 0.6, 5: 0.7, 7: 0.9, 8: 1.0}
    qw = [(0, 4, 0.2, 0.55), (4, 5, 0.6, 0.65), (5, 7, 0.7, 0.85), (7, 8, 0.9, 0.95), (8, 10, 1.0, 1.3)]
    m = vt.timing(ja, text, rz, qw, [])
    assert parts(m)[0] == (6, "20")  # "Gornek" is one part, said at 0.20


def test_a_player_token_is_never_split():
    ja = "{name}よ、来い。"
    text = "冒険者よ、来い。"
    rz = {0: 0.1, 3: 0.5, 5: 0.8}
    qw = [(0, 3, 0.1, 0.45), (3, 4, 0.5, 0.6), (5, 7, 0.8, 1.1)]
    m = vt.timing(ja, text, rz, qw, [])
    at = 0
    for n, _ in parts(m):
        assert not (0 < at < len("{name}")), "a part starts inside the token"
        at += n
    assert sum(n for n, _ in parts(m)) == len(ja)


def test_the_string_holds_only_numbers_colons_dashes_and_spaces():
    m = vt.timing(TEXT, TEXT, RZ, QW, [])
    assert set(m) <= set("0123456789:- ")
