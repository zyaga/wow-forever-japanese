# ADR-059: A gender branch is trimmed, and the quest log's markers sit beside its back button

- **Status:** Accepted
- **Date:** 2026-10-04
- **Related:** [ADR-005](005-gossip-key-fingerprint.md) (normalize_v1) · [ADR-019](019-quest-english-per-field-and-live-check.md) (the live check) · [ADR-024](024-gender-variants-and-short-name-candidates.md) (female variants) · [ADR-003](003-ship-stale-with-marker.md) (the stale marker) · [Pipeline](../systems/pipeline.md)

## Context

A playtest on Forever 1.60.1.70205 showed `[要更新 / English Changed]` on the Coldridge Valley mail delivery quest, whose English had not changed. The stored English writes the gender code with spaces around its branches: `do a favor for me, $g lad : lass;?`. The collector recorded what the client shows from the same quest: `do a favor for me, lad?`. The client trims a branch. `normalize_v1` kept the first branch with its spaces (`lad ?` after the whitespace collapse), so the stored hash never matched the live English, and the live check called the line changed.

The same shape (`$g lad : lass;`, `$G sir : ma'am;`, `$gboyo : girlie;`) is in 107 stored lines: 79 gossip keys and 28 quest fields. A gossip line keyed on the untrimmed form was never found in game at all.

Separately, on the quest log's details pane the marker was drawn inline, on its own line above the description. It pushed the text down and read as part of the quest.

## Decision

1. **`normalize_v1` trims a gender branch**, in Python and in `Core/Normalize.lua` alike: `$G<male>:<female>;` becomes the male branch without the spaces around it, and `female_variant` does the same for the female branch. Two hash vectors (`gender-03`, `gender-04`) hold both sides to it.
2. **Stored hashes are re-stamped, nothing is retranslated.** `python -m wfj.dev.rehash_english` recomputes every English hash. A gossip key moves to its new key with its translations and readings. A translation that recorded the old hash gets the new one: the text is the same, only how it is hashed changed. Where the new key is already another English line (the same text from a second source, five on this corpus), the line with a gender code keeps the key, since it speaks for both wordings (its female key ships as an alias, ADR-024); otherwise the line already there stays. The other line is dropped with its translations and readings, and each drop is printed. The run stops with nothing written when a drop would lose a hand-written translation or the only translation, or when two lines move to one key. Only ASCII whitespace is trimmed, the set Lua's `%s` matches, so both sides hash alike.
3. **The details pane's markers go to the right of its back button, one per line**, a banner of the addon's own anchored to the button (`QuestMap.makeBanner`). The client's other widget in that strip, the account-completed notice, hides itself on load and its refresh is empty on Forever (`blizzard_uipanels_game/camelot/questframetemplates.lua:1-15`), so the spot is free. The tracker's popup has no back button and keeps its markers inline.

## Consequences

- 79 gossip keys moved and 28 quest fields re-stamped. At the 5 shared keys the line with the gender code was kept and the male-only capture from a second source was dropped, so female characters keep their Japanese there (199 gender aliases before and after). No Japanese changed.
- A future source that spaces a gender code the same way hashes to what the client shows.
- The re-hash tool is the step to run after any later change to `normalize_v1`.
