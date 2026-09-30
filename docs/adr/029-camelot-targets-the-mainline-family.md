# ADR-029: Forever's `camelot` targets the mainline family; one surface file serves both clients

- **Status:** Accepted. Implemented in `addon/WoWForeverJapanese/UI/QuestMap.lua`,
  `UI/PvPRank.lua`, `UI/Communities.lua`; `UI/QuestFrame.lua` (the branching `QuestInfo_Display` hook, the
  cross-surface forget, `Compat` routing); `UI/SpellBook.lua`, `Talents.lua`, `Skills.lua`, `Mail.lua`, `Friends.lua`,
  `Character.lua`, `Reputation.lua`, `Bank.lua`, `Bags.lua`, `Merchant.lua`, `Trainer.lua`, `Raid.lua`,
  `MicroMenu.lua`, `GameMenu.lua` (camelot candidates); `UI/KeyCapture.lua`, `UI/RevealBinding.lua` (`Compat` routing);
  `UI/HelpTooltip.lua` (`walkAs`); `Core/UIStrings.lua`, `Core/UIStringKeys.lua`; `Main.lua` and the TOC (three surfaces);
  `pipeline/wfj/dev/ui_inventory.py` and `pipeline/wfj/dev/ui_windows.py` (`FOREVER_WINDOWS`), `pipeline/ui_inventory.txt`,
  `pipeline/wfj/dev/client_surface.py`. Not yet verified in game on Forever (the re-target checklist in
  [Testing strategy](../testing/strategy.md)).
- **Date:** 2026-09-19

> Superseded in part by [ADR-034](034-forever-is-the-only-target.md): Classic Era is not a target; "one surface file serves both clients" is replaced by one Forever path per surface (the Era candidates, the Era hooks, `UI/Guild.lua`, `UI/Honor.lua` and `UI/QuestLog.lua` are removed), and the Classic Era UI inventory is gone.

## Context

