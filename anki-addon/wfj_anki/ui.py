"""The add-on inside Anki: when a sync runs, the menu lines, the browser's reset action and the settings
window.
The only module, with `__init__`, that touches Anki's windows."""

from __future__ import annotations

import platform
from collections.abc import Callable
from pathlib import Path
from typing import Any

import anki.lang
import aqt
from aqt import gui_hooks, mw
from aqt.operations import QueryOp, on_op_finished
from aqt.qt import (
    QAction,
    QButtonGroup,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMenu,
    QPushButton,
    QRadioButton,
    Qt,
    QVBoxLayout,
    QWidget,
    qconnect,
)
from aqt.utils import showWarning, tooltip

from . import discover, media, sync, text
from .collection import AnkiNotes
from .settings import AUDIOS, FRONTS, Settings, from_config, to_config

MODULE = __name__.split(".")[0]


def japanese() -> bool:
    return anki.lang.current_lang.startswith("ja")


def t(key: str, **values: object) -> str:
    return text.get(key, japanese(), **values)


# ── When a sync runs ────────────────────────────────────────────────────────


class Syncer:
    """A sync runs when a profile opens, when Anki becomes the active application and when the player asks. It
    is
    passed over while nothing changed since the last one, and waits while a card is being studied: adding
    notes
    then would redraw the card under the player."""

    def __init__(self) -> None:
        self.running = False
        self.waiting = False
        self.seen: tuple[Any, ...] | None = None  # the saved files and the settings of the last sync
        self.last: sync.Result | None = None
        self.problem = ""
        self.found: tuple[str, list[discover.SavedFile]] | None = None  # the folder setting and what it gave

    def profile_opened(self) -> None:
        """Another profile is another collection: nothing a sync learned about the last one holds for it."""
        self.seen, self.last, self.problem = None, None, ""
        self.request()

    def settings(self) -> Settings:
        return from_config(mw.addonManager.getConfig(MODULE))

    def files(self, settings: Settings, look: bool = False) -> list[discover.SavedFile]:
        """The saved files to read. Looking for the game walks every drive, which can wait on a sleeping one,
        and this runs each time Anki comes to the front: so the files found once are used while they are still
        there, and the search runs again only when the player asks or the folder setting changes."""
        kept = self.found
        usable = not look and kept is not None and kept[0] == settings.folder and bool(kept[1])
        if usable and all(f.path.is_file() for f in kept[1]):
            return kept[1]
        files = discover.find(settings.folder, platform.system(), Path.home())
        self.found = (settings.folder, files)
        return files

    def request(self, asked: bool = False, done: Callable[[], None] | None = None) -> None:
        if mw.col is None or self.running:
            return
        if mw.state == "review" and not asked:
            self.waiting = True
            return
        self.waiting = False
        settings = self.settings()
        files = self.files(settings, look=asked)
        seen = (discover.signature(files), settings)
        if not sync.due(seen, self.seen, self.last, asked):
            return
        self._run(settings, files, seen, None, asked, done)

    def reset(self, note_ids: list[Any]) -> None:
        if mw.col is None or self.running:
            return
        settings = self.settings()
        self._run(settings, self.files(settings), None, note_ids, True, None)

    def _run(
        self,
        settings: Settings,
        files: list[discover.SavedFile],
        seen: tuple[Any, ...] | None,
        reset_ids: list[Any] | None,
        asked: bool,
        done: Callable[[], None] | None,
    ) -> None:
        self.running = True

        def work(col: Any) -> tuple[sync.Result, Any, bool]:
            notes = AnkiNotes(col, settings, shrink=media.qt_shrink)
            prepared = notes.prepare()
            reset = notes.keys_of(reset_ids) if reset_ids is not None else None
            result = sync.apply(notes, sync.read(files), reset=reset)
            return result, notes.finish(), prepared

        def finished(outcome: tuple[sync.Result, Any, bool]) -> None:
            result, changes, prepared = outcome
            self.running = False
            self.problem = ""
            if reset_ids is None:
                self.last, self.seen = result, seen
            if changes is not None:
                on_op_finished(mw, changes, self)
            elif prepared:
                mw.reset()
            if reset_ids is not None:
                tooltip(t("tip_reset", updated=result.updated))
            elif result.added or result.updated:
                tooltip(t("tip_added", added=result.added, updated=result.updated))
            elif asked and done is None:
                tooltip(text.summary(result, japanese()))
            if done:
                done()

        def failed(error: Exception) -> None:
            self.running = False
            self.problem = t("failed", error=str(error))
            if asked:
                showWarning(self.problem)
            if done:
                done()

        QueryOp(parent=mw, op=work, success=finished).failure(failed).run_in_background()

    def summary(self) -> str:
        return self.problem or text.summary(self.last, japanese())


syncer = Syncer()


# ── The settings window ─────────────────────────────────────────────────────


