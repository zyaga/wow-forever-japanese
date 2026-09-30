-- ADR-038: Core/UIStrings argument kinds and forms. The `entry` kind taking a colour-wrapped entry, the `entryList`
-- and `entryOrText` kinds, colonPrefix with an entry rest, the count label, the duration suffix, the icon after a word,
-- colour-wrapped paragraphs, header lines, the voice announce parts, the `seq` fill form, `time` taking "< 1 minute",
-- the Japanese FULLDATE, the atlas argument and `|A…|a` kept byte-identical.
local H = require("tests.lua.spec.helpers")

describe("Core/UIStrings additions", function()
  local UIS, index, rows

  local function h1(text)
    local n = 0
    for i = 1, #text do n = (n * 31 + text:byte(i)) % 4294967296 end
    return n
  end

  local ATLAS = "|A:editmode-up-arrow:16:11:0:3|a"
  local UI = {
    GUILD_EVENT_FORMAT = { "%1$s %2$s: %3$s", "%1$s %2$s: %3$s" },
    GUILD_EVENT_TODAY = { "TODAY", "今日" },
    WEEKDAY_MONDAY = { "Monday", "月曜日" },
    BAG_FILTER_ASSIGNED_TO = { "Assigned to: |cffffffff%s|r", "割り当て先: |cffffffff%s|r" },
    BAG_FILTER_EQUIPMENT = { "Equipment", "装備品" },
    BAG_FILTER_CONSUMABLES = { "Consumables", "消耗品" },
    SOLD_BY_COLON = { "Sold By:", "販売者:" },
    AUCTION_HOUSE_MAIL_MULTIPLE_SELLERS = { "Multiple Sellers", "複数の販売者" },
    MAIL_MULTIPLE_ITEMS = { "Multiple items", "複数のアイテム" },
    DAMAGE_METER_COMBAT_NUMBER = { "Combat %d", "戦闘 %d" },
    COOLDOWN_VIEWER_SETTINGS_BUTTON_REVERT_CHANGES = { "Revert", "元に戻す" },
    OPTION_TOOLTIP_DISABLE_CHAT = { "Disables chat.", "チャットを無効にします。" },
    OPTION_TOOLTIP_DISABLE_CHAT_ACCOUNT_MUTE = { "Go to your account settings.", "アカウント設定に移動してください。" },
    HAVE_MAIL_FROM = { "Unread mail from:", "未読メールの差出人:" },
    VOICE_CHAT_CHANNEL_ANNOUNCE = { "%1$s %2$s %3$s", "%1$s %2$s %3$s" },
    VOICE_CHAT_NOTIFICATION_CHANNEL_ACTIVATED_PARTY = { "Joined |c%sParty|r voice chat.",
      "|c%sパーティー|rのボイスチャットに参加しました。" },
    VOICE_CHAT_NOTIFICATION_COMMS_MODE_VOICE_ACTIVATED = { "Open Mic.", "オープンマイク。" },
    VOICE_CHAT_CHANNEL_MEMBER_COUNT_ACTIVE = { "%d |4player:players; in channel.", "チャンネルに%d人。" },
    TIME_IN_QUEUE = { "Time in Queue: %s", "待機時間: %s" },
    LESS_THAN_ONE_MINUTE = { "< 1 minute", "1分未満" },
    FULLDATE = { "%1$s, %2$s %3$d %4$d", "%4$d年%2$s%3$d日(%1$s)" },
    MONTH_SEPTEMBER = { "September", "9月" },
    WEEKDAY_THURSDAY = { "Thursday", "木" },
    GUILDCONTROL_DISCORD_SETTINGS = { "%s Discord Settings", "%s Discord設定" },
    HUD_EDIT_MODE_COLLAPSE_OPTIONS = { "Collapse options " .. ATLAS, "オプションを折りたたむ " .. ATLAS },
    QUICK_JOIN_TOAST_MESSAGE = { "%s queued for %s", "%sが%sの順番待ちに登録しました" },
    SOCIAL_QUEUE_FORMAT_ARENA_SKIRMISH = { "Arena Skirmish", "アリーナ小競り合い" },
    GUILD_BANK_LOG_TIME = { "|cff009999   ( %s ago )|r", "|cff009999   ( %s前 )|r" },
    LASTONLINE_MINS = { "< an hour", "1時間未満" },
    COOLDOWN_VIEWER_SETTINGS_ACTION_ADD_ALERT = { "Cannot add cooldown alert: %s",
      "クールダウンアラートを追加できません: %s" },
    COOLDOWN_VIEWER_SETTINGS_ADD_ALERT_TOOLTIP_DISABLED_TOO_MANY = {
      "You have too many alerts, please remove one first.",
      "アラートが多すぎます。先に1つ削除してください。" },
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

  local function ja(text, only)
    local key, args
    if only then key, args = index:matchOnly(text, only) else key, args = index:match(text) end
    assert.is_not_nil(key, text)
    return index:fill(rows[key][1], args), key
  end

  it("an `entry` argument may be wrapped in one colour, kept around its Japanese (GUILD_EVENT_TODAY)", function()
    local text = "|cffffd200TODAY|r 8:00 PM: Raid Night"
    assert.are.equal("|cffffd200今日|r 8:00 PM: Raid Night", ja(text, { "GUILD_EVENT_FORMAT" }))
    assert.are.equal("月曜日 8:00 PM: Raid Night", ja("Monday 8:00 PM: Raid Night", { "GUILD_EVENT_FORMAT" }))
    assert.is_nil(index:matchOnly("|cffffd200Someday|r 8:00 PM: x", { "GUILD_EVENT_FORMAT" })) -- no entry inside
    assert.is_nil(index:match(text)) -- key-only: never an unrestricted match
  end)

  it("an `entryList` shows every filter in Japanese with the delimiter kept; one unknown piece keeps it all "
    .. "English",
    function()
      local only = { "BAG_FILTER_ASSIGNED_TO" } -- key-only: the bag portrait asks by key
      assert.are.equal("割り当て先: |cffffffff装備品,消耗品|r", ja("Assigned to: |cffffffffEquipment,Consumables|r", only))
      assert.are.equal("割り当て先: |cffffffff装備品, 消耗品|r",
        ja("Assigned to: |cffffffffEquipment, Consumables|r", only))
      assert.are.equal("割り当て先: |cffffffff装備品|r", ja("Assigned to: |cffffffffEquipment|r", only))
      assert.is_nil(index:matchOnly("Assigned to: |cffffffffEquipment,Reagents|r", only))
      assert.is_nil(index:match("Assigned to: |cffffffffEquipment|r")) -- never an unrestricted match
    end)

  it("colonPrefix whose rest is a granted entry shows both in Japanese; any other rest (a name) is kept", function()
    assert.are.equal("販売者: 複数の販売者", ja("Sold By: Multiple Sellers"))
    assert.are.equal("販売者: Thrall", ja("Sold By: Thrall"))
  end)

  it("a count label keeps the count; the duration suffix and the icon after a word are kept", function()
    assert.are.equal("複数のアイテム (3)", ja("Multiple items (3)"))
    assert.are.equal("戦闘 3 [01:23]", ja("Combat 3 [01:23]"))
    assert.is_nil(index:match("Onyxia [01:23]")) -- a named session stays English
    assert.are.equal("元に戻す |A:common-icon-undo:0:0|a", ja("Revert |A:common-icon-undo:0:0|a"))
  end)

  it("a colour-wrapped paragraph, header lines with names kept, and the voice announce parts", function()
    assert.are.equal("チャットを無効にします。\n\n|cffff2020アカウント設定に移動してください。|r",
      ja("Disables chat.\n\n|cffff2020Go to your account settings.|r"))
    assert.are.equal("未読メールの差出人:\nThrall\nJaina", ja("Unread mail from:\nThrall\nJaina"))
    local line = "|A:voicechat-icon-headphone-on:0:0|aJoined |cff00ccffParty|r voice chat. Open Mic. "
      .. "3 players in channel."
    local out, key = ja(line, { "VOICE_CHAT_CHANNEL_ANNOUNCE" })
    assert.are.equal("VOICE_CHAT_CHANNEL_ANNOUNCE", key)
    assert.are.equal("|A:voicechat-icon-headphone-on:0:0|a|cff00ccffパーティー|rのボイスチャットに参加しました。 "
      .. "オープンマイク。 チャンネルに3人。", out)
    assert.is_nil(index:match("Joined something. Open Mic. 3 players in channel."))
  end)

  it("`time` takes a leading '<' (LESS_THAN_ONE_MINUTE, LASTONLINE_MINS); FULLDATE is a Japanese date", function()
    assert.are.equal("待機時間: 1分未満", ja("Time in Queue: < 1 minute"))
    assert.are.equal("|cff009999   ( 1時間未満前 )|r", ja("|cff009999   ( < an hour ago )|r"))
    assert.are.equal("2026年9月25日(木)", ja("Thursday, September 25 2026"))
    assert.is_nil(index:match("Someday, September 25 2026")) -- the weekday must be a dictionary word
  end)

  it("an atlas argument is taken verbatim; `|A…|a` in an entry renders byte-identical", function()
    assert.are.equal("|A:ui-discord:19:19|a Discord設定",
      ja("|A:ui-discord:19:19|a Discord Settings", { "GUILDCONTROL_DISCORD_SETTINGS" })) -- key-only
    assert.are.equal("オプションを折りたたむ " .. ATLAS, ja("Collapse options " .. ATLAS))
  end)

  it("`entryOrText`: the queue name in Japanese when it is an entry, as written otherwise", function()
    local only = { "QUICK_JOIN_TOAST_MESSAGE" }
    assert.are.equal("Thrallがアリーナ小競り合いの順番待ちに登録しました", ja("Thrall queued for Arena Skirmish", only))
    assert.are.equal("ThrallがDeadminesの順番待ちに登録しました", ja("Thrall queued for Deadmines", only))
    assert.is_nil(index:match("Thrall queued for Deadmines")) -- key-only
  end)

  it("`seq` fills its parts in order, kept text as written, and fails closed", function()
    local args = { form = "seq", parts = { "[001] ", { key = "GUILD_EVENT_TODAY", open = "|cff00ff00", close = "|r" },
      " x 3", { key = "MAIL_MULTIPLE_ITEMS" } } }
    assert.are.equal("[001] |cff00ff00今日|r x 3複数のアイテム", index:fill("ignored", args))
    local bad = { form = "seq", parts = { { key = "FULLDATE", args = { key = "FULLDATE" } } } }
    assert.is_nil(index:fill("ignored", bad))
  end)

  it("the add-alert disabled tooltip: the action template around a status key, both in Japanese, key-only", function()
    local text = "Cannot add cooldown alert: You have too many alerts, please remove one first."
    assert.are.equal("クールダウンアラートを追加できません: アラートが多すぎます。先に1つ削除してください。",
      ja(text, { "COOLDOWN_VIEWER_SETTINGS_ACTION_ADD_ALERT" }))
    assert.is_nil(index:matchOnly("Cannot add cooldown alert: something else",
      { "COOLDOWN_VIEWER_SETTINGS_ACTION_ADD_ALERT" }))
    assert.is_nil(index:match(text)) -- key-only
  end)
end)
