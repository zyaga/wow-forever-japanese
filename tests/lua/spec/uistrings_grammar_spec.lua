-- Core/UIStrings: plural grammar, the whitelisted label forms, restricted matching,
-- text captures on name-carrying templates, the tightened "Requires %s", durations inside cooldown lines, and
-- enchantment stat lines as fingerprint rows.
local H = require("tests.lua.spec.helpers")

describe("Core/UIStrings additions", function()
  local UIS, index, rows, english
  local labelsBefore

  local function h1(text) -- a stand-in 32-bit fingerprint: the index only compares it with itself
    local n = 0
    for i = 1, #text do n = (n * 31 + text:byte(i)) % 4294967296 end
    return n
  end

  local UI = {
    DAYS_ABBR = { "%d |4Day:Days;", "%d日" },
    FIVE = { "%d |4a:b; %d |4c:d; %d |4e:f; %d |4g:h; %d |4i:j;", "%d %d %d %d %d" }, -- past the 4-group cap
    SPELL_STAT1_NAME = { "Strength", "筋力" },
    CHARACTER_BUTTON = { "Character Info", "キャラクター情報" },
    ACCEPT = { "Accept", "受注" },
    PLAYER_LEVEL = { "Level %d %s %s", "レベル%d %s %s" },
    WARRIOR_WORD = { "Warrior", "戦士" },
    ITEM_MIN_LEVEL = { "Requires Level %d", "必要レベル %d" },
    ITEM_MIN_SKILL = { "Requires %s (%d)", "必要: %s (%d)" },
    ITEM_REQ_SKILL = { "Requires %s", "必要: %s" },
    ITEM_COOLDOWN_TOTAL = { "(%s Cooldown)", "(クールダウン %s)" },
    ITEM_COOLDOWN_TIME = { "Cooldown remaining: %s", "残りクールダウン: %s" },
    INT_SPELL_DURATION_SEC = { "%d sec", "%d秒" },
    INT_SPELL_DURATION_MIN = { "%d min", "%d分" },
    INT_SPELL_DURATION_HOURS = { "%d |4hour:hrs;", "%d時間" },
    SPELL_DURATION_MIN = { "%.2f min", "%.2f分" },
    LASTONLINE_MINUTES = { "%d |4minute:minutes;", "%d分" },
    SPELL_TIME_REMAINING_SEC = { "%d |4second:seconds; remaining", "残り%d秒" },
    ITEM_SPELL_TRIGGER_ONEQUIP = { "Equip:", "装備時:" },
    ITEM_MOD_SPELL_POWER = { "Increases spell power by %s.", "呪文パワーが%s上昇。" },
    ["SpellItemEnchantment:900"] = { "+3 Fire Spell Damage", "炎呪文ダメージ +3" },
    ["SpellItemEnchantment:901"] = { "+3 Fire Spell Damage", "炎呪文ダメージ +3" },
    NEWBIE_TOOLTIP_XPBAR = { "The amount of experience you have earned.", "獲得した経験値の量です。" },
    EXHAUST_TOOLTIP1 = { "|cffffd200%s|r\n|cffffffff%d%% of normal experience|r",
      "|cffffd200%s|r\n|cffffffff通常の%d%%|r" },
    REQUIRES_LABEL = { "Requires:", "必要:" }, TRAINER_REQ_LEVEL = { "Level |cffffffff%d|r", "レベル |cffffffff%d|r" },
    TRAINER_REQ_SKILL_RANK = { "%s (|cffffffff%d|r)", "%s (|cffffffff%d|r)" },
  }

  before_each(function()
    local ns = {}
    H.loadPure("Core/UIStringKeys.lua", "WoWForeverJapanese", ns)
    H.loadPure("Core/UIStrings.lua", "WoWForeverJapanese", ns)
    UIS = ns.UIStrings
    labelsBefore = UIS.LABELS.ACCEPT
    rows, english = {}, {}
    for key, pair in pairs(UI) do
      rows[key] = { pair[2], h1(pair[1]), "." }
      if not key:find(":") then english[key] = pair[1] end
    end
    index = UIS.build({ rows = rows, hash = h1, english = function(key) return english[key] end })
  end)

  after_each(function() UIS.LABELS.ACCEPT = labelsBefore end)

  it("matches a plural template in its singular, plural and raw forms, and fills the Japanese", function()
    for _, text in ipairs({ "1 Day", "3 Days", "3 |4Day:Days;" }) do
      local key, args = index:match(text)
      assert.are.equal("DAYS_ABBR", key, text)
      assert.are.equal(text:match("^%d+") .. "日", index:fill(rows.DAYS_ABBR[1], args))
    end
    assert.is_nil(index:match("3 Dayz"))
  end)

  it("counts a template with more plural groups than the matcher takes as unsupported, never indexed", function()
    assert.are.equal(1, index.counts.unsupported)
    assert.are.same({ "FIVE" }, index.problems.unsupported)
    assert.is_nil(index:match("1 a 2 c 3 e 4 g 5 i"))
  end)

  it("bareColon, wrapped and binding forms reach only whitelisted keys", function()
    local key, args = index:match("Strength:")
    assert.are.equal("SPELL_STAT1_NAME", key)
    assert.are.equal("筋力:", index:fill(rows.SPELL_STAT1_NAME[1], args))

    key, args = index:match("|cff20ff203 Days |r")
    assert.are.equal("DAYS_ABBR", key)
    assert.are.equal("|cff20ff203日 |r", index:fill(rows.DAYS_ABBR[1], args))

    key, args = index:match("Character Info |cffffd200(C)|r")
    assert.are.equal("CHARACTER_BUTTON", key)
    assert.are.equal("キャラクター情報 |cffffd200(C)|r", index:fill(rows.CHARACTER_BUTTON[1], args))

    assert.is_nil(index:match("Accept:")) -- ACCEPT has no bareColon form
    assert.is_nil(index:match("|cffffffffAccept|r")) -- nor wrapped
    assert.is_nil(index:match("Accept |cffffd200(A)|r")) -- nor binding
    assert.is_nil(index:match("|cff20ff20Unknown words|r"))
    UIS.LABELS.ACCEPT = { "wrapped", "bareColon" } -- a list of forms
    local fresh = UIS.build({ rows = rows, hash = h1, english = function(k) return english[k] end })
    assert.are.equal("ACCEPT", (fresh:match("|cffffffffAccept|r")))
    assert.are.equal("ACCEPT", (fresh:match("Accept:")))
  end)

  it("matchOnly ignores a key outside its set; text captures stay verbatim and in order", function()
    assert.are.equal("ACCEPT", (index:matchOnly("Accept", { "ACCEPT" })))
    assert.is_nil(index:matchOnly("Accept", { DECLINE = true }))
    local key, args = index:match("Level 10 Night Elf Warrior")
    assert.are.equal("PLAYER_LEVEL", key)
    -- "Warrior" is a dictionary word, but a text capture is a name: never translated
    assert.are.equal("レベル10 Night Elf Warrior", index:fill(rows.PLAYER_LEVEL[1], args))
  end)

  it("ITEM_REQ_SKILL takes a skill or an equipment list, never a level or a ranked skill", function()
    assert.are.equal("ITEM_REQ_SKILL", (index:match("Requires Herbalism")))
    assert.are.equal("ITEM_REQ_SKILL", (index:match("Requires Bows, Crossbows, Guns")))
    assert.are.equal("ITEM_REQ_SKILL", (index:match("Requires Two-Handed Maces")))
    assert.are.equal("ITEM_MIN_LEVEL", (index:match("Requires Level 40")))
    assert.are.equal("ITEM_MIN_SKILL", (index:match("Requires Engineering (225)")))
    assert.is_nil(index:match("Requires 3 things: now"))
  end)

  it("a cooldown's duration is shown in Japanese when it is one or two duration entries", function()
    local function show(text)
      local key, args = index:match(text)
      return key and index:fill(rows[key][1], args)
    end
    assert.are.equal("(クールダウン 30秒)", show("(30 sec Cooldown)"))
    assert.are.equal("(クールダウン 2.50分)", show("(2.50 min Cooldown)"))
    assert.are.equal("残りクールダウン: 1時間30分", show("Cooldown remaining: 1 hour 30 min"))
    assert.are.equal("残りクールダウン: 2 fortnights", show("Cooldown remaining: 2 fortnights"))
  end)

  it("a spell-only duration takes the forms a spell's $d prints, never the friends list's", function()
    assert.are.equal("30分", index:duration("30 minutes"))  -- a friends-list "last online" duration
    assert.is_nil(index:duration("30 minutes", true))         -- written by the English in a tooltip: not a $d
    assert.are.equal("30秒", index:duration("30 sec", true))
  end)

  it("a buff tooltip's time-remaining line, singular and plural", function()
    local function show(text)
      local key, args = index:match(text)
      return key and index:fill(rows[key][1], args)
    end
    assert.are.equal("残り12秒", show("12 seconds remaining"))
    assert.are.equal("残り1秒", show("1 second remaining"))
  end)

  it("enchantment stat lines are fingerprint rows; ids sharing English share Japanese", function()
    assert.are.equal(2, index.counts.hashed)
    local key = index:match("+3 Fire Spell Damage")
    assert.is_truthy(key == "SpellItemEnchantment:900" or key == "SpellItemEnchantment:901")
    assert.are.equal("炎呪文ダメージ +3", rows[key][1])
  end)

  it("the binding suffix is taken in any colour code case (the client generates it)", function()
    local key, args = index:match("Character Info |cFFFFD200(Escape)|r")
    assert.are.equal("CHARACTER_BUTTON", key)
    assert.are.equal("キャラクター情報 |cFFFFD200(Escape)|r", index:fill(rows.CHARACTER_BUTTON[1], args))
  end)

  it("the paragraphs form fills every part joined by a blank line, and only when every part matches", function()
    local ok = "The amount of experience you have earned.\n\n|cffffd200Rested|r\n|cffffffff200% of normal experience|r"
    local key, args = index:match(ok)
    assert.are.equal("NEWBIE_TOOLTIP_XPBAR", key)
    assert.are.equal("獲得した経験値の量です。\n\n|cffffd200Rested|r\n|cffffffff通常の200%|r",
      index:fill(rows.NEWBIE_TOOLTIP_XPBAR[1], args))
    assert.is_nil(index:match("The amount of experience you have earned.\n\nSomething else entirely."))
  end)

  it("a fill that cannot put an argument back fails closed instead of showing an unfilled template", function()
    local _, args = index:match("|cff20ff203 Days |r")
    args.inner = { key = "DAYS_ABBR" } -- the argument went missing
    assert.is_nil(index:fill(rows.DAYS_ABBR[1], args))
  end)

  it("the list form fills every requirement item and keeps an ability name as shown", function()
    local text = "Requires: Level |cffffffff40|r, First Aid (|cffffffff150|r), |cffffffffStrong Bandage|r"
    local key, args = index:match(text)
    assert.are.equal("REQUIRES_LABEL", key)
    assert.are.equal("必要: レベル |cffffffff40|r, First Aid (|cffffffff150|r), |cffffffffStrong Bandage|r",
      index:fill(rows.REQUIRES_LABEL[1], args))
    -- a skill-rank item never swallows the whole line (its argument is a skill, not free text)
    assert.are_not.equal("TRAINER_REQ_SKILL_RANK", (index:match(text)))
  end)

  it("an Equip: run line matches its ITEM_MOD template through the equip form", function()
    local key, args = index:match("Equip: Increases spell power by 12.")
    assert.are.equal("ITEM_MOD_SPELL_POWER", key)
    assert.are.equal("装備時: 呪文パワーが12上昇。", index:fill(rows.ITEM_MOD_SPELL_POWER[1], args))
    assert.is_nil(index:match("Equip: Restores 5 mana per 5 sec.")) -- not a template in the dictionary
    assert.is_nil(index:match("Use: Increases spell power by 12.")) -- only Equip:
  end)
end)
