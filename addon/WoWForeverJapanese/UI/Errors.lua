-- UI/Errors.lua: the UI errors frame's red and yellow lines (surface "errors", area "ui", ADR-035): "Out of
-- range.", "Not enough mana", "Inventory is full.", "Kobold Vermin slain: 3/10".
-- Writer [verified: Forever 1.60.1.69913]: UIErrorsFrame is a MessageFrame (blizzard_uierrorsframe/mainline/
--   uierrorsframe.xml). UI_ERROR_MESSAGE / UI_INFO_MESSAGE carry (messageType, message); TryDisplayMessage calls
--   self:AddMessage(message, r, g, b, 1.0, messageType) (uierrorsframe.lua:13–24, 146–157). GetGameMessageInfo(
--   messageType) returns the GlobalStrings key of that message (gameerrordocumentation.lua:10–25; the client itself
--   reads _G[it], blizzard_channels/mainline/voiceutils.lua:82–84). AddMessage is post-hooked on the instance; the
--   line's FontString is GetFontStringByID(messageType).
-- The line is matched only against its own key (its `%s` arguments (names) kept as written, UIStrings.argKinds).
-- A key whose English is only "%s" is a pass-through wrapper (ERR_SPELL_FAILED_S carries a SPELL_FAILED_* line): its
-- line is matched against every listed error key instead.
-- A line with no id (SYSMSG, uierrorsframe.lua:14–16; Blizzard's Lua AddMessage), with LE_GAME_ERR_SYSTEM
-- (AddExternalErrorMessage / AddExternalWarningMessage, :158–163), or whose id's key did not match, takes the Lua-line
-- rule below (an exact dictionary English, or a Lua template). Never touched: text that is neither; another addon's
-- own sentence stays as written.
-- Repeats: a throttled type flashes its line instead of adding it again only when the line's text
-- equals the incoming English (TryFlashingExistingMessage, :118–127); once the line is Japanese that is never true, so
-- the client would re-add it AND replay its error sound / voice line on every press (:146–155). The frame's own
-- ShouldDisplayMessageType, called only from TryDisplayMessage (:133–147; blizzard_channels' TryDisplayMessage), is
-- wrapped on the instance: while the line of that id is our Japanese for that same English, the client's English is put
-- back for the length of the original check, so the client decides exactly as it would without the addon (flash and
-- no sound for a throttled type, a new line for any other), then our Japanese goes back. Taint: the wrapper runs inside
-- the errors frame's event handler and the voice-channel error display, neither of which reaches a protected call;
-- TryFlashingExistingMessage itself (also used by AddExternalMessage, which Blizzard's action code calls) is untouched.
local _, WFJ = ...
local Errors = {}
WFJ.Errors = Errors

local SURFACE = "errors"
Errors.SURFACE = SURFACE
local Compat = WFJ.Compat

Errors.NEVER_TOUCH = {} -- each line is restricted to its own key

local CANDIDATES = { frame = { "UIErrorsFrame" }, messageInfo = { "GetGameMessageInfo" },
  timer = { "C_Timer" } }

local onlyByKey = {} -- { [key] = { [key] = true } }: one `only` set per key, so matchOnly caches it
local wrapperSet, wrapperIndex -- the listed error keys a wrapper's line may be, rebuilt when the index is
local MIN_LETTERS = 4 -- a template's own letters (specifiers aside) before a wrapper's line may be it

-- A wrapper's line can be any error text, so only a key whose English says something of its own may take it: an
-- exact string, or a template with at least MIN_LETTERS letters outside its specifiers ("Requires %s", never "%s.";
-- ERR_TAME_FAILED would take any other addon's sentence).
local function carried(en)
  if type(en) ~= "string" then return false end
  local literal = en:gsub("%%%d*%$?[-+ #0]*%d*%.?%d*[sdiufgcx%%]", "")
  local _, letters = literal:gsub("%a", "")
  return letters >= MIN_LETTERS
end

local function errorKeys(index)
  if wrapperIndex ~= index then
    wrapperSet, wrapperIndex = {}, index
    for key in pairs(index.rows or {}) do
      if WFJ.UIStrings.isErrorKey(key) and carried(Compat.resolve(key)) then wrapperSet[key] = true end
    end
  end
  return wrapperSet
end
Errors.errorKeys = errorKeys -- UI/ChatSystem matches a SYSTEM chat line against the same set

local function exactSet(key)
  local set = onlyByKey[key]
  if not set then
    set = { [key] = true }
    onlyByKey[key] = set
  end
  return set
end

-- The `only` set a line of `key` is matched against. → set | nil (no index yet)
function Errors.only(key)
  local index = WFJ.UIIndex
  if not index then return nil end
  if Compat.resolve(key) == "%s" then return errorKeys(index) end
  return exactSet(key)
end

-- The lines Blizzard's Lua adds itself (UIErrorsFrame:AddMessage(KEY, r, g, b, a) with no id, or
-- AddExternalErrorMessage (LE_GAME_ERR_SYSTEM)) carry a GlobalStrings text of any family (ERR_NOT_ENOUGH_MONEY,
-- PAPERDOLL_AUTO_EQUIP_MINING_ONLY, GUILD_RENAME_ERROR_*, …; pipeline/wfj/dev/ui_inventory.py errors_call_keys). Such a
-- line, and a line whose id did not resolve, is matched exactly against the whole dictionary (one English is one
-- Japanese; the UI/HudLabels action-status rule) or against the few templates that Lua formats; never any other
-- template, so another addon's sentence is never taken for one.
-- (Not ERR_QUEST_ADD_FOUND_SII, questmapframe.lua:573: its Japanese is its English, "%s: %d/%d", and a template with no
-- letters would take any other addon's "x: 1/2" line.)
Errors.LUA_TEMPLATES = { TOO_MANY_WATCHED_TOKENS = true, ACHIEVEMENT_WATCH_TOO_MANY = true } -- camelot
-- blizzard_tokenui.lua:463, achievementui:1718
-- communitieserrors.lua:120–132 (a community action's error; removed from a community), communitieshyperlink.lua:16
local LUA_FAMILIES = { "^ERROR_CLUB_ACTION_", "^CLUB_REMOVED_REASON_" }
local luaSet, luaIndex
local function luaTemplates(index)
  if luaIndex ~= index then
    luaSet, luaIndex = {}, index
    for key in pairs(Errors.LUA_TEMPLATES) do luaSet[key] = true end
    for key in pairs(index.rows or {}) do
      for _, family in ipairs(LUA_FAMILIES) do
        if key:find(family) then luaSet[key] = true end
      end
    end
  end
  return luaSet
end

-- A Lua-added line: an exact dictionary English, else one of the Lua templates. → 1 | 0
local function showLua(fs, recKey)
  local index = WFJ.UIIndex
  if not index or type(fs) ~= "table" or type(fs.GetText) ~= "function" then return 0 end
  local text = fs:GetText()
  if type(text) ~= "string" or text == "" then return 0 end
  local key = index:exactKey(text)
  return WFJ.Labels.show(SURFACE, recKey, fs, nil, { only = key and exactSet(key) or luaTemplates(index) })
end

-- The FontStrings showing `message` [in game: GetFontStringByID(id) right after AddMessage still names
-- the previous line of that id: a first line was never found, and a quick repeat translated the older line instead
-- of itself (the frame adds a new line per repeat of a non-throttled type). So a line is looked up on the next frame,
-- when it exists: every shown region with that text, and the id's line when it shows that text. Regions: unverified
-- that the Forever MessageFrame's lines are its regions; if not, the id's line is still found]. → list
local function linesFor(frame, message, messageID)
  local out, seen = {}, {}
  local function add(fs)
    if type(fs) == "table" and not seen[fs] and type(fs.GetText) == "function" and fs:GetText() == message
        and (type(fs.IsShown) ~= "function" or fs:IsShown()) then
      seen[fs] = true
      out[#out + 1] = fs
    end
  end
  if type(messageID) == "number" and type(frame.GetFontStringByID) == "function" then
    add(frame:GetFontStringByID(messageID))
  end
  if type(frame.GetRegions) == "function" then
    for _, region in ipairs({ frame:GetRegions() }) do add(region) end
  end
  return out
end

-- One record per line FontString (two lines of one id can show at once, each its own record). → key
local lineKey = WFJ.Labels.keyer("line.")

-- The line(s) `message` went to, in Japanese: by the id's key (`only`), else by the Lua-line rule. → lines shown
function Errors.render(frame, message, messageID, only)
  if type(message) ~= "string" or message == "" then return 0 end
  local n = 0
  for _, fs in ipairs(linesFor(frame, message, messageID)) do
    local key = lineKey(fs)
    if only and WFJ.Labels.show(SURFACE, key, fs, nil, { only = only }) == 1 then
      n = n + 1
    else
      n = n + showLua(fs, key) -- LE_GAME_ERR_SYSTEM, no id, or an id whose key did not match
    end
  end
  return n
end

-- hooksecurefunc target (UIErrorsFrame:AddMessage). → 1 (a render is on its way) | 0
function Errors.onAddMessage(frame, message, _, _, _, _, messageID)
  if type(frame) ~= "table" or type(message) ~= "string" or message == "" then return 0 end
  local only
  if type(messageID) == "number" then
    local info = Compat.get(SURFACE, "messageInfo")
    local ok, key = false, nil
    if type(info) == "function" then
      ok, key = pcall(info, messageID) -- another addon's AddMessage may pass any number as its id
    end
    only = ok and type(key) == "string" and key ~= "" and Errors.only(key) or nil
  end
  local timer = Compat.get(SURFACE, "timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    timer.After(0, function() Errors.render(frame, message, messageID, only) end)
  else
    Errors.render(frame, message, messageID, only)
  end
  return 1
end

-- The record of the line `messageType` shows while it is our Japanese for `message`. → rec, fs | nil
local function ours(frame, messageType, message)
  if type(messageType) ~= "number" or type(message) ~= "string" then return nil end
  local fs = frame:GetFontStringByID(messageType)
  local rec = type(fs) == "table" and WFJ.SurfaceState.get(SURFACE, lineKey(fs)) or nil
  if not rec or rec.fs ~= fs or rec.en ~= message or type(rec.applied) ~= "string" then return nil end
  if fs:GetText() ~= rec.applied then return nil end
  return rec, fs
end

-- The wrapper around the instance's ShouldDisplayMessageType (see the header). → the original's answer
function Errors.wrapShould(original)
  return function(frame, messageType, message, ...)
    local rec, fs = ours(frame, messageType, message)
    if not rec then return original(frame, messageType, message, ...) end
    fs:SetText(message)
    local show = original(frame, messageType, message, ...)
    if not show and type(frame.flashingFontStrings) == "table" and frame.flashingFontStrings[fs] then
      fs.origMsg = rec.applied -- the flash (OnUpdate, :31–52) runs while the text is still the flashed text
    end
    fs:SetText(rec.applied)
    return show
  end
end

local hooked = false

function Errors.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  local frame = Compat.get(SURFACE, "frame")
  if type(frame) ~= "table" or type(frame.AddMessage) ~= "function"
      or type(Compat.get(SURFACE, "messageInfo")) ~= "function" then
    return false
  end
  hooked = true
  hooksecurefunc(frame, "AddMessage", Errors.onAddMessage)
  if type(frame.ShouldDisplayMessageType) == "function" and type(frame.GetFontStringByID) == "function" then
    frame.ShouldDisplayMessageType = Errors.wrapShould(frame.ShouldDisplayMessageType)
  end
  WFJ.Render.updateBanner(SURFACE)
  return true
end
