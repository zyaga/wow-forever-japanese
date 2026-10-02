# Research: every text the Forever client serves

- **Date:** 2026-10-02
- **Question:** What text does the Forever client serve, which of it does the addon translate, and what is left
  without a reason?
- **Build:** Forever beta 1.60.1.70170 (`wow_classic_beta`), read-only, offline
  ([ADR-021](../adr/021-client-tables-from-the-local-archive.md)).
- **Artifacts:** `pipeline/served_columns.txt` (generated, `make served-columns`) and
  `pipeline/served_dispositions.txt` (hand-written). Decision: [ADR-051](../adr/051-coverage-by-served-data.md).

## Options

| Option | Pros | Cons |
|---|---|---|
| Widen the visible-spell list with more sources | small change | still a guess; misses tables, not only spells |
| Pin a column map for every shipped table | exact columns | 1,161 tables; every build needs new pins first |
| Find text columns from the bytes, decide each one by hand | catches new tables and columns; no map | the decisions are hand work; one table layout not readable yet |

## Method

1. **Tables.** The archive root names no files, so the DB2 tables are found through the community listfile
   (`<FileDataID>;<path>`, every `dbfilesclient/*.db2` it names). A listed table the build does not ship is
   skipped (`casc.LocalArchive.ships`).
2. **Text columns, from the bytes** (`io/db2.text_fields`). In a dense table a column is text when every non-zero
   value points at the start of a NUL-terminated UTF-8 string. In a sparse table the strings are inline, so the
   column layout is the one string or number layout under which every record parses, with layouts that put
   strings first tried first. A column empty on every row is not counted as text.
3. **Hotfixes.** Valid rows of `Cache/ADB/enUS/DBCache.bin` for a table that keeps its text fields first are read as
   their leading strings and replace the archive row with the same id. A hotfix table hash the archive does not
   name is listed as `hotfix-only`.
4. **Server caches.** The text the server sends rather than the archive (quests, NPC text, book pages, creature
   and object names) lands in `Cache/WDB/enUS/*.wdb`; each cache is listed with its record count.
5. **Counts per column:** rows, non-empty values, distinct values.
6. **Display-site sweep.** For every column, the Forever client's own UI source (the 1.60.1.70170 extract of
   `Interface/AddOns`) was searched for the API that returns it and the frame that prints it. Each column then got
   a disposition.

## Findings

### The inventory on 1.60.1.70170

| Count | Value |
|---|---|
| Tables the install ships | 1,161 |
| Tables with text | 171 |
| Text columns | 254 |
| Unreadable tables | 1 (`collectablesourcevendorsparse`, a secondary-key layout the reader does not implement) |
| Server caches | 6 (`questcache` 2,406 records, `creaturecache` 13, `gameobjectcache` 10, `npccache`, `pagetextcache`, `petitioncache` empty on this install) |

### Verification against the pinned column maps

The pipeline reads 31 tables through column maps pinned with cross-build evidence
([ADR-027](../adr/027-column-maps-verified-per-build.md)). On 1.60.1.70170 the byte-level detection finds the same
text columns in all 31. The only differences are string fields a map declares that are empty on every row, which
the detection does not count as text. Two independent methods agreeing is evidence for both.

### Dispositions

| Disposition | Columns | Lines |
|---|---|---|
| Shipped through a surface | 36 | 76,470 |
| Names (stay English) | 53 | 68,793 |
| Internal (never printed) | 96 | 370,638 |
| No place in the Forever client | 26 | 1,782 |
| Same text as another column | 7 | 10,965 |
| Empty on this build | 3 | 0 |
| Not decided yet | 39 | 7,115 |

The full per-column list, with each disposition and its evidence, is generated into
[Coverage](../operations/coverage.md) under "Served text inventory".

### What the visible-spell scope missed

Counting every served spell line instead of the visible subset: spell tooltips and auras have 25,458 served lines,
10,369 ship Japanese, and 15,064 are gaps (9,810 descriptions, 5,254 auras; 7,319 distinct texts). These are world
buffs and the spells creatures and bosses cast, whose aura text a player reads on their own buff bar. Other gaps on
this build: quest 7, book 4, item 2.

### Display-site sweep

Paths are relative to `Interface/AddOns` in the 1.60.1.70170 extract.

**Shown in game, not translated yet**

