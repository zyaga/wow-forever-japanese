-- UI/GossipChrome.lua: the gossip window's fixed words (surface "gossip.chrome", area "ui", ADR-016).
-- Static: the Goodbye button (XML text="GOODBYE"; nothing rewrites it; a fixed 78×22 UIPanelButtonTemplate that only
-- resizes through SetTextToFit, which nothing calls) [verified: classic_era Blizzard_UIPanels_Game/Classic/
-- GossipFrame.xml:48–58].
-- Rows: the greeting list is a pooled ScrollBox (UpdateScrollBox, run once from OnLoad) [verified: Shared/
-- GossipFrameShared.lua:119–168, Classic/GossipFrame.lua:3–11]. A quest row's text is written by
-- UpdateTitleForQuest with SetFormattedText on the row button: IGNORED_QUEST_DISPLAY / TRIVIAL_QUEST_DISPLAY /
-- NORMAL_QUEST_DISPLAY around the quest title [verified: GossipFrameShared.lua:27–42]. Only the "(ignored)" /
-- "(low level)" suffix is chrome: those two templates are matched with `only`, and the title is an ARGS `text` capture
-- (verbatim: names stay in English). Rows are followed through Blizzard's own subscriber API,
-- ScrollUtil.AddInitializedFrameCallback with iterateExisting, which fires after every row initializer, including
-- rows acquired later while scrolling [verified: Blizzard_SharedXML/Shared/Scroll/ScrollUtil.lua:21–30,
-- ScrollBoxListView.lua:383–396]. The element data carries buttonType (GOSSIP_BUTTON_TYPE_ACTIVE_QUEST 4 /
-- _AVAILABLE_QUEST 5) and info = questInfo with isTrivial / isIgnored [verified: GossipFrameShared.lua:1–5,
-- 256–274]. Option rows, normal quest rows and the greeting (UI/Gossip) are never matched; a pooled row reused for
-- one of them drops our record (never restored over the client's text).
-- The height calculator measures hidden spare buttons with the English (GossipFrameShared.lua:124–140, 244–249); the
-- Japanese suffix is shorter, so the row does not re-layout.
-- Untouched: the title, which is the NPC name (SetGossipTitle(UnitName("npc")), GossipFrameShared.lua:286,
-- Classic/GossipFrame.lua:66–68). Release on GossipFrame's OnHide (a mixin method binding; HookScript runs after it).
local _, WFJ = ...
local GossipChrome = {}
WFJ.GossipChrome = GossipChrome

local SURFACE = "gossip.chrome" -- its own surface: UI/Gossip owns "gossip" (greeting, options)
GossipChrome.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
GossipChrome.STATIC = STATIC
local Compat = WFJ.Compat

-- Widgets this module must never record: the NPC name on the title plate (ButtonFrameTemplate's $parentTitleText).
GossipChrome.NEVER_TOUCH = { "GossipFrameTitleText" }

local SUFFIX_KEYS = { "TRIVIAL_QUEST_DISPLAY", "IGNORED_QUEST_DISPLAY" }
local questTypes = { [4] = true, [5] = true } -- replaced at init by the client's constants when they resolve

local rowKeys = setmetatable({}, { __mode = "k" }) -- pooled row button → its record key
local rowCount = 0

local function rowKey(frame)
  local key = rowKeys[frame]
  if not key then
    rowCount = rowCount + 1
    key = "row" .. rowCount
    rowKeys[frame] = key
  end
  return key
end

-- ScrollUtil callback. The OnInitializedFrame event passes (owner, frame, elementData); iterateExisting runs
-- scrollBox:ForEachFrame(callback), which passes (frame, elementData) and stops at a truthy return [verified:
-- ScrollUtil.lua:22–24, ScrollBoxListView.lua:136–145], so both shapes are accepted and nothing is returned.
function GossipChrome.onRow(a, b, c)
  local frame, data = b, c
  if a ~= GossipChrome then frame, data = a, b end
  if type(frame) ~= "table" then return end
  local key = rowKey(frame)
  local info = type(data) == "table" and data.info
  if type(info) == "table" and questTypes[data.buttonType] and (info.isTrivial or info.isIgnored) then
    WFJ.Labels.show(SURFACE, key, frame, nil, { only = SUFFIX_KEYS })
  else
    WFJ.SurfaceState.drop(SURFACE, key) -- an option / normal quest / greeting row: never ours
  end
  WFJ.Render.updateBanner(SURFACE)
end

function GossipChrome.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function GossipChrome.init()
  Compat.declare(SURFACE, "frame", { "GossipFrame" })
  Compat.declare(SURFACE, "scrollUtil", { "ScrollUtil" })
  Compat.declare(SURFACE, "activeQuest", { "GOSSIP_BUTTON_TYPE_ACTIVE_QUEST" })
  Compat.declare(SURFACE, "availableQuest", { "GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST" })
  if hooked then return false end
  local frame = Compat.get(SURFACE, "frame")
  local panel = type(frame) == "table" and frame.GreetingPanel
  if type(panel) ~= "table" then return false end
  hooked = true
  local active, available = Compat.get(SURFACE, "activeQuest"), Compat.get(SURFACE, "availableQuest")
  if type(active) == "number" and type(available) == "number" then
    questTypes = { [active] = true, [available] = true }
  end
  WFJ.Labels.showAll(STATIC, { { "ui.goodbye", panel.GoodbyeButton } })
  local util = Compat.get(SURFACE, "scrollUtil")
  if type(panel.ScrollBox) == "table" and type(util) == "table"
      and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(panel.ScrollBox, GossipChrome.onRow, GossipChrome, true)
  end
  if frame.HookScript then frame:HookScript("OnHide", GossipChrome.release) end
  return true
end
