-- UI/PhraseBook.lua: the phrase book (docs/systems/chat-tools.md), built the way the study tab and card are
-- (UI/StudyWindow): two small frames of the addon's own that share one saved spot (WFJ_DB.phrases.point). The
-- BUTTON is the client's own chat button with a gold 文. A click swaps it for the CARD at the same spot; the card's
-- minus puts the button back, its X hides both until /wfj phrases (the next login shows the button as before), and
-- either frame drags the other with it. The card: topics as the client's own tabs, two columns, one fixed size
-- whatever the topic. A click on a phrase types it into the chat box (Core/ChatPhrases.typed) and collapses the
-- card; the player presses Enter. Nothing here is a protected call.
local _, WFJ = ...
local Book = {}
WFJ.PhraseBook = Book

local Compat = WFJ.Compat
local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText
local SURFACE = "chat.phrasebook"
local CANDIDATES = { chatFrame = { "ChatFrame1" }, activeBox = { "ChatFrameUtil.GetActiveWindow" },
  openChat = { "ChatFrameUtil.OpenChat", "ChatFrame_OpenChat" } }

Book.COLS = 2
Book.ROWS = 8 -- the fullest topic the card has room for is COLS x ROWS phrases (a test holds the data to it)
local COL_W, ROW_H, PAD, HEAD, TABS_H, FOOT = 340, 38, 12, 34, 36, 24
local PAGE_TOP = HEAD + TABS_H + 6
local BUTTON_W, BUTTON_H = 27, 26

local db -- WFJ_DB (init): db.phrases = { point = { p, rp, x, y } }
local card, button
local rows, tabs, topic = {}, {}, nil
local cardOpen, closed = false, false

local function pick(key) return W.pick(Text.get(key)) end

local function opt()
  db = db or {} -- opened before (or without) init: the spot is then kept for the session only
  db.phrases = db.phrases or {}
  return db.phrases
end

-- ── Placement ─────────────────────────────────────────────────────────────

-- where the player dragged either frame, else by the chat frame's own buttons, above its menu button
local function place(f)
  if not f then return end
  f:ClearAllPoints()
  local p = opt().point
  local parent = Compat.resolve("UIParent")
  if type(p) == "table" and type(p[1]) == "string" and type(p[2]) == "string" and type(p[3]) == "number"
      and type(p[4]) == "number" then
    f:SetPoint(p[1], parent, p[2], p[3], p[4])
    return
  end
  -- never dragged: beside the chat window itself, so it is right however early this runs and follows the chat
  -- window when the player moves it (the screen clamp keeps it on screen)
  local chat = Compat.get(SURFACE, "chatFrame")
  local menu = Compat.resolve("ChatFrameMenuButton")
  if f == button and type(menu) == "table" and menu.IsShown and menu:IsShown() then
    f:SetPoint("BOTTOM", menu, "TOP", 0, -2) -- centred over the chat window's own menu button
  elseif type(chat) == "table" and chat.buttonSide == "right" then
    -- the client moved the chat window's buttons to its right side: the card opens there too
    f:SetPoint("BOTTOMRIGHT", chat, "BOTTOMRIGHT", BUTTON_W + 4, 34)
  elseif type(chat) == "table" then
    f:SetPoint("BOTTOMLEFT", chat, "BOTTOMLEFT", -(BUTTON_W + 4), 34)
  else
    f:SetPoint("LEFT", parent, "LEFT", 4, 0)
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
    place(self == card and button or card) -- the other frame follows
  end)
end

-- ── Typing a phrase ────────────────────────────────────────────────────────

-- Into the chat box that is open, else a new one. The text goes in with the edit box's own Insert or the client's
-- own open call; the player sends it.
function Book.type(phrase)
  local text = WFJ.ChatPhrases.typed(phrase)
  local active = Compat.get(SURFACE, "activeBox")
  local box = type(active) == "function" and active() or nil
  if type(box) == "table" and type(box.Insert) == "function" then
    box:Insert(text)
    return text
  end
  local open = Compat.get(SURFACE, "openChat")
  if type(open) == "function" then open(text) end
  return text
end

-- ── The card ───────────────────────────────────────────────────────────────

