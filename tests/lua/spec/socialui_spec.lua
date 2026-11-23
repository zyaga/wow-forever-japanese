-- The social window: UI/SocialUI.lua over SocialUIFrame replayed from the Forever client's blizzard_socialui
-- (mainline/socialui.lua, socialuitemplates.*), blizzard_socialuishared (socialuisharedtemplates.*) and the card
-- views of blizzard_friendsframe (mainline/friendslisttemplates.*, friendrequestslisttemplates.*, friendslistutil.lua).
-- A friend's name, a BattleTag and a character's name stay as written.
local S = require("tests.lua.spec.stub_camelot_social")
local Stub = require("tests.lua.spec.wow_stub")
local M = require("tests.lua.spec.menu_stub")

local FILES = S.files("Core/Placeholders.lua", "UI/SettingsKeys.lua", "UI/Menus.lua", "UI/MenusTags.lua",
  "UI/MenusUntagged.lua", "UI/SocialUI.lua")

local UI = {
  FRIENDS = { "Friends", "フレンド" }, RAID = { "Raid", "レイド" }, QUICK_JOIN = { "Quick Join", "クイック参加" },
  ADD_NEW_FRIEND = { "Add New Friend", "新しいフレンドを追加" }, FILTER = { "Filter", "フィルター" },
  ADDING_FRIENDS_DISABLED = { "Adding friends is disabled.", "フレンドの追加は無効です。" },
  FRIENDS_LIST_OFFLINE = { "Offline", "オフライン" },
  BNET_LAST_ONLINE_TIME = { "last online %s ago", "最終オンライン: %s前" },
  LASTONLINE_DAYS = { "%d |4day:days;", "%d日" },
  FRIENDS_TOOLTIP_TOO_MANY_CHARACTERS = { "(%d more |4character:characters;)", "(ほか%dキャラクター)" },
  SOCIAL_TAB_UNAVAILABLE = { "The %s feature is unavailable due to your account's privacy settings.",
    "アカウントのプライバシー設定により、%sの機能は利用できません。" },
  IGNORE_LIST = { "Ignore List", "無視リスト" }, IGNORED = { "Ignored", "無視中" },
  IGNORE_PLAYER = { "Ignore Player", "プレイヤーを無視" },
  UNIGNORE_PLAYER_BUTTON_LABEL = { "Remove from list", "リストから削除" },
  BATTLENET_BROADCAST = { "Broadcast", "ブロードキャスト" }, UPDATE = { "Update", "更新" },
  CANCEL = { "Cancel", "キャンセル" },
  FRIENDS_LIST_ENTER_TEXT = { "Tell your friends what you're doing", "今していることをフレンドに伝えよう" },
  BATTLENET_UNAVAILABLE = { "Blizzard services are unavailable", "Blizzardのサービスは利用できません" },
  CONTACTS_MENU_NAME = { "Menu", "メニュー" },
  FRIENDS_LIST_STATUS_TOOLTIP = { "Status: |cffffffff%s|r", "ステータス: |cffffffff%s|r" },
  GUILD_ONLINE_LABEL = { "Online", "オンライン" }, FRIENDS_LIST_AWAY = { "Away", "離席" },
  STATUS = { "Status", "状態" }, ACCEPT = { "Accept", "承認" }, CONTINUE = { "Continue", "続ける" },
  RECENT_ALLY_INTERACTION_TIME_FORMAT = { "%s ago", "%s前" },
  TRAVEL_PASS_INVITE = { "Invite to Group", "グループに招待" },
  RECENT_ALLIES_PARTY_BUTTON_OFFLINE_TOOLTIP = { "Player Offline", "プレイヤーはオフラインです" },
  FRIENDS_LEVEL_TEMPLATE = { "Level %d %s", "レベル %d %s" },
  SOCIAL_UI_FRIENDS_LIST_FRIEND_IN_GROUP_TOOLTIP = { "%s In a Group", "%sはグループに参加中" },
  SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_PVP = { "PvP", "対人戦" },
  SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_RAIDING = { "Raiding", "レイド攻略" },
  SOCIAL_UI_FRIENDS_LIST_BATTLE_NET_FRIEND_TAGS_FORMAT = { "|cnNORMAL_FONT_COLOR:Tags: %s|r",
    "|cnNORMAL_FONT_COLOR:タグ: %s|r" },
  SOCIAL_UI_FRIENDS_LIST_BATTLE_NET_FRIEND_TAGS_OFFLINE_FORMAT = { "|cnFRIENDS_GRAY_COLOR:Tags: %s|r",
    "|cnFRIENDS_GRAY_COLOR:タグ: %s|r" },
  REPORT_PLAYER = { "Report Player", "プレイヤーを通報" }, BLOCK_INVITES = { "Block Invites", "招待をブロック" },
  -- a dictionary word a name widget may happen to hold
  CLOSE = { "Close", "閉じる" },
}
-- Core/UIStrings: the last-online time is a duration the client formats
local NEEDS = { ARGS = { BNET_LAST_ONLINE_TIME = { [1] = "time" },
  RECENT_ALLY_INTERACTION_TIME_FORMAT = { [1] = "time" }, SOCIAL_TAB_UNAVAILABLE = { [1] = "words" },
  FRIENDS_LIST_STATUS_TOOLTIP = { [1] = "word" } } }

