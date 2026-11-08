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
local WIDTH, HEIGHT, PAD = 320, 244, 12
local TAB_WIDTH, TAB_HEIGHT = 116, 36 -- read at a glance from across the screen, like a minimap icon

local db -- WFJ_DB (init): db.study = { point = { p, rp, x, y } }
local card, tab, ticker
local current, answered -- the entry on the card (nil: the done state) and whether its back shows
local cardOpen, closed, inCombat = false, false, false
local last = {} -- the last scan shown: the tab's and footer's texts are re-put only when they change
local pendingAttach = false -- the card shows a word whose readings and mark wait for the card to be on screen
local rec = { surface = "study", key = "sentence" } -- the sentence's record for UI/Readings

-- The header's buttons: the client's own close box (RedButton-Exit, 24 px) and, for Collapse, its hide button
-- of the same family (RedButton-MiniCondense, the minus) [verified: UIPanelCloseButtonNoScripts and
-- UIPanelHideButtonNoScripts, SharedXML/SharedUIPanelTemplates.xml:134-147]; the voice chat speaker (an atlas,
-- with a glyph when the client has none) for the sound; Show answer plays the options checkbox click, Good the loot
-- window's coin jingle and Again the quest log's abandon sound [verified: SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
-- = 856, LOOT_WINDOW_COIN_SOUND = 120, IG_QUEST_LOG_ABANDON_QUEST = 846, SharedXML/SoundKitConstants.lua].
local ICON = {
  hilight = "Interface\\Buttons\\UI-Common-MouseHilight",
  speaker = "voicechat-icon-speaker", muted = "voicechat-icon-speaker-mute",
}
local BUTTON = 24 -- the close button's own size
local REVEAL_SOUND, GOOD_SOUND, AGAIN_SOUND = 856, 120, 846
local FLASH = 0.2 -- seconds the whole card glows after a grade, like a saved word's tint

local S = function() return WFJ.Settings end
local function now() return Compat.call("time") or 0 end
local function today() return Compat.call("date", "%Y-%m-%d") or "" end
local function cap() return tonumber(S().get("study.newPerDay")) or 20 end
local function view() return WFJ.ReadingView end

-- one walk of the list: what to ask and the counts
local function scan() return WFJ.Study.scan(WFJ.Words.entries(), now(), today(), cap()) end
function StudyWindow.counts() return scan() end

local function opt()
  db = db or {} -- opened before (or without) init: the spot is then kept for the session only
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
  if type(p) == "table" and type(p[1]) == "string" and type(p[2]) == "string" and type(p[3]) == "number"
      and type(p[4]) == "number" then
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

local tipFrame -- the card's own tooltip, so its line can take the bundled face (the game's has no Japanese glyphs)
local function tip(owner, text)
  tipFrame = tipFrame or CreateFrame("GameTooltip", "WFJStudyTip", Compat.resolve("UIParent"), "GameTooltipTemplate")
  tipFrame:SetOwner(owner, "ANCHOR_TOP")
  tipFrame:SetText(text, 1, 1, 1)
  local line = Compat.resolve("WFJStudyTipTextLeft1")
  if type(line) == "table" then WFJ.Font.set(line, WFJ.Font.PATH, 13, "") end
  tipFrame:Show()
end

local function hideTip()
  if tipFrame then tipFrame:Hide() end
end

-- A button the close button's size with a one-line tooltip that follows the language: from a client template
-- (its own art), or plain with an icon texture drawn at `art` pixels, centred, under the client's mouse-over glow.
local function iconButton(parent, template, art, textKey, onClick)
  local b = CreateFrame("Button", nil, parent, template)
  b:SetSize(BUTTON, BUTTON)
  if not template then
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(art, art)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b:SetHighlightTexture(ICON.hilight, "ADD")
  end
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self) tip(self, W.pick(Text.get(textKey))) end)
  b:SetScript("OnLeave", hideTip)
  return b
end

local function atlasExists(name)
  local T = Compat.resolve("C_Texture")
  return type(T) == "table" and type(T.GetAtlasExists) == "function" and T.GetAtlasExists(name) == true
end

-- The speaker shows the sound setting: lit while a Good plays the tick, muted while it does not.
local function setSpeaker(f)
  local b = f.mute
  local on = S().get("study.sound") == true
  b.on = on
  local atlas = on and ICON.speaker or ICON.muted
  if atlasExists(atlas) and type(b.icon.SetAtlas) == "function" then
    b.icon:SetAtlas(atlas)
    b.glyph:Hide()
  else
    b.icon:SetTexture(nil)
    b.glyph:Show()
    if on then b.glyph:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3]) else b.glyph:SetTextColor(0.5, 0.5, 0.5) end
  end
end

