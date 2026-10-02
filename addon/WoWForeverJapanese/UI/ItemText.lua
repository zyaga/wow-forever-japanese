-- UI/ItemText.lua: the book / letter / plaque window (surface "itemtext", area "books", ADR-022): the page
-- text, translated by the key of its API English (a book page's Japanese is shipped under the hash of the English it
-- was checked against; the client exposes no page id). The title (the item / object name), the page number and the
-- Prev / Next buttons are not this surface's.
-- Forever writes the page inside ItemTextFrameMixin:OnEvent [verified: forever 1.60.1.69913
-- blizzard_uipanels_game/mainline/itemtextframe.lua:18–31, 33–175; itemtextframe.xml:57–81, 163–173]:
--   * ITEM_TEXT_BEGIN sets each HTML text type's font object from ITEM_TEXT_FONTS[material] (default: P, H1, H2, H3 →
--     QuestFont; "ParchmentLarge": P QuestFont, H1 Fancy48Font, H2 Game20Font, H3 Fancy32Font) and its colour from
--     GetMaterialTextColors (lua:46–71).
--   * ITEM_TEXT_READY re-anchors and re-sizes ItemTextPageText for the material (lua:93–117), then writes
--     ItemTextPageText:SetText(ItemTextGetText()) (no leading newline) or, when ItemTextGetCreator() returns one,
--     ItemTextGetText() .. "\n\n" .. ITEM_TEXT_FROM .. "\n" .. creator .. "\n" (lua:119–125); then sizes the scroll
--     child: SetHeight(1), UpdateScrollChildRect(), and SetHeight(frame height + range + 30) when floor(range) > 0
--     (lua:127–132). Every page turn fires ITEM_TEXT_READY again. ITEM_TEXT_CLOSED hides the frame (lua:171–173).
--   * The frame's OnEvent is bound in XML by method="OnEvent" (xml:165), so the hook is HookScript("OnEvent") on the
--     frame (ADR-009's frame-script exception), which runs after the client's handler. OnHide is XML-bound (xml:170).
--   * ItemTextPageText is a SimpleHTML (xml:71–77): SetText, per-text-type GetFont / SetFont / GetFontObject /
--     SetFontObject / GetTextColor / SetTextColor, and no GetText [verified: Blizzard_APIDocumentationGenerated/
--     SimpleHTMLAPIDocumentation.lua]. A small adapter (below) gives SurfaceState the FontString interface it uses.
-- A page is shown only when the SimpleHTML last received exactly the text the client builds from the getters (the
-- ADR-009 equality guard). A page with a creator is a letter a player wrote: never ours, never marked.
-- Markers are inline above the prose (no banner): inside the <BODY> of an HTML page, so the markup still parses
-- [unverified: that a |c colour code renders inside a SimpleHTML <P>; an in-game check].
-- ADR-044: the word card needs FontString:CalculateScreenAreaFromCharacterSpan, which a SimpleHTML lacks
-- [verified: forever 1.60.1.70009 SimpleHTMLAPIDocumentation.lua: GetTextData gives { text, type, align }, no
-- positions]. So a plain-text page (no <HTML>) showing Japanese is drawn in a FontString of ours, laid where the
-- SimpleHTML's text starts, as wide as it, in the P text type's font and colour; the SimpleHTML is given "" while it
-- shows, and the scroll child is sized from the FontString. The client's own text (English: Alt, off, missing,
-- release) and every HTML page go back through the SimpleHTML exactly as before. UI/Readings covers that FontString
-- (page:spanRegion).
local _, WFJ = ...
local ItemText = {}
WFJ.ItemText = ItemText

local SURFACE, AREA, KIND, KEY = "itemtext", "books", "book", "page"
ItemText.SURFACE = SURFACE
-- the HTML text types the client styles [verified: forever mainline/itemtextframe.lua:18–31, 51–53, 60–71]
local TAGS = { "P", "H1", "H2", "H3" }

local Compat = WFJ.Compat
local SS = WFJ.SurfaceState

-- The page number is a number; the title (the item / object name, SetTitle) is never touched here: names stay in
-- English.
ItemText.NEVER_TOUCH = { "ItemTextCurrentPage" }

local deps = {}