-- the tab strip puts the client's own (Latin-only) font back on a tab when it is selected: ours goes back on
local function fontTabs()
  if not card then return end
  for _, tab in ipairs(tabs) do
    tab.Text:SetText(pick("chat.topic." .. tab.topic))
    WFJ.Font.set(tab.Text, WFJ.Font.PATH, 14, "")
    -- a tab made with no text was given a text area of almost no width, and the tab's own sizing reads that width
    -- back [verified: forever blizzard_sharedxml/shared/tabsystem/tabsystemtemplates.lua:225–250, UpdateTabWidth]:
    -- cleared, so it measures the words (a cut-off tab is blank and shows the client's tooltip)
    tab.Text:SetWidth(0)
    if tab.UpdateTabWidth then tab:UpdateTabWidth() end
  end
  -- the client's tabs have a least width of their own, and nine of them are wider than the card: the strip is
  -- drawn smaller so every topic sits inside it (the words are set larger above to make up for it)
  local total = 0
  for _, tab in ipairs(tabs) do total = total + (tab.GetWidth and tab:GetWidth() or 0) + 1 end
  local room = Book.COLS * COL_W
  local ts = card.tabSystem
  if ts.SetScale then
    local scale = total > room and room / total or 1
    ts:SetScale(scale)
    ts:ClearAllPoints() -- offsets are counted in the strip's own, smaller units
    ts:SetPoint("BOTTOMLEFT", card, "TOPLEFT", PAD / scale, -(HEAD + TABS_H) / scale)
  end
  if card.tabSystem.MarkDirty then card.tabSystem:MarkDirty() end
end

local function row(n)
  local r = rows[n]
  if r then return r end
  r = CreateFrame("Button", nil, card)
  r:SetSize(COL_W - 6, ROW_H - 4)
  r:SetPoint("TOPLEFT", card, "TOPLEFT", PAD + ((n - 1) % Book.COLS) * COL_W,
    -PAGE_TOP - math.floor((n - 1) / Book.COLS) * ROW_H)
  r:RegisterForClicks("LeftButtonUp")
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(r)
  hl:SetColorTexture(1, 0.82, 0, 0.12)
  r.ja = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.ja:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -2)
  r.ja:SetWidth(COL_W - 18)
  r.ja:SetJustifyH("LEFT")
  r.ja:SetWordWrap(false)
  r.en = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.en:SetPoint("TOPLEFT", r.ja, "BOTTOMLEFT", 0, -2)
  r.en:SetWidth(COL_W - 18)
  r.en:SetJustifyH("LEFT")
  r.en:SetWordWrap(false)
  -- one click types the phrase and gets out of the way: the card goes back to the button
  r:SetScript("OnClick", function(self)
    Book.type(self.phrase)
    Book.collapse()
  end)
  rows[n] = r
  return r
end

local function fill()
  local n = 0
  for _, p in ipairs(WFJ.ChatPhrases.list()) do
    if p.topic == topic then
      n = n + 1
      local r = row(n)
      r.phrase = p
      r.ja:SetText(p.ja)
      WFJ.Font.set(r.ja, WFJ.Font.PATH, 14, "")
      r.en:SetText(p.en)
      r:Show()
    end
  end
  for i = n + 1, #rows do rows[i]:Hide() end
  return n
end

function Book.pick(name)
  topic = name
  for _, tab in ipairs(tabs) do
    if tab.topic == name then card.tabSystem:SetTabVisuallySelected(tab.tabID) end
  end
  fontTabs()
  return fill()
end

local function relabel()
  if not card then return end
  card.title:SetText(pick("chat.book.title"))
  WFJ.Font.set(card.title, WFJ.Font.PATH, 15, "")
  card.foot:SetText(pick("chat.book.how"))
  WFJ.Font.set(card.foot, WFJ.Font.PATH, 11, "")
  fontTabs()
end

