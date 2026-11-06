-- A stand-in for the Dialogue UI addon's two windows, written for these specs from how that addon behaves (read at
-- its 1.0.7 b source; none of its code is here). What the adapter relies on:
--   * DUIQuestFrame's page handlers run self:ReleaseAllObjects() first, then lay the page out top to bottom.
--   * FormatParagraph splits its text on control characters and, per piece, acquires a pooled FontString
--     (self:AcquireLeftFontString, which calls SetFontObject on it), sets the text and measures it at once.
--   * Quest bodies go through self:FormatQuestText(offsetY, method), which reads the text itself; the offer's
--     objectives through FormatParagraph; the progress page's objective lines ("- line" rows) through InsertText.
--   * UpdateQuestTitle writes FrontFrame.Header.Title; option buttons write their label in SetButtonText, gossip
--     options through SetGossip(data, hotkey) and quest rows through SetQuestName(questInfo), which also runs again
--     when the quest's data loads late.
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
    for _, f in ipairs(p.active) do f.inUse = false; f.text = "" end
    p.active = {}
  end
  return p
end

local function button(frame)
  local b = CreateFrame("Button", nil, frame)
  b.Name = Stub.fontString("")
  b.Name:SetFontObject(_G.DUIFont_Quest_Gossip)
  function b:SetButtonText(name)
    self.Name:SetText(name)
    self.measuredFont = { self.Name:GetFont() }
  end
  function b:SetGossip(data, hotkey)
    local name = data.name
    if hotkey then name = hotkey .. ". " .. name end
    self:SetButtonText(name)
  end
  function b:SetQuestName(questInfo)
    if questInfo.level then
      self:SetButtonText(("[%d] %s"):format(questInfo.level, questInfo.title))
    else
      self:SetButtonText(questInfo.title)
    end
  end
  function b:SetQuest(questInfo, hotkey)
    self.questInfo, self.hotkey = questInfo, hotkey
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
  local f = CreateFrame("Frame", "DUIQuestFrame")
  f.fontStringPool = pool(f)
  f.buttons = {}
  f.redraws = 0
  f.FrontFrame = { Header = { Title = Stub.fontString("") } }
  f.FrontFrame.Header.Title:SetFontObject(_G.DUIFont_Quest_Title_18)

  function f:Hide()
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
    hideChildren(self)
  end

  function f:AcquireLeftFontString(obj)
    local fs = self.fontStringPool.acquire()
    fs:SetFontObject(obj or _G.DUIFont_Quest_Paragraph)
    return fs
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
local function format(raw, store)
  local first = true
  local function put(tag, text)
    store[#store + 1] = { text = text, fontTag = tag, isPageStart = first or nil }
    first = false
  end
  if raw:find("<HTML>", 1, true) then
    for tag, body in raw:gmatch("<(%a+%d?)>([^<]*)</%a+%d?>") do
      tag = tag:lower()
      if tag == "p" or tag == "h1" then put(tag, body) end
    end
  else
    for _, piece in ipairs(split(raw)) do put("p", piece) end
  end
end

function DUI.installBookFrame(opts)
  opts = opts or {}
  fontObject("DUIFont_Book_Paragraph", "Interface\\AddOns\\DialogueUI\\Fonts\\frizqt__.ttf", 14)
  fontObject("DUIFont_Book_H1", "Interface\\AddOns\\DialogueUI\\Fonts\\frizqt__.ttf", 20)
  local f = CreateFrame("Frame", "DUIBookFrame")
  f.measures, f.shows = 0, 0
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
    sf.SetObjectData = function(x, obj, data, contentIndex)
      obj = obj or Stub.fontString("")
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
    for _, raw in ipairs(DUI.book.pages) do format(raw, content) end
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
