-- UI/MapLegend.lua: the world map's legend panel on Forever (surface "maplegend", area "ui", ADR-016 /
-- ADR-029). camelot loads blizzard_uipanels_game/mainline/maplegendframe.lua|xml, mainline/maplegendframedata.lua and
-- camelot/maplegendframedata.lua; the panel is QuestMapFrame.MapLegend (questmapframe.xml:954), its side tab
-- QuestMapFrame.MapLegendTab (:459–466).
-- Reachability: camelot hides the tab (camelot/questmapframeoverrides.lua:6; questmapframe.lua:245–246), and
-- WorldMapMixin:UninitializeGamepad shows it again unconditionally (blizzard_worldmap/blizzard_worldmap.lua:1188), so
-- the legend opens after a gamepad-mode session. The camelot data file lists what it holds: three categories and
-- seven entries (camelot/maplegendframedata.lua:1–16). Whether it shows in ordinary play is an in-game check.
-- - MapLegendMixin:SetupCategories builds everything once, at the panel's OnLoad (maplegendframe.lua:3–33): a
--   MapLegendCategoryTemplate per category (TitleText = MAP_LEGEND_CATEGORY_*) under ScrollFrame.ScrollChild, and a
--   MapLegendButtonTemplate per entry (button text = MAP_LEGEND_<entry>). They are unnamed children, reached with
--   GetChildren and keyed by widget. Static labels, shown on the panel's OnShow.
-- - The panel's own heading: BorderFrame-level TitleText = MAP_LEGEND_FRAME_LABEL (maplegendframe.xml:41).
-- - Tooltips: MapLegendButtonMixin:OnEnter builds the entry's name and MAP_LEGEND_<entry>_TOOLTIP on GameTooltip with
--   the button as owner (maplegendframe.lua:37–44); the tab's tooltip is its tooltipText MAP_LEGEND_FRAME_LABEL
--   (SidePanelTabButtonMixin:OnEnter, blizzard_sharedxml/mainline/shareduipaneltemplates.lua:406–420). Each is a
--   help-tooltip owner restricted to the legend's keys.
-- No name appears on this panel; every widget is still restricted to the legend's own keys.
local _, WFJ = ...
local MapLegend = {}
WFJ.MapLegend = MapLegend

local SURFACE = "maplegend"
MapLegend.SURFACE = SURFACE
local Compat = WFJ.Compat

MapLegend.NEVER_TOUCH = {}

-- camelot/maplegendframedata.lua:1–5 → mainline/maplegendframedata.lua:16–19, 26–27, 34
local ENTRIES = { "MAP_LEGEND_REPEATABLE", "MAP_LEGEND_LOCALSTORY", "MAP_LEGEND_INPROGRESS", "MAP_LEGEND_TURNIN",
  "MAP_LEGEND_DUNGEON", "MAP_LEGEND_RAID", "MAP_LEGEND_FLIGHTPOINT" }
local CATEGORY = { only = { "MAP_LEGEND_CATEGORY_QUESTS", "MAP_LEGEND_CATEGORY_ACTIVITIES",
  "MAP_LEGEND_CATEGORY_MOVEMENT" } }
local ENTRY = { only = ENTRIES }
local TOOLTIP = { only = {} }
for _, key in ipairs(ENTRIES) do
  TOOLTIP.only[#TOOLTIP.only + 1] = key
  TOOLTIP.only[#TOOLTIP.only + 1] = key .. "_TOOLTIP"
end
local LABEL = { only = { "MAP_LEGEND_FRAME_LABEL" } }
MapLegend.KEYS = { category = CATEGORY.only, entry = ENTRIES, tooltip = TOOLTIP.only }

local categoryKey = WFJ.Labels.keyer("category.")
local entryKey = WFJ.Labels.keyer("entry.")

local function get(key) return Compat.get(SURFACE, key) end

local function children(frame)
  if type(frame) ~= "table" or type(frame.GetChildren) ~= "function" then return {} end
  return { frame:GetChildren() }
end

-- Every category and entry under the scroll child. `each(kind, widget)`.
local function walk(each)
  local panel = get("panel")
  local scroll = type(panel) == "table" and panel.ScrollFrame or nil
  local child = type(scroll) == "table" and scroll.ScrollChild or nil
  for _, category in ipairs(children(child)) do
    if type(category) == "table" and type(category.TitleText) == "table" then
      each("category", category)
      for _, button in ipairs(children(category)) do
        if type(button) == "table" and type(button.GetFontString) == "function" then each("entry", button) end
      end
    end
  end
end

-- The panel's OnShow. → the number of dictionary words found.
function MapLegend.onShow()
  local panel = get("panel")
  local list = { { "label", type(panel) == "table" and panel.TitleText or nil, LABEL } }
  walk(function(kind, widget)
    if kind == "category" then
      list[#list + 1] = { categoryKey(widget), widget.TitleText, CATEGORY }
    else
      list[#list + 1] = { entryKey(widget), widget, ENTRY }
    end
  end)
  return WFJ.Labels.showAll(SURFACE, list)
end

function MapLegend.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init. Without QuestMapFrame: false.
function MapLegend.init()
  Compat.declare(SURFACE, "panel", { "QuestMapFrame.MapLegend" })
  Compat.declare(SURFACE, "tab", { "QuestMapFrame.MapLegendTab" })
  local panel = get("panel")
  if hooked or type(panel) ~= "table" or type(panel.HookScript) ~= "function" then return false end
  hooked = true
  panel:HookScript("OnShow", MapLegend.onShow)
  panel:HookScript("OnHide", MapLegend.release)
  walk(function(kind, widget)
    if kind == "entry" then WFJ.HelpTooltip.register(widget, TOOLTIP) end
  end)
  local tab = get("tab")
  if type(tab) == "table" then WFJ.HelpTooltip.register(tab, LABEL) end
  return true
end
