-- A recipe's tooltip on Forever: the crafted item's tooltip as a nested block first, then the recipe's own
-- "Use: Teaches you …" line. The tooltip data names both items; each part gets its own item's Japanese.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Align.lua", "Core/State.lua", "Core/Settings.lua",
  "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Normalize.lua", "Core/Hash.lua",
  "Core/Collector.lua", "UI/Font.lua", "UI/Render.lua",
  "UI/TimeLine.lua", "UI/Tooltip.lua", "UI/TooltipUnit.lua" }

local JERKY_JA = "18秒間でhealthを61回復。回復中は\n座っている必要があります。"
local RECIPE_JA = "Tough Jerkyの調理法を習得します。"
local DATA = {
  ["item.description"] = {
    [117] = { ja = JERKY_JA, status = "u" },
    [9000] = { ja = RECIPE_JA, status = "u" },
  },
}
local LINES = { "Recipe: Tough Jerky", "Tough Jerky",
  "Use: Restores 61 health over 18 sec. Must remain seated while eating.", "Requires Level 5",
  "Use: Teaches you how to cook Tough Jerky.", "Sell Price: 5c" }
-- the tooltip data as the client hands it for a recipe (types: ItemName 22, NestedBlock 19, ItemSpellTriggerOnUse 44,
-- UsageRequirement 43, ItemSpellTriggerLearn 38, SellPrice 11)
local function recipeData()
  return { id = 9000, type = 0, lines = {
    { type = 22, lineIndex = 1 }, { type = 19, lineIndex = 1, tooltipID = 117, tooltipType = 0 },
    { type = 22, lineIndex = 2 }, { type = 44, lineIndex = 3, spellID = 1 }, { type = 43, lineIndex = 4 },
    { type = 38, lineIndex = 5, spellID = 2 }, { type = 11, lineIndex = 6 } } }
end

describe("UI/Tooltip on a recipe's tooltip", function()
  local WFJ, tt, records

  local function show(link, lines, data)
    tt.item = { name = link:match("%[(.-)%]"), link = link }
    tt.spell = nil
    tt:writeLines(lines)
    tt.primaryInfo = data and { tooltipData = data } or nil
    tt.shown = true
    Stub.fireTooltipSet(tt, "Item")
  end

  local function text(i) return _G["GameTooltipTextLeft" .. i]:GetText() end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    _G.Enum.TooltipDataLineType = { ItemName = 22, NestedBlock = 19, ItemSpellTriggerLearn = 38,
      ItemSpellTriggerOnUse = 44, UsageRequirement = 43, SellPrice = 11 }
    WFJ = H.loadChunks(FILES)
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Settings.load(nil, 1, {})
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      marker = function(n) return WFJ.Settings.get("marker." .. n) end,
      align = WFJ.Align.check,
    }))
    records = {}
    WFJ.Collector.record = function(kind, id, field, raw)
      records[#records + 1] = { kind, id, field, raw }
      return "recorded"
    end
    WFJ.Tooltip.init()
    tt = _G.GameTooltip
  end)

  after_each(function()
    _G.Enum = nil
    Stub.keys.alt = false
  end)

  for _, case in ipairs({
    { "the link names the crafted item (a chat link)", "|Hitem:117::|h[Tough Jerky]|h" },
    { "the link names the recipe (a bag slot)", "|Hitem:9000::|h[Recipe: Tough Jerky]|h" },
  }) do
    it("the crafted item's lines get its Japanese and the Teaches line the recipe's: " .. case[1], function()
      show(case[2], LINES, recipeData())
      assert.are.equal(JERKY_JA, text(3))
      assert.are.equal(RECIPE_JA, text(5))
      assert.are.equal("Recipe: Tough Jerky", text(1))
      assert.are.same({ "item", 117, "description", LINES[3] }, records[1])
      assert.are.same({ "item", 9000, "description", LINES[5] }, records[2])
    end)
  end

  it("a crafted item whose run would reach the Teaches line stops before it", function()
    local lines = { "Recipe: Tough Jerky", "Tough Jerky",
      "Use: Restores 61 health over 18 sec. Must remain seated while eating.",
      "Use: Teaches you how to cook Tough Jerky.", "Sell Price: 5c" }
    local data = recipeData()
    data.lines = { { type = 22, lineIndex = 1 }, { type = 19, lineIndex = 1, tooltipID = 117, tooltipType = 0 },
      { type = 22, lineIndex = 2 }, { type = 44, lineIndex = 3 }, { type = 38, lineIndex = 4 },
      { type = 11, lineIndex = 5 } }
    show("|Hitem:117::|h[Tough Jerky]|h", lines, data)
    assert.are.equal(JERKY_JA, text(3))
    assert.are.equal(RECIPE_JA, text(4))
  end)

  it("a recipe whose Teaches line comes before the crafted item's block is read as one item", function()
    local lines = { "Recipe: Tough Jerky", "Use: Teaches you how to cook Tough Jerky.", "Tough Jerky",
      "Use: Restores 61 health over 18 sec. Must remain seated while eating.", "Sell Price: 5c" }
    local data = recipeData()
    data.lines = { { type = 22, lineIndex = 1 }, { type = 38, lineIndex = 2 },
      { type = 19, lineIndex = 3, tooltipID = 117, tooltipType = 0 }, { type = 22, lineIndex = 3 },
      { type = 44, lineIndex = 4 }, { type = 11, lineIndex = 5 } }
    show("|Hitem:117::|h[Tough Jerky]|h", lines, data)
    assert.is_nil(WFJ.Tooltip.recipeOf(tt, #lines))
    assert.are.equal(1, #records) -- one run under the link's item, no separate Teaches record
    assert.are.equal(117, records[1][2])
  end)

  it("without tooltip data, or without a nested item, the tooltip is one item as before", function()
    show("|Hitem:117::|h[Tough Jerky]|h", { "Tough Jerky",
      "Use: Restores 61 health over 18 sec. Must remain seated while eating.", "Sell Price: 5c" })
    assert.are.equal(JERKY_JA, text(2))
    local plain = { id = 117, lines = { { type = 22, lineIndex = 1 }, { type = 44, lineIndex = 2 } } }
    show("|Hitem:117::|h[Tough Jerky]|h", { "Tough Jerky",
      "Use: Restores 61 health over 18 sec. Must remain seated while eating.", "Sell Price: 5c" }, plain)
    assert.are.equal(JERKY_JA, text(2))
  end)

  it("the reveal key shows the recipe's English again", function()
    show("|Hitem:117::|h[Tough Jerky]|h", LINES, recipeData())
    assert.are.equal(RECIPE_JA, text(5))
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(LINES[3], text(3))
    assert.are.equal(LINES[5], text(5))
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal(RECIPE_JA, text(5))
  end)
end)
