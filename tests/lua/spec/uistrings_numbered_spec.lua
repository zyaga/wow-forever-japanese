-- ADR-042: the NUMBERED WidgetText rows (Core/UIStrings index:matchNumbers, every digit run
-- of the live line becomes `#`, the skeleton's fingerprint names the row, its Japanese takes the numbers as `%k$s`),
-- the other restricted families, and the customizationChoice / customizationSource argument kinds.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

-- A NUMBERED row's English here is its SKELETON ("#" for every number run): H.uiSetup hashes the English it is given
-- as the row's h1, and the pipeline's h1 for a WidgetText row is the skeleton's hash (pipeline core/numbered).
local UI = {
  ["WidgetText:4401"] = { "Towers Controlled: #", "制圧した塔: %1$s" },
  ["WidgetText:5120"] = { "Bases: #  Resources: #/#", "資源: %2$s/%3$s  拠点: %1$s" }, -- reordered
  ["ItemSubClassName:2:10"] = { "Staves", "杖" },
  ["CustomizationOption:30"] = { "Hair Style", "髪型" },
  ["CustomizationChoice:12"] = { "Brown", "茶色" },
  ["CustomizationSource:3"] = { "See colors", "色を見る" },
  ["PvpColumn:1"] = { "Flag Captures", "旗の奪取" },
  ["LfgActivity:285"] = { "Custom", "カスタム" },
  ["ItemNameDescription:7"] = { "Green", "緑" },
  ["ItemNameDescription:8"] = { "Blue", "青" }, ["ItemNameDescription:9"] = { "Blue", "ブルー" }, -- ambiguous
  CLOSE = { "Close", "閉じる" }, -- an open global string …
  ["CustomizationChoice:40"] = { "Close", "短髪" }, -- … a choice with the same English, other Japanese
  ["LfgActivity:9"] = { "Close", "近接" }, -- … and a third family's
  CHARACTER_CUSTOMIZATION_CHOICE_TOOLTIP = { "%d: %s", "%d: %s" },
  BARBERSHOP_CUSTOMIZATION_SOURCE_FORMAT = { "Source: %s", "入手方法: %s" },
}

describe("numbered rows and the widget-text families in UIStrings", function()
  local WFJ, index
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(H.UI_FILES)
    H.uiSetup(WFJ, UI)
    index = WFJ.UIIndex
  end)
  after_each(function() H.uiTeardown() end)

  it("every second-round family is a restricted fingerprint key; only WidgetText is numbered", function()
    for _, family in ipairs({ "ItemSubClassName", "CustomizationCategory", "CustomizationOption",
      "CustomizationChoice", "CustomizationSource", "PvpColumn", "PvpColumnTooltip", "LfgCategory",
      "LfgActivityGroup", "LfgActivity", "ItemNameDescription", "WidgetText" }) do
      local key = family .. ":1"
      assert.is_true(WFJ.UIStrings.isFingerprintKey(key), key)
      assert.is_true(WFJ.UIStrings.isRestrictedKey(key), key)
      assert.are.equal(family == "WidgetText", WFJ.UIStrings.isNumberedKey(key), key)
      assert.is_false(WFJ.UIStrings.isSlottedKey(key), key)
    end
    assert.is_false(WFJ.UIStrings.isNumberedKey("EmoteText:1"))
    assert.is_false(WFJ.UIStrings.isNumberedKey(nil))
  end)

  it("matchNumbers: one number → the row and the number; the Japanese takes it", function()
    local key, numbers = index:matchNumbers("Towers Controlled: 3")
    assert.are.equal("WidgetText:4401", key)
    assert.are.same({ "3" }, numbers)
    assert.are.equal("制圧した塔: 3", index:fill(index.rows[key][1], numbers))
    key, numbers = index:matchNumbers("Towers Controlled: 12")
    assert.are.equal("制圧した塔: 12", index:fill(index.rows[key][1], numbers))
  end)

  it("matchNumbers: several numbers in the line's order, placed where the Japanese asks", function()
    local key, numbers = index:matchNumbers("Bases: 2  Resources: 150/1600")
    assert.are.equal("WidgetText:5120", key)
    assert.are.same({ "2", "150", "1600" }, numbers)
    assert.are.equal("資源: 150/1600  拠点: 2", index:fill(index.rows[key][1], numbers))
  end)

  it("matchNumbers: colour codes (their hex digits included) and textures are left out before the numbers", function()
    local key, numbers = index:matchNumbers("Towers Controlled: |cff00ff003|r")
    assert.are.equal("WidgetText:4401", key)
    assert.are.same({ "3" }, numbers)
    key, numbers = index:matchNumbers("|cffffd100Towers Controlled: 4|r")
    assert.are.same({ "4" }, numbers)
    assert.are.equal("WidgetText:4401", key)
    key = index:matchNumbers("|TInterface\\Icons\\INV_Misc_12:0|tTowers Controlled: 5")
    assert.are.equal("WidgetText:4401", key)
  end)

  it("matchNumbers: another line, an empty line or a non-string → nil", function()
    assert.is_nil(index:matchNumbers("Towers Destroyed: 3"))
    assert.is_nil(index:matchNumbers(""))
    assert.is_nil(index:matchNumbers(nil))
    assert.is_nil(index:matchNumbers("Towers Controlled:")) -- the number missing: another skeleton
  end)

  it("no numbered rows shipped → matchNumbers is nil", function()
    H.uiTeardown()
    H.uiSetup(WFJ, { ["CustomizationChoice:12"] = { "Brown", "茶色" } })
    assert.is_nil(WFJ.UIIndex:matchNumbers("Towers Controlled: 3"))
  end)

  it("a numbered row is found only where a widget's set names it, never by the open match", function()
    assert.is_nil(index:match("Towers Controlled: 3"))
    assert.is_nil(index:matchOnly("Towers Controlled: 3", { ["PvpColumn:1"] = true }))
    local widgetText = WFJ.UIStrings.familyKeys(index.rows, "WidgetText")
    local key, numbers = index:matchOnly("Towers Controlled: 3", widgetText)
    assert.are.equal("WidgetText:4401", key)
    assert.are.equal("制圧した塔: 3", index:fill(index.rows[key][1], numbers))
  end)

  it("a restricted family's plain row: only its family's set finds it", function()
    assert.is_nil(index:match("Staves"))
    assert.is_nil(index:exactKey("Staves"))
    assert.are.same({ "ItemSubClassName:2:10" }, index:restrictedKeys("Staves"))
    assert.are.equal("ItemSubClassName:2:10",
      (index:matchOnly("Staves", WFJ.UIStrings.familyKeys(index.rows, "ItemSubClassName"))))
    assert.is_nil(index:matchOnly("Staves", WFJ.UIStrings.familyKeys(index.rows, "LfgActivity")))
    assert.are.same({}, index:restrictedKeys(""))
    assert.are.same({}, index:restrictedKeys(nil))
    assert.are.same({}, index:restrictedKeys("Towers Controlled: 3")) -- a numbered row is not in this index
  end)

  it("a restricted family keeps its own Japanese beside an open global string of the same English", function()
    assert.are.equal("CLOSE", (index:match("Close")))
    local choices = WFJ.UIStrings.familyKeys(index.rows, "CustomizationChoice")
    local key = index:matchOnly("Close", choices)
    assert.are.equal("CustomizationChoice:40", key)
    assert.are.equal("短髪", index.rows[key][1])
    local k, args = index:matchOnly("2: Close", { "CHARACTER_CUSTOMIZATION_CHOICE_TOOLTIP" })
    assert.are.equal("2: 短髪", index:fill(index.rows[k][1], args))
    -- another family with the same English and other Japanese: each widget gets its own family's row
    local restricted = {}
    for _, rk in ipairs(index:restrictedKeys("Close")) do restricted[rk] = true end
    assert.are.same({ ["CustomizationChoice:40"] = true, ["LfgActivity:9"] = true }, restricted)
    assert.are.equal("LfgActivity:9", (index:matchOnly("Close", WFJ.UIStrings.familyKeys(index.rows, "LfgActivity"))))
  end)

  it("one English with two Japanese inside one family is ambiguous and shown by neither", function()
    local amb = {}
    for _, k in ipairs(index.problems.ambiguous) do amb[k] = true end
    assert.is_true(amb["ItemNameDescription:8"] and amb["ItemNameDescription:9"])
    local only = WFJ.UIStrings.familyKeys(index.rows, "ItemNameDescription")
    assert.is_nil(index:matchOnly("Blue", only))
    assert.are.equal("ItemNameDescription:7", (index:matchOnly("Green", only)))
  end)

  it("customizationChoice: '3: Brown' takes the choice's Japanese; an unlisted choice is kept verbatim", function()
    local only = { "CHARACTER_CUSTOMIZATION_CHOICE_TOOLTIP" }
    local key, args = index:matchOnly("3: Brown", only)
    assert.are.equal("CHARACTER_CUSTOMIZATION_CHOICE_TOOLTIP", key)
    assert.are.equal("3: 茶色", index:fill(index.rows[key][1], args))
    key, args = index:matchOnly("4: Midnight Blue", only)
    assert.are.equal("4: Midnight Blue", index:fill(index.rows[key][1], args))
    key, args = index:matchOnly("5: Staves", only) -- another family's word is never taken for a choice
    assert.are.equal("5: Staves", index:fill(index.rows[key][1], args))
  end)

  it("customizationSource: 'Source: See colors' takes the source's Japanese, else as written", function()
    local only = { "BARBERSHOP_CUSTOMIZATION_SOURCE_FORMAT" }
    local key, args = index:matchOnly("Source: See colors", only)
    assert.are.equal("入手方法: 色を見る", index:fill(index.rows[key][1], args))
    key, args = index:matchOnly("Source: A quest", only)
    assert.are.equal("入手方法: A quest", index:fill(index.rows[key][1], args))
  end)
end)
