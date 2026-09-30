-- UI/InstanceDifficulty.lua over the banner the
-- camelot minimap creates (blizzard_minimap/mainline/minimap.xml:442) with the tooltips of
-- blizzard_framexml/camelot/instancedifficultyoverrides.lua:9–22 and instancedifficulty.lua:218–247.
local R = require("tests.lua.spec.stub_retail")

local UI = {
  LFG_TYPE_DUNGEON = { "Dungeon", "ダンジョン" }, LFG_TYPE_RAID = { "Raid", "レイド" },
  DUNGEON_DIFFICULTY_5PLAYER = { "5 Player", "5人" }, RAID_DIFFICULTY_40PLAYER = { "40 Player", "40人" },
  GUILD_GROUP = { "Guild Group", "ギルドグループ" },
  DUNGEON_DIFFICULTY_BANNER_TOOLTIP = { "%s Difficulty", "難易度: %s" }, PLAYER_DIFFICULTY1 = { "Normal", "ノーマル" },
  DUNGEON_DIFFICULTY_BANNER_TOOLTIP_PLAYER_COUNT = { "%d/%d Players", "%d/%d人" },
  GUILD_ACHIEVEMENTS_ELIGIBLE = { "At least %1$d out of %2$d players in your group are members of %3$s. Guild "
    .. "achievements can be earned.", "グループの%2$d人中%1$d人以上が%3$sのメンバーです。ギルドアチーブメントを獲得できます。" },
}
local GLOBALS = { "MinimapCluster" }

local function build()
  local cluster = CreateFrame("Frame", "MinimapCluster")
  R.tree(cluster, { ["InstanceDifficulty.Guild"] = { frame = true } })
  return cluster
end

R.suite(getfenv(1), {
  title = "the instance difficulty tooltip on Forever", module = "InstanceDifficulty",
  file = "UI/InstanceDifficulty.lua", root = "MinimapCluster", globals = GLOBALS, ui = UI, build = build,
  args = { GUILD_ACHIEVEMENTS_ELIGIBLE = { [3] = "text" } },
  cases = {
    { "the camelot banner tooltip is Japanese; Alt shows English", function(frame, WFJ)
      R.tooltip(frame.InstanceDifficulty, { "Raid", "40 Player" })
      assert.are.equal("レイド", _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("40人", _G.GameTooltipTextLeft2:GetText())
      R.alt(WFJ, true)
      assert.are.equal("Raid", _G.GameTooltipTextLeft1:GetText())
      R.alt(WFJ, false)
    end },
    { "the guild-group banner tooltip is Japanese", function(frame)
      R.tooltip(frame.InstanceDifficulty.Guild, { "Normal Difficulty", "4/5 Players", "", "Guild Group" })
      assert.are.equal("難易度: ノーマル", _G.GameTooltipTextLeft1:GetText()) -- the difficulty a dictionary word
      assert.are.equal("4/5人", _G.GameTooltipTextLeft2:GetText())
      assert.are.equal("ギルドグループ", _G.GameTooltipTextLeft4:GetText())
      R.tooltip(frame.InstanceDifficulty.Guild, { "Mythic Keystone Difficulty" }) -- no entry: the name kept
      assert.are.equal("難易度: Mythic Keystone", _G.GameTooltipTextLeft1:GetText())
      R.tooltip(frame.InstanceDifficulty, { "Normal Difficulty" }) -- the banner itself never takes the guild title
      assert.are.equal("Normal Difficulty", _G.GameTooltipTextLeft1:GetText())
    end },
  },
  name = function(frame)
    R.tooltip(frame.InstanceDifficulty.Guild, { "Guild Group", -- the client's format with a guild called "Raid"
      "At least 3 out of 5 players in your group are members of Raid. Guild achievements can be earned." })
    assert.are.equal("グループの5人中3人以上がRaidのメンバーです。ギルドアチーブメントを獲得できます。",
      _G.GameTooltipTextLeft2:GetText())
    R.tooltip(frame.InstanceDifficulty.Guild, { "Raid" }) -- not a key of the guild tooltip
    assert.are.equal("Raid", _G.GameTooltipTextLeft1:GetText())
  end,
  wrong = function(frame)
    frame.InstanceDifficulty.Guild = "x"
    return function(f)
      R.tooltip(f.InstanceDifficulty, { "Dungeon", "5 Player" })
      assert.are.equal("ダンジョン", _G.GameTooltipTextLeft1:GetText())
    end
  end,
})
