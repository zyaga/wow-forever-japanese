-- UI/DialogueUI.lua: the Dialogue UI addon's quest and gossip window, when the player has that addon (ADR-073).
-- Dialogue UI turns the client's quest and gossip windows off and draws the same text in its own frame,
-- DUIQuestFrame. Every method of that frame and of its buttons is left as Dialogue UI made it: this module only
-- follows them with hooksecurefunc, so Dialogue UI's own code runs first and untouched, and the Japanese is written
-- afterwards into the FontStrings it wrote. A method replaced by a function of ours would run Dialogue UI's code, and
-- every value it writes (the click handler an option button keeps), on this addon's taint, and a later click would
-- carry it into the game's own windows (ADR-073). A paragraph's Japanese goes in through a hook on the FontString's
-- SetText, which runs before Dialogue UI measures it, so its layout fits the Japanese. Nothing of Dialogue UI is
-- shipped or required: without it, or with a version whose frame lacks a member listed below, nothing is installed
-- and its window shows its English. The lines, keys, markers, fonts, word cards and voice are the ones the client's
-- windows get. UI/DialogueUIBook does the same for its book window and shares the helpers exported here.
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

-- The members of DUIQuestFrame this module follows or relies on [read: Dialogue UI 1.0.7 c,
-- Code/Dialogue/DialogueUI.lua: every page handler starts with self:ReleaseAllObjects(); FormatParagraph splits its
-- text on control characters and, for each piece, takes a FontString from self:AcquireLeftFontString (which takes it
-- from self:AcquireFontString), sets the piece and measures it at once; InsertText and AcquireAndSetSubHeader do the
-- same with one text]
DialogueUI.MEMBERS = { "FormatParagraph", "AcquireFontString", "AcquireLeftFontString", "InsertText",
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
local hook -- hooksecurefunc, read at install
local MAX_ERRORS = 5
local errors = 0
local run -- the line whose paragraphs Dialogue UI is writing now: { holder, slots, english, done, fontStrings, … }
local writing = false -- this module is writing a text: the hook on that FontString lets its own write pass
local touched = false -- the page shows a line this module looked up: a reveal key or switch change redraws it
local holders = {} -- surface .. key → text holder
local cards = {} -- word-card records on the page's paragraphs
local patched = setmetatable({}, { __mode = "k" }) -- option buttons whose writers are followed
local followed = setmetatable({}, { __mode = "k" }) -- pooled FontStrings whose SetText is followed
-- A pooled FontString handed out by AcquireLeftFontString holds body text (a paragraph, an objective line, a reward
-- line): FontString → { obj = the font object it was asked for }. One from AcquireFontString alone is a heading.
local body = setmetatable({}, { __mode = "k" })
local newest -- the FontString AcquireFontString handed out last
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

-- `text` written into `fs` by this module: the hook that follows that FontString's SetText lets it pass.
function DialogueUI.write(fs, text)
  writing = true
  local ok, err = pcall(fs.SetText, fs, text)
  writing = false
  if not ok then error(err, 0) end
end
-- true while this module itself writes a FontString (the hooks of UI/DialogueUIFrames pass it by too)
function DialogueUI.writing() return writing end
local write = DialogueUI.write

-- Text pieces as Dialogue UI splits a text into paragraphs (on control characters, a lone space dropped), each with
-- where it starts and ends in the text [read: Dialogue UI 1.0.7 c, API.lua SplitParagraph].
local function pieces(text)
  local out = {}
  for s, piece, e in text:gmatch("()([^%c]+)()") do
    if piece ~= " " then out[#out + 1] = { s = s, e = e - 1, text = piece } end
  end
  return out
end
DialogueUI.pieces = pieces

-- `full` (a line's text to show) spread over the `n` paragraphs Dialogue UI made of the English. → { text per
-- paragraph } | nil. Dialogue UI made as many FontStrings as the English has paragraphs, so a text with more pieces
-- puts the first ones together in the first (a marker line stays right above the first paragraph), and one with
-- fewer leaves the last ones empty.
function DialogueUI.spread(full, n)
  local p = pieces(full)
  if #p == 0 or n < 1 then return nil end
  local slots = {}
  if #p >= n then
    local extra = #p - n
    slots[1] = full:sub(p[1].s, p[1 + extra].e)
    for i = 2, n do slots[i] = p[i + extra].text end
  else
    for i = 1, n do slots[i] = p[i] and p[i].text or "" end
  end
  return slots
end
local spread = DialogueUI.spread

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

-- Dialogue UI's windows open and close, and the interface they hide comes back, inside Dialogue UI's own show and
-- hide calls: when it shows the interface again, the game's windows that come back with it (the bags, a vendor) run
-- their OnShow in that same call. A script or hook of this addon in there would leave its taint for them, so these
-- changes are seen from a frame of this addon's own, outside the interface (no parent), that looks each frame.
local watched = {} -- { frame, closed, opened, shown }
local UI_EVERY = 0.2 -- seconds between looks at the interface itself
local sinceUi, uiShown = 0, nil

local function shownNow(f)
  return type(f) == "table" and type(f.IsShown) == "function" and f:IsShown() and true or false
end

local function watch(_, elapsed)
  local changed = false
  for _, w in ipairs(watched) do
    local shown = shownNow(w.frame)
    if shown ~= w.shown then
      if w.shown and not shown and w.closed then guarded(w.closed) end
      if shown and not w.shown and w.opened then guarded(w.opened) end
      w.shown, changed = shown, true
    end
  end
  sinceUi = sinceUi + (type(elapsed) == "number" and elapsed or 0)
  if sinceUi >= UI_EVERY then
    sinceUi = 0
    local shown = shownNow(Compat.resolve("UIParent"))
    if shown ~= uiShown then uiShown, changed = shown, true end
  end
  if changed then guarded(DialogueUI.liftPanel) end
end

local function watchWindow(entry)
  watched[#watched + 1] = entry
  if not DialogueUI.poller then
    local createFrame = Compat.resolve("CreateFrame")
    if type(createFrame) ~= "function" then return nil end
    local poller = createFrame("Frame")
    poller:SetScript("OnUpdate", WFJ.Perf.wrap("idle.dialogueui", watch))
    poller:Show()
    DialogueUI.poller = poller
  end
  return DialogueUI.poller
end

-- `fn` runs once Dialogue UI's window `f` is seen closed, and the voice panel is lifted or put back as windows open and
-- close and the interface comes back. → the watching frame (one for every window)
function DialogueUI.onClose(f, fn) return watchWindow({ frame = f, closed = fn }) end
-- `fn` runs once Dialogue UI's window `f` is seen open.
function DialogueUI.onOpen(f, fn) return watchWindow({ frame = f, opened = fn }) end

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
  HandleQuestDetail = { surface = S.detail, panel = "detail", fields = { "description", "objectives" } },
  HandleQuestProgress = { surface = S.progress, panel = "progress", fields = { "progress" } },
  HandleQuestComplete = { surface = S.reward, panel = "reward", fields = { "completion" } },
}
local GETTER = { description = "getDescription", objectives = "getObjectives", progress = "getProgress",
  completion = "getCompletion" }

-- The game's lines the page Dialogue UI is drawing may lay out as paragraphs → { { surface, key, en, area, kind, id,
-- live, questID, panel } }
local function lines(self)
  local handler, out = self.handler, {}
  if handler == "HandleGossip" or handler == "HandleQuestGreeting" then
    local en = handler == "HandleGossip" and call("getGossip") or call("getGreeting")
    local id = type(en) == "string" and en ~= "" and gossipKey(en) or nil
    if id then
      out[1] = { surface = handler == "HandleGossip" and S.gossip or S.greeting, key = "greeting", en = en,
        area = "gossip", kind = "gossip", id = id }
    end
    return out
  end
  local page = QUEST_PAGES[handler]
  local questID = page and call("getQuestID")
  if type(questID) ~= "number" or questID == 0 then return out end
  for _, field in ipairs(page.fields) do
    local en = call(GETTER[field])
    if type(en) == "string" and en ~= "" then
      local kind, id = WFJ.QuestFrame.fieldSource(questID, field, en)
      if id ~= nil then
        -- live: the values a quest line fills in (`$N1`) and the stale marker's live check come from this text
        out[#out + 1] = { surface = page.surface, key = field, en = en, area = "quests", kind = kind, id = id,
          live = en, questID = questID, panel = page.panel }
      end
    end
  end
  return out
