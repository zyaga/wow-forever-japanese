-- UI/DialogueUI.lua: the Dialogue UI addon's quest and gossip window, when the player has that addon (ADR-073).
-- Dialogue UI turns the client's quest and gossip windows off and draws the same text in its own frame,
-- DUIQuestFrame. This module replaces a few methods on that one frame with wrappers that put the Japanese in before
-- Dialogue UI lays the text out, and always call the original. Nothing of Dialogue UI is shipped or required:
-- without it, or with a version whose frame lacks a member listed below, nothing is installed and its window shows
-- its English. The lines, keys, markers, fonts, word cards and voice are the ones the client's windows get.
-- UI/DialogueUIBook does the same for its book window and shares the helpers exported here.
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
local inRow = false -- a gossip option or quest row is writing its label: it keeps its own Japanese and face
local touched = false -- the page shows a line this module looked up: a reveal key or switch change redraws it
local holders = {} -- surface .. key → text holder
local cards = {} -- word-card records on the page's paragraphs
local patched = setmetatable({}, { __mode = "k" }) -- option buttons whose writers are wrapped
-- English → gossip key: the key hashes the text for several player-name forms, and a page draws its gossip text and
-- every option again on each redraw. Emptied when it grows past KEY_CACHE_MAX.
local keyCache, keyCount, KEY_CACHE_MAX = {}, 0, 500
local lastHandler -- the page handler Dialogue UI ran last: another page's lines are shown anew, as a new window's
local scrollTo -- where the reader was when this module asked for a redraw (the redraw scrolls to the top)

local function call(key, ...)
  local fn = Compat.get(SURFACE, key)
  if type(fn) ~= "function" then return nil end
  return fn(...)
end

local function gossipKey(en)
  local k = keyCache[en]
  if k == nil and type(deps.key) == "function" then
    k = deps.key(en)
    if keyCount >= KEY_CACHE_MAX then keyCache, keyCount = {}, 0 end
    keyCache[en], keyCount = k or false, keyCount + 1
  end
  return k or nil
end

function DialogueUI.installed() return installed end
-- false once repeated errors switched both Dialogue UI modules off for the session
function DialogueUI.healthy() return errors < MAX_ERRORS end
function DialogueUI.active() return installed and errors < MAX_ERRORS end

local function settle(ok, ...)
  if ok then return true, ... end
  errors = errors + 1
  local E = WFJ.ErrorLog
  if E and type(E.recordCaught) == "function" then pcall(E.recordCaught, tostring((...))) end
  if errors == MAX_ERRORS and WFJ.Diag then
    pcall(WFJ.Diag.log, "dialogueui", "errors in Dialogue UI's windows: left in English for this session")
  end
  return false
end

-- Runs `fn` guarded: an error is recorded and counted, and after MAX_ERRORS both Dialogue UI modules stop changing
-- text for the session; every wrapper then passes Dialogue UI's own text through. → true, results | false
function DialogueUI.guarded(fn, ...)
  return settle(pcall(fn, ...))
end
local guarded = DialogueUI.guarded

