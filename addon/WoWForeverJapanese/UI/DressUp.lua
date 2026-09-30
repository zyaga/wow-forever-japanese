-- UI/DressUp.lua: the dressing room on Forever (surface "dressup", area "ui", ADR-016 / ADR-029).
-- camelot loads blizzard_uipanels_game/mainline/dressupframes.lua|xml and camelot/dressupframesoverrides.lua
-- (blizzard_uipanels_game.toc:27–29); DressUpFrame opens from DressUpItemLink / DressUpVisual (a Ctrl-clicked item,
-- dressupframes.lua:10–24, 88–108), SideDressUpFrame beside the windows that ask for it.
-- - Title: DressUpModelFrameMixin:OnLoad → self:SetTitle(DRESSUP_FRAME)
--   (blizzard_sharedxmlgame/dressupmodelframemixin.lua:155–158) → Labels.title.
-- - Static (XML text, shown on OnShow): DressUpFrameCancelButton CLOSE (dressupframes.xml:304),
--   DressUpFrame.ResetButton RESET (:434), DressUpFrame.LinkButton LINK_TRANSMOG_CUSTOM_SET (:444; shown while the
--   model is the player, dressupmodelframemixin.lua:134), SideDressUpFrame.ResetButton RESET (:100).
-- - Tooltip: DressUpFrame.ToggleCustomSetDetailsButton's inline OnEnter builds
--   GameTooltip_SetTitle(DRESSING_ROOM_APPEARANCE_LIST) (dressupframes.xml:383–387): a help-tooltip owner restricted
--   to that key.
-- The custom-set dropdown (WardrobeCustomSetDropdownTemplate,
--   blizzard_framexml/wardrobecustomsets.xml|lua): its empty text is SetDefaultText(grey-wrapped
--   TRANSMOG_CUSTOM_SET_NONE) (lua:22), shown in .Text by UpdateText; it is shown only while the text is colour-wrapped
--   so a saved set's name (the player's own, plain text) is never touched, even one that reads "No Custom Set". Its
--   SaveButton SAVE (xml:30). The menu's "+ New Custom Set" entry is UI/Menus' MENU_WARDROBE_CUSTOM_SETS (lua:101–150).
-- The appearance list's empty slot rows: DressUpCustomSetDetailsSlotMixin:SetAppearance writes
--   Name:SetFormattedText(TRANSMOG_EMPTY_SLOT_FORMAT "(%s)", the slot word) (mainline/dressupframes.lua:835–846). Its
--   English is PARENS_TEMPLATE's ("(%s)", an `entry` argument: the slot word in Japanese), so the rows are matched
--   with that key. The panel's Refresh (self:Refresh, :570) re-acquires its pooled rows; a post-hook on it walks the
--   active rows, each restricted to PARENS_TEMPLATE (an item or appearance name has no parentheses).
-- - The same rows' illusions, "Illusion: <name>" (TRANSMOGRIFIED_ENCHANT, SetDetails' name,
--   dressupframes.lua:909, 948): the one Refresh hook restricts each row to PARENS_TEMPLATE and TRANSMOGRIFIED_ENCHANT
--   (surface "dressup.slots", forgotten on each Refresh), the illusion's name kept as written.
-- Never touched: a saved custom set's name, the details panel's slot rows (item and appearance names,
-- dressupframes.lua:820–930).
-- Release each frame's records on its OnHide.
local _, WFJ = ...
local DressUp = {}
WFJ.DressUp = DressUp

local SURFACE = "dressup"
local SIDE = "dressup.side"
DressUp.SURFACE, DressUp.SIDE = SURFACE, SIDE
local Compat = WFJ.Compat

DressUp.NEVER_TOUCH = {}

