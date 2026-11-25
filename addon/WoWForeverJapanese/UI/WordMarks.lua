-- UI/WordMarks.lua: the word status marks on a word-card cover (docs/systems/word-status.md). On the reading
-- places the player switched on, every word carries its status: an underline while it is unknown or learning, and
-- a soft highlight on the unknown words the highlight setting picks; a small tag over the text says how much of
-- it the player knows. A Shift+click on the word under the mouse steps its status and a Shift+right-click ignores
-- it. UI/Readings owns the covers and calls in here: laid / clear / entered for the marks, click / pollRight for
-- the clicks, statusLine for the word card. Which word takes which mark is Core/WordMarks' plan; this file draws.
-- The marks are textures on the cover, so they scroll and clip with the text and are never made in combat on
-- their own (a cover is only made out of combat).
local _, WFJ = ...
local Marks = {}
WFJ.WordMarks = Marks

local Compat = WFJ.Compat
local View = WFJ.ReadingView

-- The place a surface belongs to: each place has its own setting (`marks.<place>`).
local PLACE = {
  ["questframe.detail"] = "quest", ["questframe.reward"] = "quest", ["questframe.progress"] = "quest",
  ["questframe.greeting"] = "quest", ["questmap.info"] = "quest", ["questmap.popup.info"] = "quest",
  gossip = "quest",
  ["dialogueui.detail"] = "quest", ["dialogueui.progress"] = "quest", ["dialogueui.reward"] = "quest",
  ["dialogueui.greeting"] = "quest", ["dialogueui.gossip"] = "quest", ["dialogueui.title"] = "quest",
  itemtext = "book", ["dialogueui.book"] = "book",
  voicepanel = "voicepanel",
  ["tooltip.frozen"] = "tooltip",
}
Marks.PLACE = PLACE

local UNDERLINE = { unknown = { 0.95, 0.25, 0.25, 0.9 }, learning = { 0.1, 0.4, 1, 1 } }
local HIGHLIGHT = { 0.2, 0.9, 0.3, 0.2 }
local STATUS_COLOR = { unknown = "fff24040", learning = "ff4d94ff", known = "ff66dd66", ignored = "ff999999" }
-- the texts that take a score tag: a quest's main block (the tag is the whole quest's), an NPC line, a book page
local SCORED = { ["quest.description"] = true, ["quest.progress"] = true, ["quest.completion"] = true,
  gossip = true, book = true }
local SCORE_MIN = 5 -- a text of fewer counted words takes no tag
local ROOMY = 4 -- a gap between text lines this wide takes the thicker line

local function pick(key, ...)
  return WFJ.OptionsWidgets.pick(WFJ.OptionsText.get(key, ...))
end

local function setting(id) return WFJ.Settings.get(id) end

-- → the cover's place when its setting is on, else nil. A chat word's cover (UI/ChatCards) is the chat place.
function Marks.active(cover)
  local place = cover.marksPlace or (cover.kind == "chat" and "chat") or nil
  if not place or not View.enabled or not setting("marks." .. place) then return nil end
  return place
end

-- ── Drawing ──────────────────────────────────────────────────────────────────

local covers = setmetatable({}, { __mode = "k" }) -- every cover that was laid on a marked place

local function hide(cover)
  for _, t in ipairs(cover.markTex or {}) do t:Hide() end
  if cover.scoreFs then cover.scoreFs:Hide() end
end

