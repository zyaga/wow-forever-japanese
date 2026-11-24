-- UI/SpellBookNames.lua: the spellbook's page in Japanese without writing into the game's text (surface
-- "spellbook.names", ADR-058, ADR-106): each spell's name while names are on, and the words around it (the line
-- under a name, the level line, the section headers, the page number). An experiment a combat run must confirm.
-- The game measures each spell item's three lines when it refills a page (TrimTextSpace: GetText, GetStringHeight,
-- GetLineHeight [verified: blizzard_playerspells/spellbook/blizzard_spellbookitem.lua:163-171, 173-181]), and text or
-- a font this addon wrote there came back tainted and reached the action bars (ADR-058). So here:
-- - The Japanese is drawn by this addon's own FontString, on this addon's own frame, placed over the game's text.
--   The frame is a child of the book only so that it is shown and hidden with it; it is no child of a spell item,
--   of its text container, of a header or of the paging controls, whose layouts walk every child and region
--   [verified: blizzard_sharedxml/layoutframe.lua:58-62, 468-470, 488-511].
-- - The game's text keeps its text, font, size, colour, anchors and shown state. The one thing changed on it is its
--   alpha, set to 0 so the English does not show through. Nothing in the spellbook, the paged content frame or the
--   layout frames reads a region's alpha back: there is no GetAlpha or GetEffectiveAlpha call in
--   blizzard_playerspells/spellbook, blizzard_playerspells/camelot/spellbook, blizzard_pagedcontent or
--   layoutframe.lua, and the layout reads IsShown and the rect only [verified: layoutframe.lua:38, 455-466]. The
--   value the game wrote is remembered and put back whenever the label goes away.
-- - Nothing runs inside the spellbook's own passes: no hook on a spellbook method and no script on a spellbook
--   frame. This frame's OnUpdate reads the page once a frame, after the game's pass has ended, the way UI/TextWatch
--   does; its OnHide gives every text back.
-- - The page's items are read from PagedSpellsFrame.frames, the list the game itself walks
--   [verified: blizzard_pagedcontent/blizzard_pagedcontentframe.lua:42, 176-178, 541-544]; a spell item is a frame
--   with spellBookItemInfo [verified: blizzard_spellbookitem.lua:104, 129-131], which headers and spacers lack.
-- - In combat: no frame of the spellbook, the paged content or the flyout button is protected (no protected="true"
--   and no secure template in blizzard_playerspells, blizzard_pagedcontent, blizzard_flyout), and a region's SetAlpha
--   is not a protected function [verified: blizzard_apidocumentationgenerated/simpleregionapidocumentation.lua:
--   122-131; only SetScale and SetIgnoreParentScale are, :168-181]. Should a frame that owns a text report itself
--   protected in combat, nothing is written on that text until combat ends.
-- The texts, each a FontString of the client:
-- - A spell's name, TextContainer.Name [verified: blizzard_spellbookitem.xml:65, 74; .lua:17, 184]. The item's code
--   writes its alpha at each refill (0.6 for a spell not learned, else 1 [verified: .lua:227, 254; .xml:48]), so the
--   alpha is read again every frame and the label is dimmed as the game dimmed the name.
-- - The line under it, TextContainer.SubName ("Rank 1", "Passive", "Racial"), and the level line,
--   TextContainer.RequiredLevel ("Level 20", "See your trainer") [verified: .xml:81, 88; .lua:190, 252, 262,
--   295-300]. The same refill writes their alpha [verified: .lua:228-229, 255-256] and hides one that is empty
--   [verified: .lua:163-171, 251, 261]: a hidden one gets no label.
-- - A section header's Text [verified: spellbook/blizzard_spellbooktemplates.xml:5-17], written once per refill by
--   SpellBookHeaderMixin:Init [verified: blizzard_spellbooktemplates.lua:3-7] with a skill line's name
--   [verified: blizzard_spellbookcategory.lua:76-80, 377], "Pet" [verified: :324], "Transmogrify" [verified: :487]
--   or a search result's group [verified: blizzard_spellbooksearch.lua:5-32, 251]. The game never writes its alpha.
--   A header frame is in PagedSpellsFrame.frames like an item [verified: blizzard_pagedcontentframe.lua:403-406,
--   541-544].
-- - The page number, PagingControls.PageText [verified: blizzard_pagedcontent/blizzard_pagingcontrols.xml:20-25,
--   54-66; spellbook/blizzard_spellbookframe.xml:143-154], written by UpdateControls, which then lays the controls
--   out by the text's rect [verified: blizzard_pagingcontrols.lua:110-127]. The game writes the controls frame's
--   alpha (:116), never the text's.
local _, WFJ = ...
local SpellBookNames = {}
WFJ.SpellBookNames = SpellBookNames

