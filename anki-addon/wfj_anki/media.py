"""A file of the game's, ready for Anki's media: its name there and its bytes.

A screenshot is the whole screen, often several megabytes, and every card's media is sent to AnkiWeb and to the
phone, so a picture is made smaller when Qt is there to do it. The sound files are small already and go as they are.
"""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

PREFIX = "wfj-"  # the add-on's files in the media folder, apart from the player's own
WIDEST = 1600  # pixels: wide enough to read the game's text on a card
SHOWN_AS_IS = {".jpg", ".jpeg", ".png"}  # what Anki can show without being converted

Shrink = Callable[[Path], "bytes | None"]


def sound(path: Path) -> tuple[str, bytes] | None:
    try:
        return PREFIX + path.name, path.read_bytes()
    except OSError:
        return None


def picture(path: Path, shrink: Shrink | None) -> tuple[str, bytes] | None:
    """`shrink(path)` gives the picture as a smaller JPEG, or None when it cannot read the file."""
    if not path.is_file():
        return None
    small = shrink(path) if shrink else None
    if small:
        return f"{PREFIX}{path.stem}.jpg", small
    if path.suffix.lower() not in SHOWN_AS_IS:
        return None
    try:
        return PREFIX + path.name, path.read_bytes()
    except OSError:
        return None


def qt_shrink(path: Path) -> bytes | None:
    """The picture no wider than WIDEST, as a JPEG, drawn by Qt (which Anki ships)."""
    from aqt.qt import QBuffer, QByteArray, QImage, QIODevice, Qt

    image = QImage(str(path))
    if image.isNull():
        return None
    if image.width() > WIDEST:
        image = image.scaledToWidth(WIDEST, Qt.TransformationMode.SmoothTransformation)
    data = QByteArray()
    buffer = QBuffer(data)
    buffer.open(QIODevice.OpenModeFlag.WriteOnly)
    if not image.save(buffer, "JPG", 85):
        return None
    return bytes(data.data())