class SettingsDialog(QDialog):
    def __init__(
        self,
        parent: QWidget | None,
        settings: Settings,
        summary: Callable[[], str],
        count: Callable[[str], int],
        save: Callable[[Settings], None],
        sync_now: Callable[[Callable[[], None]], None],
        ja: bool,
    ):
        super().__init__(parent)
        self._summary, self._count, self._save, self._sync_now, self._ja = summary, count, save, sync_now, ja
        say = lambda key, **values: text.get(key, ja, **values)  # noqa: E731
        self._say = say
        self.setWindowTitle(say("title"))
        self.setMinimumWidth(560)
        box = QVBoxLayout(self)
        box.setSpacing(10)

        intro = QLabel(say("intro"))
        intro.setWordWrap(True)
        box.addWidget(intro)

        box.addWidget(self._heading(say("folder")))
        row = QHBoxLayout()
        self.folder = QLineEdit(settings.folder)
        self.folder.setPlaceholderText(say("folder_hint"))
        browse = QPushButton(say("browse"))
        qconnect(browse.clicked, self._browse)
        qconnect(self.folder.editingFinished, self._look)
        row.addWidget(self.folder)
        row.addWidget(browse)
        box.addLayout(row)
        self.found = QLabel("")
        self.found.setWordWrap(True)
        box.addWidget(self.found)

        box.addWidget(self._heading(say("front")))
        self.front = self._choices(box, FRONTS, ("front_sentence", "front_word"), settings.front)
        box.addWidget(self._heading(say("audio")))
        self.audio = self._choices(box, AUDIOS, ("audio_back", "audio_front"), settings.audio)
        hint = QLabel(say("choices_hint"))
        hint.setWordWrap(True)
        hint.setEnabled(False)
        box.addWidget(hint)

        self.status = QLabel("")
        self.status.setWordWrap(True)
        self.status.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        box.addWidget(self._heading(say("last")))
        box.addWidget(self.status)

        buttons = QDialogButtonBox()
        self.sync_button = buttons.addButton(say("sync"), QDialogButtonBox.ButtonRole.ActionRole)
        save_button = buttons.addButton(say("save"), QDialogButtonBox.ButtonRole.AcceptRole)
        close = buttons.addButton(say("close"), QDialogButtonBox.ButtonRole.RejectRole)
        qconnect(self.sync_button.clicked, self._sync)
        qconnect(save_button.clicked, self._accept)
        qconnect(close.clicked, self.reject)
        box.addWidget(buttons)
        self._look()
        self.refresh()

    def _heading(self, words: str) -> QLabel:
        label = QLabel(f"<b>{words}</b>")
        label.setContentsMargins(0, 8, 0, 0)
        return label

    def _choices(
        self, box: QVBoxLayout, values: tuple[str, ...], keys: tuple[str, ...], chosen: str
    ) -> QButtonGroup:
        group = QButtonGroup(self)
        for index, (value, key) in enumerate(zip(values, keys, strict=True)):
            button = QRadioButton(self._say(key))
            button.setChecked(value == chosen)
            group.addButton(button, index)
            box.addWidget(button)
        return group

    def chosen(self) -> Settings:
        return Settings(
            folder=self.folder.text().strip(),
            front=FRONTS[max(self.front.checkedId(), 0)],
            audio=AUDIOS[max(self.audio.checkedId(), 0)],
        )

    def _browse(self) -> None:
        start = self.folder.text().strip() or str(Path.home())
        picked = QFileDialog.getExistingDirectory(self, self._say("choose"), start)
        if picked:
            self.folder.setText(picked)
            self._look()

    def _look(self) -> None:
        n = self._count(self.folder.text().strip())
        self.found.setText(self._say("found", n=n) if n else self._say("not_found"))

    def refresh(self) -> None:
        self.status.setText(self._summary())
        self.sync_button.setEnabled(True)

    def _sync(self) -> None:
        self._save(self.chosen())
        self.sync_button.setEnabled(False)
        self._sync_now(self.refresh)

    def _accept(self) -> None:
        self._save(self.chosen())
        self.accept()


def open_settings() -> None:
    def save(settings: Settings) -> None:
        mw.addonManager.writeConfig(MODULE, to_config(settings))

    def count(folder: str) -> int:
        return len(discover.find(folder, platform.system(), Path.home()))

    def sync_now(done: Callable[[], None]) -> None:
        syncer.request(asked=True, done=done)

    dialog = SettingsDialog(mw, syncer.settings(), syncer.summary, count, save, sync_now, japanese())
    if dialog.exec():
        # a saved card choice reaches the cards with the next sync
        syncer.request(asked=True, done=lambda: None)


# ── Wiring ──────────────────────────────────────────────────────────────────


def _browser_menu(browser: aqt.browser.Browser, menu: QMenu) -> None:
    action = menu.addAction(t("reset"))
    qconnect(action.triggered, lambda: syncer.reset(list(browser.selected_notes())))


def _state_changed(new_state: str, _old_state: str) -> None:
    if syncer.waiting and new_state != "review":
        syncer.request()


def _application_state(state: Qt.ApplicationState) -> None:
    if state == Qt.ApplicationState.ApplicationActive:
        syncer.request()


def start() -> None:
    menu = QMenu(t("menu"), mw)
    sync_action = QAction(t("sync"), mw)
    qconnect(sync_action.triggered, lambda: syncer.request(asked=True))
    settings_action = QAction(t("settings"), mw)
    qconnect(settings_action.triggered, open_settings)
    menu.addAction(sync_action)
    menu.addAction(settings_action)
    mw.form.menuTools.addMenu(menu)
    mw.addonManager.setConfigAction(MODULE, open_settings)

    gui_hooks.profile_did_open.append(syncer.profile_opened)
    gui_hooks.state_did_change.append(_state_changed)
    gui_hooks.browser_will_show_context_menu.append(_browser_menu)
    qconnect(mw.app.applicationStateChanged, _application_state)
