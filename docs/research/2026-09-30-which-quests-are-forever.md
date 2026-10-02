# Which quests are Forever's: what the server's answers prove

> 2026-09-30. World of Warcraft: Forever beta **1.60.1.70124**, its quest cache after a full in-game scan
> (2,262 quests with text, 75 stubs), its own `QuestV2`, `QuestSort` and `AreaTable` tables, and Classic Era
> 1.15.9.70003's `QuestV2` for comparison. Read-only; nothing here changed the pipeline.

## Why this exists

The quest scan asks the Forever server for quest text by id and the client caches every answer. The
question was whether that text could belong to quests Forever does not use: leftovers from Classic Era,
Season of Discovery, or retail expansions. If it could, the addon would ship Japanese for quests no player
meets, and, worse, could not be trusted to have found the quests players do meet. This note records what
the server's answers prove, so the next re-pull does not have to work it out again.

## Findings

### 1. The server answers only quests it has

Forever's `QuestV2` lists 6,605 quest ids. The full scan asked for all of them. The server answered
2,184 with text or a stub and gave **no answer at all** for 4,421. A quest with no answer never reaches the
cache. Grouped by where the id also appears:

| ids | asked | text | stub | no answer |
|---|---|---|---|---|
| vanilla (below 10,000) | 3,756 | 1,358 | 40 | 2,358 |
| Classic Era / Season of Discovery additions (10,000 to 79,999) | 263 | 50 | 6 | 207 |
| in both Forever's and Era's `QuestV2` (80,000 and up; the Season of Discovery era) | 789 | 15 | 0 | 774 |
| only in Forever's `QuestV2` (80,000 and up) | 1,797 | 715 | 0 | 1,082 |

The 15 Season-of-Discovery-era ids the server does answer are all "Special" sort, level 45 or 60 book quests
("Legends of the Tidesages", "Necromancy 101"). Every one of them is in Forever's own `QuestV2`. **No answered
quest is in Era's `QuestV2` and not in Forever's.**

Of the 2,262 answered quests: 1,422 are in both clients' `QuestV2`, 716 in Forever's only, and 124 in
neither (see finding 4). Zero are Era-only.

So the server itself is the filter. A quest the server does not have gets no answer; a quest it answers is
one the Forever server carries. This is why the served step (ADR-034) ships every quest the cache holds.

Note (2026-10-02): the served step no longer drops a quest a later scan misses. Since
[ADR-050](../adr/050-english-is-additive.md), a quest any Forever build answered keeps its English.

### 2. Every quest record carries its zone, and every zone is a Forever zone

The cache record's fixed part (the first 436 bytes on this layout) was profiled word by word across all
2,262 records. The signed 32-bit value at **byte 24** is the quest's zone or sort, in Blizzard's usual shape:

- a negative value is the negated id of a row in Forever's `QuestSort`: Paladin (141), Fishing (101), Lunar
  Festival (366), Special (284), and two sorts Forever added, **Camping (666)** and **Night Elf (676)**. Every
  negative value in the cache is a `QuestSort` id; none is unknown.
- a positive value is a row in Forever's `AreaTable` (Elwynn Forest 12, The Barrens 17, Teldrassil 141,
  Stormwind City 1519). **Every positive value in the cache is in Forever's `AreaTable`**; none is missing.

Forever's new zones appear by name, from Forever's own table:

