-- A stand-in for the Dialogue UI addon's two windows, written for these specs from how that addon behaves (read at
-- its 1.0.7 c source; none of its code is here). What the adapter relies on:
--   * DUIQuestFrame's page handlers run self:ReleaseAllObjects() first, then lay the page out top to bottom.
--   * FormatParagraph splits its text on control characters and, per piece, acquires a pooled FontString
--     (self:AcquireLeftFontString, which takes it from self:AcquireFontString and calls SetFontObject on it), sets
--     the text and measures it at once. The pool's EnumerateActive lists the FontStrings in use, newest last.
--   * Quest bodies go through self:FormatQuestText(offsetY, method), which reads the text itself; the offer's
--     objectives through FormatParagraph; the progress page's objective lines ("- line" rows) through InsertText.
--   * UpdateQuestTitle writes FrontFrame.Header.Title; option buttons write their label in SetButtonText (the label,
--     then Layout measures it), gossip options through SetGossip(data, hotkey) and quest rows through
--     SetQuestName(questInfo), which also runs again when the quest's data loads late. Before writing the label each
--     sets the fields its click reads (type, id, gossipOptionID, onClickFunc).
--   * OnSettingsChanged re-runs the current handler one frame later (C_Timer.After 0); its HideUI hides the frame.
--   * DUIBookFrame caches every page's paragraphs into one content table (entries { text, fontTag, isPageStart }),
--     measures them with its book font objects, then ShowUI hands the table to its ScrollFrame, which writes an
--     entry into a FontString only when it is laid out (ScrollFrame:SetObjectData). OnSettingsChanged measures
--     the same table again and calls ShowUI again.
local Stub = require("tests.lua.spec.wow_stub")

local DUI = {}

