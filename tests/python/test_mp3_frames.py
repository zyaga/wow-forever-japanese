"""A voice file is snipped into one file per sentence at MP3 frame boundaries when the packs are built
(ADR-090): a byte-exact copy, so the pieces played back to back are the original file."""

from __future__ import annotations

import pytest

from wfj.core import mp3_frames

RATE = 22050


def frame(padding: int = 0) -> bytes:
    """One MPEG-2 layer III frame at 32 kbps, 22.05 kHz, mono, as LAME writes the packs' files."""
    b1 = 0xF3  # sync, MPEG-2, layer III, no CRC
    b2 = (4 << 4) | (0 << 2) | (padding << 1)  # 32 kbps, 22.05 kHz
    b3 = 0xC0  # mono
    size = 72000 * 32 // RATE + padding
    return bytes([0xFF, b1, b2, b3]) + bytes([0x11]) * (size - 4)


def mp3(n: int) -> bytes:
    return b"".join(frame(i % 3 == 0) for i in range(n))


def test_frames_are_read_with_the_rate_and_samples_per_frame():
    offsets, rate, per = mp3_frames.frames(mp3(10))
    assert len(offsets) == 10 and rate == RATE and per == 576
    assert offsets[0] == 0 and offsets == sorted(offsets)


def test_the_pieces_are_the_original_bytes_in_order():
    data = mp3(200)
    pieces = mp3_frames.split(data, [1.0, 3.5])
    assert len(pieces) == 3
    assert b"".join(p for p, _ in pieces) == data


def test_each_piece_has_its_exact_length_and_they_add_up():
    data = mp3(200)
    pieces = mp3_frames.split(data, [1.0, 3.5])
    assert sum(s for _, s in pieces) == pytest.approx(200 * 576 / RATE)
    assert pieces[0][1] == pytest.approx(round((1.0 + mp3_frames.LEAD[RATE]) * RATE / 576) * 576 / RATE)


def test_no_cuts_is_one_piece_the_whole_file():
    data = mp3(50)
    assert mp3_frames.split(data, []) == [(data, pytest.approx(50 * 576 / RATE))]


def test_a_cut_at_the_edges_or_twice_on_one_frame_makes_no_empty_piece():
    data = mp3(100)
    pieces = mp3_frames.split(data, [0.0, 1.0, 1.001, 99.0])
    assert all(p for p, _ in pieces) and b"".join(p for p, _ in pieces) == data


@pytest.mark.parametrize("bad", [
    b"ID3" + bytes(20) + mp3(5),  # a tag LAME writes without -t
    mp3(5)[:-3],  # cut short
    bytes([0xFF, 0xFB, 0x50, 0xC0]) + bytes(200),  # MPEG-1: not what the packs are made with
    b"\x00\x00" + mp3(5),  # no sync at the start
])
def test_a_file_it_cannot_read_frame_by_frame_is_refused(bad):
    with pytest.raises(mp3_frames.Mp3Error):
        mp3_frames.split(bad, [0.05])
