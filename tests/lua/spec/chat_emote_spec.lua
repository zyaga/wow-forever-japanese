-- emote chat lines: UI/ChatSystem.lua on a CHAT_MSG_TEXT_EMOTE line, the client's
-- EmotesTextData text with the sender's name turned into a player link (blizzard_chatframebase/mainline/
-- chatframeoverrides.lua:635–644) and a timestamp in front when the player turned them on (:661–664). The rows are
-- slotted fingerprint rows (EmoteText:<id>): matched by putting the names back, never by shipped English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  ["EmoteText:1"] = { "%s waves at %s.", "%sは%sに手を振った。" },
  ["EmoteText:2"] = { "%s waves at you.", "%sがあなたに手を振った。" },
  ["EmoteText:3"] = { "You wave at %s.", "あなたは%sに手を振った。" },
  ["EmoteText:5"] = { "You wave.", "あなたは手を振った。" },
  ["EmoteText:34"] = { "%s beckons %s over.", "%2$sを%1$sが手招きした。" }, -- the Japanese puts the names the other way
  ["EmoteText:29"] = { "%s is so bashful...too bashful to get %s's attention.",
    "%sは恥ずかしくて%sの気を引けない。" },
  ["EmoteText:19"] = { "%s apologizes to %s.  Sorry!", "%sは%sに謝った。ごめんなさい！" },
}
local NAMES = { "CHAT_FRAMES", "ChatTypeInfo", "ChatFrame1", "issecretvalue", "UnitName", "Ambiguate" }
local SYSTEM, EMOTE = 1, 5

