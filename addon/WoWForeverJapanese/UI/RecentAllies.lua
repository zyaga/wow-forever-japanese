-- UI/RecentAllies.lua: the social window's Recent Allies panel on Forever (surface "recentallies", area "ui",
-- ADR-016). Blizzard_RecentAllies loads at login; RecentAlliesFrame.List (RecentAlliesListTemplate) is a
-- child of FriendsFrame (blizzard_friendsframe/camelot/friendsframe.xml:775–777), shown by the contacts header's
-- Recent Allies tab when C_RecentAllies.IsSystemEnabled() (camelot/friendsframe.lua:456, 622; the tab and the title
-- are UI/Friends.lua's).
-- The panel has no fixed labels: a row is a name, a level, a class, a location and the last activity's description.
-- That description is RecentAllyInteraction.description (recentalliesdocumentation.lua:286–293), the client-table
-- text of the activity's RolodexType row (ADR-042). Which RolodexType column the client sends is not documented, so
-- both families match: RecentAllyType (Description_lang, "Party Member") and RecentAllyInteraction (the other text
-- column, "Fought Together"). Each row and its buttons are set up from the ScrollBox's initialized-frame callback
-- (keyed by widget), each restricted to its keys:
--   CharacterData.MostRecentInteraction, written by Initialize → SetMostRecentInteraction (:130–135, 265–268) before
--     the callback runs: the two families only; any other text stays as written;
--   the row (RecentAlliesEntryMixin:BuildRecentAllyTooltip, blizzard_recentalliestemplates.lua:153–225): the
--     "Recent Activities" / "<time> ago" double line (:203–206), and the activity line under it
--     (ConvertInteractionToTooltipString, :207, 270–288): the bare description for an activity with no context, the
--     two families only (an activity with a place or an item joins them with
--     RECENT_ALLY_TOOLTIP_INTERACTION_WITH_CONTEXT_FORMAT, blizzard_recentalliesutil.lua:61–128, and stays English).
--     The name line is the character's full name with its realm [likely], so it never equals an activity word. Its
--     race, class, faction, location and note lines are names or server text and are never matched; the level / race
--     line RECENT_ALLY_TOOLTIP_LEVEL_RACE_FORMAT "Level %d  %s  %s" (:163–167), its atlas divider and the race name
--     kept as written (`text`);
--   PartyButton: "Invite to Group", and "Player Offline" when disabled (:367–380);
--   StateIconContainer.PinDisplay: "Pinned Ally" / "Pinned Ally (Expires in <time>)" (:406–418).
-- The time arguments are SecondsFormatter output (blizzard_recentalliesutil.lua:50–59), kept as written unless the
-- dictionary's duration entries cover them.
-- Never touched: CharacterData.Name / Level / Class / Location.
-- Set up only where FriendsFrame carries SetTitle (the mainline social window, UI/Labels.title).
--
-- The card view of the same file (RecentAlliesSocialView*, blizzard_recentalliestemplates.lua:425–907) is the Recent
-- Allies tab of the newer social window: SocialUIFrame.RecentAlliesList (blizzard_socialui/mainline/socialui.lua:
-- 191–204), a SocialUIContactsFrameTemplate (blizzard_socialuishared/socialuisharedtemplates.xml:99–176). Set up
-- whenever that frame exists, with or without the older panel:
--   static: ActionButton's "Add New Friend" (InitializeActionButton, :467–470) and its disabled reason
--     (SocialUIAddFriendButtonMixin:ShowDisabledTooltip, socialuisharedtemplates.lua:62–67); the search box's
--     Instructions (instructionText, socialuisharedtemplates.xml:5); the filter dropdown's own text
--     (WowStyle1FilterDropdownTemplate) and its untagged menu, once shown (UI/Menus): Status with the four presence
--     words, Categories with the activity kinds (GenerateSearchFilterMenu, :495–505; the labels :425–431 and
--     blizzard_recentalliesutil.lua:3–11);
--   rows, from the ScrollBox's initialized-frame callback (pooled, keyed by widget): a header's "Pinned %d/%d",
--     "Legacy Friends %d/%d" or "Recent Allies %d/%d" (TryInsertRecentAlliesSubTree, :662–680, 709–723); a card's
--     Level "Lvl %d", MostRecentInteraction (the two RolodexType families) and, while names are Japanese, its Class
--     and Location, each inside the colour the client wraps it in (:785–846). The card's Name is never touched;
--   a card's tooltip (BuildTooltip, :1066–1167; ShowTooltip is called as self:… and post-hooked on the card): line
--     1 is the character's name and is never read, line 2 the separator; lines 3 to 5 are always "Level %d %s" with
--     the class, the race and the faction (AddCharacterDataToTooltip, :1103–1109), line 6 the location when the
--     card's own stateData.currentLocation is that text (:1111–1122). They are written by place (UI/SocialUI
--     .cardLines). "Recent Activities" / "<time> ago" and a bare activity line are the card's help-tooltip keys;
--   PartyButton, StateDisplay.PinDisplay and StateDisplay.FriendRequestSentDisplay own one-line tooltips
--     (:1249–1263, 1281–1298, 1314–1323).
-- The tab's privacy notice (FriendsDisabledText) is UI/SocialUI's; the card's right-click menu is UI/MenusUnit's.
local _, WFJ = ...
local RecentAllies = {}
WFJ.RecentAllies = RecentAllies