end

-- The line whose first paragraph Dialogue UI just wrote as `text` → the line, with what Dialogue UI put before it in
-- that paragraph (the NPC's name and a colon) as its prefix and its English paragraphs, or nil (not a game line this
-- page shows, e.g. the gossip confirm text). A hint Dialogue UI puts before the gossip is a paragraph of its own and
-- stays as it is.
local function identify(self, text)
  for _, el in ipairs(lines(self)) do
    local en = pieces(el.en)
    local first = en[1] and en[1].text
    if first and #text >= #first and text:sub(-#first) == first then
      el.prefix = text:sub(1, #text - #first)
      el.english = { text }
      for i = 2, #en do el.english[i] = en[i].text end
      return el
    end
  end
  return nil
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
  -- who shows the quest's offer, progress text or turn-in: the Collector keeps the NPC for the line's voice, as on
  -- the client's own quest window (a field with no speaker is refused there)
  local creature = C and el.questID and type(C.recordQuestNpc) == "function" and C.creatureId(guid)
  if creature then
    local sex = Compat.resolve("UnitSex")
    local log = WFJ.VoiceQuestLog
    local display, from
    if log and type(log.displayFor) == "function" then display, from = log.displayFor(creature) end
    -- UnitSex on an NPC unit [unverified on Forever; in-game check in docs/testing/strategy.md]
    pcall(C.recordQuestNpc, el.questID, el.key, guid, type(sex) == "function" and sex("npc") or nil,
      from == "saved" and display or nil)
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
  run = nil
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
  if S_ and S_.enabled and not S_.showsEnglish() and S_.areaEnabled("ui") then return OWN_WORDS[en] end
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

-- Option buttons. Dialogue UI writes a button's label in SetButtonText (the label, then its Layout sizes the button to
-- it), a gossip option's through SetGossip and a quest row's through SetQuestName [read: Dialogue UI 1.0.7 c,
-- Code/Dialogue/UITemplates.lua]. Each runs as Dialogue UI wrote it; afterwards the label FontString gets the
-- Japanese and the button's own Layout sizes it again. Layout only measures and anchors; the fields the button's
-- click reads (onClickFunc, id, gossipOptionID, type) are never written here.
local ROW = { gossip = true, availableQuest = true, activeQuest = true }

