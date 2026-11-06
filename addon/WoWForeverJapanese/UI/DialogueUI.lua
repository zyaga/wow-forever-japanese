-- UI/DialogueUI.lua: the Dialogue UI addon's quest and gossip window, when the player has that addon (ADR-073).
-- Dialogue UI turns the client's quest and gossip windows off and draws the same text in its own frame,
-- DUIQuestFrame. This module replaces a few methods on that one frame with wrappers that put the Japanese in before
-- Dialogue UI lays the text out, and always call the original. Nothing of Dialogue UI is shipped or required:
-- without it, or with a version whose frame lacks a member listed below, nothing is installed and its window shows
-- its English. The lines, keys, markers, fonts, word cards and voice are the ones the client's windows get.
local _, WFJ = ...
local DialogueUI = {}
WFJ.DialogueUI = DialogueUI

local Compat = WFJ.Compat
local SURFACE = "dialogueui"
local S = {
  detail = "dialogueui.detail", progress = "dialogueui.progress", reward = "dialogueui.reward",
  greeting = "dialogueui.greeting", gossip = "dialogueui.gossip", title = "dialogueui.title",
  rows = "dialogueui.rows",
}
DialogueUI.SURFACES = S

-- The members of DUIQuestFrame the wrappers replace or call [read: Dialogue UI 1.0.7 b,
-- Code/Dialogue/DialogueUI.lua: every page handler starts with self:ReleaseAllObjects(), quest prose goes through
-- self:FormatQuestText → self:FormatParagraph, which acquires each paragraph's FontString with
-- self:AcquireLeftFontString and measures it as soon as its text is set]
DialogueUI.MEMBERS = { "FormatParagraph", "FormatQuestText", "AcquireLeftFontString", "InsertText",
  "UpdateQuestTitle", "AcquireOptionButton", "ReleaseAllObjects", "OnSettingsChanged", "HandleGossip",
  "HandleQuestDetail", "HandleQuestProgress", "HandleQuestComplete", "HandleQuestGreeting" }

Compat.declare(SURFACE, "getQuestID", { "GetQuestID" })
Compat.declare(SURFACE, "getTitle", { "GetTitleText" })
Compat.declare(SURFACE, "getDescription", { "GetQuestText" })
Compat.declare(SURFACE, "getObjectives", { "GetObjectiveText" })
Compat.declare(SURFACE, "getProgress", { "GetProgressText" })
Compat.declare(SURFACE, "getCompletion", { "GetRewardText" })
Compat.declare(SURFACE, "getGreeting", { "GetGreetingText" })
Compat.declare(SURFACE, "getGossip", { "C_GossipInfo.GetText" })

local deps = {} -- { key(text) → gossip key } from Main
local frame -- DUIQuestFrame, once installed
local installed = false
local MAX_ERRORS = 5
local errors = 0
local current -- the text FormatParagraph is laying out: { holder, fontStrings, … }
local questText -- the quest page FormatQuestText is laying out ("Detail", "Progress", "Complete")
local japaneseRows = false -- InsertText is laying out objective lines with Japanese in them
local touched = false -- the page shows a line this module looked up: a reveal key or switch change redraws it
local holders = {} -- surface .. key → text holder
local cards = {} -- word-card records on the page's paragraphs
local patched = setmetatable({}, { __mode = "k" }) -- option buttons whose writers are wrapped

local function call(key, ...)
  local fn = Compat.get(SURFACE, key)
  if type(fn) ~= "function" then return nil end
  return fn(...)
end

local function pack(...) return { n = select("#", ...), ... } end
DialogueUI.pack = pack

function DialogueUI.installed() return installed end
-- false once repeated errors switched both Dialogue UI modules off for the session
function DialogueUI.healthy() return errors < MAX_ERRORS end
function DialogueUI.active() return installed and errors < MAX_ERRORS end

