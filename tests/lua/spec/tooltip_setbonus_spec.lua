-- An item set's bonus lines: the client fills "(2) Set: %s" / "Set: %s" with a bonus spell's description. A line takes
-- the bonus spell whose rendered description is the line, when the gate accepts its Japanese; else it stays English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  ITEM_SET_BONUS = { "Set: %s", "セット: %s" },
  ITEM_SET_BONUS_GRAY = { "(%d) Set: %s", "(%d) セット: %s" },
}
local SPELLS = {
  [460230] = { ja = "命中率を$N1%上昇させます。", status = "u" },
  [460231] = { ja = "攻撃力が$N1上昇します。", status = "u" },
}

describe("UI/Tooltip set bonus lines", function()
  local WFJ, tt, bonuses, records

  local function left(i) return _G["GameTooltipTextLeft" .. i] end
  local function show(lines)
    Stub.setItemTooltip(tt, "|Hitem:15062:0:0:0|h[Devilsaur Leggings]|h", lines)
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    local files = {}
    for i, f in ipairs(H.UI_FILES) do files[i] = f end
    files[#files + 1] = "UI/TimeLine.lua"
    files[#files + 1] = "UI/Tooltip.lua"
    WFJ = H.loadChunks(files)
    H.uiSetup(WFJ, UI)
    WFJ.Lookup = { get = function(kind, id) return kind == "spell.description" and SPELLS[id] or nil end }
    WFJ.GateText = function(entry, lines) return WFJ.Align.check(entry and entry.ja, lines) end
    bonuses = { 460230 }
    -- the bonus spell's description as the client renders it (C_Spell.GetSpellDescription)
    Stub.spellDescriptions[460230] = "Improves your chance to hit by 2.0%."
    _G.C_Item = { GetSetBonusesForSpecializationByItemID = function(_, id)
      return id == 15062 and bonuses or {}
    end }
    records = {}
    WFJ.Collector.record = function(kind, id, field, raw)
      records[#records + 1] = { kind, id, field, raw }
      return "recorded"
    end
    WFJ.Tooltip.init()
    tt = _G.GameTooltip
  end)

  after_each(function()
    H.uiTeardown()
    _G.C_Item = nil
    Stub.keys.alt = false
  end)

  it("a bonus not yet active is written with its spell's Japanese; Alt shows the English", function()
    show({ "Devilsaur Leggings", "Devilsaur Armor (0/2)", "(2) Set: Improves your chance to hit by 2.0%." })
    assert.are.equal("(2) セット: 命中率を2.0%上昇させます。", left(3):GetText())
    assert.are.equal("Devilsaur Armor (0/2)", left(2):GetText()) -- the set's name stays English
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("(2) Set: Improves your chance to hit by 2.0%.", left(3):GetText())
  end)

  it("an active bonus is read by the client's own \"Set: \"", function()
    show({ "Devilsaur Leggings", "Set: Improves your chance to hit by 2.0%." })
    assert.are.equal("セット: 命中率を2.0%上昇させます。", left(2):GetText())
  end)

  it("each line takes the spell whose description the client renders as that line", function()
    bonuses = { 460231, 460230 }
    Stub.spellDescriptions[460230] = "Improves your chance to hit by 2.0%."
    Stub.spellDescriptions[460231] = "+40 Attack Power."
    show({ "Devilsaur Leggings", "(2) Set: Improves your chance to hit by 2.0%.", "(3) Set: +40 Attack Power." })
    assert.are.equal("(2) セット: 命中率を2.0%上昇させます。", left(2):GetText())
    assert.are.equal("(3) セット: 攻撃力が40上昇します。", left(3):GetText())
  end)

  it("a line whose spell the client does not name stays English, even when a Japanese would fit it", function()
    bonuses = { 460231, 460230 }
    Stub.spellDescriptions[460230] = nil
    show({ "Devilsaur Leggings", "(2) Set: Improves your chance to hit by 2.0%." })
    assert.are.equal("(2) Set: Improves your chance to hit by 2.0%.", left(2):GetText())
  end)

  it("a line no spell fits stays English whole and is recorded under the one spell left", function()
    bonuses = { 460230, 999 }
    show({ "Devilsaur Leggings", "(2) Set: Improves your chance to hit by 2.0%.", "(4) Set: Something new." })
    assert.are.equal("(4) Set: Something new.", left(3):GetText())
    assert.are.same({ "spell", 999, "description", "Something new." }, records[#records])
  end)

  it("a bonus line the client wrote with no text yet shows its own words in Japanese", function()
    -- as the window test showed set items on Forever 1.60.1.71091: "(4) Set: " and "Set: " with nothing after
    show({ "Devilsaur Leggings", "Set: ", "(4) Set: " })
    assert.are.equal("セット: ", left(2):GetText())
    assert.are.equal("(4) セット: ", left(3):GetText())
  end)

  it("with Japanese names: the set's heading and the names inside a bonus line in Japanese", function()
    local rows = {}
    local names = { ["Devilsaur Armor"] = "デビルソール・アーマー", ["Attack Power"] = "アタック・パワー" }
    for english, ja in pairs(names) do rows[WFJ.Names.key(english)] = ja .. "\t" .. ja end
    WFJ.Data.add("name", rows)
    SPELLS[460232] = { ja = "Attack Powerが$N1上昇します。", status = "u" }
    bonuses = { 460232 }
    Stub.spellDescriptions[460232] = "Increases Attack Power by 40."
    WFJ.State.names = true
    show({ "Devilsaur Leggings", "Devilsaur Armor (1/2)", "(2) Set: Increases Attack Power by 40." })
    assert.are.equal("デビルソール・アーマー (1/2)", left(2):GetText())
    assert.are.equal("(2) セット: アタック・パワーが40上昇します。", left(3):GetText())
    WFJ.State.names = false
    SPELLS[460232] = nil
  end)

  it("without the client's set API the lines stay English", function()
    _G.C_Item = nil
    show({ "Devilsaur Leggings", "(2) Set: Improves your chance to hit by 2.0%." })
    assert.are.equal("(2) Set: Improves your chance to hit by 2.0%.", left(2):GetText())
  end)
end)
