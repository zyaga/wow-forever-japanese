# Coverage: how much of the game ships in Japanese

> **Generated** by `make coverage` (`pipeline/wfj/dev/coverage.py`) on 2026-10-02 at commit `5d94983`.
> Do not edit by hand: every pull request that changes `data/` re-runs it. Measured from
> the English the Forever client serves; spells are the player-visible set; a line that is only a
> name, a placeholder quest or a picture-only page counts as done (nothing to translate).

## Translation

| Surface | English lines | Ship Japanese | Nothing to translate | Done | Not yet |
|---|---|---|---|---|---|
| Quest text | 19,452 | 19,341 | 111 | 100.0% | 0 |
| NPC dialogue (gossip, speech) | 10,641 | 10,641 | 0 | 100.0% | 0 |
| Book / letter pages | 1,257 | 1,205 | 52 | 100.0% | 0 |
| Quest objective lines | 409 | 372 | 37 | 100.0% | 0 |
| Exploration / event objectives | 218 | 216 | 2 | 100.0% | 0 |
| Item descriptions | 10,124 | 8,611 | 0 | 85.1% | 1,513 |
| Spell tooltips + auras (player-visible) | 10,302 | 10,248 | 0 | 99.5% | 54 |
| Interface strings | 13,697 | 13,697 | 0 | 100.0% | 0 |
| **All** | **66,100** | | | **97.6%** | **1,567** |

Lines shipped as their English under a maintainer ruling (`ruling: accept`, for names, classes,
professions, internal strings): quest 329, gossip 81, item 888, spell 285, ui 86.

### Nothing to translate (counted as done)

| Surface | Why | Lines |
|---|---|---|
| Quest objective lines | name only (`pipeline/objective_names.txt`) | 37 |
| Exploration / event objectives | name only (`pipeline/area_names.txt`) | 2 |
| Quest text | placeholder quest (never shown) | 108 |
| Quest text | a bare label: a name or a one-word placeholder (ships as the English) | 3 |
| Book / letter pages | Missing Text / picture-only page | 49 |
| Book / letter pages | picture-only or cipher page | 2 |
| Book / letter pages | a bare label: names and numbers only (ships as the English) | 1 |

### What is not done yet

| Surface | Why | Lines |
|---|---|---|
| Item descriptions | no Japanese yet: no text from the Forever tables on this build yet (English still from Classic Era); rechecked at each re-pull | 1,511 |
| Item descriptions | no Japanese yet | 2 |
| Spell tooltips + auras (player-visible) | no Japanese yet | 30 |
| Spell tooltips + auras (player-visible) | no Japanese yet: no text from the Forever tables on this build yet (English still from Classic Era); rechecked at each re-pull | 22 |
| Spell tooltips + auras (player-visible) | rejected: ruled_reject | 2 |

## Word cards (readings with meanings)

| Type | Lines that can carry a word list | With one | Done | Stale | Words | With a meaning |
|---|---|---|---|---|---|---|
| quest | 18,037 | 18,037 | 100.0% | 177 | 285,915 | 100.0% |
| gossip | 10,513 | 10,513 | 100.0% | 0 | 98,175 | 100.0% |
| ui | 13,265 | 13,265 | 100.0% | 0 | 39,889 | 100.0% |
| book | 1,167 | 1,167 | 100.0% | 0 | 39,571 | 100.0% |

Item, spell, objective and area text take no word cards; HTML book pages
and lines holding a `|` escape are not counted.
