# ADR-028: A duration is copied from the live line, never named by the translation

- **Status:** Accepted. Implemented in `addon/WoWForeverJapanese/Core/Align.lua` (`Align.durations`, `Align.fill`,
  `Align.fillValues`, the `duration` parameter of `Align.check`), `Core/Translator.lua` (`filled`, `liveDiffers`),
  `Core/Collector.lua`, `Main.lua` (the `align` and `fillValues` deps pass `UIIndex:duration`),
  `pipeline/wfj/core/align.py` (`DURATION_CODE`, `DURATION_UNITS`, `slots`, `slot_problems`, `duration_slots`,
  `duration_indices`), `pipeline/wfj/core/normalize.py` (`mask_values`), `pipeline/wfj/cmd/generate.py`
  (`masked_fields`), `pipeline/wfj/dev/translate_lint.py`, `pipeline/wfj/dev/translate_batch.py`,
  `pipeline/wfj/dev/rule_baked_numbers.py` (`--durations`), `docs/content/translation-style-guide.md` (the
  **Tooltips** section), `tests/lua/spec/align_spec.lua`, `tests/python/test_align.py`,
  `tests/python/test_translate_lint.py`.
- **Date:** 2026-09-18

## Context

Item and spell tooltip English is a **template the client fills**: `Restores $o1 health over $d.` is what the
data holds, and the player is shown `Restores 61 health over 18 sec.` A translation has to carry placeholders
rather than values, because the values differ per item, rank, level and talent. `$N<k>` already does this: the
addon replaces it with the k-th number of the line the client is showing (`Align.values` / `Align.fill`,
ADR-010), and a written-out number is refused by `Align.check` the moment the client's value differs. That is
why almost none of the predecessor corpus's item descriptions, which bake their numbers in, still display.

A **duration** does not fit that. `$d` prints through the client's own duration strings
(`INT_SPELL_DURATION_SEC` `%d sec`, `_MIN` `%d min`, `_HOURS` `%d |4hour:hrs;`, `_DAYS` `%d |4day:days;`, plus
the `SPELL_DURATION_*` float forms and `SPELL_DURATION_UNTIL_CANCELLED`), and **which one it picks depends on
the length**. The same template is seconds on one item and minutes on another. `$N<k>` yields the bare number,
so a Japanese line using it has to name a unit itself (`$N2秒`), and that is a guess: correct while the client
prints seconds, silently wrong when it prints minutes.

Worse, **the runtime gate cannot catch it.** `Align.check` refuses a translation whose names or numbers are not
in the live line; `18分` against a line reading `18 sec` passes, because the number matches and `分` is
Japanese text the gate never reads. A wrong unit is not a refused line: it is a displayed mistranslation. Duration
units are therefore never assumed; the system has to get them right every time.

## Decision

1. **A duration is copied out of the live line, with its unit, and never named by the corpus.** A placeholder
   `$D<k>` is replaced with the whole k-th duration **phrase** of the line the client is showing: number and
   unit together, exactly as rendered. `$D1かけてhealthを$N1回復します。` reads `18秒かけて…` on a seconds line
   and `2分かけて…` on a minutes line, from one stored translation.

2. **The rendering is UIStrings', not a second vocabulary.** `Index:duration(value)` (ADR-016) turns a live
   duration into Japanese using the `UIStrings.DURATIONS` GlobalStrings entries the addon ships, understands one
   or two of them (`1 hr 30 min`), and answers `nil` for anything that is not a duration. `Align`'s renderer is
   `Index:duration(text, true)`, limited to the strings a spell's `$d` prints (`UIStrings.SPELL_DURATIONS`:
   `INT_SPELL_DURATION_*`, `SPELL_DURATION_*`, `*_ABBR`); the friends-list `LASTONLINE_*` forms are not a
   spell's. No unit list is hard-coded in the addon, so the client's own wording stays the source of truth,
   including our own translated forms, since `INT_SPELL_DURATION_SEC` is `%d秒` in the shipped UI data and the
   live line may therefore already read `18秒`.

3. **`$D` indexes durations, `$N` indexes every number.** `$D1` is the first duration in the line whatever
   `$N` index its number happens to carry, because "the first duration" is what a drafter can see. `$N`
   counts every number in reading order, the duration's included.

