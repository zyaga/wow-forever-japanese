# ADR-033: Name-list tails as `$T`; untagged menus through the dropdown's RegisterMenu

- **Status:** Accepted. Implemented in `pipeline/wfj/core/align.py` (`NAME_LIST_TAIL`, `split_tail`, `tail_problems`), `dev/translate_lint.py`,
  `dev/translate_batch.py`, `core/status.py`; `addon/WoWForeverJapanese/Core/Align.lua` (`Align.splitTail`),
  `Core/UIStrings.lua` and `Core/UIStringKeys.lua` (`icon`, `optionTip`, `verbatim`, the `%%` rule), `UI/Menus.lua` (`Menus.UNTAGGED`),
  `UI/MenusUntagged.lua`, `Main.lua`. The in-game checks are pending (the
  level-1 checklist in [Testing strategy](../testing/strategy.md)).
- **Date:** 2026-09-22

## Context

These are the level-1 gaps on Forever that [ADR-032](032-level-1-gaps-subtexts-and-name-titles.md) did not decide.
Four of them need a design decision:

- **Name-list tails.** Languages (1293657) and Armor Proficiency (1293712) are visible, auto-learned level-1 spells
  whose descriptions end in a chain of `$?s<id>[<line break>$@spellname<id>][]`: one line per spell the player knows,
  each that spell's name ("Common", "Dwarvish", "Mail"). `align.UNCOUNTABLE` (`$\?|\$@`, `core/align.py:52`)
  rejected the whole description, so `translate_batch` dropped both rows. They are the only two level-1 spells with
  English and no Japanese.
- **Untagged menus.** The Options window's dropdowns (`Settings.InitDropdown`,
  `blizzard_settings_shared/blizzard_settings.lua:552–568`) and Edit Mode's setting dropdowns
  (`EditModeSettingDropdownMixin:SetupSetting`, `blizzard_editmode/shared/editmodetemplates.lua:22–53`) build their
  menus with no tag. `Menu.ModifyMenu` ([ADR-031](031-objective-lines-menus-and-helptips.md)) never sees them:
  `SecureModifyMenu` returns when the description has no tag (`blizzard_menu/menu.lua:2708–2717`).
- **Composite UI lines with an icon or two colours.** A role radio is `INLINE_TANK_ICON .. " " .. TANK` and a friends
  status radio is `|T…|t Available`; a Settings option's hover is `|c…<label>|r: |c…<tooltip>|r` or `|c…<label>|r:`
  (`blizzard_settings.lua:441–457`). No UIStrings label form matched either.
- **`%%` with no specifier.** The crit hovers and `ARMOR_MAX_EFFECTIVENESS_TOOLTIP` hold a literal `%%` and no
  specifier. `UIStrings.build` indexed them as plain text, but the client always prints them through `format()`
  (camelot `paperdollframestats.lua:477, 539–545`), so the screen shows "100%" and the index held "100%%": they never
  matched.

## Decision