local CANDIDATES = {
  frame = { "DressUpFrame" }, close = { "DressUpFrameCancelButton" },
  reset = { "DressUpFrame.ResetButton", "DressUpFrameResetButton" }, link = { "DressUpFrame.LinkButton" },
  toggle = { "DressUpFrame.ToggleCustomSetDetailsButton" },
  customSet = { "DressUpFrame.CustomSetDropdown" }, details = { "DressUpFrame.CustomSetDetailsPanel" },
  save = { "DressUpFrame.CustomSetDropdown.SaveButton" },
  side = { "SideDressUpFrame" }, sideReset = { "SideDressUpFrame.ResetButton" },
}

local TITLE = { only = { "DRESSUP_FRAME" } }
local RESET = { only = { "RESET" } }
local LIST_TOOLTIP = { only = { "DRESSING_ROOM_APPEARANCE_LIST" } }

local NO_SET = { only = { "TRANSMOG_CUSTOM_SET_NONE" } }
local function get(key) return Compat.get(SURFACE, key) end

-- The custom-set dropdown's text after UpdateText: the empty text only (colour-wrapped by the client); a saved set's
-- name is plain text and is never shown. → 1 | 0
function DressUp.onSetText(dropdown)
  local fs = type(dropdown) == "table" and dropdown.Text or nil
  local text = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
  if type(text) ~= "string" or text:sub(1, 2) ~= "|c" then
    WFJ.SurfaceState.drop(SURFACE, "customSet")
    return 0
  end
  return WFJ.Labels.show(SURFACE, "customSet", fs, nil, NO_SET)
end

function DressUp.onShow()
  local n = WFJ.Labels.title(SURFACE, get("frame"), TITLE)
  return n + WFJ.Labels.showAll(SURFACE, {
    { "close", get("close"), { only = { "CLOSE" } } },
    { "reset", get("reset"), RESET },
    { "link", get("link"), { only = { "LINK_TRANSMOG_CUSTOM_SET" } } },
    { "save", get("save"), { only = { "SAVE" } } },
  }) + DressUp.onSetText(get("customSet"))
end

function DressUp.onSideShow()
  return WFJ.Labels.showAll(SIDE, { { "reset", get("sideReset"), RESET } })
end

-- The details panel's slot rows after its Refresh (see the header): an empty slot's "(Head)" and an
-- illusion's "Illusion: <name>". → the number of rows shown
local SLOTS = SURFACE .. ".slots"
DressUp.SLOTS = SLOTS
local SLOT_ROW = { only = { "PARENS_TEMPLATE", "TRANSMOGRIFIED_ENCHANT" } }
local slotKey = WFJ.Labels.keyer("slot.")
function DressUp.onDetails()
  WFJ.Render.forget(SLOTS) -- the pool was released and refilled
  local panel = get("details")
  local pool = type(panel) == "table" and panel.slotPool or nil
  local n = 0
  if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
    for row in pool:EnumerateActive() do
      local name = type(row) == "table" and row.Name or nil
      if type(name) == "table" then n = n + WFJ.Labels.show(SLOTS, slotKey(name), name, nil, SLOT_ROW) end
    end
  end
  WFJ.Render.updateBanner(SLOTS)
  return n
end

function DressUp.release() return WFJ.Render.release(SURFACE) + WFJ.Render.release(SLOTS) end
function DressUp.releaseSide() return WFJ.Render.release(SIDE) end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function DressUp.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  hooked = true
  frame:HookScript("OnShow", DressUp.onShow)
  frame:HookScript("OnHide", DressUp.release)
  local side = get("side")
  if type(side) == "table" and type(side.HookScript) == "function" then
    side:HookScript("OnShow", DressUp.onSideShow)
    side:HookScript("OnHide", DressUp.releaseSide)
  end
  local toggle = get("toggle")
  if type(toggle) == "table" then WFJ.HelpTooltip.register(toggle, LIST_TOOLTIP) end
  local details = get("details")
  if type(details) == "table" and type(details.Refresh) == "function" then
    hooksecurefunc(details, "Refresh", DressUp.onDetails)
  end
  local customSet = get("customSet")
  if type(customSet) == "table" and type(customSet.UpdateText) == "function" then
    hooksecurefunc(customSet, "UpdateText", DressUp.onSetText)
  end
  DressUp.onShow() -- the title was written at load
  return true
end
