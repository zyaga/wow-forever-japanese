-- UI/BuffIdentity.lua: which buff a buff-bar tooltip shows when the client hides it. In combat the player's buff
-- tooltip arrives with a secret aura instance id and secret lines, and the aura's spell id, icon and slots are secret
-- too; what stays readable is the hovered buff-bar button's position (buttonInfo.index, Blizzard's own counter
-- [verified: blizzard_buffframe/buffframe.lua:729–760]), how many buff buttons are shown, and the spell the player
-- just cast (UNIT_SPELLCAST_SUCCEEDED is secret only for units other than the player and their pet [verified:
-- blizzard_apidocumentationgenerated/secretpredicatesdocumentation.lua:110–113]) [verified in game: /wfj debug buffs].
-- So the buff bar is followed as a model: its exact list whenever it is readable, then in combat a button added right
-- after the player cast a spell known to buff the player is that spell (known from a cast whose buff was seen while
-- readable, out of combat or still on the bar when a fight ends), and a button removed is the one whose known end
-- time came. Anything else (a buff from someone else, a proc, two changes at once) loses track until it is readable
-- again. The same model runs while the bar is readable and is compared with the truth after every change: it is used
-- in combat only after it has been right MIN_CONFIRMED times in a row; one wrong prediction sets the count back to 0.
-- What was learnt is kept in WFJ_DB.buffIdentity and starts over when the client build changes.
local _, WFJ = ...
local BuffIdentity = {}
WFJ.BuffIdentity = BuffIdentity
local Compat = WFJ.Compat

BuffIdentity.MIN_CONFIRMED = 3
local CAST_WINDOW = 1.5 -- seconds between a cast and the button it adds
local EXPIRY_SLACK = 1.0 -- seconds around a known end time

local db -- { build, selfSpells = { [spell id] = duration }, confirmed = n, misses = n, lastMiss = reason | nil }
local model = { list = {}, valid = false } -- { spell, instance, expires } per buff button, in its order
local recentCast -- { spell, at }
local hiddenCasts = {} -- spells cast while the bar was hidden: learnt as self buffs once it is readable again

local function isSecret(...)
  local f = Compat.resolve("issecretvalue")
  if type(f) ~= "function" then return false end
  for i = 1, select("#", ...) do
    if f((select(i, ...))) then return true end
  end
  return false
end

local function now()
  local f = Compat.resolve("GetTime")
  return type(f) == "function" and f() or 0
end

-- Takes the loaded WFJ_DB table. → the learnt state
function BuffIdentity.load(saved)
  local info = Compat.resolve("GetBuildInfo")
  local build = type(info) == "function" and (tostring((info())) .. "." .. tostring((select(2, info())))) or nil
  if type(saved) ~= "table" then db = { selfSpells = {}, confirmed = 0 }; return db end
  if type(saved.buffIdentity) ~= "table" or saved.buffIdentity.build ~= build then
    saved.buffIdentity = { build = build, selfSpells = {}, confirmed = 0 }
  end
  db = saved.buffIdentity
  db.selfSpells = db.selfSpells or {}
  db.confirmed = db.confirmed or 0
  return db
end

local function state()
  if not db then db = { selfSpells = {}, confirmed = 0 } end
  return db
end

