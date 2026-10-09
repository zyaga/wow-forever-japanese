# Research: menus, HelpTip callouts and composite lines on Forever

- **Date:** 2026-09-25
- **Question:** A set of inventoried UI keys had been excluded while the forms to show them did not exist yet: menu and
  dropdown entries, unit menus outside level 1, strings carrying markup, HelpTip callouts and help-plate tiles, objective
  lines, the SocialUI card view and composite lines. Each needs a final disposition: listed with the surface and form
  that shows it, or excluded with a true `permanent:` reason. Which, and what has to be built?
- **Client:** World of Warcraft: Forever beta, UI extract and GlobalStrings at build **1.60.1.69913**. The camelot
  load set is the one `python -m wfj.dev.client_addons --files` reads from the client's own TOCs (3,228 files of the
  `login` / `lod` addons).
- **Citations:** `path:line`, paths relative to the extract's `interface/addons/` root, lowercased as extracted,
  unless they are repo paths (`UI/…`, `Core/…` under `addon/WoWForeverJapanese/`; `pipeline/…`). The extract is not
  committed; short quotations from it are.
- **Decisions:** [ADR-038](../adr/038-menus-callouts-and-composite-forms.md).

## Options

| Option | Pros | Cons |
|---|---|---|
| One row per key, disposition `list` / `permanent`, the surface and form named per row | A test can hold the table against the two key files; the work to build reads off it | ~600 rows |
| Keep per-group notes and reconcile while building | Less up-front work | Overlapping groups (a HelpTip callout that is also a markup string) get two answers; no single source of truth |

