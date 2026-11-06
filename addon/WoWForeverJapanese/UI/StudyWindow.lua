-- UI/StudyWindow.lua: studying the saved word list in game (ADR-071, docs/systems/study.md). Two small frames of
-- the addon's own: a TAB at the screen edge saying how many words wait, and the CARD it opens: the word, the
-- sentence it was saved from (the word under a gold mark; the sentence's other words take word cards through
-- UI/Readings, surface "study"), then the answer and the two grades, Again and Good. Core/Study decides what comes
-- next and when; this file only shows it. Both frames are movable and share one saved spot (WFJ_DB.study.point);
-- the card collapses to the tab, either close button hides both for the session, and /wfj study, the minimap
-- menu, the key binding and the Words page open the card again whatever the tab setting says. In combat both hide
-- (a setting) with Show / Hide only: nothing here is a protected call. The word list's change event (State "words")
-- and a ticker that runs only while something is on screen keep the counts current.
local _, WFJ = ...
local StudyWindow = {}
WFJ.StudyWindow = StudyWindow

local Compat = WFJ.Compat
local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText

StudyWindow.TICK = 15 -- seconds between count refreshes while the tab or the card is on screen
local WIDTH, HEIGHT, PAD = 320, 214, 12
local TAB_WIDTH, TAB_HEIGHT = 84, 24

local db -- WFJ_DB (init): db.study = { point = { p, rp, x, y } }
local card, tab, ticker
local current, answered -- the entry on the card (nil: the done state) and whether its back shows
local cardOpen, closed, inCombat = false, false, false
local last = {} -- the last scan shown: the tab's and footer's texts are re-put only when they change
local rec = { surface = "study", key = "sentence" } -- the sentence's record for UI/Readings

local S = function() return WFJ.Settings end
local function now() return Compat.call("time") or 0 end
local function today() return Compat.call("date", "%Y-%m-%d") or "" end
local function cap() return tonumber(S().get("study.newPerDay")) or 20 end
local function view() return WFJ.ReadingView end

-- one walk of the list: what to ask and the counts
local function scan() return WFJ.Study.scan(WFJ.Words.entries(), now(), today(), cap()) end
function StudyWindow.counts() return scan() end

local function opt()
  db.study = db.study or {}
  return db.study
end

-- ── Placement ─────────────────────────────────────────────────────────────

-- the right edge, middle, until the player drags it; placed at build, after a drag and on reset
local function place(f)
  if not f then return end
  f:ClearAllPoints()
  local p = opt().point
  local parent = Compat.resolve("UIParent")
  if type(p) == "table" and p[1] then
    f:SetPoint(p[1], parent, p[2], p[3], p[4])
  else
    f:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
  end
end

local function movable(f)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint(1)
    opt().point = { p, rp, x, y }
    place(self == card and tab or card) -- the other frame follows
  end)
end

local function backdrop(f)
  if not f.SetBackdrop then return end
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  f:SetBackdropColor(0.06, 0.05, 0.04, 0.92)
  f:SetBackdropBorderColor(0.45, 0.32, 0.18, 1)
end

local function closeButton(parent, size)
  local b = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
  b:SetSize(size, size)
  b:SetScript("OnClick", function() StudyWindow.close() end)
  return b
end

-- ── The sentence: its readings and the mark ──────────────────────────────

-- The saved word under a gold tint (a FontString cannot bold part of a line): its screen areas come from
-- UI/Readings' guarded span call, measured when the card shows and once more a frame later, when a just-shown
-- FontString has its layout.
local function drawMark()
  local f = card
  for _, t in ipairs(f.marks) do t:Hide() end
  local m, v = f.mark, view()
  if not m or not v then return end
  local areas = v.spanAreas(f.sentence, f.sentence:GetText(), m.first, m.last, "study")
  for i, a in ipairs(areas or {}) do
    local t = f.marks[i]
    if not t then
      t = f:CreateTexture(nil, "BACKGROUND", nil, 1)
      t:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.35)
      f.marks[i] = t
    end
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", f.sentence, "BOTTOMLEFT", a.left, a.bottom)
    t:SetSize(math.max(a.width, 1), math.max(a.height, 1))
    t:Show()
  end
end

local function detach()
  local v = view()
  if v and rec.fs then pcall(v.detach, rec) end
  if card then
    card.mark = nil
    for _, t in ipairs(card.marks) do t:Hide() end
  end
end

local function attach(e)
  local f = card
  local others, own = WFJ.Words.lineSpans(e)
  rec.fs, rec.applied, rec.meta, rec.spans = f.sentence, e.sentence, { kind = e.kind, id = e.id }, others
  local v = view()
  if v and others[1] then pcall(v.attach, rec) end
  f.mark = own
  drawMark()
  if own then Compat.call("C_Timer.After", 0, function() if card.mark == own then drawMark() end end) end
end

-- ── The card's states ────────────────────────────────────────────────────

