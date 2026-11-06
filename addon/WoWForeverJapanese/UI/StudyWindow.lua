-- UI/StudyWindow.lua: studying the saved word list in game (ADR-071, docs/systems/study.md). Two small frames of
-- the addon's own: a TAB at the screen edge saying how many words wait, and the CARD it opens: the word, the
-- sentence it was saved from (the word marked in gold; the sentence's other words take word cards through
-- UI/Readings, surface "study"), then the answer and the two grades, Again and Good. Core/Study decides what comes
-- next and when; this file only shows it. Both frames are movable and share one saved spot (WFJ_DB.study.point);
-- the card collapses to the tab, the close button hides both for the session, and /wfj study, the minimap menu, the
-- key binding and the Words page open the card again whatever the tab setting says. In combat both hide
-- (a setting) with Show / Hide only: nothing here is a protected call.
local _, WFJ = ...
local StudyWindow = {}
WFJ.StudyWindow = StudyWindow

local Compat = WFJ.Compat
local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText

StudyWindow.WIDTH, StudyWindow.HEIGHT = 320, 214
StudyWindow.TICK = 15 -- seconds between count refreshes while the window is in use
local PAD = 12
local MARK = { 1, 0.82, 0 } -- the gold of the hovered-word tint

local db -- WFJ_DB (init): db.study = { point = { p, rp, x, y } }
local card, tab, events
local current -- the entry on the card, nil in the done state
local cardOpen, closed, inCombat, ticking = false, false, false, false
local rec = { surface = "study", key = "sentence" } -- the sentence's record for UI/Readings

local S = function() return WFJ.Settings end
local function now() return Compat.call("time") or 0 end
local function today() return Compat.call("date", "%Y-%m-%d") or "" end
local function cap() return tonumber(S().get("study.newPerDay")) or 20 end
local function entries() return WFJ.Words.entries() end

function StudyWindow.counts()
  return WFJ.Study.counts(entries(), now(), today(), cap())
end

local function opt()
  if not db then db = {} end -- never reached after init; keeps a call before it harmless
  db.study = db.study or {}
  return db.study
end

-- Both languages on one line, as the word list's chat lines.
local function say(key, ...)
  local en, ja = Text.get(key, ...)
  print("WFJ: " .. en .. " ・ " .. ja)
end

-- ── Placement ─────────────────────────────────────────────────────────────

-- the right edge, middle, until the player drags it
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
  end)
end

-- ── The sentence's readings ──────────────────────────────────────────────

local function view() return WFJ.ReadingView end

local function detach()
  local v = view()
  if v and rec.fs then pcall(v.detach, rec) end
end

