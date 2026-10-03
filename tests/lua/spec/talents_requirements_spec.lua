-- The talent tooltip's requirement lines on the Forever (camelot) client: AddConditionsToTooltip adds each shown
-- condition's tooltipText, its tooltipFormat (a SharedString row's English) formatted with spentAmountRequired and the
-- tree's name, red when unmet (blizzard_sharedtalentui/blizzard_sharedtalentutil.lua:679-699, 726-730;
-- blizzard_sharedtalentframe.lua:1914-1972). The pass reads the frame's condInfoCache for the button's conditionIDs.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local PS = require("tests.lua.spec.stub_playerspells")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
for _, f in ipairs({ "UI/SpellBook.lua", "UI/Talents.lua" }) do FILES[#FILES + 1] = f end

local REQUIRE = "Spend %d more |4point:points; in %s |4Talent:Talents;"
local UI = {
  TALENT_BUTTON_TOOLTIP_RANK_FORMAT = { "Rank %s/%s", "ランク %s/%s" },
  TALENT_BUTTON_TOOLTIP_PURCHASE_INSTRUCTIONS = { "Click to learn", "クリックで習得" },
  ["SharedString:911"] = { REQUIRE, "%2$sのタレントにあと%1$dポイント使う" },
  ["SharedString:992"] = { "Tab 1", "タブ1" },
}

describe("talent requirement lines", function()
  local WFJ
  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function line(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
  local function button(conditions, field)
    local display = CreateFrame("Button")
    display.talentFrame = { condInfoCache = conditions }
    local ids = {}
    for id in pairs(conditions) do ids[#ids + 1] = id end
    table.sort(ids)
    display[field or "nodeInfo"] = { conditionIDs = ids }
    return display
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    PS.install()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    PS.loadPlayerSpells()
    WFJ.Talents.init()
  end)
  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
  end)

  it("an unmet requirement is Japanese with the number and the tree's name kept, red kept; Alt shows English",
    function()
      local red = "|cffff2020Spend 5 more points in Beast Mastery Talents|r"
      local display = button({ [7] = { tooltipFormat = REQUIRE, spentAmountRequired = 5 } })
      PS.hoverTalent(display, { "Tab 1", "Rank 0/1", "", red, "Click to learn" })
      assert.are.equal("Tab 1", line(1)) -- the talent's name is never read
      assert.are.equal("ランク 0/1", line(2))
      assert.are.equal("|cffff2020Beast Masteryのタレントにあと5ポイント使う|r", line(4))
      assert.are.equal("クリックで習得", line(5))
      alt(true)
      assert.are.equal(red, line(4))
      alt(false)
      assert.are.equal("|cffff2020Beast Masteryのタレントにあと5ポイント使う|r", line(4))
      _G.GameTooltip:Hide()
      assert.are.equal(red, line(4))
    end)

  it("a met requirement (no colour), singular, from a display's entryInfo", function()
    local display = button({ [3] = { tooltipFormat = REQUIRE } }, "entryInfo")
    PS.hoverTalent(display, { "Mortal Strike", "Spend 1 more point in Arms Talent" })
    assert.are.equal("Armsのタレントにあと1ポイント使う", line(2))
  end)

  it("without the condition's template the line stays English; another line never takes the family", function()
    local text = "Spend 5 more points in Arms Talents"
    PS.hoverTalent(CreateFrame("Button"), { "Mortal Strike", text, "Tab 1" })
    assert.are.equal(text, line(2))
    assert.are.equal("Tab 1", line(3)) -- a plain SharedString row: only as a condition's own text
    -- a condition whose template no row has
    PS.hoverTalent(button({ [1] = { tooltipFormat = "Requires level %d" } }), { "Mortal Strike", "Requires level 10" })
    assert.are.equal("Requires level 10", line(2))
    -- a condition the frame has not cached, or a wrong-typed cache
    local display = button({})
    display.nodeInfo = { conditionIDs = { 9 } }
    PS.hoverTalent(display, { "Mortal Strike", text })
    assert.are.equal(text, line(2))
    display.talentFrame = { condInfoCache = "x" }
    assert.has_no.errors(function() PS.hoverTalent(display, { "Mortal Strike", text }) end)
    assert.are.same({}, WFJ.Talents.conditionFormats(nil))
  end)
end)