local Compat = WFJ.Compat
local SURFACE = "spellbook.names"
SpellBookNames.SURFACE = SURFACE
SpellBookNames.PROPERTY = "alpha" -- the one property of the game's text this module changes
SpellBookNames.MIN_SIZE = 9 -- a long text is drawn smaller, down to this, before it is cut short
local PLAYER_SPELLS = "Blizzard_PlayerSpells"

local driver -- this addon's frame: runs the pass and owns every label
local entries = {} -- the game's FontString → { label, alpha, hidden, ... }
local stamp = 0
local logged = false
local hid, back = 0, 0 -- the alpha writes of the pass now running: texts hidden, texts given back
local drawn = { names = 0, subtexts = 0, levels = 0, headers = 0, pages = 0 } -- the labels of the last pass

local function declare()
  Compat.declare(SURFACE, "book", { "PlayerSpellsFrame.SpellBookFrame" })
  Compat.declare(SURFACE, "paged", { "PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame" })
end

local function secret(value)
  local isSecret = Compat.resolve("issecretvalue")
  return type(isSecret) == "function" and isSecret(value) and true or false
end

local function inCombat()
  local f = Compat.resolve("InCombatLockdown")
  return type(f) == "function" and f() and true or false
end

-- Whether the page shows Japanese now: the master switch, the interface area, and Japanese on screen (the reveal
-- key and the direction). A name needs the names setting on top of this.
local function active()
  local State = WFJ.State
  return State.enabled and State.areaEnabled("ui") and not WFJ.Modifier.english()
end

local function protected(frame)
  return type(frame) == "table" and type(frame.IsProtected) == "function" and frame:IsProtected() and true or false
end

local function isText(fs)
  return type(fs) == "table" and type(fs.GetText) == "function" and type(fs.GetAlpha) == "function"
end

-- A spell item's name and the frames a write on it would touch. → fs, item's text container | nil
local function nameOf(item)
  if type(item) ~= "table" or type(item.spellBookItemInfo) ~= "table" then return nil end
  local container = item.TextContainer
  local fs = type(container) == "table" and container.Name or nil
  if not isText(fs) then return nil end
  return fs, container
end

-- A name's Japanese, while names are on. → ja | nil
local function nameJa(en)
  if not WFJ.State.names then return nil end
  return (WFJ.Names.item(en))
end
local NAME = { id = "names", find = nameJa }

-- The game's text shown again with the alpha the game gave it, and the label hidden. → true when the alpha was
-- written
local function giveBack(fs, e)
  if e.label then e.label:Hide() end
  if not e.hidden then return false end
  -- any alpha above 0 is the game's own, written since: it stays
  if fs:GetAlpha() ~= 0 then
    e.hidden = false
    return false
  end
  if inCombat() and (protected(e.owner) or protected(e.parent)) then return false end
  fs:SetAlpha(e.alpha)
  e.hidden = false
  return true
end

-- Every text given back. → the number of alpha writes
function SpellBookNames.restore()
  local n = 0
  for fs, e in pairs(entries) do
    if giveBack(fs, e) then n = n + 1 end
  end
  return n
end

