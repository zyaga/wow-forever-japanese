-- the camelot FriendsFrame's titles (SetTitle's TitleContainer.TitleText and
-- FriendsFrameTitleText, the guild-tab skip decided by FRIEND_TAB_GUILD existing, so Quick Join on tab 3 translates),
-- and the who list in the load-on-demand Blizzard_GroupFinder_VanillaStyle in either load order; the friend rows'
-- info line and the help tooltips.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Social = require("tests.lua.spec.stub_social")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Friends.lua"

local ADDON = "Blizzard_GroupFinder_VanillaStyle"
-- the who filter dropdown goes through UI/Menus + UI/MenusUntagged (loaded in their own describe)
local MENU_FILES = {}
for i, f in ipairs(FILES) do MENU_FILES[i] = f end
for _, f in ipairs({ "UI/SettingsKeys.lua", "UI/MenusUnit.lua", "UI/Menus.lua", "UI/MenusTags.lua",
  "UI/MenusUntagged.lua" }) do MENU_FILES[#MENU_FILES + 1] = f end

local UI = {
  CONTACTS_TAB_TITLE = { "Contacts", "連絡先" }, CONTACTS_LIST_TITLE = { "Contacts", "連絡先" },
  CONTACTS_RECENT_ALLIES_TITLE = { "Recent Allies", "最近の仲間" }, RECRUIT_A_FRIEND = { "Recruit A Friend", "友達を招待" },
  RAID = { "Raid", "レイド" }, QUICK_JOIN = { "Quick Join", "クイック参加" }, IGNORE_LIST = { "Ignore List", "無視リスト" },
  WHO_LIST_SEARCH_INSTRUCTIONS = { "Search Zones, Guilds, Classes, Races, Levels", "ゾーン、ギルド、クラス、種族、レベルで検索" },
  SEARCH = { "Search", "検索" },
  WHO_FRAME_TOTAL_TEMPLATE = { "%d |4Person:People; Found", "該当 %d人" },
  WHO_FRAME_SHOWN_TEMPLATE = { "(%d displayed)", "(%d人表示)" }, LFG_WHO_LEVEL = { "Level %d", "レベル %d" },
  FRIENDS = { "Friends", "フレンド" }, CONTACTS_RECENT_ALLIES_TAB_NAME = { "Recent Allies", "最近の仲間" },
  CONTACTS_MENU_NAME = { "Menu", "メニュー" }, WHO_LIST_LEVEL_TOOLTIP = { "Level %d", "レベル %d" },
  RAF_RECRUIT_FRIEND = { "|cffffd200Recruit:|r %s", "|cffffd200リクルート:|r %s" },
  RAF_RECRUITER_FRIEND = { "|cffffd200Recruiter:|r %s", "|cffffd200リクルーター:|r %s" },
  FRIEND_REQUESTS = { "Friend Requests (%d)", "フレンドリクエスト (%d)" }, ACCEPT = { "Accept", "承認" },
  -- dictionary words a name widget may happen to hold (never ours to translate there)
  ZONE = { "Zone", "ゾーン" }, WARRIOR = { "Warrior", "戦士" },
  -- the offline info line and the help tooltips
  FRIENDS_LIST_OFFLINE = { "Offline", "オフライン" }, BNET_LAST_ONLINE_TIME = { "last online %s ago", "最終オンライン: %s前" },
  LASTONLINE_DAYS = { "%d |4day:days;", "%d日" }, GUILD = { "Guild", "ギルド" },
  NEWBIE_TOOLTIP_FRIENDSTAB = { "Allows you to manage a list of players you enjoy playing with.",
    "一緒に遊ぶプレイヤーのリストを管理できます。" },
  FRIENDS_LIST_STATUS_TOOLTIP = { "Status: |cffffffff%s|r", "ステータス: |cffffffff%s|r" },
  FRIENDS_LIST_AWAY = { "Away", "離席" },
  -- a Recruit-A-Friend-linked friend's summon button (camelot friendsframe.lua:1010–1017)
  RAF_SUMMON_LINKED = { "Summon Linked Friend", "リンクしたフレンドを召喚" },
  COOLDOWN_REMAINING = { "Cooldown remaining:", "クールダウン残り:" },
  -- the who row's invite button and the filter menu (wholist.lua:117–121, 316–526)
  WHO_PARTY_BUTTON_TOOLTIP = { "Invite to Group", "グループに招待" }, RACE = { "Race", "種族" },
  CLASS = { "Class", "クラス" }, CHECK_ALL = { "Check All", "すべてチェック" },
  WHO_SORT_LABEL = { "Sort By", "並べ替え" }, NAME = { "Name", "名前" },
  WHO_SORT_ASCENDING_LABEL = { "Ascending", "昇順" }, WHO_SORT_DESCENDING_LABEL = { "Descending", "降順" },
}

describe("the social window on Forever's camelot FriendsFrame", function()
  local WFJ, SS

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do
        if rec.fs == widget then return false end
      end
    end
    return true
  end

  local function contactsTitle() return _G.FriendsFrame.TitleContainer.TitleText:GetText() end

  local function setup(whoFirst, files)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(files or FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    Social.installCamelot()
    if whoFirst then Social.loadWhoList() end
    assert.is_true(WFJ.Friends.init())
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.FRIEND_TAB_FRIENDS, _G.FRIEND_TAB_RAID, _G.FRIEND_TAB_QUICK_JOIN = nil, nil, nil
    _G.LFGWhoListFrame = nil -- a load-on-demand frame: absent until a spec loads it
  end)

  describe("titles and tabs", function()
    before_each(function() setup(false) end)

    it("the contacts titles follow FriendsFrame:SetTitle; Raid and Quick Join (tab 3) follow FriendsFrameTitleText",
      function()
        _G.FriendsFrame_Update()
        assert.are.equal("連絡先", contactsTitle())
        _G.FriendsTabHeader.selectedTab = 2
        _G.FriendsFrame_Update()
        assert.are.equal("最近の仲間", contactsTitle())
        _G.FriendsTabHeader.selectedTab = 3
        _G.FriendsFrame_Update()
        assert.are.equal("友達を招待", contactsTitle())
        _G.FriendsFrame.selectedTab = 2
        _G.FriendsFrame_Update()
        assert.are.equal("レイド", _G.FriendsFrameTitleText:GetText())
        _G.FriendsFrame.selectedTab = 3 -- Quick Join: no guild tab on camelot, so tab 3 is never skipped
        _G.FriendsFrame_Update()
        assert.are.equal("クイック参加", _G.FriendsFrameTitleText:GetText())
        alt(true)
        assert.are.equal("Quick Join", _G.FriendsFrameTitleText:GetText())
        assert.are.equal("Recruit A Friend", contactsTitle())
        alt(false)
        assert.are.equal("クイック参加", _G.FriendsFrameTitleText:GetText())
      end)

    it("the titles go through Labels.title: re-rendered right after a SetTitle, kept after a second"
      .. " one, and a title that is a name (a dictionary word) stays English", function()
      _G.FriendsFrame_Update()
      _G.FriendsFrame:SetTitle(_G.CONTACTS_RECENT_ALLIES_TITLE) -- no FriendsFrame_Update in between
      assert.are.equal("最近の仲間", contactsTitle())
      _G.FriendsFrame:SetTitle(_G.CONTACTS_RECENT_ALLIES_TITLE)
      assert.are.equal("最近の仲間", contactsTitle())
      _G.FriendsFrame:SetTitle(_G.RAID) -- not one of the contacts titles
      assert.are.equal("Raid", contactsTitle())
      local ignore = _G.FriendsFrame.IgnoreListWindow
      ignore:SetTitle(_G.IGNORE_LIST)
      assert.are.equal("無視リスト", ignore.TitleContainer.TitleText:GetText())
      ignore:SetTitle(_G.IGNORE_LIST)
      assert.are.equal("無視リスト", ignore.TitleContainer.TitleText:GetText())
    end)

    it("the tabs and the ignore list window's title are Japanese at init", function()
      assert.are.equal("連絡先", _G.FriendsFrameTab1:GetText())
      assert.are.equal("クイック参加", _G.FriendsFrameTab4:GetText())
      assert.are.equal("無視リスト", _G.FriendsFrame.IgnoreListWindow.TitleContainer.TitleText:GetText())
    end)

    it("the contacts header tabs translate and follow UpdateTabText; a disabled (wrapped) tab stays English",
      function()
        local tabs = _G.FriendsTabHeader.TabSystem.tabs
        assert.are.equal("フレンド", tabs[1]:GetText())
        assert.are.equal("最近の仲間", tabs[2]:GetText())
        assert.are.equal("友達を招待", tabs[3]:GetText())
        tabs[2]:SetTabEnabled(false)
        assert.are.equal("|cff808080Recent Allies|r", tabs[2]:GetText())
        tabs[2]:SetTabEnabled(true)
        assert.are.equal("最近の仲間", tabs[2]:GetText())
        alt(true)
        assert.are.equal("Recruit A Friend", tabs[3]:GetText())
        alt(false)
      end)

    it("the contacts menu button's tooltip title translates", function()
      Social.hover(_G.FriendsFrameBattlenetFrame.ContactsMenuButton, { "Menu" })
      assert.are.equal("メニュー", _G.GameTooltipTextLeft1:GetText())
    end)

    it("a Recruit-A-Friend row's info label translates with the location kept; a plain location is untouched",
      function()
        Social.friends = { { name = "Jaina", area = "Theramore Isle", raf = "recruit" },
          { name = "Thrall", area = "Orgrimmar", raf = "recruiter" }, { name = "Rexxar", area = "Menu" } }
        for _, row in ipairs(Social.rows) do _G.FriendsFrame_UpdateFriendButton(row) end
        assert.are.equal("|cffffd200リクルート:|r Theramore Isle", Social.rows[1].info:GetText())
        assert.are.equal("|cffffd200リクルーター:|r Orgrimmar", Social.rows[2].info:GetText())
        assert.are.equal("Menu", Social.rows[3].info:GetText())
        assert.are.equal("Jaina", Social.rows[1].name:GetText())
      end)

    it("offline / last-online info translates; names and a location that reads like a word do not",
      function()
        Social.friends = { { name = "Tomo", offline = true }, { name = "Kei", offline = true, lastOnline = "3 days" },
          { name = "Offline", area = "Guild" } }
        for _, row in ipairs(Social.rows) do _G.FriendsFrame_UpdateFriendButton(row) end
        assert.are.equal("オフライン", Social.rows[1].info:GetText())
        assert.are.equal("最終オンライン: 3日前", Social.rows[2].info:GetText())
        assert.are.equal("Guild", Social.rows[3].info:GetText()) -- a location, outside `only`
        assert.are.equal("Offline", Social.rows[3].name:GetText())
        assert.are.equal(WFJ.Font.PATH, (Social.rows[1].info:GetFont()))
        for i = 1, 3 do assert.is_true(unrecorded(Social.rows[i].name)) end
        alt(true)
        assert.are.equal("Offline", Social.rows[1].info:GetText())
        assert.are.equal("last online 3 days ago", Social.rows[2].info:GetText())
        alt(false)
        -- the rows are reused for other entries
        Social.friends[1], Social.friends[3] = Social.friends[3], Social.friends[1]
        for _, row in ipairs(Social.rows) do _G.FriendsFrame_UpdateFriendButton(row) end
        assert.are.equal("Guild", Social.rows[1].info:GetText())
        assert.are.equal("オフライン", Social.rows[3].info:GetText())
      end)

    it("a friend row's summon button: its title and the cooldown label, the time as written", function()
      Social.friends = { { name = "Jaina", area = "Theramore Isle" } }
      local row = Social.rows[1]
      row.summonButton = CreateFrame("Button")
      _G.FriendsFrame_UpdateFriendButton(row)
      Social.hover(row.summonButton, { "Summon Linked Friend", "Cooldown remaining: 4 min 59 sec" })
      assert.are.equal("リンクしたフレンドを召喚", _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("クールダウン残り: 4 min 59 sec", _G.GameTooltipTextLeft2:GetText())
      alt(true)
      assert.are.equal("Cooldown remaining: 4 min 59 sec", _G.GameTooltipTextLeft2:GetText())
      alt(false)
      Social.hover(row.summonButton, { "Friends" }) -- not this button's key
      assert.are.equal("Friends", _G.GameTooltipTextLeft1:GetText())
      row.summonButton = nil
    end)

    it("help tooltips: a tab's title (binding suffix kept) and help line; the status word nests",
      function()
        Social.hover(_G.FriendsFrameTab1, { "Friends |cffffd200(O)|r", UI.NEWBIE_TOOLTIP_FRIENDSTAB[1] })
        assert.are.equal("フレンド |cffffd200(O)|r", _G.GameTooltipTextLeft1:GetText())
        assert.are.equal(UI.NEWBIE_TOOLTIP_FRIENDSTAB[2], _G.GameTooltipTextLeft2:GetText())
        Social.hover(_G.FriendsFrameStatusDropdown, { "Status: |cffffffffAway|r" })
        assert.are.equal("ステータス: |cffffffff離席|r", _G.GameTooltipTextLeft1:GetText())
      end)

    it("the invite header and each pooled invite row's Accept translate through their own initializers",
      function()
        Social.invites = { "Accept", "Jaina#1234" } -- an account named like a UI word stays as written
        local header = Social.buildInvites()
        assert.are.equal("フレンドリクエスト (2)", header:GetText())
        assert.are.equal("承認", Social.inviteButtons[1].AcceptButton:GetText())
        assert.are.equal("承認", Social.inviteButtons[2].AcceptButton:GetText())
        assert.are.equal("Accept", Social.inviteButtons[1].Name:GetText())
        assert.is_true(unrecorded(Social.inviteButtons[1].Name))
        Social.invites = { "Thrall#1" } -- the list rebuilds: the reused header shows its new count
        Social.buildInvites()
        assert.are.equal("フレンドリクエスト (1)", header:GetText())
        alt(true)
        assert.are.equal("Friend Requests (1)", header:GetText())
        alt(false)
        assert.are.equal(1, #Stub.hooks.FriendsFrame_UpdateFriendInviteHeaderButton)
        assert.are.equal(1, #Stub.hooks.FriendsFrame_UpdateFriendInviteButton)
      end)

    it("the who list waits for Blizzard_GroupFinder_VanillaStyle's ADDON_LOADED", function()
      Social.loadWhoList() -- the frames exist now; the addon's ADDON_LOADED is forwarded next
      assert.are.equal(UI.WHO_LIST_SEARCH_INSTRUCTIONS[1], _G.WhoFrameEditBox.Instructions:GetText())
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
      assert.are.equal(UI.WHO_LIST_SEARCH_INSTRUCTIONS[2], _G.WhoFrameEditBox.Instructions:GetText())
      Social.who = { total = 2, rows = { { name = "Zone", level = 12, class = "Warrior", zone = "Zone" },
        { name = "Thrall", level = 60, class = "Shaman", zone = "Orgrimmar" } } }
      _G.LFGWhoListFrame:UpdateWhoList()
      assert.are.equal("該当 2人  ", _G.LFGWhoListFrame.WhoFrameTotals:GetText())
      assert.are.equal("レベル 12", Social.whoRows[1].Level:GetText())
      assert.are.equal("レベル 60", Social.whoRows[2].Level:GetText())
      assert.are.equal("Zone", Social.whoRows[1].Name:GetText())
      assert.are.equal("Warrior", Social.whoRows[1].Class:GetText())
      assert.are.equal("Zone", Social.whoRows[1].Variable:GetText())
      for _, part in ipairs({ "Name", "Race", "Class", "Variable", "GuildName" }) do
        assert.is_true(unrecorded(Social.whoRows[1][part]), part)
      end
      assert.is_true(unrecorded(_G.WhoFrameEditBox))
      assert.are.equal(1, #Stub.hooks["LFGWhoListFrame:UpdateWhoList"])
      -- the row's tooltip (name, level, zone): only the level line translates
      Social.hover(Social.whoRows[2], { "Thrall", "Level 60", "Zone" })
      assert.are.equal("Thrall", _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("レベル 60", _G.GameTooltipTextLeft2:GetText())
      assert.are.equal("Zone", _G.GameTooltipTextLeft3:GetText())
    end)
  end)

  describe("the who list's invite button and filter menu", function()
    local M = require("tests.lua.spec.menu_stub")

    before_each(function()
      _G.Menu = { ModifyMenu = function() end }
      setup(true, MENU_FILES)
      WFJ.Menus.init()
    end)

    after_each(function() _G.Menu = nil end)

    it("the invite button's tooltip translates; Alt shows English", function()
      Social.who = { total = 1, rows = { { name = "Thrall", level = 60, class = "Shaman", zone = "Orgrimmar" } } }
      _G.LFGWhoListFrame:UpdateWhoList()
      Social.hover(Social.whoRows[1].InviteButton, { "Invite to Group" })
      assert.are.equal("グループに招待", _G.GameTooltipTextLeft1:GetText())
      alt(true)
      assert.are.equal("Invite to Group", _G.GameTooltipTextLeft1:GetText())
      alt(false)
    end)

    it("the filter menu's section and sort entries translate; class, race and zone names stay", function()
      -- LFGWhoListFilterUtil.SetupFilterMenu (wholist.lua:316–321): Class / Race / Zone submenus, then Sort By
      local root = M.element(nil)
      local class = root:CreateButton("Class")
      class:CreateButton("Check All")
      class:CreateButton("Warrior") -- a class name (a dictionary word here): never matched
      local race = root:CreateButton("Race")
      race:CreateButton("Human")
      local zone = root:CreateButton("Zone")
      zone:CreateButton("Orgrimmar")
      local sort = root:CreateButton("Sort By")
      sort:CreateButton("Name")
      sort:CreateButton("Ascending")
      sort:CreateButton("Descending")
      _G.LFGWhoListFrame.FilterDropdown:RegisterMenu(root)
      local frames = M.open(root)
      local function text(e) return frames[e].fontString:GetText() end
      assert.are.equal("クラス", text(class))
      assert.are.equal("すべてチェック", text(class.children[1]))
      assert.are.equal("Warrior", text(class.children[2]))
      assert.are.equal("種族", text(race))
      assert.are.equal("Human", text(race.children[1]))
      assert.are.equal("ゾーン", text(zone))
      assert.are.equal("Orgrimmar", text(zone.children[1]))
      assert.are.equal("並べ替え", text(sort))
      assert.are.equal("名前", text(sort.children[1]))
      assert.are.equal("昇順", text(sort.children[2]))
      assert.are.equal("降順", text(sort.children[3]))
      alt(true)
      assert.are.equal("Sort By", text(sort))
      assert.are.equal("Ascending", text(sort.children[2]))
      alt(false)
    end)
  end)

  describe("who list already loaded", function()
    before_each(function() setup(true) end)

    it("is set up at init; a reused row shows its new level; Alt shows the English", function()
      assert.are.equal(UI.WHO_LIST_SEARCH_INSTRUCTIONS[2], _G.WhoFrameEditBox.Instructions:GetText())
      Social.who = { total = 60, rows = { { name = "Jaina", level = 20, class = "Mage", zone = "Theramore" } } }
      _G.LFGWhoListFrame:UpdateWhoList()
      assert.are.equal("該当 60人  (50人表示)", _G.LFGWhoListFrame.WhoFrameTotals:GetText())
      assert.are.equal("レベル 20", Social.whoRows[1].Level:GetText())
      Social.who.rows[1].level = 21
      _G.LFGWhoListFrame:UpdateWhoList()
      assert.are.equal("レベル 21", Social.whoRows[1].Level:GetText())
      alt(true)
      assert.are.equal("Level 21", Social.whoRows[1].Level:GetText())
      assert.are.equal("60 |4Person:People; Found  (50 displayed)", _G.LFGWhoListFrame.WhoFrameTotals:GetText())
      alt(false)
      assert.are.equal("レベル 21", Social.whoRows[1].Level:GetText())
      assert.are.equal(0, WFJ.LoadOnDemand.loaded(ADDON)) -- nothing left waiting
    end)
  end)
end)
