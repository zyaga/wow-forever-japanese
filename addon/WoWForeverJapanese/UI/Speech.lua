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

-- The Japanese for the server's English (with its `%s`, before the speaker is filled in). key: its gossip key when
-- the caller already has it. → ja | nil
function Speech.translate(en, key)
  if type(en) ~= "string" or en == "" or not deps.key then return nil end
  local entry = WFJ.Lookup.keyed("gossip", key or deps.key(en))
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
-- true for no language ("" or nil) or one of this character's languages; a secret, or no way to list them, → false
function Speech.knownLanguage(language)
  if language == nil or (not secret(language) and language == "") then return true end
  if secret(language) then return false end
  local numLanguages, byIndex = Compat.resolve("GetNumLanguages"), Compat.resolve("GetLanguageByIndex")
  if type(numLanguages) ~= "function" or type(byIndex) ~= "function" then return false end
  for i = 1, numLanguages() or 0 do
    if byIndex(i) == language then return true end
  end
  return false
end

-- A speech line that ships Japanese but is left English says why in the problem log (docs/systems/diagnostics.md),
-- so a report names its cause from the log alone: the reason, the event, the chat frame and the line's gossip key,
-- never the line's text or a name. A line whose English cannot be read is logged without a key. One entry per
-- reason per session (Diag counts the repeats).
local function speechEvent(event)
  return type(event) == "string" and not secret(event)
    and (event:find("^CHAT_MSG_MONSTER") or event:find("^CHAT_MSG_RAID_BOSS")) and true or false
end

-- a secret is never compared: comparing one raises
local function readable(en) return type(en) == "string" and not secret(en) and en ~= "" end

local function shipped(key)
  local entry = WFJ.Lookup.keyed("gossip", key)
  return type(entry) == "table" and entry.status == "." and type(entry.ja) == "string" and entry.ja ~= ""
end

local lastReason, lastJa -- the current line's exit reason and whether its own Japanese went in, for Speech.trace

local function why(reason, frame, event, en, key) -- → 0
  lastReason = lastReason or reason
  if not speechEvent(event) or not WFJ.Diag then return 0 end
  if readable(en) then
    key = key or (deps.key and deps.key(en))
    if key == nil or not shipped(key) then return 0 end
  end
  WFJ.Diag.log("speech", reason, { event = event, frame = WFJ.Diag.nameOf(frame), key = key })
  return 0
end

