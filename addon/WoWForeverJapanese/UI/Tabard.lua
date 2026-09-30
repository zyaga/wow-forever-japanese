-- UI/Tabard.lua: the tabard designer's window on Forever (surface "tabard", area "ui", ADR-016 / ADR-029).
-- camelot loads blizzard_uipanels_game/mainline/tabardframe.lua|xml; the window is registered with the player
-- interaction manager and opened by TabardFrame_Open (tabardframe.lua:21–27, 45–60).
-- - Static (shown on the frame's OnShow):
--     TabardFrameCustomization1–5Text  EMBLEM_SYMBOL, EMBLEM_SYMBOL_COLOR, EMBLEM_BORDER, EMBLEM_BORDER_COLOR,
--                                      EMBLEM_BACKGROUND, written by each row's inline OnLoad (tabardframe.xml:278–328)
--     TabardFrameCostLabel             TABARDVENDORCOST (xml:248)
--     TabardFrameAcceptButton / TabardFrameCancelButton  ACCEPT / CANCEL (xml:353, 365)
-- - Writer: TabardFrame_UpdateButtons writes TabardFrameGreetingText = TABARDVENDORGREETING,
--   TABARDVENDORNOGUILDGREETING, PERSONALTABARDVENDORGREETING or PERSONALTABARDVENDORUNOWNEDGREETING
--   (tabardframe.lua:90–106); a global called by name from TabardFrame_Open (:26) and the OnEvent (:64): post-hooked.
-- Never touched: TabardFrameNameText (the designer NPC's name, tabardframe.lua:23).
-- Release on TabardFrame's OnHide.
local _, WFJ = ...
local Tabard = {}
WFJ.Tabard = Tabard

local SURFACE = "tabard"
Tabard.SURFACE = SURFACE
local Compat = WFJ.Compat

Tabard.NEVER_TOUCH = { "TabardFrameNameText" }

local ROWS = { "EMBLEM_SYMBOL", "EMBLEM_SYMBOL_COLOR", "EMBLEM_BORDER", "EMBLEM_BORDER_COLOR", "EMBLEM_BACKGROUND" }
local GREETING = { only = { "TABARDVENDORGREETING", "TABARDVENDORNOGUILDGREETING", "PERSONALTABARDVENDORGREETING",
  "PERSONALTABARDVENDORUNOWNEDGREETING" } }

local CANDIDATES = {
  frame = { "TabardFrame" }, greeting = { "TabardFrameGreetingText" }, cost = { "TabardFrameCostLabel" },
  accept = { "TabardFrameAcceptButton" }, cancel = { "TabardFrameCancelButton" },
}
for i = 1, #ROWS do CANDIDATES["row" .. i] = { "TabardFrameCustomization" .. i .. "Text" } end

local function get(key) return Compat.get(SURFACE, key) end

-- hooksecurefunc target (TabardFrame_UpdateButtons). → 1 | 0
function Tabard.onUpdateButtons()
  local n = WFJ.Labels.show(SURFACE, "greeting", get("greeting"), nil, GREETING)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

function Tabard.onShow()
  local list = {
    { "cost", get("cost"), { only = { "TABARDVENDORCOST" } } },
    { "accept", get("accept"), { only = { "ACCEPT" } } },
    { "cancel", get("cancel"), { only = { "CANCEL" } } },
    { "greeting", get("greeting"), GREETING },
  }
  for i = 1, #ROWS do list[#list + 1] = { "row" .. i, get("row" .. i), { only = ROWS } } end
  return WFJ.Labels.showAll(SURFACE, list)
end

function Tabard.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Tabard.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  Compat.declare(SURFACE, "updateButtons", { "TabardFrame_UpdateButtons" })
  local frame = get("frame")
  if hooked or type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  hooked = true
  frame:HookScript("OnShow", Tabard.onShow)
  frame:HookScript("OnHide", Tabard.release)
  if type(get("updateButtons")) == "function" then
    hooksecurefunc("TabardFrame_UpdateButtons", Tabard.onUpdateButtons)
  end
  return true
end
