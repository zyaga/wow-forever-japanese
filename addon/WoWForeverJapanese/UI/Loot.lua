-- UI/Loot.lua: the loot window on Forever (surface "loot", area "ui", ADR-016 / ADR-029).
-- camelot loads blizzard_uipanels_game/mainline/lootframe.lua|xml and scrollingflatpanel.lua|xml. LootFrame is a
-- ScrollingFlatPanelTemplate (lootframe.xml:116), opened on LOOT_OPENED (lootframe.lua:59, 131–150). A LootFrame
-- without its ScrollBox is not this shape: init returns false.
-- - Title: ScrollingFlatPanelMixin:OnLoad → self:SetTitle(self.panelTitle), panelTitle = ITEMS (scrollingflatpanel.lua:
--   5–6; lootframe.xml:119) → Labels.title.
-- - Rows: LootFrameMixin:Open fills the ScrollBox (lootframe.lua:233–262); each item row's initializer runs
--   LootFrameItemElementMixin:Init, which writes QualityText = _G["ITEM_QUALITY<n>_DESC"] (:621–626) and Text = the
--   item's name (:490). Rows are ScrollBox frames: followed with ScrollUtil.AddInitializedFrameCallback, keyed by the
--   QualityText widget, restricted to the quality words. A money row has no QualityText (lootframe.xml:100–113).
-- Never touched: a row's Text (the item or coin text) and Item.Count.
-- The gamepad prompts (FRAME_ACTION_LOOT / _LOOT_ALL / _CLOSE, :350–358) are not widgets of this window.
-- Release on LootFrame's OnHide.
local _, WFJ = ...
local Loot = {}
WFJ.Loot = Loot

local SURFACE = "loot"
Loot.SURFACE = SURFACE
local Compat = WFJ.Compat

Loot.NEVER_TOUCH = {} -- rows are pooled and unnamed: their name text is simply never read (see onRow)

local TITLE = { only = { "ITEMS" } }
local QUALITY = { only = {} }
-- 1–7 (Common … Heirloom). Not 0: "Poor" is also RESISTANCE_POOR's English, and one English takes one Japanese
-- (a resistance rating's word is wrong for an item); it stays English. Not 8: "WoW Token" is a product's name.
for i = 1, 7 do QUALITY.only[#QUALITY.only + 1] = "ITEM_QUALITY" .. i .. "_DESC" end
Loot.QUALITY_KEYS = QUALITY.only

local rowKey = WFJ.Labels.keyer("quality.")

local function get(key) return Compat.get(SURFACE, key) end

-- ScrollUtil callback: (owner, frame, elementData) for a new row, (frame, elementData) for the iterateExisting pass
-- (blizzard_sharedxml/shared/scroll/scrollutil.lua AddInitializedFrameCallback). Returns nothing: ForEachFrame stops
-- at the first truthy return.
function Loot.onRow(a, b)
  local row = a
  if a == Loot then row = b end
  local quality = type(row) == "table" and row.QualityText or nil
  if type(quality) ~= "table" then return end
  WFJ.Labels.show(SURFACE, rowKey(quality), quality, nil, QUALITY)
end

function Loot.onShow()
  local n = WFJ.Labels.title(SURFACE, get("frame"), TITLE)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

function Loot.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Loot.init()
  Compat.declare(SURFACE, "frame", { "LootFrame" })
  Compat.declare(SURFACE, "scrollUtil", { "ScrollUtil" })
  local frame = get("frame")
  if hooked or type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  if type(frame.ScrollBox) ~= "table" then return false end -- no ScrollBox to follow: not this shape
  hooked = true
  frame:HookScript("OnShow", Loot.onShow)
  frame:HookScript("OnHide", Loot.release)
  local util = get("scrollUtil")
  if type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(frame.ScrollBox, Loot.onRow, Loot, true)
  end
  Loot.onShow()
  return true
end
