# Research: what Forever's `camelot` game type loads in place of each gated-away surface

- **Date:** 2026-09-19
- **Question:** For every surface the addon hooks that is absent on Forever, which client files does `camelot` load
  instead, who writes the text, and by what name or path can the addon reach it?
- **Client:** World of Warcraft: Forever beta. TOCs were extracted read-only at build **1.60.1.69913** with
  `wfj.dev.client_ui` (the read-only ADR-021 path): 347 Blizzard TOCs. The `.lua` / `.xml` extract is the one from
  the first Forever survey (build 1.60.1.69893 era, not stamped). Every `Blizzard_UIPanels_Game.toc` line cited below reads the same,
  at the same line number, in both builds.
- **Citations:** `path:line`, with paths relative to the extract's `interface/addons/` root, lowercased as extracted.
  "TOC" means that addon's own `.toc`. The extract and the TOC set are not committed; short quotations from them are, and the TOC excerpt is
  [uipanels-game-toc-gating.md](2026-09-17-forever-client-surface/uipanels-game-toc-gating.md).

This corrects three first readings in [the 2026-09-17 survey](2026-09-17-forever-client-differences.md), whose text now
states the corrected findings: that a file whose `[AllowLoadGameType]` list does not name `camelot` never loads, that the quest window
runs the `vanilla` code, and that `camelot` does not explain mail, honor and friends.

## Options

How one addon build can serve both clients once the camelot frames are known:

| Option | Pros | Cons |
|---|---|---|
| A. Keep one file per surface; Classic Era `Compat` candidates first, camelot names or dotted paths after; install only the hooks that resolve | One file per surface (ADR-009); Classic Era path untouched; `/wfj debug` already reports what did not resolve | Each surface file carries two hook shapes |
| B. New surface file where camelot shows a different feature, not a renamed frame | Keeps a Classic surface from being bent around an unrelated window | More files registered in Main's init order |
| C. Separate Forever build | No branching in Lua | Two packages, two TOCs; the first Forever pass already showed one build works (ADR-025) |

The chosen design takes A everywhere and B for PvP rank, the quest map and Communities.

## Findings

### 1. `camelot` is a member of the `mainline` family

