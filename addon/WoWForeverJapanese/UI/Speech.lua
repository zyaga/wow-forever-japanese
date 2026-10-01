-- UI/Speech.lua: what NPCs say, yell, whisper and emote (surface "speech", area "gossip", the NPC talk setting,
-- ADR-035 §10): in the chat window, in speech bubbles and, for boss emotes, in the middle of the screen. The
-- text is the server's (VMaNGOS broadcast_text, imported as gossip lines keyed by the hash of their English), found
-- by the same key the NPC talk window uses (Main's gossip key).
-- Writers [verified: Forever 1.60.1.69913]:
--   chat: ChatFrameMixin:MessageEventHandler formats CHAT_MSG_MONSTER_* / RAID_BOSS_* with a MessageFormatter
--     closure: format(CHAT_<TYPE>_GET .. message, pflag .. speaker, speaker), the message's `%s` left for the speaker's
--     name (blizzard_chatframebase/mainline/chatframeoverrides.lua:543–633), then self:AddMessage(line, r, g, b,
--     typeId, accessID, typeID, event, eventArgs, MessageFormatter) (:665–672). The post-hook on each chat frame's
--     AddMessage reads the server's English from eventArgs[1], and the line is rewritten in the history with
--     TransformMessages to MessageFormatter(<the Japanese>), Blizzard's own pattern for a changed line
--     (chatframeutil.lua:853–877). Alt / the switch: UI/ChatSystem's visible-line swap (the pair is remembered there).
--   bubbles: C_ChatBubbles.GetAllChatBubbles(false) (chatbubblesdocumentation.lua:11–24): a bubble's `.String`
--     (blizzard_chatbubble/chatbubbletemplates.xml:3–24) is looked for over the next frames after a say / yell and
--     rewritten with the bundled face. [unverified: bubble timing and wrap width; forbidden (instance) bubbles are
--     never touched]
--   boss emotes: RaidWarningFrame's OnEvent adds format(message, playerName, playerName) as the newest line
--     (blizzard_raidwarning/raidwarning.lua:83–119, 205–227); a HookScript OnEvent finds that FontString by its
--     messageOrder and sets the Japanese. Its layout is never re-run from here (it re-anchors Edit Mode frames).
-- Secret text (chat messaging lockdown: dungeons, raids, encounters; chatinfodocumentation.lua) is never touched: the
-- line stays English. A stale row, a missing one, or a `%s` count that differs leaves the English.
local _, WFJ = ...
local Speech = {}
WFJ.Speech = Speech

local SURFACE = "speech"
local AREA = "gossip" -- the NPC talk setting
Speech.SURFACE = SURFACE
local Compat = WFJ.Compat

Speech.NEVER_TOUCH = {}

local CANDIDATES = { frames = { "CHAT_FRAMES" }, typeInfo = { "ChatTypeInfo" }, bubbles = { "C_ChatBubbles" },
  raidWarning = { "RaidWarningFrame" }, openTemporary = { "FCF_OpenTemporaryWindow" }, isSecret = { "issecretvalue" },
  timer = { "C_Timer" } }

Speech.TYPES = { "MONSTER_SAY", "MONSTER_YELL", "MONSTER_WHISPER", "MONSTER_EMOTE", "MONSTER_PARTY",
  "RAID_BOSS_EMOTE", "RAID_BOSS_WHISPER" }
local BUBBLE_TYPES = { MONSTER_SAY = true, MONSTER_YELL = true, MONSTER_PARTY = true }
Speech.BUBBLE_SCANS, Speech.BUBBLE_INTERVAL = 8, 0.1 -- a bubble is looked for 8 times, 0.1 s apart

local deps = {}
local hooked = setmetatable({}, { __mode = "k" })
local ready = false

local function get(key) return Compat.get(SURFACE, key) end

local function secret(value)
  local isSecret = get("isSecret")
  return type(isSecret) == "function" and isSecret(value) and true or false
end

local ids -- { [chat type id] = type name }
local function typeIds()
  if ids then return ids end
  local info = get("typeInfo")
  if type(info) ~= "table" then return nil end
  ids = {}
  for _, name in ipairs(Speech.TYPES) do
    local t = info[name]
    if type(t) == "table" and t.id ~= nil then ids[t.id] = name end
  end
  return ids
end

local function count(s, pattern)
  local _, n = s:gsub(pattern, "")
  return n
end

-- The Japanese for the server's English (with its `%s`, before the speaker is filled in). → ja | nil
function Speech.translate(en)
  if type(en) ~= "string" or en == "" or not deps.key then return nil end
  local entry = WFJ.Lookup.keyed("gossip", deps.key(en))
  if type(entry) ~= "table" or entry.status ~= "." or type(entry.ja) ~= "string" or entry.ja == "" then return nil end
  local ja = deps.expand and deps.expand(entry.ja) or entry.ja
  if type(ja) ~= "string" or ja == "" or count(ja, "%%s") ~= count(en, "%%s") then return nil end
  return ja
end

-- The Japanese as a format() string: every `%` but the speaker's `%s` escaped.
local function escaped(ja)
  return (ja:gsub("%%", "%%%%"):gsub("%%%%s", "%%s"))
end

-- Bubbles waiting for their frame: { en, ja, frames left }.
local pending = {}
local bubbleText = setmetatable({}, { __mode = "k" }) -- fs → { en, ja }

-- The bubble's FontString is the client's, pooled and reused for later lines, so the bundled face goes on with
-- Font.bundle and comes off with Font.restore (its own font, remembered) whenever it shows English again.
local function setBubble(fs, rec)
  local english = not WFJ.ChatSystem.wanted(AREA)
  fs:SetText(english and rec.en or rec.ja)
  if english then WFJ.Font.restore(fs) else WFJ.Font.bundle(fs) end
end

-- A line shown in several chat tabs reaches AddMessage once per tab: one bubble is waited for.
local function queued(lineID)
  if lineID == nil then return false end
  for _, p in ipairs(pending) do
    if p.id == lineID then return true end
  end
  return false
end

-- One pass over the bubbles: a waiting line is put on the bubble showing its English. → bubbles set
function Speech.scanBubbles()
  local api = get("bubbles")
  if #pending == 0 then return 0 end
  if type(api) ~= "table" or type(api.GetAllChatBubbles) ~= "function" then
    pending = {}
    return 0
  end
  local n = 0
  for _, bubble in ipairs(api.GetAllChatBubbles(false) or {}) do
    if type(bubble) == "table" and not (type(bubble.IsForbidden) == "function" and bubble:IsForbidden()) then
      for _, child in ipairs({ type(bubble.GetChildren) == "function" and bubble:GetChildren() or nil }) do
        local fs = type(child) == "table" and child.String or nil
        local text = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
        if type(text) == "string" and not secret(text) then
          for i = #pending, 1, -1 do
            if pending[i].en == text then
              bubbleText[fs] = { en = pending[i].en, ja = pending[i].ja }
              setBubble(fs, bubbleText[fs])
              table.remove(pending, i)
              n = n + 1
              break
            end
          end
        end
      end
    end
  end
  for i = #pending, 1, -1 do
    pending[i].left = pending[i].left - 1
    if pending[i].left <= 0 then table.remove(pending, i) end
  end
  return n
end

-- The bubble scans run on a timer while a line waits for its bubble (the client makes it after the line).
local scanning = false
function Speech.scheduleScan()
  local timer = get("timer")
  if scanning or type(timer) ~= "table" or type(timer.After) ~= "function" then return end
  scanning = true
  local function tick()
    -- a pass that raises (an unexpected bubble) drops the waiting lines and never leaves the scan latched
    if not pcall(Speech.scanBubbles) then pending = {} end
    if #pending > 0 then timer.After(Speech.BUBBLE_INTERVAL, tick) else scanning = false end
  end
  timer.After(Speech.BUBBLE_INTERVAL, tick)
end

-- hooksecurefunc target (a chat frame's AddMessage). → 1 | 0
function Speech.onAddMessage(frame, line, _, _, _, typeId, _, _, _, eventArgs, formatter)
  local byId = typeIds()
  local name = byId and byId[typeId]
  if not name or type(frame) ~= "table" or type(line) ~= "string" or type(eventArgs) ~= "table"
      or type(formatter) ~= "function" or type(frame.TransformMessages) ~= "function" then
    return 0
  end
  local en, lineID = eventArgs[1], eventArgs[11]
  if type(en) ~= "string" or secret(en) or secret(line) or not WFJ.ChatSystem.on(AREA) then return 0 end
  local ja = Speech.translate(en)
  local jaLine = line
  if ja then
    local ok, formatted = pcall(formatter, escaped(ja))
    if ok and type(formatted) == "string" then jaLine = formatted else ja = nil end
  end
  -- the prefix's words ("%s says: ") too, also on a line with no Japanese of its own
  jaLine = WFJ.ChatSystem.prefixed(jaLine, name) or jaLine
  if jaLine == line then return 0 end
  if not WFJ.ChatSystem.remember(jaLine, line, AREA) then return 0 end
  frame:TransformMessages(function(text, _, _, _, lineType, _, _, _, args)
    return lineType == typeId and type(args) == "table" and not secret(args[11]) and args[11] == lineID
      and not secret(text) and text == line
  end, function(_, ...)
    return jaLine, ...
  end)
  if ja and BUBBLE_TYPES[name] and count(en, "%%s") == 0 and not queued(lineID) then
    pending[#pending + 1] = { en = en, ja = ja, id = lineID, left = Speech.BUBBLE_SCANS }
    Speech.scheduleScan()
  end
  return 1
end

-- HookScript target (RaidWarningFrame OnEvent): a boss emote / whisper in the middle of the screen. → 1 | 0
local warnText = setmetatable({}, { __mode = "k" }) -- fs → { en, ja }
function Speech.onRaidWarning(frame, event, message, playerName)
  if (event ~= "RAID_BOSS_EMOTE" and event ~= "RAID_BOSS_WHISPER") or type(frame) ~= "table"
      or type(message) ~= "string" or secret(message) or not WFJ.ChatSystem.on(AREA) then
    return 0
  end
  local ja = Speech.translate(message)
  local pool = frame.fontStringPool
  if not ja or type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local ok, jaBody = pcall(string.format, escaped(ja), playerName, playerName)
  local okEn, enBody = pcall(string.format, message, playerName, playerName)
  if not ok or not okEn then return 0 end
  for fs in pool:EnumerateActive() do
    if fs.messageOrder == frame.messageCounter and fs:GetText() == enBody then
      warnText[fs] = { en = enBody, ja = jaBody }
      setBubble(fs, warnText[fs])
      return 1
    end
  end
  return 0
end

-- The modifier / the switch changed: the bubbles and the boss emote lines still showing our text follow.
function Speech.refresh()
  for _, map in ipairs({ bubbleText, warnText }) do
    for fs, rec in pairs(map) do
      local text = fs:GetText()
      if secret(text) then
        map[fs] = nil
        WFJ.Font.restore(fs)
      elseif text == rec.en or text == rec.ja then
        setBubble(fs, rec)
      else
        map[fs] = nil
        WFJ.Font.restore(fs) -- the pooled string shows another line now
      end
    end
  end
end

local function hookFrame(frame)
  if hooked[frame] or type(frame.AddMessage) ~= "function" then return 0 end
  hooked[frame] = true
  hooksecurefunc(frame, "AddMessage", Speech.onAddMessage)
  return 1
end

function Speech.hookAll()
  local n = 0
  local names = get("frames")
  for _, name in ipairs(type(names) == "table" and names or {}) do
    local frame = Compat.resolve(name)
    if type(frame) == "table" then n = n + hookFrame(frame) end
  end
  return n
end

-- deps: { key = function(text) → gossip key, expand = function(ja) → ja } (Main's, as UI/Gossip gets them)
function Speech.init(d)
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if ready then return false end
  deps = d or {}
  -- the chat side's Alt / switch and fonts are UI/ChatSystem's: without it a rewritten line could not go back
  if type(get("frames")) ~= "table" or not typeIds() or type(deps.key) ~= "function"
      or not WFJ.ChatSystem.isReady() then
    return false
  end
  ready = true
  Speech.hookAll()
  if type(get("openTemporary")) == "function" then hooksecurefunc("FCF_OpenTemporaryWindow", Speech.hookAll) end
  local warn = get("raidWarning")
  if type(warn) == "table" and type(warn.HookScript) == "function" then
    warn:HookScript("OnEvent", Speech.onRaidWarning)
  end
  return true
end

WFJ.State.on("enabled", Speech.refresh)
WFJ.State.on("area", Speech.refresh)
WFJ.State.on("modifier", Speech.refresh)
