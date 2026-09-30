-- UI/AddonList.lua: the AddOn List window on Forever (surfaces "addonlist" and "addonlist.static", area "ui",
-- ADR-016). Blizzard_AddonList is loaded at login; the window opens from the game menu's AddOns button
-- (blizzard_gamemenu/shared/gamemenuframe.lua:230) and from the performance warning
-- (blizzard_addonperformance/addonperformance.lua:21). UI/AddonListButton.lua only adds this addon's Settings button
-- to a row; this module shows the window's own fixed words. Every widget is a parentKey of AddonList
-- (blizzard_addonlist/addonlist.xml:120–235).
-- Static (XML text=): the title, AddonList:SetTitle(ADDON_LIST) in OnLoad (addonlist.lua:232, Labels.title);
--   ForceLoad's unnamed ADDON_FORCE_LOAD label (xml:137), Performance.Header (xml:160), CancelButton,
--   EnableAllButton, DisableAllButton (xml:190–208).
-- Dynamic:
--   AddonList_Update (global, addonlist.lua:440–547) → OkayButton: RELOADUI or OKAY (:541, :544);
--   AddonList:UpdatePerformance (the frame's own method, every frame while shown, lua:688–773) → Performance.Current /
--     Average / Peak, "Current CPU: %s" around a percentage. Each is restricted to its own key, so the per-frame pass
--     matches one template. With a warning the text is wrapped in a colour and ends in a texture (lua:743–744): it
--     matches nothing and stays English; its hover ADDON_LIST_PERFORMANCE_WARNING_TOOLTIP is a help tooltip;
--   AddonList_InitAddon(entry, treeNode) (global, looked up on every row build, lua:275, 352–438) → the row's Status
--     (`_G["ADDON_" .. reason]`, :409: "Disabled", "Dependency missing", …), Reload (REQUIRES_RELOAD, xml:64) and
--     LoadAddonButton (LOAD_ADDON, xml:82). Rows are pooled: keyed by widget;
--   the row tooltip (AddonTooltip_Update, lua:851–893; AddonTooltip is GameTooltip in game, :183): the owner is the
--     row, restricted to the fixed lines: ADDON_BANNED_TOOLTIP, INTERFACE_ACTION_BLOCKED_TOOLTIP, the CPU and memory
--     lines, and the "Dependencies: " prefix, the addon names after it kept as written. The first line is
--     the addon's title, the next its own notes: never matched. It is rebuilt every frame
--     while hovered (lua:1009–1011). The Enabled checkbox's ENABLED_FOR_SOME (lua:375, 1025–1031);
--   the character dropdown (lua:642–667): ALL, or the player's own name. Its text is shown only when it is ALL and
--     the player is not called that.
-- Never touched: a row's Title (the addon's name and icon), a category row's Title (the addon's own Category, or the
-- client's untranslated "Uncategorized" literal, lua:478), the search box.
local _, WFJ = ...
local AddonList = {}
WFJ.AddonList = AddonList

local SURFACE = "addonlist"
AddonList.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
local Compat = WFJ.Compat

AddonList.NEVER_TOUCH = { "AddonList.SearchBox" }

local CANDIDATES = {
  frame = { "AddonList" }, update = { "AddonList_Update" },
  initAddon = { "AddonList_InitAddon" }, okay = { "AddonList.OkayButton" }, cancel = { "AddonList.CancelButton" },
  enableAll = { "AddonList.EnableAllButton" }, disableAll = { "AddonList.DisableAllButton" },
  forceLoad = { "AddonList.ForceLoad" }, perfHeader = { "AddonList.Performance.Header" },
  current = { "AddonList.Performance.Current" }, average = { "AddonList.Performance.Average" },
  peak = { "AddonList.Performance.Peak" }, dropdown = { "AddonList.Dropdown" }, unitName = { "UnitName" },
}

local TITLE = { only = { "ADDON_LIST" } }
local OKAY = { only = { "OKAY", "RELOADUI" } }
local PERF = { { "current", "ADDON_LIST_PERFORMANCE_CURRENT_CPU" }, { "average", "ADDON_LIST_PERFORMANCE_AVERAGE_CPU" },
  { "peak", "ADDON_LIST_PERFORMANCE_PEAK_CPU" } }
for _, p in ipairs(PERF) do p[3] = { only = { p[2] } } end
local PERF_WARNING = { only = { "ADDON_LIST_PERFORMANCE_WARNING_TOOLTIP" } }
-- C_AddOns.IsAddOnLoadable's reasons, as `_G["ADDON_" .. reason]`
local STATUS = { only = { "ADDON_MISSING", "ADDON_DISABLED", "ADDON_BANNED", "ADDON_CORRUPT", "ADDON_INSECURE",
  "ADDON_INTERFACE_VERSION", "ADDON_INCOMPATIBLE", "ADDON_DEMAND_LOADED", "ADDON_NOT_AVAILABLE",
  "ADDON_EXCLUDED_FROM_BUILD", "ADDON_NO_ACTIVE_INTERFACE", "ADDON_WRONG_ACTIVE_INTERFACE", "ADDON_WRONG_GAME_TYPE",
  "ADDON_WRONG_LOAD_PHASE", "ADDON_USER_ADDONS_DISABLED", "ADDON_UNKNOWN_ERROR", "ADDON_DEP_MISSING",
  "ADDON_DEP_DISABLED", "ADDON_DEP_BANNED", "ADDON_DEP_CORRUPT", "ADDON_DEP_INSECURE",
  "ADDON_DEP_INTERFACE_VERSION", "ADDON_DEP_INCOMPATIBLE", "ADDON_DEP_DEMAND_LOADED", "ADDON_DEP_NOT_AVAILABLE",
  "ADDON_DEP_EXCLUDED_FROM_BUILD", "ADDON_DEP_NO_ACTIVE_INTERFACE", "ADDON_DEP_WRONG_ACTIVE_INTERFACE",
  "ADDON_DEP_WRONG_GAME_TYPE", "ADDON_DEP_WRONG_LOAD_PHASE" } }
