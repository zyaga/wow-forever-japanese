-- UI/DialogueUIBook.lua: the Dialogue UI addon's book window, when the player has that addon (ADR-073). Dialogue UI
-- turns the client's book window off, reads every page of a book, splits each into blocks (paragraphs, or an HTML
-- page's headings and paragraphs), measures them and shows the whole book in one scroll. The blocks live in one
-- content table its window keeps; this module writes each page's Japanese into that page's blocks after Dialogue UI
-- showed them, then has Dialogue UI measure and show the same table again. Nothing of Dialogue UI is shipped or
-- required; a page whose Japanese cannot be placed stays English.
local _, WFJ = ...
local Book = {}
WFJ.DialogueUIBook = Book

local Compat = WFJ.Compat
local SURFACE = "dialogueui.book"
Book.SURFACE = SURFACE

-- [read: Dialogue UI 1.0.7 b, Code/Book/BookUI.lua: Init builds the scroll frame on the first book, ShowUI hands it
-- the content table (entries { text, fontTag, isPageStart }), OnSettingsChanged measures that table again a frame
-- later and calls ShowUI again]
Book.MEMBERS = { "ShowUI", "OnSettingsChanged", "Init" }
-- the book's font objects, by block tag; the title (the book's name) keeps Dialogue UI's face
local FONTS = { "DUIFont_Book_Paragraph", "DUIFont_Book_H1", "DUIFont_Book_H2", "DUIFont_Book_H3", "DUIFont_Book_10" }

local deps = {} -- { key(text) → book key } from Main
local frame -- DUIBookFrame, once installed
local installed = false
local raw = {} -- page number → the page's English as the client gave it while Dialogue UI turned through the book
local creator -- the name of the player who wrote the book (a letter): left as it is
local book -- the book showing: { content, pages = { { entries, en, html, key, holder } }, original = { [i] = text } }
local saved = {} -- font object name → { path, size, flags } it had before the bundled face
local cards = {} -- word-card records on the visible blocks

function Book.installed() return installed end

local function active() return installed and WFJ.DialogueUI.healthy() end
local function guarded(...) return WFJ.DialogueUI.guarded(...) end

