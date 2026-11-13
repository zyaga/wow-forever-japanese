# ADR-088: Every menu is written after it opens

- **Status:** Accepted
- **Date:** 2026-11-13
- **Deciders:** the maintainer
- **Related:** [ADR-031](031-objective-lines-menus-and-helptips.md) (menus through `Menu.ModifyMenu` initializers) · [ADR-033](033-level-1-gaps-name-list-tails-and-untagged-menus.md) (untagged menus) · [ADR-069](069-unit-menus-and-edit-mode-stay-english.md) (the unit menus and Edit Mode left English) · [ADR-077](077-the-quest-windows-are-never-re-measured-from-addon-code.md) (no client layout run from addon code) · [ADR-087](087-the-chat-menu-is-written-after-it-opens.md) (the chat menu written after it opens) · [Client limits](../architecture/client-limits.md)

## Context

[ADR-087](087-the-chat-menu-is-written-after-it-opens.md) moved the chat menu off initializers after a language picked from it was stored tainted on the chat box. Every other menu the addon translated still had an initializer on each entry:

- every tagged menu in `Menus.TAGS` (the tags `UI/Menus` declares, the tags `UI/MenusTags` adds for the other windows, and the gamepad's More Actions menu), through a `Menu.ModifyMenu` callback;
- the untagged menus (the Options window's dropdowns, the who list's filter, the Group Finder's listing menu and the crafting-orders recipe menu), through `UI/MenusUntagged`'s pre-open hooks, which added the same initializers;
- the spellbook's settings menu, through a `Menu.ModifyMenu` callback of its own in `UI/SpellBook`.

What the client source shows (build 1.60.1.70888):

- `InitializeFrame` runs an element's initializers and then sets its `OnMouseDown`, `OnEnter` and `OnLeave` scripts in the same function (`blizzard_menu/menu.lua:1117–1131`). Once an initializer of this addon has run there, the scripts are set tainted, and every pick from the menu runs tainted. This was traced in game for the chat menu ([ADR-087](087-the-chat-menu-is-written-after-it-opens.md)); for the other menus it is the same code path.
- The client shows a menu frame with `proxy:Show()`, which fires `MenuProxy.OnShow` (`menu.lua:2506, 2531, 1845–1849`), after the frame's scripts are set. For a menu whose description has a tag it then fires `Menu.OpenMenuTag` (`menu.lua:2453–2459, 2566`). A submenu goes through the same function and gets only `MenuProxy.OnShow`; so does an untagged menu.
- `EventRegistry` callbacks run under `securecallfunction` inside `secureexecuterange` (`blizzard_sharedxmlbase/callbackregistry.lua:198–214`). What the addon does in one does not reach the client's code that runs after the event.
- The menu frame reports the region that opened it (`GetOwnerRegion`, `menu.lua:1906–1908`).
- A pick that keeps the menu open (a checkbox, such as a bag filter) has the client run its own initializers again on the open entries, which writes the English back (`menu.lua:2353–2367, 1682–1700`).
- A scrolling menu moves its element frames into its scroll box's rows (`menu.lua:1813–1818`), so they are not the menu frame's own children.
- An entry's text widget is anchored on its left, one line, and sized to its English (`menuvariants.lua:16–19`, `compositor.lua:71–72`, `menutemplates.lua:298`). Every entry of a menu gets one common width (`menu.lua:1430–1480`). A scrolling menu has a fixed size (`menu.lua:1860–1874`).

The unit right-click menus had been left English for a related reason ([ADR-069](069-unit-menus-and-edit-mode-stay-english.md)): the pass that runs the initializers also runs each entry's `IsEnabled`, which calls `CheckInteractDistance`, protected in combat (`unitpopupsharedutils.lua:195–205`).

The first plan was to check each menu's picks one by one in game and move only the menus whose picks write something a protected call reads later.

## Decision

1. **No menu gets an initializer.** Nothing in the addon registers a `Menu.ModifyMenu` callback or calls `AddInitializer` or `AddResetter` on a menu description. A static test fails on any of them, and on a `Compat.declare` of `Menu.ModifyMenu` (`tests/python/test_protected_paths.py`).
2. **A tagged root menu is written on `Menu.OpenMenuTag`.** `UI/Menus` remembers the menu frame `MenuProxy.OnShow` reported last; when `Menu.OpenMenuTag` follows for a tag in `Menus.TAGS`, that frame becomes the open menu and its entries are written through `Menus.showElement` with the tag's keys. The entries are the element frames under the menu frame, found down to four levels so that a scrolling menu's entries inside its scroll box's rows are found too; an element frame is not searched further, since the buttons attached to it are its own.
3. **Submenus and untagged menus are written on `MenuProxy.OnShow`.** A menu frame shown while the open menu's root is still shown is a submenu and is written with the open menu's keys. Otherwise, a frame whose owner region an opener recorded is an untagged menu: `UI/MenusUntagged` no longer touches the description, it only records the owner region and its tag (the Options dropdowns when the client sets them up, the two context menus when they are populated), and `UI/Menus` asks `MenusUntagged.specFor(owner)` with the frame's `GetOwnerRegion()`. The untagged menus' specs live in `Menus.TAGS` like every other, under tags of their own (`SETTINGS_DROPDOWN`, `CONTEXT_LFG_SEARCH_ENTRY`, `CONTEXT_CUSTOMER_ORDER_RECIPE`, and `WHO_FILTER` from `UI/Friends`) that the client never fires, so only `specFor` reaches them.
4. **A pick that keeps the menu open is followed.** One written text widget per menu frame is followed by `UI/TextWatch` from the addon's own frame. A checkbox pick reruns every entry's initializers at once, so one widget is enough to see it: when the client writes the English back, the whole menu frame is written again after the client's pass has ended. On `MenuProxy.OnHide` the records on that frame's widgets are dropped by their keys and the watch is removed (`TextWatch.remove`, new; it also hides the watch's own frame, so nothing runs once nothing is followed), before the client hands the widgets back to the pool every menu shares.
5. **A name title stays English.** For a tag marked `titleIsName`, the root menu's top entry (the one with the highest `GetTop`; the generator creates the title first and entries stack downwards, `menu.lua:1500–1540`) is the title and is never written. Its text is the menu's name, and no other entry with that same English is written either, so a channel named "Trade" stays "Trade". A title text the client keeps secret counts as no name. Nothing is read from the menu's `contextData`.
6. **The menu is widened to the Japanese with `SetWidth` alone.** After a menu frame's entries are written, a label whose Japanese is wider than its text widget gets `SetWidth` to its unbounded width (`GetUnboundedStringWidth`). If a label then passes its entry's right edge, less the margin the client left after the widest English label, every entry and the menu frame widen by the largest overflow. No client layout code runs. `SetTextToFit` stays forbidden. A scrolling menu (its scroll box shown) is not widened.
7. **The spellbook's settings menu is one more tag.** `MENU_SPELL_BOOK_SETTINGS` is in `Menus.TAGS` with its keys and its tooltip key listed in `UI/MenusTags`, and `UI/SpellBook` has no menu hook, initializer, resetter, menu keys or `spellbook.menu` surface of its own.
8. **The unit right-click menus are in Japanese again.** `UI/MenusUnit` is back with the key lists it had before [ADR-069](069-unit-menus-and-edit-mode-stay-english.md) and adds one `MENU_UNIT_<which>` spec per `which`, each with `titleIsName`. A unit menu is written after the pass that runs `IsEnabled` and `CheckInteractDistance`, so nothing of this addon runs in that pass. The unit's name stays English. `blizzard_unitpopup` and `blizzard_unitpopupshared` are no longer `protected` in `pipeline/forever_addon_dispositions.txt`: they are `library`, their words reaching the screen as menu entries through `UI/Menus` and `UI/MenusUnit`.
9. **Edit Mode is unchanged.** It stays as the client writes it ([ADR-069](069-unit-menus-and-edit-mode-stay-english.md)).
10. **An error on these paths is recorded, never raised.** The callbacks run for every menu the client opens or hides; each body runs under `pcall` and a distinct error is recorded once (surface `menus.afteropen`, or `menus.untagged` for the populate hook).

## Rationale

- Every menu with an initializer had the same cause: scripts set in the function that ran the addon's code. Finding which picks reach a protected call would need an in-game scan per menu and per pick, and a new menu or a new client build could add one. Moving every menu removes the cause for all of them with one mechanism, and the initializer path is gone from the addon.
- The registry callbacks run after the scripts are set and under `securecallfunction`, so writing there leaves the client's own code clean.
- What the initializer path gave for free, a menu laid out for the Japanese, is taken over by the fit. Plain `SetWidth` on the regions is the one thing the addon may do without running client layout under its taint ([ADR-077](077-the-quest-windows-are-never-re-measured-from-addon-code.md)).
- The unit menus were English only because the addon's code ran inside their element pass. With nothing of the addon in that pass, they can be Japanese like every other menu.

## Consequences

- A pick from any translated menu (Share Quest on the tracker, an equipment set, a Group Finder role, an Options dropdown entry, a unit menu entry) runs as the client's own code. [likely: traced for the chat menu only]
- The unit right-click menus (target, focus, self, party, raid, pet, friend, Communities and the rest of the `which` list) show their entries in Japanese; the unit's name stays English. `tests/python/test_protected_paths.py::test_no_source_registers_a_unit_menu` is replaced by `test_no_source_adds_a_menu_initializer`.
- If the client rebuilds an open menu's entries, they show English until the menu is opened again (as in [ADR-087](087-the-chat-menu-is-written-after-it-opens.md)). A checkbox pick is not a rebuild: the watch puts the Japanese back.
- One menu tree is tracked at a time, its tag and its root frame, as the client keeps one open.
- `docs/testing/strategy.md` has the in-game steps below.

## Not known

All of these are [likely] until the maintainer's in-game pass:

- **A unit menu in combat.** Right-clicking a party frame in combat and picking an entry raises no `ADDON_ACTION_BLOCKED`.
- **Share Quest from the tracker in combat.** No block names the addon ([ADR-077](077-the-quest-windows-are-never-re-measured-from-addon-code.md) left this open).
- **Labels not cut off.** The fit gives every Japanese label room, submenus included.
- **A client re-layout of an open menu.** Whether the client lays out an open menu again (and undoes the widening) without rebuilding its entries. No such path was found in the source.

## Alternatives considered

- **Check each menu's picks one by one in game** and move only the menus that need it. Rejected: the cause is the same in every menu, the scan would be long, and it would have to be repeated for every new menu and client build.
- **`Menu.GetManager():GetOpenMenu()`** to find the open menu. It returns the manager's private menu object (`menu.lua:1995–1997`), not the proxy the registry events report, so it does not give the frames to write.
- **Lay the menu out again through the client's layout code** (`Layout`, `MarkDirty`, `SetTextToFit`) after writing. That would run the client's layout under this addon's taint, the pattern [ADR-077](077-the-quest-windows-are-never-re-measured-from-addon-code.md) removed.
- **Keep the unit menus English.** Clean, but no longer needed once nothing of the addon runs in their element pass.
