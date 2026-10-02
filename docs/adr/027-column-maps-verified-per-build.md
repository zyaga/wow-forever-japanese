# ADR-027: A DB2 column map is verified per build, against a second client

- **Status:** Accepted
- **Date:** 2026-09-18
- **Implemented in:** `pipeline/wfj/io/client_tables.py` (`Layout`, `Table.layouts`, `for_layout`,
  `Table.optional`, `TableAbsent`), `pipeline/wfj/dev/verify_columns.py`; evidence in
  [Verifying the Forever client's DB2 column maps](../research/2026-09-18-forever-db2-columns.md)

## Context

`io/client_tables.py` is the only place that knows which DB2 field is which column. A DB2 file carries field
widths and offsets but **no field names**, so the mapping is external knowledge, and a wrong mapping does not
crash: it silently yields the wrong strings. Reading `Description_lang` from the field that actually holds the
flavour text produces English that *looks* fine, imports cleanly, passes the translation lint, gets drafted,
and ships. Nothing downstream can catch it, because every downstream check asks "is this good Japanese for this
English", not "is this the right English".

[ADR-021](021-client-tables-from-the-local-archive.md) handles this by pinning each table to the layout hash and
field count it was verified on, and refusing any build whose layout moved. That mechanism worked exactly as
intended: Forever's 1.60.1.69913 moved four tables and `client_tables` stopped on all four rather than guess.

That left the question of how to re-verify. The first verification compared every written column against
wago.tools' export of the same build, but wago is **not** a data source for this project, only a cross-check.
And the pipeline reads **two live clients**, so a table needs a map per build, not one global map.

## Decision

**A column map is verified against a second installed client, and pinned per build with its evidence.**

1. **The oracle is another client, not wago.** `dev/verify_columns.py` reads the same table from two installs
   through `io/casc.py` and reports, per written text column, how often the same field holds the same string for
   ids present in both. A client whose map is already verified is a *better* oracle than an external export: it
   is the same field of the same table read by the same code, so a disagreement is about the client rather than
   about two toolchains.

2. **Two independent constraints, both reported.** For a sparse table, which string-field sets the reader
   accepts at all. Where exactly one parses, the string layout is fixed *before* any content is compared, and
   no content evidence can override it. Then cross-build agreement per column.

3. **Three outcomes, not two.** High agreement means the column did not move. Low agreement *with a better
   field* means it moved, and the report names that field. Low agreement with *no* better field means the
   column is in place and the build changed the data: a finding about content, not about the map. Collapsing
   the third case into "moved" sends the next reader hunting a column that never went anywhere.

4. **Absence of evidence is never a verdict.** Two clients sharing no ids for a table exits non-zero rather
   than reporting 0%.

5. **A table carries one `Layout` per build it has been verified on**, each holding the layout hash, the field
   count, **the citation that verified it**, and only the parts of the column map that *differ*. Leaving
   `columns` unset is the positive assertion that nothing moved, and a test enforces that it is not restated
   redundantly. An unverified layout is still refused, now naming every layout that has been verified.

6. **A table only some builds ship is `optional`**, and its absence from the client's root is reported rather
   than failing the run, but **only** absence. A table that is present and will not read still fails, because
   otherwise an encrypted or truncated table would quietly read as "this build doesn't have it".

7. **Where there is no second client, verify end to end instead.** `ItemXItemEffect` exists only on Forever, so
   it was proved by resolving a known item through the whole join to a known English string, which is stronger
   evidence than a percentage.

## Exception: id-only tables pinned in a dev tool

`pipeline/wfj/dev/level1_spells.py` (`make level1-spells`) pins its own column maps for `SkillLineAbility` and
`SkillLine` instead of adding a `Layout` to `io/client_tables.py`. The reason is that **nothing is imported
from these tables**: the tool reads them only for spell ids and skill categories and writes a committed artifact
(`pipeline/level1_spells.txt`). They carry no translatable text, so they need no CSV, source stamp, hotfix decode
or provenance, and routing them through `client_tables` would add all of that for no data. The rule of this ADR
still binds them: each map is keyed by layout hash, carries its evidence (`SkillLineAbility`: Forever prepended
two fields, 16 → 18, verified by cross-build agreement over the 6,047 ids both clients hold), and an unverified
layout is refused. A table that later gains an import moves its map into `client_tables` with it.

The visible-spell scope tool (`dev/visible_spells.py`, which pinned `SkillLineAbility` and `TraitDefinition` the
same way) was removed by [ADR-051](051-coverage-by-served-data.md): coverage now counts every spell the client
serves. The served-text inventory that replaced it (`dev/served_columns.py`) finds text columns from the bytes and
needs no map; on 1.60.1.70170 it matches the pinned maps of all 31 tables the pipeline reads, which is a second,
independent check on those pins.

## Consequences

- Re-verifying a layout bump is one command whose output is committed as the evidence, rather than an
  investigation someone has to repeat. The next build is cheap.
- The pin now carries *why* it is trusted, so a reviewer can re-derive it instead of taking it on faith.
- Two clients are supported at once without branching on build number anywhere outside `for_layout`.
- **The oracle is only as good as its own verification.** Classic Era's map was verified against wago's export
  of the same build; this ADR inherits that. If that was wrong, this inherits the error, which is why the
  string-set constraint matters: it is independent of the oracle entirely.
- **Agreement percentages say nothing about ids only the new build has.** Those are a larger population and
  belong to the import's delta report.
- A column that moved *and* whose content changed on the same build would show a low rate with an ambiguous
  best field. That has not happened yet; if it does, the tool reports the ambiguity rather than picking.

## Alternatives considered

- **Compare against wago.tools' export of the new build**: wago is not a data source for this project; the
  second client is available, local, and a closer comparison anyway. Wago remains usable as a cross-check.
- **Bump the layout hash and field count, and trust that no column moved.** The fastest path and the reason
  this ADR exists. `QuestV2` did move a column on this very build, so the assumption would have been wrong on
  the first build it was applied to.
- **Infer names from the community DBD definitions (WoWDBDefs).** A real option, and it is where the field
  *names* ultimately come from. Rejected as the verification: it is a third-party file keyed by layout hash
  that would have to be fetched and trusted, and it tells us what the field is *called*, not that our reader
  reads that field correctly on this build. It stays available as a hint when a column genuinely moves.
- **Detect string fields by sniffing for printable bytes.** Fragile in both directions (numeric fields can
  look like text and short strings can look numeric), and unnecessary: the record-size constraint already
  decides it, exactly, for the tables that matter.
- **One global map, with the newest build winning.** Breaks the other live client, which is not hypothetical:
  adding a Forever-only table broke the Classic Era pull before `optional` existed.

## Related

- [ADR-021: Client tables from the local archive](021-client-tables-from-the-local-archive.md)
- [ADR-026: A blank archive-entry header is unwritten](026-blank-archive-header-is-unwritten.md): without it
  none of these tables could be read on Forever at all
- [Verifying the Forever client's DB2 column maps](../research/2026-09-18-forever-db2-columns.md): the evidence
