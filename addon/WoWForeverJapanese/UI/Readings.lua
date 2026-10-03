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
-- It also refuses text holding `|`: how the client counts bytes around escape sequences is not verified.
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
}

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
  cooldownviewer = true, damagemeter = true, ["deathrecap.tip"] = true, ["editmode.selection"] = true,
  errors = true, gamepad = true,
  ghostframe = true, help = true, hudlabels = true, lossofcontrol = true, majorfactiontoast = true,
  ["questmap.trackerlabels"] = true, ["questmap.trackerobjectives"] = true, questtimer = true, queuestatus = true,
  ["quickjoin.tip"] = true, ["spellbook.menu"] = true, statusnotices = true, tracker = true, unitframes = true,
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

local covers = setmetatable({}, { __mode = "k" }) -- FontString → its cover frame

-- ── The guard ──────────────────────────────────────────────────────────────

local function boundary(text, i)
  if i == #text + 1 then return true end
  local c = text:byte(i)
  return c ~= nil and (c < 0x80 or c >= 0xC0)
end

-- `first`, `last`: a word's first and last byte (inclusive, as Core/Readings returns them). → areas | nil, why
function View.spanAreas(fs, text, first, last, where)
  local right = last + 1
  local why
  if type(text) ~= "string" or text:find("|", 1, true) then
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

-- ── The box ───────────────────────────────────────────────────────────────

local box, boxText
local function ensureBox()
  if box then return box end
  -- the game's tooltip frame and border, like the word card [verified: TooltipBackdropTemplate,
  -- Blizzard_SharedXML/Shared/Tooltip/SharedTooltipTemplates.xml, Blizzard_SharedXML.toc:160–161]
  box = CreateFrame("Frame", nil, Compat.resolve("UIParent"), "TooltipBackdropTemplate")
  box:SetFrameStrata("TOOLTIP")
  -- a template font first, so SetText never meets a FontString without one if the bundled font is refused
  boxText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  boxText:SetPoint("CENTER", box, "CENTER", 0, 0)
  box:Hide()
  return box
end

local TINT = { 1, 0.82, 0, 0.22 } -- gold, low alpha: the word under the mouse

local function clearHover(cover)
  for _, t in ipairs(cover.tints) do t:Hide() end
  cover.hovered = nil
  if box and box.owner == cover then box:Hide(); box.owner = nil end
  if WFJ.ReadingPopup then WFJ.ReadingPopup.hide(cover) end
end

-- The word's gloss when the popup should show it, else nil → the reading-only box.
local function glossFor(word)
  if not View.glossesOn or not WFJ.Glosses or not WFJ.ReadingPopup then return nil end
  return word.card or WFJ.Glosses.get(word.gloss) -- card: a class / race word (Core/Readings.withTokenWords)
end

local function showHover(cover, word)
  clearHover(cover)
  cover.hovered = word
  for i, r in ipairs(word.rects) do
    local t = cover.tints[i]
    if not t then
      t = cover:CreateTexture(nil, "BACKGROUND")
      t:SetColorTexture(TINT[1], TINT[2], TINT[3], TINT[4])
      cover.tints[i] = t
    end
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", cover, "BOTTOMLEFT", r.left, r.bottom)
    t:SetSize(math.max(r.width, 1), math.max(r.height, 1))
    t:Show()
  end
  local _, size = cover.fs:GetFont()
  local r = word.rects[1]
  local gloss = glossFor(word)
  if gloss then
    WFJ.ReadingPopup.show(cover, r.left + r.width / 2, r.bottom + r.height + 2, word, gloss, size)
    return
  end
  local b = ensureBox()
  WFJ.Font.set(boxText, WFJ.Font.PATH, math.max(size or 12, 12), "")
  boxText:SetTextColor(1, 1, 1)
  boxText:SetText(word.reading)
  b:SetSize(boxText:GetStringWidth() + 18, boxText:GetStringHeight() + 12) -- room for the tooltip border
  b:ClearAllPoints()
  b:SetPoint("BOTTOM", cover, "BOTTOMLEFT", r.left + r.width / 2, r.bottom + r.height + 2)
  b.owner = cover
  b:Show()
end

