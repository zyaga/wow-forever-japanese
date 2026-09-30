-- UI/EquipmentFlyout.lua: the character window's equipment flyout on Forever (surface "equipmentflyout", area "ui",
-- ADR-016). Blizzard_FrameXML loads camelot/equipmentflyout.xml|lua at login on `camelot`; the paper doll
-- opens it from an item slot (EquipmentFlyout_Show, equipmentflyout.lua:229; blizzard_uipanels_game/camelot/
-- paperdollframe.lua:2466–2485 reads EquipmentFlyoutFrame.button).
-- Tooltips: the three special buttons of an equipment-set edit set their own Lua tooltips, owned by
--   EquipmentFlyoutFrame.buttonFrame (EquipmentFlyout_DisplaySpecialButton, :582–627): EQUIPMENT_MANAGER_IGNORE_SLOT,
--   EQUIPMENT_MANAGER_UNIGNORE_SLOT, EQUIPMENT_MANAGER_PLACE_IN_BAGS (GameTooltip:SetText). The same owner shows the
--   item tooltips of the flyout's item buttons (:661–666): UI/HelpTooltip never walks an item tooltip, and the owner
--   is restricted to the three keys.
-- Static labels (XML text=): NavigationFrame.PreviousPageText PREVIOUS and NextPageText NEXT (equipmentflyout.xml:
--   111–116; the page prompts shown for a gamepad, :80–99), shown on the flyout's OnShow.
local _, WFJ = ...
local EquipmentFlyout = {}
WFJ.EquipmentFlyout = EquipmentFlyout

local SURFACE = "equipmentflyout"
EquipmentFlyout.SURFACE = SURFACE
local Compat = WFJ.Compat

EquipmentFlyout.NEVER_TOUCH = {}

local CANDIDATES = { frame = { "EquipmentFlyoutFrame" }, buttons = { "EquipmentFlyoutFrame.buttonFrame" },
  prev = { "EquipmentFlyoutFrame.NavigationFrame.PreviousPageText" },
  next = { "EquipmentFlyoutFrame.NavigationFrame.NextPageText" } }
local TOOLTIP = { only = { "EQUIPMENT_MANAGER_IGNORE_SLOT", "EQUIPMENT_MANAGER_UNIGNORE_SLOT",
  "EQUIPMENT_MANAGER_PLACE_IN_BAGS" } }
local PREV = { only = { "PREVIOUS" } }
local NEXT = { only = { "NEXT" } }

local function get(key) return Compat.get(SURFACE, key) end

-- The page labels (the flyout's OnShow). → the number of dictionary words found.
function EquipmentFlyout.show()
  return WFJ.Labels.showAll(SURFACE, { { "prev", get("prev"), PREV }, { "next", get("next"), NEXT } })
end

local hooked = false

-- Called by Main after Compat.init and HelpTooltip.init. → true when the flyout was hooked now; false on
-- a second call.
function EquipmentFlyout.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  local frame = get("frame")
  if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  hooked = true
  local buttons = get("buttons")
  if type(buttons) == "table" then WFJ.HelpTooltip.register(buttons, TOOLTIP) end
  frame:HookScript("OnShow", EquipmentFlyout.show)
  EquipmentFlyout.show()
  return true
end
