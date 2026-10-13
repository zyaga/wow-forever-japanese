-- Core/UIStrings over lines with links, plural groups and names: a line holding a link is matched by key with the
-- link kept byte for byte, label included; |4 plural lines in their singular and plural forms; a colour-wrapped
-- name captured as text; the dual-wield comparison's colour hex; the sell price range's colon labels; the loot
-- specialization, talent prerequisite and temporary enchant lines with their name slots.
local H = require("tests.lua.spec.helpers")

describe("Core/UIStrings: links, plurals, colour-wrapped names", function()
  local UIS, index, rows, english

  local function h1(text)
    local n = 0
    for i = 1, #text do n = (n * 31 + text:byte(i)) % 4294967296 end
    return n
  end

  local LEVEL = "|cffFF4E00|Hlevelup:%d:LEVEL_UP_TYPE_CHARACTER|h[Level %d]|h|r"
  local UI = {
    LEVEL_UP = { "Congratulations, you have reached " .. LEVEL .. "!",
      "おめでとうございます。" .. LEVEL .. "に到達しました！" },
    ERR_FRIEND_ONLINE_SS = { "|Hplayer:%s|h[%s]|h has come online.", "|Hplayer:%s|h[%s]|hがオンラインになりました。" },
    LOOT_ROLL_NEED = { "|HlootHistory:%d|h[Loot]|h: %s has selected Need for: %s",
      "|HlootHistory:%d|h[Loot]|h: %sが%sにニードを選択しました" },
    COUNTDOWN_SET = { "|Hplayer:%s|h[%s]|h started a countdown timer.", "|Hplayer:%s|h[%s]|hがカウントダウンを開始しました。" },
    DUEL_TO_THE_DEATH_REQUESTED = { "|Hplayer:%s|h[%s]|h has challenged you to a duel to the death.",
      "|Hplayer:%s|h[%s]|hから死闘の決闘を申し込まれました。" },
    ITEM_COOLDOWN_TIME_DAYS = { "Cooldown remaining: %d |4day:days;", "残りクールダウン: %d日" },
    ITEM_SPELL_CHARGES = { "%d |4Charge:Charges;", "チャージ %d回" },
    ITEM_CREATED_BY = { "|cff00ff00<Made by %s>|r", "|cff00ff00<製作者: %s>|r" },
    ITEM_WRAPPED_BY = { "|cff00ff00<Gift from %s>|r", "|cff00ff00<%sからの贈り物>|r" },
    ITEM_DELTA_DUAL_WIELD_COMPARISON_MAINHAND_DESCRIPTION = { "(With |c%s%s|r equipped in your main-hand)",
      "(メインハンドに|c%s%s|rを装備した場合)" },
    MINIMUM = { "Minimum", "最低" }, MAXIMUM = { "Maximum", "最高" },
    LOOT_SPECIALIZATION_DEFAULT = { "Current Specialization ( %s )", "現在の専門化 ( %s )" },
    TOOLTIP_TALENT_PREREQ = { "Requires %1$d |4point:points; in %2$s", "%2$sに%1$dポイント必要" },
    ITEM_ENCHANT_TIME_LEFT_MIN = { "%s (%d min)", "%s (%d分)" }, ITEM_MISSING = { "%s missing", "%sが不足" },
    ITEM_ENCHANT_TIME_LEFT_DAYS = { "%s (%d |4day:days;)", "%s (%d日)" },
    -- a coloured template whose bare form is another key's English, the coloured one sorting first
    AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT = { "Time Left: |cffffffff%s|r", "残り時間: |cffffffff%s|r" },
    BONUS_OBJECTIVE_TIME_LEFT = { "Time Left: %s", "残り時間：%s" }, AUCTION_TIME_LEFT3 = { "Long", "長い" },
    -- a coloured template the client never prints bare: no bare form, so a player's own text never matches it
    PLAYER_IS_PVP_AFK = { "|cffff64ff%s (Inactive)|r", "|cffff64ff%s (離席中)|r" },
    CONFIRM_XP_LOSS = { "If I resurrect you, you will be afflicted by %s of |cff71d5ff|Hspell:15007|h"
      .. "[Resurrection Sickness]|h|r.",
      "復活させると、%sの|cff71d5ff|Hspell:15007|h[Resurrection Sickness]|h|rにかかります。" },
  }

  before_each(function()
    local ns = {}
    H.loadPure("Core/UIStringKeys.lua", "WoWForeverJapanese", ns)
    H.loadPure("Core/UIStrings.lua", "WoWForeverJapanese", ns)
    UIS = ns.UIStrings
    rows, english = {}, {}
    for key, pair in pairs(UI) do
      rows[key] = { pair[2], h1(pair[1]), "." }
      english[key] = pair[1]
    end
    index = UIS.build({ rows = rows, hash = h1, english = function(key) return english[key] end })
  end)

  local function filled(key, text, only)
    local k, args = index:matchOnly(text, only or { key })
    assert.are.equal(key, k, text)
    args.key = k
    return index:fill(rows[key][1], args), args
  end

  it("a chat line with a link is a chat-family key, matched by key only, the link kept byte for byte", function()
    assert.is_true(UIS.isChatKey("LEVEL_UP"))
    assert.is_true(UIS.isChatKey("COUNTDOWN_SET"))
    local live = "Congratulations, you have reached |cffFF4E00|Hlevelup:5:LEVEL_UP_TYPE_CHARACTER|h[Level 5]|h|r!"
    assert.is_nil(index:match(live)) -- never an unrestricted template
    assert.are.equal("おめでとうございます。|cffFF4E00|Hlevelup:5:LEVEL_UP_TYPE_CHARACTER|h[Level 5]|h|r"
      .. "に到達しました！", filled("LEVEL_UP", live))
    assert.are.equal("|Hplayer:Wind Mami|h[Wind Mami]|hがオンラインになりました。",
      filled("ERR_FRIEND_ONLINE_SS", "|Hplayer:Wind Mami|h[Wind Mami]|h has come online."))
    assert.are.equal("|Hplayer:Reyn-Realm|h[Reyn]|hがカウントダウンを開始しました。",
      filled("COUNTDOWN_SET", "|Hplayer:Reyn-Realm|h[Reyn]|h started a countdown timer."))
    local item = "|cff1eff00|Hitem:2488:0:0:0|h[Worn Shortsword]|h|r"
    assert.are.equal("|HlootHistory:3|h[Loot]|h: Reynが" .. item .. "にニードを選択しました",
      filled("LOOT_ROLL_NEED", "|HlootHistory:3|h[Loot]|h: Reyn has selected Need for: " .. item))
  end)

  it("a dialog line with a player link captures the name twice and keeps the link", function()
    assert.are.equal("|Hplayer:Reyn|h[Reyn]|hから死闘の決闘を申し込まれました。",
      filled("DUEL_TO_THE_DEATH_REQUESTED", "|Hplayer:Reyn|h[Reyn]|h has challenged you to a duel to the death."))
    local text = "If I resurrect you, you will be afflicted by 10 minutes of |cff71d5ff|Hspell:15007|h"
      .. "[Resurrection Sickness]|h|r."
    assert.are.equal("復活させると、10 minutesの|cff71d5ff|Hspell:15007|h[Resurrection Sickness]|h|rにかかります。",
      filled("CONFIRM_XP_LOSS", text))
  end)

  it("a |4 plural line matches its singular and its plural form", function()
    assert.are.equal("残りクールダウン: 1日", filled("ITEM_COOLDOWN_TIME_DAYS", "Cooldown remaining: 1 day"))
    assert.are.equal("残りクールダウン: 3日", filled("ITEM_COOLDOWN_TIME_DAYS", "Cooldown remaining: 3 days"))
    assert.are.equal("チャージ 1回", filled("ITEM_SPELL_CHARGES", "1 Charge"))
    assert.are.equal("チャージ 5回", filled("ITEM_SPELL_CHARGES", "5 Charges"))
    assert.are.equal("Arms に5ポイント必要", (filled("TOOLTIP_TALENT_PREREQ", "Requires 5 points in Arms ")))
  end)

  it("a colour-wrapped name is captured as text and put back as sent", function()
    local key, args = index:match("|cff00ff00<Made by Wind Mami>|r")
    assert.are.equal("ITEM_CREATED_BY", key)
    assert.are.equal("Wind Mami", args[1])
    assert.are.equal("|cff00ff00<製作者: Wind Mami>|r", index:fill(rows.ITEM_CREATED_BY[1], args))
    key, args = index:match("|cff00ff00<Gift from Reyn>|r")
    assert.are.equal("ITEM_WRAPPED_BY", key)
    assert.are.equal("|cff00ff00<Reynからの贈り物>|r", index:fill(rows.ITEM_WRAPPED_BY[1], args))
    assert.is_nil(index:match("|cff00ff00<Made by Wind. Mami>|r")) -- a period is never a name's
  end)

  it("a colour-wrapped template also matches the line printed without its colour codes, asked by key", function()
    local key, args = index:matchOnly("<Made by Wind Mami>", { "ITEM_CREATED_BY" })
    assert.are.equal("ITEM_CREATED_BY", key)
    assert.are.equal("Wind Mami", args[1])
    assert.are.equal("<製作者: Wind Mami>", index:fill(rows.ITEM_CREATED_BY[1], args))
    assert.is_nil(index:matchOnly("<Made by Wind Mami>|r", { "ITEM_CREATED_BY" }))
  end)

  it("the dual-wield comparison captures the colour hex and the weapon's name", function()
    local text = "(With |cffffffffWorn Shortsword|r equipped in your main-hand)"
    local key, args = index:matchOnly(text, { "ITEM_DELTA_DUAL_WIELD_COMPARISON_MAINHAND_DESCRIPTION" })
    assert.are.equal("ITEM_DELTA_DUAL_WIELD_COMPARISON_MAINHAND_DESCRIPTION", key)
    assert.are.same({ "ffffffff", "Worn Shortsword" }, { args[1], args[2] })
    args.key = key
    assert.are.equal("(メインハンドに|cffffffffWorn Shortsword|rを装備した場合)",
      index:fill(rows.ITEM_DELTA_DUAL_WIELD_COMPARISON_MAINHAND_DESCRIPTION[1], args))
  end)

  it("the sell price range's labels take a colon form; the loot spec and enchant lines keep their names", function()
    local key, args = index:match("Minimum: 5c")
    assert.are.equal("MINIMUM", key)
    assert.are.equal("最低: 5c", index:fill(rows.MINIMUM[1], args))
    key, args = index:match("Maximum: 1g 20s")
    assert.are.equal("MAXIMUM", key)
    assert.are.equal("最高: 1g 20s", index:fill(rows.MAXIMUM[1], args))
    assert.are.equal("現在の専門化 ( Fury )", filled("LOOT_SPECIALIZATION_DEFAULT", "Current Specialization ( Fury )"))
    assert.are.equal("Sharpened (5分)", filled("ITEM_ENCHANT_TIME_LEFT_MIN", "Sharpened (5 min)"))
    assert.are.equal("Sharpened (2日)", filled("ITEM_ENCHANT_TIME_LEFT_DAYS", "Sharpened (2 days)"))
  end)

  it("only the keys the client prints bare get a bare form, and it is matched only by key", function()
    assert.is_nil(index:match("Raid night (Inactive)"))
    assert.are.equal("PLAYER_IS_PVP_AFK", (index:match("|cffff64ffBob (Inactive)|r")))
    assert.is_nil(index:match("<Made by Reyn>")) -- a player could type that shape
    assert.are.equal("ITEM_CREATED_BY", (index:matchOnly("<Made by Reyn>", { "ITEM_CREATED_BY" })))
  end)

  it("a free text with a word or two after it is matched only by key, never on any line of its shape", function()
    assert.is_nil(index:match("Talent points missing"))
    assert.is_nil(index:match("Rank 3 (5 min)"))
    assert.are.equal("ITEM_MISSING", (index:matchOnly("Hearthstone missing", { "ITEM_MISSING" })))
  end)

  it("a bare form never takes another key's English nor makes either key ambiguous", function()
    UIS.BARE.AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT = true -- as if the client printed it bare too
    index = UIS.build({ rows = rows, hash = h1, english = function(key) return english[key] end })
    UIS.BARE.AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT = nil
    for _, k in ipairs(index.problems.ambiguous) do
      assert.is_not.equal("AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT", k)
      assert.is_not.equal("BONUS_OBJECTIVE_TIME_LEFT", k)
    end
    local key, args = index:matchOnly("Time Left: |cffffffffLong|r", { "AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT" })
    assert.are.equal("AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT", key)
    args.key = key
    assert.are.equal("残り時間: |cffffffff長い|r", index:fill(rows[key][1], args))
    -- the plain key's own English stays its own: matched without the bare flag, its fill untouched
    key, args = index:match("Time Left: 5 min")
    assert.are.equal("BONUS_OBJECTIVE_TIME_LEFT", key)
    assert.is_nil(args.bare)
  end)
end)
