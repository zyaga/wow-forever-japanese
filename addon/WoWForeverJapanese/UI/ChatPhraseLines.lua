-- UI/ChatPhraseLines.lua: a phrase from the phrase book as it shows in chat (docs/systems/chat-tools.md).
-- Arriving: a message filter on the chat events a player types into hands Core/ChatPhrases the message; a marked
-- phrase comes back in the reader's language, and the message as it arrived is kept. Any other message, and a
-- message the client keeps secret, is left exactly as it is. The filter is the client's own way for an addon to
-- change a chat message before it is drawn [verified: forever blizzard_chatframebase/shared/chatframefilters.lua:
-- 150–166 (a callback's second return onwards replace the arguments), :202 ChatFrameUtil.AddMessageEventFilter].
-- The reveal key: after UI/ChatSystem's own pass over the visible lines, a line holding a changed phrase shows, in
-- Japanese first, the message as it was sent, and in English first the Japanese phrase; on release its own text
-- goes back. The history is never rewritten.
local _, WFJ = ...
local Lines = {}
WFJ.ChatPhraseLines = Lines

local Compat = WFJ.Compat
local SURFACE = "chat.phrases"
local CANDIDATES = { frames = { "CHAT_FRAMES" }, isSecret = { "issecretvalue" },
  addFilter = { "ChatFrameUtil.AddMessageEventFilter", "ChatFrame_AddMessageEventFilter" } }

-- the chat events a player types into
Lines.EVENTS = { "SAY", "YELL", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "GUILD", "OFFICER",
  "WHISPER", "WHISPER_INFORM", "CHANNEL", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" }

local function secret(v)
  local f = Compat.get(SURFACE, "isSecret")
  return type(f) == "function" and f(v) and true or false
end

local function on()
  return WFJ.State.enabled and WFJ.Settings.get("chat.phrases") == true
end

-- The message filter. → false (never drops a message), then the changed message and the event's other values
function Lines.filter(_, _, msg, ...)
  if not on() or secret(msg) or type(msg) ~= "string" then return false end
  local P = WFJ.ChatPhrases
  local shown = P.translate(msg, WFJ.State.direction)
  if not shown then return false end
  P.keep(shown, msg)
  return false, shown, ...
end

-- ── The reveal key ───────────────────────────────────────────────────────────

local revealed = setmetatable({}, { __mode = "k" }) -- the visible lines now showing something else

-- What a line holding the changed message shows while the reveal key is held: the message as sent (Japanese
-- first), or its phrases in Japanese (English first).
local function held(raw)
  if WFJ.State.direction == "en" then return WFJ.ChatPhrases.translate(raw, "ja") or raw end
  return raw
end

function Lines.reveal(frame)
  local lines = type(frame) == "table" and type(frame.visibleLines) == "table" and frame.visibleLines or {}
  local holding = WFJ.State.modifierHeld and on()
  local P = WFJ.ChatPhrases
  for _, line in ipairs(lines) do
    local text = line:GetText()
    if type(text) == "string" and not secret(text) then
      if holding then
        local raw, first, last = P.sent(text)
        if raw then
          line:SetText(text:sub(1, first - 1) .. held(raw) .. text:sub(last + 1))
          revealed[line] = true
        end
      elseif revealed[line] then
        revealed[line] = nil
        -- a line UI/ChatSystem does not rewrite still holds what the key showed: its own text goes back
        local info = line.messageInfo
        local own = type(info) == "table" and info.message or nil
        if type(own) == "string" and not secret(own) and own ~= text and P.sent(own) then line:SetText(own) end
      end
    end
  end
end

function Lines.revealAll()
  local names = Compat.get(SURFACE, "frames")
  for _, name in ipairs(type(names) == "table" and names or {}) do
    local f = Compat.resolve(name)
    if type(f) == "table" then Lines.reveal(f) end
  end
end

local hooked = setmetatable({}, { __mode = "k" })

-- Called after UI/ChatSystem has hooked the chat frames (Main), so this pass runs after its own.
function Lines.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local add = Compat.get(SURFACE, "addFilter")
  if type(add) ~= "function" then return false end
  if not Lines.filtering then
    Lines.filtering = true
    for _, e in ipairs(Lines.EVENTS) do add("CHAT_MSG_" .. e, Lines.filter) end
    WFJ.State.on("language", Lines.revealAll)
    WFJ.State.on("chat", Lines.revealAll)
  end
  local names = Compat.get(SURFACE, "frames")
  for _, name in ipairs(type(names) == "table" and names or {}) do
    local f = Compat.resolve(name)
    if type(f) == "table" and not hooked[f] and type(f.AddOnDisplayRefreshedCallback) == "function" then
      hooked[f] = true
      f:AddOnDisplayRefreshedCallback(Lines.reveal)
    end
  end
  return true
end
