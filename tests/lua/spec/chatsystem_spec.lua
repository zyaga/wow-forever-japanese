-- UI/ChatSystem.lua over chat frames that replay the Forever ScrollingMessageFrame history
-- (blizzard_sharedxml/scrollingmessageframe.lua: AddMessage packages { message, r, g, b, extraData }, TransformMessages
-- rewrites the entries a predicate picks, each refresh re-initializes a visible line's font and then calls the
-- display-refreshed callbacks) and the chat event handler's AddMessage(arg1, info.r, info.g, info.b, info.id).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

-- the code-of-conduct notice's static link (GlobalStrings ONLINE_SAFETY_NOTICE)
local LINK = "|HurlIndex:64|h|cnVISITABLE_URL_DEFAULT_CHAT_LINK_COLOR:"
  .. "https://support.blizzard.com/article/42673|r|h"
local UI = {
  ERR_GROUP_FULL = { "Your party is full.", "パーティーがいっぱいです。" },
  ERR_QUEST_ADD_KILL_SII = { "%s slain: %d/%d", "%s を倒した: %d/%d" },
  ERR_TAME_FAILED = { "%s.", "%s。" }, -- no text of its own: never a chat line's template
  CLUB_FINDER_GUILD = { "Guild", "ギルド" }, -- an exact dictionary English that is no error key
  -- two English, one Japanese (the shipped data has such pairs)
  ERR_NOT_IN_GROUP = { "You aren't in a party.", "パーティーに所属していません。" },
  ERR_NOT_IN_PARTY = { "You are not in a party.", "パーティーに所属していません。" },
  -- all system chat (loot / XP / reputation / away …)
  LOOT_ITEM_SELF_MULTIPLE = { "You receive loot: %sx%d", "戦利品を入手: %sx%d" },
  COMBATLOG_XPGAIN_FIRSTPERSON = { "%s dies, you gain %d experience.", "%sが倒れ、%dの経験値を獲得しました。" },
  LEVEL_UP_STAT = { "Your %s increases by %d.", "%sが%d上昇しました。" },
  SPELL_STAT1_NAME = { "Strength", "筋力" },
  MARKED_AFK_MESSAGE = { "You are now Away: %s", "離席中になりました: %s" },
  ONLINE_SAFETY_NOTICE = { "Remember to act responsibly. View our Code of Conduct on " .. LINK .. " for more.",
    "責任ある行動を。詳しくは" .. LINK .. "の行動規範を。" },
  ROLE_CHANGED_INFORM = { "%s is now %s.", "%sの役割が%sになりました。" },
  TANK = { "Tank", "タンク" },
  CHATLOGDISABLED = { "Chat logging disabled.", "チャットの記録を無効にしました。" },
  TIME_PLAYED_TOTAL = { "Total time played: %s", "総プレイ時間: %s" },
  TIME_DAYHOURMINUTESECOND = { "%d |4day:days;, %d |4hour:hours;, %d |4minute:minutes;, %d |4second:seconds;",
    "%d日、%d時間、%d分、%d秒" },
  -- the voice channel's announce / management lines (channelframe.lua:502–526) and the Communities chat's
  -- client-written lines (communitieschatframe.lua:354–397)
  VOICE_CHAT_CHANNEL_ANNOUNCE = { "%1$s %2$s %3$s", "%1$s %2$s %3$s" },
  VOICE_CHAT_NOTIFICATION_CHANNEL_ACTIVATED_PARTY = { "Joined |c%sParty|r voice chat.",
    "|c%sパーティー|rのボイスチャットに参加しました。" },
  VOICE_CHAT_NOTIFICATION_COMMS_MODE_PTT = { "Push %s to talk.", "%sを押して発言。" },
  VOICE_CHAT_CHANNEL_MEMBER_COUNT_ACTIVE = { "%d |4player:players; in channel.", "チャンネルに%d人。" },
  VOICE_CHAT_CHANNEL_MANAGEMENT_TIP = { "%1$s Press %2$s to manage and join voice chat.",
    "%1$s %2$sでボイスチャットの管理と参加ができます。" },
  COMMUNITIES_CHAT_FRAME_TODAY_NOTIFICATION = { "Today", "今日" },
  COMMUNITIES_CHAT_FRAME_UNREAD_MESSAGES_NOTIFICATION = { "Unread Messages", "未読メッセージ" },
  COMMUNITIES_MESSAGE_OF_THE_DAY_FORMAT = { "Message of the Day: \"%s\"", "今日のメッセージ: 「%s」" },
  -- a friendship's rank points (FriendshipReputation, a client-table family the reputation line names)
  ["FriendshipGain:513"] = { "You gain %d Rank Points.", "ランクポイントを%d獲得した。" },
  ["ServerMessage:1"] = { "[SERVER] Shutdown in %s", "[サーバー] %s後にシャットダウン" },
}
local NAMES = { "CHAT_FRAMES", "ChatTypeInfo", "ChatFrame1", "ChatFrame2", "FCF_OpenTemporaryWindow",
  "issecretvalue" }
