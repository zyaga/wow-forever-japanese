-- UI/IntroWindow.lua: the welcome window (docs/systems/settings.md). Core/Intro decides when it is owed (once to
-- every player); Main hands it IntroWindow.request, which opens it. It can be opened again from the settings pages
-- and /wfj intro. The first page asks what the player is here for: three cards (study Japanese, study English,
-- just play), the selected one described under them, then how names should show (English names or Japanese names,
-- each with one example name as it will look), and Confirm, which writes those choices' ordinary settings.
-- After it comes a short tour, one page at a time with Back and Next: each page of IntroWindow.PAGES has a heading,
-- one picture (Media/Tour) and a few points, and a page that does not fit the player's choice is left out. A new
-- page is a new entry of that list, its picture and its texts.
-- It is the one addon window that shows both languages at once: the player has not learned the reveal key yet, so
-- a one-language window could be unreadable to them. The reveal key and the translation switch change nothing
-- here. Only the addon's own copy (UI/OptionsText), never game text.
local _, WFJ = ...
local IntroWindow = {}
WFJ.IntroWindow = IntroWindow

local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText
local WIDTH, LEFT = 640, 26
local HEIGHT = 620 -- the window is this tall on every page, so nothing moves under the mouse from page to page
local TEXT_WIDTH = WIDTH - 2 * LEFT
-- the inset panel moved up under the title bar and down to the bottom edge, as in UI/CollectorReminder
local INSET_TOP, INSET_BOTTOM = 24, 4
local TOP, BOTTOM, PAD = INSET_TOP + 4, INSET_BOTTOM + 4, 12
local LINE, BLOCK = 7, 14 -- between lines in a block; above and below the rule between the two blocks
local HEAD = 10 -- under a block's opening line
local KEY = "|cffffd200%s|r" -- the reveal key's name, in the gold the client uses for key names
local BOX, BUTTON = 20, 22
-- a tour picture is drawn at its file's own size, centred, so it is as sharp as the screenshot it was cut from
local PICTURE_W, PICTURE_H = 512, 256
local PICTURE_X = math.floor((TEXT_WIDTH - PICTURE_W) / 2)
local HEAD_ROOM, PICTURE_GAP = 44, 24 -- a tour page's heading (two lines), and the gap above and below its picture
local MEDIA = "Interface\\AddOns\\WoWForeverJapanese\\Media\\Tour\\"

IntroWindow.frame = nil
IntroWindow.closedByPlayer = false -- Close, Esc or any hide outside a cinematic: it stays closed
IntroWindow.waiting = false -- a cinematic is playing: open when it ends
local watcher -- the frame that hears the cinematic events, made by the first request

IntroWindow.step = "pick" -- "pick": the question and its three cards; "info": the tour
IntroWindow.page = 1 -- which of the tour's pages shows, among the ones the choice has
IntroWindow.selected = nil -- the card clicked on the first page; nothing is written until Confirm
IntroWindow.names = false -- the names choice clicked on the first page: Japanese names, or the client's English
-- The example both name options show: one NPC's name as the client writes it and as the name tables spell it. The
-- Japanese is read from the tables, so it is drawn as it will look; the spelling here stands in should the name
-- ever lose its line.
local EXAMPLE, EXAMPLE_JA = "Marshal McBride", "マーシャル・マクブライド"
local NAME_GAP, NAME_H = 12, 54
local NAME_W = math.floor((TEXT_WIDTH - NAME_GAP) / 2)
local ABOUT = 62 -- room under the cards for what the selected one does: three points
local NAMES_NOTE = 36 -- room under the names answers for the note on Japanese names: a line in each language
local BULLET = { ja = "・", en = "•  " }
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

-- The tour, in order. `picture` is a file of Media/Tour; `points` name the lines under it (POINTS below); `who`
-- lists the choices that see the page (every choice when it is missing; "other" is settings that match no choice).
-- A frozen tooltip takes its cards only while Japanese is what shows, so only studying Japanese has that page.
IntroWindow.PAGES = {
  { id = "start", picture = "start", points = { "lead", "hold", "minimap" } },
  { id = "cards", picture = "cards", points = { "readings", "words", "export" },
    who = { ja = true, en = true, other = true } },
  { id = "status", picture = "status", points = { "status.click", "status.marks", "status.import" },
    who = { ja = true, en = true, other = true } },
  { id = "freeze", picture = "freeze", points = { "freeze", "freeze.close" }, who = { ja = true } },
  { id = "chat", picture = "chat", points = { "chat.cards", "chat.copy", "chat.phrases" } },
  { id = "more", picture = "more", points = { "more.names", "more.report" } },
}

