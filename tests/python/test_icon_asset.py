"""The addon's own icons are round: `Media/icon.tga` (the TOC's IconTexture, the medallion with its gold
rim) and `Media/minimap.tga` (the minimap button: the red disc and the character only, since the game's
ring is the rim there). Each is a 64×64 uncompressed 32-bit TGA whose corners are transparent. An opaque
file shows black corners in the AddOn List, so these tests guard the transparency."""

from pathlib import Path

import pytest

MEDIA = Path(__file__).resolve().parents[2] / "addon/WoWForeverJapanese/Media"
ICONS = ("icon.tga", "minimap.tga")


def _pixels(name):
    data = (MEDIA / name).read_bytes()
    id_len, cmap_type, image_type = data[0], data[1], data[2]
    width = data[12] | data[13] << 8
    height = data[14] | data[15] << 8
    bpp, descriptor = data[16], data[17]
    body = data[18 + id_len :]
    return cmap_type, image_type, width, height, bpp, descriptor, body


@pytest.mark.parametrize("name", ICONS)
def test_icon_is_a_64px_uncompressed_32bit_tga_with_alpha(name):
    cmap_type, image_type, width, height, bpp, descriptor, body = _pixels(name)
    assert (cmap_type, image_type) == (0, 2)  # true colour, uncompressed
    assert (width, height, bpp) == (64, 64, 32)
    assert descriptor & 0x0F == 8  # eight alpha bits
    assert len(body) >= width * height * 4


@pytest.mark.parametrize("name", ICONS)
def test_icon_corners_are_transparent_and_centre_opaque(name):
    _, _, width, _, _, _, body = _pixels(name)

    def alpha(x, y):  # BGRA; the row order does not matter for these symmetric probes
        return body[(y * width + x) * 4 + 3]

    for x, y in ((0, 0), (63, 0), (0, 63), (63, 63), (2, 2)):
        assert alpha(x, y) == 0, (x, y)
    assert alpha(32, 32) == 255


def test_the_minimap_icon_has_no_gold_rim():
    # the game's ring is the rim on the minimap: this file's own edge is the red disc, all the way round
    _, _, width, _, _, _, body = _pixels("minimap.tga")
    for x, y in ((32, 2), (32, 61), (2, 32), (61, 32)):
        b, g, r, a = body[(y * width + x) * 4 : (y * width + x) * 4 + 4]
        assert a > 200 and r > 2 * g and r > 2 * b, (x, y, r, g, b, a)
