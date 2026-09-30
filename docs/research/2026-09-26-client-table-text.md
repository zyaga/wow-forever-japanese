# Research: the text held in client tables the pipeline never read

> 2026-09-26. Subject: **World of Warcraft: Forever beta 1.60.1.70009** (`wow_classic_beta`). Oracle:
> **Classic Era 1.15.9.69722** (`wow_classic_era`). Both installs read read-only through `io/casc.py` and
> `io/db2.py` (ADR-021). Decision: [ADR-042](../adr/042-client-table-text-families.md).

- **Date:** 2026-09-26
- **Question:** which client tables hold text a Forever player is shown, where it is shown, and how each is read,
  verified and matched.

## Measurement

Every candidate table (and three found on the way), read from both installs. A field counts as text when the
reader accepts it as a string field for every row. "Rows" is the record count; "text" is non-empty / distinct.

| table | Era rows | Forever rows | Forever text (non-empty / distinct) | Forever display site | decision |
|---|---|---|---|---|---|
| Faction | 209 | 252 | Name 253 / 252 · **Description 59 / 58** | reputation detail pane (`blizzard_uipanels_game/camelot/reputationframe.lua:758, 771` → `characterframe.lua:873–885`) | imported: `FactionDescription` (names stay English) |
| Achievement | 34 | 433 | **Description 389 / 316 · Title 433 / 367 · Reward 130 / 1** | achievement window rows, the Legacy window's challenge cards, the Statistics tab, the tracker, the toast | imported: `AchievementTitle`, `AchievementDescription`, `AchievementReward` |
| Achievement_Category (found on the way) | 13 | 56 | **Name 56 / 53** | achievement / Legacy / Statistics category lists | imported: `AchievementCategory` (class, profession and zone names left out) |
| SkillLine | 129 | 154 | DisplayName 154 / 134 · **Description 53 / 27** | skills detail pane (`camelot/skillsframe.lua:273`) | imported: `SkillLineDescription` (skill names stay English) |
| SkillLineCategory (found on the way) | 9 | 9 | **Name 9 / 9** | skills list headers (`camelot/skillsframe.lua:127–141`) | imported: `SkillCategory` |
| EmotesTextData | 1,350 | 1,350 | **Text 1,334 / 1,315** | chat, `CHAT_MSG_TEXT_EMOTE` (`blizzard_chatframebase/mainline/chatframeoverrides.lua:635–644`) | imported: `EmoteText` (slotted) |
| EmotesText / Emotes | 255 / 90 | 255 / 121 | slash tokens (`WAVE`) / animation names (`STATE_SIT`) | none: internal | not imported |
| HolidayNames | 0 | 16 | Name 16 | calendar headers | not imported: event names (style guide: events are names) |
| HolidayDescriptions | 0 | 17 | **Description 17 / 17** | calendar holiday frame (`blizzard_calendar/mainline/blizzard_calendar.lua:2471–2482`) | imported: `HolidayDescription` |
| BattlemasterList | 4 | 10 | Name 10 · short 4 · long 5 | none on camelot: `blizzard_pvpui` is gated, `pvphelper.lua:22–46` queues without a frame | not imported: no Forever display site |
| LFGDungeons | 67 | 76 | Name 71 | none: the camelot callers discard `description` (`socialqueue.lua:19`, `quickjointoast.lua:593`); the finder is gated | not imported: no Forever display site |
| CurrencyTypes | 0 | 9 | Name 9 · **Description 8 / 8** | token frame detail pane (`blizzard_tokenui/camelot/blizzard_tokenui.lua:479–482, 537`) and the entry tooltip | imported: `CurrencyDescription` (names stay English) |
| CurrencyCategory (found on the way) | 0 | 6 | **Name 6 / 6** | token frame headers (`camelot/blizzard_tokenui.lua:5–8, 215–219`) | imported: `CurrencyCategory` |
| SpellMechanic | 28 | 33 | Name 36 / 33 (lower case: `dazed`) | none: searched `mechanic` in every addon; loss-of-control text is `LOSS_OF_CONTROL_DISPLAY_*` | not imported: no Forever display site |
| SpellDispelType | 11 | 11 | **Name 11** · InternalName 4 | aura tooltip, right side (C-side) [unverified in game] | imported: `DispelType` (Magic, Curse, Disease, Poison) |
| CreatureType | 11 | 13 | **Name 13** | unit tooltip level line (C-side) | imported: `CreatureType` |
| CreatureFamily | 26 | 27 | Name 27 | pet paper doll, unit tooltip | not imported: pet families are names |
| QuestSort | 36 | 39 | **SortName 39** | quest log headers (`blizzard_uipanels_game/mainline/questmapframe.lua:2044–2048`) | imported: `QuestSort` (classes, professions, events, races left out) |
| SpellCategory | 228 | 260 | Name 261 / 260 (developer names) | none: searched `spellcategory` / `GetSpellCategory` / `categoryName` | not imported: no Forever display site |
| FactionGroup | 4 | 4 | Horde / Alliance / Player / Monster | none | not imported: names |

