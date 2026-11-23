-- Recent allies: UI/RecentAllies.lua over RecentAlliesFrame.List replayed from camelot
-- blizzard_recentallies (blizzard_recentalliestemplates.lua:153–225, 367–380, 406–418; rows are pooled ScrollBox
-- frames). Every name, location and activity description stays English.
local S = require("tests.lua.spec.stub_camelot_social")
local Stub = require("tests.lua.spec.wow_stub")

local M = require("tests.lua.spec.menu_stub")

local FILES = S.files("Core/Placeholders.lua", "UI/SettingsKeys.lua", "UI/Menus.lua", "UI/MenusTags.lua",
  "UI/MenusUntagged.lua", "UI/RecentAllies.lua", "UI/SocialUI.lua")

local UI = {
  RECENT_ALLY_RECENT_ACTIVITIES_LABEL = { "Recent Activities", "最近のアクティビティ" },
  RECENT_ALLY_INTERACTION_TIME_FORMAT = { "%s ago", "%s前" },
  RECENT_ALLIES_PARTY_BUTTON_TOOLTIP = { "Invite to Group", "グループに招待" },
  RECENT_ALLIES_PARTY_BUTTON_OFFLINE_TOOLTIP = { "Player Offline", "プレイヤーはオフラインです" },
  RECENT_ALLY_PIN_TOOLTIP = { "Pinned Ally", "ピン留めした仲間" },
  RECENT_ALLY_PIN_EXPIRING_TOOLTIP = { "Pinned Ally (Expires in %s)", "ピン留めした仲間 (%s後に期限切れ)" },
  CLOSE = { "Close", "閉じる" },
  RECENT_ALLY_TOOLTIP_LEVEL_RACE_FORMAT = { "Level %d  %s  %s", "レベル%d  %s  %s" },
  -- client-table rows (fingerprints: no global; ADR-042): RolodexType's two text columns
  ["RecentAllyType:1"] = { "Party Member", "パーティメンバー" },
  ["RecentAllyInteraction:11"] = { "Fought Together", "共闘した" },
  ["CurrencyCategory:9"] = { "Miscellaneous", "その他" }, -- another family: never an activity
  -- the newer social window's card view
  SOCIAL_UI_RECENT_ALLIES_ADD_FRIEND_BUTTON_LABEL = { "Add New Friend", "新しいフレンドを追加" },
  ADDING_FRIENDS_DISABLED = { "Adding friends is disabled.", "フレンドの追加は無効です。" },
  SOCIAL_UI_SEARCH_BOX_INSTRUCTIONS = { "Search for keywords", "キーワードで検索" },
  FILTER = { "Filter", "フィルター" },
  SOCIAL_UI_RECENT_ALLIES_VIEW_HEADER_PINNED = { "Pinned %d/%d", "ピン留め %d/%d" },
  SOCIAL_UI_RECENT_ALLIES_CARD_LEVEL_DISPLAY_FORMAT = { "Lvl %d", "Lv%d" },
  SOCIAL_UI_RECENT_ALLIES_TOOLTIP_LEVEL_CLASS_FORMAT = { "Level %d %s", "レベル %d %s" },
  SOCIAL_UI_RECENT_ALLIES_FRIEND_REQUEST_SENT_TOOLTIP = { "Friend request sent", "フレンド申請を送信しました" },
  SOCIAL_FILTER_DROPDOWN_STATUS = { "Status", "状態" },
  SOCIAL_UI_PRESENCE_TYPE_LABEL_AWAY = { "Away", "離席" },
  RECENT_ALLIES_CATEGORIES_FILTER_LABEL = { "Categories", "カテゴリー" },
  SOCIAL_UI_BATTLE_NET_FRIEND_TAG_LABEL_DUNGEONS = { "Dungeons", "ダンジョン" },
}
-- Core/UIStrings: both time arguments are SecondsFormatter output
local NEEDS = { ARGS = { RECENT_ALLY_INTERACTION_TIME_FORMAT = { [1] = "time" },
  RECENT_ALLY_PIN_EXPIRING_TOOLTIP = { [1] = "time" } } }

local C = {}

