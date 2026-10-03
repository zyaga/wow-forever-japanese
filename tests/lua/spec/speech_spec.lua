-- UI/Speech.lua: NPC speech in the chat window (the event handler's MessageFormatter replayed:
-- format(CHAT_<TYPE>_GET .. message, name, name), chatframeoverrides.lua:543–672), in speech bubbles and as boss emotes
-- on RaidWarningFrame (raidwarning.lua:83–119, 205–227). Gossip rows are keyed here by the English itself (the key
-- function Main passes is the Collector's hash; the module only calls it).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  CHAT_MONSTER_SAY_GET = { "%s says: ", "%sの発言: " },
  CHAT_MONSTER_YELL_GET = { "%s yells: ", "%sの叫び: " },
  CHAT_SAY_GET = { "%s says: ", "%sの発言: " },
}
local GOSSIP = {
  ["Stay close, {name}!"] = { "離れるな、{name}！", "." },
  ["%s goes into a frenzy!"] = { "%sは狂乱状態になった！", "." },
  ["The rest is stale."] = { "古い訳。", "s" },
  ["%s laughs."] = { "笑った。", "." }, -- a draft that lost the speaker's %s: never shown
}
local function format(...) return string.format(...) end
local NAMES = { "CHAT_FRAMES", "ChatTypeInfo", "ChatFrame1", "FCF_OpenTemporaryWindow", "issecretvalue",
  "RaidWarningFrame", "C_ChatBubbles" }
local SAY, YELL, EMOTE, BOSS, PLAYER_SAY = 11, 12, 13, 14, 1

