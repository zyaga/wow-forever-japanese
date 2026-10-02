-- Recent allies: UI/RecentAllies.lua over RecentAlliesFrame.List replayed from camelot
-- blizzard_recentallies (blizzard_recentalliestemplates.lua:153–225, 367–380, 406–418; rows are pooled ScrollBox
-- frames). Every name, location and activity description stays English.
local S = require("tests.lua.spec.stub_camelot_social")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = S.files("UI/RecentAllies.lua")

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
