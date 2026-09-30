local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

describe("UI/RevealBinding: a bound modifier is taken over by an override binding (ADR-018)", function()
  local WFJ, S, RB, fires

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    S, RB = WFJ.Settings, WFJ.RevealBinding
    Stub.bindingCalls = {}
    fires = {}
    WFJ.State.on("modifier", function(v) fires[#fires + 1] = v end)
  end)

  local function calls()
    local out = {}
    for _, c in ipairs(Stub.bindingCalls) do
      out[#out + 1] = c[1] == "SetOverrideBinding" and table.concat({ c[1], tostring(c[3]), c[4], c[5] }, " ") or c[1]
    end
    return out
  end

  it("out of combat a bound key clears then sets the priority override; a polled key only clears", function()
    assert.is_true((S.set("modifier", "q")))
    assert.are.same({ "ClearOverrideBindings", "SetOverrideBinding true Q WFJ_REVEAL" }, calls())
    assert.are.equal(Stub.bindingCalls[1][2], Stub.bindingCalls[2][2]) -- one owner frame
    assert.are.equal("applied", RB.state)
    Stub.bindingCalls = {}
    S.set("modifier", "lalt")
    assert.are.same({ "ClearOverrideBindings" }, calls())
    assert.are.equal("none", RB.state)
  end)

  it("in combat nothing is written until PLAYER_REGEN_ENABLED, then exactly once", function()
    Stub.combat = true
    S.set("modifier", "q")
    assert.are.same({}, calls())
    assert.are.equal("queued", RB.state)
    Stub.combat = false
    Stub.fireAll("PLAYER_REGEN_ENABLED")
    assert.are.same({ "ClearOverrideBindings", "SetOverrideBinding true Q WFJ_REVEAL" }, calls())
    Stub.bindingCalls = {}
    Stub.fireAll("PLAYER_REGEN_ENABLED")
    assert.are.same({}, calls())
  end)

  it("WFJ_RevealKey down / up reveals the live English and restores the Japanese", function()
    S.set("modifier", "q")
    WFJ.Render.init(WFJ.Translator.new({ -- Main's deps, with a one-row fixture instead of the shipped data
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id)
        if kind == "quest.title" and id == 2 then return { ja = "Sharptalonの鉤爪", status = "." } end
        return nil
      end,
      marker = function() return false end,
    }))
    Stub.quest = { id = 2, title = "Sharptalon's Claw", description = "", objectives = "", progress = "",
      completion = "" }
    Stub.showDetail()
    assert.are.equal("Sharptalonの鉤爪", QuestInfoTitleHeader:GetText())
    Stub.pressed.Q = true
    WFJ_RevealKey("down")
    assert.are.equal("Sharptalon's Claw", QuestInfoTitleHeader:GetText())
    Stub.pressed.Q = false
    WFJ_RevealKey("up")
    assert.are.equal("Sharptalonの鉤爪", QuestInfoTitleHeader:GetText())
    assert.are.same({ true, false }, fires)
  end)

  it("the watcher re-polls while held and stops itself when the key reads up", function()
    S.set("modifier", "q")
    Stub.pressed.Q = true
    WFJ_RevealKey("down")
    local owner = Stub.bindingCalls[1][2]
    assert.is_function(owner:GetScript("OnUpdate"))
    owner:GetScript("OnUpdate")(owner) -- still held: keeps watching
    assert.is_function(owner:GetScript("OnUpdate"))
    Stub.pressed.Q = false -- released while the game window had no focus: no "up" edge
    owner:GetScript("OnUpdate")(owner)
    assert.is_nil(owner:GetScript("OnUpdate"))
    assert.is_false(WFJ.State.modifierHeld)
    assert.are.same({ true, false }, fires)
  end)

  it("a down edge from a key the modifier is not (a stray Key Bindings entry) reveals nothing", function()
    S.set("modifier", "q")
    WFJ_RevealKey("down")
    assert.is_false(WFJ.State.modifierHeld)
    assert.are.same({}, fires)
  end)
end)
