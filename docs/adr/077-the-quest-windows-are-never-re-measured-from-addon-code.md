# ADR-077: The quest windows are never re-measured from addon code

- **Status:** Accepted
- **Date:** 2026-11-10
- **Deciders:** the maintainer
- **Related:** [ADR-009](009-surfaces-post-hook-the-writer.md) (the refit) · [ADR-058](058-text-blizzard-measures-on-a-protected-path-stays-untouched.md) · [ADR-069](069-unit-menus-and-edit-mode-stay-english.md) (the tracker title click) · [Client limits](../architecture/client-limits.md) · [Diagnostics](../systems/diagnostics.md#tracing-a-blocked-action)

## Context

On Forever 1.60.1.70862 a player sharing a quest with the group in combat, from the objective tracker's right-click menu, got the "action blocked" message with this addon named. The problem log held the block and its stack: `QuestLogPushQuest()` from `QuestUtil.ShareQuest` (`QuestUtils.lua:358`), called by the menu's Share entry (`Blizzard_QuestObjectiveTracker.lua:115`) through the menu's `Pick` (`Menu.lua:934`). The same session logged the world map's quest pins refused 381 times in combat (`SetPassThroughButtons`, `MapCanvas_DataProviderBase.lua:290/300`), the tracker's `topModulePadding` written tainted 100 times, and, at the right-click, the clicked block's `id` and `parentModule` already tainted. The session before it logged `WorldMapFrame.mapID` written tainted at `QuestMapFrame.lua:1101` and `QuestMapFrame.DetailsFrame.questID` tainted after the calls at `:919` and `:1182` (the writer check names the line that called `QuestMapFrame_ShowQuestDetails`; the assignment is at `:1047`). The first block scan listed the details pane's scroll bar fields (`scrollPercentage`, `visibleExtentPercentage`, `panExtentPercentage`) as tainted by this addon; both scans listed `RewardsFrameContainer.isFixedHeight` (the second printed only 200 of its fields). The first scan also listed `QuestScrollFrame.Contents.poiSelectedButton`, which only `QuestLogQuests_Update` writes.

What is traced: those fields were tainted, and the blocks and writes above followed. What is inferred [likely]: that this addon's own refit wrote the scroll bar fields first. No logged stack shows the write itself, because the first write stacks of the session were pushed out of the log. The inference: after writing Japanese into the quest log's details pane, the quest popup or the quest window, each surface's refit called the panel scroll frame's `UpdateScrollChildRect()` ([ADR-009](009-surfaces-post-hook-the-writer.md)). Called from addon code, that runs the scroll frame's range scripts and callbacks synchronously under the addon's taint: the scroll bar's `SetVisibleExtentPercentage` and `SetPanExtentPercentage`, `QuestLogQuestDetailsMixin:AdjustRewardsFrameContainer` and `QuestMapFrame_AdjustPathButtons` (`questmapframe.lua:466–468, 965–968, 1015–1040`).

From there the client's own code would carry it:

1. The next `QuestMapFrame_ShowQuestDetails` calls `ScrollBar:ScrollToBegin()` (`questmapframe.lua:1055`), which reads `visibleExtentPercentage` (`scrollbar.lua:143–145, 173–176, 219–220`). The rest of that call runs tainted: it sets the map (`SetMapID`, `:1101`) and the return map.
2. The map's quest pins are acquired from the quest data provider after the map id is set, and their protected `SetPassThroughButtons` is refused in combat once that pass runs tainted [likely; the block's stack runs `QuestMapFrame_CloseQuestDetails` → `ClearFocusedQuestID` → `QuestDataProvider` → `AcquirePin`].
3. Once the quest map runs tainted, `DetailsFrame.questID` is written tainted. The tracker reads it on every quest update (`QuestMapFrame_GetFocusedQuestID`, `blizzard_questobjectivetracker.lua:296`), so its blocks are rebuilt tainted, and the tainted `topModulePadding` keeps every later tracker update tainted until a reload.
4. A right-click on a tracker title reads the tainted block and builds the menu tainted; its Share calls `QuestLogPushQuest`, which the client refuses in combat with this addon named.

## Decision

1. **The quest surfaces have no scroll refit.** `UI/QuestMap` (the details pane and the popup) and `UI/QuestFrame` (the detail, progress, reward and greeting panels) write their Japanese and never call `UpdateScrollChildRect`. The quest greeting's title buttons keep their own height refit, a `SetHeight` on the button, which runs no Blizzard Lua.
2. **The client keeps those ranges itself.** Blizzard's own quest window and quest popup never call `UpdateScrollChildRect` after `QuestInfo_Display` (`questframe.lua:132, 581`; `questmapframe.lua:2696`), and a long English text still scrolls in them. The details pane re-measures itself in `SetRewardsHeight` right after its `QuestInfo_Display` calls, after this addon's hook has written the Japanese (`questmapframe.lua:1050–1075, 1011`).
3. **A static test keeps it out.** `tests/python/test_protected_paths.py` fails when shipped Lua calls `UpdateScrollChildRect` outside `UI/ItemText.lua` and `UI/Tutorial.lua`.