| Column | Shown? | Evidence | Covered? |
|---|---|---|---|
| `criteriatree.f0` | yes: achievement and Legacy criteria, objective tracker | `GetAchievementCriteriaInfo` criteriaString; `blizzard_legacysystem/blizzard_legacychallengebutton.lua:102-111, 172-175`; `blizzard_objectivetracker/blizzard_achievementobjectivetracker.lua:130-152` | no. 1,507 distinct texts reachable from the 432 achievement root trees; most are place, creature or item names that stay English |
| `renownrewards.f0` / `f1` / `f2` | yes: Legacy reward track, PvP rank pane, renown toast | `C_MajorFactions.GetRenownRewardsForLevel`; `blizzard_framexml/rewardtracktemplates.lua:493-545`; `blizzard_uipanels_game/camelot/pvprankframe.lua:185-206`; `blizzard_majorfactions/blizzard_majorfactionrenowntoast.lua:71-76` | no |
| `sharedstring.f0` | yes: talent requirement lines | `blizzard_sharedtalentui/blizzard_sharedtalentutil.lua:679-699` | no |
| `tradeskillcategory.f0` | yes: recipe list headers | `blizzard_professionstemplates/blizzard_professionsrecipelist.lua:207` | no |
| `mailtemplate.f0` | yes: NPC mail bodies | `blizzard_mailframe/mailframe.lua:776-777` | no |
| `questinfo.f0` | yes: quest tags on map pin tooltips | `blizzard_framexmlutil/mainline/questutils.lua:31-58` | no |
| `areapoi.f1`, `areapoistate.f0` | yes: map POI tooltip descriptions | `blizzard_sharedmapdataproviders/sharedmappoitemplates.lua:139-157` | no |
| `petloyalty.f0` | yes: hunter pet loyalty on the pet pane | `blizzard_uipanels_game/camelot/paperdollframe.lua:549-551` | no |
| `map.f5` | yes: battleground queue subtitle | `blizzard_queuestatusframe/mainline/queuestatusframe.lua:801-819` | no |
| `difficulty.f0` | yes: raid info, calendar | `blizzard_raidframe/mainline/raidframe.lua:157-158` | no |
| `uieventtoast.f3` | yes: event toasts | `blizzard_framexml/eventtoastmanager.lua:491-492` | no |
| `broadcasttext.f0` | yes: cinematic subtitles (12 rows) | `blizzard_subtitles/blizzard_subtitles.lua:37-95` | no |

**Shown only if a system is on (in-game check needed)**

| Column | Where it would show | Covered? |
|---|---|---|
| `rolodextype.f0` / `f1` | Recent Allies tab | no |
| `transmogsituation.f0`, `transmogsituationtrigger.f0` / `f1`, `transmogoutfitslotoption.f0` | transmog outfits | no |
| `friendshipreputation.f0` / `f1` | a chat line | no |
| `mapdifficulty.f0`, `mapdifficultyxcondition.f0` | instance entry error lines | no |

**Words inside a sentence the addon already translates**

These print as an argument of a GlobalStrings template the interface dictionary already ships, so translating them
changes the kind of that argument, not the sentence.

| Column | Template | Covered? |
|---|---|---|
| `itempetfood.f0` | `PET_DIET_TEMPLATE` | no |
| `exhaustion.f0` | `EXHAUST_TOOLTIP1` | no |
| `itemsubclassmask.f0` | `SPELL_REQUIRED_FORM` | no |
| `spellfocusobject.f0` | required-tools lines; many values are object names | no (names question) |
| `locktype.f0` / `f1` / `f2` | lock and gathering lines | no (in-game check) |

**Unsure, in-game check needed:** `spellrange.f0` / `f1`, `playercondition.f0`, `spellflyout.f0` / `f1`, `toy.f0`,
`servermessages.f0`.

**Not shown on Forever** (written as `no-display`, with the evidence in `pipeline/served_dispositions.txt`):
`itemclass`, `itembagfamily`, `traitcost`, `traitcurrencysource`, `spelldiminish`, the GM survey tables,
`barbershopstyle` (a legacy table), `chrcustomization`, `gametips` (the loading screen is drawn by the client, not by
a frame an addon reaches), the PvP UI descriptions (`blizzard_pvpui.toc` excludes camelot), the tables only glue
screens read (character create, realm list, character services, configuration warnings), and the in-game shop
(its addons declare `UseSecureEnvironment: 1`).

**Kept English on purpose:** chat channel names (`chatchannels`), like every other name.

### Columns still to decide

The 39 columns listed above as shown, conditionally shown, words in a sentence, or unsure are the "not decided
yet" row: `criteriatree.f0`, `renownrewards.f0` `f1` `f2`, `sharedstring.f0`, `tradeskillcategory.f0`,
`mailtemplate.f0`, `questinfo.f0`, `areapoi.f1`, `areapoistate.f0`, `petloyalty.f0`, `map.f5`, `difficulty.f0`,
`uieventtoast.f3`, `broadcasttext.f0`, `rolodextype.f0` `f1`, `transmogsituation.f0`,
`transmogsituationtrigger.f0` `f1`, `transmogoutfitslotoption.f0`, `friendshipreputation.f0` `f1`,
`mapdifficulty.f0`, `mapdifficultyxcondition.f0`, `itempetfood.f0`, `exhaustion.f0`, `itemsubclassmask.f0`,
`spellfocusobject.f0`, `locktype.f0` `f1` `f2`, `spellrange.f0` `f1`, `playercondition.f0`, `spellflyout.f0` `f1`,
`toy.f0`, `servermessages.f0`. Each needs either a surface that reads it or a written reason, and the ones that
are shown are new surfaces for the maintainer to approve.

## Recommendation

Measure coverage against the inventory and require a disposition for every served column
([ADR-051](../adr/051-coverage-by-served-data.md)). Regenerate the inventory on every build and read its delta as
part of the harvest. Translate the spell gaps first (largest, already a surface), then decide the 39 open columns.

## Related

- [The visible-spell scope (superseded)](2026-09-18-forever-visible-spell-scope.md)
- [ADR-027: column maps verified per build](../adr/027-column-maps-verified-per-build.md)
- [ADR-042: client-table text families](../adr/042-client-table-text-families.md)
- [Pipeline](../systems/pipeline.md) · [Data model](../architecture/data-model.md) · [Coverage](../operations/coverage.md)
