# ADR-073: Dialogue UI windows get our Japanese when it is installed

- **Status:** Accepted
- **Date:** 2026-11-06
- **Deciders:** the maintainer
- **Related:** [ADR-004](004-zero-runtime-dependencies.md) (zero runtime dependencies, narrowed here) · [ADR-009](009-surfaces-post-hook-the-writer.md) (post-hook the writer) · [ADR-054](054-quest-text-keyed-by-its-english.md) (quest text keyed by its English) · [Addon modules](../architecture/addon-modules.md)
- **Amended by:** [ADR-083](083-quest-titles-are-names.md): quest titles stay the game's English in Dialogue UI's windows, popups and flyout as shipped; the Japanese titles show only with the titles switch on.

## Context

Dialogue UI, a popular quest addon that runs on Forever, turns Blizzard's quest, gossip and book windows off and draws the same game text in its own windows (`DUIQuestFrame` for quests and NPC talk, `DUIBookFrame` for books). With it installed, players of this addon see English where it matters most: none of the hooks on Blizzard's windows fire, so no Japanese, no word cards and no voice. A player asked for compatibility. [ADR-004](004-zero-runtime-dependencies.md) rules out dependencies and integration with other addons.

## Decision

When Dialogue UI is loaded, two window modules (`UI/DialogueUI.lua`, `UI/DialogueUIBook.lua`) look for its two windows and work inside them. They follow Dialogue UI's methods with `hooksecurefunc` and write our Japanese into the text Dialogue UI wrote, before it lays that text out where the layout depends on it. The lines, keys, markers, fonts, word cards and voice are the ones Blizzard's windows get.

**Hooks, not replacements.** No method or field of Dialogue UI's frames, buttons, pools or texts is ever replaced by a function of the addon's. The modules first replaced a few methods with wrappers that called the original. Dialogue UI's own code then ran inside the addon's function, so every value it wrote there carried the addon's taint: an option button's click handler and its ids among them. Its click reads that handler and, for an option that opens a window such as a vendor, shows the game's hidden interface again, so the vendor and bag windows ran their `OnShow` on the addon's taint and a later bag click (a Hearthstone) was blocked in the addon's name. With `hooksecurefunc`, Dialogue UI's own method runs first, untouched, and the addon's code runs after it and leaves no taint behind. A paragraph's Japanese goes in through a hook on that FontString's `SetText`, which runs between Dialogue UI's write and its measuring, so Dialogue UI still lays out the Japanese itself. A button's label is written after Dialogue UI's writer, and the button's own `Layout` sizes it again. For the same reason no script of Dialogue UI's windows or of `UIParent` is hooked: Dialogue UI shows the hidden interface again inside its window's close, and the windows that come back with it run their `OnShow` in that same call. A frame of the addon's own, outside the interface, looks at the windows and the interface each frame instead. `tests/python/test_dialogueui_hooks.py` fails on any function put in a key of a Dialogue UI object and on any hook on `UIParent`.

The addon ships, embeds and requires nothing of Dialogue UI: no dependency field in the TOC, no copied code, and without Dialogue UI the modules do nothing. Each module checks every Dialogue UI member it uses when it installs; if one is missing, it installs nothing, writes one line to the problem log, and Dialogue UI shows its English. Repeated errors in the wrappers switch both modules off for the session, again leaving Dialogue UI's English.

