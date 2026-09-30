# The Forever client's quest cache layout

> 2026-09-18. `questcache.wdb` from **World of Warcraft: Forever beta 1.60.1.69913**, written on a
> clean Exit Game after an in-game quest scan. 1,929,386 bytes, 1,965 records. **Derived and pinned**: the
> reader carries this layout as `io/wdb.LAYOUTS[69913]`, and all 1,965 records read exactly.

## Why this exists

`io/wdb.py` read the quest cache against the one layout verified on Classic Era 1.15.9.69722. ADR-020
decision 2 says a changed layout on a Forever build **stops the import and never imports misread text**. It
did exactly that, on the first record:

```
questcache.wdb: quest 94222: a list count at 480/484/488 is not zero (layout not seen on 1.15.9.69722)
```

That was the reader working as designed. This note records how the new layout was derived and what it was
checked against, so the next build's bump is a verification and not a re-derivation.

## The framing did not move

Magic `TSQW`, build `69913`, locale `SUne` (enUS reversed), then `[quest id u32][length u32][payload]`
records ended by an 8-byte zero terminator. 1,929,378 of 1,929,386 bytes are consumed by the records, so
record boundaries were correct from the start and only the *payload* moved. Payloads run 506–1,969 bytes
(1.15.9's fixed part alone was 504).

That framing is the reason `read_ids` exists: it walks the records without decoding a payload, so a rescan
list (`io/wdb.read_ids`) can be produced on a build whose payload layout is **not** pinned yet. That
is how a rescan could be planned before the layout was solved.

## The layout

Both builds have the same shape: a fixed part holding the counts, then the variable parts in order, then the
string-length block and the nine strings. What changed is where the counts live, what lists exist, and where
the block sits.

| part | Classic Era 1.15.9.69722 | **Forever 1.60.1.69913** |
|---|---|---|
| objective count | `u32` at `448` | **`u32` at `436`** |
| a list of 12-byte entries, **before** the objectives | none | **count `u32` at `64`** |
| objectives start | `504` | **`488`** |
| objective record | 43 bytes: fixed part, length byte at `+41`, flag at `+42`, then the text | **43 bytes plus 4 per entry of an inner list counted by the `u32` at `+33`;** the length byte and flag follow the entries. With an empty inner list this is 1.15.9's record exactly |
| a list of 4-byte entries, **after** the objectives | none | **count `u32` at `448`** (1.15.9's objective-count slot, reused) |
| conditional-text arrays | none | **counts `u32` at `472` and `476`**; one entry is `[PlayerCondition id u32][quest-giver id u32][12-bit length + 4 bits of zero padding][text]` |
| string-length block | fixed, at `492`, **before** the objectives | **immediately after the variable parts**, wherever they end |
| block bit widths | 9·12·12·9·10·8·10·8·11, MSB first | **unchanged** |
| bits after the nine lengths | must be `0` | **must be `32`** (the same value on all 1,965 records) |
| `u32` that must be zero | `480`, `484`, `488` | **`480`, `484`** (`488` is now the objectives) |

Nine strings, back to back, no NUL, in the same order on both builds: title, objectives (log description),
description, area description, portrait giver text, portrait giver name, portrait turn-in text, portrait
turn-in name, completion log. The reader uses the first four; the rest are not fields in our model.

### How each number was established

Against an oracle of the 1,245 quests whose English title we already hold in `data/english/quest`:

1. **Objective count 448 → 436, objectives 504 → 488.** Title offsets clustered at 500, 543, 586, 629:
   steps of exactly 43, the objective record size, and the count at `436` matched the step count on 1,006
   of the 1,016 records where it could be derived from the title's offset.
2. **The block moved after the objectives.** For the 360 records with no objectives the block sat at 488 and
   its first 9 bits equalled `len(title)` on **360 of 360**.
3. **The 12-byte list at `64`.** The zero-objective records that still failed had their block 12 or 36 bytes
   late. Exactly one `u32` in the whole fixed part predicted that gap as `value × 12`, unanimously over 519
   records: offset `64`. Adding it took the fit from 1,616 to 1,781 of 1,965.
4. **The 4-byte list at `448`.** 154 of the remaining records needed exactly 4 more bytes. Exactly one bit in
   the entire fixed part predicted which (bit 0 of byte `448`), and the `u32` there is 1 on those 154 and 0
   on the other 1,811. Adding it took the fit to 1,935.
5. **The conditional-text arrays at `472` / `476`.** The last positive residuals held readable quest prose,
   with a 10-byte header whose 12-bit length matched the residual exactly (`0x1cb0 >> 4 = 459`, residual
   `469 − 10`). Of the `u32` that are zero on every record that already read, only `472` and `476` were
   non-zero on these, with values 1 and 2: the entry counts. Fit 1,947.
6. **The objective's inner list at `+33`.** The last 18 records had an objective flag byte that was not
   `0x80`, i.e. the walk was reading `+41`/`+42` in the wrong place. Their objective regions decoded as a
   `u32` count at `+33`, four bytes, then `count × 4` bytes, then the length byte and flag. For example,
   quest 93165's single objective carries 12 consecutive ids (`0x867a`–`0x8685`). Fit **1,965 of 1,965**.

### What it was checked against

- **All 1,965 payloads consume exactly.** No record is skipped, truncated or padded.
- **The bits after the nine string lengths are `32` on every record**, so the assertion is "this build's
  value", not a relaxed one.
- **1,233 of the 1,245 titles we already hold reproduce character for character.** The 12 that differ are
  Forever's own edits, not mis-slicing: `WANTED: "Hogger"` for `Wanted:  "Hogger"`, `One Shot. One Kill.`
  for `One Shot.  One Kill.`, `Oh Brother...` for `Oh Brother. . .`, `Your Place in the World` for
  `Your Place In The World`, and two ids reused for other quests (5679/5646 `Devouring Plague` →
  `Dark Sacrifice`, 490 `<UNUSED>` → `Bounty: Gnarlpine Furbolg`).
- **The two layouts do not read each other.** Layout 69722 reads 0 of the 1,965 Forever records, and layout
  69913 reads 0 of the Classic Era fixture's, so picking the wrong one is loud, never plausible-looking
  (a test pins this).
- **Every count field is exercised** by the cache: the 12-byte list at 0/1/2/3 entries, the 4-byte list at
  0/1, the two conditional arrays at 0/1 and 0/2, an objective's inner list at 0/1/2/3/4/12. The committed
  fixture `tests/fixtures/wdb-forever/` carries one record per part.

## What the cache holds on this build

1,899 quests and 66 placeholders, of 1,965 records: 1,899 titles, 1,709 objectives, 1,705 descriptions, 81
area descriptions, 250 objective texts across 189 quests, and 15 conditional-text entries across 14 quests.

## Conditional quest text: read, reported, not imported

Forever serves a **variant of a quest's description per `PlayerCondition`**. Quest 92596 is the clear case: its description has a second variant for mages (condition 137886). Classic Era's
cache has none of these; only 14 quests in this cache use one.

The reader decodes them so the payload is fully accounted for, `WdbQuest.conditional` carries them, and
`import english wdb` prints how many it found and which quests, but **nothing is imported**. Every entry is
addressed by a game ID ([principle 5](../architecture/principles.md)), and a conditional variant is keyed by
`(quest, condition)`: a key that does not exist in the data model and has no display design in the addon
either (the addon would have to evaluate the condition to know which variant the player is being shown).
Supporting it is separate work.

## The cache was incomplete

1,965 quests is not the whole game: Forever's `QuestV2` lists 6,600 ids. The rescan list (`io/wdb.read_ids`) names the
rest, and the import reports quest coverage against `QuestV2`.

## Pinning the next build

`python -m wfj.dev.wdb_layout <cache>` reports, per pinned layout, how many records it reads and the first it
cannot, and names a winner only if exactly one reads **every** record. A layout that reads most of a cache is
a layout we do not understand (a partial fit of 82% is where this derivation started), and the tool refuses it
(exit 1). When a pinned layout wins on a new build, add a `Layout` for that build to `io/wdb.LAYOUTS` with
its evidence; when none does, derive the difference the way this note did.

## Related

- [ADR-020: Quest cache harvest](../adr/020-quest-cache-harvest.md) (the per-build layout)
- [ADR-027: A DB2 column map is verified per build](../adr/027-column-maps-verified-per-build.md), the
  per-build shape this reader follows
- [Pipeline](../systems/pipeline.md)
