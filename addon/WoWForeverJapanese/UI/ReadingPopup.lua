-- UI/ReadingPopup.lua: the word popup (ADR-039): the card UI/Readings shows in place of
-- its reading-only box when the hovered word carries a meaning (Core/Glosses) and `readings.glosses` is on.
--
--   倒して  たおして              the word (larger) and its reading
--   ← 倒す（たおす）              the dictionary form, only when it differs from the word
--   defeat (and then)            the word's meaning in this sentence, wrapped inside a fixed width
--
-- Same strata and anchor as the reading box: bottom-centre above the word, clamped to the screen. It owns no data and
-- no hit testing: UI/Readings decides when it shows and hides.
local _, WFJ = ...
local Popup = {}
WFJ.ReadingPopup = Popup

-- UIParent is read through Compat.resolve (as UI/Readings does); this module declares no Compat surface.
local Compat = WFJ.Compat

Popup.WIDTH = 280 -- the card's width; the meaning wraps inside it. A head line (word + reading) wider than that
-- widens the card to fit it: a whole verb phrase is one word (減らしてやって欲しい)
local PAD = 10 -- inside the tooltip border
local GAP = 3

local frame, wordFs, readingFs, lemmaFs, meaningFs

local function text(parent, size, r, g, b)
  -- a template font first, so SetText never meets a FontString without one if the bundled font is refused
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  WFJ.Font.set(fs, WFJ.Font.PATH, size, "")
  fs:SetTextColor(r, g, b)
  fs:SetJustifyH("LEFT")
  return fs
end

local function ensure()
  if frame then return frame end
  -- the game's own tooltip frame and border, so the card looks like the client's widgets [verified:
  -- TooltipBackdropTemplate, Blizzard_SharedXML/Shared/Tooltip/SharedTooltipTemplates.xml, Blizzard_SharedXML.toc:
  -- 160–161; the calendar's description field uses it]
  frame = CreateFrame("Frame", nil, Compat.resolve("UIParent"), "TooltipBackdropTemplate")
  frame:SetFrameStrata("TOOLTIP")
  -- verified on Forever: blizzard_menu/menu.lua:1530 calls SetClampedToScreen(true) on a frame
  frame:SetClampedToScreen(true)
  wordFs = text(frame, 16, 1, 1, 1)
  readingFs = text(frame, 13, 1, 0.82, 0)
  lemmaFs = text(frame, 12, 0.72, 0.72, 0.72)
  meaningFs = text(frame, 12, 0.92, 0.92, 0.92)
  frame:Hide()
  return frame
end

-- The lines the card shows for `word` (a Core/Readings span: { word, reading }) and its gloss → head, reading,
-- dictionary form (nil when it is the word itself), meaning. Pure layout text, tested on its own.
function Popup.lines(word, gloss)
  local lemma
  -- the dictionary form laid out like the head line (word, then its reading) in softer colours of its own (pale
  -- blue word, muted gold reading), so it reads as the entry behind the word above (a bare
  -- "←" read as pointing at nothing)
  if gloss.lemma ~= word.word then
    lemma = "|cffbfd4f2" .. gloss.lemma .. "|r　|cffc9a65a" .. gloss.lemmaReading .. "|r"
  end
  -- a kana word is its own reading: shown once
  return word.word, word.reading ~= word.word and word.reading or "", lemma, gloss.meaning
end

-- Shows the card for `word` above the point (x, y) of `anchor` (the cover frame, its BOTTOMLEFT origin).
function Popup.show(anchor, x, y, word, gloss, size)
  local f = ensure()
  local head, reading, lemma, meaning = Popup.lines(word, gloss)
  local headSize = math.max((size or 12) + 2, 14)
  WFJ.Font.set(wordFs, WFJ.Font.PATH, headSize, "")
  wordFs:SetText(head)
  readingFs:SetText(reading)
  wordFs:ClearAllPoints()
  wordFs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
  readingFs:ClearAllPoints()
  readingFs:SetPoint("LEFT", wordFs, "RIGHT", 8, 0)
  local height = PAD + wordFs:GetStringHeight()
  local below = wordFs
  if lemma then
    lemmaFs:SetText(lemma)
    lemmaFs:ClearAllPoints()
    lemmaFs:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -GAP)
    lemmaFs:Show()
    height = height + GAP + lemmaFs:GetStringHeight()
    below = lemmaFs
  else
    lemmaFs:SetText("")
    lemmaFs:Hide()
  end
  local width = math.max(Popup.WIDTH, 2 * PAD + wordFs:GetStringWidth() + 8 + readingFs:GetStringWidth())
  if lemma then width = math.max(width, 2 * PAD + lemmaFs:GetStringWidth()) end
  meaningFs:SetWidth(width - 2 * PAD)
  meaningFs:SetText(meaning)
  meaningFs:ClearAllPoints()
  meaningFs:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -GAP - 2)
  height = height + GAP + 2 + meaningFs:GetStringHeight() + PAD
  f:SetSize(width, height)
  f:ClearAllPoints()
  f:SetPoint("BOTTOM", anchor, "BOTTOMLEFT", x, y)
  f.owner = anchor
  f:Show()
  return f
end

function Popup.hide(owner)
  if frame and (owner == nil or frame.owner == owner) then
    frame:Hide()
    frame.owner = nil
  end
end

function Popup.frame() return frame end
