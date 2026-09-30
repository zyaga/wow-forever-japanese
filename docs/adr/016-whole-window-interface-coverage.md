# ADR-016: Whole-window interface coverage: static labels before first show, help tooltips by owner, load-on-demand hooks, richer templates, restricted matching, never-touch widgets

- **Status:** Accepted. Implemented in `Core/UIStrings.lua` and `Core/UIStringKeys.lua`, `UI/Labels.lua`, `UI/ButtonText.lua`, `UI/Tooltip.lua`, `UI/HelpTooltip.lua`, `UI/LoadOnDemand.lua`, one module per window (`UI/Character.lua`, `Reputation`, `Skills`, `Honor`, `SpellBook`, `Talents`, `Trainer`, `GossipChrome`, `Merchant`, `Bank`, `Bags`, `Mail`, `Friends`, `Guild`, `Raid`, `MicroMenu`, `Tutorial`), `Main.lua`, `UI/Slash.lua`; pipeline `wfj/core/markup.py`, `core/status.py`, `core/model.py`, `cmd/validate.py`, `cmd/import_.py`, `io/wago.py`, `dev/ui_inventory.py`, `dev/enchant_drafts.py`, `Makefile` (`ui-source`, `ui-inventory`). In-game verification is checklist 13.
- **Date:** 2026-09-14
- **Extends:** [ADR-015](015-ui-text-surfaces.md) (targeted post-hooks over one dictionary) and [ADR-014](014-machine-drafted-text-and-ui-dictionary.md) (the `ui` type).

## Context
[ADR-015](015-ui-text-surfaces.md) put Japanese on interface words in item and spell tooltips, the quest window, the quest log and the game menu. Every other window a player keeps open (character sheet, spellbook, talents, trainer, merchant, bank, bags, mail, social, raid, micro menu) stayed English. The goal is the whole UI except names, with coverage found from the client's source rather than screenshots.

The source research ([whole-UI window inventory](../research/2026-09-14-whole-ui-window-inventory.md)) found hazards that ADR-015's mechanism does not handle on its own:
- XML `function=` script bindings and `owner.UpdateTooltip` references are captured before the addon loads, so a post-hook on the global never fires on those paths.
- Tabs measure their text on `OnShow` (`PanelTemplates_TabResize`, capped at 88 px). `PanelTemplates_SelectTab` swaps the font object after `ButtonText`'s `OnDisable` re-apply has already run.
- Help tooltips (micro buttons, stat hovers, empty slots) are written in Lua with `GameTooltip:SetText` / `AddLine`, so neither `OnTooltipSetItem` nor `OnTooltipSetSpell` fires.
- Talents, trainer and the raid roster are load-on-demand addons.
- The windows' strings use plural grammar (`|4Day:Days;`), colour wrappers and composites: a binding suffix, `"Strength:"`, a two-space join.
- Several widgets hold either a UI word or a name (the friends title on the guild tab, bag titles, reputation headers). Others are text Blizzard reads back (`OpenMailSender.Name`, `RaidGroupButtonNClass`) or sends to the server (`GuildInfoEditBox`).
- Addon code that writes `frame.selectedTab`, `SpellBookFrame.bookType` or a dropdown's `.text` taints secure item-use and casting paths.