The Forever TOCs use two placeholders. On this client `[Family]` expands to the `Mainline\` folder and `[Game]` to the
`Camelot\` folder. The evidence, all quoted verbatim:

```
blizzard_uipanels_game/blizzard_uipanels_game.toc
44:[Family]\CharacterFrame.lua				[AllowLoadGameType mainline] [ExcludeLoadGameType camelot]
45:[Game]\CharacterFrame.lua				[AllowLoadGameType camelot]
173:[Family]\QuestMapFrameOverrides.lua		[AllowLoadGameType mainline] [ExcludeLoadGameType camelot]
174:[Game]\QuestMapFrameOverrides.lua		[AllowLoadGameType camelot]
```

- An `[ExcludeLoadGameType camelot]` on a line already gated `[AllowLoadGameType mainline]` has meaning only if
  `camelot` matches `mainline`. The same pairing appears for `PaperDollFrame`, `ReputationFrame`,
  `QuestFrameTemplates`, `BankFrame` and `QuestMapFrameUtils` (the same TOC, lines 52–53, 61/69, 83–84, 140–141,
  177–178).
- `blizzard_uipanels_game/` in the extract has folders `camelot`, `cata`, `mainline`, `shared`, `standard` and
  `vanilla`, and **no `classic`**. `blizzard_friendsframe/` ships only `camelot/` and `mainline/`.
- Whole addons are gated the same way. `blizzard_pvpui/blizzard_pvpui.toc:8–9`:

  ```
  ## AllowLoadGameType: mainline, mists
  ## ExcludeLoadGameType: camelot
  ```

- The live probe agrees. `QuestInfo_Display` answered `function` while the vanilla quest-log writer
  `QuestLog_UpdateQuestDetails` answered absent
  ([probe-answers-run2.lua](2026-09-17-forever-client-surface/probe-answers-run2.lua)). The only `QuestInfo.lua` a
  mainline-family client can load is `[Family]\QuestInfo.lua [AllowLoadGameType mainline]`
  (`blizzard_uipanels_game.toc:100`); lines 101–102 are `vanilla, tbc` and `wrath, cata, mists`.

**The load rule, as the rest of this doc applies it:** a TOC line loads on Forever when its `AllowLoadGameType` is
absent or names `camelot` or `mainline`, and its `ExcludeLoadGameType` names neither. A line gated only `classic`,
`vanilla`, `tbc` and so on does not load.

**Consequence: Forever runs the retail (mainline) UI with camelot overrides.** The classic `QuestLogFrame`,
`SpellBookFrame`, `SkillFrame`, `HonorFrame`, `MailFrame` and `FriendsFrame` in `Blizzard_UIPanels_Game` are all gated
`classic` or `vanilla, tbc, wrath`, so none of them load:

```
blizzard_uipanels_game/blizzard_uipanels_game.toc
32:[Family]\SpellBookFrame.lua				[AllowLoadGameType classic]
38:[Family]\SkillFrame.lua					[AllowLoadGameType classic]
75:Vanilla\HonorFrame.lua					[AllowLoadGameType vanilla, tbc, wrath]
77:[Family]\HonorFrame_Shared.lua			[AllowLoadGameType classic]
96:[Game]\QuestLogFrame.lua				[AllowLoadGameType vanilla, tbc, wrath]
151:[Family]\FriendsFrame.lua				[AllowLoadGameType classic]
207:[Family]\MailFrame.lua					[AllowLoadGameType classic]
```

The quest **window** also runs mainline code, not vanilla:

```
88:[Family]\QuestFrame.lua
89:Vanilla\QuestFrame.lua					[AllowLoadGameType vanilla]
91:[Family]\QuestFrame.xml					[AllowLoadGameType mainline]
100:[Family]\QuestInfo.lua					[AllowLoadGameType mainline]
```

Line 88 has no conditional, so it loads, but `[Family]` there is `Mainline\`. The addon's quest-window hooks still land
because the mainline `QuestInfo_Display` keeps the same name and signature (`blizzard_uipanels_game/mainline/questinfo.lua:28`).

### 2. Quest details, quest list and tracker

**Loaded on camelot** (`blizzard_uipanels_game.toc:173–178`, quoted in finding 1 for 173–174):

```
175:[Family]\QuestMapFrame.lua				[AllowLoadGameType mainline]
176:[Family]\QuestMapFrame.xml				[AllowLoadGameType mainline]
177:[Family]\QuestMapFrameUtils.lua			[AllowLoadGameType mainline] [ExcludeLoadGameType camelot]
178:[Game]\QuestMapFrameUtils.lua			[AllowLoadGameType camelot]
```

So: `blizzard_uipanels_game/mainline/questmapframe.lua|xml`, `mainline/questinfo.lua|xml`,
`camelot/questmapframeoverrides.lua` and `camelot/questmapframeutils.lua`. The tracker is
`blizzard_objectivetracker`, loaded unconditionally apart from one camelot override
(`blizzard_objectivetracker/blizzard_objectivetracker.toc:35–36`):

```
35:Blizzard_QuestObjectiveTracker.lua
36:[Game]/Blizzard_QuestObjectiveTrackerOverride.lua [AllowLoadGameType camelot]
```

**Frames.** `QuestMapFrame` (`mainline/questmapframe.xml:423`), details scroll `QuestMapDetailsScrollFrame` with child
`.Contents` (xml:788, 799), details frame `QuestMapFrame.QuestsFrame.DetailsFrame` (no global; lua:465, xml:648), quest
list `QuestScrollFrame` (xml:490), tracker popup `QuestLogPopupDetailFrame` (xml:308) with
`QuestLogPopupDetailFrameScrollFrame` (:321) `.ScrollChild` (:332). The map panel sits inside `WorldMapFrame`
(`QuestLogOwnerMixin`, `blizzard_worldmap/blizzard_worldmap.xml:4`).

**Details writer.** `QuestMapFrame_ShowQuestDetails(questID)` (`mainline/questmapframe.lua:1044–1110`) sets
`C_QuestLog.SetSelectedQuest` (:1046) and calls:

- `QuestInfo_Display(QUEST_TEMPLATE_MAP_DETAILS, detailsFrame.ScrollFrame.Contents)` (:1050)
- `QuestInfo_Display(QUEST_TEMPLATE_MAP_REWARDS, …RewardsFrame, nil, nil, true)` (:1051)

It is reached by global name from `QuestMapFrame_UpdateAll` (:909–919), `QuestMapLogTitleButton_OnClick` (:2498),
`QuestMapFrame_OpenToQuestDetails` (:1175–1178, used by the tracker at
`blizzard_objectivetracker/blizzard_questobjectivetracker.lua:68, 103`) and `QuestMapFrame_ToggleShowDestination` (:952).
The popup is a third caller: `QuestLogPopupDetailMixin:Update` → `QuestInfo_Display(QUEST_TEMPLATE_LOG,
self.ScrollFrame.ScrollChild)` (questmapframe.lua:2688–2689).

`QUEST_TEMPLATE_MAP_DETAILS` has `questLog = true` (`mainline/questinfo.lua:1161–1176`). The addon's existing
`QuestInfo_Display` hook returns early for any `template.questLog`, so it ignores both the map and the popup today.

**Shared widgets.** The quest window (`mainline/questframe.lua:129, 566`), the map and the popup all write the **same
global FontStrings**, which `QuestInfo_Display` re-parents (`mainline/questinfo.lua:99–110`):

| field | FontString | English written | source |
|---|---|---|---|
| title | `QuestInfoTitleHeader` (questinfo.xml:728) | `QuestUtils_DecorateQuestText(id, C_QuestLog.GetTitleForQuestID(id), true)`; `QUEST_TITLE_FORMAT_FAILED` when failed | questinfo.lua:137–161 |
| description | `QuestInfoDescriptionText` (xml:749) | 1st return of `GetQuestLogQuestText()` | questinfo.lua:182–192 |
| objectives | `QuestInfoObjectivesText` (xml:734) | 2nd return of `GetQuestLogQuestText()` | questinfo.lua:388–397 |

The quest id is `C_QuestLog.GetSelectedQuest()` (questinfo.lua:124–126). `GetQuestLogQuestText` answered `function` on
the live client; `GetQuestLogTitle`, `GetQuestLogSelection` and `GetQuestLogSelectedID` are absent
([probe-answers-run2.lua](2026-09-17-forever-client-surface/probe-answers-run2.lua)).

`QuestUtils_DecorateQuestText` (`blizzard_framexmlutil/mainline/questutils.lua:728–760`) prepends an atlas link for
replayable or disabled quests, dungeon and raid tags and non-normal classifications. For those quests the header does
not equal `GetTitleForQuestID`.

`SurfaceState.release` restores `rec.en` without checking who owns the widget now (`addon/WoWForeverJapanese/Core/SurfaceState.lua:109–146`).
With three surfaces on one set of FontStrings, a surface that releases on hide could write its old English over
another surface's Japanese. Hence the design rule that each surface forgets the other surfaces' records before it shows.

**Quest list.** `QuestLogQuests_Update()` (questmapframe.lua:2104) rebuilds the list. Rows are written by the **local**
`QuestLogQuests_AddQuestButton` (:1808), which cannot be hooked:

- title `button.Text:SetText(QuestUtils_DecorateQuestText(questID, title, false, false, true, true))` (:1828), where
  `title` carries camelot's `"[" .. level .. ("+" if elite) .. "] "` prefix (:1631–1634; the prefix is defined in
  `camelot/questmapframeoverrides.lua:13–16`) and possibly a `"[n] "` party count (:1639);
- `button.TagText` `(Elite)` (:1833–1836; `camelot/questmapframeoverrides.lua:19–21`);
- rows carry `button.questID`, `.questLogIndex`, `.info` (:1814–1816); pools `QuestScrollFrame.titleFramePool` and
  `.objectiveFramePool` (:1228–1233).

camelot hides the map tabs (`camelot/questmapframeoverrides.lua:4–6`) and redefines `QuestLogQuests_ShowQuestCount`
(`camelot/questmapframeutils.lua:7–18`) over the mainline stub (questmapframe.lua:2167).

**Tracker.** `QuestObjectiveTrackerMixin:UpdateSingle(quest)` (`blizzard_objectivetracker/blizzard_questobjectivetracker.lua:289`)
writes the header with `block:SetHeader(SetQuestTitleLevelAndDifficultyColor(questID, quest.title))` (:298, :307); the
decoration is an optional `"[lvl] "` and a colour wrap (`blizzard_framexmlutil/mainline/difficultyutil.lua:84–96`).
`block.id` is the quest id (:56). Writes go through `ObjectiveTrackerBlockMixin:SetStringText`
(`blizzard_objectivetracker/blizzard_objectivetrackerblock.lua:134–153`). Module `QuestObjectiveTracker`
(`blizzard_questobjectivetracker.xml:26`), container `ObjectiveTrackerFrame` (`blizzard_objectivetracker.xml:3`). The
only camelot override is `CanShowTimerBar() → false` (`camelot/blizzard_questobjectivetrackeroverride.lua:1–3`).
Objective progress lines come from `GetQuestLogLeaderBoard` (:214–258); the addon shipped no objective data at the time.

**Fixed labels** (global strings): details pane `BACK`, `REWARDS`, `ABANDON_QUEST_ABBREV`, `SHARE_QUEST_ABBREV`,
`TRACK_QUEST_ABBREV` (questmapframe.xml:694, 777, 807, 818, 843), rewritten to `UNTRACK_QUEST_ABBREV` /
`TRACK_QUEST_ABBREV` on every show (questmapframe.lua:1147–1153); `QUEST_DESCRIPTION`, `QUEST_OBJECTIVES`,
`REQUIRED_MONEY` (questinfo.xml:743, 746, 740); list `QUEST_LOG_NO_RESULTS`, `QUEST_LOG_NO_QUESTS` (questmapframe.xml:509,
515), `SEARCH_QUEST_LOG` (lua:1241), `QUEST_LOG_COUNT_TEMPLATE` (`camelot/questmapframeutils.lua:14, 16`); popup buttons
(questmapframe.xml:351, 381, 392, 404).

`QuestFrameCancelButton`, which the addon's quest-window surface declares, is not in the mainline quest XML.

### 3. Spellbook

**Loaded on camelot.** The classic spellbook is gated away (`blizzard_uipanels_game.toc:32–37`). Forever loads the
load-on-demand `Blizzard_PlayerSpells` (`blizzard_playerspells/blizzard_playerspells.toc`):

```
2:## LoadOnDemand: 1
3:## Dependencies: Blizzard_SharedTalentUI, Blizzard_PagedContent, Blizzard_HelpPlate
32:[Game]/SpellBook/Blizzard_SpellBookTemplates.xml	[AllowLoadGameType camelot]
39:SpellBook/Blizzard_SpellBookFrame.lua
41:[Game]/SpellBook/Blizzard_SpellBookFrame.lua	[AllowLoadGameType camelot]
43:Blizzard_PlayerSpellsFrame.lua
44:[Game]/Blizzard_PlayerSpellsFrame.lua			[AllowLoadGameType camelot]
46:[Game]/Blizzard_PlayerSpellsFrame.xml			[AllowLoadGameType camelot]
```

Loader `PlayerSpellsFrame_LoadUI()` (`blizzard_playerspells/blizzard_playerspells_bootstrap.lua:3–5`). The run-2 probe
saw the addon loaded. It does not exist on Classic Era, so waiting for its `ADDON_LOADED` is inert there.

**Frames.** One global host for spellbook **and** talents: `PlayerSpellsFrame`
(`blizzard_playerspells/camelot/blizzard_playerspellsframe.xml:4`), with children by parentKey only: `.SpellBookFrame`
(:51), `.TalentsFrame` (:44), `.SpecFrame` (:33, a stub on camelot). The window tabs are hidden: `IsTabSystemAvailable`
returns false (`camelot/blizzard_playerspellsframe.lua:58–63`).

**Writers.**

| Classic widget → text | camelot equivalent | writer |
|---|---|---|
| `SpellBookTitleText` `SPELLBOOK` | `PlayerSpellsFrame.TitleContainer.TitleText` = `SPELLBOOK` / `TALENTS` / `SPECIALIZATION` / `TALENTS_INSPECT_FORMAT` | `PlayerSpellsFrameMixin:UpdateFrameTitle` (`blizzard_playerspells/blizzard_playerspellsframe.lua:155–171`), called by method lookup from `SetTab` (:190) and `SetInspecting` (:306) |
| `SpellBookPageText` `PAGE_NUMBER` | `.SpellBookFrame.PagedSpellsFrame.PagingControls.PageText` = `PAGE_NUMBER_WITH_MAX` | `PagingControlsMixin:UpdateControls` (`blizzard_pagedcontent/blizzard_pagingcontrols.lua:110–127`) |
| `SpellBookFrameTabButton1/2` | icon tabs, no text; tooltips are skill-line names, `PET`, `TRANSMOGRIFY` | `camelot/spellbook/blizzard_spellbookframe.lua:45–74` |
| `ShowAllSpellRanksCheckboxText` | a Menu checkbox, tag `MENU_SPELL_BOOK_SETTINGS` | `spellbook/blizzard_spellbookframe.lua:191, 205–226`; `camelot/spellbook/blizzard_spellbookframe.lua:9–43` |
| `SpellButtonN` subtext | pooled item `.SubName` | `SpellBookItemMixin:UpdateSubName` (`spellbook/blizzard_spellbookitem.lua:183–201, 295–301`), a late write inside `ContinueWithCancelOnSpellLoad` (:193–199) |
| (new) | item `.RequiredLevel`: `SPELLBOOK_AVAILABLE_AT`, `SPELLBOOK_TRAINABLE`, `BOOSTED_CHAR_SPELL_TEMPLOCK` | `spellbookitem.lua:236–252` |

`SetTitle` writes `self.TitleContainer.TitleText` (`blizzard_sharedxml/portraitframe.lua:3–14`). That FontString is
`name="$parentTitleText"` under an **unnamed** `TitleContainer`
(`blizzard_sharedxml/mainline/shareduipaneltemplates.xml:486–494`), so a global `PlayerSpellsFrameTitleText` is not
established. The dotted path is.

**Refresh.** `OnPagedSpellsUpdate` is registered by function reference (`spellbook/blizzard_spellbookframe.lua:46`), so
an instance hook on it misses the event path. It triggers
`EventRegistry "PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged"` (:91). Displayed items:
`ForEachDisplayedSpell(fn)` (:608–614). Show/hide events at :109 and :127. Registrations by reference capture the
function (`blizzard_sharedxmlbase/callbackregistrant.lua:14–18, 50–60`); `EventRegistry` callbacks run through
`securecallfunction` (`blizzard_sharedxmlbase/callbackregistry.lua:201, 204`).

### 4. Skills

**Loaded on camelot** (`blizzard_uipanels_game.toc`):

```
38:[Family]\SkillFrame.lua					[AllowLoadGameType classic]
71:[Game]\SkillsFrame.lua					[AllowLoadGameType camelot]
72:[Game]\SkillsFrame.xml					[AllowLoadGameType camelot]
```

Not load-on-demand. Frame: global **`SkillsFrame`** (not `SkillFrame`; `blizzard_uipanels_game/camelot/skillsframe.xml:121`),
parent `CharacterFrame`, mixin `SkillsFrameMixin`; children `.ScrollBox` (:123) and `.SkillDetailFrame` (:169,
`CharacterFrameSidePaneTemplate`, `camelot/characterframe.xml:317`).

None of the Classic skills text exists here: no `LEARN_SKILL_TEMPLATE` row, no collapse-all, cancel or unlearn button
(full read of `camelot/skillsframe.lua|xml`). Row and pane titles are skill names (`skillsframe.lua:270, 325, 372`). The
new fixed text:

- `SKILL_DETAIL_SELECT_PROMPT` → `SkillDetailFrame.EmptyText` via `SetEmpty` (`skillsframe.lua:255`;
  `camelot/characterframe.lua:942–951`);
- `WEAPON_SKILL_DETAIL_SAME_LEVEL_HEADER`, `WEAPON_SKILL_DETAIL_BOSS_HEADER` (category rows, `skillsframe.lua:297, 305`);
- `WEAPON_SKILL_DETAIL_SAME_LEVEL[_RANGED]`, `WEAPON_SKILL_DETAIL_BOSS[_RANGED]` (`%s` templates with colour codes,
  `skillsframe.lua:301–315`), in pooled rows `SkillDetailFrame.rowPools` (`characterframe.lua:841–845`).

`SkillsFrameMixin:Update` is called by method lookup (`skillsframe.lua:159, 195`). `SkillDetailFrame.Refresh` is
registered by reference (:226), so a row click (:388) bypasses an instance hook on it; inside it `SetEmpty` and
`LayoutRows` are called by method lookup (`characterframe.lua:943–950`). `CharacterFrameSidePaneMixin` is shared with
other side panes, so hooks must be on the instance.

### 5. Talents

**Loaded on camelot.** The same `Blizzard_PlayerSpells` (`blizzard_playerspells.toc`):

```
9:[Game]/ClassTalents/Blizzard_ClassTalentUtil.lua	[AllowLoadGameType camelot]
23:ClassTalents/Blizzard_ClassTalentsFrame.lua
25:[Game]/ClassTalents/Blizzard_ClassTalentsFrame.lua		[AllowLoadGameType camelot]
27:[Game]/ClassTalents/Blizzard_ClassTalentsFrame.xml		[AllowLoadGameType camelot]
```

The shared tree UI is `blizzard_sharedtalentui/blizzard_sharedtalentui.toc:2, 40`:

```
## LoadOnDemand: 0
[Game]\Blizzard_SharedTalentOverrides.lua [AllowLoadGameType camelot]
```

The classic `Blizzard_TalentUI` has no TOC in the Forever set. camelot's talent binding calls
`PlayerSpellsUtil.ToggleClassTalentOrSpecFrame()` (`blizzard_framexml/bindings_camelot.xml:1223–1225`). `TalentFrame_Update`
exists because `blizzard_framexml.toc:96` loads `[Family]\TalentFrameBase.lua [AllowLoadGameType mainline]`
(`blizzard_framexml/mainline/talentframebase.lua:32`), but nothing in the extract calls it.

**Frame.** `PlayerSpellsFrame.TalentsFrame` (mixin `ClassTalentsFrameMixin`,
`camelot/classtalents/blizzard_classtalentsframe.xml:153`), a `C_Traits` tree.

| Classic → key | camelot | where |
|---|---|---|
| title `TALENTS` | window title via `UpdateFrameTitle` (shared with the spellbook) | finding 3 |
| `UNSPENT_TALENT_POINTS` | `.ClassCurrencyDisplay.UnspentLabel` static `UNSPENT_POINTS` | `camelot/classtalents/blizzard_classtalentsframe.xml:4–36, 382`; `classtalents/blizzard_classtalentsframe.lua:18–26, 776–778` |
| `MASTERY_POINTS_SPENT` | gone: per-tree header is the tree name and a number | `camelot/classtalents/blizzard_classtalentsframe.lua:310–323` |
| `TALENT_SPEC_ACTIVATE` | `.ActiveSpec.ActivateButton` (static); `.ActiveSpec.ActiveLabel` `TALENT_SPEC_ACTIVE` (new) | camelot xml:102, 111, 388 |
| `LEARN` | `.ApplyButton` `TALENT_FRAME_APPLY_BUTTON_TEXT` | camelot xml:438 |
| reset / cancel | an icon dropdown, Menu tag `MENU_CLASS_TALENT_FRAME_RESET`; no cancel button | `classtalents/blizzard_classtalentsframe.lua:81–87`; camelot xml:487, 519 |
| spec tabs | `.TabSystem` tabs `DUAL_SPEC_PRIMARY` / `DUAL_SPEC_SECONDARY` with atlas markup; `TALENT_SPEC_LOCKED` | `camelot/classtalents/blizzard_classtalentsframe.lua:39–49, 124–134, 150–157` |
| talent tooltip | `TalentDisplayMixin:SetTooltipInternal` on `GameTooltip`: `TALENT_BUTTON_TOOLTIP_*`, `TALENT_FRAME_INCREASED_RANKS_TEXT` | `blizzard_sharedtalentui/blizzard_talentdisplay.lua:100–125, 290–305, 370`; `blizzard_talentbuttonspend.lua:84–137` |

`EventRegistry "TalentDisplay.TooltipCreated"` fires after `tooltip:Show()` (`blizzard_talentdisplay.lua:124`). The talent
micro button's unlock level is `Constants.LevelConstsExposed.MIN_TALENT_LEVEL`, lowered by a legacy node
(`blizzard_micromenu/camelot/mainmenubarmicrobuttonsoverrides.lua:6–14`); its value is not in the source.

### 6. Mail

**Why the names are gone.** `blizzard_uipanels_game.toc:207–208` gate the classic mail files `classic`. Forever loads a
separate addon, `blizzard_mailframe/blizzard_mailframe.toc:4–8`:

```
## Dependencies: Blizzard_FriendsFrame
## AllowLoad: Game
## AllowLoadGameType: mainline
MailFrame.lua
MailFrame.xml
```

Not load-on-demand. It is the retail mail frame: `MailFrame inherits="ButtonFrameTemplate" mixin="MailMixin"`
(`blizzard_mailframe/mailframe.xml:276`).

- `InboxTitleText`, `SendMailTitleText`, `OpenMailTitleText` are replaced by the template title.
  `MailFrameTab_OnClick` calls `MailFrame:SetTitle(INBOX)` / `SetTitle(SENDMAIL)` (mailframe.lua:217, 225), and
  OpenMailFrame's inline OnShow calls `SetTitle(OPENMAIL)` (mailframe.xml:1337–1341). Inbox and Send share **one**
  FontString, rewritten on every tab click. Access path: `MailFrame.TitleContainer.TitleText`,
  `OpenMailFrame.TitleContainer.TitleText`.
- `InboxFrame_Update` and `OpenMail_Update` are gone (no such globals in the extract). They are frame methods now,
  `InboxMixin:Update` (mailframe.lua:316) and `OpenMailMixin:Update` (:747), called as `InboxFrame:Update()` /
  `OpenMailFrame:Update()` (lua:147–148, 462, 471, 529, 549, 566, 587; xml:145).
- The page buttons are parentKey-only: `InboxFrame.PrevPageButton` / `.NextPageButton` (xml:394, 419).
- `OpenMailInvoiceBuyMode` is removed (no hits).
- Still present under the same names: `MailFrameTab1/2` (xml:865, 875), `MailItem1..7` (:359–389), `SendMailFrame`
  (:463), `SendMailMoneyText` (:748), `SendMailErrorText` (:470), `OpenAllMail` (:444), the `OpenMailInvoice*` labels
  (:1115–1157) and the Open Mail buttons (:1307–1325).

| text | writer | mailframe line |
|---|---|---|
| title `INBOX` / `SENDMAIL` | `MailFrameTab_OnClick` (global; tab OnClick by name, xml:871, 881) | lua:197–230 |
| title `OPENMAIL` | OpenMailFrame inline OnShow | xml:1337–1341 |
| item expiry + `.tooltip` `TIME_UNTIL_*` | `InboxFrame:Update` | lua:392–403 |
| invoice labels, `AMOUNT_*`, `FUNDS_DELAY` | `OpenMailFrame:Update` | lua:798–861 |
| `TAKE_ATTACHMENTS` / `NO_ATTACHMENTS` | `OpenMailFrame:Update` | lua:974, 978 |
| `DELETE` / `MAIL_RETURN` | `OpenMailFrame:Update` | lua:1045, 1047 |
| `AMOUNT_TO_SEND` / `COD_AMOUNT` | `SendMailRadioButton_OnClick` (global) | lua:1462–1473 |
| `MAIL_COD_ERROR[_COLORBLIND]` | SendMailFrame inline OnShow | xml:850–857 |
| `OPEN_ALL_MAIL_BUTTON[_OPENING]` | `OpenAllMailMixin:StartOpening/StopOpening` | lua:1521–1543 |

`MailFrameTab_OnClick` also exists on Classic Era, so hooking it is harmless there.

### 7. Honor → PvP rank

**Why the names are gone.** Every classic honor file is gated away (`blizzard_uipanels_game.toc:75–80`; lines 75 and 77
are quoted in finding 1), and `Blizzard_PVPUI` excludes camelot (finding 1). The camelot replacement is a different
feature, loaded from the same always-loaded addon:

```
213:[Game]\PVPRankFrame.lua					[AllowLoadGameType camelot]
214:[Game]\PVPRankFrame.xml					[AllowLoadGameType camelot]
```

`PVPRankFrame` (global, parent `CharacterFrame`, `blizzard_uipanels_game/camelot/pvprankframe.xml:3`) is a season rank
panel on a major-faction renown track (a constant in pvprankframe.lua:1, 91). It has no
honorable / dishonorable kill rows and no session / yesterday / week periods. It is the character frame's PvP tab
(`camelot/characterframeconstants.lua:1, 22–25`; tab `CharacterFrameModeTab4`, `CHARACTER_FRAME_TAB_PVP`,
`camelot/characterframe.xml:589–593`). Every name `UI/Honor.lua` declares (`HonorFrame*`, `HonorLevelText`,
`HonorFrame_Update`, `HonorFrame_SetLevel`, …) exists only in unloaded files.

| widget (parentKey path) | text | writer (pvprankframe.lua) |
|---|---|---|
| `PVPRankFrame.SeasonTimerField` | `SEASON_ENDS_IN_TIME` with an unabbreviated two-unit duration | `:UpdateSeasonCountdownTimer` :78–88, on a **1-second ticker** :50–58 |
| `.MainInfoFrame.CurrentSeasonField` | `EXPANSION_SEASON_NAME` formatted with `''` (a leading space) | `:Update` :102 |
| `.MainInfoFrame.CurrentRankField` | `PVP_RANK_0_NAME` or `PVP_RANK_NUMBER_AND_TITLE` (`%s` is the rank title) | `:Update` :107–111 |
| `.MainInfoFrame.CurrentRankProgressField` | `PVP_RANK_CURRENT_PROGRESS` | `:Update` :119 |
| `.DetailFrame` title, subtitle, description, empty text, pooled row labels | `PVP_RANK_DETAIL_UNAVAILABLE`, `PVP_RANK_NUMBER`, `PVP_RANK_SEASON_RANKUP_DESCRIPTION`, `PVP_RANK_SEASON_PROGRESS[_NO_MAX]`, `PVP_RANK_WEEKLY_CAP_INCREASE`, `PVP_RANK_NEXT_REWARD`, `PVP_RANK_REWARDS_VENDOR_HORDE/ALLIANCE` | `PVPRankDetailFrameMixin:Refresh` :132–217, through the side-pane setters (`camelot/characterframe.lua:850–951`) |

All of these keys are in Forever's GlobalStrings. The methods are called as `self:…()` (OnShow :46, OnEvent :74,
ticker :52/56, DetailFrame OnShow :129), so frame-method hooks see them. There is no global writer to hook by name.

### 8. Friends and the who list

**Why the names are gone.** `blizzard_uipanels_game.toc:151–152` gate the classic `FriendsFrame` `classic`. Forever loads
`blizzard_friendsframe/blizzard_friendsframe.toc`:

```
6:## AllowLoadGameType: mainline
15:[Family]\FriendsFrame.lua	[ExcludeLoadGameType camelot]
16:[Game]\FriendsFrame.lua		[AllowLoadGameType camelot]
```

The camelot `FriendsFrame` has **no who panel**: `WhoList_Update` exists only in the excluded
`mainline/friendsframe.lua:1084`, and `ShowWhoPanel` (`camelot/friendsframe.lua:1358`) opens `LFGParentFrame` tab 3. The
who list lives in `blizzard_groupfinder_vanillastyle/blizzard_groupfinder_vanillastyle.toc`:

```
5:## AllowLoadGameType: classic, camelot
6:## LoadOnDemand: 1
28:[Family]\WhoList.lua							[ExcludeLoadGameType classic]
29:[Family]\WhoList.xml							[ExcludeLoadGameType classic]
```

The probe saw it load in session. The frame is `LFGWhoListFrame` (`blizzard_groupfinder_vanillastyle/mainline/wholist.xml:65`,
mixin `LFGWhoListMixin`), a ScrollBox.

- Totals: `LFGWhoListFrame.WhoFrameTotals` (parentKey only, wholist.xml:68), written by
  `LFGWhoListMixin:UpdateWhoList` (wholist.lua:219–239) as `format(WHO_FRAME_TOTAL_TEMPLATE, n) .. "  " ..
  (WHO_FRAME_SHOWN_TEMPLATE or "")`, the same shape as Classic Era; called from OnEvent (:172–175).
- `WhoFrameEditBox` is still a global (wholist.xml:96); its instructions are now `WHO_LIST_SEARCH_INSTRUCTIONS`
  (`blizzard_sharedxml/shared/inputbox/inputboxtemplates.lua:175–177`).
- Rows (pooled `LFGWhoListButtonTemplate`): `.Level` = `LFG_WHO_LEVEL` (wholist.lua:66–67); row tooltip
  `WHO_LIST_LEVEL_TOOLTIP` (:81). The other row fields are names.
- Gone with no replacement: `WhoFrameColumnHeader1/3/4`, `WhoFrameGroupInviteButton`, `WhoFrameAddFriendButton`,
  `WhoFrameWhoButton` (an icon now), `WhoFrameDropdown`.

**The rest of the friends frame changed too.** camelot has three tabs, `FRIENDS = 1`, `RAID = 2`, `QUICK_JOIN = 3`
(`camelot/friendsframe.lua:30–33`), and **no guild tab**, so the addon's `GUILD_TAB = 3` guard now skips the Quick Join
title. Titles go two ways: `FriendsFrame:SetTitle(CONTACTS_LIST_TITLE | CONTACTS_RECENT_ALLIES_TITLE | RECRUIT_A_FRIEND)`
into `TitleContainer.TitleText`, while `RAID` / `QUICK_JOIN` go to `FriendsFrameTitleText` (lua:452–471, xml:402).
`FriendsFrame_UpdateFriendButton(button, elementData)` still exists and is looked up at call time (lua:337–351), so the
existing hook still fires. The ignore list is `FriendsFrame.IgnoreListWindow` (xml:785; title `IGNORE_LIST`, lua:2461).
camelot can host friends inside `SocialUIFrame` when `C_SocialUI.IsSystemEnabled()` (lua:1261;
`blizzard_socialui/blizzard_socialui.toc:5` `## AllowLoadGameType: mainline`).