-- The sentence's words from the line's reading list, minus any span over the tested word (its reading is the
-- answer). → spans | nil
local function sentenceSpans(e)
  local R = WFJ.Readings
  local s = e.sentence
  if not R or type(s) ~= "string" or s == "" or e.kind == nil or e.id == nil then return nil end
  local words = R.words(e.kind, e.id)
  if not words then return nil end
  local out = {}
  local wf, wl = e.wf, e.wl
  local own = type(wf) == "number" and type(wl) == "number"
  for _, sp in ipairs(R.locate(words, s)) do
    if not (own and sp.first <= wl and sp.last >= wf) then out[#out + 1] = sp end
  end
  return out
end

local function attach(e)
  local f = card
  rec.fs, rec.applied, rec.meta = f.sentence, e.sentence, { kind = e.kind, id = e.id }
  rec.spans = sentenceSpans(e)
  local own = type(e.wf) == "number" and type(e.wl) == "number" and e.wf >= 1 and e.wl >= e.wf
  rec.mark = own and { first = e.wf, last = e.wl } or nil
  local v = view()
  if v then pcall(v.attach, rec) end
end

-- ── The card's states ────────────────────────────────────────────────────

local function setShown(w, on)
  if w then W.setShown(w, on) end
end

local function front(e)
  local f = card
  current = e
  detach()
  W.put(f.word, e.word or "", 20)
  f.sentence:SetText(e.sentence or "")
  WFJ.Font.set(f.sentence, WFJ.Font.PATH, 14, "")
  setShown(f.sentence, true)
  setShown(f.show, true)
  setShown(f.again, false)
  setShown(f.good, false)
  setShown(f.answer.en, false)
  setShown(f.message.en, false)
  attach(e)
end

-- What comes next, as the second line of the done state: a word back within the hour (minutes), else tomorrow's
-- new words when today's are used up, else the next word's time today, else its day.
local function nextLine(c)
  local secs = c.nextDue and c.nextDue - now()
  if secs and secs < 3600 then return Text.get("study.nextIn", math.max(1, math.ceil(secs / 60))) end
  if c.fresh > 0 and c.newLeft == 0 then return Text.get("study.tomorrow") end
  if not c.nextDue then return Text.get("study.empty") end
  if Compat.call("date", "%Y-%m-%d", c.nextDue) == today() then
    return Text.get("study.nextAt", Compat.call("date", "%H:%M", c.nextDue) or "")
  end
  return Text.get("study.nextOn", Compat.call("date", "%Y-%m-%d", c.nextDue) or "")
end

local function done()
  local f = card
  current = nil
  detach()
  local en, ja = Text.get("study.title")
  W.put(f.word, W.pick(en, ja), 20)
  f.sentence:SetText("")
  setShown(f.sentence, false)
  setShown(f.show, false)
  setShown(f.again, false)
  setShown(f.good, false)
  setShown(f.answer.en, false)
  local line1en, line1ja = Text.get("study.done")
  local en2, ja2 = nextLine(StudyWindow.counts())
  W.setPair(f.message, line1en .. "\n" .. en2, line1ja .. "\n" .. ja2)
  setShown(f.message.en, true)
end

local function nextCard()
  local e = WFJ.Study.next(entries(), now(), today(), cap())
  if e then front(e) else done() end
end

function StudyWindow.showAnswer()
  local f, e = card, current
  if not e then return end
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
  W.setPair(f.answer, table.concat(en, "\n"), table.concat(ja, "\n"))
  setShown(f.answer.en, true)
  setShown(f.show, false)
  setShown(f.again, true)
  setShown(f.good, true)
end

function StudyWindow.grade(rating)
  if not current then return end
  local st = WFJ.Study.answer(current.key, rating, now(), today())
  if not st then return say("words.refused") end
  nextCard()
  StudyWindow.refresh()
end

-- ── Showing and hiding ───────────────────────────────────────────────────

local function hidden()
  return closed or (inCombat and S().get("study.combatHide") == true)
end

local buildTab

-- the tab is built on first need, never at load: a player with nothing to study pays nothing for it
local function apply()
  local c = StudyWindow.counts()
  local waiting = c.due + c.newLeft
  local showCard = cardOpen and not hidden()
  local showTab = not cardOpen and not hidden() and S().get("study.tab") == true and waiting > 0
  if showTab and not tab then buildTab() end
  if showTab then
    local en, ja = Text.get("study.tab", waiting)
    W.put(tab.text, W.pick(en, ja), 12)
    place(tab)
  end
  if tab then tab:SetShown(showTab) end
  if card then
    if showCard then
      place(card)
      local en, ja = Text.get("study.footer", c.due, c.newLeft)
      W.put(card.footer, W.pick(en, ja), 11)
    end
    card:SetShown(showCard)
  end
  if showCard or showTab then W.relabelIfStale() end
end

local function tick()
  if closed then ticking = false; return end
  StudyWindow.refresh()
  local after = Compat.resolve("C_Timer.After")
  if type(after) == "function" then after(StudyWindow.TICK, tick) else ticking = false end
end

local function startTicking()
  if ticking then return end
  local after = Compat.resolve("C_Timer.After")
  if type(after) ~= "function" then return end
  ticking = true
  after(StudyWindow.TICK, tick)
end

-- Kept current: a save, a removal, a grade or a setting changes what waits; a done card asks again when a word
-- comes due.
function StudyWindow.refresh()
  if card and cardOpen and current == nil then
    local e = WFJ.Study.next(entries(), now(), today(), cap())
    if e then front(e) else done() end -- the done state's second line follows the clock
  elseif card and cardOpen and current and not WFJ.Study.card(current.key) and not WFJ.Study.readonly() then
    -- the word on the card was removed from the list (a new card has no state either: check the list itself)
    local still = false
    for _, e in ipairs(entries()) do if e.key == current.key then still = true end end
    if not still then nextCard() end
  end
  apply()
end

-- ── Build ────────────────────────────────────────────────────────────────

local function backdrop(f)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints(f)
  f.bg:SetColorTexture(0.06, 0.05, 0.04, 0.92)
  f.border = CreateFrame("Frame", nil, f, "BackdropTemplate")
  f.border:SetAllPoints(f)
  if f.border.SetBackdrop then
    f.border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
    f.border:SetBackdropBorderColor(0.45, 0.32, 0.18, 1)
  end
end

function buildTab()
  tab = CreateFrame("Button", "WFJStudyTab", Compat.resolve("UIParent"))
  tab:SetSize(64, 24)
  tab:SetFrameStrata("HIGH")
  backdrop(tab)
  tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tab.text:SetPoint("CENTER", tab, "CENTER", 0, 0)
  tab.text:SetTextColor(MARK[1], MARK[2], MARK[3])
  movable(tab)
  tab:SetScript("OnClick", function() StudyWindow.open() end)
  tab:Hide()
  return tab
end

local function buildCard()
  local f = CreateFrame("Frame", "WFJStudyCard", Compat.resolve("UIParent"))
  f:SetSize(StudyWindow.WIDTH, StudyWindow.HEIGHT)
  f:SetFrameStrata("HIGH")
  backdrop(f)
  movable(f)
  local inner = StudyWindow.WIDTH - 2 * PAD

  f.word = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.word:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
  f.word:SetJustifyH("LEFT")

  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetSize(26, 26)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  f.close:SetScript("OnClick", function() StudyWindow.close() end)
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
  f:Hide()
  card = f
  StudyWindow.frame = f
  return f
end

-- ── Entry points ─────────────────────────────────────────────────────────

-- Opens the card on the next word (or the done state), whatever the tab setting says and whether it was closed.
function StudyWindow.open()
  closed, cardOpen = false, true
  if not card then buildCard() end
  nextCard()
  apply()
  startTicking()
  return card
end

function StudyWindow.collapse()
  cardOpen = false
  detach()
  apply()
end

-- Hides the tab and the card until something opens the card again (the next login shows the tab as before).
function StudyWindow.close()
  closed, cardOpen = true, false
  current = nil
  detach()
  apply()
end

function StudyWindow.toggle()
  if card and card:IsShown() then StudyWindow.collapse() else StudyWindow.open() end
end

-- `/wfj study reset`: back to the right edge. `words`: the command's words after "study"; `say(fmt, ...)` prints.
function StudyWindow.command(words, reply)
  if words[1] ~= "reset" then return reply("study: /wfj study opens the card; /wfj study reset puts it back") end
  opt().point = nil
  place(tab)
  place(card)
  reply("study: the card is back at the right edge of the screen")
end

function WFJ_StudyToggle() StudyWindow.toggle() end

-- Called by Main with WFJ_DB after the word list and the study table have loaded.
function StudyWindow.init(saved)
  db = saved
  closed, cardOpen = false, false
  local lockdown = Compat.resolve("InCombatLockdown")
  inCombat = type(lockdown) == "function" and lockdown() and true or false
  if not events then
    events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event)
      inCombat = event == "PLAYER_REGEN_DISABLED"
      apply()
    end)
    local update = function() pcall(StudyWindow.refresh) end -- shared events: a study error never stops the others
    WFJ.State.on("study", update)
    WFJ.State.on("enabled", update)
    WFJ.State.on("modifier", update)
  end
  apply()
  if S().get("study.tab") then startTicking() end
  return true
end
