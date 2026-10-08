-- UI/VoicePanelText.lua: the voice panel's text (ADR-063): the line paged a sentence at a time, each page's words for
-- the word cards, the English shown while the reveal key is held, and the whole-text window.
--   Text.paginate(ja) → pages, starts, offsets      (pure: starts are shares of the line, offsets bytes in `ja`)
--   Text.pageSpans(item, offset, page) → the page's words, located in the whole line
--   Text.showPage(fs, item, page, spans) · Text.showEnglish(fs, item) · Text.detach()
--   Text.openWhole(anchor, item, look, toQuestLog) → true when shown · Text.refreshWhole(item, look)
--   Text.hideWhole() · Text.wholeShown()
-- Word cards come from UI/Readings like every other surface (surface "voicepanel"); a page passes its words in
-- `rec.spans`, because a line's word list is in the order of the whole line and a sentence alone can match an
-- earlier sentence's word late and miss its own.
local _, WFJ = ...
local Text = {}
WFJ.VoicePanelText = Text

local Compat = WFJ.Compat

local SHORT_PAGE = 12 -- characters: a shorter sentence joins the next page
local WHOLE_WIDTH, WHOLE_HEIGHT = 480, 300

local rec = { surface = "voicepanel", key = "text" } -- the panel text's record for UI/Readings
local wholeRec = { surface = "voicepanel", key = "full" } -- the whole-text window's record
local lineSpans, lineSpansFor -- the displayed line's words in the whole line, and the item they are for
local whole -- the whole-text window, built on first use

local function chars(s)
  return (s:gsub("[\128-\191]", "")):len()
end

-- The line split after 。！？ and line breaks (a closing bracket stays with its sentence); a sentence under
-- SHORT_PAGE characters joins the next. → pages, the share of the line each starts at, the byte each starts at in
-- `ja` (nil for a page that is not a plain slice of it: trimmed pieces joined)
function Text.paginate(ja)
  local pages, starts, offsets = {}, {}, {}
  if type(ja) ~= "string" or ja == "" then return { "" }, { 0 }, {} end
  local s = ja
  for _, p in ipairs({ "。", "！", "？", "\n" }) do s = s:gsub(p, p .. "\1") end
  for _, close in ipairs({ "」", "』", "）" }) do s = s:gsub("\1" .. close, close .. "\1") end
  local parts, carry = {}, ""
  for raw in (s .. "\1"):gmatch("(.-)\1") do
    local piece = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if piece ~= "" then
      carry = carry == "" and piece or (carry .. piece)
      if chars(carry) >= SHORT_PAGE then
        parts[#parts + 1] = carry
        carry = ""
      end
    end
  end
  if carry ~= "" then
    if #parts > 0 then parts[#parts] = parts[#parts] .. carry else parts[1] = carry end
  end
  local total = 0
  for _, p in ipairs(parts) do total = total + chars(p) end
  local at, from = 0, 1
  for i, p in ipairs(parts) do
    pages[i], starts[i] = p, total > 0 and at / total or 0
    at = at + chars(p)
    local found = ja:find(p, from, true)
    offsets[i] = found
    if found then from = found + #p end
  end
  return pages, starts, offsets
end

-- The words of a page starting at byte `offset` of `item.ja`, shifted to the page; a page with no offset is looked
-- up on its own.
function Text.pageSpans(item, offset, page)
  if lineSpansFor ~= item then
    lineSpansFor = item
    lineSpans = item and type(item.ja) == "string" and WFJ.Readings.lookup(item.kind, item.id, item.ja) or nil
  end
  if not offset or not lineSpans then return WFJ.Readings.lookup(item.kind, item.id, page) end
  local last = offset + #page - 1
  local out = {}
  for _, sp in ipairs(lineSpans) do
    if sp.first >= offset and sp.last <= last then
      out[#out + 1] = { first = sp.first - offset + 1, last = sp.last - offset + 1, word = sp.word,
        reading = sp.reading, gloss = sp.gloss }
    end
  end
  return out
end

local function attach(r)
  if WFJ.ReadingView then pcall(WFJ.ReadingView.attach, r) end
end

function Text.detach()
  if WFJ.ReadingView and rec.fs then pcall(WFJ.ReadingView.detach, rec) end
end

function Text.showPage(fs, item, page, spans)
  fs:SetText(page)
  rec.fs, rec.applied, rec.meta, rec.spans = fs, page, { kind = item.kind, id = item.id }, spans
  attach(rec)
end

-- The line's English as the client wrote it into its window when the line started, whole (its sentences do not
-- line up with the Japanese pages), with no word cards.
function Text.showEnglish(fs, item)
  Text.detach()
  fs:SetText(item.en or item.ja or "")
end

-- ── The whole-text window ─────────────────────────────────────────────────