-- Text pieces as Dialogue UI splits a plain page: on control characters, a lone space dropped.
local function split(text)
  local out = {}
  for piece in text:gmatch("[^%c]+") do
    if piece ~= " " then out[#out + 1] = piece end
  end
  return out
end

local function squash(s) return (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end

-- An HTML page's text blocks in order: what lies between its tags, a line break kept inside its block.
local function blocks(html)
  local out = {}
  local text = html:gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("<[^>]*>", "\1")
  for piece in (text .. "\1"):gmatch("(.-)\1") do
    local s = squash(piece)
    if s ~= "" then out[#out + 1] = piece:gsub("^%s+", ""):gsub("%s+$", "") end
  end
  return out
end

-- An inline marker line Render put before a page's text → marker, the rest | nil, text
local function splitMarker(text)
  local marker, rest = text:match("^(|c%x%x%x%x%x%x%x%x.-|r)\n(.*)$")
  if marker then
    for _, m in pairs(WFJ.MARKER) do
      if marker:find(m, 1, true) then return marker, rest end
    end
  end
  return nil, text
end

-- ── Writing the pages ──────────────────────────────────────────────────────

-- The page's Japanese paragraphs into its blocks, in order: blocks left over are emptied, paragraphs left over are
-- joined into the last block. → { [entry index] = { text, at } } (where each block's text starts in `ja`)
local function placePlain(pg, ja, content)
  local paras = split(ja)
  if #paras == 0 then return nil end
  local placed, n, from = {}, #pg.entries, 1
  for i, idx in ipairs(pg.entries) do
    local t = i < n and (paras[i] or "") or (paras[i] and table.concat(paras, "\n\n", i) or "")
    content[idx].text = t
    -- a block that is one paragraph is found in the page as it is; a joined last block may not be (no cards there)
    local at = t ~= "" and ja:find(t, from, true) or nil
    placed[idx] = { text = t, at = at }
    if at then from = at + #t end
  end
  return placed
end

-- An HTML page: each block Dialogue UI made is one of the English page's blocks, in order; it gets the Japanese
-- page's block at the same place. → placed | nil when the blocks do not line up
local function placeHtml(pg, ja, content)
  local en, jb = blocks(pg.en), blocks(ja)
  if #en ~= #jb then return nil end
  local plan, k = {}, 1
  for _, idx in ipairs(pg.entries) do
    local t = squash(content[idx].text)
    while k <= #en and squash(en[k]) ~= t do k = k + 1 end
    if k > #en then return nil end
    plan[idx] = jb[k]
    k = k + 1
  end
  for idx, t in pairs(plan) do content[idx].text = t end
  return {}
end

-- One page's text as its record holds it now. → whether the page shows text in the bundled face
local function place(pg, content)
  local text = pg.holder and pg.holder.text
  if type(text) ~= "string" or text == pg.en then return false end
  local marker, body = splitMarker(text)
  local placed = body ~= pg.en and (pg.html and placeHtml or placePlain)(pg, body, content) or nil
  if body ~= pg.en and not placed then
    if WFJ.Diag then pcall(WFJ.Diag.log, "dialogueui", "a book page's Japanese does not fit Dialogue UI's blocks") end
    return false
  end
  pg.placed, pg.ja = placed, placed and body or nil
  if marker then
    local first = content[pg.entries[1]]
    first.text = marker .. "\n" .. first.text
  end
  return true
end

local function fonts(bundled)
  for _, name in ipairs(FONTS) do
    local obj = Compat.resolve(name)
    if type(obj) == "table" and type(obj.GetFont) == "function" and type(obj.SetFont) == "function" then
      if bundled then
        local path, size, flags = obj:GetFont()
        if path ~= WFJ.Font.PATH then saved[name] = { path, size, flags or "" } end
        local s = saved[name]
        if s then obj:SetFont(WFJ.Font.PATH, s[2], s[3]) end
      elseif saved[name] then
        obj:SetFont(saved[name][1], saved[name][2], saved[name][3])
        saved[name] = nil
      end
    end
  end
end

local function detachCards()
  local V = WFJ.ReadingView
  for _, card in ipairs(cards) do
    if V and type(V.detach) == "function" then pcall(V.detach, card) end
  end
  cards = {}
end

-- Writes every page as its record says (Japanese, or English with a marker), and has Dialogue UI measure the
-- table again when anything changed.
local function write()
  local content = book.content
  local before = {}
  for i, e in ipairs(content) do before[i] = e.text end
  for i, t in pairs(book.original) do content[i].text = t end
  local any = false
  for _, pg in ipairs(book.pages) do
    pg.placed, pg.ja = nil, nil
    if place(pg, content) then any = true end
  end
  local changed = any ~= book.bundled
  for i, e in ipairs(content) do
    if e.text ~= before[i] then changed = true end
  end
  book.bundled = any
  if not changed then return end
  detachCards()
  fonts(any)
  frame:OnSettingsChanged()
end

local function forget()
  detachCards()
  if book then
    for i, t in pairs(book.original) do book.content[i].text = t end -- Dialogue UI may show its cached book again
  end
  book = nil
  fonts(false)
  WFJ.Render.release(SURFACE)
end

-- A book Dialogue UI just showed for the first time: its pages, their records, then the Japanese.
local function opened(content)
  forget()
  if creator then return end -- a letter a player wrote
  local pages, pg = {}, nil
  local original = {}
  for i, e in ipairs(content) do
    if type(e) == "table" then
      if e.isPageStart then
        pg = { entries = {} }
        pages[#pages + 1] = pg
      end
      if pg and type(e.text) == "string" then
        pg.entries[#pg.entries + 1] = i
        original[i] = e.text
      end
    end
  end
  book = { content = content, pages = pages, original = original, bundled = false }
  for n, p in ipairs(pages) do
    local en = raw[n]
    if type(en) == "string" and en ~= "" and p.entries[1] and type(deps.key) == "function" then
      p.en, p.html = en, en:find("<HTML>", 1, true) ~= nil
      p.key = deps.key(en)
      if p.key then
        p.holder = { text = en, font = { flags = "" } }
        function p.holder:GetText() return self.text end
        function p.holder:SetText(t) self.text = t end
        function p.holder:GetFont() return self.font.path, self.font.size, self.font.flags end
        function p.holder:SetFont(path, size, flags)
          self.font = { path = path, size = size, flags = flags or "" }
          return true
        end
        WFJ.Render.show(SURFACE, "page" .. n, p.holder, en, "books", "book", p.key)
      end
    end
  end
  write()
end

-- A block Dialogue UI laid out in a FontString: a word card for a plain page's Japanese, with its share of the
-- page's words (an HTML page keeps the client's layout and takes none).
local function card(obj, data, index)
  local V, R = WFJ.ReadingView, WFJ.Readings
  if not (book and V and type(V.attach) == "function" and type(obj) == "table" and type(data) == "table") then
    return
  end
  for n, pg in ipairs(book.pages) do
    local placed = pg.placed and pg.placed[index]
    if placed and placed.at and not pg.html and data.text == placed.text and placed.text ~= "" then
      local listed = R and type(R.lookup) == "function" and R.lookup("book", pg.key, pg.ja) or nil
      local at, len = placed.at, #placed.text
      local spans = {}
      for _, sp in ipairs(listed or {}) do
        if sp.first >= at and sp.last <= at + len - 1 then
          spans[#spans + 1] = { first = sp.first - at + 1, last = sp.last - at + 1, word = sp.word,
            reading = sp.reading, gloss = sp.gloss, card = sp.card }
        end
      end
      local rec = { surface = SURFACE, key = "page" .. n .. "." .. index, fs = obj, applied = data.text,
        meta = { kind = "book", id = pg.key }, spans = spans }
      cards[#cards + 1] = rec
      pcall(V.attach, rec)
      return
    end
  end
end

local hooked = setmetatable({}, { __mode = "k" }) -- scroll frames whose block writer is wrapped
local function hookScroll(f)
  local sf = f.ScrollFrame
  if type(sf) ~= "table" or type(sf.SetObjectData) ~= "function" or hooked[sf] then return end
  hooked[sf] = true
  local orig = sf.SetObjectData
  sf.SetObjectData = function(self, obj, data, index, ...)
    local o = orig(self, obj, data, index, ...)
    if active() then guarded(card, o, data, index) end
    return o
  end
end

local function afterShow(self)
  local sf = self.ScrollFrame
  local content = type(sf) == "table" and sf.content or nil
  if type(content) ~= "table" then return end
  hookScroll(self)
  if book and book.content == content then return end -- measured again after our write, or shown again
  opened(content)
end

local function onEvent(_, event)
  if event == "ITEM_TEXT_BEGIN" then
    raw, creator = {}, nil
  elseif event == "ITEM_TEXT_READY" then
    local page, text = Compat.resolve("ItemTextGetPage"), Compat.resolve("ItemTextGetText")
    local who = Compat.resolve("ItemTextGetCreator")
    local n = type(page) == "function" and page() or nil
    if type(n) == "number" and type(text) == "function" then raw[n] = text() end
    if type(who) == "function" then creator = who() end
  end
end

-- Installs on DUIBookFrame when every member is there. → true when installed now
function Book.install()
  if installed then return false end
  local f = Compat.resolve("DUIBookFrame")
  if type(f) ~= "table" then return false end
  for _, m in ipairs(Book.MEMBERS) do
    if type(f[m]) ~= "function" then
      if WFJ.Diag then pcall(WFJ.Diag.log, "dialogueui", "Dialogue UI's book has no " .. m .. ": left in English") end
      return false
    end
  end
  frame = f
  local showUI, init = f.ShowUI, f.Init
  f.ShowUI = function(self, ...)
    local res = WFJ.DialogueUI.pack(showUI(self, ...))
    if active() then guarded(afterShow, self) end
    return unpack(res, 1, res.n)
  end
  f.Init = function(self, ...)
    local res = WFJ.DialogueUI.pack(init(self, ...))
    guarded(hookScroll, self)
    return unpack(res, 1, res.n)
  end
  local createFrame = Compat.resolve("CreateFrame")
  if type(createFrame) == "function" then
    local ev = createFrame("Frame")
    ev:RegisterEvent("ITEM_TEXT_BEGIN")
    ev:RegisterEvent("ITEM_TEXT_READY")
    ev:SetScript("OnEvent", onEvent)
    local watcher = createFrame("Frame", nil, f) -- hears the window close (see UI/DialogueUI)
    watcher:SetScript("OnHide", function() guarded(forget) end)
    watcher:Show()
  end
  for _, event in ipairs({ "modifier", "enabled", "area", "markers" }) do
    WFJ.State.on(event, function()
      if book and active() then guarded(write) end
    end)
  end
  if WFJ.VoicePlayer and type(WFJ.VoicePlayer.addWindow) == "function" then
    WFJ.VoicePlayer.addWindow("DUIBookFrame", { SURFACE }, nil)
  end
  installed = true
  return true
end

-- Main: `d` = { key(text) → book key }. Installs now when Dialogue UI is loaded, else when it loads.
function Book.init(d)
  deps = d or {}
  WFJ.LoadOnDemand.when("DialogueUI", function() Book.install() end)
  return installed
end
