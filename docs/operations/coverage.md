# Coverage: how much of the game ships in Japanese

> **Generated** by `make coverage` (`pipeline/wfj/dev/coverage.py`) on 2026-09-30 at commit `65ba82b`.
> Do not edit by hand: every pull request that changes `data/` re-runs it. Measured from
> the English the Forever client serves; spells are the player-visible set; a line that is only a
> name, a placeholder quest or a picture-only page counts as done (nothing to translate).

## Translation

| Surface | English lines | Ship Japanese | Nothing to translate | Done | Not yet |
|---|---|---|---|---|---|
| Quest text | 19,188 | 19,064 | 118 | 100.0% | 6 |
| NPC dialogue (gossip, speech) | 10,641 | 10,641 | 0 | 100.0% | 0 |
| Book / letter pages | 1,257 | 1,203 | 50 | 99.7% | 4 |
| Quest objective lines | 395 | 358 | 37 | 100.0% | 0 |
| Exploration / event objectives | 217 | 215 | 2 | 100.0% | 0 |
| Item descriptions | 10,086 | 8,537 | 0 | 84.6% | 1,549 |
| Spell tooltips + auras (player-visible) | 10,280 | 10,201 | 0 | 99.2% | 79 |
| Interface strings | 13,392 | 13,392 | 0 | 100.0% | 0 |
| **All** | **65,456** | | | **97.5%** | **1,638** |

Lines shipped as their English under a maintainer ruling (`ruling: accept`, for names, classes,
professions, internal strings): quest 329, gossip 81, item 880, spell 279, ui 4.

### Nothing to translate (counted as done)

| Surface | Why | Lines |
|---|---|---|
| Quest objective lines | name only (`pipeline/objective_names.txt`) | 37 |
| Exploration / event objectives | name only (`pipeline/area_names.txt`) | 2 |
| Quest text | placeholder quest (never shown) | 118 |
| Book / letter pages | Missing Text / picture-only page | 49 |
| Book / letter pages | picture-only or cipher page | 1 |

### What is not done yet

| Surface | Why | Lines |
|---|---|---|
| Quest text | no Japanese yet | 6 |
| Book / letter pages | no Japanese yet | 4 |
| Item descriptions | no Japanese yet: English still from wago (Classic Era); waits for the Forever re-pull | 1,505 |
| Item descriptions | no Japanese yet | 33 |
| Item descriptions | rejected: ruled_reject | 9 |
| Item descriptions | rejected: duplicate_conflict | 2 |
| Spell tooltips + auras (player-visible) | no Japanese yet | 55 |
| Spell tooltips + auras (player-visible) | no Japanese yet: English still from wago (Classic Era); waits for the Forever re-pull | 22 |
| Spell tooltips + auras (player-visible) | rejected: ruled_reject | 2 |

## Word cards (readings with meanings)

| Type | Lines that can carry a word list | With one | Done | Stale | Words | With a meaning |
|---|---|---|---|---|---|---|
| quest | 17,774 | 17,774 | 100.0% | 175 | 281,935 | 100.0% |
| gossip | 10,513 | 10,513 | 100.0% | 0 | 98,175 | 100.0% |
| ui | 13,043 | 13,043 | 100.0% | 0 | 39,014 | 100.0% |
| book | 1,165 | 1,165 | 100.0% | 0 | 39,566 | 100.0% |

Item, spell, objective and area text take no word cards; HTML book pages
and lines holding a `|` escape are not counted.
