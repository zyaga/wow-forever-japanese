-- UI/CombatText.lua over the floating combat text replayed from Forever blizzard_combattext/shared/
-- combattext.lua: AddMessage (:335–430) acquires a pooled FontString, SetText(message), appends it to
-- activeFontStrings. Whole-message words translate; numbers, names and secret values are never matched.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/CombatText.lua"

local UI = {
  COMBAT_TEXT_MISS = { "Miss", "ミス" },
  MISS = { "Miss", "ミス" }, -- shares its English with COMBAT_TEXT_MISS
  COMBAT_TEXT_DODGE = { "Dodge", "回避" },
  COMBAT_TEXT_ABSORB = { "Absorb", "吸収" },
  ENTERING_COMBAT = { "Entering Combat", "戦闘開始" },
  LEAVING_COMBAT = { "Leaving Combat", "戦闘終了" },
  COMBAT_TEXT_COMBO_POINTS = { "<%d Combo |4Point:Points;>", "<コンボポイント %d>" },
  CANCEL = { "Cancel", "キャンセル" }, -- a dictionary word outside the combat text set
  -- the trailers (their English starts with a space: " (%d absorbed)")
  ABSORB_TRAILER = { " (%d absorbed)", "（%d吸収）" }, BLOCK_TRAILER = { " (%d blocked)", "（%dブロック）" },
  RESIST_TRAILER = { " (%d resisted)", "（%d抵抗）" },
}
-- the energize and aura-end forms (the trailers are above)
local UI45 = {
  COMBO_POINTS = { "Combo |4Point:Points;", "コンボポイント" },
  AURA_END = { "<%s> fades", "<%s>が消えた" },
}
local function en(key) return UI[key][1] end
local function ja(key) return UI[key][2] end

local SECRET = {}

-- CombatText with a two-string pool, so reuse happens quickly.
local function installCombatText()
  local frame = CreateFrame("Frame", "CombatText")
  frame.activeFontStrings = {}
  frame.pool = { Stub.fontString(""), Stub.fontString("") }
  function frame.AddMessage(self, message)
    local fs = table.remove(self.pool, 1)
    if not fs then -- recycle the oldest, as the pool does once a message has scrolled away
      fs = table.remove(self.activeFontStrings, 1)
    end
    fs.text = message
    table.insert(self.activeFontStrings, fs)
  end
  return frame
end

