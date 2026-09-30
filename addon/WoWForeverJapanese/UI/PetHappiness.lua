-- UI/PetHappiness.lua: the hunter pet happiness tooltip on Forever (surface "pethappiness" via UI/HelpTooltip, area
-- "ui", ADR-016). Blizzard_FrameXML loads pethappiness.xml|lua at login on `camelot`: the
-- PetFrameHappinessTemplate (pethappiness.xml:3) whose PetHappinessIndicatorMixin:OnEnter builds a Lua GameTooltip
-- (pethappiness.lua:76–91):
--   line 1  self.tooltip = PET_HAPPINESS1 / 2 / 3 ("Unhappy" / "Content" / "Happy") or NONE (:4–8, :49)
--   then    PET_DAMAGE_PERCENTAGE "Causes %d%% of normal damage" (:50), GAINING_LOYALTY / LOSING_LOYALTY (:51–57)
--   last    PET_DIET_TEMPLATE "|cffffd200Diet:|r %s" around the food types joined by PET_FOOD_DELIMIT (:60–74); the
--           food list stays English inside the Japanese (a `text` argument, Core/UIStrings), NONE when empty.
-- Three frames inherit the template on camelot, each registered as a tooltip owner (UI/HelpTooltip, restricted to the
-- keys above): PetFrameHappiness on the pet frame (blizzard_unitframe/mainline/petframe.xml:179),
-- PetPaperDollPetHappinessInfo on the character window's pet tab (blizzard_uipanels_game/camelot/paperdollframe.xml:
-- 740) and PetStableFrame.modelScene.diet in the stable (blizzard_stableui/camelot/blizzard_stableui.xml:177; a login
-- addon on camelot, forever_addons.txt). An owner that is absent or not a frame is skipped.
local _, WFJ = ...
local PetHappiness = {}
WFJ.PetHappiness = PetHappiness

local SURFACE = "pethappiness"
PetHappiness.SURFACE = SURFACE
local Compat = WFJ.Compat

PetHappiness.NEVER_TOUCH = {}

local OWNERS = {
  pet = { "PetFrameHappiness" }, paperdoll = { "PetPaperDollPetHappinessInfo" },
  stable = { "PetStableFrame.modelScene.diet" },
}
local TOOLTIP = { only = { "PET_HAPPINESS1", "PET_HAPPINESS2", "PET_HAPPINESS3", "NONE", "PET_DAMAGE_PERCENTAGE",
  "GAINING_LOYALTY", "LOSING_LOYALTY", "PET_DIET_TEMPLATE" } }

local done = false

-- Called by Main after Compat.init and HelpTooltip.init. → true when at least one owner was registered
-- now; false on a second call.
function PetHappiness.init()
  for key, names in pairs(OWNERS) do Compat.declare(SURFACE, key, names) end
  if done then return false end
  local any = false
  for key in pairs(OWNERS) do
    local owner = Compat.get(SURFACE, key)
    if type(owner) == "table" then
      WFJ.HelpTooltip.register(owner, TOOLTIP)
      any = true
    end
  end
  done = any
  return any
end
