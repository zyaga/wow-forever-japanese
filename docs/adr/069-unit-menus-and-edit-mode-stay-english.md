# ADR-069: The unit right-click menus and Edit Mode stay as the client writes them

- **Status:** Accepted
- **Date:** 2026-11-05
- **Related:** [ADR-058](058-text-blizzard-measures-on-a-protected-path-stays-untouched.md) (text Blizzard measures on a protected path) · [Client limits](../architecture/client-limits.md) · [Diagnostics log](../systems/diagnostics.md) · [ADR-031](031-objective-lines-menus-and-helptips.md) (menus) · [ADR-038](038-menus-callouts-and-composite-forms.md) · [ADR-030](030-every-window-the-forever-client-loads.md) (every window)

## Context

On launch day, Forever 1.60.1.70790, the addon's problem log recorded three kinds of block under this addon's name.
Each entry carries the stack of the blocked call; the taint watch ([Diagnostics](../systems/diagnostics.md#the-taint-watch))
recorded the tainted fields and writers around them.

1. **A unit right-click menu in combat.** Right-clicking a party frame in combat logged
   `ADDON_ACTION_BLOCKED CheckInteractDistance()`. The stack: `PartyMemberFrame.lua:412` → `UnitPopupShared.lua:109`
   → `Menu.lua` → `MenuTemplates.lua:112` `ButtonFinalInitializer` → `description:IsEnabled()` →
   `UnitPopupSharedUtils.lua:203`.
   `UI/Menus` added its own function with `AddInitializer` to every element of a tagged menu, the unit menus
   included (their keys were in `UI/MenusUnit`). The menu calls an element's initializers and then
   `ButtonFinalInitializer` in one pass (`menutemplates.lua:105–112`). Once the addon's initializer has run, the rest
   of that pass is tainted. That includes `IsEnabled`, whose unit-popup predicate calls `CheckInteractDistance`,
   protected in combat (`unitpopupsharedutils.lua:195–205`). No text the addon writes is involved: running inside the
   pass is enough.
2. **Leaving Edit Mode.** Leaving Edit Mode, out of combat, logged `ADDON_ACTION_FORBIDDEN ClearTarget()` five
   times. The stack: `EditModeSystemTemplates.lua:1205` `onClickHandler` → `CheckHideAndLockEditMode` →
   `HideUIPanel` → `OnEditModeExit` → `EditModeFrameReset` → `ResetTargetAndFocus` → `EditModeManager.lua:2013`.
   The taint scan after each first block named `EditModeManagerFrame.AccountSettings.expanded` as tainted by this
   addon. The taint watch caught Edit Mode's own handlers running tainted twice, the system dialog's Quick Keybind
   button `onClickHandler` and `OnEditModeExit`, and both then wrote `showAllButtons` on every multi-bar and
   `snappedToFrame` on the bottom bars. `UI/EditMode` wrote Japanese into the manager window, its account settings,
   the system settings dialog, the layout dialogs and the HUD selection overlays, and Edit Mode lays those frames out
   by measuring that text (`SetExpandedState` → `LayoutSettings` / `EditModeManagerFrame:Layout`,
   `editmodemanager.lua:2931–2945`; the system dialog's `UpdateDialog` → `Layout`). This is the ADR-058 pattern: text
   the addon wrote, measured by Blizzard on a path that ends in a protected call.
3. **A tracked quest title clicked in combat.** Clicking a quest title in the objective tracker in combat logged
   `ADDON_ACTION_BLOCKED Button:SetPassThroughButtons()` twice. The stack: `ObjectiveTrackerBlock.lua:388`
   `OnHeaderClick` → `QuestMapFrame_OpenToQuestDetails` → `ShowUIPanel(WorldMapFrame)` → the quest pins'
   `AcquirePin` → `MapCanvas_DataProviderBase.lua:290/300`. Before it, `ObjectiveTrackerFrame.topModulePadding` turned
   tainted three times, each right after a `QUEST_LOG_UPDATE`. Its writer's stack starts at `DirtiableMixin`'s
   `dirtyCallback`, run by `RunNextFrame` from `MarkDirty` (`mixinutil.lua:341–352`): a whole tracker update runs
   tainted when `MarkDirty` is called by tainted code, and the pooled blocks it fills keep that taint for a later
   click. The log does not show who called `MarkDirty`.

## Decision

1. **The unit right-click menus stay as the client writes them.** `UI/Menus` registers no `Menu.ModifyMenu` callback
   for any unit popup tag (`MENU_UNIT_*`), so no addon initializer runs in a unit menu. `UI/MenusUnit` and its key
   lists are gone. The keys stay in `pipeline/ui_keys.txt`: other surfaces may still show words such as Target or
   Inspect. Every other tagged menu keeps its callback; none of their predicates calls a protected function.
2. **Edit Mode stays as the client writes it.** Nothing of this addon writes into, or hooks, any Edit Mode frame:
   the manager window, its account settings, the system settings dialog, the layout dialogs, the HUD selection
   overlays (the cooldown viewers' "Essential Cooldowns" style labels included), the layout menu
   (`MENU_EDIT_MODE_MANAGER`) and Edit Mode's setting dropdowns. `UI/EditMode` is gone.
3. **The tracker is traced before it is changed.** The taint watch logs a `write` entry,
   `ObjectiveTrackerFrame.dirty`, with the caller's stack whenever `MarkDirty` leaves the `dirty` flag tainted. The
   fix follows the caller that entry names. The decision for the tracker is pending until then.
4. **A static test keeps both out.** `tests/python/test_protected_paths.py` fails when any shipped Lua outside
   `UI/TaintWatch` names a unit menu tag, `WFJ.MenusUnit` or an Edit Mode frame (comments aside), or when the TOC
   loads `UI/EditMode.lua` or `UI/MenusUnit.lua`. `UI/TaintWatch` only reads, so its scan roots may name Edit Mode.

## Consequences

- The player now sees the client's English in every unit right-click menu (on a portrait, a party or raid frame, a
  name in chat, a friend or recent ally, a Communities or guild member, the chat roster, the PvP scoreboard): its
  entries, the raid-target submenu, the loot and role entries, the whisper hover. Holding the reveal key changes
  nothing there.
- Edit Mode is English: the manager window and its checkboxes, a HUD element's "Click to edit" label and system
  name, a system's settings and their dropdowns, the layout menu and the New Layout, Rename and Import dialogs, and
  the four cooldown viewers' selection labels. Its first-open callouts stay Japanese: they are HelpTip frames that
  `UI/HelpTips` writes, not Edit Mode frames.
- Getting either back would mean drawing the addon's own text over Blizzard's instead of writing into it or running
  inside its pass. That needs its own in-game proof with the taint watch before it ships. Nothing is deferred: no
  ticket plans it.
- The tracker block is not fixed by this record. Its cause is being traced with the new `write` entry; the fix and
  its reason are added here once the trace names the caller.
