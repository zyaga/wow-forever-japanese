-- Core/State.lua: the addon's runtime state and the one channel back to UI (pub/sub). No frame access.
-- Events: "enabled"(bool) · "area"(id, bool) · "modifier"(bool) · "markers"() (each fired only on change);
-- "language"(english), fired when what the screen shows flips between Japanese and English, by the reveal key or by
-- the direction (everything that follows the language listens to this one; "modifier" is the key alone);
-- "readings"(bool), fired by the `readings.enabled` setting's apply (UI/Readings shows / hides its covers);
-- and "revealKey"(key), fired by Modifier.setKey on every apply so UI/RevealBinding re-applies.
-- "lineShown"(surface, recordKey, kind, id), fired by UI/Render's show when the client wrote a line and it now shows in
-- Japanese (UI/VoicePlayer); "voice"(), fired by the voice settings' apply. "words"(), fired by Core/Words when
-- the word list changes (a save, Remove last, Clear all): Core/Study, UI/WordsWindow, UI/StudyWindow and UI/Options
-- follow it. "names"(bool), fired by setNames when names switch between the client's English and their Japanese
-- (the `names.japanese` setting, while the name tables are in memory): quest titles follow it too.
-- "namesSetting"(bool), fired by that setting's apply on every change, also when the tables were let go and names
-- cannot switch until a reload (UI/Options shows its reload line).
local _, WFJ = ...
local State = { enabled = true, modifierHeld = false, areas = {}, direction = "ja", names = false }
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

-- Whether names show in Japanese. → whether it changed
function State.setNames(v)
  v = v and true or false
  if State.names == v then return false end
  State.names = v
  State.fire("names", v)
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

-- Whether the screen shows English now. The direction says which language is first ("ja": Japanese, with English
-- while the reveal key is held; "en": English, with Japanese while it is held).
function State.showsEnglish()
  return (State.direction == "en") ~= State.modifierHeld
end

function State.setModifierHeld(v)
  v = v and true or false
  if State.modifierHeld == v then return false end
  State.modifierHeld = v
  State.fire("modifier", v)
  State.fire("language", State.showsEnglish())
  return true
end

-- "ja" | "en"; anything else is ignored. → whether it changed
function State.setDirection(v)
  if (v ~= "ja" and v ~= "en") or State.direction == v then return false end
  State.direction = v
  State.fire("direction", v)
  State.fire("language", State.showsEnglish())
  return true
end
