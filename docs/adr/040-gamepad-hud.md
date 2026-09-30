# ADR-040: The gamepad-mode HUD in Japanese: prompts, legend, radial menu and skip button

- **Status:** Accepted. Implemented in `addon/WoWForeverJapanese/UI/Gamepad.lua`,
  `UI/MenusTags.lua` (`MORE_CONTEXT_ACTIONS` gains `Gamepad.MENU_KEYS`), `Core/UIStringKeys.lua` (three `OWN` keys, the
  `wrapped` legend headers, `SKIP` `number`, the `icon` input-icon lines), `Main.lua`, the TOC;
  `pipeline/wfj/dev/ui_windows.py` (`FOREVER_WINDOWS["gamepad"]`), `pipeline/forever_addon_dispositions.txt`,
  `ui_keys.txt`, `ui_exclusions.txt`, `ui_inventory.txt`, `ui_uninventoried.txt`. The in-game checks are pending (the
  gamepad checklist in [Testing strategy](../testing/strategy.md)).
- **Date:** 2026-09-25
- **Relates to:** [ADR-016](016-whole-window-interface-coverage.md) (restricted matching, hooks on instances),
  [ADR-035](035-ui-errors-frame-surface.md) (the exact Lua-line rule), [ADR-037](037-staticpopup-dialogs-and-owned-keys.md)
  (keys that own their Japanese), [ADR-038](038-menus-callouts-and-composite-forms.md) (menu tags and the untagged hook).

## Context

Forever loads `Blizzard_Gamepad`, `Blizzard_GamepadSharedUtility` and `Blizzard_GamepadTargeting` at login on camelot.
In gamepad input mode (`InputUtil.IsGamepadUIEnabled`: Options → Gamepad, or a connected controller) every window gets
a footer of button prompts ("Close", "Equip", "More Actions"), the HUD shows a persistent controller legend, a radial
main menu opens from the controller, and cinematics show a hold-to-skip button. Every text on Forever is in scope, so this text is translated too.

What made the HUD different from the windows already covered:

- **Prompt frames copy their mixin when made.** `InputPromptMixin:SetPromptText`
  (`blizzard_gamepadsharedutility/inputprompts/inputprompts.lua:34–42`) sets the label, sizes `ControlDescText` to the
  text's width and calls `RefreshInputPromptSize`. Prompt frames get the method through `Mixin` / `mixin="…"` at
  creation, so a hook on the mixin reaches only frames made after it; frames made before the addon loaded hold the old
  method, are unnamed and sit in no list the addon can reach.
- **Labels are measured and laid out by the writer.** A footer legend (`InputPromptLegendMixin:RefreshWithPromptedBindings`,
  `inputlegendpromptgroup.lua:94–121`) lays the prompts out with `ApplyDefaultPromptPositioning` after writing them,
  on every focus change. A Japanese label of a different width left in place would overlap or leave gaps.
- **A footer shows more than its own keys.** Next to the gamepad phrases a footer shows generic words (OKAY, CANCEL,
  NEXT) and the neighbouring window's jump-hint title (CHARACTER, WORLD_MAP, TALENTS), which change with each window.
- **Shared English, different meaning.** "Back" on a footer is 戻る, but the shipped `BACK` slot word is 背中; the
  radial's "Point" and "Train" emotes collide with the resample-quality option (ポイント) and the trainer's button (訓練).
- **Other writers.** The radial menu (`GamepadRadial`, made at load) writes its header, segment labels and D-pad
  indicator labels; the skip button's `OnUpdate` rewrites `SKIP` or `SKIP .. " " .. n` every frame
  (`consoletemplates.lua:135–147`); the "More Actions" menus are `MenuUtil` context menus with no tag
  (`PromptedBindingMixin:CreateMoreActionsMenu`, `promptedbinding.lua:126–181`).

## Decision

1. **The gamepad HUD is a surface.** New surface `gamepad` (area `ui`), module `UI/Gamepad.lua`, called by `Main` with
   the other Forever surfaces. The three gamepad addons are dispositioned `surface gamepad`; `FOREVER_WINDOWS["gamepad"]`
   scans the prompt / legend templates, the persistent legend, the radial, the skip button and group targeting. The
   window footers' labels are set in each window's own gamepad setup, which those windows' surfaces already scan.
2. **Hook points.**

   | writer | hook | re-fit |
   |---|---|---|
   | footer and legend prompts | `InputPromptMixin:SetPromptText` post-hooked | the prompt re-sized as the writer does it (`ControlDescText:SetWidth`, `RefreshInputPromptSize`), then its legend's `ApplyDefaultPromptPositioning` (a persistent-legend entry has fixed anchors and no such method) |
   | radial menu | `GamepadRadial:ActivateRadial` and `ContextActionSelector:SetMenuOptions` post-hooked on the instances | none (fixed layout) |
   | skip button | the button's `OnUpdate` (`HookScript`); `GamepadMode.CreateHoldButtonWithTextFromTemplate` post-hooked for a button made later | none |
   | "More Actions" menus | the menu is tagged `MORE_CONTEXT_ACTIONS` (`promptedbinding.lua:140`): `UI/MenusTags` appends `Gamepad.MENU_KEYS` to that tag's list, and `UI/Menus`' `Menu.ModifyMenu` callback shows them | the menu system's own |
   | radial error lines | `UI/Errors`' exact Lua-line rule (`RADIAL_ERROR_*`, `ERROR_NO_FRAME_TO_FOCUS`) | the errors frame's own |

