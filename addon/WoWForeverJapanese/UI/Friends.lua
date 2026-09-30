-- UI/Friends.lua: the social window's friends, ignore and who panels (surface "friends", area "ui",
-- ADR-016). The raid panel is UI/Raid.lua. Blizzard_FriendsFrame loads its camelot files (blizzard_friendsframe.toc:
-- 15–19).
-- Static labels (XML text= and OnLoad writes, shown at init so each tab's own OnShow → PanelTemplates_TabResize
-- measures the Japanese): the tabs, Add Friend / Send Message, the Battle.net unavailable label and broadcast frame,
-- the Real ID request warning (unnamed regions), FriendsTooltipOtherGameAccounts (FriendsFrameTooltip_SetLine
-- measures it at show time with no new text), and the ignore list window's SetTitle(IGNORE_LIST) at its setup
-- (lua:2461).
-- Dynamic writers, each post-hooked by name:
--   tabs: Friends / Raid / Quick Join (FRIEND_TAB_COUNT = 3, camelot friendsframe.lua:30–33). FriendsFrame_Update
--     writes RAID / QUICK_JOIN to FriendsFrameTitleText (lua:461–473) and the contacts titles with
--     FriendsFrame:SetTitle (CONTACTS_LIST_TITLE / CONTACTS_RECENT_ALLIES_TITLE / RECRUIT_A_FRIEND, lua:447–459) →
--     FriendsFrame.TitleContainer.TitleText;
--   FriendsFrame_UpdateFriendButton → button.info (Offline / "last online %s ago", or a Recruit-A-Friend friend's
--     RAF_RECRUIT_FRIEND / RAF_RECRUITER_FRIEND: "|cffffd200Recruit:|r <location>", GetOnlineInfoText,
--     lua:1615–1628; the location is kept as written). Zones, rich presence and names stay as written;
--   the list builds invite rows through their own initializers (camelot friendsframe.lua:337–351; the factory looks
--     each global up at call time, so the name hook runs): FriendsFrame_UpdateFriendInviteHeaderButton → the header's
--     FRIEND_REQUESTS (:1631–1637), FriendsFrame_UpdateFriendInviteButton → the pooled invite row's AcceptButton
--     (text="ACCEPT", friendsframe.xml:98; the Decline button is an icon).
--   who: the camelot FriendsFrame has no who panel. ShowWhoPanel opens LFGParentFrame tab 3 (lua:1358); the list is
--     LFGWhoListFrame in the load-on-demand Blizzard_GroupFinder_VanillaStyle (its toc: LoadOnDemand 1), set up
--     through WFJ.LoadOnDemand.when whichever way it loads.
--     LFGWhoListMixin:UpdateWhoList writes .WhoFrameTotals = format(WHO_FRAME_TOTAL_TEMPLATE, n) .. "  " .. (shown
--     template or "") (mainline/wholist.lua:219–239; the frame's own method, called as self:UpdateWhoList() from
--     OnEvent, :172–175); the two-space join is the `joined` label form (both halves filled, Core/UIStrings);
--     WhoFrameEditBox's Instructions read WHO_LIST_SEARCH_INSTRUCTIONS (wholist.xml:96, SearchBoxTemplate). Rows are
--     pooled ScrollBox frames: each row's .Level (LFG_WHO_LEVEL, wholist.lua:66–67) is shown from the ScrollBox's
--     initialized-frame callback (ScrollUtil.AddInitializedFrameCallback, the raid-info pattern); Name / Race / Class
--     / Variable / GuildName are never touched (restricted to LFG_WHO_LEVEL on .Level only).
--     Each row is also a help-tooltip owner restricted to WHO_LIST_LEVEL_TOOLTIP (LFGWhoListButtonMixin:OnEnter,
--     wholist.lua:24–32: line 1 the name, line 3 zone / guild / race, never matched).
--     Since 1.60.1.70009 a row's InviteButton is a help-tooltip owner restricted to WHO_PARTY_BUTTON_TOOLTIP
--     (WhoInviteButtonMixin:ShowTooltip, wholist.lua:117–121). The filter dropdown (FilterDropdown, wholist.xml:182)
--     is an untagged DropdownButton (LFGWhoListFilterUtil.SetupFilterMenu, wholist.lua:278–321, 336–378, 460–526):
--     hooked through UI/MenusUntagged.hookDropdown as the WHO_FILTER spec, its entries restricted to the section
--     words and the sort entries; the class, race and zone entries under them are names and never match.
--   the contacts header's TabSystem tabs (FriendsTabHeaderMixin:GenerateHeaderTabs, camelot friendsframe.lua:
--     612–616: FRIENDS / CONTACTS_RECENT_ALLIES_TAB_NAME / RECRUIT_A_FRIEND; TabSystemButtonMixin:UpdateTabText
--     rewrites a tab's text on SetTabEnabled, tabsystemtemplates.lua:192–207, so each tab's own method is hooked; a
--     disabled tab's colour-wrapped text stays English).
-- Help tooltips (GameTooltip_AddNewbieTip / SetText on a frame owner): tabs, Add Friend, Send Message, the broadcast
-- button, the contacts menu button's title CONTACTS_MENU_NAME (ContactsMenuMixin:OnEnter, lua:2502–2506), the status
-- dropdown ("Status: %s", the status word nested).
-- Records are never released: the rows are rewritten through hooks that stay installed, and a label on a hidden frame
-- costs nothing; modifier / area changes restore and re-apply every record (Render.refresh).
local _, WFJ = ...
local Friends = {}
WFJ.Friends = Friends