### 9. Guild → Communities

The classic `GuildFrame` lives in `[Family]\FriendsFrame.xml [AllowLoadGameType classic]` (`blizzard_uipanels_game.toc:152`),
which does not load. The camelot friends frame has no `GuildFrame` and no guild tab (no hits in
`blizzard_friendsframe/camelot/`). `ToggleGuildFrame` on camelot is `blizzard_game/mainline/game.lua:1–25`
(`blizzard_game/blizzard_game.toc:13` `[Family]\Game.lua`, unconditional), which opens `ToggleCommunitiesFrame()` or
`ToggleGuildFinder()`. The `useClassicGuildUI` branch to the classic guild tab exists only in `blizzard_game/classic/game.lua:6–8`, which
does not load on camelot. **On camelot the guild UI is Communities only.**

`blizzard_communities/blizzard_communities.toc` has no addon-level game-type gate and no `LoadOnDemand` line. Its
dependencies include `Blizzard_GuildControlUI` (line 2), which is load-on-demand
(`blizzard_guildcontrolui/blizzard_guildcontrolui.toc:2`). Its one camelot line:

```
61:[Game]/CommunitiesFrameOverrides.lua [AllowLoadGameType camelot]
```

The override is three lines and disables personal achievements. The micro menu depends on Communities for the whole
mainline family (`blizzard_micromenu/blizzard_micromenu.toc:2` `## Dep: Blizzard_Communities [AllowLoadGameType mainline]`).