local GREY, DARK, WHITE = "|cff808080", "|cff404040", "|cffffffff"
local C = {}

-- SocialUIFrame as its OnLoad leaves it: the bar, the side windows, the two lists and the tab pool.
local function install()
  local frame = S.frame("SocialUIFrame")
  frame.TitleContainer = { TitleText = S.fs("") }
  function frame.SetTitle(self, text) self.TitleContainer.TitleText.text = text end
  S.put(frame, "BattleNetBar.ControlsContainer.OnlineStatusDropdown", S.dropdown("status"))
  S.put(frame, "BattleNetBar.ControlsContainer.BattleNetMenuButton", S.frame(nil, "menu"))
  S.put(frame, "BattleNetBar.ControlsContainer.PersonalBattleTagDisplay.DisplayText", S.fs("Close#1234"))
  S.put(frame, "BattleNetUnavailableNoticeFrame.Header.HeaderText", S.fs(_G.BATTLENET_UNAVAILABLE))
  S.put(frame, "BattleNetBroadcastFrame.Title", S.fs("Broadcast"))
  S.put(frame, "BattleNetBroadcastFrame.EditBox.PromptText", S.fs(_G.FRIENDS_LIST_ENTER_TEXT))
  S.put(frame, "BattleNetBroadcastFrame.UpdateButton", S.button(nil, "Update"))
  S.put(frame, "BattleNetBroadcastFrame.CancelButton", S.button(nil, "Cancel"))
  local ignore = S.put(frame, "IgnoreListFrame", S.frame(nil, "ignore"))
  ignore.TitleContainer = { TitleText = S.fs("Ignore List") }
  function ignore.SetTitle(self, text) self.TitleContainer.TitleText.text = text end
  ignore.BlockButton, ignore.UnblockButton = S.button(nil, "Ignore Player"), S.button(nil, "Remove from list")
  ignore.ScrollBox = Stub.scrollBox()
  for _, key in ipairs({ "FriendsList", "FriendRequestsList" }) do
    local list = S.put(frame, key, S.frame(nil, key))
    list.ActionButton = S.button(nil, "Add New Friend")
    list.FriendsDisabledText = S.fs("")
    list.ScrollBox = Stub.scrollBox()
    S.put(list, "FilterBar.SearchBar.Instructions", S.fs("Search for keywords"))
    local filter = S.put(list, "FilterBar.SearchFilterDropdown", S.dropdown("filter"))
    filter:SetDefaultText("Filter")
  end
  S.put(frame, "FriendRequestsList.RealIDWarning.ContinueButton", S.button(nil, "Continue"))
  frame.socialTabPool = S.pool(function() return S.frame() end)
  -- SocialUIFrameMixin:RefreshTabs / RefreshContentFrame / RefreshTitle (socialui.lua:385–396, 534–544, 627–630)
  function frame.RefreshTabs(self)
    self.socialTabPool:ReleaseAll()
    for _ = 1, 3 do self.socialTabPool:Acquire() end
  end
  function frame.RefreshContentFrame(self)
    if C.friendsDisabled then
      self.FriendsList.FriendsDisabledText.text = _G.SOCIAL_TAB_UNAVAILABLE:format("Friends")
    end
  end
  -- a friend card as FriendsListSocialCardMixin:Initialize leaves it (friendslisttemplates.lua:567–600)
  function C.card(existing, friend)
    local row = existing or CreateFrame("Button")
    row.FriendName = row.FriendName or S.fs("")
    row.Name, row.Level = row.Name or S.fs(""), row.Level or S.fs("")
    row.Class, row.Location = row.Class or S.fs(""), row.Location or S.fs("")
    row.PartyButton = row.PartyButton or S.frame()
    row.StateDisplay = row.StateDisplay or { FavoriteDisplay = S.frame() }
    frame.FriendsList.ScrollBox:initFrame(row, {}, function()
      local colour = friend.offline and DARK or GREY
      row.FriendName.text = colour .. friend.name .. "|r"
      row.Name.text = friend.character and (colour .. friend.character .. "|r") or ""
      row.Class.text = friend.class and ("|cffc79c6e" .. friend.class .. "|r") or ""
      row.Location.text = colour .. friend.location .. "|r"
    end)
    return row
  end
  function C.header(text)
    local row = Stub.button(nil, "")
    row.ButtonText = S.fs("")
    frame.FriendsList.ScrollBox:initFrame(row, {}, function() row.fontString.text = text end)
    return row
  end
  function C.request(name, ago)
    local row = CreateFrame("Button")
    row.AcceptButton = { Text = S.fs("Accept") }
    row.Name, row.FriendType = S.fs(name), S.fs(GREY .. "Wants to be your WoW friend|r")
    row.RequestTimestamp = S.fs("")
    frame.FriendRequestsList.ScrollBox:initFrame(row, {}, function()
      row.RequestTimestamp.text = WHITE .. ago .. " ago|r"
    end)
    return row
  end
  function C.ignored(text, isHeader)
    local row = CreateFrame("Frame")
    if isHeader then row.Text = S.fs(text) else row.Name = S.fs(text) end
    ignore.ScrollBox:initFrame(row, {})
    return row
  end
  return frame
