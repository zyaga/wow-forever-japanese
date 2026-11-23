-- UI/ChatSystem: names on the chat window's visible lines while Japanese names are on. An NPC line (UI/Speech
-- rewrites its history once with its Japanese) shows the speaker's name and the names inside its Japanese in
-- Japanese; an item, spell or quest link in any line shows its label in Japanese, the link itself as the client
-- wrote it. The history is left as it is, so the reveal key and the names setting follow on the next display
-- refresh. The history entry is packaged as the client does (scrollingmessageframe.lua PackageEntry: message, r, g,
-- b, extraData = { typeId, accessID, typeID, event, eventArgs, formatter }).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  CHAT_MONSTER_SAY_GET = { "%s says: ", "%sの発言: " },
  CHAT_SAY_GET = { "%s says: ", "%sの発言: " },
}
local GOSSIP = {
  ["Never forget the Great War, {name}."] = { "{name}よ、Great Warを忘れるな。", "." },
}
local KEY = {}
for en in pairs(GOSSIP) do KEY[en] = ("%016x"):format(#en) end
local function keyOf(text) return KEY[(text:gsub("Thrall", "{name}"))] or ("%016x"):format(0) end

local NAMES = { "CHAT_FRAMES", "ChatTypeInfo", "ChatFrame1", "FCF_OpenTemporaryWindow", "issecretvalue",
  "UnitName" }
local SYSTEM, PLAYER_SAY, PARTY, SAY = 1, 2, 3, 11

local function chatFrame()
  local frame = { history = {}, visibleLines = { Stub.fontString("") }, callbacks = {},
    fontObject = Stub.fontObject("Fonts\\ARIALN.TTF", 14) }
  local function package(message, r, g, b, ...)
    local n = select("#", ...)
    local extraData = n > 0 and { n = n, ... } or nil
    return { message = message, r = r, g = g, b = b, extraData = extraData }
  end
  local function unpackage(e)
    if e.extraData then return e.message, e.r, e.g, e.b, unpack(e.extraData, 1, e.extraData.n) end
    return e.message, e.r, e.g, e.b
  end
  function frame:AddMessage(message, r, g, b, ...) self.history[#self.history + 1] = package(message, r, g, b, ...) end
  function frame:TransformMessages(predicate, transform)
    for i, e in ipairs(self.history) do
      if predicate(unpackage(e)) then self.history[i] = package(transform(unpackage(e))) end
    end
  end
  function frame:GetFontObject() return self.fontObject end
  function frame:AddOnDisplayRefreshedCallback(cb) self.callbacks[#self.callbacks + 1] = cb end
  -- a display refresh: the newest entry on the one visible line, then the callbacks
  function frame:Refresh()
    local line, e = self.visibleLines[1], self.history[#self.history]
    line.messageInfo = e
    line:SetFontObject(self.fontObject)
    line:SetText(e and e.message or "")
    for _, cb in ipairs(self.callbacks) do cb(self) end
    return line:GetText()
  end
  return frame
end

local lineID = 0
-- the chat event handler for a monster line (chatframeoverrides.lua:554–683): the speaker plain, never a link
local function npc(frame, body, speaker, target)
  lineID = lineID + 1
  local function formatter(msg) return string.format("%s says: " .. msg, speaker, speaker) end
  local args = { body, speaker, "", n = 12 }
  args[5], args[11] = target, lineID
  frame:AddMessage(formatter(body), 1, 1, 0.6, SAY, nil, nil, "CHAT_MSG_MONSTER_SAY", args, formatter)
end
-- a player's line in party chat: never rewritten in the history
local function party(frame, text, speaker)
  lineID = lineID + 1
  local args = { text, speaker, "", n = 12 }
  args[11] = lineID
  frame:AddMessage("[" .. speaker .. "]: " .. text, 0.6, 0.6, 1, PARTY, nil, nil, "CHAT_MSG_PARTY", args)
end

local ITEM = "|cff9d9d9d|Hitem:2589::::::::10:::::::|h[Linen Cloth]|h|r"
local SPELL = "|cff71d5ff|Hspell:116:0|h[Frostbolt]|h|r"
local QUEST = "|cffffff00|Hquest:2:10|h[Sharptalon's Claw]|h|r"
-- a recipe: an enchant link labelled with the skill and the recipe
local RECIPE = "|cffffd000|Henchant:13898|h[Enchanting: Enchant Weapon - Fiery Weapon]|h|r"

describe("names on the chat window's lines", function()
  local WFJ, f, secrets

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  before_each(function()
    secrets = {}
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    Stub.installScrollUtil()
    local files = {}
    for i, file in ipairs(H.UI_FILES) do files[i] = file end
    for _, file in ipairs({ "Core/Lookup.lua", "UI/Errors.lua", "UI/ChatSystem.lua", "UI/Speech.lua" }) do
      files[#files + 1] = file
    end
    WFJ = H.loadChunks(files)
    _G.ChatTypeInfo = { SYSTEM = { id = SYSTEM }, SAY = { id = PLAYER_SAY }, PARTY = { id = PARTY },
      MONSTER_SAY = { id = SAY } }
    f = chatFrame()
    _G.ChatFrame1 = f
    _G.CHAT_FRAMES = { "ChatFrame1" }
    _G.issecretvalue = function(v) return secrets[v] == true end
    _G.UnitName = function(unit) if unit == "player" then return "Thrall" end end -- a player named like a game name
    H.uiSetup(WFJ, UI)
    WFJ.Data.gossip = {}
    for en, row in pairs(GOSSIP) do WFJ.Data.gossip[KEY[en]] = { row[1], row[2] } end
    WFJ.Data.add("name", {
      [WFJ.Names.key("Aedis Brom")] = "エイディス・ブロム\tえいでぃす・ぶろむ",
      [WFJ.Names.key("Great War")] = "グレート・ウォー\tぐれーと・うぉー",
      [WFJ.Names.key("Thrall")] = "スロール\tすろーる",
      [WFJ.Names.key("Linen Cloth")] = "リネン・クロス\tりねん・くろす",
      [WFJ.Names.key("Frostbolt")] = "フロストボルト\tふろすとぼると",
      [WFJ.Names.key("Enchanting")] = "エンチャンティング\tえんちゃんてぃんぐ",
      [WFJ.Names.key("Enchant Weapon - Fiery Weapon")] = "エンチャント・ウェポン・ファイアリー・ウェポン\tえんちゃんと",
    })
    WFJ.State.setArea("gossip", true)
    WFJ.State.setNames(true)
    assert.is_true(WFJ.ChatSystem.init())
    local expand = function(ja) return (ja:gsub("{name}", "Thrall")) end
    assert.is_true(WFJ.Speech.init({ key = keyOf, expand = expand }))
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, n in ipairs(NAMES) do _G[n] = nil end
  end)

  it("an NPC's line shows the speaker's name and the names in its Japanese; the history keeps them", function()
    npc(f, "Never forget the Great War, Thrall.", "Aedis Brom")
    assert.are.equal("Aedis Bromの発言: Thrallよ、Great Warを忘れるな。", f.history[#f.history].message)
    -- the player's own name stays as written even though a game name shares it
    assert.are.equal("エイディス・ブロムの発言: Thrallよ、グレート・ウォーを忘れるな。", f:Refresh())
    alt(true)
    assert.are.equal("Aedis Brom says: Never forget the Great War, Thrall.", f.visibleLines[1]:GetText())
    alt(false)
    assert.are.equal("エイディス・ブロムの発言: Thrallよ、グレート・ウォーを忘れるな。", f.visibleLines[1]:GetText())
    WFJ.State.setNames(false)
    assert.are.equal("Aedis Bromの発言: Thrallよ、Great Warを忘れるな。", f.visibleLines[1]:GetText())
    WFJ.State.setNames(true)
    assert.are.equal("エイディス・ブロムの発言: Thrallよ、グレート・ウォーを忘れるな。", f.visibleLines[1]:GetText())
  end)

  it("an NPC's line with no Japanese of its own: only the speaker's name; the English names are left", function()
    npc(f, "Remember the Great War.", "Aedis Brom")
    assert.are.equal("エイディス・ブロムの発言: Remember the Great War.", f:Refresh())
  end)

  it("a speaker with no Japanese name keeps the name as written", function()
    npc(f, "Never forget the Great War, Thrall.", "Nobody Known")
    assert.are.equal("Nobody Knownの発言: Thrallよ、グレート・ウォーを忘れるな。", f:Refresh())
  end)

  it("a recipe link shows the skill and the recipe in Japanese; the player's own words stay", function()
    party(f, "WTS " .. RECIPE .. " 7g MY MATS", "Bob")
    assert.are.equal("[Bob]: WTS |cffffd000|Henchant:13898|h[エンチャンティング: エンチャント・ウェポン・ファイアリー・ウェポン]"
      .. "|h|r 7g MY MATS", f:Refresh())
    alt(true)
    assert.are.equal("[Bob]: WTS " .. RECIPE .. " 7g MY MATS", f.visibleLines[1]:GetText())
    alt(false)
    WFJ.State.setNames(false)
    assert.are.equal("[Bob]: WTS " .. RECIPE .. " 7g MY MATS", f.visibleLines[1]:GetText())
  end)

  it("an item and a spell link in a player's line show their labels in Japanese, the links as written", function()
    party(f, "need " .. ITEM .. " for " .. SPELL, "Bob")
    assert.are.equal("[Bob]: need |cff9d9d9d|Hitem:2589::::::::10:::::::|h[リネン・クロス]|h|r for "
      .. "|cff71d5ff|Hspell:116:0|h[フロストボルト]|h|r", f:Refresh())
    assert.are.equal("[Bob]: need " .. ITEM .. " for " .. SPELL, f.history[#f.history].message)
    alt(true)
    assert.are.equal("[Bob]: need " .. ITEM .. " for " .. SPELL, f.visibleLines[1]:GetText())
    alt(false)
    assert.are.equal("[Bob]: need |cff9d9d9d|Hitem:2589::::::::10:::::::|h[リネン・クロス]|h|r for "
      .. "|cff71d5ff|Hspell:116:0|h[フロストボルト]|h|r", f.visibleLines[1]:GetText())
    WFJ.State.setNames(false)
    assert.are.equal("[Bob]: need " .. ITEM .. " for " .. SPELL, f.visibleLines[1]:GetText())
  end)

  it("a quest link shows the quest's shipped Japanese title", function()
    local get = WFJ.Lookup.get
    WFJ.Lookup.get = function(kind, id)
      if kind == "quest.title" and id == 2 then return { ja = "Sharptalonの鉤爪", status = "." } end
      return get(kind, id)
    end
    party(f, "anyone on " .. QUEST .. "?", "Bob")
    assert.are.equal("[Bob]: anyone on |cffffff00|Hquest:2:10|h[Sharptalonの鉤爪]|h|r?", f:Refresh())
  end)

  it("a link a player typed (bars doubled), an unknown label and the items area off stay as written", function()
    local typed = "||Hitem:2589||h[Linen Cloth]||h"
    party(f, typed, "Bob")
    assert.are.equal("[Bob]: " .. typed, f:Refresh())
    party(f, "|Hitem:1::::::::10:::::::|h[Nobody Known Sword]|h", "Bob")
    assert.are.equal("[Bob]: |Hitem:1::::::::10:::::::|h[Nobody Known Sword]|h", f:Refresh())
    WFJ.State.setArea("items", false)
    party(f, ITEM, "Bob")
    assert.are.equal("[Bob]: " .. ITEM, f:Refresh())
  end)

  it("a secret line is never read", function()
    local text = "[Bob]: " .. ITEM
    secrets[text] = true
    f:AddMessage(text, 1, 1, 1, PARTY)
    assert.has_no.errors(function() f:Refresh() end)
    assert.are.equal(text, f.visibleLines[1]:GetText())
  end)
end)