local function handle(frame, line, typeId, event, eventArgs, formatter)
  local en = type(eventArgs) == "table" and eventArgs[1] or nil
  local byId = typeIds()
  local name = byId and byId[typeId]
  if not name then return why("unknown chat type", frame, event, en) end
  if type(frame) ~= "table" or type(line) ~= "string" then return why("no line", frame, event, en) end
  if type(eventArgs) ~= "table" then return why("no eventArgs", frame, event, en) end
  if type(formatter) ~= "function" then return why("no formatter", frame, event, en) end
  if type(frame.TransformMessages) ~= "function" then return why("no TransformMessages", frame, event, en) end
  local lineID = eventArgs[11]
  if type(en) ~= "string" then return why("no English", frame, event, en) end
  if secret(en) or secret(line) then return why("secret text", frame, event, en) end
  -- what the NPC said goes to the Collector like a gossip line, keyed the same way, with the speaker's creature
  -- id from the event's GUID (eventArgs[12]); NPC speech is in no client file, so playing is how it is found. A
  -- line the NPC says to another player (eventArgs[5], the target) may hold that player's name, which would end
  -- up in public data: only lines to no one or to this player are recorded.
  -- A line in a language this character does not know (eventArgs[3], shown as "[Orcish] …") arrives scrambled,
  -- so only lines in no language or a known one are recorded [verified: chatframeoverrides.lua:581, the language
  -- header; chatframemenubutton.lua:120, the known languages].
  local guid, target, language = eventArgs[12], eventArgs[5], eventArgs[3]
  local me = Compat.resolve("UnitName")
  me = type(me) == "function" and me("player") or nil
  local toOther = type(target) == "string" and target ~= "" and not secret(target) and target ~= me
  if WFJ.Collector and not secret(guid) and not secret(target) and not toOther and Speech.knownLanguage(language) then
    WFJ.Collector.recordGossip(en, guid)
  end
  local key = en ~= "" and deps.key and deps.key(en) or nil -- once per line: translate and every later exit use it
  if not WFJ.ChatSystem.on(AREA) then return why("NPC talk off", frame, event, en, key) end
  local ja = Speech.translate(en, key)
  local jaLine = line
  lastJa = ja ~= nil
  if ja then
    local ok, formatted = pcall(formatter, escaped(ja))
    if ok and type(formatted) == "string" then
      jaLine = formatted
    else
      ja, lastJa = nil, false
      why("formatter error", frame, event, en, key)
    end
  else
    why("translation refused", frame, event, en, key) -- logged only when the line ships Japanese
  end
  -- the prefix's words ("%s says: ") too, also on a line with no Japanese of its own
  jaLine = WFJ.ChatSystem.prefixed(jaLine, name) or jaLine
  if jaLine == line then return why("line unchanged", frame, event, en, key) end
  if not WFJ.ChatSystem.remember(jaLine, line, AREA) then return why("remember refused", frame, event, en, key) end
  local matched = 0 -- the history is filtered synchronously [verified: scrollingmessageframe.lua:95–107]
  frame:TransformMessages(function(text, _, _, _, lineType, _, _, _, args)
    local hit = lineType == typeId and type(args) == "table" and not secret(args[11]) and args[11] == lineID
      and not secret(text) and text == line
    if hit then matched = matched + 1 end
    return hit
  end, function(_, ...)
    return jaLine, ...
  end)
  if matched == 0 then why("no line matched", frame, event, en, key) end
  if ja and BUBBLE_TYPES[name] and count(en, "%%s") == 0 and not queued(lineID) then
    pending[#pending + 1] = { en = en, ja = ja, id = lineID, left = Speech.BUBBLE_SCANS }
    Speech.scheduleScan()
  end
  return 1
end

-- Every NPC line is traced, translated or not, so one sighting in play names why a line stayed English without a
-- rerun: one "speechline" entry per outcome and key per session (Diag counts the repeats). It holds hashes and
-- flags only, never the text or the speaker's name: whether the English still has the speaker's `%s`, whether the
-- speaker's name is written into it, and the key the line would have with that name put back as `%s`.
local function keyShipped(key) return key ~= nil and shipped(key) or false end

function Speech.trace(frame, event, eventArgs, outcome)
  if not speechEvent(event) or not WFJ.Diag then return end
  local en = type(eventArgs) == "table" and eventArgs[1] or nil
  local fields = { event = event, frame = WFJ.Diag.nameOf(frame), translated = lastJa == true }
  local key
  if readable(en) then
    key = deps.key and deps.key(en) or nil
    fields.key, fields.shipped, fields.hasToken = key, keyShipped(key), en:find("%s", 1, true) ~= nil
    local speaker = eventArgs[2]
    if type(speaker) == "string" and not secret(speaker) and speaker ~= "" then
      local at = en:find(speaker, 1, true)
      fields.speakerInText = at ~= nil
      if at then
        local parts, from = {}, 1
        while at do
          parts[#parts + 1] = en:sub(from, at - 1)
          from = at + #speaker
          at = en:find(speaker, from, true)
        end
        parts[#parts + 1] = en:sub(from)
        local swapped = deps.key and deps.key(table.concat(parts, "%s")) or nil
        fields.speakerKey, fields.speakerKeyShipped = swapped, keyShipped(swapped)
      end
    else
      fields.speakerInText = type(speaker) == "string" and secret(speaker) and "secret" or "none"
    end
  else
    fields.english = en == nil and "none" or (secret(en) and "secret" or type(en))
  end
  WFJ.Diag.log("speechline", tostring(outcome) .. " " .. tostring(key or "-"), fields)
end

function Speech.onAddMessage(frame, line, _, _, _, typeId, _, _, event, eventArgs, formatter)
  lastReason, lastJa = nil, nil
  local result = handle(frame, line, typeId, event, eventArgs, formatter)
  pcall(Speech.trace, frame, event, eventArgs, lastReason or (lastJa and "translated" or "changed"))
  return result
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
  WFJ.Diag.watch(frame, "AddMessage", WFJ.Diag.nameOf(frame))
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
