# ADR-069: A saved word list, filled by a polled click and exported as text

- **Status:** Accepted
- **Date:** 2026-11-05
- **Related:** [ADR-036](036-readings-hover-word-lists.md) (word readings) · [ADR-039](039-word-meanings-written-in-context.md) (word meanings) · [ADR-041](041-word-cards-on-window-labels.md) (word cards on window labels) · [Word list](../systems/word-list.md) · [Readings](../systems/readings.md) · [Settings](../systems/settings.md)

## Context

The word card shows a word's reading, dictionary form and meaning while the mouse is on it, and nothing stays once the mouse moves on. A player asked, in issue #55, to save a word from the game, copy the saved words out, reset the list, and keep it between sessions. Learners usually study such words later in a flashcard program, most often Anki.

Four limits shape any answer:

- **The covers.** The word card works through a cover frame over each FontString that takes mouse motion only, so every click, drag and wheel scroll reaches the window under the text ([Readings](../systems/readings.md)). A cover that took clicks would sit between the player and that window: the quest window's text, a scrolling description, the voice panel the player drags by its text. The client already refuses the motion flag (`SetPropagateMouseMotion`) in combat, so a cover's mouse flags can change only out of combat.
- **Files.** An addon can write nothing but its SavedVariables, which the client writes on `/reload`, logout and a normal exit. It cannot write a file of its own, read the clipboard, or talk to another program.
- **English.** The addon never stores or shows the game's English ([principle 3](../architecture/principles.md#3-japanese-by-default-english-one-key-away)).
- **Keys.** The reveal key's modifier shows English while it is held, so no word is highlighted then.

## Decision

1. **An account-wide list in its own SavedVariables.** `WFJ_Words = { schema, entries, everSaved }`, apart from `WFJ_DB` (settings) and `WFJ_Collector` (which a player may attach to a public issue). Every character shares it: the words belong to the learner, not the character. It is loaded through the `step(…) or WFJ_Words` guard, so a failed load never hands the client an empty list to write. A list with a higher `schema` is kept unchanged and never written; an older addon version, which does not list the table in its TOC, drops it at its first logout, and the changelog says to export first.

2. **Keyed by source and dictionary form.** An entry's key is the reading row's kind and id plus the word's dictionary form (the word itself when it has none): `quest.description:456:倒す`. The same word saved twice from one text, in any inflection, is one entry; the same word from another text is another entry, with that sentence and that sentence's meaning. A reworded translation keeps its keys, because no key holds line text. Never a position.

3. **The save click is polled, never taken.** While a word is highlighted, the setting `words.saveClick` (Ctrl+click by default; Shift+click, Cmd+click on a Mac, a plain click, or off) saves it. The cover's existing `OnUpdate`, which runs only while the mouse is over it, reads `IsMouseButtonDown("LeftButton")`: a press over a word and a release over the same word, with the chosen modifiers held at the release, is a save. The covers keep their mouse flags unchanged, so the click also reaches whatever is under the text, as before. The reveal key's own modifier is never offered, and moving the reveal key onto the save click moves the save click to the next free choice (also at load, for a stored clash).

4. **The export is text on screen, with Anki's headers.** `/wfj words`, a Words settings page and the minimap button's menu open a window with the whole list as tab-separated text, selected for Cmd+C / Ctrl+C, Remove last and Clear all. There is no Copy button: the client blocks `CopyToClipboard` for addons (`ADDON_ACTION_FORBIDDEN`, seen in game). The text starts with Anki's import headers (`#separator:Tab`, `#html:true`, `#columns:…`; Anki 2.1.54 or later); the Key column comes first, and the window asks the player to make it the note type's first field, so Anki, which matches duplicates on the first field, updates notes on a second import instead of adding them again. The same text pastes into a text file or a spreadsheet.

5. **Only Japanese and the player's own data.** An entry holds the word, its reading, dictionary form, meaning, the Japanese sentence it was shown in (with the character's name where the line names it), where it was shown, the quest id and Japanese quest title for quest text, the date, and a screenshot file name. No English game text: a class or race word's English name is the meaning its card already shows.

6. **An optional screenshot.** With `words.screenshot` on (off by default), a save hides the card, keeps the gold tint, calls `Screenshot()`, and records the image's file name, built from the time at `SCREENSHOT_SUCCEEDED` and the screenshot format setting the way the client names screenshots; the chat line prints after, so it is not in the image. The export's image column points Anki at that file once the player copies it into Anki's media folder.

7. **Found without reading the docs.** The word card shows a grey hint naming the save click until the first save ever (`everSaved`, kept through Clear all); the intro window, the About page and `/wfj help` name it too.

## Consequences

- Saving a word changes nothing for any other click: a click, drag or wheel scroll over covered text reaches the same frame it did before, whatever the setting, and nothing in the save path is a protected call, so it works in combat.
- A click shorter than one frame is missed, because the poll never sees the button down. On the voice panel a save click is also a click on the panel.
- The player moves the text (and the images) themselves; there is no file to find and no program to install. A very long list is a long block of text.
- Words saved since the last `/reload`, logout or normal exit are lost in a crash, as any SavedVariables change is.
- Going back to an older addon version loses the list unless it was exported first.
- The screenshot file name pattern and its format CVar are not verified yet; the [in-game check](../testing/strategy.md#word-list-checklist) settles them.
- The toggle contract gains the save click, the card's hint, the word list window, the screenshot on save and `WFJ_Words` as allowed additions, recorded with the project's critical rules.

## Alternatives considered

- **Click-enabled covers** (`SetMouseClickEnabled` with `SetPropagateMouseClicks`). The cover would get the click and pass it on, but it would then stand between the player and every window under the text: drags of the voice panel and wheel scrolls would depend on the client propagating each kind of input as hoped, and the flags could change only out of combat. Polling needs none of that.
- **Hooking each window's own mouse handlers.** Every word-card surface (quest window panels, the quest map, gossip, book pages, window labels, the voice panel) would need its own hook into Blizzard frames, with taint risk on each. The cover is already the one place that knows which word is under the mouse.
- **A key to save the hovered word.** It needs a free key the player has to bind, and the request was a click. Not built.
- **Writing a file, or an Anki add-on that reads the SavedVariables.** An addon cannot write a file, and an add-on is another program to install and keep working against both the game and Anki. Text on screen works with a text editor, a spreadsheet and Anki's own import.
- **CSV.** Meanings and sentences hold commas; tab-separated text with Anki's headers serves all three uses with no quoting.
- **Keying by the word alone.** One word means different things in different sentences, and each meaning is written for its sentence. Keying by word would keep only the first sense and the first sentence.
- **A list per character.** The learner, not the character, is studying; a per-character list would split the words across alts.

## Update: covers pass clicks on

A cover that takes mouse motion only still caught clicks: the client sends a click to the frame under the mouse that takes mouse input, and a translated search box placeholder ("Search" in the auction house, the bags and the other search boxes) had its cover in front of the box, so the box never got the click while Japanese showed. Each cover now also turns its own clicks off (`SetMouseClickEnabled(false)`) and passes them on (`SetPropagateMouseClicks(true)`), set once when the cover is made, out of combat like the motion flag. The decision above stands: the save click is still read by polling, never from a click event, and the cover never takes a click itself.
