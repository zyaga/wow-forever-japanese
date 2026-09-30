# ADR-003: Stale translations ship, marked; numeric changes reject

- **Status:** Accepted. The stale mechanism is in `pipeline/wfj/core/status.py`. Stale is sticky: `check` keeps the hash a line was checked against until an audit pass re-verifies it, and a rebuild of `data/` (`make data`, or `make import-english` + `make check`) carries prior hashes across by (id, field) (ADR-012 §4).
- **Date:** 2026-09-13

## Context
Forever patches will edit English text. Most edits are typo fixes and rewording where the existing Japanese is still right; a minority change facts (counts, levels, names). Blanking every changed field until re-checked would drop coverage on each patch; shipping every changed field silently would show wrong facts.

## Decision
A field whose stored `source_hash` no longer matches the current English becomes `stale`. Stale fields **ship** and are rendered with a small **stale marker**; they are first in line for the next audit pass. Exception: if the alignment check finds the numbers in the Japanese no longer all occur in the new English (a count or level changed), the field is `rejected` (reason `numbers_changed`) and falls back to live English immediately.

## Consequences
- Coverage survives cosmetic patches; fact changes of the numeric kind never ship wrong.
- Non-numeric fact changes (a renamed NPC, a moved location) can ship stale until re-audit. This is mitigated by the name check in alignment (a renamed NPC fails the Latin-name check) and by the marker.
- The stale marker is one of the permitted on-screen additions ([principle 3](../architecture/principles.md#3-japanese-by-default-english-one-key-away)).
- **Items and spells.** Item and spell lines become `stale` when their tooltip English changes ([ADR-007 addendum](007-unaligned-ships-with-runtime-gate.md)). They have no offline numbers check, so the `numbers_changed` exception does not apply offline; the in-game align gate still runs on a stale item or spell entry and leaves the English when a number changed.
- **Redrafting a stale line.** The baseline is stored per line, and a machine variant records no English hash, so `check` cannot tell a draft cut from the current English from an older one. `import draft --reverify` (`make import-draft … REVERIFY=1`) is the signal, given at import time, that a draft was written from the current English. It takes UI, quest, objective, item and spell lines and re-stamps the line's baseline with exactly what a fresh `check` would record (`check.current_baseline`: the hash, its source, and, for a field judged against another field, `of`), so the redraft ships trusted instead of stale. Gossip is left out: it is keyed by the English hash, so a rewording is a new key. The flag refuses a line whose hand-written variant is not ruled `reject`.
- **Stale hand-written lines.** A stale hand-written line keeps the stale marker until it is reviewed against its new English. A person's translation is updated only if its Japanese no longer matches the new English, and then with the person's Japanese as the foundation (a `correction` variant, the [ADR-012](012-human-decisions-survive-regeneration.md) shape), never redrafted. Otherwise the Japanese is kept and only the English baseline is re-stamped to `check.current_baseline`. `pipeline/wfj/dev/apply_review.py` applies such a review. A later build's rewording marks hand-written lines stale again, and the same review clears them.

## Alternatives considered
- **Blank stale**: always correct, coverage collapses after each patch until someone re-checks thousands of fields.
- **Ship stale silently**: the predecessor behaviour; players cannot tell what to trust.