-- A text's label, made the first time the text has Japanese.
local function labelFor(e, fs, kind)
  if e.label then return e.label end
  local label = driver:CreateFontString(nil, "OVERLAY")
  if kind.anchor == "RIGHT" then
    -- the game's box is as wide as its English: the label keeps the box's right edge and middle line, and its width
    -- is its own
    label:SetPoint("RIGHT", fs, "RIGHT", 0, 0)
    label:SetWordWrap(false)
  else
    -- the label takes the text's width and starts at its top; its height is its own, so the game's box is not needed
    label:SetPoint("TOPLEFT", fs, "TOPLEFT", 0, 0)
    label:SetPoint("TOPRIGHT", fs, "TOPRIGHT", 0, 0)
    label:SetWordWrap(true)
  end
  -- a client font first: a text needs a font, and the bundled one is refused until the client has loaded its file
  label:SetFont(WFJ.Font.CLIENT, WFJ.Font.DEFAULT_SIZE, "")
  label:Hide()
  e.label = label
  return label
end

-- The label dressed like the game's text: its size and flags in the bundled face, its colour, alignment and shadow,
-- and no more lines than the English takes. Done again only when what it copies changed. → false when the client
-- refused the bundled face (its file is not loaded yet): the label cannot show Japanese now
local function dress(e, fs, ja, en)
  local label = e.label
  local _, size, flags = fs:GetFont()
  size, flags = WFJ.Font.size(size) or WFJ.Font.DEFAULT_SIZE, flags or ""
  local lines = math.max(1, fs:GetNumLines() or 1)
  local width = fs:GetWidth()
  if e.en ~= en or e.shownJa ~= ja or e.size ~= size or e.lines ~= lines or e.width ~= width then
    e.en = nil
    if WFJ.Font.set(label, WFJ.Font.PATH, size, flags) == false then return false end
    label:SetMaxLines(lines)
    label:SetJustifyH(fs:GetJustifyH() or "LEFT")
    label:SetShadowColor(fs:GetShadowColor())
    label:SetShadowOffset(fs:GetShadowOffset())
    label:SetText(ja)
    local fit = size
    while fit > SpellBookNames.MIN_SIZE and label:IsTruncated() do
      fit = fit - 1
      label:SetFont(WFJ.Font.PATH, fit, flags)
    end
    e.en, e.shownJa, e.size, e.lines, e.width = en, ja, size, lines, width
  end
  -- the colour and the dimming of a spell not learned follow the game at every look
  label:SetTextColor(fs:GetTextColor())
  label:SetAlpha(e.alpha)
  label:Show()
  return true
end

-- The Japanese of a text, looked up again only when the game's text or the names setting changed. → ja | nil
local function japanese(e, kind, en)
  local names = WFJ.State.names and true or false
  if e.src ~= en or e.srcNames ~= names then
    e.src, e.srcNames, e.ja = en, names, kind.find(en) or false
  end
  return e.ja or nil
end

-- One text of the page: its label placed and the game's text hidden, or the text given back. `owner` and `parent`
-- are the frames a write on it would touch. → true when its label shows
local function place(fs, kind, owner, parent)
  local e = entries[fs]
  if not e then
    e = { alpha = 1, hidden = false }
    entries[fs] = e
  end
  e.owner, e.parent, e.stamp = owner, parent, stamp
  local en = fs:GetText()
  local ja
  -- a text the game hid (an empty line) or hides from addons is not read further
  if not secret(en) and type(en) == "string" and en ~= "" and fs:IsShown() then ja = japanese(e, kind, en) end
  if not ja then
    -- a text with no Japanese keeps the game's text, visible
    if giveBack(fs, e) then back = back + 1 end
    return false
  end
  if inCombat() and (protected(owner) or protected(parent)) then
    if e.label then e.label:Hide() end
    return false
  end
  labelFor(e, fs, kind)
  local alpha = fs:GetAlpha()
  -- above 0 the game wrote it (a refill), or this is the first look: that is the value to put back
  if alpha ~= 0 or not e.hidden then e.alpha = alpha end
  -- the label first: the English is hidden only once the Japanese is on screen
  if not dress(e, fs, ja, en) then
    if giveBack(fs, e) then back = back + 1 end
    return false
  end
  e.hidden = true
  drawn[kind.id] = drawn[kind.id] + 1
  if alpha == 0 then return true end
  fs:SetAlpha(0)
  hid = hid + 1
  return true
end

