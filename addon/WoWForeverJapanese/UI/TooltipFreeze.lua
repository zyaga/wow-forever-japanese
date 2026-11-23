-- UI/TooltipFreeze.lua: the frozen tooltip (ADR-104). A key press while a tooltip shows draws a copy of it in the
-- same place (same size, lines, fonts and colours), with the comparison tooltips beside it. The copy stays after
-- the game hides its own tooltip, so the mouse can go onto it, and its Japanese lines take word cards
-- (UI/Readings). The key again, or Esc, closes it; the key over another tooltip makes the copy that one's.
--
-- The game's own tooltip is never held open: whatever the mouse was on hides it on leave, and standing in the way
-- of that would run addon code inside the action buttons' own handlers.
--
-- Which words a line takes comes from the record the addon kept when it wrote that line's Japanese
-- (Core/SurfaceState: the line's kind, id and the exact text written). The records go when the game's tooltip
-- hides, so they are read at the key press. A line the client has rewritten since, a line written in combat (no
-- record is kept there) and a line the addon never wrote take no cards.
--
-- A line coloured in parts holds colour codes, and how the client counts bytes around an escape sequence is not
-- verified (UI/Readings refuses such text). So the words are measured on a twin line: the same text without the
-- colour codes, same font and width, drawn at the same place with no opacity. Colour codes take no room, so both
-- wrap alike. A line holding any other escape (a texture, a link) takes no cards.
local _, WFJ = ...
local Freeze = {}
WFJ.TooltipFreeze = Freeze

local Compat = WFJ.Compat
local SURFACE = "tooltip.frozen"
local FIRST_KEY = "CTRL-F"

-- GameTooltip and the comparison tooltips it shows beside itself
-- [verified: forever blizzard_gametooltip/mainline/gametooltip.lua:955, self.shoppingTooltips]
local FRAMES = { "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }

Freeze.copies = {} -- the copies showing, GameTooltip's first: { frame, lines = { { fs, twin, rec } } }

local pool = {} -- [i] = { frame, strings = {}, used = n }: one per tooltip frame, made on first need
local signature -- what the tooltip the copy was made from belongs to, and its first line
local closing = false

local function showing(tip)
  return type(tip) == "table" and tip:IsShown() and tip:GetLeft() ~= nil and (tip:NumLines() or 0) > 0
end

-- In combat the client hands out a tooltip's texts, colours and sizes as values an addon may pass on but never
-- read, compare or join (docs/architecture/client-limits.md). Such a value goes straight into the copy.
local function secret(value) return WFJ.SurfaceState.secret(value) end

-- What tells one tooltip from another: what it belongs to and its first line, where that may be read. The other
-- lines are left out: the client rewrites a cooldown or a time left while the mouse rests on the tooltip.
local function identity(tip)
  local first = Compat.resolve(tip:GetName() .. "TextLeft1")
  local text = first and first:GetText()
  return { owner = tip.GetOwner and tip:GetOwner() or nil, first = not secret(text) and text or nil }
end

local function same(a, b)
  return a ~= nil and a.owner == b.owner and a.first == b.first
end

-- ── The copy's frames and lines ───────────────────────────────────────────

local function slot(i)
  local s = pool[i]
  if s then return s end
  local name = "WFJFrozenTooltip" .. i
  local frame = CreateFrame("Frame", name, Compat.resolve("UIParent"), "TooltipBackdropTemplate")
  -- under the TOOLTIP strata, so the word card (drawn there) is never behind the copy
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:EnableMouse(true) -- nothing under the copy answers the mouse while it shows
  frame:SetClampedToScreen(true)
  frame:Hide()
  frame:SetScript("OnHide", function() Freeze.close() end)
  if i == 1 then
    -- Esc hides every frame named here [verified: forever blizzard_uiparentpanelmanager/shared/
    -- uiparentpanelmanager.lua:21, :1108]; the first copy's hide closes the rest
    local special = Compat.resolve("UISpecialFrames")
    if type(special) == "table" then special[#special + 1] = name end
  end
  s = { frame = frame, strings = {}, used = 0 }
  pool[i] = s
  return s
end

local function fontString(s)
  s.used = s.used + 1
  local fs = s.strings[s.used]
  if not fs then
    fs = s.frame:CreateFontString(nil, "ARTWORK", "GameTooltipText")
    fs:SetJustifyV("TOP")
    s.strings[s.used] = fs
  end
  if fs.SetAlpha then fs:SetAlpha(1) end
  return fs
end

-- `fs` laid out as `src` is, in the copy's own coordinates, holding `text`
local function layLike(s, fs, tip, src, text)
  local path, size, flags = src:GetFont()
  if path and not secret(path) and not secret(size) and not secret(flags) then
    WFJ.Font.set(fs, path, WFJ.Font.size(size) or WFJ.Font.DEFAULT_SIZE, flags)
  end
  if src.GetJustifyH then fs:SetJustifyH(src:GetJustifyH()) end
  if fs.SetSpacing and src.GetSpacing then fs:SetSpacing(src:GetSpacing()) end
  if fs.SetNonSpaceWrap and src.CanNonSpaceWrap then fs:SetNonSpaceWrap(src:CanNonSpaceWrap()) end
  fs:SetWordWrap(true)
  fs:SetWidth(src:GetWidth())
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", s.frame, "TOPLEFT", src:GetLeft() - tip:GetLeft(), src:GetTop() - tip:GetTop())
  fs:SetText(text)
  fs:Show()
end

-- → the line's text when `src` is a line the tooltip shows, else nil; and whether the text may not be read
local function shownText(src)
  if type(src) ~= "table" or not src:IsShown() or not src:GetLeft() or not src:GetTop() then return nil end
  local text = src:GetText()
  if secret(text) then return text, true end
  if type(text) ~= "string" or text == "" then return nil end
  return text, false
end

-- ── Word cards ────────────────────────────────────────────────────────────

-- Whether a copy made now takes cards at all: Japanese is what shows, and the client is out of combat (a cover
-- cannot be made in combat, UI/Readings).
local function cardsNow()
  if WFJ.State.enabled == false or (WFJ.Modifier and WFJ.Modifier.english()) then return false end
  local inCombat = Compat.resolve("InCombatLockdown")
  return not (type(inCombat) == "function" and inCombat())
end

-- → kind, id, the text without its colour codes; nil when the line takes no cards. Which kinds ship words is the
-- lookup's to say (Core/Readings).
local function cardLine(src, text)
  local rec = WFJ.SurfaceState.of(src)
  local meta = rec and rec.meta
  if not meta or rec.applied ~= text or meta.id == nil then return nil end
  local plain = WFJ.UIStrings.stripColour(text)
  if plain:find("|", 1, true) then return nil end
  return meta.kind, meta.id, plain
end

local function attachCards(s, entry, tip, src, text)
  local kind, id, plain = cardLine(src, text)
  if not kind then return end
  local words = WFJ.Readings.lookup(kind, id, plain)
  if not words or not words[1] then return end
  local twin = fontString(s)
  layLike(s, twin, tip, src, plain)
  if twin.SetAlpha then twin:SetAlpha(0) end
  local rec = { fs = twin, applied = plain, surface = SURFACE, spans = words, meta = { kind = kind, id = id } }
  if WFJ.ReadingView.attach(rec) then
    entry.twin, entry.rec = twin, rec
  else
    twin:Hide()
  end
end

-- ── Copy, close, toggle ───────────────────────────────────────────────────

local function colours(tip, frame)
  -- [verified: forever blizzard_sharedxml/nineslice.lua:327, :345]
  local from, to = tip.NineSlice, frame.NineSlice
  if type(from) ~= "table" or type(to) ~= "table" then return end
  if from.GetCenterColor and to.SetCenterColor then pcall(function() to:SetCenterColor(from:GetCenterColor()) end) end
  if from.GetBorderColor and to.SetBorderColor then pcall(function() to:SetBorderColor(from:GetBorderColor()) end) end
end

local function copyOf(i, tip, cards)
  local s = slot(i)
  local frame, ui = s.frame, Compat.resolve("UIParent")
  -- the copy takes the tooltip's own scale, so its lengths and positions carry over as they are
  if frame.SetScale then frame:SetScale(tip:GetEffectiveScale() / ui:GetEffectiveScale()) end
  frame:SetSize(tip:GetWidth(), tip:GetHeight())
  frame:ClearAllPoints()
  frame:SetPoint("BOTTOMLEFT", ui, "BOTTOMLEFT", tip:GetLeft(), tip:GetBottom())
  colours(tip, frame)
  frame:Show()
  local copy = { frame = frame, lines = {} }
  local name = tip:GetName()
  for n = 1, tip:NumLines() or 0 do
    for _, side in ipairs({ "Left", "Right" }) do
      local src = Compat.resolve(name .. "Text" .. side .. n)
      local text, unreadable = shownText(src)
      if text then
        local fs = fontString(s)
        layLike(s, fs, tip, src, text)
        fs:SetTextColor(src:GetTextColor())
        local entry = { fs = fs }
        if cards and not unreadable then attachCards(s, entry, tip, src, text) end
        copy.lines[#copy.lines + 1] = entry
      end
    end
  end
  return copy
end

local function hideAll()
  for _, copy in ipairs(Freeze.copies) do
    for _, entry in ipairs(copy.lines) do
      if entry.rec then WFJ.ReadingView.detach(entry.rec) end
    end
  end
  for _, s in pairs(pool) do
    for i = 1, s.used do s.strings[i]:Hide() end
    s.used = 0
    s.frame:Hide()
  end
end

-- Hiding a copy's frame runs this again (OnHide); `closing` stops the loop, and is put back whatever happens, or
-- one error here would leave every later close doing nothing.
function Freeze.close()
  if closing then return end
  closing = true
  local ok, err = pcall(hideAll)
  Freeze.copies, signature = {}, nil
  closing = false
  if not ok then error(err, 0) end
end

-- Draws the copies of the tooltip showing now and of the comparison tooltips beside it.
function Freeze.show()
  Freeze.close()
  local cards = cardsNow()
  local copies = {}
  -- a copy half drawn is a frame that takes the mouse with nothing in it: an error takes the frames down again
  local ok, err = pcall(function()
    for _, name in ipairs(FRAMES) do
      local tip = Compat.resolve(name)
      if showing(tip) then copies[#copies + 1] = copyOf(#copies + 1, tip, cards) end
    end
  end)
  Freeze.copies = copies
  if not ok then
    Freeze.close()
    error(err, 0)
  end
  signature = identity(Compat.resolve("GameTooltip"))
end

-- The key: freezes the tooltip showing now; with none showing (or the same one already frozen), closes the copy.
function Freeze.toggle()
  local tip = Compat.resolve("GameTooltip")
  local frozen = Freeze.copies[1] ~= nil
  if showing(tip) and not (frozen and same(signature, identity(tip))) then
    Freeze.show()
  elseif frozen then
    Freeze.close()
  end
end

-- A key with no action is free only once the client has loaded the player's saved bindings: before that every
-- key reads as free, and binding one would take it from the player's own action for good. The client's own
-- frames read their keys on UPDATE_BINDINGS [verified: forever blizzard_actionbar/wowlabs/keybindreminder.lua:15,
-- :26; blizzard_actionbar/shared/actionbutton.lua:217, :994], so the offer waits for the first one
-- [unverified: that the first UPDATE_BINDINGS of a session follows the saved bindings' load; in-game check: a
-- fresh login on a character whose saved bindings hold Ctrl+F keeps that action].
local bindingsIn = false

function Freeze.bindingsLoaded(db)
  bindingsIn = true
  Freeze.offerKey(db)
end

-- The binding's first key, offered once per account: bound only when the binding has no key and nothing is on the
-- key. `db` (the saved settings table) remembers that the offer was made, whichever way it went; an offer that
-- could not be decided (combat) is made again.
function Freeze.offerKey(db)
  if not bindingsIn or type(db) ~= "table" or db.freezeKeyOffered then return end
  -- With Ctrl as the reveal key, holding Ctrl for this chord would show the English, and a copy made then takes
  -- no cards: no offer while that is so.
  local reveal = WFJ.Settings.get("modifier")
  if type(reveal) == "string" and reveal:lower():find("ctrl", 1, true) then return end
  if WFJ.KeyCapture.offerDefault(WFJ.KeyCapture.FREEZE, FIRST_KEY) then db.freezeKeyOffered = true end
end

-- A copy made while Japanese showed keeps its text, but its cards follow what the screen shows now: gone while
-- English shows or translation is off, back when the Japanese is.
local function followLanguage()
  local cards = cardsNow()
  for _, copy in ipairs(Freeze.copies) do
    for _, entry in ipairs(copy.lines) do
      if entry.rec then
        if cards then WFJ.ReadingView.attach(entry.rec) else WFJ.ReadingView.detach(entry.rec) end
      end
    end
  end
end
WFJ.State.on("language", followLanguage)
WFJ.State.on("enabled", followLanguage)

function WFJ_FreezeTooltip() Freeze.toggle() end