-- ── The SimpleHTML adapter ─────────────────────────────────────────────────
-- received: the text the SimpleHTML was last given (a SetText post-hook sees every write, ours and the client's).
-- logical:  what GetText reports: the client's text as written, or the text SurfaceState asked us to show.
-- client:   the page text the client wrote for the page on record.
-- tags:     each text type's font object, font and colour as the client set them at ITEM_TEXT_BEGIN.
-- fs:       our FontString for a plain-text Japanese page (made on first use); drawn: it shows the page.
local page = { html = nil, received = nil, logical = nil, client = nil, tags = nil, writing = false, fs = nil,
  drawn = false }
ItemText.page = page

function page:GetText()
  return self.logical
end

-- An inline marker goes inside the body of an HTML page, as its own paragraph (text before <HTML> is not markup).
local function inHtml(text)
  local at = text:find("<[Hh][Tt][Mm][Ll]")
  if not at or at == 1 then return text end
  local prefix = text:sub(1, at - 1):gsub("%s+$", "")
  local rest = text:sub(at)
  if prefix == "" then return rest end
  local _, bodyEnd = rest:find("<[Bb][Oo][Dd][Yy][^>]*>")
  if not bodyEnd then return rest end
  return rest:sub(1, bodyEnd) .. "\n<P>" .. prefix .. "</P>" .. rest:sub(bodyEnd + 1)
end

local function htmlPage(text)
  return text:find("<[Hh][Tt][Mm][Ll]") ~= nil
end

-- Our FontString, on the scroll child beside the SimpleHTML (created once; nil when the client gives no
-- CreateFontString).
function page:fontString()
  if self.fs then return self.fs end
  local parent = type(self.html.GetParent) == "function" and self.html:GetParent() or nil
  if not (parent and type(parent.CreateFontString) == "function") then return nil end
  -- QuestFont: the P text type's default [verified: forever mainline/itemtextframe.xml:76], so the FontString never
  -- starts without a font; layout() then takes this item's P font and colour
  local fs = parent:CreateFontString(nil, "ARTWORK", "QuestFont")
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  -- Japanese has no spaces to break on [verified: SimpleFontStringAPIDocumentation.lua, SetNonSpaceWrap]
  if type(fs.SetNonSpaceWrap) == "function" then fs:SetNonSpaceWrap(true) end
  fs:Hide()
  self.fs = fs
  return fs
end

-- Lays the FontString where the SimpleHTML's text starts, as wide as it (the client re-anchors and re-sizes the
-- SimpleHTML for the material on every ITEM_TEXT_READY [verified: forever mainline/itemtextframe.lua:93–117]), in the
-- P text type's current font and colour.
local function layout(fs, html)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", html, "TOPLEFT", 0, 0)
  fs:SetWidth(html:GetWidth())
  local path, size, flags = html:GetFont("P")
  if path then fs:SetFont(path, size, flags) end
  local r, g, b, a = html:GetTextColor("P")
  if r then fs:SetTextColor(r, g, b, a) end
end

local function writeHtml(self, out)
  self.writing = true
  local ok, err = pcall(self.html.SetText, self.html, out)
  self.writing = false
  if not ok then error(err, 0) end
end

-- The client's own English: exactly what it wrote, or that text under an inline marker (the missing marker:
-- Render writes MARKER_INLINE_COLOR … "|r\n" before it). Japanese that merely ends with the English is not.
local function clientEnglish(self, text)
  local c = self.client
  if c == nil then return false end
  if text == c then return true end
  local mark = WFJ.MARKER_INLINE_COLOR
  return #text > #c + #mark and text:sub(1, #mark) == mark and text:sub(-(#c + 1)) == "\n" .. c
end

-- The client's text is written back as is; any other text is written the way the client writes a page (as is; Forever
-- adds no leading newline), with an inline marker moved inside an HTML page's body. Japanese on a plain-text
-- page is drawn in our FontString, the SimpleHTML left empty; the client's English (with or without the missing
-- marker) stays in the SimpleHTML.
function page:SetText(text)
  local fs = not clientEnglish(self, text) and not htmlPage(text) and self:fontString() or nil
  if fs then
    writeHtml(self, "")
    layout(fs, self.html)
    fs:SetText(text)
    fs:Show()
    self.drawn = true
  else
    if self.fs then
      self.fs:SetText("")
      self.fs:Hide()
    end
    self.drawn = false
    writeHtml(self, text ~= self.client and inHtml(text) or text)
  end
  self.logical = text
end

