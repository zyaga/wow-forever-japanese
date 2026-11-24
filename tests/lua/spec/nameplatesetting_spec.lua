-- UI/NamePlateSetting: the client's nameplate settings follow the names choice, and a chat line says when
-- Japanese names are on with nameplates off.
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
    assert.are.equal("0", _G.WFJ_DB.namePlatesWas[CVAR])
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
    assert.are.equal("0", _G.WFJ_DB.namePlatesWas[CVAR])
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

  -- every creature with a name over its head: enemies and neutral ones, their minions and minor units, friendly
  -- NPCs, and out of combat too
  local ALL = { "nameplateShowFriendlyNpcs", "nameplateShowEnemies", "nameplateShowAll",
    "nameplateShowEnemyMinions", "nameplateShowEnemyMinus" }
  local function every(value)
    for _, name in ipairs(ALL) do cvar[name] = value end
  end

  it("Japanese names turn on the nameplates of every creature, and English names put each one back", function()
    boot("0", { schema = 1, settings = {}, intro = true, asked = true, askedNames = true })
    every("0")
    cvar.nameplateShowEnemies = "1" -- the player had enemy nameplates on already
    login()
    S.set("names.japanese", true)
    for _, name in ipairs(ALL) do assert.are.equal("1", cvar[name], name) end
    assert.is_nil(_G.WFJ_DB.namePlatesWas.nameplateShowEnemies) -- on before: nothing to put back
    assert.are.equal("0", _G.WFJ_DB.namePlatesWas.nameplateShowAll)
    S.set("names.japanese", false)
    assert.are.equal("1", cvar.nameplateShowEnemies)
    for _, name in ipairs({ "nameplateShowFriendlyNpcs", "nameplateShowAll", "nameplateShowEnemyMinions",
      "nameplateShowEnemyMinus" }) do
      assert.are.equal("0", cvar[name], name)
    end
    assert.is_nil(_G.WFJ_DB.namePlatesWas)
    assert.are.equal(0, lines())
  end)

  it("a player who chose Japanese names on an older version gets the new settings at login, once", function()
    boot("1", { schema = 1, settings = { ["names.japanese"] = true }, namePlatesWas = "0", intro = true,
      asked = true, askedNames = true })
    every("0")
    cvar.nameplateShowFriendlyNpcs = "1"
    login()
    for _, name in ipairs(ALL) do assert.are.equal("1", cvar[name], name) end
    assert.are.equal("0", _G.WFJ_DB.namePlatesWas.nameplateShowFriendlyNpcs) -- the old saved value, kept
    assert.are.equal("0", _G.WFJ_DB.namePlatesWas.nameplateShowEnemies)
    assert.are.equal(0, lines())
    -- turned off by hand afterwards: said once, never turned back on, also not at the next login
    writes = {}
    cvar.nameplateShowEnemies = "0"
    Stub.fireAll("CVAR_UPDATE", "nameplateShowEnemies", "0")
    assert.are.equal(1, lines())
    assert.are.same({}, writes)
  end)

  -- the nameplate range and the client's English names over NPC heads
  local OVERHEAD = { "UnitNameNPC", "UnitNameHostleNPC", "UnitNameInteractiveNPC", "UnitNameFriendlySpecialNPCName" }

  it("Japanese names widen the nameplate range and hide the English names over NPC heads; English puts them back",
    function()
      boot("0", { schema = 1, settings = {}, intro = true, asked = true, askedNames = true })
      every("0")
      cvar.nameplateMaxDistance = "20"
      for _, name in ipairs(OVERHEAD) do cvar[name] = "1" end
      cvar.UnitNameFriendlySpecialNPCName = "0" -- already off: nothing to put back
      login()
      S.set("names.japanese", true)
      assert.are.equal("60", cvar.nameplateMaxDistance)
      for _, name in ipairs(OVERHEAD) do assert.are.equal("0", cvar[name], name) end
      assert.are.equal("20", _G.WFJ_DB.namePlatesWas.nameplateMaxDistance)
      assert.are.equal("1", _G.WFJ_DB.namePlatesWas.UnitNameNPC)
      assert.is_nil(_G.WFJ_DB.namePlatesWas.UnitNameFriendlySpecialNPCName)
      S.set("names.japanese", false)
      assert.are.equal("20", cvar.nameplateMaxDistance)
      for _, name in ipairs({ "UnitNameNPC", "UnitNameHostleNPC", "UnitNameInteractiveNPC" }) do
        assert.are.equal("1", cvar[name], name)
      end
      assert.are.equal("0", cvar.UnitNameFriendlySpecialNPCName)
      assert.are.equal(0, lines())
    end)

  it("a client that holds the range to its own limit is not written again at each login", function()
    boot("1", { schema = 1, settings = {}, intro = true, asked = true, askedNames = true })
    every("1")
    cvar.nameplateMaxDistance = "20"
    _G.C_CVar.SetCVar = function(name, v)
      writes[#writes + 1] = name .. "=" .. tostring(v)
      cvar[name] = name == "nameplateMaxDistance" and tostring(math.min(tonumber(v), 41)) or tostring(v)
    end
    login()
    S.set("names.japanese", true)
    assert.are.equal("41", cvar.nameplateMaxDistance)
    writes = {}
    Stub.fireAll("PLAYER_ENTERING_WORLD", false, true)
    assert.are.same({}, writes)
  end)

  it("a player who already had Japanese names gets the range and the overhead names at the next login", function()
    boot("1", { schema = 1, settings = { ["names.japanese"] = true }, intro = true, asked = true, askedNames = true,
      namePlatesAsked = { nameplateShowFriendlyNpcs = true, nameplateShowEnemies = true, nameplateShowAll = true,
        nameplateShowEnemyMinions = true, nameplateShowEnemyMinus = true } })
    every("1")
    cvar.nameplateMaxDistance = "20"
    for _, name in ipairs(OVERHEAD) do cvar[name] = "1" end
    login()
    assert.are.equal("60", cvar.nameplateMaxDistance)
    for _, name in ipairs(OVERHEAD) do assert.are.equal("0", cvar[name], name) end
    assert.are.equal(0, lines())
  end)

  it("a minor setting turned off by hand says nothing: those creatures are the player's call", function()
    boot("0", { schema = 1, settings = {}, intro = true, asked = true, askedNames = true })
    every("0")
    login()
    S.set("names.japanese", true)
    cvar.nameplateShowEnemyMinus = "0"
    Stub.fireAll("CVAR_UPDATE", "nameplateShowEnemyMinus", "0")
    assert.are.equal(0, lines())
  end)
end)
