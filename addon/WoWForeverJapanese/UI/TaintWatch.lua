-- UI/TaintWatch.lua: finds where this addon's taint reaches the action bars, so a blocked action in combat can be
-- traced to the line that caused it instead of guessed at (docs/systems/diagnostics.md, ADR-058).
-- A bar layout in combat is blocked when Blizzard's code reads a value this addon's taint reached earlier, out of
-- combat; the block itself only shows the reader. This module records the writer. Everything here only reads:
--   fields   the Blizzard fields the bar layout reads (FIELDS), checked with issecurevariable every CHECK_EVERY
--            seconds; the first time one reads as tainted by this addon, a "turned" entry with the recent events;
--   writers  a post-hook on the Blizzard function that writes each of those fields: a "write" entry with the call
--            stack when the value comes out tainted (the stack names the path that carried the taint);
--   bars     every CHECK_EVERY * SWEEP_EVERY seconds out of combat, any field on the action bars that newly reads
--            as tainted, for fields not on the list;
--   events   the last RING game events, saved with each entry above and with each block;
--   scan     at the first block of a session, and on /wfj taint: every field under the bar and Edit Mode frames
--            that reads as tainted, and the globals this addon tainted.
-- Its own post-hooks run after the hooked function returns and read only; they were present through the sessions
-- that proved the bars clean.
local _, WFJ = ...
local TaintWatch = {}
WFJ.TaintWatch = TaintWatch

local C = WFJ.Compat

TaintWatch.CHECK_EVERY = 2 -- seconds between field checks
TaintWatch.SWEEP_EVERY = 5 -- field checks between bar sweeps
TaintWatch.RING = 60 -- game events kept
TaintWatch.SCAN_DEPTH = 2

TaintWatch.BARS = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
  "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar", "MultiCastActionBarFrame" }
TaintWatch.SNAPPED = { "MainActionBar", "StanceBar", "PetActionBar", "MainStatusTrackingBarContainer",
  "SecondaryStatusTrackingBarContainer", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft",
  "MultiBarRight", "MultiBar5", "MultiBar6", "MultiBar7", "PossessActionBar" }
-- the frames the block-time scan walks
TaintWatch.SCAN_ROOTS = { "StanceBar", "PetActionBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
  "MultiBarLeft", "MultiBarRight", "MultiBar5", "MultiBar6", "MultiBar7", "EditModeManagerFrame",
  "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "MicroButtonAndBagsBar",
  "ObjectiveTrackerFrame", "GameTooltip", "PlayerSpellsFrame" }
-- events too frequent to say anything about a taint
TaintWatch.NOISY = {}
for _, e in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_HEALTH",
  "UNIT_AURA", "UNIT_COMBAT", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_ABSORB_AMOUNT_CHANGED",
  "UNIT_HEAL_PREDICTION", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_COOLDOWN",
  "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_UPDATE_STATE", "CURSOR_CHANGED", "MODIFIER_STATE_CHANGED",
  "UPDATE_MOUSEOVER_UNIT", "UNIT_SPELLCAST_SENT", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_FLAGS",
  "UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE", "UNIT_TARGETABLE_CHANGED", "UPDATE_UI_WIDGET", "GLOBAL_MOUSE_DOWN",
  "GLOBAL_MOUSE_UP", "UNIT_MAXHEALTH", "UNIT_MAXPOWER", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
  "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED_QUIET", "BAG_UPDATE_COOLDOWN", "UPDATE_SHAPESHIFT_COOLDOWN",
  "UNIT_RANGEDDAMAGE", "UNIT_ATTACK_SPEED", "UNIT_DAMAGE", "UNIT_RESISTANCES", "UNIT_STATS",
  "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_SOFT_FRIEND_CHANGED", "CVAR_UPDATE",
  "WORLD_CURSOR_TOOLTIP_UPDATE", "COMBAT_LOG_MESSAGE", "ACTION_RANGE_CHECK_UPDATE",
  "SPELL_ACTIVATION_OVERLAY_HIDE" }) do
  TaintWatch.NOISY[e] = true
end

