-- Core/UIStrings: the h1-gated index over the shipped UI strings, template match and fill.
local H = require("tests.lua.spec.helpers")

local function ns()
  H.coreStub()
  local t = {}
  H.loadChunk("Core/Const.lua", "WoWForeverJapanese", t)
  H.loadPure("Core/Normalize.lua", "WoWForeverJapanese", t)
  H.loadPure("Core/Hash.lua", "WoWForeverJapanese", t)
  H.loadPure("Core/UIStringKeys.lua", "WoWForeverJapanese", t)
  H.loadPure("Core/UIStrings.lua", "WoWForeverJapanese", t)
  return t
end

-- The client's English (what the globals hold) and the shipped rows (Japanese + h1 of the drafted-against English).
local EN = {
  ACCEPT = "Accept", SPEED = "Speed", SELL_PRICE = "Sell Price", SPELL_REAGENTS = "Reagents: ", RANK = "Rank",
  INVTYPE_CLOAK = "Back", SPELL_SCHOOL2_CAP = "Fire", FACTION_STANDING_LABEL6 = "Honored", INVTYPE_BAG = "Bag",
  ITEM_MIN_LEVEL = "Requires Level %d", ITEM_REQ_SKILL = "Requires %s", ITEM_MIN_SKILL = "Requires %s (%d)",
  ITEM_REQ_REPUTATION = "Requires %s - %s", ITEM_MOD_STAMINA = "%c%d Stamina",
  ITEM_RESIST_SINGLE = "%c%d %s Resistance", DAMAGE_TEMPLATE = "%s - %s Damage", SINGLE_DAMAGE_TEMPLATE = "%s Damage",
  DURABILITY_TEMPLATE = "Durability %d / %d", SPELL_CAST_TIME_SEC = "%.3g sec cast", DPS_TEMPLATE =
  "(%s damage per second)", CONTAINER_SLOTS = "%d Slot %s", ["ItemSubClass:2:0"] = "Axe", ["ItemSubClass:2:1"] = "Axe",
  TOOLTIP_TALENT_NEXT_RANK = "Next rank:", ARMOR_TEMPLATE = "%s Armor", ITEM_WRITTEN_BY = "Written by %s",
  SPELL_SCHOOL5_CAP = "Shadow", INVTYPE_CHEST = "Chest", ["ItemSubClass:4:7"] = "Libram",
}
local JA = {
  ACCEPT = "受注", SPEED = "速度", SELL_PRICE = "売値", SPELL_REAGENTS = "触媒: ", RANK = "ランク", INVTYPE_CLOAK = "背中",
  SPELL_SCHOOL2_CAP = "炎", FACTION_STANDING_LABEL6 = "尊敬", INVTYPE_BAG = "バッグ",
  ITEM_MIN_LEVEL = "必要レベル %d", ITEM_REQ_SKILL = "必要: %s", ITEM_MIN_SKILL = "必要: %s (%d)",
  ITEM_REQ_REPUTATION = "必要: %s - %s", ITEM_MOD_STAMINA = "スタミナ %c%d", ITEM_RESIST_SINGLE = "%3$s耐性 %1$c%2$d",
  DAMAGE_TEMPLATE = "%s - %s ダメージ", SINGLE_DAMAGE_TEMPLATE = "%s ダメージ", DURABILITY_TEMPLATE = "耐久度 %d / %d",
  SPELL_CAST_TIME_SEC = "詠唱 %.3g秒", DPS_TEMPLATE = "(秒間ダメージ %s)", CONTAINER_SLOTS = "%dスロットの%s",
  ["ItemSubClass:2:0"] = "斧", ["ItemSubClass:2:1"] = "斧", TOOLTIP_TALENT_NEXT_RANK = "次のランク:",
  ARMOR_TEMPLATE = "アーマー %s", ITEM_WRITTEN_BY = "作者: %s", SPELL_SCHOOL5_CAP = "暗黒", INVTYPE_CHEST = "胴",
  ["ItemSubClass:4:7"] = "リブラム",
}

