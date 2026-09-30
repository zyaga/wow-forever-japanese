-- UI/EquipmentFlyout.lua over an EquipmentFlyoutFrame replayed from
-- camelot blizzard_framexml/camelot/equipmentflyout.xml (:50–173) and .lua (:582–627 special-button tooltips).
local Stub = require("tests.lua.spec.wow_stub")
local R = require("tests.lua.spec.stub_retail")

local UI = {
  EQUIPMENT_MANAGER_IGNORE_SLOT = { "Ignore This Slot", "このスロットを無視" },
  EQUIPMENT_MANAGER_PLACE_IN_BAGS = { "Place In Bags", "バッグに入れる" },
  PREVIOUS = { "Previous", "前へ" }, NEXT = { "Next", "次へ" },
}
local GLOBALS = { "EquipmentFlyoutFrame" }

local function build()
  local frame = CreateFrame("Frame", "EquipmentFlyoutFrame")
  R.tree(frame, { ["buttonFrame"] = { frame = true }, ["NavigationFrame.PreviousPageText"] = _G.PREVIOUS,
    ["NavigationFrame.NextPageText"] = _G.NEXT })
  return frame
end

R.suite(getfenv(1), {
  title = "the equipment flyout on Forever", module = "EquipmentFlyout",
  file = "UI/EquipmentFlyout.lua", root = "EquipmentFlyoutFrame", globals = GLOBALS, ui = UI, build = build,
  cases = {
    { "the special buttons' tooltips and the page labels are Japanese; Alt shows English", function(frame, WFJ)
      frame:Show()
      assert.are.equal("前へ", frame.NavigationFrame.PreviousPageText:GetText())
      assert.are.equal("次へ", frame.NavigationFrame.NextPageText:GetText())
      R.tooltip(frame.buttonFrame, { _G.EQUIPMENT_MANAGER_IGNORE_SLOT })
      assert.are.equal("このスロットを無視", _G.GameTooltipTextLeft1:GetText())
      R.alt(WFJ, true)
      assert.are.equal("Ignore This Slot", _G.GameTooltipTextLeft1:GetText())
      R.alt(WFJ, false)
    end },
  },
  name = function(frame)
    R.tooltip(frame.buttonFrame, { "Next" }) -- an item called "Next" in the flyout's own tooltip stays English
    assert.are.equal("Next", _G.GameTooltipTextLeft1:GetText())
  end,
  wrong = function(frame)
    frame.buttonFrame = Stub
    frame.NavigationFrame.PreviousPageText = "x"
    return function(f)
      f:Show()
      assert.are.equal("次へ", f.NavigationFrame.NextPageText:GetText())
    end
  end,
})
