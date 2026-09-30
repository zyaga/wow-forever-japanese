# ADR-038: Menus, HelpTip callouts and composite lines on every Forever window: the forms, hooks and markup that show them

- **Status:** Accepted. Implemented in `addon/WoWForeverJapanese/Core/UIStrings.lua` (the
  `entryList` / `entryOrText` kinds, a colour-wrapped `entry`, `time` taking `<`, the `seq` fill),
  `Core/UIStringKeys.lua` (the label forms, the `ARGS` and `ONLY` entries), `Core/Objectives.lua` (thousands separators), `UI/Labels.lua`
  (`showArgs`, `part`), `UI/HelpTooltip.lua` (`appended`, `refit`), `UI/Menus.lua` (utility-button owners, the
  optional `show`, `UNTAGGED` context specs, `MenusUnit.WHICH`), `UI/MenusTags.lua`, `UI/MenusUnit.lua`,
  `UI/MenusUntagged.lua` (the `Menu.PopulateDescription` post-hook), `UI/ChatSystem.lua` (`hookKeyed`,
  `translateOnly`), `UI/HelpTips.lua` and the other surface files (57 `UI/*.lua` files in all), the TOC;
  `pipeline/wfj/core/markup.py` (`|A`, `|cn`), `pipeline/wfj/dev/translate_batch.py` (`cut` reads
  `objective_names.txt`), `pipeline/wfj/dev/ui_windows.py` (`CommunitiesUtil.lua`), `ui_keys.txt`,
  `ui_exclusions.txt`, `ui_inventory.txt`. The in-game checks are pending (the
  level-1 checklist in [Testing strategy](../testing/strategy.md)).
- **Date:** 2026-09-25

## Context

About 600 inventoried UI keys were still excluded as "not handled yet": menu entries, markup-carrying strings and
HelpTip callouts, reworded lines, objective lines, the SocialUI card view, composite lines, and the unit menus outside
level 1. Two principles set the bar: every text is in scope on Forever, and menus show Japanese. The
[research](../research/2026-09-25-menus-callouts-and-composites.md) gives every key one disposition (`list` or
`permanent`, a few sent to the owned-keys work of [ADR-037](037-staticpopup-dialogs-and-owned-keys.md)) and names the
form or hook each listed key needs.

What the existing mechanisms could not reach:

- **Menus with no hook point.** 48 tagged menus of other windows were not in `Menus.TAGS`; 13 unit `which`s had no key
  list; the utility buttons on a menu element (the gear / cancel / play-sample icons,
  `blizzard_menu/menutemplates.lua:645–649`) own their own tooltip, and only the element frame was registered, so the
  shipped Edit Mode `HUD_EDIT_MODE_DELETE_LAYOUT` / `_RENAME_OR_COPY_LAYOUT` hovers never showed Japanese; and two
  context menus are built with `MenuUtil.CreateContextMenu`, which sets no tag and calls no `RegisterMenu`.
