# Coverage: how much of the game ships in Japanese

> **Generated** by `make coverage` (`pipeline/wfj/dev/coverage.py`) on 2026-10-05 at commit `7d5ca65e`.
> Do not edit by hand: every pull request that changes `data/` re-runs it. Measured from
> the English the Forever client serves, every line of it; a line that is only a
> name, a placeholder quest or a picture-only page counts as done (nothing to translate).

## Translation

| Surface | English lines | Ship Japanese | Nothing to translate | Done | Not yet |
|---|---|---|---|---|---|
| Quest text | 20,084 | 19,973 | 111 | 100.0% | 0 |
| NPC dialogue (gossip, speech) | 10,942 | 10,942 | 0 | 100.0% | 0 |
| Book / letter pages | 1,257 | 1,205 | 52 | 100.0% | 0 |
| Quest objective lines | 409 | 372 | 37 | 100.0% | 0 |
| Exploration / event objectives | 218 | 216 | 2 | 100.0% | 0 |
| Item descriptions | 10,124 | 8,611 | 0 | 85.1% | 1,513 |
| Spell tooltips + auras | 25,458 | 25,271 | 0 | 99.3% | 187 |
| Interface strings | 15,845 | 15,845 | 0 | 100.0% | 0 |
| **All** | **84,337** | | | **98.0%** | **1,700** |

Lines shipped as their English under a maintainer ruling (`ruling: accept`, for names, classes,
professions, internal strings): quest 331, gossip 81, item 888, spell 300, ui 313.

### Nothing to translate (counted as done)

| Surface | Why | Lines |
|---|---|---|
| Quest objective lines | name only (`pipeline/objective_names.txt`) | 37 |
| Exploration / event objectives | name only (`pipeline/area_names.txt`) | 2 |
| Quest text | placeholder quest (never shown) | 108 |
| Quest text | a bare label: a name or a one-word placeholder (ships as the English) | 3 |
| Book / letter pages | Missing Text / picture-only page | 49 |
| Book / letter pages | picture-only or cipher page | 2 |
| Book / letter pages | a bare label: names and numbers only (ships as the English) | 1 |

### What is not done yet

| Surface | Why | Lines |
|---|---|---|
| Item descriptions | no Japanese yet: no text from the Forever tables on this build yet (English still from Classic Era); rechecked at each re-pull | 1,511 |
| Item descriptions | no Japanese yet: the template uses a code drafting cannot place yet (too_many_variants) | 1 |
| Item descriptions | no Japanese yet: the template uses a code drafting cannot place yet (branches_indistinguishable) | 1 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (unsupported_code:$@spellaura) | 47 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (unsupported_code:$@spelldesc) | 35 |
| Spell tooltips + auras | no Japanese yet: no text from the Forever tables on this build yet (English still from Classic Era); rechecked at each re-pull | 22 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (branches_indistinguishable) | 19 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (unsupported_code:$@expandkey) | 17 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (too_many_variants) | 6 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:407624) | 4 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (unsupported_code:$@null) | 3 |
| Spell tooltips + auras | rejected: ruled_reject | 2 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (unsupported_code:$@auracaster) | 2 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:399963) | 2 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:403338) | 2 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:407613) | 2 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:407631) | 2 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:407676) | 2 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:407669) | 2 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:409541) | 2 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (unclosed_branch) | 2 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:998) | 2 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:134732) | 1 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:364456) | 1 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:407993) | 1 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:409552) | 1 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:409069) | 1 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:426158) | 1 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (uncountable) | 1 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:19293) | 1 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:377950) | 1 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:414924) | 1 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (missing_included_spell:1300354) | 1 |
| Spell tooltips + auras | no Japanese yet: the template uses a code drafting cannot place yet (unsupported_code:$@auradesc) | 1 |

## Served text inventory

Every text column the client serves on 1.60.1.70170 (`pipeline/served_columns.txt`: its
tables, hotfixes and server caches), with the disposition
`pipeline/served_dispositions.txt` gives it.
Lines are non-empty values; a server cache counts the records this install holds.

