"""The voice files' MP3 frames, and a file snipped at frame boundaries into one file per sentence (ADR-090).

The packs' files are MPEG-2 layer III, constant bit rate, with no tag (LAME `-t`, voice_make.LAME): a plain
run of frames, each a fixed 576 samples. Snipping between two frames copies the bytes as they are, so the
pieces played back to back are the original file. A piece's first frame may lean on the frame before it (the
bit reservoir) and decode a little off for one frame; the cuts sit in the middle of a pause of at least
150 ms (core/voice_timing.MIN_CUT_PAUSE), so that frame is silence either way."""

from __future__ import annotations

from collections.abc import Sequence

# MPEG-2 layer III bit rates (kbps) by header index, and sample rates by index
_BITRATES = {1: 8, 2: 16, 3: 24, 4: 32, 5: 40, 6: 48, 7: 56, 8: 64, 9: 80, 10: 96, 11: 112, 12: 128, 13: 144,
             14: 160}
_RATES = {0: 22050, 1: 24000, 2: 16000}
SAMPLES_PER_FRAME = 576  # MPEG-2 layer III
# seconds a decoded voice MP3 runs behind the WAV it was made from, by sample rate: LAME's encoder and
# decoder delay (1,105 samples) plus the levelling limiter's 5 ms look-ahead, measured on files made by
# voice_make.to_levelled_mp3. A cut on the recording's clock is snipped this much later in the MP3.
LEAD = {22050: 0.055, 24000: 0.051}


class Mp3Error(ValueError):
    """A file that is not the plain run of MPEG-2 layer III frames the packs are made of."""


def frames(data: bytes) -> tuple[list[int], int, int]:
    """→ the byte offset of every frame, the sample rate, the samples per frame. Raises Mp3Error on a tag,
    a lost sync, another MPEG version or layer, a change of sample rate, or a last frame cut short."""
    offsets: list[int] = []
    rate = None
    i = 0
    while i < len(data):
        if i + 4 > len(data) or data[i] != 0xFF or (data[i + 1] & 0xE0) != 0xE0:
            raise Mp3Error(f"no frame at byte {i}")
        b1, b2 = data[i + 1], data[i + 2]
        version, layer = (b1 >> 3) & 3, (b1 >> 1) & 3
        if version != 2 or layer != 1:
            raise Mp3Error(f"frame at byte {i} is not MPEG-2 layer III")
        bitrate, here = _BITRATES.get(b2 >> 4), _RATES.get((b2 >> 2) & 3)
        if bitrate is None or here is None:
            raise Mp3Error(f"frame at byte {i} has no bit rate or sample rate")
        if rate is None:
            rate = here
        elif here != rate:
            raise Mp3Error(f"frame at byte {i} changes the sample rate")
        size = 72000 * bitrate // here + ((b2 >> 1) & 1)
        if i + size > len(data):
            raise Mp3Error(f"the last frame, at byte {i}, is cut short")
        offsets.append(i)
        i += size
    if rate is None:
        raise Mp3Error("no frames")
    return offsets, rate, SAMPLES_PER_FRAME


def header(data: bytes) -> tuple[int, int]:
    """→ the sample rate and bit rate (kbps) the first frame names. Raises Mp3Error when there is none."""
    if len(data) < 4 or data[0] != 0xFF or (data[1] & 0xE0) != 0xE0 or ((data[1] >> 3) & 3) != 2:
        raise Mp3Error("no MPEG-2 frame at the start")
    rate, kbps = _RATES.get((data[2] >> 2) & 3), _BITRATES.get(data[2] >> 4)
    if rate is None or kbps is None:
        raise Mp3Error("the first frame has no bit rate or sample rate")
    return rate, kbps


def lead(data: bytes) -> float:
    """The seconds a file runs behind its recording (LEAD at the file's sample rate)."""
    return LEAD[header(data)[0]]


def split(data: bytes, cuts: Sequence[float]) -> list[tuple[bytes, float]]:
    """The file snipped at the frame nearest each cut (seconds on the recording's clock, the file's LEAD
    later in the MP3) → [(piece, seconds)]. A cut that would make an empty piece (at an edge, or on the same
    frame as another) is skipped."""
    offsets, rate, per = frames(data)
    at = sorted({round((c + LEAD[rate]) * rate / per) for c in cuts})
    at = [k for k in at if 0 < k < len(offsets)]
    bounds = [0, *at, len(offsets)]
    out = []
    for a, b in zip(bounds, bounds[1:], strict=False):
        end = offsets[b] if b < len(offsets) else len(data)
        out.append((data[offsets[a]:end], (b - a) * per / rate))
    return out
