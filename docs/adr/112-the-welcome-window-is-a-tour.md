# ADR-112: The welcome window is a tour

- **Status:** Accepted
- **Date:** 2026-11-25

## Context
The welcome window asks once what the player is here for (study Japanese, study English, just play) and writes the settings that choice needs (ADR-081). Its second page then listed what to know to start: the reveal key, the word cards, the frozen tooltip, the minimap button and the voice download, one line each.

That page did not do its job. Players did not know some features existed: the frozen tooltip and its key, the chat tools (word cards in chat, copying a line to paste into a translator, the phrase book), and now word status (ADR-111). One line per feature on one page had no room to say how to use any of them, and every new feature made the page longer.

The window is the one place the addon is sure to talk to every player, and it is the one addon window that shows both languages at once, because the player has not learned the reveal key yet.

## Decision
1. **After the question comes a tour, one page at a time.** Each page has a heading, one picture and up to three short points, every text in Japanese with its English under it. The foot has Back, the page's number and the count, and Next; on the last page Next reads Start and closes the window. Back on the first tour page returns to the question. The question and what Confirm writes are unchanged.
2. **One window, with its pages from one list.** The pages are entries of `IntroWindow.PAGES` (id, picture, points, which choices see it), laid out by one function. A new page is a new entry, its texts and its picture; nothing else in the window changes.
3. **A page that does not fit the choice is left out.** Study Japanese sees start, cards, status, freeze, chat, more. Study English sees the same without the frozen tooltip, which takes word cards only while Japanese shows. Just play sees start, chat and more: it turns word cards off, so it has no word list, no word status marks and no word cards on a frozen tooltip to show. A point that does not apply (a save click that is off, word cards in chat after Just play) is left out of its page.
4. **A picture per page, shipped as image files in the format already proven to load.** Each is 512 x 256, uncompressed TGA with 32 bits a pixel and rows from the bottom up, the layout the addon's icon and minimap button already load in. Each is cut from a screenshot of the game with the addon at work, showing its Japanese, never a picture made to show English game prose. The sources are kept in `docs/images/tour/`, and `make intro-images` cuts and converts them with the image tool macOS ships, so nothing is installed.
5. **One size and one look for every page.** The window has one fixed size on the question and on every tour page, and a tour page puts its heading, its picture and its first point at the same height whatever it holds, so nothing changes size or moves between pages and Confirm, Back and Next stay under the mouse. The height is a constant: measuring each page's text gave different answers for pages that were not on screen.
6. **The voice download moves to the last page**, shown only while no voice pack has loaded.

## Consequences
- Each feature gets room for how to use it, with a picture of it at work, and the tour can grow by one list entry per feature.
- The six pictures add about 3.1 MB to the addon.
- A picture shows a feature's look at the time it was taken. When a feature's look changes, its picture has to be retaken: a new source in `docs/images/tour/` and `make intro-images`. Until a screenshot of a feature exists, its page can carry a stand-in cut from another screenshot.
- Converting the pictures needs a Mac. The TGA files are committed, so building or testing the addon does not.
- A test fails while a page names a picture with no file or a file has no page, so the list and the files cannot drift apart.
- The tour is longer to click through than the old page. Esc closes it on any page, and it shows once.

## Alternatives considered
- **A longer single page**: one more line per feature still leaves no room for how to use it, and the window would grow past a comfortable height as features are added.
- **A link to the website**: most players would not open it, and the window can already show the feature in the player's own language, in the game.
- **Several windows, one per feature**: more frames to build and close, and no single place for Back, Next and the count.
- **Pictures drawn live from the game's own frames** (opening a quest window or a tooltip behind the tour): the frames a page needs are not on screen for a new character, opening them changes what the player sees, and the result depends on the player's other addons and window layout.
