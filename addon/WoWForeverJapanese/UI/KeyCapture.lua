-- UI/KeyCapture.lua: capturing a key on the settings page, and the toggle binding the page writes.
-- A capture button: click → it listens for one key (OnKeyDown, EnableKeyboard) or mouse button (OnMouseDown),
-- converts it the client's way (GetConvertedKeyOrButton [verified: BindingUtil.lua:66]; the toggle also
-- CreateKeyChordStringUsingMetaKeyState [verified: BindingUtil.lua:116]) and hands the value to onKey.
--   mode "reveal": one key, no chord; a lone modifier completes as its side (LALT → lalt); Modifier.normalize decides.
--   mode "toggle": modifiers alone wait for the key they modify; the result may be a chord (CTRL-J).
-- One capture listens at a time. Escape, a second click, hiding the page or combat cancel. The two main mouse buttons
-- never bind (the click that starts a capture must not bind itself). Refuses to start in combat.
-- Every client function here is declared through Compat (surface "keycapture") and called only once it
-- resolves to a function; all of them are globals on both clients [verified: Forever blizzard_sharedxml/
-- bindingutil.lua:66, 86, 116; blizzard_settings_shared/blizzard_keybindings.lua:94, 108, 127], but a name the client
-- moved into a namespace or dropped must cost the settings page nothing. A missing name degrades safely: no binding is
-- read as none, no binding is ever written, nothing raises. They are resolved at call time (the declared candidates
-- walked through Compat.resolve, not memoized) so a later hooksecurefunc wrapper on the global is the one called.
local _, WFJ = ...
local KeyCapture = {}
WFJ.KeyCapture = KeyCapture

local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText
local Compat = WFJ.Compat

local NAMESPACE = "keycapture"
KeyCapture.SURFACE = NAMESPACE -- a Compat namespace, not a translated surface
-- key → candidate names, in preference order.
local API = {
  inCombat = { "InCombatLockdown" },
  convert = { "GetConvertedKeyOrButton" },
  isMeta = { "IsMetaKey" },
  chord = { "CreateKeyChordStringUsingMetaKeyState" },
  bindingAction = { "GetBindingAction" },
  bindingText = { "GetBindingText" },
  bindingKey = { "GetBindingKey" },
  setBinding = { "SetBinding" },
  saveBindings = { "SaveBindings" },
  bindingSet = { "GetCurrentBindingSet" },
}
for key, cands in pairs(API) do Compat.declare(NAMESPACE, key, cands) end
KeyCapture.API = API

-- The client function for `key`, or nil when no candidate is a function now.
local function api(key)
  for _, name in ipairs(API[key]) do
    local fn = Compat.resolve(name)
    if type(fn) == "function" then return fn end
  end
  return nil
end

-- Combat as the client reports it; nil when the client cannot say (then nothing binding-related is written).
local function inCombat()
  local fn = api("inCombat")
  if not fn then return nil end
  return fn() and true or false
end

-- The binding writers, all present, or nil: a half-available set never writes.
local function writers()
  local key, set, save, current = api("bindingKey"), api("setBinding"), api("saveBindings"), api("bindingSet")
  if not (key and set and save and current) then return nil end
  return key, set, save, current
end

KeyCapture.TOGGLE = "WFJ_TOGGLE"
KeyCapture.REVEAL = "WFJ_REVEAL"
KeyCapture.active = nil -- the capture currently listening, if any

