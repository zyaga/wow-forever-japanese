-- UI/BossBanner.lua over a BossBanner replayed from camelot
-- blizzard_framexml/bossbannertoast.xml (:139–225) and .lua (:73–112 loot rows, :229–243 BossBanner_Play). The
-- boss's, the item's and the looter's names stay English.
local Stub = require("tests.lua.spec.wow_stub")
local R = require("tests.lua.spec.stub_retail")

local UI = {
  BOSS_YOU_DEFEATED = { "You Defeated", "撃破" }, BOSS_KILL_SUBTITLE = { "has been defeated", "を倒した" },
  BOSS_BANNER_LOOT_SET = { "Set: %s", "セット: %s" },
}
local GLOBALS = { "BossBanner", "BossBanner_ConfigureLootFrame" }

local function build()
  local banner = CreateFrame("Frame", "BossBanner")
  R.tree(banner, { Title = "", SubTitle = _G.BOSS_KILL_SUBTITLE })
  -- BossBanner_Play (lua:229–243): the title, then Show
  function banner.play(self, name, praise)
    self.Title.text = praise and _G.BOSS_YOU_DEFEATED or name
    self:Hide()
    self:Show()
  end
  function banner.Hide(self) self.shown = false end
  _G.BossBanner_ConfigureLootFrame = function(lootFrame, data)
    lootFrame.ItemName.text = data.item
    lootFrame.SetName.text = data.set and string.format(_G.BOSS_BANNER_LOOT_SET, data.set) or ""
    lootFrame.PlayerName.text = data.player
  end
  return banner
end

local function lootRow()
  local row = CreateFrame("Frame")
  R.tree(row, { ItemName = "", SetName = "", PlayerName = "" })
  return row
end

R.suite(getfenv(1), {
  title = "the boss-defeated banner on Forever", module = "BossBanner", file = "UI/BossBanner.lua",
  root = "BossBanner", globals = GLOBALS, ui = UI, build = build,
  args = { BOSS_BANNER_LOOT_SET = { [1] = "text" } },
  cases = {
    { "the subtitle and the praise title are Japanese; Alt shows English", function(frame, WFJ)
      frame:play("Ragnaros")
      assert.are.equal("を倒した", frame.SubTitle:GetText())
      frame:play(nil, true)
      assert.are.equal("撃破", frame.Title:GetText())
      R.alt(WFJ, true)
      assert.are.equal("You Defeated", frame.Title:GetText())
      R.alt(WFJ, false)
    end },
    { "a loot row's set line is Japanese around the set's English name", function()
      local row = lootRow()
      _G.BossBanner_ConfigureLootFrame(row, { item = "Onslaught Girdle", set = "Battlegear of Wrath", player = "Tank" })
      assert.are.equal("セット: Battlegear of Wrath", row.SetName:GetText())
      assert.are.equal("Onslaught Girdle", row.ItemName:GetText())
    end },
  },
  name = function(frame, WFJ)
    frame:play("Onyxia")
    assert.are.equal("Onyxia", frame.Title:GetText())
    assert.is_true(R.unrecorded(WFJ, frame.Title))
    local row = lootRow()
    _G.BossBanner_ConfigureLootFrame(row, { item = "Set: Gold", player = "has been defeated" })
    assert.are.equal("has been defeated", row.PlayerName:GetText())
    assert.is_true(R.unrecorded(WFJ, row.PlayerName))
    assert.is_true(R.unrecorded(WFJ, row.ItemName))
  end,
  wrong = function(frame)
    frame.SubTitle = Stub
    _G.BossBanner_ConfigureLootFrame = "x"
    return function(f)
      f:play(nil, true)
      assert.are.equal("撃破", f.Title:GetText())
    end
  end,
})
