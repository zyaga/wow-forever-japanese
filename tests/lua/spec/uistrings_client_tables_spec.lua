-- ADR-042: the client-table text families in Core/UIStrings. Fingerprint rows keyed by
-- `<Family>:<id>`, synonyms across families and with a global string of the same English, the slotted (emote) rows,
-- and the family-restricted argument kinds (creatureType, holidayDescription).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  ["FactionDescription:69"] = { "The Alliance capital is populated by Night Elves.", "Allianceの首都にはナイトエルフが住む。" },
  ["AchievementTitle:319"] = { "Duels won", "決闘の勝利数" },
  ["AchievementCategory:21"] = { "Player vs. Player", "プレイヤー対プレイヤー" },
  ["CurrencyCategory:2"] = { "Player vs. Player", "プレイヤー対プレイヤー" }, -- same English, same Japanese
  ["QuestSort:1"] = { "Epic", "エピック" },
  ITEM_QUALITY4_DESC = { "Epic", "エピック" }, -- the global string with that English
  ["CreatureType:7"] = { "Humanoid", "人型" },
  ["DispelType:2"] = { "Curse", "呪い" },
  ["SkillCategory:7"] = { "Class Skills", "クラススキル" },
  ["AchievementCategory:125"] = { "Dungeons and Raids", "ダンジョンとレイド" },
  ["QuestSort:22"] = { "Dungeons and Raids", "ダンジョン・レイド" }, -- another family may word it its own way
  ["QuestSort:23"] = { "Dungeons and Raids", "別の訳" }, -- same family, same English, other Japanese: ambiguous
  ["EmoteText:2"] = { "%s waves at you.", "%sがあなたに手を振った。" },
  ["EmoteText:5"] = { "You wave.", "あなたは手を振った。" },
  UNIT_TYPE_LEVEL_TEMPLATE = { "Level %d %s", "レベル%d %s" },
  UNIT_TYPE_PLUS_LEVEL_TEMPLATE = { "Level %d Elite %s", "レベル%d エリート %s" },
  ["HolidayDescription:10"] = { "A time of merriment.", "陽気に過ごす時。" },
  CALENDAR_HOLIDAYFRAME_BEGINSENDS = { "%1$s|n|nBegins: %2$s %3$s|nEnds: %4$s %5$s",
    "%1$s|n|n開始: %2$s %3$s|n終了: %4$s %5$s" },
}