local SURFACE = "recentallies"
RecentAllies.SURFACE = SURFACE
local Compat = WFJ.Compat

local VIEW = "SocialUIFrame.RecentAlliesList"

RecentAllies.NEVER_TOUCH = { VIEW .. ".FilterBar.SearchBar" }

local CANDIDATES = {
  friends = { "FriendsFrame" }, list = { "RecentAlliesFrame.List" }, rows = { "RecentAlliesFrame.List.ScrollBox" },
  scrollUtil = { "ScrollUtil" },
  view = { VIEW }, viewRows = { VIEW .. ".ScrollBox" }, viewAdd = { VIEW .. ".ActionButton" },
  viewSearch = { VIEW .. ".FilterBar.SearchBar.Instructions" },
  viewFilter = { VIEW .. ".FilterBar.SearchFilterDropdown" },
}

local ROW_KEYS = { "RECENT_ALLY_RECENT_ACTIVITIES_LABEL", "RECENT_ALLY_INTERACTION_TIME_FORMAT",
  "RECENT_ALLY_TOOLTIP_LEVEL_RACE_FORMAT" }
local PARTY_TIP = { only = { "RECENT_ALLIES_PARTY_BUTTON_TOOLTIP", "RECENT_ALLIES_PARTY_BUTTON_OFFLINE_TOOLTIP" } }
local PIN_TIP = { only = { "RECENT_ALLY_PIN_TOOLTIP", "RECENT_ALLY_PIN_EXPIRING_TOOLTIP" } }

-- The card view. Each list names the string the client writes and the older key with the same English.
local ADD = { only = { "SOCIAL_UI_RECENT_ALLIES_ADD_FRIEND_BUTTON_LABEL", "ADD_NEW_FRIEND" } }
local ADD_TIP = { only = { "ADDING_FRIENDS_DISABLED" } }
local SEARCH = { only = { "SOCIAL_UI_SEARCH_BOX_INSTRUCTIONS" } }
local FILTER = { only = { "FILTER" } }
local HEADER = { only = { "SOCIAL_UI_RECENT_ALLIES_VIEW_HEADER_LEGACY_FRIENDS",
  "SOCIAL_UI_RECENT_ALLIES_VIEW_HEADER_PINNED", "SOCIAL_UI_RECENT_ALLIES_VIEW_HEADER_UNPINNED" } }
local CARD_LEVEL = { wrapped = true, only = { "SOCIAL_UI_RECENT_ALLIES_CARD_LEVEL_DISPLAY_FORMAT" } }
local CARD_TIP_KEYS = { "RECENT_ALLY_RECENT_ACTIVITIES_LABEL", "RECENT_ALLY_INTERACTION_TIME_FORMAT" }
local REQUEST_SENT_TIP = { only = { "SOCIAL_UI_RECENT_ALLIES_FRIEND_REQUEST_SENT_TOOLTIP" } }
-- the filter dropdown's untagged menu (blizzard_recentalliestemplates.lua:425–431, 495–505; the activity kinds,
-- blizzard_recentalliesutil.lua:3–11)
local FILTER_TAG = "SOCIAL_UI_RECENT_ALLIES_FILTER"
local FILTER_MENU = { source = "blizzard_recentalliestemplates.lua:495", keys = { "SOCIAL_FILTER_DROPDOWN_STATUS",
  "STATUS", "SOCIAL_UI_PRESENCE_TYPE_LABEL_ONLINE", "GUILD_ONLINE_LABEL", "SOCIAL_UI_PRESENCE_TYPE_LABEL_AWAY",
  "FRIENDS_LIST_AWAY", "SOCIAL_UI_PRESENCE_TYPE_LABEL_BUSY", "FRIENDS_LIST_BUSY",
  "SOCIAL_UI_PRESENCE_TYPE_LABEL_OFFLINE", "FRIENDS_LIST_OFFLINE", "RECENT_ALLIES_CATEGORIES_FILTER_LABEL",
  "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_PROFESSIONS", "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_PVP",
  "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_RAIDING", "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_DUNGEONS",
  "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_DELVE", "SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_QUESTING" } }