| zone id | name | answered quests |
|---|---|---|
| 16593 | Zephras Isle | 116 |
| 16611 | Ruins of Lordaeron | 12 |
| 16919 | The Hall of Thanes | 4 |
| 16591 | Riverglades | 1 |
| 16941 | Crafting (the Craftsman's Writ quests, a name-only area) | 150 |

Also in the fixed part, by the same profile (values consistent with the field, not cross-checked against a
table): byte 4 is the quest type (0, 1 or 2), byte 8 the quest level (0 to 60), byte 16 the minimum level
(0 to 48), byte 36 a linked quest id. The reader does not decode these; nothing in the pipeline needs them.

**Decision (the maintainer, 2026-09-30): no zone gate and no zone report.** The check found nothing to
filter, so the server's answer stays the only rule. To redo the check on a later build: read the signed
32-bit value at byte 24 of each record's payload, map negatives against `QuestSort.csv` and positives against
`AreaTable` (FileDataID 1353545 in the community listfile, read with `db2.read(buf, {0, 1})`; field 1 is
`AreaName_lang`), and list any value in neither. It takes one script and a minute.

### 3. `AreaTable` reads on Forever without a pinned map

`AreaTable` is not one of the pipeline's tables. For this check it was read raw from the archive: 1,417
records, layout hash `0x999A6797`, 24 fields, 46 records in three encrypted sections skipped. Fields 0 and
1 are strings (`ZoneName`, `AreaName_lang`), which is enough to name a zone id. Ids from 16003 up are
Forever's own rows (Azshara, Mount Hyjal and dozens of subzones renumbered, then the new zones above).

### 4. The client's own quest list is incomplete

124 answered quests are in **neither** client's `QuestV2`: vanilla holiday and reputation quests (ids 7883
to 7946, 8021 to 8026, 8565 to 8570, 8811 to 8856), Alterac Valley (6846, 6901), and twelve Forever ids
(80001, 91736, 91899, 91900, 91904, 92534, 93459, 94472, 94473, 97065, 97066, 97067). They reached the
cache only because an earlier build's cache had them from play, and the re-pull rescans what the previous
cache held.

So a scan driven by `QuestV2` alone cannot find every quest the server has. The only complete method is to
ask the server about **every id**. Known quest ids on this build fall in 1 to 9,999 and 50,000 to 99,326;
the sweep asks 1 to 9,999 and 50,000 to 105,000 (62,663 ids after dropping what the cache already holds,
about 52 minutes at the scan's 0.05 s per query). A quest the server does not have costs one unanswered
query. The beta-day harvest runbook (step 3) has the command.

Run on 2026-10-01 (the whole range, after a first run cut by a disconnect): 13 more quests answered, all in
Forever zones or sorts (999, 1005, 1006, 1500, 78270, 91901, 91905, 91906, 93862, 94616, 95042, 97583,
99267), none in either client's `QuestV2`; no new stub. The cache then held 2,281 quests.

### 5. Stub quests the title filter does not catch

The reader drops a record whose title starts with a tag such as `<UNUSED>` or `[DNT]`, or is only `REUSE`.
These titles pass and ship translated today: `Hunter test quest` (7681, 7682), `test quest - do not use`
(7869, 7870), `Collin's Test Quest` (8230), `test copy quest` (8270), `Test Kill Quest` (8274), `Redeem iCoke
Prize Voucher` (8021 to 8026, 9273) and `Redeem iCoke Gift Box Voucher` (9353), `jktestquest1a` (92534),
`zzOLD UNUSED Cult Ambush` (92480), `(UNUSED) The Rusty Gadget` (93173), `UNUSED` (94559). Most have zone 0.

**Decision (the maintainer, 2026-09-30): leave them.** A translation shows only when the game shows the
quest, so these cost nothing on screen; a rule for 21 quests is not worth its upkeep.

## What this settles

- A quest the Forever server answers is a Forever quest: it is in the server's database, in a Forever zone
  or sort. That is the strongest proof available from the client side. Whether an NPC offers it can only be
  proven by play.
- A quest the server does not answer is not on Forever, whatever `QuestV2` or Era say.
- The full scan on a new build is the sweep of every id, not the `QuestV2` list, so nothing depends on the
  previous cache surviving.

## Method (to repeat it)

1. Full scan and sweep in game, Exit Game, `make wdb-copy`.
2. Group the cache's ids by membership in Forever's and Era's `QuestV2` (Era's from `python -m
   wfj.dev.client_tables --product wow_classic_era --tables QuestV2 QuestSort` into a scratch folder).
3. Profile the fixed part: for every 4-byte offset below the objective count, the distinct values, minimum,
   maximum and how many are negative. The zone field is the one whose negatives are all `QuestSort` ids.
4. Map the positives against `AreaTable` as in finding 2.

## Related

- [ADR-020](../adr/020-quest-cache-harvest.md), the quest cache as the English source
- [ADR-034](../adr/034-forever-is-the-only-target.md), the served step
- [The Forever client's quest cache layout](2026-09-18-forever-questcache-layout.md), the text parts of the record
- The beta-day harvest runbook, step 3 (the sweep) and step 6 (what an answer means)