describe("the floating combat text on Forever", function()
  local WFJ

  local function load()
    local ns = H.loadChunks(FILES)
    H.uiSetup(ns, UI)
    return ns
  end

  local function fresh()
    H.uiTeardown()
    _G.CombatText, _G.CombatText_LoadUI, _G.issecretvalue = nil, nil, nil
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    _G.CombatText_LoadUI = function() end
    _G.issecretvalue = function(v) return v == SECRET end
  end

  local function last() return _G.CombatText.activeFontStrings[#_G.CombatText.activeFontStrings] end

  before_each(function()
    fresh()
    WFJ = load()
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.CombatText, _G.CombatText_LoadUI, _G.issecretvalue = nil, nil, nil
  end)

  it("addon already loaded: words translate; numbers, names and fragments stay as written", function()
    installCombatText()
    Stub.loadedAddons["Blizzard_CombatText"] = true
    assert.is_true(WFJ.CombatText.init())
    _G.CombatText:AddMessage(en("COMBAT_TEXT_MISS"))
    assert.are.equal(ja("COMBAT_TEXT_MISS"), last():GetText())
    _G.CombatText:AddMessage(en("ENTERING_COMBAT"))
    assert.are.equal(ja("ENTERING_COMBAT"), last():GetText())
    _G.CombatText:AddMessage("<3 Combo Points>")
    assert.are.equal("<コンボポイント 3>", last():GetText())
    for _, message in ipairs({ "-152", "+40", "<Cancel>", "<Cancel> fades", "-5 (3 blocked)", "+40 Mana", "(Cancel +5)",
      "Cancel", "+40 [Healer]  (12 absorbed)" }) do
      _G.CombatText:AddMessage(message)
      assert.are.equal(message, last():GetText())
    end
  end)

  it("the combo-point energize and an aura's end translate; numbers and names kept", function()
    fresh()
    local ns = H.loadChunks(FILES)
    local ui = {}
    for k, v in pairs(UI) do ui[k] = v end
    for k, v in pairs(UI45) do ui[k] = v end
    ui.COMBAT_TEXT_COMBO_POINTS = nil
    H.uiSetup(ns, ui)
    installCombatText()
    Stub.loadedAddons["Blizzard_CombatText"] = true
    ns.CombatText.init()
    local cases = {
      { "<3 Combo |4Point:Points;>", "<3 コンボポイント>" },
      { "<Cancel> fades", "<Cancel>が消えた" },
      { "-5  (3 crushed)", "-5  (3 crushed)" }, -- no trailer key: as written
      { "<2 Holy Power>", "<2 Holy Power>" }, -- another power word: as written
      { "+40 [Thrall]  (1,200 absorbed)", "+40 [Thrall]  (1,200 absorbed)" }, -- a healer's name: never read
    }
    for _, c in ipairs(cases) do
      _G.CombatText:AddMessage(c[1])
      assert.are.equal(c[2], last():GetText())
    end
    _G.CombatText:AddMessage("<Cancel> fades")
    local fs = last()
    Stub.keys.alt = true
    ns.Modifier.refresh()
    assert.are.equal("<Cancel> fades", fs:GetText())
    Stub.keys.alt = false
    ns.Modifier.refresh()
    assert.are.equal("<Cancel>が消えた", fs:GetText())
  end)

  it("a number joined to a trailer keeps the number and shows the trailer in Japanese", function()
    installCombatText()
    Stub.loadedAddons["Blizzard_CombatText"] = true
    WFJ.CombatText.init()
    _G.CombatText:AddMessage("-152  (40 blocked)") -- combattext.lua:237: "-"..data.." "..format(BLOCK_TRAILER, arg3)
    assert.are.equal("-152 （40ブロック）", last():GetText())
    _G.CombatText:AddMessage("+1,240  (12 absorbed)")
    assert.are.equal("+1,240 （12吸収）", last():GetText())
    _G.CombatText:AddMessage("-9  (3 resisted)")
    assert.are.equal("-9 （3抵抗）", last():GetText())
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal("-9  (3 resisted)", last():GetText())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    _G.CombatText:AddMessage(SECRET) -- a secret amount is never read
    assert.are.equal(SECRET, last():GetText())
  end)

  it("a reused FontString forgets its word: Alt never puts it back over a number or a secret", function()
    installCombatText()
    Stub.loadedAddons["Blizzard_CombatText"] = true
    WFJ.CombatText.init()
    _G.CombatText:AddMessage(en("COMBAT_TEXT_DODGE"))
    local first = last()
    _G.CombatText:AddMessage(en("COMBAT_TEXT_ABSORB"))
    _G.CombatText:AddMessage("-152") -- reuses `first`
    assert.are.equal(first, last())
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal("-152", first:GetText())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    assert.are.equal("-152", first:GetText())
    assert.has_no.errors(function() _G.CombatText:AddMessage(SECRET) end)
    assert.are.equal(SECRET, last():GetText())
  end)

  it("addon loaded later: the hook goes in on ADDON_LOADED", function()
    assert.is_false(WFJ.CombatText.init())
    installCombatText()
    Stub.loadedAddons["Blizzard_CombatText"] = true
    WFJ.LoadOnDemand.loaded("Blizzard_CombatText")
    _G.CombatText:AddMessage(en("LEAVING_COMBAT"))
    assert.are.equal(ja("LEAVING_COMBAT"), last():GetText())
    assert.are.equal(1, #Stub.hooks["CombatText:AddMessage"])
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    local frame = installCombatText()
    frame.activeFontStrings = "moved"
    Stub.loadedAddons["Blizzard_CombatText"] = true
    assert.has_no.errors(function() assert.is_false(WFJ.CombatText.init()) end)
    fresh()
    local ns = load()
    frame = installCombatText()
    _G.issecretvalue = "not a function"
    Stub.loadedAddons["Blizzard_CombatText"] = true
    assert.has_no.errors(function() assert.is_true(ns.CombatText.init()) end)
    assert.has_no.errors(function()
      frame:AddMessage(en("COMBAT_TEXT_MISS"))
      frame:AddMessage(42)
      ns.CombatText.onAddMessage("x", "Miss")
      ns.CombatText.onAddMessage({ activeFontStrings = { 7 } }, "Miss")
    end)
  end)

  it("a client without the combat text loader or frame is skipped without error", function()
    fresh()
    _G.CombatText_LoadUI = nil
    local bare = load()
    assert.has_no.errors(function() assert.is_false(bare.CombatText.init()) end)
  end)
end)
