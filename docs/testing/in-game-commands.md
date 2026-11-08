# In-game commands for a check

An in-game check never depends on what the tester's character has. Nobody needs to own the item, know the spell, have the talent, be a certain level or be on the quest. The check opens the exact thing by its id with a `/run` line, the same way a link in chat would.

## How a check is handed over

- Every command goes in a code block of its own, one line each, in the order to run them.
- Each step says what should be on screen, in plain words ("the green Equip lines show 26 and 2%").
- The steps start with `/reload` when a new build was copied, and end with `/reload` when the addon's log or trace has to be read afterwards.
- A command is used only after it was checked in the Forever client's own code (the file and line are listed below). The last column says whether it has been run in game yet; a new one goes in as "not yet" and changes once it worked.
- If nothing can open the thing by id, the check is done with a spec, or a small dev command is built for it. The tester is never asked to go and find it.

## Commands

| To open | Command | Notes | Source (Forever 1.60.1.70685) | Run in game |
|---|---|---|---|---|
| An item's tooltip, as if linked in chat | `/run SetItemRef("item:<id>","[x]","LeftButton")` | Opens `ItemRefTooltip`. An item the client has not seen yet may open empty: run it a second time. | `blizzard_uipanels_game/mainline/itemref.lua:6`, `:390` | yes (2026-11-08) |
| A spell's tooltip, as if linked in chat | `/run SetItemRef("spell:<id>","[x]","LeftButton")` | Same window and same rule as an item. | `itemref.lua:6`; `SetHyperlink`, `tooltipdatahandler.lua:590` | not yet |
| A quest's tooltip, as if linked in chat | `/run SetItemRef("quest:<id>:0","[x]","LeftButton")` | Same window. | `itemref.lua:6`, `:39` | not yet |
| The talent window | `/run PlayerSpellsUtil.OpenToClassTalentsTab()` | Then hover the talent named in the check. A talent's tooltip needs the tree, so the talent has to be one the class has; any rank works. | `blizzard_framexmlutil/mainline/playerspellsutil.lua:32` | yes (2026-11-08) |
| The world map and quest log | `/run ToggleQuestLog()` | | `blizzard_uipanels_game/mainline/questmapframe.lua:2174` | not yet |
| The addon's tooltip trace, kept in the saved file | `/wfj debug tooltip on`, then `/reload` after the check | Records every pass over a spell or item tooltip and every write to its lines; `/wfj debug tooltip off` clears it. | `UI/Slash.lua` | yes (2026-11-08) |

## Examples

Gnarled Necromancer's Staff (item 251534), the item in issue #87:

```
/run SetItemRef("item:251534","[x]","LeftButton")
```
