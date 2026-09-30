# ADR-039: Word meanings: written by the model in context, shown in a word card

- **Status:** Accepted. Implemented in `pipeline/wfj/core/readings.py` (the 5-item entry, `meaning_problems`),
  `pipeline/wfj/core/glosses.py`, `pipeline/wfj/cmd/glosses.py` (`wfj glosses check`), `pipeline/wfj/cmd/generate.py`,
  `pipeline/wfj/cmd/validate.py`, `pipeline/wfj/emit/lua_writer.py` (`gloss_text`), `pipeline/wfj/emit/schema.py`
  (`gloss_relpath`, `TOC_ORDER`), `addon/WoWForeverJapanese/Core/Glosses.lua`, `Core/Readings.lua`,
  `UI/ReadingPopup.lua`, `UI/Readings.lua`, `Core/Settings.lua` (`readings.glosses`), `UI/Options.lua`, `UI/Slash.lua`.
  The word card is one of the allowed on-screen additions
  ([principle 3](../architecture/principles.md#3-japanese-by-default-english-one-key-away)); it is widened to window
  labels by [ADR-041](041-word-cards-on-window-labels.md). The in-game checks are the word card checklist in
  [Testing strategy](../testing/strategy.md).
- **Date:** 2026-09-25

## Context

The word-reading box ([ADR-036](036-readings-hover-word-lists.md)) shows a word's reading on hover. A learner also
wants to know what the word means, and for an inflected word (減らしてやって欲しい), what the whole form means and which
verb it comes from.

A first build took meanings from JMdict (EDRDG, CC BY-SA 4.0) through a rule-based deinflector. Measured on the
readings corpus, 90.6% of distinct words matched after deinflection (98.3% of uses), and 94 of 100 random matches were
right. The failures are structural, not tuning:

- A dictionary lists senses; it does not know which one the sentence uses (3 of 100 wrong sense: 半人前, 考えられなく,
  向いてる).
- Deinflection picks the wrong entry when a noun shares the verb stem's spelling (3 of 100: 隠し, 育て, 崩し).
- Kana words cannot be told apart by spelling: いる is 居る "to be" or 要る "to be needed"; しまった is an interjection
  or a form of しまう.
- Game compounds (大族長, 職業用, 見張り塔) and classical forms are missing.
- Shipping a JMdict subset needs an About-screen credit and CC BY-SA for that subset.

The model already writes every line's readings with the sentence in front of it (ADR-036 decision 6).

## Decision

1. **A reading entry may carry a meaning.** An entry is `[word, reading]` or
   `[word, reading, dictionary form, its reading, meaning]`. The meaning is written by the model with the sentence in
   front of it: the meaning the sentence uses, of the **whole** inflected word (食べている → 食べる, "is eating";
   減らしてやって欲しい → 減らす, "I want you to reduce (them) for me"). The line's English sits beside it in the batch row
   (`en`, batch input only), so a meaning uses the game's word where the Japanese word translates it, never bent to
   fit.
2. **One word = the whole inflected unit** when it carries a meaning: a verb or adjective with all its endings and
   helper verbs, noun + する, a noun with a plural or honorific suffix, a fixed expression. A noun and its particle
   are never one word. The dictionary form keeps the text's spelling (いる, not 居る).
3. **Kana words** are allowed only as 5-item entries whose reading is the word itself, listed for the card only.
   A 3- or 4-item entry is refused; so are an empty, untrimmed or over-60-character meaning, a meaning holding `|`,
   tab or newline, a dictionary form holding ASCII and a non-kana dictionary-form reading. The batch rules are in the
   [translation batches runbook](../operations/translation-batches.md).
4. **Each meaning is stored once.** `generate` numbers every distinct `(dictionary form, its reading, meaning)` of the
   current readings from 1 in sorted order into `Data/Gloss/Gloss_<NNNN>.lua` (1,000 per file, loaded after the
   readings); a reading row packs a word that carries one as `word=reading=n`. A stale reading's meanings are not
   emitted. `validate` prints how many words carry a meaning.
5. **JMdict is a local cross-check only.** `wfj glosses check --jmdict FILE` lists the dictionary forms JMdict does
   not know, most used first. No JMdict data is committed or shipped (a test enforces it).
6. **The word card.** `Core/Glosses.lua` is the pure read path; `UI/ReadingPopup.lua` draws the card: the word, its
   reading unless it is kana (shown once), `← dictionary form（reading）` only when it differs, then the meaning,
   280 px wide, clamped to the screen. `UI/Readings.lua` picks the card for a word with a meaning and the reading-only
   box otherwise, at the same anchor.
7. **Class and race words** the addon fills in for `{class}` / `{race}`, and the same katakana words in prose, get a
   card with the English name (`Core/Readings.withTokenWords`, spellings from `Core/Placeholders`) when the word
   stands alone (not inside a longer katakana word such as コントロール or オークション) and no listed word covers
   that spot. 人間 is left out (in prose it means "person"). Names stay English
   ([principle 2](../architecture/principles.md#2-names-stay-in-english)).
8. **One setting**, `readings.glosses`, default on: "Show word meanings in the reading box", a checkbox in the main
   page's translation section, under the readings checkbox. `/wfj glosses on|off`; `/wfj glosses` prints the state and
   the count. Off → the reading-only box, and kana words stop being hover targets. `readings.enabled` off hides both.
   `/wfj debug` has a glosses line.
9. **What the card may show.** The word-reading box is widened to the word card: the word's dictionary form and a
   short English meaning of the word as the sentence uses it; nothing drawn until the mouse is on a word, never while
   English shows, one setting for the box and one for the meanings. "No stored English" means the game's English
   text: the meanings are model-written word meanings, which may use the game's own word for a word where it matches,
   but never a whole English line or sentence of the game's text
   ([principle 4](../architecture/principles.md#4-the-addon-never-ships-stored-english)).

## Consequences

- The meaning is the sense the sentence uses, for inflected forms, compounds and kana words alike. The pilot's
  independent check found 97 of 100 words right, 0 wrong boundaries, readings or dictionary forms, 3 wrong meanings
  (corrected).
- Meanings are part of the readings: a translation change makes them stale together, and they are rewritten together.
  **Every quest, gossip, UI and book translation batch writes meanings** in its readings step (5-item entries).
- **Size is an open cost.** Rows with meanings are several times the reading-only rows for the same lines (kana words
  are listed too, and each carries a meaning); the estimate for the whole corpus is +10–15 MB in game. Reductions (no
  repeated reading for kana words, shorter pointers, loading meanings on demand) wait for a memory review once every
  surface is translated.
- Meaning numbers are regenerated from the whole set, so any added meaning renumbers `Data/Gloss/`: two branches that
  both add readings conflict there and resolve by regenerating ([Translation batches](../operations/translation-batches.md#resolving-a-readings-merge-conflict)).
- Nothing licensed ships; no About-screen credit is needed.

## Alternatives considered

- **JMdict + a rule-based deinflector**: built and measured: 90.6% coverage, 94/100 right, but wrong senses and wrong
  entries a dictionary cannot avoid without the sentence, kana words unresolvable, game compounds missing, and CC BY-SA
  obligations on the shipped subset.
- **JMdict + the model picking the sense**: keeps dictionary wording, but still misses compounds, still needs the
  sentence for kana words, keeps the licence obligations, and costs model time anyway; writing the meaning directly is
  simpler and covers everything.
- **A separate meanings data type** keyed apart from the readings: the meaning depends on the same word boundary and
  the same Japanese as the reading, so it would go stale in step with it anyway; one entry keeps them together.