local SURFACE = "friends"
Friends.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
local Compat = WFJ.Compat

local WHO_ADDON = "Blizzard_GroupFinder_VanillaStyle"
-- RAID / QUICK_JOIN are what camelot writes here (lua:461–473)
local TITLE_KEYS = { "FRIENDS_LIST", "IGNORE_LIST", "WHO_LIST", "RAID", "QUICK_JOIN" }
local CONTACTS_TITLE_KEYS = { "CONTACTS_LIST_TITLE", "CONTACTS_RECENT_ALLIES_TITLE", "RECRUIT_A_FRIEND" }
local CONTACTS_TITLE = { only = CONTACTS_TITLE_KEYS }
local IGNORE_TITLE = { only = { "IGNORE_LIST" } }
local WHO_INSTRUCTION_KEYS = { "WHO_LIST_SEARCH_INSTRUCTIONS", "SEARCH" }
-- The who row's invite button and the filter dropdown's entries (see the header)
local WHO_INVITE_TIP = { only = { "WHO_PARTY_BUTTON_TOOLTIP" } }
local WHO_FILTER_TAG = "WHO_FILTER"
local WHO_FILTER = { source = "wholist.lua:316", keys = { "CLASS", "RACE", "ZONE", "CHECK_ALL", "UNCHECK_ALL",
  "WHO_SORT_LABEL", "NAME", "LEVEL", "WHO_SORT_ASCENDING_LABEL", "WHO_SORT_DESCENDING_LABEL" } }
local CAMELOT_INFO_KEYS = { "FRIENDS_LIST_OFFLINE", "BNET_LAST_ONLINE_TIME", "RAF_RECRUIT_FRIEND",
  "RAF_RECRUITER_FRIEND" }
local HEADER_TAB_KEYS = { "FRIENDS", "CONTACTS_RECENT_ALLIES_TAB_NAME", "RECRUIT_A_FRIEND" }