local RELOAD = { only = { "REQUIRES_RELOAD" } }
local LOAD = { only = { "LOAD_ADDON" } }
local ROW_TOOLTIP = { only = { "ADDON_BANNED_TOOLTIP", "INTERFACE_ACTION_BLOCKED_TOOLTIP",
  "ADDON_LIST_PERFORMANCE_AVERAGE_CPU", "ADDON_LIST_PERFORMANCE_CURRENT_CPU", "ADDON_LIST_PERFORMANCE_PEAK_CPU",
  "ADDON_LIST_PERFORMANCE_ENCOUNTER_CPU", "ADDON_LIST_PERFORMANCE_MEMORY_MB", "ADDON_LIST_PERFORMANCE_MEMORY_KB",
  "ADDON_DEPENDENCIES" } } -- "Dependencies: <addon>, <addon>" (AddonTooltip_BuildDeps, lua:832–843, 865)
local ENABLED_TOOLTIP = { only = { "ENABLED_FOR_SOME" } }
local ALL = { only = { "ALL" } }

local function get(key) return Compat.get(SURFACE, key) end

local rowKey = WFJ.Labels.keyer("row.") -- a pooled row widget's record key: follows the widget

-- hooksecurefunc target (AddonList_InitAddon): one pooled row after the client filled it. Returns nothing.
function AddonList.onRow(entry)
  if type(entry) ~= "table" then return end
  local show = WFJ.Labels.show
  for _, part in ipairs({ { "Status", STATUS }, { "Reload", RELOAD }, { "LoadAddonButton", LOAD } }) do
    local w = entry[part[1]]
    if type(w) == "table" then show(SURFACE, rowKey(w), w, nil, part[2]) end
  end
  WFJ.HelpTooltip.register(entry, ROW_TOOLTIP)
  if type(entry.Enabled) == "table" then WFJ.HelpTooltip.register(entry.Enabled, ENABLED_TOOLTIP) end
end

-- hooksecurefunc target (AddonList_Update). → 1 | 0
function AddonList.onUpdate()
  return WFJ.Labels.show(SURFACE, "okay", get("okay"), nil, OKAY)
end

-- hooksecurefunc target (AddonList:UpdatePerformance, every frame while shown). → the number of words found.
function AddonList.onPerformance()
  local n = 0
  for _, p in ipairs(PERF) do n = n + WFJ.Labels.show(SURFACE, p[1], get(p[1]), nil, p[3]) end
  return n
end

-- The dropdown's own text: ALL, unless that is what the player is called (the other entry is the player's name).
-- hooksecurefunc target (Dropdown:UpdateText). → 1 | 0
function AddonList.onDropdown()
  local dropdown = get("dropdown")
  local text = type(dropdown) == "table" and dropdown.Text or nil
  if type(text) ~= "table" or type(text.GetText) ~= "function" then return 0 end
  local unitName = get("unitName")
  local player = type(unitName) == "function" and unitName("player") or nil
  local rec = WFJ.SurfaceState.get(SURFACE, "dropdown")
  local ours = rec and rec.fs == text and rec.applied ~= nil and text:GetText() == rec.applied
  if not ours and (player == nil or text:GetText() == player) then
    WFJ.SurfaceState.drop(SURFACE, "dropdown")
    return 0
  end
  return WFJ.Labels.show(SURFACE, "dropdown", text, nil, ALL)
end

-- The labels the client writes once. → the number of dictionary words found.
function AddonList.showStatic()
  local force = get("forceLoad")
  local n = WFJ.Labels.showAll(STATIC, {
    { "cancel", get("cancel"), { only = { "CANCEL" } } },
    { "enableAll", get("enableAll"), { only = { "ENABLE_ALL_ADDONS" } } },
    { "disableAll", get("disableAll"), { only = { "DISABLE_ALL_ADDONS" } } },
    { "perfHeader", get("perfHeader"), { only = { "ADDON_LIST_PERFORMANCE_HEADER" } } },
    { "forceLoad", WFJ.Labels.region(force, "ADDON_FORCE_LOAD"), { only = { "ADDON_FORCE_LOAD" } } },
  })
  return n + WFJ.Labels.title(STATIC, get("frame"), TITLE)
end

-- HookScript target (AddonList OnShow).
function AddonList.onShow()
  local n = AddonList.showStatic() + AddonList.onUpdate() + AddonList.onPerformance() + AddonList.onDropdown()
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function AddonList.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  if type(get("initAddon")) == "function" then hooksecurefunc("AddonList_InitAddon", AddonList.onRow) end
  if type(get("update")) == "function" then hooksecurefunc("AddonList_Update", AddonList.onUpdate) end
  if type(frame.UpdatePerformance) == "function" then
    hooksecurefunc(frame, "UpdatePerformance", AddonList.onPerformance)
  end
  local dropdown = get("dropdown")
  if type(dropdown) == "table" and type(dropdown.UpdateText) == "function" then
    hooksecurefunc(dropdown, "UpdateText", AddonList.onDropdown)
  end
  for _, key in ipairs({ "current", "average", "peak" }) do
    local fs = get(key)
    if type(fs) == "table" then WFJ.HelpTooltip.register(fs, PERF_WARNING) end
  end
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", AddonList.onShow) end
  AddonList.onShow()
  return true
end
