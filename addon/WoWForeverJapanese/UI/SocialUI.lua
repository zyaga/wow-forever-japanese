-- UI/SocialUI.lua: the social window the client opens for the friends key, SocialUIFrame (surface
-- "friends.social", area "ui", ADR-016). Blizzard_SocialUI and Blizzard_SocialUIShared load at login beside
-- Blizzard_FriendsFrame (blizzard_socialui.toc, blizzard_friendsframe.toc); ToggleSocialUI shows SocialUIFrame while
-- C_SocialUI.IsSystemEnabled() (blizzard_socialuishared/socialuicontrol.lua:1–19), and the older FriendsFrame
-- (UI/Friends.lua) is then not the window the player sees. The friends and friend request lists are
-- blizzard_friendsframe's mainline card views (friendslisttemplates.*, friendrequestslisttemplates.*), created as
-- SocialUIFrame's tab content (blizzard_socialui/mainline/socialui.lua:118–130, 175–252).
-- The window's own strings (SOCIAL_UI_*) are shown through the dictionary keys that carry the same English; a string
-- with no such key stays as the client wrote it.
-- Static labels (XML text= and OnLoad writes, shown at init):
--   the Battle.net notice's header (socialuitemplates.xml:204), the broadcast window's title, prompt and two
--   buttons (:237, 314, 328, 338), the ignore list's title (SetTitle, socialuitemplates.lua:614) and two buttons
--   (xml:399, 409), each list's Add New Friend button (friendslisttemplates.lua:71,
--   friendrequestslisttemplates.lua:41), the filter dropdown's fixed text (WowStyle1FilterDropdownTemplate), the
--   Real ID warning's Continue button (friendrequestslisttemplates.xml:27).
-- Dynamic writers:
--   the title: SocialUIFrameMixin:RefreshTitle → self:SetTitle(tabName) on every tab change (socialui.lua:627–630),
--     through the shared SetTitle helper, restricted to the tab names;
--   the tabs: pooled side tabs rebuilt by RefreshTabs (socialui.lua:385–396), each a help-tooltip owner: its
--     tooltip is the tab name in the highlight colour and, on a disabled tab, the reason
--     (socialuitemplates.lua:22, 70–80);
--   a list's privacy notice: SocialUIContactsFrameInitializeAADC writes FriendsDisabledText as the tab is selected
--     (socialuisharedtemplates.lua:158–170), a global called through each tab's contentFrameSetupCallback
--     (socialui.lua:189, 537–540): the copy the tab table holds was taken at load, so the window's
--     RefreshContentFrame is hooked instead;
--   friend cards: pooled ScrollBox rows set up from the initialized-frame callback. Location is "Offline",
--     "last online %s ago" or a zone, colour-wrapped (friendslistutil.lua:307–320, 435–444); Class is the class name
--     in its colour (:392–401). A zone and a class show their Japanese while names are on;
--   friend request cards: the Accept button (friendrequestslisttemplates.xml:91) and the "%s ago" time (:374–375);
--   the ignore list's rows: a header's text (socialuitemplates.lua:733, 742).
-- Help tooltips (GetAppropriateTooltip is GameTooltip in game): the status dropdown ("Status: %s", the status word
-- nested), the menu button's title, the Add New Friend button's disabled reason, a card (its last-online line and
-- the count of further characters), its party button (the invite word, the offline and restriction reasons, the
-- cross-faction sentence, "Also in group:"), its summon button.
-- A card tooltip's character block (AddWowCharacterDetailsToTooltip, friendslisttemplates.lua:884–910): the
--   character's name, then one line each for "Level %d %s" with the class, the race, the zone and the faction, in
--   that order. After each card's ShowTooltip (:1096–1101, called as self:…, post-hooked on the card) the block is
--   found by the three values the card's own account data holds (elementData.accountInfo.gameAccountInfo's
--   raceName, areaName and factionName, each UNKNOWN when missing) on three lines in a row, the level line above
--   them. The level line shows its Japanese with the class in the word prose uses for it, the race that word too,
--   the zone and the faction their names, the last three only while names are Japanese (SocialUI.cardLines, surface
--   "help.social", released on GameTooltip's OnHide).
--   The in-group line ("%s In a Group" after an icon) is the line straight under the faction, the last the block
--   writes (:871–881, 908): only that line is asked, and only for that string.
--   The tags line ("Tags: %s" in a named colour, :942–963) is the last line of the section the first separator
--   opens: the client writes the character block, the note and the tags there and starts every later part (the
--   broadcast, the last-online line, the further characters) with a separator of its own (BuildTooltip, :1106–1125;
--   the separator is a line holding one space, socialuiutil.lua:159–167). It is asked only while the card's data
--   holds tags, and only for the two tags strings: the label shows its Japanese, and so does each tag that is one
--   of the client's own tag words (socialuiutil.lua:3–20), the delimiter between them kept (LIST_DELIMITER, :962).
--   A note has no label: an icon, then the player's text (:930–939).
--   The friend's further characters (:1038–1093) come under the last separator, two lines each for a character of
--   this game: an icon, then "<name>, <level> <race> <class>" (FRIENDS_TOOLTIP_WOW_TOON_TEMPLATE, :1005–1019), then
--   the zone. The card holds no data for them, so the same two client calls the tooltip made are asked again
--   (C_BattleNet.GetFriendNumGameAccounts and GetFriendGameAccountInfo with elementData.friendIndex, :1059–1065),
--   and a pair of lines is written only when the first ends with that character's own text and the second is its
--   zone. The race and the class show the word prose uses, the zone its name, all three only while names are
--   Japanese; the character's name and the level are kept as written.
--   No other line is read: the character's name above the block, a note, a broadcast and another game's status
--   line are a player's or another game's text.
-- Menus, written once the client has shown them (UI/Menus): the status menu, the bar's menu, the request card's
-- decline menu, and the filter dropdown's untagged menu.
-- Never touched: a friend's name, BattleTag, character name and note, the player's own BattleTag, an ignored
-- player's name, and the boxes the player types in.
-- The other four tabs' views are each their panel's module: UI/RecentAllies, UI/QuickJoin, UI/RecruitAFriend and
-- UI/Raid. Their privacy notices are written by the same callback as the friends lists' and are shown here.
-- Records are never released: the rows are rewritten through hooks that stay installed, and a label on a hidden frame
-- costs nothing; modifier / area changes restore and re-apply every record (Render.refresh).
local _, WFJ = ...
local SocialUI = {}
WFJ.SocialUI = SocialUI

local SURFACE = "friends.social"
SocialUI.SURFACE = SURFACE
local Compat = WFJ.Compat

-- The player's own BattleTag, the broadcast box and the search boxes (dotted paths from the window).
SocialUI.NEVER_TOUCH = {
  "SocialUIFrame.BattleNetBar.ControlsContainer.PersonalBattleTagDisplay.DisplayText",
  "SocialUIFrame.BattleNetBroadcastFrame.EditBox",
  "SocialUIFrame.FriendsList.FilterBar.SearchBar",
  "SocialUIFrame.FriendRequestsList.FilterBar.SearchBar",
}

local CANDIDATES = { frame = { "SocialUIFrame" }, scrollUtil = { "ScrollUtil" }, tooltip = { "GameTooltip" },
  unknown = { "UNKNOWN" }, battleNet = { "C_BattleNet" }, toon = { "FRIENDS_TOOLTIP_WOW_TOON_TEMPLATE" } }
-- a card tooltip's lines, under the help surface: tooltip lines, never a window's labels
local TIP = "help.social"
-- "Level %d %s" with a class, in a friend's and a recent ally's tooltip
local LEVEL = { "FRIENDS_LEVEL_TEMPLATE", "SOCIAL_UI_RECENT_ALLIES_TOOLTIP_LEVEL_CLASS_FORMAT" }
-- a card tooltip's in-group line, and its tags line for a friend who is online or not
local IN_GROUP = { "SOCIAL_UI_FRIENDS_LIST_FRIEND_IN_GROUP_TOOLTIP" }
local TAGS = { "SOCIAL_UI_FRIENDS_LIST_BATTLE_NET_FRIEND_TAGS_FORMAT",
  "SOCIAL_UI_FRIENDS_LIST_BATTLE_NET_FRIEND_TAGS_OFFLINE_FORMAT" }
-- the words a tag can be (socialuiutil.lua:3–15), and the string the client joins them with
-- (friendslisttemplates.lua:962)
local TAG_LABELS = { "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_PROFESSIONS", "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_PVP",
  "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_RAIDING", "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_DUNGEONS",
  "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_DELVE", "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_QUESTING",
  "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_ROLEPLAYING", "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_DPS",
  "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_HEALER", "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_TANK" }
local TAG_DELIMITER = "LIST_DELIMITER"
-- the line the client opens each part of a card's tooltip with (socialuiutil.lua:159–167)
local SEPARATOR = " "
-- the tab views whose privacy notice SocialUIContactsFrameInitializeAADC or
-- RecruitAFriendFrameSocialViewInitializeAADC writes (socialui.lua:189, 203, 217, 247, 261)
local NOTICE_VIEWS = { "FriendsList", "FriendRequestsList", "RecentAlliesList", "QuickJoinFrame",
  "RecruitAFriendFrame" }

-- The tab names (socialui.lua:182–272): the window's own strings, and the older keys that carry the same English
local TAB_KEYS = { "SOCIAL_UI_FRIENDS_TAB_NAME", "SOCIAL_UI_RECENT_ALLIES_TAB_NAME", "SOCIAL_UI_QUICK_JOIN_TAB_NAME",
  "SOCIAL_UI_FRIEND_REQUESTS_TAB_NAME", "SOCIAL_UI_RECRUIT_A_FRIEND_TAB_NAME", "SOCIAL_UI_RAID_TAB_NAME",
  "FRIENDS", "CONTACTS_RECENT_ALLIES_TAB_NAME", "QUICK_JOIN", "RECRUIT_A_FRIEND", "RAID" }
local TITLE = { only = TAB_KEYS }
-- a tab's tooltip: its name in the highlight colour, and under it the reason a disabled tab gives
-- (socialuitemplates.lua:22, socialui.lua:283–289)
local TAB_TIP = { wrapped = true, only = { "DIFFICULTY_LOCKED_REASON_STORY_RAID" } }
for _, key in ipairs(TAB_KEYS) do TAB_TIP.only[#TAB_TIP.only + 1] = key end
local DISABLED = { only = { "SOCIAL_TAB_UNAVAILABLE" } }
local ADD_FRIEND = { only = { "ADD_NEW_FRIEND" } }
local ADD_FRIEND_TIP = { only = { "ADDING_FRIENDS_DISABLED" } }
local FILTER = { only = { "FILTER" } }
local STATUS_TIP = { only = { "FRIENDS_LIST_STATUS_TOOLTIP" } }
local MENU_TIP = { only = { "CONTACTS_MENU_NAME" } }
local COPY_TIP = { only = { "SOCIAL_UI_BATTLE_TAG_COPY_BUTTON_LABEL" } }
-- a card's location line, inside the card's grey (friendslistutil.lua:307–320, 403–416, 435–444)
local LOCATION = { wrapped = true, only = { "FRIENDS_LIST_OFFLINE", "BNET_LAST_ONLINE_TIME", "RAF_RECRUIT_FRIEND",
  "RAF_RECRUITER_FRIEND" } }
-- a card's tooltip (friendslisttemplates.lua:976–984, 1087–1092): line 1 is the friend's name and is never read;
-- every other line is a name, a note or a zone
local CARD_TIP = { from = 2,
  only = { "FRIENDS_LIST_OFFLINE", "BNET_LAST_ONLINE_TIME", "FRIENDS_TOOLTIP_TOO_MANY_CHARACTERS" } }
-- the party button's tooltip (friendslisttemplates.lua:1368–1505; the labels and reasons, friendslistutil.lua:
-- 218–229, 485–490)
local PARTY_TIP = { only = { "TRAVEL_PASS_INVITE", "SUGGEST_INVITE", "REQUEST_INVITE",
  "TRAVEL_PASS_INVITE_CROSS_FACTION", "SUGGEST_INVITE_CROSS_FACTION", "REQUEST_INVITE_CROSS_FACTION",
  "RECENT_ALLIES_PARTY_BUTTON_OFFLINE_TOOLTIP", "ERR_TRAVEL_PASS_NOT_LEADER", "ERR_TRAVEL_PASS_NOT_ALLIED",
  "ERR_TRAVEL_PASS_DIFFERENT_REALM", "ERR_TRAVEL_PASS_NO_INFO", "ERR_TRAVEL_PASS_NOT_WOW",
  "ERR_TRAVEL_PASS_WRONG_PROJECT", "ERR_TRAVEL_PASS_WRONG_PROJECT_MAINLINE_OVERRIDE",
  "ERR_TRAVEL_PASS_WRONG_PROJECT_CLASSIC_OVERRIDE", "ERR_TRAVEL_PASS_MOBILE", "ERR_TRAVEL_PASS_DIFFERENT_REGION",
  "ERR_TRAVEL_PASS_GAME_MODE", "CROSS_FACTION_INVITE_TOOLTIP", "SOCIAL_QUEUE_ALSO_IN_GROUP",
  "SOCIAL_QUEUE_AND_MORE" } }
local FAVORITE_TIP = { only = { "SOCIAL_UI_FRIENDS_LIST_FAVORITE_TOOLTIP" } }
-- the summon button (friendslisttemplates.lua:1278–1289): the cooldown line has ITEM_COOLDOWN_TIME's English
local SUMMON_TIP = { only = { "RAF_SUMMON_LINKED", "ITEM_COOLDOWN_TIME" } }
local LIST_HEADER = { only = { "SOCIAL_UI_FAVORITE_FRIENDS_LIST_HEADER", "SOCIAL_UI_FRIENDS_LIST_HEADER",
  "SOCIAL_UI_FRIEND_REQUESTS_RECEIVED_HEADER" } }
local ACCEPT = { only = { "ACCEPT" } }
-- a request card's time, "%s ago" in the highlight colour: RECENT_ALLY_INTERACTION_TIME_FORMAT has that English
local REQUEST_TIME = { wrapped = true, only = { "RECENT_ALLY_INTERACTION_TIME_FORMAT" } }
local REQUEST_KIND = { wrapped = true, only = { "SOCIAL_UI_FRIEND_REQUESTS_CARD_REAL_ID_LABEL",
  "SOCIAL_UI_FRIEND_REQUESTS_CARD_BATTLE_NET_LABEL", "SOCIAL_UI_FRIEND_REQUESTS_CARD_TITLE_LABEL" } }
local IGNORE_HEADER = { only = { "IGNORED", "SOCIAL_UI_IGNORE_LIST_BATTLE_NET_BLOCK_HEADER" } }
local IGNORE_TITLE = { only = { "IGNORE_LIST" } }

-- The menus the window opens. A status entry is its icon and its word with no space between them
-- (socialuitemplates.lua:205–217); the filter menu is untagged (socialuisharedtemplates.lua:117–119,
-- friendslisttemplates.lua:1–8, 79–95; the tag words, socialuiutil.lua:3–15).
local MENUS = {
  MENU_SOCIAL_UI_BATTLE_NET_PRESENCE = { source = "socialuitemplates.lua:203", keys = { "GUILD_ONLINE_LABEL",
    "FRIENDS_LIST_AWAY", "FRIENDS_LIST_BUSY", "SOCIAL_UI_PRESENCE_TYPE_LABEL_APPEAR_OFFLINE" } },
  MENU_SOCIAL_UI_BATTLE_NET_BAR = { source = "socialuitemplates.lua:238", keys = { "IGNORE_LIST" } },
  MENU_FRIEND_REQUESTS_DECLINE = { source = "friendrequestslisttemplates.lua:519",
    keys = { "REPORT_PLAYER", "BLOCK_INVITES" } },
}
local FILTER_TAG = "SOCIAL_UI_FRIENDS_FILTER"
local FILTER_MENU = { source = "friendslisttemplates.lua:79", keys = { "STATUS", "SOCIAL_FILTER_DROPDOWN_TAGS",
  "GUILD_ONLINE_LABEL", "FRIENDS_LIST_AWAY", "FRIENDS_LIST_BUSY", "FRIENDS_LIST_OFFLINE",
  "SOCIAL_UI_FRIENDS_LIST_IN_QUEUE_FILTER_LABEL", "SOCIAL_UI_FRIENDS_LIST_AVAILABLE_FOR_QUEUE_FILTER_LABEL",
  "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_INTERESTS", "COMMUNITY_MEMBER_LIST_DROP_DOWN_ROLES",
  "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_PROFESSIONS", "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_PVP",
  "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_RAIDING", "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_DUNGEONS",
  "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_DELVE", "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_QUESTING",
  "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_ROLEPLAYING", "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_DPS",
  "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_HEALER", "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_TANK" } }

local function get(key) return Compat.get(SURFACE, key) end

-- A nested field of a Blizzard frame (read only). → value | nil
local function field(t, ...)
  for _, k in ipairs({ ... }) do
    if type(t) ~= "table" then return nil end
    t = t[k]
  end
  return t
end

-- A stable record key per pooled widget: records follow the widget, not the row's place in the list.
local keyer = WFJ.Labels.keyer
local locationKey, classKey, headerKey = keyer("ui.location."), keyer("ui.class."), keyer("ui.header.")
local acceptKey, timeKey, kindKey = keyer("ui.accept."), keyer("ui.requestTime."), keyer("ui.requestKind.")
local ignoreHeaderKey = keyer("ui.ignoreHeader.")

local function register(owner, opts)
  if type(owner) == "table" then WFJ.HelpTooltip.register(owner, opts) end
end

-- The labels the client writes once at load. → the number of dictionary words found.
function SocialUI.showStatic()
  local frame = get("frame")
  local notice, broadcast = field(frame, "BattleNetUnavailableNoticeFrame"), field(frame, "BattleNetBroadcastFrame")
  local ignore, friends, requests = field(frame, "IgnoreListFrame"), field(frame, "FriendsList"),
    field(frame, "FriendRequestsList")
  local items = {
    { "ui.noticeHeader", field(notice, "Header", "HeaderText"), { only = { "BATTLENET_UNAVAILABLE" } } },
    { "ui.noticeText", field(notice, "Text"), { only = { "SOCIAL_UI_BATTLENET_UNAVAILABLE_ALERT" } } },
    { "ui.broadcastTitle", field(broadcast, "Title"), { only = { "BATTLENET_BROADCAST" } } },
    { "ui.broadcastPrompt", field(broadcast, "EditBox", "PromptText"), { only = { "FRIENDS_LIST_ENTER_TEXT" } } },
    { "ui.broadcastUpdate", field(broadcast, "UpdateButton"), { only = { "UPDATE" } } },
    { "ui.broadcastCancel", field(broadcast, "CancelButton"), { only = { "CANCEL" } } },
    { "ui.ignoreBlock", field(ignore, "BlockButton"), { only = { "IGNORE_PLAYER" } } },
    { "ui.ignoreUnblock", field(ignore, "UnblockButton"), { only = { "UNIGNORE_PLAYER_BUTTON_LABEL" } } },
    { "ui.friendsAdd", field(friends, "ActionButton"), ADD_FRIEND },
    { "ui.friendsSearch", field(friends, "FilterBar", "SearchBar", "Instructions"),
      { only = { "SOCIAL_UI_SEARCH_BOX_INSTRUCTIONS" } } },
    { "ui.requestsAdd", field(requests, "ActionButton"), ADD_FRIEND },
    { "ui.requestsContinue", field(requests, "RealIDWarning", "ContinueButton"), { only = { "CONTINUE" } } },
  }
  local n = WFJ.Labels.title(SURFACE, ignore, IGNORE_TITLE, "ui.ignoreTitle")
  -- the filter button's own text, which the menu writes again on every choice
  n = n + WFJ.Labels.dropdown(SURFACE, "ui.friendsFilter", field(friends, "FilterBar", "SearchFilterDropdown"), FILTER)
  return n + WFJ.Labels.showAll(SURFACE, items)
end

-- hooksecurefunc target (SocialUIFrame:RefreshTabs): the pooled tabs the window shows now. → tabs registered
function SocialUI.onTabs()
  local pool = field(get("frame"), "socialTabPool")
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  for tab in pool:EnumerateActive() do
    register(tab, TAB_TIP)
    n = n + 1
  end
  return n
end

-- hooksecurefunc target (SocialUIFrame:RefreshContentFrame): the selected list's privacy notice, written just
-- before by the tab's setup callback. → 1 | 0
function SocialUI.onContent()
  local n = 0
  for _, key in ipairs(NOTICE_VIEWS) do
    n = n + WFJ.Labels.show(SURFACE, "ui.disabled." .. key, field(get("frame"), key, "FriendsDisabledText"), nil,
      DISABLED)
  end
  return n
end

-- A name behind its colour code (a zone, a class), in Japanese while names are on. → 1 | 0
local function showName(recKey, fs)
  return WFJ.NameLabels.wrapped(SURFACE, recKey, fs)
end

local function drop(recKey)
  WFJ.SurfaceState.drop(TIP, recKey)
  return 0
end

-- A value the addon may read and compare: a string the client does not hide.
local function plain(v)
  return not WFJ.SurfaceState.secret(v) and type(v) == "string" and v ~= ""
end

-- Left line `i` of a tooltip and its text, when the text is readable. → FontString, text | nil
local function lineAt(tt, i)
  local name = type(tt.GetName) == "function" and tt:GetName() or nil
  local fs = type(name) == "string" and Compat.resolve(name .. "TextLeft" .. i) or nil
  local text = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
  if plain(text) then return fs, text end
  return nil
end

-- The word prose uses for a class or a race, while names are Japanese. → string | nil
local function word(text)
  local resolve = WFJ.UIStrings.word
  return type(resolve) == "function" and resolve(text) or nil
end

-- A line that is no dictionary line and whose words are not the name list's (a race, a further character's race and
-- class): `ja` stands as the whole line, recorded under the level line's key. → 1 | 0
local function showWords(recKey, fs, ja)
  local index = WFJ.UIIndex
  for _, key in ipairs(LEVEL) do
    if ja and index and index.rows[key] then
      return WFJ.Labels.showArgs(TIP, recKey, fs, key, { form = "seq", parts = { ja } }, WFJ.HelpTooltip.refit)
    end
  end
  return drop(recKey)