-- The card's sounds, all off with the setting (the speaker button).
local function sound(id)
  if S().get("study.sound") == true then Compat.call("PlaySound", id) end
end

-- A grade's sound and a blink over the whole card while the next one comes: green for Good, red for Again, the
-- grade buttons' own colours.
local function reward(rating)
  local good = rating == WFJ.Study.GOOD
  sound(good and GOOD_SOUND or AGAIN_SOUND)
  local f = card
  if good then f.glow:SetColorTexture(0.1, 0.8, 0.2, 0.25) else f.glow:SetColorTexture(0.9, 0.1, 0.1, 0.25) end
  f.glow:Show()
  Compat.call("C_Timer.After", FLASH, function() f.glow:Hide() end)
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

local fit -- the card's height follows its text; defined with the card's states

local function attach(e)
  local f = card
  local others, own = WFJ.Words.lineSpans(e)
  rec.fs, rec.applied, rec.meta, rec.spans = f.sentence, e.sentence, { kind = e.kind, id = e.id }, others
  rec.exclude = own -- a saved class / race word would otherwise get its card back from the token-word pass
  local v = view()
  if v and others[1] then pcall(v.attach, rec) end
  f.mark = own
  drawMark()
  if own then
    Compat.call("C_Timer.After", 0, function()
      if card.mark == own then drawMark(); fit() end
    end)
  end
end

-- ── The card's states ────────────────────────────────────────────────────

-- The card grows to its text: a two-line title, a four-line sentence and a long answer would otherwise run under
-- the grades. GetStringHeight is the laid-out height [likely: FontString API with a set width]; the card measures
-- again a frame later (the deferred redraw) once the client has laid the text out.
local GAPS = { title = 12, rule = 9 + 1 + 9, meaning = 8, buttons = 12 + 22 }
local function textHeight(fs)
  if not fs:IsShown() or type(fs.GetStringHeight) ~= "function" then return 0 end
  return math.ceil(fs:GetStringHeight())
end

function fit()
  local f = card
  local h = PAD + textHeight(f.word) + GAPS.title
  if current then
    h = h + textHeight(f.sentence)
    if answered then
      h = h + GAPS.rule + textHeight(f.answer.en) + GAPS.meaning + textHeight(f.meaning)
    end
  else
    h = h + textHeight(f.message.en) + textHeight(f.message.ja)
  end
  f:SetHeight(math.max(HEIGHT, h + GAPS.buttons + PAD))
end

local function showState()
  local f, asking = card, current ~= nil
  W.setShown(f.sentence, asking)
  W.setShown(f.show, asking and not answered)
  W.setShown(f.again, asking and answered)
  W.setShown(f.good, asking and answered)
  W.setShown(f.answer.en, asking and answered)
  W.setShown(f.meaning, asking and answered)
  W.setShown(f.rule, asking and answered)
  W.setShown(f.message.en, not asking)
  fit()
end

-- The readings and the mark are attached once the card is on screen (apply): a hidden FontString has no layout to
-- measure, and the client refuses a cover in combat.
-- The title holds about nine characters on one line at its full size; a longer word (a saved phrase) drops to the
-- sentence's size and may take two lines. The sentence hangs under the title, so it moves with it.
local TITLE_CHARS = 9
local function titleSize(word)
  local chars = select(2, word:gsub("[^\128-\191]", "")) -- UTF-8 characters: every byte that starts one
  if chars > TITLE_CHARS then return 14, 2 end
  return 20, 1
end

local function setTitle(word)
  local size, lines = titleSize(word)
  if card.word.SetMaxLines then card.word:SetMaxLines(lines) end
  W.put(card.word, word, size)
end

local function front(e)
  current, answered = e, false
  detach()
  setTitle(e.word or "")
  W.put(card.sentence, e.sentence or "", 14)
  pendingAttach = true
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
  current, answered, pendingAttach = nil, false, false
  detach()
  setTitle(W.pick(Text.get("study.title")))
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
  sound(REVEAL_SOUND)
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
  W.setPair(card.answer, table.concat(en, "\n"), table.concat(ja, "\n"))
  W.put(card.meaning, e.meaning or "", 14) -- the English, a half line under the Japanese
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
  ticker = timer.NewTicker(StudyWindow.TICK, WFJ.Perf.wrap("idle.study.tick", function() StudyWindow.refresh() end))
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
  local waiting = r.waiting
  local showCard = cardOpen and not hidden()
  local showTab = not cardOpen and not hidden() and S().get("study.tab") == true and waiting > 0
  last.waiting, last.due, last.newLeft = waiting, r.due, r.newLeft
  if showTab then
    if not tab then buildTab() end
    putIfChanged(tab.text, "tab", W.pick(Text.get("study.tab", waiting)), 16)
  end
  if tab then tab:SetShown(showTab) end
  if card then
    if showCard then
      putIfChanged(card.footer, "footer", W.pick(Text.get("study.footer", r.due, r.newLeft)), 11)
      setSpeaker(card)
      W.relabelIfStale()
    end
    card:SetShown(showCard)
    if showCard and pendingAttach and current then
      pendingAttach = false
      attach(current)
    end
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
  if tab and tab:IsShown() then putIfChanged(tab.text, "tab", W.pick(Text.get("study.tab", last.waiting)), 16) end
  if card and card:IsShown() then
    putIfChanged(card.footer, "footer", W.pick(Text.get("study.footer", last.due, last.newLeft)), 11)
    if current == nil then setTitle(W.pick(Text.get("study.title"))) end
    W.relabelIfStale()
  end
