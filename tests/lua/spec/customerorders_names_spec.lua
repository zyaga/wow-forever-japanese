-- UI/CustomerOrders: the form's RecipeName holds the ordered item's name. Form:Init's recipe loader writes it, measures
-- it (SetHeight(GetStringHeight())) and then calls Professions.SetupOutputIcon (blizzard_professionscustomerordersform
-- .lua:1120–1140). While names are on the name shows its Japanese, written only after that measure, so the client
-- measures its own English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/CustomerOrders.lua"

local ADDON = "Blizzard_ProfessionsCustomerOrders"

describe("UI/CustomerOrders' recipe name", function()
  local WFJ, frame, form, setups

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    setups = 0
    _G.Professions = { SetupOutputIcon = function() setups = setups + 1 end }
    Stub.loadedAddons[ADDON] = true
    frame = CreateFrame("Frame", "ProfessionsCustomerOrdersFrame")
    form = CreateFrame("Frame", nil, frame)
    frame.Form = form
    form.RecipeName = Stub.fontString("")
    form.OutputIcon = CreateFrame("Button")
    function form.Init(self, order) -- the recipe loader, run at once (the item's data cached)
      self.RecipeName:SetText(order.item)
      self.measured = self.RecipeName:GetText() -- SetHeight(GetStringHeight()), form.lua:1138
      _G.Professions.SetupOutputIcon(self.OutputIcon, {}, {})
    end
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, {})
    WFJ.Data.add("name", {
      [WFJ.Names.key("Linen Bandage")] = "リネン・バンデージ\tりねん・ばんでーじ",
      [WFJ.Names.key("Copper Bracers")] = "コッパー・ブレイサーズ\tこっぱー・ぶれいさーず",
    })
    WFJ.State.setNames(true)
    assert.is_true(WFJ.CustomerOrders.init())
    frame:Show()
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.ProfessionsCustomerOrdersFrame, _G.Professions = nil, nil
  end)

  it("the name shows its Japanese after the loader measured the English; reveal and closing give it back", function()
    form:Init({ item = "Linen Bandage" })
    assert.are.equal(1, setups) -- the client's own function still runs
    assert.are.equal("Linen Bandage", form.measured)
    assert.are.equal("リネン・バンデージ", form.RecipeName:GetText())
    alt(true)
    assert.are.equal("Linen Bandage", form.RecipeName:GetText())
    alt(false)
    assert.are.equal("リネン・バンデージ", form.RecipeName:GetText())
    frame:Hide()
    assert.are.equal("Linen Bandage", form.RecipeName:GetText())
  end)

  it("another order's name: the loader writes and measures its English first", function()
    form:Init({ item = "Linen Bandage" })
    form:Init({ item = "Copper Bracers" })
    assert.are.equal("Copper Bracers", form.measured)
    assert.are.equal("コッパー・ブレイサーズ", form.RecipeName:GetText())
    form:Init({ item = "Nobody Known Sword" })
    assert.are.equal("Nobody Known Sword", form.RecipeName:GetText())
  end)

  it("the crafting page's output icon is not this form's: nothing is written", function()
    form.RecipeName:SetText("Linen Bandage")
    _G.Professions.SetupOutputIcon(CreateFrame("Button"), {}, {})
    assert.are.equal("Linen Bandage", form.RecipeName:GetText())
    assert.are.equal(0, form.RecipeName.calls.addonSetText)
  end)

  it("with names off nothing is written", function()
    WFJ.State.setNames(false)
    form:Init({ item = "Linen Bandage" })
    assert.are.equal("Linen Bandage", form.RecipeName:GetText())
    assert.are.equal(0, form.RecipeName.calls.addonSetText)
  end)
end)
