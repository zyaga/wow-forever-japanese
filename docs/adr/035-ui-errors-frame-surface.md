# ADR-035: Game-message lines: the UI errors frame, system chat and NPC speech, each matched against its own key

- **Status:** Accepted. Implemented in `addon/WoWForeverJapanese/UI/Errors.lua`,
  `UI/ChatSystem.lua` (§7–§9), `UI/Speech.lua` (§10), `Core/UIStrings.lua` (`isErrorKey`, `isChatKey`, `argKinds`,
  `keyOnly`), `Core/UIStringKeys.lua` (`CHAT_FAMILIES`, `ERROR_UNRESTRICTED`, the `ERROR_CLUB_ACTION_*`,
  `CLUB_REMOVED_REASON_*`, system chat and `CHAT_*_GET` `ARGS`), `Main.lua`, the TOC; `pipeline/wfj/cmd/validate.py` (`key_arg_kinds`,
  `ui_chat_families`), `pipeline/wfj/dev/ui_windows.py` (`FOREVER_WINDOWS["errors"]` / `["chatsystem"]` /
  `["speech"]`, `DYNAMIC["errors"]` / `["chatsystem"]` / `["speech"]`), `pipeline/wfj/dev/ui_inventory.py`
  (`errors_call_keys`, `chat_call_keys`),
  `pipeline/wfj/io/vmangos.py` (`read_speech`), `pipeline/wfj/cmd/import_english.py`,
  `pipeline/wfj/dev/translate_lint.py` (`speaker:`), `pipeline/forever_addon_dispositions.txt`, `ui_keys.txt`,
  `ui_exclusions.txt`. The in-game checks are pending (the game-message checklist in
  [Testing strategy](../testing/strategy.md)).
- **Date:** 2026-09-23

## Context

The red and yellow lines in the middle of the screen ("Out of range.", "Not enough mana", "Inventory is full.",
"Kobold Vermin slain: 3/10") are the most frequent English a level-1 player sees. `blizzard_uierrorsframe` was disposed
`not-a-window`, so none of them were inventoried.

The C client sends them: `UI_ERROR_MESSAGE` / `UI_INFO_MESSAGE` carry `(messageType, message)`, and
`UIErrorsMixin:TryDisplayMessage` calls `self:AddMessage(message, r, g, b, 1.0, messageType)`
(`blizzard_uierrorsframe/mainline/uierrorsframe.lua:13–24, 146–157`). `UIErrorsFrame` is a `MessageFrame`, one line
per message id (`GetFontStringByID`). `GetGameMessageInfo(messageType)` returns the GlobalStrings key of that message
(`gameerrordocumentation.lua:10–25`; the client reads `_G[it]` itself, `blizzard_channels/mainline/voiceutils.lua:82–84`).