local function chatFrame()
  local frame = { history = {}, visibleLines = { Stub.fontString("") }, callbacks = {},
    fontObject = { font = { path = "Fonts\\ARIALN.TTF", size = 14, flags = "" } } }
  function frame:AddMessage(message, r, g, b, ...)
    self.history[#self.history + 1] = { message = message, r = r, g = g, b = b, extra = { ... } }
  end
  function frame:TransformMessages(predicate, transform)
    for i, e in ipairs(self.history) do
      if predicate(e.message, e.r, e.g, e.b, unpack(e.extra)) then
        local message = transform(e.message, e.r, e.g, e.b, unpack(e.extra))
        self.history[i] = { message = message, r = e.r, g = e.g, b = e.b, extra = e.extra }
      end
    end
  end
  function frame:GetNumMessages() return #self.history end
  function frame:GetMessageInfo(i) local e = self.history[#self.history - i + 1]; return e and e.message end
  function frame:GetFontObject() return self.fontObject end
  function frame:AddOnDisplayRefreshedCallback(cb) self.callbacks[#self.callbacks + 1] = cb end
  function frame:Refresh()
    local e = self.history[#self.history]
    local line = self.visibleLines[1]
    line.messageInfo = e
    line:SetFontObject(self.fontObject)
    line:SetText(e and e.message or "")
    for _, cb in ipairs(self.callbacks) do cb(self) end
  end
  function frame:Last() return self.history[#self.history].message end
  return frame
end

local secrets, target, lineID = {}, nil, 0
local function install()
  _G.ChatTypeInfo = { SYSTEM = { id = SYSTEM, r = 1, g = 1, b = 0 },
    TEXT_EMOTE = { id = EMOTE, r = 1, g = 0.5, b = 0.25 } }
  _G.ChatFrame1 = chatFrame()
  _G.CHAT_FRAMES = { "ChatFrame1" }
  _G.issecretvalue = function(v) return secrets[v] == true end
  _G.UnitName = function(unit)
    if unit == "player" then return "Me" end
    if unit == "target" then return target end
  end
  _G.Ambiguate = function(name) return (name:gsub("%-.*$", "")) end
end

local function link(name) return "|Hplayer:" .. name .. "-Realm:" .. name .. ":TEXT_EMOTE|h" .. name .. "|h" end

-- The chat frame's AddMessage for a TEXT_EMOTE line: AddMessage(msg, r, g, b, info.id, accessID, typeID, event,
-- eventArgs): eventArgs[2] the sender (arg2), [11] the line id.
local function emote(message, sender)
  lineID = lineID + 1
  local args = { message, sender .. "-Realm" }
  args[11] = lineID
  _G.ChatFrame1:AddMessage(message, 1, 0.5, 0.25, EMOTE, 1, 1, "CHAT_MSG_TEXT_EMOTE", args)
end

describe("emote chat lines", function()
  local WFJ
  before_each(function()
    secrets, target = {}, nil
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    Stub.installScrollUtil()
    local files = {}
    for i, f in ipairs(H.UI_FILES) do files[i] = f end
    files[#files + 1] = "UI/Errors.lua"
    files[#files + 1] = "UI/ChatSystem.lua"
    WFJ = H.loadChunks(files)
    install()
    H.uiSetup(WFJ, UI)
    assert.is_true(WFJ.ChatSystem.init())
  end)
  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, n in ipairs(NAMES) do _G[n] = nil end
  end)

  it("another player's emote at you: the sender's link is kept in the Japanese", function()
    emote(link("Bob") .. " waves at you.", "Bob")
    assert.are.equal(link("Bob") .. "があなたに手を振った。", _G.ChatFrame1:Last())
  end)

  it("your own emote at your target, and at a name the addon cannot know", function()
    target = "Alice"
    emote("You wave at Alice.", "Me")
    assert.are.equal("あなたはAliceに手を振った。", _G.ChatFrame1:Last())
    target = nil
    emote("You wave at Stormwind City Guard.", "Me") -- a creature: a run of words is tried as the name
    assert.are.equal("あなたはStormwind City Guardに手を振った。", _G.ChatFrame1:Last())
  end)

  it("a third player's emote at someone: the sender known, the other name found", function()
    emote(link("Bob") .. " waves at Alice.", "Bob")
    assert.are.equal(link("Bob") .. "はAliceに手を振った。", _G.ChatFrame1:Last())
  end)

  it("a line with no name, a positional Japanese, a possessive and a double space", function()
    emote("You wave.", "Me")
    assert.are.equal("あなたは手を振った。", _G.ChatFrame1:Last())
    emote(link("Bob") .. " beckons Alice over.", "Bob")
    assert.are.equal("Aliceを" .. link("Bob") .. "が手招きした。", _G.ChatFrame1:Last())
    emote(link("Bob") .. " is so bashful...too bashful to get Alice's attention.", "Bob")
    assert.are.equal(link("Bob") .. "は恥ずかしくてAliceの気を引けない。", _G.ChatFrame1:Last())
    emote(link("Bob") .. " apologizes to Alice.  Sorry!", "Bob")
    assert.are.equal(link("Bob") .. "はAliceに謝った。ごめんなさい！", _G.ChatFrame1:Last())
  end)

  it("a timestamp in front is kept; a name that starts like AM / PM is not taken for one", function()
    emote("12:34 You wave.", "Me")
    assert.are.equal("12:34 あなたは手を振った。", _G.ChatFrame1:Last())
    emote("[12:34:56] You wave.", "Me")
    assert.are.equal("[12:34:56] あなたは手を振った。", _G.ChatFrame1:Last())
    assert.are.same({ "12:34 ", "Mad waves." }, { WFJ.ChatSystem.splitStamp("12:34 Mad waves.") })
    assert.are.same({ "12:34 PM ", "You wave." }, { WFJ.ChatSystem.splitStamp("12:34 PM You wave.") })
    assert.are.same({ "", "You wave." }, { WFJ.ChatSystem.splitStamp("You wave.") })
  end)

  it("a line no row matches, a secret line and a SYSTEM line with emote text stay as written", function()
    emote(link("Bob") .. " dances with Alice.", "Bob")
    assert.are.equal(link("Bob") .. " dances with Alice.", _G.ChatFrame1:Last())
    secrets["You wave."] = true
    emote("You wave.", "Me")
    assert.are.equal("You wave.", _G.ChatFrame1:Last())
    secrets = {}
    _G.ChatFrame1:AddMessage("You wave.", 1, 1, 0, SYSTEM) -- not an emote line: plain lines take exact English only
    assert.are.equal("You wave.", _G.ChatFrame1:Last())
  end)

  it("Alt shows the English on the visible line, releasing puts the Japanese back", function()
    emote("You wave.", "Me")
    local f = _G.ChatFrame1
    f:Refresh()
    assert.are.equal("あなたは手を振った。", f.visibleLines[1]:GetText())
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal("You wave.", f.visibleLines[1]:GetText())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    assert.are.equal("あなたは手を振った。", f.visibleLines[1]:GetText())
  end)
end)
