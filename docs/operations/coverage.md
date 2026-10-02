# Coverage: how much of the game ships in Japanese

> **Generated** by `make coverage` (`pipeline/wfj/dev/coverage.py`) on 2026-10-02 at commit `9bb3134`.
> Do not edit by hand: every pull request that changes `data/` re-runs it. Measured from
> the English the Forever client serves; spells are the player-visible set; a line that is only a
> name, a placeholder quest or a picture-only page counts as done (nothing to translate).

## Translation

| Surface | English lines | Ship Japanese | Nothing to translate | Done | Not yet |
|---|---|---|---|---|---|
| Quest text | 19,452 | 19,337 | 108 | 100.0% | 7 |
| NPC dialogue (gossip, speech) | 10,641 | 10,641 | 0 | 100.0% | 0 |
| Book / letter pages | 1,257 | 1,203 | 50 | 99.7% | 4 |
| Quest objective lines | 409 | 372 | 37 | 100.0% | 0 |
| Exploration / event objectives | 218 | 216 | 2 | 100.0% | 0 |
| Item descriptions | 10,124 | 8,611 | 0 | 85.1% | 1,513 |
| Spell tooltips + auras (player-visible) | 10,302 | 10,248 | 0 | 99.5% | 54 |
| Interface strings | 13,593 | 13,512 | 0 | 99.4% | 81 |
| **All** | **65,996** | | | **97.5%** | **1,659** |

Lines shipped as their English under a maintainer ruling (`ruling: accept`, for names, classes,
professions, internal strings): quest 329, gossip 81, item 888, spell 285, ui 4.

### Nothing to translate (counted as done)

| Surface | Why | Lines |
|---|---|---|
| Quest objective lines | name only (`pipeline/objective_names.txt`) | 37 |
| Exploration / event objectives | name only (`pipeline/area_names.txt`) | 2 |
| Quest text | placeholder quest (never shown) | 108 |
| Book / letter pages | Missing Text / picture-only page | 49 |
| Book / letter pages | picture-only or cipher page | 1 |

### What is not done yet

| Surface | Why | Lines |
|---|---|---|
| Quest text | no Japanese yet | 7 |
| Book / letter pages | no Japanese yet | 4 |
| Item descriptions | no Japanese yet: no text from the Forever tables on this build yet (English still from Classic Era); rechecked at each re-pull | 1,511 |
| Item descriptions | no Japanese yet | 2 |
| Spell tooltips + auras (player-visible) | no Japanese yet | 30 |
| Spell tooltips + auras (player-visible) | no Japanese yet: no text from the Forever tables on this build yet (English still from Classic Era); rechecked at each re-pull | 22 |
| Spell tooltips + auras (player-visible) | rejected: ruled_reject | 2 |
| Interface strings | no Japanese yet | 81 |

## Word cards (readings with meanings)

| Type | Lines that can carry a word list | With one | Done | Stale | Words | With a meaning |
|---|---|---|---|---|---|---|
| quest | 18,033 | 18,033 | 100.0% | 177 | 285,908 | 100.0% |
| gossip | 10,513 | 10,513 | 100.0% | 0 | 98,175 | 100.0% |
| ui | 13,162 | 13,162 | 100.0% | 0 | 39,731 | 100.0% |
| book | 1,165 | 1,165 | 100.0% | 0 | 39,566 | 100.0% |

Item, spell, objective and area text take no word cards; HTML book pages
and lines holding a `|` escape are not counted.
