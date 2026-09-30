-- Core/Modifier.lua: the modifier, the key held to show the live English (docs/systems/settings.md, ADR-018).
-- Three classes:
--   either  alt · ctrl · shift                             polled IsAltKeyDown() …       signal MODIFIER_STATE_CHANGED
--   side    lalt · ralt · lctrl · rctrl · lshift · rshift  polled IsLeftAltKeyDown() …   signal MODIFIER_STATE_CHANGED
--   bound   any other single client key name (Q, F5, BUTTON4). UI/RevealBinding takes it over with the WFJ_REVEAL
--           override binding; held = the binding saw "down" AND the key still polls down. A binding does not fire
--           while an EditBox has focus, so typing the key reveals nothing; a lost key-up is cleared by the next poll.
-- Events and the binding's keystate are only invalidation signals routed to refresh(); the truth is the poll, read at
-- every Translator.resolve. (MODIFIER_STATE_CHANGED does not fire while an EditBox has focus.)
local _, WFJ = ...
local Modifier = {}
WFJ.Modifier = Modifier

local POLL = {
  alt = function() return IsAltKeyDown() end,
  ctrl = function() return IsControlKeyDown() end,
  shift = function() return IsShiftKeyDown() end,
  lalt = function() return IsLeftAltKeyDown() end,
  ralt = function() return IsRightAltKeyDown() end,
  lctrl = function() return IsLeftControlKeyDown() end,
  rctrl = function() return IsRightControlKeyDown() end,
  lshift = function() return IsLeftShiftKeyDown() end,
  rshift = function() return IsRightShiftKeyDown() end,
}
local EITHER = { alt = true, ctrl = true, shift = true }

-- Presets in the order the settings page lists them, with their English key names (key names stay English).
Modifier.PRESETS = { "alt", "ctrl", "shift", "lalt", "ralt", "lctrl", "rctrl", "lshift", "rshift" }
local DISPLAY = {
  alt = "Alt", ctrl = "Ctrl", shift = "Shift", lalt = "Left Alt", ralt = "Right Alt",
  lctrl = "Left Ctrl", rctrl = "Right Ctrl", lshift = "Left Shift", rshift = "Right Shift",
}

-- Client key names that can never be the modifier: the two main mouse buttons (the click that starts a capture must
-- not bind itself), Escape, the client's "no key", and meta keys that are not a side (a bare META has no poll).
local REFUSED = {
  BUTTON1 = true, BUTTON2 = true, ESCAPE = true, UNKNOWN = true,
  ALT = true, CTRL = true, SHIFT = true, META = true, LMETA = true, RMETA = true,
}

local key = "alt"
local edgeDown = false -- a `bound` key: the WFJ_REVEAL binding's last keystate was "down"

-- → canonical value | nil. Lower-case matches the polled classes (LAlt, LALT → lalt); anything else is an
-- upper-case client key name of 1–16 printable bytes that is not a chord ("CTRL-Q"; the minus key is "-"), and not the
-- mouse wheel, a gamepad button or a mouse button past 5.
function Modifier.normalize(v)
  if type(v) ~= "string" then return nil end
  local lower = v:lower()
  if POLL[lower] then return lower end
  local up = v:upper()
  if #up < 1 or #up > 16 or not up:find("^[%w%p]+$") then return nil end
  if #up > 1 and up:find("-", 1, true) then return nil end
  if REFUSED[up] then return nil end
  -- keys with no held state to poll: the wheel, gamepad buttons, mouse buttons past 5
  if up:find("^MOUSEWHEEL") or up:find("^PAD") then return nil end
  local button = tonumber(up:match("^BUTTON(%d+)$"))
  if button and button > 5 then return nil end
  return up
end

-- → "either" | "side" | "bound" (for a canonical value)
function Modifier.class(k)
  if EITHER[k] then return "either" end
  if POLL[k] then return "side" end
  return "bound"
end

-- English name of a preset; a bound key is returned as-is (the UI passes it through GetBindingText).
function Modifier.display(k)
  return DISPLAY[k] or k
end

function Modifier.key() return key end

-- The key UI/RevealBinding must take over, or nil when the modifier is polled.
function Modifier.bindingKey()
  if POLL[key] then return nil end
  return key
end

local function boundPoll(k)
  local n = k:match("^BUTTON(%d+)$")
  if n then
    -- "MiddleButton" / "Button4" / "Button5" [likely: the client's mouse-button names, BindingUtil.lua:28–39;
    -- FrameXML only calls IsMouseButtonDown("LeftButton"), so the others are unconfirmed in game]
    return IsMouseButtonDown(n == "3" and "MiddleButton" or ("Button" .. n)) and true or false
  end
  return IsKeyDown(k) and true or false
end

function Modifier.isDown()
  local f = POLL[key]
  if f then return f() and true or false end
  if not edgeDown then return false end
  if boundPoll(key) then return true end
  edgeDown = false -- the key-up never arrived (focus left mid-hold): the poll wins
  return false
end

-- Re-poll and mirror into State; fires "modifier" only on change. Returns whether it changed.
function Modifier.refresh()
  return WFJ.State.setModifierHeld(Modifier.isDown())
end

-- The WFJ_REVEAL binding's keystate (Main.lua's WFJ_RevealKey). → whether the held state changed.
function Modifier.bindingEdge(down)
  edgeDown = down and true or false
  return Modifier.refresh()
end

-- `apply` of the `modifier` setting. Changing the key while the old one is held drops to not-held (doc edge case).
-- Fires State "revealKey" so UI/RevealBinding re-applies (Core never calls binding APIs).
function Modifier.setKey(k)
  local n = Modifier.normalize(k)
  if n then
    key = n
    edgeDown = false
    WFJ.State.fire("revealKey", n)
  end
  return Modifier.refresh()
end
