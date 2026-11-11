-- UI/IntroWindow.lua: the window a first install shows once, at its first login (docs/systems/settings.md).
-- Core/Intro decides when; Main hands it IntroWindow.request, which opens it. It is the one addon window that shows
-- both languages at once, a Japanese block above an English one: the player has not learned the reveal key yet, so
-- a one-language window could be unreadable to them. The reveal key and the translation switch change nothing here.
-- Lines: what the addon does,
-- the reveal key (named as set), the word readings, the minimap button and, while no voice pack has loaded, the
-- voice download with its address to copy. Only the addon's own copy (UI/OptionsText), never game text.
local _, WFJ = ...
local IntroWindow = {}
WFJ.IntroWindow = IntroWindow

local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText
local WIDTH, LEFT = 520, 26
local TEXT_WIDTH = WIDTH - 2 * LEFT
-- the inset panel moved up under the title bar and down to the bottom edge, as in UI/CollectorReminder
local INSET_TOP, INSET_BOTTOM = 24, 4
local TOP, BOTTOM, PAD = INSET_TOP + 4, INSET_BOTTOM + 4, 12
local LINE, BLOCK = 7, 14 -- between lines in a block; above and below the rule between the two blocks
local HEAD = 10 -- under a block's opening line
local KEY = "|cffffd200%s|r" -- the reveal key's name, in the gold the client uses for key names
local BOX, BUTTON = 20, 22

IntroWindow.frame = nil
IntroWindow.closedByPlayer = false -- Close, Esc or any hide outside a cinematic: it stays closed
IntroWindow.waiting = false -- a cinematic is playing: open when it ends
local watcher -- the frame that hears the cinematic events, made by the first request

IntroWindow.step = "pick" -- "pick": the question and its three cards; "info": what the choice means
IntroWindow.selected = nil -- the card clicked on the first page; nothing is written until Confirm
local ABOUT = 62 -- room under the cards for what the selected one does: two lines in each language
local PURPOSES = { "ja", "en", "play" }
-- The client's own icons, one per choice: a scroll, a book, a sword.
local ICONS = { ja = "Interface\\Icons\\INV_Scroll_03", en = "Interface\\Icons\\INV_Misc_Book_09",
  play = "Interface\\Icons\\INV_Sword_27" }
local CARD_GAP = 12
local CARD_W, CARD_H = math.floor((TEXT_WIDTH - 2 * CARD_GAP) / 3), 150
local PAIR, POINT = 3, 12 -- between a point's Japanese and its English; between two points
local CHANGE = 110 -- the Change button's room at the right of the hold-key point
local BORDER, BORDER_ON = { 0.45, 0.38, 0.25 }, W.GOLD

-- What each choice writes: which language shows first, whether pointing at a word shows its card, and whether the
-- study tab comes up when saved words are due (playing only wants neither). Nothing else.
local WRITES = {
  ja = { direction = "ja", cards = true, tab = true },
  en = { direction = "en", cards = true, tab = true },
  play = { direction = "ja", cards = false, tab = false },
}

-- The choice the settings match now, or nil when they match none (English first with the cards off). The study tab
-- is not part of the match: a learner who hid it is still a learner.
local function shownPurpose()
  local S = WFJ.Settings
  for _, purpose in ipairs(PURPOSES) do
    local w = WRITES[purpose]
    if S.get("direction") == w.direction and S.get("readings.enabled") == w.cards then return purpose end
  end
  return nil
end

-- Two font strings per point, not W.label: a W.label re-shows one language whenever the reveal key flips. The
-- Japanese line sits above its English, so each point reads as one thing in both languages.
local function line(p, width)
  local r = {}
  r.ja = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  r.en = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  for _, fs in ipairs({ r.ja, r.en }) do
    fs:SetWidth(width or TEXT_WIDTH)
    fs:SetJustifyH("LEFT")
  end
  r.en:SetTextColor(W.JA_COLOR[1], W.JA_COLOR[2], W.JA_COLOR[3])
  return r
end

-- A point's two texts; the opening line is a size up.
local function fill(r, en, ja, lead)
  W.put(r.ja, ja, lead and 14 or 13)
  W.put(r.en, en, lead and 12 or 11)
