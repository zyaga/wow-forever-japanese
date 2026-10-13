-- UI/Tooltip over coloured and indented item tooltip lines: "Made by" with and without its colour code, the sell
-- price range as the client indents it, a line coloured end to end, coloured runs, and the dual-wield comparison line
-- of a comparison tooltip.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
for _, f in ipairs({ "UI/TimeLine.lua", "UI/Tooltip.lua", "UI/TooltipUnit.lua" }) do
  FILES[#FILES + 1] = f
end

local UI = {
  ITEM_CREATED_BY = { "|cff00ff00<Made by %s>|r", "|cff00ff00<製作者: %s>|r" },
  ITEM_ENCHANT_TIME_LEFT_MIN = { "%s (%d min)", "%s (%d分)" }, ITEM_MISSING = { "%s missing", "%sが不足" },
  MINIMUM = { "Minimum", "最低" }, MAXIMUM = { "Maximum", "最高" }, SELL_PRICE = { "Sell Price", "売値" },
  ARMOR_TEMPLATE = { "%s Armor", "アーマー %s" }, ITEM_MIN_LEVEL = { "Requires Level %d", "必要レベル %d" },
  ["SpellItemEnchantment:387"] = { "+17 Armor", "アーマー +17" }, -- an enchantment's whole text
  ITEM_BIND_ON_PICKUP = { "Binds when picked up", "拾うとソウルバウンド" },
  CURRENTLY_EQUIPPED = { "Currently Equipped", "装備中" },
  ITEM_DELTA_DUAL_WIELD_COMPARISON_MAINHAND_DESCRIPTION = { "(With |c%s%s|r equipped in your main-hand)",
    "(メインハンドに|c%s%s|rを装備した場合)" },
}

describe("UI/Tooltip: colour-wrapped names, coloured lines, the sell price range", function()
  local WFJ, tt

  local function left(i) return _G["GameTooltipTextLeft" .. i] end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    WFJ.Tooltip.init()
    tt = _G.GameTooltip
  end)

  after_each(function() H.uiTeardown() end)

  it("Made by: the name kept, with the colour code the client wrote or without it", function()
    Stub.setItemTooltip(tt, "|Hitem:2589:0:0:0|h[Linen Cloth]|h",
      { "Linen Cloth", "|cff00ff00<Made by Reyn>|r", "Minimum: 5c", "Maximum: 1g 20s" })
    assert.are.equal("|cff00ff00<製作者: Reyn>|r", left(2):GetText())
    assert.are.equal("最低: 5c", left(3):GetText())
    assert.are.equal("最高: 1g 20s", left(4):GetText())
    Stub.setItemTooltip(tt, "|Hitem:2589:0:0:0|h[Linen Cloth]|h", { "Linen Cloth", "<Made by Wind Mami>" })
    assert.are.equal("<製作者: Wind Mami>", left(2):GetText())
  end)

  it("an item tooltip asks by key for its lines of a broad shape: an enchant's time left, a missing item", function()
    Stub.setItemTooltip(tt, "|Hitem:2488:0:0:0|h[Worn Shortsword]|h",
      { "Worn Shortsword", "Sharpened (5 min)", "Hearthstone missing" })
    assert.are.equal("Sharpened (5分)", left(2):GetText())
    assert.are.equal("Hearthstoneが不足", left(3):GetText())
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
