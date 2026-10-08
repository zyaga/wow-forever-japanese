-- UI/VoicePanelText.lua: the voice panel's text (ADR-063): the line paged a sentence at a time, each page's words for
-- the word cards, the English shown while the reveal key is held, and the whole-text window.
--   Text.paginate(ja, budget) → pages, starts, segs (pure: starts are shares of the line; segs map each page's pieces
--                                 back to their bytes in `ja`)
--   Text.pageSpans(item, segs, page) → the page's words, located in the whole line
--   Text.showPage(fs, item, page, spans) · Text.showEnglish(fs, item) · Text.detach()
--   Text.openWhole(anchor, item, look, toQuestLog, english) → true when shown · Text.refreshWhole(item, look, english)
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

local ENDS = { "。", "！", "？" } -- a sentence ends at a run of these (and its closing brackets)
local CLOSES = { "」", "』", "）" }

-- the byte length of the mark from ENDS / CLOSES / "\n" starting at `i`, or nil
local function markAt(ja, i, set)
  for _, m in ipairs(set) do
    if ja:sub(i, i + #m - 1) == m then return #m end
  end
  return nil
end

-- The line's sentences as { text, from }: `from` is the byte the trimmed text starts at in `ja`. A sentence ends after
-- a run of 。！？ and the closing brackets after it, or at a line break; spaces and breaks around it are trimmed.
local function sentences(ja)
  local out, start, i = {}, 1, 1
  local function cut(stop)
    local raw = ja:sub(start, stop)
    local lead = #(raw:match("^%s*"))
    local text = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if text ~= "" then out[#out + 1] = { text = text, from = start + lead } end
    start = stop + 1
  end
  while i <= #ja do
    if ja:sub(i, i) == "\n" then
      cut(i)
      i = i + 1
    else
      local n = markAt(ja, i, ENDS)
      if n then
        local j = i + n
        while true do -- the rest of the run, then its closing brackets
          local m = markAt(ja, j, ENDS) or markAt(ja, j, CLOSES)
          if not m then break end
          j = j + m
        end
        cut(j - 1)
        i = j
      else
        i = i + 1
      end
    end
  end
  if start <= #ja then cut(#ja) end
  return out
end

-- A sentence longer than `budget` characters split after 、 into pieces that fit (a piece with no 、 to split at is
-- cut at the budget, on a character boundary), each with its byte offset.
local function fit(piece, budget)
  if not budget or chars(piece.text) <= budget then return { piece } end
  local out, text, base = {}, piece.text, piece.from
  local from, at = 1, 1 -- the current piece's first byte, and the scan position, in `text`
  local lastComma -- the byte after the last 、 seen in the current piece
  while at <= #text do
    local c = text:byte(at)
    local len = c >= 0xF0 and 4 or c >= 0xE0 and 3 or c >= 0xC0 and 2 or 1
    if text:sub(at, at + len - 1) == "、" then lastComma = at + len end
    if chars(text:sub(from, at + len - 1)) > budget then
      local stop = (lastComma and lastComma > from) and lastComma - 1 or at - 1
      out[#out + 1] = { text = text:sub(from, stop), from = base + from - 1 }
      from, lastComma = stop + 1, nil
    end
    at = at + len
  end
  if from <= #text then out[#out + 1] = { text = text:sub(from), from = base + from - 1 } end
  return out
end

-- The line in pages a sentence at a time; a sentence under SHORT_PAGE characters joins the next, and a sentence over
-- `budget` characters (what the look's lines hold) is split after 、.
-- → pages, the share of the line each starts at, and per page its pieces { from (byte in `ja`), at (byte in the
-- page), len } so the line's words can be mapped onto it
function Text.paginate(ja, budget)
  if type(ja) ~= "string" or ja == "" then return { "" }, { 0 }, { {} } end
  local pieces = {}
  for _, sentence in ipairs(sentences(ja)) do
    for _, piece in ipairs(fit(sentence, budget)) do pieces[#pieces + 1] = piece end
  end
  local pages, segs = {}, {}
  local text, seg = "", {}
  local function flush()
    if text ~= "" then pages[#pages + 1], segs[#segs + 1] = text, seg end
    text, seg = "", {}
  end
  for _, piece in ipairs(pieces) do
    if text ~= "" and chars(text) >= SHORT_PAGE then flush() end
    seg[#seg + 1] = { from = piece.from, at = #text + 1, len = #piece.text }
    text = text .. piece.text
  end
  flush()
  if #pages == 0 then return { "" }, { 0 }, { {} } end
  local total, at, starts = 0, 0, {}
  for _, p in ipairs(pages) do total = total + chars(p) end
  for i, p in ipairs(pages) do
    starts[i] = total > 0 and at / total or 0
    at = at + chars(p)
  end
  return pages, starts, segs
end

-- The words of a page made of `segs` (from Text.paginate), located in the whole line and moved to the page.
function Text.pageSpans(item, segs, page)
  if lineSpansFor ~= item then
    lineSpansFor = item
    lineSpans = item and type(item.ja) == "string" and WFJ.Readings.lookup(item.kind, item.id, item.ja) or nil
  end
  if not segs or not segs[1] or not lineSpans then return WFJ.Readings.lookup(item.kind, item.id, page) end
  local out = {}
  for _, sp in ipairs(lineSpans) do
    for _, sg in ipairs(segs) do
      if sp.first >= sg.from and sp.last <= sg.from + sg.len - 1 then
        local shift = sg.at - sg.from
        out[#out + 1] = { first = sp.first + shift, last = sp.last + shift, word = sp.word, reading = sp.reading,
          gloss = sp.gloss }
      end
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
-- `english`: the reveal key is held: the line's English, with no word cards (they never show while English does).
function Text.refreshWhole(item, L, english)
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
  if english then
    if WFJ.ReadingView and wholeRec.fs then pcall(WFJ.ReadingView.detach, wholeRec) end
    whole.text:SetText(item.en or item.ja or "")
    whole.child:SetHeight(math.max(whole.text:GetStringHeight() + 8, 10))
    return
  end
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
function Text.openWhole(anchor, item, L, toQuestLog, english)
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
  Text.refreshWhole(item, L, english)
  return true
end

function Text.hideWhole()
  if whole then whole:Hide() end
end

function Text.wholeShown()
  return whole ~= nil and whole:IsShown()
end
