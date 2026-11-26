# Anki add-on

> A small add-on for desktop Anki (25.09 or later) that reads the game's saved file and turns every saved word into an Anki card by itself, with its screenshot and its sentence's audio. Two halves: the addon writes a ready-made copy of the word list at logout and `/reload` (`Core/AnkiExport.lua`, the `ankiexport` step in `Main.lua`), and the add-on in `anki-addon/wfj_anki/` reads it and writes notes. Decision: [ADR-110](../adr/110-a-ready-made-export-for-the-anki-add-on.md).

## Purpose
The [word list](word-list.md)'s export window makes a player copy text, import it and then copy every screenshot and sound file into Anki's media folder by hand, again for each new word. The add-on does all of that: after the player installs it (and points it at the World of Warcraft folder if it is not found), saved words show up in Anki as finished cards, with furigana on the back, the screenshot and the sentence in its NPC's voice. Words saved before the add-on are filled in too. It only ever changes notes it made, keeps a field the player edited, and never touches a card's schedule or review history.

## How it works
```mermaid
sequenceDiagram
  participant U as Player
  participant G as Game (Main.lua)
  participant E as Core/AnkiExport
  participant F as WoWForeverJapanese.lua
  participant A as Anki add-on (ui, sync)
  participant C as Anki collection
  U->>G: save words, then /reload or log out
  G->>E: save(WFJ_Anki, Words.entries(), time(), deps)
  E-->>G: { schema, written, voice, rows }
  G->>F: the client writes the saved variables
  U->>A: open a profile, bring Anki to the front, or Sync now
  A->>A: discover the saved files; skip if none changed
  A->>F: read WFJ_Anki (every client, every account)
  A->>C: prepare the note type and the deck
  A->>A: plan: new notes, fields to write, media to bring
  A->>C: add notes, write fields, add media (one undo step)
  A->>U: tooltip: N new, M updated
```

### The game's side: `WFJ_Anki`
At `PLAYER_LOGOUT` (which the client fires at `/reload` too) the last step of `Main.lua`'s logout branch sets `WFJ_Anki` from `AnkiExport.save`. The step is guarded, so a fault in it costs none of the tables saved before it; a fault while building keeps the table that was loaded and records `ankiexport` in the problem log ([Diagnostics](diagnostics.md)). The table is account-wide and listed in the TOC's `## SavedVariables`.

```lua
WFJ_Anki = {
  schema = 1,
  written = <time() at the logout>,
  voice = <true when a voice pack is loaded>,
  rows = { <row>, … },   -- one per word list entry, in saved order
}
```

| row field | holds |
|---|---|
| `key`, `lang` | the entry's key and `"en"` for an English entry (empty for a Japanese one) |
| `word`, `reading`, `lemma`, `lemmaReading`, `meaning` | as in the entry |
| `sentence` | the sentence with the word in `<b>`, by its byte offsets (`Words.bold`) |
| `wordFurigana`, `sentenceFurigana` | Anki's furigana format, as the export's columns (`Words.furigana`, `Words.sentenceFurigana`); an English entry's word as it is |
| `jaSentence` | an English entry's Japanese sentence |
| `source`, `questId`, `questTitle`, `saved`, `shot` | as in the entry |
| `audio` | the sentence's sound files, `<pack folder>/Sound/<file>`, in play order (from `StudyVoice.find`); empty with no pack or no voiced sentence |

