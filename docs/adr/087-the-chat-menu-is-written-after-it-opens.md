# ADR-087: The chat menu is written after it opens

- **Status:** Accepted
- **Date:** 2026-11-13
- **Deciders:** the maintainer
- **Related:** [ADR-031](031-objective-lines-menus-and-helptips.md) (menus through `Menu.ModifyMenu` initializers) · [ADR-033](033-level-1-gaps-name-list-tails-and-untagged-menus.md) (untagged menus, and why `MenuProxy.OnShow` was not used there) · [ADR-069](069-unit-menus-and-edit-mode-stay-english.md) (the menu pass runs tainted) · [ADR-077](077-the-quest-windows-are-never-re-measured-from-addon-code.md) · [Client limits](../architecture/client-limits.md)

## Context

A player reported the client refusing to send a chat message with this addon named: `ADDON_ACTION_BLOCKED`, `SendChatMessage()`, from the chat box's `SendText`.

What the client source shows (build 1.60.1.70888):

- The send line is `C_ChatInfo.SendChatMessage(text, type, self.languageID)` (`blizzard_chatframebase/shared/chatframeeditbox.lua:296–319`). The call has restrictions (`chatinfodocumentation.lua:564–577`).
- `languageID` is written by `ChatFrameEditBoxMixin:SetGameLanguage` (`chatframeeditbox.lua:835–839`), which the chat menu calls when a language is picked from its Language submenu (`mainline/chatframemenubutton.lua:116–124, 164–170`).
- A menu element's initializers run, then the client measures the element, then it sets the element's `OnMouseDown`, `OnEnter` and `OnLeave` scripts, in one step (`blizzard_menu/menu.lua:1016–1066, 1117–1131`). Each initializer runs on its own, but the measure after them reads the text the addon wrote, which comes back tainted, and the scripts are set after it.

`UI/Menus.lua` translated the chat menu (tag `MENU_CHAT_SHORTCUTS`) like every tagged menu: a `Menu.ModifyMenu` callback that adds an initializer to each element ([ADR-031](031-objective-lines-menus-and-helptips.md)).

What is traced in game (the maintainer, client build 1.60.1.70938, `issecurevariable` over the chat box's fields):

| Build | After login | After picking a language |
|---|---|---|
| Initializers on every entry (as shipped) | clean | `language`, `languageID` tainted by this addon |
| Initializers on the top-level entries only | not checked | `language`, `languageID` tainted by this addon |
| No callback for this menu (menu in English) | clean | clean |
| Entries written after the menu opens (this decision) | clean | clean, menu in Japanese |

What is inferred [likely]: that the tainted scripts are the path (the source reading above). The scans show the fields, not the step that tainted them. That the refusal only happens while a restriction such as combat is active is also [likely], from the call's `HasRestrictions` flag; it was not tried.

## Decision

1. **The chat menu gets no initializer.** `MENU_CHAT_SHORTCUTS` is not in `Menus.TAGS`, so no `Menu.ModifyMenu` callback is registered for it.
2. **Its entries are written once the client reports the menu open.** The client triggers `Menu.OpenMenuTag` after it has built a tagged menu and set its elements' scripts (`menu.lua:2453–2459`), and `MenuProxy.OnShow` for each menu frame it shows (`menu.lua:1845–1849`). `UI/Menus.lua` remembers the shown menu frames and, on `Menu.OpenMenuTag` for a tag in `Menus.AFTER_OPEN`, shows every element frame under them through the same `Menus.showElement` the initializers use.
3. **The menu keeps the client's layout.** It is not laid out again for the Japanese.
4. **Its text widgets are let go when the menu hides.** A menu's text widgets come from one pool that every menu shares (`blizzard_menu/compositor.lua:367–390`), and the initializer path drops its records in a resetter. This path has no resetter, so on `MenuProxy.OnHide`, which fires before the client hands the widgets back (`menu.lua:1751–1764, 1851–1853`), the addon drops the records on the text widgets it wrote. It remembers the widgets, not their element frames, because a rebuild of the open menu hands the same widgets to other frames. Without that, a later refresh would write this addon's font or text onto whichever menu took the widget next, a unit right-click menu included.
5. **An error on this path is recorded, never raised.** `Menu.OpenMenuTag` fires for every tagged menu the client opens; the callback's body runs under `pcall` and records a distinct error once, as the untagged menus' hook does.
6. **Only this menu.** Every other tagged menu keeps its initializers.

## Rationale

- The pick is what must stay clean, and it runs through the element's scripts. Writing the Japanese after those scripts are set leaves them as the client set them.
- [ADR-033](033-level-1-gaps-name-list-tails-and-untagged-menus.md) turned `MenuProxy.OnShow` down for the untagged menus because it fires after the menu is laid out in English. That cost is small here: the menu has a minimum width and its Japanese labels are short. None was cut off in game.
- Leaving the menu in English also keeps the pick clean, but drops a translated surface to do it. The maintainer ruled it out.

## Consequences

- A language picked from the chat menu is stored untainted, and the chat box reads it clean when a message is sent.
- The chat menu looks as before: its top-level entries in Japanese, slash commands and language names as the client writes them.
- If the client rebuilds the open menu's entries, they show English until the menu is opened again. No pick does that: a pick closes the menu, and an open submenu never rebuilds the root. The chat menu button rebuilds its menu on `LANGUAGE_LIST_CHANGED`, `CAN_PLAYER_SPEAK_LANGUAGE_CHANGED` and `NEUTRAL_FACTION_SELECT_RESULT` (`chatframemenubutton.lua`, `OnEvent`), which is the one way to see it.
- A label much longer than its English would be cut off, since the width is the client's. A new label on this menu is checked in game.
- `docs/testing/strategy.md` has a step for the language pick.

## Not known

- **Other menus.** Every menu this addon translates with an initializer has its elements' scripts set after the same measure, so a pick from it may run tainted too. Whether any other menu's pick writes a value the client later reads on a restricted call has not been looked at. The unit right-click menus are already left alone for a related reason ([ADR-069](069-unit-menus-and-edit-mode-stay-english.md)).
- **The chat types on this menu.** Picking Say, Party and the others ran through the same scripts. They are expected to be clean now for the same reason; only the language pick was scanned.

## Alternatives considered

- **Skip only the submenus.** Tried in game: the language fields were still tainted, because the Language entry itself, whose hover opens the submenu, still carried the initializer.
- **Leave the menu in English.** Clean, but not a fix.
- **Return a size from the initializer** so the client skips its measure (`menu.lua:1031–1040`). The size would be a value the addon produced, read by the same step.