-- Each point's English and Japanese for the choice shown, with the keys named as they are set now; nothing for a
-- point that does not apply (it is then left out of its page).
local POINTS = {
  lead = function(shown) return Text.get(shown == "en" and "intro.lead.en" or "intro.lead") end,
  hold = function(shown)
    return Text.get(shown == "en" and "intro.hold.en" or "intro.hold", KEY:format(WFJ.Options.keyName()))
  end,
  minimap = function() return Text.get("intro.minimap") end,
  readings = function(shown) return Text.get(shown == "en" and "intro.readings.en" or "intro.readings") end,
  words = function()
    local click = WFJ.Settings.get("words.saveClick")
    if click == "off" then return nil end
    local d = WFJ.Settings.definition("words.saveClick")
    return Text.get("intro.words", KEY:format(d.choiceText and d.choiceText[click] or click))
  end,
  export = function() return Text.get("intro.export") end,
  ["status.click"] = function() return Text.get("intro.status.click") end,
  ["status.marks"] = function() return Text.get("intro.status.marks") end,
  ["status.import"] = function() return Text.get("intro.status.import") end,
  freeze = function()
    local key = WFJ.KeyCapture.keyOf(WFJ.KeyCapture.FREEZE)
    if key then return Text.get("intro.freeze", KEY:format(WFJ.KeyCapture.keyText(key))) end
    return Text.get("intro.freeze.unset")
  end,
  ["freeze.close"] = function() return Text.get("intro.freeze.close") end,
  ["chat.cards"] = function(shown)
    if shown == "play" then return nil end -- playing only has no word cards
    return Text.get("intro.chat.cards")
  end,
  ["chat.copy"] = function() return Text.get("intro.chat.copy") end,
  ["chat.phrases"] = function() return Text.get("intro.chat.phrases") end,
  ["more.names"] = function() return Text.get("intro.more.names") end,
  ["more.report"] = function() return Text.get("intro.more.report") end,
}