Forever's interface is gated by a **game type**, `camelot`, and the client's TOCs gate whole files away from it:
the quest log, spellbook, skills, talents and guild frames the addon hooked do not exist there. The first reading
was "a file whose list does not name `camelot` never loads", which left three more gaps unexplained (mail's title
labels, the honor frame's writers, the who-list writer).

The research ([camelot surface re-target](../research/2026-09-19-camelot-surface-retarget.md)) settled both.
**`camelot` is a member of the `mainline` family.** In Forever's TOCs `[Family]` expands to `Mainline\` and `[Game]`
to `Camelot\`; lines such as `[Family]\CharacterFrame.lua [AllowLoadGameType mainline] [ExcludeLoadGameType camelot]`
beside `[Game]\CharacterFrame.lua [AllowLoadGameType camelot]` only make sense if `camelot` matches `mainline`, and
`Blizzard_UIPanels_Game` has no `Classic\` folder on this client. Forever runs the **retail (mainline) UI with camelot
overrides**. That explains the rest too: mail moved into `Blizzard_MailFrame`, honor is replaced by `PVPRankFrame`, and
the who list moved into the load-on-demand `Blizzard_GroupFinder_VanillaStyle`.

Three properties of the mainline UI shape how the addon can reach it:

- **Many frames have no globals.** Children are `parentKey`s (`PlayerSpellsFrame.SpellBookFrame`,
  `SkillsFrame.SkillDetailFrame`), and titles are written by `SetTitle` into an unnamed
  `TitleContainer.TitleText`.
- **Writers are mixin methods, and some are registered by function reference.** A method called as `self:Update()`
  can be post-hooked on the frame. A method registered by reference (`SpellBookFrame.OnPagedSpellsUpdate`,
  `SkillDetailFrame.Refresh`, the bank frame's title callback; the bank title itself stays English)
  captured the function at registration, so a hook on the frame
  never sees that call path.
- **Rows are pooled.** Spell items, skill-detail rows, who rows, roster rows and trainer services are pool or
  ScrollBox frames with no stable index.

And one property of the quest UI is a correctness hazard: the quest window, the quest map's details pane and the
tracker's popup all call `QuestInfo_Display`, which **re-parents the same global FontStrings**
(`QuestInfoTitleHeader`, `QuestInfoObjectivesText`, `QuestInfoDescriptionText`) into whichever of them is showing.
`SurfaceState.release` restores a record's English without asking who owns the widget now, so a surface releasing on
its frame's hide could write its old English over another surface's Japanese.

At the time the addon also had to keep working unchanged on Classic Era, from one addon build (ADR-025).

## Decision

1. **Target the mainline family on Forever.** The addon's working model of Forever is "retail UI with camelot
   overrides", and a TOC line counts as loaded on Forever when its `AllowLoadGameType` is absent or names `camelot`
   or `mainline` and its `ExcludeLoadGameType` names neither. Every re-target, and the Forever UI inventory's file
   map, is read from the TOCs under that rule.

2. **One surface file serves both clients.** Each surface keeps its one file (ADR-009). Its `Compat` candidate lists
   name the Classic Era global first and the camelot name or dotted path after
   (`PlayerSpellsFrame.TitleContainer.TitleText`, which `Compat.lookup` walks to any depth). A hook is installed
   only for a writer that resolves, so each client gets the hooks that exist on it and the Classic Era path is
   untouched. Where camelot's widgets and writers are only reachable through a different frame, the camelot branch
   installs only when the Classic name is absent (mail titles, friends' who list, raid's Forever-only buttons).

3. **Hook the shape the writer has.**
   - `hooksecurefunc(globalName)` for a global function (`MailFrameTab_OnClick`, `ClassTrainerFrame_InitServiceButton`,
     `ContainerFrame_GenerateFrame`).
   - `hooksecurefunc(frame, "Method")` for a mixin method called by method lookup (`PVPRankFrame:Update`,
     `InboxFrame:Update`, `PlayerSpellsFrame:UpdateFrameTitle`, the tab and checkbox instances).
   - For a method registered **by reference**, hook what it calls by method lookup (`SetEmpty` / `LayoutRows` on the
     skills and reputation side panes), or subscribe to the `EventRegistry` event it
     fires (`PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged`, `TalentDisplay.TooltipCreated`).
   - Menu entries whose initializer closes over the English get an initializer of our own through
     `Menu.ModifyMenu` (the spellbook settings menu).
   - Load-on-demand addons (`Blizzard_PlayerSpells`, `Blizzard_GroupFinder_VanillaStyle`, and `Blizzard_Communities`
     whichever way it loads) go through the existing `UI/LoadOnDemand.lua` wait.

4. **Walk pools after the writer; never address a row by position.** A surface walks the frame's active pool (or
   follows the ScrollBox with `ScrollUtil.AddInitializedFrameCallback`) after the writer runs. A pooled row's record
   is keyed by a stable id where the client provides one (`questID`, `block.id`, the spell slot) and otherwise by the
   row widget itself.

5. **Everything by type, never by truthiness.** A resolved name is used only as the type the code needs: a function
   is called only when `type(fn) == "function"`, a widget is read and written only when its `GetText` and `SetText`
   are functions, a frame is hooked only when `HookScript` is a function. A client that moves a name into a namespace
   table therefore degrades to untouched English instead of raising "attempt to call a table". `UI/QuestFrame.lua`,
   `UI/KeyCapture.lua` and `UI/RevealBinding.lua` route every client API through `Compat` on the same rule;
   `RevealBinding` reads `unavailable` when the binding API is missing, and the polled modifier still works.

6. **The shared QuestInfo FontStrings forget across surfaces.** `UI/QuestFrame.lua` keeps the one
   `QuestInfo_Display` hook and branches on the call: a `template.questLog` call goes to `UI/QuestMap.lua`
   (the map's details pane or the tracker popup), anything else to the quest window's panels. The quest map keeps
   its records on the shared QuestInfo widgets (the three fields, the QuestInfo labels, and the popup's
   `QuestInfoRewardsFrame` words) on sub-surfaces of their own, `questmap.info` and `questmap.popup.info`
   (`QuestMap.QUESTINFO`); each pane's own labels (Back, Abandon / Share / Track, …) stay on `questmap` /
   `questmap.popup`. Showing on any of the three first **forgets** the other two's shared records: the other
   `questmap.*.info` sub-surface (`Render.forget` → `SurfaceState.dropAll`, which removes the records and writes
   English back only where a widget still shows that surface's own applied text; the client's writer has just
   rewritten them, so in practice nothing is written), and, through `QuestFrame.forgetQuestInfo`, only the shared
   keys of `questframe.detail` / `.reward` (title, description, objectives, completion, the QuestInfo labels, the
   reward labels), never the quest window's own Accept / Decline / Complete buttons. A pane's own buttons are
   never forgotten by another surface. A later release then restores only what its own surface still owns. Each
   surface releases on its own frame's `OnHide`.

7. **Guild parity, not all of Communities.** On camelot the guild UI is `Blizzard_Communities` only.
   `UI/Communities.lua` covers what `UI/Guild.lua` covers on Classic Era: the roster's column headers, the member
   count, the member detail pane, the guild info and news labels. ClubFinder, chat streams, community settings,
   invitations and tickets are separate work.

8. **A new `pvprank` surface, not a bent `Honor.lua`.** Camelot's `PVPRankFrame` is a season rank panel on a
   renown track, a different feature from the Classic honor frame. It is its own file, `UI/PvPRank.lua`;
   `UI/Honor.lua` still serves Classic Era.

9. **The UI inventory is per client** (superseded by [ADR-034](034-forever-is-the-only-target.md) §8: one inventory,
   Forever's, in `pipeline/ui_inventory.txt`). `wfj.dev.ui_inventory` took `--client era|forever`. `era` wrote
   `pipeline/ui_inventory.txt`; `forever` read a Forever UI extract through a casefold path index (the extract is
   lowercased), used the camelot file map `FOREVER_WINDOWS`, and wrote a second, committed inventory.
   `test_ui_coverage.py` held `ui_keys.txt` and `ui_exclusions.txt` to both.

## Consequences

- One build serves both clients, as ADR-025 set out. Each surface file carries two hook shapes, which is the cost of
  not shipping a second package.
- `/wfj debug`'s unresolved list is longer by design: Classic Era names read unresolved on Forever and camelot names
  on Classic Era. It is grouped by surface, so the expected misses are readable as such.
- Three new surfaces join Main's guarded init order (`questmap`, `pvprank`, `communities`). A surface broken in game
  is disabled by removing its one `step`, with nothing else touched.
- The dictionary grows, because the camelot files show words Classic Era never did.
- Whether a pooled-row hook reaches rows created after it, whether `TitleContainer.TitleText` also has a global
  name, and which tracker module renders normal quests are **not established from source**. Every hook degrades to
  English if the in-game answer differs; the Forever re-target checklist names each check.
- Objective progress lines in the tracker and quest list are a separate surface ([ADR-031](031-objective-lines-menus-and-helptips.md)).

## Alternatives considered

- **A separate Forever build.** No per-client branching in Lua, but two packages and two TOCs to release, and ADR-025
  already showed one build loads on both.
- **A generic client-adapter layer.** `Compat` candidate lists already carry the per-client difference; an adapter
  would be an abstraction with one implementation per surface.
- **Hook by-reference callbacks on the frame instance.** Misses the event path, because the registration captured the
  original function.
- **Restore QuestInfo widgets only if they still show our text.** `SurfaceState.drop` does that per widget, but it
  cannot tell another surface's Japanese from ours on a shared FontString; forgetting across surfaces removes the
  ambiguity.
- **Cover all of Communities at once.** About 280 text sites across ClubFinder, streams and settings, most of
  which the Classic guild frame never had. Parity first; the rest separately.
- **Rename `Honor.lua` to serve the PvP rank panel.** The two share no widgets, writers or keys; one file with two
  unrelated features would have two reasons to change.

## Related

- [Research: camelot surface re-target](../research/2026-09-19-camelot-surface-retarget.md) ·
  [Forever client differences](../research/2026-09-17-forever-client-differences.md)
- [ADR-009: Surfaces post-hook the writer](009-surfaces-post-hook-the-writer.md) ·
  [ADR-016: Whole-window interface coverage](016-whole-window-interface-coverage.md) ·
  [ADR-025: Guarded surface init and a runtime-chosen tooltip hook path](025-guarded-surface-init-and-runtime-tooltip-path.md)
- [Addon modules](../architecture/addon-modules.md) ·
  [Pipeline](../systems/pipeline.md)
