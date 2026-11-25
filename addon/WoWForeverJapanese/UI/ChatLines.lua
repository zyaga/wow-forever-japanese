-- UI/ChatLines.lua: which chat line the mouse is on (docs/systems/chat-tools.md). Nothing is hooked and no chat
-- line is changed: while a listener wants it, a timer finds the visible, readable line under the mouse and tells
-- the listeners (UI/ChatCards for the word card, UI/ChatCopy for the copy icon). It never names a line that has
-- faded out or whose text the client keeps secret (chat messaging lockdown). It also knows which lines a player
-- typed, for the tools that want only the message.
--   ChatLines.onLine(fn)             fn(frame, line, text) for the line under the mouse, fn(nil) when there is none
--   ChatLines.look()                 one look at the mouse (the timer's step; specs call it)
--   ChatLines.typedPart(line, text)  → what a player typed in that line | nil (not a typed line, or not shaped so)
--   ChatLines.secret(value)          → true when the client keeps the value from addons
--   ChatLines.TYPED                  the chat types a player types into
local _, WFJ = ...
local Lines = {}
WFJ.ChatLines = Lines

local Compat = WFJ.Compat
local SURFACE = "chat.lines"
local CANDIDATES = { frames = { "CHAT_FRAMES" }, typeInfo = { "ChatTypeInfo" }, isSecret = { "issecretvalue" } }
-- declared when the file loads, not at init: the other chat tools ask ChatLines.secret before they read a line, and
-- that answer must not wait on this module's start
for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end

Lines.EVERY = 0.04 -- seconds between looks
Lines.FADED = 0.2 -- a line fainter than this has faded out: nothing on text the player cannot see

-- The chat types a player types into: the lines whose text is a player's own, and the chat events the phrase book
-- listens on (UI/ChatPhraseLines). A numbered channel has a type of its own (CHANNEL1 … CHANNEL<CHANNELS>).
Lines.TYPED = { "SAY", "YELL", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "GUILD", "OFFICER",
  "WHISPER", "WHISPER_INFORM", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "BN_WHISPER", "BN_WHISPER_INFORM",
  "COMMUNITIES_CHANNEL", "CHANNEL" }
Lines.CHANNELS = 20

local listeners = {}
local told = false -- the listeners were last told of a line (so "no line" is said once, not every look)

function Lines.secret(value)
  local f = Compat.get(SURFACE, "isSecret")
  return type(f) == "function" and f(value) and true or false
end
local secret = Lines.secret

function Lines.onLine(fn) listeners[#listeners + 1] = fn end

-- ── Which lines a player typed ──────────────────────────────────────────────

local typedIds
local function typedLine(line)
  local info = line.messageInfo
  -- the chat type is the first value the chat frame stores with a line [verified: forever
  -- blizzard_chatframebase/mainline/chatframeoverrides.lua:416, AddMessage(text, r, g, b, info.id)]
  local id = type(info) == "table" and type(info.extraData) == "table" and info.extraData[1] or nil
  local types = Compat.get(SURFACE, "typeInfo")
  if id == nil or secret(id) or type(types) ~= "table" then return false end
  if not typedIds then
    -- read by name: walking the client's table of chat types finds no entries on this client
    typedIds = {}
    local function note(name)
      local t = types[name]
      if type(t) == "table" and t.id ~= nil then typedIds[t.id] = true end
    end
    for _, name in ipairs(Lines.TYPED) do note(name) end
    for i = 1, Lines.CHANNELS do note("CHANNEL" .. i) end
  end
  return typedIds[id] == true
end

function Lines.typedPart(line, text)
  if type(line) ~= "table" or not typedLine(line) then return nil end
  return WFJ.ChatWords.typedPart(text)
end

-- ── The look ───────────────────────────────────────────────────────────────

local function readable(line)
  if not (line:IsVisible() and line:GetAlpha() > Lines.FADED and line:IsMouseOver()) then return nil end
  local text = line:GetText()
  if type(text) == "string" and not secret(text) and text ~= "" then return text end
  return nil
end

-- The readable chat line under the mouse. → frame, line, text | nil
local function lineUnderMouse()
  local names = Compat.get(SURFACE, "frames")
  if type(names) ~= "table" then return nil end
  for _, name in ipairs(names) do
    local f = Compat.resolve(name)
    if type(f) == "table" and type(f.visibleLines) == "table" and f:IsVisible() and f:IsMouseOver() then
      for _, line in ipairs(f.visibleLines) do
        local text = readable(line)
        if text then return f, line, text end
      end
    end
  end
  return nil
end

function Lines.look()
  local frame, line, text = lineUnderMouse()
  if not line and not told then return nil end
  told = line ~= nil
  for _, fn in ipairs(listeners) do fn(frame, line, text) end
  return line
end

-- The timer runs only while the chat tools that follow the mouse can show anything.
local function wanted()
  if not WFJ.State.enabled then return false end
  return WFJ.Settings.get("chat.cards") == true or WFJ.Settings.get("chat.copy") == true
end

local function follow()
  local on = wanted()
  if Lines.driver then
    if on then Lines.driver:Show() else Lines.driver:Hide() end
  end
  -- going quiet: the listeners take down what they show
  if not on and told then
    told = false
    for _, fn in ipairs(listeners) do fn(nil) end
  end
end

function Lines.init()
  if Lines.driver then return false end
  Lines.driver = CreateFrame("Frame")
  local since = 0
  Lines.driver:SetScript("OnUpdate", function(_, elapsed) -- a hidden frame gets no updates
    since = since + elapsed
    if since < Lines.EVERY then return end
    since = 0
    Lines.look()
  end)
  WFJ.State.on("chat", follow)
  WFJ.State.on("enabled", follow)
  follow()
  return true
end