describe("client-table text families in UIStrings", function()
  local WFJ, index
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(H.UI_FILES)
    H.uiSetup(WFJ, UI)
    index = WFJ.UIIndex
  end)
  after_each(function() H.uiTeardown() end)

  it("every family prefix is a fingerprint key; only EmoteText is slotted", function()
    for _, key in ipairs({ "FactionDescription:1", "AchievementTitle:1", "AchievementDescription:1",
      "AchievementReward:1", "AchievementCategory:1", "SkillLineDescription:1", "SkillCategory:1", "EmoteText:1",
      "HolidayDescription:1", "CurrencyDescription:1", "CurrencyCategory:1", "DispelType:1", "CreatureType:1",
      "QuestSort:1" }) do
      assert.is_true(WFJ.UIStrings.isFingerprintKey(key), key)
      assert.are.equal(key:find("^EmoteText:") ~= nil, WFJ.UIStrings.isSlottedKey(key), key)
    end
    assert.is_false(WFJ.UIStrings.isFingerprintKey("FACTION_OTHER"))
  end)

  it("a family row is found only where a widget names its family, never by the open match", function()
    local faction = WFJ.UIStrings.familyKeys(index.rows, "FactionDescription")
    assert.are.equal("FactionDescription:69",
      (index:matchOnly("The Alliance capital is populated by Night Elves.", faction)))
    assert.is_nil(index:match("The Alliance capital is populated by Night Elves."))
    assert.is_nil(index:exactKey("Duels won")) -- also a name somewhere: the open match never turns it Japanese
    assert.is_nil(index:match("Curse"))
    assert.are.equal("DispelType:2", (index:matchOnly("Curse", WFJ.UIStrings.familyKeys(index.rows, "DispelType"))))
    assert.is_nil(index:matchOnly("Duels won", faction)) -- another family's row
    assert.is_true(WFJ.UIStrings.isRestrictedKey("AchievementTitle:1"))
    assert.is_false(WFJ.UIStrings.isRestrictedKey("SpellSubtext:1")) -- the spell-subtext family stays open
  end)

  it("a widget restricted to one family finds a word another family or a global string shares", function()
    local currency = WFJ.UIStrings.familyKeys(index.rows, "CurrencyCategory")
    assert.are.same({ ["CurrencyCategory:2"] = true }, currency)
    assert.is_not_nil(index:matchOnly("Player vs. Player", currency))
    local sort = WFJ.UIStrings.familyKeys(index.rows, "QuestSort")
    assert.is_not_nil(index:matchOnly("Epic", sort)) -- answered by ITEM_QUALITY4_DESC, QuestSort:1 its synonym
    assert.is_nil(index:matchOnly("Epic", { ["CreatureType:7"] = true }))
  end)

  it("one English with two Japanese in one family is ambiguous; another family keeps its own Japanese", function()
    assert.is_nil(index:match("Dungeons and Raids"))
    local amb = {}
    for _, k in ipairs(index.problems.ambiguous) do amb[k] = true end
    assert.is_true(amb["QuestSort:22"] and amb["QuestSort:23"])
    assert.is_nil(amb["AchievementCategory:125"])
    assert.is_nil(index:matchOnly("Dungeons and Raids", WFJ.UIStrings.familyKeys(index.rows, "QuestSort")))
    assert.are.equal("AchievementCategory:125", (index:matchOnly("Dungeons and Raids",
      WFJ.UIStrings.familyKeys(index.rows, "AchievementCategory"))))
  end)

  it("a slotted row is not a plain fingerprint: its English with the name filled in is matched by slots", function()
    assert.is_nil(index:match("Bob waves at you."))
    local key, spans = index:matchSlots("Bob waves at you.", { "Bob" })
    assert.are.equal("EmoteText:2", key)
    assert.are.same({ { 1, 3 } }, spans)
    assert.are.equal("EmoteText:5", (index:matchSlots("You wave.", {})))
    assert.is_nil(index:matchSlots("Bob dances.", { "Bob" }))
    assert.is_nil(index:matchSlots("", { "Bob" }))
  end)

  it("a known name matched only as a whole word, and a chat flag before it goes with the name", function()
    local key, spans = index:matchSlots("<Away>Bob waves at you.", { "Bob" })
    assert.are.equal("EmoteText:2", key)
    assert.are.same({ { 1, 9 } }, spans)
    assert.is_nil((index:matchSlots("Bobby waves at me.", { "Bob" })))
  end)

  it("creatureType: a CreatureType row's Japanese in the level line, anything else as written", function()
    local key, args = index:match("Level 10 Humanoid")
    assert.are.equal("UNIT_TYPE_LEVEL_TEMPLATE", key)
    assert.are.equal("レベル10 人型", index:fill(index.rows[key][1], args))
    key, args = index:match("Level 12 Elite Humanoid")
    assert.are.equal("レベル12 エリート 人型", index:fill(index.rows[key][1], args))
    key, args = index:match("Level 10 Wolf") -- a pet family: no row, kept
    assert.are.equal("レベル10 Wolf", index:fill(index.rows[key][1], args))
    key, args = index:match("Level 60 Curse") -- another family's word is never taken for a creature type
    assert.are.equal("レベル60 Curse", index:fill(index.rows[key][1], args))
  end)

  it("holidayDescription: the holiday line takes the description's Japanese, else keeps the English", function()
    local only = { "CALENDAR_HOLIDAYFRAME_BEGINSENDS" }
    local line = "A time of merriment.|n|nBegins: Monday 1:00|nEnds: Friday 2:00"
    local key, args = index:matchOnly(line, only)
    assert.are.equal("陽気に過ごす時。|n|n開始: Monday 1:00|n終了: Friday 2:00", index:fill(index.rows[key][1], args))
    line = "Something else.|n|nBegins: Monday 1:00|nEnds: Friday 2:00"
    key, args = index:matchOnly(line, only)
    assert.are.equal("Something else.|n|n開始: Monday 1:00|n終了: Friday 2:00", index:fill(index.rows[key][1], args))
  end)
end)
