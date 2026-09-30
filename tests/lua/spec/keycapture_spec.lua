local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua",
  "UI/Font.lua", "UI/OptionsText.lua", "UI/OptionsWidgets.lua", "UI/KeyCapture.lua" }

describe("UI/KeyCapture: capturing a key on the settings page", function()
  local WFJ, KC, got, refused

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(FILES)
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Settings.load(nil, 1, {})
    KC = WFJ.KeyCapture
    got, refused = {}, {}
  end)

  local function capture(mode)
    return KC.new(CreateFrame("Frame"), { mode = mode, onKey = function(v) got[#got + 1] = v end,
      onRefused = function(why) refused[#refused + 1] = why end })
  end

  it("reveal capture takes a side, a key or a mouse button; ignores the main button; Escape cancels", function()
    local cap = capture("reveal")
    local b = cap.button
    b:click()
    assert.is_true(cap.active)
    assert.are.same({ true }, Stub.keyboardCalls)
    assert.are.equal("キーを押す", b.caption:GetText()) -- one language
    b:keyDown("LALT")
    assert.are.same({ "lalt" }, got)
    assert.is_false(cap.active)
    b:click(); b:keyDown("Q")
    b:click(); b:mouseDown("Button4")
    assert.are.same({ "lalt", "Q", "BUTTON4" }, got)
    b:click()
    b:mouseDown("LeftButton")
    assert.is_true(cap.active)
    b:keyDown("ESCAPE")
    assert.is_false(cap.active)
    assert.are.same({ "lalt", "Q", "BUTTON4" }, got)
    assert.are.same({ true, false, true, false, true, false, true, false }, Stub.keyboardCalls)
    b:click(); b:click() -- a second click cancels too
    assert.is_false(cap.active)
  end)

  it("keeps the template's pressed look (its OnMouseDown) while listening and after", function()
    local pressed = 0
    local template = function() pressed = pressed + 1 end
    local realCreate = _G.CreateFrame
    -- the key-binding button art's own OnMouseDown (UIMenuButtonStretchTemplate)
    _G.CreateFrame = function(kind, name, parent, tmpl)
      local f = realCreate(kind, name, parent, tmpl)
      if tmpl == "UIMenuButtonStretchTemplate" then f:SetScript("OnMouseDown", template) end
      return f
    end
    local cap = capture("reveal")
    _G.CreateFrame = realCreate
    local b = cap.button
    b:click()
    b:mouseDown("Button4")
    assert.are.equal(1, pressed)
    assert.are.same({ "BUTTON4" }, got)
    assert.are.equal(template, b:GetScript("OnMouseDown"))
    assert.is_nil(b:GetScript("OnKeyDown"))
  end)

  it("refuses to start in combat", function()
    local cap = capture("reveal")
    Stub.combat = true
    cap.button:click()
    assert.is_false(cap.active)
    assert.are.same({}, Stub.keyboardCalls)
    assert.are.same({ "combat" }, refused)
  end)

  it("a key bound to another action names it; our own or an unbound key does not", function()
    Stub.bindings.Q = "ACTIONBUTTON5"
    Stub.bindings.J = "WFJ_TOGGLE"
    assert.are.equal("Action Button 5", KC.conflict("Q", KC.REVEAL))
    assert.is_nil(KC.conflict("J", KC.TOGGLE))
    assert.is_nil(KC.conflict("F9", KC.REVEAL))
    assert.are.equal("Mouse Button 4", KC.keyText("BUTTON4"))
  end)

  it("toggle capture waits for the modified key, builds the chord, and writes the binding set", function()
    local cap = capture("toggle")
    cap.button:click()
    Stub.keys.ctrl = true
    cap.button:keyDown("LCTRL")
    assert.is_true(cap.active)
    cap.button:keyDown("J")
    assert.are.same({ "CTRL-J" }, got)
    assert.is_true(KC.setToggle("CTRL-J"))
    assert.are.same({ { "SetBinding", "CTRL-J", "WFJ_TOGGLE" }, { "SaveBindings", 2 } }, Stub.bindingCalls)
    assert.are.equal("CTRL-J", KC.toggleKey())
    Stub.bindingCalls = {}
    assert.is_true(KC.setToggle("F7")) -- the old key is released first
    assert.are.same({ { "SetBinding", "CTRL-J" }, { "SetBinding", "F7", "WFJ_TOGGLE" }, { "SaveBindings", 2 } },
      Stub.bindingCalls)
    Stub.bindingCalls = {}
    assert.is_true(KC.clearToggle())
    assert.are.same({ { "SetBinding", "F7" }, { "SaveBindings", 2 } }, Stub.bindingCalls)
    assert.is_nil(KC.toggleKey())
    assert.is_false(KC.clearToggle())
    Stub.combat = true
    assert.is_false(KC.setToggle("F8"))
    Stub.combat = false
    -- the client refuses the new key: the old one is put back, nothing saved
    KC.setToggle("F7")
    local realSet = _G.SetBinding
    _G.SetBinding = function(k, action)
      if k == "F9" then return false end
      return realSet(k, action)
    end
    Stub.bindingCalls = {}
    assert.is_false(KC.setToggle("F9"))
    assert.are.equal("F7", KC.toggleKey())
    for _, c in ipairs(Stub.bindingCalls) do assert.are_not.equal("SaveBindings", c[1]) end
    _G.SetBinding = realSet
  end)
end)

describe("KeyCapture.parseChord", function()
  local KC
  setup(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    KC = H.loadChunks(FILES).KeyCapture
  end)

  it("canonicalizes case and the meta order ALT CTRL SHIFT META", function()
    assert.are.equal("CTRL-J", KC.parseChord("ctrl-j"))
    assert.are.equal("ALT-CTRL-SHIFT-META-F5", KC.parseChord("meta-shift-ctrl-alt-f5"))
    assert.are.equal("Q", KC.parseChord("q"))
    assert.are.equal("BUTTON4", KC.parseChord("Button4"))
    assert.are.equal("-", KC.parseChord("-"))
    assert.are.equal("CTRL--", KC.parseChord("ctrl--"))
    for _, ok in ipairs({ "F24", "NUMPAD0", "NUMPADPLUS", "PAGEUP", "SPACE", "BUTTON31", "[", ";", "+" }) do
      assert.are.equal(ok, KC.parseChord(ok:lower()), ok)
    end
    assert.is_truthy(select(2, KC.parseChord("ctrl+j")):find("use - between keys", 1, true))
    assert.are.equal("CTRL is given twice", select(2, KC.parseChord("ctrl-ctrl-j")))
    assert.are.equal("use CTRL, not LCTRL, before a key", select(2, KC.parseChord("lctrl-j")))
  end)

  it("refuses what the page's capture never binds, with a reason", function()
    for _, bad in ipairs({ "", "ctrl-", "ctrl-ctrl-j", "foo-j", "alt", "RSHIFT", "ctrl-lalt", "button1", "BUTTON2",
        "escape", "unknown", "ctrl j", "ABCDEFGHIJKLMNOPQ", "ctrl+j", "foo", "ctrl-foo", "-j", "--", "ctrl--j",
        "lctrl-j", "mousewheelup", "pada", "f0", "f25", "button32", "numpadx" }) do
      local chord, why = KC.parseChord(bad)
      assert.is_nil(chord, bad)
      assert.is_true(type(why) == "string" and #why > 0, bad)
    end
    assert.is_nil(KC.parseChord(nil))
  end)
end)