Spell subtitles ("Racial Passive") already ship (`SpellSubtext:<spellID>`, ADR-032); the spell
tooltip's right-hand subtitle line is matched by the same fingerprint rows through `UI/Tooltip.lua`'s unrestricted
line match.

## Column maps

Every written column is the row id or a leading string field, so each table is text-only and a hotfix is read as its
leading strings. Verified 2026-09-26:

| check | result |
|---|---|
| Classic Era extract vs wago.tools 1.15.9.69722 (`dev/client_tables --against`) | 0 rows differ on each of the 9 tables Era ships rows for (HolidayDescriptions, CurrencyTypes, CurrencyCategory have none) |
| Forever extract vs wago.tools 1.60.1.70009 (the cross-check) | 0 rows differ on all 12 |
| `dev/verify_columns` Forever vs Classic Era | Faction Description 95.1 % (39/41) · Achievement Title 96.8 % (30/31; Era's 31 shared ids carry no description or reward) · Achievement_Category 60 % (3/5, content changed, position unchanged) · SkillLine Description 100 % (35/35) · SkillLineCategory 100 % (9/9) · EmotesTextData 100 % (1,334) · SpellDispelType 100 % (11/11) · CreatureType 100 % (11/11) · QuestSort 100 % (36/36) |

The re-extract into the pinned Forever folder rewrote the nine tables it already held byte for byte (SHA-1 checked).

## Rows listed

2,120 keys, one per distinct English per family (the fingerprint covers every id with that English); 94 rows left
out: 43 names, 35 developer rows (`Hidden:`, `UNUSED`, `BETA Survey`, test factions, SkillLineCategory
`Not Displayed`), 10 `Rank N` titles (Rank stays English) and 6 dispel types the client never shows as a debuff type
Of the 1,918 distinct English, 30 already ship Japanese under another key and reuse it (one English,
one Japanese).

## Matching

| family | how the addon finds the live text |
|---|---|
| `WidgetText` | numbered: the skeleton's hash (below) |
| every other family but `EmoteText` | fingerprint: the live line's hash is the row's h1 (as `ItemSubClass`, `SpellSubtext`), but only where a widget names the family (restricted: 19 family words are also item or spell names, such as "Journeyman Engineer" and "Poison", so the open match never returns them). Each restricted family is indexed on its own (per-family restricted index), so its Japanese may differ from another family's or a global string's of the same English |
| `EmoteText` | slotted: the line's plain text with the known names (sender, player, target), and failing that one more run of 1–4 words, put back as `%s`; the skeleton's hash is the row's h1 |
| `CreatureType` in the unit level line, `HolidayDescription` in the calendar | an argument kind of the template that only ever takes that family's row (`creatureType`, `holidayDescription`): a race, class, spec or pet-family name in the same slot stays as written |

## Second round: other client-table and server text

Other windows had been left waiting on client-table or server text. Measured the same way (both installs, read-only; tables the roots do not name read by
their community-listfile FileDataIDs):

| item | Forever table / finding | decision |
|---|---|---|
| auction house categories | `ItemSubClass.VerboseName_lang`, the long name `GetItemSubClassInfo` returns ("Staves", "One-Handed Axes"; 36 subclasses have one), else the short `DisplayName_lang` ("Potions", "Arrow") | family `ItemSubClassName:<c>:<s>` (70 keys; recipe / profession subclasses left out); the category button also takes the `INVTYPE_*` slot words |
| barber shop | `ChrCustomizationCategory.CategoryName_lang` (62 rows; Classic Era's layout has no text field), `ChrCustomizationOption.Name_lang` (191 distinct), `ChrCustomizationChoice.Name_lang` (1,419 distinct; Classic Era's 746 rows carry no names), `ChrCustomizationReq.ReqSource_lang` ("See colors") | families `CustomizationCategory` (19; druid forms, demon and mount rows left out), `CustomizationOption` (185; the forms left out), `CustomizationChoice` (1,305; developer rows `New 01`, `Primalist …` and 78 choices that are only a name, such as `Alexstrasza`, `Brewfest`, `Samson`, left out), `CustomizationSource` (1) |
| PvP scoreboard columns | `PVPScoreboardColumnHeader` (Forever only: Flag Captures, Bases Assaulted, Bases Defended + a tooltip each); `PVPStat` holds the same names | families `PvpColumn`, `PvpColumnTooltip` |
| group finder | `GroupFinderCategory` (5 words), `GroupFinderActivityGrp` (Dungeons, Raids, Battlegrounds, World PvP + Eastern Kingdoms, Kalimdor, Skywall), `GroupFinderActivity` (111 rows: dungeon, raid and zone names + "Custom") | families `LfgCategory` (5), `LfgActivityGroup` (4; the zone names left out), `LfgActivity` ("Custom" only) |
| UI widgets | `UiWidgetStringSource.Value_lang` (138 rows, 85 distinct): battleground and world-event status lines, 16 of them with world-state tokens (`Towers Controlled: %2327w`) | family `WidgetText` (74; event names and number-only lines left out): numbered rows (below) |
| wardrobe set variants | `TransmogSet.ItemNameDescriptionID` → `ItemNameDescription.Description_lang`: Green, Blue, White, Grey (the table's other rows are random-suffix name parts) | family `ItemNameDescription` (4) |
| mount source and lore | `Mount.SourceText_lang` / `Description_lang`: empty on every Forever row (only the 141 names are set; no hotfix) | nothing to translate |
| pet journal source and description | `BattlePetSpecies` text columns: empty on every Forever row (115 rows, no hotfix) | nothing to translate |
| Chromie Time | `UiChromieTimeExpansionInfo`: 0 rows on Forever | nothing to translate |
| splash screen | `UiSplashScreen`: 0 rows on Forever | nothing to translate |
| party pose | `UiPartyPose`: 0 rows on Forever | nothing to translate |
| generic trait tree | `TraitTree` has no text column; the title is C_Traits data or a Lua literal, and no Forever window opens the frame | `blizzard_generictraitui` recorded `unreachable` |
| Legacy reward names | reward item / title names | names |

Column maps, verified 2026-09-26: Forever extract vs wago.tools 1.60.1.70009: 0 rows differ on all eleven tables
and on ItemSubClass with its new VerboseName column. Classic Era vs wago 1.15.9.69722: 0 rows differ on the ten it
ships. `dev/verify_columns`: ChrCustomizationOption 96.4 % (81/84), GroupFinderCategory / ActivityGrp / Activity
100 %, UiWidgetStringSource 100 % (58/58), ItemNameDescription 100 % (22/22); ChrCustomizationChoice and
ChrCustomizationReq share no text with Classic Era (no evidence either way; wago's export is the check).

**Numbered rows.** A widget line's tokens are live numbers, so the English never equals the line. Both sides hash a
skeleton instead: the pipeline replaces every token and every digit run of the English with `#`, the addon every
digit run of the live line, and the skeleton's hash is the row's h1 (`core/numbered`, `Core/UIStrings`
`index:matchNumbers`). The Japanese keeps the tokens in `data/`; `generate` writes each as `%<k>$s`, k its place among
the English's number runs, and the addon fills it with the k-th number of the line.
