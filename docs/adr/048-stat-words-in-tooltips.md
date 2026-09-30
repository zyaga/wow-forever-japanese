# ADR-048: Stat words in tooltips use the interface's Japanese

- **Status:** Accepted. Style guide version sg12. Runbook: [Translation batches → Scripted redraft](../operations/translation-batches.md#scripted-redraft-a-word-swap).
- **Date:** 2026-09-30

## Context

Item and spell tooltip text names stats and resources: armor, health, mana, stamina, strength, agility, intellect, spirit, rage, energy. The hand-written corpus keeps these words in English letters (`Healthを70回復`), and the style guide up to sg11 told the drafting model to do the same. So machine tooltip lines wrote `healthを$N1回復します。`.

The interface text already translates the same words. The character sheet and an item's stat lines show アーマー, 体力, スタミナ (`STAT_ARMOR`, `HEALTH`, `SPELL_STAT3_NAME` …). A player reading a food tooltip saw `health` a few lines below a stat pane that says 体力. The two halves of one screen disagreed.

The ten words are on `pipeline/allowlist.txt`, the list of Latin words the name check does not read as names. The runtime name gate (`Core/Align.lua`) reads the same list. An estimated 170 hand-written item and spell lines still ship with these words in English letters, and many of them are checked against live English that includes another spell's text (`$@spelldesc`), which cannot be verified offline.

## Decision

1. **Tooltip stat words use the interface's Japanese.** armor アーマー, health 体力, mana マナ, stamina スタミナ, strength 筋力, agility 敏捷性, intellect 知力, spirit 精神, rage 怒り, energy エネルギー, in any case (`Increases Stamina by $s1.` → `スタミナが$N1増加します。`). `health` is never ヘルス. A stat word inside a name stays English with the name (`Mana Shield`, `Elixir of Agility`, `Spirit of Zandalar`). The words sit in the style guide's settled interface terms table and in `core/stat_words.STAT_WORDS`; a test holds the two equal.
2. **Energy is エネルギー**, the interface's `ENERGY`, not 気力.
3. **Machine lines are held to it; hand-written lines are not.** `translate_lint` fails a tooltip row (`item_description`, `spell_description`, `spell_aura`) that keeps a stat word in English letters on its own or writes ヘルス (`stat_word:<word>`). On those rows a stat word the English uses on its own (`Increases Stamina by $s1`) is no name the Japanese must keep; one inside a name in the English (`Elixir of Agility`, `Mana Shield`) still is. `test_style_guide.py` fails while any shipped machine item or spell line breaks the rule. `human` and `correction` lines keep their translators' spelling, under the rule that machine output never replaces a hand-written line.
4. **The allowlist keeps the ten words.** Only their comments changed: they now say the hand-written corpus keeps them in English letters. Taking them off would change no offline status, but it would put the hand-written lines that use them in front of the runtime name gate, where a line that fails falls back to English. That would be a regression on lines this decision does not touch.
5. **Existing machine lines are redrafted by a script, not a model.** The change is a word swap. `dev/draft_stat_words.py` swaps the words in every shipped machine item and spell line that keeps one, writes one draft file per drafting model, and checks that each row differs from its line only by the swapped words. Each redrafted line keeps the model that wrote its words: one draft per drafting model (`draft-stat-words-o5-sg12@2026-09-30`, `draft-stat-words-o55-sg12@2026-09-30`), each tag given with `--tag MODEL=TAG`. Every distinct context of a swapped word was read before import for a stat word that is really part of a name; none was found. The old variants stay in `conflicts`, and the redrafts win on the style-version tiebreak.
6. **Accept rulings move to the redraft.** Where the maintainer had accepted a machine line in place of rejected hand-written text, the accept would keep that old line winning, because an accept beats every tiebreak. `draft_stat_words --move-accepts DATE` moves the accept onto the redraft of the same text. The ruling keeps who made it, its date and its reason, and its note adds where it moved and why. The hand-written variants stay ruled `reject`.

## Consequences

- Stat words in machine tooltip text read like the character sheet. 2,790 machine lines were redrafted by the swap (item 832, spell 1,958), and three more spell lines by hand, where the English stat word sits beside an English word that is no name (`Strength Increased`, `Energy Regeneration`: now 筋力 and エネルギー回復); 446 of them (item 373, spell 73) carried an accept ruling, now on the redraft with its original date and reason. No line changed status, and no `human` or `correction` variant changed.
- Hand-written tooltip lines still show `health`, `mana` and the rest in English letters, so a player can see both spellings in different tooltips. Bringing them in line needs a correction per line and is not part of this decision.
- A new drafted tooltip line that keeps a stat word in English letters on its own fails lint, so the rule holds for later batches without a reviewer. A stat word the English uses inside a name (`Elixir of Agility`, `Mana Shield`) is still a name the Japanese must keep. A stat word written next to another English word that is no name (`Strength Increased`) is not caught; the corpus has none left.
- A redraft by script is only right when the rule is a pure word swap. Three spells (the "Mana cost" line of Light's Vigil) gained a `name_missing:Mana` from the name heuristic; they were reviewed and kept, because マナコスト is right.
- A stat word used as a real name without a Latin neighbour (a single-word name) would be swapped. The context read in point 5 is the guard for existing lines; lint does not catch it on new ones.

## Alternatives considered

- **Take the words off the allowlist.** It would enforce the rule through the name check, but hand-written lines that keep the words would then meet the runtime gate on live English that cannot be checked offline, and a failure shows English.
- **Have a model rewrite the affected lines.** The change is one word per occurrence. A rewrite could change other words, costs a drafting round and would record a new model on lines whose wording did not change.
- **気力 for energy.** It is a common rendering, but the interface's `ENERGY` is エネルギー, and using another word would recreate the mismatch this decision removes.
- **Keep English letters in machine lines too, as the hand-written corpus does.** Consistent with the corpus, but not with the interface text on the same screen.
