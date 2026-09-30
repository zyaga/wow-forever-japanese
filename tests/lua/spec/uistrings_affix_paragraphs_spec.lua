-- Core/UIStrings index features: the `affix` fill form (objective lines), the last-break `paragraphs` split (the
-- Spirit tooltip + its sitting warning), texture markup kept verbatim, and the trainer filter's wrapped entries.
local H = require("tests.lua.spec.helpers")

describe("Core/UIStrings additions", function()
  local index, rows

  local function h1(text)
    local n = 0
    for i = 1, #text do n = (n * 31 + text:byte(i)) % 4294967296 end
    return n
  end

  local ICON = "|TInterface\\GossipFrame\\AvailableQuestIcon:16:16|t"
  local UI = {
    QUEST_MONSTERS_KILLED = { "%2$d/%3$d %1$s slain", "%1$sを倒す: %2$d/%3$d" },
    DEFAULT_SPIRIT_TOOLTIP = { "Increases |cFFFFFFFFHealth Regeneration|r by %d per 5 sec\n\n|cffBCBCBCHalted|r",
      "|cFFFFFFFF体力回復|rが5秒ごとに%d上昇\n\n|cffBCBCBC停止|r" },
    SPIRIT_STANDING_WARNING = { "|cffBCBCBCHealth Regeneration is increased by 33% while sitting|r",
      "|cffBCBCBC座っている間、体力回復が33%上昇|r" },
    QUEST_LOG_NO_QUESTS = { "No quests|n|nTalk to a " .. ICON .. " above their head.",
      "クエストなし|n|n頭上に" .. ICON .. "があるキャラクターに話しかける。" },
    USED = { "Used", "習得済み" },
    ADDON_LIST_PERFORMANCE_PEAK_CPU = { "Peak CPU: %s", "ピークCPU: %s" },
    QUEST_FACTION_NEEDED_NOPROGRESS = { "%2$s %1$s", "%1$s: %2$s" },
    FACTION_STANDING_LABEL4 = { "Neutral", "中立" }, RETURN_WORD = { "Return", "返送" },
  }

  before_each(function()
    local ns = {}
    H.loadPure("Core/UIStringKeys.lua", "WoWForeverJapanese", ns)
    H.loadPure("Core/UIStrings.lua", "WoWForeverJapanese", ns)
    local english = {}
    rows = {}
    for key, pair in pairs(UI) do
      rows[key] = { pair[2], h1(pair[1]), "." }
      english[key] = pair[1]
    end
    index = ns.UIStrings.build({ rows = rows, hash = h1, english = function(key) return english[key] end })
  end)

  it("the affix form puts verbatim text around the Japanese, and around a filled template", function()
    assert.are.equal("0/1 あ (完了)", index:fill("あ", { form = "affix", before = "0/1 ", after = " (完了)" }))
    local key, args = index:matchOnly("3/10 Kobold Vermin slain", { "QUEST_MONSTERS_KILLED" })
    assert.are.equal("QUEST_MONSTERS_KILLED", key)
    assert.are.equal("Kobold Verminを倒す: 3/10 (完了)",
      index:fill(rows[key][1], { form = "affix", before = "", after = " (完了)", inner = args }))
    assert.is_nil(index:fill("%1$s %4$d", { form = "affix", before = "", after = "", inner = args })) -- fails closed
  end)

  it("a paragraph appended after a template that holds a blank line itself is split at the last one", function()
    local text = "Increases |cFFFFFFFFHealth Regeneration|r by 12 per 5 sec\n\n|cffBCBCBCHalted|r\n\n"
      .. UI.SPIRIT_STANDING_WARNING[1]
    local key, args = index:match(text)
    assert.are.equal("DEFAULT_SPIRIT_TOOLTIP", key)
    assert.are.equal("|cFFFFFFFF体力回復|rが5秒ごとに12上昇\n\n|cffBCBCBC停止|r\n\n" .. UI.SPIRIT_STANDING_WARNING[2],
      index:fill(rows[key][1], args))
    -- the Spirit tooltip alone is still an ordinary template
    assert.are.equal("DEFAULT_SPIRIT_TOOLTIP",
      (index:match("Increases |cFFFFFFFFHealth Regeneration|r by 12 per 5 sec\n\n|cffBCBCBCHalted|r")))
  end)

  it("a string carrying a texture matches as it stands and keeps the texture", function()
    local key = index:match(UI.QUEST_LOG_NO_QUESTS[1])
    assert.are.equal("QUEST_LOG_NO_QUESTS", key)
    assert.is_truthy(rows[key][1]:find(ICON, 1, true))
  end)

  it("the trainer filter's colour-wrapped entry keeps its colour", function()
    local key, args = index:match("|cff808080Used|r")
    assert.are.equal("USED", key)
    assert.are.equal("|cff808080習得済み|r", index:fill(rows[key][1], args))
  end)

  it("an objective template is matched only where a widget asks for it, and a standing is a standing",
    function()
      assert.is_nil(index:match("3/10 Kobold Vermin slain")) -- never by an unrestricted match (tooltips, auras)
      assert.is_nil(index:match("Neutral Darnassus"))
      assert.is_nil(index:matchOnly("Return to Verner", { "QUEST_FACTION_NEEDED_NOPROGRESS" })) -- a quest title
      local key, args = index:matchOnly("Neutral Darnassus", { "QUEST_FACTION_NEEDED_NOPROGRESS" })
      assert.are.equal("QUEST_FACTION_NEEDED_NOPROGRESS", key)
      assert.are.equal("Darnassus: 中立", index:fill(rows[key][1], args))
    end)

  it("the performance tooltip's CPU share keeps its decimal point (in game: \"Peak CPU: 0.04%\")", function()
    local key, args = index:match("Peak CPU: 0.04%")
    assert.are.equal("ADDON_LIST_PERFORMANCE_PEAK_CPU", key)
    assert.are.equal("ピークCPU: 0.04%", index:fill(rows[key][1], args))
  end)
end)