| Disposition | Columns | Lines |
|---|---|---|
| Shipped through a surface above | 70 | 83,224 |
| Names (stay English) | 55 | 69,037 |
| Internal (never printed) | 96 | 370,638 |
| No place in the Forever client | 29 | 1,899 |
| Same text as another column | 7 | 10,965 |
| Empty on this build | 3 | 0 |

### Every column

| Column | Disposition | Lines | Why |
|---|---|---|---|
| `achievement.f0` | surface:ui:AchievementDescription | 390 | Description_lang |
| `achievement.f1` | surface:ui:AchievementTitle | 434 | Title_lang |
| `achievement.f2` | surface:ui:AchievementReward | 130 | Reward_lang |
| `achievement_category.f0` | surface:ui:AchievementCategory | 56 | Name_lang |
| `animkitboneset.f0` | internal | 18 | animation bone set names |
| `areaconditionaldata.f0` | names | 2 | place names (The Drunken Dwarf) |
| `areapoi.f0` | names | 372 | place names (Anvilmar, Brill) |
| `areapoi.f1` | surface:ui:AreaPoiDescription | 150 | Description_lang: map point tooltip lines (zone and faction names stay English) |
| `areapoistate.f0` | surface:ui:AreaPoiState | 17 | Description_lang |
| `areatable.f0` | internal | 1,371 | ZoneName: CamelCase tokens (DunMorogh) |
| `areatable.f1` | names | 1,371 | AreaName_lang: zone and subzone names |
| `auctionhouse.f0` | names | 21 | auction house names (Stormwind Auction House) |
| `availablesuperdistrict.f0` | no-display | 5 | ruleset names, realm list (blizzard_gluexml superdistrict.lua) |
| `availablesuperdistrict.f1` | no-display | 5 | ruleset descriptions, realm list (blizzard_gluexml superdistrict.lua) |
| `availablesuperdistrict.f2` | internal | 1 | atlas names (Mode-Selection-Card-Hardcore) |
| `availablesuperdistrict.f3` | internal | 1 | atlas names |
| `bannedaddons.f0` | internal | 69 | addon names the client refuses to load |
| `bannedaddons.f1` | internal | 63 | addon version strings |
| `barbershopstyle.f0` | no-display | 1,051 | legacy table: the barber shop reads ChrCustomization only (C_BarberShop.GetAvailableCustomizations) |
| `battlemasterlist.f0` | names | 10 | battleground names |
| `battlemasterlist.f2` | no-display | 4 | PvP UI descriptions; blizzard_pvpui.toc excludes camelot |
| `battlemasterlist.f3` | no-display | 5 | PvP UI descriptions; blizzard_pvpui.toc excludes camelot |
| `battlepaycurrency.f0` | internal | 54 | currency codes (USD) |
| `battlepaycurrency.f1` | internal | 42 | price formats ($%s) |
| `battlepaycurrency.f2` | internal | 42 | price formats |
| `battlepaycurrency.f3` | no-display | 41 | blizzard_catalogshop.toc and blizzard_storeui.toc declare UseSecureEnvironment: 1 |
| `broadcasttext.f0` | surface:ui:BroadcastText | 12 | Text_lang: the archive's rows (cinematic subtitles) |
| `cfg_categories.f0` | internal | 100 | realm list categories (glue screen) |
| `cfg_datacenterlocality.f0` | internal | 9 | data center names |
| `cfg_regions.f0` | internal | 244 | region codes |
| `cfg_regions.f1` | internal | 14 | region names (DEV, Alpha) |
| `characterserviceinfo.f0` | no-display | 9 | character services, glue screens (blizzard_glueparent characterservices*.lua); blizzard_classtrial is standard-only |
| `characterserviceinfo.f1` | no-display | 9 | character services, glue screens |
| `characterserviceinfo.f2` | no-display | 5 | character services, glue screens |
| `chartitles.f0` | names | 41 | player titles (Bloodsail Admiral %s), names |
| `chartitles.f1` | names | 41 | player titles, female form |
| `chatchannels.f0` | names | 19 | channel names (General - %s); UI/Channels.lua keeps channel names English |
| `chatchannels.f1` | names | 19 | channel names (Trade) |
| `chatprofanity.f0` | internal | 3,748 | profanity filter list |
| `chrclasses.f0` | names | 9 | class names |
| `chrclasses.f1` | internal | 9 | class tokens (WARRIOR) |
| `chrclasses.f2` | names | 9 | class names |
| `chrclasses.f4` | internal | 9 | pet tokens (PET) |
| `chrclasses.f5` | no-display | 9 | character create class descriptions (blizzard_charactercreate, AllowLoad: Glue) |
| `chrclasses.f8` | names | 9 | class names, female form |
| `chrclasses.f9` | names | 9 | class names, male form |
| `chrcustomization.f0` | no-display | 76 | no reader; option labels come from ChrCustomizationOption |
| `chrcustomizationcategory.f0` | surface:ui:CustomizationCategory | 62 | CategoryName_lang |
| `chrcustomizationchoice.f0` | surface:ui:CustomizationChoice | 5,333 | Name_lang |
| `chrcustomizationoption.f0` | surface:ui:CustomizationOption | 1,170 | Name_lang |
| `chrcustomizationreq.f0` | surface:ui:CustomizationSource | 13 | ReqSource_lang |
| `chrraceracialability.f0` | internal | 40 | developer names (Human - Active - Will to Survive) |
| `chrraceracialability.f1` | no-display | 40 | character create racial ability text (blizzard_charactercreate, AllowLoad: Glue) |
| `chrraceracialability.f2` | no-display | 40 | character create racial ability text (blizzard_charactercreate, AllowLoad: Glue) |
| `chrraces.f0` | internal | 58 | two-letter race codes (Hu) |
| `chrraces.f1` | names | 58 | race names |
| `chrraces.f10` | no-display | 34 | character create race descriptions (blizzard_charactercreate, AllowLoad: Glue) |
| `chrraces.f11` | names | 26 | race kind names (Elf) |
| `chrraces.f13` | internal | 26 | lower-case race kind tokens |
| `chrraces.f2` | names | 58 | race names |
| `chrraces.f3` | names | 9 | race names |
| `chrraces.f4` | internal | 58 | lower-case race tokens for file names (human) |
| `chrraces.f5` | internal | 9 | lower-case race tokens |
| `chrraces.f6` | names | 35 | race names |
| `chrraces.f8` | internal | 26 | lower-case race tokens (sin'dorei) |
| `chrspecialization.f0` | names | 10 | specialization names |
| `chrspecialization.f1` | names | 10 | specialization names |
| `chrspecialization.f2` | internal | 1 | a developer string (I'm a pet!) |
| `clientsettings.f0` | internal | 5 | setting names (CMAA2) |
| `collectablesourceinfo.f0` | internal | 1,278 | developer labels (Item Appearance: (63286) - ...) |
| `collectablesourcevendorsparse.*` | internal | 0 | a secondary-key sparse table the reader cannot open; its name and siblings (collectablesourceinfo) hold developer labels only |
| `configurationwarning.f0` | no-display | 8 | login screen hardware warnings (glue) |
| `covenant.f0` | internal | 2 | [DNT] rows (do not translate) |
| `covenant.f1` | internal | 2 | [DNT] |
| `creature.f0` | names | 179 | companion and creature names |
| `creature.f2` | names | 3 | a creature title (Lord of Terror) |
| `creaturefamily.f0` | names | 27 | pet family names (docs/research/2026-09-26-client-table-text.md) |
| `creaturetype.f0` | surface:ui:CreatureType | 13 | Name_lang |
| `criteriatree.f0` | surface:ui:CriteriaText | 5,590 | Description_lang: achievement and Legacy criteria (the achievements' own trees) |
| `currencycategory.f0` | surface:ui:CurrencyCategory | 6 | Name_lang |
| `currencytypes.f0` | names | 9 | Name_lang: currency names (Honor Points, Darkmoon Prize Ticket) |
| `currencytypes.f1` | surface:ui:CurrencyDescription | 8 | Description_lang |
| `datatagxrecord.f0` | internal | 210 | tag tokens (HouseDecor) |
| `difficulty.f0` | surface:ui:Difficulty | 22 | Name_lang |
| `dungeonencounter.f0` | names | 342 | boss names |
| `emotes.f0` | internal | 120 | animation tokens (ONESHOT_TALK) |
| `emotestext.f0` | internal | 255 | slash tokens (AGREE) |
| `emotestextdata.f0` | surface:ui:EmoteText | 1,334 | Text_lang |
| `exhaustion.f0` | surface:ui:RestState | 5 | Name_lang (the XXX developer rows never listed) |
| `exhaustion.f1` | internal | 4 | GlobalStrings keys (COMBATLOG_XPGAIN_EXHAUSTION1) |
| `faction.f0` | names | 253 | Name_lang |
| `faction.f1` | surface:ui:FactionDescription | 59 | Description_lang |
| `factiongroup.f0` | names | 4 | Player, Alliance, Horde, Monster |
| `factiongroup.f1` | names | 2 | Alliance, Horde |
| `friendshipreputation.f0` | names | 1 | Rank Points: the PvP rank currency's name |
| `friendshipreputation.f1` | surface:ui:FriendshipGain | 1 | StandingModified_lang: You gain %d Rank Points. |
| `gamemode.f0` | internal | 5 | mode tokens (wfhc, standard) |
| `gameobjects.f0` | names | 1,415 | object names (Old Coast Road) |
| `gametips.f0` | no-display | 72 | loading screen tips are drawn by the client, not by a Lua frame an addon can reach (only the showLoadingScreenTips CVar, blizzard_settingsdefinitions_frame/camelot/interfaceoverrides.lua:63) |
| `globalcolor.f0` | internal | 336 | colour constant names |
| `globalstrings.f0` | internal | 27,349 | BaseTag: the key, not shown |
| `globalstrings.f1` | surface:ui:GlobalStrings | 27,307 | TagText_lang, inventoried key by key in pipeline/ui_inventory.txt (ui_keys.txt or ui_exclusions.txt) |
| `gmsurveyanswers.f0` | no-display | 83 | no GM survey frame (blizzard_wowsurveyui/blizzard_wowsurveyui.lua:12) |
| `gmsurveyquestions.f0` | no-display | 25 | no GM survey frame; surveys open on the web (blizzard_wowsurveyui/blizzard_wowsurveyui.lua:12) |
| `groupfinderactivity.f0` | surface:ui:LfgActivity | 109 | FullName_lang (dungeon names stay English; the curated list keeps the rest) |
| `groupfinderactivity.f1` | covered-by:groupfinderactivity.f0 | 109 | ShortName_lang: the same dungeon names, shortened |
| `groupfinderactivitygrp.f0` | surface:ui:LfgActivityGroup | 7 | Name_lang |
| `groupfindercategory.f0` | surface:ui:LfgCategory | 5 | Name_lang |
| `holidaydescriptions.f0` | surface:ui:HolidayDescription | 17 | Description_lang |
| `holidaynames.f0` | names | 16 | Name_lang: event names (Darkmoon Faire) |
| `itembagfamily.f0` | no-display | 24 | Lua reads only the family number (C_Container.GetContainerNumFreeSlots); no reader prints the name |
| `itemclass.f0` | no-display | 17 | the camelot auction data (blizzard_auctionhouseui/camelot/blizzard_auctiondata.lua) uses GlobalStrings categories; the class-only branch (shared/blizzard_auctiondata.lua:89-90) is never reached |
| `itemlimitcategory.f0` | names | 30 | item names (Signet Ring of the Bronze Dragonflight) |
| `itemnamedescription.f0` | surface:ui:ItemNameDescription | 92 | Description_lang |
| `itempetfood.f0` | surface:ui:PetFood | 8 | Name_lang: pet diet words |
| `itemsearchname.f0` | covered-by:itemsparse.f0 | 10,839 | item names again, for the search index; the names in itemsparse.f4 stay English and this table carries nothing else |
| `itemset.f0` | names | 536 | item set names (The Gladiator) |
| `itemsparse.f0` | surface:item.description | 4,842 | Description_lang |
| `itemsparse.f1` | empty | 0 | Display3_lang |
| `itemsparse.f2` | empty | 0 | Display2_lang |
| `itemsparse.f3` | empty | 0 | Display1_lang |
| `itemsparse.f4` | names | 23,720 | Display_lang: item names |
| `itemsubclass.f0` | surface:ui:ItemSubClass | 100 | DisplayName_lang |
| `itemsubclass.f1` | surface:ui:ItemSubClassName | 36 | VerboseName_lang |
| `itemsubclassmask.f0` | surface:ui:ItemSubClassMask | 3 | Name_lang (Requires Melee Weapon) |
| `languages.f0` | names | 15 | language names (Orcish) |
| `languagewords.f0` | internal | 1,583 | the made-up words other-faction speech is scrambled into |
| `lfgdungeons.f0` | names | 71 | dungeon names |
| `lightskybox.f0` | internal | 26 | model file paths |
| `liquidtype.f0` | internal | 53 | liquid type names (Water, Ocean) used by tools |
| `locale.f0` | internal | 13 | locale names for the glue screen language list |
| `locktype.f0` | surface:ui:LockTypeName | 23 | Name_lang: the lock action (Pick Lock, Disarm Trap); the gathering skills (Herbalism, Mining, Fishing) are names and left out |
| `locktype.f1` | surface:ui:LockTypeResource | 23 | ResourceName_lang: what the lock opens (Locked Items, Herbs) |
| `locktype.f2` | surface:ui:LockTypeVerb | 19 | Verb_lang: the action verb (Pick, Gather) |
| `locktype.f3` | internal | 3 | tokens (PickLock, GatherHerbs) |
| `mailtemplate.f0` | surface:ui:MailBody | 111 | Body_lang: NPC mail bodies |
| `manifestinterfacedata.f0` | internal | 134,289 | interface file folders |
| `manifestinterfacedata.f1` | internal | 134,289 | interface file names |
| `map.f0` | internal | 71 | Directory: map folder tokens |
| `map.f1` | names | 71 | MapName_lang: continent and instance names |
| `map.f2` | no-display | 6 | battleground short descriptions read only by blizzard_pvpui, which camelot does not load |
| `map.f3` | no-display | 6 | battleground long descriptions read only by blizzard_pvpui, which camelot does not load |
| `map.f4` | no-display | 1 | battleground objective title read only by blizzard_pvpui (the queue status shows the long description, map.f5) |
| `map.f5` | surface:ui:PvpLongDescription | 1 | PvpLongDescription_lang: the battleground queue subtitle |
| `mapdifficulty.f0` | surface:ui:InstanceEntryMessage | 21 | Message_lang: the error when entering an instance under its level |
| `mapdifficultyxcondition.f0` | surface:ui:InstanceEntryFailure | 139 | FailureDescription_lang |
| `mount.f0` | names | 141 | mount names |
| `namegen.f0` | internal | 2,741 | random name generator syllables |
| `namesprofanity.f0` | internal | 6,595 | name filter list |
| `namesreserved.f0` | internal | 2,559 | reserved name list |
| `namesreservedlocale.f0` | internal | 2 | reserved name patterns |
| `pagetextmaterial.f0` | internal | 6 | page background material names |
| `paperdollitemframe.f0` | internal | 48 | frame names (HeadSlot) |
| `petloyalty.f0` | surface:ui:PetLoyalty | 8 | Name_lang |
| `playercondition.f0` | surface:ui:PlayerConditionFailure | 97 | Failure_description_lang: a requirement line (Requires Frostwolf Clan - Exalted); faction names inside stay English |
| `powerdisplay.f0` | internal | 5 | GlobalStrings keys (POWER_TYPE_MANA) |
| `powertype.f0` | internal | 6 | power tokens (MANA) |
| `powertype.f1` | internal | 6 | GlobalStrings keys (MANA_COST) |
| `pvpscoreboardcolumnheader.f0` | surface:ui:PvpColumn | 3 | Name_lang |
| `pvpscoreboardcolumnheader.f1` | surface:ui:PvpColumnTooltip | 3 | Tooltip_lang |
| `pvpscoreboardcolumnheader.f2` | covered-by:pvpscoreboardcolumnheader.f0 | 3 | the same three header names (Flag Captures, Bases Assaulted) |
| `pvpstat.f0` | covered-by:pvpscoreboardcolumnheader.f0 | 3 | the same stat names as the scoreboard headers |
| `questfeedbackeffect.f0` | internal | 34 | effect names (openhandglow) |
| `questinfo.f0` | surface:ui:QuestTag | 7 | InfoName_lang: quest type tags (Elite, Dungeon) |
| `questline.f0` | names | 3 | quest line names, quest titles |
| `questsort.f0` | surface:ui:QuestSort | 39 | SortName_lang |
| `renownrewards.f0` | surface:ui:RenownRewardName | 21 | Name_lang (reward item names stay English) |
| `renownrewards.f1` | surface:ui:RenownRewardDescription | 22 | Description_lang |
| `renownrewards.f2` | surface:ui:RenownRewardToast | 22 | ToastDescription_lang |
| `resistances.f0` | covered-by:globalstrings.f1 | 7 | all 7 school names are GlobalStrings text (Physical, Holy, ...) |
| `rolodextype.f0` | surface:ui:RecentAllyType | 21 | Description_lang: the Recent Allies tab (shown on Forever, in game 1.60.1.70170) |
| `rolodextype.f1` | surface:ui:RecentAllyInteraction | 19 | the most recent interaction (Traded, Whispered) |
| `scenescriptglobaltext.f0` | internal | 29 | script names |
| `scenescriptglobaltext.f1` | internal | 29 | Lua source |
| `scenescriptpackage.f0` | internal | 9 | script package names |
| `scenescripttext.f0` | internal | 147 | script names |
| `scenescripttext.f1` | internal | 145 | Lua source |
| `screeneffect.f0` | internal | 77 | effect names (Ghost Screen Effect) |
| `screenlocation.f0` | internal | 12 | position names (Center) |
| `servermessages.f0` | surface:ui:ServerMessage | 15 | Text_lang: server notices in chat ([SERVER] Shutdown in %s); the bare %s row and the DEBUG row are left out |
| `sharedstring.f0` | surface:ui:SharedString | 37 | String_lang: talent requirement lines (profession names stay English) |
| `skillline.f0` | names | 154 | DisplayName_lang: skill and profession names |
| `skillline.f2` | surface:ui:SkillLineDescription | 56 | Description_lang |
| `skilllinecategory.f0` | surface:ui:SkillCategory | 9 | Name_lang |
| `soundemitters.f0` | internal | 1,786 | sound emitter names |
| `soundmixgroup.f0` | internal | 210 | sound mix group names |
| `soundmixgroup.f1` | internal | 210 | sound mix group names |
| `soundproviderpreferences.f0` | internal | 41 | sound test names |
| `spammessages.f0` | internal | 137 | spam filter patterns |
| `spell.f0` | surface:ui:SpellSubtext | 4,749 | NameSubtext_lang: Racial Passive and the like; Rank N stays English |
| `spell.f1` | surface:spell.description | 17,602 | Description_lang |
| `spell.f2` | surface:spell.aura | 7,753 | AuraDescription_lang |
| `spellcategory.f0` | internal | 264 | developer category names (Direct Damage - Spell); no Forever display site (docs/research/2026-09-26-client-table-text.md) |
| `spelldescriptionvariables.f0` | internal | 43 | formulas ($power=${...}) |
| `spelldiminish.f0` | no-display | 11 | stored, never printed (blizzard_spelldiminishui/blizzard_spelldiminishuitemplates.lua:21-22; arena frames show icons) |
| `spelldispeltype.f0` | surface:ui:DispelType | 11 | Name_lang |
| `spelldispeltype.f1` | internal | 4 | InternalName: the same four words, upper-case tokens for code |
| `spellflyout.f0` | surface:ui:FlyoutName | 19 | Name_lang: a spellbook flyout's name (Portal, Summon Demon) |
| `spellflyout.f1` | surface:ui:FlyoutDescription | 19 | Description_lang: the flyout's tooltip description |
| `spellfocusobject.f0` | names | 243 | object names a recipe or spell needs (Anvil, Forge, Ambermill Leyline Focus); names stay English |
| `spellitemenchantment.f0` | surface:ui:SpellItemEnchantment | 2,215 | Name_lang: enchant lines on item tooltips |
| `spellkeyboundoverride.f0` | internal | 1 | a key token (JUMP) |
| `spellmechanic.f0` | internal | 36 | lower-case mechanic names (charmed, dazed); no Forever display site (docs/research/2026-09-26-client-table-text.md) |
| `spellmissilemotion.f0` | internal | 66 | missile motion names |
| `spellname.f0` | names | 31,731 | Name_lang: spell names |
| `spelloverridename.f0` | names | 1 | one spell name |
| `spellrange.f0` | no-display | 58 | in game on 1.60.1.70170, Wrath (SpellRange 4 "Medium Range", 30 yards) shows SPELL_RANGE "30 yd range", already Japanese; melee spells use MELEE_RANGE |
| `spellrange.f1` | no-display | 58 | the short range names (Medium); not printed, as spellrange.f0 |
| `spellscript.f0` | internal | 1 | script name |
| `spellscript.f1` | internal | 1 | Lua source |
| `spellscript.f2` | internal | 1 | author name of a script |
| `spellshapeshiftform.f0` | names | 20 | form names (Cat Form), spell names |
| `talenttab.f0` | names | 27 | talent tree names (Fire, Frost) |
| `talenttab.f1` | internal | 27 | background file tokens (MageFire) |
| `taxinodes.f0` | names | 100 | flight point names |
| `terraintype.f0` | internal | 23 | terrain names for footstep sounds |
| `terraintypesounds.f0` | internal | 20 | terrain names for footstep sounds |
| `totemcategory.f0` | names | 28 | totem and tool item names (Earth Totem) |
| `toy.f0` | no-display | 1 | in game on 1.60.1.70170, ToggleCollectionsJournal(COLLECTIONS_JOURNAL_TAB_INDEX_TOYS) opens Appearances with one tab (Items); there is no Toy Box |
| `tradeskillcategory.f0` | surface:ui:TradeSkillCategory | 216 | Name_lang: recipe list headers (profession names stay English) |
| `traitcost.f0` | no-display | 10 | talent costs print CurrencyTypes text (blizzard_sharedtalentui/blizzard_sharedtalentframe.lua:1837-1849), not TraitCost |
| `traitcurrencysource.f0` | no-display | 186 | only C_ProfSpecs.GetSourceTextForPath reads it (blizzard_professions/blizzard_professionsspecializationstemplates.lua:121); camelot's profession frame has no specialization page |
| `traitdefinition.f0` | internal | 1 | one numeric override string (16972) |
| `transmogoutfitentry.f1` | names | 3 | outfit names the player gives (Outfit 1) |
| `transmogoutfitslotinfo.f0` | internal | 15 | slot tokens (HEADSLOT) |
| `transmogoutfitslotoption.f0` | surface:ui:TransmogSlotOption | 42 | Name_lang: the outfit window's slot options (One Handed Weapon, Cloth) |
| `transmogset.f0` | names | 7 | set names |
| `transmogsetgroup.f0` | names | 2 | set names |
| `transmogsituation.f0` | surface:ui:TransmogSituation | 30 | Name_lang: the transmog outfit window's situation options |
| `transmogsituationtrigger.f0` | surface:ui:TransmogTrigger | 7 | Name_lang: the outfit window's situation groups |
| `transmogsituationtrigger.f1` | surface:ui:TransmogTriggerDescription | 5 | Description_lang: the situation group's help text |
| `uicamera.f0` | internal | 380 | camera names |
| `uicameratype.f0` | internal | 10 | camera type names |
| `uieventtoast.f0` | covered-by:globalstrings.f1 | 2 | Level %d, Rank %d are GlobalStrings text |
| `uieventtoast.f1` | covered-by:globalstrings.f1 | 2 | You've Reached is GlobalStrings text |
| `uieventtoast.f3` | surface:ui:EventToastText | 2 | SubIcon_lang |
| `uimap.f0` | names | 60 | map names |
| `uimodelsceneactor.f0` | internal | 1,008 | actor names |
| `uimodelscenecamera.f0` | internal | 302 | camera names |
| `uitextureatlaselement.f0` | internal | 20,741 | atlas names |
| `uitextureatlasmember.f0` | internal | 20,545 | atlas names |
| `uitexturekit.f0` | internal | 850 | texture kit names |
| `uiwidgetstringsource.f0` | surface:ui:WidgetText | 101 | Value_lang |
| `uiwidgetvistypedatareq.f0` | internal | 515 | developer labels |
| `uiwidgetvisualization.f0` | internal | 648 | developer labels |
| `vignette.f0` | names | 2 | creature names |
| `virtualattachment.f0` | internal | 1 | a developer label |
| `voiceoverpriority.f0` | internal | 19 | developer labels |
| `wbaccesscontrollist.f0` | internal | 172 | URL patterns |
| `wdb-creaturecache.*` | names | 13 | creature names and their titles (<Innkeeper>); UI/TooltipUnit.lua leaves line 1 and title lines as the client wrote them |
| `wdb-gameobjectcache.*` | names | 10 | object names |
| `wdb-npccache.*` | surface:gossip.text | 0 | NPC dialogue; gossip English comes from VMaNGOS and the in-game collector (docs/systems/collector.md) |
| `wdb-pagetextcache.*` | surface:book.text | 0 | book and letter pages; English from VMaNGOS and the collector |
| `wdb-petitioncache.*` | internal | 0 | player-written guild charter names and text, never game text |
| `wdb-questcache.*` | surface:quest.* | 2,406 | quest text, objectives and area text, plus each conditional description and completion log line keyed like NPC dialogue; the whole server set is harvested by the quest scan (docs/operations/beta-day-harvest.md) |
| `wmoareatable.f0` | names | 7,660 | area names inside buildings |
| `worldstateexpression.f0` | internal | 3,968 | encoded expressions |
| `zoneintromusictable.f0` | internal | 54 | music names |
| `zonelight.f0` | internal | 19 | light names |
| `zonemusic.f0` | internal | 164 | music names |

## Word cards (readings with meanings)

| Type | Lines that can carry a word list | With one | Done | Stale | Words | With a meaning |
|---|---|---|---|---|---|---|
| quest | 18,669 | 18,669 | 100.0% | 177 | 297,737 | 100.0% |
| gossip | 10,814 | 10,814 | 100.0% | 0 | 103,440 | 100.0% |
| ui | 15,140 | 15,140 | 100.0% | 0 | 46,158 | 100.0% |
| book | 1,167 | 1,167 | 100.0% | 0 | 39,571 | 100.0% |

Item, spell, objective and area text take no word cards; HTML book pages
and lines holding a `|` escape are not counted.