local function buildWhole()
  whole = CreateFrame("Frame", "WFJVoicePanelText", Compat.resolve("UIParent"), "TooltipBackdropTemplate")
  whole:SetSize(WHOLE_WIDTH, WHOLE_HEIGHT)
  whole:SetFrameStrata("HIGH")
  whole:SetClampedToScreen(true)
  whole:EnableMouse(true)
  whole.bg = whole:CreateTexture(nil, "BACKGROUND", nil, 1)
  whole.bg:SetPoint("TOPLEFT", 4, -4)
  whole.bg:SetPoint("BOTTOMRIGHT", -4, 4)
  whole.title = whole:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  whole.title:SetPoint("TOPLEFT", whole, "TOPLEFT", 14, -12)
  local close = CreateFrame("Button", nil, whole, "UIPanelCloseButton")
  close:SetSize(26, 26)
  close:SetPoint("TOPRIGHT", whole, "TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() whole:Hide() end)
  local sf = CreateFrame("ScrollFrame", nil, whole, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", whole, "TOPLEFT", 14, -36)
  sf:SetPoint("BOTTOMRIGHT", whole, "BOTTOMRIGHT", -32, 12)
  whole.child = CreateFrame("Frame", nil, sf)
  whole.child:SetSize(WHOLE_WIDTH - 50, 10)
  sf:SetScrollChild(whole.child)
  -- anchored at the top with a width only: the box is as tall as its text (word positions are measured from it)
  whole.text = whole.child:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  whole.text:SetPoint("TOPLEFT", whole.child, "TOPLEFT", 0, 0)
  whole.text:SetWidth(WHOLE_WIDTH - 50)
  whole.text:SetJustifyH("LEFT")
  whole.text:SetJustifyV("TOP")
  whole.text:SetWordWrap(true)
  if whole.text.SetNonSpaceWrap then whole.text:SetNonSpaceWrap(true) end
  whole.text:SetSpacing(3)
  WFJ.Font.set(whole.text, WFJ.Font.PATH, 15, "")
  whole:SetScript("OnHide", function()
    if WFJ.ReadingView and wholeRec.fs then pcall(WFJ.ReadingView.detach, wholeRec) end
  end)
  whole:Hide()
end

-- The window's text and colours for `item` in the panel's look (parchment behind dark text on a parchment look).
function Text.refreshWhole(item, L)
  if not whole or not whole:IsShown() or not item then return end
  local parchment = L.textColor[1] < 0.5
  whole.bg:SetShown(parchment)
  if parchment then
    whole.bg:SetAtlas("QuestBG-Parchment")
    whole.title:SetTextColor(L.nameColor[1], L.nameColor[2], L.nameColor[3])
    whole.text:SetTextColor(0.12, 0.08, 0.03)
    whole.text:SetShadowOffset(0, 0)
  else
    whole.title:SetTextColor(1, 0.82, 0.02)
    whole.text:SetTextColor(1, 1, 1)
    whole.text:SetShadowOffset(1, -1)
  end
  whole.title:SetText(item.name or "")
  local ja = item.ja or ""
  whole.text:SetText(ja)
  whole.child:SetHeight(math.max(whole.text:GetStringHeight() + 8, 10))
  wholeRec.fs, wholeRec.applied, wholeRec.meta = whole.text, ja, { kind = item.kind, id = item.id }
  attach(wholeRec)
end

-- A quest line whose quest is in the player's log: the quest log opened at it (the world map's quest pane, which
-- shows it in Japanese). [verified: forever 1.60.1.70245 mainline/questmapframe.lua:1175–1179
-- (QuestMapFrame_OpenToQuestDetails); questlogdocumentation.lua:206 (GetLogIndexForQuestID)] → true when opened
local function openQuest(item)
  if type(item.kind) ~= "string" or not item.kind:match("^quest%.") or type(item.id) ~= "number" then
    return false
  end
  local QL = Compat.resolve("C_QuestLog")
  local open = Compat.resolve("QuestMapFrame_OpenToQuestDetails")
  if type(QL) ~= "table" or type(QL.GetLogIndexForQuestID) ~= "function" or type(open) ~= "function" then
    return false
  end
  if not QL.GetLogIndexForQuestID(item.id) then return false end -- an offer not taken yet is not in the log
  return pcall(open, item.id) and true or false
end

-- The whole text of `item`: the quest in the quest log when `toQuestLog` and it is there, else the window above
-- `anchor` (a second call closes the window). → true when something opened
function Text.openWhole(anchor, item, L, toQuestLog)
  if not item then return false end
  if whole and whole:IsShown() then
    whole:Hide()
    return false
  end
  if toQuestLog and openQuest(item) then return true end
  if not whole then buildWhole() end
  whole:ClearAllPoints()
  whole:SetPoint("BOTTOM", anchor, "TOP", 0, 6)
  whole:Show()
  Text.refreshWhole(item, L)
  return true
end

function Text.hideWhole()
  if whole then whole:Hide() end
end

function Text.wholeShown()
  return whole ~= nil and whole:IsShown()
end