local function build(t, english, rows)
  local function h1(text) return (t.Hash.h32x2(t.Normalize.v1(text))) end
  if not rows then
    rows = {}
    for k, ja in pairs(JA) do rows[k] = { ja, h1(EN[k]), "." } end
  end
  return t.UIStrings.build({ rows = rows, english = function(k) return (english or EN)[k] end, hash = h1 })
end

local function translate(index, text)
  local key, args = index:match(text)
  if not key then return nil end
  return index:fill(JA[key], args), key
end

describe("Core/UIStrings", function()
  it("loads under a std-lib-only environment (pure)", function()
    assert.is_function(ns().UIStrings.build)
  end)

  it("indexes a row only when the live English hash equals the shipped h1", function()
    local t = ns()
    local live = {}
    for k, v in pairs(EN) do live[k] = v end
    live.ACCEPT = "Accept Quest" -- the client's English is not what the Japanese was drafted from
    live.SPEED = nil -- the client has no such string: a missing global is unresolved, never fingerprinted
    live.ITEM_MIN_LEVEL = nil
    live["ItemSubClass:2:0"], live["ItemSubClass:2:1"] = nil, nil -- no string by design: fingerprinted
    local index = build(t, live)
    local c = index.counts
    assert.are.equal(29, c.shipped)
    assert.are.equal(1, c.mismatched)
    assert.are.equal(2, c.unresolved)
    assert.are.equal(2, c.hashed)
    assert.are.equal(24, c.indexed)
    assert.are.same({ "ACCEPT" }, index.problems.mismatched)
    assert.are.same({ "ITEM_MIN_LEVEL", "SPEED" }, index.problems.unresolved)
    assert.is_nil(index:match("Speed"))
    assert.are.equal("斧", JA[(index:match("Axe"))])
    assert.are_not.equal("ITEM_MIN_LEVEL", (index:match("Requires Level 10")))
    assert.is_nil(index:match("Accept"))
    assert.is_nil(index:match("Accept Quest"))
  end)

  it("keys that share one English: same Japanese indexes once, different Japanese is ambiguous", function()
    local t = ns()
    local index = build(t)
    assert.are.equal("ItemSubClass:2:0", (index:match("Axe"))) -- two keys, one Japanese → one entry
    local function h1(text) return (t.Hash.h32x2(t.Normalize.v1(text))) end
    local rows = { A = { "速度", h1("Speed"), "." }, B = { "スピード", h1("Speed"), "." } }
    local amb = t.UIStrings.build({ rows = rows, english = function() return "Speed" end, hash = h1 })
    assert.are.equal(2, amb.counts.ambiguous)
    assert.are.equal(0, amb.counts.indexed)
    assert.is_nil(amb:match("Speed"))
  end)

  it("a word the client has no string for is matched by the live line's fingerprint (in-game 2026-09-14)", function()
    local t = ns()
    local function h1(text) return (t.Hash.h32x2(t.Normalize.v1(text))) end
    local rows = {
      ["ItemSubClass:2:10"] = { "杖", h1("Staff"), "." }, -- the API says "Staves"; the tooltip line says "Staff"
      ["ItemSubClass:2:0"] = { "斧", h1("Axe"), "." }, ["ItemSubClass:2:1"] = { "斧", h1("Axe"), "." },
      NO_GLOBAL_TEMPLATE = { "必要 %d", h1("Needs %d"), "." }, -- a template cannot be matched without its English
      SPEED = { "速度", h1("Speed"), "." },
    }
    local index = t.UIStrings.build({ rows = rows, hash = h1, english = function(k)
      if k == "SPEED" then return "Speed" end
      return nil
    end })
    local c = index.counts
    assert.are.equal(1, c.indexed)
    assert.are.equal(3, c.hashed)
    assert.are.equal(1, c.unresolved)
    assert.are.same({ "NO_GLOBAL_TEMPLATE" }, index.problems.unresolved)
    assert.are.equal("ItemSubClass:2:10", (index:match("Staff")))
    assert.are.equal("斧", rows[(index:match("Axe"))][1])
    assert.is_nil(index:match("Staves"))
    assert.are.equal("速度", rows[(index:match("Speed"))][1])
    -- a fingerprint row whose English an English entry already answers with other Japanese is ambiguous
    rows["ItemSubClass:9:9"] = { "スピード", h1("Speed"), "." }
    local amb = t.UIStrings.build({ rows = rows, hash = h1, english = function(k)
      if k == "SPEED" then return "Speed" end
      return nil
    end })
    assert.are.same({ "ItemSubClass:9:9" }, amb.problems.ambiguous)
    assert.are.equal("速度", rows[(amb:match("Speed"))][1])
  end)

  it("never needs stored English: a row is { ja, h1, status }", function()
    local index = build(ns())
    for _, row in pairs(index.rows) do
      assert.are.equal(3, #row)
      assert.is_number(row[2])
    end
  end)

  it("matches exact strings and every template shape, filling values verbatim", function()
    local index = build(ns())
    assert.are.equal("受注", (translate(index, "Accept")))
    assert.are.equal("背中", (translate(index, "Back")))
    assert.are.equal("必要レベル 60", (translate(index, "Requires Level 60")))
    assert.are.equal("スタミナ +12", (translate(index, "+12 Stamina")))
    assert.are.equal("スタミナ -3", (translate(index, "-3 Stamina")))
    assert.are.equal("耐久度 55 / 100", (translate(index, "Durability 55 / 100")))
    assert.are.equal("詠唱 2.5秒", (translate(index, "2.5 sec cast")))
    assert.are.equal("(秒間ダメージ 1,234.5)", (translate(index, "(1,234.5 damage per second)")))
    assert.are.equal("12 - 23 ダメージ", (translate(index, "12 - 23 Damage"))) -- the two-arg template wins
    assert.are.equal("7 ダメージ", (translate(index, "7 Damage")))
    assert.are.equal("必要: Tailoring (150)", (translate(index, "Requires Tailoring (150)"))) -- profession stays
  end)

  it("puts positional arguments where the Japanese wants them and translates a capture that is an entry",
    function()
      local index = build(ns())
      assert.are.equal("炎耐性 +10", (translate(index, "+10 Fire Resistance")))
      assert.are.equal("暗黒耐性 +5", (translate(index, "+5 Shadow Resistance")))
      assert.is_nil(index:match("+5 Arcane Resistance")) -- a school word that is not an entry: not this template
      assert.are.equal("必要: Stormwind - 尊敬", (translate(index, "Requires Stormwind - Honored")))
      assert.are.equal("16スロットのバッグ", (translate(index, "16 Slot Bag")))
    end)

  it("prefers the most specific template (most literal text)", function()
    local index = build(ns())
    local _, key = translate(index, "Requires Level 10")
    assert.are.equal("ITEM_MIN_LEVEL", key) -- not ITEM_REQ_SKILL with %s = "Level 10"
    _, key = translate(index, "Requires Tailoring (150)")
    assert.are.equal("ITEM_MIN_SKILL", key)
  end)

  it("is anchored: a line that only contains a template's text is not a match", function()
    local index = build(ns())
    assert.is_nil(index:match("Equip: Increases your Stamina by 5. Requires Level 10 to use."))
    assert.is_nil(index:match("Accepted"))
    assert.is_nil(index:match(""))
    assert.is_nil(index:match(nil))
  end)

  it("labels: 'entry: rest', a prefix entry, and 'entry number'", function()
    local index = build(ns())
    assert.are.equal("売値: 1|TInterface\\MoneyFrame\\UI-GoldIcon:0|t", (translate(index,
      "Sell Price: 1|TInterface\\MoneyFrame\\UI-GoldIcon:0|t")))
    assert.are.equal("触媒: Linen Cloth", (translate(index, "Reagents: Linen Cloth")))
    assert.are.equal("速度 2.60", (translate(index, "Speed 2.60")))
    assert.are.equal("ランク 3", (translate(index, "Rank 3")))
    assert.are.equal("次のランク:", (translate(index, "Next rank:")))
    assert.is_nil(index:match("Speed of Light")) -- not a number after the entry
  end)

  it("memoises match results per text, hits and misses, and resets at the limit", function()
    local index = build(ns())
    local key1, args1 = index:match("Requires Level 60")
    local key2, args2 = index:match("Requires Level 60")
    assert.are.equal(key1, key2)
    assert.are.equal(args1, args2) -- the same table: served from the memo
    assert.is_nil(index:match("Tough Jerky"))
    assert.is_nil(index:match("Tough Jerky"))
    assert.is_false(index.memo["Tough Jerky"][1])
    for i = 1, 600 do index:match("line " .. i) end
    assert.is_true(index.memoCount <= 512)
  end)

  it("a %s is a number unless the key says otherwise: names and prose never fill a template",
    function()
      local index = build(ns())
      assert.are.equal("アーマー 45", (translate(index, "45 Armor")))
      assert.is_nil(index:match("  Blackened Defias Armor")) -- an item-set piece line
      assert.is_nil(index:match("Runic Leather Armor")) -- a recipe's created item
      assert.is_nil(index:match("Libram: Cleanse")) -- a name, not a "<Libram>: rest" label
      assert.is_nil(index:match("Chest 2")) -- only SPEED / RANK take a trailing number
      assert.is_nil(index:match("Requires a shield. Bashes the target, stunning it for 2 sec."))
      assert.are.equal("必要: Leatherworking (125)", (translate(index, "Requires Leatherworking (125)")))
    end)

  it("a school word must be a dictionary word: random-suffix spell-power lines are not damage lines",
    function()
      local t = ns()
      local function h1(x) return (t.Hash.h32x2(t.Normalize.v1(x))) end
      local en = { PLUS_SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL = "+%s %s Damage", SPELL_SCHOOL2_CAP = "Fire",
        CONTAINER_SLOTS = "%d Slot %s", INVTYPE_BAG = "Bag" }
      local ja = { PLUS_SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL = "%2$sダメージ +%1$s", SPELL_SCHOOL2_CAP = "炎",
        CONTAINER_SLOTS = "%dスロットの%s", INVTYPE_BAG = "バッグ" }
      local rows = {}
      for k, v in pairs(ja) do rows[k] = { v, h1(en[k]), "." } end
      local index = t.UIStrings.build({ rows = rows, hash = h1, english = function(k) return en[k] end })
      local function tr(x)
        local key, args = index:match(x)
        return key and index:fill(ja[key], args)
      end
      assert.are.equal("炎ダメージ +7", tr("+7 Fire Damage"))
      assert.is_nil(index:match("+3 Fire Spell Damage"))
      assert.is_nil(index:match("+5 Spell Damage"))
      assert.are.equal("16スロットのバッグ", tr("16 Slot Bag"))
      assert.are.equal("16スロットのSoul Bag", tr("16 Slot Soul Bag")) -- a bag type not in the dictionary: verbatim
    end)

  it("only word arguments are translated: a name that equals a dictionary word stays English", function()
    local index = build(ns())
    assert.are.equal("作者: Shadow", (translate(index, "Written by Shadow"))) -- a player named Shadow
    assert.are.equal("暗黒耐性 +7", (translate(index, "+7 Shadow Resistance"))) -- the school word
    assert.are.equal("必要: Chest", (translate(index, "Requires Chest"))) -- text argument, verbatim
  end)

  it("fill fails closed when the Japanese asks for an argument the line did not supply", function()
    local index = build(ns())
    assert.is_nil(index:fill("%s と %2$s", { "a" }))
    assert.are.equal("100% 確実", index:fill("100%% 確実", {}))
  end)

  it("parse follows format(): plain, positional, precision, literal percent", function()
    local P = ns().UIStrings.parse
    local parts, n = P("%c%d Stamina")
    assert.are.equal(2, n)
    assert.are.same({ arg = 1, conv = "c", flags = "" }, parts[1])
    parts, n = P("%3$s耐性 %1$c%2$d")
    assert.are.equal(3, n)
    assert.are.equal(3, parts[1].arg)
    parts = P("%.3g sec")
    assert.are.equal(".3", parts[1].flags)
    parts, n = P("50%% off")
    assert.are.equal(0, n)
    assert.are.equal("50% off", parts[1].lit)
  end)

  it("a lone space flag running into a word is prose, not a specifier", function()
    local P = ns().UIStrings.parse
    local parts, n = P("above 100% is for SSAA")
    assert.are.equal(0, n)
    assert.are.equal("above 100% is for SSAA", parts[1].lit)
    parts, n = P("% d left")
    assert.are.equal(1, n)
    assert.are.equal(" ", parts[1].flags)
  end)
end)

-- One template is compiled per distinct English, under whichever of its keys sorts first, so
-- every key of such a group must declare the same argument kinds; otherwise adding a key silently re-captures the
-- line for the others. `PVP_LEAVE_BUTTON_TIME`, `KEY_BINDING_NAME_AND_KEY` and `SETTINGS_SUBCATEGORY_FMT` all hold
-- "%s (%s)"; the PvP countdown regressed to English when the two new keys declared narrower kinds.
describe("keys that share one English declare one set of argument kinds", function()
  local WFJ
  setup(function() WFJ = ns() end)

  it("the PvP countdown still matches with the two new keys in the same group", function()
    local t = ns()
    local function h1(text) return (t.Hash.h32x2(t.Normalize.v1(text))) end
    local en = { PVP_LEAVE_BUTTON_TIME = "%s (%s)", KEY_BINDING_NAME_AND_KEY = "%s (%s)",
      SETTINGS_SUBCATEGORY_FMT = "%s (%s)", PVP_MATCH_LEAVE_BUTTON = "Leave Match" }
    local rows = {
      PVP_LEAVE_BUTTON_TIME = { "%s（%s）", h1(en.PVP_LEAVE_BUTTON_TIME), "." },
      KEY_BINDING_NAME_AND_KEY = { "%s（%s）", h1(en.KEY_BINDING_NAME_AND_KEY), "." },
      SETTINGS_SUBCATEGORY_FMT = { "%s（%s）", h1(en.SETTINGS_SUBCATEGORY_FMT), "." },
      PVP_MATCH_LEAVE_BUTTON = { "試合を退出", h1(en.PVP_MATCH_LEAVE_BUTTON), "." },
    }
    local index = t.UIStrings.build({ rows = rows, hash = h1, english = function(k) return en[k] end })
    -- the button word is an `entry` (PVP_MATCH_LEAVE_BUTTON), the countdown is kept as the client wrote it
    local key, args = index:matchOnly("Leave Match (30)", { "PVP_MATCH_LEAVE_BUTTON", "PVP_LEAVE_BUTTON_TIME" })
    assert.is_truthy(key)
    assert.are.equal("試合を退出（30）", index:fill(rows[key][1], args))
  end)

  it("the three \"%s (%s)\" keys agree, so the PvP countdown still matches", function()
    local A = WFJ.UIStrings.ARGS
    for _, key in ipairs({ "PVP_LEAVE_BUTTON_TIME", "KEY_BINDING_NAME_AND_KEY", "SETTINGS_SUBCATEGORY_FMT" }) do
      assert.are.equal("entry", A[key][1], key)
      assert.are.equal("text", A[key][2], key)
    end
  end)
end)
