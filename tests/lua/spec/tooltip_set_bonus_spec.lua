-- UI/Tooltip over item tooltip lines with set bonuses and names: a set bonus line shown whole through the set spell's
-- Japanese (the line stays English, whole, when the spell has none), "Made by" with and without its colour code,
-- the sell price range, and the dual-wield comparison line of a comparison tooltip.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
for _, f in ipairs({ "Core/SetBonus.lua", "UI/TimeLine.lua", "UI/Tooltip.lua", "UI/TooltipUnit.lua" }) do
  FILES[#FILES + 1] = f
end

local UI = {
  ITEM_SET_BONUS = { "Set: %s", "セット: %s" }, ITEM_SET_BONUS_GRAY = { "(%d) Set: %s", "(%d) セット: %s" },
  BOSS_BANNER_LOOT_SET = { "Set: %s", "セット: %s" }, -- shares the English and sorts first: the index's name for it
  ITEM_CREATED_BY = { "|cff00ff00<Made by %s>|r", "|cff00ff00<製作者: %s>|r" },
  MINIMUM = { "Minimum", "最低" }, MAXIMUM = { "Maximum", "最高" }, SELL_PRICE = { "Sell Price", "売値" },
  ARMOR_TEMPLATE = { "%s Armor", "アーマー %s" }, ITEM_MIN_LEVEL = { "Requires Level %d", "必要レベル %d" },
  ["SpellItemEnchantment:387"] = { "+17 Armor", "アーマー +17" }, -- an enchantment's whole text
  ITEM_BIND_ON_PICKUP = { "Binds when picked up", "拾うとソウルバウンド" },
  CURRENTLY_EQUIPPED = { "Currently Equipped", "装備中" },
  ITEM_DELTA_DUAL_WIELD_COMPARISON_MAINHAND_DESCRIPTION = { "(With |c%s%s|r equipped in your main-hand)",
    "(メインハンドに|c%s%s|rを装備した場合)" },
}
-- the set spells' Japanese, gated at run time like every spell line (status "u": unaligned)
local SPELLS = {
  [460230] = "スタミナ +$N1。", [18979] = "スタミナ +$N1。", [23863] = "アーマーが$N1上昇します。",
}

describe("UI/Tooltip: set bonuses, colour-wrapped names, the sell price range", function()
  local WFJ, tt

  local function left(i) return _G["GameTooltipTextLeft" .. i] end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI, { lookup = function(kind, id)
      if kind == "spell.description" and SPELLS[id] then return { ja = SPELLS[id], status = "u" } end
      return nil
    end })
    WFJ.Data = WFJ.Data or {}
    -- Data/ItemSets.lua: set → { spell, threshold, … } in threshold order; item → set
    WFJ.Data.itemSets = { [143] = { 460230, 2 }, [142] = { 18979, 2, 23863, 3 }, [144] = { 99999, 2 } }
    WFJ.Data.setItems = { [15062] = 143, [15063] = 143, [13340] = 142, [15070] = 144 }
    WFJ.Tooltip.init()
    tt = _G.GameTooltip
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
  end)

  it("a set bonus line shows whole through the set spell's Japanese, the set name line untouched", function()
    Stub.setItemTooltip(tt, "|Hitem:15062:0:0:0|h[Devilsaur Leggings]|h",
      { "Devilsaur Leggings", "Binds when picked up", "Devilsaur Armor (1/2)", "(2) Set: +4 Stamina.",
        "Sell Price: 12c" })
    assert.are.equal("拾うとソウルバウンド", left(2):GetText())
    assert.are.equal("Devilsaur Armor (1/2)", left(3):GetText())
    assert.are.equal("(2) セット: スタミナ +4。", left(4):GetText())
    assert.are.equal("売値: 12c", left(5):GetText())
  end)

  it("a hover with Alt held records the set line too: English while held, Japanese when let go", function()
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    Stub.setItemTooltip(tt, "|Hitem:15062:0:0:0|h[Devilsaur Leggings]|h",
      { "Devilsaur Leggings", "Devilsaur Armor (1/2)", "(2) Set: +4 Stamina." })
    assert.are.equal("(2) Set: +4 Stamina.", left(3):GetText())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    assert.are.equal("(2) セット: スタミナ +4。", left(3):GetText())
  end)

  it("each set line is its set's bonus in threshold order; an active bonus has no count", function()
    Stub.setItemTooltip(tt, "|Hitem:13340:0:0:0|h[Cadaverous Belt]|h",
      { "Cadaverous Belt", "Cadaverous Garb (2/5)", "Set: +4 Stamina.", "(3) Set: Increases your armor by 50." })
    assert.are.equal("セット: スタミナ +4。", left(3):GetText())
    assert.are.equal("(3) セット: アーマーが50上昇します。", left(4):GetText())
  end)

  it("a set bonus whose spell ships no Japanese leaves the whole line English, never half", function()
    Stub.setItemTooltip(tt, "|Hitem:15070:0:0:0|h[Hidden Belt]|h",
      { "Hidden Belt", "Hidden Armor (1/3)", "(2) Set: +4 Stamina." })
    assert.are.equal("(2) Set: +4 Stamina.", left(3):GetText())
    -- a gray count that is not the spell's threshold is another bonus: left alone
    Stub.setItemTooltip(tt, "|Hitem:15062:0:0:0|h[Devilsaur Leggings]|h",
      { "Devilsaur Leggings", "Devilsaur Armor (1/2)", "(5) Set: +4 Stamina." })
    assert.are.equal("(5) Set: +4 Stamina.", left(3):GetText())
    -- an item in no set has no candidates
    Stub.setItemTooltip(tt, "|Hitem:2488:0:0:0|h[Worn Shortsword]|h", { "Worn Shortsword", "Set: +4 Stamina." })
    assert.are.equal("Set: +4 Stamina.", left(2):GetText())
  end)

  it("Made by: the name kept, with the colour code the client wrote or without it", function()
    Stub.setItemTooltip(tt, "|Hitem:2589:0:0:0|h[Linen Cloth]|h",
      { "Linen Cloth", "|cff00ff00<Made by Reyn>|r", "Minimum: 5c", "Maximum: 1g 20s" })
    assert.are.equal("|cff00ff00<製作者: Reyn>|r", left(2):GetText())
    assert.are.equal("最低: 5c", left(3):GetText())
    assert.are.equal("最高: 1g 20s", left(4):GetText())
    Stub.setItemTooltip(tt, "|Hitem:2589:0:0:0|h[Linen Cloth]|h", { "Linen Cloth", "<Made by Wind Mami>" })
    assert.are.equal("<製作者: Wind Mami>", left(2):GetText())
  end)

  it("a stack's sell price range as the client writes it: the header, then each value indented four spaces", function()
    Stub.setItemTooltip(tt, "|Hitem:2589:0:0:0|h[Linen Cloth]|h",
      { "Linen Cloth", "Sell Price:", "    Minimum: 5c", "    Maximum: 1g 20s" })
    assert.are.equal("売値:", left(2):GetText())
    assert.are.equal("    最低: 5c", left(3):GetText())
    assert.are.equal("    最高: 1g 20s", left(4):GetText())
  end)

  it("a line the client coloured end to end keeps that colour around its Japanese", function()
    Stub.setItemTooltip(tt, "|Hitem:2589:0:0:0|h[Linen Cloth]|h", { "Linen Cloth", "|cffff2020Requires Level 60|r" })
    assert.are.equal("|cffff2020必要レベル 60|r", left(2):GetText())
  end)

  it("a coloured structural line keeps its colours: on the argument, and on a run no argument holds", function()
    Stub.setItemTooltip(tt, "|Hitem:2589:0:0:0|h[Linen Cloth]|h",
      { "Linen Cloth", "16 Armor", "|cffff2020-3|r Armor", "|cff20ff20+17|r Armor" })
    assert.are.equal("アーマー 16", left(2):GetText()) -- matched as written: unchanged by the colour retry
    assert.are.equal("アーマー |cffff2020-3|r", left(3):GetText())
    assert.are.equal("アーマー |cff20ff20+17|r", left(4):GetText())
  end)

  it("the dual-wield comparison line of a comparison tooltip keeps the weapon's colour and name", function()
    local frame = _G.ShoppingTooltip1
    Stub.setItemTooltip(frame, "|Hitem:2488:0:0:0|h[Worn Shortsword]|h",
      { "Currently Equipped", "Worn Shortsword", "(With |cffffffffWorn Dagger|r equipped in your main-hand)" })
    WFJ.Tooltip.onCompareShow(frame)
    assert.are.equal("Worn Shortsword", _G.ShoppingTooltip1TextLeft2:GetText())
    assert.are.equal("(メインハンドに|cffffffffWorn Dagger|rを装備した場合)", _G.ShoppingTooltip1TextLeft3:GetText())
  end)
end)
