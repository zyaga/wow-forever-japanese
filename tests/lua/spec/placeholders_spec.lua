local H = require("tests.lua.spec.helpers")

describe("Core/Placeholders.expand", function()
  local P
  local HUNTER = { name = "Reyn", className = "Hunter", classFile = "HUNTER", raceName = "Night Elf",
    raceFile = "NightElf", sex = 2 }

  before_each(function()
    local WFJ = {}
    H.loadPure("Core/Placeholders.lua", "WoWForeverJapanese", WFJ) -- pure: any global access raises
    P = WFJ.Placeholders
  end)

  it("{name} becomes the player's name, every occurrence; missing or empty stays literal", function()
    assert.are.equal("御機嫌よう、Reyn。Reynよ。", (P.expand("御機嫌よう、{name}。{name}よ。", HUNTER)))
    assert.are.equal("御機嫌よう、{name}。", (P.expand("御機嫌よう、{name}。", { name = nil })))
    assert.are.equal("御機嫌よう、{name}。", (P.expand("御機嫌よう、{name}。", { name = "" })))
    assert.are.equal("{name}", (P.expand("{name}", nil)))
  end)

  it("every class file and race file has its katakana form", function()
    local classes = { WARRIOR = "ウォリアー", PALADIN = "パラディン", HUNTER = "ハンター", ROGUE = "ローグ",
      PRIEST = "プリースト", SHAMAN = "シャーマン", MAGE = "メイジ", WARLOCK = "ウォーロック", DRUID = "ドルイド" }
    for file, kana in pairs(classes) do
      assert.are.equal("若き" .. kana .. "よ", (P.expand("若き{class}よ", { classFile = file })), file)
    end
    local races = { Human = "人間", Orc = "オーク", Dwarf = "ドワーフ", NightElf = "ナイトエルフ",
      Scourge = "アンデッド", Tauren = "トーレン", Gnome = "ノーム", Troll = "トロール" }
    for file, kana in pairs(races) do
      assert.are.equal(kana .. "の者", (P.expand("{race}の者", { raceFile = file })), file)
    end
  end)

  it("an unlisted file falls back to the localized name; with neither the token stays literal", function()
    local dk = { classFile = "DEATHKNIGHT", className = "Death Knight" }
    assert.are.equal("若きDeath Knightよ", (P.expand("若き{class}よ", dk)))
    assert.are.equal("Draeneiの者", (P.expand("{race}の者", { raceFile = "Draenei", raceName = "Draenei" })))
    assert.are.equal("若き{class}よ", (P.expand("若き{class}よ", { classFile = "DEATHKNIGHT" })))
    assert.are.equal("{race}の者", (P.expand("{race}の者", {})))
  end)

  it("an ASCII gender pair takes the female form only for UnitSex 3", function()
    assert.are.equal("やあ、lad。", (P.expand("やあ、<lad/lass>。", { sex = 2 })))
    assert.are.equal("やあ、lass。", (P.expand("やあ、<lad/lass>。", { sex = 3 })))
    assert.are.equal("やあ、lad。", (P.expand("やあ、<lad/lass>。", { sex = 1 })))
    assert.are.equal("やあ、lad。", (P.expand("やあ、<lad/lass>。", {})))
    -- an emote and a single <word> are not pairs
    assert.are.equal("<Sirraは手紙の翻訳を始めた……。>", (P.expand("<Sirraは手紙の翻訳を始めた……。>", { sex = 3 })))
    assert.are.equal("<mage>", (P.expand("<mage>", { sex = 3 })))
    -- a non-ASCII pair is not expanded (the pipeline's validate rule blocks it from shipping)
    assert.are.equal("<閣下/ご婦人>", (P.expand("<閣下/ご婦人>", { sex = 3 })))
  end)

  it("an unknown {word} stays literal; distinct tokens are recorded once however often they render", function()
    local text, unknown = P.expand("{foo}と{name}と{Name}", HUNTER)
    assert.are.equal("{foo}とReynと{Name}", text) -- tokens are case-sensitive: {Name} is unknown
    assert.are.equal(2, unknown)
    for _ = 1, 5 do P.expand("{foo}", HUNTER) end -- re-resolves (Alt, refresh) do not inflate the count
    local _, again = P.expand("{bar}", HUNTER)
    assert.are.equal(1, again)
    local n, list = P.unknownTokens()
    assert.are.equal(3, n)
    assert.are.same({ "{Name}", "{bar}", "{foo}" }, list)
  end)

  it("text without tokens comes back unchanged; a known token with no value is not counted", function()
    local text, unknown = P.expand("トークンなし", HUNTER)
    assert.are.equal("トークンなし", text); assert.are.equal(0, unknown)
    local _, n = P.expand("{class}", {})
    assert.are.equal(0, n); assert.are.equal(0, (P.unknownTokens()))
    assert.are.same({ "name", "class", "race" }, P.KNOWN)
    assert.is_false(P.mayHaveTokens("トークンなし")); assert.is_true(P.mayHaveTokens("{name}"))
    assert.is_true(P.mayHaveTokens("<lad/lass>")); assert.is_false(P.mayHaveTokens(nil))
  end)
end)