local function get(key) return Compat.get(SURFACE, key) end

local activityKey = WFJ.Labels.keyer("activity.") -- a pooled row's activity text: follows the widget

-- A row's last activity, after the row's initializer wrote it. → 1 | 0
function RecentAllies.showActivity(fs)
  local opts = WFJ.Labels.families("RecentAllyType", "RecentAllyInteraction")
  local n = WFJ.Labels.show(SURFACE, activityKey(fs), fs, nil, opts)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- One pooled row after its initializer ran: (owner, frame, elementData) for a new row, (frame, elementData) for the
-- iterateExisting pass. A divider row has none of the children. Returns nothing (ForEachFrame stops on a truthy one).
function RecentAllies.onRow(a, b)
  local row = a
  if a == RecentAllies then row = b end
  if type(row) ~= "table" then return end
  local register = WFJ.HelpTooltip.register
  if type(row.CharacterData) == "table" then
    register(row, WFJ.Labels.familiesWith(ROW_KEYS, "RecentAllyType", "RecentAllyInteraction"))
    local data = row.CharacterData
    for _, key in ipairs({ "Name", "Level", "Class", "Location" }) do
      WFJ.Labels.forbid(data[key]) -- names and server text, whatever a later pass is asked to show
    end
    if type(data.MostRecentInteraction) == "table" then RecentAllies.showActivity(data.MostRecentInteraction) end
  end
  if type(row.PartyButton) == "table" then register(row.PartyButton, PARTY_TIP) end
  local pin = type(row.StateIconContainer) == "table" and row.StateIconContainer.PinDisplay or nil
  if type(pin) == "table" then register(pin, PIN_TIP) end
end

-- The card view's fixed labels. → the number of dictionary words found
function RecentAllies.showView()
  local n = WFJ.Labels.showAll(SURFACE, { { "view.add", get("viewAdd"), ADD },
    { "view.search", get("viewSearch"), SEARCH } })
  return n + WFJ.Labels.dropdown(SURFACE, "view.filter", get("viewFilter"), FILTER)
end

local headerKey, cardKey = WFJ.Labels.keyer("view.header."), WFJ.Labels.keyer("view.card.")
local tipHooked = setmetatable({}, { __mode = "k" }) -- cards whose ShowTooltip is hooked

-- hooksecurefunc target (a card's ShowTooltip): the character lines under the name and the separator, by place.
-- → the number of lines shown
function RecentAllies.onCardTooltip(card)
  local social = WFJ.SocialUI
  local tt = type(card) == "table" and social and social.cardTooltip(card) or nil
  if not tt then return 0 end
  local n = social.cardLines(tt, { { 3, "level" }, { 4, "word" }, { 5, "name" } })
  local state = type(card.elementData) == "table" and card.elementData.stateData or nil
  local location = type(state) == "table" and state.currentLocation or nil
  if n > 0 and location ~= nil then n = n + social.cardLines(tt, { { 6, "name", location } }) end
  return n
end

-- A card's last activity, inside the colour the client wraps it in (BuildMostRecentInteractionDisplayText,
-- blizzard_recentalliestemplates.lua:821–830). A family row is found by its text whatever colour is around it, so
-- the colour is taken off here and put back around the Japanese. → 1 | 0
function RecentAllies.showCardActivity(fs)
  local only = WFJ.Labels.families("RecentAllyType", "RecentAllyInteraction").only
  local text = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
  local open, inner, close
  if type(text) == "string" then open, inner, close = text:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$") end
  local part = open and WFJ.Labels.part(inner, only) or nil
  if part then
    return WFJ.Labels.showArgs(SURFACE, cardKey(fs), fs, part.key,
      { form = "wrapped", open = open, close = close, inner = part.args })
  end
  return WFJ.Labels.show(SURFACE, cardKey(fs), fs, nil, { only = only })