-- ── Hit testing ───────────────────────────────────────────────────────────

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
      words[#words + 1] = { word = sp.word, reading = sp.reading, gloss = sp.gloss, card = sp.card, rects = rects }
    end
  end
  return words
end

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
  local left, bottom = cover:GetLeft(), cover:GetBottom()
  if not cursor or not left or not bottom or not cover.words then return end
  local x, y = cursor()
  local scale = cover:GetEffectiveScale()
  local word = View.wordAt(cover.words, x / scale - left, y / scale - bottom)
  if word ~= cover.hovered then
    if word then showHover(cover, word) else clearHover(cover) end
  end
end

local function onEnter(cover)
  if not View.enabled then return end
  cover.words = measure(cover)
  if cover.words == nil then
    -- the widget shows other text now (dropped outside Render, e.g. a pooled gossip row): this cover is stale.
    -- Hide it so it never takes mouse motion from whatever is laid out there next.
    cover.spans, cover.text = nil, nil
    cover:Hide()
  elseif cover.words[1] then
    cover:SetScript("OnUpdate", onUpdate)
  end
end

local function onLeave(cover)
  cover:SetScript("OnUpdate", nil)
  cover.words = nil
  clearHover(cover)
end

-- → the FontString's cover, made on first need; nil in combat when there is none yet: SetPropagateMouseMotion is a
-- protected call the client blocks in combat [verified: forever blizzard_apidocumentationgenerated/
-- simplescriptregionapidocumentation.lua:689–691, IsProtectedFunction], so a line shown first in combat gets its
-- cover the next time it is attached out of combat.
local function coverFor(fs)
  local cover = covers[fs]
  if cover then return cover end
  local inCombat = Compat.resolve("InCombatLockdown")
  if type(inCombat) == "function" and inCombat() then return nil end
  cover = CreateFrame("Frame", nil, fs:GetParent())
  cover:SetAllPoints(fs)
  cover:SetMouseMotionEnabled(true)
  -- a cover inside a Blizzard ResizeLayout frame must never count toward its size
  -- [verified: forever mainline blizzard_sharedxml/layoutframe.lua:28, :37 (region.ignoreInLayout)]
  cover.ignoreInLayout = true
  -- the text under the cover keeps its own mouse motion, and the cover never takes clicks
  if cover.SetPropagateMouseMotion then cover:SetPropagateMouseMotion(true) end
  cover.fs, cover.tints = fs, {}
  cover:SetScript("OnEnter", onEnter)
  cover:SetScript("OnLeave", onLeave)
  cover:SetScript("OnHide", onLeave)
  covers[fs] = cover
  return cover
end

-- ── Attach / detach (called by UI/Render) ─────────────────────────────────

-- A label FontString sits in a window when its parent is a plain frame: not a button (a Button's or a
-- CheckButton's text: tabs and list rows included) and not a protected frame (a cover of ours is never laid inside
-- one). A Button's text reaches Labels as a ButtonText adapter and a menu entry as a Labels.menuText adapter: neither
-- has CalculateScreenAreaFromCharacterSpan, so `eligible` refuses them before this runs. Tooltips are refused by
-- surface (NON_WINDOW). [verified: forever mainline blizzard_gamepadsmartnavigation/utility.lua:197
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

-- the cover of a record's FontString, own or an adapter's (whatever text that FontString holds now)
local function coverOf(rec)
  local fs = rec and rec.fs
  if type(fs) == "table" and type(fs.spanRegion) == "function" then fs = fs:spanRegion() end
  return fs and covers[fs]
end

local function eligible(rec)
  local m, fs = rec.meta, region(rec)
  if not m or type(fs) ~= "table" or type(fs.CalculateScreenAreaFromCharacterSpan) ~= "function"
      or type(rec.applied) ~= "string" then
    return false
  end
  -- a label in a window (a Button's text or a menu entry is an adapter without the span call: refused above)
  if m.kind == "ui" then return not View.nonWindow(rec.surface) and inWindow(fs) end
  if not View.SURFACES[rec.surface] then return false end
  return rec.surface ~= "gossip" or rec.key == "greeting" -- gossip option rows are buttons
end

function View.detach(rec)
  local cover = coverOf(rec)
  if not cover then return end
  cover.spans, cover.text = nil, nil
  onLeave(cover)
  cover:Hide()
end

-- → true when the record's FontString now takes readings
function View.attach(rec)
  if not eligible(rec) or rec.applied:find("|", 1, true) then
    View.detach(rec)
    return false
  end
  local listed = WFJ.Readings.lookup(rec.meta.kind, rec.meta.id, rec.applied)
  -- a window label takes a cover only for its own word list; the class / race words are for prose
  if rec.meta.kind == "ui" and not (listed and listed[1]) then
    View.detach(rec)
    return false
  end
  local spans = rec.meta.kind == "ui" and listed or WFJ.Readings.withTokenWords(listed or {}, rec.applied)
  if not spans or not spans[1] then
    View.detach(rec)
    return false
  end
  local fs = region(rec)
  local cover = coverFor(fs)
  if not cover then return false end
  -- QuestInfo_Display moves its FontStrings between the quest window's panels, the quest map details pane and
  -- its popup (UI/QuestMap.lua: re-parented [verified: mainline/questinfo.lua:99–110]); the cover follows, or it
  -- would stay under a hidden parent and never see the mouse.
  local parent = fs:GetParent()
  if cover:GetParent() ~= parent then
    cover:SetParent(parent)
    cover:ClearAllPoints()
    cover:SetAllPoints(fs)
  end
  onLeave(cover)
  cover.text, cover.spans = rec.applied, spans
  cover.where = tostring(rec.meta.kind) .. " " .. tostring(rec.meta.id)
  cover:SetShown(View.enabled)
  View.attached = View.attached + 1
  -- a re-attach under a resting mouse (the pane redisplayed on QUEST_LOG_UPDATE) gets no new OnEnter: start again
  if View.enabled and cover.IsMouseOver and cover:IsMouseOver() then onEnter(cover) end
  return true
end

-- The setting (State event "readings"): off hides every cover at once; on shows the attached ones again.
function View.setEnabled(v)
  View.enabled = v and true or false
  for _, cover in pairs(covers) do
    if not View.enabled then onLeave(cover) end
    cover:SetShown(View.enabled and cover.spans ~= nil)
  end
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
