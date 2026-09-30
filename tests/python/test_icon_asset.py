"""The addon's own icon (`Media/icon.tga`, the TOC's IconTexture and the minimap button) is a
round medallion: a 64×64 uncompressed 32-bit TGA whose corners are transparent. An opaque file shows
black corners in the AddOn List (the minimap ring hides them), so this test guards the transparency."""

from pathlib import Path

ICON = Path(__file__).resolve().parents[2] / "addon/WoWForeverJapanese/Media/icon.tga"


def _pixels():
    data = ICON.read_bytes()
    id_len, cmap_type, image_type = data[0], data[1], data[2]
    width = data[12] | data[13] << 8
    height = data[14] | data[15] << 8
    bpp, descriptor = data[16], data[17]
    body = data[18 + id_len :]
    return cmap_type, image_type, width, height, bpp, descriptor, body


def test_icon_is_a_64px_uncompressed_32bit_tga_with_alpha():
    cmap_type, image_type, width, height, bpp, descriptor, body = _pixels()
    assert (cmap_type, image_type) == (0, 2)  # true colour, uncompressed
    assert (width, height, bpp) == (64, 64, 32)
    assert descriptor & 0x0F == 8  # eight alpha bits
    assert len(body) >= width * height * 4


def test_icon_corners_are_transparent_and_centre_opaque():
    _, _, width, _, _, _, body = _pixels()

    def alpha(x, y):  # BGRA; the row order does not matter for these symmetric probes
        return body[(y * width + x) * 4 + 3]

    for x, y in ((0, 0), (63, 0), (0, 63), (63, 63), (2, 2)):
        assert alpha(x, y) == 0, (x, y)
    assert alpha(32, 32) == 255
