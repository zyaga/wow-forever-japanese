-- UI/NamePlateSetting: the client's friendly NPC nameplates follow the names choice, and a chat line says when
-- Japanese names are on with those nameplates off.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

describe("UI/NamePlateSetting", function()
  local WFJ, S, cvar, writes, said, realPrint
  local CVAR = "nameplateShowFriendlyNpcs"

  local function boot(value, saved)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    cvar, writes, said = { [CVAR] = value }, {}, {}
    _G.C_CVar = {
      GetCVar = function(name) return cvar[name] end,
      SetCVar = function(name, v) cvar[name] = tostring(v); writes[#writes + 1] = name .. "=" .. tostring(v) end,
    }
    _G.WFJ_DB = saved
    WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    S = WFJ.Settings
    realPrint = _G.print
    _G.print = function(text) said[#said + 1] = text end
  end

  local function login() Stub.fireAll("PLAYER_ENTERING_WORLD", true, false) end
  local function lines()
    local n = 0
    for _, text in ipairs(said) do
      if tostring(text):find("ネームプレート", 1, true) or tostring(text):find("nameplates", 1, true) then n = n + 1 end
    end
    return n
  end

  after_each(function()
    _G.print = realPrint
    _G.C_CVar = nil
    Stub.combat = false
  end)

  it("choosing Japanese names turns the nameplates on; choosing English puts the old value back", function()
    boot("0", { schema = 1, settings = {}, intro = true, asked = true, askedNames = true })
    login()
    assert.are.same({}, writes) -- nothing at login: names are English
    S.set("names.japanese", true)
    assert.are.same({ CVAR .. "=1" }, writes)
    assert.are.equal("0", _G.WFJ_DB.namePlatesWas)
    S.set("names.japanese", false)
    assert.are.same({ CVAR .. "=1", CVAR .. "=0" }, writes)
    assert.is_nil(_G.WFJ_DB.namePlatesWas)
    assert.are.equal(0, lines())
  end)

  it("nameplates that were on already are left on when the player goes back to English names", function()
    boot("1", { schema = 1, settings = {}, intro = true, asked = true, askedNames = true })
    login()
    S.set("names.japanese", true)
    S.set("names.japanese", false)
    assert.are.same({}, writes)
  end)

  it("the saved choice writes nothing at load: a value the player set by hand stays", function()
    boot("0", { schema = 1, settings = { ["names.japanese"] = true }, intro = true, asked = true, askedNames = true })
    login()
    assert.are.same({}, writes)
    assert.are.equal(1, lines()) -- and the login says names over heads are English
  end)

  it("turning the nameplates off by hand with Japanese names on says the line once", function()
    boot("0", { schema = 1, settings = {}, intro = true, asked = true, askedNames = true })
    login()
    S.set("names.japanese", true)
    assert.are.equal(0, lines())
    cvar[CVAR] = "0"
    Stub.fireAll("CVAR_UPDATE", CVAR, "0")
    Stub.fireAll("CVAR_UPDATE", "somethingElse", "1")
    assert.are.equal(1, lines())
    assert.are.same({ CVAR .. "=1" }, writes) -- never turned back on behind the player's back
  end)

  it("in combat the write waits for the fight to end", function()
    boot("0", { schema = 1, settings = {}, intro = true, asked = true, askedNames = true })
    login()
    Stub.combat = true
    S.set("names.japanese", true)
    assert.are.same({}, writes)
    Stub.combat = false
    Stub.fireAll("PLAYER_REGEN_ENABLED")
    assert.are.same({ CVAR .. "=1" }, writes)
  end)

  it("a choice reversed during the same fight leaves the nameplates as the last choice wants them", function()
    boot("0", { schema = 1, settings = {}, intro = true, asked = true, askedNames = true })
    login()
    S.set("names.japanese", true) -- on, the earlier value kept
    Stub.combat = true
    S.set("names.japanese", false) -- waits for the fight to end
    S.set("names.japanese", true) -- changed their mind: nothing is to be written after all
    Stub.combat = false
    Stub.fireAll("PLAYER_REGEN_ENABLED")
    assert.are.equal("1", cvar[CVAR])
    assert.are.equal("0", _G.WFJ_DB.namePlatesWas)
    assert.are.equal(0, lines())
  end)

  it("a write a reload cut off is made at the next login", function()
    boot("0", { schema = 1, settings = { ["names.japanese"] = true }, namePlatesWas = "0", intro = true,
      asked = true, askedNames = true })
    login() -- Japanese names were chosen in a fight and the interface was reloaded before it ended
    assert.are.same({ CVAR .. "=1" }, writes)
    assert.are.equal(0, lines())
  end)

  it("a client without the setting is left alone", function()
    boot(nil, { schema = 1, settings = {}, intro = true, asked = true, askedNames = true })
    login()
    S.set("names.japanese", true)
    assert.are.same({}, writes)
    assert.are.same({}, WFJ.initErrors)
  end)
end)