end

-- The wrapped height of a line [likely: FontString:GetStringHeight with a set width; in-game check: the intro window
-- checklist in docs/testing/strategy.md]; the specs' stub has none.
local function height(fs)
  return math.max(14, fs.GetStringHeight and math.ceil(fs:GetStringHeight()) or 0)
end

local function rule(p)
  local t = p:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.35)
  t:SetSize(TEXT_WIDTH, 1)
  return t
end

local function edge(card, on)
  local c = on and BORDER_ON or BORDER
  if card.SetBackdropBorderColor then card:SetBackdropBorderColor(c[1], c[2], c[3], 1) end
  if not card.SetBackdropColor then return end
  if on then card:SetBackdropColor(0.16, 0.13, 0.07, 0.95) else card:SetBackdropColor(0.07, 0.06, 0.05, 0.95) end
end

-- A choice card: an icon, the English under it and the Japanese under that. It lights up under the mouse and stays
-- lit while it is the one selected; a click selects it and shows what it does under the cards.
local function card(p, purpose)
  local c = CreateFrame("Button", nil, p, "BackdropTemplate")
  c:SetSize(CARD_W, CARD_H)
  if c.SetBackdrop then
    c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  end
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetTexture(ICONS[purpose])
  c.icon:SetSize(56, 56)
  c.icon:SetPoint("TOP", 0, -20)
  local en, ja = Text.get("intro.pick." .. purpose)
  c.en = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  c.en:SetPoint("TOP", c.icon, "BOTTOM", 0, -14)
  W.put(c.en, en, 14)
  c.ja = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  c.ja:SetPoint("TOP", c.en, "BOTTOM", 0, -6)
  W.put(c.ja, ja, 13)
  c.ja:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  c:SetScript("OnEnter", function(self) edge(self, true) end)
  c:SetScript("OnLeave", function(self) edge(self, self.picked) end)
  c:SetScript("OnClick", function() IntroWindow.select(purpose) end)
  edge(c, false)
  return c
end

local function build()
  local f = W.toolWindow("WFJIntro", WIDTH, 300)
  -- where the client opens its own popups, clear of the character [verified: forever-ui-1.60.1.70425
  -- blizzard_staticpopup_game/gamedialog.xml:350, TOP 0,-135]; it grows down, so the voice section moves nothing
  f:ClearAllPoints()
  f:SetPoint("TOP", 0, -135)
  if f.Inset then
    f.Inset:ClearAllPoints()
    f.Inset:SetPoint("TOPLEFT", 4, -INSET_TOP)
    f.Inset:SetPoint("BOTTOMRIGHT", -6, INSET_BOTTOM)
  end
  W.put(f.title, WFJ.Options.TITLE, 13)
  local function page()
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 0, -TOP)
    p:SetPoint("BOTTOMRIGHT", 0, BOTTOM)
    return p
  end

  -- the first page: the question and its three answers
  local a = page()
  f.pickPage = a
  f.ask = line(a)
  local en, ja = Text.get("intro.ask")
  W.put(f.ask.ja, ja, 17)
  W.put(f.ask.en, en, 12)
  f.ask.ja:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  for _, fs in ipairs({ f.ask.ja, f.ask.en }) do fs:SetJustifyH("CENTER") end
  f.cards = {}
  for _, purpose in ipairs(PURPOSES) do f.cards[purpose] = card(a, purpose) end
  f.about = line(a)
  en, ja = Text.get("intro.confirm")
  f.confirm = W.button(a, ja .. " / " .. en, nil, 150, function() IntroWindow.pick(IntroWindow.selected) end)
  f.later = a:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.later:SetWidth(TEXT_WIDTH - 170) -- beside the Confirm button
  f.later:SetJustifyH("LEFT")
  en, ja = Text.get("intro.later")
  W.put(f.later, ja .. "　" .. en, 11)
  f.later:SetTextColor(W.JA_COLOR[1], W.JA_COLOR[2], W.JA_COLOR[3])

  -- the second page: what a new player must know, each point in Japanese with its English under it. The hold-key
  -- point leaves room for the settings page's own Change button at its right.
  local b = page()
  f.infoPage = b
  f.lead, f.hold, f.readings, f.minimap, f.voice = line(b), line(b, TEXT_WIDTH - CHANGE - 10), line(b), line(b), line(b)
  f.lead.ja:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  f.capture = WFJ.KeyCapture.new(b, { mode = "reveal", width = CHANGE, onKey = function(v)
    WFJ.Options.setModifier(v)
    IntroWindow.refill()
  end, onRefused = function() IntroWindow.refill() end })
  f.box = W.copyBox(b, LEFT, 0, TEXT_WIDTH - 12, WFJ.Options.VOICE_URL)
  fill(f.voice, Text.get("intro.voice"))
  f.voiceTitle = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  en, ja = Text.get("intro.voiceTitle")
  W.put(f.voiceTitle, ja .. " / " .. en, 14)
  f.voiceTitle:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  f.leadRule, f.voiceRule = rule(b), rule(b)
  -- the foot: Back at the left, Close at the right, each caption in both languages (nothing for W.pick to switch)
  en, ja = Text.get("intro.back")
  f.back = W.button(b, ja .. " / " .. en, nil, 130, function() IntroWindow.show("pick") end)
  en, ja = Text.get("intro.close")
  f.close = W.button(b, ja .. " / " .. en, nil, 130, function() IntroWindow.close() end)
  f:HookScript("OnHide", function() IntroWindow.hidden() end)
  IntroWindow.frame = f
  return f