-- opts = { mode, width, onKey(value), onRefused(reason) }. → capture with :start(), :stop(), :input(raw), .active
function KeyCapture.new(parent, opts)
  local cap = { mode = opts.mode, active = false, opts = opts }
  local en, ja = Text.get("button.capture")
  -- the client's key-binding button art [verified: UIMenuButtonStretchTemplate, Blizzard_SharedXML/
  -- Mainline/SharedUIPanelTemplates.xml:772, KeyBindingFrameBindingButtonTemplate's base, Blizzard_Keybindings.xml:4]
  local b = W.button(parent, en, ja, opts.width or 150, nil, "UIMenuButtonStretchTemplate")
  cap.button = b
  local templateMouseDown = b:GetScript("OnMouseDown") -- the template's pressed look, kept while listening

  local function idle()
    b:setLabel(Text.get(opts.mode == "toggle" and "button.setKey" or "button.capture"))
  end

  -- Key and mouse handlers exist only while listening: a frame with an OnKeyDown script takes keyboard input
  -- (Escape included) whenever it is visible; Blizzard's own listener sets and clears them the same way
  -- [verified: Blizzard_Keybindings.lua:26–40, KeybindListener:SetListening; in game, a standing handler swallowed
  -- Escape].
  local function listen(on)
    b:SetScript("OnKeyDown", on and function(_, key) cap:input(key) end or nil)
    b:SetScript("OnMouseDown", on and function(self, button)
      if type(templateMouseDown) == "function" then templateMouseDown(self, button) end
      cap:input(button)
    end or templateMouseDown)
    b:EnableKeyboard(on)
  end

  function cap.start(self)
    if inCombat() then
      if type(opts.onRefused) == "function" then opts.onRefused("combat") end
      return false
    end
    if KeyCapture.active and KeyCapture.active ~= self then KeyCapture.active:stop() end
    KeyCapture.active = self
    self.active = true
    listen(true)
    b:setLabel(Text.get("button.capturing"))
    return true
  end

  function cap.stop(self)
    if not self.active then return false end
    self.active = false
    if KeyCapture.active == self then KeyCapture.active = nil end
    listen(false)
    idle()
    return true
  end

  function cap.input(self, raw)
    if not self.active then return false end
    if raw == "ESCAPE" then return self:stop() end
    local convert = api("convert")
    if not convert then return false end -- no converted key: nothing is captured (Escape and a click still cancel)
    local key = convert(raw)
    if key == "ESCAPE" then return self:stop() end
    if key == "BUTTON1" or key == "BUTTON2" then return false end
    local value
    if self.mode == "reveal" then
      value = WFJ.Modifier.normalize(key)
    else
      local isMeta, chord = api("isMeta"), api("chord")
      if isMeta and chord and not isMeta(key) then value = chord(key) end
    end
    if value == nil then return false end
    self:stop()
    opts.onKey(value)
    return true
  end

  b:SetScript("OnClick", function() if cap.active then cap:stop() else cap:start() end end)
  b:HookScript("OnHide", function() cap:stop() end)
  idle()
  return cap
end

-- The action a key is bound to in the player's own binding set, as its display name, when it is not `ours`.
-- GetBindingAction without checkOverride reads the saved binding, so a key we took over still names its action
-- [likely: the client only ever passes nil there, Blizzard_Keybindings.lua:127; an in-game check].
function KeyCapture.conflict(key, ours)
  local getAction = api("bindingAction")
  local action = getAction and getAction(key)
  if type(action) ~= "string" or action == "" or action == ours then return nil end
  local getText = api("bindingText")
  return getText and getText(action, "BINDING_NAME_") or action
end

-- The toggle binding's current key (the first of up to two), or nil.
function KeyCapture.toggleKey()
  local getKey = api("bindingKey")
  if not getKey then return nil end
  local key = getKey(KeyCapture.TOGGLE)
  return key
end

-- A key or chord's display name ("CTRL-J", "Mouse Button 4").
function KeyCapture.keyText(key)
  local getText = api("bindingText")
  local text = getText and getText(key)
  return (type(text) == "string" and text ~= "") and text or key
end

-- Typed key text (`/wfj togglekey ctrl-j`) → the chord the page's capture would write, or nil + reason.
-- Meta prefixes in the order CreateKeyChordStringUsingMetaKeyState writes them, ALT CTRL SHIFT META [verified: Forever
-- blizzard_sharedxml/bindingutil.lua:112–135]; the capture never binds a lone meta key or the two main mouse buttons
-- (IsKeyPressIgnoredForBinding, :5–26, 90–92), and Escape cancels it. The key itself must be one the page can capture
-- and the client names (Forever GlobalStrings KEY_*): one printed character, F1–F24, a named key, a NUMPAD key,
-- BUTTON3–31, never the mouse wheel or a gamepad button (the page listens to OnKeyDown / OnMouseDown only). A made-up
-- name is refused here rather than handed to SetBinding. The minus key is "-" alone or after a trailing "-" (ctrl--).
local META_ORDER = { "ALT", "CTRL", "SHIFT", "META" }
local META = { ALT = true, CTRL = true, SHIFT = true, META = true }
local META_SIDES = { LALT = true, RALT = true, LCTRL = true, RCTRL = true, LSHIFT = true, RSHIFT = true,
  LMETA = true, RMETA = true }
