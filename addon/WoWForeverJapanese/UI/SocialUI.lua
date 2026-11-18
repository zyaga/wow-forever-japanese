-- UI/SocialUI.lua: the friends window the client shows while its social system is on (surface "socialui", area
-- "ui", ADR-016): SocialUIFrame, built by Blizzard_SocialUI with the friends list views of Blizzard_FriendsFrame.
-- While that system is off the client shows FriendsFrame instead (UI/Friends). Plumbing: UI/CommunitiesKit.
-- Every file:line is the 1.60.1.70959 extract.
-- The title: SocialUIFrameMixin:RefreshTitle → SetTitle(the selected tab's name) (blizzard_socialui/mainline/
--   socialui.lua:626–629; the six names lua:182–272), through Labels.title restricted to those names.
-- The friends list (SocialUIFrame.FriendsList, created for the Friends tab, lua:185–186):
--   ActionButton: SetText(SOCIAL_UI_FRIENDS_LIST_ADD_FRIEND_BUTTON_LABEL) (blizzard_friendsframe/mainline/
--     friendslisttemplates.lua:71);
--   FilterBar.SearchFilterDropdown's own text FILTER (WowStyle1FilterDropdownTemplate) and FilterBar.SearchBar's
--     placeholder (blizzard_socialuishared/socialuisharedtemplates.xml:5, 39–45): the placeholder is a label of its
--     own; what the player types is never read;
--   its ScrollBox's pooled rows: a header's ButtonText (SocialUIScrollableHeaderMixin:Initialize,
--     socialuisharedtemplates.lua:179–186: "Favorites %d/%d", "Friends List %d/%d", friendslisttemplates.lua:
--     367–377), and a friend card's Location (RefreshLocationDisplayText, lua:597–600), which holds
--     FRIENDS_LIST_OFFLINE, a last-online line or a place; only the first two are dictionary lines. A card
--     refreshes its location without being initialized again, so that method is post-hooked per card.
-- The Battle.net bar: the notice shown in place of the BattleTag (SocialUIPersonalBattleTagDisplayMixin:
--   ShowBattleNetUnavailableNotice, socialuitemplates.lua:302–304, inside a colour code).
-- The unavailable notice and the broadcast frame: XML text= (socialuitemplates.xml:204, 216, 237, 314, 328, 338).
-- The ignore list (SocialUIFrame.IgnoreListFrame): its title (lua:614), its two buttons (xml:399, 409) and its
--   header rows' Text (lua:733, 742).
-- Never touched: a friend's name, character, level and class, a place, a BattleTag, the search box, the broadcast
--   box, the names in the ignore list.
local _, WFJ = ...
local Kit = WFJ.CommunitiesKit
local SocialUI = {}
WFJ.SocialUI = SocialUI

local SURFACE = "socialui"
SocialUI.SURFACE = SURFACE

local F = "SocialUIFrame"
local LIST = F .. ".FriendsList"
local IGNORE = F .. ".IgnoreListFrame"
local BROADCAST = F .. ".BattleNetBroadcastFrame"

SocialUI.NEVER_TOUCH = { LIST .. ".FilterBar.SearchBar", BROADCAST .. ".EditBox" }

local k = Kit.new(SURFACE, {
  frame = { F }, list = { LIST }, rows = { LIST .. ".ScrollBox" }, ignore = { IGNORE },
  ignoreRows = { IGNORE .. ".ScrollBox" }, scrollUtil = { "ScrollUtil" },
})

local TITLE = { only = { "SOCIAL_UI_FRIENDS_TAB_NAME", "SOCIAL_UI_RECENT_ALLIES_TAB_NAME",
  "SOCIAL_UI_QUICK_JOIN_TAB_NAME", "SOCIAL_UI_FRIEND_REQUESTS_TAB_NAME", "SOCIAL_UI_RECRUIT_A_FRIEND_TAB_NAME",
  "SOCIAL_UI_RAID_TAB_NAME" } }
local IGNORE_TITLE = { only = { "SOCIAL_UI_IGNORE_LIST_TITLE" } }
local HEADERS = { "SOCIAL_UI_FAVORITE_FRIENDS_LIST_HEADER", "SOCIAL_UI_FRIENDS_LIST_HEADER" }
local LOCATION = { "FRIENDS_LIST_OFFLINE", "LASTONLINE_SECS", "LASTONLINE_MINS", "LASTONLINE_HOURS",
  "LASTONLINE_DAYS", "LASTONLINE_MONTHS", "LASTONLINE_YEARS" }
local IGNORE_HEADERS = { "SOCIAL_UI_IGNORE_LIST_IGNORE_HEADER", "SOCIAL_UI_IGNORE_LIST_BATTLE_NET_BLOCK_HEADER" }