end

-- Runs fn after `seconds` (1 by default), or now where the client timer is missing (the specs).
local function later(fn, seconds)
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(seconds or 1, fn) else fn() end
end

-- The points for the choice shown: playing only has no word cards to mention.
local function points(f)
  if shownPurpose() == "play" then return { f.hold, f.minimap } end
  return { f.hold, f.readings, f.minimap }
end

-- The first page: the question centred, the three cards side by side, the note under them.
local function layoutPick(f)
  local a = f.pickPage
  f.ask.ja:ClearAllPoints()
  f.ask.ja:SetPoint("TOPLEFT", a, "TOPLEFT", LEFT, -PAD - 4)
  f.ask.en:ClearAllPoints()
  f.ask.en:SetPoint("TOPLEFT", f.ask.ja, "BOTTOMLEFT", 0, -4)
  local used = PAD + 4 + height(f.ask.ja) + 4 + height(f.ask.en)
  for i, purpose in ipairs(PURPOSES) do
    local c = f.cards[purpose]
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", a, "TOPLEFT", LEFT + (i - 1) * (CARD_W + CARD_GAP), -(used + 18))
  end
  used = used + 18 + CARD_H
  -- what the selected card does, in a fixed space so the window keeps its size from one card to the next
  f.about.ja:ClearAllPoints()
  f.about.ja:SetPoint("TOPLEFT", a, "TOPLEFT", LEFT, -(used + 16))
  f.about.en:ClearAllPoints()
  f.about.en:SetPoint("TOPLEFT", f.about.ja, "BOTTOMLEFT", 0, -5)
  used = used + 16 + ABOUT
  f.confirm:ClearAllPoints()
  f.confirm:SetPoint("TOPRIGHT", a, "TOPLEFT", LEFT + TEXT_WIDTH, -(used + 16))
  f.later:ClearAllPoints()
  f.later:SetPoint("TOPLEFT", a, "TOPLEFT", LEFT, -(used + 21))
  used = used + 16 + BUTTON
  f:SetHeight(TOP + used + PAD + 4 + BOTTOM)
end

