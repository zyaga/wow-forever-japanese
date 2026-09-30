# ADR-024: Gender variants and short-name candidates: a female key per gendered English, tried after the male one; short player names tried after the literal key

- **Status:** Proposed; accepted once in-game checklist 18 passes. Implemented in `pipeline/wfj/core/normalize.py` (`female_variant`), `cmd/generate.py` (`female_index`, the alias report), `emit/lua_writer.py` (`rows` `h1f×5`, `gender_aliases`), `emit/schema.py` (`SLOTS.quest.female`); `Core/Const.lua` (`female`), `Core/Lookup.lua` (`h1f`), `Core/Translator.lua` (live rule), `Core/Collector.lua` (short-name candidates, `fingerprints` second return, quest known check).
- **Date:** 2026-09-16

## Context
Two cases make a line miss its Japanese although Japanese exists.

- **Gendered English.** The English writes `$G<male>:<female>;` where the client picks a branch by the character's sex. `normalize_v1` resolves the code to its first (male) branch, so every English hash, every gossip / trainer-greeting id and every book `english.hash` is the male text's key. A female character's live English hashes differently. A gossip, book or trainer-greeting row is not found, so the live English shows. A quest field is found by id, but its live check ([ADR-019](019-quest-english-per-field-and-live-check.md)) finds no equal fingerprint and shows a false stale marker. The collector's quest known check (`entry.h1 == h1`) fails too, so the female English is recorded as unknown.
- **Short player names.** `Normalize.replaceWord` skips tokens under `MIN_TOKEN_LEN = 3` code points. For a character called "Ka", `Collector.keys` yields only the nothing-replaced key, so a line that contains `$N` misses. `Collector.fingerprints` gives no fingerprints when a short name is in the text, so the build-time status decides.

Measured on the data at the time: English carrying `$G` is on 188 quest lines (166 distinct female keys), 125 gossip lines and 10 book pages; about 130 shipped quest fields and 124 shipped gossip lines carried it.

## Decision
1. **A female variant, derived at generate time.** `female_variant(en)` returns the English with every `$G<male>:<female>;` (either case of `G`) resolved to its second branch, written literally, or `None` when the English has no gender code. Links, textures and colour codes are stripped first, in `normalize_v1`'s order: a link's `:` would otherwise split the code. The female key is `key(normalize_v1(variant))`. For the keyed types `generate.female_index` maps each English hash in `data/english/<type>` to its female key where that key differs from the male one; a hash whose stored texts give different female keys is left out and reported (`ambiguous female variant <type>:<hash>`). For quests `generate.female_fields` works per (id, field): a literal line sharing a gendered line's hash (quest 8898's progress shares quest 8897's) does not inherit its variant. Nothing is stored in `data/` JSON. A stale line whose old English is no longer in `data/english` gets no variant.
2. **Keyed types get gender alias rows.** For gossip, book and trainer_greeting, `lua_writer.gender_aliases` repeats a row under its English's female key, with the same `{ text, status }`, in the shard of that key's first two hex characters. The conflict rule:
   - a real row under the female key wins and the alias is dropped;
   - several aliases on one key with equal rows collapse into one row;
   - several aliases on one key with different rows are all dropped, so that key shows live English.

   Nothing raises. `generate` prints `generate: gender aliases: N added · M dropped · K ambiguous`, one `dropped alias <type>:<key>` line per dropped key and one `ambiguous female variant <type>:<hash>` line per ambiguous hash. A female miss falls back to English, never to another line's Japanese.
