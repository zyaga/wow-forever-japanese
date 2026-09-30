# ADR-001: ID-keyed data with per-field provenance, status, and source hash

- **Status:** Accepted. The shipped line shape is in [data-model.md](../architecture/data-model.md): `english: {hash, src}` takes the place of `source_hash` below, and the status set also has `pending` (imported, not yet checked) and `unaligned` (ADR-007).
- **Date:** 2026-09-13

## Context
The predecessor addons stored unit and item names as position-indexed arrays with a parallel index table, carried 2,187 duplicate quest IDs that silently overwrote each other, and tracked one translator tag per quest even when only some fields were translated. Those three choices produced the "wrong text for this ID" failures the project exists to fix. Translation data will be revised for years (Forever patches, corrections, machine passes), so each value must carry enough metadata to know whether it can be trusted, replaced, or is out of date.

## Decision
Every translatable value is an **entry field** addressed by `(type, game ID, field)`, for example quest `2` / `description`, item `117` / `description`, spell `17` / `description`, or, for gossip, `(gossip, gossip key)`. Each field carries its own `status` (`trusted` · `stale` · `rejected` · `missing`), `provenance` (`human` with translator name · `machine` with model id + date · `correction` with reviewer), and `source_hash` (hash of the normalized English it was checked against). Duplicates are recorded as `rejected` with the competing candidates, never collapsed by "last one wins". Position, insertion order, and parallel index tables are forbidden ([principle 5](../architecture/principles.md#5-every-translation-is-keyed-by-the-game)).

## Consequences
- Wrong-ID bugs become impossible to introduce through data layout; the alignment check catches wrong-ID data at import.
- Per-field granularity means a quest can ship a trusted description and an English completion text; coverage reports are honest.
- Machine passes can never silently overwrite human work: the provenance class is checked in the pipeline ([principle 6](../architecture/principles.md#6-provenance-on-every-line-people-over-machines)).
- Cost: the JSON is verbose (metadata per field), and the generator must fold it into a compact Lua shape. Accepted; the JSON is the source of truth, the Lua is a build artifact.

## Alternatives considered
- **Per-quest trust + one translator tag** (predecessor): hides partial translations and makes stale detection impossible per field.
- **Position-indexed arrays** (predecessor, for size): the exact failure mode being fixed; size is solved by the generator, not the source format.
- **SQLite as source of truth**: not diffable in PRs, not reviewable on GitHub; git-versioned JSON is the contribution path (ADR-006).
