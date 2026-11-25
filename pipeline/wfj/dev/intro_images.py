"""The welcome tour's pictures (docs/systems/settings.md): cuts each source screenshot to its box, scales it
to 512 x 256 and writes it as `Media/Tour/<page>.tga`, in the layout the addon's own icons already load in
(uncompressed, 32 bits a pixel, rows from the bottom up).

    python -m wfj.dev.intro_images <repo root>

Sources are `docs/images/tour/<page>.<png|jpg>`. A box is (left, top, width, height) in the
source's pixels and is twice as wide as it is tall. The cutting and scaling are done by `sips`, the image tool
macOS ships, so nothing is installed; run it on a Mac.
"""

from __future__ import annotations

import struct
import subprocess
import sys
import tempfile
from pathlib import Path

WIDTH, HEIGHT = 512, 256
SOURCES = Path("docs") / "images" / "tour"
OUT = Path("addon") / "WoWForeverJapanese" / "Media" / "Tour"

# page -> (source file, left, top, width, height)
BOXES: dict[str, tuple[str, int, int, int, int]] = {
    "start": ("start.jpg", 0, 120, 590, 295),
    "cards": ("cards.jpg", 0, 24, 585, 292),
    "status": ("status.jpg", 0, 24, 585, 292),
    "freeze": ("freeze.jpg", 0, 24, 585, 292),
    "chat": ("chat.png", 0, 22, 857, 428),
    "more": ("more.png", 0, 20, 590, 295),
}


def tga(bmp: bytes) -> bytes:
    """An uncompressed BMP of WIDTH x HEIGHT (24 or 32 bits a pixel) as a 32-bit TGA with its rows from the
    bottom up and every pixel opaque. A BMP with a negative height holds its rows from the top down."""
    offset = struct.unpack_from("<I", bmp, 10)[0]
    width, height, _, bits = struct.unpack_from("<iiHH", bmp, 18)
    if (width, abs(height)) != (WIDTH, HEIGHT) or bits not in (24, 32):
        raise ValueError(f"expected a {WIDTH} x {HEIGHT} picture, got {width} x {height}, {bits} bits")
    step = bits // 8
    row = (WIDTH * step + 3) // 4 * 4
    out = bytearray(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, WIDTH, HEIGHT, 32, 8))
    rows = range(HEIGHT) if height > 0 else range(HEIGHT - 1, -1, -1)
    for y in rows:
        line = bmp[offset + y * row : offset + y * row + WIDTH * step]
        for x in range(WIDTH):
            out += line[x * step : x * step + 3] + b"\xff"
    return bytes(out)


def build(root: Path, page: str) -> Path:
    name, left, top, width, height = BOXES[page]
    source = root / SOURCES / name
    if not source.is_file():
        raise FileNotFoundError(f"{source}: the {page} page has no source picture")
    with tempfile.TemporaryDirectory() as tmp:
        cut, small = Path(tmp) / "cut.png", Path(tmp) / "small.bmp"
        subprocess.run(
            ["sips", "-c", str(height), str(width), "--cropOffset", str(top), str(left),
             "-s", "format", "png", str(source), "--out", str(cut)],
            check=True, capture_output=True,
        )
        subprocess.run(
            ["sips", "-z", str(HEIGHT), str(WIDTH), "-s", "format", "bmp", str(cut), "--out", str(small)],
            check=True, capture_output=True,
        )
        target = root / OUT / f"{page}.tga"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(tga(small.read_bytes()))
    return target


def main() -> None:
    root = Path(sys.argv[1]).resolve()
    for page in BOXES:
        print(build(root, page).relative_to(root))


if __name__ == "__main__":
    main()
