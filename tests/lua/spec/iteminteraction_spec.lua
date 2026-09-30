-- UI/ItemInteraction.lua over an ItemInteractionFrame replayed
-- from camelot blizzard_iteminteractionui/blizzard_iteminteractionui.xml (:5–313) and .lua (:265–301, :384–395,
-- :728–739, :812–819), load-on-demand in both load orders. The interaction's own title, button and description
-- stay as written. The recharge sentence's `%s` is a duration (`time`, C.args; the core entry is in
-- Core/UIStrings).
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")

local UI = {
  RUNEFORGE_LEGENDARY_COST_LABEL = { "Costs:", "費用:" }, NOT_ENOUGH_GOLD = { "Not enough gold.", "ゴールドが足りません。" },
  SL_SET_CONVERSION_RECHARGE_TIME = { "The Catalyst is recharging and will be functional in %s",
    "Catalystは再チャージ中です。使用可能になるまで%s" },
  GENERIC_ITEM_CONVERSION_SLOT_TOOLTIP = { "Insert an eligible item to convert to a set item.",
    "対象のアイテムを入れるとセットアイテムに変換します。" },
  CONVERT = { "Convert", "変換" },
  NOT_ENOUGH_CURRENCY = { "Not enough %s", "%sが足りません" },
}

local function en(key) return _G[key] end

local function build()
  local frame = C.window("ItemInteractionFrame")
  C.tree(frame, { ["CurrencyCost.Costs"] = en("RUNEFORGE_LEGENDARY_COST_LABEL"), Description = "",
    ["ButtonFrame.ActionButton"] = { button = "Convert" }, ItemSlot = { frame = 1 },
    ["ItemConversionFrame.ItemConversionInputSlot"] = { frame = 1 } })
  frame:SetTitle("Convert") -- frameData.titleText: interaction data that happens to be a dictionary word
  function frame.UpdateDescription(self, text) self.Description.text = text end
  return frame
end

C.suite(getfenv(1), {
  title = "the item interaction window on Forever", module = "ItemInteraction",
  file = "UI/ItemInteraction.lua", addon = "Blizzard_ItemInteractionUI", root = "ItemInteractionFrame", ui = UI,
  build = build, globals = { "ItemInteractionFrame" },
  cases = {
    { "the cost label and the recharge sentence translate; the interaction's own description does not",
      function(frame, WFJ)
        frame:Show()
        assert.are.equal("費用:", frame.CurrencyCost.Costs:GetText())
        C.args(WFJ, UI, { SL_SET_CONVERSION_RECHARGE_TIME = { [1] = "time" } })
        frame:UpdateDescription(string.format(en("SL_SET_CONVERSION_RECHARGE_TIME"), "2 Hr 5 Min")) -- :481
        assert.are.equal("Catalystは再チャージ中です。使用可能になるまで2 Hr 5 Min", frame.Description:GetText())
        frame:UpdateDescription("Convert") -- frameData.description
        assert.are.equal("Convert", frame.Description:GetText())
        C.alt(WFJ, true)
        assert.are.equal("Costs:", frame.CurrencyCost.Costs:GetText())
        C.alt(WFJ, false)
        frame:Hide()
        assert.are.equal("Costs:", frame.CurrencyCost.Costs:GetText())
      end },
    { "tooltips: the input slot and the action button translate", function(frame)
      C.tooltip(frame.ItemConversionFrame.ItemConversionInputSlot, { "", en("GENERIC_ITEM_CONVERSION_SLOT_TOOLTIP") })
      assert.are.equal("対象のアイテムを入れるとセットアイテムに変換します。", _G.GameTooltipTextLeft2:GetText())
      C.tooltip(frame.ButtonFrame.ActionButton, { en("NOT_ENOUGH_GOLD") })
      assert.are.equal("ゴールドが足りません。", _G.GameTooltipTextLeft1:GetText())
      -- NOT_ENOUGH_CURRENCY (:824–831), the currency's name kept; key-only, asked for by this owner
      C.tooltip(frame.ButtonFrame.ActionButton, { en("NOT_ENOUGH_CURRENCY"):format("Honor") })
      assert.are.equal("Honorが足りません", _G.GameTooltipTextLeft1:GetText())
    end },
  },
  name = function(frame, WFJ)
    frame:Show()
    assert.are.equal("Convert", frame.TitleContainer.TitleText:GetText())
    assert.are.equal("Convert", frame.ButtonFrame.ActionButton:GetText())
    assert.are.equal(0, WFJ.Labels.show("iteminteraction", "x", frame.ButtonFrame.ActionButton))
    assert.is_true(C.unrecorded(WFJ, frame.TitleContainer.TitleText))
  end,
  wrong = function(frame)
    frame.Description, frame.ButtonFrame, frame.ItemConversionFrame = 7, "buttons", true
    frame.ItemSlot = Stub -- a table that is no widget
    return function() assert.are.equal("費用:", frame.CurrencyCost.Costs:GetText()) end
  end,
})