-- the fields the bar layout reads: { label, global table name (nil for a global variable), key }
local function fieldList()
  local list = {}
  for _, n in ipairs(TaintWatch.BARS) do list[#list + 1] = { n .. ".showAllButtons", n, "showAllButtons" } end
  for _, n in ipairs(TaintWatch.SNAPPED) do list[#list + 1] = { n .. ".snappedToFrame", n, "snappedToFrame" } end
  list[#list + 1] = { "MultiCastActionBarFrame.inMainActionBarState", "MultiCastActionBarFrame",
    "inMainActionBarState" }
  list[#list + 1] = { "ObjectiveTrackerFrame.topModulePadding", "ObjectiveTrackerFrame", "topModulePadding" }
  list[#list + 1] = { "ON_BAR_HIGHLIGHT_MARKS", nil, "ON_BAR_HIGHLIGHT_MARKS" }
  list[#list + 1] = { "PET_ACTION_HIGHLIGHT_MARKS", nil, "PET_ACTION_HIGHLIGHT_MARKS" }
  return list
end
TaintWatch.fieldList = fieldList

local ring, ringPos = {}, 0

local function clock()
  local d = C.resolve("date")
  return type(d) == "function" and d("%H:%M:%S") or ""
end

function TaintWatch.push(text)
  ringPos = ringPos % TaintWatch.RING + 1
  ring[ringPos] = clock() .. " " .. tostring(text)
end

-- The kept events, oldest first, one per line.
function TaintWatch.events()
  local out = {}
  for i = 1, TaintWatch.RING do
    local e = ring[(ringPos + i - 1) % TaintWatch.RING + 1]
    if e then out[#out + 1] = e end
  end
  return table.concat(out, "\n")
end

local function isSecret(v)
  local f = C.resolve("issecretvalue")
  return type(f) == "function" and f(v) and true or false
end

-- One game event into the ring, with its first argument when that is a number, a boolean or one short token (an
-- addon name, a unit, an id). Chat events, any text with a space and a player's GUID are left out: the log keeps no
-- game text and nothing that names a character.
function TaintWatch.onEvent(event, a1)
  if TaintWatch.NOISY[event] or event:find("^CHAT_MSG_") then return end
  local arg = ""
  local t = type(a1)
  if (t == "number" or t == "boolean") and not isSecret(a1) then
    arg = " " .. tostring(a1)
  elseif t == "string" and not isSecret(a1) and #a1 <= 60 and not a1:find("%s") and not a1:find("^Player%-") then
    arg = " " .. a1
  end
  TaintWatch.push(event .. arg)
end

-- → true and the tainting addon when field `key` of table `t` (a global variable when `t` is nil) reads as tainted
local function check(t, key)
  local isSecure = C.resolve("issecurevariable")
  if type(isSecure) ~= "function" then return false end
  local ok, secure, by
  if t == nil then ok, secure, by = pcall(isSecure, key) else ok, secure, by = pcall(isSecure, t, key) end
  return ok and not secure, by
end
TaintWatch.isTainted = check

local function inCombat()
  local f = C.resolve("InCombatLockdown")
  return type(f) == "function" and f() and true or false
end

local function stack()
  local f = C.resolve("debugstack")
  return type(f) == "function" and (f(3, 25, 25) or "") or ""
end

-- The writer of field `label` (on `t`, or a global when `t` is nil) just ran: logged when the value is tainted.
-- → the entry, or nil
function TaintWatch.wrote(label, t, key)
  local tainted, by = check(t, key)
  if not tainted then return nil end
  local s = stack()
  local site = s:match("[^\n]*[^\n]") or "?"
  return WFJ.Diag.log("write", label .. " <" .. site:gsub("^%s+", "") .. ">", { by = tostring(by), stack = s,
    combat = inCombat(), events = TaintWatch.events() })
end

local was = {}
TaintWatch.was = was

-- One pass over FIELDS: each field that turned tainted since the last pass is logged. → the number that turned
function TaintWatch.checkFields(reason)
  local n = 0
  for _, f in ipairs(fieldList()) do
    local t = f[2] and C.resolve(f[2]) or nil
    if f[2] == nil or type(t) == "table" then
      local tainted, by = check(t, f[3])
      if tainted and not was[f[1]] then
        WFJ.Diag.log("turned", f[1], { by = tostring(by), reason = tostring(reason or "timer"), combat = inCombat(),
          events = TaintWatch.events() })
        n = n + 1
      end
      was[f[1]] = tainted and true or false
    end
  end
  return n
end

local function forbidden(t)
  local ok, yes = pcall(function() return t.IsForbidden and t:IsForbidden() end)
  return ok and yes
end

-- Each field `fn(label, key)` of table `t` that reads as tainted, `depth` levels down. A forbidden frame or a table
-- the client refuses to an addon (its iteration raises) is skipped. → the number of keys checked
local function walk(t, label, depth, seen, fn)
  if type(t) ~= "table" or seen[t] or forbidden(t) then return 0 end
  seen[t] = true
  local n = 0
  local ok = pcall(function()
    for k, v in pairs(t) do
      if type(k) == "string" then
        n = n + 1
        local tainted, by = check(t, k)
        if tainted then fn(label .. "." .. k, by) end
        if depth > 0 and type(v) == "table" and k ~= "parent" then
          n = n + walk(v, label .. "." .. k, depth - 1, seen, fn)
        end
      end
    end
  end)
  if not ok then fn(label, "unreadable") end
  return n
end

local seenBarField = {}

-- Out of combat: any field on the bars that newly reads as tainted. → the number found
function TaintWatch.sweepBars()
  if inCombat() then return 0 end
  local n = 0
  for _, name in ipairs(TaintWatch.BARS) do
    walk(C.resolve(name), name, 0, {}, function(label, by)
      if not seenBarField[label] and by ~= "unreadable" then
        seenBarField[label] = true
        n = n + 1
        WFJ.Diag.log("turned", label, { by = tostring(by), reason = "bar sweep", combat = false,
          events = TaintWatch.events() })
      end
    end)
  end
  return n
end

-- Every tainted field under SCAN_ROOTS and every global this addon tainted, logged as "taint" entries.
-- → fields found, globals found
function TaintWatch.scan(reason)
  local hits, seen, checked = {}, {}, 0
  for _, name in ipairs(TaintWatch.SCAN_ROOTS) do
    checked = checked + walk(C.resolve(name), name, TaintWatch.SCAN_DEPTH, seen, function(label, by)
      hits[#hits + 1] = label .. " (" .. tostring(by) .. ")"
    end)
  end
  local globals = {}
  for name in pairs(_G) do
    if type(name) == "string" then
      local tainted, by = check(nil, name)
      if tainted and by == WFJ.ADDON then globals[#globals + 1] = name end
    end
  end
  table.sort(globals)
  WFJ.Diag.log("taint", "scan " .. clock(), { reason = tostring(reason or "slash"), checked = checked,
    fields = table.concat(hits, " | "), globals = table.concat(globals, " | ") })
  return #hits, #globals
end

local scannedOnBlock = false

-- Main, after Diag logged a block naming this addon: the recent events, and the scan once per session.
function TaintWatch.onBlocked()
  WFJ.Diag.log("context", "events before block " .. clock(), { events = TaintWatch.events() })
  if scannedOnBlock then return false end
  scannedOnBlock = true
  TaintWatch.scan("first block")
  return true
end

local function hook(t, method, fn)
  local h = C.resolve("hooksecurefunc")
  if type(h) ~= "function" then return false end
  if t == nil then
    if type(C.resolve(method)) ~= "function" then return false end
    h(method, fn)
  else
    if type(t) ~= "table" or type(t[method]) ~= "function" then return false end
    h(t, method, fn)
  end
  return true
end

-- The writers of FIELDS. → the number of hooks placed
local function hookWriters()
  local n = 0
  for _, name in ipairs(TaintWatch.BARS) do
    local bar = C.resolve(name)
    if hook(bar, "SetShowGrid", function(self) TaintWatch.wrote(name .. ".showAllButtons", self, "showAllButtons") end)
    then
      n = n + 1
    end
  end
  for _, name in ipairs(TaintWatch.SNAPPED) do
    local f = C.resolve(name)
    for _, m in ipairs({ "SetSnappedToFrame", "ClearFrameSnap" }) do
      if hook(f, m, function(self) TaintWatch.wrote(name .. ".snappedToFrame", self, "snappedToFrame") end) then
        n = n + 1
      end
    end
  end
  if hook(C.resolve("MultiCastActionBarFrame"), "MainActionBarStateOverridden", function(self)
    TaintWatch.wrote("MultiCastActionBarFrame.inMainActionBarState", self, "inMainActionBarState")
  end) then
    n = n + 1
  end
  if hook(C.resolve("ObjectiveTrackerFrame"), "UpdateTopPadding", function(self)
    TaintWatch.wrote("ObjectiveTrackerFrame.topModulePadding", self, "topModulePadding")
  end) then
    n = n + 1
  end
  for _, fn in ipairs({ "ClearOnBarHighlightMarks", "UpdateOnBarHighlightMarksBySpell",
    "UpdateOnBarHighlightMarksByFlyout", "UpdateOnBarHighlightMarksByPetAction" }) do
    if hook(nil, fn, function() TaintWatch.wrote("ON_BAR_HIGHLIGHT_MARKS", nil, "ON_BAR_HIGHLIGHT_MARKS") end) then
      n = n + 1
    end
  end
  local pet = C.resolve("PetActionBar")
  for _, m in ipairs({ "UpdatePetActionHighlightMarks", "ClearPetActionHighlightMarks" }) do
    if hook(pet, m, function() TaintWatch.wrote("PET_ACTION_HIGHLIGHT_MARKS", nil, "PET_ACTION_HIGHLIGHT_MARKS") end)
    then
      n = n + 1
    end
  end
  return n
end

local started = false

-- Called by Main after Diag. → the number of writer hooks placed, or false on a client without issecurevariable
function TaintWatch.init()
  if started then return false end
  if type(C.resolve("issecurevariable")) ~= "function" then return false end
  started = true
  local create = C.resolve("CreateFrame")
  if type(create) == "function" then
    local f = create("Frame")
    if type(f.RegisterAllEvents) == "function" then
      f:RegisterAllEvents()
      f:SetScript("OnEvent", function(_, event, a1) TaintWatch.onEvent(event, a1) end)
    end
  end
  for _, fn in ipairs({ "ShowUIPanel", "HideUIPanel" }) do
    hook(nil, fn, function(frame)
      local name = type(frame) == "table" and type(frame.GetName) == "function" and frame:GetName() or frame
      TaintWatch.push(fn .. " " .. tostring(name))
    end)
  end
  local n = hookWriters()
  TaintWatch.checkFields("load")
  local timer = C.resolve("C_Timer")
  if type(timer) == "table" and type(timer.NewTicker) == "function" then
    local ticks = 0
    timer.NewTicker(TaintWatch.CHECK_EVERY, function()
      ticks = ticks + 1
      TaintWatch.checkFields("timer")
      if ticks % TaintWatch.SWEEP_EVERY == 0 then TaintWatch.sweepBars() end
    end)
  end
  return n
end
