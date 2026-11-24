-- UI/Currency: the detail pane's Title is the selected currency's name (TokenDetailFrameMixin:Refresh →
-- SetPaneTitle(name, icon .. " " .. quantity), blizzard_tokenui/camelot/blizzard_tokenui.lua:524–533;
-- blizzard_uipanels_game/camelot/characterframe.lua:845–849) and each list entry's Content.Name is a currency's name
-- (TokenEntryMixin:Initialize, blizzard_tokenui.lua:51–56). While names are on each shows the name's Japanese where
-- the name list has it; the Subtitle (an icon and a count) is unchanged.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Currency.lua"

describe("UI/Currency's currency names", function()
  local WFJ, frame, detail, selected

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function entry(name)
    local e = CreateFrame("Button")
    e.Content = { Name = Stub.fontString("") }
    function e.Initialize(self, data) self.Content.Name:SetText(data.name) end
    e:Initialize({ name = name })
    return e
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    frame = CreateFrame("Frame", "TokenFrame")
    frame.ScrollBox = Stub.scrollBox()
    detail = CreateFrame("Frame", "TokenDetailFrame")
    detail.Title, detail.Subtitle = Stub.fontString(""), Stub.fontString("")
    selected = nil
    function detail.Refresh(self)
      if not selected then return end
      self.Title:SetText(selected.name)
      self.Subtitle:SetText("|T123:16:16|t " .. selected.quantity)
    end
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, {})
    WFJ.Data.add("name", {
      [WFJ.Names.key("Badge of Justice")] = "バッジ・オブ・ジャスティス\tばっじ・おぶ・じゃすてぃす",
    })
    WFJ.State.setNames(true)
    assert.is_true(WFJ.Currency.init())
    frame:Show()
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.TokenFrame, _G.TokenDetailFrame = nil, nil
  end)

  it("the detail pane's title shows the name's Japanese; the count stays; reveal and closing give it back", function()
    selected = { name = "Badge of Justice", quantity = "12" }
    detail:Refresh()
    assert.are.equal("バッジ・オブ・ジャスティス", detail.Title:GetText())
    assert.are.equal("|T123:16:16|t 12", detail.Subtitle:GetText())
    assert.are.equal(0, detail.Subtitle.calls.addonSetText)
    alt(true)
    assert.are.equal("Badge of Justice", detail.Title:GetText())
    alt(false)
    frame:Hide()
    assert.are.equal("Badge of Justice", detail.Title:GetText())
    frame:Show() -- the tab opens again on the same currency
    assert.are.equal("バッジ・オブ・ジャスティス", detail.Title:GetText())
  end)

  it("a list entry's name shows its Japanese; a name the list does not hold stays", function()
    local known, unknown = entry("Badge of Justice"), entry("Honor Points")
    frame.ScrollBox:initFrame(known, {})
    frame.ScrollBox:initFrame(unknown, {})
    assert.are.equal("バッジ・オブ・ジャスティス", known.Content.Name:GetText())
    assert.are.equal("Honor Points", unknown.Content.Name:GetText())
    assert.are.equal(0, unknown.Content.Name.calls.addonSetText)
    alt(true)
    assert.are.equal("Badge of Justice", known.Content.Name:GetText())
    alt(false)
  end)

  it("with names off nothing is written", function()
    WFJ.State.setNames(false)
    selected = { name = "Badge of Justice", quantity = "1" }
    detail:Refresh()
    local e = entry("Badge of Justice")
    frame.ScrollBox:initFrame(e, {})
    assert.are.equal(0, detail.Title.calls.addonSetText)
    assert.are.equal(0, e.Content.Name.calls.addonSetText)
  end)
end)