-- The second page: the opening line, a rule, the points; while no voice pack has loaded, a rule and the voice
-- section; then the two buttons. Each piece hangs from the one above it, so the gaps never depend on a measured
-- height; only the window's does.
local function layoutInfo(f, voice)
  local prev, used
  local function chain(region, gap, x, h)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", x or 0, -gap)
    used = used + gap + (h or (region.GetObjectType and region:GetObjectType() == "FontString" and height(region) or 0))
    prev = region
  end
  local function pair(r, gap)
    chain(r.ja, gap)
    chain(r.en, PAIR)
  end
  f.lead.ja:ClearAllPoints()
  f.lead.ja:SetPoint("TOPLEFT", f.infoPage, "TOPLEFT", LEFT, -PAD - 2)
  prev, used = f.lead.ja, PAD + 2 + height(f.lead.ja)
  chain(f.lead.en, PAIR)
  chain(f.leadRule, BLOCK, 0, 1)
  for i, r in ipairs(points(f)) do pair(r, i == 1 and BLOCK or POINT) end
  f.capture.button:ClearAllPoints()
  f.capture.button:SetPoint("TOPRIGHT", f.hold.ja, "TOPLEFT", TEXT_WIDTH, 3)
  if voice then
    chain(f.voiceRule, BLOCK + 2, 0, 1)
    chain(f.voiceTitle, BLOCK)
    pair(f.voice, HEAD)
    chain(f.box, LINE + 2, 6, BOX) -- InputBoxTemplate's left cap sits outside the frame
  end
  f.back:ClearAllPoints()
  f.back:SetPoint("BOTTOMLEFT", f.infoPage, "BOTTOMLEFT", LEFT, PAD)
  f.close:ClearAllPoints()
  f.close:SetPoint("BOTTOMRIGHT", f.infoPage, "BOTTOMRIGHT", -LEFT, PAD)
  f:SetHeight(TOP + used + BLOCK + 6 + BUTTON + PAD + BOTTOM)
end

local function layout(f)
  if IntroWindow.step == "info" then layoutInfo(f, f.voiceShown) else layoutPick(f) end
end

local function refused(f)
  for _, r in ipairs({ f.ask, f.lead, f.hold, f.readings, f.minimap, f.voice }) do
    if WFJ.Font.isPending(r.ja) or WFJ.Font.isPending(r.en) then return true end
  end
  return false
end

