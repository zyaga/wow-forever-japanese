"""WoW Forever Japanese for Anki: the words saved in the game become cards, with their images and audio.

Inside Anki this starts the add-on. Outside it (the tests import the modules that do not need Anki) it does
nothing.
"""

try:
    from aqt import mw
except ImportError:
    mw = None

if mw is not None:
    from . import ui

    ui.start()
