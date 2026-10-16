-- The pet stable on Forever: UI/Stable.lua over a PetStableFrame replayed from camelot
-- blizzard_stableui/camelot/blizzard_stableui.xml (:63–262) and .lua (OnShow :50–54, SelectPet :264–295, slot Update
-- :348–373, slot OnEnter :312–319). Pet names and families stay English; the loyalty line is
-- format(PET_LOYALTY_TEMPLATE, rank, level) (SelectPet, lua:281): the template and a PetLoyalty row's rank in Japanese,
-- the level number kept.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Stable.lua"

-- Forever GlobalStrings (build 1.60.1.70425) → a test Japanese
local UI = {
  STABLE_SLOT_TEXT = { "Do you wish to purchase another stable slot?", "厩舎スロットをもう1つ購入しますか？" },
  COSTS_LABEL = { "Cost:", "費用:" }, PURCHASE = { "Purchase", "購入" },
  STABLE_SLOT_COST_TEXT = { "Stable Slot Cost:", "厩舎スロットの費用:" },
  CURRENT_PET = { "Current Pet:", "現在のペット:" }, STABLED_PETS = { "Stabled Pets:", "預けているペット:" },
  EMPTY_STABLE_SLOT = { "|cffffffffEmpty Stable Slot|r", "|cffffffff空の厩舎スロット|r" },
  STABLES = { "Stables", "厩舎" },
  PET_LOYALTY_TEMPLATE = { "%s (Loyalty: %d)", "%s（忠誠度：%d）" },
  UNIT_LEVEL_TEMPLATE = { "Level %d", "レベル%d" },
  CLOSE = { "Close", "閉じる" }, -- a dictionary word a pet can be named after
  ["PetLoyalty:6"] = { "Best Friend", "親友" }, -- client-table row (fingerprint: no global; ADR-042)
}

local function en(key) return _G[key] end

local GLOBALS = { "PetStableFrame", "PetStableSlotText", "PetStableCostLabel", "PetStableLevelText",
  "PetStableLoyaltyText", "PetStableCurrentPet", "PetStableStabledPet1", "PetStableStabledPet2" }

local function installStable()
  local frame = CreateFrame("Frame", "PetStableFrame")
  frame.TitleContainer = { TitleText = Stub.fontString("") } -- PortraitFrameTemplate (xml:63)
  function frame.SetTitle(self, title) self.TitleContainer.TitleText.text = title end
  frame:SetScript("OnShow", function(self) self:SetTitle(en("STABLES")) end) -- lua:53
  Stub.namedFontString("PetStableSlotText", en("STABLE_SLOT_TEXT"))
  Stub.namedFontString("PetStableCostLabel", en("COSTS_LABEL"))
  Stub.namedFontString("PetStableLevelText", "")
  Stub.namedFontString("PetStableLoyaltyText", "")
  frame.purchaseButton = Stub.button(nil, en("PURCHASE"))
  frame.GamepadSlotCostText = Stub.fontString(en("STABLE_SLOT_COST_TEXT"))
  local current = CreateFrame("CheckButton", "PetStableCurrentPet")
  current.Text = Stub.fontString(en("CURRENT_PET")) -- parentKey="Text" (xml:197)
  current:addRegion(current.Text)
  local stabled = CreateFrame("CheckButton", "PetStableStabledPet1")
  stabled.Text = Stub.fontString(en("STABLED_PETS")) -- xml:211
  stabled:addRegion(stabled.Text)
  CreateFrame("CheckButton", "PetStableStabledPet2")
  function frame.Update() end -- money frames and slot textures only
  function frame.SelectPet(_, pet) -- lua:264–295
    local level = string.format(en("UNIT_LEVEL_TEMPLATE"), pet.level) .. " " .. pet.family
    _G.PetStableLevelText.text = pet.name == pet.family and level or (pet.name .. " " .. level)
    _G.PetStableLoyaltyText.text = string.format(en("PET_LOYALTY_TEMPLATE"), pet.loyalty, pet.loyaltyLevel or 3)
  end
  return frame
end

