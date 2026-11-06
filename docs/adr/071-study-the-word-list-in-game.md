# ADR-071: Studying the word list in game with FSRS flashcards

- **Status:** Accepted
- **Date:** 2026-11-05
- **Related:** [ADR-069](069-saved-word-list.md) (the saved word list) · [ADR-036](036-readings-hover-word-lists.md) (word readings) · [ADR-039](039-word-meanings-written-in-context.md) (word meanings) · [Study](../systems/study.md) · [Word list](../systems/word-list.md) · [Readings](../systems/readings.md) · [Settings](../systems/settings.md)

## Context

The word list ([ADR-069](069-saved-word-list.md)) keeps the words a player saves with the save click, and its export puts them into Anki. Until now that was the only way to study them: outside the game, after copying the text out. A player asked for the words to be studied inside the game, like Anki, one card at a time, in the quiet moments the game has anyway: on a flight path, on a boat, waiting for a respawn.

Four limits shape the answer:

- **Files.** An addon writes nothing but its SavedVariables and reads no file of another program. It cannot read Anki's schedule or write to it, so whatever studies in game keeps its own schedule.
- **English.** The addon never stores or shows the game's English ([principle 3](../architecture/principles.md#3-japanese-by-default-english-one-key-away)). The back of a card may show the word card's model-written meaning, which the word list already holds, and nothing more.
- **Text.** A FontString draws one face and one colour for the whole line: it cannot bold one word of a sentence. The addon can only draw something over the word's rectangles, as the word card's gold tint already does.
- **Combat.** A cover frame cannot be made in combat (the client blocks `SetPropagateMouseMotion` there), and a window the player did not ask for is in the way during a fight.

## Decision

1. **FSRS-6 as published, with two grades and Anki's due order.** `Core/Fsrs.lua` is the FSRS-6 memory model ported from the published library sources (py-fsrs 6.3.2 and fsrs-rs 6.6.2, which agree), with their 21 default parameters and nothing tuned. The desired retention is 90%: a word graded **Good** comes back after its stability in whole days, at least one, which is the FSRS interval at which the chance of recall has fallen to 0.9. **Again** is one 10-minute relearn step (Anki's default) and counts as a lapse. There are no Hard and Easy buttons: most Anki users are told to use two grades, and two buttons fit a small card. The queue is Anki's: the earliest due word first, then new words in the order they were saved, while today's new count is under the daily cap (`study.newPerDay`: 5, 10, 20 or 50, default 20). The day is the client's local date, so the cap rolls at midnight, not at Anki's 4 am.

2. **Its own SavedVariables table, keyed like the list.** `WFJ_Study = { schema, cards, days }`, account-wide, apart from `WFJ_Words`: `cards` holds one state per word list key (stability, difficulty, due time, last review, repetitions, lapses), `days` how many new words were started on each date. It holds keys and numbers only, no text. It is loaded after the word list through the same `step(…) or WFJ_Study` guard, so a failed load never hands the client an empty table to write. A table with a higher `schema` is kept read-only and grading is refused with the word list's own chat line. A word removed from the list loses its card (at load, after Remove last, after Clear all), so a word saved again starts as new; only a listed word is graded.

3. **A tab and a card, with the word card's readings and a gold mark.** A small tab at the screen edge shows how many words wait (due plus new under the cap), and only while something waits. Clicking it opens one card: the word, large, and the sentence it was saved from, with the tested word marked by the gold tint, drawn by the card over the word's rectangles, which it measures through `UI/Readings`' guarded span call. The sentence is a word-card surface (`study`): pointing at any other word shows its reading and meaning as in quest text, while the tested word is never a hover target on the front, because its reading is the answer. Show answer reveals the reading, the dictionary form where it differs, and the meaning; then Again and Good. When nothing is due the card says so and when the next word comes.

4. **Always recoverable.** The card collapses to the tab; the close button hides both for the session; the next login shows the tab again. `/wfj study`, the minimap button's menu (**Study words (N due)**), the key binding **Study words** and the Words page's **Open the study card** button open the card whatever the tab setting says and whether it was closed. Both frames are movable, clamped to the screen, and share one saved spot (`WFJ_DB.study.point`); `/wfj study reset` puts them back at the right edge.

5. **Out of the way in combat.** With `study.combatHide` on (the default), entering combat hides the tab and the card and leaving it shows again whatever was showing. Only `Show` and `Hide` on the addon's own frames; no protected call is made on either event.

6. **No sync with Anki.** The export is unchanged, with no study columns. A player who studies in game and also imports the list into Anki keeps two schedules; the docs say so.

## Consequences

- A saved word can be studied where it was met, with no program to install and nothing to copy out; the export still works for a player who prefers Anki.
- The schedule is FSRS as the libraries ship it, so the intervals are the ones an Anki user with default parameters would see, apart from two differences: the day rolls at midnight, and whole-day rounding comes from the stability alone (no fuzz, no interval cap).
- Two grades mean a word is either forgotten or known; there is no "hard" to shorten an interval or "easy" to stretch it.
- The tested word's mark is drawn over the text, not in it: it depends on the FontString's layout, so it is drawn when the card shows the word and once more a frame later, and a line that has not laid out yet shows its mark one frame late.
- A card opened in combat with the combat setting off shows no hover readings until it is next opened out of combat, because no cover can be made in combat; the mark needs no cover.
- Study state is lost with the word, and with an older addon version (which does not list `WFJ_Study` in its TOC, so the client drops the table at its first logout); the list itself is untouched.
- The toggle contract gains the study tab and card and `WFJ_Study` as allowed additions, recorded with the project's critical rules.

## Alternatives considered

- **A homemade interval scheme, or SM-2.** Simpler to write, but every learner would get intervals no flashcard program uses, and a learner who knows Anki would feel the difference. FSRS-6 is published, tested, and the model Anki ships; the port is under a hundred lines.
- **Four grades (Again, Hard, Good, Easy).** Anki offers them, and the formulas allow them, but two grades are what most users are told to use, and four buttons do not fit a card that should stay small. The port keeps the ratings general because the difficulty formula references the Easy grade; no button is added.
- **Study state inside `WFJ_Words`.** One table would need every entry's shape to change and would mix what the player exports with what the scheduler writes. A separate table keyed by the same key is pruned to the list and leaves the export as it was.
- **An Anki-only workflow.** It already exists (the export). It needs another program, a copy out of the game, and a moment away from the game; the request was to study while playing.
- **A full window, like the word list window.** A dialog with a list of cards, statistics and buttons gets in the way of play. One small card that collapses to a tab fits the moments it is for.
