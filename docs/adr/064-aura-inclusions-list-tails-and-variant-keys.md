# ADR-064: Aura inclusions, expand branches, wider name-list tails and variant keys

- **Status:** Accepted. Amends [ADR-043](043-included-text-icons-and-branch-variants.md) (inclusions and branch
  variants) and [ADR-033](033-level-1-gaps-name-list-tails-and-untagged-menus.md) (name-list tails). Implemented in
  `pipeline/wfj/core/align.py` (`INCLUSION`, `_INCLUDED_FIELD`, `NULL`, `_EXPANDKEY`, `parse_branches`,
  `NAME_LIST_TAIL`, `split_tail`, `tail_problems`, `indistinguishable`, `variant_key`, `variant_keys`),
  `pipeline/wfj/cmd/generate.py` (`_branch_refusal`), `pipeline/wfj/emit/lua_writer.py` (`variants_literal`),
  `pipeline/wfj/dev/translate_batch.py`, `pipeline/wfj/dev/translate_lint.py`, `pipeline/wfj/dev/coverage.py`
  (`template_reason`), `addon/WoWForeverJapanese/Core/Align.lua` (`splitTail`, `variantKey`, `checkVariants`);
  `vectors/align_vectors.jsonl` (`variantKey` rows). Tally: [inclusions and
  branches](../research/2026-09-27-inclusions-and-branches.md).
- **Date:** 2026-10-12
- **Related:** [Pipeline](../systems/pipeline.md) · [Translation batches](../operations/translation-batches.md) ·
  [Testing strategy](../testing/strategy.md) (the in-game checks)

## Context

After ADR-043 and ADR-033, 227 item and spell tooltip lines on Forever 1.60.1.70338 still shipped English because
`translate_batch cut` could not place their template. By reason:

| Reason | Lines | What the templates are |
|---|---|---|
| `unsupported_code:$@spellaura` | 94 | `$@spellaura<id>` (88 whole-line, 4 inside text), and 2 bare `$@spellaura` |
| `unsupported_code:$@spelldesc` | 35 | `$@spelldesc<1243081>`: the id written in angle brackets |
| `missing_included_spell` | 34 | the included spell has no row in the Forever tables |
| `branches_indistinguishable` | 20 | branches that differ only in words (the Druid feral talents 16902-16906, 17079, 364106) |
| `unsupported_code:$@expandkey` | 17 | weapon-skill tooltips: `…$@expandkey[<three more level rows>]` |
| `too_many_variants` | 11 | the Riding skills, the Paladin and Hunter ability lists (icon and name chains), the level-bracket lute, prose-paragraph lists |
| `uncountable` | 8 | the seven Shaman totem lists (a line break between the condition and `[`), 459611's aura |
| `unclosed_branch` | 3 | 436516 (a blank line between a branch and its else) and its two includers |
| `unsupported_code:$@null` | 3 | 348779 (`$@null` twice), included by the Chronoboon and Hardcore auras |
| `unsupported_code:$@auracaster` | 2 | "Controlled by $@auracaster." |

Every case had to keep the two rules that make tooltip lines safe: the addon shows a line only when every name and
number of the filled Japanese is on the live line ([ADR-007](007-unaligned-ships-with-runtime-gate.md)), and no
stored English ships ([principle 1](../architecture/principles.md)).

### Claims about the client

