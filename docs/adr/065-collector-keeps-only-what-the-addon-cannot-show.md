# ADR-065: The collector keeps only what the addon cannot show

- **Status:** Accepted
- **Date:** 2026-10-12
- **Related:** [ADR-013](013-collector-english.md) (collector English) · [ADR-056](056-collector-send-string.md) (the send string) · [ADR-061](061-voice-over-from-a-separate-pack.md) (voice over) · [ADR-007](007-unaligned-ships-with-runtime-gate.md) (the tooltip align gate) · [Collector](../systems/collector.md)

## Context

The English Collector's waiting count (the login reminder, the minimap menu entry and tooltip, the send window, `/wfj collector status`) is meant to say how many lines the addon still needs. After the 1.60.1.70338 re-pull, the maintainer's own collector file showed 155 lines waiting, and almost all of them already showed in Japanese in game. Three kinds of line were counted wrongly:

- **Item and spell tooltips.** They are recorded with the character's numbers filled in ("Heals 70 to 90 damage over 12 sec."). The shipped row carries the hash of the client's template, so the exact hash check never matched any of them.
- **Quest lines that name a class or race in plain words.** Recording turns the reader's own class and race into `$C` / `$R`, so a Warrior stores "the warrior trainer" as "the $C trainer". The shipped English says "warrior" literally, so the hashes differed.
- **NPC names.** They never get Japanese (names stay English), so every one counted forever.

Lines were also never removed once a release covered them; only a send or a clear made the count go down.

## Decision

1. **One check: the display gate.** `covered(entry)` says whether the addon shows Japanese for this English. Recording ("known", nothing written), the unsent count, the send list and the prune all use it.
2. **Quest literal forms.** After the exact `h1` / `h1f` match, each form the stored text may have had on screen is tried: `$C` and `$R` each kept, or replaced by the recording character's word from `p` as written or lowercased, at most 9 forms, masked as before when the Japanese carries `$N<k>` / `$D<k>`. A line with no `p` gets no literal forms.
3. **Tooltips through the tooltip align gate.** An item or spell line is covered when its row has Japanese and the same align gate the tooltip uses accepts that Japanese for the recorded paragraphs. The gate enters `Collector` as an optional dep, `aligns(entry, lines)`, which `Main` wires with `WFJ.GateText`: the Translator's align calls (`WFJ.Align` and the UI index's duration renderer) without the switches. Without the dep no item or spell line is covered. An item with no row of its own is covered when every recorded line is an `Equip:` stat line the dictionary translates whole, through a second optional dep, `statLine(text)` ([ADR-066](066-recipe-and-set-bonus-lines-from-the-tooltip-data.md)).
4. **NPC names are kept but never counted.** They are still recorded (voice casting reads them from `data/english/unit`). They never count toward the reminder, the minimap entry or the status, and they ride along with a send only when at least one line goes, or with `send all`.
5. **Prune on load.** `Collector.prune()` drops every covered entry (never an NPC name) and its sent row. `Main` runs it as its own step right after the UI index is built, because the duration renderer needs it. A file from a newer version is never touched, and an entry whose check raises is kept.

## Rationale

- The count should answer "what does the addon still need?", and the only honest answer is what the display does. Any other rule drifts from it.
- Collector stays free of world access: the align knowledge comes in as a dep, the way the Translator gets it.
- Measured on the maintainer's file (364 entries, 164 sent): this decision alone takes the count from 155 to 4, and a prune drops 266 entries and keeps 98, 90 of them NPC names. With recipes, the cooldown tail and Forever's item stat lines read apart as well ([ADR-066](066-recipe-and-set-bonus-lines-from-the-tooltip-data.md)), the count is 1.

## Consequences

### Positive
- The reminder and the minimap count show only lines the addon cannot show in Japanese, so a player who sees a number has something worth sending.
- The collector file shrinks after an update to what is still missing, which frees space under the 4 MB cap.

### Negative
- A tooltip the game reworded while keeping its numbers counts as covered. That is exactly what the display does (it shows the Japanese), and tooltip English is read again from the client tables on every re-pull, so the rewording is caught there.
- Pruned entries are gone from the file. They are only lines the addon ships Japanese for; anything the addon cannot show is recorded again the next time it is seen.
- A residue still counts, and it is real: a quest line a build reworded. On the maintainer's file that is one line, recorded on an older build, whose English differs from the shipped English by one letter. Recipe tooltips and the "(1 Sec Cooldown)" tail, which counted here at first, are read apart now ([ADR-066](066-recipe-and-set-bonus-lines-from-the-tooltip-data.md)).
- A spell description from the spell API keeps the client's plural code ("for 1 |4hour:hrs;."), while the tooltip line shows the resolved words. `Align.durations` reads a duration written in that code, so the collector's copy of such a line is covered like the tooltip it came from.

## Alternatives considered

- **Ship masked template hashes from the pipeline:** rejected. Filled values like "70 to 90" and durations never mask back to the template, so many tooltips would still miss.
- **Prune any entry whose id ships Japanese:** rejected. It would drop real rewordings, the lines the collector exists to catch.
- **Stop recording NPC names:** rejected. Voice casting reads them.