**Access paths.** `CommunitiesFrame` (`blizzard_communities/communitiesframe.xml:303`) with parentKeys `MemberList` (:467),
`GuildBenefitsFrame` (:536), `GuildDetailsFrame` (:542, also global `CommunitiesFrameGuildDetailsFrame`),
`GuildNameAlertFrame` (:554), `GuildMemberDetailFrame` (:613). Top-level `CommunitiesGuildTextEditFrame` and
`CommunitiesGuildLogFrame` (`guildinfo.xml:289, 384`), `CommunitiesGuildNewsFiltersFrame` (`guildnews.xml:384`),
`GuildControlUI` (`blizzard_guildcontrolui/guildcontrolui.xml:402`).

Writers equivalent to what `UI/Guild.lua` covers on Classic Era:

- member detail: `CommunitiesGuildMemberDetailMixin:DisplayMember` (`guildroster.lua:91`): `FRIENDS_LEVEL_TEMPLATE`,
  `GUILD_ONLINE_LABEL`, `GUILD_NOTE_EDITLABEL`, `GUILD_OFFICERNOTE_EDITLABEL`; static labels `ZONE_COLON`, `RANK_COLON`,
  `LAST_ONLINE_COLON`, `NOTE_COLON`, `OFFICER_NOTE_COLON`, `REMOVE`, `GROUP_INVITE` (`guildroster.xml:19–98`);