local CANDIDATES = {
  frame = { "FriendsFrame" }, title = { "FriendsFrameTitleText" },
  update = { "FriendsFrame_Update" }, updateButton = { "FriendsFrame_UpdateFriendButton" },
  inviteHeaderUpdate = { "FriendsFrame_UpdateFriendInviteHeaderButton" },
  inviteUpdate = { "FriendsFrame_UpdateFriendInviteButton" },
  tab1 = { "FriendsFrameTab1" }, tab3 = { "FriendsFrameTab3" }, tab4 = { "FriendsFrameTab4" },
  addFriend = { "FriendsFrameAddFriendButton" }, sendMessage = { "FriendsFrameSendMessageButton" },
  tooltipPlaying = { "FriendsTooltipOtherGameAccounts" }, statusDropdown = { "FriendsFrameStatusDropdown" },
  whoEditBox = { "WhoFrameEditBox" }, whoTotals = { "LFGWhoListFrame.WhoFrameTotals" },
  whoFilter = { "LFGWhoListFrame.FilterDropdown" },
  contactsTitle = { "FriendsFrame.TitleContainer.TitleText" },
  ignoreTitle = { "FriendsFrame.IgnoreListWindow.TitleContainer.TitleText" }, whoFrame = { "LFGWhoListFrame" },
  tabSystem = { "FriendsTabHeader.TabSystem" },
  scrollUtil = { "ScrollUtil" },
  listFrame = { "FriendsListFrame" }, battlenet = { "FriendsFrameBattlenetFrame" },
}

-- Widgets this module must never record: the EditBoxes (Compat global names).
Friends.NEVER_TOUCH = { "WhoFrameEditBox", "AddFriendNameEditBox" }

local function get(key) return Compat.get(SURFACE, key) end

-- A nested field of a Blizzard frame (read only). → value | nil
local function field(t, ...)
  for _, k in ipairs({ ... }) do
    if type(t) ~= "table" then return nil end
    t = t[k]
  end
  return t
end

-- A stable record key per row widget (pooled / hybrid rows are reused; records follow the widget, not the index):
-- one WFJ.Labels.keyer per record family.
local acceptKey, infoKey = WFJ.Labels.keyer("ui.accept."), WFJ.Labels.keyer("ui.info.")
local inviteHeaderKey, whoLevelKey = WFJ.Labels.keyer("ui.inviteHeader."), WFJ.Labels.keyer("ui.whoLevel.")
local headerTabKey = WFJ.Labels.keyer("ui.headerTab.")

