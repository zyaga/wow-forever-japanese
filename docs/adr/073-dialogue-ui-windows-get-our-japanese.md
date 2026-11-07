# ADR-073: Dialogue UI windows get our Japanese when it is installed

- **Status:** Accepted
- **Date:** 2026-11-06
- **Deciders:** the maintainer
- **Related:** [ADR-004](004-zero-runtime-dependencies.md) (zero runtime dependencies, narrowed here) · [ADR-009](009-surfaces-post-hook-the-writer.md) (post-hook the writer) · [ADR-054](054-quest-text-keyed-by-its-english.md) (quest text keyed by its English) · [Addon modules](../architecture/addon-modules.md)

## Context

Dialogue UI, a popular quest addon that runs on Forever, turns Blizzard's quest, gossip and book windows off and draws the same game text in its own windows (`DUIQuestFrame` for quests and NPC talk, `DUIBookFrame` for books). With it installed, players of this addon see English where it matters most: none of the hooks on Blizzard's windows fire, so no Japanese, no word cards and no voice. A player asked for compatibility. [ADR-004](004-zero-runtime-dependencies.md) rules out dependencies and integration with other addons.

## Decision

When Dialogue UI is loaded, two window modules (`UI/DialogueUI.lua`, `UI/DialogueUIBook.lua`) look for its two windows and work inside them. They replace a few methods on those frame instances with wrappers that put our Japanese in before Dialogue UI lays the text out, and they call the original every time. The lines, keys, markers, fonts, word cards and voice are the ones Blizzard's windows get.

The addon ships, embeds and requires nothing of Dialogue UI: no dependency field in the TOC, no copied code, and without Dialogue UI the modules do nothing. Each module checks every Dialogue UI member it uses when it installs; if one is missing, it installs nothing, writes one line to the problem log, and Dialogue UI shows its English. Repeated errors in the wrappers switch both modules off for the session, again leaving Dialogue UI's English.

Dialogue UI's buttons, section headings, reward headings and the tags over a quest page title are mostly the game's own strings (its locale reads them from the client). A label that is exactly one of the client's interface strings gets that string's Japanese, as on the client's windows; a heading's band is sized again for the Japanese. A third module, `UI/DialogueUIFrames.lua`, works on Dialogue UI's frames that have no name, told apart by their own members: its item tooltip (every line after the item name gets the game's Japanese through the same matchers as the client's tooltips), its chat panel (an NPC line arriving gets the chat window's Japanese) and its quest popups (the quest's Japanese title). A scan finds those frames when the window is set up, after the quest events Dialogue UI makes a popup on, and when its window opens, going on from the last frame it saw.

A few words are Dialogue UI's own with no client string behind them: the "Requirements" heading (Forever has no such string), and in its tooltip "Replace", "Show Comparison" and "Hide Comparison". These show the addon's own Japanese (必要なもの, 交換:, 比較を表示, 比較を隠す), as the voice panel's words do, under the same switches as the game's words. Its other own words stay English. Its quest-complete flyout stays English: it is off by default and measures its text inside code the addon cannot reach, so a swap could break its layout.

While a Dialogue UI window is open, the voice panel is taken out from under the game interface (no parent, at the interface's scale) so it shows whole while Dialogue UI fades that interface out, and is put back when the window closes.

Each module's install runs under one guard: an error on the way is recorded and Dialogue UI keeps its English, with nothing raised. Every frame check and wrapper is guarded, and an event the client does not have is passed over.

Dialogue UI's public translator API (`SetTranslator`) is not used: it shows both languages by default, which the toggle contract forbids, and it covers quests only.

This narrows ADR-004: an optional adapter that runs only when the player already has the other addon is allowed. Dependencies, `## OptionalDeps` and embedded libraries stay forbidden.

## Rationale

- Putting the Japanese in before Dialogue UI measures the text lets Dialogue UI lay out and size the Japanese itself, in the bundled font set on each line before it is measured. Rewriting the text after layout would leave Dialogue UI's sizes fitted to the English.
- The reveal key, the master switch, the area switches and the markers ask Dialogue UI to draw the page again with its own redraw. The wrappers reuse the line records they already made, so a hold or a release never starts a voice line again.
- Keys are the same as on Blizzard's windows (quest id and field, the English-keyed variants of ADR-054, the gossip and book keys of the English), so every line that ships for Blizzard's windows ships for Dialogue UI's with no data change.
- Wrapping instance methods and checking the members on install keeps a Dialogue UI update that changes its internals to "English again", never a broken window.

## Consequences

### Positive
- Dialogue UI users get the same Japanese, reveal key, markers, word cards and voice as on Blizzard's windows, plus Japanese quest titles, NPC talk options and quest rows in its lists, its game-word buttons and headings, its item tooltip lines, its chat panel lines and its quest popup titles.
- Players without Dialogue UI see no change.

### Negative
- The modules follow Dialogue UI's internals, which can change in its updates. The member check and the error limit bound the damage to English text.
- Holding the reveal key uses Dialogue UI's own redraw, which clears its gossip history and a reward the player had chosen on the turn-in page. The module puts the page's scroll position back after the redraw.
- Dialogue UI fades the game interface out while its window shows, so the word card and reading box move under the Dialogue UI window while they point at its text. The voice panel is lifted out from under the faded interface for that time and goes back after; under it, only its 3D head would draw (a model ignores its parent's alpha).
- Lines already in Dialogue UI's chat panel keep what they showed when they arrived (the panel keeps its own list), so the reveal key and the switches change only lines arriving while they are set.
- The tooltip, chat panel and popups are found by their shape, not a name; a Dialogue UI update that changes that shape leaves them in English.
- An item's effect lines (Use:, Equip:) stayed English in Dialogue UI's tooltip at first: the game's own tooltip translates them by item id across the whole run, which Dialogue UI's line writers do not let the addon see in one place. *Amended 2026-11-07:* Dialogue UI reads the client's tooltip data line by line (`ProcessTooltipData`), so it is now handed a copy of that data with the run as one Japanese line, as the game's tooltip shows it; Dialogue UI's own data is never changed. Two more parts that had stayed English show Japanese from the same change: a tag over a quest title that Dialogue UI fills in after the page drew (each tag button found is followed at its `SetQuestTagNameAndIcon`; a tag button made for the first time after the page drew is found on the next page), and its quest-complete flyout (off by default), which is handed the quest's Japanese title and turn-in paragraphs while every text its pool hands out takes the bundled face first, so it measures the Japanese in the face it shows. An error alert, a quest with no Japanese or the reveal key held leaves the flyout's English.
- Dialogue UI measures a book's text and its chat panel's lines through its own font objects before any line is drawn, so the modules set the bundled face on those objects (Dialogue UI's, never the client's): the book's while a book shows Japanese (given back when it closes or shows English), the chat panel's when the panel is found, before it holds a line. The rest of the addon still never changes a font object.

## Alternatives considered

- **Dialogue UI's `SetTranslator` API:** stable, but shows English and Japanese together by default (forbidden) and covers quests only.
- **Do nothing:** Dialogue UI users keep seeing English.
- **Replace the game API functions Dialogue UI reads:** Dialogue UI keeps its own copies of them from its load, and replacing Blizzard functions risks taint.