- **Composite lines.** An argument that is a colour-wrapped entry ("|cffffd200Today|r", `guildnews.lua:121`), a
  comma-joined list of entries (a bag's filters), a label with a count, a duration or an atlas after it, a header
  followed by names, a line whose three sentences each are an entry (the voice-channel announce), a tooltip line a
  writer appends to an **item** tooltip (which `HelpTooltip.walk` leaves to the item path), a SimpleHTML text (the
  guild event log) and a `ScrollingMessageFrame` log (the guild bank).
- **Markup.** `core/markup.py` did not count `|A…|a` atlases and the curation test banned them from listed English; a
  named colour opener `|cnNAME:` was not counted (only its `|r`), so a Japanese that dropped it passed.

## Decision

1. **Permanent only on source evidence.** A key is `permanent` only when the Forever extract proves it never
   shows: a file camelot does not load, a camelot override that replaces the writer, dead code, no words of its own,
   another flavour's system whose gate is in the source. Reachability only the game can show is `list` with an
   in-game check. The Dragonflight crafting systems keep their precedent: tooltip lines `permanent` with the gate
   cited; their HelpTips and help-plate tiles `list` (shown at no extra cost if they ever fire).
2. **`FULLDATE` is a Japanese date.** `%1$s, %2$s %3$d %4$d` (weekday, month, day, year) ships in the
   year 年 month day 日 (weekday) shape ("2026年9月25日(金曜日)"); the weekday and month are `word` arguments shown in Japanese. Nothing on
   record backs "dates keep the client's format".
3. **One English, one Japanese.** `AVAILABLE`, `TRADESKILL_FILTER_SLOTS` ("Slots") and
   `MOUNT_JOURNAL_FILTER_GROUND` ("Ground") each collide with a shipped key of another meaning: they need per-screen
   Japanese (`UIStrings.OWN`, [ADR-037](037-staticpopup-dialogs-and-owned-keys.md)) and stay English until they have it.
4. **Colour markup is no bar to listing** (ADR-016's precedent).
5. **`|H` link labels stay verbatim.** The whole link is one token; only the text around it is translated
   (`RAF_NO_RECRUITS_DESC`, `TEXT_TO_SPEECH_MORE_VOICES`). `ACTION_SWING`, shown only as a link label, is `permanent`.
6. **Communities chat: client text only.** The date / unread separators and the message-of-the-day label are
   rewritten; the club broadcast inside the MOTD line and every member's message are never touched: player text is
   not ours.
7. **StaticPopups are not part of this.** [ADR-037](037-staticpopup-dialogs-and-owned-keys.md) covers the StaticPopup
   dialogs.
8. **`|A` and `|cn` are markup.** `markup.TOKEN` counts an atlas `|A<atlas>…|a` verbatim like a file texture, and a
   named colour opener `|cnNAME:` like a hex one, its name verbatim (`VERBATIM = ("|T", "|A", "|cn")`); a Japanese that
   drops or alters one is `markup_changed`. `test_ui_keys.py` allows `|A` in listed English. `|K` and `$` stay out by
   curation. This amends [ADR-031](031-objective-lines-menus-and-helptips.md) §4.
9. **New argument kinds (`Core/UIStrings.lua`, declared per key in `Core/UIStringKeys.lua`).**

   | kind | what it takes | fill |
   |---|---|---|
   | `entry` (widened) | an entry, or an entry wrapped in one `\|cAARRGGBB…\|r` (`Index:entryArg`) | the entry's Japanese, the colour kept around it |
   | `entryList` | `LIST_DELIMITER`-joined pieces, every one an entry (`Index:entryList`); any other piece fails the match | each piece in Japanese, each delimiter as written |
   | `entryOrText` | an entry if it is one, else anything | the entry's Japanese, or the text as written (`QUICK_JOIN_TOAST_MESSAGE`'s queue) |
   | `time` (widened) | a leading `<` too | `LESS_THAN_ONE_MINUTE`, `LASTONLINE_MINS` join `DURATIONS` |

   Names inside every new template (players, tabs, channels, spells, layouts, recipes, currencies, adapters) are
   `text` or `verbatim`, kept as written. A template with little literal text, a `verbatim` / `entryOrText`
   argument, or a writer that asks by key is key-only (`UIStrings.ONLY`).
10. **New label forms (`LABELS` in `Core/UIStringKeys.lua`, granted per key).**

    | form | shape | keys |
    |---|---|---|
    | `colonPrefixEntry` | `colonPrefix` whose rest is itself this entry ("Sold By: Multiple Buyers") | `AUCTION_HOUSE_MAIL_MULTIPLE_BUYERS` / `_SELLERS` |
    | `countLabel` | "\<entry> (\<n>)" | `MAIL_MULTIPLE_ITEMS` |
    | `durationSuffix` | "\<entry> [01:23]" | `DAMAGE_METER_COMBAT_NUMBER` |
    | `iconAfter` | "\<entry> \|A…\|a" | `COOLDOWN_VIEWER_SETTINGS_BUTTON_REVERT_CHANGES` |
    | `headerLines` | "\<entry>\n\<name>\n…", the names as written | `HAVE_MAIL_FROM` |
    | `voiceParts` | "[\|A…\|a]\<sentence>. \<sentence>. \<n sentence>.", each sentence an entry | `VOICE_CHAT_CHANNEL_ANNOUNCE` |
    | `paragraphs` (widened) | a paragraph may be colour-wrapped (the muted-account paragraph, `social.lua:21–29`) | `OPTION_TOOLTIP_DISABLE_CHAT*` |

    Existing forms take the rest: `binding` (`MAINTANK` / `MAINASSIST` / `PETS`, the voice mute titles,
    `TRANSMOG_SHEATHE_WEAPON_TOOLTIP`), `wrapped` (the quality-coloured filter entries, grey / red / light-grey
    labels), `icon`, `colonPrefix` (`COOLDOWN_REMAINING`, `TIME_REMAINING`), `colon`. A `seq` fill writes parts in
    order (text as written, `{ key, args[, open, close] }` filled) for lines a surface splits itself.
11. **Composite lines a surface splits itself: `Labels.showArgs` / `Labels.part`.** `Labels.part(text, only)` matches
    one piece against a key set; the surface builds `seq` / `affix` args from the pieces and shows the line with
    `Labels.showArgs(surface, recKey, widget, key, args)`, which keeps the Alt / switch / area behaviour of
    `Labels.show` and never turns its own Japanese back to English on a re-run. Forms that have one user live in that
    surface: the combat-text `energize` ("<3 Combo Points>", only `COMBO_POINTS`) and `AURA_END` (the combat-text
    trailers use the `affix` form); the death-recap trailer (`DEATH_RECAP_DAMAGE_TT` with its `TEXT_MODE_A_STRING_RESULT_*` groups); the
    ready-check line; the Event Trace row; the guild bank tab title (split at the last double space); the guild
    officer permissions (`|n`-joined, all-or-nothing); the recipe toast's "%s (Rank %i)" with its star.
12. **Item-tooltip appended lines: `HelpTooltip.appended(tt, opts)`.** `walk` still leaves item tooltips alone. A
    surface calls `appended` right after the writer that appends to one (`AuctionHouseUtil.AddAuctionHouseTooltipInfo`
    (sellers, time left), the enchant slot's replace hint, an order reagent's provider line, a bag's
    `BAG_FILTER_ASSIGNED_TO`), and every left line is matched **only** against `opts.only` (required). The item's own
    lines are no key of that set, so they stay with `UI/Tooltip` and are never rewritten twice. Records live on
    their own surface, released on the tooltip's `OnHide`. `HelpTooltip.refit` is exported for a surface that writes
    a line itself (`UI/QuestMap`'s dashed objective lines), so its `Show` never starts a walk.
13. **Other tooltip frames reuse `TooltipLines.follow`.** `EventTraceTooltip` ("Timestamp:", "Arg %d:"; one
    follow, surface `eventtrace.tooltip`) and `EmbeddedItemTooltip` while its owner is a Recruit-A-Friend activity
    chest. There is no generic "any tooltip frame" walker.
14. **Menus.**
    - `UI/MenusTags.lua` (data, loaded after `UI/Menus.lua`) adds the other windows' tags to `Menus.TAGS`, each with its `source`
      file:line, `keys`, `tooltips`, `titleIsName` where the first element is a name, and extends 3 existing tags
      (Edit Mode's character-layouts header, the queue eye's arena / pet-battle entries, the world-quest filters).
      `UI/Menus.lua` stays one mechanism.
    - `Menus.showElement` registers each of the element's children (its utility buttons, parented to the element,
      `compositor.lua:34–46`) as help-tooltip owners with the tag's `tooltips`.
    - A tag may carry `show(surface, recKey, fs)`, called when the `only` match found nothing (the damage meter's
      "Combat 3 [01:23]" session entries, `DamageMeter.showSession`).
    - `MenusUnit.WHICH` holds 13 unit `which`s, each with its own list (`BN_FRIEND`, `BN_FRIEND_OFFLINE`,
      `RAID_PLAYER`, `RAID`, `COMMUNITIES_WOW_MEMBER`, `COMMUNITIES_GUILD_MEMBER`, `COMMUNITIES_MEMBER`,
      `COMMUNITIES_COMMUNITY`, `GUILDS_GUILD`, `CHAT_ROSTER`, `RECENT_ALLY`, `RECENT_ALLY_OFFLINE`,
      `DISCORD_USER_SELF`): the effective entries (shared ← mainline ← camelot overrides) mapped through each
      button's `GetText`. Every one is `titleIsName`; the entries beside protected actions (focus, main tank) are
      text-only writes, as in [ADR-032](032-level-1-gaps-subtexts-and-name-titles.md).
    - **Untagged context menus: `hooksecurefunc(Menu, "PopulateDescription", …)`** in `UI/MenusUntagged.lua`.
      `MenuUtil.CreateContextMenu` looks the field up at call time and populates before it opens
      (`menuutil.lua:157–161`), so the post-hook holds the populated description before any element frame exists
      (the point a `ModifyMenu` callback runs at), so the menu is laid out with the Japanese. It returns at once unless
      the description has no tag and one of two recognisers holds: the Group Finder search-entry menu (an element
      whose text is `LFG_LIST_REPORT_GROUP_FOR` or `REPORT_GROUP_FINDER_ADVERTISEMENT`, both with a space, never a
      character name; the first element, the leader's name, is the title) and the crafting-orders recipe menu
      (`owner.contextMenuGenerator == generator`). They walk as `Menus.UNTAGGED.CONTEXT_LFG_SEARCH_ENTRY` /
      `CONTEXT_CUSTOMER_ORDER_RECIPE`.
15. **HelpTips.** `HelpTips.KEYS` gains the reachable callouts of every other window (Edit Mode, the auction house,
    the world map, currencies, the assisted-combat button, loot history, the chat language button, voice, the queue
    eye, collections and the wardrobe, the transmogrifier, professions and crafting orders); `PLATE_KEYS` the
    professions and transmogrifier help-plate tiles. Same `ApplyText` hook (ADR-031 §3).
16. **Key-restricted chat path: `ChatSystem.hookKeyed(frame, keys)`.** A message frame outside `CHAT_FRAMES` whose
    client lines are one of a few keys (the Communities `Chat.MessageFrame`: `COMMUNITIES_CHAT_FRAME_TODAY_ /
    _YESTERDAY_ / _UNREAD_MESSAGES_NOTIFICATION`, `COMMUNITIES_MESSAGE_OF_THE_DAY_FORMAT`) gets `AddMessage` and
    `BackFillMessage` post-hooks. Only a line that is wholly one of those keys (`ChatSystem.translateOnly`) is
    rewritten, once, in the history, as ADR-035 §7; the visible lines follow Alt and the switch the same way.
17. **The guild logs.**
    - **Event log:** `CommunitiesGuildLogFrame`'s SimpleHTML is **parsed, not rebuilt**. A `SetText` post-hook reads
      each text the client writes; every `|n` line is matched as its `GUILDEVENT_TYPE_*` template (player names and
      the rank kept) followed by the `GUILD_BANK_LOG_TIME` suffix; a line that matches nothing stays as written. An
      adapter gives `Render` the FontString interface (the SimpleHTML has no `GetText`).
    - **Guild bank log:** `GuildBankMessageFrame:AddMessage` post-hooked on the instance; the time suffix and
      `GUILDBANK_LOG_QUANTITY` are peeled, the head is matched by key, the entry rewritten with `TransformMessages`
      (ADR-035 §7's pattern); the pairs of the current log are remembered until the next `Clear()`.
    - Guild news `GUILD_EVENT_FORMAT` (the day a colour-wrapped entry), the reputation bar's standing word, the text-
      edit dialog title; guild control's officer permissions and Discord labels.
18. **Objective lines.** A count with thousands separators ("0/1,200 …") is split and kept as written
    (`[%d,]` in both `Objectives.split` patterns). A `QUEST_DASH` line in the quest-list title tooltip is looked up
    through the objective path, the dash kept. The quest-list title button takes the row's height change (it was sized
    to the summed English heights, `questmapframe.lua:1959–1961`) and the list is laid out once per update.
    Content-tracking lines and vignette "Defeat %s" objectives join. `cut` leaves out the ids in
    `pipeline/objective_names.txt`.
19. **The add-alert disabled tooltip.** `COOLDOWN_VIEWER_SETTINGS_ACTION_ADD_ALERT` ("Cannot add cooldown alert: %s",
    an `entry`, key-only) and `COOLDOWN_VIEWER_SETTINGS_ADD_ALERT_TOOLTIP_DISABLED_NO_VALID` are listed, not treated as
    chat lines: the `_TOO_MANY` status is only ever shown inside that template
    (`cooldownviewersettings.lua:291–292, 1793–1798`), so the template and its statuses belong to the menu tooltip.
20. **Names stay out of the new templates.**
    - **The new templates are key-only.** Every template this ADR adds whose argument holds text (`text`, `words`,
      `entry`, `entryOrText`, `entryList`, `verbatim`) is in `UIStrings.ONLY`: each surface already asks for it by
      key, and an unrestricted match took names ("%s Recipe", "%s Begins", "Illusion: %s" around an item, quest or
      spell name). `matchOnly` also takes a key-only `wrapped` template (a macro's title, the layout headers). A
      busted spec runs every English item / spell name, quest title and objective line through the unrestricted
      match and fails on any of these keys.
    - **Calendar event-name keys follow the event's type.** `CALENDAR_EVENTNAME_FORMAT_START` / `_END` (a holiday's
      start / end, tooltip only) and `_RAID_LOCKOUT` / `_RAID_RESET` are offered only for a line showing a `HOLIDAY` /
      `RAID_LOCKOUT` / `RAID_RESET` event (`CALENDAR_CALENDARTYPE_(TOOLTIP_)NAMEFORMAT`, `blizzard_calendar.lua:
      395–452`; the event read back through `C_Calendar.GetDayEvent`). A player / guild / community event is a plain
      "%s" the player typed: "Raid Night Begins" stays byte-identical. Two identical lines the day's events cannot
      tell apart both stay English.
    - **An `entry` is never a template that carries text.** An `entry`-kind argument takes an exact entry or a
      template whose arguments are numbers, times, percentages or dictionary words; a template with a text-like
      argument is admitted only when the enclosing key is listed in `UIStrings.ENTRY_TEXT` (none is), so
      "- Defeat Hogger (Current Health: 50%)" is no `"%s (%s)"` line.
    - The voice announce parts answer only a caller that asks for `VOICE_CHAT_CHANNEL_ANNOUNCE`; the untagged-menu
      hook never raises into the client's menu (errors go to `WFJ.initErrors`); the Communities chat hook tests a
      line against its keys' English before any lookup.

## Consequences

- Every key of the research table has its disposition (`test_ui_dispositions.py` reads the table). Every menu Forever
  can open shows Japanese entries with names, layouts, channels and titles as written; English stays one key-hold away.
- Every change to shared code is additive (a new kind, form, token, registry entry): each `UIStrings` / `Labels` /
  `HelpTooltip` / `Menus` consumer keeps its behaviour, and every existing spec and pytest vector passes unchanged
  (the research doc's §8 table).
- A menu entry Blizzard adds to a tag later stays English until its key joins the tag; a new untagged context menu
  needs its own recogniser.
- The `PopulateDescription` hook runs on every menu the client opens; it returns at once for a tagged one. Taint of
  the Group Finder invite / report actions after it is an in-game check.
- `appended` and `hookKeyed` only touch lines of their key set: another addon's tooltip line or chat line is never
  taken for one.
- Many surfaces are built without proof that Forever shows them (content tracking, vignettes, crafting orders,
  transmogrification, guild bank, voice, Discord, the achievements game rule, combo-point energize, bank tabs,
  comparison cycling); a surface Forever never opens costs nothing. The SimpleHTML adapters (guild event log,
  Recruit-A-Friend, player choice) assume the plain text draws with the `P` font [unverified; in game].
- `|A` and `|cn` in a listed English are now checked in every Japanese; a draft that drops one is rejected at import.
- Shared-English groups ship one Japanese (the shipped one reused); "Slots" and "Ground" stay English until given
  their own Japanese (`UIStrings.OWN` gives "Available" the trainer filter's).

## Alternatives considered

- **A post-hook on `LFGBrowseFrame.CreateSearchEntryMenu`**: rejected: it runs after the menu is laid out in English
  and needs a relayout (the approach ADR-033 rejected for untagged dropdowns). **Replacing the method**: rejected, it
  taints the invite path. **The `MenuProxy.OnShow` event**: rejected, also after layout.
- **Rebuilding the guild event log from `GetGuildEventInfo`**: rejected: the client's own text is what Alt must show;
  parsing what it wrote keeps one source of truth.
- **A generic walker for any tooltip frame**: rejected; only the item-tooltip tail and the two named
  frames are needed.
- **Letting `walk` read item tooltips with a key set**: rejected: the item path (`UI/Tooltip`) owns those lines; a
  second walk would rewrite them twice.
- **Keeping `|A` out by curation**: rejected: listed English carries atlases (the Edit Mode expand / collapse
  labels) and several lines take one around or inside the text (the undo button, the voice announce, the Discord
  label); counting it verbatim, like `|T`, is the smaller change.

## Related

- [ADR-015: UI text surfaces](015-ui-text-surfaces.md) · [ADR-031: objective lines, menus and HelpTips](031-objective-lines-menus-and-helptips.md) ·
  [ADR-033: untagged menus](033-level-1-gaps-name-list-tails-and-untagged-menus.md) ·
  [ADR-035: game-message lines](035-ui-errors-frame-surface.md)
- [Research](../research/2026-09-25-menus-callouts-and-composites.md) · [Addon modules](../architecture/addon-modules.md) ·
  [Pipeline](../systems/pipeline.md) · [Translation batches](../operations/translation-batches.md)