## Decision
1. **One module per window, over the shared label step.** Each module lists its widgets, post-hooks its leaf writers by global name (never a `function=`-bound `OnShow`), and hands hits to `Labels.show` → `UIStrings.match` / `matchOnly` → `Render.show`. Surfaces: `character`, `reputation`, `skills`, `honor`, `spellbook`, `talents`, `trainer`, `gossip`, `merchant`, `bank`, `bags`, `mail`, `friends`, `friends.guild`, `raid`, and `help` (HelpTooltip's, also used by `MicroMenu`). A module may add `<surface>.static`.
   **The tutorial popup** is one more window module, `UI/Tutorial.lua` (surface `tutorial`, area `ui`). On Forever `Blizzard_FrameXML` loads the mainline `tutorialframe.lua|xml` at login (`blizzard_framexml.toc:32–33`); `TUTORIAL_TRIGGER` → `TutorialFrame_NewTutorial` → `TutorialFrame_Update(id)` (`tutorialframe.lua:227–229, 359–606`), which draws only the 8 ids `DISPLAY_DATA` lists (17 whispers, 18 grouping, 22 friends, 27 fatigue, 28 swimming, 37 broken items, 46 raids, 52 companions; `:119–182`) and writes `TutorialFrameTitle` / `TutorialFrameText` (`:494, 498`). The module post-hooks the global `TutorialFrame_Update` by name, forgets the surface on every call (a new tutorial, Prev / Next, a display-size change), then shows the title, the body, the Okay button (`CLOSE`, through `ButtonText`) and the Prev / Next buttons' unnamed FontStrings (`PREV` / `NEXT`, found with `Labels.region`, §14); it releases on `TutorialFrame`'s `OnHide`. **Restricted (§13):** each widget's `only` is its own key set (the 8 `TUTORIAL_TITLE<n>`, the 8 `TUTORIAL<n>`, `CLOSE`, `PREV`, `NEXT`), so no other dictionary word is read off the popup. **The body's refit:** the frame's height is fixed per tutorial (`tileHeight`, `:440–441`), sized for the English, and the body's scroll child is a fixed 1×1 frame (`tutorialframe.xml:126–140`), so the client's body never scrolls and a longer Japanese body would be clipped. The refit gives the scroll child the Japanese body's height, so it scrolls; the client's 1 is put back before each update and on release (the scroll bar is an in-game check). **The reveal key while it is open:** the popup takes the keyboard (`OnKeyDown`, `tutorialframe.xml:267`), so `MODIFIER_STATE_CHANGED` does not arrive and Alt would do nothing until it closed; its `OnUpdate` (hooked, runs only while shown) re-polls the modifier, as `UI/RevealBinding` does for a bound key. The Forever GlobalStrings hold only the plain keys (no race / class variant of `TUTORIAL<n>_<RACE>_<CLASS>`).
2. **Static labels before first show.** At init each module shows its load-time labels (XML `text=` and OnLoad writes) on `<surface>.static`, which is never released. The text is Japanese before the window's first show, so Blizzard's own tab `OnShow` resize measures the Japanese (`CharacterFrameTemplates.xml:84–87`). Modifier, area and master changes restore and re-apply these like every record.
3. **No layout calls from addon code.** The addon never calls `PanelTemplates_SetTab`, `UpdateTabs`, `SetDisabledTabState`, `TabResize`, `ShowUIPanel`, `HideUIPanel`, `:SetTextToFit`, `:UpdateButton` or `SpellBookFrame:Update`. It never assigns `.selectedTab`, `.bookType`, `.tooltipText` or `.UpdateTooltip`, never mentions `UIPanelWindows` or `Menu.ModifyMenu`, and calls `:SetScript(` only in `Main.lua` and `UI/Options.lua`. `tests/python/test_forbidden_calls.py` enforces the list over `addon/**/*.lua` (comments ignored). **Width limit:** a width measured once is kept. Text toggled while a window is open (Alt, area off) keeps the last measured width, and labels sized from English at OnLoad (the Activate button, the trainer and skills "All" tabs, `FriendsTabHeaderTab1/2`, the invite Accept button) stay English-sized.
   `UI/OptionsWidgets`, `UI/KeyCapture`, `UI/RevealBinding` and `UI/AddonListButton` also call `:SetScript(`, only on frames they create ([ADR-018](018-reveal-key-override-binding.md)).
4. **`hooksecurefunc(frame, method)` on Blizzard frame instances is accepted.** It stores a wrapper on the frame, but no field Blizzard reads is written. Used on `SpellBookFrame.Update`, `ShowAllSpellRanksCheckbox.UpdatePages`, `OpenAllMail.StartOpening` / `StopOpening`, dropdown `UpdateText`, `GameTooltip` methods, and `SetText` on each `SpellButtonNSubSpellName`.
5. **Scroll-box rows through Blizzard's subscriber API.** Gossip quest rows and raid-info rows use `ScrollUtil.AddInitializedFrameCallback(scrollBox, cb, owner, true)`. It is Blizzard's own subscription, not a field write, and the callbacks run through `securecallfunction` (`CallbackRegistry.lua:200–204`). Unlike the spell-load callbacks the spellbook avoids (Alternatives), these rows are not protected frames. The callback accepts both call shapes: `(frame, elementData)` from the iterate-existing pass, and `(owner, frame, elementData)` from later initializations (`ScrollUtil.lua:21–30`).
6. **Help tooltips by owner** (`UI/HelpTooltip.lua`, surface `help`). Window modules register the frames that own Lua-built tooltips (`HelpTooltip.register(owner, { only = … })`). Post-hooks on `GameTooltip:SetText`, `AppendText` and `Show` walk the tooltip, as do named client setters a module asks for (`SetTalent`, `SetPetAction`). They catch `owner:UpdateTooltip()` refreshes that call functions captured before load. The walk runs only when `GetOwner()` is registered, and never while `GetItem()` or `GetSpell()` returns something: those lines belong to the tooltip surface (ADR-010, ADR-015). Every left and right line goes through `Labels.show`, line 1 included (a title here). An `AppendText` binding suffix is handled by rewriting the line back to English + suffix before matching. One `Show()` refit per pass, only when a line changed. Release on `OnHide`.
7. **Load-on-demand hook installation** (`UI/LoadOnDemand.lua`). `LoadOnDemand.when(addon, fn)` runs `fn` now when `C_AddOns.IsAddOnLoaded`, otherwise once on that addon's `ADDON_LOADED`. `Main` keeps `ADDON_LOADED` registered after its own load, forwards other addons' names, and guards against a second own load. Users: `Blizzard_TalentUI`, `Blizzard_TrainerUI`, `Blizzard_RaidUI`.
8. **Tab fonts.** `ButtonText.init` post-hooks `PanelTemplates_SelectTab`, `DeselectTab`, `SetDisabledTabState` and `UpdateTabs` (which `EnableTab` / `DisableTab` call). After each, every adapter is checked, and one with the bundled font applied gets it back if its region lost it (a loop over the adapters on each call: cheap, but not free).
9. **Dropdown button text.** `Labels.dropdown(surface, recKey, dropdown)` post-hooks the instance's `UpdateText` and shows `dropdown.Text`. `dropdown:SetText` is a Lua override that writes `self.text` and is never called. Instances: `ClassTrainerFrame.FilterDropdown`, `WhoFrameDropdown`.
10. **Plural and markup templates** (`Core/UIStrings`).
    - A template with `|4singular:plural;` is indexed three times: all-singular, all-plural and raw. Whether `FontString:GetText()` returns the resolved or raw form is unknown.
    - More than 4 groups → not indexed, counted `unsupported` (shown by `/wfj debug ui`). The cap of 4 fits `TIME_DAYHOURMINUTESECOND`, the `/played` duration and the only listed key with 4 groups.
    - Colour codes inside a template are literal text.
    - Pipeline: `check` rejects `markup_changed:<detail>` when the Japanese does not keep the English's multiset of `|cAARRGGBB`, `|r` and line breaks, or carries a malformed `|4`. A `|4` group may be dropped in Japanese. A template with no words outside its specifiers and colour codes (`(%s)`, `%s (|cffffffff%d|r)`) needs no kana or kanji in its Japanese. Validate rule 7's ambiguity check compares the Japanese normalized the way the English is (colour codes stripped), so `Level %d` / `Level |cffffffff%d|r` with `レベル %d` / `レベル |cffffffff%d|r` are one meaning, not ambiguous.
    - Curation admits `|c` and `|4` in a key's English. `|H`, `|T`, `|A`, `|K` and `$` stay barred.
11. **Whitelisted label forms.** A `LABELS` value is one form or a list; a form reaches only the keys listed for it. `FORM_PATTERNS` grants `equip` to `^ITEM_MOD_`. New forms:
    - `bareColon` `"Strength:"`;
    - `wrapped` `|cAARRGGBB<entry or template>|r` (+ spaces). It also takes a `number`-form label inside the colour (`|cffffffffStrength 18|r`) and a two-term duration (`5 Hrs 30 Mins`, recorded under the first term's key);
    - `binding` `<entry> |cffffd200(<key>)|r`, plus the pet bar's `|cffffd200 (Ctrl-1)|r` variant;
    - `equip` `Equip: <ITEM_MOD_* template>`;
    - `colonPrefix` `<entry ending in ':'> <rest>` (`Item Sold: Linen Cloth`, `Latency: 45ms`);
    - `joined` `<template>  <template>` or `<template>  ` (`WhoList_Update`); both halves must be `joined` keys, never half Japanese;
    - `list` `<entry ending in ':'> <item>, <item>…` (the trainer's `Requires:` line, `REQUIRES_LABEL`): each item that is a `listItem` key (`TRAINER_REQ_LEVEL(_RED)`, `TRAINER_REQ_SKILL_RANK(_RED)`) is filled in Japanese; any other item (an ability name, `TRAINER_REQ_ABILITY`) stays as shown.
12. **Typed captures for the new windows** (`UIStrings.ARGS`):
    - Every other name-carrying template is `text` (verbatim): race and class in `PLAYER_LEVEL`, quest title, talent tree, pet diet, item stack, protocol names.
    - `skill` (`ITEM_REQ_SKILL`, and the skill name in `TRAINER_REQ_SKILL_RANK(_RED)`): letters, spaces, apostrophes, hyphens and commas, never digits or parentheses, so "Requires Level 40" and "Requires Engineering (225)" win their own templates.
    - `entry`: the capture must itself be a dictionary entry or template and is shown filled. `PARENS_TEMPLATE` uses it for "(Rank 2)" and "(Buyout)".
    - `time` is translated when it is one or two `UIStrings.DURATIONS` entries: `INT_SPELL_DURATION_*`, `SPELL_DURATION_*`, `*_ABBR`, `LASTONLINE_*`. Otherwise it stays verbatim.
    - **Synonyms:** keys sharing one English and one Japanese are indexed under the first, and forms, `matchOnly` and durations honour every key of the group.
    - Validate rule 7 adds `adjacent_captures_reordered`: two free-text captures (`text` / `words` / `skill` / `time`, read from `Core/UIStringKeys.lua` ARGS) separated only by whitespace must keep their order in the Japanese. The addon splits them lazily.
13. **Key-restricted matching.** `index:matchOnly(text, keys)` and `Labels.show(…, { only = keys })` accept a match only when the key (or a synonym) is in the set. Used wherever a widget may also hold a name: the friends title (never on tab 3), bag titles (backpack and keyring ids only), reputation headers, the merchant buyback title, trainer subtexts and the requirements line (`REQUIRES_LABEL`), talent and pet tooltips, and every help owner.
14. **Unnamed labels.** `Labels.region(frame, key)` finds the FontString region of `frame` whose text is the key's live English, cached per frame. Examples: bank "Item Slots", mail "To:", Prev / Next.
15. **Never-touch widgets.** Each module declares `NEVER_TOUCH` (global names, dotted paths for children: `OpenMailSender.Name`). `Main` registers them with `Labels.forbidNames` before the modules initialize, and a load-on-demand window (talents, trainer, raid roster) registers its own again when it sets up, since its widgets exist only then. `Labels.show` then refuses those widgets on any surface and drops their records. Covered: EditBoxes, name widgets, and text Blizzard reads back or sends. `tests/lua/spec/ui_nevertouch_spec.lua` checks the declarations, the refusal on any surface and the load-on-demand registration; each window's spec drives its own writers with its never-touch widgets holding dictionary words.
16. **Tooltip carry-overs.**
    - An item's `Equip: <ITEM_MOD_* template>` description-run lines become `ui` records (`装備時: ` + the filled template) only when the description surface wrote nothing on the run: no entry, or the gate refused, and no marker shown. Other run lines stay English.
    - Bag types (`ItemSubClass:1:*`) fill `CONTAINER_SLOTS`.
    - Enchantment stat lines are a new `ui` id form, `SpellItemEnchantment:<id>`: English = wago `SpellItemEnchantment.Name_lang` matching `[+-]\d+ words`, matched by fingerprint like `ItemSubClass:` rows. Enchant names ("Crusader") never match and stay English.
17. **Pipeline coverage.**
    - `make ui-source` pins Gethe/wow-ui-source `classic_era` at `33e177d9bf38d76d5c6c6e05d5da78db1899659a` into `predecessors/wow-ui-source`. `make ui-inventory` regenerates `pipeline/ui_inventory.txt`.
    - `WINDOWS` gains one entry per surface. `DYNAMIC` lists run-time-built names per surface (`SPELL_STAT\d_NAME`, `FACTION_STANDING_LABEL\d(_FEMALE)?`, slot names, `PET_TYPE_*`, `LASTONLINE_*`, `GUILDCONTROL_OPTION\d+`, `PET_ACTION_*`, `PET_MODE_*`, `GUILD_TOTAL`, `SEARCH`). The scanner also sees `..NAME..` concatenations.
    - `test_ui_coverage.py` adds surface parity (inventory surfaces = the modules' `SURFACE` / `DECLARE` constants) and one sample key per surface.
18. **Glossary additions** (terminology for the new windows, ADR-014 §10):
    - タレント for talents (following `TOOLTIP_TALENT_TIER_POINTS`);
    - フォーカス for Focus;
    - 承諾 for Accept;
    - label before number with a half-width space, e.g. enchant lines `炎呪文ダメージ +3` from a 33-phrase table (`python -m wfj.dev.enchant_drafts`);
    - pet book titles ペット / 悪魔;
    - the standings of ADR-014 §10 for reputation bars.

## Consequences
- **Dictionary:** window and help strings are machine-drafted `ui` rows; the `SpellItemEnchantment:<id>` lines are generated from the phrase table (`draft-ui-enchant`).
- **Inventory:** one surface per window; every inventoried key is either listed or excluded with a reason.
- New coverage on these windows is dictionary rows plus a module line. A window whose Blizzard addon is absent (Communities guild UI, a client without `BankFramePurchaseButton`) is skipped. `/wfj debug`'s unresolved list shows window names that are absent until a load-on-demand addon loads.
- **Records never released on hide.** Character, Reputation, Skills, Honor, Bank, Bags, Mail, Friends, Guild and Raid keep their records, because their writers run while the frame is hidden. A record whose widget the client rewrote without a hook is dropped by `Render.refresh` (ADR-015's stale rule). Gossip, Merchant, SpellBook, Talents and Trainer release their dynamic surface on `OnHide`.
- **Performance to watch:** the inbox row's `OnUpdate` re-runs its tooltip every frame while hovered, so the help walk re-matches up to two lines per frame (memoised). The Main Menu performance tooltip rebuilds about once a second.
- **Left English** (each excluded or never-touch, with its reason):
  - `TRAINER_PET_SPELL_LABEL` suffix: appended to a name widget Blizzard reads back;
  - pet level line "Level 9 Wolf" (no form carries a verbatim suffix, and "Level %d" is also `ITEM_LEVEL`) and the pet XP bar text;
  - honor `(Rank N)`: concatenated, and the title is re-anchored from its width;
  - `GUILD_TITLE_TEMPLATE` lines ("%s of %s" joins two names);
  - raid pullout labels (finding the frame means calling `RaidPullout_GetFrame`, which creates frames) and multi-unit raid resets ("3 Days 4 Hr");
  - the guild rename alert (`SetFontObject` in `GuildFrame_CheckName` would drop the bundled font);
  - `FRIENDS_LIST_REALM` / `ZONE` tooltips are not hooked;
  - `NEWBIE_TOOLTIP_XPBAR .. "\n\n" .. EXHAUST_TOOLTIP1` is one concatenated line (the XP tick title translates);
  - `FEATURE_BECOMES_AVAILABLE_AT_LEVEL` is excluded: no Vanilla micro button has `minLevel`, so the micro-button disabled-reason example is `ERR_RESTRICTED_ACCOUNT_TRIAL`.
- **Mechanism deviations:**
  - Spellbook subtext is followed through each `SpellButtonNSubSpellName`'s own `SetText`, not a `ContinueOnSpellLoad` callback. Registering one writes Blizzard's shared `SpellEventListener.callbacks` table, a taint risk for the later secure `UpdateButton`.
  - The LFG minimap button is a help owner (the only Era display of `LFG_BUTTON`).
  - `Guild` guards on `GuildFrame` existence: FriendsFrame.xml always builds it, and `useClassicGuildUI` only hides the tab.
  - The gossip surface is `gossip`, the guild surface `friends.guild`.
- **Unverified client facts** carried to checklist 13:
  - `|4` resolved vs raw from `GetText`;
  - `AppendText` onto the current vs the original text;
  - `useClassicGuildUI` and `showNewbieTips` defaults;
  - `BankFramePurchaseButton` / `GuildFrameLFGButtonText` existence;
  - what `SetPetAction` writes;
  - whether a talent tooltip returns a spell;
  - which duration templates the C client prints in cooldown lines;
  - whether random-suffix lines are `SpellItemEnchantment` text;
  - tab fonts after `SelectTab`, and taint after casting and bag use in combat.
- **Rollback** is a PR revert. Removing one window module from the TOC leaves harmless dictionary rows, and the parity test flags the orphaned inventory surface.

## Alternatives considered
- **Whole-UI `SetText` metatable hook** (ADR-015's alternative): still unproven for fonts, per-call cost and taint on this client. The per-window modules stay small because matching, rendering and fonts are shared.
- **`Menu.ModifyMenu` for dropdown and menu popup entries**: runs inside Blizzard's menu initializers, and the no-writes rule has no verdict on `AddInitializer`. Popup entries stay excluded here; only the button text is covered (menus came later, [ADR-038](038-menus-callouts-and-composite-forms.md)).
- **Our own `Spell:ContinueOnSpellLoad` callback for late spellbook subtext**: writes Blizzard's `SpellEventListener.callbacks`; a `SetText` post-hook on the subtext FontString sees the same writes with no table write.
- **Re-measuring widths** (`PanelTemplates_TabResize` after our write): calling Blizzard layout code from addon code, and a Japanese width stale again after Alt. Showing static labels before the first show gets the measurement without a call.
- **Hooking `CharacterFrame_OnShow` / `PaperDollFrame_OnShow` globals**: `function=` bindings hold the function value, so the hook never fires from the script; the leaf writers are called by name.
- **A generic `GameTooltip` `OnShow` walker**: misses lines added after the first `Show`, and the ~1 s rebuild of a shown tooltip. Sharing `tooltip.GameTooltip` would forget the tooltip surface's records. Owner-registered method hooks on a separate surface avoid all three.

## Related
- [ADR-015: UI text surfaces](015-ui-text-surfaces.md) · [ADR-014: Machine-drafted text and the UI dictionary](014-machine-drafted-text-and-ui-dictionary.md) · [ADR-009: Surfaces post-hook the writer](009-surfaces-post-hook-the-writer.md) · [ADR-010: Tooltip in-place run replacement](010-tooltip-in-place-run-replacement.md)
- [Research: whole-UI window inventory](../research/2026-09-14-whole-ui-window-inventory.md) · [Research: whole-UI text mechanism](../research/2026-09-14-whole-ui-text-mechanism.md)
- [Addon modules](../architecture/addon-modules.md) · [Pipeline](../systems/pipeline.md) · [Data model](../architecture/data-model.md) · [Testing](../testing/strategy.md): checklist 13