The first was taken: the [disposition table](#disposition-table) is the source of truth, and a test reads it.

## Findings

### Summary

604 keys, each with exactly one row, filed under the group of its surface. Every HelpTip callout and help-plate tile
is H, including the ones that also carry markup. The counts are the table's:

| group | what | list | permanent | total |
|---|---|---|---|---|
| F | menu and dropdown entries | 165 | 13 | 178 |
| U | unit menus outside level 1 | 34 | 7 | 41 |
| B | markup-carrying strings | 64 | 18 | 82 |
| H | HelpTip callouts and help-plate tiles | 47 | 9 | 56 |
| A | lines recorded as "reworded" that were in fact never drafted | 25 | 28 | 53 |
| C | objective lines | 6 | 4 | 10 |
| E | SocialUIFrame card view | 0 | 9 | 9 |
| V | composite lines | 64 | 46 | 110 |
| FU | composite forms and untriaged keys | 37 | 19 | 56 |
| D | Communities dialog leftovers | 5 | 1 | 6 |
| X | stale exclusion reasons | 2 | 1 | 3 |
| **all** | | **449** | **155** | **604** |

### Method

- Four sweeps of the extract (menus, unit menus and HelpTips; markup; composites and objective lines; the remaining
  forms) gave a verdict per key. This document merges them and resolves the overlaps.
- **A key is `permanent` only on source evidence**: the extract proves it never shows on Forever (a file camelot does
  not load, a camelot override that replaces the writer, dead code, no words of its own, or a system of another
  flavour whose gate is in the source). Everything whose reachability only the game can show is `list` with an
  in-game check (below).
- The Dragonflight crafting systems (quality, concentration, optional / finishing reagents, recraft, salvage, charges)
  follow the existing precedent (`PROFESSIONS_USE_BEST_QUALITY_REAGENTS`, `OPTIONAL_REAGENT_TOOLTIP_CLICK_TO_ADD`):
  their tooltip lines are `permanent` with the source gate cited; their HelpTips and help-plate tiles are `list`,
  because the HelpTips mechanism shows them at no extra cost if they ever fire. One in-game check covers the family.
- Colour markup in the English is no bar to listing. `|H` link labels stay verbatim. StaticPopup text is covered by
  the dialog surface ([ADR-037](../adr/037-staticpopup-dialogs-and-owned-keys.md)).
- A few keys share one English with a different meaning elsewhere ("Available", "Slots", "Ground"). They get their own
  Japanese on that screen (`UIStrings.OWN`).
- Checks against the extract: every row with a `path:line` was checked mechanically (the cited file exists, the line
  is in range, and the key itself appears at the cited line; where the decisive line is a gate or an opener, the
  evidence gives the key's line first and the gate as `context`). Every `list` row's evidence file is in the camelot
  load set. The ~55 menu tags were checked against their `SetTag(…)` lines. The 38 claims that decide `list` against
  `permanent` were checked by hand (the context-menu and utility-button mechanics, the camelot micro-menu list, the
  SocialUI gate, the camelot filter menus, the coin symbols and the rest).

## Disposition table

One row per key. `surface / form`: for `list`, the owning file(s) under `addon/WoWForeverJapanese/` and the form (an
existing one: `exact`, `template` with its `ARGS` kinds, `wrapped`, `binding`, `colon`, `colonPrefix`, `icon`,
`prefix`, an `entry` / `words` argument of another key; or a new one from "Forms and hooks"); for `permanent`, the
exact reason in `pipeline/ui_exclusions.txt`. `[in-game: …]` marks a reachability check. A `|` inside a cell is
written `\|` (unescape it when reading the table).

| key | group | disposition | surface / form | evidence |
|---|---|---|---|---|
| ACHIEVEMENT_FILTER_ALL_EXPLANATION | F | list | UI/Menus.lua TAGS MENU_ACHIEVEMENT_FILTER tooltips · exact [in-game: achievements game rule] | blizzard_achievementui/mainline/blizzard_achievementui.lua:56 · context blizzard_achievementui/mainline/blizzard_achievementui.lua:277–285 |
| ACHIEVEMENT_FILTER_COMPLETE_EXPLANATION | F | list | UI/Menus.lua TAGS MENU_ACHIEVEMENT_FILTER tooltips · exact [in-game: achievements game rule] | blizzard_achievementui/mainline/blizzard_achievementui.lua:57 · context blizzard_achievementui/mainline/blizzard_achievementui.lua:277–285 |
| ACHIEVEMENT_FILTER_INCOMPLETE_EXPLANATION | F | list | UI/Menus.lua TAGS MENU_ACHIEVEMENT_FILTER tooltips · exact [in-game: achievements game rule] | blizzard_achievementui/mainline/blizzard_achievementui.lua:57 · context blizzard_achievementui/mainline/blizzard_achievementui.lua:277–285 |
| ACHIEVEMENT_FILTER_TITLE | F | list | UI/Menus.lua TAGS MENU_ACHIEVEMENT_FILTER tooltips · exact [in-game: achievements game rule] | blizzard_achievementui/mainline/blizzard_achievementui.lua:277–285 |
| ADD_FAVORITE_STATUS | F | list | UI/Menus.lua TAGS MORE_CONTEXT_ACTIONS + UI/MenusUnit.lua BN_FRIEND, BN_FRIEND_OFFLINE · exact | blizzard_professions/blizzard_professionsframe.lua:859 · context blizzard_gamepadsharedutility/promptedbindings/promptedbinding.lua:211–238 |
| AUCTION_HOUSE_DROPDOWN_REMOVE_FAVORITE | F | list | UI/Menus.lua TAGS MENU_AUCTION_HOUSE_FAVORITE · exact | blizzard_auctionhouseui/shared/blizzard_auctionhousesharedtemplates.lua:1–19 |
| AUCTION_HOUSE_DROPDOWN_SET_FAVORITE | F | list | UI/Menus.lua TAGS MENU_AUCTION_HOUSE_FAVORITE · exact | blizzard_auctionhouseui/shared/blizzard_auctionhousesharedtemplates.lua:1–19 |
| AUCTION_HOUSE_FILTER_CATEGORY_EQUIPMENT | F | list | UI/Menus.lua TAGS MENU_AUCTION_HOUSE_SEARCH_FILTER · exact | blizzard_auctionhouseui/mainline/blizzard_auctionhouseutil.lua:37 · context blizzard_auctionhouseui/shared/blizzard_auctionhousesearchbar.lua:140–172 |
| AUCTION_HOUSE_FILTER_CATEGORY_RARITY | F | list | UI/Menus.lua TAGS MENU_AUCTION_HOUSE_SEARCH_FILTER · exact | blizzard_auctionhouseui/mainline/blizzard_auctionhouseutil.lua:38 · context blizzard_auctionhouseui/shared/blizzard_auctionhousesearchbar.lua:140–172 |
| AUCTION_HOUSE_FILTER_CURRENTEXPANSION_ONLY | F | list | UI/Menus.lua TAGS MENU_AUCTION_HOUSE_SEARCH_FILTER · exact | blizzard_auctionhouseui/mainline/blizzard_auctionhouseutil.lua:9 · context blizzard_auctionhouseui/shared/blizzard_auctionhousesearchbar.lua:140–172 |
| AUCTION_HOUSE_FILTER_DROP_DOWN_LEVEL_RANGE | F | list | UI/Menus.lua TAGS MENU_AUCTION_HOUSE_SEARCH_FILTER, MENU_PROFESSIONS_CUSTOMER_ORDER_BROWSE · exact | blizzard_auctionhouseui/shared/blizzard_auctionhousesearchbar.lua:143 |
| AUCTION_HOUSE_FILTER_RUNECARVING | F | list | UI/Menus.lua TAGS MENU_AUCTION_HOUSE_SEARCH_FILTER · exact (colour in the English is kept) [in-game: filter group present] | blizzard_auctionhouseui/mainline/blizzard_auctionhouseutil.lua:18 · context blizzard_auctionhouseui/shared/blizzard_auctionhousesearchbar.lua:140–172 |
| AUCTION_HOUSE_FILTER_UNCOLLECTED_ONLY | F | list | UI/Menus.lua TAGS MENU_AUCTION_HOUSE_SEARCH_FILTER · exact | blizzard_auctionhouseui/mainline/blizzard_auctionhouseutil.lua:7 · context blizzard_auctionhouseui/shared/blizzard_auctionhousesearchbar.lua:140–172 |
| AUCTION_HOUSE_FILTER_UPGRADES_ONLY | F | list | UI/Menus.lua TAGS MENU_AUCTION_HOUSE_SEARCH_FILTER · exact | blizzard_auctionhouseui/mainline/blizzard_auctionhouseutil.lua:10 · context blizzard_auctionhouseui/shared/blizzard_auctionhousesearchbar.lua:140–172 |
| AUCTION_HOUSE_FILTER_USABLE_ONLY | F | list | UI/Menus.lua TAGS MENU_AUCTION_HOUSE_SEARCH_FILTER · exact | blizzard_auctionhouseui/mainline/blizzard_auctionhouseutil.lua:8 · context blizzard_auctionhouseui/shared/blizzard_auctionhousesearchbar.lua:140–172 |
| AVAILABLE | F | list | listed and owned (UIStrings.OWN), the trainer filter menu (UI/Menus MENU_TRAINER_FILTER, `wrapped`) | blizzard_trainerui/mainline/blizzard_trainerui.lua:252 |
| BATTLEFIELDMINIMAP_OPACITY_LABEL | F | list | UI/Menus.lua TAGS MENU_BATTLEFIELD_MAP · exact | blizzard_battlefieldmap/mainline/blizzard_battlefieldmap.lua:48–80 |
| BATTLE_PET_FAVORITE | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_RECIPE_LIST_FAVORITE, MENU_PROFESSIONS_CRAFTER_ORDER, MENU_WARBANDSCENE_FAVORITE, MENU_PET_COLLECTION_PET, MENU_TOYBOX_FAVORITE, MENU_MOUNT_COLLECTION_MOUNT + UI/MenusUntagged.lua contextMenu (customer-orders recipe list) · exact | blizzard_professionscustomerorders/blizzard_professionscustomerordersbrowseorders.lua:139–155 |
| BATTLE_PET_UNFAVORITE | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_RECIPE_LIST_FAVORITE, MENU_PROFESSIONS_CRAFTER_ORDER, MENU_WARBANDSCENE_FAVORITE, MENU_PET_COLLECTION_PET, MENU_TOYBOX_FAVORITE, MENU_MOUNT_COLLECTION_MOUNT + UI/MenusUntagged.lua contextMenu (customer-orders recipe list) · exact | blizzard_professionscustomerorders/blizzard_professionscustomerordersbrowseorders.lua:139–155 |
| BLIZZARD_COMBAT_LOG_MENU_BOTH | F | list | UI/Menus.lua TAGS MENU_COMBAT_LOG · template ARGS {[1] = text} | blizzard_combatlog/mainline/blizzard_combatlog.lua:1107–1143 |
| BLIZZARD_COMBAT_LOG_MENU_EVERYTHING | F | list | UI/Menus.lua TAGS MENU_COMBAT_LOG · exact | blizzard_combatlog/mainline/blizzard_combatlog.lua:1122 · context blizzard_combatlog/mainline/blizzard_combatlog.lua:1491–1506 |
| BLIZZARD_COMBAT_LOG_MENU_INCOMING | F | list | UI/Menus.lua TAGS MENU_COMBAT_LOG · template ARGS {[1] = text} | blizzard_combatlog/mainline/blizzard_combatlog.lua:1107–1143 |
| BLIZZARD_COMBAT_LOG_MENU_OUTGOING | F | list | UI/Menus.lua TAGS MENU_COMBAT_LOG · template ARGS {[1] = text} | blizzard_combatlog/mainline/blizzard_combatlog.lua:1107–1143 |
| BLIZZARD_COMBAT_LOG_MENU_OUTGOING_ME | F | list | UI/Menus.lua TAGS MENU_COMBAT_LOG · template ARGS {[1] = text} | blizzard_combatlog/mainline/blizzard_combatlog.lua:1107–1143 |
| BLIZZARD_COMBAT_LOG_MENU_RESET | F | list | UI/Menus.lua TAGS MENU_COMBAT_LOG · exact | blizzard_combatlog/mainline/blizzard_combatlog.lua:1131 · context blizzard_combatlog/mainline/blizzard_combatlog.lua:1491–1506 |
| BLIZZARD_COMBAT_LOG_MENU_SAVE | F | list | UI/Menus.lua TAGS MENU_COMBAT_LOG · exact | blizzard_combatlog/mainline/blizzard_combatlog.lua:1126 · context blizzard_combatlog/mainline/blizzard_combatlog.lua:1491–1506 |
| BLIZZARD_COMBAT_LOG_MENU_SPELL_HIDE | F | list | UI/Menus.lua TAGS MENU_COMBAT_LOG · exact | blizzard_combatlog/mainline/blizzard_combatlog.lua:484 |
| BLIZZARD_COMBAT_LOG_MENU_SPELL_LINK | F | list | UI/Menus.lua TAGS MENU_COMBAT_LOG · template ARGS {[1] = text} | blizzard_combatlog/mainline/blizzard_combatlog.lua:496 · context blizzard_combatlog/mainline/blizzard_combatlog.lua:1107–1143 |
| BN_TOAST_ONLINE | F | list | UI/BNetToast.lua BOTTOM · wrapped (its LABELS entry, the existing line kept) | blizzard_bnet/mainline/bnet.lua:237 |
| BOSSES_KILLED | F | list | UI/GroupFinder.lua HelpTooltip.register (listing lockout frame) · template (numbers) | blizzard_groupfinder_vanillastyle/mainline/blizzard_lfgvanilla_listing.xml:224–226 |
| BUTTON_LAG_AUCTIONHOUSE | F | list | UI/Menus.lua TAGS MORE_CONTEXT_ACTIONS · exact | blizzard_professions/blizzard_professionsframe.lua:954 · context blizzard_gamepadsharedutility/promptedbindings/promptedbinding.lua:211–238 |
| CALENDAR_ACCEPT_INVITATION | F | list | UI/Menus.lua TAGS MENU_CALENDAR_DAY · exact | blizzard_calendar/mainline/blizzard_calendar.lua:2199–2290 |
| CALENDAR_COPY_EVENT | F | list | UI/Menus.lua TAGS MENU_CALENDAR_DAY · exact | blizzard_calendar/mainline/blizzard_calendar.lua:2199–2290 |
| CALENDAR_CREATE_GUILD_ANNOUNCEMENT | F | list | UI/Menus.lua TAGS MENU_CALENDAR_DAY · exact | blizzard_calendar/mainline/blizzard_calendar.lua:2199–2290 |
| CALENDAR_DECLINE_INVITATION | F | list | UI/Menus.lua TAGS MENU_CALENDAR_DAY · exact | blizzard_calendar/mainline/blizzard_calendar.lua:2199–2290 |
| CALENDAR_INVITELIST_CLEARMODERATOR | F | list | UI/Menus.lua TAGS MENU_CALENDAR_CREATE_INVITE · exact | blizzard_calendar/mainline/blizzard_calendar.lua:3890–3915 |
| CALENDAR_INVITELIST_INVITETORAID | F | list | UI/Menus.lua TAGS MENU_CALENDAR_CREATE_INVITE · exact | blizzard_calendar/mainline/blizzard_calendar.lua:3890–3915 |
| CALENDAR_INVITELIST_SETINVITESTATUS | F | list | UI/Menus.lua TAGS MENU_CALENDAR_CREATE_INVITE · exact | blizzard_calendar/mainline/blizzard_calendar.lua:3890–3915 |
| CALENDAR_INVITELIST_SETMODERATOR | F | list | UI/Menus.lua TAGS MENU_CALENDAR_CREATE_INVITE · exact | blizzard_calendar/mainline/blizzard_calendar.lua:3890–3915 |
| CALENDAR_PASTE_EVENT | F | list | UI/Menus.lua TAGS MENU_CALENDAR_DAY · exact | blizzard_calendar/mainline/blizzard_calendar.lua:2199–2290 |
| CALENDAR_REMOVE_INVITATION | F | list | UI/Menus.lua TAGS MENU_CALENDAR_DAY · exact | blizzard_calendar/mainline/blizzard_calendar.lua:2199–2290 |
| CALENDAR_TENTATIVE_INVITATION | F | list | UI/Menus.lua TAGS MENU_CALENDAR_DAY · exact | blizzard_calendar/mainline/blizzard_calendar.lua:2199–2290 |
| CLICK_CHEST_TO_CLAIM_REWARD | F | list | UI/RecruitAFriend.lua + UI/HelpTooltip.lua tooltipFrame (EmbeddedItemTooltip, activity-button owner) · exact | blizzard_recruitafriend/recruitafriendframe.lua:548 |
| CONTENT_TRACKING_OPEN_JOURNAL_OPTION | F | list | UI/Menus.lua TAGS MENU_OBJECTIVE_TRACKER · exact | blizzard_objectivetracker/blizzard_adventureobjectivetracker.lua:70–74 |
| CONTEXT_ACTION_LABEL_SEE_IN_BAG | F | list | UI/Menus.lua TAGS MORE_CONTEXT_ACTIONS · exact | blizzard_professions/blizzard_professionscraftingoutputlog.lua:473 · context blizzard_gamepadsharedutility/promptedbindings/promptedbinding.lua:211–238 |
| COOLDOWN_VIEWER_SETTINGS_ADD_ALERT | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_ITEM · template (numbers) | blizzard_cooldownviewer/cooldownviewersettings.lua:280 |
| COOLDOWN_VIEWER_SETTINGS_ADD_ALERT_TOOLTIP_DISABLED_TOO_MANY | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_ITEM tooltips · exact | blizzard_cooldownviewer/cooldownviewersettings.lua:1782 · context blizzard_cooldownviewer/cooldownviewersettings.lua:288–293 |
| COOLDOWN_VIEWER_SETTINGS_ADD_NEW_ALERT | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_ITEM · exact | blizzard_cooldownviewer/cooldownviewersettings.lua:278 · context blizzard_cooldownviewer/cooldownviewersettings.lua:344–360 |
| COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_TOOLTIP_DELETE | F | list | UI/Menus.lua utilityTooltip (MENU_COOLDOWN_SETTINGS_ITEM utility buttons) · exact | blizzard_cooldownviewer/cooldownviewersettingsalerts.lua:202–234 |
| COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_TOOLTIP_EDIT | F | list | UI/Menus.lua utilityTooltip (MENU_COOLDOWN_SETTINGS_ITEM utility buttons) · exact | blizzard_cooldownviewer/cooldownviewersettingsalerts.lua:202–234 |
| COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_PLAY_SAMPLE | F | list | UI/Menus.lua utilityTooltip (MENU_COOLDOWN_SETTINGS_ITEM utility buttons) · exact | blizzard_cooldownviewer/cooldownviewersettingsalerts.lua:202–234 |
| COOLDOWN_VIEWER_SETTINGS_ASSIGN_TO_CATEGORY | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_ITEM · template ARGS {[1] = text} | blizzard_cooldownviewer/cooldownviewersettings.lua:104 |
| COOLDOWN_VIEWER_SETTINGS_ASSIGN_TO_EMPTY_CATEGORY | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_ITEM · exact | blizzard_cooldownviewer/cooldownviewersettings.lua:102 · context blizzard_cooldownviewer/cooldownviewersettings.lua:344–360 |
| COOLDOWN_VIEWER_SETTINGS_CHARACTER_LAYOUTS_HEADER | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_LAYOUTS · wrapped + template ARGS {[1] = text} | blizzard_cooldownviewer/cooldownviewersettings.lua:1097 |
| COOLDOWN_VIEWER_SETTINGS_CLEAR_ALL_ALERTS | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_ITEM · exact | blizzard_cooldownviewer/cooldownviewersettings.lua:302 · context blizzard_cooldownviewer/cooldownviewersettings.lua:344–360 |
| COOLDOWN_VIEWER_SETTINGS_COPY_LAYOUT | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_LAYOUTS · exact | blizzard_cooldownviewer/cooldownviewersettings.lua:1086–1197 |
| COOLDOWN_VIEWER_SETTINGS_COPY_TO_CLIPBOARD | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_LAYOUTS · exact (same English as the shipped HUD_EDIT_MODE_COPY_TO_CLIPBOARD) | blizzard_cooldownviewer/cooldownviewersettings.lua:1187 |
| COOLDOWN_VIEWER_SETTINGS_DELETE_LAYOUT | F | list | UI/Menus.lua utilityTooltip (MENU_COOLDOWN_SETTINGS_LAYOUTS utility buttons) · exact | blizzard_cooldownviewer/cooldownviewersettings.lua:1143–1151 |
| COOLDOWN_VIEWER_SETTINGS_ERROR_CANNOT_COPY_DEFAULT_LAYOUT | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_LAYOUTS tooltips · exact | blizzard_cooldownviewer/cooldownviewersettings.lua:1086–1197 |
| COOLDOWN_VIEWER_SETTINGS_ERROR_CANNOT_COPY_DEFAULT_LAYOUT_LINE | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_LAYOUTS tooltips · exact | blizzard_cooldownviewer/cooldownviewersettings.lua:1086–1197 |
| COOLDOWN_VIEWER_SETTINGS_ERROR_CANNOT_SWITCH_TO_LAYOUT | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_LAYOUTS tooltips · exact | blizzard_cooldownviewer/cooldownviewersettings.lua:1086–1197 |
| COOLDOWN_VIEWER_SETTINGS_ERROR_CANNOT_SWITCH_TO_LAYOUT_TOOLTIP_LINE | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_LAYOUTS tooltips · template ARGS {[1] = text, [2] = text} | blizzard_cooldownviewer/cooldownviewersettings.lua:1118 |
| COOLDOWN_VIEWER_SETTINGS_RENAME_LAYOUT | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_LAYOUTS · exact | blizzard_cooldownviewer/cooldownviewersettings.lua:1086–1197 |
| COOLDOWN_VIEWER_SETTINGS_RENAME_OR_COPY_LAYOUT | F | list | UI/Menus.lua utilityTooltip (MENU_COOLDOWN_SETTINGS_LAYOUTS utility buttons) · exact | blizzard_cooldownviewer/cooldownviewersettings.lua:1143–1151 |
| COOLDOWN_VIEWER_SETTINGS_RESET_LAYOUT_TO_DEFAULT | F | list | UI/Menus.lua TAGS COOLDOWN_VIEWER_SETTINGS_MENU · exact | blizzard_cooldownviewer/cooldownviewersettings.lua:943–951 |
| COOLDOWN_VIEWER_SETTINGS_SHOW_OPTIONS | F | list | UI/Menus.lua TAGS COOLDOWN_VIEWER_SETTINGS_MENU · exact | blizzard_cooldownviewer/cooldownviewersettings.lua:943–951 |
| COOLDOWN_VIEWER_SETTINGS_SHOW_UNLEARNED | F | list | UI/Menus.lua TAGS COOLDOWN_VIEWER_SETTINGS_MENU · exact | blizzard_cooldownviewer/cooldownviewersettings.lua:943–951 |
| COOLDOWN_VIEWER_SETTINGS_USE_STARTER_LAYOUT | F | list | UI/Menus.lua TAGS MENU_COOLDOWN_SETTINGS_LAYOUTS · wrapped | blizzard_cooldownviewer/cooldownviewersettings.lua:1167 |
| CRAFT_IS_MAKEABLE | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_FILTER · exact | blizzard_professionstemplates/blizzard_professions.lua:1246 · context blizzard_professionstemplates/camelot/blizzard_professions.lua:1–14 |
| CURRENCY_FILTER_TYPE_CHARACTER | F | permanent | permanent: not displayed on Forever: camelot's currency window defines the filter names (blizzard_tokenui/camelot/blizzard_tokenui.lua:316–336) but builds no filter menu; MENU_CURRENCY_FRAME_FILTER is in blizzard_tokenui/mainline/blizzard_tokenui.lua:331, which camelot does not load | blizzard_tokenui/camelot/blizzard_tokenui.lua:316–336 |
| CURRENCY_FILTER_TYPE_TRANSFERABLE | F | permanent | permanent: not displayed on Forever: camelot's currency window defines the filter names (blizzard_tokenui/camelot/blizzard_tokenui.lua:316–336) but builds no filter menu; MENU_CURRENCY_FRAME_FILTER is in blizzard_tokenui/mainline/blizzard_tokenui.lua:331, which camelot does not load | blizzard_tokenui/camelot/blizzard_tokenui.lua:316–336 |
| CURRENCY_FILTER_TYPE_TRANSFERABLE_TOOLTIP | F | permanent | permanent: not displayed on Forever: camelot's currency window defines the filter names (blizzard_tokenui/camelot/blizzard_tokenui.lua:316–336) but builds no filter menu; MENU_CURRENCY_FRAME_FILTER is in blizzard_tokenui/mainline/blizzard_tokenui.lua:331, which camelot does not load | blizzard_tokenui/camelot/blizzard_tokenui.lua:316–336 |
| DAMAGE_METER_CATEGORY_ACTIONS | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_WINDOW_TRACKED_TYPE · exact | blizzard_damagemeter/damagemetersessionwindow.lua:4 · context blizzard_damagemeter/damagemetersessionwindow.lua:383–393 |
| DAMAGE_METER_CATEGORY_DAMAGE | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_WINDOW_TRACKED_TYPE · exact | blizzard_damagemeter/damagemetersessionwindow.lua:2 · context blizzard_damagemeter/damagemetersessionwindow.lua:383–393 |
| DAMAGE_METER_CATEGORY_HEALING | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_WINDOW_TRACKED_TYPE · exact | blizzard_damagemeter/damagemetersessionwindow.lua:3 · context blizzard_damagemeter/damagemetersessionwindow.lua:383–393 |
| DAMAGE_METER_COMBAT_NUMBER | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_SESSIONS · durationSuffix (Core/UIStrings.lua) | blizzard_damagemeter/damagemetersessionwindow.lua:422–428 |
| DAMAGE_METER_CURRENT_SESSION | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_SESSIONS · exact | blizzard_damagemeter/damagemetersessionwindow.lua:415–438 |
| DAMAGE_METER_HIDE_WINDOW | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_WINDOW_SETTINGS · exact | blizzard_damagemeter/damagemetersessionwindow.lua:468–517 |
| DAMAGE_METER_LOCK_WINDOW | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_WINDOW_SETTINGS · exact | blizzard_damagemeter/damagemetersessionwindow.lua:468–517 |
| DAMAGE_METER_MAKE_INTERACTABLE | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_WINDOW_SETTINGS · exact | blizzard_damagemeter/damagemetersessionwindow.lua:468–517 |
| DAMAGE_METER_MAKE_UNINTERACTABLE | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_WINDOW_SETTINGS · exact | blizzard_damagemeter/damagemetersessionwindow.lua:468–517 |
| DAMAGE_METER_OPEN_EDIT_MODE | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_WINDOW_SETTINGS · exact | blizzard_damagemeter/damagemetersessionwindow.lua:468–517 |
| DAMAGE_METER_OPEN_SETTINGS | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_WINDOW_SETTINGS · exact | blizzard_damagemeter/damagemetersessionwindow.lua:468–517 |
| DAMAGE_METER_OVERALL_SESSION | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_SESSIONS · exact | blizzard_damagemeter/damagemetersessionwindow.lua:415–438 |
| DAMAGE_METER_RESET_ALL_SESSIONS | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_WINDOW_SETTINGS · exact | blizzard_damagemeter/damagemetersessionwindow.lua:468–517 |
| DAMAGE_METER_SHOW_NEW_WINDOW | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_WINDOW_SETTINGS · exact | blizzard_damagemeter/damagemetersessionwindow.lua:468–517 |
| DAMAGE_METER_UNLOCK_WINDOW | F | list | UI/Menus.lua TAGS MENU_DAMAGE_METER_WINDOW_SETTINGS · exact | blizzard_damagemeter/damagemetersessionwindow.lua:468–517 |
| ENTER_PET_BATTLE | F | list | UI/Menus.lua TAGS MENU_QUEUE_STATUS_FRAME · exact [in-game: runtime-gated queue] | blizzard_queuestatusframe/mainline/queuestatusframe.lua:1544 · context blizzard_queuestatusframe/mainline/queuestatusframe.lua:1358–1365, 1544–1552 |
| EVENTTRACE_APPLY_DEFAULT_FILTER | F | list | UI/Menus.lua TAGS MENU_EVENT_TRACE_FILTER · exact | blizzard_eventtrace/blizzard_eventtrace.lua:464–532 |
| EVENTTRACE_LOG_CR_EVENTS | F | list | UI/Menus.lua TAGS MENU_EVENT_TRACE_FILTER · exact | blizzard_eventtrace/blizzard_eventtrace.lua:464–532 |
| EVENTTRACE_LOG_WHEN_HIDDEN | F | list | UI/Menus.lua TAGS MENU_EVENT_TRACE_FILTER · exact | blizzard_eventtrace/blizzard_eventtrace.lua:464–532 |
| EVENTTRACE_SHOW_ARGUMENTS | F | list | UI/Menus.lua TAGS MENU_EVENT_TRACE_FILTER · exact | blizzard_eventtrace/blizzard_eventtrace.lua:464–532 |
| EVENTTRACE_SHOW_SECRET_VALUES | F | list | UI/Menus.lua TAGS MENU_EVENT_TRACE_FILTER · exact | blizzard_eventtrace/blizzard_eventtrace.lua:464–532 |
| EVENTTRACE_SHOW_TIMESTAMP | F | list | UI/Menus.lua TAGS MENU_EVENT_TRACE_FILTER · exact | blizzard_eventtrace/blizzard_eventtrace.lua:464–532 |
| EXPANSION_FILTER_TEXT | F | list | UI/Menus.lua TAGS MENU_TOYBOX_FILTER · exact | blizzard_collections/mainline/blizzard_toybox.lua:116–140 |
| GROUP_BUFF_FILTER_MOVE_TO_HIDDEN | F | list | UI/Menus.lua TAGS MENU_GROUP_BUFF_FILTER_ITEM · exact | blizzard_cooldownviewer/groupbufffilter.lua:426–461 |
| GROUP_BUFF_FILTER_MOVE_TO_SHOWN | F | list | UI/Menus.lua TAGS MENU_GROUP_BUFF_FILTER_ITEM · exact | blizzard_cooldownviewer/groupbufffilter.lua:426–461 |
| GROUP_BUFF_FILTER_NEW_VISUAL_ALERT | F | list | UI/Menus.lua TAGS MENU_GROUP_BUFF_FILTER_ITEM · exact | blizzard_cooldownviewer/groupbufffilter.lua:426–461 |
| GUILDCONTROL_DISCORD_SETTINGS | F | list | UI/Menus.lua TAGS MENU_GUILD_PERMISSIONS · atlasArg (template ARGS {[1] = text} taking the \|A…\|a markup verbatim) [in-game: C_Discord.IsEnabled] | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:70–72 |
| HUD_EDIT_MODE_CHARACTER_LAYOUTS_HEADER | F | list | UI/Menus.lua TAGS MENU_EDIT_MODE_MANAGER · wrapped + template ARGS {[1] = text} | blizzard_editmode/shared/editmodemanager.lua:8 · context blizzard_editmode/shared/editmodemanager.lua:1357 |
| LEAVE_ARENA | F | list | UI/Menus.lua TAGS MENU_QUEUE_STATUS_FRAME · exact [in-game: runtime-gated queue] | blizzard_queuestatusframe/mainline/queuestatusframe.lua:1358–1365, 1544–1552 |
| LEAVE_ZONE | F | list | UI/Menus.lua TAGS MENU_QUEUE_STATUS_FRAME · template ARGS {[1] = text} [in-game: CanHearthAndResurrectFromArea] | blizzard_queuestatusframe/mainline/queuestatusframe.lua:272–280 |
| LFG_LIST_REPORT_GROUP_FOR | F | list | UI/MenusUntagged.lua contextMenu (LFG browse search-entry menu, title = leader name) · exact | blizzard_groupfinder_vanillastyle/blizzard_lfgvanilla_browse.lua:949–980 |
| LOCK_BATTLEFIELDMINIMAP | F | list | UI/Menus.lua TAGS MENU_BATTLEFIELD_MAP · exact | blizzard_battlefieldmap/mainline/blizzard_battlefieldmap.lua:48–80 |
| MOUNT_JOURNAL_FILTER_AQUATIC | F | list | UI/Menus.lua TAGS MENU_MOUNT_COLLECTION_FILTER · exact | blizzard_collections/mainline/blizzard_mountcollection.lua:954–1000 |
| MOUNT_JOURNAL_FILTER_DRAGONRIDING | F | list | UI/Menus.lua TAGS MENU_MOUNT_COLLECTION_FILTER · exact | blizzard_collections/mainline/blizzard_mountcollection.lua:954–1000 |
| MOUNT_JOURNAL_FILTER_FLYING | F | list | UI/Menus.lua TAGS MENU_MOUNT_COLLECTION_FILTER · exact | blizzard_collections/mainline/blizzard_mountcollection.lua:954–1000 |
| MOUNT_JOURNAL_FILTER_GROUND | F | list | `UI/MenusTags.lua` mount journal filter · `UIStrings.OWN` (own Japanese, 地上) | blizzard_collections/mainline/blizzard_mountcollection.lua:954–1000 |
| MOUNT_JOURNAL_FILTER_RIDEALONG | F | list | UI/Menus.lua TAGS MENU_MOUNT_COLLECTION_FILTER · exact | blizzard_collections/mainline/blizzard_mountcollection.lua:954–1000 |
| MOUNT_JOURNAL_FILTER_TYPE | F | list | UI/Menus.lua TAGS MENU_MOUNT_COLLECTION_FILTER · exact | blizzard_collections/mainline/blizzard_mountcollection.lua:954–1000 |
| MOUNT_JOURNAL_FILTER_UNUSABLE | F | list | UI/Menus.lua TAGS MENU_MOUNT_COLLECTION_FILTER · exact | blizzard_collections/mainline/blizzard_mountcollection.lua:954–1000 |
| NOT_COLLECTED | F | list | UI/Menus.lua TAGS MENU_TRANSMOG_SETS_FILTER, MENU_PET_COLLECTION_FILTER, MENU_TOYBOX_FILTER, MENU_WARDROBE_BASE_SETS_FILTER, MENU_MOUNT_COLLECTION_FILTER, MENU_HEIRLOOMS_FILTER · exact | blizzard_collections/classic/blizzard_petcollection.lua:100–106 |
| OBJECTIVES_VIEW_ACHIEVEMENT | F | list | UI/Menus.lua TAGS MENU_ACHIEVEMENT_TRACKER · exact | blizzard_objectivetracker/blizzard_achievementobjectivetracker.lua:75–79 |
| OBJECTIVES_VIEW_IN_ENDEAVORS_TAB | F | permanent | permanent: not displayed on Forever: the endeavors block's context menu (blizzard_objectivetracker/blizzard_initiativetasksobjectivetracker.lua:47–50); the module has content only through Blizzard_HousingDashboard, which camelot does not load (see TRACKER_HEADER_INITIATIVE_TASKS) | blizzard_objectivetracker/blizzard_initiativetasksobjectivetracker.lua:47–50 |
| OBJECTIVES_VIEW_IN_TRAVELERS_LOG | F | permanent | permanent: not displayed on Forever: the monthly-activities block's context menu (blizzard_objectivetracker/blizzard_monthlyactivitiesobjectivetracker.lua:53–56); the module has content only through the Encounter Journal, which camelot does not load (see TRACKER_HEADER_MONTHLY_ACTIVITIES) | blizzard_objectivetracker/blizzard_monthlyactivitiesobjectivetracker.lua:53–56 |
| PET_FAMILIES | F | permanent | permanent: not displayed on Forever: only in the shared pet journal filter menu (blizzard_collections/shared/blizzard_petcollection.lua:118–210), whose PetJournal_InitFilterDropdown camelot replaces (blizzard_collections/classic/blizzard_petcollection.lua:48–108, loaded after it, blizzard_collections.toc:29–33) with a Collected / Not Collected menu | blizzard_collections/shared/blizzard_petcollection.lua:192 · context blizzard_collections/classic/blizzard_petcollection.lua:48–108 |
| PET_FILTER_BATTLE_PETS | F | permanent | permanent: not displayed on Forever: only in the shared pet journal filter menu (blizzard_collections/shared/blizzard_petcollection.lua:118–210), whose PetJournal_InitFilterDropdown camelot replaces (blizzard_collections/classic/blizzard_petcollection.lua:48–108, loaded after it, blizzard_collections.toc:29–33) with a Collected / Not Collected menu | blizzard_collections/shared/blizzard_petcollection.lua:184 · context blizzard_collections/classic/blizzard_petcollection.lua:48–108 |
| PET_FILTER_NON_COMBAT_PETS | F | permanent | permanent: not displayed on Forever: only in the shared pet journal filter menu (blizzard_collections/shared/blizzard_petcollection.lua:118–210), whose PetJournal_InitFilterDropdown camelot replaces (blizzard_collections/classic/blizzard_petcollection.lua:48–108, loaded after it, blizzard_collections.toc:29–33) with a Collected / Not Collected menu | blizzard_collections/shared/blizzard_petcollection.lua:188 · context blizzard_collections/classic/blizzard_petcollection.lua:48–108 |
| PET_FILTER_TYPES | F | permanent | permanent: not displayed on Forever: only in the shared pet journal filter menu (blizzard_collections/shared/blizzard_petcollection.lua:118–210), whose PetJournal_InitFilterDropdown camelot replaces (blizzard_collections/classic/blizzard_petcollection.lua:48–108, loaded after it, blizzard_collections.toc:29–33) with a Collected / Not Collected menu | blizzard_collections/shared/blizzard_petcollection.lua:182 · context blizzard_collections/classic/blizzard_petcollection.lua:48–108 |
| PET_JOURNAL_FILTER_USABLE_ONLY | F | list | UI/Menus.lua TAGS MENU_TOYBOX_FILTER · exact | blizzard_collections/mainline/blizzard_toybox.lua:116–140 |
| PLAYER_DIFFICULTY1 | F | list | UI/Menus.lua TAGS MENU_RAID_FRAME_DIFFICULTY · exact | blizzard_compactraidframes/mainline/blizzard_compactraidframemanager.lua:214–258 |
| PLAYER_DIFFICULTY2 | F | list | UI/Menus.lua TAGS MENU_RAID_FRAME_DIFFICULTY · exact | blizzard_compactraidframes/mainline/blizzard_compactraidframemanager.lua:214–258 |
| PLAYER_DIFFICULTY6 | F | list | UI/Menus.lua TAGS MENU_RAID_FRAME_DIFFICULTY · exact | blizzard_compactraidframes/mainline/blizzard_compactraidframemanager.lua:214–258 |
| PROFESSIONS_LISTING_DURATION_ONE | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_CUSTOMER_ORDER_DURATION · exact [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:592–596 |
| PROFESSIONS_LISTING_DURATION_THREE | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_CUSTOMER_ORDER_DURATION · exact [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:592–596 |
| PROFESSIONS_LISTING_DURATION_TWO | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_CUSTOMER_ORDER_DURATION · exact [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:592–596 |
| PROFESSIONS_TRACKING_VIEW_RECIPE | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_RECIPE_TRACKER · exact | blizzard_objectivetracker/blizzard_professionsrecipetracker.lua:59–65 |
| PROFESSIONS_TRACK_RECIPE | F | list | UI/Menus.lua TAGS MORE_CONTEXT_ACTIONS · exact; + UI/Crafting.lua TrackRecipeCheckbox label · wrapped | blizzard_professions/blizzard_professionsframe.lua:860 |
| PROFESSIONS_UNTRACK_RECIPE | F | list | UI/Menus.lua TAGS MORE_CONTEXT_ACTIONS, MENU_PROFESSIONS_RECIPE_TRACKER · exact | blizzard_objectivetracker/blizzard_professionsrecipetracker.lua:59–69 |
| PROFESSION_RECIPES_IS_FIRST_CRAFT | F | permanent | permanent: not displayed on Forever: camelot's Professions.SetupFilterMenu (blizzard_professionstemplates/camelot/blizzard_professions.lua:1–14, loaded after the shared file) builds only the skill-up, makeable and slots filters; the learned / first-craft filters (blizzard_professionstemplates/blizzard_professions.lua:1218–1242) have no other caller | blizzard_professionstemplates/blizzard_professions.lua:1240 · context blizzard_professionstemplates/camelot/blizzard_professions.lua:1–14 |
| PROFESSION_RECIPES_SHOW_LEARNED | F | permanent | permanent: not displayed on Forever: camelot's Professions.SetupFilterMenu (blizzard_professionstemplates/camelot/blizzard_professions.lua:1–14, loaded after the shared file) builds only the skill-up, makeable and slots filters; the learned / first-craft filters (blizzard_professionstemplates/blizzard_professions.lua:1218–1242) have no other caller | blizzard_professionstemplates/blizzard_professions.lua:1219 · context blizzard_professionstemplates/camelot/blizzard_professions.lua:1–14 |
| PROFESSION_RECIPES_SHOW_UNLEARNED | F | permanent | permanent: not displayed on Forever: camelot's Professions.SetupFilterMenu (blizzard_professionstemplates/camelot/blizzard_professions.lua:1–14, loaded after the shared file) builds only the skill-up, makeable and slots filters; the learned / first-craft filters (blizzard_professionstemplates/blizzard_professions.lua:1218–1242) have no other caller | blizzard_professionstemplates/blizzard_professions.lua:1223 · context blizzard_professionstemplates/camelot/blizzard_professions.lua:1–14 |
| PROF_ORDER_CANT_ADD_FRIEND_OFFLINE | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_CUSTOMER_ORDER_FORM tooltips (titleIsName) · exact [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:245–323 |
| PROF_ORDER_CANT_ADD_FRIEND_WRONG_FACTION | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_CUSTOMER_ORDER_FORM tooltips (titleIsName) · exact [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:245–323 |
| PROF_ORDER_CANT_IGNORE_ALREADY_IGNORED | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_CUSTOMER_ORDER_FORM tooltips (titleIsName) · exact [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:245–323 |
| PROF_ORDER_CANT_WHISPER_OFFLINE | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_CUSTOMER_ORDER_FORM tooltips (titleIsName) · exact [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:245–323 |
| PROF_ORDER_CANT_WHISPER_WRONG_FACTION | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_CUSTOMER_ORDER_FORM tooltips (titleIsName) · exact [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:245–323 |
| PVP_REPORT_AFK_ALL | F | list | UI/Menus.lua TAGS MENU_GROUP_MEMBERS_PIN · exact | blizzard_sharedmapdataproviders/groupmembersdataprovider.lua:167–178 |
| RAF_NO_RECRUITS_DESC | F | list | UI/RecruitAFriend.lua SetNoRecruitsText post-hook (SimpleHTML) · exact (\|H link in static_links, label verbatim) | blizzard_recruitafriend/recruitafriendframe.lua:55 |
| RAF_RECRUIT_ACTIVITY_DESCRIPTION | F | list | UI/RecruitAFriend.lua + UI/HelpTooltip.lua tooltipFrame (EmbeddedItemTooltip) · template ARGS {[1] = text} | blizzard_recruitafriend/recruitafriendframe.lua:528 |
| RAID_FRAME_SORT_LABEL | F | permanent | permanent: not displayed on Forever: only in the shared pet journal filter menu (blizzard_collections/shared/blizzard_petcollection.lua:118–210), whose PetJournal_InitFilterDropdown camelot replaces (blizzard_collections/classic/blizzard_petcollection.lua:48–108, loaded after it, blizzard_collections.toc:29–33) with a Collected / Not Collected menu; its other use, the house editor (blizzard_houseeditor/blizzard_houseeditorcustomizationpettemplates.lua:178), is not loaded on camelot | blizzard_collections/shared/blizzard_petcollection.lua:208 · context blizzard_collections/classic/blizzard_petcollection.lua:48–108 |
| REMOVE_FAVORITE_STATUS | F | list | UI/Menus.lua TAGS MORE_CONTEXT_ACTIONS + UI/MenusUnit.lua BN_FRIEND, BN_FRIEND_OFFLINE · exact | blizzard_professions/blizzard_professionsframe.lua:859 · context blizzard_gamepadsharedutility/promptedbindings/promptedbinding.lua:211–238 |
| REPORT_CALENDAR | F | list | UI/Menus.lua TAGS MENU_CALENDAR_DAY · exact | blizzard_calendar/mainline/blizzard_calendar.lua:2199–2290 |
| REPORT_GROUP_FINDER_ADVERTISEMENT | F | list | UI/MenusUntagged.lua contextMenu (LFG browse search-entry menu, title = leader name) · exact | blizzard_groupfinder_vanillastyle/blizzard_lfgvanilla_browse.lua:949–980 |
| REQUEST_ROLL | F | list | UI/Menus.lua TAGS MENU_GROUP_LOOT · exact | blizzard_uipanels_game/mainline/grouplootframe.lua:201–260 |
| SHOW_BATTLEFIELDMINIMAP_PLAYERS | F | list | UI/Menus.lua TAGS MENU_BATTLEFIELD_MAP · exact | blizzard_battlefieldmap/mainline/blizzard_battlefieldmap.lua:48–80 |
| SHOW_PRIMARY_PROFESSION_ON_MAP_TEXT | F | list | UI/Menus.lua TAGS MENU_WORLD_MAP_TRACKING · exact [in-game: world-quest filters] | blizzard_worldmap/blizzard_worldmaptemplates.lua:340 · context blizzard_worldmap/blizzard_worldmaptemplates.lua:274–300, 399–401 |
| SHOW_SECONDARY_PROFESSION_ON_MAP_TEXT | F | list | UI/Menus.lua TAGS MENU_WORLD_MAP_TRACKING · exact [in-game: world-quest filters] | blizzard_worldmap/blizzard_worldmaptemplates.lua:341 · context blizzard_worldmap/blizzard_worldmaptemplates.lua:274–300, 399–401 |
| SHOW_WORLD_QUESTS_ON_MAP_TEXT | F | list | UI/Menus.lua TAGS MENU_WORLD_MAP_TRACKING · exact [in-game: world-quest filters] | blizzard_worldmap/blizzard_worldmaptemplates.lua:339 · context blizzard_worldmap/blizzard_worldmaptemplates.lua:274–300, 399–401 |
| SOCIAL_QUEUE_FORMAT_ARENA | F | list | UI/QuickJoin.lua queue lines · dash + template (numbers) [in-game: arena queues] | blizzard_uipanels_game/shared/socialqueue.lua:50–52, 137 |
| SOCIAL_QUEUE_FORMAT_ARENA_SKIRMISH | F | list | UI/QuickJoin.lua queue lines · dash [in-game: arena queues] | blizzard_uipanels_game/shared/socialqueue.lua:50–52, 137 |
| SOCIAL_SHARE_TEXT | F | list | UI/Menus.lua TAGS MORE_CONTEXT_ACTIONS · exact | blizzard_legacysystem/blizzard_legacysystem.lua:208 · context blizzard_gamepadsharedutility/promptedbindings/promptedbinding.lua:211–238 |
| SURRENDER_ARENA | F | list | UI/Menus.lua TAGS MENU_QUEUE_STATUS_FRAME · exact [in-game: runtime-gated queue] | blizzard_queuestatusframe/mainline/queuestatusframe.lua:1358–1365, 1544–1552 |
| TRADESKILL_FILTER_HAS_SKILL_UP | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_FILTER · exact | blizzard_professionstemplates/blizzard_professions.lua:1232 · context blizzard_professionstemplates/camelot/blizzard_professions.lua:1–14 |
| TRADESKILL_FILTER_SLOTS | F | list | `UI/MenusTags.lua` MENU_PROFESSIONS_FILTER · `UIStrings.OWN` (own Japanese, 装備スロット) | blizzard_professionstemplates/blizzard_professions.lua:1280 · context blizzard_professionstemplates/camelot/blizzard_professions.lua:11–13 |
| TRADESKILL_POST | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_CRAFTING_PAGE · exact | blizzard_professions/blizzard_professionscrafting.lua:367–369 |
| TRADESKILL_RECIPE_LEVEL_DROPDOWN_OPTION_FORMAT | F | list | UI/Menus.lua TAGS MENU_PROFESSIONS_RECIPE_LEVEL · template (numbers) | blizzard_professions/blizzard_professionsrecipelevel.lua:90–93 |
| TRANSMOG_ARTIFACT_OPTIONS_HEADER | F | list | UI/Menus.lua TAGS MENU_TRANSMOG_OPTIONS · exact [in-game: transmogrifier] | blizzard_transmog/blizzard_transmogtemplates.lua:488–549 |
| TRANSMOG_CUSTOM_SET_DELETE | F | list | UI/Menus.lua TAGS MENU_TRANSMOG_CUSTOM_SETS_MODEL_FILTER · wrapped [in-game: transmogrifier] | blizzard_transmog/blizzard_transmogtemplates.lua:1732 |
| TRANSMOG_CUSTOM_SET_DRESSING_ROOM | F | list | UI/Menus.lua TAGS MENU_TRANSMOG_CUSTOM_SETS_MODEL_FILTER · exact | blizzard_transmog/blizzard_transmogtemplates.lua:1709 |
| TRANSMOG_CUSTOM_SET_RENAME | F | list | UI/Menus.lua TAGS MENU_TRANSMOG_CUSTOM_SETS_MODEL_FILTER · exact | blizzard_transmog/blizzard_transmogtemplates.lua:1715 |
| TRANSMOG_CUSTOM_SET_REPLACE | F | list | UI/Menus.lua TAGS MENU_TRANSMOG_CUSTOM_SETS_MODEL_FILTER · exact | blizzard_transmog/blizzard_transmogtemplates.lua:1725 |
| TRANSMOG_EDIT_OUTFIT_SLOT | F | list | UI/Menus.lua TAGS MENU_TRANSMOG_OUTFIT_ENTRY · exact | blizzard_transmog/blizzard_transmogtemplates.lua:34 |
| TRANSMOG_ITEM_SET_FAVORITE | F | list | UI/Menus.lua TAGS MENU_TRANSMOG_SETS_MODEL_FILTER, MENU_WARDROBE_SETS_SET, MENU_WARDROBE_SETS_SET_DETAIL, MENU_WARDROBE_ITEMS_MODEL_FILTER · exact | blizzard_transmog/blizzard_transmogtemplates.lua:1506 |
| TRANSMOG_ITEM_UNSET_FAVORITE | F | list | UI/Menus.lua TAGS MENU_TRANSMOG_SETS_MODEL_FILTER, MENU_WARDROBE_SETS_SET, MENU_WARDROBE_SETS_SET_DETAIL, MENU_WARDROBE_ITEMS_MODEL_FILTER · exact | blizzard_transmog/blizzard_transmogtemplates.lua:1506 |
| TRANSMOG_SETS_FAVORITE_WITH_DESCRIPTION | F | list | UI/Menus.lua TAGS MENU_WARDROBE_SETS_SET · template ARGS {[1] = text} | blizzard_collections/shared/blizzard_wardrobe_sets.lua:579–587 |
| TRANSMOG_SETS_UNFAVORITE_WITH_DESCRIPTION | F | list | UI/Menus.lua TAGS MENU_WARDROBE_SETS_SET · template ARGS {[1] = text} | blizzard_collections/shared/blizzard_wardrobe_sets.lua:579–587 |
| TRANSMOG_SET_OPEN_COLLECTION | F | list | UI/Menus.lua TAGS MENU_TRANSMOG_SETS_MODEL_FILTER · exact | blizzard_transmog/blizzard_transmogtemplates.lua:1511 |
| TRANSMOG_SET_PVE | F | list | UI/Menus.lua TAGS MENU_TRANSMOG_SETS_FILTER, MENU_WARDROBE_BASE_SETS_FILTER · exact | blizzard_collections/mainline/blizzard_wardrobe.lua:101–111 |
| TRANSMOG_SET_PVP | F | list | UI/Menus.lua TAGS MENU_TRANSMOG_SETS_FILTER, MENU_WARDROBE_BASE_SETS_FILTER · exact | blizzard_collections/mainline/blizzard_wardrobe.lua:101–111 |
| VOICE_TOOLTIP_PARENTAL_MUTE_MIC | F | list | UI/Channels.lua MUTE_TIP · binding (LABELS grant; the \|n\|n is inside the English) | blizzard_voicetogglebutton/voicetogglebutton.lua:60–69 |
| VOICE_TOOLTIP_PARENTAL_UNMUTE_MIC | F | list | UI/Channels.lua MUTE_TIP · binding (LABELS grant; the \|n\|n is inside the English) | blizzard_voicetogglebutton/voicetogglebutton.lua:60–69 |
| VOICE_TOOLTIP_SILENCED_MUTE_MIC | F | list | UI/Channels.lua MUTE_TIP · binding (LABELS grant; the \|n\|n is inside the English) | blizzard_voicetogglebutton/voicetogglebutton.lua:60–69 |
| VOICE_TOOLTIP_SILENCED_UNMUTE_MIC | F | list | UI/Channels.lua MUTE_TIP · binding (LABELS grant; the \|n\|n is inside the English) | blizzard_voicetogglebutton/voicetogglebutton.lua:60–69 |
| WORLD_MAP_FILTER_LABEL_WORLD_QUESTS_SUBMENU_TYPE | F | list | UI/Menus.lua TAGS MENU_WORLD_MAP_TRACKING · exact [in-game: world-quest filters] | blizzard_worldmap/blizzard_worldmaptemplates.lua:274–300, 399–401 |
| WORLD_QUESTS_FILTER_DESCRIPTION | F | list | UI/Menus.lua TAGS MENU_WORLD_MAP_TRACKING tooltips · exact [in-game: world-quest filters] | blizzard_worldmap/blizzard_worldmaptemplates.lua:339 · context blizzard_worldmap/blizzard_worldmaptemplates.lua:274–300 |
| WORLD_QUEST_REWARD_FILTERS_TITLE | F | list | UI/Menus.lua TAGS MENU_WORLD_MAP_TRACKING · exact [in-game: world-quest filters] | blizzard_worldmap/blizzard_worldmaptemplates.lua:274–300, 399–401 |
| WOW_LABS_LEAVE_QUEUE | F | list | UI/Menus.lua TAGS MENU_QUEUE_STATUS_FRAME · exact [in-game: runtime-gated queue] | blizzard_queuestatusframe/mainline/queuestatusframe.lua:1519 · context blizzard_queuestatusframe/mainline/queuestatusframe.lua:1358–1365, 1544–1552 |
| BATTLETAG_REMOVE_FRIEND_CONFIRMATION | U | permanent | permanent: shown only in a StaticPopup (ADR-015 §5): StaticPopup_Show("CONFIRM_REMOVE_BN_FRIEND") (blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:581–600) | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:581–600 |
| BN_BLOCK_FRIEND | U | permanent | permanent: not displayed in game: only in the GLUE_FRIEND / GLUE_FRIEND_OFFLINE menus (blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:636), chosen only on the login screen (C_Glue.IsOnGlueScreen, blizzard_friendsframe/camelot/friendsframe.lua:220, 245), where no addon runs | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:637 · context blizzard_friendsframe/camelot/friendsframe.lua:220, 245 |
| CHAT_OWNER | U | list | UI/MenusUnit.lua CHAT_ROSTER (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:2779 · context blizzard_channels/mainline/rosterbutton.lua:181 |
| COMMUNITIES_LIST_DROP_DOWN_CLEAR_UNREAD_NOTIFICATIONS | U | list | UI/MenusUnit.lua GUILDS_GUILD, COMMUNITIES_COMMUNITY (new `which` lists) · exact (title = club name, titleIsName) | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:3166 · context blizzard_communities/communitieslist.lua:802–804 |
| COMMUNITIES_LIST_DROP_DOWN_COMMUNITIES_NOTIFICATION_SETTINGS | U | list | UI/MenusUnit.lua GUILDS_GUILD, COMMUNITIES_COMMUNITY (new `which` lists) · exact (title = club name, titleIsName) | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:3156 · context blizzard_communities/communitieslist.lua:802–804 |
| COMMUNITIES_LIST_DROP_DOWN_COMMUNITIES_SETTINGS | U | list | UI/MenusUnit.lua COMMUNITIES_COMMUNITY (new `which` lists) · exact (titleIsName) | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:3135 · context blizzard_communities/communitieslist.lua:802–804 |
| COMMUNITIES_LIST_DROP_DOWN_FAVORITE | U | list | UI/MenusUnit.lua COMMUNITIES_COMMUNITY (new `which` lists) · exact (titleIsName) | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:3124 · context blizzard_communities/communitieslist.lua:802–804 |
| COMMUNITIES_LIST_DROP_DOWN_INVITE | U | list | UI/MenusUnit.lua GUILDS_GUILD, COMMUNITIES_COMMUNITY (new `which` lists) · exact (title = club name, titleIsName) | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:3176 · context blizzard_communities/communitieslist.lua:802–804 |
| COMMUNITIES_LIST_DROP_DOWN_LEAVE_CHARACTER_COMMUNITY | U | list | UI/MenusUnit.lua COMMUNITIES_WOW_MEMBER, COMMUNITIES_MEMBER, COMMUNITIES_COMMUNITY (new `which` lists) · exact | blizzard_unitpopup/mainline/unitpopupbuttons.lua:399–401 |
| COMMUNITIES_LIST_DROP_DOWN_LEAVE_COMMUNITY | U | list | UI/MenusUnit.lua COMMUNITIES_WOW_MEMBER, COMMUNITIES_MEMBER, COMMUNITIES_COMMUNITY (new `which` lists) · exact | blizzard_unitpopup/mainline/unitpopupbuttons.lua:399–401 |
| COMMUNITIES_LIST_DROP_DOWN_UNFAVORITE | U | list | UI/MenusUnit.lua COMMUNITIES_COMMUNITY (new `which` lists) · exact (titleIsName) | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:3124 · context blizzard_communities/communitieslist.lua:802–804 |
| COMMUNITY_MEMBER_LIST_DROP_DOWN_BATTLETAG_FRIEND | U | list | UI/MenusUnit.lua COMMUNITIES_MEMBER (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:2947 · context blizzard_unitpopupshared/unitpopupsharedmenus.lua:397 |
| COMMUNITY_MEMBER_LIST_DROP_DOWN_REMOVE | U | list | UI/MenusUnit.lua COMMUNITIES_WOW_MEMBER, COMMUNITIES_MEMBER (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:2977 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:117–137 |
| COMMUNITY_MEMBER_LIST_DROP_DOWN_ROLES | U | list | UI/MenusUnit.lua COMMUNITIES_WOW_MEMBER, COMMUNITIES_MEMBER (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:3052 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:117–137 |
| COMMUNITY_MEMBER_LIST_DROP_DOWN_SET_NOTE | U | list | UI/MenusUnit.lua COMMUNITIES_WOW_MEMBER, COMMUNITIES_MEMBER (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:3008 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:117–137 |
| DEMOTE | U | list | UI/MenusUnit.lua RAID_PLAYER, RAID (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:2011 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:59–77 |
| DISCORD_CHAT_MESSAGE_CLICK_DELETE | U | list | UI/MenusUnit.lua DISCORD_USER_SELF (new `which` lists) · exact [in-game: Discord] | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:3710 · context blizzard_uipanels_game/mainline/itemrefhandlers.lua:335–365 |
| GUILD_LEAVE | U | list | UI/MenusUnit.lua COMMUNITIES_GUILD_MEMBER (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:891 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:140–158 |
| GUILD_PROMOTE | U | list | UI/MenusUnit.lua COMMUNITIES_GUILD_MEMBER (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:870 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:140–158 |
| MAKE_MODERATOR | U | list | UI/MenusUnit.lua CHAT_ROSTER (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:2717 · context blizzard_channels/mainline/rosterbutton.lua:181 |
| PET_ABANDON | U | list | UI/MenusUnit.lua PET (new `which` lists) · exact (existing which; same English as the shipped RELEASE_PET_BUTTON_LABEL) | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:1062 |
| RAID_DIFFICULTY1 | U | permanent | permanent: not displayed on Forever: only in UnitPopupRaidDifficultyButtonMixin:GetEntries (blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:1562–1569), listed only by the mainline self menu (blizzard_unitpopup/mainline/unitpopupmenus.lua:17), which camelot's self menu (blizzard_unitpopup/camelot/unitpopupmenus.lua:2–24) replaces without it | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:1635 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:2–24 |
| RAID_DIFFICULTY2 | U | permanent | permanent: not displayed on Forever: only in UnitPopupRaidDifficultyButtonMixin:GetEntries (blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:1562–1569), listed only by the mainline self menu (blizzard_unitpopup/mainline/unitpopupmenus.lua:17), which camelot's self menu (blizzard_unitpopup/camelot/unitpopupmenus.lua:2–24) replaces without it | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:1714 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:2–24 |
| RECENT_ALLIES_MENU_BUTTON_LABEL_PIN | U | list | UI/MenusUnit.lua RECENT_ALLY, RECENT_ALLY_OFFLINE (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:3743 · context blizzard_recentallies/blizzard_recentalliestemplates.lua:357, 1050 |
| RECENT_ALLIES_MENU_BUTTON_LABEL_SET_NOTE | U | list | UI/MenusUnit.lua RECENT_ALLY, RECENT_ALLY_OFFLINE (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:3727 · context blizzard_recentallies/blizzard_recentalliestemplates.lua:357, 1050 |
| RECENT_ALLIES_MENU_BUTTON_LABEL_UNPIN | U | list | UI/MenusUnit.lua RECENT_ALLY, RECENT_ALLY_OFFLINE (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:3743 · context blizzard_recentallies/blizzard_recentalliestemplates.lua:357, 1050 |
| REMOVE_FRIEND_CONFIRMATION | U | permanent | permanent: shown only in a StaticPopup (ADR-015 §5): StaticPopup_Show("CONFIRM_REMOVE_BN_FRIEND") (blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:581–600) | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:581–600 |
| REMOVE_MODERATOR | U | list | UI/MenusUnit.lua CHAT_ROSTER (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:2748 · context blizzard_channels/mainline/rosterbutton.lua:181 |
| REMOVE_TITLE_FRIEND_CONFIRMATION | U | permanent | permanent: shown only in a StaticPopup (ADR-015 §5): StaticPopup_Show("CONFIRM_REMOVE_BN_FRIEND") (blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:581–600) | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:581–600 |
| REPORT_CLUB_MEMBER | U | list | UI/MenusUnit.lua COMMUNITIES_WOW_MEMBER, COMMUNITIES_GUILD_MEMBER, COMMUNITIES_MEMBER (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:1385 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:117–158 |
| SET_MAIN_ASSIST | U | list | UI/MenusUnit.lua RAID (new `which` lists) · exact (protected neighbours: text-only writes) | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:1996 · context blizzard_unitpopupshared/unitpopupsharedmenus.lua:163–169 |
| SET_MAIN_TANK | U | list | UI/MenusUnit.lua RAID (new `which` lists) · exact (protected neighbours: text-only writes) | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:1965 · context blizzard_unitpopupshared/unitpopupsharedmenus.lua:163–169 |
| SET_RAID_ASSISTANT | U | list | UI/MenusUnit.lua RAID_PLAYER, RAID (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:1938 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:59–77 |
| SET_RAID_LEADER | U | list | UI/MenusUnit.lua RAID_PLAYER, RAID (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:1911 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:59–77 |
| SOCIAL_UI_BATTLE_NET_FRIEND_TAGS_LABEL | U | list | UI/MenusUnit.lua BN_FRIEND, BN_FRIEND_OFFLINE (new `which` lists) · template (numbers) | blizzard_unitpopup/mainline/unitpopupbuttons.lua:62–66 |
| SOCIAL_UI_BATTLE_NET_TITLE_FRIEND_EDIT_NAME_BUTTON_LABEL | U | list | UI/MenusUnit.lua BN_FRIEND, BN_FRIEND_OFFLINE (new `which` lists) · exact | blizzard_unitpopup/mainline/unitpopupbuttons.lua:182 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:80–114 |
| UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_LEGACY_RAID | U | permanent | permanent: not displayed on Forever: only in UnitPopupRaidDifficultyButtonMixin:GetEntries (blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:1562–1569), listed only by the mainline self menu (blizzard_unitpopup/mainline/unitpopupmenus.lua:17), which camelot's self menu (blizzard_unitpopup/camelot/unitpopupmenus.lua:2–24) replaces without it | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:3469 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:2–24 |
| VIEW_FRIENDS_OF_FRIENDS | U | list | UI/MenusUnit.lua BN_FRIEND, BN_FRIEND_OFFLINE (new `which` lists) · exact | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:613 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:80–114 |
| VOICE_CHAT_SETTINGS | U | list | UI/MenusUnit.lua CHAT_ROSTER (new `which` lists) · exact [in-game: voice chat] | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:2903 · context blizzard_channels/mainline/rosterbutton.lua:181 |
| VOTE_TO_ABANDON | U | list | UI/MenusUnit.lua SELF (new `which` lists) · exact (existing which) | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:966 · context blizzard_unitpopup/camelot/unitpopupmenus.lua:22 |
| VOTE_TO_ABANDON_ON_COOLDOWN | U | list | UI/MenusUnit.lua TOOLTIPS for SELF (an element tooltip) · template ARGS {[1] = time} (\|cn markup counted) | blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:990–1000 |
| ADDON_DEPENDENCIES | B | list | UI/AddonList.lua ROW_TOOLTIP · prefix (automatic "<X>: " entry, addon names kept) | blizzard_addonlist/addonlist.lua:832–843 |
| ARACHNOPHOBIA_MODE_SUBTEXT | B | permanent | permanent: not displayed on Forever: the subtext of the arachnophobia setting, which only the mainline AccessibilityOverrides.CreateArachnophobiaSetting creates; camelot's is empty (blizzard_settingsdefinitions_frame/camelot/accessibilityoverrides.lua:9–11) | blizzard_settingsdefinitions_frame/accessibility.xml:8 · context blizzard_settingsdefinitions_frame/camelot/accessibilityoverrides.lua:9–11 |
| AUCTION_HOUSE_TOOLTIP_TIME_LEFT_LONG | B | list | UI/AuctionHouse.lua time-left cell owner · exact; also the `entry` of AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT (itemAppended) | blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:263–277 |
| AUCTION_HOUSE_TOOLTIP_TIME_LEFT_MEDIUM | B | list | UI/AuctionHouse.lua time-left cell owner · exact; also the `entry` of AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT (itemAppended) | blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:263–277 |
| AUCTION_HOUSE_TOOLTIP_TIME_LEFT_SHORT | B | list | UI/AuctionHouse.lua time-left cell owner · exact; also the `entry` of AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT (itemAppended) | blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:263–277 |
| AUCTION_HOUSE_TOOLTIP_TIME_LEFT_VERY_LONG | B | list | UI/AuctionHouse.lua time-left cell owner · exact; also the `entry` of AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT (itemAppended) | blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:263–277 |
| BONUS_VALOR_TOOLTIP | B | permanent | permanent: not displayed on Forever: a line of the dungeon-finder completion reward (blizzard_framexml/mainline/alertframesystems.lua:69–81); the dungeon finder (Blizzard_GroupFinder) is not loaded on camelot, and "%s%d" is a colour code and a number | blizzard_framexml/mainline/alertframesystems.lua:69–81 |
| CAA_SAMPLE_DISPELTTYPE | B | list | UI/SettingsKeys.lua options · the `words` argument of CAA_DEBUFF_SELF_ALERT_FORMAT_DEBUFF_TYPE (ARGS {[1] = words}) [in-game: voice chat] | blizzard_settingsdefinitions_shared/audioassist.lua:1279 |
| CAA_SAY_PLAYER_RESOURCE_FORMAT_TOOLTIP | B | list | UI/SettingsKeys.lua options · template ARGS {[1] = entry}, the existing line kept [in-game: voice chat] | blizzard_settingsdefinitions_shared/audioassist.lua:759 · context blizzard_settingsdefinitions_shared/audioassist.lua:684–700 |
| CAA_SAY_PLAYER_RESOURCE_LABEL | B | list | UI/SettingsKeys.lua options · template ARGS {[1] = entry}, the existing line kept [in-game: voice chat] | blizzard_settingsdefinitions_shared/audioassist.lua:708 · context blizzard_settingsdefinitions_shared/audioassist.lua:684–700 |
| CAA_SAY_PLAYER_RESOURCE_THROTTLE_TOOLTIP | B | list | UI/SettingsKeys.lua options · template ARGS {[1] = entry}, the existing line kept [in-game: voice chat] | blizzard_settingsdefinitions_shared/audioassist.lua:798 · context blizzard_settingsdefinitions_shared/audioassist.lua:684–700 |
| CAA_SAY_PLAYER_RESOURCE_TOOLTIP | B | list | UI/SettingsKeys.lua options · template ARGS {[1] = entry}, the existing line kept [in-game: voice chat] | blizzard_settingsdefinitions_shared/audioassist.lua:731 · context blizzard_settingsdefinitions_shared/audioassist.lua:684–700 |
| CAA_SAY_PLAYER_RESOURCE_VOICE_TOOLTIP | B | list | UI/SettingsKeys.lua options · template ARGS {[1] = entry}, the existing line kept [in-game: voice chat] | blizzard_settingsdefinitions_shared/audioassist.lua:777 · context blizzard_settingsdefinitions_shared/audioassist.lua:684–700 |
| CAA_SAY_PLAYER_RESOURCE_VOLUME_TOOLTIP | B | list | UI/SettingsKeys.lua options · template ARGS {[1] = entry}, the existing line kept [in-game: voice chat] | blizzard_settingsdefinitions_shared/audioassist.lua:819 · context blizzard_settingsdefinitions_shared/audioassist.lua:684–700 |
| COOLDOWN_VIEWER_SETTINGS_BUTTON_REVERT_CHANGES | B | list | UI/CooldownViewer.lua UndoButton · iconAfter ("<entry> \|A…\|a", Core/UIStrings.lua) | blizzard_cooldownviewer/cooldownviewersettings.lua:1208–1210 |
| COPPER_AMOUNT_SYMBOL | B | permanent | permanent: no words of its own: a coin letter after a number (blizzard_framexml/mainline/coinpickupframe.lua:36–38; blizzard_moneyframe/mainline/moneyframe.lua:266–269) | blizzard_moneyframe/mainline/moneyframe.lua:266–269 |
| COPPER_AMOUNT_TEXTURE | B | permanent | permanent: no words of its own: "%d\|T…\|t" is a number and a coin icon (blizzard_sharedxml/formattingutil.lua:90–93) | blizzard_sharedxml/formattingutil.lua:90–93 |
| CURRENCY_TRANSFER_LOG_TIME_FORMAT | B | permanent | permanent: not displayed on Forever: a line of the currency transfer log (blizzard_tokenui/blizzard_currencytransfer.lua:770), whose only opener is instantiated in blizzard_tokenui/mainline/blizzard_tokenui.xml:150, which camelot does not load | blizzard_tokenui/blizzard_currencytransfer.lua:770 |
| DEATH_RECAP_AVOIDABLE_SPELL | B | list | UI/DeathRecap.lua DamageInfo tooltip · icon (LABELS grant) | blizzard_deathrecap/mainline/blizzard_deathrecap.lua:62–68 |
| DEATH_RECAP_DEADLY_SPELL | B | list | UI/DeathRecap.lua DamageInfo tooltip · icon (LABELS grant) | blizzard_deathrecap/mainline/blizzard_deathrecap.lua:62–68 |
| DUNGEON_DIFFICULTY_BANNER_TOOLTIP | B | list | UI/InstanceDifficulty.lua guild banner owner · template ARGS {[1] = words} [in-game: guild group] | blizzard_framexml/instancedifficulty.lua:222–232 |
| ESTIMATED_TIME_TO_SELL_LABEL | B | list | UI/AuctionHouse.lua WoW Token rows · tokenSell ("\|cffffffff<entry>\|r<fragment>") | blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:4, 264 |
| EVENTTRACE_ARG_FMT | B | list | UI/EventTrace.lua TooltipLines.follow (EventTraceTooltip) · the existing line kept | blizzard_eventtrace/blizzard_eventtrace.lua:817, 832 |
| EVENTTRACE_LOG_DISCARD | B | list | UI/EventTrace.lua log rows · eventTraceRow ("[id] \|c…--- <entry> ---\|r") | blizzard_eventtrace/blizzard_eventtrace.lua:240 · context blizzard_eventtrace/blizzard_eventtrace.lua:803–809, 930–936 |
| EVENTTRACE_LOG_PAUSE | B | list | UI/EventTrace.lua log rows · eventTraceRow ("[id] \|c…--- <entry> ---\|r") | blizzard_eventtrace/blizzard_eventtrace.lua:629 · context blizzard_eventtrace/blizzard_eventtrace.lua:803–809, 930–936 |
| EVENTTRACE_LOG_PAUSE_WHILE_HIDDEN | B | list | UI/EventTrace.lua log rows · eventTraceRow ("[id] \|c…--- <entry> ---\|r") | blizzard_eventtrace/blizzard_eventtrace.lua:135 · context blizzard_eventtrace/blizzard_eventtrace.lua:803–809, 930–936 |
| EVENTTRACE_LOG_START | B | list | UI/EventTrace.lua log rows · eventTraceRow ("[id] \|c…--- <entry> ---\|r") | blizzard_eventtrace/blizzard_eventtrace.lua:129 · context blizzard_eventtrace/blizzard_eventtrace.lua:803–809, 930–936 |
| EVENTTRACE_MARKER | B | list | UI/EventTrace.lua log rows · eventTraceRow ("[id] \|c…--- <entry> ---\|r") | blizzard_eventtrace/blizzard_eventtrace.lua:229 · context blizzard_eventtrace/blizzard_eventtrace.lua:803–809, 930–936 |
| EVENTTRACE_MESSAGE_FORMAT | B | permanent | permanent: no words of its own: "--- %s ---" is the carrier of the eventTraceRow form (blizzard_eventtrace/blizzard_eventtrace.lua:932) | blizzard_eventtrace/blizzard_eventtrace.lua:932 |
| EVENTTRACE_SECRET_FMT | B | permanent | permanent: a raw argument value, never a label: the Event Trace argument formatter (blizzard_eventtrace/blizzard_eventtrace.lua:797); argument rows are never touched | blizzard_eventtrace/blizzard_eventtrace.lua:797 |
| EVENTTRACE_TIMESTAMP | B | list | UI/EventTrace.lua TooltipLines.follow (EventTraceTooltip) · the existing line kept | blizzard_eventtrace/blizzard_eventtrace.lua:832 · context blizzard_eventtrace/blizzard_eventtrace.lua:817, 832 |
| GOLD_AMOUNT_TEXTURE | B | permanent | permanent: no words of its own: "%d\|T…\|t" is a number and a coin icon (blizzard_sharedxml/formattingutil.lua:90–93) | blizzard_sharedxml/formattingutil.lua:90–93 |
| GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT | B | list | UI/GuildBank.lua GuildBankMessageFrame · guildBankLog (ARGS {[1] = verbatim}) [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:806–808 |
| GUILDBANK_LOG_QUANTITY | B | permanent | permanent: no words of its own: " x %d" appended to a guild bank log line (blizzard_guildbankui/mainline/blizzard_guildbankui.lua:764, 769), kept by the guildBankLog form | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:764, 769 |
| GUILDBANK_TAB_DEPOSIT_ONLY | B | list | UI/GuildBank.lua TabTitle · guildBankTab ("<head>  <access entry>") | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:385–398 |
| GUILDBANK_TAB_FULL_ACCESS | B | list | UI/GuildBank.lua TabTitle · guildBankTab ("<head>  <access entry>") | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:385–398 |
| GUILDBANK_TAB_LOCKED | B | list | UI/GuildBank.lua TabTitle · guildBankTab ("<head>  <access entry>") | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:385–398 |
| GUILDBANK_TAB_WITHDRAW_ONLY | B | list | UI/GuildBank.lua TabTitle · guildBankTab ("<head>  <access entry>") | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:385–398 |
| GUILD_OFFICER_PERMISSION_ACCESS_CHANNELS | B | list | UI/GuildControl.lua OfficerPermissions · lineList ("\|n"-joined) | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:471–483, 511 |
| GUILD_OFFICER_PERMISSION_DELETE_EVENTS | B | list | UI/GuildControl.lua OfficerPermissions · lineList ("\|n"-joined) | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:471–483, 511 |
| GUILD_OFFICER_PERMISSION_DELETE_MESSAGES | B | list | UI/GuildControl.lua OfficerPermissions · lineList ("\|n"-joined) | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:471–483, 511 |
| GUILD_OFFICER_PERMISSION_FINDER_LIST | B | list | UI/GuildControl.lua OfficerPermissions · lineList ("\|n"-joined) | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:471–483, 511 |
| GUILD_OFFICER_PERMISSION_GUILD_INFO | B | list | UI/GuildControl.lua OfficerPermissions · lineList ("\|n"-joined) | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:471–483, 511 |
| GUILD_OFFICER_PERMISSION_INVITE_APPLICANTS | B | list | UI/GuildControl.lua OfficerPermissions · lineList ("\|n"-joined) | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:471–483, 511 |
| GUILD_OFFICER_PERMISSION_MOTD | B | list | UI/GuildControl.lua OfficerPermissions · lineList ("\|n"-joined) | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:471–483, 511 |
| GUILD_OFFICER_PERMISSION_OFFICER_NOTES | B | list | UI/GuildControl.lua OfficerPermissions · lineList ("\|n"-joined) | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:471–483, 511 |
| GUILD_OFFICER_PERMISSION_PUBLIC_NOTES | B | list | UI/GuildControl.lua OfficerPermissions · lineList ("\|n"-joined) | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:471–483, 511 |
| GUILD_OFFICER_PERMISSION_REMOVE_FROM_VOICE | B | list | UI/GuildControl.lua OfficerPermissions · lineList ("\|n"-joined) | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:471–483, 511 |
| GUILD_OFFICER_PERMISSION_SET_DISCORD | B | list | UI/GuildControl.lua OfficerPermissions · lineList ("\|n"-joined) | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:471–483, 511 |
| GX_ADAPTER_EXTERNAL | B | list | UI/SettingsKeys.lua options (Menus SETTINGS_DROPDOWN) · template ARGS {[1] = text} | blizzard_settingsdefinitions_shared/graphics.lua:1436–1450 |
| GX_ADAPTER_LOW_POWER | B | list | UI/SettingsKeys.lua options (Menus SETTINGS_DROPDOWN) · template ARGS {[1] = text} | blizzard_settingsdefinitions_shared/graphics.lua:1436–1450 |
| HUD_EDIT_MODE_COLLAPSE_OPTIONS | B | list | UI/SettingsKeys.lua editmode (Expander.Label) · exact with the \|A…\|a atlas as a markup token | blizzard_editmode/shared/editmodemanager.lua:2916–2918 |
| HUD_EDIT_MODE_EXPAND_OPTIONS | B | list | UI/SettingsKeys.lua editmode (Expander.Label) · exact with the \|A…\|a atlas as a markup token | blizzard_editmode/shared/editmodemanager.lua:2916–2918 |
| LOOT_HISTORY_CURRENT_WINNER | B | list | UI/LootHistory.lua CurrentWinnerText · template ARGS {[1] = words} + ONLY | blizzard_framexml/mainline/loothistory.lua:150–158 |
| LOOT_HISTORY_PLAYER_DELIMITER | B | permanent | permanent: no words of its own: ", " between names or food types (blizzard_framexml/mainline/loothistory.lua:91; blizzard_framexml/pethappiness.lua:73) | blizzard_framexml/mainline/loothistory.lua:91 |
| LOOT_HISTORY_ROLL_TIE | B | list | UI/LootHistory.lua CurrentWinnerText · the `words` argument of LOOT_HISTORY_CURRENT_WINNER | blizzard_framexml/mainline/loothistory.lua:150–158 |
| LOOT_HISTORY_WAITING_ON | B | list | UI/LootHistory.lua row tooltip · prefix (automatic "<X>: " entry, names kept) | blizzard_framexml/mainline/loothistory.lua:67–104 |
| OPTION_TOOLTIP_DISABLE_CHAT_ACCOUNT_MUTE | B | list | UI/SettingsPanel.lua tooltip · paragraphsWrapped (a colour-wrapped paragraph part) [in-game: muted account] | blizzard_settingsdefinitions_frame/social.lua:21–29 |
| PET_FOOD_DELIMIT | B | permanent | permanent: no words of its own: ", " between names or food types (blizzard_framexml/mainline/loothistory.lua:91; blizzard_framexml/pethappiness.lua:73) | blizzard_framexml/pethappiness.lua:73 |
| PLAYER_CHOICE_QUALITY_STRING_COMMON | B | list | UI/PlayerChoice.lua OptionText · playerChoicePrefix ("\|c…<word>\|r\|n\|n" + server description kept) [in-game: a power choice] | blizzard_playerchoice/blizzard_playerchoicepowerchoicetemplate.lua:220 · context blizzard_playerchoice/blizzard_playerchoicepowerchoicetemplate.lua:209, 218–229 |
| PLAYER_CHOICE_QUALITY_STRING_EMPTY | B | permanent | permanent: no words of its own: "\|n\|n" (blizzard_playerchoice/blizzard_playerchoicecypheroptiontemplate.lua:77–82) | blizzard_playerchoice/blizzard_playerchoicecypheroptiontemplate.lua:77–82 |
| PLAYER_CHOICE_QUALITY_STRING_EPIC | B | list | UI/PlayerChoice.lua OptionText · playerChoicePrefix ("\|c…<word>\|r\|n\|n" + server description kept) [in-game: a power choice] | blizzard_playerchoice/blizzard_playerchoicepowerchoicetemplate.lua:223 · context blizzard_playerchoice/blizzard_playerchoicepowerchoicetemplate.lua:209, 218–229 |
| PLAYER_CHOICE_QUALITY_STRING_RARE | B | list | UI/PlayerChoice.lua OptionText · playerChoicePrefix ("\|c…<word>\|r\|n\|n" + server description kept) [in-game: a power choice] | blizzard_playerchoice/blizzard_playerchoicepowerchoicetemplate.lua:222 · context blizzard_playerchoice/blizzard_playerchoicepowerchoicetemplate.lua:209, 218–229 |
| PLAYER_CHOICE_QUALITY_STRING_UNCOMMON | B | list | UI/PlayerChoice.lua OptionText · playerChoicePrefix ("\|c…<word>\|r\|n\|n" + server description kept) [in-game: a power choice] | blizzard_playerchoice/blizzard_playerchoicepowerchoicetemplate.lua:221 · context blizzard_playerchoice/blizzard_playerchoicepowerchoicetemplate.lua:209, 218–229 |
| QUICK_JOIN_TOOLTIP_AVAILABLE_ROLES | B | list | UI/QuickJoin.lua QUEUE_LINES · colonPrefix (LABELS grant) | blizzard_uipanels_game/shared/socialqueue.lua:156–167 |
| QUICK_JOIN_TOOLTIP_AVAILABLE_ROLES_FORMAT | B | permanent | permanent: no words of its own: "%s %s" joins two role icons (blizzard_uipanels_game/shared/socialqueue.lua:166) | blizzard_uipanels_game/shared/socialqueue.lua:166 |
| RAID_DIFFICULTY | B | list | UI/ReadyCheck.lua Text · readyCheckLine ("\n<entry>: <difficulty>") [in-game: toggle-difficulty raid] | blizzard_framexml/mainline/readycheck.lua:100–108 |
| RECENT_ALLY_NOTE_FORMAT | B | permanent | permanent: no words of its own: a note icon before the player's note (blizzard_recentallies/blizzard_recentalliestemplates.lua:211–215) | blizzard_recentallies/blizzard_recentalliestemplates.lua:211–215 |
| RECENT_ALLY_TOOLTIP_LEVEL_RACE_FORMAT | B | list | UI/RecentAllies.lua ROW_TIP · template ARGS {[2] = text, [3] = text} | blizzard_recentallies/blizzard_recentalliestemplates.lua:163–167 |
| RESTRICT_CHAT_CONFIG_ENABLE | B | permanent | permanent: not displayed on Forever: passed to format(RESTRICT_CHAT_CONFIG_TOOLTIP, …) (blizzard_chatframe/mainline/chatconfigframe.lua:2344), but Forever's RESTRICT_CHAT_CONFIG_TOOLTIP has no %s, so the argument is dropped | blizzard_chatframe/mainline/chatconfigframe.lua:2344 |
| RESTRICT_CHAT_CONFIG_TOOLTIP | B | list | UI/ChatConfig.lua left check-button owners · exact (\|cn markup counted) [in-game: chat disabled] | blizzard_chatframe/mainline/chatconfigframe.lua:2342–2350 |
| SILVER_AMOUNT_SYMBOL | B | permanent | permanent: no words of its own: a coin letter after a number (blizzard_framexml/mainline/coinpickupframe.lua:36–38; blizzard_moneyframe/mainline/moneyframe.lua:266–269) | blizzard_moneyframe/mainline/moneyframe.lua:266–269 |
| SILVER_AMOUNT_TEXTURE | B | permanent | permanent: no words of its own: "%d\|T…\|t" is a number and a coin icon (blizzard_sharedxml/formattingutil.lua:90–93) | blizzard_sharedxml/formattingutil.lua:90–93 |
| SOCIAL_ENABLE_DISCORD_FUNCTIONALITY | B | list | UI/SettingsKeys.lua options · atlasArg (template ARGS {[1] = text}) [in-game: Discord] | blizzard_settingsdefinitions_frame/social.lua:304–309 |
| SPEECH_TO_TEXT_SUBTEXT | B | list | UI/SettingsKeys.lua options · exact (\|H link in static_links, label verbatim) [in-game: voice chat] | blizzard_settingsdefinitions_shared/audioassist.xml:8 |
| TEXT_TO_SPEECH_MORE_VOICES | B | list | UI/TextToSpeech.lua MoreVoicesURLContainer.Text (off NEVER_TOUCH) · exact (\|H link in static_links, label verbatim) | blizzard_chatframe/shared/texttospeechframe.xml:99 |
| TOKEN_TRY_AGAIN_LATER | B | list | UI/AuctionHouse.lua WoWTokenResults.Buyout owner · template ARGS {[1] = time} | blizzard_auctionhouseui/shared/blizzard_auctionhousewowtokenframe.lua:62–75 |
| TRADESKILL_RECIPE_LEVEL_RECIPE_FORMAT | B | list | UI/Alerts.lua recipe toast Name (key-only exception) · template ARGS {[1] = text} [in-game: recipeLevel set] | blizzard_framexml/mainline/alertframesystems.lua:996–1003 |
| TRANSMOG_ACTIVE_SLOT_TITLE_FORMAT | B | permanent | permanent: no words of its own: "$slot ($option)" is filled by gsub with a slot and an option name (blizzard_transmog/blizzard_transmog.lua:1842–1846) | blizzard_transmog/blizzard_transmog.lua:1842–1846 |
| TRANSMOG_SHEATHE_WEAPON_TOOLTIP | B | list | UI/Transmog.lua SheatheWeaponToggle.Checkbox owner · binding (LABELS grant) [in-game: transmogrifier] | blizzard_transmog/blizzard_transmog.lua:857–865 |
| TUTORIAL_TOKEN_GAME_TIME_STEP_2_BALANCE | B | list | UI/AuctionHouse.lua LeftDisplay.Tutorial3 · template ARGS {[1] = verbatim} + ONLY [in-game: balance enabled] | blizzard_auctionhouseui/shared/blizzard_auctionhousewowtokenframe.lua:360–365 |
| VIDEO_OPTIONS_RECOMMENDED | B | list | UI/SettingsPanel.lua tooltip only-list · colon (LABELS grant; same English as the shipped RECOMMENDED) | blizzard_settings_shared/blizzard_settings.lua:465–468 |
| ACCOUNT_COMPLETED_QUESTS_FILTER_TUTORIAL | H | list | UI/HelpTips.lua KEYS · exact (\|cn markup counted) | blizzard_worldmap/blizzard_worldmaptemplates.lua:377–397 |
| ACCOUNT_TRANSFERABLE_CURRENCIES_TUTORIAL | H | list | UI/HelpTips.lua KEYS · exact (\|cn markup counted) [in-game: a transferable currency] | blizzard_tokenui/camelot/blizzard_tokenui.lua:425–445 |
| ASSISTED_COMBAT_ROTATION_ACTION_BUTTON_HELPTIP | H | list | UI/HelpTips.lua KEYS · exact [in-game: needs the assisted-combat action on a bar, C_ActionBar.IsAssistedCombatAction] | blizzard_actionbar/shared/actionbutton.lua:1981–2020 |
| AUCTION_HOUSE_UNDERCUT_TUTORIAL | H | list | UI/HelpTips.lua KEYS · exact | blizzard_auctionhouseui/shared/blizzard_auctionhousesellframe.lua:509 |
| CRAFTING_ORDER_PLACED_TUTORIAL | H | list | UI/HelpTips.lua KEYS · exact [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersmyorders.lua:290 |
| CRAFTING_ORDER_TUTORIAL_OPTIONAL_REAGENTS | H | list | UI/HelpTips.lua KEYS · exact [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:693–700 |
| CRAFTING_ORDER_TUTORIAL_REAGENTS | H | list | UI/HelpTips.lua KEYS · exact [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:680–690 |
| CRAFTING_ORDER_TUTORIAL_RECRAFT | H | list | UI/HelpTips.lua KEYS · exact [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:1292 |
| EDIT_MODE_HELPTIPS_ADVANCED_OPTIONS | H | list | UI/HelpTips.lua KEYS · exact | blizzard_editmode/shared/editmodemanager.lua:2959–2985 |
| EDIT_MODE_HELPTIPS_LAYOUTS | H | list | UI/HelpTips.lua KEYS · exact | blizzard_editmode/shared/editmodemanager.lua:2959–2985 |
| EDIT_MODE_HELPTIPS_SELECT_FRAMES | H | list | UI/HelpTips.lua KEYS · exact | blizzard_editmode/shared/editmodemanager.lua:2959–2985 |
| EDIT_MODE_HELPTIPS_SHOW_HIDDEN_FRAMES | H | list | UI/HelpTips.lua KEYS · exact | blizzard_editmode/shared/editmodemanager.lua:2959–2985 |
| EMBER_COURT_MAP_HELPTIP | H | permanent | permanent: a Shadowlands HelpTip: shown only for scenario widget set 461 (Ember Court) (blizzard_objectivetracker/blizzard_scenarioobjectivetracker.lua:26–30), content with no Classic counterpart | blizzard_objectivetracker/blizzard_scenarioobjectivetracker.lua:9 · context blizzard_objectivetracker/blizzard_scenarioobjectivetracker.lua:26–30 |
| ENCOUNTER_JOURNAL_LINK_BUTTON_TUTORIAL | H | permanent | permanent: not displayed on Forever: the bonus-roll Encounter Journal link HelpTip (blizzard_uipanels_game/mainline/grouplootframe.lua:707–716) opens loot in Blizzard_EncounterJournal, which camelot does not load (blizzard_encounterjournal.toc) | blizzard_uipanels_game/mainline/grouplootframe.lua:707–716 |
| FRAME_TUTORIAL_9_0_GRRISON_LANDING_PAGE_BUTTON_CALLINGS | H | permanent | permanent: a Shadowlands HelpTip: shown only while the Type_9_0 (covenant) garrison landing button is visible (blizzard_minimap/mainline/minimap.lua:1258–1275), a system with no Classic-content counterpart | blizzard_minimap/mainline/minimap.lua:1258–1275 |
| HEIRLOOMS_JOURNAL_TUTORIAL_UPGRADE | H | list | UI/HelpTips.lua KEYS · exact | blizzard_collections/mainline/blizzard_heirloomcollection.lua:644 |
| LOOT_HISTORY_ROLL_TUTORIAL | H | list | UI/HelpTips.lua KEYS · exact | blizzard_framexml/mainline/loothistory.lua:552–563 |
| NEW_SPOKEN_LANGUAGE_HELPTIP | H | list | UI/HelpTips.lua KEYS · exact | blizzard_chatframebase/mainline/chatframemenubutton.lua:3 |
| OPTIONAL_REAGENT_TUTORIAL_SLOT | H | list | UI/HelpTips.lua KEYS · exact [in-game: optional reagent slot] | blizzard_professions/blizzard_professionscrafting.lua:1501, 1524 |
| PROFESSIONS_CRAFTING_HELP_BAR | H | list | UI/HelpTips.lua PLATE_KEYS · exact [in-game: each tile only when its widget shows] | blizzard_professions/blizzard_professionscrafting.lua:1205–1364 |
| PROFESSIONS_CRAFTING_HELP_BASIC_REAGENTS | H | list | UI/HelpTips.lua PLATE_KEYS · exact [in-game: each tile only when its widget shows] | blizzard_professions/blizzard_professionscrafting.lua:1205–1364 |
| PROFESSIONS_CRAFTING_HELP_BEST_QUALITY | H | list | UI/HelpTips.lua PLATE_KEYS · exact [in-game: each tile only when its widget shows] | blizzard_professions/blizzard_professionscrafting.lua:1205–1364 |
| PROFESSIONS_CRAFTING_HELP_FINISHING_REAGENTS | H | list | UI/HelpTips.lua PLATE_KEYS · exact [in-game: each tile only when its widget shows] | blizzard_professions/blizzard_professionscrafting.lua:1205–1364 |
| PROFESSIONS_CRAFTING_HELP_GEAR | H | list | UI/HelpTips.lua PLATE_KEYS · exact [in-game: each tile only when its widget shows] | blizzard_professions/blizzard_professionscrafting.lua:1205–1364 |
| PROFESSIONS_CRAFTING_HELP_OPTIONAL_REAGENTS | H | list | UI/HelpTips.lua PLATE_KEYS · exact [in-game: each tile only when its widget shows] | blizzard_professions/blizzard_professionscrafting.lua:1205–1364 |
| PROFESSIONS_CRAFTING_HELP_STATS | H | list | UI/HelpTips.lua PLATE_KEYS · exact [in-game: each tile only when its widget shows] | blizzard_professions/blizzard_professionscrafting.lua:1205–1364 |
| PROFESSIONS_GATHERING_JOURNAL_LIST_HELP | H | list | UI/HelpTips.lua PLATE_KEYS · exact [in-game: each tile only when its widget shows] | blizzard_professions/blizzard_professionscrafting.lua:1205–1364 |
| PROFESSIONS_GATHERING_JOURNAL_STATS_HELP | H | list | UI/HelpTips.lua PLATE_KEYS · exact [in-game: each tile only when its widget shows] | blizzard_professions/blizzard_professionscrafting.lua:1205–1364 |
| PROFESSIONS_HELP_1 | H | permanent | permanent: not displayed on Forever: the professions book help plate (blizzard_professionsbook/blizzard_professionsbook.lua:543–555) opens only from ProfessionsBook_ToggleTutorial in blizzard_professionsbook/blizzard_professionsbook.xml:27, which camelot does not load (blizzard_professionsbook.toc:11) | blizzard_professionsbook/blizzard_professionsbook.lua:543–555 |
| PROFESSIONS_HELP_2 | H | permanent | permanent: not displayed on Forever: the professions book help plate (blizzard_professionsbook/blizzard_professionsbook.lua:543–555) opens only from ProfessionsBook_ToggleTutorial in blizzard_professionsbook/blizzard_professionsbook.xml:27, which camelot does not load (blizzard_professionsbook.toc:11) | blizzard_professionsbook/blizzard_professionsbook.lua:543–555 |
| PROFESSIONS_SPECS_CAN_UNLOCK_SPEC | H | permanent | permanent: not displayed on Forever: a HelpTip on the professions specializations tab (blizzard_professions/blizzard_professionsframe.lua:340–367); camelot's ProfessionsFrame (blizzard_professions/camelot/blizzard_professionsframe.xml) builds no TabSystem or specializations page, so the tabs are never added (blizzard_professions/blizzard_professionsframe.lua:40–46) | blizzard_professions/blizzard_professionsframe.lua:340–367 |
| PROFESSIONS_SPECS_PENDING_POINTS | H | permanent | permanent: not displayed on Forever: a HelpTip on the professions specializations tab (blizzard_professions/blizzard_professionsframe.lua:340–367); camelot's ProfessionsFrame (blizzard_professions/camelot/blizzard_professionsframe.xml) builds no TabSystem or specializations page, so the tabs are never added (blizzard_professions/blizzard_professionsframe.lua:40–46) | blizzard_professions/blizzard_professionsframe.lua:340–367 |
| PROFESSIONS_TUTORIAL_FINISHING_REAGENT | H | list | UI/HelpTips.lua KEYS · exact [in-game: finishing reagent slot] | blizzard_professions/blizzard_professionscrafting.lua:1524 · context blizzard_professions/blizzard_professionscrafting.lua:1501, 1524 |
| PROFESSIONS_UNSPENT_SPEC_POINTS_REMINDER | H | permanent | permanent: not displayed on Forever: a HelpTip on the professions specializations tab (blizzard_professions/blizzard_professionsframe.lua:340–367); camelot's ProfessionsFrame (blizzard_professions/camelot/blizzard_professionsframe.xml) builds no TabSystem or specializations page, so the tabs are never added (blizzard_professions/blizzard_professionsframe.lua:40–46) | blizzard_professions/blizzard_professionsframe.lua:340–367 |
| PROFESSION_EQUIPMENT_LOCATION_HELPTIP | H | list | UI/HelpTips.lua KEYS · exact [in-game: profession tool slots] | blizzard_professions/blizzard_professions_bootstrap.lua:24–35 |
| SPEECH_TO_TEXT_TUTORIAL | H | list | UI/HelpTips.lua KEYS · exact [in-game: voice chat] | blizzard_chatframe/shared/voicechattranscriptionbutton.lua:210–220 |
| TORGHAST_REROLL_TIP | H | permanent | permanent: a Torghast HelpTip on the player-choice toggle (blizzard_playerchoice/blizzard_playerchoicetogglebutton.lua:196), a Shadowlands system with no Classic-content counterpart; its siblings TORGHAST_REROLL_* are excluded the same way | blizzard_playerchoice/blizzard_playerchoicetogglebutton.lua:196 |
| TOYBOX_FAVORITE_HELP | H | list | UI/HelpTips.lua KEYS · exact | blizzard_collections/mainline/blizzard_toybox.lua:183 · context blizzard_collections/mainline/blizzard_toybox.lua:34, 378 |
| TOYBOX_MOUSEWHEEL_PAGING_HELP | H | list | UI/HelpTips.lua KEYS · exact | blizzard_collections/mainline/blizzard_toybox.lua:34, 378 |
| TRANSMOG_CUSTOM_SETS_HELPTIP | H | list | UI/HelpTips.lua KEYS · exact [in-game: transmogrifier] | blizzard_transmog/blizzard_transmog.lua:1447 · context blizzard_transmog/blizzard_transmog.lua:377, 798, 1435–1471 |
| TRANSMOG_CUSTOM_SETS_MIGRATION_HELPTIP | H | list | UI/HelpTips.lua KEYS · exact [in-game: transmogrifier] | blizzard_transmog/blizzard_transmog.lua:1471 · context blizzard_transmog/blizzard_transmog.lua:377, 798, 1435–1471 |
| TRANSMOG_HELP_1 | H | list | UI/HelpTips.lua PLATE_KEYS · exact (\|cn markup counted) [in-game: transmogrifier] | blizzard_transmog/blizzard_transmog.lua:106–108 |
| TRANSMOG_HELP_2 | H | list | UI/HelpTips.lua PLATE_KEYS · exact (\|cn markup counted) [in-game: transmogrifier] | blizzard_transmog/blizzard_transmog.lua:106–108 |
| TRANSMOG_HELP_3 | H | list | UI/HelpTips.lua PLATE_KEYS · exact (\|cn markup counted) [in-game: transmogrifier] | blizzard_transmog/blizzard_transmog.lua:106–108 |
| TRANSMOG_OUTFITS_HELPTIP | H | list | UI/HelpTips.lua KEYS · exact [in-game: transmogrifier] | blizzard_transmog/blizzard_transmog.lua:377, 798, 1435–1471 |
| TRANSMOG_SETS_HELPTIP | H | list | UI/HelpTips.lua KEYS · exact [in-game: transmogrifier] | blizzard_transmog/blizzard_transmog.lua:1435 · context blizzard_transmog/blizzard_transmog.lua:377, 798, 1435–1471 |
| TRANSMOG_SETS_TAB_TUTORIAL | H | list | UI/HelpTips.lua KEYS · exact | blizzard_collections/mainline/blizzard_wardrobe.lua:575–584 |
| TRANSMOG_SITUATIONS_HELPTIP | H | list | UI/HelpTips.lua KEYS · exact [in-game: transmogrifier] | blizzard_transmog/blizzard_transmog.lua:1459 · context blizzard_transmog/blizzard_transmog.lua:377, 798, 1435–1471 |
| TRANSMOG_TRIAL_OF_STYLE_HELPTIP | H | list | UI/HelpTips.lua KEYS · exact [in-game: Trial of Style outfit] | blizzard_transmog/blizzard_transmog.lua:390 |
| TRANSMOG_WEAPON_OPTIONS_HELPTIP | H | list | UI/HelpTips.lua KEYS · exact [in-game: transmogrifier] | blizzard_transmog/blizzard_transmog.lua:798 · context blizzard_transmog/blizzard_transmog.lua:377, 798, 1435–1471 |
| TUTORIAL_HUD_REVAMP_LFG_QUEUE_CHANGES | H | list | UI/HelpTips.lua KEYS · exact | blizzard_queuestatusframe/mainline/queuestatusframe.lua:333–345 |
| TUTORIAL_VOICE | H | list | UI/HelpTips.lua KEYS · exact [in-game: voice channels] | blizzard_channels/mainline/channelframe.lua:235–245 |
| WARDROBE_SHORTCUTS_TUTORIAL_1 | H | list | UI/HelpTips.lua KEYS · exact | blizzard_collections/mainline/blizzard_wardrobe.lua:1552 |
| WARDROBE_SHORTCUTS_TUTORIAL_2 | H | list | UI/Wardrobe.lua the shortcuts HelpTip's appended frame FontStrings · exact | blizzard_collections/mainline/blizzard_wardrobe.xml:168, 174 |
| WARDROBE_SHORTCUTS_TUTORIAL_3 | H | list | UI/Wardrobe.lua the shortcuts HelpTip's appended frame FontStrings · exact | blizzard_collections/mainline/blizzard_wardrobe.xml:174 · context blizzard_collections/mainline/blizzard_wardrobe.xml:168, 174 |
| WARDROBE_TRACKING_TUTORIAL | H | list | UI/HelpTips.lua KEYS · exact | blizzard_collections/mainline/blizzard_wardrobe.lua:1148–1165 |
| AUCTION_HOUSE_AUCTION_SOLD_PREFIX | A | list | UI/AuctionHouse.lua auctions item cell's Prefix · exact (colour in the English) | blizzard_auctionhouseui/shared/blizzard_auctionhousetablebuilder.lua:737–742 |
| AUCTION_HOUSE_BUYER_FORMAT | A | list | UI/AuctionHouse.lua bid / buyout cell owners · template ARGS {[1] = text} | blizzard_auctionhouseui/shared/blizzard_auctionhousetablebuilder.lua:556–570, 591–597 |
| AUCTION_HOUSE_DIALOG_PER_UNIT_INCREASE | A | list | UI/AuctionHouse.lua BuyDialog notification button owner · exact (left half of a double line) | blizzard_auctionhouseui/shared/blizzard_auctionhousebuydialog.lua:31–43 |
| AUCTION_HOUSE_DIALOG_TOTAL_INCREASE | A | list | UI/AuctionHouse.lua BuyDialog notification button owner · exact (left half of a double line) | blizzard_auctionhouseui/shared/blizzard_auctionhousebuydialog.lua:31–43 |
| AUCTION_HOUSE_HIGH_BIDDER_FORMAT | A | list | UI/AuctionHouse.lua bid / buyout cell owners · template ARGS {[1] = text} | blizzard_auctionhouseui/shared/blizzard_auctionhousetablebuilder.lua:556–570, 591–597 |
| AUCTION_HOUSE_TIME_LEFT_FORMAT_ACTIVE | A | list | UI/AuctionHouse.lua time-left cell owner · template ARGS {[1] = time} | blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:390–396 |
| AUCTION_HOUSE_TIME_LEFT_FORMAT_SOLD | A | permanent | permanent: dead code: `return sold and …SOLD… or …ACTIVE…` reads a global `sold` that no file defines (blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:395), so the SOLD branch is never taken | blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:395 |
| AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT | A | list | UI/AuctionHouse.lua itemAppended (AuctionHouseUtil.AddAuctionHouseTooltipInfo) · template ARGS {[1] = entry} | blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:301–306 |
| AUCTION_HOUSE_TOOLTIP_MULTIPLE_SELLERS_FORMAT | A | list | UI/AuctionHouse.lua owners cell owner + itemAppended (AuctionHouseUtil.AddAuctionHouseTooltipInfo) · template ARGS {[1] = text} | blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:281–304 |
| AUCTION_HOUSE_TOOLTIP_OVERFLOW_SELLERS_FORMAT | A | list | UI/AuctionHouse.lua owners cell owner + itemAppended (AuctionHouseUtil.AddAuctionHouseTooltipInfo) · template ARGS {[1] = text} | blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:281–304 |
| AUCTION_HOUSE_TOOLTIP_SELLER_FORMAT | A | list | UI/AuctionHouse.lua owners cell owner + itemAppended (AuctionHouseUtil.AddAuctionHouseTooltipInfo) · template ARGS {[1] = text} | blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:281–304 |
| CAP_REACHED_TRIAL | A | permanent | permanent: a Free Trial (GameLimitedMode) line at the trial profession cap (blizzard_professionstemplates/blizzard_professionsrankbar.lua:14–19), a retail account system with no Classic counterpart (as CAPPED_LEVEL_TRIAL) | blizzard_professionstemplates/blizzard_professionsrankbar.lua:14–19 |
| CRAFTING_ORDER_RECRAFT_WARNING2 | A | permanent | permanent: not displayed on Forever: a recrafting line (Dragonflight recraft system: blizzard_professions/blizzard_professionscrafting.lua:1540–1544; blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:810–817); Forever's Vanilla recipes have no recraft | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:53 · context blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:810–817 |
| ENCHANT_TARGET_TOOLTIP_CLICK_TO_REPLACE | A | list | UI/Crafting.lua itemAppended (the enchant slot's OnEnter, after SetItemByGUID) · exact [in-game: enchant-target slot] | blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1232–1240 |
| FINISHING_REAGENT_TOOLTIP_CLICK_TO_REMOVE | A | permanent | permanent: not displayed on Forever: an optional / finishing (Modifying) reagent slot line, a Dragonflight crafting system; the slots exist only for recipes that have them (blizzard_professionstemplates/blizzard_professions.lua:560–572), and Forever's Vanilla recipes have none (as OPTIONAL_REAGENT_TOOLTIP_CLICK_TO_ADD) | blizzard_professionstemplates/blizzard_professions.lua:560–572 |
| GAIN_EXPERIENCE | A | permanent | permanent: not displayed on Forever: only in dungeon-finder reward tooltips (the LFG completion alert, blizzard_framexml/mainline/alertframesystems.lua:234; LFGDungeonReadyDialogReward, blizzard_groupfinder/shared/lfgframe.lua:868–875); Blizzard_GroupFinder is not loaded on camelot (camelot uses the Vanilla-style listing finder) | blizzard_framexml/mainline/alertframesystems.lua:234 |
| LOOT_HISTORY_OFF_SPEC_FMT | A | permanent | permanent: not displayed on Forever: shown only for roll state NeedOffSpec (blizzard_framexml/mainline/loothistory.lua:272), and no loot roll frame in the camelot load set offers an off-spec roll (the enum is read only by loothistory.lua) | blizzard_framexml/mainline/loothistory.lua:269–274 |
| OPTIONAL_REAGENT_TOOLTIP_CLICK_TO_EXCHANGE | A | permanent | permanent: not displayed on Forever: an optional / finishing (Modifying) reagent slot line, a Dragonflight crafting system; the slots exist only for recipes that have them (blizzard_professionstemplates/blizzard_professions.lua:560–572), and Forever's Vanilla recipes have none (as OPTIONAL_REAGENT_TOOLTIP_CLICK_TO_ADD) | blizzard_professionstemplates/blizzard_professions.lua:560–572 |
| OPTIONAL_REAGENT_TOOLTIP_CLICK_TO_REMOVE | A | permanent | permanent: not displayed on Forever: an optional / finishing (Modifying) reagent slot line, a Dragonflight crafting system; the slots exist only for recipes that have them (blizzard_professionstemplates/blizzard_professions.lua:560–572), and Forever's Vanilla recipes have none (as OPTIONAL_REAGENT_TOOLTIP_CLICK_TO_ADD) | blizzard_professionstemplates/blizzard_professions.lua:560–572 |
| PLAYTIME_TIRED_ABILITY | A | permanent | permanent: shown only under the anti-addiction play-time limit (PartialPlayTime / NoPlayTime, blizzard_professions/blizzard_professionscrafting.lua:798–806), a regional account system with no counterpart on Forever | blizzard_professions/blizzard_professionscrafting.lua:798–806 |
| PLAYTIME_UNHEALTHY_ABILITY | A | permanent | permanent: shown only under the anti-addiction play-time limit (PartialPlayTime / NoPlayTime, blizzard_professions/blizzard_professionscrafting.lua:798–806), a regional account system with no counterpart on Forever | blizzard_professions/blizzard_professionscrafting.lua:798–806 |
| PROFESSIONS_ALLOCATIONS_TOOLTIP | A | permanent | permanent: not displayed on Forever: part of the Dragonflight crafting-quality system, shown only for a recipe or reagent that carries crafting quality or crafting stats (supportsQualities / supportsCraftingStats gates, blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389); Forever's Vanilla recipes have none (as PROFESSIONS_USE_BEST_QUALITY_REAGENTS) | blizzard_professionstemplates/blizzard_professions.lua:510 · context blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389 |
| PROFESSIONS_ALLOCATIONS_TOOLTIP_2 | A | permanent | permanent: not displayed on Forever: part of the Dragonflight crafting-quality system, shown only for a recipe or reagent that carries crafting quality or crafting stats (supportsQualities / supportsCraftingStats gates, blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389); Forever's Vanilla recipes have none (as PROFESSIONS_USE_BEST_QUALITY_REAGENTS) | blizzard_professionstemplates/blizzard_professions.lua:506 · context blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389 |
| PROFESSIONS_CRAFTING_CONCENTRATION_HELPTIP | A | list | UI/HelpTips.lua KEYS · exact [in-game: a recipe with the Dragonflight crafting feature] | blizzard_professions/blizzard_professionscrafting.lua:1563 · context blizzard_professions/blizzard_professionscrafting.lua:1558–1559 |
| PROFESSIONS_CRAFTING_CURRENCY_LABEL_FORMAT | A | permanent | permanent: no words of its own: "%d/%d" (blizzard_professionstemplates/blizzard_professionstemplates.lua:809) | blizzard_professionstemplates/blizzard_professionstemplates.lua:809 |
| PROFESSIONS_CRAFTING_EXPECTED_QUALITY | A | permanent | permanent: not displayed on Forever: part of the Dragonflight crafting-quality system, shown only for a recipe or reagent that carries crafting quality or crafting stats (supportsQualities / supportsCraftingStats gates, blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389); Forever's Vanilla recipes have none (as PROFESSIONS_USE_BEST_QUALITY_REAGENTS) | blizzard_professionstemplates/blizzard_professionsrecipecrafterdetails.lua:166 · context blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389 |
| PROFESSIONS_CRAFTING_EXPECTED_QUALITY_WITH_CONCENTRATION | A | permanent | permanent: not displayed on Forever: part of the Dragonflight crafting-quality system, shown only for a recipe or reagent that carries crafting quality or crafting stats (supportsQualities / supportsCraftingStats gates, blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389); Forever's Vanilla recipes have none (as PROFESSIONS_USE_BEST_QUALITY_REAGENTS) | blizzard_professionstemplates/blizzard_professionsrecipecrafterdetails.lua:161 · context blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389 |
| PROFESSIONS_CRAFTING_EXPECTED_QUALITY_WITH_NEXT_SKILL | A | permanent | permanent: not displayed on Forever: part of the Dragonflight crafting-quality system, shown only for a recipe or reagent that carries crafting quality or crafting stats (supportsQualities / supportsCraftingStats gates, blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389); Forever's Vanilla recipes have none (as PROFESSIONS_USE_BEST_QUALITY_REAGENTS) | blizzard_professionstemplates/blizzard_professionsrecipecrafterdetails.lua:163 · context blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389 |
| PROFESSIONS_CRAFTING_HELP_FILTERS | A | list | UI/HelpTips.lua PLATE_KEYS · exact | blizzard_professions/blizzard_professionscrafting.lua:1213 |
| PROFESSIONS_CRAFTING_ORDERS_NPC_HELPTIP | A | permanent | permanent: not displayed on Forever: a HelpTip anchored to the crafting-orders tab (blizzard_professions/blizzard_professionsframe.lua:373–376, 455); camelot's ProfessionsFrame builds only CraftingPage and BookPage (blizzard_professions/camelot/blizzard_professionsframe.xml:67–79) | blizzard_professions/blizzard_professionsframe.lua:373–376 |
| PROFESSIONS_CRAFTING_QUALITY | A | permanent | permanent: not displayed on Forever: part of the Dragonflight crafting-quality system, shown only for a recipe or reagent that carries crafting quality or crafting stats (supportsQualities / supportsCraftingStats gates, blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389); Forever's Vanilla recipes have none (as PROFESSIONS_USE_BEST_QUALITY_REAGENTS) | blizzard_professionstemplates/blizzard_professions.lua:114 · context blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389 |
| PROFESSIONS_CRAFTING_QUALITY_BONUS_INCR | A | permanent | permanent: not displayed on Forever: part of the Dragonflight crafting-quality system, shown only for a recipe or reagent that carries crafting quality or crafting stats (supportsQualities / supportsCraftingStats gates, blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389); Forever's Vanilla recipes have none (as PROFESSIONS_USE_BEST_QUALITY_REAGENTS) | blizzard_professionstemplates/blizzard_professionstemplates.lua:589 · context blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389 |
| PROFESSIONS_INSUFFICIENT_REAGENTS | A | list | UI/Crafting.lua CreateButton / CreateAllButton owners · wrapped (LABELS grant) | blizzard_professions/blizzard_professionscrafting.lua:638–655 |
| PROFESSIONS_INSUFFICIENT_REAGENT_SLOTS | A | permanent | permanent: not displayed on Forever: an optional / finishing (Modifying) reagent slot line, a Dragonflight crafting system; the slots exist only for recipes that have them (blizzard_professionstemplates/blizzard_professions.lua:560–572), and Forever's Vanilla recipes have none (as OPTIONAL_REAGENT_TOOLTIP_CLICK_TO_ADD) | blizzard_professions/blizzard_professionscrafting.lua:653 · context blizzard_professionstemplates/blizzard_professions.lua:560–572 |
| PROFESSIONS_MISSING_REQUIREMENT | A | list | UI/Crafting.lua CreateButton / CreateAllButton owners · wrapped (LABELS grant) | blizzard_professions/blizzard_professionscrafting.lua:638–655 |
| PROFESSIONS_ORDERS_NOT_ENOUGH_REAGENTS | A | list | UI/CustomerOrders.lua reagent slot checkbox owner · wrapped [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:792–793 |
| PROFESSIONS_ORDER_CRAFTER_REQUIRED_REAGENT | A | list | UI/CustomerOrders.lua itemAppended (the order form's reagent slot OnEnter) · exact [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:828–835 |
| PROFESSIONS_ORDER_CUSTOMER_REQUIRED_REAGENT | A | list | UI/CustomerOrders.lua itemAppended (the order form's reagent slot OnEnter) · exact [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:828–835 |
| PROFESSIONS_OUTPUT_MULTICRAFT_DESC | A | permanent | permanent: not displayed on Forever: part of the Dragonflight crafting-quality system, shown only for a recipe or reagent that carries crafting quality or crafting stats (supportsQualities / supportsCraftingStats gates, blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389); Forever's Vanilla recipes have none (as PROFESSIONS_USE_BEST_QUALITY_REAGENTS) | blizzard_professions/blizzard_professionscraftingoutputlog.lua:77 · context blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389 |
| PROFESSIONS_PREREQUISITE_REAGENTS | A | permanent | permanent: not displayed on Forever: an optional / finishing (Modifying) reagent slot line, a Dragonflight crafting system; the slots exist only for recipes that have them (blizzard_professionstemplates/blizzard_professions.lua:560–572), and Forever's Vanilla recipes have none (as OPTIONAL_REAGENT_TOOLTIP_CLICK_TO_ADD) | blizzard_professions/blizzard_professionscrafting.lua:651 · context blizzard_professionstemplates/blizzard_professions.lua:560–572 |
| PROFESSIONS_RECIPE_COOLDOWN | A | list | UI/Crafting.lua CreateButton / CreateAllButton owners · wrapped (LABELS grant) | blizzard_professions/blizzard_professionscrafting.lua:638–655 |
| PROFESSIONS_REQUIRED_TOOLS | A | list | UI/Crafting.lua SchematicForm.RequiredTools (post-hook UpdateRequiredTools) · template ARGS {[1] = text} (\|cn markup counted) | blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:740–750 |
| PROFESSIONS_SPECIALIZATION_CURRENCY_TOTAL | A | permanent | permanent: not displayed on Forever: the specializations page's currency line; camelot's ProfessionsFrame builds only CraftingPage and BookPage (blizzard_professions/camelot/blizzard_professionsframe.xml:67–79), never the specializations page | blizzard_professionstemplates/blizzard_professions.lua:1499 · context blizzard_professions/camelot/blizzard_professionsframe.xml:67–79 |
| PROFESSIONS_TUTORIAL_OPTIONAL_REAGENT | A | list | UI/HelpTips.lua KEYS · exact [in-game: a recipe with the Dragonflight crafting feature] | blizzard_professions/blizzard_professionscrafting.lua:1470–1476 |
| PROFESSIONS_TUTORIAL_QUALITY_BAR | A | list | UI/HelpTips.lua KEYS · exact [in-game: a recipe with the Dragonflight crafting feature] | blizzard_professions/blizzard_professionscrafting.lua:1453 · context blizzard_professions/blizzard_professionscrafting.lua:1427–1431 |
| PROFESSIONS_TUTORIAL_REAGENT_QUALITY | A | list | UI/HelpTips.lua KEYS · exact [in-game: a recipe with the Dragonflight crafting feature] | blizzard_professions/blizzard_professionscrafting.lua:1433 · context blizzard_professions/blizzard_professionscrafting.lua:1446–1447 |
| PROFESSIONS_TUTORIAL_RECRAFT | A | list | UI/HelpTips.lua KEYS · exact [in-game: a recipe with the Dragonflight crafting feature] | blizzard_professions/blizzard_professionscrafting.lua:1540–1544 |
| PROFESSIONS_UNIQUE_EQUIP_LIMITATION_DISC | A | permanent | permanent: not displayed on Forever: a recrafting line (Dragonflight recraft system: blizzard_professions/blizzard_professionscrafting.lua:1540–1544; blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:810–817); Forever's Vanilla recipes have no recraft | blizzard_professions/blizzard_professionscrafting.lua:654 · context blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:810–817 |
| PROFESSIONS_USE_BEST_QUALITY_REAGENTS | A | permanent | permanent: not displayed on Forever: part of the Dragonflight crafting-quality system, shown only for a recipe or reagent that carries crafting quality or crafting stats (supportsQualities / supportsCraftingStats gates, blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389); Forever's Vanilla recipes have none (as PROFESSIONS_USE_BEST_QUALITY_REAGENTS) | blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:98 · context blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389 |
| RECRAFT_REAGENT_TOOLTIP_CLICK_TO_REPLACE | A | permanent | permanent: not displayed on Forever: a recrafting line (Dragonflight recraft system: blizzard_professions/blizzard_professionscrafting.lua:1540–1544; blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:810–817); Forever's Vanilla recipes have no recraft | blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:810–817 |
| SALVAGE_REAGENT_TOOLTIP_CLICK_TO_REMOVE | A | permanent | permanent: not displayed on Forever: a salvage recipe's reagent slot (blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1160–1170), a Dragonflight system; Forever's Vanilla recipes have no salvage recipes | blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1160–1170 |
| TRADESKILL_NAME_RANK_WITH_MODIFIER | A | permanent | permanent: no words of its own: "%s %d (\|cff20ff20+%d\|r ) /%d" is a profession name and numbers (blizzard_professionstemplates/blizzard_professionsrankbar.lua:9), as TRADESKILL_NAME_RANK | blizzard_professionstemplates/blizzard_professionsrankbar.lua:9 |
| TRANSMOG_SITUATIONS_NO_VALID_OPTIONS | A | list | UI/Transmog.lua situations dropdown · wrapped via Labels.dropdown [in-game: transmogrifier] | blizzard_transmog/blizzard_transmog.lua:3112 |
| CONTENT_TRACKING_LOCATION_UNAVAILABLE | C | list | UI/QuestMap.lua tracker hook extended to AdventureObjectiveTracker blocks · exact (colour in the English) [in-game: content tracking] | blizzard_objectivetracker/blizzard_adventureobjectivetracker.lua:163 · context blizzard_objectivetracker/blizzard_adventureobjectivetracker.lua:288–290 |
| CONTENT_TRACKING_OBJECTIVE_FORMAT | C | permanent | permanent: no words of its own: "- %s" is a dash and the server's objective text (blizzard_sharedmapdataproviders/contenttrackingdataprovider.lua:133) | blizzard_sharedmapdataproviders/contenttrackingdataprovider.lua:133 |
| CONTENT_TRACKING_RETRIEVING_INFO | C | list | UI/QuestMap.lua tracker hook extended to AdventureObjectiveTracker blocks · exact (colour in the English) [in-game: content tracking] | blizzard_objectivetracker/blizzard_adventureobjectivetracker.lua:156 · context blizzard_objectivetracker/blizzard_adventureobjectivetracker.lua:288–290 |
| CONTENT_TRACKING_ROUTE_UNAVAILABLE | C | list | UI/QuestMap.lua tracker hook extended to AdventureObjectiveTracker blocks · exact (colour in the English) [in-game: content tracking] | blizzard_objectivetracker/blizzard_adventureobjectivetracker.lua:168 · context blizzard_objectivetracker/blizzard_adventureobjectivetracker.lua:288–290 |
| OPTIONAL_QUEST_OBJECTIVE_DESCRIPTION | C | list | UI/QuestMap.lua AdventureObjectiveTracker blocks · template ARGS {[1] = verbatim} + ONLY [in-game: content tracking] | blizzard_objectivetracker/blizzard_adventureobjectivetracker.lua:170–175 |
| PROFESSIONS_TRACKER_REAGENT_COUNT_FORMAT | C | permanent | permanent: no words of its own: "%s/%d" (blizzard_objectivetracker/blizzard_professionsrecipetracker.lua:185) | blizzard_objectivetracker/blizzard_professionsrecipetracker.lua:185 |
| PROFESSIONS_TRACKER_REAGENT_FORMAT | C | permanent | permanent: no words of its own: "%s %s" is a count and a reagent's item name (blizzard_objectivetracker/blizzard_professionsrecipetracker.lua:178, 186) | blizzard_objectivetracker/blizzard_professionsrecipetracker.lua:178, 186 |
| PROFESSIONS_TRACKER_REAGENT_RANGE_FORMAT | C | permanent | permanent: no words of its own: "(%d-%d)" (blizzard_objectivetracker/blizzard_professionsrecipetracker.lua:170–178) | blizzard_objectivetracker/blizzard_professionsrecipetracker.lua:170–178 |
| TOOLTIP_VIGNETTE_OBJECTIVE_DEFEAT | C | list | UI/MapPins.lua VIGNETTE_KEYS · template ARGS {[1] = text} [in-game: vignette with objectives] | blizzard_sharedmapdataproviders/vignettedataprovider.lua:335 · context blizzard_sharedmapdataproviders/vignettedataprovider.lua:340–346, 503–507 |
| TOOLTIP_VIGNETTE_OBJECTIVE_DEFEAT_SHOW_HEALTH | C | list | UI/MapPins.lua VIGNETTE_KEYS · template ARGS {[1] = text, [2] = percent} [in-game: vignette with objectives] | blizzard_sharedmapdataproviders/vignettedataprovider.lua:336 · context blizzard_sharedmapdataproviders/vignettedataprovider.lua:308–313 |
| SOCIAL_UI_RECENT_ALLIES_ADD_FRIEND_BUTTON_LABEL | E | permanent | permanent: not displayed on Forever: only in SocialUIFrame's Recent Allies card view (blizzard_recentallies/blizzard_recentalliestemplates.lua:469; created only as SocialUIFrame's tab content, blizzard_socialui/mainline/socialui.lua:192–203), and SocialUIFrame opens only when C_SocialUI.IsSystemEnabled() (blizzard_socialuishared/socialuicontrol.lua:9–11; blizzard_friendsframe/camelot/friendsframe.lua:1261–1263), which is false on Forever (in game 2026-09-19) | blizzard_recentallies/blizzard_recentalliestemplates.lua:469 · context blizzard_socialuishared/socialuicontrol.lua:9–11 |
| SOCIAL_UI_RECENT_ALLIES_CARD_LEVEL_DISPLAY_FORMAT | E | permanent | permanent: not displayed on Forever: only in SocialUIFrame's Recent Allies card view (blizzard_recentallies/blizzard_recentalliestemplates.lua:792; created only as SocialUIFrame's tab content, blizzard_socialui/mainline/socialui.lua:192–203), and SocialUIFrame opens only when C_SocialUI.IsSystemEnabled() (blizzard_socialuishared/socialuicontrol.lua:9–11; blizzard_friendsframe/camelot/friendsframe.lua:1261–1263), which is false on Forever (in game 2026-09-19) | blizzard_recentallies/blizzard_recentalliestemplates.lua:792 · context blizzard_socialuishared/socialuicontrol.lua:9–11 |
| SOCIAL_UI_RECENT_ALLIES_FRIEND_REQUEST_SENT_TOOLTIP | E | permanent | permanent: not displayed on Forever: only in SocialUIFrame's Recent Allies card view (blizzard_recentallies/blizzard_recentalliestemplates.lua:1321; created only as SocialUIFrame's tab content, blizzard_socialui/mainline/socialui.lua:192–203), and SocialUIFrame opens only when C_SocialUI.IsSystemEnabled() (blizzard_socialuishared/socialuicontrol.lua:9–11; blizzard_friendsframe/camelot/friendsframe.lua:1261–1263), which is false on Forever (in game 2026-09-19) | blizzard_recentallies/blizzard_recentalliestemplates.lua:1321 · context blizzard_socialuishared/socialuicontrol.lua:9–11 |
| SOCIAL_UI_RECENT_ALLIES_NOTE_FORMAT | E | permanent | permanent: not displayed on Forever: only in SocialUIFrame's Recent Allies card view (blizzard_recentallies/blizzard_recentalliestemplates.lua:1132; created only as SocialUIFrame's tab content, blizzard_socialui/mainline/socialui.lua:192–203), and SocialUIFrame opens only when C_SocialUI.IsSystemEnabled() (blizzard_socialuishared/socialuicontrol.lua:9–11; blizzard_friendsframe/camelot/friendsframe.lua:1261–1263), which is false on Forever (in game 2026-09-19) | blizzard_recentallies/blizzard_recentalliestemplates.lua:1132 · context blizzard_socialuishared/socialuicontrol.lua:9–11 |
| SOCIAL_UI_RECENT_ALLIES_NOTE_OFFLINE_FORMAT | E | permanent | permanent: not displayed on Forever: only in SocialUIFrame's Recent Allies card view (blizzard_recentallies/blizzard_recentalliestemplates.lua:1132; created only as SocialUIFrame's tab content, blizzard_socialui/mainline/socialui.lua:192–203), and SocialUIFrame opens only when C_SocialUI.IsSystemEnabled() (blizzard_socialuishared/socialuicontrol.lua:9–11; blizzard_friendsframe/camelot/friendsframe.lua:1261–1263), which is false on Forever (in game 2026-09-19) | blizzard_recentallies/blizzard_recentalliestemplates.lua:1132 · context blizzard_socialuishared/socialuicontrol.lua:9–11 |
| SOCIAL_UI_RECENT_ALLIES_TOOLTIP_LEVEL_CLASS_FORMAT | E | permanent | permanent: not displayed on Forever: only in SocialUIFrame's Recent Allies card view (blizzard_recentallies/blizzard_recentalliestemplates.lua:1088; created only as SocialUIFrame's tab content, blizzard_socialui/mainline/socialui.lua:192–203), and SocialUIFrame opens only when C_SocialUI.IsSystemEnabled() (blizzard_socialuishared/socialuicontrol.lua:9–11; blizzard_friendsframe/camelot/friendsframe.lua:1261–1263), which is false on Forever (in game 2026-09-19) | blizzard_recentallies/blizzard_recentalliestemplates.lua:1088 · context blizzard_socialuishared/socialuicontrol.lua:9–11 |
| SOCIAL_UI_RECENT_ALLIES_VIEW_HEADER_LEGACY_FRIENDS | E | permanent | permanent: not displayed on Forever: only in SocialUIFrame's Recent Allies card view (blizzard_recentallies/blizzard_recentalliestemplates.lua:709; created only as SocialUIFrame's tab content, blizzard_socialui/mainline/socialui.lua:192–203), and SocialUIFrame opens only when C_SocialUI.IsSystemEnabled() (blizzard_socialuishared/socialuicontrol.lua:9–11; blizzard_friendsframe/camelot/friendsframe.lua:1261–1263), which is false on Forever (in game 2026-09-19) | blizzard_recentallies/blizzard_recentalliestemplates.lua:709 · context blizzard_socialuishared/socialuicontrol.lua:9–11 |
| SOCIAL_UI_RECENT_ALLIES_VIEW_HEADER_PINNED | E | permanent | permanent: not displayed on Forever: only in SocialUIFrame's Recent Allies card view (blizzard_recentallies/blizzard_recentalliestemplates.lua:716; created only as SocialUIFrame's tab content, blizzard_socialui/mainline/socialui.lua:192–203), and SocialUIFrame opens only when C_SocialUI.IsSystemEnabled() (blizzard_socialuishared/socialuicontrol.lua:9–11; blizzard_friendsframe/camelot/friendsframe.lua:1261–1263), which is false on Forever (in game 2026-09-19) | blizzard_recentallies/blizzard_recentalliestemplates.lua:716 · context blizzard_socialuishared/socialuicontrol.lua:9–11 |
| SOCIAL_UI_RECENT_ALLIES_VIEW_HEADER_UNPINNED | E | permanent | permanent: not displayed on Forever: only in SocialUIFrame's Recent Allies card view (blizzard_recentallies/blizzard_recentalliestemplates.lua:723; created only as SocialUIFrame's tab content, blizzard_socialui/mainline/socialui.lua:192–203), and SocialUIFrame opens only when C_SocialUI.IsSystemEnabled() (blizzard_socialuishared/socialuicontrol.lua:9–11; blizzard_friendsframe/camelot/friendsframe.lua:1261–1263), which is false on Forever (in game 2026-09-19) | blizzard_recentallies/blizzard_recentalliestemplates.lua:723 · context blizzard_socialuishared/socialuicontrol.lua:9–11 |
| ABSORB_TRAILER | V | list | UI/CombatText.lua AddMessage hook · the `affix` form (CombatText.TRAILERS), the existing line kept | blizzard_combattext/shared/combattext.lua:166–182 |
| ACHIEVEMENTS_COMPLETED_CATEGORY | V | list | UI/Achievement.lua comparison status bar title (post-hook) · template ARGS {[1] = text} [in-game: achievements game rule] | blizzard_achievementui/mainline/blizzard_achievementui.lua:880–892 |
| ACHIEVEMENT_META_COMPLETED_DATE | V | list | UI/Achievement.lua meta-criteria owners · template ARGS {[1] = text} (FormatShortDate kept) [in-game: achievements game rule] | blizzard_achievementui/mainline/blizzard_achievementui.lua:2772–2779 |
| ACTION_SWING | V | permanent | permanent: shown only as the label of an \|Haction link (TEXT_MODE_A_STRING_ACTION "\|Haction:%s\|h%s\|h", blizzard_deathrecap/mainline/blizzard_deathrecap.lua:106–147); a link label is never translated: the whole \|H…\|h…\|h link is one verbatim markup token (pipeline/wfj/core/markup.py; ADR-031 §4) | blizzard_deathrecap/mainline/blizzard_deathrecap.lua:106–147 |
| ALREADY_FRIEND_FMT | V | list | UI/Menus.lua TAGS MENU_PROFESSIONS_CUSTOMER_ORDER_FORM tooltips · template ARGS {[1] = text} [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:286 |
| ALSO_QUEUED_FOR | V | permanent | permanent: not displayed on Forever: a Raid Finder queue line (LE_LFG_CATEGORY_RF, blizzard_queuestatusframe/mainline/queuestatusframe.lua:914–917); the dungeon finder (Blizzard_GroupFinder) is not loaded on camelot, which opens the Vanilla-style listing finder (blizzard_queuestatusframe/camelot/queuestatusframeoverrides.lua:3–11) | blizzard_queuestatusframe/mainline/queuestatusframe.lua:914–917 |
| ARCANE_CHARGES | V | permanent | permanent: not displayed on Forever: a class power no Forever class has; combat text names it only in its energize branch (blizzard_combattext/shared/combattext.lua:199–211) and camelot excludes its power bar (blizzard_unitframe/blizzard_unitframe.toc:110–111 ExcludeLoadGameType camelot) | blizzard_combattext/shared/combattext.lua:199–211 |
| AUCTION_HOUSE_DIALOG_ITEM_FORMAT | V | permanent | permanent: no words of its own: an item name and a quantity (blizzard_auctionhouseui/shared/blizzard_auctionhousebuydialog.lua:255) | blizzard_auctionhouseui/shared/blizzard_auctionhousebuydialog.lua:255 |
| AUCTION_HOUSE_EQUIPMENT_RESULT_FORMAT | V | permanent | permanent: no words of its own: an item name and its item level (blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:315) | blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:315 |
| AURA_END | V | list | UI/CombatText.lua WORDS · template ARGS {[1] = text} [in-game: auras combat text on] | blizzard_combattext/shared/combattext.lua:156–157 |
| BLOCK_TRAILER | V | list | UI/CombatText.lua AddMessage hook · the `affix` form (CombatText.TRAILERS), the existing line kept | blizzard_combattext/shared/combattext.lua:237 · context blizzard_combattext/shared/combattext.lua:147–148 |
| CALENDAR_ANNOUNCEMENT_CREATEDBY_PLAYER | V | list | UI/Calendar.lua DAY_TOOLTIP only · template ARGS {[1] = text} | blizzard_calendar/mainline/blizzard_calendar.lua:2178, 2184 |
| CALENDAR_EVENTNAME_FORMAT_END | V | list | UI/Calendar.lua DAY_TOOLTIP only · template ARGS {[1] = text} | blizzard_calendar/mainline/blizzard_calendar.lua:408–412, 2149 |
| CALENDAR_EVENTNAME_FORMAT_RAID_LOCKOUT | V | list | UI/Calendar.lua DAY_TOOLTIP + day buttons eventButtonText1 + event picker (post-hook CalendarFrame_Update) · template ARGS {[1] = text} | blizzard_calendar/mainline/blizzard_calendar.lua:413–421, 447–451, 1575–1579 |
| CALENDAR_EVENTNAME_FORMAT_RAID_RESET | V | list | UI/Calendar.lua DAY_TOOLTIP + day buttons eventButtonText1 + event picker (post-hook CalendarFrame_Update) · template ARGS {[1] = text} | blizzard_calendar/mainline/blizzard_calendar.lua:413–421, 447–451, 1575–1579 |
| CALENDAR_EVENTNAME_FORMAT_START | V | list | UI/Calendar.lua DAY_TOOLTIP only · template ARGS {[1] = text} | blizzard_calendar/mainline/blizzard_calendar.lua:395–423, 2149 |
| CALENDAR_EVENT_CREATORNAME | V | list | UI/Calendar.lua CalendarViewEventCreatorName / CalendarCreateEventCreatorName (off NEVER_TOUCH, only) · template ARGS {[1] = text} | blizzard_calendar/mainline/blizzard_calendar.lua:2822, 3579 |
| CALENDAR_EVENT_INVITEDBY_PLAYER | V | list | UI/Calendar.lua DAY_TOOLTIP only · template ARGS {[1] = text} | blizzard_calendar/mainline/blizzard_calendar.lua:2180 |
| CALENDAR_HOLIDAYFRAME_BEGINSENDS | V | list | UI/Calendar.lua CalendarViewHolidayFrame.ScrollingFont (post-hook) · template ARGS {[1] = verbatim, [2]–[5] = text} + ONLY | blizzard_calendar/mainline/blizzard_calendar.lua:2472–2481 |
| CALENDAR_RAID_LOCKOUT_DESCRIPTION | V | list | UI/Calendar.lua CalendarViewRaidFrame.ScrollingFont (post-hook) · template ARGS {[1] = text, [2] = text} | blizzard_calendar/mainline/blizzard_calendar.lua:2517–2525 |
| CALENDAR_RAID_RESET_DESCRIPTION | V | list | UI/Calendar.lua CalendarViewRaidFrame.ScrollingFont (post-hook) · template ARGS {[1] = text, [2] = text} | blizzard_calendar/mainline/blizzard_calendar.lua:2526–2529 |
| CALENDAR_SIGNEDUP_FOR_GUILDEVENT_WITH_STATUS | V | list | UI/Calendar.lua DAY_TOOLTIP only · template ARGS {[1] = entry} | blizzard_calendar/mainline/blizzard_calendar.lua:2170–2174 |
| CALENDAR_TOOLTIP_DATE_RANGE | V | permanent | permanent: no words of its own: two FormatShortDate dates (blizzard_calendar/mainline/blizzard_calendar.lua:2138) | blizzard_calendar/mainline/blizzard_calendar.lua:2138 |
| CALENDAR_VIEW_EVENTTYPE | V | list | UI/Calendar.lua CalendarViewEventTypeName · template ARGS {[1] = entry, [2] = text} + ONLY | blizzard_calendar/mainline/blizzard_calendar.lua:2805–2809 |
| CHI | V | permanent | permanent: not displayed on Forever: a class power no Forever class has; combat text names it only in its energize branch (blizzard_combattext/shared/combattext.lua:199–211) and camelot excludes its power bar (blizzard_unitframe/blizzard_unitframe.toc:112–113 ExcludeLoadGameType camelot) | blizzard_combattext/shared/combattext.lua:199–211 |
| CLICK_BINDINGS_BINDING_TEXT_FORMAT | V | list | UI/ClickBinding.lua ROW_BINDING · template ARGS {[1] = modifiers, [2] = entry} + ONLY, the existing line kept | blizzard_clickbindingui/blizzard_clickbindingui.lua:224–231 |
| CLICK_BINDING_MACRO_TITLE | V | list | UI/ClickBinding.lua ROW_NAME · template ARGS {[1] = text} + wrapped | blizzard_clickbindingui/blizzard_clickbindingui.lua:174–177, 196–206 |
| COMBO_POINTS | V | list | UI/CombatText.lua AddMessage hook · energize ("<N <power word>>", N kept; the \|4 plural resolved) [in-game: level-1 Rogue, energize combat text on] | blizzard_combattext/shared/combattext.lua:199–211 |
| CRAFTING_ORDER_RECIPE_PROFESSION_FMT | V | list | UI/CustomerOrders.lua order form title · template ARGS {[1] = text} [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:1166 |
| CRAFTING_ORDER_TIME_PENDING_FMT | V | list | UI/CustomerOrders.lua order form · template ARGS {[1] = time} [in-game: crafting orders] | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:1329 |
| CURRENCY_TRANSFER_DESTINATION | V | list | UI/CurrencyTransfer.lua SourceSelector.PlayerName (only) · template ARGS {[1] = text} [in-game: a transferable currency] | blizzard_tokenui/blizzard_currencytransfer.lua:535 |
| CURRENCY_TRANSFER_LOG_CURRENCY_FORMAT | V | permanent | permanent: no words of its own: a count and a currency name, in the transfer log camelot never opens (blizzard_tokenui/blizzard_currencytransfer.lua:769) | blizzard_tokenui/blizzard_currencytransfer.lua:769 |
| DAMAGE_METER_ENTRY_FORMAT_COMPACT | V | permanent | permanent: no words of its own: numbers only (blizzard_damagemeter/damagemeterentry.lua:123–129) | blizzard_damagemeter/damagemeterentry.lua:123–129 |
| DAMAGE_METER_ENTRY_FORMAT_COMPLETE | V | permanent | permanent: no words of its own: numbers only (blizzard_damagemeter/damagemeterentry.lua:125) | blizzard_damagemeter/damagemeterentry.lua:125 |
| DAMAGE_METER_ENTRY_FORMAT_COMPLETE_NO_PARENTHESIS | V | permanent | permanent: no words of its own: numbers only (blizzard_damagemeter/damagemeterentry.lua:127) | blizzard_damagemeter/damagemeterentry.lua:127 |
| DAMAGE_METER_SOURCE_NAME | V | permanent | permanent: no words of its own: "%d. %s" is a rank and a name (blizzard_damagemeter/damagemeterentry.lua:576–577) | blizzard_damagemeter/damagemeterentry.lua:576–577 |
| DAMAGE_METER_SPELL_ENTRY_CREATURE | V | permanent | permanent: no words of its own: a spell and a creature name (blizzard_damagemeter/damagemeterentry.lua:722–723) | blizzard_damagemeter/damagemeterentry.lua:722–723 |
| DAMAGE_METER_SPELL_ENTRY_UNIT | V | permanent | permanent: no words of its own: a spell and a unit name (blizzard_damagemeter/damagemeterentry.lua:726–730) | blizzard_damagemeter/damagemeterentry.lua:726–730 |
| DEATH_RECAP_DAMAGE_TT | V | list | UI/DeathRecap.lua DamageInfo tooltip · trailer (head TEXT_MODE_A_STRING_VALUE_SCHOOL, tail TEXT_MODE_A_STRING_RESULT_* groups) | blizzard_deathrecap/mainline/blizzard_deathrecap.lua:44–51, 167–187 |
| DISCORD_GUILD_LINKED_CHANNEL | V | list | UI/GuildControl.lua DiscordLinkFrame.linkedChannel · template ARGS {[1] = text} [in-game: Discord] | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:327–331 |
| DISCORD_GUILD_LINKED_SERVER | V | list | UI/GuildControl.lua DiscordLinkFrame.linkedServer · template ARGS {[1] = text} [in-game: Discord] | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:327–330 |
| DISCORD_VALID_SERVER_CHANNEL_LIST | V | list | UI/GuildControl.lua discordFrame.channelListTitle · template ARGS {[1] = text} [in-game: Discord] | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:376–378 |
| DUNGEON_NAME_WITH_DIFFICULTY | V | permanent | permanent: no words of its own: a dungeon name and the client's difficulty name (blizzard_calendar/mainline/blizzard_calendar.lua:62–68) | blizzard_calendar/mainline/blizzard_calendar.lua:62–68 |
| ENCHANTED_TOOLTIP_LINE | V | list | UI/Crafting.lua output-log elements (ItemContainer.Text) · template ARGS {[1] = text} | blizzard_professions/blizzard_professionscraftingoutputlog.lua:29–42 |
| ENCOUNTER_JOURNAL_SEARCH_RESULTS | V | list | UI/Achievement.lua SearchResults.TitleText · template ARGS {[1] = verbatim} + ONLY [in-game: achievements game rule] | blizzard_achievementui/mainline/blizzard_achievementui.lua:3787–3794 |
| EXAMPLE_TARGET_MONSTER | V | permanent | permanent: a unit name, not a word: it fills the target-name slot of the chat settings' example combat-log line (blizzard_chatframe/mainline/chatconfigframe.lua:1198, 1216); names stay English | blizzard_chatframe/mainline/chatconfigframe.lua:1198, 1216 |
| FINISHING_REAGENT_TOOLTIP_TITLE | V | permanent | permanent: not displayed on Forever: an optional / finishing (Modifying) reagent slot line, a Dragonflight crafting system; the slots exist only for recipes that have them (blizzard_professionstemplates/blizzard_professions.lua:560–572), and Forever's Vanilla recipes have none (as OPTIONAL_REAGENT_TOOLTIP_CLICK_TO_ADD) | blizzard_professionstemplates/blizzard_professions.lua:584–587 |
| FLAG_COUNT_TEMPLATE | V | permanent | permanent: no words of its own: "x %d" after an atlas (blizzard_pvpmatch/pvpmatchtable.lua:289–292) | blizzard_pvpmatch/pvpmatchtable.lua:289–292 |
| FULLDATE | V | list | UI/Calendar.lua date labels + DAY_TOOLTIP + INVITE_ROW_TOOLTIP · fullDate (ARGS {[1] = word, [2] = word}; Japanese %4$d年%2$s%3$d日(%1$s)) | blizzard_calendar/mainline/blizzard_calendar.lua:2123, 2706, 2824, 3438, 3543 |
| FURY | V | permanent | permanent: not displayed on Forever: not in the combat-text energize branch (blizzard_combattext/shared/combattext.lua:191–211); its only other use is the combat-log power map (blizzard_combatlogbase/mainline/combatlogconstants.lua:1–19) or a PowerBarColor index, for a power no Forever class has | blizzard_combatlogbase/mainline/combatlogconstants.lua:16 · context blizzard_combattext/shared/combattext.lua:191–211 |
| GUILDBANK_BUYTAB_MONEY_FORMAT | V | list | UI/GuildBank.lua GuildBankMessageFrame · guildBankLog (ARGS {[1] = text, [2] = verbatim}) [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:803 |
| GUILDBANK_DEPOSIT_FORMAT | V | list | UI/GuildBank.lua GuildBankMessageFrame · guildBankLog (ARGS {[1] = text, [2] = verbatim}) [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:762–765 |
| GUILDBANK_DEPOSIT_MONEY_FORMAT | V | list | UI/GuildBank.lua GuildBankMessageFrame · guildBankLog (ARGS {[1] = text, [2] = verbatim}) [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:794 |
| GUILDBANK_GUILD_RENAME_PURCHASE | V | list | UI/GuildBank.lua GuildBankMessageFrame · guildBankLog (ARGS {[1] = text, [2] = verbatim}) [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:810 |
| GUILDBANK_GUILD_RENAME_REFUND | V | list | UI/GuildBank.lua GuildBankMessageFrame · guildBankLog (ARGS {[1] = text, [2] = verbatim}) [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:812 |
| GUILDBANK_INFO_TITLE_FORMAT | V | list | UI/GuildBank.lua TabTitle · guildBankTab head, template ARGS {[1] = text} [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:373–397 |
| GUILDBANK_LOG_TITLE_FORMAT | V | list | UI/GuildBank.lua TabTitle · guildBankTab head, template ARGS {[1] = text} [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:373–397 |
| GUILDBANK_MOVE_FORMAT | V | list | UI/GuildBank.lua GuildBankMessageFrame · guildBankLog (ARGS {[1] = text, [2] = verbatim, [4] = text, [5] = text}) [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:772 |
| GUILDBANK_REMAINING_MONEY | V | list | UI/GuildBank.lua LimitLabel (only) · template ARGS {[1] = text, [2] = entry} [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:405–421 |
| GUILDBANK_REPAIR_MONEY_FORMAT | V | list | UI/GuildBank.lua GuildBankMessageFrame · guildBankLog (ARGS {[1] = text, [2] = verbatim}) [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:798 |
| GUILDBANK_UNLOCKTAB_FORMAT | V | list | UI/GuildBank.lua GuildBankMessageFrame · guildBankLog (ARGS {[1] = text}) [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:805 |
| GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT | V | list | UI/GuildBank.lua GuildBankMessageFrame · guildBankLog (ARGS {[1] = text, [2] = verbatim}) [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:800 |
| GUILDBANK_WITHDRAW_FORMAT | V | list | UI/GuildBank.lua GuildBankMessageFrame · guildBankLog (ARGS {[1] = text, [2] = verbatim}) [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:767–770 |
| GUILDBANK_WITHDRAW_MONEY_FORMAT | V | list | UI/GuildBank.lua GuildBankMessageFrame · guildBankLog (ARGS {[1] = text, [2] = verbatim}) [in-game: guild vault] | blizzard_guildbankui/mainline/blizzard_guildbankui.lua:796 |
| GUILD_TRADE_SKILL_TITLE | V | list | UI/Professions.lua SetTitleFormatted hook · template ARGS {[1] = text} [in-game: a guild profession view] | blizzard_professions/blizzard_professionsframe.lua:246–253 |
| HAPPINESS | V | permanent | permanent: not displayed on Forever: not in the combat-text energize branch (blizzard_combattext/shared/combattext.lua:191–211); its only other use is the combat-log power map (blizzard_combatlogbase/mainline/combatlogconstants.lua:1–19) or a PowerBarColor index, for a power no Forever class has | blizzard_combattext/shared/combattextconstants.lua:94 · context blizzard_combattext/shared/combattext.lua:191–211 |
| HAVE_MAIL_FROM | V | list | UI/Minimap.lua mail tooltip · headerLines ("<entry>\n<name>…", names kept) | blizzard_minimap/mainline/minimap.lua:484–489 |
| HOLY_POWER | V | permanent | permanent: not displayed on Forever: a class power no Forever class has; combat text names it only in its energize branch (blizzard_combattext/shared/combattext.lua:199–211) and camelot excludes its power bar (blizzard_unitframe/blizzard_unitframe.toc:108–109 ExcludeLoadGameType camelot) | blizzard_combattext/shared/combattext.lua:199–211 |
| INSANITY | V | permanent | permanent: not displayed on Forever: not in the combat-text energize branch (blizzard_combattext/shared/combattext.lua:191–211); its only other use is the combat-log power map (blizzard_combatlogbase/mainline/combatlogconstants.lua:1–19) or a PowerBarColor index, for a power no Forever class has | blizzard_combattext/shared/combattextconstants.lua:92 · context blizzard_combattext/shared/combattext.lua:191–211 |
| LESS_THAN_ONE_MINUTE | V | list | UI/QueueStatus.lua TimeInQueue (TIME_IN_QUEUE {[1] = time}) · time kind widened (DURATIONS entry, leading "<") | blizzard_queuestatusframe/mainline/queuestatusframe.lua:1083–1086, 1260 |
| LFG_FOLLOWER_NAME_PREFIX | V | permanent | permanent: no words of its own: "*%s" marks a follower-dungeon companion's name (blizzard_unitframe/mainline/unitframe.lua:163), a retail system | blizzard_unitframe/shared/compactunitframe.lua:855 |
| LUNAR_POWER | V | permanent | permanent: not displayed on Forever: not in the combat-text energize branch (blizzard_combattext/shared/combattext.lua:191–211); its only other use is the combat-log power map (blizzard_combatlogbase/mainline/combatlogconstants.lua:1–19) or a PowerBarColor index, for a power no Forever class has | blizzard_combatlogbase/mainline/combatlogconstants.lua:10 · context blizzard_combattext/shared/combattext.lua:191–211 |
| MAELSTROM | V | permanent | permanent: not displayed on Forever: not in the combat-text energize branch (blizzard_combattext/shared/combattext.lua:191–211); its only other use is the combat-log power map (blizzard_combatlogbase/mainline/combatlogconstants.lua:1–19) or a PowerBarColor index, for a power no Forever class has | blizzard_combattext/shared/combattextconstants.lua:87 · context blizzard_combattext/shared/combattext.lua:191–211 |
| MATCHMAKING_ENEMY_AVG_RATING | V | permanent | permanent: not displayed on Forever: shown only in a rated battleground or arena (ShouldShowMatchmakingText, blizzard_pvpmatch/pvpmatchutil.lua:84–93, 115–121), a rated-PvP system with no Classic-content counterpart | blizzard_pvpmatch/pvpmatchutil.lua:118 · context blizzard_pvpmatch/pvpmatchutil.lua:84–93, 115–121 |
| MATCHMAKING_YOUR_AVG_RATING | V | permanent | permanent: not displayed on Forever: shown only in a rated battleground or arena (ShouldShowMatchmakingText, blizzard_pvpmatch/pvpmatchutil.lua:84–93, 115–121), a rated-PvP system with no Classic-content counterpart | blizzard_pvpmatch/pvpmatchutil.lua:117 · context blizzard_pvpmatch/pvpmatchutil.lua:84–93, 115–121 |
| MYTHIC_PLUS_DESERTER_CONSEQUENCE | V | list | listed with the StaticPopup dialogs (UI/Popups, ADR-037) | blizzard_framexml/mainline/instanceabandon.lua:143 · context blizzard_framexml/mainline/instanceabandon.lua:77, 143 |
| MYTHIC_PLUS_DESERTER_FLAGGED | V | list | listed with the StaticPopup dialogs (UI/Popups, ADR-037) | blizzard_framexml/mainline/instanceabandon.lua:143 · context blizzard_framexml/mainline/instanceabandon.lua:77, 143 |
| NOT_ENOUGH_CURRENCY | V | list | UI/ItemInteraction.lua action button owner · template ARGS {[1] = text} [in-game: item interaction NPC] | blizzard_iteminteractionui/blizzard_iteminteractionui.lua:824–831 |
| PAIN | V | permanent | permanent: not displayed on Forever: not in the combat-text energize branch (blizzard_combattext/shared/combattext.lua:191–211); its only other use is the combat-log power map (blizzard_combatlogbase/mainline/combatlogconstants.lua:1–19) or a PowerBarColor index, for a power no Forever class has | blizzard_combatlogbase/mainline/combatlogconstants.lua:17 · context blizzard_combattext/shared/combattext.lua:191–211 |
| PERSONAL_CRAFTING_ORDERS_AVAIL_FMT | V | permanent | permanent: not displayed on Forever: the minimap personal crafting-orders indicator (blizzard_minimap/mainline/minimap.lua:530–548) is for a crafter's personal orders, and camelot's ProfessionsFrame has no crafting-orders page (blizzard_professions/camelot/blizzard_professionsframe.xml:67–79; as MAILFRAME_CRAFTING_ORDERS_TOOLTIP_TITLE) | blizzard_minimap/mainline/minimap.lua:530–548 |
| PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER | V | permanent | permanent: not displayed on Forever: a recrafting line (Dragonflight recraft system: blizzard_professions/blizzard_professionscrafting.lua:1540–1544; blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:810–817); Forever's Vanilla recipes have no recraft | blizzard_objectivetracker/blizzard_professionsrecipetracker.lua:132 |
| PROFESSIONS_CRAFTING_QUALITY_BONUSES | V | permanent | permanent: not displayed on Forever: part of the Dragonflight crafting-quality system, shown only for a recipe or reagent that carries crafting quality or crafting stats (supportsQualities / supportsCraftingStats gates, blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1311, 1328, 1389); Forever's Vanilla recipes have none (as PROFESSIONS_USE_BEST_QUALITY_REAGENTS) | blizzard_professionstemplates/blizzard_professionstemplates.lua:581 |
| PROFESSIONS_ORDER_RECRAFT_TITLE_FMT | V | permanent | permanent: not displayed on Forever: a recrafting line (Dragonflight recraft system: blizzard_professions/blizzard_professionscrafting.lua:1540–1544; blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:810–817); Forever's Vanilla recipes have no recraft | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:1114 |
| PROFESSIONS_RECRAFT_ORDER_NAME_FMT | V | permanent | permanent: not displayed on Forever: a recrafting line (Dragonflight recraft system: blizzard_professions/blizzard_professionscrafting.lua:1540–1544; blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:810–817); Forever's Vanilla recipes have no recraft | blizzard_professionstemplates/blizzard_professionstemplates.lua:467 |
| PVP_TAB_FILTER_COUNTED | V | permanent | permanent: no words of its own: a faction name and a count (blizzard_pvpmatch/pvpmatchresults.lua:169–170) | blizzard_pvpmatch/pvpmatchresults.lua:169–170 |
| QUEUED_STATUS_BRAWL_RULES_SUBTITLE | V | permanent | permanent: no words of its own: "%s\|n\|n%s" is a PvP brawl's name and server description (blizzard_queuestatusframe/mainline/queuestatusframe.lua:955–962) | blizzard_queuestatusframe/mainline/queuestatusframe.lua:955–962 |
| QUICK_JOIN_TOAST_EXTRA_QUEUES | V | permanent | permanent: no words of its own: a queue name and a count (blizzard_quickjoin/quickjointoast.lua:447–449) | blizzard_quickjoin/quickjointoast.lua:447–449 |
| QUICK_JOIN_TOAST_LFGLIST_MESSAGE | V | list | UI/QuickJoin.lua toast writer hook · toastTemplate (ARGS {[1] = text, [2] = verbatim}, ONLY) | blizzard_quickjoin/quickjointoast.lua:452–453 |
| QUICK_JOIN_TOAST_MESSAGE | V | list | UI/QuickJoin.lua toast writer hook · toastTemplate (ARGS {[1] = text, [2] = entryOrText}) | blizzard_quickjoin/quickjointoast.lua:445–455 |
| RAID_MEMBER_NOT_READY | V | permanent | permanent: not displayed on Forever: the dungeon-finder "suspended" queue state only (blizzard_queuestatusframe/mainline/queuestatusframe.lua:918–927); the dungeon finder (Blizzard_GroupFinder) is not loaded on camelot | blizzard_queuestatusframe/mainline/queuestatusframe.lua:918–927 |
| REAGENT_TOOLTIP_ALLOCATION_REQUIREMENT | V | permanent | permanent: not displayed on Forever: an optional / finishing (Modifying) reagent slot line, a Dragonflight crafting system; the slots exist only for recipes that have them (blizzard_professionstemplates/blizzard_professions.lua:560–572), and Forever's Vanilla recipes have none (as OPTIONAL_REAGENT_TOOLTIP_CLICK_TO_ADD) | blizzard_professionstemplates/blizzard_professions.lua:117–128 |
| RESIST_TRAILER | V | list | UI/CombatText.lua AddMessage hook · the `affix` form (CombatText.TRAILERS), the existing line kept | blizzard_combattext/shared/combattext.lua:251 |
| SEARCH_RESULTS_STRING_WITH_COUNT | V | permanent | permanent: not displayed on Forever: only in the minimized crafting view (blizzard_professions/blizzard_professionscrafting.lua:934–946), entered through MaximizeMinimize, which only the mainline ProfessionsFrame XML has; camelot does not load it (blizzard_professions.toc:25) | blizzard_professions/blizzard_professionscrafting.lua:934–946 |
| SOCIAL_QUEUE_FORMAT_BATTLEGROUND | V | list | UI/QuickJoin.lua queue lines · dash + template ARGS {[1] = text} | blizzard_uipanels_game/shared/socialqueue.lua:39–46, 136–140 |
| SOCIAL_QUEUE_FORMAT_DUNGEON | V | permanent | permanent: not displayed on Forever: a Quick Join name for a dungeon-finder ("lfg") queue (blizzard_uipanels_game/shared/socialqueue.lua:14–23); the dungeon finder (Blizzard_GroupFinder) is not loaded on camelot | blizzard_uipanels_game/shared/socialqueue.lua:14–23 |
| SOCIAL_QUEUE_FORMAT_HEROIC_DUNGEON | V | permanent | permanent: not displayed on Forever: a Quick Join name for a dungeon-finder ("lfg") queue (blizzard_uipanels_game/shared/socialqueue.lua:24–25); the dungeon finder (Blizzard_GroupFinder) is not loaded on camelot | blizzard_uipanels_game/shared/socialqueue.lua:24–25 |
| SOCIAL_QUEUE_FORMAT_RAID | V | permanent | permanent: not displayed on Forever: a Quick Join name for a dungeon-finder ("lfg") queue (blizzard_uipanels_game/shared/socialqueue.lua:26–29); the dungeon finder (Blizzard_GroupFinder) is not loaded on camelot | blizzard_uipanels_game/shared/socialqueue.lua:26–29 |
| SOCIAL_QUEUE_FORMAT_WORLDPVP | V | permanent | permanent: not displayed on Forever: a Quick Join name for a dungeon-finder ("lfg") queue (blizzard_uipanels_game/shared/socialqueue.lua:30–31); the dungeon finder (Blizzard_GroupFinder) is not loaded on camelot | blizzard_uipanels_game/shared/socialqueue.lua:30–31 |
| SOUL_SHARDS | V | permanent | permanent: not displayed on Forever: a class power no Forever class has; combat text names it only in its energize branch (blizzard_combattext/shared/combattext.lua:199–211) and camelot excludes its power bar (blizzard_unitframe/blizzard_unitframe.toc:75–76 ExcludeLoadGameType camelot) | blizzard_combattext/shared/combattext.lua:199–211 |
| TEXT_MODE_A_STRING_RESULT_ABSORB | V | list | UI/DeathRecap.lua DamageInfo tooltip · trailer tail, template ARGS {[1] = text} | blizzard_deathrecap/mainline/blizzard_deathrecap.lua:175 |
| TEXT_MODE_A_STRING_RESULT_BLOCK | V | list | UI/DeathRecap.lua DamageInfo tooltip · trailer tail, template ARGS {[1] = text} | blizzard_deathrecap/mainline/blizzard_deathrecap.lua:185 |
| TEXT_MODE_A_STRING_RESULT_OVERKILLING | V | list | UI/DeathRecap.lua DamageInfo tooltip · trailer tail, template ARGS {[1] = text} | blizzard_deathrecap/mainline/blizzard_deathrecap.lua:170 |
| TEXT_MODE_A_STRING_RESULT_RESIST | V | list | UI/DeathRecap.lua DamageInfo tooltip · trailer tail, template ARGS {[1] = text} | blizzard_deathrecap/mainline/blizzard_deathrecap.lua:180 |
| TEXT_MODE_A_STRING_VALUE_SCHOOL | V | list | UI/DeathRecap.lua DamageInfo tooltip · trailer head, template ARGS {[1] = text, [2] = words} | blizzard_deathrecap/mainline/blizzard_deathrecap.lua:49–50 |
| TRADESKILL_CHARGES_REMAINING_NEXT_USE | V | permanent | permanent: not displayed on Forever: shown only for a recipe with charges (maxCharges > 0, blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:560–582), a retail crafting system; Vanilla cooldown recipes take the COOLDOWN_REMAINING path | blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:560–582 |
| TRANSMOGRIFIED_ENCHANT | V | list | UI/DressUp.lua custom-set detail slots (DressUpCustomSetDetailsSlotMixin:SetDetails) · template ARGS {[1] = text} [in-game: a weapon illusion] | blizzard_uipanels_game/mainline/dressupframes.lua:899–915 |
| VOICE_CHAT_CHANNEL_ANNOUNCE | V | list | UI/ChatSystem.lua system line · voiceParts (head, comms-mode entry, member-count tail) [in-game: voice chat] | blizzard_channels/mainline/channelframe.lua:502–513 |
| VOICE_CHAT_CHANNEL_MANAGEMENT_TIP | V | list | UI/ChatSystem.lua CHAT_FAMILIES · template ARGS {[1] = text, [2] = text} [in-game: voice chat] | blizzard_channels/mainline/channelframe.lua:515–527 |
| VOICE_CHAT_CHANNEL_MEMBER_COUNT_ACTIVE | V | list | UI/ChatSystem.lua system line · voiceParts (head, comms-mode entry, member-count tail) [in-game: voice chat] | blizzard_channels/mainline/channelframe.lua:502–513 |
| WORLD_MAP_WILDBATTLEPET_LEVEL | V | permanent | permanent: not displayed on Forever: the wild battle-pet level label (blizzard_sharedmapdataproviders/arealabeldataprovider.lua:106–132), gated by the PetBattlesDisabled game rule and an unlocked pet loadout; pet battles have no Classic-content counterpart | blizzard_sharedmapdataproviders/arealabeldataprovider.lua:106–132 |
| ARTIFACT_XP_REWARD | FU | permanent | permanent: not displayed on Forever: shown only for a quest with artifact XP (blizzard_uipanels_game/mainline/questinfo.xml:530, 658), a Legion artifact system with no Classic-content counterpart | blizzard_uipanels_game/mainline/questinfo.xml:530, 658 |
| AUCTION_HOUSE_MAIL_MULTIPLE_BUYERS | FU | list | UI/Mail.lua purchaser line (record SOLD_BY_COLON / PURCHASED_BY_COLON) · colonPrefixEntry [in-game: a multi-buyer commodity sale] | blizzard_mailframe/mailframe.lua:787–788 |
| AUCTION_HOUSE_MAIL_MULTIPLE_SELLERS | FU | list | UI/Mail.lua purchaser line (record SOLD_BY_COLON / PURCHASED_BY_COLON) · colonPrefixEntry [in-game: a multi-buyer commodity sale] | blizzard_mailframe/mailframe.lua:787–788 |
| BAG_FILTER_ASSIGNED_TO | FU | list | UI/Bags.lua bag-slot and portrait owners · template ARGS {[1] = entryList} | blizzard_mainmenubarbagbuttons/shared/mainmenubarbagbuttons.lua:112–116 |
| BANK_TAB_DEPOSIT_ASSIGNMENTS | FU | list | UI/Bank.lua bankTabPool owners · template ARGS {[1] = entryList} [in-game: bank tabs] | blizzard_uipanels_game/mainline/bankframetemplates.lua:322–326 |
| BANK_TAB_EXPANSION_ASSIGNMENT | FU | list | UI/Bank.lua bankTabPool owners · template ARGS {[1] = entry} [in-game: bank tabs] | blizzard_uipanels_game/mainline/bankframetemplates.lua:317–319 |
| BNET_BROADCAST_SENT_TIME | FU | permanent | permanent: dead code on Forever: the line is built with FRIENDS_BROADCAST_TIME_COLOR_CODE (blizzard_friendsframe/camelot/friendsframe.lua:1987), which only blizzard_framexmlbase/cata/constants.lua:38 and blizzard_framexmlbase/mists/constants.lua:38 define; camelot loads neither (blizzard_framexmlbase.toc:15–23), so the concatenation errors before the text is shown | blizzard_friendsframe/camelot/friendsframe.lua:1987 |
| BONUS_OBJECTIVE_EXPERIENCE_FORMAT | FU | permanent | permanent: not displayed on Forever: written only for world-quest / bonus-objective / scenario / invasion rewards (blizzard_framexmlutil/mainline/questutils.lua:773; blizzard_objectivetracker/blizzard_scenarioobjectivetracker.lua:479), retail systems | blizzard_objectivetracker/blizzard_scenarioobjectivetracker.lua:479 |
| BONUS_SKILLPOINTS | FU | permanent | permanent: not displayed on Forever: shown only for a quest with a skill-point reward (blizzard_uipanels_game/mainline/questinfo.lua:933–938); Vanilla quest data has no reward-skill field | blizzard_uipanels_game/mainline/questinfo.lua:933–938 |
| BONUS_SKILLPOINTS_TOOLTIP | FU | permanent | permanent: not displayed on Forever: shown only for a quest with a skill-point reward (blizzard_uipanels_game/mainline/questinfo.lua:933–938); Vanilla quest data has no reward-skill field | blizzard_uipanels_game/mainline/questinfo.lua:933–938 |
| COOLDOWN_REMAINING | FU | list | UI/Friends.lua each friend row's summonButton owner (only RAF_SUMMON_LINKED, COOLDOWN_REMAINING) · colonPrefix (LABELS grant) | blizzard_friendsframe/camelot/friendsframe.lua:1011–1016 |
| ELITE | FU | list | UI/QuestMap.lua title button TagText (only PARENS_TEMPLATE) · the `entry` of PARENS_TEMPLATE | blizzard_uipanels_game/camelot/questmapframeoverrides.lua:19–21 |
| FEATURE_NOT_AVAILBLE_PANDAREN | FU | permanent | permanent: not displayed on Forever: shown only for a Neutral-faction (Pandaren) character (blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:427–428); Forever has no Pandaren | blizzard_communitiessecure/communitiesadddialog.lua:128 |
| GRAND_MASTER | FU | permanent | permanent: not displayed on Forever: named only in PROFESSION_RANKS (blizzard_professionsbook/blizzard_professionsbook.lua:1–9), whose only reader is blizzard_uipanels_game/cata/spellbookprofessions.lua:90 (not loaded on camelot); camelot's rank bar never reads it (blizzard_professionsbook/camelot/blizzard_professionsbook.lua:29–43) | blizzard_professionsbook/blizzard_professionsbook.lua:1–9 |
| GUILDEVENT_TYPE_DEMOTE | FU | list | UI/Communities.lua CommunitiesGuildLogFrame_Update post-hook · guildEventLog (names, rank `text`; GUILD_BANK_LOG_TIME suffix) | blizzard_communities/guildinfo.lua:163–194 |
| GUILDEVENT_TYPE_INVITE | FU | list | UI/Communities.lua CommunitiesGuildLogFrame_Update post-hook · guildEventLog (names, rank `text`; GUILD_BANK_LOG_TIME suffix) | blizzard_communities/guildinfo.lua:163–194 |
| GUILDEVENT_TYPE_JOIN | FU | list | UI/Communities.lua CommunitiesGuildLogFrame_Update post-hook · guildEventLog (names, rank `text`; GUILD_BANK_LOG_TIME suffix) | blizzard_communities/guildinfo.lua:163–194 |
| GUILDEVENT_TYPE_PROMOTE | FU | list | UI/Communities.lua CommunitiesGuildLogFrame_Update post-hook · guildEventLog (names, rank `text`; GUILD_BANK_LOG_TIME suffix) | blizzard_communities/guildinfo.lua:163–194 |
| GUILDEVENT_TYPE_QUIT | FU | list | UI/Communities.lua CommunitiesGuildLogFrame_Update post-hook · guildEventLog (names, rank `text`; GUILD_BANK_LOG_TIME suffix) | blizzard_communities/guildinfo.lua:163–194 |
| GUILDEVENT_TYPE_REMOVE | FU | list | UI/Communities.lua CommunitiesGuildLogFrame_Update post-hook · guildEventLog (names, rank `text`; GUILD_BANK_LOG_TIME suffix) | blizzard_communities/guildinfo.lua:163–194 |
| GUILD_EVENT_FORMAT | FU | list | UI/Communities.lua GuildNewsButton_SetText post-hook · template ARGS {[1] = entry, [2] = text, [3] = verbatim} + ONLY | blizzard_communities/guildnews.lua:120–136 |
| GUILD_EVENT_TODAY | FU | list | UI/Communities.lua · entryWrapped (the colour-wrapped `entry` of GUILD_EVENT_FORMAT) | blizzard_communities/guildnews.lua:120–136 |
| GUILD_INFO_EDITLABEL | FU | list | UI/CommunitiesGuild.lua CommunitiesGuildTextEditFrame_SetType post-hook (Title, only) · exact | blizzard_communities/guildinfo.lua:138 |
| GUILD_MOTD_EDITLABEL | FU | list | UI/CommunitiesGuild.lua CommunitiesGuildTextEditFrame_SetType post-hook (Title, only) · exact | blizzard_communities/guildinfo.lua:132 |
| ILLUSTRIOUS | FU | permanent | permanent: not displayed on Forever: named only in PROFESSION_RANKS (blizzard_professionsbook/blizzard_professionsbook.lua:1–9), whose only reader is blizzard_uipanels_game/cata/spellbookprofessions.lua:90 (not loaded on camelot); camelot's rank bar never reads it (blizzard_professionsbook/camelot/blizzard_professionsbook.lua:29–43) | blizzard_professionsbook/blizzard_professionsbook.lua:1–9 |
| INVTYPE_PROFESSION_TOOL | FU | permanent | permanent: never shown: the professions tutorial compares an item's inventory type to the literal string "INVTYPE_PROFESSION_TOOL" (blizzard_tutorials/blizzard_tutorials_professions.lua:112), an identifier, not this GlobalString | blizzard_tutorials/blizzard_tutorials_professions.lua:112 |
| INVTYPE_WEAPONMAINHAND_PET | FU | list | UI/Character.lua pet stat-row tooltips (key-only) · exact | blizzard_uipanels_game/camelot/paperdollframe.lua:2293–2294 |
| ITEM_COMPARISON_CYCLING_DISABLED_MSG_MAINHAND | FU | list | UI/Tooltip.lua showStructural (ShoppingTooltip lines) · exact [in-game: compare cycling] | blizzard_sharedxmlgame/tooltip/tooltipcomparisonmanager.lua:295–310 |
| ITEM_COMPARISON_CYCLING_DISABLED_MSG_OFFHAND | FU | list | UI/Tooltip.lua showStructural (ShoppingTooltip lines) · exact [in-game: compare cycling] | blizzard_sharedxmlgame/tooltip/tooltipcomparisonmanager.lua:295–310 |
| ITEM_COMPARISON_SWAP_ITEM_MAINHAND_DESCRIPTION | FU | list | UI/Tooltip.lua showStructural (ShoppingTooltip lines) · template ARGS {[1] = text} [in-game: compare cycling] | blizzard_sharedxmlgame/tooltip/tooltipcomparisonmanager.lua:295–310 |
| ITEM_COMPARISON_SWAP_ITEM_OFFHAND_DESCRIPTION | FU | list | UI/Tooltip.lua showStructural (ShoppingTooltip lines) · template ARGS {[1] = text} [in-game: compare cycling] | blizzard_sharedxmlgame/tooltip/tooltipcomparisonmanager.lua:295–310 |
| ITEM_DELTA_DESCRIPTION | FU | list | UI/Tooltip.lua showStructural (ShoppingTooltip lines, key-only) · exact [in-game: the delta block shows] | blizzard_sharedxmlgame/tooltip/tooltipcomparisonmanager.lua:263–267 |
| ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION | FU | list | UI/Tooltip.lua showStructural (ShoppingTooltip lines, key-only) · exact [in-game: the delta block shows] | blizzard_sharedxmlgame/tooltip/tooltipcomparisonmanager.lua:263–267 |
| ITEM_PET_KNOWN | FU | permanent | permanent: not displayed on Forever: only in the pet battle UI (blizzard_petbattleui/shared/blizzard_petbattleui.lua:1274–1276); pet battles have no Classic-content counterpart | blizzard_petbattleui/shared/blizzard_petbattleui.lua:1274 |
| ITEM_SET_NAME | FU | permanent | permanent: no words of its own: "%s (%d/%d)" is a set name and counts (blizzard_collections/shared/blizzard_wardrobe_sets.lua:164) | blizzard_collections/shared/blizzard_wardrobe_sets.lua:164 |
| ITEM_SPELL_MAX_USABLE_LEVEL | FU | list | UI/Tooltip.lua item spell lines · trailer (" (Requires level %d or below)" peeled; the head keeps the item-description lookup) [in-game: an item with a max-level spell] | no Lua writer: the client appends it to an item spell line (GlobalStrings ITEM_SPELL_MAX_USABLE_LEVEL) |
| ITEM_UPGRADED_LABEL | FU | list | UI/Alerts.lua loot toast Label (only) · exact [in-game: an upgraded loot toast] | blizzard_framexml/mainline/alertframesystems.lua:466 |
| ITEM_UPGRADE_NO_MORE_UPGRADES | FU | list | UI/ItemUpgrade.lua FrameErrorText (only) + UpgradeButton owner · exact [in-game: a maxed upgradeable item] | blizzard_itemupgradeui/mainline/blizzard_itemupgradeui.lua:240, 255–259 |
| MAIL_MULTIPLE_ITEMS | FU | list | UI/Mail.lua HELP + MailItem1..7Button owners (only) · countLabel ("<entry> (<n>)") | blizzard_mailframe/mailframe.lua:494 |
| MAINASSIST | FU | list | UI/Raid.lua RaidClassButton_OnEnter post-hook → HelpTooltip.walkAs (only these 3) · binding (LABELS grant) | blizzard_raidui/mainline/blizzard_raidui.lua:48–53, 93, 119–122 |
| MAINTANK | FU | list | UI/Raid.lua RaidClassButton_OnEnter post-hook → HelpTooltip.walkAs (only these 3) · binding (LABELS grant) | blizzard_raidui/mainline/blizzard_raidui.lua:48–53, 93, 119–122 |
| MASTER | FU | permanent | permanent: not displayed on Forever: named only in PROFESSION_RANKS (blizzard_professionsbook/blizzard_professionsbook.lua:1–9), whose only reader is blizzard_uipanels_game/cata/spellbookprofessions.lua:90 (not loaded on camelot); camelot's rank bar never reads it (blizzard_professionsbook/camelot/blizzard_professionsbook.lua:29–43) | blizzard_professionsbook/blizzard_professionsbook.lua:1–9 |
| MUTED | FU | permanent | permanent: dead code: the raid roster tooltip line calls GameToolTip (a misspelled, undefined global) behind a `voice` that is never assigned (blizzard_raidui/mainline/blizzard_raidui.xml:117–118) | blizzard_raidui/mainline/blizzard_raidui.xml:117–118 |
| NEWBIE_TOOLTIP_ACHIEVEMENT | FU | permanent | permanent: dead code: assigned to a micro button's newbieText (blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:969, 1630, 1688), which nothing in the micro menu reads | blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:969 |
| NEWBIE_TOOLTIP_ENCOUNTER_JOURNAL | FU | permanent | permanent: dead code: assigned to a micro button's newbieText (blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:969, 1630, 1688), which nothing in the micro menu reads | blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:1630 |
| PETS | FU | list | UI/Raid.lua RaidClassButton_OnEnter post-hook → HelpTooltip.walkAs (only these 3) · binding (LABELS grant) | blizzard_raidui/mainline/blizzard_raidui.lua:48–53, 93, 119–122 |
| PLAY_MOVIE_PREPEND | FU | list | UI/Gossip.lua (existing GOSSIP_OPTION_PREPEND fill) · the `entry` of GOSSIP_OPTION_PREPEND | blizzard_uipanels_game/shared/gossipframeshared.lua:77–82 |
| RESTRICT_CHAT_COMMUNITIES_TOOLTIP_INSTRUCTION | FU | list | UI/CommunitiesFrame.lua chatTab (only RESTRICT_CHAT_TOOLTIP_FORMAT) · the `entry` / entryWrapped of RESTRICT_CHAT_TOOLTIP_FORMAT [in-game: chat disabled] | blizzard_communities/communitiesframe.lua:1026–1028 |
| RESTRICT_CHAT_MESSAGE_SUPPRESSED | FU | list | UI/CommunitiesFrame.lua chatTab (only RESTRICT_CHAT_TOOLTIP_FORMAT) · the `entry` / entryWrapped of RESTRICT_CHAT_TOOLTIP_FORMAT [in-game: chat disabled] | blizzard_communities/communitiesframe.lua:1026–1028 |
| REWARD_ABILITY | FU | list | UI/QuestFrame.lua reward header · exact (same English as the listed REWARD_SPELL: one Japanese, reused) | blizzard_uipanels_game/mainline/questinfo.lua:475 |
| REWARD_FOLLOWER | FU | permanent | permanent: not displayed on Forever: a garrison follower quest reward (blizzard_uipanels_game/mainline/questinfo.lua:472), a system with no Classic-content counterpart | blizzard_uipanels_game/mainline/questinfo.lua:472 |
| STORE_MICRO_BUTTON_ALERT_TRIAL_CAP_REACHED | FU | permanent | permanent: a trial-account micro-button alert (IsTrialAccount, blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:1847–1850), a retail account system with no Classic counterpart (as CAPPED_LEVEL_TRIAL) | blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:1850 |
| TALENTS_LINK_FORMAT | FU | list | UI/SpellBook.lua HOST_TITLE_KEYS · template ARGS {[1] = text, [2] = text} [in-game: a linked build] | blizzard_playerspells/blizzard_playerspellsframe.lua:162 |
| TALENT_MICRO_BUTTON_SPEC_TUTORIAL | FU | permanent | permanent: dead code: only a key of PLAYERSPELLS_FRAME_PRIORITIES (blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:15); no alert ever shows it | blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:15 |
| TIME_REMAINING | FU | list | UI/QuestFrame.lua QuestInfoTimerFrame OnUpdate + QuestInfo_ShowTimer post-hook · colonPrefix (LABELS grant; the time kept) | blizzard_uipanels_game/mainline/questinfo.lua:9, 331 |
| ZEN_MASTER | FU | permanent | permanent: not displayed on Forever: named only in PROFESSION_RANKS (blizzard_professionsbook/blizzard_professionsbook.lua:1–9), whose only reader is blizzard_uipanels_game/cata/spellbookprofessions.lua:90 (not loaded on camelot); camelot's rank bar never reads it (blizzard_professionsbook/camelot/blizzard_professionsbook.lua:29–43) | blizzard_professionsbook/blizzard_professionsbook.lua:1–9 |
| CLUB_FINDER_LOOKING_FOR_CLASS_SPEC_WITH_ROLE | D | permanent | permanent: no words of its own: "%s\|t %s %s" is a role icon, a spec and a class name (blizzard_framexmlutil/communitiesutil.lua:334) | blizzard_framexmlutil/communitiesutil.lua:334 |
| CLUB_FINDER_RECRUITING_ALL_SPECS | D | list | UI/ClubFinder.lua card (only) · exact; blizzard_framexmlutil/communitiesutil.lua joins FOREVER_WINDOWS["communities"] [in-game: C_ClubFinder.IsEnabled] | blizzard_framexmlutil/communitiesutil.lua:342 |
| COMMUNITIES_CHAT_FRAME_TODAY_NOTIFICATION | D | list | UI/CommunitiesFrame.lua + UI/ChatSystem.lua communitiesChat (MessageFrame AddMessage / BackFillMessage, key-restricted) · exact | blizzard_communities/communitieschatframe.lua:357 |
| COMMUNITIES_CHAT_FRAME_UNREAD_MESSAGES_NOTIFICATION | D | list | UI/CommunitiesFrame.lua + UI/ChatSystem.lua communitiesChat (MessageFrame AddMessage / BackFillMessage, key-restricted) · exact | blizzard_communities/communitieschatframe.lua:369 |
| COMMUNITIES_CHAT_FRAME_YESTERDAY_NOTIFICATION | D | list | UI/CommunitiesFrame.lua + UI/ChatSystem.lua communitiesChat (MessageFrame AddMessage / BackFillMessage, key-restricted) · exact | blizzard_communities/communitieschatframe.lua:359 |
| COMMUNITIES_MESSAGE_OF_THE_DAY_FORMAT | D | list | UI/CommunitiesFrame.lua + UI/ChatSystem.lua communitiesChat · template ARGS {[1] = verbatim} + ONLY | blizzard_communities/communitieschatframe.lua:397 |
| ACHIEVEMENT_BUTTON | X | permanent | permanent: not displayed on Forever: camelot's micro-menu list (blizzard_micromenu/camelot/micromenucontaineroverrides.lua:2–19) omits AchievementMicroButton; only the mainline list adds it (blizzard_micromenu/mainline/micromenucontaineroverrides.lua:7), which camelot does not load (blizzard_micromenu.toc:11–12) | blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:968 · context blizzard_micromenu/camelot/micromenucontaineroverrides.lua:2–19 |
| GUILD_BANK_LOG_TIME | X | list | UI/GuildBank.lua guildBankLog + UI/Communities.lua guildEventLog · the suffix, template ARGS {[1] = time} | blizzard_communities/guildinfo.lua:191 |
| RESTRICT_CHAT_TOOLTIP_FORMAT | X | list | UI/CommunitiesFrame.lua chatTab (only) · template ARGS {[1] = entry, [2] = entry} with entryWrapped [in-game: chat disabled] | blizzard_communities/communitiesframe.lua:1026–1028 |

## Forms and hooks

Each new form is the smallest shape that fits; a form with one surface as its only user lives in that surface file;
forms that go through `Labels.show` (menus, tooltips, labels) live in `Core/UIStrings.lua` (`matchUncached` /
`fill`), with their per-key tables (`LABELS` / `ARGS`) in `Core/UIStringKeys.lua`. "Keys" counts the `list` rows naming the form.

### contextMenu

- **Shape:** An untagged context menu opened by `MenuUtil.CreateContextMenu`. Post-hook `Menu.PopulateDescription`; when the description has no tag and matches one of two openers, walk it with `Menus.onMenu` under a pseudo-tag (`CONTEXT_LFG_SEARCH_ENTRY` with `titleIsName`, `CONTEXT_CUSTOMER_ORDER_RECIPE`). Details in "Context-menu hook".
- **Keys (4):** `BATTLE_PET_FAVORITE`, `BATTLE_PET_UNFAVORITE`, `LFG_LIST_REPORT_GROUP_FOR`, `REPORT_GROUP_FINDER_ADVERTISEMENT`
- **Owner:** UI/MenusUntagged.lua (+ UI/Menus.lua `UNTAGGED` specs)
- **Source:** blizzard_menu/menuutil.lua:151–166; blizzard_menu/menu.lua:2708–2722

### utilityTooltip

- **Shape:** A menu element's utility button (gear, cancel, play-sample) owns its own tooltip: `MenuTemplates.SetUtilityButtonTooltipText(button, text)` hooks the button's OnEnter to `GameTooltip_SetTitle(tooltip, text)` with the button as owner. Post-hook `MenuTemplates.SetUtilityButtonTooltipText` and `HelpTooltip.register(button, { only = UTILITY_TOOLTIPS })`. Fixes the shipped `HUD_EDIT_MODE_DELETE_LAYOUT` / `HUD_EDIT_MODE_RENAME_OR_COPY_LAYOUT` too (only the element frame is registered today, `UI/Menus.lua:222`).
- **Keys (5):** `COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_TOOLTIP_DELETE`, `COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_TOOLTIP_EDIT`, `COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_PLAY_SAMPLE`, `COOLDOWN_VIEWER_SETTINGS_DELETE_LAYOUT`, `COOLDOWN_VIEWER_SETTINGS_RENAME_OR_COPY_LAYOUT`
- **Owner:** UI/Menus.lua
- **Source:** blizzard_menu/menutemplates.lua:645–649; blizzard_menu/menuutil.lua:114–130; blizzard_editmode/shared/editmodemanager.lua:1396–1405

### durationSuffix

- **Shape:** `"%s [%s]"`: a session name and `SecondsToClock`: `"Combat 3 [01:23]"`. Split `^(.-) (%[[%d:]+%])$`; the head is matched (`DAMAGE_METER_COMBAT_NUMBER`, numbers), the bracket kept.
- **Keys (1):** `DAMAGE_METER_COMBAT_NUMBER`
- **Owner:** Core/UIStringKeys.lua (LABELS)
- **Source:** blizzard_damagemeter/damagemetersessionwindow.lua:418–428

### atlasArg

- **Shape:** A `%s` filled with `CreateAtlasMarkup(…)`. Existing template with `[1] = "text"`: the `|A…|a` capture has no period, so `text` takes it verbatim; the busted case pins it.
- **Keys (2):** `GUILDCONTROL_DISCORD_SETTINGS`, `SOCIAL_ENABLE_DISCORD_FUNCTIONALITY`
- **Owner:** Core/UIStringKeys.lua (ARGS)
- **Source:** blizzard_guildcontrolui/blizzard_guildcontrolui.lua:70–72; blizzard_settingsdefinitions_frame/social.lua:304–309

### entryWrapped

- **Shape:** the `entry` kind also takes `|cAARRGGBB<entry>|r` (the `wrapped` branch of `matchUncached`), colour kept around the Japanese.
- **Keys (4):** `GUILD_EVENT_TODAY`, `RESTRICT_CHAT_COMMUNITIES_TOOLTIP_INSTRUCTION`, `RESTRICT_CHAT_MESSAGE_SUPPRESSED`, `RESTRICT_CHAT_TOOLTIP_FORMAT`
- **Owner:** Core/UIStrings.lua (the `entry` ARGS kind)
- **Source:** blizzard_communities/guildnews.lua:120–136; blizzard_communities/communitiesframe.lua:1026–1028

### entryList

- **Shape:** the capture split on `LIST_DELIMITER` (Forever: `","`), every piece an entry, else not this template; the delimiter kept.
- **Keys (2):** `BAG_FILTER_ASSIGNED_TO`, `BANK_TAB_DEPOSIT_ASSIGNMENTS`
- **Owner:** Core/UIStrings.lua (new ARGS kind)
- **Source:** blizzard_uipanels_game/mainline/containerframe.lua:2319–2335; blizzard_uipanels_game/mainline/bankframetemplates.lua:322–326

### colonPrefixEntry

- **Shape:** `"<entry ending in ':'> <rest>"` where the rest is exactly a whitelisted entry (the multiple-buyers / -sellers words): the rest shows its Japanese; any other rest (a name) stays as written.
- **Keys (2):** `AUCTION_HOUSE_MAIL_MULTIPLE_BUYERS`, `AUCTION_HOUSE_MAIL_MULTIPLE_SELLERS`
- **Owner:** Core/UIStrings.lua (`colonPrefix` rest lookup) + Core/UIStringKeys.lua (LABELS)
- **Source:** blizzard_mailframe/mailframe.lua:787–788

### countLabel

- **Shape:** `"<entry> (<n>)"`, pattern `^(.-) (%(%d+%))$`, whitelisted keys only.
- **Keys (1):** `MAIL_MULTIPLE_ITEMS`
- **Owner:** Core/UIStringKeys.lua (LABELS)
- **Source:** blizzard_mailframe/mailframe.lua:494

### itemAppended

- **Shape:** Lines Blizzard adds after an item: `HelpTooltip.walk` returns early for any tooltip showing an item or a spell (`UI/HelpTooltip.lua:68–75`). Post-hook the writer (`AuctionHouseUtil.AddAuctionHouseTooltipInfo(tooltip, …)`, the enchant slot and order-form reagent slot OnEnter), remember the line count before it, and walk only the lines after it with `only`. The item's own lines stay with the item path (no double rewrite).
- **Keys (11):** `AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT`, `AUCTION_HOUSE_TOOLTIP_MULTIPLE_SELLERS_FORMAT`, `AUCTION_HOUSE_TOOLTIP_OVERFLOW_SELLERS_FORMAT`, `AUCTION_HOUSE_TOOLTIP_SELLER_FORMAT`, `AUCTION_HOUSE_TOOLTIP_TIME_LEFT_LONG`, `AUCTION_HOUSE_TOOLTIP_TIME_LEFT_MEDIUM`, `AUCTION_HOUSE_TOOLTIP_TIME_LEFT_SHORT`, `AUCTION_HOUSE_TOOLTIP_TIME_LEFT_VERY_LONG`, `ENCHANT_TARGET_TOOLTIP_CLICK_TO_REPLACE`, `PROFESSIONS_ORDER_CRAFTER_REQUIRED_REAGENT`, `PROFESSIONS_ORDER_CUSTOMER_REQUIRED_REAGENT`
- **Owner:** UI/HelpTooltip.lua (+ the owning surface)
- **Source:** blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:301–306; blizzard_professionstemplates/blizzard_professionsrecipeschematicform.lua:1232–1240

### lineList

- **Shape:** `table.concat(lines, "|n")` in one FontString: split on `|n`, each line an entry, all-or-nothing, rejoined with `|n`.
- **Keys (11):** `GUILD_OFFICER_PERMISSION_ACCESS_CHANNELS`, `GUILD_OFFICER_PERMISSION_DELETE_EVENTS`, `GUILD_OFFICER_PERMISSION_DELETE_MESSAGES`, `GUILD_OFFICER_PERMISSION_FINDER_LIST`, `GUILD_OFFICER_PERMISSION_GUILD_INFO`, `GUILD_OFFICER_PERMISSION_INVITE_APPLICANTS`, `GUILD_OFFICER_PERMISSION_MOTD`, `GUILD_OFFICER_PERMISSION_OFFICER_NOTES`, `GUILD_OFFICER_PERMISSION_PUBLIC_NOTES`, `GUILD_OFFICER_PERMISSION_REMOVE_FROM_VOICE`, `GUILD_OFFICER_PERMISSION_SET_DISCORD`
- **Owner:** UI/GuildControl.lua
- **Source:** blizzard_guildcontrolui/blizzard_guildcontrolui.lua:471–483, 511

### guildEventLog

- **Shape:** M5: the guild event log is a SimpleHTML the client fills from `GetGuildEventInfo` rows (one `GUILDEVENT_TYPE_*` line plus the `GUILD_BANK_LOG_TIME` suffix and `|n` per row). It is **parsed, not rebuilt** (ADR-038 §17): a `SetText` post-hook on the SimpleHTML reads the text the client wrote, matches every `|n` line as its `GUILDEVENT_TYPE_*` template by key (player names and the rank kept as `text`) followed by the time suffix in Japanese, and leaves a line that matches nothing as written; an adapter gives `Render` the FontString interface, so Alt and the switch show the client's own text.
- **Keys (7):** `GUILDEVENT_TYPE_DEMOTE`, `GUILDEVENT_TYPE_INVITE`, `GUILDEVENT_TYPE_JOIN`, `GUILDEVENT_TYPE_PROMOTE`, `GUILDEVENT_TYPE_QUIT`, `GUILDEVENT_TYPE_REMOVE`, `GUILD_BANK_LOG_TIME`
- **Owner:** UI/CommunitiesGuild.lua
- **Source:** blizzard_communities/guildinfo.lua:163–194; blizzard_communities/guildinfo.xml:422

### guildBankLog

- **Shape:** Each `GuildBankMessageFrame` line is `<template> [ x <n>]<GUILD_BANK_LOG_TIME>`: post-hook `GuildBankFrame_UpdateLog` / `GuildBankFrame_UpdateMoneyLog`, rewrite through the message-frame transform `UI/ChatSystem.lua` already uses, peel the time suffix and the quantity, match the head by key (`only`).
- **Keys (13):** `GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT`, `GUILDBANK_BUYTAB_MONEY_FORMAT`, `GUILDBANK_DEPOSIT_FORMAT`, `GUILDBANK_DEPOSIT_MONEY_FORMAT`, `GUILDBANK_GUILD_RENAME_PURCHASE`, `GUILDBANK_GUILD_RENAME_REFUND`, `GUILDBANK_MOVE_FORMAT`, `GUILDBANK_REPAIR_MONEY_FORMAT`, `GUILDBANK_UNLOCKTAB_FORMAT`, `GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT`, `GUILDBANK_WITHDRAW_FORMAT`, `GUILDBANK_WITHDRAW_MONEY_FORMAT`, `GUILD_BANK_LOG_TIME`
- **Owner:** UI/GuildBank.lua
- **Source:** blizzard_guildbankui/mainline/blizzard_guildbankui.lua:750–816

### guildBankTab

- **Shape:** `<head>  <access>`: split at the **last** double space; the head is a tab name (kept) or `GUILDBANK_INFO_TITLE_FORMAT` / `GUILDBANK_LOG_TITLE_FORMAT` (whose own English has a double space); the tail a `GUILDBANK_TAB_*` entry, colour kept.
- **Keys (6):** `GUILDBANK_INFO_TITLE_FORMAT`, `GUILDBANK_LOG_TITLE_FORMAT`, `GUILDBANK_TAB_DEPOSIT_ONLY`, `GUILDBANK_TAB_FULL_ACCESS`, `GUILDBANK_TAB_LOCKED`, `GUILDBANK_TAB_WITHDRAW_ONLY`
- **Owner:** UI/GuildBank.lua
- **Source:** blizzard_guildbankui/mainline/blizzard_guildbankui.lua:373–398

### trailer

- **Shape:** `<head> <trailer template>…`: the head kept as written (a number, a healer name) or matched as its own template (`TEXT_MODE_A_STRING_VALUE_SCHOOL`), each trailing parenthesised group matched as its key (numbers kept). The item-tooltip case peels `ITEM_SPELL_MAX_USABLE_LEVEL` and hands the head to the existing item-description lookup.
- **Keys (10):** `ABSORB_TRAILER`, `BLOCK_TRAILER`, `DEATH_RECAP_DAMAGE_TT`, `ITEM_SPELL_MAX_USABLE_LEVEL`, `RESIST_TRAILER`, `TEXT_MODE_A_STRING_RESULT_ABSORB`, `TEXT_MODE_A_STRING_RESULT_BLOCK`, `TEXT_MODE_A_STRING_RESULT_OVERKILLING`, `TEXT_MODE_A_STRING_RESULT_RESIST`, `TEXT_MODE_A_STRING_VALUE_SCHOOL`
- **Owner:** UI/CombatText.lua, UI/DeathRecap.lua, UI/Tooltip.lua
- **Source:** blizzard_combattext/shared/combattext.lua:147–182, 237–251; blizzard_deathrecap/mainline/blizzard_deathrecap.lua:44–51, 167–187

### energize

- **Shape:** `"<" .. N .. " " .. _G[power] .. ">"`: N kept, the power word (`|4` resolved by count) in Japanese.
- **Keys (1):** `COMBO_POINTS`
- **Owner:** UI/CombatText.lua
- **Source:** blizzard_combattext/shared/combattext.lua:199–211

### fullDate

- **Shape:** `FULLDATE` `"%1$s, %2$s %3$d %4$d"` → Japanese `%4$d年%2$s%3$d日(%1$s)`; weekday and month are `word` arguments (WEEKDAY_* / MONTH_* already listed).
- **Keys (1):** `FULLDATE`
- **Owner:** UI/Calendar.lua (+ Core/UIStringKeys.lua ARGS)
- **Source:** blizzard_calendar/mainline/blizzard_calendar.lua:2123, 2706, 2824, 3438, 3543

### iconAfter

- **Shape:** `"<entry> |A…|a"`: the atlas after the word, kept verbatim.
- **Keys (1):** `COOLDOWN_VIEWER_SETTINGS_BUTTON_REVERT_CHANGES`
- **Owner:** Core/UIStrings.lua (the `icon` form mirrored) + Core/UIStringKeys.lua (LABELS)
- **Source:** blizzard_cooldownviewer/cooldownviewersettings.lua:1208–1210

### eventTraceRow

- **Shape:** A log row `"[id] |c…--- <entry> ---|r"` (EVENTTRACE_MESSAGE_FORMAT): the id and colour kept, the inner entry in Japanese; argument rows never touched.
- **Keys (5):** `EVENTTRACE_LOG_DISCARD`, `EVENTTRACE_LOG_PAUSE`, `EVENTTRACE_LOG_PAUSE_WHILE_HIDDEN`, `EVENTTRACE_LOG_START`, `EVENTTRACE_MARKER`
- **Owner:** UI/EventTrace.lua
- **Source:** blizzard_eventtrace/blizzard_eventtrace.lua:803–809, 930–936

### tooltipFrame

- **Shape:** Two tooltip frames other than GameTooltip are walked the same way (owner registered, `only`): `EventTraceTooltip` (left side of its double lines) and `EmbeddedItemTooltip` for the Recruit-a-Friend activity buttons. Only these two (YAGNI: no generic walker).
- **Keys (4):** `CLICK_CHEST_TO_CLAIM_REWARD`, `EVENTTRACE_ARG_FMT`, `EVENTTRACE_TIMESTAMP`, `RAF_RECRUIT_ACTIVITY_DESCRIPTION`
- **Owner:** UI/HelpTooltip.lua (+ UI/EventTrace.lua, UI/RecruitAFriend.lua)
- **Source:** blizzard_eventtrace/blizzard_eventtrace.lua:812–834; blizzard_recruitafriend/recruitafriendframe.lua:518–552

### paragraphsWrapped

- **Shape:** `<entry>\n\n|cAARRGGBB<entry>|r`: a paragraph part may be colour-wrapped (the `paragraphs` form calls `core(part)`, which never unwraps today).
- **Keys (1):** `OPTION_TOOLTIP_DISABLE_CHAT_ACCOUNT_MUTE`
- **Owner:** Core/UIStrings.lua (the `paragraphs` form)
- **Source:** blizzard_settingsdefinitions_frame/social.lua:21–29

### playerChoicePrefix

- **Shape:** `"|cAARRGGBB<word>|r|n|n" .. <server description>`: the rarity word in Japanese, the description kept.
- **Keys (4):** `PLAYER_CHOICE_QUALITY_STRING_COMMON`, `PLAYER_CHOICE_QUALITY_STRING_EPIC`, `PLAYER_CHOICE_QUALITY_STRING_RARE`, `PLAYER_CHOICE_QUALITY_STRING_UNCOMMON`
- **Owner:** UI/PlayerChoice.lua
- **Source:** blizzard_playerchoice/blizzard_playerchoicepowerchoicetemplate.lua:209, 218–229

### readyCheckLine

- **Shape:** `READY_CHECK_MESSAGE .. "\n" .. RAID_DIFFICULTY .. ": " .. <difficulty name>`: both parts matched, the difficulty name kept.
- **Keys (1):** `RAID_DIFFICULTY`
- **Owner:** UI/ReadyCheck.lua
- **Source:** blizzard_framexml/mainline/readycheck.lua:100–108

### tokenSell

- **Shape:** `WHITE(ESTIMATED_TIME_TO_SELL_LABEL) .. <fragment>`: the colour-wrapped label in Japanese, the fragment kept.
- **Keys (1):** `ESTIMATED_TIME_TO_SELL_LABEL`
- **Owner:** UI/AuctionHouse.lua
- **Source:** blizzard_auctionhouseui/shared/blizzard_auctionhouseutil.lua:4, 264

### dash

- **Shape:** The Quick Join tooltip's `"- %s"` name formatter: the dash kept, the queue name matched as its template.
- **Keys (3):** `SOCIAL_QUEUE_FORMAT_ARENA`, `SOCIAL_QUEUE_FORMAT_ARENA_SKIRMISH`, `SOCIAL_QUEUE_FORMAT_BATTLEGROUND`
- **Owner:** UI/QuickJoin.lua
- **Source:** blizzard_uipanels_game/shared/socialqueue.lua:39–52, 136–140

### toastTemplate

- **Shape:** The Quick Join toast: a hook on the toast writer; `[2]` is an entry when it is one (the queue name in Japanese), verbatim otherwise.
- **Keys (2):** `QUICK_JOIN_TOAST_LFGLIST_MESSAGE`, `QUICK_JOIN_TOAST_MESSAGE`
- **Owner:** UI/QuickJoin.lua (+ an `entryOrText` ARGS kind)
- **Source:** blizzard_quickjoin/quickjointoast.lua:445–455

### voiceParts

- **Shape:** `"%1$s %2$s %3$s"` with no literal text: split off the trailing member-count template, then the comms-mode entry; the head (atlas + channel-activated template) already has ARGS; all-or-nothing.
- **Keys (2):** `VOICE_CHAT_CHANNEL_ANNOUNCE`, `VOICE_CHAT_CHANNEL_MEMBER_COUNT_ACTIVE`
- **Owner:** UI/ChatSystem.lua
- **Source:** blizzard_channels/mainline/channelframe.lua:502–513

### headerLines

- **Shape:** `"<entry>\n<name>\n<name>…"`: the first line in Japanese, sender names as written.
- **Keys (1):** `HAVE_MAIL_FROM`
- **Owner:** UI/Minimap.lua
- **Source:** blizzard_minimap/mainline/minimap.lua:484–489

### time kind widened

- **Shape:** `LESS_THAN_ONE_MINUTE` ("< 1 minute") joins `UIStrings.DURATIONS` (`Core/UIStringKeys.lua`); the `time` capture admits a leading `<`.
- **Keys (1):** `LESS_THAN_ONE_MINUTE`
- **Owner:** Core/UIStrings.lua (the `time` capture) + Core/UIStringKeys.lua (DURATIONS)
- **Source:** blizzard_queuestatusframe/mainline/queuestatusframe.lua:1083–1086, 1260

### communitiesChat

- **Shape:** A second entry point into the ChatSystem rewrite for `CommunitiesFrame.Chat.MessageFrame` (AddMessage **and** BackFillMessage), keyed by an explicit key set (the three separators, the MOTD), never a type id, never a player line: a member's message is never touched.
- **Keys (4):** `COMMUNITIES_CHAT_FRAME_TODAY_NOTIFICATION`, `COMMUNITIES_CHAT_FRAME_UNREAD_MESSAGES_NOTIFICATION`, `COMMUNITIES_CHAT_FRAME_YESTERDAY_NOTIFICATION`, `COMMUNITIES_MESSAGE_OF_THE_DAY_FORMAT`
- **Owner:** UI/CommunitiesFrame.lua + UI/ChatSystem.lua
- **Source:** blizzard_communities/communitieschatframe.lua:357–397

### `|A` markup token

- **Shape:** `|A…|a` counted as one verbatim token (a Japanese that drops or changes it is `markup_changed`); the listing ban (`test_ui_keys.py:118–123`) lifted. `|cnNAME:` counted as an opener too (the 8 rows marked "|cn markup counted", and 31 shipped lines).
- **Keys (2):** `HUD_EDIT_MODE_COLLAPSE_OPTIONS`, `HUD_EDIT_MODE_EXPAND_OPTIONS`
- **Owner:** pipeline/wfj/core/markup.py, tests/python/test_ui_keys.py
- **Source:** blizzard_editmode/shared/editmodemanager.lua:2916–2918

### `static_links`

- **Shape:** Three `|H` links join `static_links`: `SPEECH_TO_TEXT_SUBTEXT`, `TEXT_TO_SPEECH_MORE_VOICES` and `RAF_NO_RECRUITS_DESC` (the third is the Recruit-a-Friend description, a SimpleHTML whose writer `SetNoRecruitsText` is post-hooked). Link labels stay verbatim.
- **Keys (3):** `RAF_NO_RECRUITS_DESC`, `SPEECH_TO_TEXT_SUBTEXT`, `TEXT_TO_SPEECH_MORE_VOICES`
- **Owner:** tests/python/test_ui_keys.py
- **Source:** blizzard_recruitafriend/recruitafriendframe.lua:55

### New menu tags (`UI/MenusTags.lua` `Menus.TAGS`, data)

| tag | source | keys | new |
|---|---|---|---|
| `COOLDOWN_VIEWER_SETTINGS_MENU` | blizzard_cooldownviewer/cooldownviewersettings.lua:943 | 3 | yes |
| `MENU_ACHIEVEMENT_FILTER` | blizzard_achievementui/mainline/blizzard_achievementui.lua:277 | 4 | yes |
| `MENU_ACHIEVEMENT_TRACKER` | blizzard_objectivetracker/blizzard_achievementobjectivetracker.lua:75 | 1 | yes |
| `MENU_AUCTION_HOUSE_FAVORITE` | blizzard_auctionhouseui/shared/blizzard_auctionhousesharedtemplates.lua:3 | 2 | yes |
| `MENU_AUCTION_HOUSE_SEARCH_FILTER` | blizzard_auctionhouseui/shared/blizzard_auctionhousesearchbar.lua:141 | 8 | yes |
| `MENU_BATTLEFIELD_MAP` | blizzard_battlefieldmap/mainline/blizzard_battlefieldmap.lua:49 | 3 | yes |
| `MENU_CALENDAR_CREATE_INVITE` | blizzard_calendar/mainline/blizzard_calendar.lua:3890 | 4 | yes |
| `MENU_CALENDAR_DAY` | blizzard_calendar/mainline/blizzard_calendar.lua:2199 | 8 | yes |
| `MENU_COMBAT_LOG` | blizzard_combatlog/mainline/blizzard_combatlog.lua:1493 | 9 | yes |
| `MENU_COOLDOWN_SETTINGS_ITEM` | blizzard_cooldownviewer/cooldownviewersettings.lua:346 | 6 | yes |
| `MENU_COOLDOWN_SETTINGS_LAYOUTS` | blizzard_cooldownviewer/cooldownviewersettings.lua:1086 | 9 | yes |
| `MENU_DAMAGE_METER_SESSIONS` | blizzard_damagemeter/damagemetersessionwindow.lua:415 | 3 | yes |
| `MENU_DAMAGE_METER_WINDOW_SETTINGS` | blizzard_damagemeter/damagemetersessionwindow.lua:468 | 9 | yes |
| `MENU_DAMAGE_METER_WINDOW_TRACKED_TYPE` | blizzard_damagemeter/damagemetersessionwindow.lua:384 | 3 | yes |
| `MENU_EDIT_MODE_MANAGER` | blizzard_editmode/shared/editmodemanager.lua:1340 | 1 | no (keys added) |
| `MENU_EVENT_TRACE_FILTER` | blizzard_eventtrace/blizzard_eventtrace.lua:464 | 6 | yes |
| `MENU_GROUP_BUFF_FILTER_ITEM` | blizzard_cooldownviewer/groupbufffilter.lua:426 | 3 | yes |
| `MENU_GROUP_LOOT` | blizzard_uipanels_game/mainline/grouplootframe.lua:202 | 1 | yes |
| `MENU_GROUP_MEMBERS_PIN` | blizzard_sharedmapdataproviders/groupmembersdataprovider.lua:167 | 1 | yes |
| `MENU_GUILD_PERMISSIONS` | blizzard_guildcontrolui/blizzard_guildcontrolui.lua:62 | 1 | yes |
| `MENU_HEIRLOOMS_FILTER` | blizzard_collections/mainline/blizzard_heirloomcollection.lua:127 | 1 | yes |
| `MENU_MOUNT_COLLECTION_FILTER` | blizzard_collections/mainline/blizzard_mountcollection.lua:982 | 7 | yes |
| `MENU_MOUNT_COLLECTION_MOUNT` | blizzard_collections/mainline/blizzard_mountcollection.lua:192 | 2 | yes |
| `MENU_OBJECTIVE_TRACKER` | blizzard_objectivetracker/blizzard_adventureobjectivetracker.lua:70 | 1 | yes |
| `MENU_PET_COLLECTION_FILTER` | blizzard_collections/classic/blizzard_petcollection.lua:100 | 1 | yes |
| `MENU_PET_COLLECTION_PET` | blizzard_collections/classic/blizzard_petcollection.lua:350 | 2 | yes |
| `MENU_PROFESSIONS_CRAFTER_ORDER` | blizzard_professions/blizzard_professionscrafterorderpage.lua:76 | 2 | yes |
| `MENU_PROFESSIONS_CRAFTING_PAGE` | blizzard_professions/blizzard_professionscrafting.lua:367 | 1 | yes |
| `MENU_PROFESSIONS_CUSTOMER_ORDER_BROWSE` | blizzard_professionscustomerorders/blizzard_professionscustomerordersbrowseorders.lua:100 | 1 | yes |
| `MENU_PROFESSIONS_CUSTOMER_ORDER_DURATION` | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:592 | 3 | yes |
| `MENU_PROFESSIONS_CUSTOMER_ORDER_FORM` | blizzard_professionscustomerorders/blizzard_professionscustomerordersform.lua:245 | 6 | yes |
| `MENU_PROFESSIONS_FILTER` | blizzard_professionstemplates/camelot/blizzard_professions.lua:2 | 2 | yes |
| `MENU_PROFESSIONS_RECIPE_LEVEL` | blizzard_professions/blizzard_professionsrecipelevel.lua:90 | 1 | yes |
| `MENU_PROFESSIONS_RECIPE_LIST_FAVORITE` | blizzard_professionstemplates/blizzard_professionsrecipelist.lua:65 | 2 | yes |
| `MENU_PROFESSIONS_RECIPE_TRACKER` | blizzard_objectivetracker/blizzard_professionsrecipetracker.lua:59 | 2 | yes |
| `MENU_QUEUE_STATUS_FRAME` | blizzard_queuestatusframe/mainline/queuestatusframe.lua:224 | 5 | no (keys added) |
| `MENU_RAID_FRAME_DIFFICULTY` | blizzard_compactraidframes/mainline/blizzard_compactraidframemanager.lua:215 | 3 | yes |
| `MENU_TOYBOX_FAVORITE` | blizzard_collections/mainline/blizzard_toybox.lua:265 | 2 | yes |
| `MENU_TOYBOX_FILTER` | blizzard_collections/mainline/blizzard_toybox.lua:116 | 3 | yes |
| `MENU_TRANSMOG_CUSTOM_SETS_MODEL_FILTER` | blizzard_transmog/blizzard_transmogtemplates.lua:1706 | 4 | yes |
| `MENU_TRANSMOG_OPTIONS` | blizzard_transmog/blizzard_transmogtemplates.lua:488 | 1 | yes |
| `MENU_TRANSMOG_OUTFIT_ENTRY` | blizzard_transmog/blizzard_transmogtemplates.lua:32 | 1 | yes |
| `MENU_TRANSMOG_SETS_FILTER` | blizzard_transmog/blizzard_transmog.lua:2676 | 3 | yes |
| `MENU_TRANSMOG_SETS_MODEL_FILTER` | blizzard_transmog/blizzard_transmogtemplates.lua:1503 | 3 | yes |
| `MENU_WARBANDSCENE_FAVORITE` | blizzard_sharedxml/mainline/sharedcollectiontemplates.lua:7 | 2 | yes |
| `MENU_WARDROBE_BASE_SETS_FILTER` | blizzard_collections/mainline/blizzard_wardrobe.lua:101 | 3 | yes |
| `MENU_WARDROBE_ITEMS_MODEL_FILTER` | blizzard_transmogshared/blizzard_transmogshared.lua:695 | 2 | yes |
| `MENU_WARDROBE_SETS_SET` | blizzard_collections/shared/blizzard_wardrobe_sets.lua:566 | 4 | yes |
| `MENU_WARDROBE_SETS_SET_DETAIL` | blizzard_collections/shared/blizzard_wardrobe_sets.lua:938 | 2 | yes |
| `MENU_WORLD_MAP_TRACKING` | blizzard_worldmap/blizzard_worldmaptemplates.lua:229 | 6 | no (keys added) |
| `MORE_CONTEXT_ACTIONS` | blizzard_gamepadsharedutility/promptedbindings/promptedbinding.lua:212 | 7 | yes |

`MENU_PROFESSIONS_CRAFTER_ORDER` and `MENU_WARBANDSCENE_FAVORITE` are harmless tags whose generators camelot never
runs (no crafter orders page; no warband scenes); they cost one line each and keep the favourite keys' tag list
complete.

### New unit menus (`UI/MenusUnit.lua`, data; `UI/Menus.lua` registers `MENU_UNIT_<which>`)

The level-1 `which`s share one key list today (`UI/Menus.lua:202–205`). The new `which`s get their own lists (their
effective entries: shared ← mainline ← `blizzard_unitpopup/camelot/unitpopupmenus.lua`); `titleIsName` on all of
them (a player, club or channel name). Club menus (`GUILDS_GUILD`, `COMMUNITIES_COMMUNITY`) title with the club name
from `contextData` (`blizzard_communities/communitieslist.lua:790–805`). A busted case covers a club named like an
entry.

| which | keys |
|---|---|
| `BN_FRIEND` | `SOCIAL_UI_BATTLE_NET_FRIEND_TAGS_LABEL`, `SOCIAL_UI_BATTLE_NET_TITLE_FRIEND_EDIT_NAME_BUTTON_LABEL`, `VIEW_FRIENDS_OF_FRIENDS` |
| `BN_FRIEND_OFFLINE` | `SOCIAL_UI_BATTLE_NET_FRIEND_TAGS_LABEL`, `SOCIAL_UI_BATTLE_NET_TITLE_FRIEND_EDIT_NAME_BUTTON_LABEL`, `VIEW_FRIENDS_OF_FRIENDS` |
| `CHAT_ROSTER` | `CHAT_OWNER`, `MAKE_MODERATOR`, `REMOVE_MODERATOR`, `VOICE_CHAT_SETTINGS` |
| `COMMUNITIES_COMMUNITY` | `COMMUNITIES_LIST_DROP_DOWN_CLEAR_UNREAD_NOTIFICATIONS`, `COMMUNITIES_LIST_DROP_DOWN_COMMUNITIES_NOTIFICATION_SETTINGS`, `COMMUNITIES_LIST_DROP_DOWN_COMMUNITIES_SETTINGS`, `COMMUNITIES_LIST_DROP_DOWN_FAVORITE`, `COMMUNITIES_LIST_DROP_DOWN_INVITE`, `COMMUNITIES_LIST_DROP_DOWN_LEAVE_CHARACTER_COMMUNITY`, `COMMUNITIES_LIST_DROP_DOWN_LEAVE_COMMUNITY`, `COMMUNITIES_LIST_DROP_DOWN_UNFAVORITE` |
| `COMMUNITIES_GUILD_MEMBER` | `GUILD_LEAVE`, `GUILD_PROMOTE`, `REPORT_CLUB_MEMBER` |
| `COMMUNITIES_MEMBER` | `COMMUNITIES_LIST_DROP_DOWN_LEAVE_CHARACTER_COMMUNITY`, `COMMUNITIES_LIST_DROP_DOWN_LEAVE_COMMUNITY`, `COMMUNITY_MEMBER_LIST_DROP_DOWN_BATTLETAG_FRIEND`, `COMMUNITY_MEMBER_LIST_DROP_DOWN_REMOVE`, `COMMUNITY_MEMBER_LIST_DROP_DOWN_ROLES`, `COMMUNITY_MEMBER_LIST_DROP_DOWN_SET_NOTE`, `REPORT_CLUB_MEMBER` |
| `COMMUNITIES_WOW_MEMBER` | `COMMUNITIES_LIST_DROP_DOWN_LEAVE_CHARACTER_COMMUNITY`, `COMMUNITIES_LIST_DROP_DOWN_LEAVE_COMMUNITY`, `COMMUNITY_MEMBER_LIST_DROP_DOWN_REMOVE`, `COMMUNITY_MEMBER_LIST_DROP_DOWN_ROLES`, `COMMUNITY_MEMBER_LIST_DROP_DOWN_SET_NOTE`, `REPORT_CLUB_MEMBER` |
| `DISCORD_USER_SELF` | `DISCORD_CHAT_MESSAGE_CLICK_DELETE` |
| `GUILDS_GUILD` | `COMMUNITIES_LIST_DROP_DOWN_CLEAR_UNREAD_NOTIFICATIONS`, `COMMUNITIES_LIST_DROP_DOWN_COMMUNITIES_NOTIFICATION_SETTINGS`, `COMMUNITIES_LIST_DROP_DOWN_INVITE` |
| `PET` | `PET_ABANDON` |
| `RAID` | `DEMOTE`, `SET_MAIN_ASSIST`, `SET_MAIN_TANK`, `SET_RAID_ASSISTANT`, `SET_RAID_LEADER` |
| `RAID_PLAYER` | `DEMOTE`, `SET_RAID_ASSISTANT`, `SET_RAID_LEADER` |
| `RECENT_ALLY` | `RECENT_ALLIES_MENU_BUTTON_LABEL_PIN`, `RECENT_ALLIES_MENU_BUTTON_LABEL_SET_NOTE`, `RECENT_ALLIES_MENU_BUTTON_LABEL_UNPIN` |
| `RECENT_ALLY_OFFLINE` | `RECENT_ALLIES_MENU_BUTTON_LABEL_PIN`, `RECENT_ALLIES_MENU_BUTTON_LABEL_SET_NOTE`, `RECENT_ALLIES_MENU_BUTTON_LABEL_UNPIN` |
| `SELF` | `VOTE_TO_ABANDON` |

### Surface hooks without a new form

RaidClassButton (`RaidClassButton_OnEnter` → `HelpTooltip.walkAs`), `QuestInfoTimerFrame` OnUpdate + `QuestInfo_ShowTimer`,
each friend row's RAF summon button (this also gives the listed `RAF_SUMMON_LINKED` its first owner), `GuildNewsButton_SetText`,
`CommunitiesGuildTextEditFrame_SetType`, the guild reputation bar's `UpdateFaction` / OnLeave (`FACTION_STANDING_LABEL*`,
already listed), the AdventureObjectiveTracker blocks (QuestMap's tracker hook extended), the vignette pin tooltip
(`VIGNETTE_KEYS`), the Calendar holiday / raid frames and `CalendarFrame_Update`, the guild control Discord frames, the
professions output log, the dress-up custom-set slots, the recipe toast name, the loot toast label, the item-upgrade
error text, the comparison tooltip lines (`showStructural`), the toast writer of Quick Join, the Wardrobe shortcuts
HelpTip's appended frame, the undo button, the WoW Token rows, the BuyDialog notification button, the auction cells.

### Existing forms reused

| form | list rows naming it |
|---|---|
| exact (whole-line entry) | 253 |
| template (ARGS kinds) | 99 |
| wrapped | 14 |
| binding | 8 |
| colonPrefix | 3 |
| colon | 1 |
| icon | 3 |
| prefix (automatic "<X>: ") | 2 |
| an `entry` / `words` argument of another key | 11 |
| HelpTips.KEYS | 38 |
| HelpTips.PLATE_KEYS | 13 |

## Context-menu hook

**Sourced.** `hooksecurefunc(Menu, "PopulateDescription", fn)` sees every context menu after its generator ran and
before any element frame exists (the same point a `Menu.ModifyMenu` callback runs at), so the menu is laid out with
the Japanese (no second layout pass).

1. `Menu` is a global table (`blizzard_menu/menu.lua:22`) and `Menu.PopulateDescription` a plain field of it:
   ```lua
   function Menu.PopulateDescription(menuGenerator, ownerRegion, description, ...)
   	securecallfunction(menuGenerator, ownerRegion, description, ...);
   	securecallfunction(SecureModifyMenu, ownerRegion, description, ...);
   end
   ```
   (`blizzard_menu/menu.lua:2719–2722`). `SecureModifyMenu` returns at once when the description has no tag
   (`menu.lua:2708–2712`), which is why `Menu.ModifyMenu` never reaches these menus.
2. `MenuUtil.CreateContextMenu` looks the field up at call time, populates, and only then opens:
   ```lua
   local elementDescription = MenuUtil.CreateRootMenuDescription(menuMixin);
   Menu.PopulateDescription(generator, ownerRegion, elementDescription, ...);
   local menu = Menu.GetManager():OpenContextMenu(ownerRegion, elementDescription);
   ```
   (`blizzard_menu/menuutil.lua:157–161`). A post-hook on the table field therefore runs between population and
   `OpenContextMenu`; it receives `(generator, ownerRegion, description, …)`, where `description` is the same root
   description proxy a ModifyMenu callback gets (`EnumerateElementDescriptions` and `AddInitializer` are forwarded,
   `menu.lua:537–549, 649–671`), so `Menus.onMenu`'s walk applies unchanged.
3. The hook also runs for every DropdownButton (`blizzard_menu/dropdownbutton.lua:251–262`), so it returns at once
   unless `description:GetTag()` is nil (`menu.lua:588–593`) and one of the two openers is recognised:
   - **LFG browse search entry** (`blizzard_groupfinder_vanillastyle/blizzard_lfgvanilla_browse.lua:949–980`):
     `MenuUtil.CreateContextMenu(LFGBrowseFrame.SearchEntryDropDown, function(owner, rootDescription) … end)`.
     `SearchEntryDropDown` is defined nowhere in the extract, so the owner falls back to
     `GetAppropriateTopLevelParent()` (`menuutil.lua:152–154`) and cannot identify the menu; the generator is an
     anonymous closure. Recognise it by content: an untagged root whose elements' text
     (`MenuUtil.GetElementText(child)`, `menuutil.lua:176–178`) includes `LFG_LIST_REPORT_GROUP_FOR` or
     `REPORT_GROUP_FINDER_ADVERTISEMENT`; both English strings have a space, so a character name can never equal
     them. The first root element is the leader-name title → walk with `skipTitle` (`titleIsName`).
   - **Customer-orders recipe list** (`blizzard_professionscustomerorders/blizzard_professionscustomerordersrecipelist.lua:96–97,
     115–117`; generator set at `…browseorders.lua:139–155`): `MenuUtil.CreateContextMenu(self, self.contextMenuGenerator,
     spellID)` with the element as owner → recognise `ownerRegion.contextMenuGenerator == generator`.
4. Keys: `CONTEXT_LFG_SEARCH_ENTRY` = `SEND_MESSAGE`, the invite texts (already listed), `LFG_LIST_REPORT_GROUP_FOR`,
   `REPORT_GROUP_FINDER_ADVERTISEMENT`; `CONTEXT_CUSTOMER_ORDER_RECIPE` = `BATTLE_PET_FAVORITE`, `BATTLE_PET_UNFAVORITE`.
   Text-only writes through the initializer, as every tagged menu; taint of the invite / report actions after the
   hook is an in-game check (below). The other untagged context menu in the orders window,
   `…customerordersmyorders.lua:33`, is tagged (`MENU_PROFESSIONS_CUSTOMER_ORDER`) and needs nothing new.

Rejected: a post-hook on `LFGBrowseFrame.CreateSearchEntryMenu` (runs after the menu is laid out in English, needs a
relayout pass, the approach ADR-033 rejected for the untagged dropdowns); replacing the method (taints the invite
path); the `"MenuProxy.OnShow"` registry event (`menu.lua:1802–1806`, also after layout).

## In-game checks

The rows marked `[in-game: …]` are built and listed; these checks show whether Forever ever shows them. A `/dump` is typed in the chat box; "action" is what to do.

| check | keys | how |
|---|---|---|
| content tracking | CONTENT_TRACKING_*, OPTIONAL_QUEST_OBJECTIVE_DESCRIPTION, CONTENT_TRACKING_OPEN_JOURNAL_OPTION | `/dump C_ContentTracking.GetCollectableSourceTrackingEnabled()`; then Collections → Appearances, shift-click an uncollected appearance, look at the objective tracker |
| vignette objectives | TOOLTIP_VIGNETTE_OBJECTIVE_DEFEAT(_SHOW_HEALTH) | action: hover a rare / vignette pin on the world map; a "- Defeat <name>" line shows the Japanese with the name kept |
| crafting orders | PROF_ORDER_*, PROFESSIONS_LISTING_DURATION_*, CRAFTING_ORDER_*, PROFESSIONS_ORDER*_REQUIRED_REAGENT, ALREADY_FRIEND_FMT, customer-orders recipe menu | action: talk to a crafting-orders NPC in a capital; `/dump ProfessionsCustomerOrdersFrame and ProfessionsCustomerOrdersFrame:IsShown()` |
| transmogrifier | TRANSMOG_* menus, HelpTips, plates, TRANSMOG_SHEATHE_WEAPON_TOOLTIP, TRANSMOG_SITUATIONS_NO_VALID_OPTIONS | action: talk to a transmogrifier NPC; `/dump TransmogFrame and TransmogFrame:IsShown()` |
| guild vault | GUILDBANK_* log, tab titles, limit | action: open a guild vault; `/dump GetNumGuildBankTabs()` |
| voice chat | CAA_*, SPEECH_TO_TEXT_*, TUTORIAL_VOICE, VOICE_CHAT_* | `/dump C_VoiceChat.IsEnabled()` |
| Discord | GUILDCONTROL_DISCORD_SETTINGS, DISCORD_*, SOCIAL_ENABLE_DISCORD_FUNCTIONALITY | `/dump C_Discord.IsEnabled()` |
| achievements game rule | ACHIEVEMENT_FILTER_*, ACHIEVEMENTS_COMPLETED_CATEGORY, ACHIEVEMENT_META_COMPLETED_DATE, ENCOUNTER_JOURNAL_SEARCH_RESULTS | `/dump C_GameRules.IsGameRuleActive(Enum.GameRule.AchievementsPanelDisabled)` (true ⇒ the window never opens) |
| combo-point energize | COMBO_POINTS | `/run SetCVar("floatingCombatTextEnergyGains_v2", 1)`; a level-1 Rogue uses Sinister Strike: "<1 コンボポイント>"-style text, the number kept |
| Edit Mode utility tooltips | HUD_EDIT_MODE_DELETE_LAYOUT, HUD_EDIT_MODE_RENAME_OR_COPY_LAYOUT (shipped), COOLDOWN_VIEWER_SETTINGS_* utility buttons | action: Edit Mode → create a layout → open the layout dropdown, hover the gear and the X; Cooldown Settings → an entry's alert submenu, hover its buttons |
| world-quest filters | SHOW_*_ON_MAP_TEXT, WORLD_QUEST* | `/dump MapUtil.MapShouldShowWorldQuestFilters(WorldMapFrame:GetMapID())` |
| queue status entries | ENTER_PET_BATTLE, LEAVE_ARENA, SURRENDER_ARENA, WOW_LABS_LEAVE_QUEUE, LEAVE_ZONE, SOCIAL_QUEUE_FORMAT_ARENA* | action: right-click the queue eye while queued; `/dump CanHearthAndResurrectFromArea()` |
| context menus + taint | LFG_LIST_REPORT_GROUP_FOR, REPORT_GROUP_FINDER_ADVERTISEMENT | action: Group Finder → Browse → right-click a listing: Japanese entries, the leader name English; choose Invite / Send Message afterwards and check no "blocked action" error |
| assisted combat | ASSISTED_COMBAT_ROTATION_ACTION_BUTTON_HELPTIP | `/dump C_AssistedCombat and C_AssistedCombat.IsAvailable()` |
| Dragonflight crafting family | the `permanent` crafting-quality / optional-reagent / recraft rows; the listed PROFESSIONS_CRAFTING_HELP_* tiles and PROFESSIONS_TUTORIAL_* HelpTips | action: open any recipe: no quality meter, no optional or finishing slot, no concentration; if one shows, the family is relisted |
| profession tool slots | PROFESSION_EQUIPMENT_LOCATION_HELPTIP, PROFESSIONS_CRAFTING_HELP_GEAR | `/dump ProfessionsFrame.CraftingPage.Prof0ToolSlot:IsShown()` with the professions window open |
| bank tabs | BANK_TAB_DEPOSIT_ASSIGNMENTS, BANK_TAB_EXPANSION_ASSIGNMENT | `/dump C_Bank.ShouldUsePlayerBagsInBank()` (true ⇒ no bank tabs) |
| club finder | CLUB_FINDER_RECRUITING_ALL_SPECS | `/dump C_ClubFinder.IsEnabled()` |
| guild reputation bar | FACTION_STANDING_LABEL* on the guild bar | `/dump C_Reputation.GetGuildFactionData()` |
| comparison cycling | ITEM_COMPARISON_*, ITEM_DELTA_* | `/dump GetCVarBool("allowCompareWithToggle")`; shift-hover a weapon with two equipped |
| item lines | ITEM_SPELL_MAX_USABLE_LEVEL, ITEM_UPGRADED_LABEL, ITEM_UPGRADE_NO_MORE_UPGRADES | action: note any item showing "(Requires level N or below)", an "Upgraded" loot toast, or an item-upgrade window |
| other conditional windows | player choice, toggle-difficulty ready check, guild-group banner, recipe toast rank, Trial of Style, currency transfer, item interaction, weapon illusion, muted-account tooltip, chat-disabled tooltips, WoW Token balance | action: note when seen; no dedicated step |
| broadcast time (permanent) | BNET_BROADCAST_SENT_TIME | action: hover a Battle.net friend with a broadcast: expected a Lua error or no time line (the colour global is undefined on camelot) |

At level 1: the context menus (Group Finder browse), the Edit Mode utility tooltips, the combo-point
energize (a Rogue), the HelpTips of a first map / Edit Mode open, the quest timer (quest 3522, a 300-second timer,
reachable at level 2) and the Communities chat separators need no special content.

## Outcome

- The table is applied: the `list` rows are in `pipeline/ui_keys.txt` and drafted, the `permanent` rows' reasons are
  in `pipeline/ui_exclusions.txt`, and a test holds both files to this table.
- The context-menu hook is built as sourced above, and the new forms and hooks as listed, each with its busted case.
  [ADR-038](../adr/038-menus-callouts-and-composite-forms.md) records the new forms, the utility-button and
  context-menu hooks, the `|A` / `|cn` markup tokens and the item-tooltip appended lines.
- Open observations: Forever's "Equipped" `CompareHeader.Label` on shopping tooltips; the listed
  `APPRENTICE`…`ARTISAN` and micro-menu `NEWBIE_TOOLTIP_*` keys (from Era) may never render on Forever; the listed
  `BATTLEGROUND_YOUR_PERSONAL_RATING` / `BATTLEGROUND_ROLE_AVERAGE_MMV` sit behind the same rated-only gate as the
  `MATCHMAKING_*` rows.

## Related

- [ADR-038](../adr/038-menus-callouts-and-composite-forms.md) · [ADR-031](../adr/031-objective-lines-menus-and-helptips.md) ·
  [ADR-033](../adr/033-level-1-gaps-name-list-tails-and-untagged-menus.md) · [ADR-015](../adr/015-ui-text-surfaces.md)
- [Forever window sweep](2026-09-19-forever-window-sweep.md)
