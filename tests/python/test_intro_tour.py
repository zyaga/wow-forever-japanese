"""The welcome tour's pictures: every page names a file the addon ships, in the size the window draws."""

import re
import struct
from pathlib import Path

from wfj.dev import intro_images

ADDON = Path("addon") / "WoWForeverJapanese"
TOUR = ADDON / "Media" / "Tour"


def pages(root: Path) -> list[str]:
    """The pictures the welcome window's page list names, in order."""
    text = (root / ADDON / "UI" / "IntroWindow.lua").read_text("utf-8")
    body = text[text.index("IntroWindow.PAGES = {") : text.index("\n}\n", text.index("IntroWindow.PAGES = {"))]
    return re.findall(r'picture = "([a-z]+)"', body)


def test_every_page_has_a_picture_and_every_picture_a_page(root):
    named = pages(root)
    assert len(named) >= 6 and len(set(named)) == len(named)
    shipped = sorted(p.stem for p in (root / TOUR).glob("*.tga"))
    assert shipped == sorted(named)
    assert sorted(intro_images.BOXES) == sorted(named)


def test_a_picture_is_an_uncompressed_512_by_256_image_like_the_addons_icons(root):
    icon = (root / ADDON / "Media" / "icon.tga").read_bytes()
    for name in pages(root):
        data = (root / TOUR / f"{name}.tga").read_bytes()
        kind, width, height, bits, descriptor = struct.unpack_from("<xxB9xHHBB", data)
        assert (kind, width, height, bits) == (2, intro_images.WIDTH, intro_images.HEIGHT, 32), name
        assert descriptor == icon[17], name  # the same row order and alpha depth as the icons that load today
        assert len(data) == 18 + width * height * 4, name


def test_a_box_is_twice_as_wide_as_it_is_tall():
    for page, (_, _, _, width, height) in intro_images.BOXES.items():
        assert abs(width - 2 * height) <= 1, page


def test_the_converter_turns_a_top_down_bitmap_bottom_up():
    width, height = intro_images.WIDTH, intro_images.HEIGHT
    header = struct.pack("<2sIHHIIiiHHIIiiII", b"BM", 54 + width * height * 3, 0, 0, 54, 40, width, -height, 1, 24,
                         0, 0, 0, 0, 0, 0)
    top, rest = b"\x01\x02\x03" * width, b"\x09\x09\x09" * width * (height - 1)
    out = intro_images.tga(header + top + rest)
    assert out[18:22] == b"\x09\x09\x09\xff"  # the first row written is the picture's bottom row
    assert out[-4:] == b"\x01\x02\x03\xff"  # and the last is its top row
