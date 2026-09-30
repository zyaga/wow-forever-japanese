# ADR-043: Included text spliced into the draft, icons copied, branch variants chosen by the live line

- **Status:** Accepted. Implemented in `pipeline/wfj/core/align.py` (`expand_inclusions`,
  `included_spells`, `icon_indices`, `branching`, `ja_variants`, `indistinguishable`, `never_shown`,
  `MAX_INCLUDE_DEPTH` = 4, `MAX_VARIANTS` = 16), `pipeline/wfj/core/english_text.py` (`model_english`, moved from
  `dev/translate_batch`), `pipeline/wfj/cmd/check.py` (`Included`, `current_baseline(…, includes)`),
  `pipeline/wfj/core/status.py` (`decide(…, includes_changed)`), `pipeline/wfj/cmd/generate.py` (`branch_variants`),
  `pipeline/wfj/emit/lua_writer.py` (`variants_literal`), `pipeline/wfj/cmd/validate.py` (rule 4 reads `includes`),
  `pipeline/wfj/dev/translate_batch.py` (`expand_included`, `_annotate_branches`, `<batch>.dropped.jsonl`),
  `pipeline/wfj/dev/translate_lint.py` (`_check_branches`, `_icon_problems`), `pipeline/wfj/dev/apply_review.py`
  (`--scope templates`), `addon/WoWForeverJapanese/Core/Align.lua` (`textures`, `$I` in `fill`, `checkVariants`),
  `Core/Lookup.lua` (table slot → `variants` / `shapes`), `Core/Translator.lua` (`alignVariants`, `T.variants`),
  `Main.lua`, `UI/Slash.lua`; the style guide. Tally: [inclusions and branches](../research/2026-09-27-inclusions-and-branches.md).
- **Date:** 2026-09-27

## Context

About 850 Forever tooltip lines (item description, spell description, aura) shipped English because the slot model could
not count their template (`align.UNCOUNTABLE`, [ADR-028](028-a-duration-is-copied-not-named.md)):

- **746 include another spell's text.** `$@spelldesc<id>` prints that spell's description, `$@spelltooltip<id>` its
  aura text, `$@spellname<id>` its name, and `$@spellicon<id>` its icon. Item 733's description is two inclusions.
  The values of the included text are the included spell's, and the client prints them in place.
- **99 carry a branch** `$?<cond>[A][B]` (chains `$?c1[A]?c2[B][C]`, nesting) that the client resolves at display
  time from a talent (`$?s11094`), an aura (`$?a768`), a faction (`$?pc923`) or the player's level (`$?$PL<24`).
  After inclusions are spliced in, 232 lines carry a branch, many inside the included text.

The addon can only gate a tooltip line against what the client is showing now ([ADR-002](002-live-english-only.md),
[ADR-007](007-unaligned-ships-with-runtime-gate.md)): every name and number of the filled Japanese must occur in the
live line. Neither case fits a single Japanese string numbered over one fixed set of values.

