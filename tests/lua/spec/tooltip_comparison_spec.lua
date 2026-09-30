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
    files[#files + 1] = "UI/Tooltip.lua"
    WFJ = H.loadChunks(files)
    H.uiSetup(WFJ, UI, { lookup = function(kind, id)
      if kind == "item.description" then return DATA[id] end
    end })
    WFJ.Lookup = { get = function(kind, id) return kind == "item.description" and DATA[id] or nil end }
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
