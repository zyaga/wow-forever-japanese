-- UI/NamePlateSetting.lua: the client's own nameplate settings, kept in step with the names choice.
-- A name over a creature's head is drawn by the client in the game world, where no addon can write. A unit with a
-- nameplate shows its name there instead, and a nameplate's name is a widget (UI/UnitFrames writes it). So Japanese
-- names over heads need a nameplate on every creature that has a name: the client's settings for enemy units
-- (neutral ones among them), their minions and minor units, friendly NPCs, and the one that shows nameplates out
-- of combat too [verified: forever-ui-1.60.1.71037 blizzard_settingsdefinitions_frame/nameplates.lua:461-520, the
-- settings and their CVars; without the last one the client shows nameplates only in combat, :461 and its tooltip].
-- A player's nameplate is not asked for: a player's name is never changed.
-- When the player chooses Japanese names each setting that is off is turned on and its value before that is kept in
-- the saved settings; choosing English names puts those values back. A value the player sets by hand afterwards is
-- left alone: with Japanese names on and one of the main settings off, one chat line says names over heads are
-- English, when it happens and once at each login.
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
-- Every setting turned on with Japanese names. The first three decide whether a creature has a nameplate at all;
-- the line about names in English is said for those. The other two only widen the enemy setting.
NamePlateSetting.CVARS = { "nameplateShowFriendlyNpcs", "nameplateShowEnemies", "nameplateShowAll",
  "nameplateShowEnemyMinions", "nameplateShowEnemyMinus" }
NamePlateSetting.MAIN = 3
NamePlateSetting.CVAR = NamePlateSetting.CVARS[1]
local API = { inCombat = { "InCombatLockdown" }, cvars = { "C_CVar" } }
for key, cands in pairs(API) do Compat.declare(NAMESPACE, key, cands) end
NamePlateSetting.API = API

local db, watcher
local pending = {} -- cvar → the value a write in combat is waiting to set
local wasOn        -- whether every main setting was on at the last look, so the line is said when one goes off, once

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
local function isOn(cvar)
  local C = cvars()
  if not C then return nil end
  local v = C.GetCVar(cvar or NamePlateSetting.CVAR)
  if v == nil then return nil end
  return v == "1"
end
NamePlateSetting.isOn = isOn

-- → whether every main setting this client has is on, or nil when it has none of them
local function allOn()
  local any, on = false, true
  for i = 1, NamePlateSetting.MAIN do
    local state = isOn(NamePlateSetting.CVARS[i])
    if state ~= nil then
      any = true
      on = on and state
    end
  end
  if not any then return nil end
  return on
end

local function write(cvar, value)
  local C = cvars()
  if not C then return end
  if inCombat() then
    pending[cvar] = value
    return
  end
  pending[cvar] = nil
  C.SetCVar(cvar, value)
end

local function warn()
  local W, T = WFJ.OptionsWidgets, WFJ.OptionsText
  if not (W and T) then return end
  print(W.pick(T.get("names.plates.off")))
end

-- The values kept from before Japanese names turned a setting on, by setting. Saved settings of a version that
-- knew one setting hold its value alone.
local function kept()
  if type(db.namePlatesWas) == "string" then db.namePlatesWas = { [NamePlateSetting.CVAR] = db.namePlatesWas } end
  return db.namePlatesWas
end

-- Turns on every setting that is off and that Japanese names has not turned on before, keeping its value.
-- A setting already asked for is the player's from then on.
local function turnOn()
  local was = kept() or {}
  local asked = type(db.namePlatesAsked) == "table" and db.namePlatesAsked or {}
  for _, cvar in ipairs(NamePlateSetting.CVARS) do
    local on = isOn(cvar)
    if pending[cvar] ~= nil then on = pending[cvar] == "1" end -- a waiting write is what the setting will be
    if on ~= nil and not asked[cvar] then
      asked[cvar] = true
      if not on then
        -- what choosing English names puts back; a value kept from a choice reversed in the same fight stays
        if was[cvar] == nil then was[cvar] = "0" end
        write(cvar, "1")
      end
    end
  end
  db.namePlatesAsked = asked
  db.namePlatesWas = next(was) and was or nil
end

local function putBack()
  local was = kept()
  db.namePlatesWas, db.namePlatesAsked = nil, nil
  for cvar, value in pairs(was or {}) do write(cvar, value) end
end

-- The names choice changed, by the welcome window's Confirm or the settings page.
local function onNames(japanese)
  if type(db) ~= "table" or allOn() == nil then return end
  if japanese then turnOn() else putBack() end
  if next(pending) == nil then wasOn = allOn() end
end

-- The client's setting may have changed under us (its own options page, another addon, a slash command).
local function onChanged()
  local on = allOn()
  if on == nil then return end
  if wasOn and not on and WFJ.State.names and next(pending) == nil then warn() end
  wasOn = on
end

function NamePlateSetting.flush()
  if inCombat() then return end
  for cvar, value in pairs(pending) do write(cvar, value) end
  wasOn = allOn()
end

function NamePlateSetting.start(saved)
  db = saved
  wasOn = allOn()
  if wasOn == nil then return false end -- no such setting on this client: nothing to follow
  if not watcher then
    watcher = CreateFrame("Frame")
    watcher:RegisterEvent("CVAR_UPDATE")
    watcher:SetScript("OnEvent", onChanged)
    WFJ.State.on("names", onNames)
  end
  if WFJ.State.names then
    -- a setting never asked for yet (one this version added, or a first choice a reload cut off) is turned on
    -- here; one with a kept value that is off again was asked for in a fight and the interface reloaded before
    -- it ended, so that write is made here too. Any other setting that is off is the player's, and they are
    -- told what it means.
    local asked = type(db.namePlatesAsked) == "table" and db.namePlatesAsked or nil
    local was = kept()
    if not asked then
      -- settings saved before the list of asked settings existed: Japanese names asked for the first setting
      -- then, so off now is the player's own choice
      db.namePlatesAsked = { [NamePlateSetting.CVAR] = true }
    end
    for cvar in pairs(was or {}) do
      if isOn(cvar) == false then write(cvar, "1") end
    end
    turnOn()
    if next(pending) == nil then
      wasOn = allOn()
      if not wasOn then warn() end
    end
  end
  return true
end
