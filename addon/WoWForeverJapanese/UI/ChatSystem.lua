-- UI/ChatSystem.lua: the game's own chat lines (surface "chatsystem", area "ui", ADR-035 §7–§9; emote lines
-- ADR-042): every plain chat type (SYSTEM, loot, money, currency, XP, honor, reputation, skill, tradeskill,
-- opening, achievements … PLAIN_TYPES), such as "Your party is full.", "You are now Away: AFK", "You receive loot:
-- %s.", and the prefix words of a player's say / yell / whisper / AFK / DND / raid warning / channel join-leave
-- line (ChatSystem.prefixed; the player's own text is never touched). UI/Speech remembers its NPC lines here too
-- (remember / wanted by area).
-- Writers [verified: Forever 1.60.1.69913]: ChatFrameMixin:MessageEventHandler adds a CHAT_MSG_SYSTEM (and SKILL,
--   CURRENCY, …) line as self:AddMessage(arg1, info.r, info.g, info.b, info.id) (blizzard_chatframebase/mainline/
--   chatframeoverrides.lua:395–400), after the whisper-window routing that compares arg1 with the English of
--   ERR_CHAT_PLAYER_NOT_FOUND_S / ERR_FRIEND_ONLINE_SS / ERR_FRIEND_OFFLINE_S (:377–394) and after the message filters
--   (Blizzard's battleground roll-up matches English, battlegroundchatfilters.lua). Blizzard's Lua adds its own with
--   ChatFrameUtil.AddSystemMessage / DisplaySystemMessage*: the same call with ChatTypeInfo.SYSTEM.id
--   (chatframeutil.lua:297–315). Each chat frame's AddMessage is post-hooked on the instance, so all of that has
--   already read the English: no key has to be held back.
-- The line is then rewritten in that frame's history with TransformMessages, a secure-elevation wrapper whose addon
-- callbacks run tainted (blizzard_sharedxml/scrollingmessageframe.lua:95–107, 795–824; Blizzard does the same,
-- itemrefhandlersshared.lua:217). Only a line of a PLAIN_TYPES chat type id is considered, never a secret one (chat
-- messaging lockdown makes CHAT_MSG_SYSTEM text secret, chatinfodocumentation.lua:2455); it takes an exact dictionary
-- English (one English is one Japanese; also the non-error lines Blizzard's Lua prints, e.g. the guild-rename
-- refusal) or a chat key's template, matched by key only: a listed error key with text of its own (UI/Errors' wrapper
-- set), a key of UIStrings.CHAT_FAMILIES, or EXTRA_TEMPLATES; never any other template. A stale row or a failed fill
-- leaves the English.
-- Alt / the switch: the history is rewritten once, when the line arrives, and never again; a
-- rewrite repackages the entry with a new timestamp (PackageEntry, scrollingmessageframe.lua:737–745), which would
-- bring every faded line back. Holding the modifier, or switching the addon / its UI area off, instead puts the
-- remembered English on the VISIBLE lines (and the frame's own font back), and each display refresh keeps doing so
-- while it lasts; releasing puts the Japanese back. A line that arrives while the addon or the UI area is off is left
-- English for good. One Japanese is remembered with one English: a line whose Japanese another English already has
-- stays English (so Alt never shows English the client did not write there), and past MAX_REMEMBERED pairs new lines
-- stay English (a pair still in some history is never forgotten).
-- Font: the chat fonts have no Japanese member, so the bundled face is put on every visible line showing one of our
-- Japanese strings from the frame's AddOnDisplayRefreshedCallback (:164–175) with SetFont directly (a deferred font
-- retry would land on a pooled English line; in game), shrunk until it fits the line's laid-out height (fit). The
-- visible lines are fixed rows the messages move through, and the refresh's re-init (SetFontObject with the frame's
-- own object, scrollingmessageframe.lua:642, 716) does not undo our SetFont (in game: every row a Japanese line had
-- passed showed later English in the bundled face). So each row given the bundled face is remembered (Font.bundle)
-- and given the frame's font back directly (Font.restore) once it shows anything else.
local _, WFJ = ...
local ChatSystem = {}
WFJ.ChatSystem = ChatSystem

local SURFACE = "chatsystem"
ChatSystem.SURFACE = SURFACE
local Compat = WFJ.Compat