3. **Quest rows gain optional `h1f×5`.** A row where some field's English has a female variant gets five more slots after the status string: the female `h1` per field, `nil` where there is none. Rows without one keep the 11-slot shape. `SLOTS.quest.female = 11` in `schema.py` and `Const.lua` (parity-tested), so field `i`'s `h1f` is at slot `i + 11`. A field checked against another field's English (`english.of`) ships no `h1`, and so no `h1f`.
4. **The addon reads `h1f`.** `Lookup.get` returns `{ ja, status, h1, h1f }` for quest fields. `Translator`'s live rule counts a fingerprint equal to `h1` or `h1f` as a match. The collector's quest known check does the same. The keyed surfaces need no change: the live key finds the alias row.
5. **Short-name candidates, after the existing three.** When the player's name is 1–2 code points, `Collector.keys` appends two candidates: full (name, class, race) and name only, each with the name also replaced by `{name}` as a whole word (exact case, ASCII-letter boundaries). The replace runs on the markup-free normalized text, so a colour code is never hit. The order is full, name only, none, then short full, short name only. A line whose literal English is shipped still wins. `normalize_v1`, `Normalize.replaceWord` and the hash vectors are unchanged.
6. **`fingerprints` reports inconclusive.** `Collector.fingerprints(raw, player)` returns the `h1` of every distinct candidate, short-name ones included, and a second value `inconclusive`: `true` when a 1–2 code-point name occurs in the text as a word, else `nil`. The live rule: an equal fingerprint means no marker; no equal fingerprint while inconclusive returns `nil`, so the build-time status decides. ADR-019's "no false stale marker from a short name" holds.

## Consequences
- Female characters see the same Japanese as male characters on gendered quest, gossip and book lines, and gendered quest fields lose their false stale marker. Characters with very short names match `$N` lines.
- The generated data changes only by the `h1f` suffix on gendered quest rows and the added alias rows; `data/` JSON is unchanged.
- `Data/Meta.lua` counts translated lines, not alias keys. `/wfj debug` "entries" counts keys, aliases included, so the two can differ.
- **Accepted residual:** a short name that is also an ordinary word ("An"). The literal key is tried first. A wrong line can show only when the literal line is unshipped and another line's `$N` form equals the live text at every occurrence of the word.
- **Coverage gap, fails closed:** the short-name candidate replaces every occurrence. A text that uses the name both as the name and as an ordinary word ("An old tome… Greetings, An.") matches no candidate and stays English; a quest field in that case lets the status decide (`inconclusive`).
- The collector's *recording* path still refuses short names (`short_name`). Only its quest known check changed.
- Human quest lines written in one gender's wording already showed to female characters, with a marker. Only the marker is removed; the wording is unchanged.
- **[unverified, checklist 18]:** whether the client trims the spaces inside a spaced branch such as `$g brother : sister;` (VMaNGOS gossip writes some branches this way). In the data, female branches have leading spaces only (collapsed away by whitespace normalization either way), while male branches have trailing spaces (quest 59, gossip 89 lines), so trimming would affect the male key. `/wfj debug gossip` keys for a male character settle it.
- **Rollback:** revert the PR and re-release. No SavedVariables change. `make generate` on the reverted code brings back the 11-slot quest rows and single-key keyed rows.

## Alternatives considered
- **Store female hashes in `data/` JSON via `check`**: the variant is derivable from `data/english`; storing it churns every gendered line's data for no new information.
- **A per-sex Lua lookup, or gender candidates built in the addon**: impossible: the addon sees only the female live English and cannot rebuild the male text from it.
- **Lower `normalize_v1`'s `MIN_TOKEN_LEN`**: changes the Python ↔ Lua contract and its vectors, and the collector's privacy refusal of short names.
- **Raise on alias conflicts, as for book duplicates ([ADR-022](022-book-and-trainer-greeting-surfaces.md))**: a female miss should fall back to English, not break the build.
- **Leave either case a known limit**: the fix is small and additive.

## Related
- [ADR-005: Gossip key fingerprint](005-gossip-key-fingerprint.md) · [ADR-017: Gossip surface](017-gossip-surface.md) · [ADR-019: Quest English per field and live check](019-quest-english-per-field-and-live-check.md) · [ADR-022: Book and trainer-greeting surfaces](022-book-and-trainer-greeting-surfaces.md)
- [Data model](../architecture/data-model.md) · [Addon modules](../architecture/addon-modules.md) · [Pipeline](../systems/pipeline.md) · [Testing](../testing/strategy.md): checklist 18