-- Runs `fn` guarded: an error is recorded and counted, and after MAX_ERRORS both Dialogue UI modules stop changing
-- text for the session; every wrapper then passes Dialogue UI's own text through. → true, results | false
function DialogueUI.guarded(fn, ...)
  local res = pack(pcall(fn, ...))
  if res[1] then return unpack(res, 1, res.n) end
  errors = errors + 1
  local E = WFJ.ErrorLog
  if E and type(E.recordCaught) == "function" then pcall(E.recordCaught, tostring(res[2])) end
  if errors == MAX_ERRORS and WFJ.Diag then
    pcall(WFJ.Diag.log, "dialogueui", "errors in Dialogue UI's windows: left in English for this session")
  end
  return false
end
local guarded = DialogueUI.guarded

-- Calls `orig` with the module state `set` holds for its duration, put back even when `orig` errors (the error is
-- Dialogue UI's own and is raised again).
local function during(set, unset, orig, ...)
  set()
  local res = pack(pcall(orig, ...))
  unset()
  if not res[1] then error(res[2], 0) end
  return unpack(res, 2, res.n)
end

-- ── One text of the page ───────────────────────────────────────────────────

-- A stand-in widget for one text of the page (the gossip, a quest field): Render writes our Japanese and its font
-- here, and the wrapper hands that text to Dialogue UI, which splits it into paragraphs and lays them out.
local function holder(surface, key)
  local id = surface .. "\0" .. key
  local h = holders[id]
  if h then return h end
  h = { text = "", font = { flags = "" } }
  function h:GetText() return self.text end
  function h:SetText(t) self.text = t end
  function h:GetFont() return self.font.path, self.font.size, self.font.flags end
  function h:SetFont(path, size, flags)
    self.font = { path = path, size = size, flags = flags or "" }
    return true
  end
  holders[id] = h
  return h
end

local function paragraphFont()
  local obj = Compat.resolve("DUIFont_Quest_Paragraph") -- Dialogue UI's own name: not declared, absent without it
  if type(obj) == "table" and type(obj.GetFont) == "function" then
    local path, size, flags = obj:GetFont()
    if path then return { path = path, size = size, flags = flags or "" } end
  end
  return { path = "Fonts\\FRIZQT__.TTF", size = 13, flags = "" }
end

local QUEST_PAGES = {
  HandleQuestDetail = { surface = S.detail, panel = "detail" },
  HandleQuestProgress = { surface = S.progress, panel = "progress" },
  HandleQuestComplete = { surface = S.reward, panel = "reward" },
}
local FIELD_OF = { Detail = "description", Progress = "progress", Complete = "completion" }
local GETTER = { description = "getDescription", objectives = "getObjectives", progress = "getProgress",
  completion = "getCompletion" }

-- What a FormatParagraph call lays out → { surface, key, en, prefix, area, kind, id, live } | nil (not ours: the text
-- is not the game's line, e.g. the gossip confirm text). Dialogue UI may put text before the line (the NPC's name
-- and a colon, a hint), so the line is found at the end of what it passes, and the rest is kept as it is.
local function identify(self, text)
  if type(text) ~= "string" or text == "" then return nil end
  local handler = self.handler
  local el
  if handler == "HandleGossip" or handler == "HandleQuestGreeting" then
    local en = handler == "HandleGossip" and call("getGossip") or call("getGreeting")
    if type(en) ~= "string" or en == "" or type(deps.key) ~= "function" then return nil end
    el = { surface = handler == "HandleGossip" and S.gossip or S.greeting, key = "greeting", en = en,
      area = "gossip", kind = "gossip", id = deps.key(en) }
  else
    local page = QUEST_PAGES[handler]
    local field = page and (questText and FIELD_OF[questText] or (handler == "HandleQuestDetail" and "objectives"))
    if not field then return nil end
    local questID = call("getQuestID")
    local en = call(GETTER[field])
    if type(questID) ~= "number" or questID == 0 or type(en) ~= "string" or en == "" then return nil end
    local kind, id = WFJ.QuestFrame.fieldSource(questID, field, en)
    -- live: the values a quest line fills in (`$N1`) and the stale marker's live check come from this text
    el = { surface = page.surface, key = field, en = en, area = "quests", kind = kind, id = id, live = en,
      questID = questID, panel = page.panel }
  end
  if el.id == nil then return nil end
  if text == el.en then
    el.prefix = ""
  elseif #text > #el.en and text:sub(-#el.en) == el.en then
    el.prefix = text:sub(1, #text - #el.en)
  else
    return nil
  end
  return el
end

-- The line's record, made when it is new. → its holder
local function render(el)
  local h = holder(el.surface, el.key)
  local rec = WFJ.SurfaceState.get(el.surface, el.key)
  -- the same line laid out again (a redraw for the reveal key or a switch, the greeting again on a quest log update):
  -- the record already holds what to show, and showing it anew would start its voice line again
  if h.shown and rec and rec.fs == h and rec.en == el.en and rec.meta and rec.meta.id == el.id then return h end
  h.text, h.font, h.shown = el.en, paragraphFont(), nil
  WFJ.Render.show(el.surface, el.key, h, el.en, el.area, el.kind, el.id, { live = el.live })
  h.shown = true -- a show that failed half way is shown anew next time
  -- UI/VoicePlayer remembers who showed a quest line, for replays from the quest log
  if el.panel and el.key ~= "objectives" then pcall(WFJ.State.fire, "questShown", el.questID, el.panel) end
  return h
end

-- Word cards on the paragraphs Dialogue UI just made of our Japanese, each with its share of the line's words.
local function attachCards(el)
  local V, R = WFJ.ReadingView, WFJ.Readings
  if not (V and type(V.attach) == "function") then return end
  local rec = WFJ.SurfaceState.get(el.surface, el.key)
  local text = el.holder.text
  if not (rec and rec.applied ~= nil and rec.applied == text) then return end -- English showing: no cards
  local listed = R and type(R.lookup) == "function" and R.lookup(el.kind, el.id, text) or nil
  local full, shift, from = el.prefix .. text, #el.prefix, 1
  for i, fs in ipairs(el.fontStrings) do
    local t = fs:GetText()
    local at = type(t) == "string" and t ~= "" and full:find(t, from, true) or nil
    if at then
      from = at + #t
      local spans = {}
      for _, sp in ipairs(listed or {}) do
        local first, last = sp.first + shift, sp.last + shift
        if first >= at and last <= at + #t - 1 then
          spans[#spans + 1] = { first = first - at + 1, last = last - at + 1, word = sp.word, reading = sp.reading,
            gloss = sp.gloss, card = sp.card }
        end
      end
      local card = { surface = el.surface, key = el.key .. "." .. i, fs = fs, applied = t,
        meta = { kind = el.kind, id = el.id }, spans = spans }
      cards[#cards + 1] = card
      pcall(V.attach, card)
    end
  end
end

local function detachCards()
  local V = WFJ.ReadingView
  for _, card in ipairs(cards) do
    if V and type(V.detach) == "function" then pcall(V.detach, card) end
  end
  cards = {}
end

-- ── Fonts ───────────────────────────────────────────────────────────────────

local function fontObject(obj)
  if type(obj) == "string" then obj = Compat.resolve(obj) end
  if type(obj) ~= "table" then obj = Compat.resolve("DUIFont_Quest_Paragraph") end
  return type(obj) == "table" and obj or nil
end

-- A pooled FontString Dialogue UI just acquired: the bundled face for our Japanese before Dialogue UI measures it,
-- else Dialogue UI's own face back (re-applying its font object leaves a face set since in place).
local function dress(fs, obj)
  local japanese = japaneseRows or (current and current.holder.font.path == WFJ.Font.PATH)
  if japanese then
    WFJ.Font.bundle(fs, fontObject(obj))
  elseif WFJ.Font.dressed(fs) then
    WFJ.Font.restore(fs, fontObject(obj))
  end
  if current then current.fontStrings[#current.fontStrings + 1] = fs end
end

local function dressRow(button, japanese)
  local fs = button.Name
  if type(fs) ~= "table" or type(fs.GetFont) ~= "function" then return end
  local obj = type(fs.GetFontObject) == "function" and fs:GetFontObject() or nil
  if japanese then
    WFJ.Font.bundle(fs, obj)
  elseif WFJ.Font.dressed(fs) then
    WFJ.Font.restore(fs, obj)
  end
end

-- ── Rows: titles, options, objective lines (no records, no markers) ────────

local function rowJapanese(en, area, kind, id, live)
  touched = true
  local text, _, action = WFJ.Render.preview(S.rows, en, nil, area, kind, id, { compact = true, live = live })
  if action == "apply" and type(text) == "string" then return text end
  return nil
end

local function gossipRow(name)
  local id = type(deps.key) == "function" and deps.key(name) or nil
  return id and rowJapanese(name, "gossip", "gossip", id) or nil
end

local function questRow(questInfo)
  return rowJapanese(questInfo.title, "quests", "quest.title", questInfo.questID, questInfo.title)
end

-- The writers of one option button: a gossip option gets a copy of its data with the Japanese name, a quest row its
-- Japanese title for the call (Dialogue UI writes the label again from the same questInfo when the quest loads).
local function patch(button)
  if patched[button] then return end
  patched[button] = true
  local setGossip, setQuestName = button.SetGossip, button.SetQuestName
  if type(setGossip) == "function" then
    button.SetGossip = function(b, data, ...)
      local ja
      if DialogueUI.active() and type(data) == "table" and type(data.name) == "string" then
        local ok, text = guarded(gossipRow, data.name)
        ja = ok and text or nil
      end
      guarded(dressRow, b, ja ~= nil)
      if not ja then return setGossip(b, data, ...) end
      local copy = {}
      for k, v in pairs(data) do copy[k] = v end
      copy.name = ja
      return setGossip(b, copy, ...)
    end
  end
  if type(setQuestName) == "function" then
    button.SetQuestName = function(b, questInfo, ...)
      local ja
      if DialogueUI.active() and type(questInfo) == "table" and type(questInfo.title) == "string"
          and type(questInfo.questID) == "number" then
        local ok, text = guarded(questRow, questInfo)
        ja = ok and text or nil
      end
      guarded(dressRow, b, ja ~= nil)
      if not ja then return setQuestName(b, questInfo, ...) end
      local title = questInfo.title
      return during(function() questInfo.title = ja end, function() questInfo.title = title end,
        setQuestName, b, questInfo, ...)
    end
  end
end

-- The progress page's objective lines ("- Kobold Vermin slain: 3/10", one per line) → the text with each shipped
-- line in Japanese, or nil when none is
local function objectiveLines(self, text)
  if self.handler ~= "HandleQuestProgress" or type(text) ~= "string" or text:sub(1, 2) ~= "- " then return nil end
  touched = true
  local out, any = {}, false
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local core = line:match("^%- (.*)$")
    local ja = core and WFJ.QuestMap and WFJ.QuestMap.objectiveJapanese(core, S.rows) or nil
    if type(ja) == "string" and ja ~= "" and ja ~= core then
      out[#out + 1] = "- " .. ja
      any = true
    else
      out[#out + 1] = line
    end
  end
  return any and table.concat(out, "\n") or nil
end

-- The quest title in the page header: a widget of its own, rendered after Dialogue UI wrote it.
local function showTitle(self)
  local header = type(self.FrontFrame) == "table" and self.FrontFrame.Header
  local fs = type(header) == "table" and header.Title or nil
  local id, en = call("getQuestID"), call("getTitle")
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" or type(id) ~= "number" or id == 0
      or type(en) ~= "string" or en == "" or fs:GetText() ~= en then
    return
  end
  touched = true
  WFJ.Render.show(S.title, "title", fs, en, "quests", "quest.title", id, { live = en, compact = true })
end

-- ── The wrappers ───────────────────────────────────────────────────────────

local WRAP = {}

function WRAP.FormatParagraph(orig)
  return function(self, offsetY, text, ...)
    if not DialogueUI.active() then return orig(self, offsetY, text, ...) end
    local ok, el = guarded(identify, self, text)
    if not ok or not el then return orig(self, offsetY, text, ...) end
    touched = true
    local shown, h = guarded(render, el)
    if not shown then return orig(self, offsetY, text, ...) end
    el.holder, el.fontStrings = h, {}
    local res = pack(during(function() current = el end, function() current = nil end,
      orig, self, offsetY, el.prefix .. h.text, ...))
    guarded(attachCards, el)
    return unpack(res, 1, res.n)
  end
end

function WRAP.FormatQuestText(orig)
  return function(self, offsetY, method, ...)
    local prev = questText
    return during(function() questText = method end, function() questText = prev end, orig, self, offsetY, method, ...)
  end
end

function WRAP.AcquireLeftFontString(orig)
  return function(self, obj, ...)
    local fs = orig(self, obj, ...)
    if type(fs) == "table" then guarded(dress, fs, obj) end
    return fs
  end
end

function WRAP.InsertText(orig)
  return function(self, offsetY, text, obj, ...)
    if not DialogueUI.active() then return orig(self, offsetY, text, obj, ...) end
    local ok, ja = guarded(objectiveLines, self, text)
    if not ok or not ja then return orig(self, offsetY, text, obj, ...) end
    return during(function() japaneseRows = true end, function() japaneseRows = false end,
      orig, self, offsetY, ja, obj, ...)
  end
end

function WRAP.AcquireOptionButton(orig)
  return function(self, ...)
    local b = orig(self, ...)
    if type(b) == "table" then guarded(patch, b) end
    return b
  end
end

-- The page is drawn again by Dialogue UI's own redraw (it runs the page's handler again a frame later), so its
-- layout fits the text now showing.
local function redraw()
  if not (DialogueUI.active() and touched and frame) then return end
  if type(frame.IsVisible) == "function" and not frame:IsVisible() then return end
  frame:OnSettingsChanged()
end

local function release()
  detachCards()
  touched = false
  for _, h in pairs(holders) do h.shown = nil end
  for _, s in pairs(S) do WFJ.Render.release(s) end
end

-- Installs the wrappers on DUIQuestFrame when every member is there. → true when installed now
function DialogueUI.install()
  if installed then return false end
  local f = Compat.resolve("DUIQuestFrame") -- read now: it may come after this addon's load
  if type(f) ~= "table" then return false end
  for _, m in ipairs(DialogueUI.MEMBERS) do
    if type(f[m]) ~= "function" then
      if WFJ.Diag then pcall(WFJ.Diag.log, "dialogueui", "Dialogue UI's window has no " .. m .. ": left in English") end
      return false
    end
  end
  frame = f
  for name, wrap in pairs(WRAP) do f[name] = wrap(f[name]) end
  local hook = Compat.resolve("hooksecurefunc")
  hook(f, "UpdateQuestTitle", function(self) guarded(showTitle, self) end)
  -- every page handler starts here: the page's paragraphs are about to be released and laid out again
  hook(f, "ReleaseAllObjects", function()
    detachCards()
    touched = false
  end)
  local createFrame = Compat.resolve("CreateFrame")
  if type(createFrame) == "function" then
    -- Dialogue UI sets its window's OnHide script again after load (a HookScript on it would be dropped): a child
    -- frame of ours hears the window close
    local watcher = createFrame("Frame", nil, f)
    watcher:SetScript("OnHide", function() guarded(release) end)
    watcher:Show()
  end
  for _, event in ipairs({ "modifier", "enabled", "area", "markers" }) do
    WFJ.State.on(event, function() guarded(redraw) end)
  end
  if WFJ.VoicePlayer and type(WFJ.VoicePlayer.addWindow) == "function" then
    -- "npc" is the unit Dialogue UI itself names the speaker by on quest and gossip pages
    WFJ.VoicePlayer.addWindow("DUIQuestFrame", { S.detail, S.progress, S.reward, S.greeting, S.gossip }, "npc")
  end
  installed = true
  if WFJ.Diag then pcall(WFJ.Diag.log, "dialogueui", "Dialogue UI found: its quest and gossip window gets Japanese") end
  return true
end

-- Main: `d` = { key(text) → gossip key }. Installs now when Dialogue UI is loaded, else when it loads.
-- → true when installed now
function DialogueUI.init(d)
  deps = d or {}
  WFJ.LoadOnDemand.when("DialogueUI", function() DialogueUI.install() end)
  return installed
end
