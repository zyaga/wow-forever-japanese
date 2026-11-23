# ADR-104: The frozen tooltip, and word cards on tooltip text

- **Status:** Accepted
- **Date:** 2026-11-22
- **Deciders:** the maintainer
- **Related:** [ADR-036](036-readings-hover-word-lists.md) (word readings; tooltips took none) · [ADR-039](039-word-meanings-written-in-context.md) (meanings) · [ADR-041](041-word-cards-on-window-labels.md) (word cards on window labels; not on tooltips) · [ADR-018](018-reveal-key-override-binding.md) (the addon's key bindings)

## Context

A tooltip belongs to whatever the mouse is on. Moving the mouse toward it hides it, so a word in it can never be pointed at. For that reason ADR-036 and ADR-041 gave tooltips no word cards, and item and spell text never got readings. That text is a large share of the Japanese a player reads: 11,129 item lines and 26,087 spell lines can carry a word list.

The client has no way to hold a tooltip open. Its files (build 1.60.1.71037) have one tooltip that stays, the one a chat link opens, which only covers things that have a link in chat.

The maintainer tried a trial in game on 2026-11-22: a key that freezes the tooltip in place, with word cards on it. He approved it and asked for the full version.

## Decision

1. **A key freezes the tooltip as a copy.** While a tooltip shows, the binding "Freeze the tooltip" draws a copy of it in the same place: same size, lines, fonts and colours, with the comparison tooltips beside it. The copy stays when the game hides its own tooltip. The key again, or Esc, closes it. The key over another tooltip makes the copy that one's.
2. **The game's tooltip is never held open and never changed.** Whatever the mouse was on hides it on leave, from inside its own handler. Standing in the way of that would run addon code in the action buttons' handlers. The copy is a frame of the addon's own.
3. **The copy is a word-card surface.** Each line the addon wrote in Japanese takes word cards and the save click from that line's own data: an item's description, a spell's description or aura, a window word (`ui`), a quest title. The line is found through the record the addon kept when it wrote it (its kind, id and the exact text written), read at the key press, because the records go when the tooltip hides.
4. **Which lines take none.** A line the client has rewritten since the addon wrote it. A line the addon never wrote (a name, a number line). A line holding a texture or a link. A copy made in combat: the addon keeps no per-line record of what it writes in combat, and a cover cannot be made there. A copy made while English is showing or with translation off: it shows the text as it stood, with no cards.
5. **A line coloured in parts is measured on a twin.** The word-card view refuses text holding an escape sequence, because how the client counts bytes around one is not verified. The copy draws the line as shown and lays a second line over it with the same text minus its colour codes, same font and width, at no opacity. Colour codes take no room, so both wrap alike, and the words are measured on the twin.
6. **Item and spell text ships readings and meanings.** Two new reading types, `item` and `spell`, in the existing record and row format: `data/reading/item/`, `data/reading/spell/`, generated to `Data/Reading/Reading_item_*.lua` and `Reading_spell_*.lua`, rows `["item:<id>"]` and `["spell:<id>"]`. Every flow that changes item or spell Japanese writes them in the same round, as for quest text.
7. **A tooltip line's words are written a sentence at a time.** Tooltip lines repeat each other by the sentence: the same sentence with another item's name ("…の作り方を習得します。" stands in 884 lines), or with another number behind its placeholder. A line is cut into pieces at its line breaks and after each 。！？ that is not inside brackets or quotes. A `$?…[a][b]` branch is cut apart at its brackets only when each bracket holds whole sentences; a branch that chooses between parts of one sentence stays in that sentence. Two pieces are the same sentence when they match with the branch condition, the number of each placeholder, every English name and every number no Japanese follows left out: none of those can be a word, so both hold the same words in the same order. The placeholder's letter still counts, and so does a number with Japanese right after it, because a counter reads by the number before it. A sentence with nothing to list (an English name and a particle) is written with an empty word list. `wfj readings export-tooltips` writes one row for each sentence nobody has written; `wfj readings import-tooltips` checks each row against its sentence and builds every line whose sentences are all written; `wfj readings spread` builds a line added or changed later. The written sentences are read back out of the current records, so there is no second store. A line with a current reading of its own, a correction among them, is left alone. `make import-draft` and `make report-apply` run the reuse step (`make tooltip-words`), so a new tooltip that says nothing new costs no drafting.
8. **Words are checked against the shipped text.** Generate ships a hand-written tooltip line with its manual breaks joined, and a break can fall inside a sentence or a number. So a tooltip line's sentences, its word checks and its stale hash all use the line as it ships (`readings.japanese_of`), in export, import, generate, validate and coverage alike.
9. **No English word cards on tooltips.** English first shows the client's own tooltip; the copy shows it as it stood. Item and spell readings ship no English card rows.
10. **Objective and area text still take no readings.** They are tracker and quest-log lines, not tooltip text.
11. **The binding gets a first key, once.** Once per account, at login out of combat, when the binding has no key and nothing is bound to Ctrl+F, the addon binds Ctrl+F to it and saves the bindings. It never takes a key from another action, and it never binds again after that once (a player who unbinds it keeps it unbound). A login in combat makes the offer when combat ends.
12. **The bindings have their own section and their names follow the language.** Every binding names the category `BINDING_HEADER_WFJ`, so the client lists them under "WoW Forever Japanese" instead of under Other with a header row drawn as a key. The six binding names are Japanese or English by the settings pages' rule.
13. **The word card and the reading box are solid.** They draw a fill under their border on every surface, so text behind them never shows through. A card over a tooltip's text was hard to read without it.
14. **The welcome window names the key.** Nothing on screen shows that a tooltip can be frozen, so the welcome window's second page carries one point on it for a player who chose to study Japanese: the key as bound, or where to set one while the binding has no key. It is left out for the other two choices, where a frozen tooltip has no word cards.

## Consequences

- The addon gains one reading row for each item and spell line that ships Japanese with something to annotate: about 37,000 rows on top of about 50,000. The generated size and load cost are measured before the drafting round.
- The first drafting round covers about 17,000 sentences, a third less text than drafting each distinct line. A first 200 lines, drafted whole, already built 2,546 more lines. After the round, a tooltip translation batch owes only the sentences nobody has written, and `validate` lists the lines that lack a word list.
- A tooltip line holding an escape sequence in its stored text is never owed a reading (`export-tooltips` lists each).
- The saved word list gains two sources, `item` and `spell`.
- The first key writes the player's saved bindings without a click from them. It is held to an empty key, once.
- A player on English first gets the frozen copy without cards.
- The in-game window test gains a frozen-tooltip check when it reaches the same branch as this change.
- The critical rules list the frozen tooltip among the allowed on-screen additions.
