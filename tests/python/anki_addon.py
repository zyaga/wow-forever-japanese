"""Puts the Anki add-on's package on the import path for its tests, and names the folders they use."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "anki-addon"
FIXTURES = ROOT / "tests" / "fixtures" / "anki"

if str(ADDON) not in sys.path:
    sys.path.insert(0, str(ADDON))