-- The labels the client writes once at load. → the number of dictionary words found.
function Friends.showStatic()
  local items = {}
  for _, key in ipairs({ "tab1", "tab3", "tab4", "addFriend", "sendMessage", "tooltipPlaying" }) do
    items[#items + 1] = { "ui." .. key, get(key) }
  end
  items[#items + 1] = { "ui.whoInstructions", field(get("whoEditBox"), "Instructions") }
  local bn = get("battlenet")
  items[#items + 1] = { "ui.bnUnavailable", field(bn, "UnavailableLabel") }
  items[#items + 1] = { "ui.bnInfoLabel", field(bn, "UnavailableInfoFrame", "Label") }
  items[#items + 1] = { "ui.bnInfoText", field(bn, "UnavailableInfoFrame", "Text") }
  local broadcast = field(bn, "BroadcastFrame")
  items[#items + 1] = { "ui.bnBroadcast", WFJ.Labels.region(broadcast, "BATTLENET_BROADCAST") }
  items[#items + 1] = { "ui.bnUpdate", field(broadcast, "ScrollFrame", "UpdateButton") }
  items[#items + 1] = { "ui.bnCancel", field(broadcast, "ScrollFrame", "CancelButton") }
  items[#items + 1] = { "ui.bnPrompt", field(broadcast, "ScrollFrame", "EditBox", "PromptText") }
  local rid = field(get("listFrame"), "RIDWarning")
  items[#items + 1] = { "ui.ridTitle", WFJ.Labels.region(rid, "BATTLENET_FRIEND_REQUEST_RECEIVED") }
  items[#items + 1] = { "ui.ridInfo", WFJ.Labels.region(rid, "RID_FRIEND_REQUEST_INFO") }
  -- the ignore list window's SetTitle(IGNORE_LIST), through the shared title helper
  local n = WFJ.Labels.title(STATIC, field(get("frame"), "IgnoreListWindow"), IGNORE_TITLE, "ui.ignoreTitle")
  return n + WFJ.Labels.showAll(STATIC, items)
end

-- hooksecurefunc target (FriendsFrame_Update). → the number of dictionary words found.
function Friends.onUpdate()
  local frame = get("frame")
  -- the contacts title goes through the shared SetTitle helper: the same widget
  -- (FriendsFrame.TitleContainer.TitleText), the same record and the same `only`; it is also re-shown right after a
  -- SetTitle.
  return WFJ.Labels.show(SURFACE, "ui.title", get("title"), nil, { only = TITLE_KEYS })
    + WFJ.Labels.title(SURFACE, frame, CONTACTS_TITLE, "ui.contactsTitle")
end

-- A Recruit-A-Friend-linked friend's summon button (SummonButtonMixin:OnEnter, camelot friendsframe.lua:
-- 1010–1017): RAF_SUMMON_LINKED, then COOLDOWN_REMAINING .. " " .. SecondsToTime(…): the colonPrefix form, the time
-- kept as written.
local SUMMON_TIP = { only = { "RAF_SUMMON_LINKED", "COOLDOWN_REMAINING" } }

-- hooksecurefunc target (FriendsFrame_UpdateFriendButton). → the number of dictionary words found.
function Friends.onFriendButton(button)
  if type(button) ~= "table" then return 0 end
  if type(button.summonButton) == "table" then WFJ.HelpTooltip.register(button.summonButton, SUMMON_TIP) end
  if type(button.info) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, infoKey(button.info), button.info, nil, { only = CAMELOT_INFO_KEYS })
end

-- hooksecurefunc target (FriendsFrame_UpdateFriendInviteHeaderButton): the pooled header button. → 1 | 0
function Friends.onInviteHeader(button)
  if type(button) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, inviteHeaderKey(button), button, nil, { only = { "FRIEND_REQUESTS" } })
end

-- hooksecurefunc target (FriendsFrame_UpdateFriendInviteButton): a pooled invite row's Accept. → 1 | 0
function Friends.onInvite(button)
  local accept = field(button, "AcceptButton")
  if type(accept) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, acceptKey(accept), accept, nil, { only = { "ACCEPT" } })
end

-- hooksecurefunc target (LFGWhoListFrame:UpdateWhoList). → 1 | 0
function Friends.onWho()
  return WFJ.Labels.show(SURFACE, "ui.whoTotals", get("whoTotals"), nil, { only = { "WHO_FRAME_TOTAL_TEMPLATE" } })
end

-- One pooled who row after its initializer ran (ScrollUtil's initialized-frame callback: (owner, frame,
-- elementData) for a new row, (frame, elementData) for the iterateExisting pass). Returns nothing: ForEachFrame stops
-- at the first truthy return (see UI/Raid.onRow).
function Friends.onWhoRow(a, b)
  local row = a
  if a == Friends then row = b end
  local level = field(row, "Level")
  if type(level) ~= "table" then return end
  WFJ.Labels.show(SURFACE, whoLevelKey(level), level, nil, { only = { "LFG_WHO_LEVEL" } })
  WFJ.HelpTooltip.register(row, { only = { "WHO_LIST_LEVEL_TOOLTIP" } })
  local invite = field(row, "InviteButton")
  if type(invite) == "table" then WFJ.HelpTooltip.register(invite, WHO_INVITE_TIP) end
end

-- The filter dropdown, through the untagged-menu mechanism (UI/MenusUntagged). → true when hooked
local function hookWhoFilter()
  local menus, untagged = WFJ.Menus, WFJ.MenusUntagged
  if type(menus) ~= "table" or type(menus.UNTAGGED) ~= "table" or type(untagged) ~= "table"
      or type(untagged.hookDropdown) ~= "function" then
    return false
  end
  menus.UNTAGGED[WHO_FILTER_TAG] = menus.UNTAGGED[WHO_FILTER_TAG] or WHO_FILTER
  return untagged.hookDropdown(get("whoFilter"), WHO_FILTER_TAG)
end

-- One contacts header tab, after Init or UpdateTabText wrote it. → 1 | 0
local function showHeaderTab(tab)
  return WFJ.Labels.show(STATIC, headerTabKey(tab), tab, nil, { only = HEADER_TAB_KEYS })
end

local tabHooked = setmetatable({}, { __mode = "k" })

-- Every tab of FriendsTabHeader.TabSystem (built at its OnLoad, before this addon). → words found
function Friends.showHeaderTabs()
  local tabs = field(get("tabSystem"), "tabs")
  if type(tabs) ~= "table" then return 0 end
  local n = 0
  for _, tab in ipairs(tabs) do
    if type(tab) == "table" then
      if not tabHooked[tab] and type(tab.UpdateTabText) == "function" then
        tabHooked[tab] = true
        hooksecurefunc(tab, "UpdateTabText", showHeaderTab)
      end
      n = n + showHeaderTab(tab)
    end
  end
  return n
end

local whoHooked = false

-- Blizzard_GroupFinder_VanillaStyle's who list, once that addon is loaded (now, or on its ADDON_LOADED).
-- → true when the who list was found.
function Friends.setupWho()
  for _, key in ipairs({ "whoFrame", "whoTotals", "whoEditBox", "whoFilter" }) do
    Compat.declare(SURFACE, key, CANDIDATES[key])
  end
  local frame = get("whoFrame")
  if type(frame) ~= "table" then return false end
  WFJ.Labels.forbidNames(Friends.NEVER_TOUCH) -- WhoFrameEditBox exists only now (Main's registration found none)
  WFJ.Labels.show(STATIC, "ui.whoInstructions", field(get("whoEditBox"), "Instructions"), nil,
    { only = WHO_INSTRUCTION_KEYS })
  if whoHooked then return true end
  whoHooked = true
  if type(frame.UpdateWhoList) == "function" then hooksecurefunc(frame, "UpdateWhoList", Friends.onWho) end
  local util = get("scrollUtil")
  if type(frame.ScrollBox) == "table" and type(util) == "table"
      and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(frame.ScrollBox, Friends.onWhoRow, Friends, true)
  end
  hookWhoFilter()
  Friends.onWho()
  return true
end

local function registerHelp()
  local HT = WFJ.HelpTooltip
  for _, key in ipairs({ "tab1", "tab3", "tab4", "addFriend", "sendMessage" }) do
    local owner = get(key)
    if type(owner) == "table" then HT.register(owner) end
  end
  local status = get("statusDropdown")
  if type(status) == "table" then HT.register(status, { only = { "FRIENDS_LIST_STATUS_TOOLTIP" } }) end
  local contactsMenu = field(get("battlenet"), "ContactsMenuButton")
  if type(contactsMenu) == "table" then HT.register(contactsMenu, { only = { "CONTACTS_MENU_NAME" } }) end
  local broadcastButton = field(get("battlenet"), "BroadcastButton")
  if type(broadcastButton) == "table" then
    HT.register(broadcastButton, { only = { "CHAT_LABEL", "NEWBIE_TOOLTIP_CHATMENU" } })
  end
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Friends.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked or type(get("frame")) ~= "table" then return false end
  hooked = true
  Friends.showStatic()
  registerHelp()
  local writers = { { "update", "FriendsFrame_Update", Friends.onUpdate },
    { "updateButton", "FriendsFrame_UpdateFriendButton", Friends.onFriendButton },
    { "inviteHeaderUpdate", "FriendsFrame_UpdateFriendInviteHeaderButton", Friends.onInviteHeader },
    { "inviteUpdate", "FriendsFrame_UpdateFriendInviteButton", Friends.onInvite } }
  for _, w in ipairs(writers) do
    if type(get(w[1])) == "function" then hooksecurefunc(w[2], w[3]) end
  end
  Friends.showHeaderTabs()
  WFJ.LoadOnDemand.when(WHO_ADDON, Friends.setupWho)
  return true
end