local function split(text)
  local out = {}
  for piece in tostring(text or ""):gmatch("[^%c]+") do
    if piece ~= " " then out[#out + 1] = piece end
  end
  return out
end
DUI.split = split

-- Frames created with `parent` hear its hide, as the client's child frames do.
local function hideChildren(parent)
  for _, f in ipairs(Stub.frames) do
    if f.parent == parent and f.shown and f.scripts.OnHide then f.scripts.OnHide(f) end
  end
end

local function fontObject(name, path, size)
  local obj = Stub.fontObject(path, size, "")
  function obj:SetFont(p, s, f) self.font = { path = p, size = s, flags = f or "" }; return true end
  obj.name = name
  _G[name] = obj
  return obj
end

-- where a span of characters sits: one fixed rectangle is enough for these specs
local function AREA() return { { left = 0, bottom = 0, width = 10, height = 10 } } end

-- Every FontString a frame's pool hands out, with what it held and the font it wore when the frame measured it.
local function pool(frame)
  local p = { all = {}, active = {} }
  function p.acquire()
    local fs
    for _, f in ipairs(p.all) do
      if not f.inUse then fs = f; break end
    end
    if not fs then
      fs = Stub.fontString("")
      fs.parent = frame
      fs.GetParent = function(x) return x.parent end
      fs.CalculateScreenAreaFromCharacterSpan = AREA
      p.all[#p.all + 1] = fs
    end
    fs.inUse = true
    p.active[#p.active + 1] = fs
    return fs
  end
  function p.release()
    for _, f in ipairs(p.active) do f.inUse = false; f.text = ""; f.ttsFlag = nil end
    p.active = {}
  end
  function p.EnumerateActive()
    local copy = {}
    for i, f in ipairs(p.active) do copy[i] = f end
    return ipairs(copy)
  end
  -- Dialogue UI's pools are tables with methods: the specs check none of them is replaced
  function p:Acquire() return p.acquire() end
  return p
end

-- Dialogue UI's option click: it reads the button's own handler [read: UITemplates.lua OnClick]
local function SELECT_OPTION() end
local function SELECT_QUEST() end
local function GOODBYE_CLICK() end
DUI.SELECT_OPTION, DUI.SELECT_QUEST, DUI.GOODBYE_CLICK = SELECT_OPTION, SELECT_QUEST, GOODBYE_CLICK

local function button(frame)
  local b = CreateFrame("Button", nil, frame)
  b.Name = Stub.fontString("")
  b.Name:SetFontObject(_G.DUIFont_Quest_Gossip)
  -- sizes the button to its label as it shows now
  function b:Layout(largePadding)
    self.measuredFont = { self.Name:GetFont() }
    self.measuredText = self.Name:GetText()
    self.largePadding = largePadding
    self.layouts = (self.layouts or 0) + 1
  end
  function b:SetButtonText(name, largePadding)
    self.Name:SetText(name)
    self:Layout(largePadding)
  end
  function b:SetGossip(data, hotkey)
    self.gossipOptionID = data.gossipOptionID
    self.iconFor = data.name -- some option icons are picked by the option's English name
    self.id, self.type, self.onClickFunc = data.orderIndex or 0, "gossip", SELECT_OPTION
    local name = data.name
    if hotkey then name = hotkey .. ". " .. name end
    self:SetButtonText(name, false)
  end
  function b:SetQuestName(questInfo)
    if questInfo.level then
      self:SetButtonText(("[%d] %s"):format(questInfo.level, questInfo.title), true)
    else
      self:SetButtonText(questInfo.title, true)
    end
  end
  function b:SetQuest(questInfo, hotkey)
    self.type, self.onClickFunc = "availableQuest", SELECT_QUEST
    self.questInfo, self.hotkey, self.questID = questInfo, hotkey, questInfo.questID
    self:SetQuestName(questInfo)
  end
  -- the quest's data arrived after the button was set: the label is written again from the same questInfo
  function b:loadLater() self:SetQuestName(self.questInfo) end
  return b
end

-- Page data the handlers read: DUI.page = { npc, gossip, options, quests, hint, prefixName, title, questID,
-- description, objectives, progress, completion, greeting, progressLines }
DUI.page = {}

local QUEST_TEXT = { Detail = "description", Progress = "progress", Complete = "completion" }

function DUI.installQuestFrame(opts)
  opts = opts or {}
  fontObject("DUIFont_Quest_Paragraph", "Interface\\AddOns\\DialogueUI\\Fonts\\frizqt__.ttf", 14)
  fontObject("DUIFont_Quest_Gossip", "Interface\\AddOns\\DialogueUI\\Fonts\\frizqt__.ttf", 13)
  fontObject("DUIFont_Quest_Title_18", "Interface\\AddOns\\DialogueUI\\Fonts\\frizqt__.ttf", 18)
  fontObject("DUIFont_Quest_SubHeader", "Interface\\AddOns\\DialogueUI\\Fonts\\frizqt__.ttf", 14)
  fontObject("DUIFont_Item", "Interface\\AddOns\\DialogueUI\\Fonts\\frizqt__.ttf", 10)
  local f = CreateFrame("Frame", "DUIQuestFrame")
  f.fontStringPool = pool(f)
  f.buttons = {}
  f.redraws = 0
  f.FrontFrame = { Header = { Title = Stub.fontString("") } }
  -- the tag over the title ("Dungeon"): a button with its own SetText, in Dialogue UI's DUIFont_Item
  local tag = { ButtonText = Stub.fontString("") }
  tag.ButtonText:SetFontObject(_G.DUIFont_Item)
  function tag:SetText(t) self.ButtonText:SetText(t) end
  -- QuestHeaderWidget.lua ButtonMixin: a tag Dialogue UI fills in later, when its quest data comes; its
  -- SetClickable(false) applies DUIFont_Item after the text
  function tag:SetQuestTagNameAndIcon(name)
    self:SetText(name)
    self.ButtonText:SetFontObject(_G.DUIFont_Item)
  end
  f.tag = tag
  f.FrontFrame.Header.GetChildren = function() return tag end
  f.headings = {}
  f.ExitButton = button(f)
  f.ExitButton.type, f.ExitButton.onClickFunc = "goodbye", GOODBYE_CLICK
  -- the option buttons in use, in the order they were taken
  f.optionButtonPool = { EnumerateActive = function()
    local out = {}
    for _, b in ipairs(f.buttons) do if b.inUse then out[#out + 1] = b end end
    return ipairs(out)
  end }
  -- the page scroll: ReleaseAllObjects puts it back at the top
  f.ScrollFrame = { value = 0 }
  function f.ScrollFrame:SnapTo(v) self.value = v end
  f.FrontFrame.Header.Title:SetFontObject(_G.DUIFont_Quest_Title_18)

  function f:Hide()
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
    hideChildren(self)
  end

  function f:AcquireFontString()
    return self.fontStringPool.acquire()
  end
  function f:AcquireLeftFontString(obj)
    local fs = self:AcquireFontString()
    fs:SetFontObject(obj or _G.DUIFont_Quest_Paragraph)
    return fs
  end
  -- a section heading on a band sized from the heading's width as measured now
  function f:AcquireAndSetSubHeader(text)
    local fs = self:AcquireFontString()
    fs:SetFontObject(_G.DUIFont_Quest_SubHeader)
    fs:SetText(text)
    local bg = { fs = fs, height = 20, measuredFont = { fs:GetFont() } }
    bg.SetSize = function(b, w, h) b.width, b.height = w, h end
    bg.GetHeight = function(b) return b.height end
    fs.GetWrappedWidth = function(x) return #x.text * (x.font.path:find("ipagui", 1, true) and 4 or 6) end
    bg:SetSize(fs:GetWrappedWidth() + 16, 20)
    self.headings[#self.headings + 1] = bg
    return bg
  end
  function f:AcquireExitButton() return self.ExitButton end
  -- the reward list: its heading set straight on a FontString
  function f:FormatRewards(offsetY)
    if DUI.page.rewardsHeader then
      local fs = self:AcquireLeftFontString()
      fs:SetText(DUI.page.rewardsHeader)
    end
    return offsetY
  end
  function f:AcquireOptionButton()
    local b
    for _, x in ipairs(self.buttons) do
      if not x.inUse then b = x; break end
    end
    if not b then
      b = button(self)
      self.buttons[#self.buttons + 1] = b
    end
    b.inUse = true
    return b
  end
  function f:ReleaseAllObjects()
    self.ScrollFrame.value = 0
    self.fontStringPool.release()
    for _, b in ipairs(self.buttons) do b.inUse = false end
  end
  function f:FormatParagraph(offsetY, text, ttsFlag)
    local first, last
    for _, piece in ipairs(split(text)) do
      local fs = self:AcquireLeftFontString()
      fs:SetText(piece)
      fs.measuredFont = { fs:GetFont() }
      fs.ttsFlag = ttsFlag
      first = first or fs
      last = fs
      offsetY = offsetY + fs:GetHeight()
    end
    return offsetY, first, last
  end
  function f:InsertText(offsetY, text, obj)
    local fs = self:AcquireLeftFontString(obj)
    fs:SetText(text)
    fs.measuredFont = { fs:GetFont() }
    return offsetY + fs:GetHeight()
  end
  local function named(text)
    if DUI.page.prefixName and text then return DUI.page.npc .. ": " .. text end
    return text
  end
  function f:FormatQuestText(offsetY, method)
    local text = named(DUI.page[QUEST_TEXT[method]])
    if text and text ~= "" then offsetY = self:FormatParagraph(offsetY, text, 3) end
    return offsetY, nil
  end
  function f:UpdateQuestTitle()
    self.FrontFrame.Header.Title:SetFontObject(_G.DUIFont_Quest_Title_18)
    self.FrontFrame.Header.Title:SetText(GetTitleText())
    self.tag:SetText(DUI.page.tag or "")
    return 6
  end
  function f:HandleGossip()
    self:ReleaseAllObjects()
    local text = C_GossipInfo.GetText()
    if DUI.page.hint then text = DUI.page.hint .. "\n\n" .. text end
    self:FormatParagraph(0, named(text), 0)
    for i, opt in ipairs(DUI.page.options or {}) do
      self:AcquireOptionButton():SetGossip({ name = opt, orderIndex = i - 1 }, i)
    end
    for _, q in ipairs(DUI.page.quests or {}) do
      self:AcquireOptionButton():SetQuest({ questID = q.id, title = q.title, level = q.level })
    end
    self:AcquireExitButton():SetButtonText(_G.GOODBYE or "Goodbye", true)
  end
  function f:HandleQuestGreeting()
    self:ReleaseAllObjects()
    self:FormatParagraph(0, named(GetGreetingText()), 0)
    for _, q in ipairs(DUI.page.quests or {}) do
      self:AcquireOptionButton():SetQuest({ questID = q.id, title = q.title, level = q.level })
    end
  end
  function f:HandleQuestDetail()
    self:ReleaseAllObjects()
    self.questID = GetQuestID()
    self:UpdateQuestTitle("Detail")
    local y = self:FormatQuestText(0, "Detail")
    local objectives = GetObjectiveText()
    if objectives and objectives ~= "" then self:FormatParagraph(y, objectives, 3) end
    for _, h in ipairs(DUI.page.headings or {}) do self:AcquireAndSetSubHeader(h) end
    if DUI.page.rewardLine then self:InsertText(y, DUI.page.rewardLine) end
    self:FormatRewards(y)
  end
  function f:HandleQuestProgress()
    self:ReleaseAllObjects()
    self.questID = GetQuestID()
    self:UpdateQuestTitle("Progress")
    local y = self:FormatQuestText(0, "Progress")
    if DUI.page.progressLines then self:InsertText(y, DUI.page.progressLines) end
  end
  function f:HandleQuestComplete()
    self:ReleaseAllObjects()
    self.questID = GetQuestID()
    self:UpdateQuestTitle("Complete")
    self:FormatQuestText(0, "Complete")
  end
  local HANDLERS = { GOSSIP_SHOW = "HandleGossip", QUEST_GREETING = "HandleQuestGreeting",
    QUEST_DETAIL = "HandleQuestDetail", QUEST_PROGRESS = "HandleQuestProgress", QUEST_COMPLETE = "HandleQuestComplete" }
  function f:ShowUI(event)
    self.handler = HANDLERS[event]
    self[self.handler](self)
    self:Show()
  end
  function f:OnSettingsChanged()
    if not (self:IsShown() and self.handler) or self.settingsDirty then return end
    self.settingsDirty = true
    C_Timer.After(0, function()
      self.settingsDirty = nil
      self.redraws = self.redraws + 1
      self[self.handler](self)
    end)
  end
  function f:HideUI() self:Hide() end
  for _, name in ipairs(opts.without or {}) do f[name] = nil end
  return f
end

-- Dialogue UI's chat panel: an unnamed frame whose scroll view (a child frame) keeps the lines it was given in its
-- data provider's list, each with the speaker's words before it, measured through the panel's font object as they
-- come in (ChatFrame.lua AddMessage, ScrollViewDataProvider:AddContent / CalculateAllExtent).
local CHAT_PREFIX = { CHAT_MSG_MONSTER_SAY = "%s says: ", CHAT_MSG_MONSTER_YELL = "%s yells: " }
function DUI.installChatPanel()
  fontObject("DUIFont_ChatFont", "Interface\\AddOns\\DialogueUI\\Fonts\\frizqt__.ttf", 10)
  local c = CreateFrame("Frame")
  local view = CreateFrame("Frame", nil, c)
  local list = { content = {}, objects = {}, measured = {}, isVisible = true, views = 0 }
  view.dataProvider = list
  function list:CalculateAllExtent()
    self.measured = {}
    for i, v in ipairs(self.content) do self.measured[i] = { v[1], _G.DUIFont_ChatFont:GetFont() } end
  end
  function list:UpdateView() self.views = self.views + 1 end
  c.lines = list.content
  c.GetChildren = function() return view end
  function c:AddMessage(text, name, event)
    if event == "CHAT_MSG_MONSTER_EMOTE" then
      if text:find("%%s") then text = text:format(name) else text = text:gsub("%%", "") end
    end
    local prefix = CHAT_PREFIX[event]
    if prefix then text = prefix:format(name) .. text end
    list.content[#list.content + 1] = { text, event }
    list.measured[#list.content] = { text, _G.DUIFont_ChatFont:GetFont() }
    local obj = Stub.fontString("")
    obj.dataIndex = #list.content
    obj:SetText(text)
    list.objects[#list.objects + 1] = obj
  end
  c.SendContentToClipboard = function() end
  c.UpdateVisibility = function() end
  c.list = list
  return c
end

-- Dialogue UI's item tooltip: an unnamed frame with a line grid (Tooltip_Base.lua). A line is added to the grid's
-- next row (left) or the current row's second column (right); an empty text adds nothing. Its reader of the client's
-- tooltip data keeps the data and adds one line per data line (Tooltip_Private.lua ProcessTooltipData,
-- ProcessTooltipDataLines). Its layout, when it shows, passes over a row with no entry.
function DUI.installTooltip()
  local t = CreateFrame("Frame")
  t.numLines, t.grid = 0, {}
  t.ProcessInfo = function() end
  function t:AddLeftLine(text)
    if not text or text == "" then return end
    self.numLines = self.numLines + 1
    local fs = Stub.fontString(text)
    self.grid[self.numLines] = { fs }
    return fs
  end
  function t:AddRightLine(text)
    if not text or text == "" then return end
    local fs = Stub.fontString(text)
    self.grid[self.numLines] = self.grid[self.numLines] or {}
    self.grid[self.numLines][2] = fs
    return fs
  end
  function t:ProcessTooltipDataLines(lines)
    for _, line in ipairs(lines) do
      if line.leftText then self:AddLeftLine(line.leftText) end
      if line.rightText then self:AddRightLine(line.rightText) end
    end
  end
  function t:ProcessTooltipData(tipData)
    self.numLines, self.grid, self.tooltipData = 0, {}, tipData
    self:ProcessTooltipDataLines(tipData.lines, 1)
    return true
  end
  -- the rows its layout shows, in order
  function t:texts()
    local out = {}
    for i = 1, self.numLines do
      if self.grid[i] then out[#out + 1] = self.grid[i][1]:GetText() end
    end
    return out
  end
  function t:right(row) return self.grid[row] and self.grid[row][2] end
  return t
end

-- The quest-complete flyout, made when first needed: SetQuestText writes the title and lays each paragraph out from a
-- pool of texts as it writes them (QuestFlyout.lua, QuestFlyoutFrameMixin:SetQuestText).
function DUI.makeFlyout()
  local f = CreateFrame("Frame")
  f.Title = Stub.fontString("")
  f.texts = {}
  f.fontStringPool = {}
  function f.fontStringPool:Acquire()
    local fs = Stub.fontString("")
    f.texts[#f.texts + 1] = fs
    return fs
  end
  function f.fontStringPool:EnumerateActive()
    local copy = {}
    for i, fs in ipairs(f.texts) do copy[i] = fs end
    return ipairs(copy)
  end
  -- SetQuestData keeps the quest's data (its paragraphs among it) and writes it with SetQuestText
  function f:SetQuestText(title, paragraphs)
    self.texts = {}
    self.Title:SetText(title)
    self.measuredIn = {}
    for _, text in ipairs(paragraphs) do
      if text ~= "" and text ~= " " then
        local fs = self.fontStringPool:Acquire()
        fs:SetText(text)
        self.measuredIn[#self.measuredIn + 1] = fs.font and fs.font.path or "client" -- the face it is measured in
      end
    end
  end
  function f:SetQuestData(data)
    self.questData = data
    self:SetQuestText(data.title, data.paragraphs)
  end
  f.SetQuestRewards = function() end
  function f:paragraphs()
    local out = {}
    for i, fs in ipairs(self.texts) do out[i] = fs:GetText() end
    return out
  end
  return f
end

-- A quest popup, made when one is first needed (after this addon installed).
function DUI.makePopup()
  local p = CreateFrame("Frame")
  p.Title = Stub.fontString("")
  -- the name written, then scaled to fit as it shows (Widget_QuestPopup.lua SetTitle, FontUtil SetAutoScalingText)
  function p:SetTitle(title)
    self.Title:SetText("")
    self.Title:SetText(title)
    self.scaledFor = self.Title:GetText()
  end
  function p:SetQuestDataByID(questID)
    self.questID = questID
    self:SetTitle(DUI.questNames[questID])
    self:Show()
  end
  return p
end
DUI.questNames = {}

-- The game API the quest window reads, over DUI.page.
function DUI.installGameAPI()
  DUI.page = {}
  DUI.timers = {}
  _G.C_Timer = { After = function(_, fn) DUI.timers[#DUI.timers + 1] = fn end }
  _G.C_GossipInfo = { GetText = function() return DUI.page.gossip end }
  _G.GetQuestID = function() return DUI.page.questID or 0 end
  _G.GetTitleText = function() return DUI.page.title end
  _G.GetQuestText = function() return DUI.page.description end
  _G.GetObjectiveText = function() return DUI.page.objectives end
  _G.GetProgressText = function() return DUI.page.progress end
  _G.GetRewardText = function() return DUI.page.completion end
  _G.GetGreetingText = function() return DUI.page.greeting end
end

-- Runs the frames C_Timer.After queued (the next frame), until none is left.
function DUI.flush()
  local guard = 0
  while #DUI.timers > 0 do
    local list = DUI.timers
    DUI.timers = {}
    for _, fn in ipairs(list) do fn() end
    guard = guard + 1
    assert(guard < 20, "timers keep queueing")
  end
end

-- The visible paragraph texts of DUIQuestFrame, in order.
function DUI.paragraphs()
  local out = {}
  for _, fs in ipairs(_G.DUIQuestFrame.fontStringPool.active) do out[#out + 1] = fs.text end
  return out
end

function DUI.labels()
  local out = {}
  for _, b in ipairs(_G.DUIQuestFrame.buttons) do
    if b.inUse then out[#out + 1] = b.Name:GetText() end
  end
  return out
end

-- ── The book window ────────────────────────────────────────────────────────

-- DUI.book = { pages = { raw page text, ... }, item = "Book name" }: ITEM_TEXT_READY turns through every page.
DUI.book = { pages = {} }

local TAG_FONTS = { p = "DUIFont_Book_Paragraph", h1 = "DUIFont_Book_H1" }

-- The content entries of one raw page: plain text → one "p" entry per paragraph; HTML → one entry per <P>/<H1>.
-- A page that stores nothing leaves its start mark for the next page's first entry, as Dialogue UI's cache does.
-- → whether the start mark is still pending
local function format(raw, store, pending)
  local first = true
  local function put(tag, text)
    store[#store + 1] = { text = text, fontTag = tag, isPageStart = (first or pending) or nil }
    first, pending = false, false
  end
  if raw:find("<HTML>", 1, true) then
    for tag, body in raw:gmatch("<(%a+%d?)>([^<]*)</%a+%d?>") do
      tag = tag:lower()
      if tag == "p" or tag == "h1" then put(tag, body) end
    end
  else
    for _, piece in ipairs(split(raw)) do put("p", piece) end
  end
  return first
end

function DUI.installBookFrame(opts)
  opts = opts or {}
  fontObject("DUIFont_Book_Paragraph", "Interface\\AddOns\\DialogueUI\\Fonts\\frizqt__.ttf", 14)
  fontObject("DUIFont_Book_H1", "Interface\\AddOns\\DialogueUI\\Fonts\\frizqt__.ttf", 20)
  local f = CreateFrame("Frame", "DUIBookFrame")
  f.measures, f.shows = 0, 0
  f.fontStringPool = pool(f) -- the texts its scroll frame lays blocks out in (BookUI.lua Formatter)
  function f:Hide()
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
    hideChildren(self)
  end
  function f:Init()
    if self.ScrollFrame then return end
    local sf = { objects = {} }
    self.ScrollFrame = sf
    sf.SetContent = function(x, content) x.content = content end
    -- a block with no object yet takes one from the book's pool
    sf.SetObjectData = function(x, obj, data, contentIndex)
      obj = obj or f.fontStringPool.acquire()
      obj.parent = f
      obj.GetParent = function(o) return o.parent end
      obj.CalculateScreenAreaFromCharacterSpan = AREA
      obj:SetFontObject(_G[TAG_FONTS[data.fontTag] or TAG_FONTS.p])
      obj:SetText(data.text)
      obj.contentIndex = contentIndex
      x.objects[contentIndex] = obj
      return obj
    end
  end
  -- every page cached (the client turned through them), then measured, then shown
  function f:cache()
    self:Init()
    local content = {}
    local pending = false
    for _, raw in ipairs(DUI.book.pages) do pending = format(raw, content, pending) end
    self.cached = content
    self:measure()
  end
  function f:measure()
    self.measures = self.measures + 1
    for _, e in ipairs(self.cached) do
      e.measuredFont = { _G[TAG_FONTS[e.fontTag]]:GetFont() }
      e.measuredText = e.text
    end
    self:ShowUI()
  end
  function f:ShowUI()
    self.shows = self.shows + 1
    self.ScrollFrame:SetContent(self.cached)
    self:Show()
  end
  -- the scroll frame lays out the entries in view (here: all of them)
  function f:layout()
    for i, e in ipairs(self.ScrollFrame.content) do
      if e.text then self.ScrollFrame:SetObjectData(self.ScrollFrame.objects[i], e, i) end
    end
  end
  function f:OnSettingsChanged()
    if not self:IsShown() or self.settingsDirty then return end
    self.settingsDirty = true
    C_Timer.After(0, function()
      self.settingsDirty = nil
      self:measure()
    end)
  end
  function f:HideUI() self:Hide() end
  for _, name in ipairs(opts.without or {}) do f[name] = nil end
  return f
end

-- The client's book API over DUI.book, and the reading of every page with ITEM_TEXT_READY as the client turns.
function DUI.installItemTextAPI()
  DUI.book = { pages = {}, item = "Old Journal", page = 1 }
  _G.ItemTextGetPage = function() return DUI.book.page end
  _G.ItemTextGetText = function() return DUI.book.pages[DUI.book.page] end
  _G.ItemTextGetItem = function() return DUI.book.item end
  _G.ItemTextGetCreator = function() return DUI.book.creator end
end

function DUI.openBook(pages)
  DUI.book.pages = pages
  Stub.fireAll("ITEM_TEXT_BEGIN")
  for i = 1, #pages do
    DUI.book.page = i
    Stub.fireAll("ITEM_TEXT_READY")
  end
  DUI.book.page = 1
  _G.DUIBookFrame:cache()
end

return DUI
