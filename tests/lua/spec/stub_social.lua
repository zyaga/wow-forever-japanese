-- The social window as the Forever client builds it: the camelot FriendsFrame, the
-- load-on-demand who list, and Blizzard_RaidUI on demand. Widgets carry the English their XML text= / OnLoad writes
-- put there; writer functions are globals replaying the client's writes (the client's own writes go to `fs.text`, so a
-- spec can count ours through fs.calls.SetText).
-- Install AFTER H.uiSetup: the English is read from the globals it sets (a key it does not set reads as the key).
local Stub = require("tests.lua.spec.wow_stub")

local Social = {}

local function en(key)
  local v = rawget(_G, key)
  return type(v) == "string" and v or key
end

local function fs(name, key) return Stub.namedFontString(name, key and en(key) or "") end
local function button(name, key) return Stub.button(name, key and en(key) or "") end
local function write(widget, text) -- the client's own write (a FontString or a Stub.button)
  if widget.fontString then widget.fontString.text = text else widget.text = text end
end

-- Blizzard_RaidUI arriving on demand: the roster frames its XML builds (group labels, the unnamed "Empty" region of
-- every slot, each member button's Name / Level / Class and Rank / Role / Loot icons) and the load flag. The spec
-- forwards ADDON_LOADED to WFJ.LoadOnDemand.loaded, as Main does.
function Social.loadRaidUI()
  for g = 1, 8 do
    CreateFrame("Frame", "RaidGroup" .. g)
    button("RaidGroup" .. g .. "Label").fontString.text = en("GROUP") .. " " .. g -- OnLoad (xml:331)
    for s = 1, 5 do
      local slot = CreateFrame("Button", "RaidGroup" .. g .. "Slot" .. s)
      slot:addRegion(Stub.fontString(en("EMPTY")))
    end
  end
  for i = 1, 40 do
    CreateFrame("Button", "RaidGroupButton" .. i)
    fs("RaidGroupButton" .. i .. "Name")
    fs("RaidGroupButton" .. i .. "Level")
    button("RaidGroupButton" .. i .. "Class")
    for _, part in ipairs({ "Rank", "Role", "Loot" }) do CreateFrame("Button", "RaidGroupButton" .. i .. part) end
  end
  -- RaidGroupFrame_Update's roster writes (Blizzard_RaidUI.lua:365–374)
  _G.RaidGroupFrame_Update = function()
    for i, m in ipairs(Social.raid or {}) do
      _G["RaidGroupButton" .. i .. "Name"].text = m.name
      _G["RaidGroupButton" .. i .. "Class"].fontString.text = m.class
      _G["RaidGroupButton" .. i .. "Level"].text = tostring(m.level)
    end
  end
  Stub.loadedAddons["Blizzard_RaidUI"] = true
end

-- A Lua-built help tooltip on `owner`: SetOwner, SetText (line 1), AddLine for the rest, Show
-- (GameTooltip.lua:468–484).
function Social.hover(owner, lines)
  local tt = _G.GameTooltip
  tt:SetOwner(owner)
  tt:SetText(lines[1])
  for i = 2, #lines do tt:AddLine(lines[i]) end
  tt:Show()
end

-- Forever's camelot FriendsFrame (blizzard_friendsframe/camelot/friendsframe.{lua,xml}): tabs Friends /
-- Raid / Quick Join (FRIEND_TAB_COUNT = 3, lua:30–33; no FRIEND_TAB_GUILD, no who panel), FriendsFrame_Update
-- (lua:427–475): tab 1 → FriendsFrame:SetTitle(CONTACTS_LIST_TITLE | CONTACTS_RECENT_ALLIES_TITLE |
-- RECRUIT_A_FRIEND) → TitleContainer.TitleText; tab 2 → FriendsFrameTitleText RAID; tab 3 → QUICK_JOIN. The ignore
-- list window's title is set once (FriendsIgnoreListMixin:InitializeFrameVisuals, lua:2461).
-- Install AFTER H.uiSetup.
function Social.installCamelot()
  Social.guildName, Social.raid = nil, nil
  Social.inviteHeader = nil
  _G.FRIEND_TAB_GUILD, _G.FRIEND_TAB_WHO = nil, nil
  _G.FRIEND_TAB_FRIENDS, _G.FRIEND_TAB_RAID, _G.FRIEND_TAB_QUICK_JOIN = 1, 2, 3
  local function titled(frame)
    frame.TitleContainer = CreateFrame("Frame")
    frame.TitleContainer.TitleText = Stub.fontString("")
    function frame.SetTitle(self, t) self.TitleContainer.TitleText.text = t end
  end
  local frame = CreateFrame("Frame", "FriendsFrame")
  frame.selectedTab = 1
  titled(frame)
  fs("FriendsFrameTitleText")
  Stub.tab("FriendsFrameTab1", en("CONTACTS_TAB_TITLE"))
  Stub.tab("FriendsFrameTab3", en("RAID"))
  Stub.tab("FriendsFrameTab4", en("QUICK_JOIN"))
  local header = CreateFrame("Frame", "FriendsTabHeader")
  header.selectedTab = 1
  header.friendsTabID, header.recentAlliesTabID, header.recruitAFriendTabID = 1, 2, 3
  -- the header's TabSystem (TabSystemMixin:AddTab / TabSystemButtonMixin:Init + UpdateTabText,
  -- tabsystemtemplates.lua:167–207, 288–297), built at the header's OnLoad (GenerateHeaderTabs, lua:612–616)
  header.TabSystem = CreateFrame("Frame")
  header.TabSystem.tabs = {}
  for i, key in ipairs({ "FRIENDS", "CONTACTS_RECENT_ALLIES_TAB_NAME", "RECRUIT_A_FRIEND" }) do
    local tab = button(nil, key)
    tab.tabText = en(key)
    function tab.UpdateTabText(self)
      self.fontString.text = self.forceDisabled and ("|cff808080" .. self.tabText .. "|r") or self.tabText
    end
    function tab.SetTabEnabled(self, enabled)
      self.forceDisabled = not enabled
      self:UpdateTabText()
    end
    header.TabSystem.tabs[i] = tab
  end
  -- the Battle.net bar's contacts menu button (xml:457; ContactsMenuMixin:OnEnter, lua:2502–2506)
  local bn = CreateFrame("Frame", "FriendsFrameBattlenetFrame")
  bn.ContactsMenuButton = CreateFrame("DropdownButton")
  -- the status dropdown (xml:658), a help-tooltip owner (its OnEnter, lua:584–597)
  CreateFrame("DropdownButton", "FriendsFrameStatusDropdown")
  -- FriendsFrame_UpdateFriendButton: a row's info line: FRIENDS_LIST_OFFLINE / BNET_LAST_ONLINE_TIME for an
  -- offline friend (lua:1566–1568, 1714), a Recruit-A-Friend friend's location through GetOnlineInfoText
  -- (lua:1615–1628), else the location. Social.friends = { { name, area, raf = "recruit" | "recruiter" | nil,
  -- offline = true, lastOnline = "<duration>" } }
  Social.friends = {}
  _G.FriendsFrame_UpdateFriendButton = function(row)
    local entry = Social.friends[row.index]
    row.name.text = entry.name
    if entry.offline and entry.lastOnline then
      row.info.text = string.format(en("BNET_LAST_ONLINE_TIME"), entry.lastOnline)
    elseif entry.offline then
      row.info.text = en("FRIENDS_LIST_OFFLINE")
    elseif entry.raf == "recruit" then
      row.info.text = string.format(en("RAF_RECRUIT_FRIEND"), entry.area)
    elseif entry.raf == "recruiter" then
      row.info.text = string.format(en("RAF_RECRUITER_FRIEND"), entry.area)
    else
      row.info.text = entry.area
    end
  end
  Social.rows = {}
  for i = 1, 3 do Social.rows[i] = { index = i, name = Stub.fontString(""), info = Stub.fontString("") } end
  -- the invite rows' own initializers (camelot friendsframe.lua:1631–1675), which the list's element factory looks up
  -- by name each time it builds a row (lua:337–351). Social.invites = { accountName, … }
  _G.FRIENDS_BUTTON_TYPE_INVITE_HEADER, _G.FRIENDS_BUTTON_TYPE_INVITE = 5, 4
  Social.invites = {}
  _G.FriendsFrame_UpdateFriendInviteHeaderButton = function(headerButton)
    write(headerButton, string.format(en("FRIEND_REQUESTS"), #Social.invites))
  end
  _G.FriendsFrame_UpdateFriendInviteButton = function(row, elementData)
    row.buttonType, row.id = elementData.buttonType, elementData.id
    row.Name.text = Social.invites[elementData.id]
  end
  Social.inviteButtons = {}
  frame.IgnoreListWindow = CreateFrame("Frame")
  titled(frame.IgnoreListWindow)
  frame.IgnoreListWindow:SetTitle(en("IGNORE_LIST"))
  _G.FriendsFrame_Update = function()
    local tab = _G.FriendsFrame.selectedTab or 1
    if tab == 1 then
      local h = _G.FriendsTabHeader.selectedTab
      if h == 1 then
        _G.FriendsFrame:SetTitle(en("CONTACTS_LIST_TITLE"))
      elseif h == 2 then
        _G.FriendsFrame:SetTitle(en("CONTACTS_RECENT_ALLIES_TITLE"))
      else
        _G.FriendsFrame:SetTitle(en("RECRUIT_A_FRIEND"))
      end
    elseif tab == 2 then
      _G.FriendsFrameTitleText.text = en("RAID")
    elseif tab == 3 then
      _G.FriendsFrameTitleText.text = en("QUICK_JOIN")
    end
  end
end

-- the camelot list (re)building its invite rows: the header, then one pooled FriendsFrameFriendInviteTemplate
-- row per invite (Name + AcceptButton text="ACCEPT", friendsframe.xml:59–100), through the globals by name.
-- → the header button
function Social.buildInvites()
  local header = Social.inviteHeader or button(nil)
  Social.inviteHeader = header
  _G.FriendsFrame_UpdateFriendInviteHeaderButton(header, { buttonType = _G.FRIENDS_BUTTON_TYPE_INVITE_HEADER })
  for i = 1, #Social.invites do
    local row = Social.inviteButtons[i]
    if not row then
      row = CreateFrame("Frame")
      row.Name = Stub.fontString("")
      row.AcceptButton = button(nil, "ACCEPT")
      Social.inviteButtons[i] = row
    end
    _G.FriendsFrame_UpdateFriendInviteButton(row, { buttonType = _G.FRIENDS_BUTTON_TYPE_INVITE, id = i })
  end
  return header
end

-- Blizzard_GroupFinder_VanillaStyle arriving (load-on-demand): LFGWhoListFrame (mainline/wholist.xml:65–156)
-- with its parentKey WhoFrameTotals, WhoFrameEditBox (SearchBoxTemplate; Instructions = WHO_LIST_SEARCH_INSTRUCTIONS),
-- a pooled ScrollBox and LFGWhoListMixin:UpdateWhoList (wholist.lua:219–239) copied onto the frame. Social.who =
-- { total, rows = { { name, level, race, class, zone, guild } } }; UpdateWhoList re-initializes one pooled row per
-- entry (LFGWhoListButtonMixin:InitButton, lua:50–88). The spec forwards ADDON_LOADED, as Main does.
function Social.loadWhoList()
  local frame = CreateFrame("Frame", "LFGWhoListFrame")
  frame.WhoFrameTotals = Stub.fontString("")
  frame.ScrollBox = Stub.scrollBox()
  local edit = CreateFrame("EditBox", "WhoFrameEditBox")
  edit.editText = ""
  function edit.GetText(self) return self.editText end
  function edit.SetText(self, t) self.editText = t end
  edit.Instructions = Stub.fontString(en("WHO_LIST_SEARCH_INSTRUCTIONS"))
  frame.EditBox = edit
  -- the filter DropdownButton (wholist.xml:182): OpenMenu regenerates, then RegisterMenu(root)
  local dropdown = CreateFrame("Button")
  function dropdown.RegisterMenu(self, root) self.root = root end
  frame.FilterDropdown = dropdown
  Social.who = { total = 0, rows = {} }
  Social.whoRows = {}
  local function init(row, data)
    row.Name.text = data.name
    row.Level.text = string.format(en("LFG_WHO_LEVEL"), data.level)
    row.Race.text = data.race or ""
    row.Class.text = data.class or ""
    row.Variable.text = data.zone or ""
    row.GuildName.text = data.guild or ""
  end
  function frame.UpdateWhoList(self)
    local shown = ""
    if Social.who.total > 50 then shown = string.format(en("WHO_FRAME_SHOWN_TEMPLATE"), 50) end
    self.WhoFrameTotals.text = string.format(en("WHO_FRAME_TOTAL_TEMPLATE"), Social.who.total) .. "  " .. shown
    for i, data in ipairs(Social.who.rows) do
      local row = Social.whoRows[i]
      if not row then
        row = CreateFrame("Button")
        for _, part in ipairs({ "Name", "Level", "Race", "Class", "Variable", "GuildName" }) do
          row[part] = Stub.fontString("")
        end
        row.InviteButton = CreateFrame("Button") -- WhoInviteButtonMixin (wholist.xml:56)
        Social.whoRows[i] = row
      end
      self.ScrollBox:initFrame(row, data, init)
    end
  end
  Stub.loadedAddons["Blizzard_GroupFinder_VanillaStyle"] = true
  return frame
end

return Social
