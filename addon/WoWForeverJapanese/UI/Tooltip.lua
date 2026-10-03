-- UI/Tooltip.lua: item, spell and aura (buff / debuff) tooltips (areas "items" / "spells"), one surface per frame:
--   tooltip.GameTooltip · tooltip.ItemRefTooltip · tooltip.ShoppingTooltip1/2 · tooltip.ItemRefShoppingTooltip1/2
-- The client's tooltips are the `mainline` flavour: every line is written from C_TooltipInfo data before the
-- TooltipDataProcessor post-calls run (Enum.TooltipDataType.Item / .Spell / .UnitAura; see Tooltip.modern), so one
-- post-call per type serves every tooltip frame and only the six declared frames are ours. "Next rank:" and the three
-- talent-hint strings are enUS literals [likely; in-game check in docs/testing/strategy.md]. Tooltips are the
-- documented exception to "English from the API": the lines ARE the English (addon-modules.md, render mechanism §1).
-- Which lines (ADR-010): items → the "description run" from line 2 (Use: / Equip: / Chance on hit: / a "flavour
-- quote", blank lines inside it included); spells → the line whose text equals GetSpellDescription(id), with the
-- positional rule (last non-empty non-hint line, or above "Next rank:") only when that API is absent. The run's
-- first line is the primary record; the others are companions that blank while it is applied.
-- The gate (Core/Align.check, through Translator) fills $N values from the run and checks names + numbers
-- against exactly those lines; any doubt leaves the tooltip alone. Release on the frame's OnHide.
-- The Collector gets the item run's text and the spell's GetSpellDescription string, never a positional guess;
-- an aura's line 2 only where that spell's aura ships.
-- Structural lines (area "ui", ADR-015): every other line, left and right (`TextRight<i>`: the armor / weapon
-- type, "Speed 2.60", a spell's "Rank 1" beside its name), is matched against the UI dictionary (WFJ.UIIndex: exact,
-- template, label) and shown as record "ui.L<i>" / "ui.R<i>" with the captured values. Never a description line and
-- never the NAME: the left line whose text is the item / spell name, and left line 1 of a tooltip whose first line is
-- its name. A comparison tooltip puts its "Currently Equipped" header on line 1 and the name on line 2 (seen in game),
-- so there line 1 is a header and the name is found by its text.
-- The run of an item with no translation gets its "Equip: <stat template>" lines as ui records (showEquipLines).
-- Auras: a buff or debuff tooltip is GameTooltip:SetUnitAura / SetUnitBuff / SetUnitDebuff or their
-- *ByAuraInstanceID twins: buff frame, target of target, party, raid, compact frames, nameplates [verified: Forever
-- 1.60.1 blizzard_buffframe/buffframe.lua:1145–1149, unitframe/mainline/targetframe.xml:45,
-- shared/partymemberframe.lua:202–206]. The target frame's own aura buttons use AuraButtonTooltip, a forbidden
-- frame no addon can reach (docs/architecture/client-limits.md). Forever types them Enum.TooltipDataType.UnitAura
-- and GetSpell answers only for Spell (tooltiputil.lua:25–31), so the Spell post-call never sees one; the surface
-- registers a UnitAura post-call, which fires on the first build and on every rebuild. The spell id comes from
-- C_UnitAuras with the call's own arguments, as Blizzard's PTR reporter does
-- (blizzard_ptrfeedback_tooltips.lua:22–32). The aura text is line 2 [likely: tooltipdatahandler.lua writes it
-- from C_TooltipInfo data; in-game check in docs/testing/strategy.md]: refused when empty or a UI-dictionary line,
-- and the runtime gate refuses a line whose names and numbers do not fit. An owner with UpdateTooltip re-shows the
-- aura about 5 times a second while hovered; each pass forgets and re-renders, as item tooltips do.
-- ADR-038:
--   comparison tooltips: after the compared item's lines (ProcessInfo), TooltipComparisonManager appends the delta
--     header ITEM_DELTA_DESCRIPTION / ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION and, with cycling on,
--     ITEM_COMPARISON_SWAP_ITEM_MAINHAND / _OFFHAND_DESCRIPTION (the key binding kept, `text`) or
--     ITEM_COMPARISON_CYCLING_DISABLED_MSG_MAINHAND / _OFFHAND (blizzard_sharedxmlgame/tooltip/
--     tooltipcomparisonmanager.lua:250–316), after the Item post-call ran. Each comparison frame's Show is post-hooked
--     and its lines are matched against those keys only (COMPARE_KEYS), as "ui.L<i>" records beside the structural
--     ones (a line matching none of them is left alone, its structural record kept);
--   an item spell line's trailer ITEM_SPELL_MAX_USABLE_LEVEL " (Requires level %d or below)" (C-side tooltip data; no
--     Lua writer in the extract): peeled off a run line before the Collector reads it; for a trusted (ungated) item
--     translation the trailer's Japanese is appended to the run's Japanese (the `affix` fill form). A gated entry
--     keeps the whole line (its align gate sees all of it).
-- Hidden passes (ADR-051, in combat): an action button's tooltip arrives with every row's text secret; the spell or
-- item id stays readable, so the pass translates the client's own tooltip data for that id and writes it onto the
-- rows by position, the countdown by the client's own duration (see "Hidden passes" below). A buff tooltip in combat
-- has no readable handle and is left in English.
local _, WFJ = ...
local Tooltip = {}
WFJ.Tooltip = Tooltip

local Compat = WFJ.Compat
local DECLARE = "tooltip"

Tooltip.FRAMES = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
  "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }
Tooltip.SURFACES = {}
Tooltip.IS_SURFACE = {} -- frame name → true; the data-processor path is handed tooltips this addon never declared
for i, name in ipairs(Tooltip.FRAMES) do
  Tooltip.SURFACES[i] = DECLARE .. "." .. name
  Tooltip.IS_SURFACE[name] = true
end

-- Trigger strings are Blizzard globals; the enUS text is the fallback [likely, long-standing global strings;
-- in-game check in docs/testing/strategy.md].
local TRIGGERS = {
  { key = "onUse", global = "ITEM_SPELL_TRIGGER_ONUSE", fallback = "Use:" },
  { key = "onEquip", global = "ITEM_SPELL_TRIGGER_ONEQUIP", fallback = "Equip:" },
  { key = "onProc", global = "ITEM_SPELL_TRIGGER_ONPROC", fallback = "Chance on hit:" },
}
local NEXT_RANK = "Next rank:"
local HINTS = { ["Left click to add a point"] = true, ["Right click to remove a point"] = true,
  ["Click to learn"] = true }

local resolvedFrames = 0
local auraHooks = 0 -- aura methods served (6 on either path), 0 when the surface has no aura path
local inRefit = {}
local refits = {}