local NEVER_BOUND = { BUTTON1 = true, BUTTON2 = true, ESCAPE = true, UNKNOWN = true }
local NAMED = { SPACE = true, TAB = true, ENTER = true, BACKSPACE = true, INSERT = true, DELETE = true, HOME = true,
  END = true, PAGEUP = true, PAGEDOWN = true, UP = true, DOWN = true, LEFT = true, RIGHT = true, NUMLOCK = true,
  SCROLLLOCK = true, PAUSE = true, PRINTSCREEN = true, NUMPADDECIMAL = true, NUMPADDIVIDE = true, NUMPADMINUS = true,
  NUMPADMULTIPLY = true, NUMPADPLUS = true }
local USAGE = "expected a key (f5, ctrl-j, button4, …)"

local function knownKey(key)
  if #key == 1 or NAMED[key] or key:find("^NUMPAD%d$") then return true end
  local f = tonumber(key:match("^F(%d%d?)$"))
  if f then return f >= 1 and f <= 24 end
  local b = tonumber(key:match("^BUTTON(%d%d?)$"))
  return b ~= nil and b >= 3 and b <= 31
end

function KeyCapture.parseChord(text)
  if type(text) ~= "string" or not text:find("^[%w%p]+$") then return nil, USAGE end
  if #text > 1 and text:find("+", 1, true) then return nil, "use - between keys (ctrl-j, not ctrl+j)" end
  local up = text:upper()
  local key, prefix
  if up == "-" then
    key = "-"
  elseif up:sub(-2) == "--" then
    key, prefix = "-", up:sub(1, -3)
  else
    key = up:match("([^-]+)$")
    if key and #key < #up then prefix = up:sub(1, #up - #key - 1) end
  end
  if key == nil then return nil, USAGE end
  local held = {}
  if prefix ~= nil then
    for part in (prefix .. "-"):gmatch("([^-]*)-") do
      if part == "" then return nil, USAGE end
      if META_SIDES[part] then return nil, ("use %s, not %s, before a key"):format(part:sub(2), part) end
      if not META[part] then return nil, ("%s is not ALT, CTRL, SHIFT or META"):format(part) end
      if held[part] then return nil, part .. " is given twice" end
      held[part] = true
    end
  end
  if META[key] or META_SIDES[key] then return nil, "a modifier alone cannot be the key" end
  if NEVER_BOUND[key] then return nil, key .. " cannot be bound" end
  if not knownKey(key) then return nil, key .. " is not a key name the settings page can set" end
  local chord = {}
  for _, m in ipairs(META_ORDER) do if held[m] then chord[#chord + 1] = m end end
  chord[#chord + 1] = key
  return table.concat(chord, "-")
end

-- Combat as the client reports it (true / false), or nil when it cannot say (Slash asks before writing).
KeyCapture.inCombat = inCombat

-- Writes the toggle binding into the player's binding set, replacing its old key(s). Out of combat only. When the
-- client refuses the new key, the old keys are put back and nothing is saved. A client without the binding API (or
-- one that cannot report combat) is never written. → true when written
function KeyCapture.setToggle(key)
  local getKey, set, save, current = writers()
  if not getKey or inCombat() ~= false then return false end
  local old = { getKey(KeyCapture.TOGGLE) }
  for _, k in ipairs(old) do set(k) end
  if not set(key, KeyCapture.TOGGLE) then
    for _, k in ipairs(old) do set(k, KeyCapture.TOGGLE) end
    return false
  end
  save(current())
  return true
end

function KeyCapture.clearToggle()
  local getKey, set, save, current = writers()
  if not getKey or inCombat() ~= false then return false end
  local keys = { getKey(KeyCapture.TOGGLE) }
  if #keys == 0 then return false end
  for _, old in ipairs(keys) do set(old) end
  save(current())
  return true
end
