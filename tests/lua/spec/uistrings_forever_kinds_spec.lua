-- The Core/UIStrings entries for the Forever (camelot) surfaces: the `percent` argument kind (the
-- weapon-skill detail pane), `text` captures on the talent tooltip / inspect title templates, and the `binding` form
-- on the mainline-family micro buttons.
local H = require("tests.lua.spec.helpers")

describe("Core/UIStrings additions", function()
  local UIS, index, rows

  local function h1(text)
    local n = 0
    for i = 1, #text do n = (n * 31 + text:byte(i)) % 4294967296 end
    return n
  end

  local UI = {
    WEAPON_SKILL_DETAIL_SAME_LEVEL = {
      "Chance to |cFFFFFFFFHit|r: %s\n\nChance to |cFFFFFFFFCritically Hit|r: %s",
      "|cFFFFFFFF命中|r率: %s\n\n|cFFFFFFFFクリティカル|r率: %s" },
    WEAPON_SKILL_DETAIL_BOSS = {
      "Hit: %s\n\nCrit: %s\n\n|cFFFFFFFFGlancing Blows|r occur %s of the time and deal %s less damage",
      "命中: %s\n\nクリティカル: %s\n\n|cFFFFFFFFかすり|rは%sの確率で発生し、ダメージが%s減少" },
    TALENT_BUTTON_TOOLTIP_RANK_FORMAT = { "Rank %s/%s", "ランク %s/%s" },
    TALENT_BUTTON_TOOLTIP_REPLACED_BY_FORMAT = { "Replaced by %s", "%sに置き換え" },
    TALENTS_INSPECT_FORMAT = { "Talents - %s", "タレント - %s" },
    PROFESSIONS_BUTTON = { "Professions", "専門職" },
    PVP_RANK_NUMBER_AND_TITLE = { "Rank %d - %s", "ランク%d - %s" },
    EXPANSION_SEASON_NAME = { "%s Season %d", "%sシーズン%d" },
    SEASON_ENDS_IN_TIME = { "Season ends in: %s", "シーズン終了まで: %s" },
    D_DAYS = { "%d |4Day:Days;", "%d日" }, D_HOURS = { "%d |4Hour:Hours;", "%d時間" },
    D_MINUTES = { "%d |4Minute:Minutes;", "%d分" },
    MINUTES_ABBR = { "%d |4Min:Min;", "%d分" },
    INT_SPELL_DURATION_MIN = { "%d min", "%d分" },
    QUEST_LOG_COUNT_TEMPLATE = { "Quests: %s%d|r|cffffffff/%d|r", "クエスト: %s%d|r|cffffffff/%d|r" },
    ACCEPT = { "Accept", "受注" },
    UNIT_TYPE_LEVEL_TEMPLATE = { "Level %d %s", "レベル%d %s" },
    COMMUNITY_MEMBER_CHARACTER_INFO_FORMAT = { "Level %d %s %s", "レベル%d %s %s" },
  }

  before_each(function()
    local ns = {}
    H.loadPure("Core/UIStringKeys.lua", "WoWForeverJapanese", ns)
    H.loadPure("Core/UIStrings.lua", "WoWForeverJapanese", ns)
    UIS = ns.UIStrings
    rows = {}
    local english = {}
    for key, pair in pairs(UI) do
      rows[key] = { pair[2], h1(pair[1]), "." }
      english[key] = pair[1]
    end
    index = UIS.build({ rows = rows, hash = h1, english = function(key) return english[key] end })
  end)

  it("a `percent` argument takes a signed or plain percentage and is filled back verbatim", function()
    local text = "Chance to |cFFFFFFFFHit|r: +5.00%\n\nChance to |cFFFFFFFFCritically Hit|r: -0.40%"
    local key, args = index:match(text)
    assert.are.equal("WEAPON_SKILL_DETAIL_SAME_LEVEL", key)
    assert.are.equal("|cFFFFFFFF命中|r率: +5.00%\n\n|cFFFFFFFFクリティカル|r率: -0.40%", index:fill(rows[key][1], args))
    key, args = index:match("Hit: 0.00%\n\nCrit: 5.00%\n\n|cFFFFFFFFGlancing Blows|r occur 40% of the time and deal 35%"
      .. " less damage")
    assert.are.equal("WEAPON_SKILL_DETAIL_BOSS", key)
    assert.are.equal("命中: 0.00%\n\nクリティカル: 5.00%\n\n|cFFFFFFFFかすり|rは40%の確率で発生し、ダメージが35%減少",
      index:fill(rows[key][1], args))
    assert.is_nil(index:match("Hit: Fireball\n\nCrit: 5.00%\n\n|cFFFFFFFFGlancing Blows|r occur 40% of the time and"
      .. " deal 35% less damage")) -- a percent is never a word
  end)

  it("a colour-wrapped talent rank, a replacing spell and an inspected player are `text` captures", function()
    local key, args = index:match("Rank |cffffffff2|r/5")
    assert.are.equal("TALENT_BUTTON_TOOLTIP_RANK_FORMAT", key)
    assert.are.equal("ランク |cffffffff2|r/5", index:fill(rows[key][1], args))
    key, args = index:match("Replaced by Mortal Strike")
    assert.are.equal("Mortal Strikeに置き換え", index:fill(rows[key][1], args))
    key, args = index:match("Talents - Reyn")
    assert.are.equal("タレント - Reyn", index:fill(rows[key][1], args))
  end)

  it("PvP rank: the rank title and an empty expansion part pass through verbatim; the season countdown's"
    .. " unabbreviated units are durations", function()
    local key, args = index:match("Rank 5 - Knight-Lieutenant")
    assert.are.equal("PVP_RANK_NUMBER_AND_TITLE", key)
    assert.are.equal("ランク5 - Knight-Lieutenant", index:fill(rows[key][1], args))
    key, args = index:match(" Season 1") -- the client fills the expansion part with ""
    assert.are.equal("EXPANSION_SEASON_NAME", key)
    assert.are.equal("シーズン1", index:fill(rows[key][1], args))
    key, args = index:match("Season ends in: 3 Days 4 Hours")
    assert.are.equal("SEASON_ENDS_IN_TIME", key)
    assert.are.equal("シーズン終了まで: 3日4時間", index:fill(rows[key][1], args))
    key, args = index:match("Season ends in: 12 Minutes")
    assert.are.equal("シーズン終了まで: 12分", index:fill(rows[key][1], args))
    for _, k in ipairs({ "D_DAYS", "D_HOURS", "D_MINUTES", "D_SECONDS" }) do assert.is_true(index.durations[k], k) end
    -- the spell `$d` renderer's set is unchanged: the unabbreviated units are not what a spell prints
    for _, k in ipairs({ "D_DAYS", "D_HOURS", "D_MINUTES", "D_SECONDS" }) do
      assert.is_nil(index.spellDurations[k], k)
    end
    assert.is_nil(index:duration("12 Minutes", true))
    assert.are.equal("5分", index:duration("5 min", true)) -- an existing spell duration still reads the same
    assert.are.equal("5分", index:duration("5 Min"))
  end)

  it("the quest list count takes a colour code as its first argument and puts it back verbatim", function()
    local text = "Quests: |cffff00005|r|cffffffff/25|r"
    local key, args = index:match(text)
    assert.are.equal("QUEST_LOG_COUNT_TEMPLATE", key)
    assert.are.equal("クエスト: |cffff00005|r|cffffffff/25|r", index:fill(rows[key][1], args))
    key, args = index:match("Quests: |cffffffff12|r|cffffffff/25|r")
    assert.are.equal("クエスト: |cffffffff12|r|cffffffff/25|r", index:fill(rows[key][1], args))
  end)

  it("a Forever micro-button title takes the binding form; a key without it does not", function()
    local key, args = index:match("Professions |cffffd200(K)|r")
    assert.are.equal("PROFESSIONS_BUTTON", key)
    assert.are.equal("専門職 |cffffd200(K)|r", index:fill(rows[key][1], args))
    for _, k in ipairs({ "PROFESSIONS_BUTTON", "PLAYERSPELLS_BUTTON", "SPELLBOOK_BUTTON", "ACHIEVEMENT_BUTTON",
      "LEGACY_BUTTON", "HOUSING_MICRO_BUTTON", "DUNGEONS_BUTTON", "COLLECTIONS", "ENCOUNTER_JOURNAL",
      "ADVENTURE_JOURNAL" }) do
      assert.is_true(UIS.hasForm(k, "binding"), k)
    end
    assert.is_nil(index:match("Accept |cffffd200(A)|r"))
  end)

  -- matchOnly must not stop at the FIRST match: a longer template outside the set would shadow the allowed key, and
  -- a two-word pet family would keep the camelot pet level line English
  it("matchOnly retries the allowed keys' templates when a longer one outside the set matched first", function()
    local line = "Level 60 Wind Serpent"
    assert.are.equal("COMMUNITY_MEMBER_CHARACTER_INFO_FORMAT", (index:match(line)))
    local key, args = index:matchOnly(line, { "UNIT_TYPE_LEVEL_TEMPLATE" })
    assert.are.equal("UNIT_TYPE_LEVEL_TEMPLATE", key)
    assert.are.equal("レベル60 Wind Serpent", index:fill(rows[key][1], args))
    -- the unrestricted match and an allowed first match are unchanged
    assert.are.equal("UNIT_TYPE_LEVEL_TEMPLATE", (index:matchOnly("Level 60 Wolf", { "UNIT_TYPE_LEVEL_TEMPLATE" })))
    assert.are.equal("ACCEPT", (index:matchOnly("Accept", { "ACCEPT" })))
    -- nothing in the set matches: still nil
    assert.is_nil(index:matchOnly(line, { "ACCEPT" }))
  end)
end)
