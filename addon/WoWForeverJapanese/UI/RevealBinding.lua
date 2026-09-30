-- UI/RevealBinding.lua: takes a `bound` modifier over while the addon is loaded (ADR-018). One hidden owner frame:
-- ClearOverrideBindings(owner), then SetOverrideBinding(owner, true, key, "WFJ_REVEAL") [verified present:
-- RestrictedFrames.lua:24–28]. Override bindings are session-only [likely], so the player's saved binds are never
-- written and disabling the addon gives the key back. Binding calls are restricted in combat [likely]: the change
-- waits for PLAYER_REGEN_ENABLED (Main routes it to flush). While a bound key is held, an OnUpdate watcher re-polls
-- the Modifier until release, so a key-up the client never delivered cannot leave English showing.
-- InCombatLockdown / ClearOverrideBindings / SetOverrideBinding are declared through Compat (surface
-- "revealbinding") and called only once all three resolve to functions (present as globals on both clients
-- [verified: Forever blizzard_restrictedaddonenvironment/restrictedframes.lua:24–28]). If one is missing (moved into a
-- namespace, dropped) nothing is written and the state reads "unavailable": the polled modifier still works. Resolved
-- at call time, like UI/KeyCapture, so a later wrapper on the global is the one called.
local _, WFJ = ...
local RevealBinding = {}
WFJ.RevealBinding = RevealBinding

local Compat = WFJ.Compat
local NAMESPACE = "revealbinding"
RevealBinding.SURFACE = NAMESPACE -- a Compat namespace, not a translated surface
-- key → candidate names, in preference order.
local API = {
  inCombat = { "InCombatLockdown" },
  clearOverrides = { "ClearOverrideBindings" },
  setOverride = { "SetOverrideBinding" },
}
for key, cands in pairs(API) do Compat.declare(NAMESPACE, key, cands) end
RevealBinding.API = API

local function api(key)
  for _, name in ipairs(API[key]) do
    local fn = Compat.resolve(name)
    if type(fn) == "function" then return fn end
  end
  return nil
end

RevealBinding.pending = false
-- "none" (polled modifier) | "applied" | "queued" (waiting for combat to end) | "unavailable" (no binding API)
RevealBinding.state = "none"

local owner
local function frame()
  if not owner then owner = CreateFrame("Frame") end
  return owner
end

-- Applies Modifier.bindingKey() now, or queues it in combat. → true when applied
function RevealBinding.apply()
  local inCombat, clear, set = api("inCombat"), api("clearOverrides"), api("setOverride")
  if not (inCombat and clear and set) then
    RevealBinding.pending = false
    RevealBinding.state = "unavailable"
    return false
  end
  if inCombat() then
    RevealBinding.pending = true
    RevealBinding.state = "queued"
    return false
  end
  local key = WFJ.Modifier.bindingKey()
  local f = frame()
  RevealBinding.pending = false
  clear(f)
  if key then set(f, true, key, "WFJ_REVEAL") end
  RevealBinding.state = key and "applied" or "none"
  return true
end

-- PLAYER_REGEN_ENABLED: applies a change queued in combat. → true when something was applied
function RevealBinding.flush()
  if not RevealBinding.pending then return false end
  return RevealBinding.apply()
end

-- Starts (held) or stops the per-frame re-poll. It stops itself once the Modifier reads not held.
function RevealBinding.watch(held)
  local f = frame()
  if not held then
    f:SetScript("OnUpdate", nil)
    return
  end
  f:SetScript("OnUpdate", function(self)
    WFJ.Modifier.refresh()
    if not WFJ.State.modifierHeld then self:SetScript("OnUpdate", nil) end
  end)
end

WFJ.State.on("revealKey", function() RevealBinding.apply() end)
