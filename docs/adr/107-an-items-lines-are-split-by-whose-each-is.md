# ADR-107: An item's lines are split by whose each is

- **Status:** Accepted
- **Date:** 2026-11-23
- **Deciders:** the maintainer
- **Related:** [ADR-010](010-tooltip-in-place-run-replacement.md) (the description run) · [ADR-016](016-whole-window-interface-coverage.md) (stat lines) · [ADR-064](064-aura-inclusions-list-tails-and-variant-keys.md) (variant keys) · [ADR-104](104-a-filled-tooltip-line-ships-the-count-of-its-values.md) (value counts) · [Addon modules](../architecture/addon-modules.md) · [Data model](../architecture/data-model.md)

## Context

An item tooltip's "Use:", "Equip:" and "Chance on hit:" lines sit in one run, and the addon matched that whole run against the item's one shipped description. Many items have more of those lines than the description covers, and on those the tooltip went wrong. The window test read three in game:

- Slime-encrusted Pads: "Equip: Restores 3 Mana per 5 sec." got the not-translated marker, and "Equip: Restores 10 Health per 5 sec." stayed English.
- Worgenbane Talisman: "Equip: Restores 2 Mana per 5 sec." got the marker, and the use line, which is the item's description, stayed English.
- Rod of the Sleepwalker: the spell power line got the marker, and the Sleep line, which is the item's description, stayed English.

The client writes those mana, health and spell power lines from its own interface strings (`TOOLTIP_ITEM_STAT_MANA_REGEN_INCREASE` and the like, by its compiled tooltip code, with no Lua writer in the interface files), not from a spell's description: the strings say "Mana", the spells' descriptions say "mana". The addon already ships Japanese for those strings. The Talisman's use line also ends in the client's cooldown tail, whose number kept the description from fitting it. The Rod's name holds "Sleep", so its description seemed to fit the spell power line as well.

A line can also print a spell the item's description does not include at all. About 600 items still carry English taken from another client's tables, which joined a spell that Forever now prints as a stat line; the other spell lines on those items (588 of them) have Japanese of their own, as spell descriptions.

Nothing the client gives names the spell behind one line: `C_Item.GetItemSpell` names one spell per item, `GetItemStats` gives stats, and a tooltip data line carries its kind but no documented spell field.

## Decision

1. **The client's tail comes off every line of the run first**, so a cooldown's number is never one of a line's values.
2. **The description takes only the lines its Japanese fits.** A Japanese of one paragraph takes one line: the one it fits; when it fits several, those it fits without the item's name, then those that are no stat line, then the line whose words are its English. A Japanese of several paragraphs takes the longest block of lines it fits, stat lines inside it folded in as before.
3. **Every other line is whose it is.** A line the dictionary has as a stat line shows that Japanese. Else the spell it prints, found by the line's shape, shows that spell's Japanese, filled and gated on that line like any spell description. Else the line stays as the client wrote it, with no marker.
4. **The shape is the line's wording with every value masked**, keyed as a keyed branch line is (ADR-064): `align.variant_key` of the spell's English, `Align.variantKey` of the live line without its trigger word, held equal by the align vectors. `wfj generate` writes `Data/SpellShapes.lua`, shape key to spell id, only for shapes some item's description English prints, and only when every spell description of that shape ships the same Japanese with the same status. Keys only; no English ships.
5. **The marker goes only on the description's own lines.** When its Japanese fits no line, it owns what nothing else explained, when that is one place: the one line left for a Japanese of one paragraph, one block for several. A run nothing else explains stays whole, as before.

## Consequences

- The three items show every line in Japanese with no marker.
- The shape table holds about 2,000 keys (66 KB of Lua) on this build.
- A shape whose spells ship different Japanese (the mana regeneration shape has one spell drafted as `$N2秒ごとに`) gives no spell, so such a line stays English until its spells agree.
- A line the addon writes from a spell is that spell's record, with its own word cards and its own gate; the Collector still reads the run the item's description owns, or the whole run when it owns none.
- The item a spell makes, shown under that spell's tooltip, keeps the old handling.

## Alternatives considered

- **The client's own data per line.** None names the spell (see above). If a later client puts a spell id on a tooltip data line, that is the better source.
- **Splitting the item's own Japanese into paragraphs, one per line.** Its placeholders are numbered across the whole description and its value count is the whole description's, so a paragraph alone cannot be filled or gated safely.
- **Every spell's shape in the table.** Only shapes an item prints can be on an item's line; the rest would be dead weight.