-- The label of `b` as `text` (nil: as Dialogue UI left it) in the bundled face or its own, laid out again when
-- anything changed.
local function relabel(b, text, japanese, large)
  local fs = b.Name
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" then return end
  local was = WFJ.Font.dressed(fs)
  dressRow(b, japanese)
  local changed = was ~= WFJ.Font.dressed(fs)
  if text ~= nil and fs:GetText() ~= text then
    fs:SetText(text)
    changed = true
  end
  if changed and type(b.Layout) == "function" then b:Layout(large) end
end

-- A button label that is one of the game's words (Goodbye, Accept, Cancel …). A gossip option or quest row (Dialogue
-- UI set its kind before writing the label) gets its own Japanese from the hooks below, after this one; here it only
-- gets Dialogue UI's face back.
local function buttonText(b, name, large)
  if ROW[b.type] then return relabel(b, nil, false, large) end
  local ja = DialogueUI.active() and gameWord(name) or nil
  relabel(b, ja, ja ~= nil, large)
end

-- A gossip option: its Japanese name in place of the English one inside the label Dialogue UI wrote (it keeps the
-- hotkey, and the icon Dialogue UI picked by the English name).
local function gossipLabel(b, data)
  if not (DialogueUI.active() and type(data) == "table" and type(data.name) == "string") then return end
  local ja = gossipRow(data.name)
  local label = ja and b.Name:GetText()
  if type(label) ~= "string" then return end
  local s, e = label:find(data.name, 1, true)
  if s then relabel(b, label:sub(1, s - 1) .. ja .. label:sub(e + 1), true, false) end
end

