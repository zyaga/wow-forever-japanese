# ADR-060: Word meanings keep their numbers

- **Status:** Accepted
- **Date:** 2026-10-04
- **Related:** [ADR-036](036-readings-hover-word-lists.md) (readings) · [ADR-039](039-word-meanings-written-in-context.md) (word meanings) · [Readings](../systems/readings.md) · [Pipeline](../systems/pipeline.md) · [Translation batches](../operations/translation-batches.md#readings-for-a-batch)

## Context

The word card's meanings ship once each in `Data/Gloss/`, and every reading row points at a meaning by its number. `generate` numbered the distinct meanings from 1 in sorted order. One new meaning that sorts early moved the number of every meaning after it, so a batch that added a handful of meanings rewrote nearly every Reading and Gloss file (one pull request changed 567 Reading and 138 Gloss files for a small batch). Reviews drowned in diffs that changed nothing a player sees, and two batches in flight conflicted everywhere.

## Decision

1. **A committed numbers file.** `data/reading/meaning-numbers.tsv` records the number of every meaning ever numbered: `n<TAB>dictionary form<TAB>its reading<TAB>meaning`, one line per meaning, sorted by number. It is generated (marked `linguist-generated`) and never edited by hand.
2. **A meaning keeps its number.** A new meaning takes the next number after the highest in the file; several new ones are numbered in sorted order, so a run is deterministic.
3. **Numbers are never reused.** A meaning no current reading uses keeps its line and ships nowhere, which leaves a gap in `Data/Gloss/`. A meaning that comes back gets its old number.
4. **`wfj generate` writes the file**, and only when it numbered something new (`generate: N meanings numbered for the first time`). A malformed line, a number given twice or a meaning listed twice stops it with an error naming the file.
5. **`wfj validate` only reads it.** Rule 5 (regenerate-and-diff) fails when the file on disk is not the one `generate` would write: missing, some shipped meanings with no number, or any other difference. The fix is always `make generate`.

## Rationale

- The mapping has to live outside the generated files, which are build output. A file beside the readings it indexes is plain text, reviewable and versioned with the batch that changed it.
- Append-only numbering keeps a batch's diff local: new meanings land in the last Gloss file, only the Reading rows that use them change, and `Data/Meta.lua` updates its meaning count.
- Never reusing a number means an old Reading row can never point at a different meaning by accident.

## Consequences

### Positive
- A pull request changes only the generated files that gained or lost something.
- Two batches in flight conflict only at the end of the numbers file and in the last Gloss file. The fix: take the main branch's numbers file, then run `make generate` again; this branch's new meanings are numbered after main's.

### Negative
- One more committed file, about the size of `Data/Gloss/` (one line per meaning).
- Retired meanings leave gaps, and the file only grows.

### Neutral
- The shipped Lua formats, `Core/Glosses.lua` and the reading entry shape do not change. Gaps in the gloss table are harmless: it is read by number only. `Meta.counts.gloss` stays the number of meanings shipped.
- The numbers file is an index, not a translation: provenance stays on the reading records.

### Rollout
- The first `generate` with no numbers file numbers the meanings exactly as before (sorted, from 1) and writes the file, so that run changes no shipped file. On the current data it wrote the file and left all 1,701 generated files unchanged.

## Alternatives considered

- **Read the old numbers back from the generated Gloss files.** Uses build output as input; a fresh or cleaned checkout would renumber.
- **Number by a hash of the meaning.** Stable without a file, but sparse 32-bit keys put the whole table in Lua's hash part and break the 1,000-per-file shards.
- **Store the number inside each reading entry.** Changes the 5-item entry every batch writes; far more churn than this removes.