local clock = 0
local function chatFrame()
  local frame = { history = {}, visibleLines = { Stub.fontString("") }, callbacks = {},
    fontObject = Stub.fontObject("Fonts\\ARIALN.TTF", 14) }
  local function package(message, r, g, b, ...)
    clock = clock + 1
    return { message = message, r = r, g = g, b = b, extra = { n = select("#", ...), ... }, timestamp = clock }
  end
  function frame:AddMessage(message, r, g, b, ...) self.history[#self.history + 1] = package(message, r, g, b, ...) end
  function frame:TransformMessages(predicate, transform)
    for i, e in ipairs(self.history) do
      if predicate(e.message, e.r, e.g, e.b, unpack(e.extra, 1, e.extra.n)) then
        self.history[i] = package(transform(e.message, e.r, e.g, e.b, unpack(e.extra, 1, e.extra.n)))
      end
    end
  end
  function frame:GetFontObject() return self.fontObject end
  function frame:AddOnDisplayRefreshedCallback(cb) self.callbacks[#self.callbacks + 1] = cb end
  function frame:Refresh()
    local line, e = self.visibleLines[1], self.history[#self.history]
    line.messageInfo = e
    line:SetFontObject(self.fontObject)
    line:SetText(e and e.message or "")
    for _, cb in ipairs(self.callbacks) do cb(self) end
  end
  function frame:Last() return self.history[#self.history].message end
  return frame
end

-- The chat event handler for a monster line: the formatter and the AddMessage call it makes.
local lineID = 0
local function npc(frame, typeId, template, body, speaker, guid, target, language)
  lineID = lineID + 1
  local function formatter(msg) return format(template .. msg, speaker, speaker) end
  local args = { body, speaker, language or "", n = 12 }
  args[5] = target
  args[11] = lineID
  args[12] = guid
  frame:AddMessage(formatter(body), 1, 1, 0.6, typeId, nil, nil, "CHAT_MSG_MONSTER", args, formatter)
end

local secrets = {}
local bubbles = {}
local function install()
  _G.format = _G.format or string.format -- WoW's global
  _G.ChatTypeInfo = { SYSTEM = { id = 99 }, SAY = { id = PLAYER_SAY }, MONSTER_SAY = { id = SAY },
    MONSTER_YELL = { id = YELL }, MONSTER_EMOTE = { id = EMOTE }, RAID_BOSS_EMOTE = { id = BOSS } }
  _G.ChatFrame1 = chatFrame()
  _G.CHAT_FRAMES = { "ChatFrame1" }
  _G.issecretvalue = function(v) return secrets[v] == true end
  _G.C_ChatBubbles = { GetAllChatBubbles = function() return bubbles end }
  -- RaidWarningFrame: a pool of FontStrings, the newest one by messageOrder
  local warn = { fontStringPool = { active = {} }, messageCounter = 0, scripts = {} }
  function warn.fontStringPool:EnumerateActive() return pairs(self.active) end
  function warn:HookScript(_, fn) self.scripts[#self.scripts + 1] = fn end
  function warn:Fire(event, message, playerName) -- OnEvent: the mixin first, then the hooks
    local fs = Stub.fontString("")
    fs:SetText(format(message, playerName, playerName))
    self.messageCounter = self.messageCounter + 1
    fs.messageOrder = self.messageCounter
    self.fontStringPool.active[fs] = true
    for _, fn in ipairs(self.scripts) do fn(self, event, message, playerName) end
    return fs
  end
  _G.RaidWarningFrame = warn
end

local function load()
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  Stub.installTooltipAPI()
  Stub.installScrollUtil()
  local files = {}
  for i, f in ipairs(H.UI_FILES) do files[i] = f end
  for _, f in ipairs({ "Core/Lookup.lua", "UI/Errors.lua", "UI/ChatSystem.lua", "UI/Speech.lua" }) do
    files[#files + 1] = f
  end
  local WFJ = H.loadChunks(files)
  install()
  H.uiSetup(WFJ, UI)
  WFJ.Data = WFJ.Data or {}
  WFJ.Data.gossip = {}
  for en, row in pairs(GOSSIP) do WFJ.Data.gossip[en] = { row[1], row[2] } end
  return WFJ
end

local function alt(WFJ, down)
  Stub.keys.alt = down
  WFJ.Modifier.refresh()
end

describe("NPC speech", function()
  local WFJ
  before_each(function()
    secrets, bubbles, clock = {}, {}, 0
    WFJ = load()
    WFJ.State.setArea("gossip", true) -- the NPC talk setting (Settings' area.gossip, on by default)
    assert.is_true(WFJ.ChatSystem.init())
    local expand = function(ja) return (ja:gsub("{name}", "Testplayer")) end
    assert.is_true(WFJ.Speech.init({ key = function(text) return text:gsub("Testplayer", "{name}") end,
      expand = expand }))
  end)
  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, n in ipairs(NAMES) do _G[n] = nil end
  end)

  it("a say is rewritten in the chat history, the prefix's words too; the speaker's name as written", function()
    local f = _G.ChatFrame1
    npc(f, SAY, "%s says: ", "Stay close, Testplayer!", "Ralph")
    assert.are.equal("Ralphの発言: 離れるな、Testplayer！", f:Last())
    npc(f, EMOTE, "", "%s goes into a frenzy!", "Hogger")
    assert.are.equal("Hoggerは狂乱状態になった！", f:Last())
    npc(f, YELL, "%s yells: ", "Something no one translated!", "Bob")
    assert.are.equal("Bobの叫び: Something no one translated!", f:Last()) -- the prefix alone
  end)

  it("every NPC line goes to the Collector with its speaker, translated or not; a secret line does not", function()
    local recorded = {}
    WFJ.Collector = { recordGossip = function(text, guid) recorded[#recorded + 1] = { text, guid } end }
    local f = _G.ChatFrame1
    npc(f, SAY, "%s says: ", "Something no one translated!", "Lyreena", "Creature-0-1-2-3-216000-00001")
    npc(f, SAY, "%s says: ", "Stay close, Testplayer!", "Ralph", "Creature-0-1-2-3-1234-00002")
    secrets["A secret line."] = true
    npc(f, SAY, "%s says: ", "A secret line.", "Ralph", "Creature-0-1-2-3-1234-00002")
    assert.are.same({ { "Something no one translated!", "Creature-0-1-2-3-216000-00001" },
      { "Stay close, Testplayer!", "Creature-0-1-2-3-1234-00002" } }, recorded)
    -- a line to another player is never recorded (it may hold their name); one to this player is
    _G.UnitName = function() return "Testplayer" end
    npc(f, SAY, "%s says: ", "Thank you, Otherguy!", "Ralph", "Creature-0-1-2-3-1234-00002", "Otherguy")
    npc(f, SAY, "%s says: ", "Thank you, Testplayer!", "Ralph", "Creature-0-1-2-3-1234-00002", "Testplayer")
    assert.are.equal(3, #recorded)
    assert.are.equal("Thank you, Testplayer!", recorded[3][1])
    -- a language this character does not know arrives scrambled and is not recorded; a known one is
    _G.GetNumLanguages = function() return 2 end
    _G.GetLanguageByIndex = function(i) return ({ "Common", "Darnassian" })[i], i end
    npc(f, SAY, "%s says: ", "Lok tar ogar!", "Grunt", "Creature-0-1-2-3-1234-00003", nil, "Orcish")
    npc(f, SAY, "%s says: ", "Elune guide you.", "Sentinel", "Creature-0-1-2-3-1234-00004", nil, "Darnassian")
    assert.are.equal(4, #recorded)
    assert.are.equal("Elune guide you.", recorded[4][1])
    _G.GetNumLanguages, _G.GetLanguageByIndex = nil, nil
    _G.UnitName = nil
    WFJ.Collector = nil
  end)

  it("a stale row, a draft that lost %s, or a secret line stays English", function()
    local f = _G.ChatFrame1
    npc(f, SAY, "", "The rest is stale.", "Ralph")
    assert.are.equal("The rest is stale.", f:Last())
    npc(f, EMOTE, "", "%s laughs.", "Ralph")
    assert.are.equal("Ralph laughs.", f:Last())
    secrets["Stay close, Testplayer!"] = true
    npc(f, SAY, "%s says: ", "Stay close, Testplayer!", "Ralph")
    assert.are.equal("Ralph says: Stay close, Testplayer!", f:Last())
  end)

  it("Alt and the NPC talk switch show the English on the visible line", function()
    local f = _G.ChatFrame1
    npc(f, SAY, "%s says: ", "Stay close, Testplayer!", "Ralph")
    f:Refresh()
    local line = f.visibleLines[1]
    alt(WFJ, true)
    assert.are.equal("Ralph says: Stay close, Testplayer!", line:GetText())
    alt(WFJ, false)
    assert.are.equal("Ralphの発言: 離れるな、Testplayer！", line:GetText())
    WFJ.State.setArea("gossip", false)
    assert.are.equal("Ralph says: Stay close, Testplayer!", line:GetText())
    WFJ.State.setArea("gossip", true)
  end)

  it("a player's say gets the prefix's words; the player's own text is never touched", function()
    local f = _G.ChatFrame1
    local args = { "Stay close, Testplayer!", "Bob", n = 11 }
    args[11] = 500
    f:AddMessage("Bob says: Stay close, Testplayer!", 1, 1, 1, PLAYER_SAY, 7, nil, "CHAT_MSG_SAY", args)
    assert.are.equal("Bobの発言: Stay close, Testplayer!", f:Last())
  end)

  it("a speech bubble showing the English gets the Japanese in the bundled face", function()
    local f = _G.ChatFrame1
    local string = Stub.fontString("")
    local child = { String = string }
    bubbles[1] = { GetChildren = function() return child end, IsForbidden = function() return false end }
    npc(f, SAY, "%s says: ", "Stay close, Testplayer!", "Ralph")
    string:SetText("Stay close, Testplayer!") -- the client makes the bubble after the line
    assert.are.equal(1, WFJ.Speech.scanBubbles())
    assert.are.equal("離れるな、Testplayer！", string:GetText())
    assert.are.equal(WFJ.Font.PATH, string.font.path)
    alt(WFJ, true)
    assert.are.equal("Stay close, Testplayer!", string:GetText())
    assert.are.equal("Fonts\\FRIZQT__.TTF", string.font.path) -- its own font back while English shows
    alt(WFJ, false)
    assert.are.equal(WFJ.Font.PATH, string.font.path)
    string:SetText("Another line entirely") -- the client reuses the pooled string for a later bubble
    WFJ.Speech.refresh()
    assert.are.equal("Fonts\\FRIZQT__.TTF", string.font.path) -- in game: the bundled face stayed on reused bubbles
  end)

  it("a boss emote in the middle of the screen", function()
    local fs = _G.RaidWarningFrame:Fire("RAID_BOSS_EMOTE", "%s goes into a frenzy!", "Onyxia")
    assert.are.equal("Onyxiaは狂乱状態になった！", fs:GetText())
    local other = _G.RaidWarningFrame:Fire("CHAT_MSG_RAID_WARNING", "Pull in 5", "Bob")
    assert.are.equal("Pull in 5", other:GetText())
  end)
end)