-- Labels written once, from XML or at load: { recKey, path under SocialUIFrame, keys }.
local STATIC = {
  { "add", "FriendsList.ActionButton", { "SOCIAL_UI_FRIENDS_LIST_ADD_FRIEND_BUTTON_LABEL" } },
  { "searchHint", "FriendsList.FilterBar.SearchBar.Instructions", { "SOCIAL_UI_SEARCH_BOX_INSTRUCTIONS" } },
  { "unavailableHeader", "BattleNetUnavailableNoticeFrame.HeaderText", { "BATTLENET_UNAVAILABLE" } },
  { "unavailableText", "BattleNetUnavailableNoticeFrame.Text", { "SOCIAL_UI_BATTLENET_UNAVAILABLE_ALERT" } },
  { "broadcastTitle", "BattleNetBroadcastFrame.Title", { "SOCIAL_UI_BATTLENET_BROADCAST_FRAME_HEADER" } },
  { "broadcastPrompt", "BattleNetBroadcastFrame.PromptText", { "SOCIAL_UI_BATTLENET_BROADCAST_FRAME_PROMPT" } },
  { "broadcastUpdate", "BattleNetBroadcastFrame.UpdateButton",
    { "SOCIAL_UI_BATTLENET_BROADCAST_UPDATE_BUTTON_LABEL" } },
  { "broadcastCancel", "BattleNetBroadcastFrame.CancelButton",
    { "SOCIAL_UI_BATTLENET_BROADCAST_CANCEL_BUTTON_LABEL" } },
  { "ignoreBlock", "IgnoreListFrame.BlockButton", { "SOCIAL_UI_IGNORE_LIST_BLOCK_BUTTON_LABEL" } },
  { "ignoreRemove", "IgnoreListFrame.UnblockButton", { "SOCIAL_UI_IGNORE_LIST_REMOVE_BUTTON_LABEL" } },
  { "bnetNotice", "BattleNetBar.ControlsContainer.PersonalBattleTagDisplay.DisplayText",
    { "SOCIAL_UI_BATTLE_NET_UNAVAILABLE_NOTICE" } },
}

-- The static labels, found under the frame as it is now (the friends list exists once its tab was made).
-- → the number of dictionary words shown
function SocialUI.showStatic()
  local frame = k.get("frame")
  local list = {}
  for _, l in ipairs(STATIC) do
    local widget = Kit.child(frame, l[2])
    -- a widget not built yet has no record to drop
    if type(widget) == "table" then list[#list + 1] = { l[1], widget, l[3] } end
  end
  return k.showList(list)
end

local headerKey = WFJ.Labels.keyer("header.") -- a pooled row's record keys (never a position in the list)
local locationKey = WFJ.Labels.keyer("location.")
local ignoreKey = WFJ.Labels.keyer("ignore.")
local cardHooked = setmetatable({}, { __mode = "k" })

-- A friend card's location line. → 1 | 0
function SocialUI.onLocation(card)
  if type(card) ~= "table" or type(card.Location) ~= "table" then return 0 end
  return k.show(locationKey(card.Location), card.Location, LOCATION)
end

-- One pooled row of the friends list: a header (its ButtonText) or a friend card (its Location).
function SocialUI.onRow(row)
  if type(row.ButtonText) == "table" then k.show(headerKey(row.ButtonText), row.ButtonText, HEADERS) end
  if type(row.Location) == "table" then
    if not cardHooked[row] and type(row.RefreshLocationDisplayText) == "function" then
      cardHooked[row] = true
      hooksecurefunc(row, "RefreshLocationDisplayText", SocialUI.onLocation)
    end
    SocialUI.onLocation(row)
  end
  WFJ.Render.updateBanner(SURFACE)
end

-- One pooled row of the ignore list: a header's Text (an entry's is a name).
function SocialUI.onIgnoreRow(row, data)
  if type(row.Text) == "table" and type(data) == "table" and data.headerText ~= nil then
    k.show(ignoreKey(row.Text), row.Text, IGNORE_HEADERS)
  end
  WFJ.Render.updateBanner(SURFACE)
end

local hooked, listHooked = false, false

-- The friends list's own hooks: the list is created with its tab, which may be after login.
local function hookList()
  local list = k.get("list")
  if listHooked or type(list) ~= "table" then return false end
  listHooked = true
  WFJ.Labels.forbidNames(SocialUI.NEVER_TOUCH)
  k.dropdown("filter", Kit.child(list, "FilterBar.SearchFilterDropdown"), { "FILTER" })
  k.rows(k.get("rows"), SocialUI.onRow)
  return true
end

-- hooksecurefunc target (SocialUIFrame's OnShow and RefreshVisuals): the labels as they stand now.
function SocialUI.show()
  k.declare() -- the tab frames are created on demand: forget what Compat memoized before
  hookList()
  return SocialUI.showStatic()
end

-- → true when the window was set up now; false on a client without it, or when already hooked
function SocialUI.setup()
  k.declare()
  local frame = k.get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  WFJ.Labels.title(SURFACE, frame, TITLE)
  WFJ.Labels.title(SURFACE, k.get("ignore"), IGNORE_TITLE, "ignoreTitle")
  k.script(frame, "OnShow", SocialUI.show)
  k.after(frame, "RefreshVisuals", SocialUI.show)
  k.rows(k.get("ignoreRows"), SocialUI.onIgnoreRow)
  SocialUI.show()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init. Blizzard_SocialUI loads at login.
function SocialUI.init()
  k.declare()
  if type(k.get("frame")) ~= "table" then return false end
  return SocialUI.setup()
end