Dialogue UI's buttons, section headings, reward headings and the tags over a quest page title are mostly the game's own strings (its locale reads them from the client). A label that is exactly one of the client's interface strings gets that string's Japanese, as on the client's windows; a heading's band is sized again for the Japanese. A third module, `UI/DialogueUIFrames.lua`, works on Dialogue UI's frames that have no name, told apart by their own members: its item tooltip (every line after the item name gets the game's Japanese through the same matchers as the client's tooltips), its chat panel (an NPC line arriving gets the chat window's Japanese) and its quest popups (the quest's Japanese title). A scan finds those frames when the window is set up, after the quest events Dialogue UI makes a popup on, and when its window opens, going on from the last frame it saw.

A few words are Dialogue UI's own with no client string behind them: the "Requirements" heading (Forever has no such string), and in its tooltip "Replace", "Show Comparison" and "Hide Comparison". These show the addon's own Japanese (必要なもの, 交換:, 比較を表示, 比較を隠す), as the voice panel's words do, under the same switches as the game's words. Its other own words stay English. Its quest-complete flyout stays English: it is off by default and measures its text inside code the addon cannot reach, so a swap could break its layout.

While a Dialogue UI window is open, the voice panel is taken out from under the game interface (no parent, at the interface's scale) so it shows whole while Dialogue UI fades that interface out, and is put back when the window closes.

Each module's install runs under one guard: an error on the way is recorded and Dialogue UI keeps its English, with nothing raised. Every frame check and wrapper is guarded, and an event the client does not have is passed over.

Dialogue UI's public translator API (`SetTranslator`) is not used: it shows both languages by default, which the toggle contract forbids, and it covers quests only.

This narrows ADR-004: an optional adapter that runs only when the player already has the other addon is allowed. Dependencies, `## OptionalDeps` and embedded libraries stay forbidden.

## Rationale

- Putting the Japanese in before Dialogue UI measures the text lets Dialogue UI lay out and size the Japanese itself, in the bundled font set on each line before it is measured. Rewriting the text after layout would leave Dialogue UI's sizes fitted to the English. The `SetText` hook on each pooled FontString gives that order without replacing any of Dialogue UI's methods.
- Following methods with `hooksecurefunc` instead of replacing them keeps the addon's taint out of every value Dialogue UI writes, its click handlers first of all, so its clicks and the game windows they open run as they would without this addon.
- The reveal key, the master switch, the area switches and the markers write the page's texts again in place: each line from its record, each heading, option and objective line from its lookup. Dialogue UI is never asked to draw the page again, because its redraw would run under this addon's name and rebuild the option buttons with it, and a click on one could then get a bag item's use blocked in this addon's name. A hold or a release never starts a voice line again.
- Keys are the same as on Blizzard's windows (quest id and field, the English-keyed variants of ADR-054, the gossip and book keys of the English), so every line that ships for Blizzard's windows ships for Dialogue UI's with no data change.
- Hooking instance methods and checking the members on install keeps a Dialogue UI update that changes its internals to "English again", never a broken window.

## Consequences

### Positive
- Dialogue UI users get the same Japanese, reveal key, markers, word cards and voice as on Blizzard's windows, plus Japanese quest titles, NPC talk options and quest rows in its lists, its game-word buttons and headings, its item tooltip lines, its chat panel lines and its quest popup titles.
- Players without Dialogue UI see no change.

### Negative
- The modules follow Dialogue UI's internals, which can change in its updates. The member check and the error limit bound the damage to English text.
- Holding the reveal key changes the words but not the room Dialogue UI measured for them: while it is held, a text much longer in the other language can overlap the next one or leave a gap, until Dialogue UI draws the page again. The page keeps its scroll position, its gossip history and a reward the player had chosen.
- Dialogue UI fades the game interface out while its window shows, so the word card and reading box move under the Dialogue UI window while they point at its text. The voice panel is lifted out from under the faded interface for that time and goes back after; under it, only its 3D head would draw (a model ignores its parent's alpha).
- Lines already in Dialogue UI's chat panel keep what they showed when they arrived (the panel keeps its own list), so the reveal key and the switches change only lines arriving while they are set.
- The tooltip, chat panel and popups are found by their shape, not a name; a Dialogue UI update that changes that shape leaves them in English.
- Dialogue UI makes one text per paragraph of the English before the addon writes into it, so a line whose Japanese has more paragraphs than the English shows the first ones together in its first text (a stale or missing marker sits right above the first paragraph, with no paragraph gap), and one with fewer leaves its last texts empty. The chat panel's lines are swapped in Dialogue UI's own list after it stored them, which is measured again, and an item's folded effect lines are taken out of its tooltip's line grid. These are writes of data, never of functions, and none of them is a value a click reads.
- Windows opening and closing are seen on the next frame rather than inside Dialogue UI's show and hide calls.
- An item's effect lines (Use:, Equip:) stayed English in Dialogue UI's tooltip at first: the game's own tooltip translates them by item id across the whole run, which Dialogue UI's line writers do not let the addon see in one place. *Amended 2026-11-07:* Dialogue UI reads the client's tooltip data line by line (`ProcessTooltipDataLines`), so once it has added the lines, the run's first line shows the Japanese and the run's other lines are taken out of its layout, as the game's tooltip shows it; the client's data is never changed. Two more parts that had stayed English show Japanese from the same change: a tag over a quest title that Dialogue UI fills in after the page drew (each tag button found is followed at its `SetQuestTagNameAndIcon`; a tag button made for the first time after the page drew is found on the next page), and its quest-complete flyout (off by default), whose title and paragraphs get the quest's Japanese title and turn-in paragraphs as it writes them, each in the bundled face before it is measured, so it measures the Japanese in the face it shows. An error alert, a quest with no Japanese or the reveal key held leaves the flyout's English.
- Dialogue UI measures a book's text and its chat panel's lines through its own font objects before any line is drawn, so the modules set the bundled face on those objects (Dialogue UI's, never the client's): the book's while a book shows Japanese (given back when it closes or shows English), the chat panel's when the panel is found, before it holds a line. The rest of the addon still never changes a font object.

## Alternatives considered

- **Dialogue UI's `SetTranslator` API:** stable, but shows English and Japanese together by default (forbidden) and covers quests only.
- **Do nothing:** Dialogue UI users keep seeing English.
- **Replace the game API functions Dialogue UI reads:** Dialogue UI keeps its own copies of them from its load, and replacing Blizzard functions risks taint.
