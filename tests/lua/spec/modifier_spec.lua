local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local CORE = { "Core/Const.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua" }

describe("Modifier: polled truth, event as invalidation", function()
  local WFJ, fires
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(CORE)
    WFJ.Settings.load(nil, 1, {})
    fires = 0
    WFJ.State.on("modifier", function() fires = fires + 1 end)
  end)

  it("isDown follows the configured key only", function()
    assert.are.equal("alt", WFJ.Modifier.key())
    assert.is_false(WFJ.Modifier.isDown())
    Stub.keys.alt = true
    assert.is_true(WFJ.Modifier.isDown())
    Stub.keys.alt = false; Stub.keys.ctrl = true
    assert.is_false(WFJ.Modifier.isDown())
    WFJ.Settings.set("modifier", "ctrl")
    assert.is_true(WFJ.Modifier.isDown())
    Stub.keys.ctrl = false; Stub.keys.shift = true
    WFJ.Settings.set("modifier", "shift")
    assert.is_true(WFJ.Modifier.isDown())
  end)

  it("refresh fires the modifier event once per change and never when unchanged", function()
    assert.is_false(WFJ.Modifier.refresh())
    assert.are.equal(0, fires)
    Stub.keys.alt = true
    assert.is_true(WFJ.Modifier.refresh())
    assert.is_false(WFJ.Modifier.refresh())
    assert.are.equal(1, fires)
    assert.is_true(WFJ.State.modifierHeld)
    Stub.keys.alt = false
    assert.is_true(WFJ.Modifier.refresh())
    assert.are.equal(2, fires)
    assert.is_false(WFJ.State.modifierHeld)
  end)

  it("changing the key while the old one is held drops to not-held and fires once", function()
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.is_true(WFJ.State.modifierHeld)
    fires = 0
    WFJ.Settings.set("modifier", "ctrl")
    assert.is_false(WFJ.State.modifierHeld)
    assert.are.equal(1, fires)
  end)

  it("ignores an unknown key name", function()
    WFJ.Modifier.setKey("meta")
    assert.are.equal("alt", WFJ.Modifier.key())
  end)
end)

describe("Modifier grammar and held state for side / bound keys", function()
  local WFJ, M, fires
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(CORE)
    WFJ.Settings.load(nil, 1, {})
    M = WFJ.Modifier
    fires = {}
    WFJ.State.on("modifier", function(v) fires[#fires + 1] = v end)
  end)

  it("normalize canonicalizes keys and refuses what can never be the modifier", function()
    local ok = { alt = "alt", ALT = "alt", LAlt = "lalt", LALT = "lalt", rshift = "rshift", q = "Q", f5 = "F5",
      Button4 = "BUTTON4", button5 = "BUTTON5", NUMPAD1 = "NUMPAD1", ["-"] = "-" }
    for input, want in pairs(ok) do assert.are.equal(want, M.normalize(input), input) end
    for _, bad in ipairs({ "BUTTON1", "BUTTON2", "ESCAPE", "UNKNOWN", "META", "CTRL-Q", "", ("X"):rep(17), "q q",
      "MOUSEWHEELUP", "mousewheeldown", "BUTTON6", "PAD1", "PADDUP" }) do
      assert.is_nil(M.normalize(bad), bad)
    end
    assert.is_nil(M.normalize(nil))
    assert.is_nil(M.normalize(4))
    assert.are.equal("either", M.class("shift"))
    assert.are.equal("side", M.class("lctrl"))
    assert.are.equal("bound", M.class("Q"))
  end)

  it("a side value follows only its own side's poll", function()
    for _, side in ipairs({ "lalt", "ralt", "lctrl", "rctrl", "lshift", "rshift" }) do
      WFJ.Settings.set("modifier", side)
      local other = side:sub(1, 1) == "l" and ("r" .. side:sub(2)) or ("l" .. side:sub(2))
      Stub.keys[other] = true
      Stub.keys[side:sub(2)] = true -- the either poll is irrelevant to a side value
      assert.is_false(M.isDown(), side .. " with only " .. other)
      Stub.keys[side] = true
      assert.is_true(M.isDown(), side)
      Stub.keys[side], Stub.keys[other], Stub.keys[side:sub(2)] = false, false, false
    end
    assert.is_nil(M.bindingKey())
  end)

  it("a bound key is held only after the binding's down edge while the key polls down", function()
    WFJ.Settings.set("modifier", "q")
    assert.are.equal("Q", M.bindingKey())
    Stub.pressed.Q = true
    assert.is_false(M.isDown()) -- typing q in chat: IsKeyDown true, no binding edge
    assert.is_true(M.bindingEdge(true))
    assert.is_true(M.isDown())
    assert.are.same({ true }, fires)
    Stub.pressed.Q = false -- the key-up never reached the binding
    assert.is_false(M.isDown())
    assert.is_true(M.refresh())
    assert.is_false(M.refresh())
    assert.are.same({ true, false }, fires)
  end)

  it("a mouse button polls IsMouseButtonDown, not IsKeyDown", function()
    WFJ.Settings.set("modifier", "button4")
    Stub.pressed.BUTTON4 = true
    M.bindingEdge(true)
    assert.is_false(M.isDown())
    Stub.mouse.Button4 = true
    M.bindingEdge(true)
    assert.is_true(M.isDown())
    WFJ.Settings.set("modifier", "BUTTON3")
    Stub.mouse.MiddleButton = true
    M.bindingEdge(true)
    assert.is_true(M.isDown())
  end)

  it("setKey fires revealKey with the canonical key on every apply", function()
    local keys = {}
    WFJ.State.on("revealKey", function(k) keys[#keys + 1] = k end)
    WFJ.Settings.set("modifier", "f5")
    WFJ.Settings.set("modifier", "alt")
    assert.are.same({ "F5", "alt" }, keys)
  end)
end)
