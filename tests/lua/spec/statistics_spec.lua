-- ADR-042: the character window's Statistics tab on Forever (UI/Statistics.lua, surface "statistics") over a
-- StatisticsFrame replayed from camelot blizzard_statistics (statisticsframe.lua:70–91, 196–199, 235–240, 287–296):
-- a top-level header row writes `.Name` with a category name (the AchievementCategory family only); an entry or a
-- sub-header writes `.Content.Name`: a sub-category's name when the node's data says isCategory, else a statistic's
-- name, the title of its achievement row (the achievement families only). Values and every other text stay English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Achievement.lua" -- the families' `only` sets (Achievement.categoryOnly / textOnly)
FILES[#FILES + 1] = "UI/Statistics.lua"

local UI = {
  ["AchievementCategory:130"] = { "Character", "キャラクター" },
  ["AchievementCategory:141"] = { "Combat", "戦闘" },
  ["AchievementTitle:60"] = { "Total deaths", "死亡回数" },
  ACHIEVEMENT_SUMMARY_CATEGORY = { "Summary", "概要" },
  CLOSE = { "Close", "閉じる" }, -- a dictionary word a statistic may happen to be called
}

describe("the Statistics tab on Forever", function()
  local WFJ, SS, box

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end
  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do if rec.fs == widget then return false end end
    end
    return true
  end
  local function node(data) return { GetData = function() return data end } end

  -- StatisticsHeaderMixin:Initialize writes `.Name` (lua:196–199)
  local function header(name)
    local row = CreateFrame("Button")
    row.Name = Stub.fontString("")
    box:initFrame(row, node({ id = 1, name = name }), function(r) r.Name.text = name end)
    return row
  end
  -- StatisticsEntryMixin / StatisticsSubHeaderMixin:Initialize write `.Content.Name` (lua:235–240, 287–296)
  local function entry(name, isCategory, row)
    row = row or CreateFrame("Button")
    row.Content = row.Content or { Name = Stub.fontString(""), Value = Stub.fontString("") }
    box:initFrame(row, node({ id = 2, isCategory = isCategory }), function(r)
      r.Content.Name.text = name
      r.Content.Value.text = isCategory and "" or "12"
    end)
    return row
  end

  local function install()
    local frame = CreateFrame("Frame", "StatisticsFrame")
    box = Stub.scrollBox()
    frame.ScrollBox = box
    return frame
  end

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.StatisticsFrame = nil
  end)

  describe("loaded at login", function()
    before_each(function()
      load()
      install()
      WFJ.Labels.forbidNames(WFJ.Statistics.NEVER_TOUCH)
      assert.is_true(WFJ.Statistics.init())
    end)

    it("a header row's category name is Japanese; Alt shows English; a name no row has stays", function()
      local character, other = header("Character"), header("Travel")
      assert.are.equal("キャラクター", character.Name:GetText())
      assert.are.equal("Travel", other.Name:GetText())
      assert.is_true(unrecorded(other.Name))
      alt(true)
      assert.are.equal("Character", character.Name:GetText())
      alt(false)
      assert.are.equal("キャラクター", character.Name:GetText())
    end)

    it("an entry's statistic name is an achievement title, a sub-header's a category; the value stays", function()
      local stat = entry("Total deaths", false)
      local sub = entry("Combat", true)
      assert.are.equal("死亡回数", stat.Content.Name:GetText())
      assert.are.equal("12", stat.Content.Value:GetText())
      assert.is_true(unrecorded(stat.Content.Value))
      assert.are.equal("戦闘", sub.Content.Name:GetText())
      alt(true)
      assert.are.equal("Total deaths", stat.Content.Name:GetText())
      alt(false)
    end)

    it("each kind only matches its own family; a dictionary word and a name no row has stay English", function()
      assert.are.equal("Combat", entry("Combat", false).Content.Name:GetText()) -- a category as a statistic
      assert.are.equal("Total deaths", entry("Total deaths", true).Content.Name:GetText()) -- a title as a category
      assert.are.equal("Total deaths", header("Total deaths").Name:GetText())
      assert.are.equal("Close", entry("Close", false).Content.Name:GetText())
      assert.are.equal("Highest 2v2 rating", entry("Highest 2v2 rating", false).Content.Name:GetText())
    end)

    it("a pooled row reused for another statistic: the record follows the widget", function()
      local row = entry("Total deaths", false)
      entry("Highest 2v2 rating", false, row)
      assert.are.equal("Highest 2v2 rating", row.Content.Name:GetText())
      assert.is_true(unrecorded(row.Content.Name))
      entry("Combat", true, row)
      assert.are.equal("戦闘", row.Content.Name:GetText())
    end)

    it("the frame's OnHide restores the English", function()
      local row = header("Character")
      _G.StatisticsFrame:Show()
      _G.StatisticsFrame:Hide()
      assert.are.equal("Character", row.Name:GetText())
      assert.are.equal(0, SS.count("statistics"))
    end)

    it("hooks install once", function()
      assert.is_false(WFJ.Statistics.init())
      assert.are.equal(1, #box.initCallbacks)
    end)

    it("rows of the wrong shape degrade to English with no error", function()
      assert.has_no.errors(function()
        WFJ.Statistics.onRow(WFJ.Statistics, "moved")
        WFJ.Statistics.onRow(WFJ.Statistics, { Name = 7 }, node({}))
        WFJ.Statistics.onRow({ Content = { Name = "x" } }, { GetData = "x" })
        WFJ.Statistics.onRow({ Content = {} })
      end)
    end)
  end)

  it("rows built before the addon loaded are walked once at init", function()
    load()
    install()
    local row = CreateFrame("Button")
    row.Name = Stub.fontString("Character")
    box:initFrame(row, node({ id = 1 }))
    assert.is_true(WFJ.Statistics.init())
    assert.are.equal("キャラクター", row.Name:GetText())
  end)

  it("no StatisticsFrame, or a moved ScrollBox: init is false and nothing is hooked", function()
    load()
    assert.has_no.errors(function() assert.is_false(WFJ.Statistics.init()) end)
    load()
    install().ScrollBox = "moved"
    assert.has_no.errors(function() assert.is_false(WFJ.Statistics.init()) end)
  end)
end)