-- The FontString UI/Readings covers: ours, whether or not it shows this page (UI/Readings checks it holds
-- the text the record applied, so a page drawn by the SimpleHTML takes no cover).
function page:spanRegion()
  return self.fs
end

function page:GetFont()
  return self.html:GetFont("P")
end

-- Reads each text type's font object, font and colour (the client's styling for this item).
function page:snapshot()
  local tags = {}
  for _, tag in ipairs(TAGS) do
    local path, size, flags = self.html:GetFont(tag)
    local obj = type(self.html.GetFontObject) == "function" and self.html:GetFontObject(tag) or nil
    -- a text type can report an unnamed font object the SimpleHTML made for itself; setting that back on the same
    -- frame is a font object loop (a Lua error in game), so only a named object (QuestFont, Fancy48Font) is kept
    if obj ~= nil and type(obj.GetName) == "function" then
      local named = obj:GetName()
      if type(named) ~= "string" or named == "" then obj = nil end
    end
    tags[tag] = { object = obj, font = { path, size, flags }, color = { self.html:GetTextColor(tag) } }
  end
  self.tags = tags
end

local function recolor(html, tags)
  for _, tag in ipairs(TAGS) do
    local c = tags[tag].color
    if c[1] ~= nil then html:SetTextColor(tag, c[1], c[2], c[3], c[4]) end
  end
end

local function restoreTags(html, tags)
  for _, tag in ipairs(TAGS) do
    local t = tags[tag]
    -- the captured font first, then the font object: right whether or not re-assigning the same object re-applies it
    if t.font[1] ~= nil then html:SetFont(tag, t.font[1], t.font[2], t.font[3]) end
    if t.object ~= nil and type(html.SetFontObject) == "function" then
      pcall(html.SetFontObject, html, tag, t.object)
    end
  end
  recolor(html, tags)
end

-- SetFont(the P font as captured) puts back every text type's font, font object and colour; any other face is
-- applied to all four text types, each at its own captured size scaled like P's (a "ParchmentLarge" book's H1 is
-- Fancy48Font, its P QuestFont), with the flags given; then the colours are put back. SimpleHTML's SetFont returns
-- nothing [verified: SimpleHTMLAPIDocumentation.lua:184–196], so a refusal is read back from GetFont; on any refusal
-- the text types that took the face are put back too, and → false (Render retries it like a FontString's refused
-- font).
local function tagSize(tags, tag, size)
  local base = tags and tags.P.font[2]
  local own = tags and tags[tag].font[2]
  if type(base) ~= "number" or base <= 0 or type(own) ~= "number" or type(size) ~= "number" then return size end
  return size * own / base
end

function page:SetFont(path, size, flags)
  local html, tags = self.html, self.tags
  local orig = tags and tags.P.font
  if orig and path == orig[1] and size == orig[2] and flags == orig[3] then
    restoreTags(html, tags)
    return true
  end
  local refused = false
  for _, tag in ipairs(TAGS) do
    html:SetFont(tag, path, tagSize(tags, tag, size), flags)
    if html:GetFont(tag) ~= path then refused = true end
  end
  if refused then
    if tags then restoreTags(html, tags) end
    return false
  end
  if tags then recolor(html, tags) end
  if self.fs then
    layout(self.fs, html) -- our FontString follows the P text type
    -- a font that took late (Render.retryFonts) changes the page's height: size the scroll child again
    if self.drawn and ItemText.refit then ItemText.refit() end
  end
  return true
end

-- A write of the client's (a page turn, a new item) takes the page back from our FontString until Render draws
-- the Japanese again.
local function onPageSetText(_, text)
  page.received = text
  if page.writing then return end
  page.logical = text
  if page.drawn and page.fs then
    page.fs:SetText("")
    page.fs:Hide()
  end
  page.drawn = false
end

-- ── Surface ────────────────────────────────────────────────────────────────

