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

Dialogue UI's public translator API (`SetTranslator`) is not used: it shows both languages by default, which the toggle contract forbids, and it covers quests only.

This narrows ADR-004: an optional adapter that runs only when the player already has the other addon is allowed. Dependencies, `## OptionalDeps` and embedded libraries stay forbidden.

## Rationale

- Putting the Japanese in before Dialogue UI measures the text lets Dialogue UI lay out and size the Japanese itself, in the bundled font set on each line before it is measured. Rewriting the text after layout would leave Dialogue UI's sizes fitted to the English.
- The reveal key, the master switch, the area switches and the markers ask Dialogue UI to draw the page again with its own redraw. The wrappers reuse the line records they already made, so a hold or a release never starts a voice line again.
- Keys are the same as on Blizzard's windows (quest id and field, the English-keyed variants of ADR-054, the gossip and book keys of the English), so every line that ships for Blizzard's windows ships for Dialogue UI's with no data change.
- Wrapping instance methods and checking the members on install keeps a Dialogue UI update that changes its internals to "English again", never a broken window.

## Consequences

### Positive
- Dialogue UI users get the same Japanese, reveal key, markers, word cards and voice as on Blizzard's windows, plus Japanese quest titles, NPC talk options and quest rows in its lists.
- Players without Dialogue UI see no change.

### Negative
- The modules follow Dialogue UI's internals, which can change in its updates. The member check and the error limit bound the damage to English text.
- Holding the reveal key uses Dialogue UI's own redraw, which clears its gossip history and a reward the player had chosen on the turn-in page. The module puts the page's scroll position back after the redraw.
- Dialogue UI fades the game interface out while its window shows, so the word card and reading box move under the Dialogue UI window while they point at its text. The voice panel stays under the game interface and shows again when Dialogue UI brings the interface back.
- Dialogue UI measures a book's text through its own book font objects before any line is drawn, so while a book shows Japanese the book module sets the bundled face on those objects (Dialogue UI's, never the client's) and gives their faces back when the book closes or shows English. The rest of the addon still never changes a font object.

## Alternatives considered

- **Dialogue UI's `SetTranslator` API:** stable, but shows English and Japanese together by default (forbidden) and covers quests only.
- **Do nothing:** Dialogue UI users keep seeing English.
- **Replace the game API functions Dialogue UI reads:** Dialogue UI keeps its own copies of them from its load, and replacing Blizzard functions risks taint.
