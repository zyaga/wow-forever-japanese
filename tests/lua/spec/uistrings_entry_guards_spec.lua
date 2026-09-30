-- Core/UIStrings guards: an `entry` argument takes no template that carries text (exact entries and number-only
-- templates still do), and the voice announce parts answer only a caller that asks for their key.
local H = require("tests.lua.spec.helpers")

describe("Core/UIStrings entry and voice-part guards", function()
  local index, rows

  local function h1(text)
    local n = 0
    for i = 1, #text do n = (n * 31 + text:byte(i)) % 4294967296 end
    return n
  end

  local UI = {
    PVP_LEAVE_BUTTON_TIME = { "%s (%s)", "%s（%s）" }, -- [1] entry, [2] text
    PVP_MATCH_LEAVE_BUTTON = { "Leave Match", "試合を離れる" },
    TOOLTIP_VIGNETTE_OBJECTIVE_DEFEAT = { "- Defeat %s", "- %sを倒す" }, -- key-only, [1] text
    ITEM_WRITTEN_BY = { "Written by %s", "著者: %s" }, -- unrestricted, [1] text
    TIME_PLAYED_TOTAL = { "Total time played: %s", "総プレイ時間: %s" }, -- [1] entry
    TIME_DAYHOURMINUTESECOND = { "%d |4day:days;, %d |4hour:hours;, %d |4minute:minutes;, %d |4second:seconds;",
      "%d日%d時間%d分%d秒" },
    VOICE_CHAT_CHANNEL_ANNOUNCE = { "%1$s %2$s %3$s", "%1$s %2$s %3$s" },
    VOICE_CHAT_NOTIFICATION_COMMS_MODE_VOICE_ACTIVATED = { "Open Mic.", "オープンマイク。" },
    VOICE_CHAT_CHANNEL_MEMBER_COUNT_ACTIVE = { "%d |4player:players; in channel.", "チャンネルに%d人。" },
    VOICE_CHAT_NOTIFICATION_CHANNEL_ACTIVATED_PARTY = { "Joined |c%sParty|r voice chat.",
      "|c%sパーティー|rのボイスチャットに参加しました。" },
    ERR_QUEST_SESSION_RESULT_ALREADY_ACTIVE = { "Party Sync is already active.", "パーティー同期はすでに有効です。" },
    VOTE_TO_ABANDON_VOTES_NEEDED = { "%d votes needed to abandon the instance.",
      "インスタンスの放棄には%d票が必要です。" },
  }

  setup(function()
    local ns = H.loadChunks({ "Core/UIStringKeys.lua", "Core/UIStrings.lua" })
    rows = {}
    local english = {}
    for key, pair in pairs(UI) do
      rows[key] = { pair[2], h1(pair[1]), "." }
      english[key] = pair[1]
    end
    index = ns.UIStrings.build({ rows = rows, hash = h1, english = function(key) return english[key] end })
  end)

  local function ja(text, only)
    local key, args
    if only then key, args = index:matchOnly(text, only) else key, args = index:match(text) end
    assert.is_not_nil(key, text)
    return index:fill(rows[key][1], args)
  end

  it("a template carrying text is no `entry`: a vignette line or a name-carrying line inside \"%s (%s)\"",
    function()
      local only = { "PVP_LEAVE_BUTTON_TIME" }
      assert.is_nil(index:matchOnly("- Defeat Hogger (Current Health: 50%)", only))
      assert.is_nil(index:match("- Defeat Hogger (Current Health: 50%)"))
      assert.is_nil(index:matchOnly("Written by Hogger (5)", only)) -- an unrestricted text template, too
      assert.are.equal("著者: Hogger (5)", ja("Written by Hogger (5)")) -- the name-carrying line itself still matches
    end)

  it("an exact entry and a number-only template still stand as an `entry`", function()
    assert.are.equal("試合を離れる（5）", ja("Leave Match (5)", { "PVP_LEAVE_BUTTON_TIME" }))
    assert.are.equal("総プレイ時間: 2日2時間3分4秒",
      ja("Total time played: 2 days, 2 hours, 3 minutes, 4 seconds", { "TIME_PLAYED_TOTAL" }))
  end)

  it("three sentences that are each an entry are no voice line on an unrestricted match", function()
    local line = "Party Sync is already active. Party Sync is already active. 3 votes needed to abandon the instance."
    assert.is_nil(index:match(line))
    local voice = "Joined |cff00ccffParty|r voice chat. Open Mic. 3 players in channel."
    assert.is_nil(index:match(voice))
    assert.are.equal("|cff00ccffパーティー|rのボイスチャットに参加しました。 オープンマイク。 チャンネルに3人。",
      ja(voice, { "VOICE_CHAT_CHANNEL_ANNOUNCE" }))
  end)
end)