ChatSystem.NEVER_TOUCH = {}

local CANDIDATES = { frames = { "CHAT_FRAMES" }, typeInfo = { "ChatTypeInfo" },
  openTemporary = { "FCF_OpenTemporaryWindow" }, isSecret = { "issecretvalue" },
  unitName = { "UnitName" }, ambiguate = { "Ambiguate" } }

ChatSystem.MAX_REMEMBERED = 4096 -- distinct Japanese ↔ English pairs held at once; past it, new lines stay English
ChatSystem.SWEEP_EVERY = 256 -- a sweep that freed nothing is retried after this many refused lines
local jaToEn, jaArea, remembered, refused = {}, {}, 0, 0
local hooked = setmetatable({}, { __mode = "k" })
local ready = false

local function secret(value)
  local isSecret = Compat.get(SURFACE, "isSecret")
  return type(isSecret) == "function" and isSecret(value) and true or false
end

-- All system chat: the chat types the event handler adds as the bare text, no sender
-- prefix: self:AddMessage(arg1, info.r, info.g, info.b, info.id) (chatframeoverrides.lua:397–413): system, loot,
-- money, currency, XP / honor / reputation, skill, tradeskill, opening, pet info, target icons, battleground system,
-- achievements (already formatted with the player's link).
ChatSystem.PLAIN_TYPES = { "SYSTEM", "SKILL", "CURRENCY", "MONEY", "OPENING", "TRADESKILLS", "PET_INFO",
  "TARGETICONS", "BN_WHISPER_PLAYER_OFFLINE", "COLLECTED_APPEARANCE", "LOOT", "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN",
  "COMBAT_FACTION_CHANGE", "COMBAT_MISC_INFO", "BG_SYSTEM_NEUTRAL", "BG_SYSTEM_ALLIANCE", "BG_SYSTEM_HORDE",
  "ACHIEVEMENT", "GUILD_ACHIEVEMENT" }
-- System chat lines outside the UIStrings.CHAT_FAMILIES a SYSTEM line may be (Lua-built: chatframeutil.lua:251–263,
-- the GMOTD, the community channel notices); key-only through UIStrings.ONLY.
-- The voice channel's announce line (channelframe.lua:502–513, DisplaySystemMessageInPrimary): the
-- voiceParts form: its three sentences each an entry, the atlas kept.
ChatSystem.EXTRA_TEMPLATES = { "GUILD_MOTD_TEMPLATE", "TIME_PLAYED_TOTAL", "TIME_PLAYED_LEVEL",
  "COMMUNITIES_CHANNEL_ADDED_TO_CHAT_WINDOW", "COMMUNITIES_CHANNEL_REMOVED_FROM_CHAT_WINDOW",
  "VOICE_CHAT_CHANNEL_ANNOUNCE" }

-- → the set of plain chat type ids | nil (ChatTypeInfo[type].id is set at load, chattypeinfocolors.lua:12, 21)
local plainIds
local function plainTypeIds()
  if plainIds then return plainIds end
  local info = Compat.get(SURFACE, "typeInfo")
  if type(info) ~= "table" or type(info.SYSTEM) ~= "table" or info.SYSTEM.id == nil then return nil end
  plainIds = {}
  for _, name in ipairs(ChatSystem.PLAIN_TYPES) do
    local t = info[name]
    if type(t) == "table" and t.id ~= nil then plainIds[t.id] = true end
  end
  return plainIds
end

-- The keys a chat line's template may be: the errors surface's wrapper set, the chat families, the extras.
local chatSet, chatIndex
local function chatKeys(index)
  if chatIndex ~= index then
    chatSet, chatIndex = {}, index
    for key in pairs(WFJ.Errors.errorKeys(index)) do chatSet[key] = true end
    for key in pairs(index.rows or {}) do
      if WFJ.UIStrings.isChatKey(key) then chatSet[key] = true end
    end
    for _, key in ipairs(ChatSystem.EXTRA_TEMPLATES) do chatSet[key] = true end
  end
  return chatSet
end

-- The server's own notices ("[SERVER] Shutdown in 15 Minutes"): ServerMessages rows the client prints as system lines.
local serverSet, serverIndex
local function serverKeys(index)
  if serverIndex ~= index then
    serverSet, serverIndex = WFJ.UIStrings.familyKeys(index.rows, "ServerMessage"), index
  end
  return serverSet
end

-- A reputation line (COMBAT_FACTION_CHANGE) may also be a FriendshipGain row ("You gain 25 Rank Points.",
-- FriendshipReputation's StandingModified text, the number filled in by the client: UIStrings index:matchCounted). The
-- family is named for that chat type only, so no other line is ever taken for one.
local factionSet, factionIndex
local function factionKeys(index)
  if factionIndex ~= index then
    factionSet, factionIndex = {}, index
    for key in pairs(chatKeys(index)) do factionSet[key] = true end
    for key in pairs(WFJ.UIStrings.familyKeys(index.rows, "FriendshipGain")) do factionSet[key] = true end
  end
  return factionSet
end

local factionId
local function factionTypeId()
  if factionId == nil then
    local info = Compat.get(SURFACE, "typeInfo")
    local t = type(info) == "table" and info.COMBAT_FACTION_CHANGE or nil
    factionId = type(t) == "table" and t.id or false
  end
  return factionId or nil
end

-- `area`: the settings area a line belongs to: "ui" (system lines), "gossip" (NPC speech, UI/Speech)
local function on(area)
  return WFJ.State.enabled and WFJ.State.areaEnabled(area or "ui")
end
ChatSystem.on = on

local function wanted(area)
  return on(area) and not WFJ.Modifier.isDown()
end
ChatSystem.wanted = wanted

-- The pairs no chat frame's history still holds are forgotten (loot, XP, player and NPC lines are
-- mostly unique, so a session fills the limit; a pair still in some history is never forgotten; Alt needs it).
-- GetNumMessages / GetMessageInfo (scrollingmessageframe.lua:26–35). → pairs forgotten
function ChatSystem.sweep()
  local held = {}
  for frame in pairs(hooked) do
    if type(frame.GetNumMessages) == "function" and type(frame.GetMessageInfo) == "function" then
      for i = 1, frame:GetNumMessages() do
        local text = frame:GetMessageInfo(i)
        if type(text) == "string" and not secret(text) and jaToEn[text] then held[text] = true end
      end
    end
  end
  local n = 0
  for ja in pairs(jaToEn) do
    if not held[ja] then jaToEn[ja], jaArea[ja], n = nil, nil, n + 1 end
  end
  remembered = remembered - n
  return n
end

-- → true when `ja` may stand for `en` (a new pair within the limit, or the same pair again). Also UI/Speech's.
local function remember(ja, en, area)
  local known = jaToEn[ja]
  if known ~= nil then return known == en end
  if remembered >= ChatSystem.MAX_REMEMBERED then
    if refused == 0 then ChatSystem.sweep() end
    if remembered >= ChatSystem.MAX_REMEMBERED then
      refused = (refused + 1) % ChatSystem.SWEEP_EVERY
      return false
    end
  end
  refused = 0
  jaToEn[ja], jaArea[ja] = en, area or "ui"
  remembered = remembered + 1
  return true
end
ChatSystem.remember = remember

-- The Japanese for a SYSTEM line's English: an exact dictionary English (one English is one Japanese; also the
-- non-error lines Blizzard's Lua prints, ChatFrameUtil.AddSystemMessage), else, unless `exactOnly`, a chat key's
-- template, by key. → ja | nil
local function filled(index, key, args, en)
  local row = key and index.rows[key]
  if type(row) ~= "table" or row[3] ~= "." then return nil end -- trusted rows only; anything else stays English
  local ja = args and index:fill(row[1], args) or row[1]
  if type(ja) ~= "string" or ja == "" or ja == en then return nil end
  return ja
end

-- `faction` (optional): the line is a reputation line, which may also be a FriendshipGain row.
function ChatSystem.translate(en, exactOnly, faction)
  local index = WFJ.UIIndex
  if not index or type(en) ~= "string" or en == "" then return nil end
  local key, args = index:exactKey(en), nil
  if not key and not exactOnly then
    key, args = index:matchOnly(en, faction and factionKeys(index) or chatKeys(index))
  end
  local ja = filled(index, key, args, en)
  -- a server notice: its time argument is text, so no digit fingerprint finds it (Index:matchTail)
  if not ja and not exactOnly and type(index.matchTail) == "function" then
    key, args = index:matchTail(en, serverKeys(index))
    ja = filled(index, key, args, en)
  end
  return ja
end

-- communitiesChat: the Japanese for a line that may only be one of `keys` (a list): exact or template,
-- never any other key. → ja | nil
function ChatSystem.translateOnly(en, keys)
  local index = WFJ.UIIndex
  if not index or type(en) ~= "string" or en == "" or type(keys) ~= "table" then return nil end
  local key, args = index:matchOnly(en, keys)
  return filled(index, key, args, en)
end

local function eachFrame(fn)
  local names = Compat.get(SURFACE, "frames")
  for _, name in ipairs(type(names) == "table" and names or {}) do
    local frame = Compat.resolve(name)
    if type(frame) == "table" then fn(frame) end
  end
end

-- The prefix the chat frame puts before a player's (or an NPC's, UI/Speech) line: format(_G["CHAT_" .. type ..
-- "_GET"] .. message, pflag .. name, name) (chatframeutil.lua:352–355, chatframeoverrides.lua:629–633). The words of
-- the prefix are swapped in the finished line; the name, the link around it, the timestamp and the message are left
-- exactly as the client wrote them. A prefix with a channel link ("[Party]") is not listed and stays English.
ChatSystem.PREFIXED_TYPES = { "SAY", "YELL", "WHISPER", "WHISPER_INFORM", "BN_WHISPER", "BN_WHISPER_INFORM", "AFK",
  "DND", "RAID_WARNING", "CHANNEL_JOIN", "CHANNEL_LEAVE" }