end

describe("the social window (SocialUIFrame) on Forever", function()
  local WFJ, frame

  before_each(function()
    C.friendsDisabled = nil
    WFJ = S.load(FILES, UI, NEEDS)
    frame = install()
  end)
  after_each(function()
    WFJ.State.setNames(false)
    S.teardown({ "SocialUIFrame", "EventRegistry" })
  end)

  it("a client without the window is left alone", function()
    _G.SocialUIFrame = nil
    assert.is_false(WFJ.SocialUI.init())
  end)

  it("the fixed labels translate at once; the reveal key shows the client's English", function()
    assert.is_true(WFJ.SocialUI.init())
    local friends, broadcast, ignore = frame.FriendsList, frame.BattleNetBroadcastFrame, frame.IgnoreListFrame
    assert.are.equal("新しいフレンドを追加", friends.ActionButton:GetText())
    assert.are.equal("新しいフレンドを追加", frame.FriendRequestsList.ActionButton:GetText())
    assert.are.equal("フィルター", friends.FilterBar.SearchFilterDropdown.Text:GetText())
    assert.are.equal("ブロードキャスト", broadcast.Title:GetText())
    assert.are.equal("今していることをフレンドに伝えよう", broadcast.EditBox.PromptText:GetText())
    assert.are.equal("更新", broadcast.UpdateButton:GetText())
    assert.are.equal("キャンセル", broadcast.CancelButton:GetText())
    assert.are.equal("無視リスト", ignore.TitleContainer.TitleText:GetText())
    assert.are.equal("プレイヤーを無視", ignore.BlockButton:GetText())
    assert.are.equal("リストから削除", ignore.UnblockButton:GetText())
    assert.are.equal("Blizzardのサービスは利用できません",
      frame.BattleNetUnavailableNoticeFrame.Header.HeaderText:GetText())
    assert.are.equal("続ける", frame.FriendRequestsList.RealIDWarning.ContinueButton:GetText())
    -- a string the dictionary has no line for stays as the client wrote it
    assert.are.equal("Search for keywords", friends.FilterBar.SearchBar.Instructions:GetText())
    -- the player's own BattleTag is never read
    local tag = frame.BattleNetBar.ControlsContainer.PersonalBattleTagDisplay.DisplayText
    assert.are.equal("Close#1234", tag:GetText())
    assert.is_true(S.unrecorded(WFJ, tag))
    S.alt(WFJ, true)
    assert.are.equal("Add New Friend", friends.ActionButton:GetText())
    assert.are.equal("Filter", friends.FilterBar.SearchFilterDropdown.Text:GetText())
    assert.are.equal("Ignore List", ignore.TitleContainer.TitleText:GetText())
    S.alt(WFJ, false)
    assert.are.equal("新しいフレンドを追加", friends.ActionButton:GetText())
    -- the filter button's text is written again on every choice
    friends.FilterBar.SearchFilterDropdown:UpdateText()
    assert.are.equal("フィルター", friends.FilterBar.SearchFilterDropdown.Text:GetText())
  end)

  it("with translation off nothing is written", function()
    WFJ.State.setEnabled(false)
    WFJ.SocialUI.init()
    frame:SetTitle("Friends")
    assert.are.equal("Add New Friend", frame.FriendsList.ActionButton:GetText())
    assert.are.equal("Friends", frame.TitleContainer.TitleText:GetText())
    WFJ.State.setEnabled(true)
    assert.are.equal("新しいフレンドを追加", frame.FriendsList.ActionButton:GetText())
  end)

  it("the title follows the selected tab; a tab with no dictionary line keeps its English", function()
    WFJ.SocialUI.init()
    frame:SetTitle("Friends")
    assert.are.equal("フレンド", frame.TitleContainer.TitleText:GetText())
    frame:SetTitle("Raid")
    assert.are.equal("レイド", frame.TitleContainer.TitleText:GetText())
    frame:SetTitle("Friend Requests")
    assert.are.equal("Friend Requests", frame.TitleContainer.TitleText:GetText())
    frame:SetTitle("Close") -- a dictionary word that is no tab name
    assert.are.equal("Close", frame.TitleContainer.TitleText:GetText())
  end)

  it("a tab's tooltip, the menu button's, the status dropdown's and the disabled Add button's translate", function()
    WFJ.SocialUI.init()
    frame:RefreshTabs()
    local tabs = {}
    for tab in frame.socialTabPool:EnumerateActive() do tabs[#tabs + 1] = tab end
    assert.are.same({ WHITE .. "フレンド|r" }, S.tooltip(tabs[1], { WHITE .. "Friends|r" }))
    assert.are.same({ WHITE .. "クイック参加|r" }, S.tooltip(tabs[2], { WHITE .. "Quick Join|r" }))
    assert.are.same({ WHITE .. "Friend Requests|r" }, S.tooltip(tabs[3], { WHITE .. "Friend Requests|r" }))
    S.alt(WFJ, true)
    S.tooltip(tabs[1], { WHITE .. "Friends|r" })
    assert.are.equal(WHITE .. "Friends|r", _G.GameTooltipTextLeft1:GetText())
    S.alt(WFJ, false)
    local bar = frame.BattleNetBar.ControlsContainer
    assert.are.same({ "メニュー" }, S.tooltip(bar.BattleNetMenuButton, { "Menu" }))
    assert.are.same({ "ステータス: " .. WHITE .. "オンライン|r" },
      S.tooltip(bar.OnlineStatusDropdown, { "Status: " .. WHITE .. "Online|r" }))
    assert.are.same({ "フレンドの追加は無効です。" },
      S.tooltip(frame.FriendsList.ActionButton, { "Adding friends is disabled." }))
  end)

  it("the privacy notice translates when its tab is selected", function()
    WFJ.SocialUI.init()
    C.friendsDisabled = true
    frame:RefreshContentFrame()
    assert.are.equal("アカウントのプライバシー設定により、フレンドの機能は利用できません。",
      frame.FriendsList.FriendsDisabledText:GetText())
  end)

  it("the other tabs' privacy notices translate too: the same callback writes them", function()
    for _, key in ipairs({ "RecentAlliesList", "QuickJoinFrame", "RecruitAFriendFrame" }) do
      S.put(frame, key .. ".FriendsDisabledText", S.fs(""))
    end
    WFJ.SocialUI.init()
    function frame.RefreshContentFrame(self) -- hooked by name: the selected tab's setup callback
      self.QuickJoinFrame.FriendsDisabledText.text = _G.SOCIAL_TAB_UNAVAILABLE:format("Quick Join")
      self.RecruitAFriendFrame.FriendsDisabledText.text = _G.SOCIAL_TAB_UNAVAILABLE:format("Nobody Known")
    end
    frame:RefreshContentFrame()
    WFJ.SocialUI.onContent()
    assert.are.equal("アカウントのプライバシー設定により、クイック参加の機能は利用できません。",
      frame.QuickJoinFrame.FriendsDisabledText:GetText())
    -- a tab name with no dictionary line is kept as written inside the sentence
    assert.are.equal("アカウントのプライバシー設定により、Nobody Knownの機能は利用できません。",
      frame.RecruitAFriendFrame.FriendsDisabledText:GetText())
    assert.are.equal("", frame.RecentAlliesList.FriendsDisabledText:GetText())
  end)

  it("a friend card: Offline and the last-online line translate; names and a note-like word stay", function()
    local early = C.card(nil, { name = "Offline", location = "Offline", offline = true }) -- before the surface starts
    WFJ.SocialUI.init()
    assert.are.equal(DARK .. "オフライン|r", early.Location:GetText())
    assert.are.equal(DARK .. "Offline|r", early.FriendName:GetText()) -- a friend called like a status word
    assert.is_true(S.unrecorded(WFJ, early.FriendName))
    local away = C.card(nil, { name = "Kei", character = "Close", location = "last online 3 days ago", offline = true })
    assert.are.equal(DARK .. "最終オンライン: 3日前|r", away.Location:GetText())
    assert.are.equal(DARK .. "Close|r", away.Name:GetText())
    assert.is_true(S.unrecorded(WFJ, away.Name))
    S.alt(WFJ, true)
    assert.are.equal(DARK .. "Offline|r", early.Location:GetText())
    assert.are.equal(DARK .. "last online 3 days ago|r", away.Location:GetText())
    S.alt(WFJ, false)
    assert.are.equal(DARK .. "オフライン|r", early.Location:GetText())
    -- the pooled card reused for an online friend somewhere with no name line: the client's text stays
    C.card(early, { name = "Tomo", location = "In another game" })
    assert.are.equal(GREY .. "In another game|r", early.Location:GetText())
    -- a list header the dictionary has no line for
    local header = C.header("Friends List 1/3")
    assert.are.equal("Friends List 1/3", header:GetText())
  end)

  it("with Japanese names on a card's zone and class show their Japanese; with names off they stay", function()
    WFJ.Data.add("name", { [WFJ.Names.key("Stormwind City")] = "ストームウィンド・シティ\tすとーむうぃんど・してぃ",
      [WFJ.Names.key("Warrior")] = "ウォリアー\tうぉりあー", [WFJ.Names.key("Thrall")] = "スロール\tすろーる" })
    WFJ.SocialUI.init()
    WFJ.State.setNames(false)
    local friend = { name = "Thrall", character = "Thrall", class = "Warrior", location = "Stormwind City" }
    local card = C.card(nil, friend)
    assert.are.equal(GREY .. "Stormwind City|r", card.Location:GetText())
    assert.are.equal("|cffc79c6eWarrior|r", card.Class:GetText())
    WFJ.State.setNames(true)
    C.card(card, friend)
    assert.are.equal(GREY .. "ストームウィンド・シティ|r", card.Location:GetText())
    assert.are.equal("|cffc79c6eウォリアー|r", card.Class:GetText())
    -- a friend and a character named like a game name are a player's
    assert.are.equal(GREY .. "Thrall|r", card.FriendName:GetText())
    assert.are.equal(GREY .. "Thrall|r", card.Name:GetText())
    S.alt(WFJ, true)
    assert.are.equal(GREY .. "Stormwind City|r", card.Location:GetText())
    S.alt(WFJ, false)
  end)

  it("a card's tooltip: the last-online line and the count of further characters; line 1 is never read", function()
    WFJ.SocialUI.init()
    local card = C.card(nil, { name = "Offline", location = "Offline", offline = true })
    assert.are.same({ "Offline", " ", "最終オンライン: 3日前", "Close", "(ほか2キャラクター)" },
      S.tooltip(card, { "Offline", " ", "last online 3 days ago", "Close", "(2 more characters)" }))
    assert.are.same({ "Offline", " ", "オフライン" }, S.tooltip(card, { "Offline", " ", "Offline" }))
    assert.are.same({ "グループに招待", "プレイヤーはオフラインです" },
      S.tooltip(card.PartyButton, { "Invite to Group", "Player Offline" }))
  end)

  -- FriendsListSocialCardMixin:ShowTooltip → BuildTooltip (friendslisttemplates.lua:884–910, 1096–1125): the
  -- friend's name, a separator, the character's name, the level and class, the race, the zone, the faction
  local function hover(card, info, lines)
    card.tooltipLines = lines
    card.ShowTooltip = card.ShowTooltip or function(c) -- the card's own method, hooked once by the addon
      local tt = _G.GameTooltip
      tt:SetOwner(c)
      tt:ClearLines()
      for _, line in ipairs(c.tooltipLines) do tt:AddLine(line) end
      tt:Show()
    end
    C.card(card, { name = "Thrall", character = "Thrall", class = "Warrior", location = "Stormwind City" })
    -- the card's own data (Initialize, :567–571)
    card.elementData = { accountInfo = { gameAccountInfo = info, friendTags = C.tags }, friendIndex = C.friendIndex }
    card:ShowTooltip()
    local out = {}
    for i = 1, #lines do out[i] = _G["GameTooltipTextLeft" .. i]:GetText() end
    return out
  end

  it("a card's tooltip: with Japanese names on, the class, race, zone and faction lines show their Japanese; the"
    .. " character's name above them never changes; the reveal key shows the English", function()
    WFJ.UIStrings.word = function(text) return WFJ.State.names and WFJ.Placeholders.wordFor(text) or nil end
    finally(function() WFJ.UIStrings.word = nil end)
    WFJ.Data.add("name", { [WFJ.Names.key("Stormwind City")] = "ストームウィンド・シティ\tすとーむうぃんど・してぃ",
      [WFJ.Names.key("Alliance")] = "アライアンス\tあらいあんす", [WFJ.Names.key("Human")] = "ヒューマン\tひゅーまん",
      [WFJ.Names.key("Thrall")] = "スロール\tすろーる" })
    WFJ.SocialUI.init()
    WFJ.State.setNames(true)
    local card = CreateFrame("Button")
    local human = { raceName = "Human", areaName = "Stormwind City", factionName = "Alliance" }
    local english = { "Thrall", " ", "Thrall-Stormwind City", "Level 60 Warrior", "Human", "Stormwind City",
      "Alliance", "A note: Human" }
    assert.are.same({ "Thrall", " ", "Thrall-Stormwind City", "レベル 60 ウォリアー", "人間",
      "ストームウィンド・シティ", "アライアンス", "A note: Human" }, hover(card, human, english))
    S.alt(WFJ, true)
    for i = 4, 7 do assert.are.equal(english[i], _G["GameTooltipTextLeft" .. i]:GetText()) end
    S.alt(WFJ, false)
    assert.are.equal("人間", _G.GameTooltipTextLeft5:GetText())
    _G.GameTooltip:Hide()
    assert.is_nil(next(WFJ.SurfaceState.surfaces()["help.social"] or {}))
    -- a character called like a zone, with no block under it: another game's status line stays
    assert.are.same({ "Thrall", " ", "Stormwind City", "Playing another game" },
      hover(card, human, { "Thrall", " ", "Stormwind City", "Playing another game" }))
    -- the lines are not the card's own data: nothing is read
    assert.are.same(english, hover(card, { raceName = "Orc", areaName = "Orgrimmar", factionName = "Horde" }, english))
    -- names off: the level line is a dictionary line, the class and the three names stay as written
    WFJ.State.setNames(false)
    assert.are.same({ "Thrall", " ", "Thrall-Stormwind City", "レベル 60 Warrior", "Human", "Stormwind City",
      "Alliance", "A note: Human" }, hover(card, human, english))
    -- another owner's tooltip is never read
    _G.GameTooltip:SetOwner(CreateFrame("Frame"))
    assert.are.equal(0, WFJ.SocialUI.onCardTooltip(card))
    assert.are.equal(0, WFJ.SocialUI.onCardTooltip("x"))
    assert.are.equal(0, WFJ.SocialUI.cardLines(nil, {}))
  end)

  -- the lines a character block ends with and the parts under it (friendslisttemplates.lua:871–881, 930–963,
  -- 1038–1093)
  local GROUP_ICON = "|A:friends-icon-friendsInGroup:16:16|a"
  local NOTE_ICON = "|TInterface\\FriendsFrame\\UI-FriendsFrame-Note:0:0:0:0:1:1:0:1:0:1:255:209:0|t "
  local GAME_ICON = "|T4620680:0:0:0:0:32:32:0:32:0:32|t "
  local HUMAN = { raceName = "Human", areaName = "Stormwind City", factionName = "Alliance" }
  local BLOCK = { "Thrall", " ", "Thrall-Stormwind City", "Level 60 Warrior", "Human", "Stormwind City", "Alliance" }
  local BLOCK_JA = { "Thrall", " ", "Thrall-Stormwind City", "レベル 60 ウォリアー", "人間", "ストームウィンド・シティ",
    "アライアンス" }

  local function with(base, ...)
    local out = {}
    for i, line in ipairs(base) do out[i] = line end
    for _, line in ipairs({ ... }) do out[#out + 1] = line end
    return out
  end

  -- class and race words, the name list and Japanese names on; the two client calls the tooltip asks for a friend's
  -- characters, answering from `accounts`
  local function tooltipSetup(accounts)
    WFJ.UIStrings.word = function(text) return WFJ.State.names and WFJ.Placeholders.wordFor(text) or nil end
    _G.FRIENDS_TOOLTIP_WOW_TOON_TEMPLATE = "%1$s, %2$s %3$s %4$s"
    _G.C_BattleNet = { GetFriendNumGameAccounts = function() return #(accounts or {}) end,
      GetFriendGameAccountInfo = function(_, i) return accounts[i] end }
    WFJ.Data.add("name", { [WFJ.Names.key("Stormwind City")] = "ストームウィンド・シティ\tすとーむうぃんど・してぃ",
      [WFJ.Names.key("Alliance")] = "アライアンス\tあらいあんす", [WFJ.Names.key("Orgrimmar")] = "オーグリマー\tおーぐりまー",
      [WFJ.Names.key("Thrall")] = "スロール\tすろーる" })
    WFJ.SocialUI.init()
    WFJ.State.setNames(true)
    return CreateFrame("Button")
  end
  local function tooltipTeardown()
    WFJ.UIStrings.word, C.tags, C.friendIndex = nil, nil, nil
    _G.FRIENDS_TOOLTIP_WOW_TOON_TEMPLATE, _G.C_BattleNet = nil, nil
  end

  it("a card's tooltip: the in-group line under the faction shows its Japanese, the icon kept; the same words in"
    .. " a note stay; the reveal key shows the English", function()
    finally(tooltipTeardown)
    local card = tooltipSetup()
    local english = with(BLOCK, GROUP_ICON .. " In a Group", NOTE_ICON .. "In a Group")
    assert.are.same(with(BLOCK_JA, GROUP_ICON .. "はグループに参加中", NOTE_ICON .. "In a Group"),
      hover(card, HUMAN, english))
    S.alt(WFJ, true)
    assert.are.equal(GROUP_ICON .. " In a Group", _G.GameTooltipTextLeft8:GetText())
    S.alt(WFJ, false)
    assert.are.equal(GROUP_ICON .. "はグループに参加中", _G.GameTooltipTextLeft8:GetText())
    -- no in-group line: a note with those words straight under the faction is the player's
    english = with(BLOCK, NOTE_ICON .. "In a Group")
    assert.are.same(with(BLOCK_JA, NOTE_ICON .. "In a Group"), hover(card, HUMAN, english))
    -- names off: the in-group line is a dictionary line and still shows
    WFJ.State.setNames(false)
    assert.are.equal(GROUP_ICON .. "はグループに参加中",
      hover(card, HUMAN, with(BLOCK, GROUP_ICON .. " In a Group"))[8])
    -- translation off: nothing is written
    WFJ.State.setEnabled(false)
    assert.are.same(with(BLOCK, GROUP_ICON .. " In a Group"),
      hover(card, HUMAN, with(BLOCK, GROUP_ICON .. " In a Group")))
    WFJ.State.setEnabled(true)
  end)

  it("a card's tooltip: the tags line's label and the client's own tag words show their Japanese, a tag that is no"
    .. " such word stays; a broadcast with the same words and a friend with no tags are left alone", function()
    finally(tooltipTeardown)
    local card = tooltipSetup()
    _G.LIST_DELIMITER = ","
    finally(function() _G.LIST_DELIMITER = nil end)
    C.tags = { 3, 5 }
    local tags, broadcast = "|cnNORMAL_FONT_COLOR:Tags: PvP,Raiding|r", "|cnNORMAL_FONT_COLOR:Tags: mine|r"
    local TAGS_JA = "|cnNORMAL_FONT_COLOR:タグ: 対人戦,レイド攻略|r"
    local english = with(BLOCK, NOTE_ICON .. "Tags: Human", tags, " ", broadcast)
    assert.are.same(with(BLOCK_JA, NOTE_ICON .. "Tags: Human", TAGS_JA, " ",
      broadcast), hover(card, HUMAN, english))
    S.alt(WFJ, true)
    assert.are.equal(tags, _G.GameTooltipTextLeft9:GetText())
    S.alt(WFJ, false)
    assert.are.equal(TAGS_JA, _G.GameTooltipTextLeft9:GetText())
    -- names off: the label is a dictionary line and still shows
    WFJ.State.setNames(false)
    assert.are.equal(TAGS_JA, hover(card, HUMAN, with(BLOCK, tags))[8])
    WFJ.State.setNames(true)
    -- a tag that is none of the client's words, and one that only holds such a word, stay as written
    assert.are.equal("|cnNORMAL_FONT_COLOR:タグ: 対人戦,Fishing,PvP Raiding|r",
      hover(card, HUMAN, with(BLOCK, "|cnNORMAL_FONT_COLOR:Tags: PvP,Fishing,PvP Raiding|r"))[8])
    -- an offline friend: no character block, the grey form
    local offline = { "Thrall", " ", NOTE_ICON .. "alt", "|cnFRIENDS_GRAY_COLOR:Tags: PvP|r", " ",
      "last online 3 days ago" }
    assert.are.same({ "Thrall", " ", NOTE_ICON .. "alt", "|cnFRIENDS_GRAY_COLOR:タグ: 対人戦|r", " ", "最終オンライン: 3日前" },
      hover(card, { isOnline = false }, offline))
    -- the card's data holds no tags: a line that reads like one is another game's status
    C.tags = {}
    assert.are.same({ "Thrall", " ", "Stormwind City", tags }, hover(card, HUMAN, { "Thrall", " ", "Stormwind City",
      tags }))
    C.tags = nil
    assert.are.same(with(BLOCK_JA, tags), hover(card, HUMAN, with(BLOCK, tags)))
    WFJ.State.setEnabled(false)
    C.tags = { 3 }
    assert.are.same(with(BLOCK, tags), hover(card, HUMAN, with(BLOCK, tags)))
    WFJ.State.setEnabled(true)
  end)

  it("a card's tooltip: a further character's race, class and zone show their Japanese, its name and level stay;"
    .. " names off and the reveal key show the client's lines", function()
    finally(tooltipTeardown)
    local accounts = {
      { characterName = "Thrall", characterLevel = 60, raceName = "Human", className = "Warrior",
        areaName = "Stormwind City", hasFocus = true }, -- the character the block above shows: no pair of lines
      { characterName = "Hidden", characterLevel = 1, raceName = "Orc", className = "Mage", areaName = "Orgrimmar" },
      { characterName = "Orgrimmar", characterLevel = 42, raceName = "Orc", className = "Mage",
        areaName = "Orgrimmar" },
      { characterName = "Kei", characterLevel = 7 }, -- no race, class or zone yet
    }
    local card = tooltipSetup(accounts)
    C.friendIndex = 2
    local english = with(BLOCK, " ", "Playing another game", GAME_ICON .. "Orgrimmar, 42 Orc Mage", "Orgrimmar",
      "Kei, 7 Unknown Unknown", "Unknown", " ", "(2 more characters)")
    local japanese = with(BLOCK_JA, " ", "Playing another game", GAME_ICON .. "Orgrimmar, 42 オーク メイジ",
      "オーグリマー", "Kei, 7 Unknown Unknown", "Unknown", " ", "(ほか2キャラクター)")
    assert.are.same(japanese, hover(card, HUMAN, english))
    S.alt(WFJ, true)
    for i = 10, 11 do assert.are.equal(english[i], _G["GameTooltipTextLeft" .. i]:GetText()) end
    S.alt(WFJ, false)
    assert.are.equal(japanese[10], _G.GameTooltipTextLeft10:GetText())
    -- a broadcast that reads like a character's line, with no zone under it, is the player's
    local typed = with(BLOCK, " ", "Orgrimmar, 42 Orc Mage")
    assert.are.same(with(BLOCK_JA, " ", "Orgrimmar, 42 Orc Mage"), hover(card, HUMAN, typed))
    -- text in front of the character's that is no icon: not the client's line
    typed = with(BLOCK, " ", "My alt Orgrimmar, 42 Orc Mage", "Orgrimmar")
    assert.are.same(with(BLOCK_JA, " ", "My alt Orgrimmar, 42 Orc Mage", "Orgrimmar"), hover(card, HUMAN, typed))
    -- names off: the pair holds only names, and stays
    WFJ.State.setNames(false)
    local off = hover(card, HUMAN, english)
    for i = 10, 13 do assert.are.equal(english[i], off[i]) end
    WFJ.State.setNames(true)
    -- the card has no friend index: the client calls are not made
    C.friendIndex = nil
    for i, line in ipairs(hover(card, HUMAN, english)) do
      assert.are.equal(i >= 10 and i <= 13 and english[i] or japanese[i], line)
    end
    C.friendIndex = 2
    WFJ.State.setEnabled(false)
    assert.are.same(english, hover(card, HUMAN, english))
    WFJ.State.setEnabled(true)
  end)

  it("a friend request card: Accept and the time translate; the requester's name stays", function()
    WFJ.SocialUI.init()
    local row = C.request("Accept", "3 days")
    assert.are.equal("承認", row.AcceptButton.Text:GetText())
    assert.are.equal(WHITE .. "3日前|r", row.RequestTimestamp:GetText())
    assert.are.equal("Accept", row.Name:GetText())
    assert.is_true(S.unrecorded(WFJ, row.Name))
    assert.are.equal(GREY .. "Wants to be your WoW friend|r", row.FriendType:GetText()) -- no dictionary line
  end)

  it("the ignore list: a header translates; an ignored player's name stays", function()
    WFJ.SocialUI.init()
    local header, entry = C.ignored("Ignored", true), C.ignored("Ignored")
    assert.are.equal("無視中", header.Text:GetText())
    assert.are.equal("Ignored", entry.Name:GetText())
    assert.is_true(S.unrecorded(WFJ, entry.Name))
    assert.are.equal("Blocked", C.ignored("Blocked", true).Text:GetText()) -- no dictionary line
  end)

  it("the status, bar, decline and filter menus translate their words once shown", function()
    local registry = M.registry()
    WFJ.SocialUI.init()
    WFJ.Menus.init()
    local function text(frames, e) return frames[e].fontString:GetText() end
    -- the status menu: an icon and the word with no space between them (socialuitemplates.lua:205–217)
    local icon = "|A:friends-status-online:16:16|a"
    local root = M.element(nil)
    local online, away, hidden = root:CreateButton(icon .. "Online"), root:CreateButton(icon .. "Away"),
      root:CreateButton(icon .. "Appear Offline")
    local frames, menus = M.open(registry, "MENU_SOCIAL_UI_BATTLE_NET_PRESENCE", root)
    assert.are.equal(icon .. "オンライン", text(frames, online))
    assert.are.equal(icon .. "離席", text(frames, away))
    assert.are.equal(icon .. "Appear Offline", text(frames, hidden)) -- no dictionary line
    M.close(registry, menus)
    root = M.element(nil)
    local ignore = root:CreateButton("Ignore List")
    frames, menus = M.open(registry, "MENU_SOCIAL_UI_BATTLE_NET_BAR", root)
    assert.are.equal("無視リスト", text(frames, ignore))
    M.close(registry, menus)
    root = M.element(nil)
    local report, block = root:CreateButton("Report Player"), root:CreateButton("Block Invites")
    frames, menus = M.open(registry, "MENU_FRIEND_REQUESTS_DECLINE", root)
    assert.are.equal("プレイヤーを通報", text(frames, report))
    assert.are.equal("招待をブロック", text(frames, block))
    M.close(registry, menus)
    -- the filter dropdown opens its untagged menu on itself
    root = M.element(nil)
    local status = root:CreateButton("Status")
    local offline = status:CreateButton("Offline")
    local tags = root:CreateButton("Tags")
    frames = M.open(registry, nil, root, nil, frame.FriendsList.FilterBar.SearchFilterDropdown)
    assert.are.equal("状態", text(frames, status))
    assert.are.equal("オフライン", text(frames, offline))
    assert.are.equal("Tags", text(frames, tags)) -- no dictionary line
  end)
end)
