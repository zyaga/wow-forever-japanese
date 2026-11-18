-- UI/SocialUI.lua over a SocialUIFrame replayed from blizzard_socialui/mainline (socialui.lua, socialuitemplates.*),
-- blizzard_socialuishared (socialuisharedtemplates.*) and blizzard_friendsframe/mainline/friendslisttemplates.*.
-- A friend's name, character and class, a place and the names in the ignore list stay as the client wrote them.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/CommunitiesKit.lua"
FILES[#FILES + 1] = "UI/SocialUI.lua"

local UI = {
  SOCIAL_UI_FRIENDS_TAB_NAME = { "Friends", "フレンド" },
  SOCIAL_UI_RECENT_ALLIES_TAB_NAME = { "Recent Allies", "最近の仲間" },
  SOCIAL_UI_IGNORE_LIST_TITLE = { "Ignore List", "無視リスト" },
  SOCIAL_UI_FRIENDS_LIST_ADD_FRIEND_BUTTON_LABEL = { "Add New Friend", "フレンドを追加" },
  SOCIAL_UI_SEARCH_BOX_INSTRUCTIONS = { "Search for keywords", "キーワードで検索" },
  FILTER = { "Filter", "フィルター" },
  SOCIAL_UI_FAVORITE_FRIENDS_LIST_HEADER = { "Favorites %d/%d", "お気に入り %d/%d" },
  SOCIAL_UI_FRIENDS_LIST_HEADER = { "Friends List %d/%d", "フレンドリスト %d/%d" },
  FRIENDS_LIST_OFFLINE = { "Offline", "オフライン" },
  LASTONLINE_DAYS = { "%d |4day:days;", "%d日" },
  SOCIAL_UI_BATTLENET_BROADCAST_FRAME_HEADER = { "Broadcast", "ブロードキャスト" },
  SOCIAL_UI_BATTLENET_BROADCAST_UPDATE_BUTTON_LABEL = { "Update", "更新" },
  SOCIAL_UI_IGNORE_LIST_BLOCK_BUTTON_LABEL = { "Ignore Player", "プレイヤーを無視" },
  SOCIAL_UI_IGNORE_LIST_IGNORE_HEADER = { "Ignored", "無視中" },
  SOCIAL_UI_BATTLE_NET_UNAVAILABLE_NOTICE = { "Blizzard services are unavailable.", "Blizzardサービスは利用できません。" },
}

local C = {}

local function en(key) return _G[key] end
local function fs(text) return Stub.fontString(text or "") end

-- SocialUIFrame as the client builds it at login: the window with its Battle.net bar, broadcast frame and ignore
-- list (socialui.xml:9–38); the friends list is created with its tab (socialui.lua:118–128, 185–186).
local function loadWindow()
  local frame = CreateFrame("Frame", "SocialUIFrame")
  frame.TitleContainer = { TitleText = fs() }
  function frame.SetTitle(self, title) self.TitleContainer.TitleText:SetText(title) end
  function frame.RefreshVisuals(self) self:SetTitle(en(C.tab)) end -- RefreshTitle, lua:626–629
  frame.BattleNetBar = { ControlsContainer = { PersonalBattleTagDisplay = { DisplayText = fs("Player#1234") } } }
  frame.BattleNetBroadcastFrame = { Title = fs(en("SOCIAL_UI_BATTLENET_BROADCAST_FRAME_HEADER")),
    UpdateButton = Stub.button(nil, en("SOCIAL_UI_BATTLENET_BROADCAST_UPDATE_BUTTON_LABEL")) }
  local ignore = CreateFrame("Frame")
  frame.IgnoreListFrame = ignore
  ignore.TitleContainer = { TitleText = fs() }
  function ignore.SetTitle(self, title) self.TitleContainer.TitleText:SetText(title) end
  ignore.BlockButton = Stub.button(nil, en("SOCIAL_UI_IGNORE_LIST_BLOCK_BUTTON_LABEL"))
  ignore.ScrollBox = Stub.scrollBox()
  function C.ignoreRow(data)
    local row = CreateFrame("Frame")
    row.Text = fs()
    ignore.ScrollBox:initFrame(row, data, function(r, d) r.Text:SetText(d.headerText or d.name) end)
    return row
  end
  -- the Friends tab is made: the list with its button, filter bar and rows
  function C.makeList()
    local list = CreateFrame("Frame")
    frame.FriendsList = list
    list.ActionButton = Stub.button(nil, en("SOCIAL_UI_FRIENDS_LIST_ADD_FRIEND_BUTTON_LABEL"))
    local dropdown = CreateFrame("DropdownButton")
    dropdown.Text = fs(en("FILTER"))
    function dropdown.UpdateText(self) self.Text:SetText(en("FILTER")) end
    local search = CreateFrame("EditBox")
    search.Instructions = fs(en("SOCIAL_UI_SEARCH_BOX_INSTRUCTIONS"))
    list.FilterBar = { SearchFilterDropdown = dropdown, SearchBar = search }
    list.ScrollBox = Stub.scrollBox()
    C.rows = {}
    function C.row(i, data)
      local row = C.rows[i]
      if not row then
        row = CreateFrame("Button")
        C.rows[i] = row
      end
      list.ScrollBox:initFrame(row, data, function(r, d)
        r.ButtonText, r.Location, r.Class, r.RefreshLocationDisplayText = nil, nil, nil, nil
        if d.headerText then
          r.ButtonText = r.header or fs()
          r.header = r.ButtonText
          r.ButtonText:SetText(d.headerText)
        else
          r.Location, r.Class = r.location or fs(), r.class or fs()
          r.location, r.class = r.Location, r.Class
          r.Class:SetText(d.class)
          r.Location:SetText(d.location)
          r.RefreshLocationDisplayText = r.refresh or function(self) self.Location:SetText(self.next) end
          r.refresh = r.RefreshLocationDisplayText
        end
      end)
      return row
    end
    return list
  end
  C.frame = frame
  return frame
end

describe("the friends window the client shows while its social system is on", function()
  local WFJ

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    C.tab = "SOCIAL_UI_FRIENDS_TAB_NAME"
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.SocialUIFrame = nil
  end)

  it("a client without the window: init returns false and nothing is hooked", function()
    assert.is_false(WFJ.SocialUI.init())
  end)

  it("the title follows the selected tab; the ignore list has its own; a name is left as written", function()
    local frame = loadWindow()
    assert.is_true(WFJ.SocialUI.init())
    frame:RefreshVisuals()
    assert.are.equal("フレンド", frame.TitleContainer.TitleText:GetText())
    C.tab = "SOCIAL_UI_RECENT_ALLIES_TAB_NAME"
    frame:RefreshVisuals()
    assert.are.equal("最近の仲間", frame.TitleContainer.TitleText:GetText())
    frame.IgnoreListFrame:SetTitle(en("SOCIAL_UI_IGNORE_LIST_TITLE"))
    assert.are.equal("無視リスト", frame.IgnoreListFrame.TitleContainer.TitleText:GetText())
    frame:SetTitle("Offline") -- not a tab's name
    assert.are.equal("Offline", frame.TitleContainer.TitleText:GetText())
  end)

  it("the friends list made after login: its button, filter, search hint, headers and offline line", function()
    local frame = loadWindow()
    assert.is_true(WFJ.SocialUI.init())
    assert.are.equal("ブロードキャスト", frame.BattleNetBroadcastFrame.Title:GetText())
    assert.are.equal("更新", frame.BattleNetBroadcastFrame.UpdateButton:GetText())
    assert.are.equal("プレイヤーを無視", frame.IgnoreListFrame.BlockButton:GetText())
    local list = C.makeList()
    frame:RefreshVisuals() -- the tab is selected
    assert.are.equal("フレンドを追加", list.ActionButton:GetText())
    assert.are.equal("フィルター", list.FilterBar.SearchFilterDropdown.Text:GetText())
    assert.are.equal("キーワードで検索", list.FilterBar.SearchBar.Instructions:GetText())
    local header = C.row(1, { headerText = string.format(en("SOCIAL_UI_FRIENDS_LIST_HEADER"), 2, 9) })
    assert.are.equal("フレンドリスト 2/9", header.ButtonText:GetText())
    local card = C.row(2, { class = "Rogue", location = en("FRIENDS_LIST_OFFLINE") })
    assert.are.equal("オフライン", card.Location:GetText())
    assert.are.equal("Rogue", card.Class:GetText()) -- a class name
    card.next = "Stormwind City" -- the card refreshes its location without being drawn again
    card:RefreshLocationDisplayText()
    assert.are.equal("Stormwind City", card.Location:GetText())
    card.next = string.format(en("LASTONLINE_DAYS"), 3)
    card:RefreshLocationDisplayText()
    assert.are.equal("3日", card.Location:GetText())
    -- the same pooled row drawn as a header, then as a card again
    C.row(2, { headerText = string.format(en("SOCIAL_UI_FAVORITE_FRIENDS_LIST_HEADER"), 1, 1) })
    assert.are.equal("お気に入り 1/1", card.ButtonText:GetText())
  end)

  it("the Battle.net notice inside its colour code, and the ignore list's headers; an ignored name stays", function()
    local frame = loadWindow()
    local display = frame.BattleNetBar.ControlsContainer.PersonalBattleTagDisplay.DisplayText
    assert.is_true(WFJ.SocialUI.init())
    assert.are.equal("Player#1234", display:GetText()) -- a BattleTag
    display:SetText("|cffffd200" .. en("SOCIAL_UI_BATTLE_NET_UNAVAILABLE_NOTICE") .. "|r")
    frame:RefreshVisuals()
    assert.are.equal("|cffffd200Blizzardサービスは利用できません。|r", display:GetText())
    local header = C.ignoreRow({ headerText = en("SOCIAL_UI_IGNORE_LIST_IGNORE_HEADER") })
    assert.are.equal("無視中", header.Text:GetText())
    local entry = C.ignoreRow({ name = "Ignored" }) -- a player called like the header
    assert.are.equal("Ignored", entry.Text:GetText())
  end)

  it("holding the reveal key shows the English; hooks install once", function()
    local frame = loadWindow()
    assert.is_true(WFJ.SocialUI.init())
    assert.is_false(WFJ.SocialUI.setup())
    local list = C.makeList()
    frame:RefreshVisuals()
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Add New Friend", list.ActionButton:GetText())
    assert.are.equal("Friends", frame.TitleContainer.TitleText:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("フレンドを追加", list.ActionButton:GetText())
  end)
end)