- member count: `CommunitiesMemberListMixin:UpdateMemberCount` (`communitiesmemberlist.lua:395–405`,
  `COMMUNITIES_MEMBER_LIST_MEMBER_COUNT_FORMAT`);
- roster columns `COMMUNITIES_ROSTER_COLUMN_TITLE_*` in a Lua table (`communitiesmemberlist.lua:41–184`); row presence
  text in `CommunitiesMemberListEntryMixin:RefreshExpandedColumns` (:1235–1332) on pooled rows.

**Size (rough grep counts, not an inventory).** The guild core (communitiesframe, memberlist, guildroster, guildinfo,
guildnews, guildnamechange, guildperks, guildrewards, guildpreferredplaysettings, `Blizzard_GuildControlUI`) has about
76 static XML text sites and about 58 Lua writer lines with a global string, **~130 sites**. ClubFinder adds ~90, and
streams, settings, the ticket manager and invitations ~60: **~280 in all** across ~15 files and 10+ mixins. Nothing in
`UI/Guild.lua` carries over except its key lists. The re-target scoped guild work to parity with what `UI/Guild.lua`
covered on Classic Era.

### 10. Micro menu, game menu and the performance tooltip

These surfaces load and their hooks land. The gaps are in the button list and in the dictionary.

```
blizzard_micromenu/blizzard_micromenu.toc
6:[Family]\MainMenuBarMicroButtons.lua
7:[Game]\MainMenuBarMicroButtonsOverrides.lua [AllowLoadGameType camelot]
18:[Game]\MainMenuBarMicroMenu.xml [AllowLoadGameType camelot]

blizzard_gamemenu/blizzard_gamemenu.toc
8:Classic\GameMenuFrameOverrides.lua [AllowLoadGameType classic]

blizzard_performancebar/blizzard_performancebar.toc
6:PerformanceBar.lua
7:Classic\PerformanceBarOverrides.lua [AllowLoadGameType classic]
```

