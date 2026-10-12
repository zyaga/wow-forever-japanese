# ADR-065: Recipe and set bonus lines from the tooltip data

- **Status:** Accepted
- **Date:** 2026-10-12
- **Related:** [ADR-010](010-tooltip-in-place-run-replacement.md) (the description run) · [ADR-007](007-unaligned-ships-with-runtime-gate.md) (the tooltip align gate) · [ADR-016](016-whole-window-interface-coverage.md) (the UI dictionary) · [ADR-028](028-a-duration-is-copied-not-named.md) (durations) · [ADR-064](064-collector-keeps-only-what-the-addon-cannot-show.md) (what the collector keeps) · [Addon modules](../architecture/addon-modules.md)

## Context

After [ADR-064](064-collector-keeps-only-what-the-addon-cannot-show.md), the English Collector's waiting count on the maintainer's file was down to a few lines, and each was an item tooltip that really showed English in game on Forever 1.60.1.70338:

- **Recipes.** On Forever a recipe's tooltip is the crafted item's whole tooltip as a nested block, then the recipe's own "Use: Teaches you how to …" line. The description run took both items' lines as one run under one id, which matched neither item's Japanese.
- **The cooldown tail.** The client appends an item's cooldown to its spell line ("… over 18 sec. (1 Sec Cooldown)"). The tail's number counted as one of the line's values, so a branch line picked the wrong variant or none.
- **Forever's own stat lines.** The client writes many `Equip:` lines from `TOOLTIP_ITEM_STAT_*` global strings ("Equip: Improves your chance to hit by 1%.", spell power and healing, weapon skills, resistance piercing, attack power against a creature type). The UI inventory never listed that family, so an item whose only text was such lines stayed English.
- **Set bonus lines.** "(2) Set: %s" and "Set: %s" were excluded with the reason that no Forever file writes them. The game showed them. Their `%s` is a bonus spell's description, and the item's tooltip does not say which spell.

Separately, the spell API's description keeps the client's plural code ("for 1 |4hour:hrs;."), while the tooltip line shows the words. A line holding the code had no duration `Align.durations` could find.

## Decision

1. **A recipe is split by the tooltip data.** `Tooltip.recipeOf(frame, lineCount)` reads `GetPrimaryTooltipInfo().tooltipData`: its `id` is the recipe, the `NestedBlock` line whose `tooltipType` is Item gives the crafted item in `tooltipID`, and the `ItemSpellTriggerLearn` line's `lineIndex` is the recipe's own row. The description run is searched above that row and shown with the crafted item's Japanese; the row is a run of its own (record tag `learn`) with the recipe's Japanese. Each is recorded to the Collector under its own id. The item link may name either item, so the ids come from the data, not the link. The layout was seen in game with a probe build.
2. **The cooldown tail is peeled like the max-level trailer.** `peelTrailer` also takes off "(1 Sec Cooldown)" (`ITEM_COOLDOWN_TOTAL`, `_SEC`, `_MIN`, matched with and without the leading space). The peeled texts are what the run is matched against and what the Collector records. A trusted line gets the tail's Japanese appended; a gated line shows its Japanese without the tail, and the modifier shows it, as gated lines already did with the trailer.
3. **Forever's stat lines are UI keys.** The inventory's `FAMILIES` includes `TOOLTIP_ITEM_STAT_`. Of its 160 strings, 152 ship in Japanese (`装備時:` first; school and most creature names in English letters as in spell tooltips; アンデッド and 悪魔 per the glossary; skill names in English). Excluded with reasons: `TOOLTIP_ITEM_STAT_FORMAT` and `_RANGE_FORMAT` (bare layout strings). The six two-handed skill strings are left out of the inventory itself: their names hold a hyphen, and a UI key is a global name of letters, digits and underscores. `Index:statLine(text)` is the one test for an `Equip:` line the dictionary translates whole (the `equip` form or a `TOOLTIP_ITEM_STAT_*` key). The tooltip's `Equip:` walk uses it, and so does the Collector, through an optional dep `statLine`: an item with no row of its own is covered when every recorded line passes.
4. **A set bonus line takes its spell's Japanese.** `ITEM_SET_BONUS_GRAY` is a UI key whose `%s` is verbatim and which matches only where the tooltip asks for it (`UIStrings.ONLY`). The active "Set: %s" shares its English with `BOSS_BANNER_LOOT_SET`, so the tooltip reads it by the client's own `ITEM_SET_BONUS` prefix. `Tooltip.setSpells(id)` asks `C_Item.GetSetBonusesForSpecializationByItemID(spec or 0, itemID)`, which answers on Forever. A line belongs to the bonus spell whose rendered description (`C_Spell.GetSpellDescription`) equals the line's text; when none does, to the one spell whose Japanese the tooltip gate accepts for it (`WFJ.GateText`). The line is written as the wrapper's Japanese with that Japanese inside ("(2) セット: 命中率を2.0%上昇させます。"). A line no spell fits stays English whole. When exactly one English set line and one unclaimed bonus spell are left, the line is recorded to the Collector as that spell's description.
5. **One gate function.** `WFJ.GateText(entry, lines)` in `Main` is the Translator's align calls without the switches. The set bonus lines and the Collector's `aligns` dep both use it, so "would this Japanese show here" has one answer.
6. **Durations in the plural code.** `Align.durations` reads "1 |4hour:hrs;" and "5 |4Hr:Hrs; 30 |4Min:Mins;" as duration phrases, tried before the plain shapes and kept whole with the closing `;` ([ADR-028](028-a-duration-is-copied-not-named.md)).

## Rationale

- The tooltip data is the client's own account of what each row is. Reading it is exact where any rule over the text guesses.
- The set bonus API and the rendered spell description are both answers the game gives at the moment the tooltip shows, so the addon ships no item-to-set map that a build could make stale.
- A tail the client adds is not the item's text. Matching without it keeps every number the drafter saw in the place the drafter saw it.
- Measured on the maintainer's collector file with all of this in place: the waiting count went from 155 to 1, a quest line from an older build that differs from the shipped English by one letter.

## Consequences

### Positive
- Recipe tooltips show both items' text in Japanese, and both are recorded under the right id.
- Set bonus lines show in Japanese wherever the bonus spell has Japanese, with no new data to keep in step.
- 152 more kinds of item stat line show in Japanese, and items made only of them stop waiting in the collector.

### Negative
- The recipe split depends on tooltip data types (`NestedBlock`, `ItemSpellTriggerLearn`) that were seen on one build. If a later build drops them, `recipeOf` returns nil and the tooltip falls back to one run under the link's id, as before.
- A gated line that carries a cooldown tail hides the tail until the modifier is held.
- The six two-handed skill lines stay English until the key rule can hold a hyphen.
- A set line whose spell has no Japanese, or two spells that both fit, stays English.

## Alternatives considered

- **Ship an item → set → spell map from the client tables:** rejected. The ItemSet tables are not in the local extract, and the API answers in game.
- **Split recipes by text position** (the crafted item's run ends at its requirement line): rejected. It fails when the crafted item has no requirement line.
- **Strip the cooldown tail only from the Collector's copy:** rejected. The run's match would still count the tail's number, which is what picked the wrong branch.
