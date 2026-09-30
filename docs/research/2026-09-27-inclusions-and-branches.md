# Research: tooltips that include another spell's text, or branch

> Measurement. The Forever tooltip lines (build 1.60.1.70009) that still shipped English after the tooltip-template
> audit, because the slot model could not count their template: what the inclusion and branch mechanism
> ([ADR-043](../adr/043-included-text-icons-and-branch-variants.md)) drafts, and what stays English, with the reason.
> Tooling: `wfj.dev.translate_batch cut` / `translate_lint`, `wfj.dev.apply_review --scope templates`.

- **Date:** 2026-09-27
- **Question:** how many of the 854 lines the audit left can ship once included text is spliced into the draft and
  branch lines ship one Japanese per branch?

## Before drafting (full English, not a cut-short column)

| Shape once inclusions are expanded | Lines |
|---|---|
| countable (inclusion, name or icon spliced in) | 601 |
| a `$?` branch still there (often inside the included spell's text) | 232 |
| an included spell the Forever tables lack | 11 |
| `$@auracaster` / `$@spellaura` (no English to splice) | 2 |

276 lines carry an inline icon (`$@spellicon` → `$I<k>`).

## Outcome

| Outcome | Lines |
|---|---|
| **shipped** (a machine variant, status `unaligned`) | **811** |
| drafted, but `generate` ships the English (guards: a bracket block after a line break, every variant shadowed once the name line counts) | 2 |
| stays English: `missing_included_spell` | 11 |
| stays English: `branches_indistinguishable` (no variant could ever be the only one to pass) | 11 at cut + 4 at lint |
| stays English: `name_only` (nothing to translate) | 7 |
| stays English: `too_many_variants` (> 16) | 4 |
| stays English: `unsupported_code` (`$@auracaster`, `$@spellaura`) | 2 |
| stays English: `uncountable` (spell 459611's aura) | 1 |
| stays English: `placeholder` (spell 457021, English `???`) | 1 |
| **total** | **854** |

The drafted rows cover more lines than the list. A row's English is shared by lines outside it, and those lines take
the same draft (`cut` serves every undrafted line that shares a listed line's English): 831 item / spell lines in all.
257 shipped slots are branch lines (a Lua table of variants).

## Quality

Each part of the batch passed a separate checking pass on a sample (the whole part where it had fewer than 100 rows):

| Sample | Rows | OK |
|---|---|---|
| items, auras and the 45 rewrites | 122 | 121 |
| part 2 | 100 | 97 |
| part 3 | 100 | 97 |
| part 4 | 100 | 99 |
| part 5 | 100 | 99 |

Every failing row was fixed before import. One check was itself wrong (a `$s1 seconds` read as a duration), and the
draft's own `$N1秒` was kept. Two class words the lint read as part of a name (`another Priest's Renew`, `another
Rogue's Deadly Poison`) are written in katakana, as class words in prose are, with a not-names row each.

## The 45 hand-written lines with baked numbers

41 audit corrections and 4 translator lines on these templates kept the rendered numbers (`24秒間でhealthを552回復`).
All 45 were rewritten with `$N` / `$D` as corrections (`apply_review --scope templates`: the 41 superseded corrections
are marked `reject`, the 4 translator lines are kept in `conflicts`). 42 food lines also gained what the translator
left out: "become well fed" and the experience branch. Spell 5176's `$N1-$N2` for one `$s1` is one of them.

## Found while drafting

- An empty branch left two spaces in its variant's English, which the paragraph check read as a break.
- A branch combination that prints nothing is no variant: an empty Japanese would pass the gate on every line.
- A colour code glued to a word (`|CFFFFFFFFRequires`) was read as part of a name.
- The pre-draft check first refused any line with a shadowed variant. A shadowed variant only costs its players the
  Japanese, never correctness, so only a line whose every variant is shadowed is refused.

## Not verified yet

That the client prints `$@spellicon` as a `|T…|t` escape in the line's text is **[likely]**, not sourced
([principle 9](../architecture/principles.md)). A line whose live text has no escape stays English (fail closed). The
in-game check is in the [testing strategy](../testing/strategy.md).
