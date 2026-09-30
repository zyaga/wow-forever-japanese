# ADR-018: The modifier can be any key: bound keys are taken over by a session override binding, held truth stays the poll

- **Status:** Accepted. Implemented in `Core/Modifier.lua` (classes, `normalize`, `bindingEdge`, `bindingKey`), `Core/Settings.lua` (kind `key`, `check`), `Core/State.lua` (`revealKey`), `Core/Const.lua` (`BINDING_NAME_WFJ_REVEAL`), `UI/RevealBinding.lua`, `UI/KeyCapture.lua`, `Bindings.xml` (`WFJ_REVEAL`), `Main.lua` (`WFJ_RevealKey`, `PLAYER_REGEN_ENABLED`, re-apply on login / reload `PLAYER_ENTERING_WORLD`), `UI/Slash.lua`. In-game verification is checklist 14.
- **Date:** 2026-09-14

## Context
The [modifier](../glossary.md), the key held for live English (ADR-002), started as Alt, Ctrl or Shift. `Modifier.isDown` polls `IsAltKeyDown()`-family calls at every resolve, and `MODIFIER_STATE_CHANGED` is only the invalidation signal. It stays off the binding system on purpose: bindings do not fire while a frame has focus.

The goal is any key, set by pressing it on the settings page. The client can poll any key (`IsKeyDown` [verified: KeyCommand.lua:112], `IsMouseButtonDown` [verified: FloatingChatFrame.lua:1111]) and either side of a modifier (`IsLeftAltKeyDown()` … [verified: RestrictedEnvironment.lua:86–88]). Polling alone has a serious flaw for a key like `Q`: it still fires its own binding (an action button) every time the player peeks at English. A bare modifier has no such action, and a lone Alt cannot reliably be a Blizzard binding.

## Decision
1. **Three classes** (`Modifier.class`):
   - **`either`** (`alt` / `ctrl` / `shift`) and **`side`** (`lalt` … `rshift`) are polled, as before; `MODIFIER_STATE_CHANGED` invalidates. No binding is involved.
   - **`bound`** (any other single client key name up to 16 bytes, and `BUTTON3`–`BUTTON5`; no chords, never `BUTTON1` / `BUTTON2` / `ESCAPE` / a meta name without a poll) is taken over while the addon is loaded. `UI/RevealBinding.lua` calls `ClearOverrideBindings(owner)` then `SetOverrideBinding(owner, true, key, "WFJ_REVEAL")` [verified present: RestrictedFrames.lua:24–28]. `WFJ_REVEAL` is a `hidden="true"`, `runOnUp="true"` binding whose body `WFJ_RevealKey(keystate)` passes the down / up edge to `Modifier.bindingEdge` [verified: `runOnUp` + `keystate`, Bindings_Vanilla.xml:11–17].
2. **Held truth for `bound` = the binding saw `down` AND the key still polls down.** Typing the key in an EditBox sets no edge, so it reveals nothing. While held, an `OnUpdate` watcher on the owner frame re-polls each frame and stops itself on release, so a key-up that never arrives cannot leave English showing.
3. **Core stays frame-free.** `Modifier.setKey` fires the State event `revealKey(k)`; `RevealBinding` subscribes and applies. The `modifier` setting becomes `kind = "key"` with a `normalize` hook, and its `check` hook (reached through `Compat.resolve`) refuses the key currently bound to `WFJ_TOGGLE`.
4. **Combat.** Binding changes made in combat are queued (one pending value, the latest wins) and applied on `PLAYER_REGEN_ENABLED`. Key capture is refused in combat.
5. **The player's saved bindings are never written for the modifier.** The separate toggle key *is* a normal saved binding (`SetBinding` + `SaveBindings(GetCurrentBindingSet())`), set from the settings page, with a **Replace** confirmation when the key already has an action.

## Consequences
- A `Q` modifier never casts while the addon is loaded; changing the key or disabling the addon gives `Q` back, because override bindings are session-only [likely: their documented purpose; checklist 14c]. The page warns which action is taken over.
- The default Alt is polled as it always was. Stored `alt` / `ctrl` / `shift` normalize to themselves: no schema bump, no migration. A downgraded build rejects a stored `lalt` / `Q` / `BUTTON4` and falls back to Alt.
- New failure surface: combat restrictions on binding calls [likely], whether `hidden="true"` hides `WFJ_REVEAL` from Key Bindings [likely; its display name explains itself if listed; checklist 14b], and whether the Forever client passes `keystate` to override-bound actions. A missing up edge is caught by the poll; a missing down edge means the key does nothing, which checklist 14c catches before release.
- A player who binds `WFJ_REVEAL` to another key in Blizzard's list gets a key that does nothing: `isDown` still requires the configured key's poll.
- `Modifier.normalize` also refuses keys with no held state to poll: `MOUSEWHEEL*`, gamepad `PAD*`, and `BUTTON6` and up. The `IsMouseButtonDown` names `"MiddleButton"` / `"Button<n>"` are [likely; checklist 14d]; `KeyCapture.conflict` relies on `GetBindingAction` without `checkOverride` returning the saved binding [likely; checklist 14c].
- **Capture handlers exist only while listening.** A capture button sets `OnKeyDown` / `OnMouseDown` and `EnableKeyboard` when a capture starts and clears them on stop, keeping the template's own `OnMouseDown`, Blizzard's `KeybindListener:SetListening` pattern [verified: Blizzard_Keybindings.lua:26–40]. Standing handlers on the visible pages would swallow Escape in-game (the game menu would not open). One capture listens at a time.
- **Settings-UI frame owners.** `UI/OptionsWidgets.lua`, `UI/KeyCapture.lua`, `UI/RevealBinding.lua` and `UI/AddonListButton.lua` join `Main.lua` and `UI/Options.lua` as `:SetScript(` owners in `tests/python/test_forbidden_calls.py` (`FRAME_OWNERS`); each scripts only frames it creates (page widgets, the capture button, the override-binding owner, the AddOn List button), never a Blizzard frame's scripts. This amends ADR-016 decision 3. The AddOn List button calls no `HideUIPanel`.
- "The modifier is deliberately not a binding" holds for `either` / `side`, which remain polled; only the `bound` class uses a binding.

## Alternatives considered
- **Poll-only for every key**: the key's own action still fires, so the player casts while reading.
- **A Blizzard Key Bindings entry only**: set outside the addon's page, a bare modifier is not reliably bindable, and the page could only point at Blizzard's list.
- **Modifiers only (with side variants and mouse 4–5)**: no double-action problem, but not "any key".
- **`SetOverrideBindingClick` to a hidden button registered `AnyDown` / `AnyUp`** [verified pattern: CustomBindingButtonMixin.lua:116]: avoids a `Bindings.xml` entry, but down / up delivery for click bindings is less certain on this client than `runOnUp` + `keystate`. Kept as the fallback if checklist 14c fails.

## Related
- [ADR-002: Live English only](002-live-english-only.md)
- [Settings](../systems/settings.md): the modifier, key capture, the settings pages · [Addon modules](../architecture/addon-modules.md) · [Testing](../testing/strategy.md): checklist 14
