-- ADR-038: UI/Tooltip additions. A comparison tooltip's lines appended after its item post-call (the delta
-- header and the cycling hint, blizzard_sharedxmlgame/tooltip/tooltipcomparisonmanager.lua:250–316) render Japanese,
-- key-only, the key binding kept; an item spell line's max-usable-level trailer (ITEM_SPELL_MAX_USABLE_LEVEL) is peeled
-- off the run: a trusted translation gets the trailer's Japanese appended, a gated one keeps its English. Every
-- other tooltip spec runs against the same module unchanged.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  ITEM_DELTA_DESCRIPTION = { "If you replace this item, the following stat changes will occur:",
    "このアイテムを置き換えると、次の能力値の変化が起こります:" },
  ITEM_COMPARISON_SWAP_ITEM_MAINHAND_DESCRIPTION = { "Press %s to cycle through your main-hand items.",
    "%sでメインハンドのアイテムを切り替えます。" },
  ITEM_SPELL_MAX_USABLE_LEVEL = { " (Requires level %d or below)", "(レベル%d以下が必要)" },
  INVTYPE_WEAPONMAINHAND = { "Main Hand", "メインハンド" },
  ARMOR_TEMPLATE = { "%s Armor", "アーマー %s" },
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = { "damage per second", "秒間ダメージ" },
  ["SpellItemEnchantment:387"] = { "+17 Armor", "アーマー +17" }, -- an enchantment's whole text
}
local DATA = {
  [1001] = { ja = "体力を50回復する。", status = "." }, -- trusted, ungated
  [1002] = { ja = "体力を$N1回復する。", status = "u" }, -- gated
}
local POTION_LINES = function(id)
  return "|Hitem:" .. id .. ":0:0:0|h[Minor Potion]|h", { "Minor Potion",
    "Use: Restores 50 health. (Requires level 60 or below)", "Sell Price: 5c" }
end