The rows are rebuilt from the whole list each time, so a word saved before this version gets its furigana and audio too. Nothing in the game reads the table back, so there is no migration: a missing or older table is replaced. It holds nothing the word list and its export do not already hold, plus pack folder and file names ([Word list → The Anki add-on](word-list.md#the-anki-add-on)).

### Finding the game
`discover.py`, paths in and paths out:
- **A folder the player picked** (the settings window's Browse) is used alone. It may be the World of Warcraft folder or one client folder.
- **With no folder set**, the usual places are tried in order and the first that holds a saved file wins: on a Mac `/Applications`, `~/Applications` and the top and `Games` folder of each drive under `/Volumes`; on Windows `Program Files (x86)`, `Program Files`, the drive's top and `Games` on drives C to Z; elsewhere the two usual Wine prefixes.
- Under that folder, every client folder (`_forever_`, `_retail_`, a folder named `_…_` with a `WTF` folder) and every account under `WTF/Account/` that holds `SavedVariables/WoWForeverJapanese.lua` is read.
- A screenshot is looked for in `<client>/Screenshots/<file>`, a sound file in `<client>/Interface/AddOns/<pack folder>/Sound/<file>`. A name that is not a plain file name, or a sound path that is not `<WoWForeverJapanese…>/Sound/<file>`, is refused, so a saved file can never name a file elsewhere on the machine.

### Reading the saved file
`savedvars.py` reads only what a SavedVariables file holds (strings with escapes, numbers, booleans, nested tables, `["key"] =` and the client's `-- [n]` comments) and returns `WFJ_Anki` as Python values. A missing file, a file without the table or a damaged one gives nothing, never an error. A table with a higher `schema` than the add-on reads is passed over, never half read, and the settings window says the add-on needs an update. When two saved files hold the same key, the newer table's row wins.

### The note type
One note type, `WoW Forever Japanese`, one card (`Card`), notes in the deck `WoW Forever Japanese` (made if missing). Its fields, in order:

| field | holds |
|---|---|
| `Key` | the word list key. First, so Anki's own duplicate check sees it |
| `Word`, `Reading`, `Dictionary form`, `Its reading`, `Meaning` | the word card's values |
| `Sentence` | the sentence in furigana format, the word in bold |
| `Word (furigana)` | the word in furigana format |
| `Japanese sentence` | an English word's Japanese sentence |
| `Image` | an HTML image tag naming the stored screenshot (its name starts with `wfj-`) |
| `Audio` | `[sound:wfj-…]`, one per file, in play order |
| `Game` | the game the word was saved in (`Forever`, `Retail`, `Classic Era`), from the client folder's name (`_forever_`); empty for a folder not named that way. Written once, with the tag `wow::forever` (or the game's own), and shown in the back's foot line. A tag the player removes is not added again |
| `Source`, `Quest`, `Quest ID`, `Saved`, `Lang` | where it was shown, the Japanese quest title, the quest's number (shown after the source on the back: "quest 456"), the save date (UTC, `YYYY-MM-DD`), `en` or empty |
| `Sync` | the add-on's record, as JSON: a short hash of what it last wrote to each field, and of the files behind `Image` and `Audio` |

The first sync makes the note type. A note type the add-on made earlier with fewer fields gains the new ones without losing a note. A note type of the same name without a `Sync` field is the player's own and is left alone; the add-on then uses `WoW Forever Japanese (add-on)`.

### The card
- **Japanese word.** Front: the Japanese quest title when there is one, and the sentence with the word marked and no readings (`{{kanji:Sentence}}`), or the word alone. Back: the sentence with furigana, the word with its reading, the dictionary form and its reading, the meaning, the audio, the image, and a foot line with the source and the date.
- **English word** (saved in English first). Front: the English sentence with the word marked, or the word alone. Back: the word, its pronunciation, the Japanese word the line uses for it, the Japanese sentence, the audio and the image.
- **Two card choices** in the settings window: the front shows the whole sentence (default) or the word alone; the sentence's audio plays with the answer (default) or with the question too. `notetype.card` keeps one of the marked blocks in `templates/front.html` for each choice. A choice rewrites the note type's template and styling, so every card follows at once, old ones too, and no note changes. Playing audio only from a button is Anki's own deck option, so it is not a third choice.
- `templates/style.css` styles the card in light and dark, at desktop and phone width.
- The collection keeps a mark of the card the add-on last wrote. The add-on rewrites the template and styling only when its own card changes (a card choice, a new version of the add-on). A player who restyles the note type by hand keeps that until then.

### A sync
`sync.apply` runs `plan.py`'s rules against what the add-on's notes hold now, and `collection.py` writes the result:
- **Adds.** A word is told from every other by its game and its key, so the same quest and word saved in two games are two notes. A game's key with no add-on note gets one, every field filled. A note made before notes named their game is taken as the word's note for the first game that has the word, and is named and tagged then.
- **Updates.** A field of an existing note is written only when the game's value changed **and** the field still holds what the add-on last wrote (its text hashes to the `Sync` entry, Unicode form fixed first). A field with no `Sync` entry, added by a later version, counts as untouched while it is empty. After a write the new hash is stored.
- **Keeps hand edits.** A field the player changed no longer matches its hash and is skipped; the note's other fields still update. **WoW Forever Japanese: reset to the game's data**, in the card browser's right-click menu, rewrites every field of the selected add-on notes from the game.
- **Media.** A row's screenshot is made no wider than 1600 pixels and stored as a JPEG (by Anki's own Qt; without it a JPEG or PNG goes as it is); sound files go as they are. Both are stored in Anki's media with a `wfj-` prefix, apart from the player's own files. The same files as last time are not stored again. A file that is missing leaves the field as it was and is tried at the next sync, even when no saved file changed. An `Image` or `Audio` field that holds something is never emptied by a row that names no file (no screenshot taken, a pack turned off).
- **One undo step.** Everything a sync writes is one entry in Anki's undo list, named `WoW Forever Japanese`.
- The result shows as a short tooltip (`N new, M updated`), nothing when nothing changed. Under the folder, the settings window lists each game found there with how many words it holds for Anki, or that its addon has not written its list for Anki yet. It also shows the last sync's result: words found, missing screenshots and sound files with their counts, a folder with no saved file, a table too new to read, or a saved file from an addon that has not written `WFJ_Anki` yet.

- **Deleted cards stay deleted.** The collection keeps, for each client and account, the newest saved word a sync has seen. A word no newer than that with no note was deleted in Anki by the player, so it is not added again. **Tools → WoW Forever Japanese → Add deleted cards again** makes a note for every word of the game's list once more, and the settings window says how many words were left out.
- **Markup.** The game writes each row's text ready for a field: `&`, `<`, `>`, `[` and `]` are escaped, so a stage direction in angle brackets, a link's label in square brackets, or text another player typed in chat shows as text and never as a tag or a reading. The only markup is the game's own: the saved word in bold and the readings. The key is escaped when it is written to the note and read back the same way.
- **A line voiced again.** A re-voiced line keeps its file names, so the mark of a note's audio holds each file's size too: when a file changes, the card gets the new recording.

### When a sync runs
- When a profile opens, when Anki becomes the active application again, and from **Tools → WoW Forever Japanese → Sync now** (or the settings window's Sync now).
- It is skipped when no saved file changed since the last sync (same paths, sizes and modified times) and the settings are the same, unless media was missing last time or the player asked.
- It waits while a card is being studied (adding notes then would redraw the card under the player) and runs when the player leaves the review. A Sync now runs at once.
- It never runs while no collection is open, and one sync runs at a time, in the background.
- It never runs beside Anki's own sync with AnkiWeb: it waits for that to finish, then looks again, since the collection may have come from another device. After a profile opens it waits a moment for the same reason.
- Media that is missing is looked for on the next three checks, then left until a saved file changes or the player asks.
- Opening another profile starts over: that profile gets its own first sync and its own last result.
- The game's folders are searched once and remembered while the saved files are still there. A Sync now, or a changed folder setting, searches again.
- A word saved in game reaches Anki only after the next `/reload` or logout, because that is when the client writes the file.

### The settings window
**Tools → WoW Forever Japanese → Settings…** (also Anki's Config button for the add-on): the World of Warcraft folder with Browse (empty looks in the usual places) and how many saved word lists it finds there, the two card choices, Sync now, and the last sync's result. In English or Japanese, by Anki's language (`text.py`). Anki keeps the settings as the add-on's config (`config.json`: `folder`, `front`, `audio`); a value that is not one of the choices counts as not set, so a hand-edited config never stops a sync.

## Key files
- `addon/WoWForeverJapanese/Core/AnkiExport.lua`: the rows of `WFJ_Anki` (pure); `Main.lua`: the `ankiexport` logout step; `WoWForeverJapanese.toc`: `WFJ_Anki` in `## SavedVariables`
- `addon/WoWForeverJapanese/UI/WordsWindow.lua`, `UI/OptionsText.lua` (`words.addon`): the line in the word list window with the add-on's address
- `anki-addon/wfj_anki/__init__.py`: starts the add-on inside Anki, nothing outside it
- `anki-addon/wfj_anki/savedvars.py`: reads a SavedVariables file (pure)
- `anki-addon/wfj_anki/discover.py`: the game folder, client folders, saved files, media paths (pure)
- `anki-addon/wfj_anki/plan.py`: rows from the tables, the fields, what a note's fields become, the hand-edit rule (pure)
- `anki-addon/wfj_anki/notetype.py`: the note type's name, deck, fields and the template for the chosen choices (pure)
- `anki-addon/wfj_anki/settings.py`: the config and its defaults (pure)
- `anki-addon/wfj_anki/sync.py`: one sync against any collection handed in, and when one is due
- `anki-addon/wfj_anki/media.py`: a file ready for Anki's media, the screenshot made smaller
- `anki-addon/wfj_anki/collection.py`: the only module that calls Anki's collection (note type, deck, notes, media, undo)
- `anki-addon/wfj_anki/ui.py`: the menu, the browser action, the hooks (`profile_did_open`, `state_did_change`, Qt's `applicationStateChanged`) and the settings window; with `__init__.py`, the only code that knows Qt
- `anki-addon/wfj_anki/text.py`: the add-on's words in English and Japanese
- `anki-addon/wfj_anki/templates/`: `front.html`, `back.html`, `style.css`
- `anki-addon/wfj_anki/manifest.json` (the oldest Anki it runs on: 25.09), `config.json`, `config.md`
- `anki-addon/tools/package.py`: the `.ankiaddon` file; `anki-addon/tools/render_cards.py`: the card pictures

## Packaging and release
- `make anki-package` writes `build/anki/WoWForeverJapanese.ankiaddon`: a zip of the add-on's own files at its root (Python, JSON, Markdown, HTML, CSS; no cache or test file) and the repository's `LICENSE`, with the version written into `manifest.json` (the next release's unless `ANKI_VERSION=` is given). The same tree always gives the same file.
- The Release workflow builds it from the tagged tree and adds it to the GitHub release after the addon's zip is live. A problem there is a warning, not a failed release; the file is then added by hand ([Release](../operations/release.md)).
- The AnkiWeb listing is not made yet. Uploading there is done by hand from the maintainer's AnkiWeb account.
- `make anki-cards` draws the card for each front choice, front and back, light and dark, at desktop and phone width, for a Japanese word (with image and audio) and an English word, into `build/anki/cards/` (`CARD_IMAGE=` picks the stand-in screenshot; needs Chrome). It fails when a picture is missing.

## Testing
- **Lua (busted):** `tests/lua/spec/anki_export_spec.lua` (rows equal the export's values, an old entry gets its furigana and audio, a frozen list is still copied, the guarded save that the logout step in `Main.lua` calls, no pack; the step itself is checked in the game, by reading the saved file after a `/reload`), `tests/lua/spec/words_window_spec.lua` (the add-on line).
- **Python (pytest), without Anki:** `test_anki_savedvars.py` (fixture `tests/fixtures/anki/WoWForeverJapanese.lua`), `test_anki_discover.py`, `test_anki_plan.py` (the sync rules against an in-memory stand-in for the collection: adds, updates, hand edits, reset, media, removed words), `test_anki_text.py` (the add-on's words in both languages, when a sync is due, the hooks it is wired to), `test_anki_settings.py`, `test_anki_text.py`, `test_anki_template.py` (the templates rendered for each choice and both languages), `test_anki_package.py`.
- **On a real Anki collection:** `test_anki_real.py` runs `anki-addon/tests/real_collection.py` with Anki's own Python (`ANKI_PYTHON`, or where Anki's launcher keeps it) against a throwaway collection, and checks that a card's type, queue, due, interval, ease, reps and lapses and the review log are the same before and after a sync and a reset. `anki-addon/tests/settings_window.py` draws the settings window with Anki's Qt and no Anki window. Both are skipped where Anki is not installed, as in CI.
- **By hand:** the first run in Anki (install the file, the menu, the hooks, the window, a sync after `/reload`) is the maintainer's ([Testing → Anki add-on](../testing/strategy.md#anki-add-on-checklist)).

## Invariants
- The add-on writes only its own note type, note fields of its own notes, its deck and media files. It never changes a card, a schedule, a due date or the review log, and never deletes or suspends a note, even when the word left the game's list.
- Notes of any other note type are never read for matching and never changed, even with the same key. One add-on note per key.
- A field the player edited is not rewritten until they reset it.
- A filled `Image` or `Audio` field is never emptied by a sync.
- The add-on never writes in the game's folder, and reads only the addon's saved file, screenshots and the addon's own pack folders.
- The game never reads `WFJ_Anki`; `WFJ_Words` keeps `schema = 1`.

## Edge cases
- **Several clients or accounts** hold words: every saved file is read; a key in two of them takes the newer table's row, with media from that row's client.
- **Notes imported by hand** from the export window are another note type, so they stay as they are and the add-on adds its own note beside them.
- **A pack turned off or a screenshot deleted:** the field keeps what it holds. A pack updated with new files for the sentence brings the new files.
- **The addon is older than the add-on's first version** (no `WFJ_Anki` in the file): the settings window says to update the addon and `/reload` once.
- **A screenshot whose name the addon guessed wrong** ([Word list → Screenshots](word-list.md#screenshots)): counted as missing in the settings window, never blanks a field.

## Limits
- **A changed note type asks for a one-way sync.** Anki cannot merge a change to a note type's fields: after a version of the add-on adds a field, Anki's next sync with AnkiWeb asks the player to upload or download the whole collection. The player-facing text says to sync every device before installing or updating, and a field is added only when a feature needs one.
- A note whose `Sync` field was emptied or damaged by hand has every filled field counted as the player's own, so nothing in it is rewritten. Reset to the game's data puts it right.
- `Saved` is the day in UTC.
- Desktop Anki only: Anki's add-ons do not run in the phone apps. The cards reach the phone apps through AnkiWeb sync, and the template works there.
- New words arrive after a `/reload` or a logout in the game, not when they are saved.
- Anki and the game keep separate schedules; the add-on never reads or writes `WFJ_Study`.
- The AnkiWeb listing is not made yet; the add-on is installed from the file on the GitHub release.

## Related
- [Word list](word-list.md) · [Study](study.md) · [Voice over](voice.md) · [ADR-110](../adr/110-a-ready-made-export-for-the-anki-add-on.md) · [ADR-092](../adr/092-a-saved-words-sentence-audio-is-found-not-stored.md) · [ADR-069](../adr/069-saved-word-list.md) · [Testing → Anki add-on](../testing/strategy.md#anki-add-on-checklist) · [Release](../operations/release.md) · [App capabilities → Word list](../app-capabilities.md#word-list) · [Glossary](../glossary.md)
