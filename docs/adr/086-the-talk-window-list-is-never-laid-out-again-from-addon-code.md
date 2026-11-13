# ADR-086: The talk window's list is never laid out again from addon code

- **Status:** Accepted
- **Date:** 2026-11-13
- **Deciders:** the maintainer
- **Related:** [ADR-017](017-gossip-surface.md) (the gossip surface and its measure widgets) · [ADR-077](077-the-quest-windows-are-never-re-measured-from-addon-code.md) (the same rule on the quest windows) · [ADR-009](009-surfaces-post-hook-the-writer.md) (the refit) · [Client limits](../architecture/client-limits.md)

## Context

A player using a controller on Forever reported that the cursor in an NPC talk window stayed on the top option (issue #126). The screenshot showed the client's "interface action failed because of an AddOn" message. With the addon off, the same player could move between the options.

What the client source shows (build 1.60.1.70888):

- Forever's gamepad navigation (`Blizzard_GamepadSmartNavigation`) refuses to act when its code is not running secure. `EnsureIsSecure` shows that message and returns, and `SelectButton` starts with it (`smartnavigation.lua:74–88, 649–655`).
- Moving to a row inside a scroll list goes through `HandleScroll` before `SelectButton` (`smartnavigation.lua:1087–1180`, called at `:1570–1577`). `HandleScroll` calls the list's `HasScrollableExtent`, `GetDerivedScrollRange` and `CalculateScrollPercentage`, which read the view's extent and the list's scroll fields (`blizzard_sharedxml/shared/scroll/scrollbox.lua:366–396, 429–451`).
- `ScrollBox:FullUpdate(true)` runs `FullUpdateInternal` at once: it recalculates the view's extent, writes the pan extent, updates the list, and sets the list's `OnSizeChanged` script back (`scrollbox.lua:133–193`). Called from addon code, all of that runs under the addon's taint.

`UI/Gossip.lua` made that call in two places ([ADR-017](017-gossip-surface.md)): once per session after the first talk window that showed Japanese, because that window is measured before the measure widgets are hooked, and from the refit whenever a refresh (the reveal key, a setting) changed a row outside the client's own update.

What is traced in game: with the call removed, the reporting player's cursor moves between the options with a controller; the maintainer's talk window lays out normally with mouse and keyboard, and the list and its view show no field tainted by this addon (`issecurevariable` over both tables). Both checks were made on the change that removed the call; the row-height rule of Decision 2 came after them and only takes further addon calls away. What is inferred [likely]: that the fields `HandleScroll` reads were the tainted ones. No scan was taken on the build that still made the call, and the scan reads the top level of the two tables only.

## Decision

1. **`UI/Gossip.lua` never calls `ScrollBox:FullUpdate`,** and the surface has no refit.
2. **A row is always as tall as the place the client measured for it.** The client stacks the rows by their heights only when it lays the list out, and every option button sits at the same frame level. A row grown past its place would lie over the next row and could take its clicks. So a row is resized once, as it is written, and only once the client has measured that kind of row through the addon's hook: its extent is then the height of the text shown. A refresh (the reveal key, a setting) changes a row's text and never its height.
3. **The measure-widget hooks stay.** They run inside the client's own update and write only the measure widgets' text and font. The greeting's hook is placed after the first window that shows a greeting, the option's after the first window that shows an option; each first runs when the next window is measured.
4. **A static test keeps the call out.** `tests/python/test_protected_paths.py` fails when shipped Lua calls `FullUpdate` outside `UI/Labels.lua`. Only that one method is checked.

## Rationale

- This is the rule of [ADR-077](077-the-quest-windows-are-never-re-measured-from-addon-code.md) on another surface: calling a Blizzard frame's layout method from addon code runs Blizzard's code under this addon's taint, and what it writes keeps the taint for the client's next pass that reads it.
- Selecting a talk option is not a protected action, so mouse and keyboard players never met the taint. Gamepad navigation is the one reader that checks.
- Removing the call for every player, and not only in gamepad mode, leaves no taint on the list at all. A player who opened a talk window with the mouse and then switched to a controller in the same session would otherwise still be stuck until a reload.
- With no second layout, a row's height and its place can only agree if the addon leaves the height alone wherever the client measured the English. The cost is then what the player sees, never what a click reaches.

## Consequences

- In a window measured before a hook ran (the first talk window of a session with a greeting, and the first with an option, which is often the same window), the rows keep the heights and places the client measured from the English. A Japanese line that wraps to more lines than its English runs into the line below it; one that wraps to fewer leaves a gap. Talking to the NPC again shows the window measured as shown.
- The same shows while the reveal key is held with the window open, or after a setting changes its rows: the text changes, the rows do not move or change height.
- The click areas are always the ones the client laid out: no option lies over another.
- From the window after a hook was placed, the layout is the client's own and matches the shown text.
- A session that already ran the old call stays tainted until a reload: the change stops new taint, it does not clean old.
- `docs/testing/strategy.md` checklists 3 and 10 follow: the first window may show lines running into each other, and the combat check of the removed call is gone.

## Left as they are

- **The description boxes `UI/Labels` re-fits** (Reputation, Currency, Skills, two Calendar boxes) still call `FullUpdate` on their own scroll box. They hold text only, with no row for the navigation to move to, and no report names them.
- **The gamepad button prompts** are still re-sized after their label is translated (`UI/Gamepad.lua`: `RefreshInputPromptSize`, `ApplyDefaultPromptPositioning`). The reporting player's check passed with this change alone. If a controller report names another window, this is the first place to look.

## Alternatives considered

- **Skip the call only in gamepad mode.** Mouse and keyboard players would keep the exact layout in the first window, but the taint would stay in their sessions and the mid-session switch would still break.
- **Hook the client's shared list-data code** so the measure widgets are hooked before the first window is measured. That code serves every list window in the game; a change there reaches far past the talk window.
- **Keep resizing every row to its shown text.** Without a second layout the rows below do not move, so the player sees the same overlap, and a taller row then also covers the next option's click area.
- **Delay the call (`C_Timer.After`).** The timer callback is addon code: the list's code would still run tainted.