end

-- A line that is one of the client's strings `keys` around one value (an icon, a list of tags). The dictionary
-- takes a bare "%s" for a number only, so the line is split here, on the string as the client holds it now: the
-- value is whatever stands between the string's two ends, and `shown` gives the text to put in its place (the
-- value itself to keep it as written) or nil when the value is not what this line holds. → 1 | 0
local function showFilled(recKey, fs, text, keys, shown)
  local index = WFJ.UIIndex
  for _, key in ipairs(keys) do
    local template = Compat.resolve(key)
    local head, tail = nil, nil
    if plain(template) and index and index.rows[key] then head, tail = template:match("^([^%%]*)%%s([^%%]*)$") end
    if head and #text > #head + #tail and text:sub(1, #head) == head and text:sub(#text - #tail + 1) == tail then
      local value = shown(text:sub(#head + 1, #text - #tail))
      if value then return WFJ.Labels.showArgs(TIP, recKey, fs, key, { value }, WFJ.HelpTooltip.refit) end
    end
  end
  return drop(recKey)
end

-- The icon the client puts in front of the in-group words (CreateAtlasMarkup, friendslisttemplates.lua:879).
local function atlas(value)
  return value:match("^|A[^|]*|a$")
end

-- A tags line's list with each tag in Japanese. A tag is compared whole with the client's own tag words as the
-- client holds them now, so anything else between two delimiters is kept as written; the delimiter is the client's.
local function tagWords(value)
  local index, delimiter = WFJ.UIIndex, Compat.resolve(TAG_DELIMITER)
  if not index or not plain(delimiter) then return value end
  local ja = {}
  for _, key in ipairs(TAG_LABELS) do
    local en, row = Compat.resolve(key), index.rows[key]
    if plain(en) and row then ja[en] = row[1] end
  end
  local out, from = {}, 1
  while true do
    local at, to = value:find(delimiter, from, true)
    local tag = value:sub(from, at and at - 1 or #value)
    out[#out + 1] = ja[tag] or tag
    if not at then break end
    from = to + 1
  end
  return table.concat(out, delimiter)
end

-- One line of a character block. → 1 | 0
local function showCardLine(tt, i, kind)
  local fs, text = lineAt(tt, i)
  local recKey, refit = "L" .. i, WFJ.HelpTooltip.refit
  if not fs then return drop(recKey) end
  if kind == "name" then return WFJ.NameLabels.show(TIP, recKey, fs, nil, refit) end
  if kind == "level" then
    local part = WFJ.Labels.part(text, LEVEL)
    if not part then return drop(recKey) end
    local args = part.args
    local class = type(args) == "table" and args[2] or nil
    local ja = type(class) == "string" and word(class) or nil
    if ja then -- a copy: the index keeps the arguments it matched
      args = {}
      for k, v in pairs(part.args) do args[k] = v end
      args[2] = ja
    end
    return WFJ.Labels.showArgs(TIP, recKey, fs, part.key, args, refit)
  end
  return showWords(recKey, fs, word(text))
end

-- The character lines of a card's tooltip, each by its place: `lines` is a list of { line number, kind [, the value
-- the card's data holds for it] }, kind "level" (the "Level %d %s" line), "word" (a race) or "name" (a zone, a
-- faction). Nothing is written unless every line with a value still holds it and every level line is one: a line
-- that holds anything else is a player's text. → the number of lines shown
function SocialUI.cardLines(tt, lines)
  if type(tt) ~= "table" or type(lines) ~= "table" then return 0 end
  for _, line in ipairs(lines) do
    local _, text = lineAt(tt, line[1])
    if not text or (line[3] ~= nil and text ~= line[3]) then return 0 end
    if line[2] == "level" and not WFJ.Labels.part(text, LEVEL) then return 0 end
  end
  local n = 0
  for _, line in ipairs(lines) do n = n + showCardLine(tt, line[1], line[2]) end
  if n > 0 then WFJ.HelpTooltip.refit() end -- one layout for the new widths
  return n
end

-- The client built a card's tooltip again: the lines the last pass wrote are gone. → the tooltip while `owner`
-- owns it | nil
function SocialUI.cardTooltip(owner)
  local tt = get("tooltip")
  if type(tt) ~= "table" or type(tt.GetOwner) ~= "function" or type(tt.NumLines) ~= "function"
      or tt:GetOwner() ~= owner then return nil end
  WFJ.Render.forget(TIP)
  return tt
end

-- The character block of a card's tooltip, and the in-group line under it. → the number of lines shown, the last
-- line the block holds (1 when the tooltip has no block: line 1 is the friend's name)
local function characterBlock(tt, info)
  local unknown = get("unknown")
  local race, zone, faction = info.raceName or unknown, info.areaName or unknown, info.factionName or unknown
  if not (plain(race) and plain(zone) and plain(faction)) then return 0, 1 end
  -- line 1 is the friend's name, 2 the separator, 3 the character's name: the level line is 4 or later
  for i = 5, (tt:NumLines() or 0) - 2 do
    local n = SocialUI.cardLines(tt, { { i - 1, "level" }, { i, "word", race }, { i + 1, "name", zone },
      { i + 2, "name", faction } })
    if n > 0 then
      local fs, text = lineAt(tt, i + 3)
      local group = fs and showFilled("L" .. (i + 3), fs, text, IN_GROUP, atlas) or 0
      return n + group, i + 2 + group
    end
  end
  return 0, 1
end

-- The tags line: the last line of the section the first separator opens, below the character block. → 1 | 0
local function tagsLine(tt, account, blockEnd)
  local tags = account.friendTags
  local _, first = lineAt(tt, 2)
  if type(tags) ~= "table" or #tags == 0 or first ~= SEPARATOR then return 0 end
  local last
  for i = 3, tt:NumLines() or 0 do
    local _, text = lineAt(tt, i)
    if not text or text == SEPARATOR then break end
    last = i
  end
  if not last or last <= blockEnd then return 0 end
  local fs, text = lineAt(tt, last)
  return showFilled("L" .. last, fs, text, TAGS, tagWords)
end

-- "<name>, <level> <race> <class>" as the client's template orders it, or nil when the template is not the four
-- numbered values. The game's own format reads "%1$s"; plain Lua's does not, so the values are put in by number.
local function toonText(template, name, level, race, class)
  local values = { name, tostring(level), race, class }
  local text, n = template:gsub("%%(%d)%$[sd]", function(i) return values[tonumber(i)] or "%" end)
  if n ~= 4 or text:find("%", 1, true) then return nil end
  return text
end

-- One further character's pair of lines at `i`: its name line and its zone. → the number of lines shown | nil when
-- the pair is not this character's
local function showToon(tt, i, template, info)
  local unknown = get("unknown")
  local name, race, class = info.characterName, info.raceName or unknown, info.className or unknown
  local level, zone = info.characterLevel or 0, info.areaName or unknown
  if not (plain(name) and plain(race) and plain(class) and plain(zone)) or type(level) ~= "number"
      or WFJ.SurfaceState.secret(level) then return nil end
  local en = toonText(template, name, level, race, class)
  local fs, text = lineAt(tt, i)
  local zoneFs, zoneText = lineAt(tt, i + 1)
  if not en or not fs or not zoneFs or zoneText ~= zone or text:sub(-#en) ~= en then return nil end
  -- in front of the character's text the client puts nothing or the game's icon and a space (:993–1005, 1015)
  local icon = text:sub(1, #text - #en)
  if icon ~= "" and not icon:match("^|T[^|]*|t $") then return nil end
  local jaRace, jaClass = word(race), word(class)
  local ja = (jaRace or jaClass) and toonText(template, name, level, jaRace or race, jaClass or class) or nil
  return showWords("L" .. i, fs, ja and (icon .. ja) or nil)
    + WFJ.NameLabels.show(TIP, "L" .. (i + 1), zoneFs, nil, WFJ.HelpTooltip.refit)
end

-- The friend's further characters, under the tooltip's last separator below line `from`. Each character the client
-- lists is looked for in the order the client wrote them; one it left out, or one of another game, has no pair of
-- lines and is passed over. → the number of lines shown
local function furtherCharacters(tt, row, from)
  local api, friend, template = get("battleNet"), field(row, "elementData", "friendIndex"), get("toon")
  local total = tt:NumLines() or 0
  if type(api) ~= "table" or type(api.GetFriendNumGameAccounts) ~= "function"
      or type(api.GetFriendGameAccountInfo) ~= "function" or type(friend) ~= "number" or not plain(template) then
    return 0
  end
  local at
  for i = total - 2, from + 1, -1 do
    local _, text = lineAt(tt, i)
    if text == SEPARATOR then
      at = i + 1
      break
    end
  end
  local count = at and api.GetFriendNumGameAccounts(friend) or nil
  if type(count) ~= "number" or WFJ.SurfaceState.secret(count) then return 0 end
  local n = 0
  for account = 1, count do
    local info = api.GetFriendGameAccountInfo(friend, account)
    for i = at, type(info) == "table" and total - 1 or 0 do
      local shown = showToon(tt, i, template, info)
      if shown then
        n, at = n + shown, i + 2
        break
      end
    end
  end
  return n
end

-- hooksecurefunc target (a friend card's ShowTooltip): the character block with its in-group line, the tags line and
-- the friend's further characters. → the number of lines shown
function SocialUI.onCardTooltip(row)
  local tt = type(row) == "table" and SocialUI.cardTooltip(row) or nil
  local account = field(row, "elementData", "accountInfo")
  local info = field(account, "gameAccountInfo")
  if not tt or type(info) ~= "table" then return 0 end
  local n, blockEnd = characterBlock(tt, info)
  local tags = tagsLine(tt, account, blockEnd)
  local more = furtherCharacters(tt, row, math.max(blockEnd, 2)) -- line 2 opens the first part, never theirs
  if tags + more > 0 then WFJ.HelpTooltip.refit() end -- one layout for the new widths
  return n + tags + more
end

local tipHooked = setmetatable({}, { __mode = "k" }) -- cards whose ShowTooltip is hooked

-- One pooled row of the friends list after its initializer ran: (owner, frame, elementData) for a new row,
-- (frame, elementData) for the iterateExisting pass. A header is a button with its text; a spacer has neither.
-- Returns nothing (ForEachFrame stops on a truthy return).
function SocialUI.onFriendRow(a, b)
  local row = a
  if a == SocialUI then row = b end
  if type(row) ~= "table" then return end
  if type(row.Location) ~= "table" then
    if type(row.ButtonText) == "table" then WFJ.Labels.show(SURFACE, headerKey(row), row, nil, LIST_HEADER) end
    return
  end
  WFJ.Labels.forbid(row.FriendName) -- the friend's own name
  WFJ.Labels.forbid(row.Name) -- the character's
  -- Offline or the last-online line; else an online friend's zone, a game name
  if WFJ.Labels.show(SURFACE, locationKey(row.Location), row.Location, nil, LOCATION) == 0 then
    showName(locationKey(row.Location), row.Location)
  end
  if type(row.Class) == "table" then showName(classKey(row.Class), row.Class) end
  register(row, CARD_TIP)
  if not tipHooked[row] and type(row.ShowTooltip) == "function" then
    tipHooked[row] = true
    hooksecurefunc(row, "ShowTooltip", SocialUI.onCardTooltip)
  end
  register(row.PartyButton, PARTY_TIP)
  register(field(row, "StateDisplay", "FavoriteDisplay"), FAVORITE_TIP)
  register(row.RAFSummonButton, SUMMON_TIP)
  WFJ.Render.updateBanner(SURFACE)
end

-- One pooled row of the friend requests list: a header, or a card with its Accept button, the time the request was
-- sent and the kind of friend it asks for. The requester's name is never touched.
function SocialUI.onRequestRow(a, b)
  local row = a
  if a == SocialUI then row = b end
  if type(row) ~= "table" then return end
  if type(row.AcceptButton) ~= "table" then
    if type(row.ButtonText) == "table" then WFJ.Labels.show(SURFACE, headerKey(row), row, nil, LIST_HEADER) end
    return
  end
  WFJ.Labels.forbid(row.Name)
  local accept = field(row, "AcceptButton", "Text")
  if type(accept) == "table" then WFJ.Labels.show(SURFACE, acceptKey(accept), accept, nil, ACCEPT) end
  if type(row.RequestTimestamp) == "table" then
    WFJ.Labels.show(SURFACE, timeKey(row.RequestTimestamp), row.RequestTimestamp, nil, REQUEST_TIME)
  end
  if type(row.FriendType) == "table" then
    WFJ.Labels.show(SURFACE, kindKey(row.FriendType), row.FriendType, nil, REQUEST_KIND)
  end
  WFJ.Render.updateBanner(SURFACE)
end

-- One pooled row of the ignore list: a header's text; an entry's name is never touched.
function SocialUI.onIgnoreRow(a, b)
  local row = a
  if a == SocialUI then row = b end
  if type(row) ~= "table" then return end
  if type(row.Name) == "table" then
    WFJ.Labels.forbid(row.Name)
  elseif type(row.Text) == "table" then
    WFJ.Labels.show(SURFACE, ignoreHeaderKey(row.Text), row.Text, nil, IGNORE_HEADER)
  end
end

-- The filter dropdown's menu, through the untagged-menu mechanism, and the window's tagged menus. → true when the
-- filter dropdown was recorded now
local function hookMenus()
  local menus, untagged = WFJ.Menus, WFJ.MenusUntagged
  if type(menus) ~= "table" or type(menus.TAGS) ~= "table" then return false end
  for tag, spec in pairs(MENUS) do menus.TAGS[tag] = menus.TAGS[tag] or spec end
  if type(untagged) ~= "table" or type(untagged.hookDropdown) ~= "function" then return false end
  menus.TAGS[FILTER_TAG] = menus.TAGS[FILTER_TAG] or FILTER_MENU
  return untagged.hookDropdown(field(get("frame"), "FriendsList", "FilterBar", "SearchFilterDropdown"), FILTER_TAG)
end

local function registerHelp()
  local frame = get("frame")
  local bar = field(frame, "BattleNetBar", "ControlsContainer")
  register(field(bar, "OnlineStatusDropdown"), STATUS_TIP)
  register(field(bar, "BattleNetMenuButton"), MENU_TIP)
  register(field(bar, "PersonalBattleTagDisplay", "CopyBattleTagToClipboardButton"), COPY_TIP)
  register(field(frame, "FriendsList", "ActionButton"), ADD_FRIEND_TIP)
  register(field(frame, "FriendRequestsList", "ActionButton"), ADD_FRIEND_TIP)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init. → false on a client without the window.
function SocialUI.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  SocialUI.showStatic()
  registerHelp()
  hookMenus()
  WFJ.Labels.title(SURFACE, frame, TITLE, "ui.title")
  if type(frame.RefreshTabs) == "function" then hooksecurefunc(frame, "RefreshTabs", SocialUI.onTabs) end
  if type(frame.RefreshContentFrame) == "function" then
    hooksecurefunc(frame, "RefreshContentFrame", SocialUI.onContent)
  end
  SocialUI.onTabs()
  SocialUI.onContent()
  local tt = get("tooltip")
  if type(tt) == "table" and type(tt.HookScript) == "function" then
    tt:HookScript("OnHide", function() WFJ.Render.release(TIP) end)
  end
  local util = get("scrollUtil")
  if type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    local lists = { { "FriendsList", SocialUI.onFriendRow }, { "FriendRequestsList", SocialUI.onRequestRow },
      { "IgnoreListFrame", SocialUI.onIgnoreRow } }
    for _, list in ipairs(lists) do
      local box = field(frame, list[1], "ScrollBox")
      if type(box) == "table" then util.AddInitializedFrameCallback(box, list[2], SocialUI, true) end
    end
  end
  return true
end
