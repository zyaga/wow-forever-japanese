-- UI/BarberShop.lua over a BarberShopFrame replayed from camelot
-- blizzard_barbershopui/mainline/blizzard_barbershopui.xml (:10–96), load-on-demand in both load orders.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/TooltipLines.lua" -- the camera buttons' tooltip
FILES[#FILES + 1] = "UI/BarberShop.lua"

local ADDON = "Blizzard_BarberShopUI"
local UI = { CANCEL = { "Cancel", "キャンセル" }, RESET = { "Reset", "リセット" }, ACCEPT = { "Accept", "承諾" },
  RESET_CAMERA = { "Reset Camera", "カメラをリセット" },
  -- the customization text from the client tables, and the two tooltip lines
  ["CustomizationCategory:4"] = { "Hair", "髪" }, ["CustomizationOption:30"] = { "Hair Style", "髪型" },
  ["CustomizationChoice:12"] = { "Brown", "茶色" }, ["CustomizationSource:3"] = { "See colors", "色を見る" },
  CHARACTER_CUSTOMIZE_POPOUT_UNSELECTED_OPTION = { "-Select-", "-選択-" },
  CHARACTER_CUSTOMIZATION_CHOICE_TOOLTIP = { "%d: %s", "%d: %s" },
  BARBERSHOP_CUSTOMIZATION_SOURCE_FORMAT = { "Source: %s", "入手方法: %s" } }

-- Blizzard_CustomizationUI's mixins (blizzard_customizationoptiontemplates.lua): SetupOption writes the
-- option's Label (:209, :336, :111–118), CustomizationElementDetailsMixin:UpdateText the choice's SelectionName (:652,
-- "-Select-" when nothing is chosen, :684). Pooled frames copy these methods when they are created (Mixin).
local CUSTOMIZATION = "Blizzard_CustomizationUI"
local MIXINS = { "CustomizationOptionCheckButtonMixin", "CustomizationDropdownWithSteppersAndLabelMixin",
  "CustomizationOptionSliderMixin", "CustomizationElementDetailsMixin" }
local function installMixins()
  for i = 1, 3 do
    _G[MIXINS[i]] = { SetupOption = function(self, info) self.Label.text = info.name end }
  end
  _G.CustomizationElementDetailsMixin = { UpdateText = function(self, choice)
    self.SelectionName.text = choice and choice.name or _G.CHARACTER_CUSTOMIZE_POPOUT_UNSELECTED_OPTION
  end }
  Stub.loadedAddons[CUSTOMIZATION] = true
end
-- A pooled frame made from `mixin` after the addon hooked it (CreateFrame + Mixin copies the method).
local function fromMixin(mixin, field)
  local f = CreateFrame("Frame")
  f[field] = Stub.fontString("")
  for k, v in pairs(_G[mixin]) do f[k] = v end
  return f
end

local function loadBarberShop()
  local frame = CreateFrame("Frame", "BarberShopFrame")
  frame.CancelButton = Stub.button(nil, _G.CANCEL)
  frame.ResetButton = Stub.button(nil, _G.RESET)
  frame.AcceptButton = Stub.button(nil, _G.ACCEPT)
  frame.SDToggleButton = CreateFrame("CheckButton")
  frame.SDToggleButton.Text = Stub.fontString("Reset") -- no dictionary entry; a dictionary word stands in
  Stub.tooltipFrame("CustomizationNoHeaderTooltip") -- Blizzard_CustomizationUI, loaded with the barber shop
  Stub.loadedAddons[ADDON] = true
  return frame
end

describe("the barber shop on Forever", function()
  local WFJ

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end

  local function setup(loadedFirst)
    load()
    if loadedFirst then
      loadBarberShop()
      WFJ.Labels.forbidNames(WFJ.BarberShop.NEVER_TOUCH)
      assert.is_true(WFJ.BarberShop.init())
    else
      assert.is_false(WFJ.BarberShop.init()) -- waits for the addon
      loadBarberShop()
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.BarberShopFrame = nil
  end)

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    describe("Blizzard_BarberShopUI " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("the three buttons are Japanese while shown, English with Alt, and released on hide", function()
        local frame = _G.BarberShopFrame
        frame:Show()
        assert.are.equal("キャンセル", frame.CancelButton:GetText())
        assert.are.equal("リセット", frame.ResetButton:GetText())
        assert.are.equal("承諾", frame.AcceptButton:GetText())
        Stub.keys.alt = true
        WFJ.Modifier.refresh()
        assert.are.equal("Accept", frame.AcceptButton:GetText())
        Stub.keys.alt = false
        WFJ.Modifier.refresh()
        frame:Hide()
        assert.are.equal("Cancel", frame.CancelButton:GetText())
      end)

      it("the camera buttons' own tooltip frame is Japanese; an option's tooltip stays as written",
        function()
          local tt = _G.CustomizationNoHeaderTooltip
          tt:SetOwner({})
          tt:ClearLines()
          tt:AddLine("Reset Camera")
          tt:Show()
          assert.are.equal("カメラをリセット", _G.CustomizationNoHeaderTooltipTextLeft1:GetText())
          tt:ClearLines()
          tt:AddLine("Accept") -- an option named like a dictionary word: not a camera key
          tt:Show()
          assert.are.equal("Accept", _G.CustomizationNoHeaderTooltipTextLeft1:GetText())
        end)

      it("hooks install once", function()
        assert.is_false(WFJ.BarberShop.init())
        assert.is_false(WFJ.BarberShop.setup())
      end)
    end)
  end

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    describe("Blizzard_CustomizationUI " .. order[2], function()
      before_each(function()
        load()
        if order[1] then
          installMixins()
          loadBarberShop()
          assert.is_true(WFJ.BarberShop.init())
        else
          assert.is_false(WFJ.BarberShop.init())
          installMixins()
          loadBarberShop()
          assert.are.equal(1, WFJ.LoadOnDemand.loaded(CUSTOMIZATION))
          assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
        end
        _G.BarberShopFrame:Show()
      end)

      after_each(function()
        for _, m in ipairs(MIXINS) do _G[m] = nil end
      end)

      it("the four mixin methods are hooked once, on the mixin tables", function()
        assert.are.equal(3, #Stub.hooks["?:SetupOption"])
        assert.are.equal(1, #Stub.hooks["?:UpdateText"])
        assert.are.equal(0, WFJ.BarberShop.hookMixins())
      end)

      it("an option's label and a choice's name are Japanese; a name choice with no row stays; Alt English",
        function()
          local check = fromMixin("CustomizationOptionCheckButtonMixin", "Label")
          local dropdown = fromMixin("CustomizationDropdownWithSteppersAndLabelMixin", "Label")
          local slider = fromMixin("CustomizationOptionSliderMixin", "Label")
          check:SetupOption({ name = "Hair Style" })
          dropdown:SetupOption({ name = "Hair Style" })
          slider:SetupOption({ name = "Brown" }) -- a choice's word is not an option's
          assert.are.equal("髪型", check.Label:GetText())
          assert.are.equal("髪型", dropdown.Label:GetText())
          assert.are.equal("Brown", slider.Label:GetText())
          local details = fromMixin("CustomizationElementDetailsMixin", "SelectionName")
          details:UpdateText({ name = "Brown" })
          assert.are.equal("茶色", details.SelectionName:GetText())
          local other = fromMixin("CustomizationElementDetailsMixin", "SelectionName")
          other:UpdateText(nil)
          assert.are.equal("-選択-", other.SelectionName:GetText())
          other:UpdateText({ name = "Moonfeather" }) -- a druid form / name choice: no row
          assert.are.equal("Moonfeather", other.SelectionName:GetText())
          details:UpdateText({ name = "Hair Style" }) -- an option's word is not a choice's
          assert.are.equal("Hair Style", details.SelectionName:GetText())
          details:UpdateText({ name = "Brown" })
          Stub.keys.alt = true
          WFJ.Modifier.refresh()
          assert.are.equal("Hair Style", check.Label:GetText())
          assert.are.equal("Brown", details.SelectionName:GetText())
          Stub.keys.alt = false
          WFJ.Modifier.refresh()
          assert.are.equal("茶色", details.SelectionName:GetText())
        end)

      it("the option tooltip: the choice line, a locked choice's source and a category name are Japanese", function()
        local tt = _G.CustomizationNoHeaderTooltip
        tt:SetOwner({})
        tt:ClearLines()
        tt:AddLine("Hair")
        tt:AddLine("3: Brown")
        tt:AddLine("Source: See colors")
        tt:AddLine("4: Moonfeather")
        tt:Show()
        assert.are.equal("髪", _G.CustomizationNoHeaderTooltipTextLeft1:GetText())
        assert.are.equal("3: 茶色", _G.CustomizationNoHeaderTooltipTextLeft2:GetText())
        assert.are.equal("入手方法: 色を見る", _G.CustomizationNoHeaderTooltipTextLeft3:GetText())
        assert.are.equal("4: Moonfeather", _G.CustomizationNoHeaderTooltipTextLeft4:GetText())
      end)
    end)
  end

  it("without the customization mixins nothing is hooked and nothing errors", function()
    load()
    loadBarberShop()
    Stub.loadedAddons[CUSTOMIZATION] = true
    assert.has_no.errors(function() assert.is_true(WFJ.BarberShop.init()) end)
    assert.are.equal(0, WFJ.BarberShop.hookMixins())
    assert.has_no.errors(function()
      WFJ.BarberShop.onOption(nil)
      WFJ.BarberShop.onOption({})
      WFJ.BarberShop.onChoice("x")
    end)
  end)

  it("the high-definition toggle's label is never recorded, whatever it holds", function()
    setup(true)
    _G.BarberShopFrame:Show()
    assert.are.equal("Reset", _G.BarberShopFrame.SDToggleButton.Text:GetText())
    assert.are.equal(0, WFJ.Labels.show("barbershop", "x", _G.BarberShopFrame.SDToggleButton.Text))
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    load()
    local frame = loadBarberShop()
    frame.ResetButton = 7
    frame.AcceptButton = "text"
    assert.has_no.errors(function()
      assert.is_true(WFJ.BarberShop.init())
      frame:Show()
    end)
    assert.are.equal("キャンセル", frame.CancelButton:GetText())
    load()
    _G.BarberShopFrame = 42
    Stub.loadedAddons[ADDON] = true
    assert.has_no.errors(function() assert.is_false(WFJ.BarberShop.init()) end)
  end)

  it("the addon never loads → init is false and nothing is set up", function()
    load()
    assert.has_no.errors(function() assert.is_false(WFJ.BarberShop.init()) end)
  end)
end)
