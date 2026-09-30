-- UI/KeyCapture and UI/RevealBinding reach every client function through Compat and call it only once it
-- is a function. Each routed name bound to a table (the moved-into-a-namespace case) or removed: no error, no binding
-- read as one, and no binding written.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

local KC_FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua",
  "UI/Font.lua", "UI/OptionsText.lua", "UI/OptionsWidgets.lua", "UI/KeyCapture.lua" }

-- Every candidate name a module declares (its API table: key → { names }).
local function names(api)
  local out = {}
  for _, cands in pairs(api) do
    for _, name in ipairs(cands) do out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

local function writes()
  local out = {}
  for _, c in ipairs(Stub.bindingCalls) do
    if c[1] == "SetBinding" or c[1] == "SaveBindings" or c[1] == "SetOverrideBinding"
        or c[1] == "ClearOverrideBindings" then out[#out + 1] = c[1] end
  end
  return out
end

describe("UI/KeyCapture: client names through Compat", function()
  local WFJ, KC, got

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(KC_FILES)
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Settings.load(nil, 1, {})
    KC = WFJ.KeyCapture
    got = {}
    Stub.bindings.J = "WFJ_TOGGLE"
    Stub.bindings.Q = "ACTIONBUTTON5"
  end)

  local function capture(mode)
    return KC.new(CreateFrame("Frame"), { mode = mode, onKey = function(v) got[#got + 1] = v end })
  end

  it("declares every client function it calls, and each resolves on this client", function()
    assert.are.same({ "CreateKeyChordStringUsingMetaKeyState", "GetBindingAction", "GetBindingKey", "GetBindingText",
      "GetConvertedKeyOrButton", "GetCurrentBindingSet", "InCombatLockdown", "IsMetaKey", "SaveBindings",
      "SetBinding" }, names(KC.API))
    for key in pairs(KC.API) do assert.is_function(WFJ.Compat.get(KC.SURFACE, key), key) end
  end)

  for _, shape in ipairs({ "a table", "absent" }) do
    it("every routed name " .. shape .. ": no error, nothing read as a binding, nothing written", function()
      for _, name in ipairs(names(KC.API)) do _G[name] = shape == "a table" and {} or nil end
      WFJ.Compat.init(function(name) return _G[name] end)
      Stub.bindingCalls = {}
      assert.has_no.errors(function()
        local toggle = capture("toggle")
        assert.is_true(toggle:start()) -- combat unknown: a capture only listens, it writes nothing
        toggle.button:keyDown("LCTRL")
        toggle.button:keyDown("J")
        assert.is_true(toggle.active) -- no converter: no key is taken
        toggle.button:keyDown("ESCAPE")
        assert.is_false(toggle.active) -- Escape still cancels
        local reveal = capture("reveal")
        reveal.button:click()
        reveal.button:mouseDown("Button4")
        reveal.button:click()
        assert.is_false(reveal.active)
        assert.is_nil(KC.conflict("Q", KC.REVEAL))
        assert.is_nil(KC.toggleKey())
        assert.are.equal("BUTTON4", KC.keyText("BUTTON4"))
        assert.is_false(KC.setToggle("F7"))
        assert.is_false(KC.clearToggle())
      end)
      assert.are.same({}, got)
      assert.are.same({}, writes())
      assert.are.equal("WFJ_TOGGLE", Stub.bindings.J) -- the player's binding set is untouched
    end)
  end

  it("a half-available binding API never writes (the setter present, the saver missing)", function()
    _G.SaveBindings = nil
    WFJ.Compat.init(function(name) return _G[name] end)
    Stub.bindingCalls = {}
    assert.is_false(KC.setToggle("F7"))
    assert.is_false(KC.clearToggle())
    assert.are.same({}, writes())
    assert.are.equal("J", KC.toggleKey())
  end)

  it("combat unknown (InCombatLockdown missing): capture works, the binding is never written", function()
    _G.InCombatLockdown = nil
    WFJ.Compat.init(function(name) return _G[name] end)
    local cap = capture("reveal")
    cap.button:click()
    cap.button:keyDown("LALT")
    assert.are.same({ "lalt" }, got)
    Stub.bindingCalls = {}
    assert.is_false(KC.setToggle("F7"))
    assert.are.same({}, writes())
  end)
end)

describe("UI/RevealBinding: client names through Compat", function()
  local WFJ, S, RB

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    S, RB = WFJ.Settings, WFJ.RevealBinding
    Stub.bindingCalls = {}
  end)

  it("declares every client function it calls, and each resolves on this client", function()
    assert.are.same({ "ClearOverrideBindings", "InCombatLockdown", "SetOverrideBinding" }, names(RB.API))
    for key in pairs(RB.API) do assert.is_function(WFJ.Compat.get(RB.SURFACE, key), key) end
  end)

  for _, shape in ipairs({ "a table", "absent" }) do
    for _, missing in ipairs({ "InCombatLockdown", "ClearOverrideBindings", "SetOverrideBinding" }) do
      it(missing .. " " .. shape .. ": no error, no override written, state unavailable", function()
        _G[missing] = shape == "a table" and {} or nil
        assert.has_no.errors(function()
          S.set("modifier", "q")
          Stub.fireAll("PLAYER_REGEN_ENABLED")
          Stub.fireAll("PLAYER_ENTERING_WORLD", false, true)
          assert.is_false(RB.apply())
          assert.is_false(RB.flush())
        end)
        assert.are.same({}, writes())
        assert.are.equal("unavailable", RB.state)
        assert.is_false(RB.pending)
      end)
    end
  end

  it("the polled modifier still works when the override cannot be written", function()
    _G.SetOverrideBinding = {}
    S.set("modifier", "lalt")
    Stub.keys.lalt = true
    WFJ.Modifier.refresh()
    assert.is_true(WFJ.State.modifierHeld)
  end)
end)
