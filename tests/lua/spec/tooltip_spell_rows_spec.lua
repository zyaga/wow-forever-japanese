-- The rows of a spell's tooltip besides its description, as the client writes them for a profession's spell and a
-- spell with a reagent: the skill and spell name on line 1, the tools and reagents rows, a required weapon type, a
-- first row that is no name, and the lines of the item the spell makes. The English is what the game showed.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
for _, f in ipairs({ "UI/TimeLine.lua", "UI/Tooltip.lua", "UI/TooltipUnit.lua" }) do
  FILES[#FILES + 1] = f
end

local UI = {
  SPELL_REAGENTS = { "Reagents: |n", "触媒: |n" }, SPELL_TOTEMS = { "Tools: ", "道具: " },
  MELEE_RANGE = { "Melee Range", "近接距離" }, SPELL_RANGE = { "%s yd range", "射程 %sヤード" },
  -- one template is compiled for the English these keys share, under the key that sorts first
  ERR_USE_LOCKED_WITH_ITEM_S = { "Requires %s", "必要: %s" }, SPELL_EQUIPPED_ITEM = { "Requires %s", "必要: %s" },
  ["ItemSubClassMask:5"] = { "Ranged Weapon", "遠隔武器" },
  ["ItemSubClassName:2:12"] = { "Two-Handed Exotics", "両手特殊武器" },
  ["ItemSubClassName:9:8"] = { "Enchanting", "エンチャント" }, -- a recipe subclass: a profession's name, no weapon
  ITEM_CLASSES_ALLOWED = { "Classes: %s", "クラス: %s" }, ITEM_MIN_LEVEL = { "Requires Level %d", "必要レベル %d" },
  ITEM_COOLDOWN_TOTAL_MIN = { "(%d Min Cooldown)", "(クールダウン %d分)" },
}

local NAMES = {
  ["Soul Shard"] = "ソウル・シャード", ["Deathweed"] = "デスウィード", ["Crystal Vial"] = "クリスタル・ヴァイアル",
  ["Illusion Dust"] = "イリュージョン・ダスト", ["Runed Copper Rod"] = "ルーンド・カッパー・ロッド",
  ["Earth Totem"] = "アース・トーテム", ["Cache of Mau'ari"] = "キャッシュ・オブ・マウアリ",
  ["Enchanting"] = "エンチャンティング", ["First Aid"] = "ファースト・エイド",
  ["Enchant Boots - Minor Speed"] = "エンチャント・ブーツ・マイナー・スピード",
  ["Anti-Venom"] = "アンチ・ヴェノム", ["Small Venom Sac"] = "スモール・ヴェノム・サック",
  ["Mote of Magic"] = "モート・オブ・マジック", ["Deadly Poison"] = "デッドリー・ポイズン",
  ["Channel Insight"] = "チャネル・インサイト", ["Rogue"] = "ローグ", ["Quick Shot"] = "クイック・ショット",
}

local VENOM_JA = "対象にかかっているレベル$N1までの毒を治癒します。"
local MOTE_JA = "エンチャント用品の商人から入手できます。"
local ITEMS = {
  [6452] = { ja = VENOM_JA, status = "u" },
  [247786] = { ja = MOTE_JA, status = "." },
}

-- spells that make an item and show no name row: their description is row 1 (seen in game)
local CAPSULE_EN = "Creates a Death Capsule, which is used to Feign Death."
local CAPSULE_JA = "Feign Deathに使用するDeath Capsuleを作り出します。"
local POWDER_EN = "Create the reagent for the Blind ability."
local POWDER_JA = "Blind能力用の試薬を作成します。"
local SPEAR_DESC = "The spear must be reforged before it can be used. Reforging the spear requires 40 Mithril Bars, "
  .. "10 Truesilver Bars, 8 Aquamarine, 4 Solid Grinding Stone, and 2 Elemental Fire."
local SPEAR_FLAVOUR = '"Countless entered, few left."'
local SPEAR_JA = "数え切れぬ者が足を踏み入れましたが、出てきた者はわずかでした。"
ITEMS[286645] = { ja = SPEAR_JA, status = "u", values = 0, h1 = 0x333af11b }
local SPELLS = {
  [5395] = { ja = CAPSULE_JA, status = "u" },
  [6510] = { ja = POWDER_JA, status = "u" },
}

describe("UI/Tooltip: the rows of a spell's tooltip", function()
  local WFJ, tt

  local function left(i) return _G["GameTooltipTextLeft" .. i]:GetText() end

  -- a spell's tooltip as the client builds it: `name` is what the frame's GetSpell answers, `data` its tooltip data
  local function show(id, name, lines, data)
    tt.spell = { name = name, id = id }
    tt.item, tt.otherType = nil, nil
    tt.primaryInfo = data and { tooltipData = data } or nil
    tt:writeLines(lines)
    tt.shown = true
    Stub.fireTooltipSet(tt, "Spell")
  end

  local function hold(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    _G.Enum.TooltipDataLineType = { None = 0, SpellName = 13, NestedBlock = 19, ItemName = 22, SpellDescription = 34,
      FlavorText = 37, UsageRequirement = 43, ItemSpellTriggerOnUse = 44 }
    WFJ = H.loadChunks(FILES)
    local function lookup(kind, id)
      if kind == "item.description" then return ITEMS[id] end
      if kind == "spell.description" then return SPELLS[id] end
      return nil
    end
    H.uiSetup(WFJ, UI, { lookup = lookup })
    -- the tooltip reads the entries itself too (a made item's run is narrowed by its Japanese), as in game
    WFJ.Lookup = { get = lookup }
    -- as Main wires it: a game name the client fills into an interface line, in Japanese while names are on
    WFJ.UIStrings.name = function(text)
      if WFJ.State.names then return WFJ.Names.value(text) end
      return nil
    end
    local rows = {}
    for english, ja in pairs(NAMES) do rows[WFJ.Names.key(english)] = ja .. "\t" .. ja end
    WFJ.Data.add("name", rows)
    WFJ.Tooltip.init()
    tt = _G.GameTooltip
  end)

  after_each(function()
    H.uiTeardown()
    WFJ.UIStrings.name = nil
    _G.Enum = nil
    Stub.keys.alt = false
  end)

  describe("the reagents row", function()
    it("shows the label and every item's name in Japanese, a count as written", function()
      show(693, "Create Soulstone", { "Create Soulstone", "3 sec cast", "Reagents: |nSoul Shard" })
      assert.are.equal("触媒: |nソウル・シャード", left(3))
      show(11357, "Deadly Poison III", { "Deadly Poison III", "Reagents: |nDeathweed (5), Crystal Vial" })
      assert.are.equal("触媒: |nデスウィード (5), クリスタル・ヴァイアル", left(2))
      -- an item the character lacks is coloured by the client: the colour stays around its Japanese
      show(11357, "Deadly Poison III",
        { "Deadly Poison III", "Reagents: |n|cffff2020Deathweed (5)|r, Crystal Vial" })
      assert.are.equal("触媒: |n|cffff2020デスウィード (5)|r, クリスタル・ヴァイアル", left(2))
      -- a tooltip with no name row whose reagent is named like the spell
      show(21160, "Soul Shard", { "Reagents: |n|cffff2020Soul Shard|r" })
      assert.are.equal("触媒: |n|cffff2020ソウル・シャード|r", left(1))
      show(693, "Create Soulstone", { "Create Soulstone", "Reagents: |n|cffff2020Soul Shard|r" })
      assert.are.equal("触媒: |n|cffff2020ソウル・シャード|r", left(2))
    end)

    it("with names English the label alone is Japanese", function()
      WFJ.State.names = false
      show(11357, "Deadly Poison III", { "Deadly Poison III", "Reagents: |nDeathweed (5), Crystal Vial" })
      assert.are.equal("触媒: |nDeathweed (5), Crystal Vial", left(2))
    end)

    it("a list with an item the name list has no line for stays whole as written after the label", function()
      show(1232176, "Channel Insight",
        { "Channel Insight", "Reagents: |nIllusion Dust (2), Righteous Orb" })
      assert.are.equal("触媒: |nIllusion Dust (2), Righteous Orb", left(2))
    end)

    it("the reveal key shows the client's English, and the master switch off writes nothing", function()
      show(693, "Create Soulstone", { "Create Soulstone", "Reagents: |nSoul Shard" })
      hold(true)
      assert.are.equal("Reagents: |nSoul Shard", left(2))
      hold(false)
      assert.are.equal("触媒: |nソウル・シャード", left(2))
      WFJ.State.setEnabled(false)
      show(693, "Create Soulstone", { "Create Soulstone", "Reagents: |nSoul Shard" })
      assert.are.equal("Reagents: |nSoul Shard", left(2))
    end)

    it("a line of another addon that only looks like a list is left alone", function()
      show(693, "Create Soulstone", { "Create Soulstone", "Reagents: |nSoul Shard", "Bags: 3", "Inventory" })
      assert.are.equal("Bags: 3", left(3))
      assert.are.equal("Inventory", left(4))
    end)
  end)

  describe("a first row that is not the spell's name", function()
    it("is matched like any other row: a range, a reagents row", function()
      show(1232176, "Channel Insight", { "Melee Range", "Reagents: |nIllusion Dust (2), Soul Shard" })
      assert.are.equal("近接距離", left(1))
      assert.are.equal("触媒: |nイリュージョン・ダスト (2), ソウル・シャード", left(2))
      show(2835, "Deadly Poison", { "Reagents: |nDeathweed, Crystal Vial" })
      assert.are.equal("触媒: |nデスウィード, クリスタル・ヴァイアル", left(1))
    end)

    it("a first row that holds the name is never a dictionary word, and a tooltip with no known name keeps the rule",
      function()
        WFJ.State.names = false
        show(1, "Melee Range", { "Melee Range", "Instant" })
        assert.are.equal("Melee Range", left(1))
        show(1, nil, { "Melee Range", "Instant" })
        assert.are.equal("Melee Range", left(1))
      end)
  end)

  -- A spell that makes an item, shown with no name row: the tooltip data puts the description on row 1 and the
  -- made item's nested block right after it, and that block carries row 1 as its own row too.
  describe("a description on row 1", function()
    local function data(id, item, extra)
      local lines = { { type = 34, lineIndex = 1, leftText = Stub.spellDescriptions[id] },
        { type = 19, lineIndex = 1, tooltipID = item, tooltipType = 0 } }
      for _, l in ipairs(extra or {}) do lines[#lines + 1] = l end
      return { id = id, type = 1, lines = lines }
    end

    before_each(function()
      Stub.spellDescriptions[5395] = CAPSULE_EN
      Stub.spellDescriptions[6510] = POWDER_EN
    end)

    it("the only row: shown in Japanese, the client's English under the reveal key", function()
      show(5395, "Death Capsule", { CAPSULE_EN }, data(5395, 5172))
      assert.are.equal(CAPSULE_JA, left(1))
      hold(true)
      assert.are.equal(CAPSULE_EN, left(1))
      hold(false)
      assert.are.equal(CAPSULE_JA, left(1))
    end)

    it("with the made item's rows after it", function()
      show(6510, "Blinding Powder", { POWDER_EN, "Blinding Powder", "Requires Level 5" },
        data(6510, 5530, { { type = 22, lineIndex = 2 }, { type = 43, lineIndex = 3 } }))
      assert.are.equal(POWDER_JA, left(1))
      assert.are.equal("必要レベル 5", left(3))
    end)

    it("a row 1 the data does not type as the description is not taken for it", function()
      show(6510, "Blinding Powder", { POWDER_EN, "Blinding Powder" },
        { id = 6510, type = 1, lines = { { type = 0, lineIndex = 1 }, { type = 22, lineIndex = 2 } } })
      assert.are.equal(POWDER_EN, left(1))
    end)
  end)

  describe("a profession's spell: the skill and the spell's name on line 1", function()
    local LINE = "Enchanting: Enchant Boots - Minor Speed"

    it("shows both names in Japanese with names on, and the client's English under the reveal key", function()
      show(13890, "Enchant Boots - Minor Speed", { LINE, "Tools: Runed Copper Rod" })
      assert.are.equal("エンチャンティング: エンチャント・ブーツ・マイナー・スピード", left(1))
      hold(true)
      assert.are.equal(LINE, left(1))
      hold(false)
      assert.are.equal("エンチャンティング: エンチャント・ブーツ・マイナー・スピード", left(1))
    end)

    it("stays as written with names English, and when either name has no line", function()
      WFJ.State.names = false
      show(13890, "Enchant Boots - Minor Speed", { LINE })
      assert.are.equal(LINE, left(1))
      WFJ.State.names = true
      show(13637, "Enchant Boots - Lesser Agility", { "Enchanting: Enchant Boots - Lesser Agility" })
      assert.are.equal("Enchanting: Enchant Boots - Lesser Agility", left(1))
      show(13890, "Enchant Boots - Minor Speed", { "Runeforging: Enchant Boots - Minor Speed" })
      assert.are.equal("Runeforging: Enchant Boots - Minor Speed", left(1))
    end)
  end)

  describe("the lines of the item a spell makes", function()
    -- First Aid: Anti-Venom, as the tooltip data names its rows: the made item is a nested block under the reagents
    local LINES = { "First Aid: Anti-Venom", "Reagents: |nSmall Venom Sac", "Anti-Venom", "Requires Level 5",
      "Use: Target is cured of poisons up to level 25. (1 Min Cooldown)" }
    local function data(item)
      return { id = 7934, type = 1, lines = { { type = 13, lineIndex = 1 }, { type = 0, lineIndex = 2 },
        { type = 19, lineIndex = 2, tooltipID = item, tooltipType = 0 }, { type = 22, lineIndex = 3 },
        { type = 43, lineIndex = 4 }, { type = 44, lineIndex = 5 } } }
    end

    it("the use line takes the made item's Japanese, its cooldown tail left out of the line's numbers", function()
      show(7934, "Anti-Venom", LINES, data(6452))
      assert.are.equal("対象にかかっているレベル25までの毒を治癒します。", left(5))
      assert.are.equal("ファースト・エイド: アンチ・ヴェノム", left(1))
      assert.are.equal("アンチ・ヴェノム", left(3))
      assert.are.equal("必要レベル 5", left(4))
      hold(true)
      assert.are.equal(LINES[5], left(5))
      hold(false)
    end)

    it("a recipe headed by what it makes shows the skill and that name", function()
      show(1245320, "Dust to Motes", { "Enchanting: Mote of Magic" })
      assert.are.equal("エンチャンティング: モート・オブ・マジック", left(1))
      WFJ.State.names = false
      show(1245320, "Dust to Motes", { "Enchanting: Mote of Magic" })
      assert.are.equal("Enchanting: Mote of Magic", left(1))
      WFJ.State.names = true
    end)

    it("the flavour text takes the made item's Japanese", function()
      show(1245320, "Dust to Motes", { "Enchanting: Mote of Magic", "Reagents: |nSoul Shard", "Mote of Magic",
        '"Available from enchanting vendors."' },
        { id = 1245320, type = 1, lines = { { type = 13, lineIndex = 1 }, { type = 0, lineIndex = 2 },
          { type = 19, lineIndex = 2, tooltipID = 247786, tooltipType = 0 }, { type = 22, lineIndex = 3 },
          { type = 37, lineIndex = 4 } } })
      assert.are.equal(MOTE_JA, left(4))
    end)

    -- Repair the Atal'ai Spear makes the Reforged Atal'ai Spear, whose flavour line was seen English on row 13.
    -- The rows above it are a reconstruction (the run kept the row's text, not the tooltip data's line kinds).
    local SPEAR = { "Repair the Atal'ai Spear", "Reagents: |nSoul Shard", SPEAR_DESC, "Reforged Atal'ai Spear",
      "Binds when picked up", "Unique", "Two-Hand", "100 - 150 Damage", "(30.0 damage per second)",
      "Durability 100 / 100", "Requires Level 50", "Equip: Improves your chance to hit by 1%.", SPEAR_FLAVOUR }
    local function spearData(block)
      return { id = 1320864, type = 1, lines = { { type = 13, lineIndex = 1 }, { type = 0, lineIndex = 2 },
        { type = 34, lineIndex = 3 }, block, { type = 22, lineIndex = 4 }, { type = 45, lineIndex = 12 },
        { type = 37, lineIndex = 13 } } }
    end

    it("a made item's flavour line takes its Japanese, quotes and all, with an equip line above it", function()
      Stub.spellDescriptions[1320864] = SPEAR_DESC
      show(1320864, "Repair the Atal'ai Spear", SPEAR,
        spearData({ type = 19, lineIndex = 3, tooltipID = 286645, tooltipType = 0 }))
      assert.are.equal(SPEAR_JA, left(13))
      assert.are.equal(SPEAR[12], left(12))
      hold(true)
      assert.are.equal(SPEAR_FLAVOUR, left(13))
      hold(false)
      -- the flavour line right under the item's name, with nothing between
      show(1320864, "Repair the Atal'ai Spear", { SPEAR[1], SPEAR_DESC, SPEAR[4], SPEAR_FLAVOUR },
        { id = 1320864, type = 1, lines = { { type = 13, lineIndex = 1 }, { type = 34, lineIndex = 2 },
          { type = 19, lineIndex = 2, tooltipID = 286645, tooltipType = 0 }, { type = 22, lineIndex = 3 },
          { type = 37, lineIndex = 4 } } })
      assert.are.equal(SPEAR_JA, left(4))
    end)

    it("the made item's flavour line is found past its level line, as the game lays a made item out", function()
      -- the rows and the tooltip data a run recorded for this spell: the item's level line sits between its equip
      -- line and its flavour, and the data lists no line for those last two rows
      local rows = { "Tools: Blacksmith Hammer", "Reagents: |nSoul Shard", SPEAR_DESC, "Reforged Atal'ai Spear",
        "Binds when picked up", "Two-Hand", "132 - 198 Damage", "(43.4 damage per second)", "+19 Strength",
        "+14 Stamina", "Equip: Improves your chance to hit by 1%.", "Requires Level 45", SPEAR_FLAVOUR }
      local recorded = { id = 1320864, type = 1, lines = { { type = 0, lineIndex = 0 }, { type = 0, lineIndex = 1 },
        { type = 0, lineIndex = 2 }, { type = 34, lineIndex = 3 },
        { type = 19, lineIndex = 3, tooltipID = 286645, tooltipType = 0 }, { type = 22, lineIndex = 4 },
        { type = 20, lineIndex = 5 }, { type = 21, lineIndex = 6 }, { type = 0, lineIndex = 7 },
        { type = 0, lineIndex = 8 }, { type = 0, lineIndex = 9 }, { type = 0, lineIndex = 10 },
        { type = 0, lineIndex = 11 } } }
      Stub.spellDescriptions[1320864] = SPEAR_DESC
      show(1320864, "Repair the Atal'ai Spear", rows, recorded)
      assert.are.equal(SPEAR_JA, left(13))
      -- the equip line is not the flavour's: it is never held to the flavour's Japanese or marked for it
      assert.are.equal(rows[11], left(11))
      hold(true)
      assert.are.equal(SPEAR_FLAVOUR, left(13))
      hold(false)
    end)

    it("with the item tooltips area off the made item's lines stay English", function()
      WFJ.State.setArea("items", false)
      show(7934, "Anti-Venom", LINES, data(6452))
      assert.are.equal(LINES[5], left(5))
      WFJ.State.setArea("items", true)
    end)

    it("without a nested item in the tooltip data, or for an item with no Japanese, the English line stays", function()
      show(7934, "Anti-Venom", LINES, nil)
      assert.are.equal(LINES[5], left(5))
      show(7934, "Anti-Venom", LINES, { id = 7934, type = 1, lines = { { type = 13, lineIndex = 1 } } })
      assert.are.equal(LINES[5], left(5))
      show(7934, "Anti-Venom", LINES, data(999999))
      assert.is_truthy(left(5):find(LINES[5], 1, true))
      assert.is_nil(left(5):find("治癒", 1, true))
    end)
  end)

  describe("a template the client printed unfilled", function()
    it("shows its Japanese with the placeholder as the client left it", function()
      show(17233, "Bite", { "Bite", "Focus 35", "%s yd range" })
      assert.are.equal("射程 %sヤード", left(3))
      hold(true)
      assert.are.equal("%s yd range", left(3))
      hold(false)
      show(17233, "Bite", { "Bite", "Focus 35", "5 yd range" }) -- a filled one is matched as ever
      assert.are.equal("射程 5ヤード", left(3))
    end)
  end)

  describe("a value inside a requirement row", function()
    it("a weapon type is a dictionary word, Japanese whatever the names choice", function()
      for _, names in ipairs({ true, false }) do
        WFJ.State.names = names
        show(1516, "Quick Shot", { "Quick Shot", "Requires Ranged Weapon", "Requires Two-Handed Exotics" })
        assert.are.equal("必要: 遠隔武器", left(2))
        assert.are.equal("必要: 両手特殊武器", left(3))
      end
    end)

    it("a tool or a totem is an item's name: Japanese with names on, as written with names English", function()
      local lines = { "Quick Shot", "Tools: Runed Copper Rod", "Tools: Earth Totem", "Requires Cache of Mau'ari" }
      show(1516, "Quick Shot", lines)
      assert.are.equal("道具: ルーンド・カッパー・ロッド", left(2))
      assert.are.equal("道具: アース・トーテム", left(3))
      assert.are.equal("必要: キャッシュ・オブ・マウアリ", left(4))
      WFJ.State.names = false
      show(1516, "Quick Shot", lines)
      assert.are.equal("道具: Runed Copper Rod", left(2))
      assert.are.equal("道具: Earth Totem", left(3))
      assert.are.equal("必要: Cache of Mau'ari", left(4))
    end)

    it("a profession's name is a name, never the recipe subclass word that reads the same", function()
      WFJ.State.names = false
      show(1516, "Quick Shot", { "Quick Shot", "Requires Enchanting" })
      assert.are.equal("必要: Enchanting", left(2))
      WFJ.State.names = true
      show(1516, "Quick Shot", { "Quick Shot", "Requires Enchanting" })
      assert.are.equal("必要: エンチャンティング", left(2))
    end)

    it("a class list shows each class's word with names on", function()
      show(2835, "Deadly Poison", { "Deadly Poison", "Classes: Rogue" })
      assert.are.equal("クラス: ローグ", left(2))
      WFJ.State.names = false
      show(2835, "Deadly Poison", { "Deadly Poison", "Classes: Rogue" })
      assert.are.equal("クラス: Rogue", left(2))
    end)

    it("a value with no Japanese anywhere stays as written", function()
      show(7092, "Maul", { "Maul", "Requires Creature - Bear" })
      assert.are.equal("必要: Creature - Bear", left(2))
    end)
  end)
end)