-- The buff-bar buttons that show a buff, keyed by their position. → { [index] = button }, highest index, why none
local function buttons()
  local frame = Compat.resolve("BuffFrame")
  local out, top = {}, 0
  local list = type(frame) == "table" and frame.auraFrames or nil
  if type(list) ~= "table" then return out, 0, "no BuffFrame.auraFrames" end
  local seen = {}
  for _, b in ipairs(list) do
    local info = type(b) == "table" and b.buttonInfo or nil
    if type(info) == "table" and b.IsShown and b:IsShown() then seen[#seen + 1] = tostring(info.auraType) end
    if type(info) == "table" and b.IsShown and b:IsShown() and info.auraType == "Buff"
      and type(info.index) == "number" and not isSecret(info.index) then
      out[info.index] = b
      if info.index > top then top = info.index end
    end
  end
  return out, top, ("%d shown buttons, types %s"):format(#seen, table.concat(seen, ","))
end

-- The buff bar as it really is, while it is readable. → { { spell, instance, expires } ... } | nil, why not
function BuffIdentity.truth()
  local byId = Compat.resolve("C_UnitAuras.GetAuraDataByAuraInstanceID")
  if type(byId) ~= "function" then return nil, "no GetAuraDataByAuraInstanceID" end
  local list, top, buttonsWhy = buttons()
  local out = {}
  for i = 1, top do
    local b = list[i]
    if not b then return nil, "no button at position " .. i .. " (" .. buttonsWhy .. ")" end
    local instance = b.buttonInfo.auraInstanceID
    if isSecret(instance) then return nil, "aura id hidden at position " .. i end
    if type(instance) ~= "number" then return nil, "no aura id at position " .. i end
    local ok, aura = pcall(byId, "player", instance)
    if not ok or type(aura) ~= "table" then return nil, "no aura data at position " .. i .. ": " .. tostring(aura) end
    if isSecret(aura.spellId, aura.expirationTime, aura.duration) then return nil, "aura data hidden at " .. i end
    out[i] = { spell = aura.spellId, instance = instance, expires = aura.expirationTime or 0,
      duration = aura.duration or 0 }
  end
  return out
end

-- The model's next list for `count` buff buttons at time `at`, or nil when the change cannot be told apart. Pure:
-- takes the learnt self-buff spells and the last cast.
function BuffIdentity.step(list, count, at, selfSpells, cast)
  local n = #list
  local out = {}
  for i, e in ipairs(list) do out[i] = { spell = e.spell, instance = e.instance, expires = e.expires } end
  local fresh = cast and at - cast.at <= CAST_WINDOW and selfSpells[cast.spell] and cast or nil
  if count == n then
    if fresh then -- a recast refreshes its own buff
      for _, e in ipairs(out) do
        if e.spell == fresh.spell then e.expires = fresh.at + selfSpells[fresh.spell] end
      end
    end
    return out
  end
  if count == n + 1 and fresh then
    for _, e in ipairs(out) do
      if e.spell == fresh.spell then return nil end
    end
    out[#out + 1] = { spell = fresh.spell, expires = fresh.at + selfSpells[fresh.spell] }
    return out
  end
  if count < n then
    local due = {}
    for i, e in ipairs(out) do
      if e.expires and e.expires > 0 and e.expires <= at + EXPIRY_SLACK then due[#due + 1] = i end
    end
    if #due ~= n - count then return nil end
    for k = #due, 1, -1 do table.remove(out, due[k]) end
    return out
  end
  return nil
end

local function sameSpells(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i].spell ~= b[i].spell then return false end
  end
  return true
end

-- After the buff bar changed (deferred a frame, so Blizzard's own update has run).
function BuffIdentity.onAurasChanged()
  local s, at = state(), now()
  local _, count = buttons()
  local predicted = model.valid and BuffIdentity.step(model.list, count, at, s.selfSpells, recentCast) or nil
  local truth, why = BuffIdentity.truth()
  BuffIdentity.lastRead = truth and ("read " .. #truth .. " buffs") or why
  if truth then
    -- learn: a spell just cast whose buff is now on the bar buffs the player; so does one cast in a fight whose buff
    -- is still on the bar when the bar is readable again
    local cast = {}
    if recentCast and at - recentCast.at <= CAST_WINDOW then cast[recentCast.spell] = true end
    for spell in pairs(hiddenCasts) do cast[spell] = true end
    for _, e in ipairs(truth) do
      if cast[e.spell] and e.duration and e.duration > 0 then s.selfSpells[e.spell] = e.duration end
    end
    hiddenCasts = {}
    if predicted and #model.list ~= #truth then -- a change the model claimed to follow
      if sameSpells(predicted, truth) then
        s.confirmed = s.confirmed + 1
      else
        local want, got = {}, {}
        for i, e in ipairs(truth) do want[i] = tostring(e.spell) end
        for i, e in ipairs(predicted) do got[i] = tostring(e.spell) end
        s.confirmed = 0
        s.misses = (s.misses or 0) + 1
        s.lastMiss = ("model %s, bar %s"):format(table.concat(got, ","), table.concat(want, ","))
      end
    end
    model.list, model.valid = truth, true
  elseif predicted then
    model.list = predicted
  else
    model.valid = false
  end
end

-- UNIT_SPELLCAST_SUCCEEDED for the player.
function BuffIdentity.onCast(spell)
  if isSecret(spell) or type(spell) ~= "number" then return end
  recentCast = { spell = spell, at = now() }
  local inCombat = Compat.resolve("InCombatLockdown")
  if type(inCombat) == "function" and inCombat() then hiddenCasts[spell] = true end
end

-- The buff a buff-bar tooltip shows. → spell id, its instance id (nil for a buff gained hidden), its end time
-- | nil, why
function BuffIdentity.forTooltip(tooltip)
  local s = state()
  if s.confirmed < BuffIdentity.MIN_CONFIRMED then
    return nil, ("buff model not confirmed yet (%d of %d)"):format(s.confirmed, BuffIdentity.MIN_CONFIRMED)
  end
  if not model.valid then return nil, "buff model lost track" end
  local list, count = buttons()
  if count ~= #model.list then return nil, "buff bar count differs from the model" end
  for i, b in pairs(list) do
    if type(tooltip) == "table" and tooltip.IsOwned and tooltip:IsOwned(b) then
      local e = model.list[i]
      if not e then return nil, "no model entry" end
      return e.spell, e.instance, e.expires
    end
  end
  return nil, "no buff-bar button owns the tooltip"
end

-- One line for /wfj debug.
function BuffIdentity.status()
  local s = state()
  return ("buff model: %s, %d of %d confirmations, %d self buffs known, %s"):format(
    s.lastMiss and (("%d wrong, last: %s"):format(s.misses or 0, s.lastMiss)) or "never wrong", s.confirmed,
    BuffIdentity.MIN_CONFIRMED,
    (function() local n = 0; for _ in pairs(s.selfSpells) do n = n + 1 end; return n end)(),
    model.valid and ("tracking " .. #model.list .. " buffs") or "not tracking") .. "; last read: "
    .. tostring(BuffIdentity.lastRead or "never")
end

local installed = false
-- Called by UI/Tooltip.init. → true when the events are registered
function BuffIdentity.init()
  if installed then return true end
  local create, after = Compat.resolve("CreateFrame"), Compat.resolve("C_Timer.After")
  if type(create) ~= "function" then return false end
  local f = create("Frame")
  f:RegisterUnitEvent("UNIT_AURA", "player")
  f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("PLAYER_REGEN_ENABLED") -- readable again: resync
  f:SetScript("OnEvent", function(_, event, _, _, spell)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then return BuffIdentity.onCast(spell) end
    if type(after) == "function" then after(0, function() pcall(BuffIdentity.onAurasChanged) end)
    else pcall(BuffIdentity.onAurasChanged) end
  end)
  installed = true
  return true
end
