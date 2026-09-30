# Verifying the Forever client's DB2 column maps

> 2026-09-18. Subject: **World of Warcraft: Forever beta 1.60.1.69913** (`wow_classic_beta`).
> Oracle: **Classic Era 1.15.9.69722** (`wow_classic_era`), whose column map was verified against
> wago.tools' export of that build. Both installs read read-only through `io/casc.py` (ADR-021).

## Why a second client, and not wago

`io/client_tables.py` pins every table to the layout hash it was verified on and refuses a build whose layout
moved, rather than guess which field is which column ([principle 9](../architecture/principles.md)). Four tables
moved on Forever. wago.tools is not used as a data source, and it is not needed here: **a second installed client whose
map is already verified is the better oracle**, because it is the same field of the same table read by the same
code, so a disagreement is about the client and not about two toolchains.

Two independent constraints are used, and both are reported:

1. **Which string-field sets parse at all.** A sparse table stores its strings inline, so the reader has to be
   told which fields are strings; a wrong set makes the fields stop short of the record or run past it and
   `io/db2.py` raises. Where exactly one set parses, the string layout is *fixed* before any content is
   compared, and no content evidence can override it.
2. **Cross-build agreement per written text column.** For ids present in both clients, how often the same
   field holds the same string. A column that did not move scores very high, and the shortfall is content the
   new build changed. A column that moved scores near zero, and the report names the field that scores high
   instead.

A third outcome matters as much as those two: a **low** rate with **no better field** means the column is in
the right place and the build changed the data. Reporting that as "moved" would send the next reader hunting a
column that never went anywhere.

## The run

```
subject: 1.60.1.69913 (wow_classic_beta)
oracle:  1.15.9.69722 (wow_classic_era)
ItemSparse: subject 0x6FCC3191/68f · oracle 0xB51F7C79/74f
  string sets that parse: {0,1,2,3,4}; unique, the string layout is fixed
  Description_lang = field 0: 1534/1557 = 98.5% (14266 shared ids): unchanged
  Display_lang = field 4: 14154/14266 = 99.2% (14266 shared ids): unchanged
SpellName: subject 0x782EE721/1f · oracle 0x782EE721/1f
  Name_lang = field 0: 26001/26386 = 98.5% (26386 shared ids): unchanged
Spell: subject 0xE3D134FB/3f · oracle 0xE3D134FB/3f
  string sets that parse: {0,1,2} {0,1,2,3} {0,1,2,3,4} {0,1,2,3,4,5} {0,1,2,3,4,5,6} {0,1,2,3,4,5,6,7}
  Description_lang = field 1: 13464/14733 = 91.4% (26386 shared ids): unchanged
  AuraDescription_lang = field 2: 5741/6405 = 89.6% (26386 shared ids): position unchanged, content differs on this build
GlobalStrings: subject 0xD40F6D96/3f · oracle 0xD40F6D96/3f
  BaseTag = field 0: 18800/18908 = 99.4% (18908 shared ids): unchanged
  TagText_lang = field 1: 17889/18877 = 94.8% (18908 shared ids): unchanged
ItemSubClass: subject 0x1E67DB87/11f · oracle 0x1E67DB87/11f
  DisplayName_lang = field 0: 65/72 = 90.3% (72 shared ids): unchanged
  ClassID = field 3: 72/72 = 100.0% (72 shared ids): unchanged
  SubClassID = field 4: 72/72 = 100.0% (72 shared ids): unchanged
SpellItemEnchantment: subject 0x952B72B2/24f · oracle 0xC681231E/22f
  Name_lang = field 0: 2109/2157 = 97.8% (2158 shared ids): unchanged
QuestV2: subject 0x1854BDB9/3f · oracle 0xC6FAA9AA/1f
  UniqueBitFlag = field 0: 1/4805 = 0.0% (4805 shared ids): MOVED: field 1 agrees 99.9% instead
ItemEffect: subject 0x4CA77678/9f · oracle 0x1BF9CF3A/9f
  LegacySlotIndex = field 0: 7243/7243 = 100.0% (7243 shared ids): unchanged
  TriggerType = field 1: 7216/7243 = 99.6% (7243 shared ids): unchanged
  SpellID = field 6: 5227/7243 = 72.2% (7243 shared ids): position unchanged, content differs on this build
  note: relationship map empty on the subject (16965 on the oracle); a non-inline relation column cannot be read here
ItemXItemEffect: no cross-build evidence; ItemXItemEffect is not shipped on one of the two clients
```

## What it means, per table

