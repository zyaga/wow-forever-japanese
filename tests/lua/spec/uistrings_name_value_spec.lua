-- A game name the client fills into an interface line ("(Horde Territory)", "Discovered: Goldshire", a looted
-- item's link) shows in its Japanese through the resolver Main gives Core/UIStrings while names are on; a value
-- that is not a name, and every value while names are off, is kept as written.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  FACTION_CONTROLLED_TERRITORY = { "(%s Territory)", "（%s領）" },
  ERR_ZONE_EXPLORED = { "Discovered: %s", "発見: %s" },
  LOOT_ITEM_SELF = { "You receive loot: %s.", "戦利品を受け取りました: %s" },
  ITEM_MIN_SKILL = { "Requires %s (%d)", "必要: %s (%d)" },
  ITEM_REQ_SKILL = { "Requires %s", "必要: %s" },
}
local SKILL_KEYS = { "ITEM_MIN_SKILL", "ITEM_REQ_SKILL" }
-- chat and system lines whose value is a game name
local CHAT = {
  FACTION_STANDING_INCREASED = { "Reputation with %s increased by %d.", "%sとの評判が%d上がった。" },
  SKILL_RANK_UP = { "Your skill in %s has increased to %d.", "%sのスキルが%dに上がった。" },
  ERR_LEARN_SPELL_S = { "You have learned a new spell: %s.", "新しい呪文を覚えた: %s" },
  LOOT_ITEM = { "%s receives loot: %s.", "%sが戦利品を受け取った: %s" },
  COMBATLOG_XPGAIN_FIRSTPERSON = { "%s dies, you gain %d experience.", "%sを倒し、経験値を%d得た。" },
  ERR_QUEST_ADD_KILL_SII = { "%s slain: %d/%d", "%sを倒す: %d/%d" },
}
for key, pair in pairs(CHAT) do UI[key] = pair end
local KEYS = { "FACTION_CONTROLLED_TERRITORY", "ERR_ZONE_EXPLORED", "LOOT_ITEM_SELF" }
local LINK = "|cffffffff|Hitem:2589::::::::1:::::|h[Linen Cloth]|h|r"

describe("names inside interface lines", function()
  local WFJ, index
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(H.UI_FILES)
    H.uiSetup(WFJ, UI)
    index = WFJ.UIIndex
    WFJ.UIStrings.name = function(text)
      local names = { Horde = "ホード", Goldshire = "ゴールドシャイア", Cooking = "クッキング", Bows = "ボウズ",
        Guns = "ガンズ" }
      if text == LINK then return (text:gsub("Linen Cloth", "リネン・クロス")) end
      return names[text]
    end
    WFJ.UIStrings.names = function() return true end
  end)
  after_each(function()
    WFJ.UIStrings.name, WFJ.UIStrings.names = nil, nil
    H.uiTeardown()
  end)

  local function japanese(line)
    local key, args = index:matchOnly(line, KEYS)
    assert.is_not_nil(key, line)
    return index:fill(index.rows[key][1], args)
  end

  it("declares the value of each of these lines as a name", function()
    for _, key in ipairs(KEYS) do
      assert.are.equal("name", WFJ.UIStrings.argKinds(key)[1], key)
    end
  end)

  it("a value that is a name shows in Japanese; any other is kept as written", function()
    assert.are.equal("（ホード領）", japanese("(Horde Territory)"))
    assert.are.equal("発見: ゴールドシャイア", japanese("Discovered: Goldshire"))
    assert.are.equal("発見: Somewhere Unknown", japanese("Discovered: Somewhere Unknown"))
  end)

  it("a link keeps everything but its label", function()
    assert.are.equal("戦利品を受け取りました: |cffffffff|Hitem:2589::::::::1:::::|h[リネン・クロス]|h|r",
      japanese("You receive loot: " .. LINK .. "."))
  end)

  it("a line filled from its own arguments shows the name in Japanese too", function()
    local args = index:formatArgs("ERR_ZONE_EXPLORED", _G.ERR_ZONE_EXPLORED, "Goldshire")
    assert.are.equal("発見: ゴールドシャイア", index:fill(index.rows.ERR_ZONE_EXPLORED[1], args))
  end)

  it("a skill a line requires shows in Japanese, each one of a list by itself", function()
    local function skill(line)
      local key, args = index:matchOnly(line, SKILL_KEYS)
      assert.is_not_nil(key, line)
      return index:fill(index.rows[key][1], args)
    end
    assert.are.equal("必要: クッキング (100)", skill("Requires Cooking (100)"))
    assert.are.equal("必要: クッキング", skill("Requires Cooking"))
    assert.are.equal("必要: ボウズ, Crossbows, ガンズ", skill("Requires Bows, Crossbows, Guns")) -- one has no Japanese
    -- the setting switched to English names: a line seen before is filled again, not remembered
    WFJ.UIStrings.name, WFJ.UIStrings.names = nil, function() return false end
    assert.are.equal("必要: Cooking (100)", skill("Requires Cooking (100)"))
  end)

  it("a chat line's item, spell, skill, faction or creature shows in Japanese; a player's name is kept", function()
    local keys = {}
    for key in pairs(CHAT) do keys[#keys + 1] = key end
    local function chat(line)
      local key, args = index:matchOnly(line, keys)
      assert.is_not_nil(key, line)
      return index:fill(index.rows[key][1], args)
    end
    assert.are.equal("ホードとの評判が25上がった。", chat("Reputation with Horde increased by 25."))
    assert.are.equal("クッキングのスキルが5に上がった。", chat("Your skill in Cooking has increased to 5."))
    assert.are.equal("新しい呪文を覚えた: ガンズ", chat("You have learned a new spell: Guns."))
    assert.are.equal("Horde Guyが戦利品を受け取った: |cffffffff|Hitem:2589::::::::1:::::|h[リネン・クロス]|h|r",
      chat("Horde Guy receives loot: " .. LINK .. "."))
    assert.are.equal("ボウズを倒し、経験値を40得た。", chat("Bows dies, you gain 40 experience."))
    assert.are.equal("ボウズを倒す: 1/8", chat("Bows slain: 1/8"))
    assert.are.equal("Some Boarを倒す: 1/8", chat("Some Boar slain: 1/8"))
  end)

  it("with no resolver the value is kept as written", function()
    WFJ.UIStrings.name = nil
    assert.are.equal("（Horde領）", japanese("(Horde Territory)"))
  end)
end)