local function showState()
  local f, asking = card, current ~= nil
  W.setShown(f.sentence, asking)
  W.setShown(f.show, asking and not answered)
  W.setShown(f.again, asking and answered)
  W.setShown(f.good, asking and answered)
  W.setShown(f.answer.en, asking and answered)
  W.setShown(f.message.en, not asking)
end

local function front(e)
  current, answered = e, false
  detach()
  W.put(card.word, e.word or "", 20)
  W.put(card.sentence, e.sentence or "", 14)
  attach(e)
  showState()
end

-- What comes next, as the second line of the done state: a word back within the hour (minutes), else tomorrow's
-- new words when today's are used up, else the next word's time today, else its day, else save more words.
local function nextLine(r)
  local secs = r.nextDue and r.nextDue - now()
  if secs and secs < 3600 then return Text.get("study.nextIn", math.max(1, math.ceil(secs / 60))) end
  if r.fresh > 0 and r.newLeft == 0 then return Text.get("study.tomorrow") end
  if not r.nextDue then return Text.get("study.empty") end
  if Compat.call("date", "%Y-%m-%d", r.nextDue) == today() then
    return Text.get("study.nextAt", Compat.call("date", "%H:%M", r.nextDue) or "")
  end
  return Text.get("study.nextOn", Compat.call("date", "%Y-%m-%d", r.nextDue) or "")
end

local function done(r)
  current, answered = nil, false
  detach()
  W.put(card.word, W.pick(Text.get("study.title")), 20)
  local en1, ja1 = Text.get("study.done")
  local en2, ja2 = nextLine(r)
  W.setPair(card.message, en1 .. "\n" .. en2, ja1 .. "\n" .. ja2)
  showState()
end

local function nextCard(r)
  if r.entry then front(r.entry) else done(r) end
end

function StudyWindow.showAnswer()
  local e = current
  if not e then return end
  answered = true
  local en, ja = {}, {}
  local function both(a, b) en[#en + 1] = a; ja[#ja + 1] = b end
  if e.reading ~= nil and e.reading ~= "" and e.reading ~= e.word then both(e.reading, e.reading) end
  local lemma = e.lemma
  if lemma ~= nil and lemma ~= "" and (lemma ~= e.word or (e.lemmaReading ~= "" and e.lemmaReading ~= e.reading)) then
    local shown = lemma
    if e.lemmaReading ~= nil and e.lemmaReading ~= "" and e.lemmaReading ~= lemma then
      shown = shown .. "（" .. e.lemmaReading .. "）"
    end
    both(Text.get("study.lemma", shown))
  end
  if e.meaning ~= nil and e.meaning ~= "" then both(e.meaning, e.meaning) end
  W.setPair(card.answer, table.concat(en, "\n"), table.concat(ja, "\n"))
  showState()
end

-- ── Showing and hiding ───────────────────────────────────────────────────

local function hidden()
  return closed or (inCombat and S().get("study.combatHide") == true)
end

local buildTab

local function startTicker()
  if ticker then return end
  local timer = Compat.resolve("C_Timer")
  if type(timer) ~= "table" or type(timer.NewTicker) ~= "function" then return end
  ticker = timer.NewTicker(StudyWindow.TICK, function() StudyWindow.refresh() end)
end

local function stopTicker()
  if ticker then ticker:Cancel(); ticker = nil end
end

local function putIfChanged(fs, key, text, size)
  if last[key] == text then return end
  last[key] = text
  W.put(fs, text, size)
end

-- The tab is built on first need, never at load: a player with nothing to study pays nothing for it.
local function apply(r)
  local waiting = r.due + r.newLeft
  local showCard = cardOpen and not hidden()
  local showTab = not cardOpen and not hidden() and S().get("study.tab") == true and waiting > 0
  last.waiting, last.due, last.newLeft = waiting, r.due, r.newLeft
  if showTab then
    if not tab then buildTab() end
    putIfChanged(tab.text, "tab", W.pick(Text.get("study.tab", waiting)), 12)
  end
  if tab then tab:SetShown(showTab) end
  if card then
    if showCard then
      putIfChanged(card.footer, "footer", W.pick(Text.get("study.footer", r.due, r.newLeft)), 11)
      W.relabelIfStale()
    end
    card:SetShown(showCard)
  end
  -- the clock matters only while something is on screen: the tab's count, the card's done line
  if showCard or showTab then startTicker() else stopTicker() end
end

-- Kept current: a save, a removal, a grade or a setting changes what waits; a done card asks again when a word
-- comes due; a word removed from the list leaves the card.
function StudyWindow.refresh()
  local r = scan()
  if card and cardOpen and (current == nil or not WFJ.Words.has(current.key)) then nextCard(r) end
  apply(r)
end

-- The reveal key's press and release only flip the language: nothing waiting can have changed.
local function relabel()
  if tab and tab:IsShown() then putIfChanged(tab.text, "tab", W.pick(Text.get("study.tab", last.waiting)), 12) end
  if card and card:IsShown() then
    putIfChanged(card.footer, "footer", W.pick(Text.get("study.footer", last.due, last.newLeft)), 11)
    if current == nil then W.put(card.word, W.pick(Text.get("study.title")), 20) end
    W.relabelIfStale()
  end
end

function StudyWindow.grade(rating)
  if not current then return end
  if not WFJ.Study.answer(current.key, rating, now(), today()) then return WFJ.WordSave.say("words.refused") end
  local r = scan()
  nextCard(r)
  apply(r)
end

-- ── Build ────────────────────────────────────────────────────────────────

function buildTab()
  tab = CreateFrame("Button", "WFJStudyTab", Compat.resolve("UIParent"), "BackdropTemplate")
  tab:SetSize(TAB_WIDTH, TAB_HEIGHT)
  tab:SetFrameStrata("HIGH")
  backdrop(tab)
  tab.close = closeButton(tab, 18)
  tab.close:SetPoint("RIGHT", tab, "RIGHT", -2, 0)
  tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tab.text:SetPoint("LEFT", tab, "LEFT", 8, 0)
  tab.text:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  movable(tab)
  place(tab)
  tab:SetScript("OnClick", function() StudyWindow.open() end)
  tab:Hide()
  return tab
end

local function buildCard()
  local f = CreateFrame("Frame", "WFJStudyCard", Compat.resolve("UIParent"), "BackdropTemplate")
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("HIGH")
  backdrop(f)
  movable(f)
  f.marks = {}
  local inner = WIDTH - 2 * PAD

  f.word = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.word:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
  f.word:SetJustifyH("LEFT")

  f.close = closeButton(f, 26)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  local en, ja = Text.get("study.collapse")
  f.collapse = W.button(f, en, ja, 60, function() StudyWindow.collapse() end)
  f.collapse:SetPoint("RIGHT", f.close, "LEFT", -2, 0)

  -- the sentence: a template font first, then the bundled face; Japanese has no spaces to wrap at
  f.sentence = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.sentence:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -46)
  f.sentence:SetWidth(inner)
  f.sentence:SetJustifyH("LEFT")
  f.sentence:SetJustifyV("TOP")
  f.sentence:SetWordWrap(true)
  if f.sentence.SetNonSpaceWrap then f.sentence:SetNonSpaceWrap(true) end

  f.answer = W.label(f, "", "", PAD, -116, inner)
  f.message = W.label(f, "", "", PAD, -50, inner)

  en, ja = Text.get("study.show")
  f.show = W.button(f, en, ja, 120, function() StudyWindow.showAnswer() end)
  f.show:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
  en, ja = Text.get("study.again")
  f.again = W.button(f, en, ja, 96, function() StudyWindow.grade(WFJ.Study.AGAIN) end)
  f.again:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
  f.again.caption:SetTextColor(1, 0.35, 0.35)
  en, ja = Text.get("study.good")
  f.good = W.button(f, en, ja, 96, function() StudyWindow.grade(WFJ.Study.GOOD) end)
  f.good:SetPoint("LEFT", f.again, "RIGHT", 8, 0)
  f.good.caption:SetTextColor(0.45, 1, 0.45)

  f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD + 4)
  f.footer:SetJustifyH("RIGHT")
  place(f)
  f:Hide()
  card = f
  return f
