-- tests/lua/spec/buffidentity_spec.lua: UI/BuffIdentity, the buff bar model that names a buff the client hides.
local function load()
  local WFJ = { Compat = { resolve = function(name)
    if name == "issecretvalue" then return function(v) return type(v) == "table" and v.secret == true end end
    if name == "GetTime" then return function() return _G.NOW end end
    if name == "BuffFrame" then return _G.BuffFrame end
    if name == "C_UnitAuras.GetAuraDataByAuraInstanceID" then return _G.AuraById end
    if name == "GetBuildInfo" then return function() return "1.60.1", "70170" end end
    if name == "InCombatLockdown" then return function() return _G.InCombat == true end end
    return nil
  end } }
  assert(loadfile("addon/WoWForeverJapanese/UI/BuffIdentity.lua"))("WoWForeverJapanese", WFJ)
  return WFJ.BuffIdentity
end

local SECRET = { secret = true }

-- A buff bar with `ids` (instance ids, or SECRET) at positions 1..n; `owned` is the hovered position.
local function bar(ids, owned)
  local frames = {}
  for i, id in ipairs(ids) do
    frames[i] = { buttonInfo = { auraType = "Buff", index = i, auraInstanceID = id },
      IsShown = function() return true end }
  end
  _G.BuffFrame = { auraFrames = frames }
  return { IsOwned = function(_, b) return owned ~= nil and frames[owned] == b end }
end

describe("UI/BuffIdentity", function()
  local AURAS = { [11] = { spellId = 1126, expirationTime = 0, duration = 0 },
    [12] = { spellId = 1259799, expirationTime = 115, duration = 15 } }

  before_each(function()
    _G.NOW = 100
    _G.AuraById = function(_, id) return AURAS[id] end
  end)

  describe("step", function()
    local selfSpells = { [1259799] = 15 }

    it("adds the spell just cast when exactly one button is added", function()
      local B = load()
      local out = B.step({ { spell = 1126, expires = 0 } }, 2, 100.5, selfSpells, { spell = 1259799, at = 100 })
      assert.are.equal(1259799, out[2].spell)
      assert.are.equal(115, out[2].expires)
    end)

    it("gives up on an added button with no fitting cast (another player's buff, a proc)", function()
      local B = load()
      assert.is_nil(B.step({}, 1, 100, selfSpells, nil))
      assert.is_nil(B.step({}, 1, 105, selfSpells, { spell = 1259799, at = 100 })) -- the cast is too old
      assert.is_nil(B.step({}, 1, 100, {}, { spell = 1259799, at = 100 })) -- not known to buff the player
      assert.is_nil(B.step({}, 2, 100, selfSpells, { spell = 1259799, at = 100 })) -- two at once
    end)

    it("refuses a cast whose buff is already on the bar but a button was added", function()
      local B = load()
      assert.is_nil(B.step({ { spell = 1259799, expires = 110 } }, 2, 100, selfSpells, { spell = 1259799, at = 100 }))
    end)

    it("removes the buff whose end time came, and gives up when that is not clear-cut", function()
      local B = load()
      local list = { { spell = 1126, expires = 0 }, { spell = 1259799, expires = 115 } }
      local out = B.step(list, 1, 115.2, selfSpells, nil)
      assert.are.equal(1, #out)
      assert.are.equal(1126, out[1].spell)
      assert.is_nil(B.step(list, 1, 105, selfSpells, nil)) -- nothing due: someone removed a buff
    end)

    it("refreshes the end time of a recast buff", function()
      local B = load()
      local out = B.step({ { spell = 1259799, expires = 110 } }, 1, 108, selfSpells, { spell = 1259799, at = 108 })
      assert.are.equal(123, out[1].expires)
    end)
  end)

  describe("forTooltip", function()
    it("is refused until the model has been confirmed while the bar was readable", function()
      local B = load()
      B.load({})
      local tooltip = bar({ 11 }, 1)
      B.onAurasChanged()
      local spell, why = B.forTooltip(tooltip)
      assert.is_nil(spell)
      assert.truthy(why:find("not confirmed", 1, true))
    end)

    it("learns a self buff, confirms its predictions, then names a hidden buff by position", function()
      local B = load()
      local saved = {}
      B.load(saved)
      bar({ 11 })
      B.onAurasChanged() -- readable: the bar as it is
      for round = 1, B.MIN_CONFIRMED + 1 do
        B.onCast(1259799)
        bar({ 11, 12 })
        _G.NOW = _G.NOW + 0.2
        B.onAurasChanged() -- readable: learnt the first time, a confirmed prediction after
        _G.NOW = 115.3 + (round - 1) * 20
        AURAS[12].expirationTime = _G.NOW + 20 - 0.3
        bar({ 11 })
        B.onAurasChanged()
        _G.NOW = _G.NOW + 5
      end
      assert.is_nil(saved.buffIdentity.lastMiss)
      assert.is_true(saved.buffIdentity.confirmed >= B.MIN_CONFIRMED)
      -- in combat: the new buff's id is hidden, the model names it from the cast and the button's position
      B.onCast(1259799)
      local tooltip = bar({ 11, SECRET }, 2)
      _G.AuraById = function(_, id) if id == 11 then return AURAS[11] end end
      B.onAurasChanged()
      local spell, instance = B.forTooltip(tooltip)
      assert.are.equal(1259799, spell)
      assert.is_nil(instance)
    end)

    it("learns a spell cast in a fight once its buff is still on the bar after the fight", function()
      local B = load()
      local saved = {}
      B.load(saved)
      _G.InCombat = true
      B.onCast(1259799)
      bar({ 11, SECRET })
      B.onAurasChanged() -- hidden: nothing learnt
      assert.is_nil(saved.buffIdentity.selfSpells[1259799])
      _G.InCombat = false
      _G.NOW = 108
      bar({ 11, 12 })
      B.onAurasChanged() -- the fight is over and the buff is still there
      assert.are.equal(15, saved.buffIdentity.selfSpells[1259799])
    end)

    it("sets its confirmations back to 0 after a wrong prediction, so it waits to be confirmed again", function()
      local B = load()
      local saved = {}
      B.load(saved)
      saved.buffIdentity.selfSpells[1259799] = 15
      saved.buffIdentity.confirmed = B.MIN_CONFIRMED
      bar({ 11 })
      B.onAurasChanged()
      B.onCast(1259799)
      AURAS[13] = { spellId = 774, expirationTime = 200, duration = 100 } -- something else arrived
      bar({ 11, 13 })
      B.onAurasChanged()
      assert.are.equal(0, saved.buffIdentity.confirmed)
      assert.are.equal(1, saved.buffIdentity.misses)
      local spell, why = B.forTooltip(bar({ 11, 13 }, 2))
      assert.is_nil(spell)
      assert.truthy(why:find("not confirmed", 1, true))
    end)
  end)
end)
