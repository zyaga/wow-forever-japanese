-- The world the word status specs share: the pure modules and a small game of words.
local H = require("tests.lua.spec.helpers")

local Env = {}

Env.FILES = { "Core/Data.lua", "Core/Glosses.lua", "Core/Readings.lua", "Core/WordFrequency.lua",
  "Core/WordStatus.lua", "Core/WordScore.lua", "Core/WordMarks.lua", "Core/WordImport.lua" }

-- → WFJ with the modules loaded and the data below
function Env.load(saved)
  local WFJ = {}
  for _, file in ipairs(Env.FILES) do H.loadPure(file, "WoWForeverJapanese", WFJ) end
  WFJ.Placeholders = { CLASS = {}, RACE = {} }
  WFJ.Data.add("gloss", { [1] = "倒す\tたおす\tdefeat", [2] = "敵\tてき\tenemy", [3] = "食べる\tたべる\teat",
    [4] = "青い\tあおい\tblue", [5] = "開く\tあく\topen", [6] = "悪\tあく\tevil", [7] = "だろう\tだろう\tprobably",
    [8] = "増加\tぞうか\tincrease", [9] = "増加する\tぞうかする\tto increase", [10] = "谷\tたに\tvalley" })
  WFJ.Data.add("freqJa", { ["倒す\tたおす"] = "9,1,0,0,0,0", ["敵\tてき"] = "8,0,0,0,0,2",
    ["食べる\tたべる"] = "3,0,0,0,0,0", ["青い\tあおい"] = "2,0,0,0,0,0", ["開く\tあく"] = "2,0,0,0,0,0",
    ["開く\tひらく"] = "1,0,0,0,0,0", ["悪\tあく"] = "1,0,0,0,0,0", ["だろう\tだろう"] = "7,0,0,0,0,0",
    ["増加\tぞうか"] = "0,0,0,0,0,6", ["増加する\tぞうかする"] = "0,0,0,0,0,5", ["谷\tたに"] = "4,0,0,0,0,0" })
  WFJ.Data.add("freqEn", { enemy = "7,0,0,0,0,0", defeat = "4,0,0,0,0,0", valley = "2,0,0,0,0,0",
    you = "5,0,0,0,0,0" })
  WFJ.Data.add("grammar", { ["だろう\tだろう"] = "1" })
  WFJ.Data.add("chatja", { ["倒して"] = "たおして=1", ["倒し"] = "たおし=1", ["敵"] = "てき=2" })
  WFJ.Data.add("reading", {
    ["quest:7"] = { description = "敵=てき=2 倒して=たおして=1 だろう=だろう=7", objectives = "谷=たに=10",
      progress = "敵=てき=2", title = "敵=てき=2" },
    ["gossip:ab"] = { text = "谷=たに=10 敵=てき=2" },
  })
  WFJ.Data.add("english", { ["quest:7"] = { description = "defeat=2 enemy=1" }, ["gossip:ab"] = { text = "valley=1" } })
  WFJ.WordStatus.load(saved)
  return WFJ
end

return Env