-- → the tour's pages for the choice the settings match now, in order
function IntroWindow.pages()
  local audience = shownPurpose() or "other"
  local out = {}
  for _, def in ipairs(IntroWindow.PAGES) do
    if def.who == nil or def.who[audience] then out[#out + 1] = def end
  end
  return out
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

-- A names option: its label in both languages and, under it, the example name as that option shows it. Lit like a
-- choice card while it is the one selected; a click only selects it.
local function nameCard(p, japanese)
  local c = CreateFrame("Button", nil, p, "BackdropTemplate")
  c:SetSize(NAME_W, NAME_H)
  if c.SetBackdrop then
    c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  end
  local en, ja = Text.get(japanese and "intro.names.japanese" or "intro.names.english")
  c.label = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  c.label:SetPoint("TOP", 0, -9)
  W.put(c.label, ja .. " / " .. en, 11)
  c.label:SetTextColor(W.JA_COLOR[1], W.JA_COLOR[2], W.JA_COLOR[3])
  c.example = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  c.example:SetPoint("TOP", c.label, "BOTTOM", 0, -7)
  c.example:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  c:SetScript("OnEnter", function(self) edge(self, true) end)
  c:SetScript("OnLeave", function(self) edge(self, self.picked) end)
  c:SetScript("OnClick", function() IntroWindow.selectNames(japanese) end)
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
  f.about = line(a, math.floor(TEXT_WIDTH / 2) - 6) -- two lists side by side: Japanese, then English
  -- how names show: the question and its two answers, side by side
  f.namesAsk = line(a)
  en, ja = Text.get("intro.names.ask")
  W.put(f.namesAsk.ja, ja, 13)
  W.put(f.namesAsk.en, en, 11)
  f.namesAsk.ja:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  f.nameCards = { [false] = nameCard(a, false), [true] = nameCard(a, true) }
  -- under them, only while Japanese names is the selected answer: what Confirm will turn on
  f.namesNote = line(a)
  en, ja = Text.get("intro.names.note")
  W.put(f.namesNote.ja, ja, 11)
  W.put(f.namesNote.en, en, 11)
  f.namesNote.ja:SetTextColor(W.JA_COLOR[1], W.JA_COLOR[2], W.JA_COLOR[3])
  en, ja = Text.get("intro.confirm")
  f.confirm = W.button(a, ja .. " / " .. en, nil, 150, function() IntroWindow.pick(IntroWindow.selected) end)
  -- beside the Confirm button: the Japanese, with its English under it
  f.later = line(a, TEXT_WIDTH - 170)
  en, ja = Text.get("intro.later")
  W.put(f.later.ja, ja, 11)
  W.put(f.later.en, en, 11)
  f.later.ja:SetTextColor(W.JA_COLOR[1], W.JA_COLOR[2], W.JA_COLOR[3])

  -- the tour: one page frame per entry of PAGES, with its heading, its picture and its points, every text in
  -- Japanese with its English under it
  f.tour = {}
  for _, def in ipairs(IntroWindow.PAGES) do
    local p = page()
    local t = { frame = p, head = line(p), points = {} }
    -- the heading as the question page's: gold, centred, the English under it
    t.head.ja:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
    for _, fs in ipairs({ t.head.ja, t.head.en }) do fs:SetJustifyH("CENTER") end
    t.picture = p:CreateTexture(nil, "ARTWORK")
    t.picture:SetSize(PICTURE_W, PICTURE_H)
    t.picture:SetTexture(MEDIA .. def.picture)
    for i, key in ipairs(def.points) do
      -- the hold-key point leaves room for the settings page's own Change button at its right
      t.points[i] = line(p, key == "hold" and TEXT_WIDTH - CHANGE - 10 or nil)
      t[key] = t.points[i]
    end
    f.tour[def.id] = t
  end
  local start, more = f.tour.start.frame, f.tour.more.frame
  f.hold = f.tour.start.hold
  f.capture = WFJ.KeyCapture.new(start, { mode = "reveal", width = CHANGE, onKey = function(v)
    WFJ.Options.setModifier(v)
    IntroWindow.refill()
  end, onRefused = function() IntroWindow.refill() end })
  -- the voice download, on the last page while no voice pack has loaded
  f.voice = line(more)
  f.box = W.copyBox(more, LEFT, 0, TEXT_WIDTH - 12, WFJ.Options.VOICE_URL)
  fill(f.voice, Text.get("intro.voice"))
  f.voiceTitle = more:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  en, ja = Text.get("intro.voiceTitle")
  W.put(f.voiceTitle, ja .. " / " .. en, 14)
  f.voiceTitle:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  f.voiceRule = rule(more)
  -- the foot of every tour page: Back at the left, the page's number, Next at the right (Start on the last page),
  -- each caption in both languages (nothing for W.pick to switch)
  f.foot = CreateFrame("Frame", nil, f)
  f.foot:SetPoint("BOTTOMLEFT", 0, BOTTOM)
  f.foot:SetPoint("BOTTOMRIGHT", 0, BOTTOM)
  f.foot:SetHeight(BUTTON + 2 * PAD)
  en, ja = Text.get("intro.back")
  f.back = W.button(f.foot, ja .. " / " .. en, nil, 150, function() IntroWindow.back() end)
  f.back:SetPoint("BOTTOMLEFT", LEFT, PAD)
  f.next = W.button(f.foot, "", nil, 150, function() IntroWindow.next() end) -- as wide as Confirm, in its place
  f.next:SetPoint("BOTTOMRIGHT", -LEFT, PAD)
  f.count = f.foot:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.count:SetPoint("BOTTOM", 0, PAD + 5)
  f:HookScript("OnHide", function() IntroWindow.hidden() end)
  IntroWindow.frame = f
  return f
end

-- Runs fn after `seconds` (1 by default), or now where the client timer is missing (the specs).
local function later(fn, seconds)
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(seconds or 1, fn) else fn() end
end

-- The first page: the question centred, the three cards side by side, the note under them.
local function layoutPick(f)
  local a = f.pickPage
  local askH = height(f.ask.ja) + 4 + height(f.ask.en)
  local namesH = height(f.namesAsk.ja) + PAIR + height(f.namesAsk.en)
  -- what the page needs from its top to under the note on names, then the room the Confirm row takes at the foot
  local body = PAD + 4 + askH + 18 + CARD_H + 16 + ABOUT + 10 + namesH + 8 + NAME_H + 8 + NAMES_NOTE
  local foot = 16 + BUTTON + PAD
  -- never shorter than the question needs; the tour takes the same height
  f.tall = math.max(HEIGHT, TOP + body + foot + BOTTOM)
  f:SetHeight(f.tall)
  -- The window is as tall as the tour's pages need, which is more than the question does: the room left over is
  -- shared out between the page's blocks, so the page fills the window instead of leaving it empty at the bottom.
  local spare = f.tall - (TOP + body + foot + BOTTOM)
  local function share(part) return math.floor(spare * part) end
  f.ask.ja:ClearAllPoints()
  f.headY = PAD + 4 + share(0.15) -- the tour's headings sit at the same height
  f.ask.ja:SetPoint("TOPLEFT", a, "TOPLEFT", LEFT, -f.headY)
  f.ask.en:ClearAllPoints()
  f.ask.en:SetPoint("TOPLEFT", f.ask.ja, "BOTTOMLEFT", 0, -4)
  local used = PAD + 4 + share(0.15) + askH
  for i, purpose in ipairs(PURPOSES) do
    local c = f.cards[purpose]
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", a, "TOPLEFT", LEFT + (i - 1) * (CARD_W + CARD_GAP), -(used + 18 + share(0.15)))
  end
  used = used + 18 + share(0.15) + CARD_H
  -- what the selected card does, in a fixed space so nothing moves from one card to the next
  f.about.ja:ClearAllPoints()
  f.about.ja:SetPoint("TOPLEFT", a, "TOPLEFT", LEFT, -(used + 16 + share(0.1)))
  f.about.en:ClearAllPoints()
  f.about.en:SetPoint("TOPLEFT", f.about.ja, "TOPLEFT", math.floor(TEXT_WIDTH / 2) + 6, 0)
  used = used + 16 + share(0.1) + ABOUT
  -- the names question on one line pair, then its two answers side by side
  f.namesAsk.ja:ClearAllPoints()
  f.namesAsk.ja:SetPoint("TOPLEFT", a, "TOPLEFT", LEFT, -(used + 10 + share(0.25)))
  f.namesAsk.en:ClearAllPoints()
  f.namesAsk.en:SetPoint("TOPLEFT", f.namesAsk.ja, "BOTTOMLEFT", 0, -PAIR)
  used = used + 10 + share(0.25) + namesH
  for i, japanese in ipairs({ false, true }) do
    local c = f.nameCards[japanese]
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", a, "TOPLEFT", LEFT + (i - 1) * (NAME_W + NAME_GAP), -(used + 8))
  end
  used = used + 8 + NAME_H
  -- the note has a fixed space, so nothing moves from one answer to the other
  f.namesNote.ja:ClearAllPoints()
  f.namesNote.ja:SetPoint("TOPLEFT", a, "TOPLEFT", LEFT, -(used + 8))
  f.namesNote.en:ClearAllPoints()
  f.namesNote.en:SetPoint("TOPLEFT", f.namesNote.ja, "BOTTOMLEFT", 0, -3)
  -- Confirm sits at the window's foot, where the tour's Next button is, with the two lines beside it
  f.confirm:ClearAllPoints()
  f.confirm:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", -LEFT, PAD)
  f.later.en:ClearAllPoints()
  f.later.en:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", LEFT, PAD + 1)
  f.later.ja:ClearAllPoints()
  f.later.ja:SetPoint("BOTTOMLEFT", f.later.en, "TOPLEFT", 0, 3)
end

-- One tour page, laid out like the question page so the window reads as one thing: the heading centred where the
-- question's heading is, the picture, the points that apply; on the first page the Change button beside the
-- hold-key point, and on the last, while no voice pack has loaded, a rule and the voice section. The heading, the
-- picture and the first point sit at the same height on every page, whatever the page holds, so nothing jumps
-- from one page to the next; only what is under the picture differs.
local function layoutPage(f, def)
  local t = f.tour[def.id]
  local y = f.headY or (PAD + 4)
  -- puts `region` at the running height, `x` in from the text's left edge, and moves on by `h`
  local function place(region, x, h)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", t.frame, "TOPLEFT", LEFT + x, -y)
    y = y + h
  end
  -- the heading's two lines take a fixed room, not their measured height, so the picture never moves
  place(t.head.ja, 0, HEAD_ROOM)
  t.head.en:ClearAllPoints()
  t.head.en:SetPoint("TOP", t.head.ja, "BOTTOM", 0, -4)
  y = y + PICTURE_GAP
  place(t.picture, PICTURE_X, PICTURE_H)
  y = y + PICTURE_GAP
  local first = true
  for _, r in ipairs(t.points) do
    if not r.off then
      if not first then y = y + POINT + 6 end
      first = false
      place(r.ja, 0, height(r.ja) + PAIR)
      place(r.en, 0, height(r.en))
    end
  end
  if def.id == "start" then
    f.capture.button:ClearAllPoints()
    f.capture.button:SetPoint("TOPRIGHT", f.hold.ja, "TOPLEFT", TEXT_WIDTH, 3)
  end
  if def.id == "more" and f.voiceShown then
    y = y + BLOCK + 2
    place(f.voiceRule, 0, 1)
    y = y + BLOCK
    place(f.voiceTitle, 0, height(f.voiceTitle) + HEAD)
    place(f.voice.ja, 0, height(f.voice.ja) + PAIR)
    place(f.voice.en, 0, height(f.voice.en) + LINE + 2)
    place(f.box, 6, BOX) -- InputBoxTemplate's left cap sits outside the frame
  end
end

-- The tour: every page the choice has is laid out, and the window keeps the one height it has on the question,
-- so it does not change size under the mouse from one page to the next. A hidden page's lines do not always
-- report their height, so the height never comes from what the pages measure.
local function layoutTour(f)
  for _, def in ipairs(IntroWindow.pages()) do layoutPage(f, def) end
  f:SetHeight(f.tall or HEIGHT)
end

local function layout(f)
  if IntroWindow.step == "info" then layoutTour(f) else layoutPick(f) end
end

local function refused(f)
  local lines = { f.ask, f.voice }
  for _, def in ipairs(IntroWindow.PAGES) do
    local t = f.tour[def.id]
    lines[#lines + 1] = t.head
    for _, r in ipairs(t.points) do lines[#lines + 1] = r end
  end
  for _, r in ipairs(lines) do
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
  for _, def in ipairs(IntroWindow.PAGES) do
    local t = f.tour[def.id]
    local title = (def.id == "start" and shown == "en") and "intro.tour.start.en" or ("intro.tour." .. def.id)
    local titleEn, titleJa = Text.get(title)
    W.put(t.head.ja, titleJa, 17)
    W.put(t.head.en, titleEn, 12)
    for i, key in ipairs(def.points) do
      local r = t.points[i]
      local en, ja = POINTS[key](shown)
      r.off = en == nil
      if en then fill(r, en, ja) end
      W.setShown(r.ja, en ~= nil)
      W.setShown(r.en, en ~= nil)
    end
  end
  for purpose, c in pairs(f.cards) do
    c.picked = IntroWindow.selected == purpose
    edge(c, c.picked)
  end
  -- the example as each names option shows it: the client's English, and the name tables' Japanese for it
  W.put(f.nameCards[false].example, EXAMPLE, 13)
  W.put(f.nameCards[true].example, (WFJ.Names and WFJ.Names.of(EXAMPLE)) or EXAMPLE_JA, 13)
  for japanese, c in pairs(f.nameCards) do
    c.picked = (IntroWindow.names == true) == japanese
    edge(c, c.picked)
  end
  W.setShown(f.namesNote.ja, IntroWindow.names == true)
  W.setShown(f.namesNote.en, IntroWindow.names == true)
  local aboutEn, aboutJa = Text.get("intro.about." .. (IntroWindow.selected or "ja"))
  W.put(f.about.ja, BULLET.ja .. aboutJa:gsub("\n", "\n" .. BULLET.ja), 13)
  W.put(f.about.en, BULLET.en .. aboutEn:gsub("\n", "\n" .. BULLET.en), 12)
  local pages = IntroWindow.pages()
  IntroWindow.page = math.max(1, math.min(IntroWindow.page, #pages))
  local current = IntroWindow.step == "info" and pages[IntroWindow.page] or nil
  W.setShown(f.pickPage, current == nil)
  W.setShown(f.foot, current ~= nil)
  for _, def in ipairs(IntroWindow.PAGES) do W.setShown(f.tour[def.id].frame, def == current) end
  if current then
    -- the last page's button starts the game: it closes the window
    local en, ja = Text.get(IntroWindow.page == #pages and "intro.close" or "intro.next")
    f.next:setLabel(ja .. " / " .. en)
    W.put(f.count, IntroWindow.page .. " / " .. #pages, 11)
  end
  for _, region in ipairs({ f.voiceRule, f.voiceTitle, f.voice.ja, f.voice.en, f.box }) do
    W.setShown(region, f.voiceShown)
  end
  layout(f)
  -- a FontString given new text may report its old height until the client has drawn it once [likely; in-game
  -- check: the intro window checklist in docs/testing/strategy.md]: the height is taken again on the next frame
  later(function() if f:IsShown() then layout(f) end end, 0)
end

-- Shows the question ("pick") or the tour from its first page ("info").
-- The key bindings changed (a key set under Keybindings, the freeze key's first binding): an open window names the
-- freeze key as it is bound now.
function IntroWindow.bindingsChanged()
  local f = IntroWindow.frame
  if f and f:IsShown() then IntroWindow.refill() end
end

function IntroWindow.show(step)
  IntroWindow.step = step
  if step == "info" then IntroWindow.page = 1 end
  IntroWindow.refill()
end

-- Next: the page after this one; on the last page it is Start, and closes the window.
function IntroWindow.next()
  if IntroWindow.page >= #IntroWindow.pages() then return IntroWindow.close() end
  IntroWindow.page = IntroWindow.page + 1
  IntroWindow.refill()
end

-- Back: the page before this one; from the first tour page, the question.
function IntroWindow.back()
  if IntroWindow.page <= 1 then return IntroWindow.show("pick") end
  IntroWindow.page = IntroWindow.page - 1
  IntroWindow.refill()
end

-- A card clicked on the first page: it lights up and the lines under the cards say what it does. Nothing is written.
function IntroWindow.select(purpose)
  IntroWindow.selected = purpose
  IntroWindow.refill()
end

-- A names option clicked on the first page: it lights up. Nothing is written.
function IntroWindow.selectNames(japanese)
  IntroWindow.names = japanese == true
  IntroWindow.refill()
end

-- Confirm: the selected choice's settings and the names choice, then the tour.
function IntroWindow.pick(purpose)
  local w = WRITES[purpose]
  -- confirming the choice the settings already match must not undo a study tab the player hid
  local changed = shownPurpose() ~= purpose
  WFJ.Settings.set("direction", w.direction)
  WFJ.Settings.set("readings.enabled", w.cards)
  if changed then WFJ.Settings.set("study.tab", w.tab) end
  WFJ.Settings.set("names.japanese", IntroWindow.names == true)
  IntroWindow.show("info")
end

-- Opens on the question, with the voice section on the second page only without a pack. → the frame
-- noVoice: draws the voice section as if no pack had loaded (`/wfj debug intro novoice`).
function IntroWindow.open(noVoice)
  local f = IntroWindow.frame or build()
  f.voiceShown = noVoice == true or not (WFJ.Voice and WFJ.Voice.hasPack())
  -- The one time the question is put to the player it starts on studying Japanese, what the addon is first for;
  -- opened again by hand it starts on the choice the settings match.
  local asking = IntroWindow.asking
  IntroWindow.asking = false
  IntroWindow.selected = asking and "ja" or shownPurpose() or "ja"
  IntroWindow.names = WFJ.Settings.get("names.japanese") == true -- English until the player picks Japanese
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

-- What waited for this window (IntroWindow.afterClose) has its turn, once.
local function released()
  local after = IntroWindow.after
  IntroWindow.after = nil
  if after then after() end
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
  IntroWindow.owed = false
  -- a window that failed to open will never be closed: nothing waits for it
  if not (IntroWindow.frame and IntroWindow.frame:IsShown()) then released() end
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
  IntroWindow.asking = true
  IntroWindow.owed = true -- asked for, not opened yet
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
    released()
  end)
end

-- Something else owed at the same login waits its turn: `fn` runs once, when the player has closed this window.
-- Two windows opened at once would lie on top of each other.
function IntroWindow.afterClose(fn)
  if IntroWindow.owed or (IntroWindow.frame and IntroWindow.frame:IsShown()) then
    IntroWindow.after = fn
  else
    fn() -- nothing to wait for: it never opened, or is closed already
  end
end