-- The smallest space between the bottom of one text line and the top of the line below, from the words' own
-- boxes: the room an underline has, which differs by window and font. → gap (0 or more; ROOMY for a single line)
function Marks.gap(words)
  local bottoms, seen = {}, {}
  for _, w in ipairs(words) do
    for _, r in ipairs(w.rects) do
      local b = math.floor(r.bottom + 0.5)
      if not seen[b] then
        seen[b] = r
        bottoms[#bottoms + 1] = b
      end
    end
  end
  table.sort(bottoms)
  local gap
  for i = 2, #bottoms do
    local lower, upper = seen[bottoms[i - 1]], seen[bottoms[i]]
    local space = upper.bottom - (lower.bottom + lower.height)
    if not gap or space < gap then gap = space end
  end
  return math.max(gap or ROOMY, 0)
end

-- Where an underline sits for that gap: → how far its bottom edge is below the word's box, and its thickness.
-- It lies in the middle of the gap, two screen pixels thick where there is room and one where the lines are tight.
function Marks.line(gap)
  local thick = gap >= ROOMY and 1.5 or 1
  if gap < thick then return thick, thick end -- no room at all: straight under the box
  return gap / 2 + thick / 2, thick
end

local function texture(cover, used, color, left, bottom, width, height, thin)
  local t = cover.markTex[used]
  if not t then
    t = cover:CreateTexture(nil, "BACKGROUND", nil, -1)
    cover.markTex[used] = t
  end
  t:SetColorTexture(color[1], color[2], color[3], color[4])
  t:ClearAllPoints()
  t:SetPoint("BOTTOMLEFT", cover, "BOTTOMLEFT", left, bottom)
  t:SetSize(math.max(width, 1), height)
  -- a line is a whole number of screen pixels, on the pixel grid: a height between two pixels draws one pixel
  -- thick in one place and two in another [verified: forever blizzard_sharedxml/pixelutil.lua:44, :55]
  local pixel = thin and Compat.resolve("PixelUtil")
  if type(pixel) == "table" and pixel.SetPoint and pixel.SetHeight then
    pixel.SetPoint(t, "BOTTOMLEFT", cover, "BOTTOMLEFT", left, bottom)
    pixel.SetHeight(t, height, height >= 1.5 and 2 or 1)
  end
  t:Show()
end

local function scoreColor(share)
  if share >= 95 then return 0.75, 0.55, 1 end
  if share >= 80 then return 0.4, 0.9, 0.4 end
  if share >= 60 then return 1, 0.85, 0.2 end
  return 1, 0.4, 0.4
end

-- The tag over the text's top right corner. Where a window lays a line out in paragraphs, the first one carries it.
local function drawScore(cover)
  if not SCORED[cover.kind] or not setting("marks.score") then return end
  local part = type(cover.recKey) == "string" and cover.recKey:match("%.(%d+)$")
  if part and part ~= "1" then return end
  local lang = cover.english and "en" or "ja"
  local known, counted = WFJ.WordScore.text(lang, cover.kind, cover.id)
  if counted < SCORE_MIN then return end
  local fs = cover.scoreFs
  if not fs then
    fs = cover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("BOTTOMRIGHT", cover, "TOPRIGHT", 0, 1)
    cover.scoreFs = fs
  end
  local share = WFJ.WordScore.percent(known, counted)
  fs:SetText(pick("marks.scoreTag", share))
  WFJ.Font.set(fs, WFJ.Font.PATH, 11, "OUTLINE")
  fs:SetTextColor(scoreColor(share))
  fs:Show()
end

-- Draws a plan on `frame` (a cover, or a chat line's overlay): `words` carry their rectangles in the frame's own
-- coordinates, `plan` says which word takes which mark. Textures are kept on the frame and used again.
function Marks.paint(frame, words, plan)
  local gap = Marks.gap(words)
  local drop, thick = Marks.line(gap)
  frame.markGap = gap
  frame.markTex = frame.markTex or {}
  local used = 0
  for i, w in ipairs(words) do
    local mark = plan[i]
    local color = mark.underline and UNDERLINE[mark.underline]
    for _, r in ipairs(w.rects) do
      if mark.highlight then
        used = used + 1
        texture(frame, used, HIGHLIGHT, r.left, r.bottom, r.width, math.max(r.height, 1))
      end
      if color then
        used = used + 1
        texture(frame, used, color, r.left + 1, r.bottom - drop, r.width - 2, thick, true)
      end
    end
  end
  for i = used + 1, #frame.markTex do frame.markTex[i]:Hide() end
  return used
end

-- `measured`: the words' rectangles when the caller has just measured them (the mouse entering the cover).
local function draw(cover, measured)
  hide(cover)
  if not Marks.active(cover) or not cover.spans then return end
  local words = measured or View.measure(cover)
  if not words then return end
  drawScore(cover)
  local list = {}
  for i, w in ipairs(words) do
    local lang, key = WFJ.WordStatus.keyOf(w)
    list[i] = { first = w.first, last = w.last, lang = lang, key = key }
  end
  local plan = WFJ.WordMarksPlan.plan(cover.text, list, { underline = setting("marks.underline"),
    highlight = setting("marks.highlight"), english = cover.english == true })
  Marks.paint(cover, words, plan)
end

-- Marks are drawn a moment after the text is laid out, once for any number of asks.
local function schedule(cover)
  if cover.markWait then return end
  local after = Compat.resolve("C_Timer.After")
  if type(after) ~= "function" then return end
  cover.markWait = true
  after(0.05, function()
    cover.markWait = nil
    draw(cover)
  end)
end

-- UI/Readings laid `cover` over a line: `rec` is the line's record, `english` true for the client's own English.
function Marks.laid(cover, rec, english)
  cover.marksPlace = PLACE[rec.surface]
  cover.recKey, cover.english = rec.key, english == true
  hide(cover)
  if cover.marksPlace then
    covers[cover] = true
    schedule(cover)
  end
end

function Marks.clear(cover)
  hide(cover)
end

-- the mouse entered the cover and its words were just measured: the marks follow the layout as it is now
function Marks.entered(cover)
  if cover.words then draw(cover, cover.words) else hide(cover) end
end

-- the cover was shown again or changed size
function Marks.moved(cover)
  if cover.marksPlace and cover.spans then schedule(cover) end
end

-- every marked cover on screen is drawn again: a status changed, an import ran, a setting moved
function Marks.redraw()
  for cover in pairs(covers) do
    if cover.spans then schedule(cover) else hide(cover) end
  end
end

-- → what was measured for each marked text on screen (/wfj debug)
function Marks.report()
  local out = {}
  for cover in pairs(covers) do
    if cover.spans and cover.IsVisible and cover:IsVisible() then
      out[#out + 1] = ("%s gap %.2f"):format(tostring(cover.surface), cover.markGap or -1)
    end
  end
  table.sort(out)
  return #out, table.concat(out, ", ")
end

-- ── The clicks and the card ─────────────────────────────────────────────────

local function statusText(status)
  return "|c" .. STATUS_COLOR[status] .. pick("marks." .. status) .. "|r"
end

-- Whether the save click is Shift+click: marking by click is then off, and the card says so.
local function shiftSaves()
  return WFJ.WordSave ~= nil and WFJ.WordSave.choice() == "shift"
end

-- The word card's lines for a word with a status: its status, its place among the game's words, whether it is
-- one to learn next, and how to change it. → text | nil (a name, a place that is off)
function Marks.statusLine(cover, word)
  if not Marks.active(cover) then return nil end
  local lang, key = WFJ.WordStatus.keyOf(word)
  if not lang then return nil end
  local status = WFJ.WordStatus.get(lang, key)
  local line = statusText(status)
  local rank = WFJ.WordFrequency.rank(lang, key)
  if rank then line = line .. " ・ #" .. rank end
  if status == "unknown" and WFJ.WordStatus.learnNext(lang, key) then
    line = line .. " ・ |cff66dd66" .. pick("marks.common") .. "|r"
  end
  return line .. "\n" .. pick(shiftSaves() and "marks.clickOff" or "marks.clickHint")
end

-- A click released on the word it started on, with Shift held: the left button steps the word's status and the
-- right one ignores it or takes that back. → true when the click was a status click
function Marks.click(cover, word, button)
  if not Marks.active(cover) or shiftSaves() or Compat.call("IsShiftKeyDown") ~= true then return false end
  local lang, key = WFJ.WordStatus.keyOf(word)
  if not lang then return false end
  local to
  if button == "RightButton" then
    to = WFJ.WordStatus.ignore(lang, key)
  else
    to = WFJ.WordStatus.step(lang, key)
  end
  if not to then
    print("WFJ: " .. pick("marks.refused"))
    return true
  end
  local known = WFJ.WordStatus.counts(lang)
  print("WFJ: " .. pick("marks.changed", (key:gsub("\t.*", "")), statusText(to), known))
  View.reshow(cover)
  return true
end

local rightDown
local function isRightDown()
  rightDown = rightDown or Compat.resolve("IsMouseButtonDown")
  return type(rightDown) == "function" and rightDown("RightButton") == true
end

-- The right button is read by polling, like the save click: a press that starts on a word and is released on it.
function Marks.pollRight(cover)
  local down = isRightDown()
  if down and not cover.wasRight then
    cover.pressRight = cover.hovered
  elseif not down and cover.wasRight then
    local w = cover.pressRight
    cover.pressRight = nil
    if w and w == cover.hovered then Marks.click(cover, w, "RightButton") end
  end
  cover.wasRight = down
end

-- the mouse arrived: a button already held is the end of a drag, not a click
function Marks.arrived(cover)
  cover.pressRight, cover.wasRight = nil, isRightDown()
end

WFJ.State.on("wordStatus", Marks.redraw)
WFJ.State.on("wordMarks", Marks.redraw)