local SYSTEM, SAY, LOOT, XP, FACTION = 1, 2, 3, 4, 5

local clock = 0
local function chatFrame()
  local frame = { history = {}, visibleLines = { Stub.fontString(""), Stub.fontString("") }, callbacks = {},
    fontObject = Stub.fontObject("Fonts\\ARIALN.TTF", 14) }
  local function package(message, r, g, b, ...) -- PackageEntry: a new timestamp every time
    clock = clock + 1
    return { message = message, r = r, g = g, b = b, extra = { ... }, timestamp = clock }
  end
  function frame:AddMessage(message, r, g, b, ...)
    self.history[#self.history + 1] = package(message, r, g, b, ...)
  end
  function frame:BackFillMessage(message, r, g, b, ...) -- the oldest end of the history (scrollingmessageframe.lua:20)
    table.insert(self.history, 1, package(message, r, g, b, ...))
  end
  function frame:TransformMessages(predicate, transform)
    for i, e in ipairs(self.history) do
      if predicate(e.message, e.r, e.g, e.b, unpack(e.extra)) then
        self.history[i] = package(transform(e.message, e.r, e.g, e.b, unpack(e.extra)))
      end
    end
  end
  function frame:GetNumMessages() return #self.history end
  function frame:GetMessageInfo(i) -- 1 = the newest (scrollingmessageframe.lua:30–35)
    local e = self.history[#self.history - i + 1]
    if e then return e.message, e.r, e.g, e.b end
  end
  function frame:GetFontObject() return self.fontObject end
  function frame:AddOnDisplayRefreshedCallback(cb) self.callbacks[#self.callbacks + 1] = cb end
  -- RefreshDisplay: the newest entries on the visible lines, each line's font from the frame's font object first
  -- (InitializeFontString), then the callbacks
  function frame:Refresh()
    for i, line in ipairs(self.visibleLines) do
      local e = self.history[#self.history - #self.visibleLines + i]
      line.messageInfo = e
      line:SetFontObject(self.fontObject)
      line:SetText(e and e.message or "")
    end
    for _, cb in ipairs(self.callbacks) do cb(self) end
  end
  function frame:Last() return self.history[#self.history].message end
  return frame
end

local secrets = {}
local function install()
  _G.ChatTypeInfo = { SYSTEM = { id = SYSTEM, r = 1, g = 1, b = 0 }, SAY = { id = SAY, r = 1, g = 1, b = 1 },
    LOOT = { id = LOOT, r = 0, g = 0.7, b = 0 }, COMBAT_XP_GAIN = { id = XP, r = 0.4, g = 0.4, b = 1 },
    COMBAT_FACTION_CHANGE = { id = FACTION, r = 0.5, g = 0.5, b = 1 } }
  _G.ChatFrame1 = chatFrame()
  _G.CHAT_FRAMES = { "ChatFrame1" }
  _G.FCF_OpenTemporaryWindow = function()
    _G.ChatFrame2 = chatFrame()
    _G.CHAT_FRAMES[#_G.CHAT_FRAMES + 1] = "ChatFrame2"
    return _G.ChatFrame2
  end
  _G.issecretvalue = function(v) return secrets[v] == true end
end

local function system(frame, text) frame:AddMessage(text, 1, 1, 0, SYSTEM) end

local function load()
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  Stub.installTooltipAPI()
  Stub.installScrollUtil()
  local files = {}
  for i, f in ipairs(H.UI_FILES) do files[i] = f end
  files[#files + 1] = "UI/Errors.lua"
  files[#files + 1] = "UI/ChatSystem.lua"
  local WFJ = H.loadChunks(files)
  install()
  H.uiSetup(WFJ, UI)
  return WFJ
end

local function alt(WFJ, down)
  Stub.keys.alt = down
  WFJ.Modifier.refresh()
end

describe("SYSTEM chat lines", function()
  local WFJ
  before_each(function()
    secrets = {}
    WFJ = load()
    assert.is_true(WFJ.ChatSystem.init())
  end)
  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, n in ipairs(NAMES) do _G[n] = nil end
  end)

  it("a server notice is its ServerMessages row, the time kept as the client wrote it", function()
    local f = _G.ChatFrame1
    system(f, "[SERVER] Shutdown in 15:00")
    assert.are.equal("[サーバー] 15:00後にシャットダウン", f:Last())
  end)

  it("a reputation line is the FriendshipGain row with the live number; no other chat type takes it", function()
    local f = _G.ChatFrame1
    f:AddMessage("You gain 25 Rank Points.", 0.5, 0.5, 1, FACTION)
    assert.are.equal("ランクポイントを25獲得した。", f:Last())
    f:Refresh()
    alt(WFJ, true)
    assert.are.equal("You gain 25 Rank Points.", f.visibleLines[2]:GetText())
    alt(WFJ, false)
    assert.are.equal("ランクポイントを25獲得した。", f.visibleLines[2]:GetText())
    system(f, "You gain 25 Rank Points.") -- a SYSTEM line does not name the family
    assert.are.equal("You gain 25 Rank Points.", f:Last())
    f:AddMessage("You gain 25 Rank Points.", 1, 1, 1) -- an untyped line: exact English only
    assert.are.equal("You gain 25 Rank Points.", f:Last())
    f:AddMessage("Your party is full.", 0.5, 0.5, 1, FACTION) -- the chat keys still reach a reputation line
    assert.are.equal("パーティーがいっぱいです。", f:Last())
  end)

  it("a SYSTEM line is rewritten in the history when it arrives; others stay", function()
    local f = _G.ChatFrame1
    system(f, "Your party is full.")
    assert.are.equal("パーティーがいっぱいです。", f:Last())
    system(f, "Kobold Vermin slain: 1/10") -- a key-only error template with text of its own
    assert.are.equal("Kobold Vermin を倒した: 1/10", f:Last())
    system(f, "Guild") -- an exact dictionary English (a line Blizzard's Lua prints)
    assert.are.equal("ギルド", f:Last())
    f:AddMessage("Your party is full.", 1, 1, 1, SAY) -- a player's chat line: another chat type
    assert.are.equal("Your party is full.", f:Last())
    system(f, "Welcome to the realm.") -- would fit "%s.", no text of its own, never tried
    assert.are.equal("Welcome to the realm.", f:Last())
    secrets["Your party is full."] = true -- chat messaging lockdown
    system(f, "Your party is full.")
    assert.are.equal("Your party is full.", f:Last())
  end)

  it("the modifier and the switch show the English on the visible lines; the history is left alone", function()
    local f = _G.ChatFrame1
    system(f, "Your party is full.")
    system(f, "Kobold Vermin slain: 1/10")
    f:Refresh()
    local stamps = { f.history[1].timestamp, f.history[2].timestamp }
    local top, bottom = f.visibleLines[1], f.visibleLines[2]
    assert.are.equal("パーティーがいっぱいです。", top:GetText())
    alt(WFJ, true)
    assert.are.equal("Your party is full.", top:GetText())
    assert.are.equal("Kobold Vermin slain: 1/10", bottom:GetText())
    assert.are.equal(WFJ.Font.PATH, top.font.path) -- every chat line wears the bundled face, English too
    f:Refresh() -- scrolling / a new line while held: still English
    assert.are.equal("Your party is full.", top:GetText())
    alt(WFJ, false)
    assert.are.equal("パーティーがいっぱいです。", top:GetText())
    assert.are.equal(WFJ.Font.PATH, top.font.path)
    assert.are.same(stamps, { f.history[1].timestamp, f.history[2].timestamp }) -- no faded line comes back
    assert.are.equal("パーティーがいっぱいです。", f.history[1].message)
    WFJ.State.setEnabled(false)
    assert.are.equal("Your party is full.", top:GetText())
    WFJ.State.setEnabled(true)
    assert.are.equal("パーティーがいっぱいです。", top:GetText())
    WFJ.State.setArea("ui", false)
    assert.are.equal("Your party is full.", top:GetText())
    WFJ.State.setArea("ui", true)
    assert.are.equal("パーティーがいっぱいです。", top:GetText())
  end)

  it("a line that arrives while held is Japanese on release; one that arrives while off stays English", function()
    local f = _G.ChatFrame1
    alt(WFJ, true)
    system(f, "Your party is full.")
    f:Refresh()
    assert.are.equal("Your party is full.", f.visibleLines[2]:GetText())
    alt(WFJ, false)
    assert.are.equal("パーティーがいっぱいです。", f.visibleLines[2]:GetText())
    WFJ.State.setEnabled(false)
    system(f, "Kobold Vermin slain: 1/10")
    WFJ.State.setEnabled(true)
    f:Refresh()
    assert.are.equal("Kobold Vermin slain: 1/10", f.visibleLines[2]:GetText())
  end)

  it("one Japanese stands for one English; past the limit new lines stay English", function()
    local f = _G.ChatFrame1
    system(f, "You aren't in a party.")
    assert.are.equal("パーティーに所属していません。", f:Last())
    system(f, "You are not in a party.") -- the same Japanese, other English: Alt could not tell them apart
    assert.are.equal("You are not in a party.", f:Last())
    WFJ.ChatSystem.MAX_REMEMBERED = 1
    system(f, "Your party is full.")
    assert.are.equal("Your party is full.", f:Last())
    system(f, "You aren't in a party.") -- a known pair is still fine
    assert.are.equal("パーティーに所属していません。", f:Last())
  end)

  it("at the limit, the pairs no history holds any more are forgotten; one still held is kept", function()
    local f = _G.ChatFrame1
    WFJ.ChatSystem.MAX_REMEMBERED = 2
    system(f, "You aren't in a party.")
    system(f, "Your party is full.")
    f.history = { f.history[2] } -- the first line scrolled out of the history
    f:AddMessage("Kobold Vermin dies, you gain 45 experience.", 0.4, 0.4, 1, XP)
    assert.are.equal("Kobold Verminが倒れ、45の経験値を獲得しました。", f:Last()) -- the freed slot
    f:Refresh()
    alt(WFJ, true)
    assert.are.equal("Your party is full.", f.visibleLines[1]:GetText()) -- still held: Alt still has its English
    alt(WFJ, false)
    WFJ.ChatSystem.MAX_REMEMBERED = 4096
  end)

  it("a secret history entry (chat messaging lockdown) is asked about before any comparison", function()
    local f = _G.ChatFrame1
    local asked = {}
    _G.issecretvalue = function(v)
      asked[v] = true
      return v == "<secret>"
    end
    f:AddMessage("<secret>", 1, 1, 0, SYSTEM) -- a lockdown line: the hook leaves it
    asked["<secret>"] = nil -- from here on only the rewrite's predicate can ask about the history entry
    system(f, "Your party is full.")
    assert.is_true(asked["<secret>"])
    assert.are.equal("<secret>", f.history[1].message)
    assert.are.equal("パーティーがいっぱいです。", f:Last())
  end)

  it("the bundled face goes on every visible line, our Japanese and any English, at the chat size", function()
    local f = _G.ChatFrame1
    system(f, "Your party is full.")
    system(f, "Welcome to the realm.")
    f:Refresh()
    local ja, en = f.visibleLines[1], f.visibleLines[2]
    assert.are.equal("パーティーがいっぱいです。", ja:GetText())
    assert.are.equal(WFJ.Font.PATH, ja.font.path)
    assert.are.equal(14, ja.font.size)
    assert.are.equal(WFJ.Font.PATH, en.font.path) -- a player's Japanese would show here too
    assert.are.equal(14, en.font.size)
  end)

  it("an English row keeps the bundled face at the chat size, and follows a later chat font size change",
    function()
      local f = _G.ChatFrame1
      system(f, "Your party is full.")
      f:Refresh()
      local row = f.visibleLines[2]
      f:AddMessage("Ostara says: hey", 1, 1, 1, SAY) -- the Japanese moves up a row; English takes this one
      f:Refresh()
      assert.are.equal("Ostara says: hey", row:GetText())
      assert.are.equal(WFJ.Font.PATH, row.font.path)
      assert.are.equal(14, row.font.size)
      f.fontObject.font.size = 18 -- the player picks a bigger chat font: the client changes the object
      f:Refresh()
      for _, line in ipairs(f.visibleLines) do
        assert.are.equal(WFJ.Font.PATH, line.font.path)
        assert.are.equal(18, line.font.size)
      end
    end)

  it("Alt shows the English in the bundled face at the chat size; release the Japanese at the chat size", function()
    local f = _G.ChatFrame1
    system(f, "Your party is full.")
    f:Refresh()
    local row = f.visibleLines[2]
    row.font.size = 11 -- a size an earlier fit shrank it to
    alt(WFJ, true)
    assert.are.equal("Your party is full.", row:GetText())
    assert.are.equal(WFJ.Font.PATH, row.font.path)
    assert.are.equal(14, row.font.size)
    alt(WFJ, false)
    assert.are.equal(WFJ.Font.PATH, row.font.path)
    assert.are.equal(14, row.font.size) -- from the frame's font, not the row's leftover size
  end)

  it("in game: a Japanese line that takes an extra line is made smaller; a refused font is never retried",
    function()
      local line = Stub.fontString("")
      line.font = { path = "Fonts\\ARIALN.TTF", size = 14, flags = "" }
      function line.GetHeight() return 14 end -- the height the frame laid the line out at
      -- two lines (28 px) at 12 px and up, one line (14 px) below: shrinks until the extra line is gone
      function line:GetStringHeight()
        if self.font.path ~= WFJ.Font.PATH then return 14 end
        return self.font.size >= 12 and 28 or 14
      end
      assert.are.equal(11, WFJ.ChatSystem.fit(line))
      assert.are.equal(WFJ.Font.PATH, line.font.path)
      Stub.fontSetFails = true
      local refused = Stub.fontString("")
      assert.is_nil(WFJ.ChatSystem.fit(refused))
      Stub.fontSetFails = false
      assert.are.equal(0, WFJ.Font.retryPending()) -- nothing was left pending for a pooled line
    end)

  it("a one-line Japanese line a couple of pixels taller than its slot keeps its size", function()
    local line = Stub.fontString("")
    line.font = { path = "Fonts\\ARIALN.TTF", size = 14, flags = "" }
    function line.GetHeight() return 14 end
    function line.GetStringHeight() return 16 end -- the bundled face's line is a little taller: not an extra line
    assert.are.equal(14, WFJ.ChatSystem.fit(line))
  end)

  it("all system chat: loot, XP, a stat word, the away message, each its own chat type", function()
    local f = _G.ChatFrame1
    local link = "|cffffffff|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|r"
    f:AddMessage("You receive loot: " .. link .. "x3", 0, 0.7, 0, LOOT)
    assert.are.equal("戦利品を入手: " .. link .. "x3", f:Last()) -- the link and the count as written
    f:AddMessage("Kobold Vermin dies, you gain 45 experience.", 0.4, 0.4, 1, XP)
    assert.are.equal("Kobold Verminが倒れ、45の経験値を獲得しました。", f:Last())
    system(f, "Your Strength increases by 1.")
    assert.are.equal("筋力が1上昇しました。", f:Last()) -- a stat is a word, shown in Japanese
    system(f, "You are now Away: back in 5. brb")
    assert.are.equal("離席中になりました: back in 5. brb", f:Last()) -- the player's own message, periods and all
    f:AddMessage("Kobold Vermin dies, you gain 45 experience.", 1, 1, 1, SAY) -- a player typing the same words
    assert.are.equal("Kobold Vermin dies, you gain 45 experience.", f:Last())
  end)

  it("in game: /played, the duration (four plural groups, raw in the history) is an entry of its own", function()
    local f = _G.ChatFrame1
    -- ChatFrameUtil.DisplayTimePlayed: format(TIME_PLAYED_TOTAL, format(TIME_DAYHOURMINUTESECOND, d, h, m, s))
    system(f, "Total time played: 0 |4day:days;, 14 |4hour:hours;, 17 |4minute:minutes;, 49 |4second:seconds;")
    assert.are.equal("総プレイ時間: 0日、14時間、17分、49秒", f:Last())
  end)

  it("in game: Blizzard's Lua lines; a role change fills its role word; a line with no chat type is exact only",
    function()
      local f = _G.ChatFrame1
      system(f, "Bob is now Tank.")
      assert.are.equal("Bobの役割がタンクになりました。", f:Last())
      f:AddMessage("Chat logging disabled.", 1, 1, 0) -- DEFAULT_CHAT_FRAME:AddMessage(text, r, g, b): no type
      assert.are.equal("チャットの記録を無効にしました。", f:Last())
      f:AddMessage("Bob is now Tank.", 1, 1, 0) -- no type: a template is never tried (another addon's print)
      assert.are.equal("Bob is now Tank.", f:Last())
    end)

  it("in game: the code-of-conduct notice at login, its static link kept exactly as the client wrote it", function()
    local f = _G.ChatFrame1
    system(f, "Remember to act responsibly. View our Code of Conduct on " .. LINK .. " for more.")
    assert.are.equal("責任ある行動を。詳しくは" .. LINK .. "の行動規範を。", f:Last())
  end)

  it("the voice announce line: its three sentences each an entry, the atlas byte-identical; the management "
    .. "tip keeps its atlas and binding", function()
      local f = _G.ChatFrame1
      local atlas = "|A:voicechat-icon-headphone-on:0:0|a"
      local line = atlas .. "Joined |cff00ccffParty|r voice chat. Push ` to talk. 3 players in channel."
      system(f, line)
      assert.are.equal(atlas .. "|cff00ccffパーティー|rのボイスチャットに参加しました。 `を押して発言。 チャンネルに3人。",
        f:Last())
      system(f, "Joined |cff00ccffParty|r voice chat. Push ` to talk. 3 players in the raid.") -- one sentence unknown
      assert.are.equal("Joined |cff00ccffParty|r voice chat. Push ` to talk. 3 players in the raid.", f:Last())
      local tip = "|A:voicechat-channellist-icon-headphone-off:0:0|a Press (O) to manage and join voice chat."
      system(f, tip)
      assert.are.equal("|A:voicechat-channellist-icon-headphone-off:0:0|a (O)でボイスチャットの管理と参加ができます。",
        f:Last())
      f:Refresh()
      alt(WFJ, true)
      assert.are.equal(tip, f.visibleLines[2]:GetText())
      alt(WFJ, false)
    end)

  it("a key-restricted frame: the separators and the MOTD label, from AddMessage and BackFillMessage;"
    .. " a member's message is never touched", function()
      local keys = { "COMMUNITIES_CHAT_FRAME_TODAY_NOTIFICATION", "COMMUNITIES_CHAT_FRAME_YESTERDAY_NOTIFICATION",
        "COMMUNITIES_CHAT_FRAME_UNREAD_MESSAGES_NOTIFICATION", "COMMUNITIES_MESSAGE_OF_THE_DAY_FORMAT" }
      local m = chatFrame()
      assert.are.equal(1, WFJ.ChatSystem.hookKeyed(m, keys))
      assert.are.equal(0, WFJ.ChatSystem.hookKeyed(m, keys)) -- once
      m:AddMessage("Today", 0.4, 0.4, 0.4)
      assert.are.equal("今日", m:Last())
      m:AddMessage("Message of the Day: \"Raid at 8. Bring flasks!\"", 1, 1, 0)
      assert.are.equal("今日のメッセージ: 「Raid at 8. Bring flasks!」", m:Last())
      m:BackFillMessage("Unread Messages", 1, 0.5, 0)
      assert.are.equal("未読メッセージ", m.history[1].message)
      for _, text in ipairs({ "[Thrall]: Today", "Today", "Your party is full.", "[Jaina]: Unread Messages" }) do
        m:AddMessage(text == "Today" and "[Bob]: Today" or text, 1, 1, 1) -- members' lines, and a non-key English
        assert.are.equal(text == "Today" and "[Bob]: Today" or text, m:Last())
      end
      m:Refresh()
      m.visibleLines = { Stub.fontString(""), Stub.fontString("") }
      m.history[#m.history + 1] = m.history[1] -- the backfilled separator scrolled into view
      m:Refresh()
      assert.are.equal("未読メッセージ", m.visibleLines[2]:GetText())
      alt(WFJ, true)
      assert.are.equal("Unread Messages", m.visibleLines[2]:GetText())
      alt(WFJ, false)
      assert.are.equal("未読メッセージ", m.visibleLines[2]:GetText())
    end)

  it("a member's message never reaches the index: no scan, no memo slot", function()
    local keys = { "COMMUNITIES_CHAT_FRAME_TODAY_NOTIFICATION", "COMMUNITIES_CHAT_FRAME_YESTERDAY_NOTIFICATION",
      "COMMUNITIES_CHAT_FRAME_UNREAD_MESSAGES_NOTIFICATION", "COMMUNITIES_MESSAGE_OF_THE_DAY_FORMAT" }
    local m = chatFrame()
    WFJ.ChatSystem.hookKeyed(m, keys)
    local index = WFJ.UIIndex
    local calls, match, matchOnly = 0, index.match, index.matchOnly
    index.match = function(...) calls = calls + 1; return match(...) end
    index.matchOnly = function(...) calls = calls + 1; return matchOnly(...) end
    local memo = index.memoCount
    for _, text in ipairs({ "[Thrall]: Today", "[Jaina]: anyone for Deadmines?", "Your party is full.",
      "Message of the Day", "Todayish" }) do
      m:AddMessage(text, 1, 1, 1)
      assert.are.equal(text, m:Last())
    end
    assert.are.equal(0, calls)
    assert.are.equal(memo, index.memoCount)
    m:AddMessage("Message of the Day: \"Raid at 8.\"", 1, 1, 0) -- the MOTD prefix passes, then is matched by key
    assert.are.equal("今日のメッセージ: 「Raid at 8.」", m:Last())
    assert.is_true(calls > 0)
    index.match, index.matchOnly = match, matchOnly
  end)

  it("a temporary window is hooked once; init once", function()
    assert.is_false(WFJ.ChatSystem.init())
    local w = _G.FCF_OpenTemporaryWindow()
    assert.are.equal(0, WFJ.ChatSystem.hookAll()) -- the hook on FCF_OpenTemporaryWindow already took it
    system(w, "Your party is full.")
    assert.are.equal("パーティーがいっぱいです。", w:Last())
    assert.are.equal(1, #w.history)
  end)

  it("a wrong-typed call raises nothing", function()
    assert.has_no.errors(function()
      WFJ.ChatSystem.onAddMessage(nil)
      WFJ.ChatSystem.onAddMessage(_G.ChatFrame1, 5, 1, 1, 1, SYSTEM)
      WFJ.ChatSystem.onRefreshed({ visibleLines = { 3 } })
    end)
  end)
end)