- **Micro menu.** The addon's button list (`addon/WoWForeverJapanese/UI/MicroMenu.lua:44–46`) names `SocialsMicroButton` and
  `WorldMapMicroButton`, which the mainline menu does not have. It never hooks nine mainline buttons: Profession,
  PlayerSpells, Legacy, Housing, LFD, Collections, EJ, Store and Achievement. Uncovered keys: `PROFESSIONS_BUTTON`,
  `PLAYERSPELLS_BUTTON`, `SPELLBOOK_BUTTON`, `DUNGEONS_BUTTON`, `HOUSING_MICRO_BUTTON`, `ADVENTURE_JOURNAL`,
  `LEGACY_BUTTON`. Stale English: `MAINMENU_BUTTON` ("Main Menu" → "Game Menu"), `HELP_BUTTON`, `LFG_BUTTON`,
  `SPELLBOOK_ABILITIES_BUTTON` and several `NEWBIE_TOOLTIP_*`.
- **Game menu.** The addon's hook on `GameMenuFrame:InitButtons` resolves (`blizzard_gamemenu/shared/gamemenuframe.lua:163`).
  Without the classic override, `GetLogoutText` returns `LOG_OUT` ("Log Out", :284–286), which is not a dictionary key.
  Also uncovered: `GAMEMENU_EXTERNALEVENT` ("Activities") and `GAME_MENU_SHOW_REWARDS` ("Rewards").