end

-- A grade changes what waits: the Words page's counts follow State "study" (this window's own listener only
-- re-reads what it just drew).
function StudyWindow.grade(rating)
  if not current then return end
  WFJ.Study.answer(current.key, rating, now(), today()) -- a frozen table asks nothing, so it never gets here
  reward(rating)
  local r = scan()
  nextCard(r)
  apply(r)
  WFJ.State.fire("study")
end

-- ── Build ────────────────────────────────────────────────────────────────

function buildTab()
  tab = CreateFrame("Button", "WFJStudyTab", Compat.resolve("UIParent"), "BackdropTemplate")
  tab:SetSize(TAB_WIDTH, TAB_HEIGHT)
  tab:SetFrameStrata("HIGH")
  backdrop(tab)
  tab.close = closeButton(tab, 24)
  tab.close:SetPoint("RIGHT", tab, "RIGHT", -4, 0)
  tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  tab.text:SetPoint("LEFT", tab, "LEFT", 12, 0)
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
  f.word:SetWidth(inner - 100) -- the collapse and close buttons sit to its right
  f.word:SetJustifyH("LEFT")
  f.word:SetJustifyV("TOP")
  f.word:SetWordWrap(true)
  if f.word.SetNonSpaceWrap then f.word:SetNonSpaceWrap(true) end
  if f.word.SetMaxLines then f.word:SetMaxLines(1) end

  f.close = closeButton(f, BUTTON)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  f.collapse = iconButton(f, "UIPanelHideButtonNoScripts", nil, "study.collapse", function() StudyWindow.collapse() end)
  f.collapse:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
  f.mute = iconButton(f, nil, 20, "study.sound", function() S().set("study.sound", S().get("study.sound") ~= true) end)
  f.mute:SetPoint("RIGHT", f.collapse, "LEFT", -2, 0)
  f.mute.glyph = f.mute:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.mute.glyph:SetPoint("CENTER", f.mute, "CENTER", 0, 0)
  f.mute.glyph:SetText("♪")
  setSpeaker(f)

  f.glow = f:CreateTexture(nil, "BACKGROUND", nil, 7) -- over the backdrop, under every text and mark
  f.glow:SetAllPoints(f)
  f.glow:Hide()

  -- the sentence: a template font first, then the bundled face; Japanese has no spaces to wrap at
  f.sentence = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.sentence:SetPoint("TOPLEFT", f.word, "BOTTOMLEFT", 0, -12)
  f.sentence:SetWidth(inner)
  f.sentence:SetJustifyH("LEFT")
  f.sentence:SetJustifyV("TOP")
  f.sentence:SetWordWrap(true)
  if f.sentence.SetNonSpaceWrap then f.sentence:SetNonSpaceWrap(true) end

  -- a faint gold rule parts the question from the answer, like a settings section's rule
  f.rule = f:CreateTexture(nil, "ARTWORK")
  f.rule:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.45)
  f.rule:SetPoint("TOPLEFT", f.sentence, "BOTTOMLEFT", 0, -9) -- under the sentence, however many lines
  f.rule:SetSize(inner, 1)

  f.answer = W.label(f, "", "", PAD, -116, inner, 14) -- the sentence's size: it is read as closely
  f.answer.en:ClearAllPoints()
  f.answer.en:SetPoint("TOPLEFT", f.rule, "BOTTOMLEFT", 0, -9)
  f.meaning = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.meaning:SetPoint("TOPLEFT", f.answer.en, "BOTTOMLEFT", 0, -8)
  f.meaning:SetWidth(inner)
  f.meaning:SetJustifyH("LEFT")
  f.meaning:SetWordWrap(true)
  f.message = W.label(f, "", "", PAD, -50, inner)

  local en, ja = Text.get("study.show")
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
  cardOpen, pendingAttach = false, false
  detach()
  apply(scan())
end

-- Hides the tab and the card until something opens the card again (the next login shows the tab as before).
function StudyWindow.close()
  closed, cardOpen, pendingAttach = true, false, false
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