-- A first install's first login is a fresh launch, when the client refuses the bundled face until its file loads
-- (UI/Font, Main's font retry): the lines were measured in another face and wrap differently once it lands. Checks
-- once a second and lays the window out again when Font's retry has applied it, for as long as Main keeps retrying.
local function relayoutWhenFonts(f)
  if f.fontTicker or not refused(f) or type(C_Timer) ~= "table" then return end
  local tries = 0
  f.fontTicker = C_Timer.NewTicker(1, function(ticker)
    tries = tries + 1
    local waiting = refused(f)
    if not waiting and f:IsShown() then layout(f) end
    if not waiting or tries >= 600 then
      ticker:Cancel()
      f.fontTicker = nil
    end
  end)
end

-- Writes the lines for the choice shown and the reveal key as it is set now, marks the picked card, and lays the
-- page on screen out.
function IntroWindow.refill()
  local f = IntroWindow.frame
  if not f then return end
  local shown = shownPurpose()
  local english = shown == "en"
  local key = KEY:format(WFJ.Options.keyName())
  local leadEn, leadJa = Text.get(english and "intro.lead.en" or "intro.lead")
  fill(f.lead, leadEn, leadJa, true)
  fill(f.hold, Text.get(english and "intro.hold.en" or "intro.hold", key))
  fill(f.readings, Text.get(english and "intro.readings.en" or "intro.readings"))
  fill(f.minimap, Text.get("intro.minimap"))
  W.setShown(f.readings.ja, shown ~= "play")
  W.setShown(f.readings.en, shown ~= "play")
  for purpose, c in pairs(f.cards) do
    c.picked = IntroWindow.selected == purpose
    edge(c, c.picked)
  end
  fill(f.about, Text.get("intro.about." .. (IntroWindow.selected or "ja")))
  W.setShown(f.pickPage, IntroWindow.step ~= "info")
  W.setShown(f.infoPage, IntroWindow.step == "info")
  for _, region in ipairs({ f.voiceRule, f.voiceTitle, f.voice.ja, f.voice.en, f.box }) do
    W.setShown(region, f.voiceShown)
  end
  layout(f)
  -- a FontString given new text may report its old height until the client has drawn it once [likely; in-game
  -- check: the intro window checklist in docs/testing/strategy.md]: the height is taken again on the next frame
  later(function() if f:IsShown() then layout(f) end end, 0)
end

-- Shows one of the two pages.
function IntroWindow.show(step)
  IntroWindow.step = step
  IntroWindow.refill()
end

-- A card clicked on the first page: it lights up and the lines under the cards say what it does. Nothing is written.
function IntroWindow.select(purpose)
  IntroWindow.selected = purpose
  IntroWindow.refill()
end

-- Confirm: the selected choice's settings, then the second page.
function IntroWindow.pick(purpose)
  local w = WRITES[purpose]
  WFJ.Settings.set("direction", w.direction)
  WFJ.Settings.set("readings.enabled", w.cards)
  WFJ.Settings.set("study.tab", w.tab)
  IntroWindow.show("info")
end

-- Opens on the question, with the voice section on the second page only without a pack. → the frame
-- noVoice: draws the voice section as if no pack had loaded (`/wfj debug intro novoice`).
function IntroWindow.open(noVoice)
  local f = IntroWindow.frame or build()
  f.voiceShown = noVoice == true or not (WFJ.Voice and WFJ.Voice.hasPack())
  IntroWindow.selected = shownPurpose() or "ja" -- the choice the settings match, lit and described to start with
  IntroWindow.show("pick")
  relayoutWhenFonts(f)
  f:Show()
  return f
end

function IntroWindow.close()
  if IntroWindow.frame then IntroWindow.frame:Hide() end
end

-- ── When it opens ───────────────────────────────────────────────────────────
-- The client closes every window in UISpecialFrames (which is how Esc reaches this one) on its own
-- PLAYER_ENTERING_WORLD [verified: forever-ui-1.60.1.70425 blizzard_game/shared/eventimplementation.lua:306], when a
-- cinematic starts, such as a new character's race intro (CinematicFrame is a full-area panel, so showing it closes
-- the other windows [verified: blizzard_framexml/shared/cinematicframe.lua:89,
-- blizzard_uiparentpanelmanager/shared/uiparentpanelmanager.lua:281]), and again when the interface comes back after
-- it [verified: blizzard_game/shared/game.lua:91]. So the window opens a moment after it is asked for, waits out a
-- cinematic, and comes back after one that hid it. A hide outside a cinematic is the player's.

local function inCinematic()
  local playing = WFJ.Compat.resolve("InCinematic")
  return type(playing) == "function" and playing() == true
end

local function openNow()
  if IntroWindow.closedByPlayer then return end
  if inCinematic() then
    IntroWindow.waiting = true
    return
  end
  -- cleared only now, not at CINEMATIC_STOP: a hide's check a second later must still see a cinematic the player
  -- skipped within that second
  IntroWindow.waiting = false
  -- later than the login step, so the load guard is called again here: a failure is recorded as `intro`
  if WFJ.step then WFJ.step("intro", IntroWindow.open) else IntroWindow.open() end
end

local function onEvent(_, event)
  if IntroWindow.closedByPlayer then return end
  if event == "CINEMATIC_START" then
    IntroWindow.waiting = true
  elseif IntroWindow.waiting then
    later(openNow)
  end
end

-- Core/Intro's show: opens it a moment later, through any cinematic.
function IntroWindow.request()
  if not watcher then
    watcher = CreateFrame("Frame")
    watcher:RegisterEvent("CINEMATIC_START")
    watcher:RegisterEvent("CINEMATIC_STOP")
    watcher:SetScript("OnEvent", onEvent)
  end
  later(openNow)
end

-- A hide during a cinematic is the client's sweep. The cinematic's start may reach this addon after the sweep in the
-- same event, so the call is made a moment later, once CINEMATIC_START has been heard.
function IntroWindow.hidden()
  later(function()
    if IntroWindow.waiting or inCinematic() then return end
    IntroWindow.closedByPlayer = true
    if watcher then
      watcher:UnregisterEvent("CINEMATIC_START")
      watcher:UnregisterEvent("CINEMATIC_STOP")
    end
  end)
end
