-- UI/Readings.lua: the word-reading box (ADR-036, ADR-041, docs/systems/readings.md). Pointing at a Japanese word
-- in quest or gossip prose, or in a plain-text label in a window, shows its reading (少し → すこし) in a small box
-- above it. Nothing is drawn until the mouse is on a word, and never while English is showing. When the word carries
-- a meaning (Core/Glosses) and `readings.glosses` is on, UI/ReadingPopup's card shows instead. A kana word is listed
-- for the card only, so without a meaning it is not hoverable.
--
-- Render calls attach(rec) after it applies Japanese and detach(rec) when it restores, releases or drops a record.
-- attach lays a mouse-motion-only COVER frame over the FontString and remembers the text it was attached for. Gossip
-- rows are pooled and dropped without Render, so a cover can outlive its text: on enter it checks the FontString
-- still shows that text, so a missed detach never shows a wrong reading.
--
-- Word rectangles come from FontString:CalculateScreenAreaFromCharacterSpan(left, right), relative to the
-- FontString's BOTTOMLEFT (blizzard_sharedxml/scrollingmessageframe.lua:496–503), computed on each mouse enter so
-- layout and scroll are current. Indices are UTF-8 BYTES, right end EXCLUSIVE (scrollingmessageframe.lua:451–467).
-- A span that splits a character is not a Lua error: the client exits. So
-- spanAreas is the ONLY caller of that function (a test enforces it) and refuses any index off a character boundary.
-- spanAreas also refuses text holding `|`: how the client counts bytes around escape sequences is verified for one
-- kind of text only, a chat line, whose indices count the line as it is, escape sequences included, as the client's
-- own text selection counts them there [verified: forever blizzard_sharedxml/scrollingmessageframe.lua:486–503,
-- indices into visibleLine:GetText(); seen in game on chat lines holding player links and colour codes]. A chat
-- line goes through chatSpanAreas, which keeps every other check.
local _, WFJ = ...
local View = {}
WFJ.ReadingView = View

-- UIParent and GetCursorPosition are read through Compat.resolve when needed (as UI/AddonListButton reads UIParent):
-- both are on every client, and this module owns no window, so it declares no Compat surface.
local Compat = WFJ.Compat

-- Surfaces whose prose FontStrings take readings: the quest window's panels, the quest map's details pane and its
-- popup, the quest greeting, the gossip window's greeting row, and a plain-text book / letter page (ADR-044),
-- drawn in UI/ItemText's own FontString (a SimpleHTML cannot say where a word sits: an HTML page takes none). Never a
-- tooltip (it cannot be hovered), a list row, the tracker or a button.
View.SURFACES = {
  ["questframe.detail"] = true, ["questframe.reward"] = true, ["questframe.progress"] = true,
  ["questframe.greeting"] = true, ["questmap.info"] = true, ["questmap.popup.info"] = true, gossip = true,
  itemtext = true,
  voicepanel = true, -- the voice panel's text and its whole-text window (UI/VoicePanelText)
  study = true, -- the study card's sentence (UI/StudyWindow passes the words, minus the one being tested)
  -- Dialogue UI's windows (UI/DialogueUI, UI/DialogueUIBook pass each paragraph's share of the line's words)
  ["dialogueui.detail"] = true, ["dialogueui.progress"] = true, ["dialogueui.reward"] = true,
  ["dialogueui.greeting"] = true, ["dialogueui.gossip"] = true, ["dialogueui.book"] = true,
  ["dialogueui.title"] = true, -- the quest title in its page header, as the client's quest window's title
}

-- Surfaces the addon draws itself as a copy of text shown elsewhere, each line carrying its own words (`rec.spans`)
-- and the kind and id of the line it copies: the frozen tooltip (UI/TooltipFreeze). A line there takes cards
-- whatever its kind, a window word among them: the copy is a frame of ours the mouse can rest on, which the
-- tooltip it copies is not.
View.COPIES = { ["tooltip.frozen"] = true }

