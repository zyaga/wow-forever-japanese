-- UI/TooltipFreeze.lua: a trial of the frozen tooltip. A key press while a tooltip shows draws a copy of it in the
-- same place (same size, lines, fonts and colors), which stays after the game hides its own, so the mouse can go
-- onto it and its Japanese words take word cards (UI/Readings). The key again, or Esc, closes it.
--
-- The game's own tooltip is never held open: whatever the mouse was on hides it on leave, and standing in the way
-- of that would run addon code inside the action buttons' own handlers.
--
-- Trial data: the words of one line only (the Hearthstone's), listed below, until tooltip text has readings.
local _, WFJ = ...
local Freeze = {}
WFJ.TooltipFreeze = Freeze

local Compat = WFJ.Compat
local SURFACE = "tooltip.frozen"

-- word, reading, dictionary form, its reading, meaning: in the order the words stand in the line
local TRIAL = {
  { find = "ホームに設定した場所へ戻ります", words = {
    { "ホーム", "ホーム", "ホーム", "ホーム", "home (your hearthstone's inn)" },
    { "設定した", "せっていした", "設定する", "せっていする", "to set" },
    { "場所", "ばしょ", "場所", "ばしょ", "place" },
    { "戻ります", "もどります", "戻る", "もどる", "to return" },
    { "別", "べつ", "別", "べつ", "another, different" },
    { "場所", "ばしょ", "場所", "ばしょ", "place" },
    { "話しかける", "はなしかける", "話しかける", "はなしかける", "to speak to" },
    { "ホーム", "ホーム", "ホーム", "ホーム", "home (your hearthstone's inn)" },
    { "場所", "ばしょ", "場所", "ばしょ", "place" },
    { "変更できます", "へんこうできます", "変更する", "へんこうする", "to change" },
  } },
}

-- → the word spans of `text` from the trial list, or nil
local function trialSpans(text)
  for _, row in ipairs(TRIAL) do
    if text:find(row.find, 1, true) then
      local out, cursor = {}, 1
      for _, w in ipairs(row.words) do
        local s, e = text:find(w[1], cursor, true)
        if s then
          out[#out + 1] = { first = s, last = e, word = w[1], reading = w[2],
            card = { lemma = w[3], lemmaReading = w[4], meaning = w[5] } }
          cursor = e + 1
        end
      end
      return out[1] and out or nil
    end
  end
  return nil
end

local frame
local lines = {} -- pooled FontStrings of the copy
local recs = {} -- the word-card records of the lines showing
local used = 0
local signature -- the left text of the tooltip the copy was made from

local function ensure()
  if frame then return frame end
  local ui = Compat.resolve("UIParent")
  frame = CreateFrame("Frame", "WFJFrozenTooltip", ui, "TooltipBackdropTemplate")
  -- under the TOOLTIP strata, so the word card (drawn there) is never behind the copy
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:EnableMouse(true) -- nothing under the copy answers the mouse while it shows
  frame:SetClampedToScreen(true)
  frame:Hide()
  frame:SetScript("OnHide", function() Freeze.clear() end)
  local special = Compat.resolve("UISpecialFrames") -- Esc closes it
  if type(special) == "table" then special[#special + 1] = "WFJFrozenTooltip" end
  return frame
end

local function line()
  used = used + 1
  local fs = lines[used]
  if not fs then
    fs = frame:CreateFontString(nil, "ARTWORK", "GameTooltipText")
    fs:SetJustifyV("TOP")
    lines[used] = fs
  end
  return fs
end

-- Copies one line of the tooltip. → the copy, or nil when the line shows nothing
local function copyLine(tip, src)
  if type(src) ~= "table" or not src:IsShown() then return nil end
  local text = src:GetText()
  local left, top = src:GetLeft(), src:GetTop()
  if type(text) ~= "string" or text == "" or not left or not top then return nil end
  local fs = line()
  local path, size, flags = src:GetFont()
  if path then WFJ.Font.set(fs, path, size, flags) end
  fs:SetTextColor(src:GetTextColor())
  fs:SetJustifyH(src:GetJustifyH())
  if fs.SetSpacing and src.GetSpacing then fs:SetSpacing(src:GetSpacing()) end
  if fs.SetNonSpaceWrap and src.CanNonSpaceWrap then fs:SetNonSpaceWrap(src:CanNonSpaceWrap()) end
  fs:SetWordWrap(true)
  fs:SetWidth(src:GetWidth())
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", frame, "TOPLEFT", left - tip:GetLeft(), top - tip:GetTop())
  fs:SetText(text)
  fs:Show()
  return fs
end

local function colors(tip)
  local from, to = tip.NineSlice, frame.NineSlice
  if type(from) ~= "table" or type(to) ~= "table" then return end
  if from.GetCenterColor and to.SetCenterColor then pcall(function() to:SetCenterColor(from:GetCenterColor()) end) end
  if from.GetBorderColor and to.SetBorderColor then pcall(function() to:SetBorderColor(from:GetBorderColor()) end) end
end

local function leftText(tip)
  local parts, name = {}, tip:GetName()
  for i = 1, tip:NumLines() or 0 do
    local fs = Compat.resolve(name .. "TextLeft" .. i)
    parts[#parts + 1] = fs and fs:GetText() or ""
  end
  return table.concat(parts, "\n")
end

function Freeze.clear()
  for _, rec in ipairs(recs) do WFJ.ReadingView.detach(rec) end
  recs = {}
  for i = 1, used do lines[i]:Hide() end
  used = 0
  signature = nil
end

-- Draws the copy of `tip` where it stands.
function Freeze.show(tip)
  local f = ensure()
  local ui = Compat.resolve("UIParent")
  Freeze.clear()
  -- the copy takes the tooltip's own scale, so its lengths and positions carry over as they are
  f:SetScale(tip:GetEffectiveScale() / ui:GetEffectiveScale())
  f:SetSize(tip:GetWidth(), tip:GetHeight())
  f:ClearAllPoints()
  f:SetPoint("BOTTOMLEFT", ui, "BOTTOMLEFT", tip:GetLeft(), tip:GetBottom())
  colors(tip)
  f:Show() -- before the lines: OnHide of an earlier copy has run by now, never after
  local name = tip:GetName()
  for i = 1, tip:NumLines() or 0 do
    local fs = copyLine(tip, Compat.resolve(name .. "TextLeft" .. i))
    copyLine(tip, Compat.resolve(name .. "TextRight" .. i))
    local text = fs and fs:GetText()
    local spans = text and not text:find("|", 1, true) and trialSpans(text)
    if spans then
      local rec = { fs = fs, applied = text, surface = SURFACE, spans = spans, meta = { kind = "tooltip", id = i } }
      if WFJ.ReadingView.attach(rec) then recs[#recs + 1] = rec end
    end
  end
  signature = leftText(tip)
end

-- The key: freezes the tooltip showing now; with none showing (or the same one already frozen), closes the copy.
function Freeze.toggle()
  local tip = Compat.resolve("GameTooltip")
  local showing = type(tip) == "table" and tip:IsShown() and tip:GetLeft() and (tip:NumLines() or 0) > 0
  local frozen = frame and frame:IsShown()
  if showing and not (frozen and signature == leftText(tip)) then
    Freeze.show(tip)
  elseif frozen then
    frame:Hide()
  end
end

WFJ.ReadingView.SURFACES[SURFACE] = true

function WFJ_FreezeTooltip() Freeze.toggle() end