describe("the pet stable on Forever", function()
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

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
  end

  before_each(function()
    load()
    installStable()
    WFJ.Labels.forbidNames(WFJ.Stable.NEVER_TOUCH)
    assert.is_true(WFJ.Stable.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
  end)

  it("OnShow: the named labels, the purchase button and the two unnamed slot labels are Japanese; Alt shows English",
    function()
      _G.PetStableFrame:Show()
      assert.are.equal("厩舎スロットをもう1つ購入しますか？", _G.PetStableSlotText:GetText())
      assert.are.equal("費用:", _G.PetStableCostLabel:GetText())
      assert.are.equal("購入", _G.PetStableFrame.purchaseButton:GetText())
      assert.are.equal("厩舎スロットの費用:", _G.PetStableFrame.GamepadSlotCostText:GetText())
      assert.are.equal("現在のペット:", (_G.PetStableCurrentPet:GetRegions()):GetText())
      assert.are.equal("預けているペット:", (_G.PetStableStabledPet1:GetRegions()):GetText())
      alt(true)
      assert.are.equal("Cost:", _G.PetStableCostLabel:GetText())
      assert.are.equal("Current Pet:", (_G.PetStableCurrentPet:GetRegions()):GetText())
      alt(false)
      _G.PetStableFrame:Hide()
      assert.are.equal("Cost:", _G.PetStableCostLabel:GetText()) -- released on OnHide
      _G.PetStableFrame:Update() -- PET_STABLE_UPDATE while shown again
      assert.are.equal("費用:", _G.PetStableCostLabel:GetText())
    end)

  it("the window title SetTitle(STABLES) translates on every show; Alt shows English", function()
    local title = _G.PetStableFrame.TitleContainer.TitleText
    _G.PetStableFrame:Show()
    assert.are.equal("厩舎", title:GetText())
    alt(true)
    assert.are.equal("Stables", title:GetText())
    alt(false)
    _G.PetStableFrame:Hide()
    assert.are.equal("Stables", title:GetText()) -- released on OnHide
    _G.PetStableFrame:Show()
    assert.are.equal("厩舎", title:GetText())
    _G.PetStableFrame:SetTitle("Close") -- only STABLES: any other title stays as written
    assert.are.equal("Close", title:GetText())
  end)

  it("names stay English: the pet line is never recorded; a rank that is no PetLoyalty row stays as written inside"
    .. " the Japanese loyalty line", function()
    _G.PetStableFrame:Show()
    _G.PetStableFrame:SelectPet({ name = "Close", level = 12, family = "Boar", loyalty = "Close", loyaltyLevel = 2 })
    WFJ.Stable.onShow()
    assert.are.equal("Close Level 12 Boar", _G.PetStableLevelText:GetText())
    assert.are.equal("Close（忠誠度：2）", _G.PetStableLoyaltyText:GetText()) -- a dictionary word, but no PetLoyalty row
    assert.is_true(unrecorded(_G.PetStableLevelText))
  end)

  it("the loyalty line: the template and a PetLoyalty rank in Japanese, the level number kept, after SelectPet;"
    .. " Alt shows English", function()
    _G.PetStableFrame:Show()
    _G.PetStableFrame:SelectPet({ name = "Grimfang", level = 40, family = "Wolf", loyalty = "Best Friend",
      loyaltyLevel = 6 })
    assert.are.equal("親友（忠誠度：6）", _G.PetStableLoyaltyText:GetText())
    assert.are.equal("Grimfang Level 40 Wolf", _G.PetStableLevelText:GetText())
    alt(true)
    assert.are.equal("Best Friend (Loyalty: 6)", _G.PetStableLoyaltyText:GetText())
    alt(false)
    assert.are.equal("親友（忠誠度：6）", _G.PetStableLoyaltyText:GetText())
    WFJ.Stable.onShow() -- Update while the Japanese is up: still ours
    assert.are.equal("親友（忠誠度：6）", _G.PetStableLoyaltyText:GetText())
    _G.PetStableFrame:SelectPet({ name = "Grimfang", level = 40, family = "Wolf", loyalty = "Best Friend",
      loyaltyLevel = 5 })
    assert.are.equal("親友（忠誠度：5）", _G.PetStableLoyaltyText:GetText())
    _G.PetStableLoyaltyText.text = "Something else"
    WFJ.Stable.onShow() -- no PET_LOYALTY_TEMPLATE line: the client's text stays
    assert.are.equal("Something else", _G.PetStableLoyaltyText:GetText())
    _G.PetStableFrame:SelectPet({ name = "Grimfang", level = 40, family = "Wolf", loyalty = "Best Friend",
      loyaltyLevel = 6 })
    _G.PetStableFrame:Hide()
    assert.are.equal("Best Friend (Loyalty: 6)", _G.PetStableLoyaltyText:GetText()) -- released on OnHide
  end)

  it("tooltips: an empty slot translates; a pet's name tooltip does not", function()
    local tt = _G.GameTooltip
    tt:SetOwner(_G.PetStableStabledPet1)
    tt:SetText(en("EMPTY_STABLE_SLOT"))
    tt:AddLine("")
    tt:Show()
    assert.are.equal("|cffffffff空の厩舎スロット|r", _G.GameTooltipTextLeft1:GetText())
    tt:SetOwner(_G.PetStableCurrentPet)
    tt:SetText("Close") -- a pet named like a dictionary word
    tt:AddLine("Level 12 Boar")
    tt:Show()
    assert.are.equal("Close", _G.GameTooltipTextLeft1:GetText())
    assert.are.equal("Level 12 Boar", _G.GameTooltipTextLeft2:GetText())
  end)

  it("hooks install once", function()
    assert.is_false(WFJ.Stable.init())
    assert.are.equal(1, #Stub.hooks["PetStableFrame:Update"])
    assert.are.equal(1, #Stub.hooks["PetStableFrame:SelectPet"])
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    load()
    installStable()
    _G.PetStableSlotText = 42
    _G.PetStableCurrentPet = "not a frame"
    _G.PetStableLoyaltyText = {}
    assert.has_no.errors(function()
      assert.is_true(WFJ.Stable.init())
      _G.PetStableFrame:Show()
    end)
    assert.are.equal("費用:", _G.PetStableCostLabel:GetText())
    assert.are.equal("預けているペット:", (_G.PetStableStabledPet1:GetRegions()):GetText())
  end)

  it("without camelot's frame (a PetStableFrame without parentKeys, or none at all) init is false",
    function()
      load()
      for _, name in ipairs(GLOBALS) do _G[name] = nil end
      assert.has_no.errors(function() assert.is_false(WFJ.Stable.init()) end)
      local bare = CreateFrame("Frame", "PetStableFrame") -- global children only
      Stub.namedFontString("PetStableCostLabel", en("COSTS_LABEL"))
      assert.has_no.errors(function() assert.is_false(WFJ.Stable.init()) end)
      bare:Show()
      assert.are.equal("Cost:", _G.PetStableCostLabel:GetText())
      _G.PetStableFrame = "text"
      assert.has_no.errors(function() assert.is_false(WFJ.Stable.init()) end)
    end)
end)
