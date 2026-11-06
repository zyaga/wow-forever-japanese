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

Compat.declare(SURFACE, "getPage", { "ItemTextGetPage" })
Compat.declare(SURFACE, "getText", { "ItemTextGetText" })
Compat.declare(SURFACE, "getCreator", { "ItemTextGetCreator" })

local deps = {} -- { key(text) → book key } from Main
local frame -- DUIBookFrame, once installed
local installed = false
local raw = {} -- page number → the page's English as the client gave it while Dialogue UI turned through the book
local creator -- the name of the player who wrote the book (a letter): left as it is
-- the book showing: { content, pages = { { entries, en, html, key, holder, enBlocks } }, original = { [i] = text },
-- placed = { [entry index] = { text, at, page } }, bundled }
local book
local saved = {} -- font object name → { path, size, flags } it had before the bundled face
local cards = {} -- word-card records on the visible blocks
local changed = false -- a write changed a block or the faces

function Book.installed() return installed end

local function active() return installed and WFJ.DialogueUI.healthy() end
local function guarded(...) return WFJ.DialogueUI.guarded(...) end

local function call(key, ...)
  local fn = Compat.get(SURFACE, key)
  if type(fn) ~= "function" then return nil end
  return fn(...)
end

-- Text pieces as Dialogue UI splits a plain page: on control characters, a lone space dropped.
local function split(text)
  local out = {}
  for piece in text:gmatch("[^%c]+") do
    if piece ~= " " then out[#out + 1] = piece end
  end
  return out
end

local function squash(s) return (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end

-- An HTML page's text blocks in order (what lies between its tags, a line break kept inside its block) → blocks,
-- the same blocks squashed for comparing
local function blocks(html)
  local out, cmp = {}, {}
  local text = html:gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("<[^>]*>", "\1")
  for piece in (text .. "\1"):gmatch("(.-)\1") do
    local s = squash(piece)
    if s ~= "" then
      out[#out + 1] = piece:gsub("^%s+", ""):gsub("%s+$", "")
      cmp[#cmp + 1] = s
    end
  end
  return out, cmp
end

-- An inline marker line Render put before a page's text (MARKER_INLINE_COLOR … "|r\n") → marker, the rest | nil, text
local function splitMarker(text)
  local mark = WFJ.MARKER_INLINE_COLOR
  if text:sub(1, #mark) ~= mark then return nil, text end
  local stop = text:find("|r\n", #mark + 1, true)
  if not stop then return nil, text end
  return text:sub(1, stop + 1), text:sub(stop + 3)
end

-- ── Writing the pages ──────────────────────────────────────────────────────

local function setText(e, t)
  if e.text ~= t then
    e.text = t
    changed = true
  end
end

-- The page's Japanese paragraphs into its blocks, in order: blocks left over are emptied, paragraphs left over are
-- joined into the last block. Each block found as it is in the page's Japanese is noted for word cards.
local function placePlain(n, pg, ja, content)
  local paras = split(ja)
  if #paras == 0 then return false end
  local count, from = #pg.entries, 1
  for i, idx in ipairs(pg.entries) do
    local t = i < count and (paras[i] or "") or (paras[i] and table.concat(paras, "\n\n", i) or "")
    setText(content[idx], t)
    -- a joined last block may not be in the page as it is: it gets no cards
    local at = t ~= "" and ja:find(t, from, true) or nil
    if at then
      book.placed[idx] = { text = t, at = at, page = n }
      from = at + #t
    end
  end
  return true
end

-- An HTML page: each block Dialogue UI made is one of the English page's blocks, in order; it gets the Japanese
-- page's block at the same place. → false when the blocks do not line up
local function placeHtml(pg, ja, content)
  if pg.jaFor ~= ja then pg.jaFor, pg.jaBlocks = ja, blocks(ja) end
  local en, jb = pg.enBlocks, pg.jaBlocks
  if #en ~= #jb then return false end
  local plan, k = {}, 1
  for _, idx in ipairs(pg.entries) do
    local t = squash(content[idx].text)
    while k <= #en and en[k] ~= t do k = k + 1 end
    if k > #en then return false end
    plan[idx] = jb[k]
    k = k + 1
  end
  for idx, t in pairs(plan) do setText(content[idx], t) end
  return true
end

-- One page's text as its record holds it now. → whether the page shows text in the bundled face
local function place(n, pg, content)
  local text = pg.holder and pg.holder.text
  if type(text) ~= "string" or text == pg.en then return false end
  local marker, body = splitMarker(text)
  if body ~= pg.en then
    local placed
    if pg.html then placed = placeHtml(pg, body, content) else placed = placePlain(n, pg, body, content) end
    if not placed then
      if WFJ.Diag then pcall(WFJ.Diag.log, "dialogueui", "a book page's Japanese does not fit Dialogue UI's blocks") end
      return false
    end
    pg.ja = body
  end
  if marker then
    local first = content[pg.entries[1]]
    setText(first, marker .. "\n" .. first.text)
  end
  return true
end

-- Dialogue UI measures a block's height through these font objects before any FontString shows it, so the bundled
-- face has to be on the objects themselves while Japanese shows (on Dialogue UI's own objects only, given back when
-- the book closes or shows English); a face set per FontString afterwards would leave the heights measured without it.
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

-- Writes every page as its record says (Japanese, or English with a marker), and has Dialogue UI measure the
-- table again when anything changed.
local function write()
  local content = book.content
  changed = false
  book.placed = {}
  for i, t in pairs(book.original) do setText(content[i], t) end
  local any = false
  for n, pg in ipairs(book.pages) do
    pg.ja = nil
    if place(n, pg, content) then any = true end
  end
  if any ~= book.bundled then changed = true end
  book.bundled = any
  if not changed then return end
  cards = WFJ.DialogueUI.detachCards(cards)
  fonts(any)
  frame:OnSettingsChanged()
end

local function forget()
  cards = WFJ.DialogueUI.detachCards(cards)
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
  book = { content = content, pages = pages, original = original, placed = {}, bundled = false }
  for n, p in ipairs(pages) do
    local en = raw[n]
    if type(en) == "string" and en ~= "" and p.entries[1] and type(deps.key) == "function" then
      p.en, p.html = en, WFJ.ItemText.isHtml(en)
      if p.html then
        local _, cmp = blocks(en)
        p.enBlocks = cmp
      end
      p.key = deps.key(en)
      if p.key then
        p.holder = WFJ.DialogueUI.newHolder(en)
        WFJ.Render.show(SURFACE, "page" .. n, p.holder, en, "books", "book", p.key)
      end
    end
  end
  write()
end

-- A block Dialogue UI laid out in a FontString: a word card for a plain page's Japanese, with its share of the
-- page's words (an HTML page keeps the client's layout and takes none).
local function card(obj, data, index)
  local placed = book and book.placed[index]
  if not (placed and type(obj) == "table" and type(data) == "table" and data.text == placed.text) then return end
  local pg = book.pages[placed.page]
  if pg.listed == nil then
    local R = WFJ.Readings
    pg.listed = R and type(R.lookup) == "function" and R.lookup("book", pg.key, pg.ja) or false
  end
  WFJ.DialogueUI.attachCard(cards, SURFACE, "page" .. placed.page .. "." .. index, obj, placed.text, "book", pg.key,
    pg.listed or nil, placed.at, 0)
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
    local n = call("getPage")
    if type(n) == "number" then raw[n] = call("getText") end
    creator = call("getCreator")
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
  local hook = Compat.resolve("hooksecurefunc")
  hook(f, "ShowUI", function(self) if active() then guarded(afterShow, self) end end)
  hook(f, "Init", function(self) guarded(hookScroll, self) end)
  local createFrame = Compat.resolve("CreateFrame")
  if type(createFrame) == "function" then
    local ev = createFrame("Frame")
    ev:RegisterEvent("ITEM_TEXT_BEGIN")
    ev:RegisterEvent("ITEM_TEXT_READY")
    ev:SetScript("OnEvent", onEvent)
  end
  WFJ.DialogueUI.onClose(f, forget)
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