end

-- ── Entry points ─────────────────────────────────────────────────────────

-- Opens the card on the next word (or the done state), whatever the tab setting says and whether it was closed.
function StudyWindow.open()
  closed, cardOpen = false, true
  if not card then buildCard() end
  local r = scan()
  nextCard(r)
  apply(r)
  return card
end

function StudyWindow.collapse()
  cardOpen = false
  detach()
  apply(scan())
end

-- Hides the tab and the card until something opens the card again (the next login shows the tab as before).
function StudyWindow.close()
  closed, cardOpen = true, false
  current = nil
  detach()
  apply(scan())
end

function StudyWindow.toggle()
  if cardOpen then StudyWindow.collapse() else StudyWindow.open() end
end

-- `/wfj study reset`: back to the right edge. `reply(fmt, ...)` prints.
function StudyWindow.resetPosition(reply)
  opt().point = nil
  place(tab)
  place(card)
  reply("study: the card is back at the right edge of the screen")
end

-- PLAYER_REGEN_DISABLED / ENABLED (Main): both frames hide in combat when the setting says so.
function StudyWindow.setCombat(flag)
  inCombat = flag and true or false
  apply(scan())
end

function WFJ_StudyToggle() StudyWindow.toggle() end

-- Called by Main with WFJ_DB after the word list and the study table have loaded.
function StudyWindow.init(saved)
  db = saved
  closed, cardOpen = false, false
  local lockdown = Compat.resolve("InCombatLockdown") -- loaded mid-combat (a /reload): hidden from the start
  inCombat = type(lockdown) == "function" and lockdown() and true or false
  -- every listener is guarded: these events are shared with UI/Render, which must run whatever happens here
  local refresh = function() pcall(StudyWindow.refresh) end
  WFJ.State.on("study", refresh)
  WFJ.State.on("words", refresh)
  WFJ.State.on("enabled", function() pcall(relabel) end)
  WFJ.State.on("modifier", function() pcall(relabel) end)
  apply(scan())
  return true
end
