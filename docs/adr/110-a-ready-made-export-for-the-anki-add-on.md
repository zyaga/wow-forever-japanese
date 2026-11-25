# ADR-110: A ready-made export for the Anki add-on

- **Status:** Accepted
- **Date:** 2026-11-25
- **Deciders:** the maintainer
- **Related:** [ADR-069](069-saved-word-list.md) (the word list) · [ADR-092](092-a-saved-words-sentence-audio-is-found-not-stored.md) (a saved word's audio is found, not stored) · [ADR-081](081-english-first-and-english-word-cards.md) (English entries) · [Anki add-on](../systems/anki-add-on.md) · [Word list](../systems/word-list.md)

## Context

Getting saved words into Anki was all by hand: open the export window, copy the text, import it, then copy each screenshot and each sound file into Anki's media folder. Few players finish that, and it has to be done again for every new word.

An Anki add-on can do the Anki side by itself: it runs inside Anki, can read files on the player's machine and can add notes and media. What it needs from the game is each word with its furigana, its screenshot file name and its sentence's sound files.

The facts that shape where that comes from:

- An addon cannot write a file of its own. What it keeps goes into its saved variables, which the client writes at `/reload`, logout and a normal exit.
- The word list (`WFJ_Words`, `schema = 1`) does not hold the furigana or the audio. The export works them out when it runs, from the shipped readings and the loaded voice packs ([ADR-092](092-a-saved-words-sentence-audio-is-found-not-stored.md)).
- The shipped readings and the pack lists are generated Lua whose shape changes with the addon. A program outside the game would have to follow every change.
- Players keep their own notes in Anki, edit cards by hand, and care most about their review history.

## Decision

1. **The addon writes the export ready-made.** At logout and `/reload` (`PLAYER_LOGOUT`, the last step of that branch, guarded) the addon writes `WFJ_Anki = { schema = 1, written, voice, rows }` into its saved variables. `Core/AnkiExport` builds one row per saved word with the same helpers the export window uses: the fields, the sentence with the word in bold, the word's and the sentence's furigana, the screenshot file name, and the sentence's sound files as `<pack folder>/Sound/<file>`. It is rebuilt from the whole list each time. Nothing in the game reads it back.
2. **The add-on only reads.** The Anki add-on finds the game's folder, reads `WFJ_Anki` from every client and account it finds, and never writes anything in the game's folder. It needs no knowledge of the shipped data or the voice packs beyond a file path.
3. **One note per word key, in the add-on's own note type.** A word becomes one note of the note type `WoW Forever Japanese`, in the deck `WoW Forever Japanese`, with `Key` as its first field. A key that already has an add-on note is never added again.
4. **Fields only.** A sync adds notes, writes note fields and adds media files. It never changes a card, a schedule or the review log, and never deletes a note, even when the word left the game's list.
5. **Hand edits are kept.** The note's `Sync` field holds, as JSON, a short hash of what the add-on last wrote to each field. A field is rewritten only when the game's value changed and the field still holds what the add-on wrote; a field the player changed is skipped. **Reset to the game's data** in the card browser rewrites the selected notes from the game.
6. **Other notes are never touched.** Notes of any other note type are not read for matching and not changed, even with the same key. A note type of the same name that lacks the `Sync` field is the player's own; the add-on then uses `WoW Forever Japanese (add-on)`.

## Rationale

- The game already knows the furigana and the sound files, and the export window already works them out. Writing them once at logout is the same work the window does when it opens, and the add-on gets the answer instead of a second copy of the logic.
- Saved variables are the one place an addon can leave data for another program. They are written at moments the player controls (`/reload`, logout).
- Keeping the export in its own table leaves `WFJ_Words` and its schema alone, so nothing needs a migration and an older addon version reads the list as before.
- A hash per field tells a value the game changed from one the player changed without keeping a second copy of the note anywhere. It travels with the collection, to AnkiWeb and other machines.

## Consequences

- A new word reaches Anki after the next `/reload` or logout, not at the moment it is saved.
- The saved file grows by about the size of the word list again, once per account.
- The add-on is a second program in the repo, with its own tests, package and release file. Anki API changes touch one of its modules.
- Notes a player imported by hand from the export window stay as they are; the add-on adds its own note beside them.
- Words removed in game keep their notes, and a field the player edited stays edited until they reset it.
- A table written by a newer addon version is passed over by an older add-on, never half read; the add-on says so.

## Alternatives considered

- **The add-on reads the shipped data files and the voice pack lists itself.** It would need its own Lua reader for the addon's generated files and its own copy of how a sentence's sound files are found. Both change with the addon, so the add-on would break on a format change, and the logic would live in two languages.
- **Store the furigana and the audio in `WFJ_Words`.** It reverses [ADR-092](092-a-saved-words-sentence-audio-is-found-not-stored.md): every entry would carry data that goes stale when a pack is rebuilt or a line retranslated, the list would need a schema change and a migration, and words saved earlier would need filling in anyway.
- **Keep the by-hand export only.** No new table and no second program, but the copying stays, and a player has to do it again for every word. The export window stays for spreadsheets, text files and players without the add-on.