-- A quest row: its Japanese title at the end of the label Dialogue UI wrote (after the level it may put first). It
-- runs again whenever Dialogue UI writes the row again (the quest's data loading late).
local function questLabel(b, questInfo)
  if not (DialogueUI.active() and type(questInfo) == "table" and type(questInfo.title) == "string"
      and type(questInfo.questID) == "number") then
    return
  end
  local title = questInfo.title
  local ja = questRow(questInfo)
  local label = ja and b.Name:GetText()
  if type(label) ~= "string" or #label < #title or label:sub(-#title) ~= title then return end
  relabel(b, label:sub(1, #label - #title) .. ja, true, true)
end

local WRITERS = { SetButtonText = buttonText, SetGossip = gossipLabel, SetQuestName = questLabel }

-- One button's writers followed, once.
local function patch(button)
  if patched[button] then return end
  patched[button] = true
  for method, fn in pairs(WRITERS) do
    if type(button[method]) == "function" then
      hook(button, method, function(...) guarded(fn, ...) end)
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

-- ── The page's texts, as Dialogue UI writes them ───────────────────────────

local function undress(fs)
  if WFJ.Font.dressed(fs) then WFJ.Font.restore(fs) end
end

-- One paragraph of the line being written: its share of the Japanese (or of the English with a marker), in the
-- bundled face while the line shows Japanese.
local function fill(el, k, fs)
  face(fs, fontObject(body[fs] and body[fs].obj), el.holder.font.path == WFJ.Font.PATH)
  local t = el.slots[k]
  if fs:GetText() ~= t then write(fs, t) end
  el.fontStrings[#el.fontStrings + 1] = fs
  el.done = k
  if k == #el.english then
    run = nil
    guarded(attachCards, el)
  end
end

-- The first paragraph of a game line: the line is shown (its record, marker and voice) and spread over the
-- paragraphs Dialogue UI is making of its English. → true when it was one
local function startLine(fs, text)
  local el = identify(frame, text)
  if not el then return false end
  touched = true
  local shown, h = guarded(render, el)
  local slots = shown and spread(el.prefix .. h.text, #el.english)
  if not slots then return false end
  el.holder, el.slots, el.fontStrings = h, slots, {}
  run = el
  fill(el, 1, fs)
  return true
end

-- A body text Dialogue UI just wrote into `fs` (a paragraph, an objective line, a reward line), before it measures it.
local function bodyText(fs, text)
  local el = run
  if el then
    local k = el.done + 1
    if el.english[k] == text then return fill(el, k, fs) end
    -- Dialogue UI wrote something else before the line's last paragraph: the rest of that line is not coming
    run = nil
    if WFJ.Diag then pcall(WFJ.Diag.log, "dialogueui", "a line's paragraphs were not written in full") end
  end
  -- FormatParagraph asks for no font object; a line's paragraphs come only from there
  if body[fs].obj == nil and startLine(fs, text) then return end
  -- the progress page's objective lines, or a reward line ("You will be able to choose …")
  local ja = objectiveLines(frame, text) or gameWord(text)
  face(fs, fontObject(body[fs].obj), ja ~= nil)
  if ja then write(fs, ja) end
end

-- A heading Dialogue UI just wrote (AcquireAndSetSubHeader sizes the band behind it from the text's width right
-- after): a game word, or Requirements in the addon's own word, in the bundled face.
local function headingText(fs, text)
  local ja = headingWord(text)
  if not ja then return undress(fs) end
  local obj = type(fs.GetFontObject) == "function" and fs:GetFontObject() or nil
  WFJ.Font.bundle(fs, type(obj) == "table" and obj or Compat.resolve("DUIFont_Quest_SubHeader"))
  write(fs, ja)
end

-- After a pooled FontString's SetText, before Dialogue UI measures it.
local function written(fs, text)
  if writing or type(text) ~= "string" or not DialogueUI.active() then return end
  if body[fs] then guarded(bodyText, fs, text) else guarded(headingText, fs, text) end
end

-- The FontString a Dialogue UI pool handed out last (the newest active one), or nil.
function DialogueUI.newest(pool)
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return nil end
  local last
  for _, fs in pool:EnumerateActive() do last = fs end
  return type(last) == "table" and last or nil
end

-- After AcquireFontString: the FontString handed out (the newest of the pool) is followed, once.
local function acquired(self)
  newest = DialogueUI.newest(self.fontStringPool)
  if not newest then return end
  body[newest] = nil
  if not followed[newest] then
    followed[newest] = true
    hook(newest, "SetText", written)
  end
end

-- After AcquireLeftFontString (which took its FontString from AcquireFontString): that one holds body text.
local function acquiredLeft(obj)
  if newest then body[newest] = { obj = obj } end
end

-- After AcquireOptionButton: every option button in use is followed (the pool hands out the one just taken last).
local function optionButtons(self)
  local pool = self.optionButtonPool
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return end
  for _, b in pool:EnumerateActive() do
    if type(b) == "table" then patch(b) end
  end
end

-- After AcquireAcceptButton / AcquireExitButton: Dialogue UI makes each once, the first time it is needed.
local function footerButtons(self)
  for _, b in ipairs({ self.AcceptButton, self.ExitButton }) do
    if type(b) == "table" then patch(b) end
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

-- The tags over a quest page's title ("Daily", "Dungeon") are buttons Dialogue UI makes as needed; one holding a
-- game string gets its Japanese on its text and is laid out again by its own Layout. A tag Dialogue UI fills in after
-- the page drew (its quest data came late) is written by the button's own SetQuestTagNameAndIcon [read: Dialogue UI
-- 1.0.7 b, QuestHeaderWidget.lua]: each tag button found is followed there too, once.
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
    -- sized to its text in the face it has now, as after the write below
    if type(child.Layout) == "function" then child:Layout() end
    return
  end
  local ja = gameWord(text)
  tagOurs[fs] = ja
  face(fs, nil, ja ~= nil)
  if ja then
    fs:SetText(ja) -- what the tag's own SetText does [read: Dialogue UI 1.0.7 c, QuestHeaderWidget.lua]
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
          hook(child, "SetQuestTagNameAndIcon", function(b)
            if DialogueUI.active() then DialogueUI.guarded(tagJapanese, b) end
          end)
        end
        tagJapanese(child)
      end
    end
  end
end

local install -- defined below; DialogueUI.install runs it guarded

-- Follows DUIQuestFrame's members when every one is there. Any error on the way is recorded and Dialogue UI
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
  -- the FontString pool the page's texts come from (the newest one it hands out is the one just acquired)
  local pool = f.fontStringPool
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then
    if WFJ.Diag then
      pcall(WFJ.Diag.log, "dialogueui", "Dialogue UI's window has no fontStringPool: left in English")
    end
    return false
  end
  frame = f
  hook = Compat.resolve("hooksecurefunc")
  hook(f, "AcquireFontString", function(self) guarded(acquired, self) end)
  hook(f, "AcquireLeftFontString", function(_, obj) guarded(acquiredLeft, obj) end)
  hook(f, "AcquireOptionButton", function(self) guarded(optionButtons, self) end)
  for _, name in ipairs({ "AcquireAcceptButton", "AcquireExitButton" }) do -- not required: else they stay English
    if type(f[name]) == "function" then hook(f, name, function(self) guarded(footerButtons, self) end) end
  end
  guarded(footerButtons, f) -- the ones Dialogue UI made already
  -- its tooltip, chat panel and quest popups (UI/DialogueUIFrames)
  if WFJ.DialogueUIFrames then guarded(WFJ.DialogueUIFrames.install, f) end
  hook(f, "UpdateQuestTitle", function(self) guarded(showTitle, self) end)
  -- every page handler starts here: the page's paragraphs are about to be released and laid out again
  hook(f, "ReleaseAllObjects", function(self) guarded(newPage, self) end)
  for _, handler in ipairs({ "HandleGossip", "HandleQuestDetail", "HandleQuestProgress", "HandleQuestComplete",
    "HandleQuestGreeting" }) do
    hook(f, handler, function(self) guarded(restoreScroll, self) end)
  end
  DialogueUI.onClose(f, release)
  for _, event in ipairs({ "language", "enabled", "area", "markers" }) do
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