Forever 1.60.1.69913 has 2,720 `ERR_*` / `SPELL_FAILED_*` keys. Many are generic templates (`"%s."`, `"%s slain:
%d/%d"`, `"Requires %s"`) that would take other surfaces' lines if the UI index matched them unrestricted, and most
of their `%s` are names (mobs, items, zones), which stay English ([principle 2](../architecture/principles.md#2-names-stay-in-english)).

The same keys, and many more system lines (loot, money, experience, reputation, away / busy, time played), reach
the chat window, where the rest of a level-1 player's English is: the prefix before a player's line ("says:",
"whispers:") and what NPCs say, yell and emote, in chat, in speech bubbles and, for boss emotes, in the middle of
the screen. NPC speech is server text (VMaNGOS `broadcast_text`), keyed like gossip; the rest is GlobalStrings.

## Decision

1. **id → key → a match restricted to that key.** `UI/Errors.lua` (surface `errors`) post-hooks the
   **`UIErrorsFrame` instance's** `AddMessage` (mixin methods are copies, so the instance, not `UIErrorsMixin`). For a
   numeric message id: `GetGameMessageInfo(id)` (called under `pcall`, since another addon's `AddMessage` may pass any
   number as its id) → the key; the line, looked up on the next frame (§6), is shown through `Labels.show` with
   `only = { [key] = true }`. No id, no key, an unlisted key, or text that is not the key's English (another addon's
   `AddMessage` under that id) → the line goes to the Lua-line rule (§6), which leaves anything else as written.
   Alt shows the live English through the usual `Render` refresh. A line with no id (`SYSMSG`,
   `uierrorsframe.lua:14–16`, and Blizzard's own Lua `AddMessage` calls) and an `AddExternalErrorMessage` /
   `AddExternalWarningMessage` line (`LE_GAME_ERR_SYSTEM`, `:158–163`) take the same §6 rule.
2. **A pass-through wrapper is resolved against the listed error keys.** A key whose live English is exactly `"%s"`
   (`ERR_SPELL_FAILED_S` and the like) carries another message's text. Its line is matched against every listed
   `ERR_*` / `SPELL_FAILED_*` key that has **at least four letters of its own** outside its specifiers. An exact
   string qualifies; `"%s."` (`ERR_TAME_FAILED`) never does, so a wrapper never turns another addon's sentence into
   Japanese. The set is built once per UI index.
3. **An undeclared error key's `%s` is `text`; every error template is key-only.** `UIStrings.argKinds(key)`: a
   key's `UIStrings.ARGS` entry if it has one, else every `%s` is `text` (kept as the client wrote it) for an `ERR_*` /
   `SPELL_FAILED_*` key, else none. `UIStrings.keyOnly(key)`: `UIStrings.ONLY`, or any error key not in
   `UIStrings.ERROR_UNRESTRICTED`, whether or not it declares kinds, so no other surface's unrestricted match ever
   sees an error template. `ERROR_UNRESTRICTED` holds seven keys that keep their unrestricted match:
   `ERR_CLUB_FINDER_ERROR_TYPE_FLAGGED_RENAME` (a window matches it unrestricted; keeps `word`), and six that share
   their English with another surface's template, where one template is compiled per distinct English under the key
   that sorts first: `ERR_USE_LOCKED_WITH_ITEM_S`, `ERR_USE_LOCKED_WITH_SPELL_S`, `SPELL_FAILED_REQUIRES_SPELL_FOCUS`,
   `SPELL_FAILED_TOTEMS`, `SPELL_FAILED_TOTEM_CATEGORY` take `ITEM_REQ_SKILL`'s `skill` ("Requires %s");
   `ERR_RAID_LEADER_READY_CHECK_START_S` takes `READY_CHECK_MESSAGE`'s `text`.
   Declared kinds for arguments that are words or durations, not names [unverified: the exact words the client
   passes; the in-game checklist]:

   | kind | keys |
   |---|---|
   | `words`: a mechanic ("stunned") | `ERR_ATTACK_PREVENTED_BY_MECHANIC_S`, `ERR_USE_PREVENTED_BY_MECHANIC_S`, `SPELL_FAILED_PREVENTED_BY_MECHANIC` |
   | `words`: a power ("mana") | `ERR_SPELL_FAILED_ALREADY_AT_FULL_POWER_S` |
   | `words`: an item class ("Shield") | `SPELL_FAILED_EQUIPPED_ITEM_CLASS`, `_MAINHAND`, `_OFFHAND` |
   | `words`: a difficulty | `ERR_DUNGEON_DIFFICULTY_CHANGED_S`, `ERR_RAID_DIFFICULTY_CHANGED_S`, `ERR_PLAYER_DIFFICULTY_CHANGED_S`, `ERR_LEGACY_RAID_DIFFICULTY_CHANGED_S` |
   | `time`: a cooldown | `ERR_PARTY_LFG_BOOT_COOLDOWN_S`, `ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S`, `ERR_PARTY_LFG_BOOT_INPATIENT_TIMER_S`, `ERR_DIFFICULTY_CHANGE_COOLDOWN_S`, `ERR_DIFFICULTY_CHANGE_COMBAT_COOLDOWN_S`, `ERR_CHALLENGE_MODE_RESET_COOLDOWN_S` |

   A `words` argument is shown in Japanese when it is a dictionary entry, as written otherwise.
   `validate.key_arg_kinds` mirrors the default, so the adjacent-capture check sees the same kinds.
4. **Triage: list by default.** `DYNAMIC["errors"]` inventories every `ERR_*` / `SPELL_FAILED_*` key. Each is listed
   or excluded with a reason:

   | verdict | when |
   |---|---|
   | exclude: pass-through | English exactly `%s` |
   | exclude: link | English holds `\|H` player / store links |
   | exclude: not on Forever | the key belongs to a system the client files show Forever lacks (player housing, pet battles, garrisons / class halls, covenants / soulbinds, Azerite, artifacts, solo dungeons, Torghast / the Maw, Plunderstorm, runecarving, the Great Vault); the reason names the system and its evidence (housing: `## AllowLoadGameType: standard` in `blizzard_housingcharter.toc` / `blizzard_housingdashboard.toc`, never loaded on Forever) |
   | list | everything else, including every key whose system cannot be shown absent from the client files |

   A few other exclusions stay with their own reasons (an artifact relic line, the two housing decor screenshot lines,
   a pet-battle queue line, three retail-era talent config lines, Party Sync).
   The inventory also covers every string Blizzard's Lua puts on the frame (§6): `errors_call_keys` scans
   every errors-frame call (`AddMessage`, `AddExternalErrorMessage`, `AddExternalWarningMessage`, `CheckAddMessage`)
   in the camelot load set (`client_addons.sweep`) for the keys named on the call line, and `DYNAMIC["errors"]`
   gains the families Blizzard passes through a variable: `ERROR_CLUB_*`, `ERROR_COMMUNITIES_*`,
   `GUILD_RENAME_ERROR_*`, `REPORT_RESULT_*`, `PING_FAILED_*`, `RADIAL_ERROR_*`, `CRAFTING_ORDER_FAILED_*`, the
   `PROFESSIONS_*` order and auto-equip lines, `PAPERDOLL_AUTO_EQUIP_*_ONLY`, the talent-config throttle, the token
   lines and the removed-from-a-community lines (`CLUB_REMOVED_REASON_*`). The scan reads one line per call: a key
   assigned to a variable on an earlier line, or a call split over several lines, is not seen; the helper families
   name the known ones. The gamepad-prompt exclusions (`RADIAL_ERROR_*`, `ERROR_NO_FRAME_TO_FOCUS`) stay: listing
   them would translate a prompt the client sizes from its English.
5. **Throttled repeats see the client's English.** The frame throttles a repeat of the same message by comparing the
   shown text with the incoming English (`THROTTLED_MESSAGE_TYPES`, `TryFlashingExistingMessage`,
   `uierrorsframe.lua:54–75, 118–127`). Once the line shows Japanese that comparison never holds, so without help the
   client re-adds the line and replays its error sound / voice line on every press (`:146–155`). `UI/Errors.lua`
   wraps the **instance's** `ShouldDisplayMessageType` (`Errors.wrapShould`), which is called only from
   `TryDisplayMessage`: the frame's event handler and the voice-channel error display (`blizzard_channels`). While
   the line of that id is our Japanese for that same English, the wrapper puts the client's English back for the
   length of the original check, then restores the Japanese; the client decides exactly as it would without the
   addon: a throttled type flashes its existing line silently, any other type adds a new line. When the check starts
   a flash, the flash's `origMsg` is set to the Japanese, so the flash (`OnUpdate`, `:31–52`) ends on the Japanese.
   **Taint:** the wrapper runs only inside the errors frame's event handler and the voice-channel error display,
   neither of which reaches a protected call. `TryFlashingExistingMessage` itself is not touched: it is also used by
   `AddExternalMessage`, which Blizzard's action code calls, and wrapping it would put addon code on those paths.
6. **A line Blizzard's Lua adds: an exact dictionary English, or one of the Lua-formatted templates.** Most of the
   frame's Lua call sites pass no id (`UIErrorsFrame:AddMessage(KEY, 1, .1, .1, 1)`); `AddExternalErrorMessage`
   passes `LE_GAME_ERR_SYSTEM`. A line with no id, with `LE_GAME_ERR_SYSTEM`, or whose id's key did not match (§1) is
   matched **exactly** against the whole dictionary (one English is one Japanese, the `UI/HudLabels` action-status
   rule), and otherwise only against the templates Lua formats (`Errors.LUA_TEMPLATES`: `TOO_MANY_WATCHED_TOKENS`,
   `ACHIEVEMENT_WATCH_TOO_MANY`, plus the `ERROR_CLUB_ACTION_*` and `CLUB_REMOVED_REASON_*` families). Never any other
   template, so another addon's sentence is never taken for one. `ERR_QUEST_ADD_FOUND_SII` (`questmapframe.lua:573`)
   is not in the set: its Japanese is its English (`"%s: %d/%d"`), and a template with no letters would take any other
   addon's "x: 1/2" line. A community action's line is the action's sentence around a community error sentence
   (`communitieserrors.lua:120–132`); its `%s` is declared `entry` in `UIStrings.ARGS`, so the error sentence is shown
   in Japanese when it is an entry. A removed-from-a-community line formats the club's name (`:126–132`); its `%s` is
   declared `text`, kept as written. Both families are key-only (`UIStrings.keyOnly`), like the error keys, so no
   other surface's unrestricted match sees their templates.
   **Which line:** every line is looked up on the next frame (`C_Timer.After(0)`), when it exists. In game,
   `GetFontStringByID(id)` called right after `AddMessage` still names the previous line of that id: a
   first line was never found, and a quick repeat translated the older line instead of itself (the frame adds a new
   line per repeat of a non-throttled type). The lines are then the id's line when it shows the text, and every
   **shown** region with that text (a pooled, hidden line may still hold an older copy); each line FontString is its
   own record, since two lines of one id can show at once [unverified: that the Forever `MessageFrame`'s lines are
   its regions (the in-game checklist); if they are not, an id's line is still found and a line with no id stays
   English].
7. **Chat system lines: the same error keys, rewritten in the chat history.** The C client and Blizzard's Lua also
   send many of these keys to chat: `ChatFrameMixin:MessageEventHandler` adds a `CHAT_MSG_SYSTEM` line as
   `self:AddMessage(arg1, r, g, b, info.id)` (`chatframeoverrides.lua:395–400`), and `ChatFrameUtil.AddSystemMessage`
   / `DisplaySystemMessage*` make the same call with `ChatTypeInfo.SYSTEM.id` (`chatframeutil.lua:297–315`).
   `UI/ChatSystem.lua` (surface `chatsystem`, area `ui`) post-hooks each chat frame's `AddMessage` on the instance
   (the `CHAT_FRAMES` at init, and any window `FCF_OpenTemporaryWindow` makes later; each frame once). It considers
   only a line whose 5th argument is `ChatTypeInfo.SYSTEM.id` (§8: any plain chat type) and whose text is not secret
   (chat messaging lockdown makes `CHAT_MSG_SYSTEM` text secret, `chatinfodocumentation.lua:2455`). It takes an
   **exact** dictionary English (any key, since one English is one Japanese; this covers the non-error lines Blizzard's Lua
   prints, such as the guild-rename refusal `GUILD_RENAME_ERROR_MUST_BE_IN_A_GUILD` sent through
   `DisplaySystemMessageInPrimary`), else a listed error key's key-only template with at least four letters of its own
   (§2's wrapper set; §8 adds the chat families). Never any other template. A trusted row whose argument fill succeeds rewrites that history entry, once, when it arrives, with
   `TransformMessages`, a secure-elevation wrapper
   whose addon callbacks run tainted (`scrollingmessageframe.lua:95–107, 795–824`), used by Blizzard for the same
   purpose (`itemrefhandlersshared.lua:217`). A stale row or a failed fill leaves the English.
   The hook runs after the add, so the whisper-window routing that compares the English
   (`chatframeoverrides.lua:377–394`) and Blizzard's battleground roll-up filter (`battlegroundchatfilters.lua`) have
   already read it, so no key has to be held back.
   **Alt and the switch:** the history is rewritten once, on arrival, and never again: `TransformMessages` repackages
   each entry it touches with a new timestamp (`PackageEntry`, `scrollingmessageframe.lua:737–745`), so rewriting the
   history on every Alt press would bring every faded line back. Instead, while the modifier is held or the addon / its
   UI area is off, `ChatSystem.show` puts the remembered English on the **visible** lines only (in the frame's own
   font object), and the display-refreshed callback keeps doing so on every refresh (scrolling, a new line) while that
   state lasts; release puts the Japanese back in the bundled face. `ChatSystem.refresh` does nothing until a line has
   been rewritten. A line that arrives while the addon or its UI area is off is not rewritten and stays English for
   good; one that arrives while Alt is held is rewritten and shows English until release.
   **One Japanese, one English:** each rewritten line's Japanese is remembered with its English
   (`ChatSystem.MAX_REMEMBERED` = 4,096 pairs). A line whose Japanese is already remembered for a different English
   stays English: ten or more shipped Japanese strings stand for more than one English, and Alt must never show
   English the client did not write on that line. At the limit, the pairs no chat history still holds are swept out
   (`ChatSystem.sweep`); a pair still held is never forgotten.
   **Font:** each refresh re-initializes a visible line's font from the frame's font object
   (`scrollingmessageframe.lua:642`) and the chat fonts have no Japanese member (`fonts.xml`), so the bundled face is
   put back on every visible line showing one of our Japanese strings from the frame's
   `AddOnDisplayRefreshedCallback` (`:164–175`), sized to fit (§8). Pipeline: `FOREVER_WINDOWS["chatsystem"]` +
   `DYNAMIC["chatsystem"]` (the error patterns, §8's families, §9's prefixes); `blizzard_chatframebase` is disposed
   `surface chattabs,chatsystem`.
8. **System chat: every plain chat type, the chat families, a fitted font.** All system chat is in scope, not only
   the error keys. The event handler adds the chat types that have no sender prefix as the bare
   text: `self:AddMessage(arg1, info.r, info.g, info.b, info.id)` (`chatframeoverrides.lua:397–413`).
   `ChatSystem.PLAIN_TYPES` names them: `SYSTEM`, `SKILL`, `CURRENCY`, `MONEY`, `OPENING`, `TRADESKILLS`, `PET_INFO`,
   `TARGETICONS`, `BN_WHISPER_PLAYER_OFFLINE`, `COLLECTED_APPEARANCE`, `LOOT`, `COMBAT_XP_GAIN`,
   `COMBAT_HONOR_GAIN`, `COMBAT_FACTION_CHANGE`, `COMBAT_MISC_INFO`, `BG_SYSTEM_NEUTRAL` / `_ALLIANCE` / `_HORDE`,
   `ACHIEVEMENT`, `GUILD_ACHIEVEMENT` (their ids from `ChatTypeInfo`, read once). A line of any of them takes §7's
   path. The match is an exact dictionary English, else a key-only template over the **chat keys**, trusted rows
   only: §2's wrapper set, every listed key one of `UIStrings.CHAT_FAMILIES`' Lua patterns names (`LOOT_ITEM*`,
   `LOOT_MONEY*`, `YOU_LOOT_MONEY*`, `CURRENCY_GAINED*`, `COMBATLOG_XPGAIN_*`, `COMBATLOG_HONOR*`,
   `FACTION_STANDING_INCREASED*` / `_DECREASED*`, `SKILL_RANK_UP`, `TRADESKILL_LOG_*`, `OPEN_LOCK_*`, `MARKED_AFK*` /
   `MARKED_DND*`, `CLEARED_AFK` / `_DND`, `LEVEL_UP_*`, `DURABILITYDAMAGE_DEATH`, `INSTANCE_RESET_*`,
   `RANDOM_ROLL_RESULT`, `ACHIEVEMENT_BROADCAST*`), and `ChatSystem.EXTRA_TEMPLATES`: the system lines Blizzard's
   Lua builds outside those families (`GUILD_MOTD_TEMPLATE`, `TIME_PLAYED_TOTAL` / `_LEVEL`,
   `chatframeutil.lua:251–263`, and the two community-channel notices), key-only through `UIStrings.ONLY`. No Lua
   names the families: they follow GlobalStrings naming, and `DYNAMIC["chatsystem"]` inventories the same families
   (`tests/python/test_ui_errors.py` holds the two lists together). A chat-family key is treated exactly like an error
   key (`UIStrings.isChatKey`): key-only, and an undeclared `%s` is `text`. `validate.ui_chat_families` reads
   `CHAT_FAMILIES` from `Core/UIStringKeys.lua` (the one list), so `key_arg_kinds` applies the same default.
   Declared kinds:

   | kind | keys |
   |---|---|
   | `words`: a stat ("Strength") | `LEVEL_UP_STAT` |
   | `verbatim`: the player's own away / busy message, the guild message of the day, as typed | `MARKED_AFK_MESSAGE`, `MARKED_DND`, `GUILD_MOTD_TEMPLATE` |
   | `entry`: the duration line | `TIME_PLAYED_TOTAL`, `TIME_PLAYED_LEVEL` |
   | `text` (`%2`): the channel's name ("2. Trade") | `COMMUNITIES_CHANNEL_ADDED_TO_CHAT_WINDOW`, `_REMOVED_FROM_CHAT_WINDOW` |

   A key whose own English carries a link (`LEVEL_UP`, the `LOOT_ROLL_*` lines that open the loot history) is
   excluded (the dictionary never carries a link), and its line stays English; an item link passed in a `%s` (`LOOT_ITEM_SELF`) is kept as the client wrote it.
   **Font fit:** a Japanese chat line gets the bundled face with `SetFont` directly, at the line's size, then one point
   smaller at a time (never below 8) until its string height fits the height the frame laid the line out at: the
   layout measured the line in the chat font, and without the fit a Japanese line spills over the next one. Never
   `Font.set`'s deferred retry: a refused font retried later can land on a pooled line by then showing another
   message (English lines turned small in the bundled face).
   **The remembered pairs** (§7) are shared with §9 and §10 and record each pair's settings area, so Alt and the
   switch follow the area the line belongs to (`ui`, or `gossip` for NPC speech).
9. **Player chat prefixes: the words only, never the player's text.** The chat frame builds a player's line as
   `format(_G["CHAT_" .. type .. "_GET"] .. message, pflag .. name, name)` (`chatframeutil.lua:352–355`,
   `chatframeoverrides.lua:629–633`). For `ChatSystem.PREFIXED_TYPES` (`SAY`, `YELL`, `WHISPER`, `WHISPER_INFORM`,
   `BN_WHISPER`, `BN_WHISPER_INFORM`, `AFK`, `DND`, `RAID_WARNING`, `CHANNEL_JOIN`, `CHANNEL_LEAVE`),
   `ChatSystem.prefixed` splits the key's live English and its Japanese at the `%s` and swaps only the words before
   and after it in the finished line ("%s says: " → "%sの発言: "); the name, its link, the timestamp and the message
   are left exactly as the client wrote them. The row must be trusted and its source hash must match the client's own
   English for that key (a changed prefix stays English). The line is rewritten once in its frame's history, picked
   by its own line id (`eventArgs[11]`), and remembered as in §7, area `ui`. What the player typed is never touched:
   player text is not ours. A prefix with a channel link (`[Party]`, `[Guild]`, `[Raid]`, `[Instance]`,
   `CHAT_MONSTER_PARTY_GET`) or with no words (`CHAT_CHANNEL_GET` "%s: ", `CHAT_EMOTE_GET` "%s ") is excluded and
   stays English. The prefix keys are all key-only (`UIStrings.ONLY`) with a `text` name: the 11 player types and
   `CHAT_MONSTER_SAY_GET` / `_YELL_GET` / `_WHISPER_GET` (§10).
10. **NPC speech: chat, bubbles and boss emotes, from the gossip lines.** `UI/Speech.lua` (surface `speech`, area
    `gossip`, the "NPC talk" setting) handles `MONSTER_SAY`, `MONSTER_YELL`, `MONSTER_WHISPER`,
    `MONSTER_EMOTE`, `MONSTER_PARTY`, `RAID_BOSS_EMOTE` and `RAID_BOSS_WHISPER`. Its text is the server's: the lookup
    is the NPC talk window's gossip key (the hash of the English), through `Lookup.keyed("gossip", …)`.
    - **Chat.** The event handler formats these types with a `MessageFormatter` closure (`format(CHAT_\<TYPE>_GET ..
      message, pflag .. speaker, speaker)`, the message's `%s` left for the speaker's name,
      `chatframeoverrides.lua:543–633`) and passes it to `AddMessage` with the event's arguments (`:665–672`). The
      post-hook reads the server's English from `eventArgs[1]`, runs the event's own `MessageFormatter` over the
      Japanese (every `%` but the speaker's `%s` escaped), swaps the prefix's words (§9), and rewrites the entry once
      in the history by its line id with `TransformMessages`, Blizzard's own pattern for a changed line
      (`chatframeutil.lua:853–877`). A line with no Japanese of its own still gets the Japanese prefix. The pair is
      remembered in `UI/ChatSystem` with area `gossip`, so Alt and the switch use §7's visible-line swap.
    - **Bubbles.** After a say, yell or party line with Japanese and no `%s`, `C_ChatBubbles.GetAllChatBubbles(false)`
      (`chatbubblesdocumentation.lua:11–24`) is scanned up to 8 times, 0.1 s apart, for a bubble whose `.String`
      (`chatbubbletemplates.xml:3–24`) shows that English; it is rewritten in the bundled face. A forbidden bubble
      (instances) is never touched, nor a player's bubble [unverified: bubble timing and wrap width].
    - **Boss emotes.** `RaidWarningFrame`'s `OnEvent` adds `format(message, playerName, playerName)` as its newest line
      (`raidwarning.lua:83–119, 205–227`); a `HookScript("OnEvent")` finds that FontString by its `messageOrder` and
      sets the Japanese. Its layout is never re-run from here (it re-anchors Edit Mode frames). Player raid warnings
      and battleground system lines on that frame are left as they are.
    - **Alt and the switch:** chat lines follow §7's visible-line swap; bubbles and boss-emote lines still showing our
      text follow on `enabled`, `area` and `modifier` changes (`Speech.refresh`).
    - **Stays English:** secret text (chat messaging lockdown in dungeons, raids and encounters,
      `chatinfodocumentation.lua`), a stale or missing row, and a Japanese whose `%s` count differs from the English.

    **Data.** `vmangos.read_speech` reads every `broadcast_text` row (male and female text) and the importer adds it to
    the gossip English as one keyed set with the gossip greetings; a gossip text keeps its key's English (a speech row
    with other spacing never replaces it). Speech is drafted like gossip, under the style guide's "NPC speech"
    section. `translate_lint` has a `speaker:` rule: the Japanese keeps every `%s` and carries no other `%` (the client's `format()` would read it as
    a specifier). Pipeline: `FOREVER_WINDOWS["speech"]` (`RaidWarning.lua`, `ChatBubbleTemplates.xml`),
    `DYNAMIC["speech"]` (`CHAT_MONSTER_*_GET`, `CHAT_RAID_BOSS_*_GET`); `blizzard_chatbubble` and
    `blizzard_raidwarning` are disposed `surface speech`.
11. **The combat log stays English: a known limit.** On Forever the line is built inside Blizzard's secure
    environment (`blizzard_combatlogprocessor`, `## UseSecureEnvironment: 1`: `GenerateMessage` over
    `C_CombatLogSecure.GetCurrentEventInfo`, handed to the client with `C_CombatLogSecure.CreateCombatLogMessage`)
    and reaches `ChatFrame2:AddMessage` through `COMBAT_LOG_MESSAGE` (`blizzard_combatlog/mainline/
    blizzard_combatlog.lua:1684–1700`) as "a preformatted combat log message protected by a |K string wrapper"
    (`combatlogsecuredocumentation.lua:129–138`): addon code gets a sealed token, not the English, so there is
    nothing to key a translation by. Rebuilding lines from the events is closed too: `COMBAT_LOG_EVENT_UNFILTERED`
    carries `HasRestrictions` (`combatlogdocumentation.lua:130–133`) and the event-info call survives only in the
    deprecated shim. In game the combat log shows "Your Melee hit Young Nightsaber 14 Physical. (Critical)" in
    English, and a read of the frame's history returns no English text.

## Consequences

- Every listed error line, including the formatted ones, shows Japanese with its names and numbers exactly as the
  client wrote them; nothing is ever shown for a line the addon cannot tie to its key.
- The missing-translation marker never fires on this surface (only matched keys render); the stale marker renders
  inline as on every banner-less surface.
- A new error key on a later build is picked up by `DYNAMIC["errors"]`, and the coverage test fails until it is listed
  or excluded.
- An error key that later needs a narrower kind (a skill, a number word) is declared in `UIStrings.ARGS`; declaring
  kinds does not make its template unrestricted. Only a key added to `UIStrings.ERROR_UNRESTRICTED` is; do that only
  when it shares its English with another surface's template (`tests/python/test_ui_pipeline.py` pins the group rule).
- A repeated throttled error flashes its Japanese line in place with one error sound, as stock; the wrapper's
  English-then-Japanese swap happens inside one synchronous check and is never drawn. Holding Alt while a line
  flashes may leave it brightened until the next line (cosmetic; the in-game checklist records it if seen).
- Which wrapper id a cast failure uses is unverified; if it names no listed key, the line takes the §6 rule (an
  exact English is still translated) and otherwise stays English (safe).
- A Lua-added line is translated only when its text is exactly one dictionary English or fills one of the few
  Lua-formatted templates; any other text (another addon's sentence included) stays as written. A new Lua call site
  on a later build is picked up by `errors_call_keys` and fails the coverage test until triaged. So is a new line Blizzard's
  Lua prints into chat (`chat_call_keys`: `ChatFrameUtil.AddSystemMessage` / `DisplaySystemMessage*` and
  `DEFAULT_CHAT_FRAME:AddMessage` calls).
- A chat line added with no chat type (`DEFAULT_CHAT_FRAME:AddMessage(text, r, g, b)`: Blizzard's slash-command usage
  lines, `print()`, another addon's too) takes an exact dictionary English only, never a template. A line whose
  English carries a link stays English (the censored-message notice, loot rolls, the level-up line, the channel-link
  prefixes), except a static link: the code-of-conduct notice at login (`ONLINE_SAFETY_NOTICE`) is always the same
  GlobalString, so it is matched as the whole exact line and its support-site URL link is kept byte for byte
  (`core/markup.py` counts a link as one verbatim token).
- An error key that reaches chat as a system line is Japanese there too, with the same Japanese as the errors frame,
  and so is a system line that is exactly one dictionary English. Every plain system chat type (§8) is covered: loot,
  money, experience, honor, reputation, skill-ups, away / busy, level-up, time played and the guild message of the
  day show Japanese, with names, numbers, links and the player's own messages as written. A system line whose key is
  not a listed chat key, or whose own English carries a link, stays English. A new key of a chat family on a later
  build is picked up by `DYNAMIC["chatsystem"]` and fails the coverage test until triaged; a family that is new
  altogether needs `CHAT_FAMILIES` and `DYNAMIC["chatsystem"]` both.
- A player's line shows the Japanese prefix words ("の発言", "の叫び") around the name, and the text the player
  typed exactly as sent. A prefix with a channel link ("[Party]", "[Guild]") stays English.
- What NPCs say, yell, whisper and emote is Japanese in chat, in their speech bubbles and, for boss emotes, in the
  middle of the screen, under the "NPC talk" setting (area `gossip`), not the UI setting. It stays English when the
  text is secret (chat messaging lockdown in dungeons, raids and encounters), when a bubble is forbidden (instance
  bubbles), when the row is stale or missing, or when the Japanese's `%s` count differs. A speech row whose draft
  failed the lint (a name translated, not Japanese, a `$G` branch dropped) stays English, and so does any line the
  VMaNGOS data lacks.
- Combat log lines stay English (§11): the client hands addons a sealed string, not the English.
- Chat history lines are rewritten in place once, so a line scrolled back into view keeps its Japanese and a faded
  line stays faded through Alt; a line added while Alt is held turns Japanese on release, one added while the addon or
  its UI area is off stays English.
- A second English whose Japanese is already taken stays English in chat. The remembered pairs (system lines, prefixed
  player lines and NPC speech together; most are unique: loot, experience, every say) are capped at 4,096: when the
  cap is reached, the pairs no chat frame's history still holds are forgotten (a line still in some history keeps its
  pair, so Alt still has its English). Only when the histories themselves hold 4,096 of our lines does a new line stay
  English; the sweep is retried after 256 such lines.
- A history entry from chat messaging lockdown is secret: the rewrite never compares it, and a bubble or boss-emote
  line showing secret text is dropped from the Alt swap.
- A plain system line carries no line id, so its rewrite also turns an identical English line still in the history
  (one that arrived while the addon was off) Japanese, which gives it a new timestamp and brings it back into view.
  Player and NPC lines are rewritten by their line id only.
- No marker is shown on chat or speech lines: a stale or missing row leaves the line English, and on an untranslated
  NPC line only the prefix words ("の発言") are Japanese.
- An NPC line's prefix words follow the NPC talk setting (they are part of the speech line); a player line's follow the
  UI setting.
- A Japanese chat line shows in the bundled face, which covers Latin but not Hangul or Chinese: a player's own text in
  those scripts inside a prefixed line is unreadable while the line shows Japanese (Alt shows it in the chat font).
- A bubble is waited for only after the line reached a chat tab: with NPC says / yells shown in no tab, bubbles stay
  English. A player's bubble whose text is exactly an NPC line's English within the 0.8 s wait could be taken
  (rare). A `$G` speech line said to another player may show the local player's gendered Japanese [unverified].
- A long Japanese chat line may show a point or more smaller than the English around it (§8's fit, never below 8).
- `ERROR_CLUB_ACTION_REDEEM_TICKET` never translates: Blizzard formats it with `""` (`communitieshyperlink.lua:16`),
  and an empty entry fails the fill.
- A repeated external errors-frame line (`LE_GAME_ERR_SYSTEM`, `AddExternalErrorMessage`) may add a second line
  instead of flashing once it shows Japanese: `TryFlashingExistingMessage` compares the shown text and is deliberately
  not wrapped (§5, taint on Blizzard's action paths) [unverified; the in-game checklist].
- A chat addon that replaces a chat frame's `AddMessage` (timestamps and the like), or drops the event arguments
  from the call, can leave system lines, player prefixes and NPC speech English.

## Alternatives considered

- **Text-only matching over the whole dictionary** (ignore the id): rejected. Generic templates ("%s.", "%s slain:
  %d/%d") would take lines on other surfaces and other addons' text.
- **Hand-declaring ~340 `UIStrings.ARGS` entries** for the error keys with a `%s`: rejected. The prefix default gives
  `text` with no list to keep in step; only keys whose argument is a word or a duration, or that share English with
  another surface, are declared.
- **Wrapping `TryFlashingExistingMessage`** to compare against the recorded English: rejected. `AddExternalMessage`
  (called from Blizzard's action code) also goes through it, so the wrapper would sit on those paths and risk taint.
- **Excluding every `SPELL_FAILED_CUSTOM_ERROR_*` key**: rejected. There is no per-key evidence that Forever never
  sends them; the triage default is to list.

## Related

- [ADR-015: UI text surfaces](015-ui-text-surfaces.md) · [ADR-030: every window the Forever client loads](030-every-window-the-forever-client-loads.md)
- [ADR-033: name-list tails and untagged menus](033-level-1-gaps-name-list-tails-and-untagged-menus.md): the
  one-template-per-English rule
- [Addon modules](../architecture/addon-modules.md) ·
  [Translation batches](../operations/translation-batches.md) ·
  [Translation style guide](../content/translation-style-guide.md) (NPC speech)