None of these is sourced ([principle 9](../architecture/principles.md#9-claims-about-the-client-need-a-source)).
Each fails closed: if a claim is wrong the line shows English, never wrong text. The in-game check for each is in
[Testing strategy](../testing/strategy.md).

- **(a) `$@spellaura<id>` prints spell `<id>`'s aura text.** **[likely]**: in all 88 whole-line cases the same spell's
  description field reads `$@spelldesc<id>` and its aura field `$@spellaura<id>`. If it printed the description
  instead, both texts share names and numbers and the gate could pass the wrong one, so this is the one claim the
  in-game check must settle.
- **(b) An id in angle brackets (`$@spelldesc<1243081>`) is the same id as the bare form.** **[likely]**, the same
  parallel structure.
- **(c) `$@expandkey[A]` prints A when the tooltip is expanded, else nothing.** **[unverified]**. The addon picks a
  variant by the live line's shape, so any other output (a hint line, raw text) matches neither shape and the line
  stays English.
- **(d) A `]`, whitespace, then `[` is the else of the same conditional.** **[unverified]**. A literal bracket in the
  output would change the value count, so neither shape matches and the line stays English.
- **(e) `$@null` prints nothing.** **[likely]**: spell 348779 is nothing but `$@null` twice and exists only to be
  included. Only its own line depends on the claim, and that line ships nothing.
- **(f) A name list follows the head after the head's own line breaks.** The list is copied byte for byte, so its
  content needs no claim; a head whose break count differs fails the head check and the line stays English.

## Decision

1. **Every inclusion code takes its id bare or in angle brackets**, and `$@spellaura<id>` splices spell `<id>`'s
   `aura` English, like `$@spelltooltip<id>`. `included_spells` lists the pair, so `english.includes` staleness
   follows it. A bare `$@spellaura` (no id) and `$@auracaster` (the caster's name, which only the game knows) stay
   unsupported.
2. **`$@null` splices nothing.** A template left with no text (348779's own line) has nothing to translate, and
   `coverage` counts it so, not as a gap.
3. **`$@expandkey[A]` is read as the conditional `$?expandkey[A][]`.** The weapon-skill tooltips ship two variants,
   the short table and the expanded one, and the addon picks by the live line's shape as for any branch line.
4. **Whitespace is allowed inside a conditional's punctuation.** `parse_branches` accepts whitespace between a
   condition and its `[` (the Shaman totem lists put a line break there) and whitespace alone between a branch's
   `]` and the else's `[` (436516 puts a blank line there), in English and Japanese alike. A `[` after other text
   is still a stray bracket.
5. **The name-list tail is widened.** `NAME_LIST_TAIL` matches a trailing run of conditionals, each with any
   condition and an empty else, whose branches hold only spell icons, spell names, whitespace and colour codes:
   Languages and Armor Proficiency as before, now also the Riding skills, the seven Shaman totem lists and the
   Paladin and Hunter "you currently have access to" lists. The head may span several lines; it must not be empty
   and must hold no conditional of its own. The Japanese translates the head, keeps the English head's line breaks
   and ends in `$T`; `tail_problems` adds `tail_breaks` for a head whose break count differs. The addon's
   `Align.splitTail` counts the Japanese head's breaks (n) and cuts the live text at its (n+1)-th break: the head is
   checked and filled against the text before it, the lines after it are copied byte for byte. A live text with
   fewer breaks than the head fails closed; with no (n+1)-th break the tail is empty. A one-line head (n = 0) cuts
   at the first break, exactly as before.
6. **Variant keys for wordings the gate cannot tell apart.** A branch line whose variants are all shadowed
   (`never_shown`) is still refused unless every variant has a distinct **variant key**: `align.variant_key(en)` is
   `hash_key(normalize_v1(…))` of the variant's English with icons removed and every value, sum, range and duration
   (with its unit word) masked as `#`. `generate` ships the slot as `{ "<v1>", …, shape = { … }, key = { "<k1>", … } }`.
   The addon's `Align.variantKey(live, duration)` masks the live line the same way (textures out, duration phrases,
   value tokens, then `Normalize.v1` and `Hash.key`), and `checkVariants` takes only the variant whose key the live
   line has, on top of the shape and `check` rules. A variant holding a word code (`$l…;`, `$g…;`, `$z`) has no
   key, because the live line prints a word the template does not name, and the line stays refused. Keys are
   hashes: no English ships. A slot without `key` is read exactly as before.
7. **Two variants that mask alike are one.** The pre-draft check (`indistinguishable` with `english=True`) reads two
   variants whose masked English and shape are equal as the same wording (1218700's `[$1218701s1%][$1218701s2%]`
   prints one value code or another in the same sentence), so one Japanese is right for both.
8. **The lines that stay English get a plain reason, one row per reason class** in `coverage.md`
   (`coverage.template_reason`): a line that includes a spell the Forever tables do not hold, `$@auracaster`, a bare
   `$@spellaura`, too many optional parts for one translation (the level-bracket lute 279976 / 1307234 and the
   optional-paragraph lists of other spells' prose: mana gems, forms, curses, banes, the Chronoboon, Hardcore and
   Season of Mastery auras), and 459611's aura, whose value count cannot be read from its template.

## Consequences

- About 180 of the 227 lines become draftable and ship Japanese: boss and raid debuffs built from another spell's
  aura, the weapon-skill tables, the Riding and class ability lists (the names in the list stay the client's
  English), and the talents with two wordings. About 50 stay English, each counted under its reason in
  `coverage.md`.
- Nothing that shipped before changes: old slots carry no `key`, old tails have a one-line head, and generate
  output for every previously shipped slot is byte-identical.
- The data format grows additively: a branch slot may carry a `key` table beside `shape`. Reverting the PR re-emits
  without it.
- Two addon rules that choose what to show change (the tail cut point, the keyed variant choice); both fail closed
  to English. Rollback is reverting the PR and re-releasing (no saved-variables change).
- Claims (a) to (d) are unverified until their in-game checks pass. A wrong claim shows English, except (a), where
  the gate could pass the description's text in place of the aura's; that check comes first.
- Python `variant_key` and Lua `Align.variantKey` must mask alike; the align parity vectors (`variantKey` rows) pin
  the contract. A live line the Lua reader masks differently (spacing, a number it skips) shows English.
- `$T` rows gain a rule for translators: the Japanese head keeps the English head's line breaks.

## Alternatives considered

- **Evaluate `$@expandkey` or the list conditions in the addon.** Rejected, as in ADR-043: the addon never evaluates
  a condition; the live line decides.
- **Ship the variant's English, or its opening words, to pick a wording.** Rejected: no stored English ships. A
  hash of the masked wording picks the variant without carrying the text, the same rule as a sectioned line's
  opening-word keys.
- **Keys on every branch line.** Rejected: partly shadowed lines already show a variant where they can; keys only
  where a line would otherwise be refused.
- **A per-row `tail` flag or a shipped break count.** Rejected: the Japanese head's own breaks carry the count, so no
  row shape changes and old data renders unchanged.
- **One section per known spell for the optional-paragraph lists.** Deferred: a different shape from the variant
  model, sized as its own work.
