-- UI/NamePlateSetting.lua: the client's own nameplate setting for friendly NPCs, kept in step with the names choice.
-- A name over a creature's head is drawn by the client in the game world, where no addon can write. A unit with a
-- nameplate shows its name there instead, and a nameplate's name is a widget (UI/UnitFrames writes it). So Japanese
-- names over the heads of friendly NPCs need the client's "friendly NPC nameplates" setting on
-- [verified: forever-ui-1.60.1.71037 blizzard_nameplates/blizzard_nameplateconstants.lua:19, the CVar's name].
-- When the player chooses Japanese names the setting is turned on and its value before that is kept in the saved
-- settings; choosing English names puts that value back. A value the player sets by hand afterwards is left alone:
-- with Japanese names on and the nameplates off, one chat line says names over heads are English, when it happens
-- and once at each login.
-- Nameplate settings are refused in combat [likely; the in-game check is in docs/testing/strategy.md], so a write
-- asked for in combat waits for PLAYER_REGEN_ENABLED (Main routes it to flush).
--   NamePlateSetting.start(db)   after the saved settings applied: follows the names choice from here on, and says
--                                the login line when it is owed
--   NamePlateSetting.flush()     combat ended
local _, WFJ = ...
local NamePlateSetting = {}
WFJ.NamePlateSetting = NamePlateSetting

local Compat = WFJ.Compat
local NAMESPACE = "nameplatesetting"
NamePlateSetting.SURFACE = NAMESPACE -- a Compat namespace, not a translated surface
NamePlateSetting.CVAR = "nameplateShowFriendlyNpcs"
local API = { inCombat = { "InCombatLockdown" }, cvars = { "C_CVar" } }
for key, cands in pairs(API) do Compat.declare(NAMESPACE, key, cands) end
NamePlateSetting.API = API

local db, watcher
local pending -- the value a write in combat is waiting to set
local wasOn   -- whether the nameplates were on at the last look, so the line is said when they go off, once

local function cvars()
  local C = Compat.resolve("C_CVar")
  if type(C) == "table" and type(C.GetCVar) == "function" and type(C.SetCVar) == "function" then return C end
  return nil
end

local function inCombat()
  local fn = Compat.resolve("InCombatLockdown")
  return type(fn) == "function" and fn() and true or false
end

-- → true / false, or nil when the client has no such setting
local function isOn()
  local C = cvars()
  if not C then return nil end
  local v = C.GetCVar(NamePlateSetting.CVAR)
  if v == nil then return nil end
  return v == "1"
end
NamePlateSetting.isOn = isOn

local function write(value)
  local C = cvars()
  if not C then return end
  if inCombat() then
    pending = value
    return
  end
  pending = nil
  C.SetCVar(NamePlateSetting.CVAR, value)
  wasOn = value == "1"
end

local function warn()
  local W, T = WFJ.OptionsWidgets, WFJ.OptionsText
  if not (W and T) then return end
  print(W.pick(T.get("names.plates.off")))
end

-- The names choice changed, by the welcome window's Confirm or the settings page.
local function onNames(japanese)
  if type(db) ~= "table" then return end
  local on = isOn()
  if on == nil then return end
  if japanese then
    if not on then
      db.namePlatesWas = "0" -- what choosing English names puts back
      write("1")
    end
  elseif db.namePlatesWas ~= nil then
    local was = db.namePlatesWas
    db.namePlatesWas = nil
    write(was)
  end
end

-- The client's setting may have changed under us (its own options page, another addon, a slash command).
local function onChanged()
  local on = isOn()
  if on == nil then return end
  if wasOn and not on and WFJ.State.names and pending == nil then warn() end
  wasOn = on
end

function NamePlateSetting.flush()
  if pending ~= nil and not inCombat() then write(pending) end
end

function NamePlateSetting.start(saved)
  db = saved
  wasOn = isOn()
  if wasOn == nil then return false end -- no such setting on this client: nothing to follow
  if not watcher then
    watcher = CreateFrame("Frame")
    watcher:RegisterEvent("CVAR_UPDATE")
    watcher:SetScript("OnEvent", onChanged)
    WFJ.State.on("names", onNames)
  end
  if WFJ.State.names and not wasOn then warn() end
  return true
end
