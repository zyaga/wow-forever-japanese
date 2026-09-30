-- UI/DamageMeter.lua: the built-in damage meter's session windows on Forever (surface "damagemeter", area "ui",
-- ADR-016). Blizzard_DamageMeter is a login addon whose TOC names camelot (`## AllowLoadGameType: standard,
-- camelot`, blizzard_damagemeter.toc:2); the DamageMeter frame (damagemeter.xml:11) is shown while the
-- `damageMeterEnabled` CVar is on and C_DamageMeter.IsDamageMeterAvailable() (damagemeter.lua:166–199). Without
-- the DamageMeter frame init returns false.
-- A session window is created on demand, up to three, by DamageMeterMixin:SetupSessionWindow as the global
-- "DamageMeterSessionWindow<i>" (damagemeter.lua:284–285), at VARIABLES_LOADED for the saved windows and later from
-- the settings menu's "Create New Window". The existing globals are taken at init and DamageMeter:SetupSessionWindow
-- is post-hooked for the later ones (its second argument carries `sessionWindow`, lua:287–289). The mixin is copied
-- onto each window and every call is `self:…()` / `sessionWindow:…()`, so the writers are post-hooked per window:
--   :SetDamageMeterType (damagemetersessionwindow.lua:800–811) → DamageMeterTypeDropdown.TypeName, one of the
--     DAMAGE_METER_TYPE_* words (lua:34–50; xml:75);
--   :UpdateNotActiveText (lua:711–717) → MinimizeContainer.NotActive, DAMAGE_METER_AVOIDABLE_DAMAGE_NOT_ACTIVE or
--     nothing (xml:95).
-- Both are fixed words from Lua tables, never combat values. Everything else in the window is a source / spell
-- row (a player, creature or spell name and numbers that may be secret values in combat), the session timer, or the
-- one-letter session abbreviation: never read, never written.
-- Not rendered here: the session abbreviation "C" / "O" (the dropdown is sized from the English length at load,
-- lua:64–73, xml:48–49). The type / session / settings menus' entries are UI/Menus tags (UI/MenusTags); the
-- sessions menu's combat entries come here (DamageMeter.showSession).
local _, WFJ = ...
local DamageMeter = {}
WFJ.DamageMeter = DamageMeter

local SURFACE = "damagemeter"
DamageMeter.SURFACE = SURFACE
local Compat = WFJ.Compat

local MAX_WINDOWS = 3 -- MAX_DAMAGE_METER_SESSION_WINDOWS (damagemeter.lua:4)
local function windowName(i) return "DamageMeterSessionWindow" .. i end

local NEVER = {}
for i = 1, MAX_WINDOWS do
  NEVER[#NEVER + 1] = windowName(i) .. ".SessionDropdown.SessionName"
  NEVER[#NEVER + 1] = windowName(i) .. ".SessionTimer"
end
DamageMeter.NEVER_TOUCH = NEVER

local TYPE = { only = { "DAMAGE_METER_TYPE_DAMAGE_DONE", "DAMAGE_METER_TYPE_HEALING_DONE",
  "DAMAGE_METER_TYPE_ABSORBS", "DAMAGE_METER_TYPE_INTERRUPTS", "DAMAGE_METER_TYPE_DISPELS",
  "DAMAGE_METER_TYPE_DAMAGE_TAKEN", "DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN", "DAMAGE_METER_TYPE_DEATHS",
  "DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN" } }
local NOT_ACTIVE = { only = { "DAMAGE_METER_AVOIDABLE_DAMAGE_NOT_ACTIVE" } }

local windowKey = WFJ.Labels.keyer("window.") -- records follow the window object, never its index

local function child(parent, field)
  local value = type(parent) == "table" and parent[field] or nil
  return type(value) == "table" and value or nil
end

-- hooksecurefunc target (window:SetDamageMeterType). → 1 | 0
function DamageMeter.onType(window)
  local text = child(child(window, "DamageMeterTypeDropdown"), "TypeName")
  return WFJ.Labels.show(SURFACE, windowKey(window) .. ".type", text, nil, TYPE)
end

-- hooksecurefunc target (window:UpdateNotActiveText). → 1 | 0
function DamageMeter.onNotActive(window)
  local text = child(child(window, "MinimizeContainer"), "NotActive")
  return WFJ.Labels.show(SURFACE, windowKey(window) .. ".notActive", text, nil, NOT_ACTIVE)
end

-- A combat session's radio in the sessions menu is "<name> [<duration>]": the name DAMAGE_METER_COMBAT_NUMBER
-- ("Combat %d") when the session has none, then ("%s [%s]"):format(name, SecondsToClock(seconds))
-- (damagemetersessionwindow.lua:418–428). The head is matched against that one key; the bracketed duration is kept
-- as shown (the `wrapped` fill: text kept around the entry). An encounter's own name matches nothing and stays.
local SESSION = { "DAMAGE_METER_COMBAT_NUMBER" }

-- MENU_DAMAGE_METER_SESSIONS' `show` (UI/Menus.showElement, after the whole-line match found nothing). → 1 | 0
function DamageMeter.showSession(surface, recKey, fs)
  local index = WFJ.UIIndex
  local en = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
  if not index or type(en) ~= "string" or WFJ.Labels.forbidden(fs) then return 0 end
  local head, suffix = en:match("^(.-)( %[[%d:]+%])$")
  if not head or head == "" then return 0 end
  local key, args = index:matchOnly(head, SESSION)
  if not key then return 0 end
  WFJ.Render.show(surface, recKey, fs, en, "ui", "ui", key,
    { args = { form = "wrapped", open = "", close = suffix, inner = args } })
  return 1
end

local followed = setmetatable({}, { __mode = "k" })

-- Follows one session window (once) and shows its two labels. → the number of dictionary words found.
function DamageMeter.follow(window)
  if type(window) ~= "table" then return 0 end
  if not followed[window] then
    followed[window] = true
    -- a window made after load was not there when Main registered NEVER_TOUCH: forbid its two widgets now
    WFJ.Labels.forbid(child(child(window, "SessionDropdown"), "SessionName"))
    WFJ.Labels.forbid(child(window, "SessionTimer"))
    if type(window.SetDamageMeterType) == "function" then
      hooksecurefunc(window, "SetDamageMeterType", DamageMeter.onType)
    end
    if type(window.UpdateNotActiveText) == "function" then
      hooksecurefunc(window, "UpdateNotActiveText", DamageMeter.onNotActive)
    end
  end
  local n = DamageMeter.onType(window) + DamageMeter.onNotActive(window)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (DamageMeter:SetupSessionWindow(windowDataIndex, windowData)).
function DamageMeter.onSetup(_, _, windowData)
  return DamageMeter.follow(type(windowData) == "table" and windowData.sessionWindow or nil)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function DamageMeter.init()
  Compat.declare(SURFACE, "frame", { "DamageMeter" })
  for i = 1, MAX_WINDOWS do Compat.declare(SURFACE, "window" .. i, { windowName(i) }) end
  local frame = Compat.get(SURFACE, "frame")
  if hooked or type(frame) ~= "table" then return false end -- no DamageMeter
  hooked = true
  if type(frame.SetupSessionWindow) == "function" then
    hooksecurefunc(frame, "SetupSessionWindow", DamageMeter.onSetup)
  end
  for i = 1, MAX_WINDOWS do DamageMeter.follow(Compat.get(SURFACE, "window" .. i)) end
  return true
end