| table | fields | verdict |
|---|---|---|
| **ItemSparse** | 74 → **68** | No column moved. `{0,1,2,3,4}` is the only string set the reader accepts, so the string layout is fixed independently of the content comparison. `Description_lang` 98.5%, `Display_lang` 99.2%. |
| **SpellItemEnchantment** | 22 → **24** | No column moved. `Name_lang` 97.8%. |
| **QuestV2** | 1 → **3** | **The one real move.** The row id became an *inline* field 0, pushing `UniqueBitFlag` to field 1 (99.9%), and a third field was added that reads 0 on every row. Fields 0 and 2 agree 0.0%, so this is unambiguous. |
| **ItemEffect** | 9 → 9 | No column moved. `SpellID` reads 72.2% against a next-best field of 0.3%, so it is in place; about 28% of rows point at a different spell than on Classic Era. That is a finding about the data, not the map. |

The shortfalls on the unchanged columns are the content Forever reworded. That is not noise to be explained
away; it is the material that has to be re-translated, and the run above sizes it:

| column | agreement | reworded on Forever |
|---|---|---|
| `Spell.Description_lang` | 91.4% (13,464 / 14,733) | **~8.6%**: the spell tooltip text |
| `Spell.AuraDescription_lang` | 89.6% (5,741 / 6,405) | ~10.4%: buff / debuff text |
| `GlobalStrings.TagText_lang` | 94.8% (17,889 / 18,877) | ~5.2%: the UI dictionary ([the client-differences survey](2026-09-17-forever-client-differences.md) measured 79 of 700 shipped keys reworded, consistent) |
| `ItemSparse.Display_lang` | 99.2% (14,154 / 14,266) | ~0.8%: item names (which stay English anyway, [principle 2](../architecture/principles.md)) |
| `ItemSparse.Description_lang` | 98.5% (1,534 / 1,557) | ~1.5%: item flavour text |
| `SpellName.Name_lang` | 98.5% (26,001 / 26,386) | ~1.5%: spell names (stay English) |
| `SpellItemEnchantment.Name_lang` | 97.8% (2,109 / 2,157) | ~2.2%: enchantment lines |
| `ItemSubClass.DisplayName_lang` | 90.3% (65 / 72) | ~9.7%: the bag / weapon type words |

Those percentages are over ids **shared** with Classic Era. They do not count ids that exist only on Forever,
which is a separate and larger population. That count belongs to the import's delta report, not here.

## ItemEffect's ParentItemID does not exist on this build

`ItemEffect`'s relationship map is empty on Forever: every section reports `relationship_data_size` **0**,
against Classic Era's **135,732 bytes** (12 + 16,965 × 8). So `ParentItemID` cannot be read from this table at
all, and the column is written `0` with a row-count note.

The join moved into **`ItemXItemEffect.db2`** (FileDataID 3177687, layout `0x96F083AD`, one inline field, 12,565
rows), which **Classic Era does not ship**: its root names no enUS content for that id, because that client
does the join inline instead. There is therefore no second client to cross-verify it against, so it was verified
**end to end** instead, which is stronger:

```
item 4536 "Shiny Red Apple"
  → ItemXItemEffect            → ItemEffectID 97715   (ItemID 4536 from the relationship map)
  → ItemEffect.SpellID         → 433
  → Spell.Description_lang     → "Restores $o1 health over $d.  Must remain seated while eating."
```

That last line is character-for-character the English `data/english/item` already holds for item 4536. Two more
resolve the same way (`Tough Jerky` 117 and `Tough Hunk of Bread` 4540 both reach spell 433; `Hearthstone` 6948
reaches spell 8690, "Returns you to $z…").

**This also corrects a premise.** An item's tooltip "Use:" line is the *spell's* description reached through
this join. It is **not** `ItemSparse.Description_lang`, which is the flavour line and is empty for item 4536.
And because that spell text is **identical** between the two builds (`$o1` / `$d` unchanged), re-pulling the
English does **not** fix the Shiny Red Apple rendering English in game: the shipped human Japanese bakes the
literal `61` where `$o1` resolves to 58 on Forever, so `Align.check` refuses it. That line needs re-drafting with
placeholders: a translation fix, not a harvest one.

## Reproducing this

```
python -m wfj.dev.verify_columns --wow "<World of Warcraft>" \
    --product wow_classic_beta --against-product wow_classic_era [--tables ItemSparse …]
```

Read-only, no network, exits 1 if a table cannot be read on either client or if the two clients share no ids for
it. An absence of evidence is never reported as a 0% verdict.

## Related

- [ADR-027: A DB2 column map is verified per build](../adr/027-column-maps-verified-per-build.md)
- [ADR-021: Client tables from the local archive](../adr/021-client-tables-from-the-local-archive.md)
- [ADR-026: A blank archive-entry header is unwritten](../adr/026-blank-archive-header-is-unwritten.md), the
  fix that made any of these tables readable on Forever at all