describe("UI/Tooltip comparison lines and the max-usable-level trailer", function()
  local WFJ

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    local files = {}
    for i, f in ipairs(H.UI_FILES) do files[i] = f end
    files[#files + 1] = "UI/TimeLine.lua"
    files[#files + 1] = "UI/Tooltip.lua"
    WFJ = H.loadChunks(files)
    H.uiSetup(WFJ, UI, { lookup = function(kind, id)
      if kind == "item.description" then return DATA[id] end
    end })
    WFJ.Lookup = { get = function(kind, id) return kind == "item.description" and DATA[id] or nil end }
    -- a C method on the client that never calls the Lua Show; here it only records the state
    _G.ShoppingTooltip1.SetShown = function(self, shown) self.wfjShown = shown end
    WFJ.Tooltip.init()
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
  end)

  it("a comparison tooltip's delta header and cycling hint are Japanese, the key kept; Alt shows English", function()
    local tt = _G.ShoppingTooltip1
    Stub.setItemTooltip(tt, "|Hitem:2:0:0:0|h[Axe]|h", { "Currently Equipped", "Axe", "Main Hand" })
    assert.are.equal("メインハンド", _G.ShoppingTooltip1TextLeft3:GetText()) -- the structural line (unchanged path)
    tt:AddLine(" ")
    tt:AddLine(_G.ITEM_DELTA_DESCRIPTION)
    tt:AddLine("+5 Stamina") -- a delta line: not one of the keys, left alone
    tt:AddLine(_G.ITEM_COMPARISON_SWAP_ITEM_MAINHAND_DESCRIPTION:format("SHIFT-C"))
    tt:Show()
    assert.are.equal("このアイテムを置き換えると、次の能力値の変化が起こります:", _G.ShoppingTooltip1TextLeft5:GetText())
    assert.are.equal("+5 Stamina", _G.ShoppingTooltip1TextLeft6:GetText())
    assert.are.equal("SHIFT-Cでメインハンドのアイテムを切り替えます。", _G.ShoppingTooltip1TextLeft7:GetText())
    assert.are.equal("メインハンド", _G.ShoppingTooltip1TextLeft3:GetText()) -- its record kept
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(_G.ITEM_DELTA_DESCRIPTION, _G.ShoppingTooltip1TextLeft5:GetText())
  end)

  it("Forever shows the frame with SetShown: the delta header and a stat change after it are Japanese", function()
    local tt = _G.ShoppingTooltip1
    Stub.setItemTooltip(tt, "|Hitem:2:0:0:0|h[Boots]|h", { "Ragged Leather Boots", "16 Armor" })
    tt:AddLine(" ")
    tt:AddLine(_G.ITEM_DELTA_DESCRIPTION)
    tt:AddLine("-11 Armor")
    tt:AddLine("|cffff2020-3|r Armor") -- the client colours the number on its own
    tt:AddLine("|cff20ff20+17|r Armor") -- a gain, green; its bare text is the enchantment's whole string
    tt:SetShown(true)
    assert.are.equal("このアイテムを置き換えると、次の能力値の変化が起こります:", _G.ShoppingTooltip1TextLeft4:GetText())
    assert.are.equal("アーマー -11", _G.ShoppingTooltip1TextLeft5:GetText())
    assert.are.equal("アーマー |cffff2020-3|r", _G.ShoppingTooltip1TextLeft6:GetText())
    assert.are.equal("アーマー |cff20ff20+17|r", _G.ShoppingTooltip1TextLeft7:GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("-11 Armor", _G.ShoppingTooltip1TextLeft5:GetText())
    assert.are.equal("|cffff2020-3|r Armor", _G.ShoppingTooltip1TextLeft6:GetText())
    assert.are.equal("|cff20ff20+17|r Armor", _G.ShoppingTooltip1TextLeft7:GetText())
  end)

  it("a stat change with only a short stat name shows the Japanese name, the number as the client wrote it",
  function()
    local tt = _G.ShoppingTooltip1
    Stub.setItemTooltip(tt, "|Hitem:2:0:0:0|h[Staff]|h", { "Handcrafted Staff", "(1.4 damage per second)" })
    tt:AddLine(" ")
    tt:AddLine(_G.ITEM_DELTA_DESCRIPTION)
    tt:AddLine("|cff20ff20+0.7|r damage per second") -- seen in game: the number green, the name white
    tt:AddLine("-2 damage per second")
    tt:AddLine("+3 Unknown Stat") -- a name the dictionary does not hold stays as written
    tt:SetShown(true)
    assert.are.equal("秒間ダメージ |cff20ff20+0.7|r", _G.ShoppingTooltip1TextLeft5:GetText())
    assert.are.equal("秒間ダメージ -2", _G.ShoppingTooltip1TextLeft6:GetText())
    assert.are.equal("+3 Unknown Stat", _G.ShoppingTooltip1TextLeft7:GetText())
    assert.are.equal("(1.4 damage per second)", _G.ShoppingTooltip1TextLeft2:GetText()) -- before the header: not ours
    assert.is_nil(WFJ.UIIndex:match("damage per second")) -- a stat name is asked for by key only (names collide)
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("|cff20ff20+0.7|r damage per second", _G.ShoppingTooltip1TextLeft5:GetText())
  end)

  it("a trusted item translation gets the max-usable-level trailer in Japanese; the Collector sees no trailer",
    function()
      local recorded
      WFJ.Collector.record = function(_, _, _, text) recorded = text end
      Stub.setItemTooltip(_G.GameTooltip, POTION_LINES(1001))
      assert.are.equal("体力を50回復する。(レベル60以下が必要)", _G.GameTooltipTextLeft2:GetText())
      assert.are.equal("Use: Restores 50 health.", recorded)
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("Use: Restores 50 health. (Requires level 60 or below)", _G.GameTooltipTextLeft2:GetText())
    end)

  it("a gated item translation keeps the whole line to its gate (no trailer appended)", function()
    Stub.setItemTooltip(_G.GameTooltip, POTION_LINES(1002))
    local text = _G.GameTooltipTextLeft2:GetText()
    assert.is_nil(text:find("レベル60以下", 1, true))
  end)
end)