local function split(template)
  local a, b = template:find("%s", 1, true)
  if not a then return nil end
  return template:sub(1, a - 1), template:sub(b + 1)
end

-- `line` with the Japanese words of type `typeName`'s prefix. → line | nil (no trusted, current prefix row)
function ChatSystem.prefixed(line, typeName)
  local index, key = WFJ.UIIndex, "CHAT_" .. tostring(typeName) .. "_GET"
  local row = index and index.rows and index.rows[key]
  if type(line) ~= "string" or type(row) ~= "table" or row[3] ~= "." or type(index.hash) ~= "function" then
    return nil
  end
  local en = Compat.resolve(key)
  if type(en) ~= "string" or en == "" or index.hash(en) ~= row[2] then return nil end -- the client's own English
  local enPre, enPost = split(en)
  local jaPre, jaPost = split(row[1])
  if not enPre or not jaPre or enPost == "" then return nil end
  local i = 1
  if enPre ~= "" then
    i = line:find(enPre, 1, true)
    if not i then return nil end
  end
  local j = line:find(enPost, i + #enPre, true)
  if not j then return nil end
  return line:sub(1, i - 1) .. jaPre .. line:sub(i + #enPre, j - 1) .. jaPost .. line:sub(j + #enPost)
end

local prefixedIds
local function prefixedTypeIds()
  if prefixedIds then return prefixedIds end
  local info = Compat.get(SURFACE, "typeInfo")
  if type(info) ~= "table" then return nil end
  prefixedIds = {}
  for _, name in ipairs(ChatSystem.PREFIXED_TYPES) do
    local t = info[name]
    if type(t) == "table" and t.id ~= nil then prefixedIds[t.id] = name end
  end
  return prefixedIds
end

-- A player's line: the prefix's words, rewritten once in the history (the line's own id picks the entry). → 1 | 0
local function onPlayerLine(frame, message, typeId, eventArgs)
  local byId = prefixedTypeIds()
  local name = byId and byId[typeId]
  if not name or type(eventArgs) ~= "table" or eventArgs[11] == nil or not on("ui") then return 0 end
  local ja = ChatSystem.prefixed(message, name)
  if not ja or ja == message or not remember(ja, message) then return 0 end
  local lineID = eventArgs[11]
  frame:TransformMessages(function(text, _, _, _, lineType, _, _, _, args)
    -- a history entry from chat messaging lockdown is secret: never compared (an addon may not)
    return lineType == typeId and type(args) == "table" and not secret(args[11]) and args[11] == lineID
      and not secret(text) and text == message
  end, function(_, ...)
    return ja, ...
  end)
  return 1
end

-- An emote's chat line (ADR-042) (CHAT_MSG_TEXT_EMOTE, "Bob waves at you."): the client's EmotesTextData text
-- with the sender's name turned into a player link (string.gsub(message, arg2, pflag..playerLink, 1)) and a
-- timestamp in front when the player turned them on (chatframeoverrides.lua:635–644, 661–664). Its row is slotted
-- (EmoteText:<id>): the line's plain text is matched by putting the names back (UIStrings index:matchSlots: the
-- sender, the player and the target are the names it knows), and the Japanese is filled with each name exactly as the
-- line wrote it (the sender's link and chat flag kept), the timestamp in front. A line with no matching row stays
-- English.
local emoteId
local function emoteTypeId()
  if emoteId == nil then
    local info = Compat.get(SURFACE, "typeInfo")
    local t = type(info) == "table" and info.TEXT_EMOTE or nil
    emoteId = type(t) == "table" and t.id or false
  end
  return emoteId or nil
end

-- A timestamp BetterDate put in front ("12:34 ", "[12:34:56] ", "12:34 PM "), optionally colour-wrapped. → stamp, rest
function ChatSystem.splitStamp(message)
  local open, inner = message:match("^(|c%x%x%x%x%x%x%x%x)(.*)$")
  local stamp, after = (inner or message):match("^(%[?%d%d?:%d%d[:%d]*)(.*)$")
  if not stamp then return "", message end
  local ampm = after:match("^ [AaPp][Mm]") -- "12:34 PM"
  if ampm then stamp, after = stamp .. ampm, after:sub(#ampm + 1) end
  if stamp:sub(1, 1) == "[" then
    if after:sub(1, 1) ~= "]" then return "", message end
    stamp, after = stamp .. "]", after:sub(2)
  end
  local close, rest = after:match("^(|r)(.*)$")
  local space, body = (rest or after):match("^(%s*)(.*)$")
  return (open or "") .. stamp .. (close or "") .. space, body
end

-- The raw text the line wrote for a name it shows as `shown` (plain): the sender's player link with the chat flag
-- before it, else the name itself.
local function rawName(raw, shown)
  local flag, name = shown:match("^(<[^<>]*>)(.+)$")
  name = name or shown
  for at, link in raw:gmatch("()(|H[^|]*|h.-|h)") do
    if WFJ.Normalize.v1(link) == name then
      local before = raw:sub(1, at - 1)
      local icon = before:match("(|T[^|]*|t%s*)$") or ""
      return icon .. (flag or before:match("(<[^<>]*>)$") or "") .. link
    end
  end
  return shown
end

-- → ja | nil
function ChatSystem.emote(message, names)
  local index = WFJ.UIIndex
  if not index or type(index.matchSlots) ~= "function" or type(message) ~= "string" then return nil end
  local stamp, body = ChatSystem.splitStamp(message)
  local plain = WFJ.Normalize.v1(body)
  local key, spans = index:matchSlots(plain, names)
  local row = key and index.rows[key]
  if type(row) ~= "table" or row[3] ~= "." then return nil end -- trusted rows only
  local args = {}
  for i, sp in ipairs(spans) do args[i] = rawName(body, plain:sub(sp[1], sp[2])) end
  local ja = index:fill(row[1], args)
  if type(ja) ~= "string" or ja == "" then return nil end
  return stamp .. ja
end

local function knownNames(eventArgs)
  local names, seen = {}, {}
  local function add(n)
    if type(n) == "string" and n ~= "" and not secret(n) and not seen[n] then seen[n] = true; names[#names + 1] = n end
  end
  local sender = type(eventArgs) == "table" and eventArgs[2] or nil
  add(sender)
  local ambiguate = Compat.get(SURFACE, "ambiguate")
  if type(sender) == "string" and type(ambiguate) == "function" then add(ambiguate(sender, "short")) end
  local unitName = Compat.get(SURFACE, "unitName")
  if type(unitName) == "function" then
    add(unitName("player"))
    add(unitName("target"))
  end
  return names
end

local function onEmoteLine(frame, message, typeId, eventArgs)
  if not on("ui") then return 0 end
  local ja = ChatSystem.emote(message, knownNames(eventArgs))
  if not ja or ja == message or not remember(ja, message) then return 0 end
  local lineID = type(eventArgs) == "table" and eventArgs[11] or nil
  frame:TransformMessages(function(text, _, _, _, lineType, _, _, _, args)
    if lineType ~= typeId or secret(text) or text ~= message then return false end
    return lineID == nil or (type(args) == "table" and not secret(args[11]) and args[11] == lineID)
  end, function(_, ...)
    return ja, ...
  end)
  return 1
end

-- hooksecurefunc target (a chat frame's AddMessage). → 1 | 0
function ChatSystem.onAddMessage(frame, message, _, _, _, typeId, _, _, _, eventArgs)
  local ids = plainTypeIds()
  if not ids or type(frame) ~= "table" or type(message) ~= "string" or secret(message)
      or type(frame.TransformMessages) ~= "function" then
    return 0
  end
  -- a line with no chat type (DEFAULT_CHAT_FRAME:AddMessage(text, r, g, b): Blizzard's slash-command usage lines,
  -- print(), another addon's too) takes an exact dictionary English only, as the errors frame's Lua lines do
  local untyped = typeId == nil
  if not untyped and typeId == emoteTypeId() then return onEmoteLine(frame, message, typeId, eventArgs) end
  if not untyped and not ids[typeId] then return onPlayerLine(frame, message, typeId, eventArgs) end
  if not on() then return 0 end
  local ja = ChatSystem.translate(message, untyped, not untyped and typeId == factionTypeId())
  if not ja or not remember(ja, message) then return 0 end
  -- no line id on a plain line: an identical English still in the history (it arrived while off) is rewritten too
  frame:TransformMessages(function(text, _, _, _, lineType)
    return lineType == typeId and not secret(text) and text == message
  end, function(_, ...)
    return ja, ...
  end)
  return 1
end

-- The bundled face on one chat line, at the line's size: smaller when the Japanese would not fit the height the
-- frame laid the line out at (the layout measured it in the chat font, before this; in game a Japanese
-- line spilled over the next one). SetFont directly, never Font.set: a refused font must not be retried later; the
-- pooled line shows another message by then (in game: English lines turned small in the bundled face). → size set
local MIN_SIZE = 8
-- `fontObject` (optional): the frame's own font, whose size a row starts from (a row may still hold a shrunk size)
function ChatSystem.fit(line, fontObject)
  local room = type(line.GetHeight) == "function" and line:GetHeight() or 0
  local size = WFJ.Font.bundle(line, fontObject)
  if size == nil then return nil end
  local _, _, flags = line:GetFont()
  flags = flags or ""
  if type(line.GetStringHeight) ~= "function" or room <= 0 then return size end
  -- shrink only when the Japanese takes an extra line (its string height passes the room by more than half a line):
  -- the bundled face's line is a few pixels taller than the chat font's, and shrinking for that alone made
  -- one-line Japanese smaller than the English around it (seen in game)
  while size > MIN_SIZE and line:GetStringHeight() > room + size * 0.5 do
    size = size - 1
    line:SetFont(WFJ.Font.PATH, size, flags)
  end
  return size
end

-- Each visible line in the bundled face. A line showing one of our Japanese strings: the Japanese (shrunk to fit,
-- ChatSystem.fit), or, while the modifier is held or the addon / UI area is off, the remembered English. Also the
-- display-refreshed callback. → lines set to our Japanese or its English
function ChatSystem.show(frame)
  local lines = type(frame) == "table" and type(frame.visibleLines) == "table" and frame.visibleLines or {}
  local fontObject = type(frame) == "table" and type(frame.GetFontObject) == "function" and frame:GetFontObject() or nil
  local n = 0
  for _, line in ipairs(lines) do
    local info = type(line) == "table" and line.messageInfo or nil
    local ja = type(info) == "table" and info.message or nil
    local ours = type(ja) == "string" and not secret(ja) and jaToEn[ja] ~= nil
    if ours and wanted(jaArea[ja]) then
      line:SetText(ja)
      ChatSystem.fit(line, fontObject)
    else
      if ours then line:SetText(jaToEn[ja]) end
      -- every chat line wears the bundled face, English too, so a player's Japanese shows (the client's chat
      -- font has no kana or kanji); at the frame's size, which follows a change of the chat font size. Setting
      -- a font reads nothing from the line, so a secret line is dressed like any other
      if type(line) == "table" and type(line.SetFont) == "function" then WFJ.Font.bundle(line, fontObject) end
    end
    if ours then n = n + 1 end
  end
  return n
end
ChatSystem.onRefreshed = ChatSystem.show

-- communitiesChat: a message frame outside CHAT_FRAMES whose client-written lines are one of a few keys:
-- the Communities chat's date / unread separators and its message-of-the-day line (communitieschatframe.lua:357–397:
-- MessageFrame:AddMessage / BackFillMessage(text, r, g, b), no chat type). Only a line that is wholly one of `keys`
-- is rewritten (once, in the history, as a plain line is); a member's message ("[name]: text") is never one of them
-- and is never touched. The visible lines follow the modifier / the switch as a chat frame's do.
local keyedFrames = setmetatable({}, { __mode = "k" }) -- frame → its key list

-- The cheap test run before any lookup: `message` is one of `keys`' English as the client has
-- it (the global string), whole, or starts with a template's text before its first specifier ('Message of the Day: "').
-- A member's message fails it, so it never runs the index's unrestricted scan nor takes a slot of its shared memo.
local function mayBeKeyed(message, keys)
  for _, key in ipairs(keys) do
    local en = Compat.resolve(key)
    if type(en) == "string" and en ~= "" then
      local cut = en:find("%", 1, true)
      if not cut then
        if message == en then return true end
      elseif cut > 1 and message:sub(1, cut - 1) == en:sub(1, cut - 1) then
        return true
      end
    end
  end
  return false
end
ChatSystem.mayBeKeyed = mayBeKeyed

function ChatSystem.onKeyedMessage(frame, message)
  local keys = type(frame) == "table" and keyedFrames[frame] or nil
  if not keys or type(message) ~= "string" or secret(message) or type(frame.TransformMessages) ~= "function"
      or not on() or not mayBeKeyed(message, keys) then
    return 0
  end
  local ja = ChatSystem.translateOnly(message, keys)
  if not ja or not remember(ja, message) then return 0 end
  frame:TransformMessages(function(text) return not secret(text) and text == message end, function(_, ...)
    return ja, ...
  end)
  return 1
end

-- → 1 when `frame` was hooked now
function ChatSystem.hookKeyed(frame, keys)
  if type(frame) ~= "table" or type(keys) ~= "table" or hooked[frame] or type(frame.AddMessage) ~= "function" then
    return 0
  end
  hooked[frame], keyedFrames[frame] = true, keys
  hooksecurefunc(frame, "AddMessage", ChatSystem.onKeyedMessage)
  if type(frame.BackFillMessage) == "function" then
    hooksecurefunc(frame, "BackFillMessage", ChatSystem.onKeyedMessage)
  end
  if type(frame.AddOnDisplayRefreshedCallback) == "function" then
    frame:AddOnDisplayRefreshedCallback(ChatSystem.onRefreshed)
  end
  return 1
end

-- The modifier / the switch changed: every chat frame's visible lines follow (their history is left alone).
function ChatSystem.refresh()
  if remembered == 0 then return end
  if ready then eachFrame(ChatSystem.show) end
  for frame in pairs(keyedFrames) do ChatSystem.show(frame) end
end

local function hookFrame(frame)
  if hooked[frame] or type(frame.AddMessage) ~= "function" then return 0 end
  hooked[frame] = true
  hooksecurefunc(frame, "AddMessage", ChatSystem.onAddMessage)
  if type(frame.AddOnDisplayRefreshedCallback) == "function" then
    frame:AddOnDisplayRefreshedCallback(ChatSystem.onRefreshed)
  end
  return 1
end

function ChatSystem.hookAll()
  local n = 0
  eachFrame(function(frame) n = n + hookFrame(frame) end)
  return n
end

function ChatSystem.isReady() return ready end

function ChatSystem.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if ready then return false end
  if type(Compat.get(SURFACE, "frames")) ~= "table" or not plainTypeIds() then return false end
  ready = true
  ChatSystem.hookAll()
  if type(Compat.get(SURFACE, "openTemporary")) == "function" then
    hooksecurefunc("FCF_OpenTemporaryWindow", ChatSystem.hookAll) -- a whisper / temporary window made later
  end
  return true
end

WFJ.State.on("enabled", ChatSystem.refresh)
WFJ.State.on("area", ChatSystem.refresh)
WFJ.State.on("modifier", ChatSystem.refresh)