3. **Mixin plus older instances, never both.** The mixin's `SetPromptText` is post-hooked for every frame made later.
   Each frame that already exists is found once with `EnumerateFrames` (a frame whose `SetPromptText` is the mixin's
   original function) and hooked on its own, and its current label shown at once. A frame made after the mixin hook
   carries the hooked method, so it is never hooked twice; a frame made before carries the original, so it is hooked
   once as an instance (the `UI/HudLabels` rule).
4. **Match by the writer's own set first, then any exact dictionary English.** Every writer here is handed a whole
   global string, never a name and never a formatted template (the skip countdown is the declared `number` form).
   Each writer has its own set: footer and legend prompts `Gamepad.PROMPT_KEYS` (every HUD key but the two owned
   radial emotes), the radial `Gamepad.RADIAL_KEYS` (every HUD key but the trainer's `TRAIN`), the skip button `SKIP`
   alone. An owned key wins any match that names it, so "Train" on a trainer footer must never meet the emote. The
   label is tried against that set first; a label that matches none of them and is
   exactly one dictionary English takes that key (`index:exactKey`, the same rule as ADR-035's Lua lines). This keeps
   up with the footer's generic words and jump-hint titles without a list to maintain, and it is safe because these
   writers never show player, item or spell names. Anything else stays as written.
5. **Owned keys.** `FRAME_ACTION_BACK` (戻る), `RADIAL_LABEL_POINT` (指差す) and `RADIAL_LABEL_TRAIN` (汽車) own their
   Japanese (`UIStrings.OWN`, ADR-037). An owned key answers only a caller that asks for it by key, which is why
   the writer's set is tried before the exact-English step, and why the two emote keys are kept out of the prompt set.
6. **"More Actions" menus through their tag.** `PromptedBindingMixin:CreateMoreActionsMenu` tags the root description
   `MORE_CONTEXT_ACTIONS` inside the generator (`promptedbinding.lua:140`), which is registered in `UI/MenusTags`
   ([ADR-038](038-menus-callouts-and-composite-forms.md)); `Gamepad.MENU_KEYS` (equip set, split stack, destroy item,
   feed to pet, …) is appended to that tag's key list, so each entry is matched only against its tag's keys. The menu
   is never untagged, so the untagged hook is not needed.

   **Fonts and per-frame writers.** The persistent legend sets a font object on its header rows right after their
   label (`gamepadpersistentinputlegend.lua:153–156`), which puts the client's face back under the Japanese:
   `SetPromptFont` is post-hooked alongside `SetPromptText` (mixin and older instances) and the label re-shown. The
   skip button's text is rewritten every frame; an unchanged frame (same English, Alt state and switches) gets the
   last result written back directly, and only a change goes through `Labels.show`.
7. **What stays English.**
   - `NARRATION_CONTEXT_GAME_MENU`: spoken only (`C_VoiceChat.SpeakText`); nothing is drawn.
   - `ALWAYS`, `NEVER`, `FRIENDLY`: only table field names in the gamepad code; no Lua or XML reads the strings.
   - `CONTEXT_ACTION_LABEL_RESET_FILTERS`, `FRAME_ACTION_GIVE`, `FRAME_ACTION_HIDE_QUESTS`, `FRAME_ACTION_SHOW_QUESTS`,
     `FRAME_ACTION_MAP_LEVEL_CONTINENT`, `FRAME_ACTION_ROTATE_CHARACTER`: no use site on 1.60.1.70009.
   - `FRAME_ACTION_FILTER`: the trainer's filter binding uses an icon-only custom prompt frame; never drawn.
   - `RADIAL_LABEL_NO_TARGET`: only the radial's hidden label path and an uncalled function.

   Each is a `permanent` exclusion with its source evidence.

## Consequences

- A player in gamepad mode reads the footers, legend, radial menu, skip button and "More Actions" menus in Japanese;
  Alt shows English and the master switch turns it off, as for every surface.
- Footers re-lay out after each label change, so a Japanese label wider or narrower than the English keeps the
  footer's spacing.
- The exact-English step means any future footer word already in the dictionary shows Japanese with no code change.
  It depends on the writers never showing a name; a future writer that does would need a restricted `only` set.
- Colliding English needs an owned key, found only by key. Six collisions were reviewed and accepted as shared
  meanings (Angry, Bind, Chicken, Dance, Destroy, Split: `test_ui_keys.KNOWN_NAME_COLLISIONS`).
- `FRAME_ACTION_CONFIRM` / `_EXIT` (the icon selector's footer, a shared template file no surface scans) are listed in
  `ui_uninventoried.txt`.
- Nothing shows until gamepad mode is on, so the in-game check needs Options → Gamepad enabled.

## Alternatives considered

- **Leave the gamepad HUD English**: rejected; every text on Forever is in scope.
- **Hook only the mixin**: misses every prompt frame made before the addon loaded (the persistent legend, frames
  built at login).
- **Hook every instance through `EnumerateFrames` on each show**: repeated full frame walks; the one-time walk plus
  the mixin hook covers both sets.
- **A fixed key list only (no exact-English step)**: footers show generic words and other windows' titles that no
  list here could keep up with.
- **Unrestricted matching on the labels**: templates could answer a label; the writers only hand whole strings, so
  exact matching is enough and safer.