## Rationale

- Calling a Blizzard frame's method that fires its scripts runs Blizzard's code under this addon's taint, the same way calling `QuestMapFrame_OpenToQuestDetails` did ([client limits](../architecture/client-limits.md)). The fields those scripts write keep the taint for the next pass that reads them, which can be minutes later and in combat.
- Removing the call removes the one place this addon runs the quest map's scroll code itself, and the first write in the inferred chain; everything after it in the log is the client's own code. Nothing on the tracker, the quest list or the menus changes [likely: confirmed by the in-game pass below].
- The book window and the tutorial popup keep their call: each sizes its own scroll child from the range in the same step (the book window's `SetHeight(range + 30)`, the client's own pattern; the tutorial's fixed 1×1 child), and neither scroll frame feeds the quest map or the tracker. The book window's own pass can still run tainted after a refit whose range comes out unchanged (its `ScrollToBegin`, `itemtextframe.lua:134`); nothing protected is known on that pass, and the taint watch would show it.

## Consequences

- Sharing a quest from the tracker's menu, and the world map's quest pins, are expected to stop being refused under this addon's name [likely]. Sharing in combat is still not allowed by the game itself.
- **In-game pass:** after a reload, open a quest's details in the quest log out of combat, then play on; the taint watch (`/wfj taint` or the next block scan) shows `QuestMapFrame.DetailsFrame.ScrollFrame.ScrollBar.scrollPercentage`, `.visibleExtentPercentage`, `.panExtentPercentage`, `RewardsFrameContainer.isFixedHeight` and `QuestScrollFrame.Contents.poiSelectedButton` clean, no `write` entry for `ObjectiveTrackerFrame.topModulePadding`, `WorldMapFrame.mapID` or `QuestMapFrame.DetailsFrame.questID`, and no `SetPassThroughButtons` or `QuestLogPushQuest` block in combat. If any of them turns tainted again, one of the open explanations below holds.
- Holding the reveal key over a long quest text changes its length; the scroll range follows on the client's next layout pass instead of at once [likely: the client's own quest window relies on the same upkeep for English; a long Japanese quest text scrolling to its end in game confirms it].
- A session that already ran tainted stays tainted until a reload: the fix stops new taint, it does not clean old.
- The block-time taint scan walks the quest popup's and the quest window's scroll frames too (`UI/TaintWatch` `SCAN_ROOTS`): their scroll bars were reached before only through the lookups this change removed.
- The taint watch keeps the writer checks that traced this (`QuestMapFrame.DetailsFrame.questID`, `WorldMapFrame.mapID`, `ObjectiveTrackerFrame.topModulePadding`, the clicked tracker block). A normal solo session shows any of them turning tainted again, with no group needed.

## Open explanations

- **The client's own re-measure.** `SetRewardsHeight` calls `UpdateScrollChildRect` itself (`questmapframe.lua:1011`, called at `:1075`), over a scroll child whose height comes from text this addon has just written (`Contents` is a fixed 298×199 frame, `questmapframe.xml:812`). Whether a range the client computes from addon-written text reaches its scripts tainted is not known. If it does, this change does not end the chain, and the details pane's text would need the treatment of [ADR-058](058-text-blizzard-measures-on-a-protected-path-stays-untouched.md).
- **The quest list.** `poiSelectedButton` tainted means a `QuestLogQuests_Update` ran tainted. That fits the chain (`QuestMapFrame_UpdateAll` reads the tainted `DetailsFrame.questID` before it updates the list, `questmapframe.lua:917–921`), but the list's own Japanese ([ADR-058](058-text-blizzard-measures-on-a-protected-path-stays-untouched.md#update-the-quest-list-beside-the-world-map)) is not ruled out by this log.

## Alternatives considered

- **Leave the tracker in English.** The tracker's blocks were the last link, but they read the quest map's tainted quest id on every update (`blizzard_questobjectivetracker.lua:296`), and the tracker's own writes are text and sizes that run no Blizzard Lua. Taking the tracker's Japanese away would not have stopped the map's quest pins being refused.
- **Clean the tainted fields.** Anything this addon writes is tainted too; only the client's own code can write a field back clean.
- **Delay the refit (`C_Timer.After`).** The timer callback is addon code: the scripts would still run tainted.
