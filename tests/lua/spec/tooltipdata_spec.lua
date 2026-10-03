-- UI/TooltipData.lua: the tooltip-data kinds no other module handles (a currency here) are walked from line 2 on,
-- the name on line 1 left English, and keep following the modifier until the tooltip hides.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  CHARACTER_BUTTON = { "Character Info", "キャラクター情報" },
  TANK = { "Tank", "タンク" },
  ["FlyoutName:248"] = { "Portal", "ポータル" },
  ["FlyoutDescription:248"] = { "Creates a portal to a major city.", "主要都市へのポータルを作り出します。" },
}

describe("UI/TooltipData", function()
  local WFJ, tt, posts
  local function left(i) return _G["GameTooltipTextLeft" .. i] end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    posts = {}
    _G.Enum.TooltipDataType = { Currency = 5, Mount = 10, Totem = 18, Flyout = 22 }
    _G.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) posts[kind] = fn end }
    WFJ = H.loadChunks(H.UI_FILES)
    H.loadChunks({ "UI/TooltipData.lua" }, WFJ)
    H.uiSetup(WFJ, UI)
    tt = _G.GameTooltip
  end)

  after_each(function() _G.TooltipDataProcessor = nil; H.uiTeardown() end)

  it("registers a post-call per kind the client has, and walks line 2 on, the name on line 1 kept", function()
    assert.is_true(WFJ.TooltipData.init())
    assert.is_function(posts[5]); assert.is_function(posts[10]); assert.is_function(posts[18])
    tt:SetOwner(Stub.button("TokenRow", ""))
    tt:SetText("Tank") -- a name that happens to be a dictionary word
    tt:AddLine("Character Info")
    tt.primaryInfo = { tooltipData = { type = 5 } } -- built from Currency data
    posts[5](tt)
    assert.are.equal("Tank", left(1):GetText())
    assert.are.equal("キャラクター情報", left(2):GetText())
    tt:Show() -- the client's Show after the post-call: still ours
    assert.are.equal("キャラクター情報", left(2):GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Character Info", left(2):GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("キャラクター情報", left(2):GetText())
    -- the same owner writes a Lua tooltip without hiding: no tooltip data, so the adoption ends
    tt.primaryInfo = nil
    tt:SetText("Tank"); tt:AddLine("Character Info"); tt:Show()
    assert.are.equal("Character Info", left(2):GetText())
    tt:Hide() -- released: the next owner's tooltip is not adopted
    tt:SetOwner(Stub.button("Other", ""))
    tt:SetText("Character Info")
    tt:Show()
    assert.are.equal("Character Info", left(1):GetText())
  end)

  it("a flyout's tooltip: its name and description in their own families, line 1 included", function()
    WFJ.TooltipData.init()
    tt:SetOwner(Stub.button("FlyoutButton", ""))
    tt:SetText("Portal")
    tt:AddLine("Creates a portal to a major city.")
    tt:AddLine("Character Info") -- an open dictionary word: not a flyout row, left as written
    tt.primaryInfo = { tooltipData = { type = 22 } }
    posts[22](tt)
    assert.are.equal("ポータル", left(1):GetText())
    assert.are.equal("主要都市へのポータルを作り出します。", left(2):GetText())
    assert.are.equal("Character Info", left(3):GetText())
  end)

  it("ignores a tooltip other than GameTooltip and a client without the processor", function()
    WFJ.TooltipData.init()
    assert.are.equal(0, WFJ.TooltipData.walk({}))
    _G.TooltipDataProcessor = nil
    assert.is_false(WFJ.TooltipData.init())
  end)
end)