4. **Both fail closed.** `Align.fill` returns nil when any `$N<k>` or `$D<k>` has no value, and
   `Align.durations` returns nothing without a renderer, so a `$D` line on a client whose UI index is missing
   stays English rather than showing a literal `$D1`. A bare `$N` or `$D` with no digits is left alone.
   `Align.durations` begins a candidate only where a number begins and skips a number that is not a duration
   whole, so a `1.5 sec` whose float form is not shipped never comes back as `5 sec`; a trailing `.,;:)。、` is
   trimmed from the phrase. `Align` builds the duration list only when the Japanese carries a `$D`.

5. **Typed slots in the pipeline.** `core.align.slots(en)` returns one `Slot(kind, duration, client_unit)` per
   value the live line will show, in reading order, with `kind` one of `literal` · `code` · `sum` · `counter`.
   A literal is one value even with a decimal or thousands separator (`0.15`, `1,200`), mirroring
   `Align.values`. **A range is one value**: the client prints Fireball's `$s1` as `14 to 22`, so
   `Align.values` joins "A to B" into one value, filled as `14～22`, and `slots` counts a written range
   (`$s1 to $s2`, `20 to 40`) once too. `value_slots`, `duration_slots` and `code_slots` derive from it.
   - `Slot.duration` is set for a `$d` code (`$d`, `$d1`, a cross-spell `$7922d`) **and** for any number the
     English writes in front of a unit word of those strings, `core.align.DURATION_UNITS` (`sec` · `min` ·
     `hour` · `hrs` · `day` · `days` and their capitalised forms; `test_align` holds the two lists together).
     The live line shows `for 30 sec` as a duration phrase, so the Japanese copies it with `$D<k>` rather than
     naming `秒` itself. "Lasts for 30 minutes" is text the English wrote, not a spell duration, and is not
     counted. `client_unit` is set for `$d` only.
   - The count is unknowable (`None`) only for a `$?…` conditional or a `$@…` inclusion. `${…}` arithmetic is
     one `sum` slot, and `$l…;` / `$g…;` / `$z` print a word and are skipped rather than counted. A `$?…[A][B]`
     conditional whose branches read the same apart from their numbers counts as one branch
     (`align._one_branch`): Power Word: Shield's `absorbing $?a14748[${…}][$s1] damage` prints one value either
     way. Branches that differ in anything but their numbers stay `None`: words (Fire Ward's added clause), a
     word code, colour (Tiger's Fury's red "Requires Cat Form" says the requirement is unmet), line breaks, how
     many values they print, or which of those are durations. So does a branch number glued to the text outside
     it. A literal that differs between the branches (`$?a415096[20%][30%]`) is a value the client fills, so it
     needs its placeholder; one both branches write alike stays a literal.

6. **The pipeline is the only gate against a named unit, so it enforces one.** `slot_problems(en, ja)` names
   the slot at fault: `slot_missing:N<k>` (a server code or sum the Japanese does not carry),
   `duration_as_value:N<k>` (a `$N<k>` on a duration, the number without the unit the client chose) and
   `duration_missing:D<j>` (a duration whose `$D<j>` is absent). `translate_lint` reports them, plus
   `duration_index` (a `$D` past the template's durations). Where the count is `None` the rule is not applied
   and the row is verified in game, which is stated rather than guessed at. Batch rows carry the durations as
   `durations`.

7. **Trusted lines are filled with no gate.** `$N<k>` / `$D<k>` are not tooltip-only: quest objectives carry
   server counts (`Collect $1oa Lady's Tear Moss.`) that exist only in the line the player is shown. The client
   engine substitutes them, and none of the client's FrameXML handles `$Noa`, so the data can only hold the
   placeholder. `Align.fillValues(ja, scope, duration)` fills `$N` from `Align.values` and `$D` from
   `Align.durations` over the live text **without** the names-and-numbers check, and the Translator runs it
   (the `fillValues` dep, after the UI `fill`) on every trusted line and every ungated stale line of every
   type. The gate stays where it was: unaligned lines and stale item / spell lines still go through
   `Align.check`. Those lines were checked offline against their English; re-checking them live would refuse a
   good translation over the very count the server fills in. It fails closed as decision 4: a placeholder
   with no value, or no live text, returns `nil` and the line stays English; Japanese with no placeholder is
   returned unchanged.

8. **Masked hashes for filled quest fields.** A quest field whose shipped Japanese carries `$N<k>` / `$D<k>`
   has English holding a count only the live line shows, so its plain `h1` could never match. It ships a
   **masked** `h1` / `h1f`: the key of the normalized English with every number (the server's count code or a
   digit run) replaced by `#` (`normalize.mask_values`, `generate.masked_fields`). The addon masks the live
   line's digit runs the same way (`Collector.fingerprints(raw, player, masked)`), so the quest live check
   (ADR-019) and the Collector's known check still run: the count cannot fail them, a rewording still does. A
   number with separators (`1,000`) is one `#` on both sides. A **stale** line ships its sticky hash instead
   (ADR-003); masked over the new English it would match the reworded live line and drop the marker.

9. **The style guide says it, and the version records it.** A **Tooltips** section replaces **Voice** for the
   tooltip kinds (they are not dialogue; nobody is speaking), including the written-duration rule, so every
   tooltip draft's `provenance.source` records that it was written under the rules that include `$D`. A range
   is written as one `$N<k>`, not `$N1～$N2`.

10. **Hand-written lines that name a unit are set aside.** `rule_baked_numbers --durations` selects
    hand-written lines that name a `$d` unit themselves and records a reject ruling with its own note (duration
    units are never assumed); such lines are redrafted with `$N` / `$D` ([ADR-023](023-server-only-text-drafted-in-measured-batches.md)).
    Its value mode does the same for baked numbers. Templates whose value count is unknowable (`$@spelldesc…`,
    `$?…`) show the English.

11. **Float durations are one decimal on Forever.** Forever prints `SPELL_DURATION_*` as `%.1f`, where Classic
    Era used `%.2f`. The UI Japanese for those keys is `%.1f`, so `Index:duration` renders a Forever float
    duration.

## Consequences

- One stored translation serves every item sharing a template, at any duration. The 37 items whose
  description is `Restores $o1 health over $d.` are one line; the predecessor corpus holds 116, each with its
  own baked numbers.
- The addon's data format gains a placeholder. It is additive: `Align.fill`'s third parameter defaults to
  empty, and `Align.check`'s fourth is optional, so every existing consumer (`Main`'s `align` dep and
  `align_spec`) behaves as before.
- `Align.check` still cannot see a wrong unit. That is accepted, and the reason the lint rule is mandatory
  rather than advisory: the corpus is kept clean at the point of entry.
- A translation that rephrases a duration away (dropping it, or folding two into one) is refused. That is
  deliberate: the alternative is a line whose meaning depends on a unit nobody checked.
- **Two accepted limits of the masked check:** a rewording that changes only a literal number the Japanese bakes
  in is invisible to it, and whether the client ever prints a `$d` as two terms (`2 hrs 30 min`, which
  `Align.values` reads as two numbers) is unverified. Forever's float forms are single-unit.
- **Not addressed here:** `SPELL_DURATION_UNTIL_CANCELLED` ("until canceled") carries no number, so
  `Align.durations` cannot find it by scanning for digits and a `$d` that renders it has no phrase to copy.
  No template in the corpus was seen to need it; if one appears, its row is verified in game and this ADR is
  amended rather than a unit being assumed.

## Alternatives considered

- **Translate the duration GlobalStrings and let the client render Japanese, using `$N<k>` for the number.**
  We already do translate them (`%d秒`), and it does not help: the Japanese line still has to place a unit
  next to `$N<k>`, and the client's choice of unit is still unknown when the line is written.
- **Assume seconds for food and drink.** Units are never assumed, and it is wrong on the first item whose
  duration is a minute, silently, since the gate cannot see it.
- **A `$U<k>` placeholder for the unit alone, beside `$N<k>`.** Two placeholders where one phrase is wanted,
  and Japanese word order would still have to put them together correctly for every unit.
- **Parse the duration in the pipeline and store one line per rendered unit.** Multiplies the corpus by the
  number of units, and the pipeline does not know which unit any given item will use.
- **Re-check filled trusted lines live with the names-and-numbers gate.** Refuses a good translation over the
  very count the server fills in.

## Related

- [ADR-016: Whole-window interface coverage](016-whole-window-interface-coverage.md)
  (`UIStrings.DURATIONS`, `Index:duration`) · [ADR-007: Unaligned ships with a runtime gate](007-unaligned-ships-with-runtime-gate.md)
- [ADR-014: Machine-drafted text and the UI dictionary](014-machine-drafted-text-and-ui-dictionary.md): the `%d` UI templates the same idea serves
- [Translation style guide](../content/translation-style-guide.md) (**Tooltips**) ·
  [Pipeline](../systems/pipeline.md)