-- The frame a box over `anchor` belongs under: UIParent, unless the text sits in a window outside it (Dialogue UI
-- draws its windows with no parent and fades UIParent out while they show, which would hide a box under UIParent
-- with it). → that window's top frame, or UIParent
function View.host(anchor)
  local ui = Compat.resolve("UIParent")
  if not ui then return nil end
  local top, f = nil, anchor
  for _ = 1, 64 do
    if type(f.GetParent) ~= "function" then break end
    local ok, parent = pcall(f.GetParent, f)
    if not ok or type(parent) ~= "table" then break end
    if parent == ui then return ui end
    top, f = parent, parent
  end
  return top or ui
end

-- `frame` under the host of `anchor`, at the tooltip level whichever parent it has.
function View.reparent(frame, anchor)
  if type(frame.GetParent) ~= "function" or type(frame.SetParent) ~= "function" then return end
  local host = View.host(anchor)
  if host and frame:GetParent() ~= host then
    frame:SetParent(host)
    frame:SetFrameStrata("TOOLTIP")
  end
end

-- A label (a `ui` record, UI/Labels) takes readings on every surface EXCEPT these: HUD text, toasts, banners, the
-- tracker, error / combat text and tooltips are not windows (ADR-041). A name matches itself and every surface under
-- it ("alerts" covers "alerts.<anything>"). A surface naming "tooltip" is a tooltip (UI/Tooltip's "tooltip.<frame>",
-- the windows' "<window>.tooltip"); "help" is UI/HelpTooltip's (and MicroMenu's records on it). The surfaces whose
-- labels are GameTooltip lines under another name are listed by name (death recap, quick join, the guild reward
-- tooltip, the WoW Token lines), and UI/TooltipLines adds every surface it follows (View.tooltipSurface, that surface
-- only). Buttons, tabs and menus are refused by the widget itself (below). A new surface is a window unless it is
-- listed here: tests/python/test_readings.py classifies every surface the addon registers, so a new one fails there
-- until it is classified.
View.NON_WINDOW = {
  alerts = true, ["auctionhouse.token"] = true, bnettoast = true, bossbanner = true, castingbar = true,
  ["cinematic.subtitles"] = true, -- subtitle lines over a cinematic
  chattabs = true, combatfeedback = true, combattext = true, ["communities.benefits.rewardtip"] = true,
  cooldownviewer = true, damagemeter = true, ["deathrecap.tip"] = true,
  errors = true, gamepad = true,
  ghostframe = true, help = true, hudlabels = true, lossofcontrol = true, majorfactiontoast = true,
  ["minimap.zone"] = true, -- the zone's name over the minimap
  npe = true, -- the new player tutorial's on-screen prompts
  ["questmap.trackerlabels"] = true, ["questmap.trackerobjectives"] = true, questtimer = true, queuestatus = true,
  ["quickjoin.tip"] = true, statusnotices = true, tracker = true, unitframes = true,
  widgets = true, -- the UI widgets' HUD lines
  zonetext = true,
}

-- The surfaces UI/TooltipLines follows: that exact surface only, never the surfaces under its name.
local tooltipSurfaces = {}
function View.tooltipSurface(surface)
  if type(surface) == "string" then tooltipSurfaces[surface] = true end
end

-- → true when `surface` (or a surface it sits under) is in NON_WINDOW, or names or is a tooltip
function View.nonWindow(surface)
  if type(surface) ~= "string" then return true end
  if tooltipSurfaces[surface] or surface:find("tooltip", 1, true) then return true end
  local prefix = ""
  for part in surface:gmatch("[^.]+") do
    prefix = prefix == "" and part or (prefix .. "." .. part)
    if View.NON_WINDOW[prefix] then return true end
  end
  return false
end

View.enabled = true
View.glossesOn = true -- `readings.glosses`
View.refused = 0 -- spans the guard refused this session (/wfj debug)
View.refusedAt = nil -- the first refused call's "kind id first..right"
View.attached = 0 -- attaches this session (/wfj debug)

local covers = setmetatable({}, { __mode = "k" }) -- FontString → its cover: { frame, fs, tints, … }

-- ── The guard ──────────────────────────────────────────────────────────────

local function boundary(text, i)
  if i == #text + 1 then return true end
  local c = text:byte(i)
  return c ~= nil and (c < 0x80 or c >= 0xC0)
end

-- `first`, `last`: a word's first and last byte (inclusive, as Core/Readings returns them). `escapes`: the text may
-- hold escape sequences its indices count. → areas | nil, why
local function areasOf(fs, text, first, last, where, escapes)
  local right = last + 1
  local why
  if type(text) ~= "string" then
    why = "no text"
  elseif not escapes and text:find("|", 1, true) then
    why = "text holds an escape sequence"
  elseif first < 1 or right <= first or right > #text + 1 then
    why = "span out of range"
  elseif not boundary(text, first) or not boundary(text, right) then
    why = "span splits a character"
  end
  if why then
    View.refused = View.refused + 1
    View.refusedAt = View.refusedAt or ((where or "?") .. " " .. first .. ".." .. right .. ": " .. why)
    return nil, why
  end
  local ok, areas = pcall(fs.CalculateScreenAreaFromCharacterSpan, fs, first, right)
  if not ok or type(areas) ~= "table" then return nil, "no areas" end
  return areas
end

function View.spanAreas(fs, text, first, last, where)
  return areasOf(fs, text, first, last, where, false)
end

-- A word's areas on a visible chat line (UI/ChatCards): the one kind of text whose escape sequences are counted.
function View.chatSpanAreas(line, text, first, last)
  return areasOf(line, text, first, last, "chat", true)
end

-- ── The box ───────────────────────────────────────────────────────────────

-- A solid fill under a box's tooltip border: the border's own centre lets the text behind show through, which makes
-- a card over other text hard to read. Drawn on the box itself, so it sits under the border frame.
function View.solid(frame)
  local fill = frame:CreateTexture(nil, "BACKGROUND")
  fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
  fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
  fill:SetColorTexture(0.04, 0.04, 0.07, 1)
end

local box, boxText
local function ensureBox()
  if box then return box end
  -- the game's tooltip frame and border, like the word card [verified: TooltipBackdropTemplate,
  -- Blizzard_SharedXML/Shared/Tooltip/SharedTooltipTemplates.xml, Blizzard_SharedXML.toc:160–161]
  box = CreateFrame("Frame", nil, Compat.resolve("UIParent"), "TooltipBackdropTemplate")
  box:SetFrameStrata("TOOLTIP")
  View.solid(box)
  -- a template font first, so SetText never meets a FontString without one if the bundled font is refused
  boxText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  boxText:SetPoint("CENTER", box, "CENTER", 0, 0)
  box:Hide()
  return box
end

local TINT = { 1, 0.82, 0, 0.22 } -- gold, low alpha: the word under the mouse

local clearHover, showHover

function clearHover(cover)
  for _, t in ipairs(cover.tints) do t:Hide() end
  cover.hovered = nil
  if box and box.owner == cover then box:Hide(); box.owner = nil end
  if WFJ.ReadingPopup then WFJ.ReadingPopup.hide(cover.frame) end
end

-- The word's gloss when the popup should show it, else nil → the reading-only box.
local function glossFor(word)
  if not View.glossesOn or not WFJ.Glosses or not WFJ.ReadingPopup then return nil end
  return word.card or WFJ.Glosses.get(word.gloss) -- card: a class / race word (Core/Readings.withTokenWords)
end

function showHover(cover, word)
  clearHover(cover)
  cover.hovered = word
  for i, r in ipairs(word.rects) do
    local t = cover.tints[i]
    if not t then
      t = cover.frame:CreateTexture(nil, "BACKGROUND")
      t:SetColorTexture(TINT[1], TINT[2], TINT[3], TINT[4])
      cover.tints[i] = t
    end
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", cover.frame, "BOTTOMLEFT", r.left, r.bottom)
    t:SetSize(math.max(r.width, 1), math.max(r.height, 1))
    t:Show()
  end
  local _, size = cover.fs:GetFont()
  local r = word.rects[1]
  local gloss = glossFor(word)
  if gloss then
    -- a name is not a word to save: its card carries no hint about the save click
    local hint = not word.name and View.hint() or nil
    -- a word with a status carries it on its card, above the save hint (UI/WordMarks)
    local status = WFJ.WordMarks and WFJ.WordMarks.statusLine(cover, word)
    if status then hint = hint and (status .. "\n" .. hint) or status end
    WFJ.ReadingPopup.show(cover.frame, r.left + r.width / 2, r.bottom + r.height + 2, word, gloss, size, hint)
    return
  end
  local b = ensureBox()
  WFJ.Font.set(boxText, WFJ.Font.PATH, math.max(WFJ.Font.size(size) or 12, 12), "")
  boxText:SetTextColor(1, 1, 1)
  boxText:SetText(word.reading)
  b:SetSize(boxText:GetStringWidth() + 18, boxText:GetStringHeight() + 12) -- room for the tooltip border
  View.reparent(b, cover.frame)
  b:ClearAllPoints()
  b:SetPoint("BOTTOM", cover.frame, "BOTTOMLEFT", r.left + r.width / 2, r.bottom + r.height + 2)
  b.owner = cover
  b:Show()
end

-- ── Hit testing ───────────────────────────────────────────────────────────

-- For a caller that owns its cover and finds its own word (UI/ChatCards, on a chat line): `cover` carries `fs` and
-- `tints`; `word` carries `rects` and what a card needs (`word`, `reading`, and `card` or `gloss`).
View.showHover, View.clearHover = showHover, clearHover

-- The words' rectangles, now: nil when the FontString no longer shows the text the cover was attached for.
local function measure(cover)
  local fs = cover.fs
  if not cover.spans or not fs:IsVisible() or fs:GetText() ~= cover.text then return nil end
  local words = {}
  for _, sp in ipairs(cover.spans) do
    -- a kana word (its reading is itself) is listed for the popup only: with no meaning to show, or with
    -- meanings off, it is not a hover target
    local skip = sp.word == sp.reading and not glossFor(sp)
    local areas = not skip and View.spanAreas(fs, cover.text, sp.first, sp.last, cover.where)
    if areas and areas[1] then
      local rects = {}
      for _, a in ipairs(areas) do
        rects[#rects + 1] = { left = a.left, bottom = a.bottom, width = a.width, height = a.height }
      end
      words[#words + 1] = { word = sp.word, reading = sp.reading, gloss = sp.gloss, card = sp.card, rects = rects,
        first = sp.first, last = sp.last, name = sp.name }
    end
  end
  return words
end

View.measure = measure -- UI/WordMarks draws a mark under each word from the same rectangles

-- The word under (x, y), in the cover's own coordinates (origin: its BOTTOMLEFT).
function View.wordAt(words, x, y)
  for _, w in ipairs(words) do
    for _, r in ipairs(w.rects) do
      if x >= r.left and x <= r.left + r.width and y >= r.bottom and y <= r.bottom + r.height then return w end
    end
  end
  return nil
end

local function onUpdate(cover)
  local cursor = Compat.resolve("GetCursorPosition")
  local left, bottom = cover.frame:GetLeft(), cover.frame:GetBottom()
  if not cursor or not left or not bottom or not cover.words then return end
  local x, y = cursor()
  local scale = cover.frame:GetEffectiveScale()
  local word = View.wordAt(cover.words, x / scale - left, y / scale - bottom)
  if word ~= cover.hovered then
    if word then showHover(cover, word) else clearHover(cover) end
  end
  View.poll(cover)
end

local function onEnter(cover)
  if not View.enabled then return end
  cover.pressWord, cover.wasDown = nil, View.buttonDown()
  cover.words = measure(cover)
  if WFJ.WordMarks then
    WFJ.WordMarks.arrived(cover)
    WFJ.WordMarks.entered(cover)
  end
  if cover.words == nil then
    -- the widget shows other text now (dropped outside Render, e.g. a pooled gossip row): this cover is stale.
    -- Hide it so it never takes mouse motion from whatever is laid out there next.
    cover.spans, cover.text = nil, nil
    cover.frame:Hide()
  elseif cover.words[1] then
    cover.frame:SetScript("OnUpdate", function() onUpdate(cover) end)
  end
end

local function onLeave(cover)
  cover.frame:SetScript("OnUpdate", nil)
  cover.words, cover.pressWord = nil, nil
  clearHover(cover)
end

-- → the FontString's cover, made on first need; nil in combat when there is none yet: SetPropagateMouseMotion is a
-- protected call the client blocks in combat [verified: forever blizzard_apidocumentationgenerated/
-- simplescriptregionapidocumentation.lua:689–691, IsProtectedFunction], so a line shown first in combat gets its
-- cover the next time it is attached out of combat.
-- A client layout frame reads fields off every child it lays out (ignoreInLayout, layoutIndex) and sizes itself
-- around the shown ones [verified: forever blizzard_sharedxml/layoutframe.lua:33-41]. A field of ours there is a value
-- written by an addon that the client's own code reads: the layout runs tainted from that read on, and so does
-- whatever the client does next in the same pass. So a cover carries no field the client looks for, and it is never a
-- child of a layout frame: it goes under the nearest ancestor that is not one, still laid over the text.
local function isLayout(frame)
  if type(frame) ~= "table" or type(frame.IsLayoutFrame) ~= "function" then return false end
  local ok, yes = pcall(frame.IsLayoutFrame, frame)
  return ok and yes == true
end

local function hostOf(fs)
  local parent = fs:GetParent()
  local host = parent
  while isLayout(host) and type(host.GetParent) == "function" and host:GetParent() do host = host:GetParent() end
  return host or parent, parent
end

-- A cover under another frame than its text's parent no longer hides with that parent, so it follows the parent's
-- show and hide (one pair of script hooks per parent; the cover found through its text's current parent).
local followed = setmetatable({}, { __mode = "k" }) -- a text's parent → { cover → true }
local function follow(cover, parent)
  if cover.following == parent then return end
  if cover.following and followed[cover.following] then followed[cover.following][cover] = nil end
  cover.following = parent
  if not parent then return end
  local set = followed[parent]
  if not set then
    set = setmetatable({}, { __mode = "k" })
    followed[parent] = set
    if type(parent.HookScript) == "function" then
      parent:HookScript("OnHide", function()
        for c in pairs(set) do c.frame:Hide() end
      end)
      parent:HookScript("OnShow", function()
        for c in pairs(set) do c.frame:SetShown(View.enabled and c.text ~= nil) end
      end)
    end
  end
  set[cover] = true
end

-- Puts the cover under the frame its text needs it under. → nothing
local function place(cover, fs)
  local host, parent = hostOf(fs)
  if cover.frame:GetParent() ~= host then
    cover.frame:SetParent(host)
    cover.frame:ClearAllPoints()
    cover.frame:SetAllPoints(fs)
  end
  if host ~= parent then
    -- above the layout frame's own children, which the cover no longer sits among
    if type(parent.GetFrameLevel) == "function" then cover.frame:SetFrameLevel(parent:GetFrameLevel() + 2) end
    follow(cover, parent)
  else
    follow(cover, nil)
  end
end

local function coverFor(fs)
  local cover = covers[fs]
  if cover then return cover end
  local inCombat = Compat.resolve("InCombatLockdown")
  if type(inCombat) == "function" and inCombat() then return nil end
  -- the cover is this table, and its frame carries no field: a frame inside a client frame is read by the client's
  -- own code (a layout asks each child for its fields), and a value the addon wrote there taints that code's run
  local frame = CreateFrame("Frame", nil, (hostOf(fs)))
  cover = { frame = frame, fs = fs, tints = {} }
  frame:SetAllPoints(fs)
  frame:SetMouseMotionEnabled(true)
  place(cover, fs)
  -- the text under the cover keeps its own mouse motion, and the cover never takes clicks: its clicks are off and
  -- passed on to its parent, the frame the text sits in, so a search box behind its placeholder ("Search") still
  -- takes the click. Both calls are protected in combat, like the motion one, and a cover is only made out of combat
  -- [verified: forever blizzard_apidocumentationgenerated/simplescriptregionapidocumentation.lua:631, :677]. The save
  -- click is read by polling the button (View.poll), never from a click event, so it keeps working.
  if frame.SetPropagateMouseMotion then frame:SetPropagateMouseMotion(true) end
  if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
  if frame.SetPropagateMouseClicks then frame:SetPropagateMouseClicks(true) end
  frame:SetScript("OnEnter", function() onEnter(cover) end)
  frame:SetScript("OnLeave", function() onLeave(cover) end)
  frame:SetScript("OnHide", function() onLeave(cover) end)
  -- the word status marks follow the text when it is shown again or laid out at another size
  local function moved() if WFJ.WordMarks then WFJ.WordMarks.moved(cover) end end
  frame:SetScript("OnShow", moved)
  frame:SetScript("OnSizeChanged", moved)
  covers[fs] = cover
  return cover
end

-- ── Attach / detach (called by UI/Render) ─────────────────────────────────

-- A label FontString sits in a window when its parent is a plain frame: not a button (a Button's or a
-- CheckButton's text: tabs and list rows included) and not a protected frame (a cover of ours is never laid inside
-- one). A Button's text reaches Labels as a ButtonText adapter and a menu entry as a Labels.menuText adapter: neither
-- has CalculateScreenAreaFromCharacterSpan, so `eligible` refuses them before this runs. Tooltips are refused by
-- surface (NON_WINDOW). [verified: forever mainline blizzard_gamepadsmartnavigation/utility.lua:264
-- (frame:IsObjectType("Button")), blizzard_restrictedaddonenvironment/securehandlers.lua:268 (frame:IsProtected())]
local function inWindow(fs)
  local ok, parent = pcall(fs.GetParent, fs)
  if not ok or type(parent) ~= "table" then return false end
  if type(parent.IsObjectType) == "function" and parent:IsObjectType("Button") then return false end
  if type(parent.IsProtected) == "function" and parent:IsProtected() then return false end
  return true
end

-- The FontString a record's words sit in: its own, or the one an adapter draws the text in
-- (UI/ItemText's page:spanRegion), and only while that FontString holds exactly the text the record applied.
local function region(rec)
  local fs = rec and rec.fs
  if type(fs) ~= "table" or type(fs.spanRegion) ~= "function" then return fs end
  local r = fs:spanRegion()
  if type(r) ~= "table" or type(r.GetText) ~= "function" or r:GetText() ~= rec.applied then return nil end
  return r
end

-- → the cover laid on `fs`, or nil: its state, and its frame under `frame`
function View.coverAt(fs) return covers[fs] end

-- Every cover and the text it lies on, for a check of the running game: visit(fs, frame, inUse, cover) per cover,
-- `inUse` while the text is the addon's and takes word cards, `cover` its state to read (the text, the spans, the
-- marks drawn). → whether the popup dictionary is switched on
function WFJ_ReadingCovers(visit)
  for fs, cover in pairs(covers) do visit(fs, cover.frame, cover.spans ~= nil, cover) end
  return View.enabled
end

-- the cover of a record's FontString, own or an adapter's (whatever text that FontString holds now)
local function coverOf(rec)
  local fs = rec and rec.fs
  if type(fs) == "table" and type(fs.spanRegion) == "function" then fs = fs:spanRegion() end
  return fs and covers[fs]
end

-- Whether the record's surface takes word cards at all, in `fs`.
local function takesCards(rec, fs)
  local m = rec.meta
  if not m or type(fs) ~= "table" or type(fs.CalculateScreenAreaFromCharacterSpan) ~= "function" then return false end
  -- a copy (the frozen tooltip) brings the line's words, or a name line its name card
  if View.COPIES[rec.surface] then return rec.spans ~= nil or type(rec.nameCard) == "table" end
  -- a label in a window (a Button's text or a menu entry is an adapter without the span call: refused above); a
  -- widget that holds only a name (a title bar) is one too
  if m.kind == "ui" or m.kind == "name" then return not View.nonWindow(rec.surface) and inWindow(fs) end
  if not View.SURFACES[rec.surface] then return false end
  return rec.surface ~= "gossip" or rec.key == "greeting" -- gossip option rows are buttons
end

local function eligible(rec)
  return type(rec.applied) == "string" and takesCards(rec, region(rec))
end

-- Lays the record's cover over `fs` for `text` and its word spans. → true, or false in combat with no cover yet
local function lay(rec, fs, text, spans, english)
  local cover = coverFor(fs)
  if not cover then return false end
  -- QuestInfo_Display moves its FontStrings between the quest window's panels, the quest map details pane and
  -- its popup (UI/QuestMap.lua: re-parented [verified: mainline/questinfo.lua:99–110]); the cover follows, or it
  -- would stay under a hidden parent and never see the mouse.
  place(cover, fs)
  onLeave(cover)
  cover.text, cover.spans = text, spans
  cover.where = tostring(rec.meta.kind) .. " " .. tostring(rec.meta.id)
  cover.kind, cover.id, cover.surface = rec.meta.kind, rec.meta.id, rec.surface
  -- a cover that follows a hidden parent stays hidden until that parent shows
  local parent = cover.following
  cover.frame:SetShown(View.enabled and (parent == nil or type(parent.IsShown) ~= "function" or parent:IsShown()))
  if WFJ.WordMarks then WFJ.WordMarks.laid(cover, rec, english) end
  View.attached = View.attached + 1
  -- a re-attach under a resting mouse (the pane redisplayed on QUEST_LOG_UPDATE) gets no new OnEnter: start again
  if View.enabled and cover.frame.IsMouseOver and cover.frame:IsMouseOver() then onEnter(cover) end
  return true
end

function View.detach(rec)
  local cover = coverOf(rec)
  if not cover then return end
  cover.spans, cover.text = nil, nil
  if WFJ.WordMarks then WFJ.WordMarks.clear(cover) end
  onLeave(cover)
  cover.frame:Hide()
end

-- → true when the record's FontString now takes readings
function View.attach(rec)
  if not eligible(rec) or rec.applied:find("|", 1, true) then
    View.detach(rec)
    return false
  end
  -- a widget that holds only a name: one card over the whole of it, the name's reading and its English name
  if rec.meta.kind == "name" then
    local card = rec.nameCard
    if type(card) ~= "table" then
      View.detach(rec)
      return false
    end
    -- the card sits on the name itself: a colour code before it or numbers after it are no part of it. A name
    -- written before it on the same widget (a recipe heading's skill, "マイニング: ") takes its own card too.
    local cards = { { ja = card.ja or rec.applied, english = card.english, reading = card.reading } }
    for _, n in ipairs(type(rec.names) == "table" and rec.names or {}) do cards[#cards + 1] = n end
    local spans = WFJ.Readings.withNames({}, rec.applied, cards)
    return lay(rec, region(rec), rec.applied, spans)
  end
  -- rec.spans: words already located by the caller (the voice panel shows one sentence of a line whose word list is
  -- written for the whole line, so it locates them in the whole line and passes the sentence's share)
  local listed = rec.spans or WFJ.Readings.lookup(rec.meta.kind, rec.meta.id, rec.applied)
  -- a window label takes a cover only for its own word list or a name written into it; the class / race words
  -- are for prose
  local named = type(rec.names) == "table" and rec.names[1] ~= nil
  if rec.meta.kind == "ui" and not (listed and listed[1]) and not named then
    View.detach(rec)
    return false
  end
  -- the names written into the line in Japanese take their cards first, so no word anchors inside one
  local spans = WFJ.Readings.withNames(listed or {}, rec.applied, rec.names)
  if rec.meta.kind ~= "ui" then spans = WFJ.Readings.withTokenWords(spans, rec.applied, rec.exclude) end
  if not spans or not spans[1] then
    View.detach(rec)
    return false
  end
  return lay(rec, region(rec), rec.applied, spans)
end

-- English first: the line is the client's own English, untouched, and its English words take the cards. A
-- FontString the client draws the text in itself, or a book page's own (its plain-text English, drawn there for
-- this), holding no escape sequence. → true when the record's FontString now takes English cards
function View.attachEnglish(rec)
  local fs = rec and rec.fs
  -- an adapter's own FontString holds our Japanese; one that can also draw the client's English there says so
  -- (a book page: UI/ItemText's page:englishRegion)
  if type(fs) == "table" and type(fs.spanRegion) == "function" then
    fs = type(fs.englishRegion) == "function" and fs:englishRegion() or nil
  end
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" or not takesCards(rec, fs) then
    View.detach(rec)
    return false
  end
  local text = fs:GetText()
  if type(text) ~= "string" or text == "" or text:find("|", 1, true) then
    View.detach(rec)
    return false
  end
  local spans = WFJ.Readings.englishLookup(rec.meta.kind, rec.meta.id, text)
  if not spans or not spans[1] then
    View.detach(rec)
    return false
  end
  return lay(rec, fs, text, spans, true)
end

-- ── The save click (UI/WordSave, ADR-069) ────────────────────────────────
-- The cover never takes clicks (a click-enabled frame would stand between the player and the window under the text),
-- so the save click is read by polling the left button in the OnUpdate that already runs while the mouse is over the
-- cover: a press that starts on a word and is released on the same word. A press that started before the mouse
-- arrived (the end of a drag) is not a click. UI/WordSave decides whether the modifiers match and saves.

local isDown -- IsMouseButtonDown, resolved once: it is read every frame while the mouse is over a cover
function View.buttonDown()
  isDown = isDown or Compat.resolve("IsMouseButtonDown")
  return type(isDown) == "function" and isDown("LeftButton") == true
end

function View.poll(cover)
  local save, marks = WFJ.WordSave, WFJ.WordMarks
  local saving = save ~= nil and save.choice() ~= "off"
  -- a place with word status marks on also reads the status clicks (UI/WordMarks): Shift held with either button
  local marking = marks ~= nil and marks.active(cover) ~= nil
  if not saving and not marking then return end
  if marking then marks.pollRight(cover) end
  local down = View.buttonDown()
  if down and not cover.wasDown then
    cover.pressWord = cover.hovered
    -- where the cover was at the press: a frame dragged by its text (the voice panel) moves the cover with it, and a
    -- drag is not a click
    cover.pressLeft, cover.pressBottom = cover.frame:GetLeft(), cover.frame:GetBottom()
  elseif not down and cover.wasDown then
    local w = cover.pressWord
    cover.pressWord = nil
    -- a name's card is never saved: a name is not a word to study
    if w and not w.name and w == cover.hovered and cover.frame:GetLeft() == cover.pressLeft
        and cover.frame:GetBottom() == cover.pressBottom then
      if not (marking and marks.click(cover, w, "LeftButton")) and saving then save.release(cover, w) end
    end
  end
  cover.wasDown = down
end

-- The card's hint line (how to save a word), until the player has saved one.
function View.hint()
  return WFJ.WordSave and WFJ.WordSave.hint() or nil
end

-- A saved word's tint flashes once, then settles back.
function View.flash(cover)
  for _, t in ipairs(cover.tints) do
    if t:IsShown() then t:SetColorTexture(TINT[1], TINT[2], TINT[3], 0.55) end
  end
  local after = Compat.resolve("C_Timer.After")
  if type(after) ~= "function" then return end
  after(0.25, function()
    for _, t in ipairs(cover.tints) do t:SetColorTexture(TINT[1], TINT[2], TINT[3], TINT[4]) end
  end)
end

-- Hides the reading box or the card over a cover; the tint stays (UI/WordSave's screenshot shows the word).
function View.hideCard(cover)
  if box and box.owner == cover then box:Hide() end
  if WFJ.ReadingPopup then WFJ.ReadingPopup.hide(cover.frame) end
end

-- Shows the hovered word's box or card again.
function View.reshow(cover)
  local w = cover.hovered
  if w and cover.words then
    for _, t in ipairs(cover.tints) do t:Hide() end
    cover.hovered = nil
    showHover(cover, w)
  end
end

-- The setting (State event "readings"): off hides every cover at once; on shows the attached ones again.
function View.setEnabled(v)
  View.enabled = v and true or false
  for _, cover in pairs(covers) do
    if not View.enabled then onLeave(cover) end
    cover.frame:SetShown(View.enabled and cover.spans ~= nil)
  end
  if WFJ.WordMarks then WFJ.WordMarks.redraw() end
end

WFJ.State.on("readings", function(v) View.setEnabled(v) end)
-- Meanings off → the reading-only box; a card already open is closed, and a cover the mouse is on is measured again
-- (kana words are hover targets only while meanings are on), so the next move shows the right thing.
WFJ.State.on("glosses", function(v)
  View.glossesOn = v and true or false
  for _, cover in pairs(covers) do
    if cover.hovered then clearHover(cover) end
    if cover.words then cover.words = measure(cover) end
  end
end)