- **Performance tooltip.** `performancebar.lua` names the same keys as on Classic Era, but the English changed:
  `MAINMENUBAR_LATENCY_LABEL` "Latency:" → "Latency:\n%.0f ms (home)\n%.0f ms (world)" (the `data/ui` line is
  rejected: its specifiers no longer match) and `NEWBIE_TOOLTIP_LATENCY` is reworded (stale). The only caller is the
  `MainMenuMicroButtonMixin` OnUpdate (`blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:1982–1984`).
  `MainMenuBarPerformanceBarFrame[Button]` do not exist, so the addon's `LATENCY_OWNERS` (`addon/WoWForeverJapanese/UI/MicroMenu.lua:47`)
  resolve to nil and are skipped. `MainMenuMicroButton` is registered, so the tooltip walk runs; the lines stay English
  because their entries are stale or rejected.

### 11. Trainer and raid (TOC only)

The second probe run left both `unknown` because their load-on-demand addon never loaded. Their TOCs load mainline files on camelot:

```
blizzard_trainerui/blizzard_trainerui.toc
2:## LoadOnDemand: 1
6:[Family]\Blizzard_TrainerUI.lua
9:[Family]\Blizzard_TrainerUI_Camelot.lua [AllowLoadGameType camelot]

blizzard_raidui/blizzard_raidui.toc
2:## LoadOnDemand: 1
6:[Family]\Blizzard_RaidUI.lua
7:[Family]\Blizzard_RaidUI.xml			[AllowLoadGameType mainline, vanilla, tbc]
```

Their source was not read for this doc.

### 12. The UI string inventory on camelot

`pipeline/wfj/dev/ui_inventory.py` has a hard-coded Classic Era file map and reads paths case-sensitively
(`(addons / rel).read_text()`, ui_inventory.py:168); the Forever extract is lowercased. A scratch run with a camelot
file map built from the TOC gating above (the counts are measurements from that run, which is not committed):

- **693 distinct inventoried keys** are in neither `ui_keys.txt` nor `ui_exclusions.txt`. **This is a ceiling, not a
  count.** The bare-identifier match also catches generic words in the large mainline files (`NOTE`, `BACK`, `ADD`,
  gamepad narration labels), and many of those will be exclusions. Per surface: questframe 33, questlog 52, gamemenu
  6, tooltip 119, character 161, reputation 15, skills 7, honor 14, spellbook 53, talents 40, trainer 10, gossip 3,
  merchant 12, bank 42, bags 46, mail 12, friends 59, raid 2, help 36. The counts depend on which files each surface
  includes.
- Rows: 1,723 (Classic Era 1,258); 747 added, 282 dropped. 240 keys inventoried on Classic Era sit on no camelot
  surface (`ARMOR_COLON`, `ATTACK_*_COLON`, …).
- **106 new tooltip-family keys.** The pattern families match 645 keys on Forever against 539 on Classic Era, with 0
  gone. All 106 are uncovered (`ITEM_MOD_*_PENETRATION`, `ITEM_COSMETIC`, `ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP`,
  `ESSENCE_COST*`, azerite / corruption lines); many are retail-only exclusion candidates.
