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
-- the client would re-add it AND replay its error sound / voice line on every press (:146–155). Nothing of the frame
-- is replaced for this: a function of the frame written by the addon makes every error display run in the addon's
-- name, and the fields that display writes (flashingFontStrings, a line's origMsg) are then read by the client's own
-- callers of AddExternalErrorMessage (key bindings, the character window). Instead a frame of the addon's own
-- listens for the two events ahead of the client's frame and, while the line of that id is our Japanese for that
-- same English, writes the client's English back, so the client decides exactly as it would without the addon (flash
-- and no sound for a throttled type, a new line for any other). A post-hook on TryDisplayMessage then puts our
-- Japanese back and flashes the line itself, since the client's flash stops on a line whose text changed (:36–47).
-- Order: the client's frame is registered for the two events again after the addon's listener [unverified: that
-- events reach frames in the order they registered; in-game check: a repeated "Out of range" plays its sound once.
-- When the order is the other way the client adds the line again with its sound, and one log line says so].
local _, WFJ = ...
local Errors = {}
WFJ.Errors = Errors

local SURFACE = "errors"
Errors.SURFACE = SURFACE
local Compat = WFJ.Compat

Errors.NEVER_TOUCH = {} -- each line is restricted to its own key

local CANDIDATES = { frame = { "UIErrorsFrame" }, messageInfo = { "GetGameMessageInfo" },
  timer = { "C_Timer" }, create = { "CreateFrame" }, now = { "GetTime" }, cvarBool = { "GetCVarBool" } }

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
-- communitieserrors.lua:120–132 (a community action's error; removed from a community), communitieshyperlink.lua:16;
-- and the client's own instance transfer messages, which carry no GlobalStrings key: a dungeon's entry message
-- (MapDifficulty.Message) and an entry condition's failure text (MapDifficultyXCondition.FailureDescription), both
-- client-table families matched only by their exact English [unverified in game: which id, if any, such a line
-- arrives with; a line whose id did not match takes this rule too].
local LUA_FAMILIES = { "^ERROR_CLUB_ACTION_", "^CLUB_REMOVED_REASON_", "^InstanceEntryMessage:",
  "^InstanceEntryFailure:" }
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
  if type(text) ~= "string" or Compat.secret(text) or text == "" then return 0 end
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
    -- a line showing a secret value is another message: it may not be compared
    if type(fs) == "table" and not seen[fs] and type(fs.GetText) == "function" and not Compat.secret(fs:GetText())
        and fs:GetText() == message
        and (type(fs.IsShown) ~= "function" or fs:IsShown()) then
      seen[fs] = true
      out[#out + 1] = fs
    end
  end
  if type(messageID) == "number" and type(frame.GetFontStringByID) == "function" then
    add(frame:GetFontStringByID(messageID))
  end
  for _, region in ipairs(WFJ.Frames.regions(frame)) do add(region) end
  return out
end

-- One record per line FontString (two lines of one id can show at once, each its own record). → key
local lineKey = WFJ.Labels.keyer("line.")

-- The line(s) `message` went to, in Japanese: by the id's key (`only`), else by the Lua-line rule. → lines shown
function Errors.render(frame, message, messageID, only)
  if type(message) ~= "string" or Compat.secret(message) or message == "" then return 0 end
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
  -- a secret message (the client may hide one in combat) can be neither compared nor matched: it stays as written
  if type(frame) ~= "table" or type(message) ~= "string" or Compat.secret(message) or message == "" then return 0 end
  local only
  if type(messageID) == "number" and not Compat.secret(messageID) then
    local info = Compat.get(SURFACE, "messageInfo")
    local ok, key = false, nil
    if type(info) == "function" then
      ok, key = pcall(info, messageID) -- another addon's AddMessage may pass any number as its id
    end
    only = ok and Compat.readable(key) and Errors.only(key) or nil
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
  -- runs inside the client's own call: a secret message or line text is never compared there
  if type(messageType) ~= "number" or type(message) ~= "string" or Compat.secret(messageType)
      or Compat.secret(message) then
    return nil
  end
  local fs = frame:GetFontStringByID(messageType)
  local rec = type(fs) == "table" and WFJ.SurfaceState.get(SURFACE, lineKey(fs)) or nil
  if not rec or rec.fs ~= fs or rec.en ~= message or type(rec.applied) ~= "string" then return nil end
  if Compat.secret(fs:GetText()) or fs:GetText() ~= rec.applied then return nil end
  return rec, fs
end

local FLASH_SECONDS = 0.2 -- the client's own flash (uierrorsframe.lua:26–52)
local flashing = {} -- line → { start, text, r, g, b }
local flasher -- the addon's own frame whose OnUpdate runs the flashes

local function flashStep()
  local now = Compat.get(SURFACE, "now")
  local t, more = type(now) == "function" and now() or 0, false
  for fs, f in pairs(flashing) do
    local text = fs:GetText()
    local part = (t - f.start) / FLASH_SECONDS
    if Compat.secret(text) or text ~= f.text or part > 1 or part < 0 or (fs.IsShown and not fs:IsShown()) then
      if not Compat.secret(text) and text == f.text then fs:SetTextColor(f.r, f.g, f.b) end
      flashing[fs] = nil
    else
      local lift = (part > 0.5 and (1 - part) / 0.5 or part / 0.5) * 0.4
      fs:SetTextColor(f.r + lift, f.g + lift, f.b + lift)
      more = true
    end
  end
  if not more and flasher then flasher:SetScript("OnUpdate", nil) end
end

-- Flashes a line the way the client flashes a repeated error, on the text the line shows now.
function Errors.flash(fs)
  local cvarBool, now = Compat.get(SURFACE, "cvarBool"), Compat.get(SURFACE, "now")
  local create = Compat.get(SURFACE, "create")
  if type(now) ~= "function" or type(create) ~= "function" or type(fs.SetTextColor) ~= "function"
      or type(fs.GetTextColor) ~= "function" then
    return false
  end
  if type(cvarBool) == "function" and not cvarBool("flashErrorMessageRepeats") then return false end
  local f = flashing[fs]
  if f then
    f.start, f.text = now(), fs:GetText()
  else
    local r, g, b = fs:GetTextColor()
    flashing[fs] = { start = now(), text = fs:GetText(), r = r, g = g, b = b }
  end
  flasher = flasher or create("Frame")
  flasher:SetScript("OnUpdate", flashStep)
  return true
end

local waiting -- { rec, fs, message }: the line showing the client's English for the client's check of this event
local inEvent, lastShown -- the message the listener saw / the client displayed, to tell which of the two ran first
local orderLogged = false

-- Our Japanese back on the line put to English for the client's check, when the client kept that line (it flashed
-- it, or showed nothing); a line the client wrote again gets its Japanese from the AddMessage hook. → 1 | 0
function Errors.back()
  local w = waiting
  waiting = nil
  if not w then return 0 end
  local rec, fs = w.rec, w.fs
  if WFJ.SurfaceState.get(SURFACE, rec.key) ~= rec or type(rec.applied) ~= "string" then return 0 end
  local text = fs:GetText()
  if Compat.secret(text) or text ~= w.message then return 0 end
  WFJ.SurfaceState.setText(fs, rec.applied)
  Errors.flash(fs)
  return 1
end

-- The addon's own listener for UI_ERROR_MESSAGE / UI_INFO_MESSAGE, ahead of the client's frame. → 1 | 0
function Errors.onEvent(_, _, messageType, message)
  local frame = Compat.get(SURFACE, "frame")
  if type(frame) ~= "table" or type(frame.GetFontStringByID) ~= "function" then return 0 end
  Errors.back() -- a line still waiting: the client's frame never handled that event
  if lastShown ~= nil and not Compat.secret(message) and lastShown == message and not orderLogged then
    orderLogged = true
    if WFJ.Diag then WFJ.Diag.log("errors", "the client's error frame runs before the addon's listener: repeats sound again") end
  end
  lastShown = nil
  local rec, fs = ours(frame, messageType, message)
  if not rec then return 0 end
  inEvent = message
  WFJ.SurfaceState.setText(fs, message)
  waiting = { rec = rec, fs = fs, message = message }
  local timer = Compat.get(SURFACE, "timer")
  if type(timer) == "table" and type(timer.After) == "function" then timer.After(0, Errors.back) end
  return 1
end

-- hooksecurefunc target (UIErrorsFrame:TryDisplayMessage). → 1 | 0
function Errors.onDisplayed(_, _, message)
  if type(message) == "string" and not Compat.secret(message) then
    if inEvent == message then lastShown = nil else lastShown = message end
  end
  inEvent = nil
  return Errors.back()
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
  local create = Compat.get(SURFACE, "create")
  if type(frame.TryDisplayMessage) == "function" and type(frame.GetFontStringByID) == "function"
      and type(create) == "function" then
    hooksecurefunc(frame, "TryDisplayMessage", Errors.onDisplayed)
    local listener = create("Frame")
    listener:SetScript("OnEvent", Errors.onEvent)
    for _, event in ipairs({ "UI_ERROR_MESSAGE", "UI_INFO_MESSAGE" }) do
      listener:RegisterEvent(event)
      -- only an event the frame still listens for: another addon may have turned the error text off this way
      if type(frame.IsEventRegistered) == "function" and frame:IsEventRegistered(event) then
        frame:UnregisterEvent(event)
        frame:RegisterEvent(event)
      end
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return true
end
