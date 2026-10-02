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
-- *ByAuraInstanceID twins: buff frame, target, party, raid, compact frames, nameplates [verified: Forever 1.60.1
-- blizzard_buffframe/buffframe.lua:1145–1149, unitframe/mainline/targetframe.xml:45,
-- shared/partymemberframe.lua:202–206]. Forever types them Enum.TooltipDataType.UnitAura and GetSpell answers only
-- for Spell (tooltiputil.lua:25–31), so the Spell post-call never sees one; the surface registers a UnitAura
-- post-call, which fires on the first build and on every rebuild. The spell id comes from C_UnitAuras with the
-- call's own arguments, as Blizzard's PTR reporter does (blizzard_ptrfeedback_tooltips.lua:22–32). The aura text is
-- line 2 [likely: tooltipdatahandler.lua writes it from C_TooltipInfo data; in-game check in
-- docs/testing/strategy.md]: refused when empty or a UI-dictionary line, and the runtime gate refuses a line
-- whose names and numbers do not fit. An owner with UpdateTooltip re-shows the aura about 5 times a second while
-- hovered; each pass forgets and re-renders, as item tooltips do.
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

local function refitFor(frame)
  local fn = refits[frame]
  if fn then return fn end
  fn = function()
    if inRefit[frame] then return end
    inRefit[frame] = true
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
local function showRun(surface, area, kind, id, lines, first, last, refit, runArgs)
  local texts = {}
  for i = first, last do texts[#texts + 1] = lines[i].text end
  local n = 0
  -- line 1 is the name: never replaced, never a number source, but a name the Japanese may legitimately use
  if WFJ.Render.show(surface, "desc", lines[first].fs, lines[first].text, area, kind, id,
      { lines = texts, nameScope = lines[1] and lines[1].text or nil, refit = refit, args = runArgs }) then
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

-- The lines a pass rendered, per frame: { kind, id, n = line count, area, [i] = the text written }. An action
-- button's tooltip turns secret while its spell casts or cools down and turns back after, and the client rewrites
-- the lines each time; a secret pass cannot read or match them, so it puts back what the last readable pass wrote
-- for the same spell or item with the same line count, instead of leaving the English to flash in between. Writing
-- a line is allowed while reading it is not. Forgotten on the frame's OnHide.
local rendered = setmetatable({}, { __mode = "k" })

local function remember(frame, kind, id, area, lines)
  local snap = { kind = kind, id = id, n = #lines, area = area }
  for i, l in ipairs(lines) do
    local now = l.fs:GetText()
    if now ~= l.text then snap[i] = now end -- l.text: the client's line as read before this pass wrote
  end
  rendered[frame] = snap
end

-- A secret pass: the last readable pass's Japanese written back, when nothing says it no longer applies.
-- → lines written
local function reapply(frame, kind, id, lines)
  local snap = rendered[frame]
  if not snap or snap.kind ~= kind or snap.id ~= id or snap.n ~= #lines then return 0 end
  if WFJ.State.enabled == false or WFJ.Modifier.isDown() or not WFJ.State.areaEnabled(snap.area) then return 0 end
  local n = 0
  for i, l in ipairs(lines) do
    if snap[i] then
      l.fs:SetText(snap[i])
      WFJ.Font.bundle(l.fs)
      n = n + 1
    end
  end
  return n
end

local function show(frame, area, kind, id, lines, first, last, name, runArgs)
  local surface = surfaceOf(frame)
  WFJ.Render.forget(surface)
  if first and lines[first].text == "" then first, last = nil, nil end
  local refit = refitFor(frame)
  -- One refit for the whole hover: the per-record refit is a no-op while inRefit is set, then Show() runs once.
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

-- The Item post-call's target. Returns the number of records written.
function Tooltip.onItem(frame)
  if inRefit[frame] then return 0 end
  local itemName, link = frame:GetItem()
  local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
  if not id or id <= 0 then WFJ.Render.forget(surfaceOf(frame)); return 0 end
  local lines = Tooltip.lines(frame)
  local texts = {}
  for i, l in ipairs(lines) do texts[i] = l.text end
  -- restricted: nothing is read or matched, forgetting included (forget compares the widget's text)
  if anySecret(texts) then return reapply(frame, "item.description", id, lines) end
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
  remember(frame, "item.description", id, "items", lines)
  return n
end

-- The Spell post-call's target.
function Tooltip.onSpell(frame)
  if inRefit[frame] then return 0 end
  local spellName, id = frame:GetSpell()
  if type(id) ~= "number" or id <= 0 then WFJ.Render.forget(surfaceOf(frame)); return 0 end
  local lines = Tooltip.lines(frame)
  local texts = {}
  for i, l in ipairs(lines) do texts[i] = l.text end
  local description = Tooltip.spellDescription(id)
  -- restricted: nothing is read or matched, forgetting included (forget compares the widget's text)
  if anySecret(texts) or anySecret({ description }) then return reapply(frame, "spell.description", id, lines) end
  -- Only the API's string becomes data: the positional fallback is a guess.
  if description and description ~= "" then WFJ.Collector.record("spell", id, "description", description) end
  local i = Tooltip.spellLine(texts, description)
  -- "spell.description": a bare "spell" would not name one field (spells also have `aura`)
  local n = show(frame, "spells", "spell.description", id, lines, i, i, spellName)
  remember(frame, "spell.description", id, "spells", lines)
  return n
end

-- The lines a comparison tooltip gets after its item post-call (see the header). → the number shown
local COMPARE_KEYS = { "ITEM_DELTA_DESCRIPTION", "ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION",
  "ITEM_COMPARISON_SWAP_ITEM_MAINHAND_DESCRIPTION", "ITEM_COMPARISON_SWAP_ITEM_OFFHAND_DESCRIPTION",
  "ITEM_COMPARISON_CYCLING_DISABLED_MSG_MAINHAND", "ITEM_COMPARISON_CYCLING_DISABLED_MSG_OFFHAND" }
Tooltip.COMPARE_KEYS = COMPARE_KEYS
function Tooltip.onCompareShow(frame)
  local index = WFJ.UIIndex
  if inRefit[frame] or not index or not (frame.GetItem and frame:GetItem()) then return 0 end
  local surface, refit, n = surfaceOf(frame), refitFor(frame), 0
  inRefit[frame] = true
  local ok, err = pcall(function()
    for i, l in ipairs(Tooltip.lines(frame)) do
      local key, args
      if l.text ~= "" then key, args = index:matchOnly(l.text, COMPARE_KEYS) end
      local ctx = { args = args, refit = refit }
      if key and WFJ.Render.show(surface, "ui.L" .. i, l.fs, l.text, "ui", "ui", key, ctx) then n = n + 1 end
    end
  end)
  inRefit[frame] = false
  if not ok then error(err, 0) end
  if n > 0 then refit() end
  return n
end

function Tooltip.release(frame)
  rendered[frame] = nil
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
local function dataFrame(tt, want, reader)
  if type(tt) ~= "table" or type(tt.GetName) ~= "function" then return nil end
  if type(tt.IsTooltipType) == "function" and not tt:IsTooltipType(want) then return nil end
  local name = tt:GetName()
  if type(name) ~= "string" or not Tooltip.IS_SURFACE[name] then return nil end
  if type(tt[reader]) ~= "function" then return nil end
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
  -- restricted: leave everything alone, forgetting included (forget compares the widget's text)
  if anySecret(texts) then return 0 end
  local id = Tooltip.auraSpellId(method, unit, key, filter)
  if not id then WFJ.Render.forget(surfaceOf(frame)); return 0 end
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
  return show(frame, "spells", "spell.aura", id, lines, i, i, texts[1])
end

-- The aura handler: (frame, method, <that method's arguments>[, the client's own line count]). Guarded
-- as a whole: it runs from the client's buff-frame OnUpdate, so an error would repeat every frame. It is counted
-- (`Tooltip.auraErrors`, `/wfj debug`) and the tooltip is left as the client wrote it.
function Tooltip.onAura(frame, method, unit, key, filter, clientLines)
  local ok, n = pcall(auraImpl, frame, method, unit, key, filter, clientLines)
  if ok then return n end
  Tooltip.auraErrors = Tooltip.auraErrors + 1
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
      local frame = dataFrame(tt, types.Item, "GetItem")
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
      if not frame then return end
      local method, unit, key, filter, count = Tooltip.auraCall(frame)
      if method then Tooltip.onAura(frame, method, unit, key, filter, count) end
    end)
    auraHooks = #Tooltip.AURA_ORDER
  end
  -- Latched last, not first: if a registration or a hook raises, Main's guard records the failure and the
  -- surface stays retryable instead of being stuck permanently half-hooked (item hooked, spell not, no OnHide).
  hooked = true
  return resolvedFrames
end