-- The client's own scroll-child sizing, after the page text changed [verified: forever
-- mainline/itemtextframe.lua:127–132].
-- While our FontString draws the page, the SimpleHTML is empty, so the page's height is the FontString's: the
-- scroll child is made tall enough to hold it, with the client's 30 of padding.
local function refit()
  local sf = Compat.get(SURFACE, "scroll")
  local child = sf and type(sf.GetScrollChild) == "function" and sf:GetScrollChild() or nil
  if not child then return end
  child:SetHeight(1)
  sf:UpdateScrollChildRect()
  if page.drawn and page.fs then
    local _, _, _, _, y = page.html:GetPoint(1)
    local need = math.abs(tonumber(y) or 0) + page.fs:GetStringHeight()
    if need > sf:GetHeight() then
      child:SetHeight(need + 30)
      sf:UpdateScrollChildRect()
    end
    return
  end
  local range = sf:GetVerticalScrollRange()
  if math.floor(range) > 0 then child:SetHeight(sf:GetHeight() + range + 30) end
end
ItemText.refit = refit

local function call(name)
  local fn = Compat.get(SURFACE, name)
  if type(fn) ~= "function" then return nil end
  return fn()
end

-- ITEM_TEXT_BEGIN: a new item. The client has just reset every text type's font object and colour: read them, and
-- forget the previous item's record (its font is gone). → records dropped
function ItemText.onBegin()
  if not page.html then return 0 end
  page:snapshot() -- first: putting our font back must not undo this item's colours
  local n = WFJ.Render.forget(SURFACE)
  page.client = nil
  return n
end

-- A page that is no longer ours: its word covers go (SS.drop bypasses Render), then its record.
local function drop()
  local rec = SS.get(SURFACE, KEY)
  if rec and WFJ.ReadingView then WFJ.ReadingView.detach(rec) end
  SS.drop(SURFACE, KEY)
end

-- ITEM_TEXT_READY: the client has written a page. → 1 when the page is ours to show, else 0
function ItemText.onReady()
  if not page.html then return 0 end
  local en = call("getText")
  local creator = call("getCreator")
  if type(en) ~= "string" or en == "" or creator or page.received ~= en then
    drop()
    page.client = nil
    return 0
  end
  local key = deps.key and deps.key(en) or nil
  if not key then
    drop()
    page.client = nil
    return 0
  end
  if not page.tags then page:snapshot() end
  page.client = en
  page.logical = page.client
  WFJ.Render.show(SURFACE, KEY, page, page.client, AREA, KIND, key, { refit = refit })
  return 1
end

-- HookScript("OnEvent") target. → what the event's handler returned
function ItemText.onEvent(_, event)
  if event == "ITEM_TEXT_BEGIN" then return ItemText.onBegin() end
  if event == "ITEM_TEXT_READY" then return ItemText.onReady() end
  return 0
end

function ItemText.release()
  local n = WFJ.Render.release(SURFACE) -- first: the restore writes the client's text back as the client wrote it
  page.client = nil
  return n
end

-- For /wfj debug book → { open, keys = { … }, shipped = key | nil, record = rec | nil }
function ItemText.inspect()
  local frame = Compat.get(SURFACE, "frame")
  local en = call("getText")
  local out = { open = frame ~= nil and frame:IsShown() and type(en) == "string" and en ~= "", keys = {} }
  if not out.open then return out end
  out.keys = deps.keys and deps.keys(en) or {}
  for _, k in ipairs(out.keys) do
    if WFJ.Lookup.keyed("book", k) then out.shipped = k; break end
  end
  out.creator = call("getCreator") ~= nil
  out.record = SS.get(SURFACE, KEY)
  return out
end

local hooked = false

-- Called by Main after Compat.init. deps = { key(text) → book key | nil, keys(text) → { key, … } }.
function ItemText.init(d)
  deps = d or deps
  Compat.declare(SURFACE, "frame", { "ItemTextFrame" })
  Compat.declare(SURFACE, "page", { "ItemTextPageText" })
  Compat.declare(SURFACE, "scroll", { "ItemTextScrollFrame" })
  Compat.declare(SURFACE, "getText", { "ItemTextGetText" })
  Compat.declare(SURFACE, "getCreator", { "ItemTextGetCreator" })
  if hooked then return false end
  local frame, html = Compat.get(SURFACE, "frame"), Compat.get(SURFACE, "page")
  if not (frame and html and type(frame.HookScript) == "function" and type(html.SetText) == "function"
    and type(html.SetFont) == "function" and type(html.GetFont) == "function"
    and type(html.GetTextColor) == "function") then
    return false
  end
  hooked = true
  page.html = html
  hooksecurefunc(html, "SetText", onPageSetText)
  frame:HookScript("OnEvent", ItemText.onEvent)
  frame:HookScript("OnHide", ItemText.release)
  return true
end