local function install(o)
  o = o or {}
  local friends = S.frame("FriendsFrame")
  if not o.untitled then function friends.SetTitle() end end
  local frame = S.frame("RecentAlliesFrame")
  frame.List = S.frame(nil, "List")
  frame.List.ScrollBox = Stub.scrollBox()
  function C.row(existing, activity)
    local row = existing or CreateFrame("Button")
    row.CharacterData = { Name = S.fs("Close"), Level = S.fs("60"), Class = S.fs("Close"), Location = S.fs("Close"),
      MostRecentInteraction = S.fs(activity or "Close") }
    row.PartyButton = S.frame()
    row.StateIconContainer = { PinDisplay = S.frame() }
    frame.List.ScrollBox:initFrame(row, {})
    return row
  end
end

describe("the recent allies panel on Forever", function()
  local WFJ
  before_each(function() WFJ = S.load(FILES, UI, NEEDS) end)
  after_each(function() S.teardown({ "FriendsFrame", "RecentAlliesFrame" }) end)

  it("row tooltips: the fixed lines translate; name, race, class, location and activity lines do not", function()
    install()
    local early = C.row() -- a row that exists before the surface starts (the iterateExisting pass)
    assert.is_true(WFJ.RecentAllies.init())
    for _, row in ipairs({ early, C.row() }) do
      local lines = S.tooltip(row, { "Close", "Close", "Close", "Close", " ", { "Recent Activities", "3 Hrs ago" },
        "Close" })
      assert.are.same({ "Close", "Close", "Close", "Close", " ", "最近のアクティビティ", "Close" }, lines)
      assert.are.equal("3 Hrs前", S.tooltipRight(6))
      assert.are.same({ "グループに招待", "プレイヤーはオフラインです" },
        S.tooltip(row.PartyButton, { "Invite to Group", "Player Offline" }))
      assert.are.same({ "ピン留めした仲間 (2 Days後に期限切れ)" },
        S.tooltip(row.StateIconContainer.PinDisplay, { "Pinned Ally (Expires in 2 Days)" }))
      assert.are.same({ "ピン留めした仲間" }, S.tooltip(row.StateIconContainer.PinDisplay, { "Pinned Ally" }))
    end
  end)

  it("the level / race line translates with the atlas divider and the race name kept", function()
    install()
    WFJ.RecentAllies.init()
    local row = C.row()
    local divider = "|A:charactercreate-customize-dropdown-linemouseover-middle:1:10|a"
    assert.are.same({ "Close", "レベル60  " .. divider .. "  Night Elf" },
      S.tooltip(row, { "Close", "Level 60  " .. divider .. "  Night Elf" }))
    S.alt(WFJ, true)
    assert.are.equal("Level 60  " .. divider .. "  Night Elf", _G.GameTooltipTextLeft2:GetText())
    S.alt(WFJ, false)
  end)

  it("a row's last activity shows its RolodexType text in Japanese, either column; Alt shows the English", function()
    install()
    WFJ.RecentAllies.init()
    local party, fought = C.row(nil, "Party Member"), C.row(nil, "Fought Together")
    assert.are.equal("パーティメンバー", party.CharacterData.MostRecentInteraction:GetText())
    assert.are.equal("共闘した", fought.CharacterData.MostRecentInteraction:GetText())
    S.alt(WFJ, true)
    assert.are.equal("Party Member", party.CharacterData.MostRecentInteraction:GetText())
    assert.are.equal("Fought Together", fought.CharacterData.MostRecentInteraction:GetText())
    S.alt(WFJ, false)
    assert.are.equal("パーティメンバー", party.CharacterData.MostRecentInteraction:GetText())
    C.row(party, "Whispered") -- the pooled row reused: an activity with no row stays as written
    S.alt(WFJ, true)
    S.alt(WFJ, false)
    assert.are.equal("Whispered", party.CharacterData.MostRecentInteraction:GetText())
    assert.is_nil(WFJ.UIIndex:match("Party Member")) -- the families only where the widget names them
  end)

  it("an activity that is a dictionary word, another family's word or empty stays as written", function()
    install()
    WFJ.RecentAllies.init()
    for _, text in ipairs({ "Close", "Miscellaneous", "" }) do
      local row = C.row(nil, text)
      assert.are.equal(text, row.CharacterData.MostRecentInteraction:GetText())
      assert.is_true(S.unrecorded(WFJ, row.CharacterData.MostRecentInteraction))
    end
  end)

  it("the row tooltip's activity line translates; the same word on the party button's tooltip does not",
    function()
    install()
    WFJ.RecentAllies.init()
    local row = C.row(nil, "Fought Together")
    local lines = S.tooltip(row, { "Close-Realm", "Close", " ", { "Recent Activities", "3 Hrs ago" },
      "Fought Together" })
    assert.are.same({ "Close-Realm", "Close", " ", "最近のアクティビティ", "共闘した" }, lines)
    S.alt(WFJ, true)
    assert.are.equal("Fought Together", _G.GameTooltipTextLeft5:GetText())
    S.alt(WFJ, false)
    assert.are.same({ "Party Member" }, S.tooltip(row.PartyButton, { "Party Member" }))
  end)

  it("a row's name, class and location widgets can never take a record", function()
    install()
    WFJ.RecentAllies.init()
    local row = C.row()
    for _, key in ipairs({ "Name", "Class", "Location" }) do
      assert.are.equal(0, WFJ.Labels.show("recentallies", "probe", row.CharacterData[key]))
      assert.are.equal("Close", row.CharacterData[key]:GetText())
      assert.is_true(S.unrecorded(WFJ, row.CharacterData[key]))
    end
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    install()
    _G.RecentAlliesFrame.List.ScrollBox = Stub.scrollBox()
    assert.is_true(WFJ.RecentAllies.init())
    local box = _G.RecentAlliesFrame.List.ScrollBox
    assert.has_no.errors(function()
      box:initFrame({ CharacterData = 4, PartyButton = "?", StateIconContainer = true }, {})
    end)
    S.teardown({ "RecentAlliesFrame" })
    install()
    _G.RecentAlliesFrame.List = "?"
    WFJ = S.load(FILES, UI, NEEDS)
    install()
    _G.RecentAlliesFrame.List.ScrollBox = 9
    assert.has_no.errors(function() assert.is_false(WFJ.RecentAllies.init()) end)
  end)

  it("without the mainline social window init returns false and registers nothing", function()
    assert.is_false(WFJ.RecentAllies.init())
    install({ untitled = true })
    assert.is_false(WFJ.RecentAllies.init())
    assert.are.equal(0, #_G.RecentAlliesFrame.List.ScrollBox.initCallbacks)
    install()
    assert.is_true(WFJ.RecentAllies.init())
    assert.is_false(WFJ.RecentAllies.init()) -- once
    assert.are.equal(1, #_G.RecentAlliesFrame.List.ScrollBox.initCallbacks)
  end)
end)

-- The Recent Allies tab of the newer social window: SocialUIFrame.RecentAlliesList replayed from
-- blizzard_recentalliestemplates.lua:425–907 (RecentAlliesSocialView*, RecentAlliesSocialCard*) over the contacts
-- frame of blizzard_socialuishared/socialuisharedtemplates.xml:99–176. A character's name stays as written.
describe("the recent allies card view of the social window", function()
  local WFJ, view
  local GREY, WHITE = "|cff808080", "|cffffffff"

  local function installView()
    local frame = S.frame("SocialUIFrame")
    view = S.put(frame, "RecentAlliesList", S.frame(nil, "RecentAlliesList"))
    view.ActionButton = S.button(nil, "Add New Friend")
    view.ScrollBox = Stub.scrollBox()
    S.put(view, "FilterBar.SearchBar.Instructions", S.fs("Search for keywords"))
    S.put(view, "FilterBar.SearchFilterDropdown", S.dropdown("filter")):SetDefaultText("Filter")
  end
  -- a card as RecentAlliesSocialCardMixin:Initialize leaves it (:739–846)
  local function card(existing, ally)
    local row = existing or CreateFrame("Button")
    for _, key in ipairs({ "Name", "Level", "Class", "MostRecentInteraction", "Location" }) do
      row[key] = row[key] or S.fs("")
    end
    row.PartyButton = row.PartyButton or S.frame()
    row.StateDisplay = row.StateDisplay or { PinDisplay = S.frame(), FriendRequestSentDisplay = S.frame() }
    row.ShowTooltip = row.ShowTooltip or function(c) -- ShowTooltip → BuildTooltip (:1058–1070)
      local tt = _G.GameTooltip
      tt:SetOwner(c)
      tt:ClearLines()
      for _, line in ipairs(c.tooltipLines or {}) do
        if type(line) == "table" then tt:AddDoubleLine(line[1], line[2]) else tt:AddLine(line) end
      end
      tt:Show()
    end
    view.ScrollBox:initFrame(row, {}, function()
      row.Name.text = WHITE .. ally.name .. "|r"
      row.Level.text = WHITE .. "Lvl " .. ally.level .. "|r"
      row.Class.text = "|cffc79c6e" .. ally.class .. "|r"
      row.MostRecentInteraction.text = GREY .. ally.activity .. "|r"
      row.Location.text = GREY .. ally.location .. "|r"
    end)
    row.elementData = { stateData = { currentLocation = ally.location ~= "" and ally.location or nil } }
    return row
  end
  local function hover(row, lines)
    row.tooltipLines = lines
    row:ShowTooltip()
    local out = {}
    for i = 1, #lines do out[i] = _G["GameTooltipTextLeft" .. i]:GetText() end
    return out
  end

  before_each(function()
    WFJ = S.load(FILES, UI, NEEDS)
    WFJ.UIStrings.word = function(text) return WFJ.State.names and WFJ.Placeholders.wordFor(text) or nil end
    WFJ.Data.add("name", { [WFJ.Names.key("Stormwind City")] = "ストームウィンド・シティ\tすとーむうぃんど・してぃ",
      [WFJ.Names.key("Alliance")] = "アライアンス\tあらいあんす", [WFJ.Names.key("Warrior")] = "ウォリアー\tうぉりあー",
      [WFJ.Names.key("Human")] = "ヒューマン\tひゅーまん", [WFJ.Names.key("Thrall")] = "スロール\tすろーる" })
    installView()
  end)
  after_each(function()
    WFJ.UIStrings.word = nil
    WFJ.State.setNames(false)
    S.teardown({ "SocialUIFrame", "EventRegistry" })
  end)

  it("is set up with no older panel; its button, search prompt and filter text translate; the reveal key shows"
    .. " the English", function()
    assert.is_true(WFJ.RecentAllies.init())
    assert.is_false(WFJ.RecentAllies.init()) -- once
    assert.are.equal("新しいフレンドを追加", view.ActionButton:GetText())
    assert.are.equal("キーワードで検索", view.FilterBar.SearchBar.Instructions:GetText())
    assert.are.equal("フィルター", view.FilterBar.SearchFilterDropdown.Text:GetText())
    assert.are.same({ "フレンドの追加は無効です。" }, S.tooltip(view.ActionButton, { "Adding friends is disabled." }))
    S.alt(WFJ, true)
    assert.are.equal("Add New Friend", view.ActionButton:GetText())
    S.alt(WFJ, false)
    view.FilterBar.SearchFilterDropdown:UpdateText() -- written again on every choice
    assert.are.equal("フィルター", view.FilterBar.SearchFilterDropdown.Text:GetText())
  end)

  it("a header, a card's level and its last activity translate; with Japanese names on its class and location show"
    .. " their Japanese; the character's name stays", function()
    WFJ.RecentAllies.init()
    local header = Stub.button(nil, "")
    header.ButtonText = S.fs("")
    view.ScrollBox:initFrame(header, {}, function() header.fontString.text = "Pinned 1/3" end)
    assert.are.equal("ピン留め 1/3", header:GetText())
    WFJ.State.setNames(false)
    local ally = { name = "Thrall", level = 60, class = "Warrior", activity = "Fought Together",
      location = "Stormwind City" }
    local row = card(nil, ally)
    assert.are.equal(WHITE .. "Lv60|r", row.Level:GetText())
    assert.are.equal(GREY .. "共闘した|r", row.MostRecentInteraction:GetText())
    assert.are.equal("|cffc79c6eWarrior|r", row.Class:GetText()) -- names are off
    assert.are.equal(GREY .. "Stormwind City|r", row.Location:GetText())
    WFJ.State.setNames(true)
    card(row, ally)
    assert.are.equal("|cffc79c6eウォリアー|r", row.Class:GetText())
    assert.are.equal(GREY .. "ストームウィンド・シティ|r", row.Location:GetText())
    assert.are.equal(WHITE .. "Thrall|r", row.Name:GetText()) -- a player named like a game name
    assert.is_true(S.unrecorded(WFJ, row.Name))
    S.alt(WFJ, true)
    assert.are.equal(WHITE .. "Lvl 60|r", row.Level:GetText())
    assert.are.equal(GREY .. "Stormwind City|r", row.Location:GetText())
    S.alt(WFJ, false)
    -- the pooled card reused: an activity with no row and an empty location stay as written
    card(row, { name = "Kei", level = 12, class = "Tinker", activity = "Whispered", location = "" })
    assert.are.equal(GREY .. "Whispered|r", row.MostRecentInteraction:GetText())
    assert.are.equal("|cffc79c6eTinker|r", row.Class:GetText())
    assert.are.equal(WHITE .. "Lv12|r", row.Level:GetText())
  end)

  it("a card's tooltip: the level line, the activity lines and, with Japanese names on, the class, race, faction"
    .. " and location by their place; the character's name is never read", function()
    WFJ.RecentAllies.init()
    WFJ.SocialUI.init() -- the tooltip surface's release
    WFJ.State.setNames(true)
    local row = card(nil, { name = "Thrall", level = 60, class = "Warrior", activity = "Fought Together",
      location = "Stormwind City" })
    local english = { "Thrall-Stormwind City", " ", "Level 60 Warrior", "Human", "Alliance", "Stormwind City",
      "A note: Human", " ", { "Recent Activities", "3 Hrs ago" }, "Fought Together" }
    assert.are.same({ "Thrall-Stormwind City", " ", "レベル 60 ウォリアー", "人間", "アライアンス",
      "ストームウィンド・シティ", "A note: Human", " ", "最近のアクティビティ", "共闘した" }, hover(row, english))
    assert.are.equal("3 Hrs前", S.tooltipRight(9))
    S.alt(WFJ, true)
    assert.are.equal("Level 60 Warrior", _G.GameTooltipTextLeft3:GetText())
    assert.are.equal("Human", _G.GameTooltipTextLeft4:GetText())
    S.alt(WFJ, false)
    _G.GameTooltip:Hide()
    assert.is_nil(next(WFJ.SurfaceState.surfaces()["help.social"] or {}))
    -- no location in the card's data: line 6 is a note and is never read
    row.elementData.stateData.currentLocation = nil
    assert.are.same({ "Thrall", " ", "レベル 60 ウォリアー", "人間", "アライアンス", "Stormwind City" },
      hover(row, { "Thrall", " ", "Level 60 Warrior", "Human", "Alliance", "Stormwind City" }))
    -- names off: the level line is a dictionary line, the rest stays as written
    WFJ.State.setNames(false)
    assert.are.same({ "Thrall", " ", "レベル 60 Warrior", "Human", "Alliance" },
      hover(row, { "Thrall", " ", "Level 60 Warrior", "Human", "Alliance" }))
    -- its buttons
    assert.are.same({ "グループに招待", "プレイヤーはオフラインです" },
      S.tooltip(row.PartyButton, { "Invite to Group", "Player Offline" }))
    assert.are.same({ "ピン留めした仲間" }, S.tooltip(row.StateDisplay.PinDisplay, { "Pinned Ally" }))
    assert.are.same({ "フレンド申請を送信しました" },
      S.tooltip(row.StateDisplay.FriendRequestSentDisplay, { "Friend request sent" }))
    assert.are.equal(0, WFJ.RecentAllies.onCardTooltip("x"))
  end)

  it("the filter dropdown's menu translates its words once shown", function()
    local registry = M.registry()
    WFJ.RecentAllies.init()
    WFJ.Menus.init()
    local root = M.element(nil)
    local status = root:CreateButton("Status")
    local away = status:CreateButton("Away")
    local categories = root:CreateButton("Categories")
    local dungeons = categories:CreateButton("Dungeons")
    local frames = M.open(registry, nil, root, nil, view.FilterBar.SearchFilterDropdown)
    assert.are.equal("状態", frames[status].fontString:GetText())
    assert.are.equal("離席", frames[away].fontString:GetText())
    assert.are.equal("カテゴリー", frames[categories].fontString:GetText())
    assert.are.equal("ダンジョン", frames[dungeons].fontString:GetText())
  end)

  it("wrong shapes raise nothing", function()
    view.ScrollBox = 9
    assert.has_no.errors(function() assert.is_true(WFJ.RecentAllies.init()) end)
    assert.has_no.errors(function()
      WFJ.RecentAllies.onViewRow({ MostRecentInteraction = S.fs("x"), Level = 3, StateDisplay = "?" })
      WFJ.RecentAllies.onViewRow(7)
    end)
  end)
end)