-- The ends of a wrapped call that set a module state for its duration: the state is put back even when the
-- original errors (the error is Dialogue UI's own and is raised again).
local function raise(ok, ...)
  if not ok then error((...), 0) end
  return ...
end
local function endText(ok, ...) current = nil; return raise(ok, ...) end
local function endRows(ok, ...) japaneseRows = false; return raise(ok, ...) end
local function endQuestText(prev, ok, ...) questText = prev; return raise(ok, ...) end
local function endTitle(info, title, ok, ...) info.title = title; inRow = false; return raise(ok, ...) end
local function endRow(ok, ...) inRow = false; return raise(ok, ...) end

-- ── Shared with UI/DialogueUIBook ──────────────────────────────────────────

-- A stand-in widget for one text (the gossip, a quest field, a book page): Render writes our Japanese and its font
-- here, and the module hands that text to Dialogue UI, which lays it out itself.
local Holder = {}
Holder.__index = Holder
function Holder:GetText() return self.text end
function Holder:SetText(t) self.text = t end
function Holder:GetFont() return self.font.path, self.font.size, self.font.flags end
function Holder:SetFont(path, size, flags)
  self.font = { path = path, size = size, flags = flags or "" }
  return true
end
function DialogueUI.newHolder(text, font)
  return setmetatable({ text = text or "", font = font or { flags = "" } }, Holder)
end

-- A word-card record on `fs`, which shows `text`, the part of a line that starts at byte `at` of the line as the
-- word list counts it (`listed`, from Readings.lookup) once `shift` bytes Dialogue UI put before the line are added.
-- Appended to `list` and attached.
function DialogueUI.attachCard(list, surface, key, fs, text, kind, id, listed, at, shift)
  local V = WFJ.ReadingView
  if not (V and type(V.attach) == "function") then return end
  local spans, last = {}, at + #text - 1
  for _, sp in ipairs(listed or {}) do
    local first, stop = sp.first + shift, sp.last + shift
    if first >= at and stop <= last then
      spans[#spans + 1] = { first = first - at + 1, last = stop - at + 1, word = sp.word, reading = sp.reading,
        gloss = sp.gloss, card = sp.card }
    end
  end
  local rec = { surface = surface, key = key, fs = fs, applied = text, meta = { kind = kind, id = id }, spans = spans }
  list[#list + 1] = rec
  pcall(V.attach, rec)
end

-- Takes the cards in `list` down. → a new, empty list
function DialogueUI.detachCards(list)
  local V = WFJ.ReadingView
  if V and type(V.detach) == "function" then
    for _, rec in ipairs(list) do pcall(V.detach, rec) end
  end
  return {}
end

-- While either Dialogue UI window is open, the voice panel is lifted out from under the interface Dialogue UI fades.
function DialogueUI.liftPanel()
  local P = WFJ.VoicePanel
  if not (P and type(P.lift) == "function") then return end
  local open = false
  for _, name in ipairs({ "DUIQuestFrame", "DUIBookFrame" }) do
    local w = Compat.resolve(name)
    if type(w) == "table" and type(w.IsShown) == "function" and w:IsShown() then open = true end
  end
  -- Dialogue UI shows the interface again only out of combat: closed in combat, the panel stays up until it does
  local ui = Compat.resolve("UIParent")
  if not open and type(ui) == "table" and type(ui.IsShown) == "function" and not ui:IsShown() then open = true end
  P.lift(open)
end

-- `fn` runs when Dialogue UI's window `f` closes. Dialogue UI sets its window's OnHide script again after load (a
-- HookScript on it would be dropped), so a child frame of ours hears it instead.
function DialogueUI.onClose(f, fn)
  local createFrame = Compat.resolve("CreateFrame")
  if type(createFrame) ~= "function" then return end
  local watcher = createFrame("Frame", nil, f)
  watcher:SetScript("OnHide", function()
    guarded(fn)
    guarded(DialogueUI.liftPanel)
  end)
  watcher:Show()
  -- Dialogue UI keeps OnShow as it is: a hook there hears the window open
  if type(f.HookScript) == "function" then f:HookScript("OnShow", function() guarded(DialogueUI.liftPanel) end) end
  if type(f.IsShown) == "function" and f:IsShown() then guarded(DialogueUI.liftPanel) end
end

-- The bundled face on a FontString for Japanese, else the owner's face back (re-applying its font object leaves a
-- face set since in place, so a string given its face back follows the object's size when the player changes it).
local function face(fs, obj, japanese)
  if japanese then
    WFJ.Font.bundle(fs, obj)
  elseif WFJ.Font.dressed(fs) then
    WFJ.Font.restore(fs, obj)
  else
    WFJ.Font.follow(fs, obj)
  end
end

-- ── One text of the page ───────────────────────────────────────────────────

local function holder(surface, key)
  local id = surface .. "\0" .. key
  local h = holders[id]
  if not h then
    h = DialogueUI.newHolder()
    holders[id] = h
  end
  return h
end

local function paragraphFontObject()
  return Compat.resolve("DUIFont_Quest_Paragraph") -- Dialogue UI's own name: not declared, absent without it
end

local function paragraphFont()
  local obj = paragraphFontObject()
  if type(obj) == "table" and type(obj.GetFont) == "function" then
    local path, size, flags = obj:GetFont()
    if path then return { path = path, size = size, flags = flags or "" } end
  end
  return { path = WFJ.Font.CLIENT, size = 13, flags = "" }
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
    if type(en) ~= "string" or en == "" then return nil end
    el = { surface = handler == "HandleGossip" and S.gossip or S.greeting, key = "greeting", en = en,
      area = "gossip", kind = "gossip", id = gossipKey(en) }
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
  -- the font is left to the record: a record of the last line on this holder carries the face it applied, so setting
  -- the holder's font here would make that face look applied when it is not
  h.text, h.shown = el.en, nil
  if not h.font.path then h.font = paragraphFont() end
  -- the English Collector hears these lines as it does on the client's windows
  local C = WFJ.Collector
  local guid = Compat.resolve("UnitGUID")
  guid = type(guid) == "function" and guid("npc") or nil
  if not (C and type(C.record) == "function" and type(C.recordGossip) == "function") then
    C = nil
  end
  if C and el.kind == "gossip" and el.area == "gossip" then
    C.recordGossip(el.en, guid)
  elseif C and el.questID and not (el.kind == "gossip" and el.key == "description") then
    -- a description that is another wording of the quest for this character is not the quest's own
    C.record("quest", el.questID, el.key, el.en)
  end
  WFJ.Render.show(el.surface, el.key, h, el.en, el.area, el.kind, el.id, { live = el.live })
  h.shown = true -- a show that failed half way is shown anew next time
  -- UI/VoicePlayer remembers who showed a quest line, for replays from the quest log
  if el.panel and el.key ~= "objectives" then pcall(WFJ.State.fire, "questShown", el.questID, el.panel) end
  return h
end

-- Word cards on the paragraphs Dialogue UI just made of our Japanese, each with its share of the line's words.
local function attachCards(el)
  local rec = WFJ.SurfaceState.get(el.surface, el.key)
  local text = el.holder.text
  if not (rec and rec.applied ~= nil and rec.applied == text) then return end -- English showing: no cards
  local R = WFJ.Readings
  local listed = R and type(R.lookup) == "function" and R.lookup(el.kind, el.id, text) or nil
  local full, from = el.prefix .. text, 1
  for i, fs in ipairs(el.fontStrings) do
    local t = fs:GetText()
    local at = type(t) == "string" and t ~= "" and full:find(t, from, true) or nil
    if at then
      from = at + #t
      DialogueUI.attachCard(cards, el.surface, el.key .. "." .. i, fs, t, el.kind, el.id, listed, at, #el.prefix)
    end
  end
end

local function forgetLines()
  for _, h in pairs(holders) do h.shown = nil end
  for _, s in pairs(S) do WFJ.Render.release(s) end
end

-- the page is about to be laid out again, or its window closed
local function resetPage()
  cards = DialogueUI.detachCards(cards)
  touched = false
end

-- ReleaseAllObjects starts every page: a page of another kind (gossip, then a quest offer) forgets the lines of the
-- last one, as the client's windows do when one closes and another opens; the same page drawn again keeps them.
local function newPage(self)
  resetPage()
  if self.handler ~= lastHandler then
    forgetLines()
    lastHandler = self.handler
  end
end

-- ── Fonts ───────────────────────────────────────────────────────────────────

local function fontObject(obj)
  if type(obj) == "string" then obj = Compat.resolve(obj) end
  if type(obj) ~= "table" then obj = paragraphFontObject() end
  return type(obj) == "table" and obj or nil
end

-- A pooled FontString Dialogue UI just acquired: the bundled face for our Japanese before Dialogue UI measures it.
local function dress(fs, obj)
  face(fs, fontObject(obj), japaneseRows or (current ~= nil and current.holder.font.path == WFJ.Font.PATH))
  if current then current.fontStrings[#current.fontStrings + 1] = fs end
end

local function dressRow(button, japanese)
  local fs = button.Name
  if type(fs) ~= "table" or type(fs.GetFont) ~= "function" then return end
  face(fs, type(fs.GetFontObject) == "function" and fs:GetFontObject() or nil, japanese)
end

-- ── Rows: titles, options, objective lines (no records, no markers) ────────

local function rowJapanese(en, area, kind, id, live)
  touched = true
  local text, _, action = WFJ.Render.preview(S.rows, en, nil, area, kind, id, { compact = true, live = live })
  if action == "apply" and type(text) == "string" then return text end
  return nil
end

-- Dialogue UI's buttons and section headings are mostly the game's own words (its locale reads them from the client's
-- strings [read: Dialogue UI 1.0.7 b, Locales/enUS.lua]): a label that is exactly one of the client's interface
-- strings gets that string's Japanese, as on the client's windows.
local function gameWord(en)
  if type(en) ~= "string" or en == "" then return nil end
  local index = WFJ.UIIndex
  local key = index and type(index.exactKey) == "function" and index:exactKey(en) or nil
  if key then return rowJapanese(en, "ui", "ui", key) end
  return nil
end

-- Heading words Dialogue UI writes itself where the client has no string of its own (Forever has no REQUIREMENTS), in
-- the addon's own Japanese like the voice panel's words: shown under the same switches as the game's words.
local OWN_WORDS = { Requirements = "必要なもの" }
local function headingWord(en)
  local ja = gameWord(en)
  if ja or OWN_WORDS[en] == nil then return ja end
  touched = true
  local S_ = WFJ.State
  if S_ and S_.enabled and not S_.modifierHeld and S_.areaEnabled("ui") then return OWN_WORDS[en] end
  return nil
end

local function gossipRow(name)
  local C = WFJ.Collector
  local guid = Compat.resolve("UnitGUID")
  if C and type(C.recordGossip) == "function" then
    C.recordGossip(name, type(guid) == "function" and guid("npc") or nil)
  end
  local id = gossipKey(name)
  return id and rowJapanese(name, "gossip", "gossip", id) or nil
end

local function questRow(questInfo)
  return rowJapanese(questInfo.title, "quests", "quest.title", questInfo.questID, questInfo.title)
end

-- for UI/DialogueUIFrames: lookups for frames that are not the page (they never mark the page for a redraw)
local function apart(fn)
  return function(...)
    local was = touched
    local res = { fn(...) }
    touched = was
    return unpack(res)
  end
end
DialogueUI.preview, DialogueUI.gameWord, DialogueUI.questTitle = apart(rowJapanese), apart(gameWord), apart(questRow)
DialogueUI.face = function(...) return face(...) end

-- A gossip option's label with the Japanese in place of its English name, laid out again by the button. Dialogue UI
-- picks some options' icons by their English name, so the option is first set as it is and only its label changes.
local function relabel(b, name, ja)
  local label = b.Name:GetText()
  if type(label) ~= "string" then return end
  local s, e = label:find(name, 1, true)
  if s then b:SetButtonText(label:sub(1, s - 1) .. ja .. label:sub(e + 1), false) end
end

local function relabelAfter(b, data, ja, ...)
  if ja then guarded(relabel, b, data.name, ja) end
  return ...
end
local function gossipThenLabel(setGossip, b, data, ja, ...)
  return relabelAfter(b, data, ja, setGossip(b, data, ...))
end

-- The writers of one option button: a gossip option's label gets the Japanese name after Dialogue UI set it, a quest
-- row its Japanese title for the call (Dialogue UI writes the label again from the same questInfo when the quest
-- loads); the answer hint is Dialogue UI's own text in its own face.
local function patch(button)
  if patched[button] then return end
  patched[button] = true
  local setGossip, setQuestName, setHint = button.SetGossip, button.SetQuestName, button.SetGossipHint
  local setText = button.SetButtonText
  if type(setText) == "function" then
    -- a button label that is one of the game's words (Goodbye, Accept, Cancel …); a gossip option or quest row writes
    -- its label through here too, and keeps its own Japanese (inRow)
    button.SetButtonText = function(b, name, ...)
      if inRow then return setText(b, name, ...) end
      local ja
      if DialogueUI.active() then
        local ok, text = guarded(gameWord, name)
        ja = ok and text or nil
      end
      guarded(dressRow, b, ja ~= nil)
      return setText(b, ja or name, ...)
    end
  end
  if type(setGossip) == "function" and type(button.SetButtonText) == "function" then
    button.SetGossip = function(b, data, ...)
      local ja
      if DialogueUI.active() and type(data) == "table" and type(data.name) == "string" then
        local ok, text = guarded(gossipRow, data.name)
        ja = ok and text or nil
      end
      guarded(dressRow, b, ja ~= nil)
      inRow = true
      return endRow(pcall(gossipThenLabel, setGossip, b, data, ja, ...))
    end
  end
  if type(setHint) == "function" then
    button.SetGossipHint = function(b, ...)
      guarded(dressRow, b, false)
      return setHint(b, ...)
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
      inRow = true
      if not ja then return endRow(pcall(setQuestName, b, questInfo, ...)) end
      local title = questInfo.title
      questInfo.title = ja
      return endTitle(questInfo, title, pcall(setQuestName, b, questInfo, ...))
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

local function formatted(el, ...)
  guarded(attachCards, el)
  return ...
end

function WRAP.FormatParagraph(orig)
  return function(self, offsetY, text, ...)
    if not DialogueUI.active() then return orig(self, offsetY, text, ...) end
    local ok, el = guarded(identify, self, text)
    if not ok or not el then return orig(self, offsetY, text, ...) end
    touched = true
    local shown, h = guarded(render, el)
    if not shown then return orig(self, offsetY, text, ...) end
    el.holder, el.fontStrings = h, {}
    current = el
    return formatted(el, endText(pcall(orig, self, offsetY, el.prefix .. h.text, ...)))
  end
end

function WRAP.FormatQuestText(orig)
  return function(self, offsetY, method, ...)
    local prev = questText
    questText = method
    return endQuestText(prev, pcall(orig, self, offsetY, method, ...))
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
    if not (ok and ja) then ok, ja = guarded(gameWord, text) end -- a reward line ("You will be able to choose …")
    if not ok or not ja then return orig(self, offsetY, text, obj, ...) end
    japaneseRows = true
    return endRows(pcall(orig, self, offsetY, ja, obj, ...))
  end
end

-- Members wrapped when Dialogue UI has them (not required: without them its headings and footer buttons stay
-- English).
local OPTIONAL = {}

local lastFs -- the FontString AcquireFontString handed out last (a section heading's, see below)
local function undress(fs)
  if WFJ.Font.dressed(fs) then WFJ.Font.restore(fs) end
end

function OPTIONAL.AcquireFontString(orig)
  return function(self, ...)
    local fs = orig(self, ...)
    if type(fs) == "table" then
      lastFs = fs
      guarded(undress, fs)
    end
    return fs
  end
end

-- A section heading: Dialogue UI sizes the band behind it from the text's width in its own face, so the band is
-- sized again once the heading wears ours (the same padding as Dialogue UI's, 8 each side).
local function fitHeading(bg, fs)
  if type(fs) ~= "table" or type(bg) ~= "table" then return end
  WFJ.Font.bundle(fs, Compat.resolve("DUIFont_Quest_SubHeader"))
  if type(fs.GetWrappedWidth) == "function" and type(bg.GetHeight) == "function" then
    bg:SetSize(math.floor(fs:GetWrappedWidth() + 16 + 0.5), bg:GetHeight())
  end
end

function OPTIONAL.AcquireAndSetSubHeader(orig)
  return function(self, text, ...)
    local ja
    if DialogueUI.active() then
      local ok, t = guarded(headingWord, text)
      ja = ok and t or nil
    end
    if not ja then return orig(self, text, ...) end
    lastFs = nil
    local bg = orig(self, ja, ...)
    -- only the heading just written: a Dialogue UI that gets it another way leaves the band as it sized it
    local fs = lastFs
    if type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() == ja then
      guarded(fitHeading, bg, fs)
    end
    return bg
  end
end

-- The reward list's headings ("You will also receive:"): Dialogue UI sets them straight on a pooled FontString, so they
-- get their Japanese once the list is built. A body paragraph (it carries Dialogue UI's speech flag) is never one.
local function rewardHeadings(self)
  local pool = self.fontStringPool
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return end
  for _, fs in pool:EnumerateActive() do
    if type(fs) == "table" and fs.ttsFlag == nil and type(fs.GetText) == "function" then
      local ja = gameWord(fs:GetText())
      if ja then
        face(fs, Compat.resolve("DUIFont_Quest_Paragraph"), true)
        fs:SetText(ja)
      end
    end
  end
end

function OPTIONAL.FormatRewards(orig)
  return function(self, ...)
    return (function(...)
      if DialogueUI.active() then guarded(rewardHeadings, self) end
      return ...
    end)(orig(self, ...))
  end
end

local function footer(orig)
  return function(self, ...)
    local b = orig(self, ...)
    if type(b) == "table" then guarded(patch, b) end
    return b
  end
end
OPTIONAL.AcquireAcceptButton = footer
OPTIONAL.AcquireExitButton = footer

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
  local sf = frame.ScrollFrame
  scrollTo = type(sf) == "table" and (sf.scrollTarget or sf.value) or nil
  frame:OnSettingsChanged()
end

-- after a page handler ran for the redraw this module asked for: back to where the reader was
local headerTags -- below, with the other pieces found by their shape
local function restoreScroll(self)
  if DialogueUI.active() then guarded(headerTags, self) end
  local v = scrollTo
  scrollTo = nil
  local sf = self.ScrollFrame
  if type(v) == "number" and v > 0 and type(sf) == "table" and type(sf.SnapTo) == "function" then sf:SnapTo(v) end
end

local function release()
  resetPage()
  forgetLines()
  lastHandler, scrollTo = nil, nil
end

-- The tags over a quest page's title ("Daily", "Dungeon") are buttons Dialogue UI makes as needed; one holding a game
-- string gets its Japanese through its own SetText and is laid out again. A tag Dialogue UI fills in after the page
-- drew (its quest data came late) is written by the button's own SetQuestTagNameAndIcon [read: Dialogue UI 1.0.7 b,
-- QuestHeaderWidget.lua]: each tag button found is followed there too, once.
local tagFollowed = setmetatable({}, { __mode = "k" })

-- A tag's Japanese can end up in Dialogue UI's own face, which has no Japanese letters (empty boxes). The one known
-- path, a later pass over a tag that already shows the Japanese, is handled in tagJapanese. This check is the
-- backstop for any other: the tag is looked at again the next frame, a face that is not ours is logged with what it
-- was, the bundled face goes back on and the tag is laid out again.
local function tagFaceAgain(child, fs, ja)
  if type(fs.GetFont) ~= "function" or fs:GetText() ~= ja then return end
  local path, size, flags = fs:GetFont()
  if path == WFJ.Font.PATH then return end
  local obj = type(fs.GetFontObject) == "function" and fs:GetFontObject() or nil
  local objName = type(obj) == "table" and type(obj.GetName) == "function" and obj:GetName() or nil
  WFJ.Diag.log("font", "dialogueui tag face", { path = tostring(path), size = tostring(size),
    flags = tostring(flags), object = tostring(objName or (type(obj) == "table" and obj.name) or "none") })
  face(fs, nil, true)
  if type(child.Layout) == "function" then child:Layout() end
end

-- A tag button keeps its text after Dialogue UI is done with it, and every page's pass walks all of them. A tag
-- still showing the Japanese written here is no game word, so the lookup finds nothing: without this record the
-- pass would take that for a tag that was never ours and hand Dialogue UI's face back under the Japanese.
local tagOurs = setmetatable({}, { __mode = "k" }) -- the tag's text widget → the Japanese written on it

local function tagJapanese(child)
  local fs = type(child) == "table" and child.ButtonText or nil
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" or type(child.SetText) ~= "function" then return end
  local text = fs:GetText()
  local mine = tagOurs[fs]
  if mine and text == mine then
    face(fs, nil, true)
    return
  end
  local ja = gameWord(text)
  tagOurs[fs] = ja
  face(fs, nil, ja ~= nil)
  if ja then
    child:SetText(ja)
    -- its own Layout sizes the tag to its text [read: Dialogue UI 1.0.7 b, QuestHeaderWidget.lua]
    if type(child.Layout) == "function" then child:Layout() end
    local timer = Compat.resolve("C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
      timer.After(0, function() guarded(tagFaceAgain, child, fs, ja) end)
    end
  end
end
headerTags = function(self)
  local front = type(self.FrontFrame) == "table" and self.FrontFrame or nil
  local header = front and type(front.Header) == "table" and front.Header or nil
  for _, parent in ipairs({ header, front }) do
    if type(parent) == "table" then
      for _, child in ipairs(WFJ.Frames.children(parent)) do
        if type(child) == "table" and not tagFollowed[child] and type(child.SetQuestTagNameAndIcon) == "function" then
          tagFollowed[child] = true
          hooksecurefunc(child, "SetQuestTagNameAndIcon", function(b)
            if DialogueUI.active() then DialogueUI.guarded(tagJapanese, b) end
          end)
        end
        tagJapanese(child)
      end
    end
  end
end

local install -- defined below; DialogueUI.install runs it guarded

-- Installs the wrappers on DUIQuestFrame when every member is there. Any error on the way is recorded and Dialogue UI
-- keeps its English. → true when installed now
function DialogueUI.install()
  if installed then return false end
  local ok, done = pcall(install)
  if ok then return done == true end
  local E = WFJ.ErrorLog
  if E and type(E.recordCaught) == "function" then pcall(E.recordCaught, tostring(done)) end
  if WFJ.Diag then pcall(WFJ.Diag.log, "dialogueui", "Dialogue UI support failed to install: left in English") end
  return false
end

install = function()
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
  for name, wrap in pairs(OPTIONAL) do
    if type(f[name]) == "function" then f[name] = wrap(f[name]) end
  end
  for _, b in ipairs({ f.AcceptButton, f.ExitButton }) do -- made at Dialogue UI's load
    if type(b) == "table" then guarded(patch, b) end
  end
  local ui = Compat.resolve("UIParent")
  if type(ui) == "table" and type(ui.HookScript) == "function" then
    ui:HookScript("OnShow", function() guarded(DialogueUI.liftPanel) end) -- the interface back: the panel goes down
  end
  -- its tooltip, chat panel and quest popups (UI/DialogueUIFrames)
  if WFJ.DialogueUIFrames then guarded(WFJ.DialogueUIFrames.install, f) end
  local hook = Compat.resolve("hooksecurefunc")
  hook(f, "UpdateQuestTitle", function(self) guarded(showTitle, self) end)
  -- every page handler starts here: the page's paragraphs are about to be released and laid out again
  hook(f, "ReleaseAllObjects", function(self) guarded(newPage, self) end)
  for _, handler in ipairs({ "HandleGossip", "HandleQuestDetail", "HandleQuestProgress", "HandleQuestComplete",
    "HandleQuestGreeting" }) do
    hook(f, handler, function(self) guarded(restoreScroll, self) end)
  end
  DialogueUI.onClose(f, release)
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
