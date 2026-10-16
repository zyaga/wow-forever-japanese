-- UI/Stable.lua: the pet stable on Forever (surface "stable", area "ui", ADR-016, ADR-029).
-- `camelot` loads its own stable window at login: blizzard_stableui.toc `## AllowLoadGameType: standard, camelot`,
-- Camelot\Blizzard_StableUI.lua|xml. Entry point: the stable master's PET_STABLE_SHOW event → ShowUIPanel(self)
-- (blizzard_stableui/camelot/blizzard_stableui.lua:9, :40–41). init requires camelot's parentKey purchase button
-- (xml:225) and returns false without it.
-- The window title: StableFrameMixin:OnShow calls self:SetTitle(STABLES) (lua:53), shown through Labels.title
-- restricted to STABLES.
-- Static labels (XML text=), shown on the frame's OnShow and after Update:
--   PetStableSlotText STABLE_SLOT_TEXT (xml:84), PetStableCostLabel COSTS_LABEL (xml:90),
--   PetStableFrame.purchaseButton PURCHASE (xml:225),
--   the CURRENT_PET label of PetStableCurrentPet (xml:197) and the STABLED_PETS label of PetStableStabledPet1
--   (xml:211), found with Labels.region.
-- Tooltips (GameTooltip:SetText, each owner registered with UI/HelpTooltip and restricted to its key):
--   every slot button (PetStableCurrentPet, PetStableStabledPet1, PetStableStabledPet2): EMPTY_STABLE_SLOT for an
--     unlocked empty slot (lua:312–319, :362); a filled slot's tooltip is the pet's name and "Level n Family"
--     (lua:358–359), which the restriction leaves alone.
-- The loyalty line: StableFrameMixin:SelectPet writes PetStableLoyaltyText:SetText(format(PET_LOYALTY_TEMPLATE,
-- petInfo.loyaltyName, petInfo.loyaltyLevel)) (lua:281), "%s (Loyalty: %d)" around a PetLoyalty row's English. Shown
-- with the static labels and after SelectPet (post-hooked on the instance): the template in Japanese, the rank
-- through the PetLoyalty family (a rank that is no PetLoyalty row stays as written), the number kept. A line that is
-- no PET_LOYALTY_TEMPLATE line stays English.
-- Never touched: PetStableLevelText (pet name, UNIT_LEVEL_TEMPLATE and the family joined at run time, lua:276–278).
-- The money frames are numbers.
-- Release on the frame's OnHide.
local _, WFJ = ...
local Stable = {}
WFJ.Stable = Stable

local SURFACE = "stable"
Stable.SURFACE = SURFACE
local Compat = WFJ.Compat

Stable.NEVER_TOUCH = { "PetStableLevelText" }

local CANDIDATES = {
  frame = { "PetStableFrame" }, slotText = { "PetStableSlotText" }, costLabel = { "PetStableCostLabel" },
  purchase = { "PetStableFrame.purchaseButton" },
  -- shown in gamepad mode while a slot can be bought (blizzard_stableui.xml:96, blizzard_stableui.lua:234)
  slotCost = { "PetStableFrame.GamepadSlotCostText" },
  loyaltyText = { "PetStableLoyaltyText" },
  current = { "PetStableCurrentPet" }, stabled1 = { "PetStableStabledPet1" }, stabled2 = { "PetStableStabledPet2" },
}

local STATIC = {
  { "slotText", { only = { "STABLE_SLOT_TEXT" } } }, { "costLabel", { only = { "COSTS_LABEL" } } },
  { "purchase", { only = { "PURCHASE" } } }, { "slotCost", { only = { "STABLE_SLOT_COST_TEXT" } } },
}
local REGIONS = { { "current", "CURRENT_PET" }, { "stabled1", "STABLED_PETS" } }
local SLOT_TOOLTIP = { only = { "EMPTY_STABLE_SLOT" } }
local TITLE = { only = { "STABLES" } }
local LOYALTY_KEY = "PET_LOYALTY_TEMPLATE"
Stable.KEYS = { title = TITLE.only, loyalty = { LOYALTY_KEY } }

local function get(key) return Compat.get(SURFACE, key) end

-- The loyalty line split at the client's own PET_LOYALTY_TEMPLATE ("%s (Loyalty: %d)"). → rank, level | nil
local function splitLoyalty(text)
  local template = Compat.resolve(LOYALTY_KEY)
  if type(text) ~= "string" or type(template) ~= "string" then return nil end
  local pre, mid, post = template:match("^(.-)%%s(.-)%%d(.*)$")
  if not pre then return nil end
  local function lit(x) return (x:gsub("%W", "%%%0")) end
  return text:match("^" .. lit(pre) .. "(.-)" .. lit(mid) .. "(%d+)" .. lit(post) .. "$")
end

-- The loyalty line: the template in Japanese around the PetLoyalty row its rank names (else the rank as written) and
-- the level number. → 1 when shown (or still ours), else 0
local function showLoyalty()
  local fs = get("loyaltyText")
  local text = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
  local rank, level = splitLoyalty(text)
  local index = WFJ.UIIndex
  if not rank or not (index and index.rows[LOYALTY_KEY]) then
    return WFJ.Labels.showArgs(SURFACE, "loyaltyText", fs, nil)
  end
  local row = WFJ.Labels.part(rank, WFJ.Labels.families("PetLoyalty").only)
  -- the rank goes in already filled: the template declares no argument kinds, so a nested entry would stay unfilled
  local name = row and index:fillArg({ entry = row.key }) or rank
  return WFJ.Labels.showArgs(SURFACE, "loyaltyText", fs, LOYALTY_KEY, { key = LOYALTY_KEY, name, level })
end

-- HookScript("OnShow") / hooksecurefunc(PetStableFrame, "Update" / "SelectPet") target. → the number of dictionary
-- words found.
function Stable.onShow()
  local n = WFJ.Labels.title(SURFACE, get("frame"), TITLE) + showLoyalty()
  local list = {}
  for _, s in ipairs(STATIC) do list[#list + 1] = { s[1], get(s[1]), s[2] } end
  for _, r in ipairs(REGIONS) do
    list[#list + 1] = { "region." .. r[1], WFJ.Labels.region(get(r[1]), r[2]), { only = { r[2] } } }
  end
  return n + WFJ.Labels.showAll(SURFACE, list)
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
  if type(frame.SelectPet) == "function" then hooksecurefunc(frame, "SelectPet", Stable.onShow) end
  for _, key in ipairs({ "current", "stabled1", "stabled2" }) do
    WFJ.HelpTooltip.register(get(key), SLOT_TOOLTIP)
  end
  return true
end