Claims about the client this design rests on ([principle 9](../architecture/principles.md#9-claims-about-the-client-need-a-source)):

- **(a) The client splices the included spell's rendered text into the line.** Source: ADR-007 (item / spell
  Japanese was translated from rendered lines) and the predecessor's item 733 translation, which renders spell
  434's text inline ("24秒間でhealthを552回復…").
- **(b) `$@spellicon` shows as a `|T…|t` texture escape in the line's `GetText()`.** No source yet: **[likely]**.
  The in-game check is in [testing strategy](../testing/strategy.md). If the claim is wrong, `$I<k>` finds no
  escape and the line fails closed to English, never wrong text.
- **(c) A branch line shows one branch.** The addon reads which one from the live line and never claims how the
  client decides.

## Decision

1. **Included text is spliced into the English the drafter reads.** `align.expand_inclusions(en, spell_english)`
   replaces `$@spelldesc<id>` with that spell's `description` English, `$@spelltooltip<id>` with its `aura`,
   `$@spellname<id>` with its `name` (which stays English). It recurses to depth 4. A missing spell, a
   cycle, a deeper chain or any other `$@` code (`$@auracaster`, `$@spellaura`) returns no text with a reason, and
   the line stays English. A template the slot model already counts is not expanded (a name-list tail,
   [ADR-033](033-level-1-gaps-name-list-tails-and-untagged-menus.md), keeps its `$@spellname`). The drafter translates the whole expanded line as one sentence.
2. **Inline icons are copied from the live line.** `$@spellicon<id>` becomes `$I<k>` (k = its order in the line);
   the Japanese carries each `$I<k>` once (`translate_lint`: `icon_missing` / `icon_index`). The addon's
   `Align.textures` takes the `|T…|t` escapes out of the live line before values, durations, names and numbers
   are read (an icon path's digits and Latin words are neither values nor names), and `Align.fill` puts the k-th
   escape back byte for byte. No escape → `$I<k>` unfilled → fail closed.
3. **An inclusion line goes stale when an included spell changes.** `check` records
   `english.includes = {"<spellid>.<field>": <hash>}` for an item / spell line whose English splices spells in
   (a spell the tables lack hashes as `""`); a different set or hash makes the line `stale`
   (`status.decide(includes_changed)`), and `validate` accepts such a stale line although its own hash is current.
4. **A branch line keeps its skeleton in the Japanese.** Same conditions, branch counts and order; `$N<k>` /
   `$D<k>` number the values of the whole template in reading order, every branch included. `align.branching`
   splits the English into variants (cap 16; more → English, `too_many_variants`), and `align.ja_variants`
   renumbers the Japanese per variant, each with its **shape** `"<values>/<durations>"`, the counts
   `Align.values` / `Align.durations` read off a live line showing that variant. A combination that prints nothing (the whole line sits
   in a conditional and its branch is empty) is no variant: the client shows no line, and an empty Japanese would
   pass the gate everywhere. `generate` ships the slot as a Lua
   table `{ "<v1>", …, shape = { … } }`; identical (text, shape) pairs ship once.
5. **The addon chooses a variant by the live line, never by the condition.** `Align.checkVariants` treats a
   variant as a candidate when `Align.check` passes it and (only when the variants' shapes differ) the live line
   has its shape. Exactly one candidate (identical filled texts count once) → it applies, with the stale marker as
   for any gated entry; none or several → English. The Translator reaches it through its `alignVariants`
   dependency; `Lookup.get` returns `variants` / `shapes` and `ja = nil` for such a slot.
6. **Shadowed variants still ship; a line is refused only when every variant is shadowed.** A variant is
   *shadowed* when another variant also passes the gate on its line (`align.indistinguishable`: no shape, name or
   literal number tells them apart). On that line the addon sees two passes and shows English: correct, at the
   cost of that line's Japanese. Dropping the shadowed variant would let the shadowing one pass alone on the wrong
   line, so it stays. When every variant is shadowed (`align.never_shown`) nothing could ever show:
   `translate_lint` rejects the draft, `cut` leaves the row out and `generate` refuses to emit it
   (`branches_indistinguishable`). Tiger's Fury's colour-only "Requires Cat Form" pair is shadowed, but a variant
   still shows.

## Consequences

- An inclusion line's values are counted naturally: the live line already carries the included text in reading
  order, so `$N` / `$D` work as on any tooltip line. No second lookup at runtime, no cross-entry dependency in the
  addon, and the Japanese reads as one sentence rather than a joined fragment.
- The included text is translated once per including line, not once per spell: more drafting, and two lines
  including one spell may word it differently. Staleness follows the included spell through `english.includes`.
- The data format grows: an item / spell slot may be a table. The change is additive; every `Lookup.get` consumer
  (Main via the Translator, Slash debug, Tooltip status checks) handles `variants`, and reverting the PR re-emits
  without table slots.
- A branch line whose variants cannot be told apart on some line shows English there; the refusal is only for
  lines where no variant could ever show.
- Claim (b) is unverified. Until the in-game check passes, a line with `$I<k>` may show English everywhere; it can
  never show wrong text.
- Hand-written lines on these templates that kept baked numbers are rewritten with placeholders as `correction`
  variants (`apply_review --scope templates`): superseded corrections are ruled `reject`; the translator lines stay in
  `conflicts` unruled, outranked by the correction that names them in `corrects` (the
  [ADR-012](012-human-decisions-survive-regeneration.md) shape).
- A name-list tail's `$@spellname` chain is copied from the live line, so it records no `includes`: only
  the head's inclusions make a line stale.

## Alternatives considered

- **A runtime `$I<spellid>` marker that reuses the included spell's own Japanese**: the addon would look up the
  other entry and paste its Japanese in. Rejected: the including line's `$N` numbering would have to skip the
  included values and the included entry's numbering would have to be re-based into the outer line; the addon would
  depend on a second entry being shipped and current; the joined Japanese would not read as one sentence.
- **Evaluate the branch condition in the addon** (talent, aura, faction, level). Rejected: it claims client
  behaviour the addon cannot source, needs an expression engine nothing else would use, and a wrong evaluation shows
  wrong text. Reading the live line fails closed instead.
- **Ship one flattened Japanese per branch line** (the "most common" branch). Rejected: wrong text whenever the
  client prints the other branch.
- **Drop shadowed variants.** Rejected: the shadowing variant would then pass alone on the shadowed variant's
  line and show the wrong branch.