local function prefixes()
  local out = {}
  for _, t in ipairs(TRIGGERS) do
    local g = Compat.get(DECLARE, t.key)
    out[#out + 1] = (type(g) == "string" and g ~= "") and g or t.fallback
  end
  return out
end

local function isDescription(text, pre)
  if type(text) ~= "string" or text == "" then return false end
  for _, p in ipairs(pre) do
    if text:sub(1, #p) == p then return true end
  end
  return text:sub(1, 1) == '"' and text:sub(-1) == '"' and #text > 2
end

-- The frame's left (or `side` = "Right") lines as { { fs, text }, … } (index = line number). A line without a
-- FontString ends the list.
function Tooltip.lines(frame, side)
  local out, name = {}, frame:GetName()
  local n = frame:NumLines() or 0
  for i = 1, n do
    local fs = Compat.resolve(name .. "Text" .. (side or "Left") .. i)
    if not fs then break end
    out[i] = { fs = fs, text = fs:GetText() or "" }
  end
  return out
end

-- Item: the maximal contiguous run of description lines, scanning from line 2. → first, last | nil
function Tooltip.itemRun(texts)
  local pre = prefixes()
  local first
  for i = 2, #texts do
    if isDescription(texts[i], pre) then first = i; break end
  end
  if not first then return nil end
  local last = first
  while true do
    local nxt = last + 1
    while nxt <= #texts and texts[nxt] == "" do nxt = nxt + 1 end -- blank lines inside the run belong to it
    if nxt <= #texts and isDescription(texts[nxt], pre) then last = nxt else break end
  end
  return first, last
end

-- Spell: the description line. With the client's GetSpellDescription(id) [likely on Classic Era: a C API, not in
-- the FrameXML dump; in-game check in docs/testing/strategy.md], the line is found by CONTENT: the first line
-- (from 2) whose text equals the API's description, so a line another addon appended ("Spell ID: 53") or an
-- aura's "12 seconds remaining" can never be taken for the description. Without the API the positional rule stands
-- in: the last non-empty, non-hint line, or the same rule applied above "Next rank:" (/wfj debug reports which).
-- → i | nil. Never line 1, never an empty line.
local function lastTextAbove(texts, top)
  local n = top
  while n >= 2 and (texts[n] == "" or HINTS[texts[n]]) do n = n - 1 end
  return (n >= 2) and n or nil
end

function Tooltip.spellLine(texts, description)
  if type(description) == "string" then
    if description == "" then return nil end
    for i = 2, #texts do
      if texts[i] == description then return i end
    end
    return nil
  end
  for i = 2, #texts do
    if texts[i] == NEXT_RANK then return lastTextAbove(texts, i - 1) end
  end
  return lastTextAbove(texts, #texts)
end

-- The API description for a spell id, or nil when the API is absent (positional fallback).
function Tooltip.spellDescription(id)
  local api = Compat.get(DECLARE, "spellDescription")
  if type(api) ~= "function" then return nil end
  local d = api(id)
  return type(d) == "string" and d or ""
end

-- Shown twice: on Forever every layout of a wrapped Japanese line alternates between two line breaks when a word
-- sits on the wrap edge (the tooltip trace shows the wrapped width going 242, 249, 242 … with nothing else
-- changing). A refresh lays the tooltip out three times (the client's English, this refit, one more Show), so the
-- line came out the other way on every refresh and flickered. A second Show here makes the count even, so every
-- refresh ends on the same line breaks. [likely: the tooltip trace in game, Forever 1.60.1.70205; in-game check in
-- docs/testing/strategy.md]
local function refitFor(frame)
  local fn = refits[frame]
  if fn then return fn end
  fn = function()
    if inRefit[frame] then return end
    inRefit[frame] = true
    frame:Show()
    frame:Show()
    inRefit[frame] = false
  end
  refits[frame] = fn
  return fn
end

local function surfaceOf(frame)
  return DECLARE .. "." .. frame:GetName()
end

-- Hands the run to Render: line `first` is the primary ("desc"), the rest companions ("desc.<i>", follow "desc").
-- Records from the previous hover on this frame are forgotten first (the client rewrote every line). A run whose
-- first line is empty is refused: an empty English is never a translation target (addon-modules §7).
local runColors -- below anySecretOf, which it needs

local function showRun(surface, area, kind, id, lines, first, last, refit, runArgs)
  local texts = {}
  for i = first, last do texts[#texts + 1] = lines[i].text end
  local n = 0
  -- line 1 is the name: never replaced, never a number source, but a name the Japanese may legitimately use
  if WFJ.Render.show(surface, "desc", lines[first].fs, lines[first].text, area, kind, id,
      { lines = texts, nameScope = lines[1] and lines[1].text or nil, refit = refit, args = runArgs,
        partColors = runColors(lines, first, last) }) then
    n = n + 1
  end
  for i = first + 1, last do
    if WFJ.Render.show(surface, "desc." .. i, lines[i].fs, lines[i].text, area, kind, id,
        { follow = "desc", refit = refit }) then n = n + 1 end
  end
  return n
end

-- Structural lines: lines 2…N, left then right, except the description lines [first, last]. A line whose
-- text is a dictionary word, template or label becomes a "ui" record with the captured values.
local HEADED = { ShoppingTooltip1 = true, ShoppingTooltip2 = true, ItemRefShoppingTooltip1 = true,
  ItemRefShoppingTooltip2 = true } -- comparison tooltips: line 1 is "Currently Equipped", the name follows

local function showStructural(surface, frame, lines, first, last, refit, name)
  local index = WFJ.UIIndex
  if not index then return 0 end
  local n = 0
  local headed = HEADED[frame:GetName()]
  local sides = { { "L", lines }, { "R", Tooltip.lines(frame, "Right") } }
  for i = 1, #lines do
    if not (first and i >= first and i <= last) then
      for _, side in ipairs(sides) do
        local l = side[2][i]
        -- an uncached item has no name yet: on a comparison tooltip the name is then line 2 by position
        local isName = side[1] == "L" and ((i == 1 and not headed) or (name ~= nil and l and l.text == name)
          or (headed and name == nil and i == 2))
        if l and l.text ~= "" and not isName then
          local key, args = index:match(l.text)
          -- ADR-042: the right side of line 1 is never a name: on an aura it is the dispel type ("Curse"),
          -- a restricted family found only where it is asked for
          if not key and side[1] == "R" and i == 1 then
            key, args = index:matchOnly(l.text, WFJ.Labels.families("DispelType").only)
          end
          if key and WFJ.Render.show(surface, "ui." .. side[1] .. i, l.fs, l.text, "ui", "ui", key,
              { args = args, refit = refit }) then
            n = n + 1
          end
        end
      end
    end
  end
  return n
end

-- One hover: forget the previous records, the description run (when there is one and its first line is not empty),
-- then the structural lines, then one refit.
-- "Equip:" stat lines inside the run of an item the addon has NO translation for (ADR-016). Each run line that
-- is "<Equip:> <ITEM_MOD_* template>" becomes its own ui record ("装備時: " + the filled template); every other run
-- line stays English. Decided on the entry, never on what is shown now: a translated item hovered with the modifier
-- held (or its area off) shows English at that moment, and equip records there would take the run's widgets from
-- the item's own records. They run before the run's own record: a run with any Equip line matched gets no run
-- record, so no missing marker.
-- → lines matched (records captured, whatever is shown right now), lines written
local function showEquipLines(surface, id, lines, first, last, refit)
  local index = WFJ.UIIndex
  local lookup = WFJ.Lookup and WFJ.Lookup.get
  if not index then return 0, 0 end
  if type(lookup) ~= "function" or lookup("item.description", id) ~= nil then return 0, 0 end
  local matched, n = 0, 0
  for i = first, last do
    local l = lines[i]
    local key, args = index:match(l.text)
    if key and type(args) == "table" and args.form == "equip" then
      matched = matched + 1
      if WFJ.Render.show(surface, "ui.L" .. i, l.fs, l.text, "ui", "ui", key, { args = args, refit = refit }) then
        n = n + 1
      end
    end
  end
  return matched, n
end

-- A line text the client marks secret (Forever: FontString:GetText is SecretReturnsForAspect Text) may not be
-- compared or matched by addon code (an action button's tooltip in combat holds only secret lines); `type()` of one
-- is still "string", so it is asked about explicitly.
local function anySecret(texts)
  local isSecret = Compat.resolve("issecretvalue")
  if type(isSecret) ~= "function" then return false end
  for _, text in ipairs(texts) do
    if isSecret(text) then return true end
  end
  return false
end

-- The same over loose values, which may hold a nil before a secret (a list would stop at the hole).
local function anySecretOf(...)
  local isSecret = Compat.resolve("issecretvalue")
  if type(isSecret) ~= "function" then return false end
  for i = 1, select("#", ...) do
    if isSecret((select(i, ...))) then return true end
  end
  return false
end

-- The colours of a run's non-empty parts (each line, split at the line breaks inside it) for Render's partColors:
-- nil where a part has the first line's colour, "ffRRGGBB" where it differs (the gold flavour text under a green
-- Use: line). → colors | nil (all one colour, or a colour the client keeps secret)
function runColors(lines, first, last)
  local function hex(fs)
    if type(fs.GetTextColor) ~= "function" then return nil end
    local r, g, b = fs:GetTextColor()
    if anySecretOf(r, g, b) or type(r) ~= "number" then return nil end
    return ("ff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
  end
  local base = hex(lines[first].fs)
  if not base then return nil end
  local colors, differs = { n = 0 }, false
  for i = first, last do
    if lines[i].text ~= "" then
      local c = hex(lines[i].fs)
      if not c then return nil end
      for part in (lines[i].text .. "\n"):gmatch("(.-)\n") do
        if part ~= "" then
          colors.n = colors.n + 1
          if c ~= base then colors[colors.n], differs = c, true end
        end
      end
    end
  end
  return differs and colors or nil
end


local function ownerOf(frame)
  return type(frame.GetOwner) == "function" and frame:GetOwner() or nil
end

-- ── The tooltip trace (/wfj debug tooltip): every pass over a spell or item tooltip, row by row ──
-- Off unless asked for. A secret value is never compared, concatenated or measured: it is written as <secret>.
Tooltip.trace = nil
local TRACE_MAX = 400

-- A long value is cut at 70 bytes, moved back to the start of a character: a cut inside a Japanese character is
-- not UTF-8, and an edit box given text that is not UTF-8 shows none of it.
local function plain(v)
  if v == nil then return "nil" end
  if anySecretOf(v) then return "<secret>" end
  local t = tostring(v)
  if #t <= 70 then return t end
  local cut = 70
  while cut > 0 do
    local b = t:byte(cut + 1)
    if not b or b < 0x80 or b >= 0xC0 then break end -- the next byte starts a character
    cut = cut - 1
  end
  return t:sub(1, cut) .. "..."
end
Tooltip.plain = plain

-- A widget's laid-out size for the trace: " w=<width> sw=<string width> h=<height> n=<lines>", each part only when the
-- client has the method and the value may be read. A wrapped line that moves between passes shows here.
local GEOMETRY = { { "w", "GetWidth" }, { "sw", "GetStringWidth" }, { "ww", "GetWrappedWidth" }, { "h", "GetHeight" },
  { "n", "GetNumLines" } }
local function geometry(widget)
  local parts = {}
  for _, g in ipairs(GEOMETRY) do
    local fn = widget[g[2]]
    if type(fn) == "function" then
      local ok, v = pcall(fn, widget)
      if ok and type(v) == "number" and not anySecretOf(v) then parts[#parts + 1] = ("%s=%.1f"):format(g[1], v) end
    end
  end
  if type(widget.GetFont) == "function" then -- the face a wrap was measured in
    local ok, path, size = pcall(widget.GetFont, widget)
    if ok and type(path) == "string" and type(size) == "number" and not anySecretOf(path, size) then
      parts[#parts + 1] = ("font=%s@%.1f"):format(path:match("[^\\/]+$") or path, size)
    end
  end
  return #parts > 0 and (" " .. table.concat(parts, " ")) or ""
end

local function describe(fs)
  if type(fs) ~= "table" then return "-" end
  local text = fs:GetText()
  local shown = type(fs.IsShown) == "function" and fs:IsShown() and "" or " hidden"
  local colour = "<colour secret or none>"
  if type(fs.GetTextColor) == "function" then
    local r, g, b = fs:GetTextColor()
    if not anySecretOf(r, g, b) and type(r) == "number" then colour = ("%.2f,%.2f,%.2f"):format(r, g, b) end
  end
  if anySecretOf(text) then return "<secret> " .. colour .. shown end
  if text == nil then return "nil" .. shown end
  if text == "" then return "\"\"" .. shown end
  return "\"" .. plain(text) .. "\" " .. colour .. shown .. geometry(fs)
end

local function traceFrame(frame, event, id, lines, note)
  if not Tooltip.trace then return end
  local owner = ownerOf(frame)
  local ownerName = type(owner) == "table" and type(owner.GetName) == "function" and plain(owner:GetName())
    or plain(owner)
  local clock = Compat.resolve("date")
  local stamp = type(clock) == "function" and clock("%H:%M:%S") or ""
  local out = { ("[%s] %s %s id=%s owner=%s rows=%d%s %s"):format(stamp, plain(frame:GetName()), event,
    plain(id), ownerName, #lines, geometry(frame), note or "") }
  local rights = Tooltip.lines(frame, "Right")
  local kinds = {}
  if type(frame.GetPrimaryTooltipInfo) == "function" then
    local ok, info = pcall(frame.GetPrimaryTooltipInfo, frame)
    if ok and type(info) == "table" then kinds = WFJ.TooltipUnit.lineKinds(info.tooltipData) end
  end
  for i, l in ipairs(lines) do
    out[#out + 1] = ("  %d %s L %s | R %s"):format(i, kinds[i] or "?", describe(l.fs),
      describe(rights[i] and rights[i].fs))
  end
  local t = Tooltip.trace
  -- a pass identical to the one before (an owner re-showing the tooltip several times a second) is counted, not
  -- added again, so a short recording is not filled by one hover
  local body = table.concat(out, "\n", 2)
  local key = out[1]:gsub("^%[[^%]]*%] ", "") .. "\n" .. body
  if Tooltip.traceLast == key and #t > 0 then
    Tooltip.traceRepeat = (Tooltip.traceRepeat or 1) + 1
    t[#t] = t[#t]:gsub("\n  %(seen %d+ times[^\n]*$", "") .. ("\n  (seen %d times, last %s)"):format(
      Tooltip.traceRepeat, stamp)
    return
  end
  Tooltip.traceLast, Tooltip.traceRepeat = key, 1
  t[#t + 1] = table.concat(out, "\n")
  if #t > TRACE_MAX then table.remove(t, 1) end
end
Tooltip.traceFrame = traceFrame

-- One line in the trace for a hook call the addon set aside before reading the tooltip (why it was not its).
local function traceNote(text)
  if not Tooltip.trace then return end
  local clock = Compat.resolve("date")
  local stamp = type(clock) == "function" and clock("%H:%M:%S") or ""
  local t = Tooltip.trace
  local line = ("[%s] %s"):format(stamp, text)
  if Tooltip.traceLast == text and #t > 0 then
    Tooltip.traceRepeat = (Tooltip.traceRepeat or 1) + 1
    t[#t] = line .. (" (seen %d times)"):format(Tooltip.traceRepeat)
    return
  end
  Tooltip.traceLast, Tooltip.traceRepeat = text, 1
  t[#t + 1] = line
  if #t > TRACE_MAX then table.remove(t, 1) end
end

-- The calls that can lay a tooltip line out again, for the trace: on GameTooltip's wrapped left lines, SetText,
-- SetFont and SetWidth; on GameTooltip itself, Show, SetPadding and SetMinimumWidth. Each logs the method, the
-- first wrapped line's size right after the call and the caller (debugstack), so a wrap that moves between
-- passes names the call that moved it. Installed once, the first time the trace is turned on; logs only while
-- it is on.
local callHooks = false
local function callNote(method, fs)
  if not Tooltip.trace then return end
  local stack = Compat.resolve("debugstack")
  local caller = type(stack) == "function" and (stack(3, 1, 0) or ""):gsub("%s+$", "") or ""
  traceNote(("call %s%s ->%s · %s"):format(method, fs and (" " .. plain(fs:GetName())) or "", geometry(fs or {}),
    plain(caller)))
end
local function wrappedLine(frame)
  for _, l in ipairs(Tooltip.lines(frame)) do
    local ok, n = pcall(l.fs.GetNumLines, l.fs)
    if ok and type(n) == "number" and not anySecretOf(n) and n > 1 then return l.fs end
  end
  return nil
end
function Tooltip.installCallTrace()
  if callHooks then return end
  local tip = Compat.resolve("GameTooltip")
  if type(tip) ~= "table" then return end
  callHooks = true
  for _, m in ipairs({ "Show", "SetPadding", "SetMinimumWidth" }) do
    if type(tip[m]) == "function" then
      hooksecurefunc(tip, m, function(self)
        if Tooltip.trace then callNote("GameTooltip:" .. m, wrappedLine(self)) end
      end)
    end
  end
  for i = 1, 30 do
    local fs = Compat.resolve("GameTooltipTextLeft" .. i)
    if type(fs) == "table" then
      for _, m in ipairs({ "SetText", "SetFont", "SetWidth" }) do
        if type(fs[m]) == "function" then
          hooksecurefunc(fs, m, function(self)
            if not Tooltip.trace then return end
            local ok, n = pcall(self.GetNumLines, self)
            if ok and type(n) == "number" and not anySecretOf(n) and n > 1 then callNote(m, self) end
          end)
        end
      end
    end
  end
end
Tooltip.traceNote = traceNote

local function show(frame, area, kind, id, lines, first, last, name, runArgs)
  local surface = surfaceOf(frame)
  WFJ.Render.forget(surface)
  if first and lines[first].text == "" then first, last = nil, nil end
  local refit = refitFor(frame)
  -- One refit for the whole hover: the per-record refit is a no-op while inRefit is set, then the refit runs once.
  -- The flag is cleared even when a write errors, so the frame is never left silently unhandled.
  inRefit[frame] = true
  local ok, n = pcall(function()
    -- The Equip lines of an item with no translation are tried first; when any translates, the run takes
    -- no missing marker (it would claim the whole run untranslated, and its record would hold the lines the Equip
    -- records need). Only a run with nothing translatable gets the marker.
    -- Decided on what matched, not on what was written: hovered with the modifier held, the Equip records are
    -- captured but write nothing, and the run's record must still not take their lines.
    local matched, written = 0, 0
    if first and kind == "item.description" then
      matched, written = showEquipLines(surface, id, lines, first, last, refit)
    end
    if first and matched == 0 then
      written = showRun(surface, area, kind, id, lines, first, last, refit, runArgs)
    end
    return written + showStructural(surface, frame, lines, first, last, refit, name)
  end)
  inRefit[frame] = false
  if not ok then error(n, 0) end
  if n > 0 then refit() end
  return n
end

-- The max-usable-level trailer on the run's lines. `texts` is rewritten in place without it (what the Collector
-- records). → affix args carrying the trailer's Japanese | nil (none, or not one Japanese for it)
local TRAILER = { "ITEM_SPELL_MAX_USABLE_LEVEL" }
local function peelTrailer(texts, first, last)
  local index = WFJ.UIIndex
  if not index then return nil end
  local after
  for i = first, last do
    local head, tail = (texts[i] or ""):match("^(.-)( %([^()]*%))$")
    local key, args
    if head then key, args = index:matchOnly(tail, TRAILER) end
    if key then
      texts[i] = head
      local ja = index.rows[key] and index:fill(index.rows[key][1], args)
      if ja and not after then after = ja end
    end
  end
  return after and { form = "affix", before = "", after = after } or nil
end

-- ── Hidden passes: a tooltip whose rows the addon may not read ──
-- In combat the client writes an action button's tooltip from values the addon may not read: every row's text and
-- colour is secret, and so are the cooldown's numbers (SecretWhenCooldownsRestricted). What stays readable is the
-- spell or item itself (the tooltip data's id, else the owner's action slot) and each row's kind. So a hidden pass
-- asks the client for that spell's or item's own tooltip by id (C_TooltipInfo.GetSpellByID / GetItemByID), whose
-- rows are plain text, translates those rows exactly as a readable pass would, and writes the Japanese onto the
-- frame's rows by position. The cooldown countdown, a row only the frame has, is written by the client from its own
-- hidden duration (UI/TimeLine). Nothing is kept between passes; a row that cannot be placed is left as the client
-- wrote it. A buff tooltip in combat has no readable handle at all (its aura id, spell, icon and rows are all secret,
-- and the aura APIs refuse a secret id from an addon), so it is left in the client's English until it is readable.
Tooltip.hidden = { written = 0, left = 0, last = nil } -- what the hidden passes did (/wfj debug)

local function hiddenDone(n, why)
  local h = Tooltip.hidden
  if n > 0 then h.written = h.written + 1 else h.left = h.left + 1 end
  h.last = why
  return n, why
end

-- A row written on a hidden pass wears the bundled face, and the frame keeps the client's own text for it (a
-- secret value, held but never read) so the row can be given back whole: on the frame's OnHide, and the moment the
-- modifier is held, the switch is off or the area is off, before the client's next rebuild.
local hiddenRows = setmetatable({}, { __mode = "k" }) -- [frame] = { [fs] = the client's text | true }

local function dressHidden(frame, fs, clientText)
  WFJ.Font.bundle(fs)
  hiddenRows[frame] = hiddenRows[frame] or {}
  if hiddenRows[frame][fs] == nil then hiddenRows[frame][fs] = clientText == nil and true or clientText end
end

local function undressHidden(frame, writeBack)
  local list = hiddenRows[frame]
  if not list then return end
  for fs, clientText in pairs(list) do
    if writeBack and clientText ~= true then pcall(fs.SetText, fs, clientText) end
    pcall(WFJ.Font.restore, fs)
  end
  hiddenRows[frame] = nil
end

local function writeHidden(frame, fs, text)
  local clientText = fs:GetText()
  fs:SetText(text)
  dressHidden(frame, fs, clientText)
end

-- English wanted now: every frame's hidden rows get the client's text and face back.
function Tooltip.restoreHidden()
  local frames = {}
  for frame in pairs(hiddenRows) do frames[#frames + 1] = frame end
  for _, frame in ipairs(frames) do undressHidden(frame, true) end
  return #frames
end

-- The spell or item on the owner's action slot, when the owner is an action button. GetActionInfo is not a guarded
-- read: the client's own buttons call it in combat (blizzard_actionbar/shared/actionbutton.lua:525, 1476). → id | nil
local function actionIdOf(frame, want)
  local owner = ownerOf(frame)
  local slot = type(owner) == "table" and owner.action or nil
  local info = Compat.resolve("GetActionInfo")
  if type(slot) ~= "number" or anySecretOf(slot) or type(info) ~= "function" then return nil end
  local ok, kind, id = pcall(info, slot)
  if not ok or kind ~= want or type(id) ~= "number" or anySecretOf(id) then return nil end
  return id
end

local API_OF = { ["spell.description"] = "C_TooltipInfo.GetSpellByID",
  ["item.description"] = "C_TooltipInfo.GetItemByID" }

-- The client's tooltip data for the spell or item itself. A row the client hides there too (its cooldown line, or
-- more) is kept as a hidden row, so the readable ones still serve. → { { left, right, type, hidden } }, hidden count,
-- the hidden rows' numbers | nil, why
local function apiRows(kind, id)
  local get = Compat.resolve(API_OF[kind])
  if type(get) ~= "function" then return nil, "no " .. API_OF[kind] end
  local ok, data = pcall(get, id)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then
    return nil, "the client gave no tooltip data for " .. tostring(id)
  end
  local rows, hidden, which = {}, 0, {}
  for i, line in ipairs(data.lines) do
    local left, right, kindOf = line.leftText, line.rightText, line.type
    local row = { type = not anySecretOf(kindOf) and kindOf or nil }
    if anySecretOf(left, right) then
      row.hidden, row.left = true, ""
      hidden = hidden + 1
      which[#which + 1] = tostring(i)
    else
      row.left = type(left) == "string" and left or ""
      row.right = type(right) == "string" and right or nil
    end
    rows[i] = row
  end
  if #rows == 0 then return nil, "the client's tooltip data has no rows" end
  return rows, hidden, table.concat(which, ",")
end

-- Where the frame's rows and the data's rows meet: one to one from the top (seen in game: Wrath's data has five
-- rows, name, cost, cast time, the cooldown countdown hidden, the description; the frame shows those five and then
-- rows other addons appended, which are left alone). When both sides type a description row and the frame's sits
-- lower, the rows between are the frame's own extras (a countdown the data lacks) and the rows from the description
-- on are shifted. → { [frame row] = data row }, { extra frame rows } | nil, why
local function placeRows(n, m, frameAnchor, dataAnchor)
  local map, extra = {}, {}
  local k = (frameAnchor and dataAnchor) and (frameAnchor - dataAnchor) or 0
  if k < 0 then
    return nil, ("the description is row %d on the frame but row %d in the data"):format(frameAnchor, dataAnchor)
  end
  if k > 1 then
    return nil, ("%d frame rows between the data's rows and the description: not the one countdown row"):format(k)
  end
  for i = 1, n do
    if k > 0 and i >= dataAnchor and i < frameAnchor then
      extra[#extra + 1] = i
    else
      local di = i - ((k > 0 and i >= frameAnchor) and k or 0)
      if di >= 1 and di <= m then map[i] = di end
    end
  end
  return map, extra
end
Tooltip.placeRows = placeRows

-- The data rows that are the description run: a spell's SpellDescription row (else the row equal to its API
-- description), an item's run from line 2. → first, last | nil
local function dataRun(kind, id, texts, rows)
  if kind == "item.description" then return Tooltip.itemRun(texts) end
  local enum = Compat.resolve("Enum.TooltipDataLineType")
  local want = type(enum) == "table" and enum.SpellDescription or nil
  for i, r in ipairs(rows) do
    if want ~= nil and r.type == want then return i, i end
  end
  local description = Tooltip.spellDescription(id)
  if anySecretOf(description) then return nil end
  local i = Tooltip.spellLine(texts, description)
  return i, i
end

-- The frame row the client typed SpellDescription, read from the tooltip data behind the frame. → row | nil
local function frameDescriptionRow(frame)
  if type(frame.GetPrimaryTooltipInfo) ~= "function" then return nil end
  local ok, info = pcall(frame.GetPrimaryTooltipInfo, frame)
  if not ok or type(info) ~= "table" then return nil end
  local okK, kinds = pcall(WFJ.TooltipUnit.lineKinds, info.tooltipData)
  if not okK or type(kinds) ~= "table" then return nil end
  for row, name in pairs(kinds) do
    if name == "SpellDescription" then return row end
  end
  return nil
end

-- The countdown row: a spell's from its hidden cooldown duration, written by the client; an item's from the seconds
-- left, which C_Item.GetItemCooldown gives unguarded [verified: itemdocumentation.lua:434–449]. → true | nil, why
local function writeCountdown(frame, fs, kind, id)
  local wrote, why
  local clientText = fs:GetText()
  if kind == "spell.description" then
    local durationOf = Compat.resolve("C_Spell.GetSpellCooldownDuration")
    if type(durationOf) ~= "function" then return nil, "no cooldown duration API" end
    local ok, duration = pcall(durationOf, id)
    if not ok then return nil, "cooldown duration refused: " .. tostring(duration) end
    if not duration then return nil, "no cooldown duration" end
    -- a zero duration is no cooldown: the row is something else, left as the client wrote it. In combat IsZero's
    -- answer is itself a secret boolean, never compared (a Lua error in game): the client's formatter writes it
    local okZ, zero = pcall(function() return duration:IsZero() end)
    if okZ and not anySecretOf(zero) and zero == true then return nil, "no cooldown running" end
    wrote, why = WFJ.TimeLine.writeDuration(fs, duration)
    if Tooltip.trace then
      local hasSecret = type(duration) ~= "table" and type(duration.HasSecretValues) == "function"
        and select(2, pcall(duration.HasSecretValues, duration)) or "?"
      why = ("%s (duration %s, secret values %s, formatter: %s)"):format(tostring(why), type(duration),
        tostring(hasSecret), WFJ.TimeLine.status())
    end
  else
    local get, clock = Compat.resolve("C_Item.GetItemCooldown"), Compat.resolve("GetTime")
    if type(get) ~= "function" or type(clock) ~= "function" then return nil, "no item cooldown API" end
    local ok, start, duration = pcall(get, id)
    if not ok or anySecretOf(start, duration) or type(start) ~= "number" or type(duration) ~= "number" then
      return nil, "item cooldown hidden"
    end
    wrote, why = WFJ.TimeLine.writeSeconds(fs, start + duration - clock())
  end
  if wrote then dressHidden(frame, fs, clientText) end
  return wrote, why
end

-- One hidden pass over a spell or item tooltip. → rows written, how (the trace)
local function showHidden(frame, kind, id, lines)
  local area = kind == "item.description" and "items" or "spells"
  local surface = surfaceOf(frame)
  -- the records of the last readable pass hold text the client has since rewritten; dropping them would read it
  WFJ.Render.discard(surface)
  if WFJ.State.enabled == false or WFJ.Modifier.isDown() or not WFJ.State.areaEnabled(area) then
    undressHidden(frame, true)
    return hiddenDone(0, "English wanted")
  end
  if type(id) ~= "number" or anySecretOf(id) then return hiddenDone(0, "the spell or item itself is hidden") end
  local how = {}
  local rows, hiddenCount, hiddenRowsList = apiRows(kind, id)
  if not rows then
    how[#how + 1] = hiddenCount -- the reason
    rows, hiddenCount = {}, 0
  else
    how[#how + 1] = ("data rows %d%s"):format(#rows,
      hiddenCount > 0 and (", hidden: " .. hiddenRowsList) or "")
    if Tooltip.trace then
      local enum = Compat.resolve("Enum.TooltipDataLineType")
      local names = {}
      if type(enum) == "table" then for k, v in pairs(enum) do names[v] = k end end
      for i, r in ipairs(rows) do
        how[#how + 1] = ("data %d %s %s%s"):format(i, r.type ~= nil and (names[r.type] or tostring(r.type)) or "?",
          r.hidden and "<hidden>" or ("%q"):format(r.left), r.right and (" | " .. ("%q"):format(r.right)) or "")
      end
    end
  end
  local texts = {}
  for i, r in ipairs(rows) do texts[i] = r.left end
  local first, last = dataRun(kind, id, texts, rows)
  if first and rows[first].hidden then last = first end -- the run is one hidden row: its English comes from the API
  if first and not rows[first].hidden and texts[first] == "" then first, last = nil, nil end
  local frameAnchor = kind == "spell.description" and frameDescriptionRow(frame) or nil
  local map, extra = {}, {}
  if #rows > 0 then
    if kind == "item.description" and #lines ~= #rows then
      how[#how + 1] = ("the frame has %d rows, the client's data %d, and an item's rows carry no kind to place by")
        :format(#lines, #rows)
    else
      map, extra = placeRows(#lines, #rows, frameAnchor, first)
      if not map then how[#how + 1] = extra; map, extra = {}, {} end
    end
  end
  if Tooltip.trace then
    local pairsOut = {}
    for fi = 1, #lines do if map[fi] then pairsOut[#pairsOut + 1] = fi .. "=" .. map[fi] end end
    how[#how + 1] = ("frame description row %s, data description row %s, map %s, extra %s"):format(
      tostring(frameAnchor), tostring(first), table.concat(pairsOut, " "), table.concat(extra, ","))
  end
  -- the description: the data's row when readable, else (a spell) the description API's own string, on the frame
  -- row the client typed as the description or the row the placing gave it
  local descRow = frameAnchor
  if not descRow and first then
    for fi, di in pairs(map) do
      if di == first then descRow = fi end
    end
  end
  local descEn, descSource
  if first and not rows[first].hidden then
    descEn, descSource = texts[first], "the client's data"
  elseif kind == "spell.description" then
    local d = Tooltip.spellDescription(id)
    if type(d) == "string" and d ~= "" and not anySecretOf(d) then descEn, descSource = d, "the spell API" end
  end
  local runArgs = (kind == "item.description" and first and descEn) and peelTrailer(texts, first, last) or nil
  if runArgs then -- only an ungated translation takes the trailer's Japanese; a gated one keeps the whole line
    local lookup = WFJ.Lookup and WFJ.Lookup.get
    local entry = type(lookup) == "function" and lookup(kind, id) or nil
    if not (entry and entry.status == ".") then runArgs = nil end
  end
  local index = WFJ.UIIndex
  local rights = Tooltip.lines(frame, "Right")
  local name = (rows[1] and not rows[1].hidden) and texts[1] or nil
  local n, runApplied = 0, false
  local function ui(en, row1)
    if not index or type(en) ~= "string" or en == "" then return nil end
    local key, args = index:match(en)
    if not key and row1 and WFJ.Labels then key, args = index:matchOnly(en, WFJ.Labels.families("DispelType").only) end
    if not key then return nil end
    return WFJ.Render.preview(surface, en, nil, "ui", "ui", key, { args = args })
  end
  if descRow and descEn and lines[descRow] then
    local run = { descEn }
    if first and not rows[first].hidden then
      run = {}
      for j = first, last do run[#run + 1] = texts[j] end
    end
    local ja, _, action = WFJ.Render.preview(surface, descEn, nil, area, kind, id,
      { lines = run, nameScope = name, args = runArgs })
    if type(ja) == "string" then writeHidden(frame, lines[descRow].fs, ja); n = n + 1 end
    runApplied = action == "apply"
    how[#how + 1] = ("description row %d from %s"):format(descRow, descSource)
  else
    how[#how + 1] = "no description: " .. (descRow and "its English is hidden" or "no row for it")
  end
  for fi = 1, #lines do
    local di = map[fi]
    local row = di and rows[di]
    if row and not row.hidden and fi ~= descRow then
      local fs, en = lines[fi].fs, texts[di]
      if first and di > first and di <= last then
        if runApplied then writeHidden(frame, fs, WFJ.Render.BLANK); n = n + 1 end
      elseif fi > 1 and en ~= name then
        local ja = ui(en)
        if type(ja) == "string" then writeHidden(frame, fs, ja); n = n + 1 end
      end
    end
    if row and not row.hidden and row.right and rights[fi] then
      local ja = ui(row.right, fi == 1)
      if type(ja) == "string" then writeHidden(frame, rights[fi].fs, ja); n = n + 1 end
    end
  end
  -- one hidden data row is the cooldown countdown (the one secret in a spell or item tooltip): that frame row is
  -- written from the cooldown as well; more than one means the data hides something else, which is left alone
  if hiddenCount == 1 then
    for fi = 2, #lines do
      local row = map[fi] and rows[map[fi]]
      if row and row.hidden and fi ~= descRow then extra[#extra + 1] = fi end
    end
  elseif hiddenCount > 1 then
    how[#how + 1] = "hidden data rows left as the client wrote them"
  end
  table.sort(extra)
  for _, fi in ipairs(extra) do
    local ok, wrote, note = pcall(writeCountdown, frame, lines[fi].fs, kind, id)
    how[#how + 1] = ("countdown row %d: %s"):format(fi, ok and tostring(note) or ("refused: " .. tostring(wrote)))
    if ok and wrote then n = n + 1 end
  end
  return hiddenDone(n, table.concat(how, "; "))
end

-- A tooltip's item: (name, link). GameTooltip and ItemRefTooltip answer GetItem; a comparison tooltip only carries
-- its tooltip data, read through Blizzard's own TooltipUtil.GetDisplayedItem
-- [verified: blizzard_sharedxmlgame/tooltip/tooltiputil.lua:9-21].
function Tooltip.itemOf(frame)
  if type(frame.GetItem) == "function" then return frame:GetItem() end
  local displayed = Compat.resolve("TooltipUtil.GetDisplayedItem")
  if type(displayed) ~= "function" then return nil end
  local ok, name, link = pcall(displayed, frame)
  if not ok then return nil end
  return name, link
end

-- The Item post-call's target.
function Tooltip.onItem(frame)
  if inRefit[frame] then return 0 end -- our own refit re-runs the post-call; nothing new to read
  local itemName, link = Tooltip.itemOf(frame)
  local lines = Tooltip.lines(frame)
  local texts = {}
  for i, l in ipairs(lines) do texts[i] = l.text end
  -- hidden rows: nothing is read, matched or dropped (dropping a record reads its widget); the link is checked
  -- after the texts, since the client may hide it too, and then the owner's action slot names the item
  if anySecret(texts) or anySecretOf(link) then
    local id = (type(link) == "string" and not anySecretOf(link)) and tonumber(link:match("item:(%d+)")) or nil
    id = id or actionIdOf(frame, "item")
    local n, why = showHidden(frame, "item.description", id, lines)
    traceFrame(frame, "secret item", id, lines, ("-> wrote %d (%s)"):format(n, why))
    return n
  end
  local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
  if not id or id <= 0 then
    WFJ.Render.forget(surfaceOf(frame))
    traceFrame(frame, "item without an id", nil, lines, "-> 0 (link " .. plain(link) .. ")")
    return 0
  end
  traceFrame(frame, "item as the client laid it out", id, lines, "")
  local first, last = Tooltip.itemRun(texts)
  local runArgs = first and peelTrailer(texts, first, last) or nil
  -- The run is read before we write (the client rewrote every line); the Collector refuses our own text anyway.
  if first then WFJ.Collector.record("item", id, "description", table.concat(texts, "\n", first, last)) end
  if runArgs then -- only an ungated translation takes the trailer's Japanese; a gated one keeps the whole line
    local lookup = WFJ.Lookup and WFJ.Lookup.get
    local entry = type(lookup) == "function" and lookup("item.description", id) or nil
    if not (entry and entry.status == ".") then runArgs = nil end
  end
  -- No run still has structural lines.
  local n = show(frame, "items", "item.description", id, lines, first, last, itemName, runArgs)
  traceFrame(frame, "readable item", id, lines, ("-> rendered %d"):format(n))
  -- the same tooltip one frame later, as the client drew it: a wrap that moves after this pass shows there
  local after = Tooltip.trace and Compat.resolve("C_Timer.After")
  if type(after) == "function" then
    after(0, function() traceFrame(frame, "item one frame later", id, Tooltip.lines(frame), "") end)
  end
  return n
end

-- The Spell post-call's target.
function Tooltip.onSpell(frame)
  if inRefit[frame] then return 0 end
  local spellName, id = frame:GetSpell()
  local lines = Tooltip.lines(frame)
  local texts = {}
  for i, l in ipairs(lines) do texts[i] = l.text end
  -- hidden rows: nothing is read, matched or dropped (dropping a record reads its widget); the id is checked after
  -- the texts, since the client may hide it too, and then the owner's action slot names the spell
  if anySecret(texts) then
    if type(id) ~= "number" or anySecretOf(id) then id = actionIdOf(frame, "spell") end
    local n, why = showHidden(frame, "spell.description", id, lines)
    traceFrame(frame, "secret spell", id, lines, ("-> wrote %d (%s)"):format(n, why))
    return n
  end
  if type(id) ~= "number" or anySecretOf(id) or id <= 0 then WFJ.Render.forget(surfaceOf(frame)); return 0 end
  local description = Tooltip.spellDescription(id)
  if anySecretOf(description) then
    local n, why = showHidden(frame, "spell.description", id, lines)
    traceFrame(frame, "secret description", id, lines, ("-> wrote %d (%s)"):format(n, why))
    return n
  end
  -- Only the API's string becomes data: the positional fallback is a guess.
  if description and description ~= "" then WFJ.Collector.record("spell", id, "description", description) end
  local i = Tooltip.spellLine(texts, description)
  local how = ""
  if not i and type(description) == "string" and description ~= "" then
    -- the API's text differs from the tooltip's line (a trainer's spell the player has not learned): the row the
    -- client typed SpellDescription is the description, still gated by the live line's numbers
    i = frameDescriptionRow(frame)
    how = (" (api description %q differs; typed row %s)"):format(plain(description), tostring(i))
  end
  -- "spell.description": a bare "spell" would not name one field (spells also have `aura`)
  local n = show(frame, "spells", "spell.description", id, lines, i, i, spellName)
  traceFrame(frame, "readable spell", id, lines, ("-> rendered %d%s"):format(n, how))
  return n
end

-- The lines a comparison tooltip gets after its item post-call (see the header). → the number shown
local COMPARE_KEYS = { "ITEM_DELTA_DESCRIPTION", "ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION",
  "ITEM_COMPARISON_SWAP_ITEM_MAINHAND_DESCRIPTION", "ITEM_COMPARISON_SWAP_ITEM_OFFHAND_DESCRIPTION",
  "ITEM_COMPARISON_CYCLING_DISABLED_MSG_MAINHAND", "ITEM_COMPARISON_CYCLING_DISABLED_MSG_OFFHAND" }
Tooltip.COMPARE_KEYS = COMPARE_KEYS

-- A stat change line colours its number on its own ("|cffff2020-11|r Armor", seen in game): the line is matched with
-- its colour codes taken out, and an argument the client had coloured gets its colour back in the Japanese.
-- → key, args | nil
function Tooltip.matchColoured(index, text)
  local key, args = index:match(text)
  if key then return key, args end
  local bare = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  if bare == text then return nil end
  local shared
  key, shared = index:match(bare)
  if not key then return nil end
  -- the index memoizes `args` per text: a copy takes the colour, never the memo
  args = {}
  for k, v in pairs(shared or {}) do args[k] = v end
  for i, a in pairs(shared or {}) do
    if type(i) == "number" and type(a) == "string" and a ~= "" then
      local coloured = text:match("(|c%x%x%x%x%x%x%x%x" .. a:gsub("%p", "%%%0") .. "|r)")
      if coloured then args[i] = coloured end
    end
  end
  return key, args
end
-- A stat change with no template of its own: "<signed number> <short stat name>" ("+0.7 damage per second", the
-- ITEM_MOD_*_SHORT names the client's C_TooltipComparison.GetItemComparisonDelta writes), the number possibly
-- coloured. The name must be one of those stat names; it shows as "<Japanese name> <number as written>".
-- → key, args | nil
local statNameKeys = setmetatable({}, { __mode = "k" }) -- index → the list of its stat name keys
function Tooltip.matchStatChange(index, text)
  local bare = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local name = bare:match("^[%+%-][%d%.,]+ (.+)$")
  if not name or #text <= #name + 1 or text:sub(-#name - 1) ~= " " .. name then return nil end
  local keys = statNameKeys[index]
  if not keys then
    keys = {}
    for k in pairs(index.rows or {}) do
      if WFJ.UIStrings.isStatNameKey(k) then keys[#keys + 1] = k end
    end
    statNameKeys[index] = keys
  end
  local key, args = index:matchOnly(name, keys)
  if not key or args ~= nil then return nil end
  return key, { form = "number", rest = text:sub(1, #text - #name - 1) }
end

local COMPARE_HEADER_KEYS = { "EQUIPPED", "IF_EQUIPPED_TOGETHER" }
Tooltip.COMPARE_HEADER_KEYS = COMPARE_HEADER_KEYS
function Tooltip.onCompareShow(frame)
  local index = WFJ.UIIndex
  if inRefit[frame] or not index or not Tooltip.itemOf(frame) then return 0 end
  local surface, refit, n = surfaceOf(frame), refitFor(frame), 0
  inRefit[frame] = true
  local ok, err = pcall(function()
    -- the "Equipped" tab above the comparison (tooltipcomparisonmanager.lua:241-247)
    local header = type(frame.CompareHeader) == "table" and frame.CompareHeader.Label or nil
    local htext = type(header) == "table" and type(header.GetText) == "function" and header:GetText() or nil
    if type(htext) == "string" and htext ~= "" and not anySecret({ htext }) then
      local key = index:matchOnly(htext, COMPARE_HEADER_KEYS)
      if key and WFJ.Render.show(surface, "ui.header", header, htext, "ui", "ui", key, {}) then n = n + 1 end
    end
    -- after the delta header, each line is a stat change the client formats ("-11 Armor"): a stat template
    local deltas = false
    for i, l in ipairs(Tooltip.lines(frame)) do
      local key, args
      if l.text ~= "" then
        key, args = index:matchOnly(l.text, COMPARE_KEYS)
        if key == "ITEM_DELTA_DESCRIPTION" or key == "ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION" then
          deltas = true
        elseif not key and deltas and not anySecret({ l.text }) then
          key, args = Tooltip.matchColoured(index, l.text)
          if not key then key, args = Tooltip.matchStatChange(index, l.text) end
        end
      end
      local ctx = { args = args, refit = refit }
      if key and WFJ.Render.show(surface, "ui.L" .. i, l.fs, l.text, "ui", "ui", key, ctx) then n = n + 1 end
    end
  end)
  inRefit[frame] = false
  if not ok then error(err, 0) end
  if n > 0 then refit() end
  traceFrame(frame, "comparison lines", nil, Tooltip.lines(frame), ("-> rendered %d"):format(n))
  return n
end

function Tooltip.release(frame)
  undressHidden(frame)
  return WFJ.Render.release(surfaceOf(frame))
end

-- → resolved frames, declared frames, spell-description API present, the hook path taken, the aura methods
-- served (6 through the UnitAura post-call). Each later value is additive; callers that want fewer are unaffected.
function Tooltip.resolved()
  return resolvedFrames, #Tooltip.FRAMES, Compat.get(DECLARE, "spellDescription") ~= nil, Tooltip.path, auraHooks
end

-- The client's modern tooltip system, or nil when this client has none. Forever's tooltips are
-- the `mainline` flavour: the item / spell OnTooltipSet* scripts are not scripts on them (GameTooltip:HasScript
-- returns false for them in game), and the client's own
-- blizzard_sharedxmlgame/tooltip/tooltipdatahandler.lua registers handlers through
-- TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.<type>, fn) instead. → processor, types | nil
-- These two go through Compat.resolve, not Compat.declare: they are what the item / spell / aura hooks run through,
-- and their absence is reported by `/wfj debug` through the hook path (Tooltip.resolved), not as a missing widget.
function Tooltip.modern()
  local processor = Compat.resolve("TooltipDataProcessor")
  if type(processor) ~= "table" or type(processor.AddTooltipPostCall) ~= "function" then return nil end
  local types = Compat.resolve("Enum.TooltipDataType")
  if type(types) ~= "table" or types.Item == nil or types.Spell == nil then return nil end
  return processor, types
end

-- A data-processor post-call fires for every tooltip that uses the system, including anonymous ones and ones this
-- addon never declared; Render keys on the surface name, so only the six declared frames are ours. `want` is the
-- Enum.TooltipDataType this handler registered for; the client's own helpers filter with IsTooltipType
-- (blizzard_sharedxmlgame/tooltip/tooltiputil.lua), and where that method is absent the registration's own type is
-- trusted. A frame missing the reader `on*` needs (GetItem / GetSpell) is refused, never called.
-- → the frame | nil
-- With the trace on, a refused frame leaves one line saying which frame and why, so a tooltip that never turns
-- Japanese shows up in the trace instead of leaving no pass at all; the same line twice in a row is kept once.
local function traceRefusal(tt, want, why)
  local t = Tooltip.trace
  if not t then return end
  local ok, name = pcall(function() return tt:GetName() end)
  local line = ("%s refused (type %s): %s"):format(ok and plain(name) or "?", plain(want), why)
  if t[#t] ~= line then t[#t + 1] = line end
end

local function dataFrame(tt, want, reader)
  if type(tt) ~= "table" or type(tt.GetName) ~= "function" then return nil end
  if type(tt.IsTooltipType) == "function" and not tt:IsTooltipType(want) then
    traceRefusal(tt, want, "IsTooltipType is false")
    return nil
  end
  local name = tt:GetName()
  if type(name) ~= "string" or not Tooltip.IS_SURFACE[name] then
    traceRefusal(tt, want, "not one of the declared frames")
    return nil
  end
  if type(tt[reader]) ~= "function" then
    traceRefusal(tt, want, "no " .. reader)
    return nil
  end
  return tt
end

-- The GameTooltip methods that show an aura → the C_UnitAuras getter that names it from the same arguments.
-- SetUnitBuff / SetUnitDebuff take (unit, index, filter) and read the helpful / harmful list; the instance-id
-- methods take (unit, auraInstanceID, filter), and the getter ignores the filter.
Tooltip.AURA_METHODS = {
  SetUnitAura = "GetAuraDataByIndex",
  SetUnitBuff = "GetBuffDataByIndex",
  SetUnitDebuff = "GetDebuffDataByIndex",
  SetUnitAuraByAuraInstanceID = "GetAuraDataByAuraInstanceID",
  SetUnitBuffByAuraInstanceID = "GetAuraDataByAuraInstanceID",
  SetUnitDebuffByAuraInstanceID = "GetAuraDataByAuraInstanceID",
}
Tooltip.AURA_ORDER = { "SetUnitAura", "SetUnitBuff", "SetUnitDebuff", "SetUnitAuraByAuraInstanceID",
  "SetUnitBuffByAuraInstanceID", "SetUnitDebuffByAuraInstanceID" }
-- On Forever each method is a TooltipDataHandlerMixin accessor that records {getterName, getterArgs} as the
-- tooltip's info (blizzard_sharedxmlgame/tooltip/tooltipdatahandler.lua:488–503, accessor table :591–597). The
-- UnitAura post-call reads them back: the method, and the same arguments the hook path would have seen.
Tooltip.AURA_GETTERS = {
  GetUnitAura = "SetUnitAura", GetUnitBuff = "SetUnitBuff", GetUnitDebuff = "SetUnitDebuff",
  GetUnitAuraByAuraInstanceID = "SetUnitAuraByAuraInstanceID",
  GetUnitBuffByAuraInstanceID = "SetUnitBuffByAuraInstanceID",
  GetUnitDebuffByAuraInstanceID = "SetUnitDebuffByAuraInstanceID",
}

-- The aura's spell id, or nil. Forever marks these reads SecretWhenUnitAuraRestricted: in a restricted context a
-- value can be one the addon may not compare, so every read and test is protected and any doubt is "no aura".
function Tooltip.auraSpellId(method, unit, key, filter)
  local getter = Tooltip.AURA_METHODS[method]
  local get = getter and Compat.get(DECLARE, getter)
  if type(get) ~= "function" then return nil end
  -- the instance-id getter is (unit, auraInstanceID): the filter its method was called with is not an argument
  local ok, data
  if getter == "GetAuraDataByAuraInstanceID" then ok, data = pcall(get, unit, key)
  else ok, data = pcall(get, unit, key, filter) end
  if not ok or type(data) ~= "table" then return nil end
  local okId, id = pcall(function()
    local v = data.spellId
    if type(v) == "number" and v > 0 and v == math.floor(v) then return v end
    return nil
  end)
  return okId and id or nil
end

-- Line 2 is the aura text, unless it is empty or a UI-dictionary line ("25 min remaining"); then there is none.
function Tooltip.auraLine(texts)
  local text = texts[2]
  if type(text) ~= "string" or text == "" then return nil end
  local index = WFJ.UIIndex
  if index and index:match(text) then return nil end
  return 2
end

-- The Forever UnitAura post-call: the method and its arguments, read back from the tooltip's info. It fires on the
-- first build AND on every rebuild: TOOLTIP_DATA_UPDATE → RefreshData → RebuildFromTooltipInfo → ProcessInfo
-- rewrites the lines from C_TooltipInfo without calling any of the six methods (gametooltip.lua:963–979,
-- tooltipdatahandler.lua:358–385), so a method hook alone would let a rebuild put the English back mid-hover.
-- → method, unit, key, filter | nil
function Tooltip.auraCall(frame)
  local ok, method, unit, key, filter, count = pcall(function()
    local info = frame:GetPrimaryTooltipInfo()
    local args = info and info.getterArgs
    if type(args) ~= "table" then return nil end
    local data = info.tooltipData
    local n = data and type(data.lines) == "table" and #data.lines or nil
    return Tooltip.AURA_GETTERS[info.getterName], args[1], args[2], args[3], n
  end)
  if not ok or not method then return nil end
  return method, unit, key, filter, count
end

-- The aura handler: (frame, method, <that method's arguments>).
Tooltip.auraErrors = 0

local function auraImpl(frame, method, unit, key, filter, clientLines)
  if inRefit[frame] then return 0 end
  local lines = Tooltip.lines(frame)
  local texts = {}
  for i, l in ipairs(lines) do texts[i] = l.text end
  local how = Tooltip.trace and ("%s(%s, %s, %s) client rows=%s"):format(plain(method), plain(unit), plain(key),
    plain(filter), plain(clientLines)) or ""
  -- hidden rows: which buff this is stays hidden too (its aura id, spell and icon are secret, and the aura APIs
  -- refuse a secret id from an addon), so nothing can be looked up; the client's English stays, and the frame's
  -- records are let go without reading the rows they held
  if anySecret(texts) then
    WFJ.Render.discard(surfaceOf(frame))
    traceFrame(frame, "secret aura", nil, lines, "-> left, the client hides which buff it is (" .. how .. ")")
    return 0
  end
  local id = Tooltip.auraSpellId(method, unit, key, filter)
  if not id then
    traceFrame(frame, "readable aura", nil, lines, "-> left, no spell id (" .. how .. ")")
    WFJ.Render.forget(surfaceOf(frame)); return 0
  end
  local i = Tooltip.auraLine(texts)
  -- Forever: line 2 only when the client wrote it; a line another addon appended (an id line, the PTR
  -- reporter's hint) is past the client's own count and is never the aura text
  if i and clientLines and i > clientLines then i = nil end
  -- Line 2 is a positional choice, and the Collector takes no positional guess as data. It records the aura
  -- line only for a spell whose `aura` ships: evidence the spell has aura text for line 2 to be.
  local lookup = WFJ.Lookup and WFJ.Lookup.get
  if i and type(lookup) == "function" and lookup("spell.aura", id) ~= nil then
    WFJ.Collector.record("spell", id, "aura", texts[i])
  end
  local n = show(frame, "spells", "spell.aura", id, lines, i, i, texts[1])
  traceFrame(frame, "readable aura", id, lines, ("-> rendered %s, aura row %s, shipped aura text %s (%s)"):format(
    plain(n), plain(i), tostring(type(lookup) == "function" and lookup("spell.aura", id) ~= nil), how))
  return n
end

-- The aura handler: (frame, method, <that method's arguments>[, the client's own line count]). Guarded
-- as a whole: it runs from the client's buff-frame OnUpdate, so an error would repeat every frame. It is counted
-- (`Tooltip.auraErrors`, `/wfj debug`) and the tooltip is left as the client wrote it.
function Tooltip.onAura(frame, method, unit, key, filter, clientLines)
  local ok, n = pcall(auraImpl, frame, method, unit, key, filter, clientLines)
  if ok then return n end
  Tooltip.auraErrors = Tooltip.auraErrors + 1
  pcall(traceFrame, frame, "aura error", nil, Tooltip.lines(frame), "-> " .. tostring(n))
  return 0
end

Tooltip.path = nil

local hooked = false

-- Called by Main after Compat.init. Declares every name, hooks each frame that resolves.
function Tooltip.init()
  for _, name in ipairs(Tooltip.FRAMES) do Compat.declare(DECLARE, name, { name }) end
  for _, t in ipairs(TRIGGERS) do Compat.declare(DECLARE, t.key, { t.global }) end
  -- The live Forever client has no global GetSpellDescription; modern clients carry it as
  -- C_Spell.GetSpellDescription, which Compat resolves as a dotted candidate.
  Compat.declare(DECLARE, "spellDescription", { "GetSpellDescription", "C_Spell.GetSpellDescription" })
  for _, getter in pairs(Tooltip.AURA_METHODS) do Compat.declare(DECLARE, getter, { "C_UnitAuras." .. getter }) end
  if hooked then return resolvedFrames end
  resolvedFrames = 0
  -- One registration per data type, for the whole client (not per frame). OnHide is a plain widget script and stays
  -- per frame. Without the processor (not this client) nothing is hooked for item / spell / aura.
  local processor, types = Tooltip.modern()
  Tooltip.path = processor and "dataprocessor" or "none"
  if processor then
    processor.AddTooltipPostCall(types.Item, function(tt)
      -- a comparison tooltip has no GetItem (ShoppingTooltipTemplate is TooltipDataHandlerMixin only,
      -- blizzard_gametooltip/mainline/gametooltip.xml:109); it carries its tooltip data, which Tooltip.itemOf reads
      local frame = dataFrame(tt, types.Item, type(tt) == "table" and tt.GetItem == nil and "GetPrimaryTooltipData"
        or "GetItem")
      if frame then Tooltip.onItem(frame) end
    end)
    processor.AddTooltipPostCall(types.Spell, function(tt)
      local frame = dataFrame(tt, types.Spell, "GetSpell")
      if frame then Tooltip.onSpell(frame) end
    end)
  end
  for _, name in ipairs(Tooltip.FRAMES) do
    local frame = Compat.get(DECLARE, name)
    if frame and frame.HookScript then
      resolvedFrames = resolvedFrames + 1
      frame:HookScript("OnHide", function(self) Tooltip.release(self) end)
      if HEADED[name] and type(frame.Show) == "function" then -- the comparison's appended lines
        hooksecurefunc(frame, "Show", Tooltip.onCompareShow)
        -- Forever's comparison manager shows its frames with SetShown, never Show
        -- [verified: blizzard_sharedxmlgame/tooltip/tooltipcomparisonmanager.lua:53-54]
        if type(frame.SetShown) == "function" then
          hooksecurefunc(frame, "SetShown", function(f, shown) if shown then Tooltip.onCompareShow(f) end end)
        end
      end
    end
  end
  -- Auras, on GameTooltip only (every aura caller in the client's UI uses it: nameplates and the
  -- cooldown viewer through GetAppropriateTooltip(), which is GameTooltip in game): the UnitAura post-call, which
  -- also sees every rebuild.
  auraHooks = 0
  if processor and types.UnitAura ~= nil then
    processor.AddTooltipPostCall(types.UnitAura, function(tt)
      local frame = dataFrame(tt, types.UnitAura, "GetPrimaryTooltipInfo")
      if not frame then
        pcall(traceNote, ("aura post-call on %s: not one of ours"):format(
          type(tt) == "table" and type(tt.GetName) == "function" and plain(tt:GetName()) or "?"))
        return
      end
      local method, unit, key, filter, count = Tooltip.auraCall(frame)
      if method then Tooltip.onAura(frame, method, unit, key, filter, count)
      else pcall(traceFrame, frame, "aura", nil, Tooltip.lines(frame), "-> left, getter not known") end
    end)
    auraHooks = #Tooltip.AURA_ORDER
    -- the trace only: which GameTooltip call opened a buff tooltip, so a buff the post-call never sees still shows
    local tooltip = Compat.get(DECLARE, "GameTooltip")
    if type(tooltip) == "table" then
      for _, method in ipairs(Tooltip.AURA_ORDER) do
        if type(tooltip[method]) == "function" then
          hooksecurefunc(tooltip, method, function(_, unit, key, filter)
            if Tooltip.trace then
              pcall(traceNote, ("%s(%s, %s, %s) called"):format(method, plain(unit), plain(key), plain(filter)))
            end
          end)
        end
      end
    end
  end
  for _, event in ipairs({ "enabled", "area", "modifier" }) do
    WFJ.State.on(event, function() pcall(Tooltip.restoreHidden) end)
  end
  -- Latched last, not first: if a registration or a hook raises, Main's guard records the failure and the
  -- surface stays retryable instead of being stuck permanently half-hooked (item hooked, spell not, no OnHide).
  hooked = true
  return resolvedFrames
end