end

-- One pooled row of the card view after its initializer ran: (owner, frame, elementData) for a new row, (frame,
-- elementData) for the iterateExisting pass. A header is a button with its text; a spacer has neither. Returns
-- nothing (ForEachFrame stops on a truthy return).
function RecentAllies.onViewRow(a, b)
  local row = a
  if a == RecentAllies then row = b end
  if type(row) ~= "table" then return end
  if type(row.MostRecentInteraction) ~= "table" then
    if type(row.ButtonText) == "table" then WFJ.Labels.show(SURFACE, headerKey(row), row, nil, HEADER) end
    return
  end
  local register = WFJ.HelpTooltip.register
  WFJ.Labels.forbid(row.Name) -- the character's own name
  if type(row.Level) == "table" then WFJ.Labels.show(SURFACE, cardKey(row.Level), row.Level, nil, CARD_LEVEL) end
  RecentAllies.showCardActivity(row.MostRecentInteraction)
  for _, key in ipairs({ "Class", "Location" }) do -- a class and a zone, behind the colour the client wraps them in
    if type(row[key]) == "table" then WFJ.NameLabels.wrapped(SURFACE, cardKey(row[key]), row[key]) end
  end
  local tip = WFJ.Labels.familiesWith(CARD_TIP_KEYS, "RecentAllyType", "RecentAllyInteraction")
  register(row, { from = 2, only = tip.only })
  if not tipHooked[row] and type(row.ShowTooltip) == "function" then
    tipHooked[row] = true
    hooksecurefunc(row, "ShowTooltip", RecentAllies.onCardTooltip)
  end
  if type(row.PartyButton) == "table" then register(row.PartyButton, PARTY_TIP) end
  local state = type(row.StateDisplay) == "table" and row.StateDisplay or nil
  if state and type(state.PinDisplay) == "table" then register(state.PinDisplay, PIN_TIP) end
  if state and type(state.FriendRequestSentDisplay) == "table" then
    register(state.FriendRequestSentDisplay, REQUEST_SENT_TIP)
  end
  WFJ.Render.updateBanner(SURFACE)
end

-- The filter dropdown's menu, through the untagged-menu mechanism. → true when the dropdown was recorded now
local function hookFilterMenu()
  local menus, untagged = WFJ.Menus, WFJ.MenusUntagged
  if type(menus) ~= "table" or type(menus.TAGS) ~= "table" or type(untagged) ~= "table"
      or type(untagged.hookDropdown) ~= "function" then return false end
  menus.TAGS[FILTER_TAG] = menus.TAGS[FILTER_TAG] or FILTER_MENU
  return untagged.hookDropdown(get("viewFilter"), FILTER_TAG)
end

local hooked, viewHooked = false, false

-- The older panel. → true when it was set up now
local function initPanel(util)
  local friends, rows = get("friends"), get("rows")
  if hooked or type(rows) ~= "table" or type(friends) ~= "table" or type(friends.SetTitle) ~= "function" then
    return false -- a social window without SetTitle, or a client without the panel
  end
  hooked = true
  util.AddInitializedFrameCallback(rows, RecentAllies.onRow, RecentAllies, true)
  return true
end

-- The newer social window's card view. → true when it was set up now
local function initView(util)
  local view, rows = get("view"), get("viewRows")
  if viewHooked or type(view) ~= "table" then return false end
  viewHooked = true
  RecentAllies.showView()
  if type(get("viewAdd")) == "table" then WFJ.HelpTooltip.register(get("viewAdd"), ADD_TIP) end
  hookFilterMenu()
  if type(rows) == "table" then util.AddInitializedFrameCallback(rows, RecentAllies.onViewRow, RecentAllies, true) end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init. → true when a panel was set up now
function RecentAllies.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local util = get("scrollUtil")
  if type(util) ~= "table" or type(util.AddInitializedFrameCallback) ~= "function" then return false end
  local panel, view = initPanel(util), initView(util)
  return panel or view
end