local function levelOver(container)
  if type(container.GetFrameLevel) ~= "function" then return end
  -- above the items' own art, which a frame of a lower level would be drawn under
  local level = container:GetFrameLevel() + 1
  if driver:GetFrameLevel() ~= level then driver:SetFrameLevel(level) end
end

-- ───────────────────────── the words around the names: subtext, level line, header, page number ─────────────────────
-- Interface words, not names: they show Japanese whenever the page does, whatever the names setting says. A header
-- that is a skill line's name ("Arms") is a name and follows the names setting.

-- A dictionary line's Japanese, when the text is one of `only`'s lines. → ja | nil
local function wordJa(en, only)
  local index = WFJ.UIIndex
  if not index then return nil end
  local key, args = index:matchOnly(en, only)
  local row = key and index.rows[key]
  if not row then return nil end
  return index:fill(row[1], args)
end

-- "Rank %d", "Passive", a profession's rank, and the Spell table's own subtexts ("Racial Passive"). "Summon" is
-- also BATTLE_PET_SUMMON's English, and the exact entry answers before the table's row. A pet family or a form's
-- name under a spell is a name with no line here: it stays as the game wrote it.
local SUBTEXT_KEYS = { "SPELL_PASSIVE", "TOOLTIP_TALENT_RANK_CURRENT_ONLY", "RANK", "APPRENTICE", "JOURNEYMAN",
  "EXPERT", "ARTISAN", "BATTLE_PET_SUMMON" }
local LEVEL_KEYS = { SPELLBOOK_AVAILABLE_AT = true, SPELLBOOK_TRAINABLE = true, BOOSTED_CHAR_SPELL_TEMPLOCK = true }
-- The headers that are words: the pet book's, the outfits', the first skill line's ("General", the word the
-- character sheet's stat group ships) and a search result's groups.
local HEADER_KEYS = { PET = true, TRANSMOGRIFY = true, STAT_CATEGORY_GENERAL = true,
  SPELLBOOK_SEARCH_HEADER_EXACT = true, SPELLBOOK_SEARCH_HEADER_RELATED = true, SPELLBOOK_SEARCH_HEADER_NAME = true,
  SPELLBOOK_SEARCH_HEADER_DESCRIPTION = true, SPELLBOOK_SEARCH_HEADER_GENERIC = true,
  SPELLBOOK_SEARCH_HEADER_RESULTS = true }
local PAGE_KEYS = { PAGE_NUMBER = true, PAGE_NUMBER_WITH_MAX = true }
SpellBookNames.WORD_KEYS = { subtext = SUBTEXT_KEYS, level = LEVEL_KEYS, header = HEADER_KEYS, page = PAGE_KEYS }

local SUBTEXT = { id = "subtexts", find = function(en)
  return wordJa(en, WFJ.Labels.familiesWith(SUBTEXT_KEYS, "SpellSubtext").only)
end }
local LEVEL = { id = "levels", find = function(en) return wordJa(en, LEVEL_KEYS) end }
local HEADER = { id = "headers", find = function(en) return wordJa(en, HEADER_KEYS) or nameJa(en) end }
-- the numbers are the game's own: the template's captures, put back as written
local PAGE = { id = "pages", find = function(en) return wordJa(en, PAGE_KEYS) end, anchor = "RIGHT" }

-- A header's text: a frame of the page that is no spell item and holds one Text. → fs | nil
local function headerOf(item)
  if type(item) ~= "table" or item.spellBookItemInfo ~= nil or item.TextContainer ~= nil or item.Button ~= nil then
    return nil
  end
  if not isText(item.Text) or type(item.IsVisible) ~= "function" or not item:IsVisible() then return nil end
  return item.Text
end

-- The words of one frame of the page: a spell item's two lines, or a header. → the labels showing
local function words(item, container)
  local n = 0
  if container then
    if isText(container.SubName) and place(container.SubName, SUBTEXT, item, container) then n = n + 1 end
    if isText(container.RequiredLevel) and place(container.RequiredLevel, LEVEL, item, container) then n = n + 1 end
    return n
  end
  local text = headerOf(item)
  if text and place(text, HEADER, item, nil) then n = n + 1 end
  return n
