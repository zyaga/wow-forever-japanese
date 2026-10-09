-- Core/State.lua: the addon's runtime state and the one channel back to UI (pub/sub). No frame access.
-- Events: "enabled"(bool) · "area"(id, bool) · "modifier"(bool) · "markers"() (each fired only on change);
-- "readings"(bool), fired by the `readings.enabled` setting's apply (UI/Readings shows / hides its covers);
-- and "revealKey"(key), fired by Modifier.setKey on every apply so UI/RevealBinding re-applies.
-- "lineShown"(surface, recordKey, kind, id), fired by UI/Render's show when the client wrote a line and it now shows in
-- Japanese (UI/VoicePlayer); "voice"(), fired by the voice settings' apply.
local _, WFJ = ...
local State = { enabled = true, modifierHeld = false, areas = {} }
WFJ.State = State

local handlers = {}

function State.on(event, fn)
  local list = handlers[event]
  if not list then list = {}; handlers[event] = list end
  list[#list + 1] = fn
end

function State.fire(event, ...)
  local list = handlers[event]
  if not list then return 0 end
  for i = 1, #list do list[i](...) end
  return #list
end

function State.setEnabled(v)
  v = v and true or false
  if State.enabled == v then return false end
  State.enabled = v
  State.fire("enabled", v)
  return true
end

function State.setArea(id, v)
  v = v and true or false
  if State.areas[id] == v then return false end
  State.areas[id] = v
  State.fire("area", id, v)
  return true
end

function State.areaEnabled(id)
  return State.areas[id] == true
end

function State.setModifierHeld(v)
  v = v and true or false
  if State.modifierHeld == v then return false end
  State.modifierHeld = v
  State.fire("modifier", v)
  return true
end