1. **A name-list tail is markup: `$T`, in band, like `$N<k>` / `$D<k>`.**
   - Pipeline: `align.NAME_LIST_TAIL` matches a trailing run of `$?s<id>[<break>$@spellname<id>][]` groups.
     `split_tail` peels it only when it is the description's trailing run, a non-empty head precedes it, and that
     **head is one line**: the addon cuts the live description at its first line break, so a multi-line head could
     not be matched against it (Apprentice and Journeyman Riding, 33388 / 33391, end in the same chain after a
     three-line head; they stay uncountable and undrafted). `slots`
     counts the head only (the tail prints names, never a number). The Japanese translates the head and ends in a
     single `$T`. `align.tail_problems` gives `translate_lint` four reasons: `tail_missing`, `tail_unexpected`,
     `tail_misplaced` (not the one last token), `tail_chain` (the Japanese writes a `$?` / `$@` itself).
     `translate_batch._annotate_slots` keeps such a row instead of dropping it and marks it `tail: true` for the
     translator.
   - Addon: `Align.splitTail(ja, scope)` splits the Japanese at its trailing `$T` and the live text at its first line
     break. `Align.fillValues` and `Align.check` fill and check the head against the live text before that break, then
     append the live lines from that break on, byte for byte. The language and armor names stay live English
     ([principle 2](../architecture/principles.md#2-names-stay-in-english)). A `$T` anywhere but the end, or twice, fails closed to English.
   - `optionTip` (decision 3) is reached only from a **restricted** lookup (`Index:optionTip`, called
     by `matchOnly`): both halves must be dictionary entries and the label must be one of the caller's own keys, so a
     coloured "\<word>: \<word>" line on another surface is never read as an option line. And the three keys that share
     the English `"%s (%s)"` (`PVP_LEAVE_BUTTON_TIME`, `KEY_BINDING_NAME_AND_KEY`, `SETTINGS_SUBCATEGORY_FMT`) declare the
     same argument kinds: one template is compiled per distinct English under whichever key sorts first,
     so a new key with narrower kinds silently re-captures the line for the others (it had broken the PvP leave
     countdown). `tests/python/test_ui_pipeline.py` pins the rule for every group.
   - The in-band `$T` needs no data-format or row-shape change, and a row without `$T` renders exactly as before. The
     `tail` flag exists only on `translate_batch`'s working rows, never in `data/` or `Data/`.
   - Both spells ship `unaligned`: spell rows are never trusted offline
     ([ADR-007](007-unaligned-ships-with-runtime-gate.md)), so `Align.check` gates them at run time like every spell.
2. **Untagged menus are reached through each dropdown's `RegisterMenu`.** `DropdownButtonMixin:OpenMenu` always
   regenerates: `GenerateMenu` → `PopulateDescription` → `RegisterMenu(rootDescription)`, and only then the Menu
   manager's `OpenMenu` (`blizzard_menu/dropdownbutton.lua:108–131, 178–207, 255–264`). A post-hook on a dropdown's
   `RegisterMenu` therefore holds the populated description where a `ModifyMenu` callback would, before any element
   frame exists. `UI/MenusUntagged.lua` calls `Menus.onMenu` there, so `UI/Menus`' walk adds the same initializers and
   the menu is laid out with the Japanese.
   - The dropdowns are found as the client sets them up: `hooksecurefunc(Settings, "InitDropdown")` (every Options
     dropdown goes through the `Settings` table, `blizzard_settingcontrols.lua:873, 1589`,
     `blizzard_settingsdefinitions_shared/graphics.lua:319`) and a post-hook on `EditModeSettingDropdownMixin`'s
     `SetupSetting` (each pooled row copies the hooked mixin method when it is made).
   - Each untagged menu is a `Menus.UNTAGGED` entry (`SETTINGS_DROPDOWN`, `EDIT_MODE_DROPDOWN`) that matches only its
     window's keys (`UI/SettingsKeys` `options` / `editmode`). A font, locale or layout name is no key and stays
     English. The entries are never registered with `Menu.ModifyMenu`.
3. **Two UIStrings label forms and one argument kind.**
   - `icon`: `|T…|t <entry>` / `|A…|a <entry>`; the icon markup is kept verbatim in front of the Japanese. Granted to
     `TANK`, `HEALER`, `DAMAGER`, `FRIENDS_LIST_AVAILABLE`, `FRIENDS_LIST_AWAY`, `FRIENDS_LIST_BUSY`.
   - `optionTip`: `|c…<label>|r: |c…<tooltip>|r` or `|c…<label>|r:`. Both halves must be dictionary entries or the
     line stays English; each colour is kept.
   - Argument kind `verbatim`: any text, periods included, shown exactly as captured. Only for templates in
     `UIStrings.ONLY` (matched only where a widget asks by key); used by `GOSSIP_OPTION_PREPEND`'s option text.
4. **An English holding `%%` with no specifier is a template.** `UIStrings.build` puts it in the template index, so
   its `%%` matches a literal `%` and its Japanese is filled the same way. Seven listed keys change bucket, all
   formatted by camelot `paperdollframestats.lua:477, 539–545`.

## Consequences

- Any other spell whose description ends in the same chain is picked up by the same cut; a chain in the middle of a
  description is still uncountable and dropped, as before.
- The addon never stores or shows a stored name: the tail is always the client's own live lines. What the addon
  checks is the head only, so a translation of a head that the client words differently still fails closed.
- `$T` is a new token translators must keep. `translate_lint` rejects a missing, extra, misplaced or spelled-out tail.
- The untagged hook depends on `OpenMenu` calling `RegisterMenu` before the manager opens the menu, the order in the
  current source. If Blizzard reorders it, the menu shows English (safe).
- A dropdown made outside `Settings.InitDropdown` or the Edit Mode mixin is not reached; it stays English.
- The `%%` rule moves the seven listed keys that hold `%%` and no specifier from the plain-text index to the template
  index. Keys with a `%%` and a specifier were already templates.
- `verbatim` can take any text, so it is confined to `ONLY` templates; an unrestricted match never sees it.

## Alternatives considered

- **A row-level `tail` flag in the shipped data**: not used. It changes the row shape the addon reads for
  one token's worth of information; `$T` rides the existing placeholder path and old data renders unchanged.
- **Translate the chain's lines too**: rejected. They print spell names, which stay English.
- **The `MenuProxy.OnShow` registry event** (`blizzard_menu/menu.lua:1802–1806`) for untagged menus: rejected. It
  fires after the menu is laid out in English; the Japanese would need a second layout pass.
- **List each `%%` key in its plain-text form ("100%")**: rejected. It duplicates the English and breaks when the
  client's string changes; the client already prints it through `format()`.

## Related

- [ADR-007: unaligned ships with a runtime gate](007-unaligned-ships-with-runtime-gate.md)
- [ADR-031: objective lines, menus and HelpTips](031-objective-lines-menus-and-helptips.md): `Menus.TAGS`
- [ADR-032: spellbook subtexts and name titles](032-level-1-gaps-subtexts-and-name-titles.md)
- [Data model](../architecture/data-model.md) ·
  [Addon modules](../architecture/addon-modules.md) · [Pipeline](../systems/pipeline.md)