end

-- The page number, while the game shows its controls. → 1 | 0
local function pageNumber(paged)
  local controls = paged.PagingControls
  local fs = type(controls) == "table" and controls.PageText or nil
  if not isText(fs) or type(controls.IsVisible) ~= "function" or not controls:IsVisible() then return 0 end
  -- the game hides the controls of a single page by their alpha, where a book is set up to
  if type(controls.GetAlpha) == "function" and controls:GetAlpha() == 0 then return 0 end
  return place(fs, PAGE, controls, paged) and 1 or 0
end
-- ────────────────────────────────────────────── end of the words ──────────────────────────────────────────────────

-- One pass over the page. → the number of labels showing
function SpellBookNames.tick()
  if not driver then return 0 end
  local paged = Compat.get(SURFACE, "paged")
  local frames = type(paged) == "table" and paged.frames or nil
  if type(frames) ~= "table" or not active() then
    local n = SpellBookNames.restore()
    if n > 0 and WFJ.TaintWatch then WFJ.TaintWatch.push("spellbooknames gave back " .. n) end
    return 0
  end
  stamp = stamp + 1
  hid, back = 0, 0
  for id in pairs(drawn) do drawn[id] = 0 end
  local shown, levelled = 0, false
  for i = 1, #frames do
    local item = frames[i]
    local fs, container = nameOf(item)
    if fs and item:IsVisible() then
      if not levelled then
        levelOver(container)
        levelled = true
      end
      if place(fs, NAME, item, container) then shown = shown + 1 end
      shown = shown + words(item, container)
    elseif not fs then
      shown = shown + words(item, nil)
    end
  end
  shown = shown + pageNumber(paged)
  -- a text the page no longer shows (its frame handed back to its pool) gets its alpha back at once
  for fs, e in pairs(entries) do
    if e.stamp ~= stamp and (e.hidden or (e.label and e.label:IsShown())) and giveBack(fs, e) then back = back + 1 end
  end
  if WFJ.TaintWatch then
    -- into the taint watch's event list, so a block shows whether this module wrote just before it
    if hid > 0 then WFJ.TaintWatch.push("spellbooknames " .. SpellBookNames.PROPERTY .. " " .. hid) end
    if back > 0 then WFJ.TaintWatch.push("spellbooknames gave back " .. back) end
  end
  if shown > 0 and not logged then
    logged = true
    WFJ.Diag.log("spellbooknames", "first pass", { labels = shown, names = drawn.names, subtexts = drawn.subtexts,
      levels = drawn.levels, headers = drawn.headers, pages = drawn.pages, property = SpellBookNames.PROPERTY,
      combat = inCombat() })
  end
  return shown
end

-- The labels now showing (for /wfj debug and the specs). → count
function SpellBookNames.count()
  local n = 0
  for _, e in pairs(entries) do
    if e.label and e.label:IsShown() then n = n + 1 end
  end
  return n
end

-- The label over a text of the game, when it has one. → FontString | nil
function SpellBookNames.labelOf(fs)
  local e = entries[fs]
  return e and e.label or nil
end

-- The Blizzard_PlayerSpells part: this addon's frame, made once the book exists. → true when made now
function SpellBookNames.setup()
  declare()
  if driver then return false end
  local book = Compat.get(SURFACE, "book")
  local create = Compat.resolve("CreateFrame")
  if type(book) ~= "table" or type(create) ~= "function" then return false end
  -- a child of the book runs no OnUpdate while the book is closed: nothing is read then
  driver = create("Frame", nil, book)
  driver:SetAllPoints(book)
  driver:SetScript("OnUpdate", WFJ.Perf.wrap("idle.spellbooknames", SpellBookNames.tick))
  driver:SetScript("OnHide", function() SpellBookNames.restore() end)
  SpellBookNames.driver = driver
  return true
end

-- Called by Main after Compat.init and LoadOnDemand.init. → true when set up now, false while it waits for
-- Blizzard_PlayerSpells
function SpellBookNames.init()
  declare()
  return WFJ.LoadOnDemand.when(PLAYER_SPELLS, SpellBookNames.setup)
end