- **13 `ui_keys` are absent from Forever's GlobalStrings:** `ARMOR_COLON`, `ATTACK_POWER_COLON`, `ATTACK_SPEED_COLON`,
  `DAMAGE_COLON`, `DEFENSE_COLON`, `HONOR_THISWEEK` and seven `<CLASS>_INTELLECT_TOOLTIP`.
- **79 `ui_keys` have changed English** on Forever (tooltip 25, character 19, help 11, friends 6, …), the same count
  as finding 10 of the 2026-09-17 survey. `data/ui` today: 630 trusted, 38 stale, 32 rejected. Re-drafting the
  changed keys belongs with the Forever English re-pull, not with this re-target.
- Dynamic keys: character gains `DRUID_AGILITY`, `ROGUE_INTELLECT`, `ROGUE_SPIRIT` and `WARRIOR_{AGILITY,INTELLECT,SPIRIT}_TOOLTIP`
  and loses the seven `<CLASS>_INTELLECT_TOOLTIP`; help gains `PET_MODE_DEFENSIVEASSIST`.

Spellbook, skills and talents alone need these keys, none of which the dictionary has today: `PAGE_NUMBER_WITH_MAX`,
`SPECIALIZATION`, `TALENTS_INSPECT_FORMAT`, `TRANSMOGRIFY`, `SPELLBOOK_AVAILABLE_AT`, `SPELLBOOK_TRAINABLE`,
`SKILL_DETAIL_SELECT_PROMPT`, the six `WEAPON_SKILL_DETAIL_*`, `UNSPENT_POINTS`, `TALENT_SPEC_ACTIVE`,
`TALENT_FRAME_APPLY_BUTTON_TEXT`, `DUAL_SPEC_PRIMARY` / `_SECONDARY`, `TALENT_SPEC_LOCKED` and the
`TALENT_BUTTON_TOOLTIP_*` family (`TALENT_BUTTON_TOOLTIP_RANK_FORMAT` is "Rank %s/%s", where the existing
`TOOLTIP_TALENT_RANK` is "Rank %d/%d"). Without them the camelot skills surface has nothing to show.

### 13. Only an in-game check can settle

The source cannot answer these. Each is a question for an in-game pass.

**Quest**
- Whether the world map shows the quest panel at all: it is gated on
  `not C_GameRules.IsGameRuleActive(Enum.GameRule.QuestLogPanelDisabled) and GetCVarBool("questLogOpen")`
  (`blizzard_worldmap/questlogownermixin.lua:190–193`), and how the log opens (`ToggleQuestLog`, questmapframe.lua:2171).
- Whether dungeon- or raid-tagged and classified quests get a decorated header (the title equality check then leaves
  them English), and what the failed form looks like.
- Whether `GetQuestLogQuestText()` with no argument returns the selected quest on this build. Blizzard's code relies on
  it (questinfo.lua:185, 391); the probe only confirmed the function exists.
- Whether the quest window and the map or popup can be open together, and in which order they re-parent the shared
  FontStrings. The popup hides on quest dialog events (`mainline/questframe.lua:43–71`); the map does not.
- Which tracker module renders normal quests (`QuestObjectiveTracker` or `CampaignQuestObjectiveTracker`), and the
  defaults of the quest-level and difficulty-colour CVars.

**Spells**
- Whether `PlayerSpellsFrameTitleText` exists as a global.
- Whether `Blizzard_PlayerSpells` loads before or after the addon at login (`LoadOnDemand.when` handles both orders).
- The talent level gate (level 10 was seen in game; `MIN_TALENT_LEVEL`'s value is not in the source).
- Dual-spec tabs and `ActiveSpec`, which show only with two spec groups (`camelot/classtalents/blizzard_classtalentsframe.lua:107–109, 296–298`).
- The pet book (Hunter / Warlock), the `RequiredLevel` lines, and the page text on a one-page book.

**Social**
- Whether `MailFrameTitleText` exists as a global, and whether Japanese titles fit the `ButtonFrameTemplate` title
  width (`wordwrap=false`).
- Whether the PvP rank system is live on the beta: `C_MajorFactions.GetMajorFactionProgressionInfo(2800)` may be nil, in
  which case `:Update` returns early and the detail pane shows `PVP_RANK_DETAIL_UNAVAILABLE`. Also the leading-space
  season label and the duration format.
- Whether `SocialUIFrame` or `FriendsFrame` is live (`C_SocialUI.IsSystemEnabled()`).
- Whether `Blizzard_Communities` is loaded at login or on demand
  (`C_AddOns.IsAddOnLoaded` / `C_AddOns.IsAddOnLoadOnDemand("Blizzard_Communities")`), and whether `CommunitiesFrame`
  opens for guilds (`C_Club.IsEnabled` / Battle.net gates in `ToggleGuildFrame`). Needs a level-10 character in a guild.
- Whether a hook on a pooled-row mixin (`LFGWhoListButtonMixin:InitButton`, the Communities member rows) reaches rows
  created after it; the alternative is walking the ScrollBox's frames after the writer runs.

## Recommendation

Re-target per option A, with new surface files where camelot shows a different feature (B): `UI/QuestMap.lua` (map
details, popup, list, tracker), `UI/PvPRank.lua`, `UI/Communities.lua`. One `QuestInfo_Display` hook branches on
`parentFrame`, and each branch forgets the other two surfaces' records before it shows. Methods camelot registers by
function reference are reached through `EventRegistry` or through a method they call. The inventory gains a Forever
file map taken from this doc's TOC gating.
[ADR-029](../adr/029-camelot-targets-the-mainline-family.md) records the decisions.

## Related

- [The 2026-09-17 survey](2026-09-17-forever-client-differences.md) (corrected by this doc) and
  [its TOC excerpt](2026-09-17-forever-client-surface/uipanels-game-toc-gating.md)
- [ADR-029: camelot targets the mainline family](../adr/029-camelot-targets-the-mainline-family.md) ·
  [ADR-009: Surfaces post-hook the writer](../adr/009-surfaces-post-hook-the-writer.md) ·
  [ADR-021: Client tables from the local archive](../adr/021-client-tables-from-the-local-archive.md) ·
  [ADR-025: Guarded surface init and a runtime-chosen tooltip hook path](../adr/025-guarded-surface-init-and-runtime-tooltip-path.md)
