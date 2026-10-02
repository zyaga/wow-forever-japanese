-- UI/Stable.lua: the pet stable on Forever (surface "stable", area "ui", ADR-016, ADR-029).
-- `camelot` loads its own stable window at login: blizzard_stableui.toc `## AllowLoadGameType: standard, camelot`,
-- Camelot\Blizzard_StableUI.lua|xml. Entry point: the stable master's PET_STABLE_SHOW event → ShowUIPanel(self)
-- (blizzard_stableui/camelot/blizzard_stableui.lua:7, :41–42). init requires camelot's parentKey purchase button
-- (xml:252) and returns false without it.
-- Static labels (XML text=), shown on the frame's OnShow and after Update:
--   PetStableSlotText STABLE_SLOT_TEXT (xml:110), PetStableCostLabel COSTS_LABEL (xml:119),
--   PetStableFrame.purchaseButton PURCHASE (xml:252),
--   the unnamed CURRENT_PET label in PetStableCurrentPet's layers (xml:209) and the unnamed STABLED_PETS label in
--   PetStableStabledPet1's (xml:231), found with Labels.region.
-- Tooltips (GameTooltip:SetText, each owner registered with UI/HelpTooltip and restricted to its key):
--   every slot button (PetStableCurrentPet, PetStableStabledPet1, PetStableStabledPet2): EMPTY_STABLE_SLOT for an
--     unlocked empty slot (lua:178–185, :227); a filled slot's tooltip is the pet's name and "Level n Family"
--     (lua:223–224), which the restriction leaves alone;
--   PetStableFrame.loyaltyLevel: format(LOYALTY_LEVEL, n) (lua:137, :275–280).
-- Never touched: PetStableLevelText (pet name, "Level n" and the family joined at run time, lua:125–127),
-- PetStableLoyaltyText (the loyalty rank's name, lua:130), the loyalty level number. The window has no title
-- (no SetTitle call in the addon), and the money frames are numbers.
-- Release on the frame's OnHide.
local _, WFJ = ...
local Stable = {}
WFJ.Stable = Stable

local SURFACE = "stable"
Stable.SURFACE = SURFACE
local Compat = WFJ.Compat

Stable.NEVER_TOUCH = { "PetStableLevelText", "PetStableLoyaltyText", "PetStableFrame.loyaltyLevel.levelText" }

local CANDIDATES = {
  frame = { "PetStableFrame" }, slotText = { "PetStableSlotText" }, costLabel = { "PetStableCostLabel" },
  purchase = { "PetStableFrame.purchaseButton" }, loyalty = { "PetStableFrame.loyaltyLevel" },
  -- shown in gamepad mode while a slot can be bought (blizzard_stableui.xml:131, blizzard_stableui.lua:236)
  slotCost = { "PetStableFrame.GamepadSlotCostText" },
  current = { "PetStableCurrentPet" }, stabled1 = { "PetStableStabledPet1" }, stabled2 = { "PetStableStabledPet2" },
}

local STATIC = {
  { "slotText", { only = { "STABLE_SLOT_TEXT" } } }, { "costLabel", { only = { "COSTS_LABEL" } } },
  { "purchase", { only = { "PURCHASE" } } }, { "slotCost", { only = { "STABLE_SLOT_COST_TEXT" } } },
}
local REGIONS = { { "current", "CURRENT_PET" }, { "stabled1", "STABLED_PETS" } }
local SLOT_TOOLTIP = { only = { "EMPTY_STABLE_SLOT" } }
local LOYALTY_TOOLTIP = { only = { "LOYALTY_LEVEL" } }

local function get(key) return Compat.get(SURFACE, key) end

-- HookScript("OnShow") / hooksecurefunc(PetStableFrame, "Update") target. → the number of dictionary words found.
function Stable.onShow()
  local list = {}
  for _, s in ipairs(STATIC) do list[#list + 1] = { s[1], get(s[1]), s[2] } end
  for _, r in ipairs(REGIONS) do
    list[#list + 1] = { "region." .. r[1], WFJ.Labels.region(get(r[1]), r[2]), { only = { r[2] } } }
  end
  return WFJ.Labels.showAll(SURFACE, list)
end

function Stable.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Stable.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  -- camelot's frame carries the purchase button as a parentKey; another client's PetStableFrame is not this window
  if hooked or type(frame) ~= "table" or type(frame.purchaseButton) ~= "table" then return false end
  hooked = true
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnShow", Stable.onShow)
    frame:HookScript("OnHide", Stable.release)
  end
  if type(frame.Update) == "function" then hooksecurefunc(frame, "Update", Stable.onShow) end
  for _, key in ipairs({ "current", "stabled1", "stabled2" }) do
    WFJ.HelpTooltip.register(get(key), SLOT_TOOLTIP)
  end
  WFJ.HelpTooltip.register(get("loyalty"), LOYALTY_TOOLTIP)
  return true
end
