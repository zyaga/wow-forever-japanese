"""Draws the add-on's settings window to a picture, with Anki's own Qt and no Anki window, and prints what its
controls hold as JSON.

    <Anki's python> anki-addon/tests/settings_window.py <out folder>
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
ADDON = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ADDON))

from aqt.qt import QApplication  # noqa: E402
from wfj_anki import sync, text, ui  # noqa: E402
from wfj_anki.settings import Settings  # noqa: E402


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    app = QApplication.instance() or QApplication(sys.argv[:1])
    seen: dict[str, object] = {}
    for ja in (False, True):
        saved: list[Settings] = []
        result = sync.Result(added=3, updated=1, words=42, files=1, tables=1, missing_images=2)
        dialog = ui.SettingsDialog(
            None,
            Settings(folder="D:/Games/World of Warcraft", front="word"),
            lambda result=result, ja=ja: text.summary(result, ja),
            lambda folder: 2 if folder else 0,
            saved.append,
            lambda done: done(),
            ja,
        )
        dialog.show()
        app.processEvents()
        name = f"settings-{'ja' if ja else 'en'}.png"
        dialog.grab().save(str(out / name))
        dialog._accept()
        seen[name] = {
            "saved": [vars(s) for s in saved],
            "found": dialog.found.text(),
            "status": dialog.status.text(),
            "title": dialog.windowTitle(),
        }
        dialog.folder.setText("")
        dialog._look()
        seen[name]["empty"] = dialog.found.text()
    print(json.dumps(seen, ensure_ascii=False))


if __name__ == "__main__":
    main()
