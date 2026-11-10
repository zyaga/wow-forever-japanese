# ADR-077: The quest windows are never re-measured from addon code

- **Status:** Accepted
- **Date:** 2026-11-10
- **Deciders:** the maintainer
- **Related:** [ADR-009](009-surfaces-post-hook-the-writer.md) (the refit) · [ADR-058](058-text-blizzard-measures-on-a-protected-path-stays-untouched.md) · [ADR-069](069-unit-menus-and-edit-mode-stay-english.md) (the tracker title click) · [Client limits](../architecture/client-limits.md) · [Diagnostics](../systems/diagnostics.md#tracing-a-blocked-action)

## Context

On Forever 1.60.1.70862 a player sharing a quest with the group in combat, from the objective tracker's right-click menu, got the "action blocked" message with this addon named. The problem log held the block and its stack: `QuestLogPushQuest()` from `QuestUtil.ShareQuest` (`QuestUtils.lua:358`), called by the menu's Share entry (`Blizzard_QuestObjectiveTracker.lua:115`) through the menu's `Pick` (`Menu.lua:934`). The same session logged the world map's quest pins refused 381 times in combat (`SetPassThroughButtons`, `MapCanvas_DataProviderBase.lua:290/300`), the tracker's `topModulePadding` written tainted 100 times, and, at the right-click, the clicked block's `id` and `parentModule` already tainted. The session before it logged `WorldMapFrame.mapID` written tainted at `QuestMapFrame.lua:1101` and `QuestMapFrame.DetailsFrame.questID` at `:919` and `:1182`. Both block scans listed the details pane's scroll bar fields (`scrollPercentage`, `visibleExtentPercentage`, `panExtentPercentage`) and `RewardsFrameContainer.isFixedHeight` as tainted by this addon.

The addon wrote those scroll bar fields itself. After writing Japanese into the quest log's details pane, the quest popup or the quest window, each surface's refit called the panel scroll frame's `UpdateScrollChildRect()` ([ADR-009](009-surfaces-post-hook-the-writer.md)). Called from addon code, that runs the scroll frame's range scripts and callbacks synchronously under the addon's taint: the scroll bar's `SetVisibleExtentPercentage` and `SetPanExtentPercentage`, `QuestLogQuestDetailsMixin:AdjustRewardsFrameContainer` and `QuestMapFrame_AdjustPathButtons` (`questmapframe.lua:466–468, 965–968, 1015–1040`).

From there the client's own code carries it:

1. The next `QuestMapFrame_ShowQuestDetails` calls `ScrollBar:ScrollToBegin()` (`questmapframe.lua:1055`), which reads `visibleExtentPercentage` (`scrollbar.lua:143–145, 173–176, 219–220`). The rest of that call runs tainted: it sets the map (`SetMapID`, `:1101`) and the return map.
2. The map's quest pins compare the map id before their protected call, so they are refused in combat.
3. Once the quest map runs tainted, `DetailsFrame.questID` is written tainted. The tracker reads it on every quest update (`QuestMapFrame_GetFocusedQuestID`, `blizzard_questobjectivetracker.lua:296`), so its blocks are rebuilt tainted, and the tainted `topModulePadding` keeps every later tracker update tainted until a reload.
4. A right-click on a tracker title reads the tainted block and builds the menu tainted; its Share calls `QuestLogPushQuest`, which the client refuses in combat with this addon named.

## Decision

1. **The quest surfaces have no scroll refit.** `UI/QuestMap` (the details pane and the popup) and `UI/QuestFrame` (the detail, progress, reward and greeting panels) write their Japanese and never call `UpdateScrollChildRect`. The quest greeting's title buttons keep their own height refit, a `SetHeight` on the button, which runs no Blizzard Lua.
2. **The client keeps those ranges itself.** Blizzard's own quest window and quest popup never call `UpdateScrollChildRect` after `QuestInfo_Display` (`questframe.lua:132, 581`; `questmapframe.lua:2696`), and a long English text still scrolls in them. The details pane re-measures itself in `SetRewardsHeight` right after its `QuestInfo_Display` calls, after this addon's hook has written the Japanese (`questmapframe.lua:1050–1073, 1011`).
3. **A static test keeps it out.** `tests/python/test_protected_paths.py` fails when shipped Lua calls `UpdateScrollChildRect` outside `UI/ItemText.lua` and `UI/Tutorial.lua`.

## Rationale

- Calling a Blizzard frame's method that fires its scripts runs Blizzard's code under this addon's taint, the same way calling `QuestMapFrame_OpenToQuestDetails` did ([client limits](../architecture/client-limits.md)). The fields those scripts write keep the taint for the next pass that reads them, which can be minutes later and in combat.
- Removing the call removes the first tainted write in the chain; everything after it in the log is the client's own code reading that write. Nothing on the tracker, the quest list or the menus needs to change.
- The book window and the tutorial popup keep their call: each sizes its own scroll child from the range in the same step (the book window's `SetHeight(range + 30)`, the client's own pattern; the tutorial's fixed 1×1 child), and neither scroll frame feeds the quest map, the tracker or a protected call.

## Consequences

- Sharing a quest from the tracker's menu, and the world map's quest pins, are no longer refused under this addon's name. Sharing in combat is still not allowed by the game itself.
- Holding the reveal key over a long quest text changes its length; the scroll range follows on the client's next layout pass instead of at once [likely: the client's own quest window relies on the same upkeep for English; a long Japanese quest text scrolling to its end in game confirms it].
- A session that already ran tainted stays tainted until a reload: the fix stops new taint, it does not clean old.
- The taint watch keeps the writer checks that traced this (`QuestMapFrame.DetailsFrame.questID`, `WorldMapFrame.mapID`, `ObjectiveTrackerFrame.topModulePadding`, the clicked tracker block). A normal solo session shows any of them turning tainted again, with no group needed.

## Alternatives considered

- **Leave the tracker in English.** The tracker's blocks were the last link, but the log shows them tainted by the quest map, not by the tracker's own text. Taking the tracker's Japanese away would not have stopped the map's quest pins being refused.
- **Clean the tainted fields.** Anything this addon writes is tainted too; only the client's own code can write a field back clean.
- **Delay the refit (`C_Timer.After`).** The timer callback is addon code: the scripts would still run tainted.