local function buildCard()
  -- the study card's own frame: the same backdrop, border and header buttons (UI/StudyWindow)
  local f = CreateFrame("Frame", "WFJPhraseCard", Compat.resolve("UIParent"), "BackdropTemplate")
  f:SetSize(2 * PAD + Book.COLS * COL_W, PAGE_TOP + Book.ROWS * ROW_H + FOOT + PAD)
  f:SetFrameStrata("HIGH")
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.06, 0.05, 0.04, 0.92)
    f:SetBackdropBorderColor(0.45, 0.32, 0.18, 1)
  end
  movable(f)
  card = f
  f.tabs, f.rows = tabs, rows -- the in-game window test walks them (pipeline/wfj/dev/client_surface.py)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetSize(24, 24)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  f.close:SetScript("OnClick", function() Book.close() end)
  f.minus = CreateFrame("Button", nil, f, "UIPanelHideButtonNoScripts")
  f.minus:SetSize(24, 24)
  f.minus:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
  f.minus:SetScript("OnClick", function() Book.collapse() end)
  -- the client's own tab strip under the header, on a thin line [verified: TabSystemTemplate and
  -- TabSystemTopButtonTemplate, forever blizzard_sharedxml/shared/tabsystem/; UI/FixWindow builds its tabs so]
  local ts = CreateFrame("Frame", nil, f, "TabSystemTemplate")
  ts.tabTemplate = "TabSystemTopButtonTemplate"
  ts.tabPool = CreateFramePool("BUTTON", ts, "TabSystemTopButtonTemplate")
  ts.minTabWidth = 60
  ts:SetPoint("BOTTOMLEFT", f, "TOPLEFT", PAD, -(HEAD + TABS_H))
  f.tabSystem = ts
  local rule = f:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(0.45, 0.32, 0.18, 1)
  rule:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(HEAD + TABS_H))
  rule:SetSize(Book.COLS * COL_W, 1)
  local byID = {}
  for i, name in ipairs(WFJ.ChatPhrases.topics()) do
    local tabID = ts:AddTab("")
    local tab = ts:GetTabButton(tabID)
    tab.topic, tab.tabID = name, tabID
    tabs[i], byID[tabID] = tab, name
  end
  -- a click shows the topic; pick sets the visual selection itself (true: the widget's own is suppressed)
  ts:SetTabSelectedCallback(function(tabID)
    Book.pick(byID[tabID])
    return true
  end)
  hooksecurefunc(ts, "SetTabVisuallySelected", fontTabs)
  f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
  f.foot:SetTextColor(0.6, 0.6, 0.6)
  f:Hide()
  return f
end

-- ── The button ─────────────────────────────────────────────────────────────

local function buildButton()
  -- the client's own chat button: its size and its three pictures [verified: VoiceToggleButtonTemplate, forever
  -- blizzard_voicetogglebutton/voicetogglebutton.xml:3–19 (27 x 26, chatframe-button-up / -down / -highlight)],
  -- with a gold 文 where the client's buttons carry their icon
  local b = CreateFrame("Button", "WFJPhraseButton", Compat.resolve("UIParent"))
  b:SetSize(BUTTON_W, BUTTON_H)
  b:SetFrameStrata("MEDIUM")
  movable(b)
  b:RegisterForClicks("LeftButtonUp")
  b:SetNormalAtlas("chatframe-button-up")
  b:SetPushedAtlas("chatframe-button-down")
  b:SetHighlightAtlas("chatframe-button-highlight", "ADD")
  b.glyph = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  WFJ.Font.set(b.glyph, WFJ.Font.PATH, 14, "")
  b.glyph:SetTextColor(1, 0.82, 0)
  b.glyph:SetText("文")
  b.glyph:SetPoint("CENTER", b, "CENTER", 0, 0)
  b:SetScript("OnMouseDown", function(self) self.glyph:SetPoint("CENTER", self, "CENTER", -1, -2) end)
  b:SetScript("OnMouseUp", function(self) self.glyph:SetPoint("CENTER", self, "CENTER", 0, 0) end)
  b:SetScript("OnClick", function() Book.open() end)
  W.hoverLabel(b, function() return pick("chat.book.title") end)
  b:Hide()
  button = b
  return b
end

-- ── What is on screen ──────────────────────────────────────────────────────

-- One place decides: the card when open; else the button, unless it was closed for the session, its setting is
-- off, or there is no chat frame for it to sit by. Like the study card, it shows with translation off too.
local function apply()
  local showButton = not cardOpen and not closed
    and WFJ.Settings.get("chat.phraseButton") == true and type(Compat.get(SURFACE, "chatFrame")) == "table"
  if card then card:SetShown(cardOpen) end
  if showButton and not button then buildButton() end
  if button then
    if showButton then place(button) end
    button:SetShown(showButton)
  end
end

-- The button becomes the card, at the same spot; opens whatever the button's setting says.
function Book.open()
  if not card then buildCard() end
  closed, cardOpen = false, true
  place(card)
  relabel()
  apply()
  Book.pick(topic or WFJ.ChatPhrases.topics()[1])
  return card
end

-- The card becomes the button again.
function Book.collapse()
  cardOpen = false
  apply()
end

-- Hides the card and the button until something opens the card again.
function Book.close()
  closed, cardOpen = true, false
  apply()
end

function Book.toggle()
  if cardOpen then Book.collapse() else Book.open() end
end

function Book.frames() return button, card end

-- Called by Main with WFJ_DB once the chat frames exist.
function Book.init(saved)
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  db = saved
  closed, cardOpen = false, false
  WFJ.State.on("chat", function() pcall(apply) end)
  WFJ.State.on("enabled", function() pcall(apply) end)
  WFJ.State.on("language", function() pcall(relabel) end)
  apply()
  return true
end
