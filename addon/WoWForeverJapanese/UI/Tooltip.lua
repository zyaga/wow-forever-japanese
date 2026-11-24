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
-- its name. The name line is never a dictionary word; while names are on it shows the name's Japanese as record
-- "name.L<i>" (kind "name", Core/Names), under the tooltip's own area. A comparison tooltip puts its "Currently
-- Equipped" header on line 1 and the name on line 2 (seen in game), so there line 1 is a header and the name is
-- found by its text.
-- A spell's first line is its name only when it holds that name: a spell the client shows with no name line starts
-- with a row of its own ("Melee Range", "Reagents: |n…"), which is matched like any other. A profession's spell names
-- its skill first ("Enchanting: Enchant Boots - Minor Speed"); with names on both names show their Japanese, and
-- only when both have one (craftHeader). The reagents and tools rows ("Reagents: |nDeathweed (5), Crystal Vial",
-- "Tools: Runed Copper Rod") are dictionary labels with a list of item names after them (UIStrings.LIST_AFTER).
-- A spell that makes an item shows that item's own lines under its rows; the tooltip data names the item in a
-- nested block, and its use line and flavour text are a run of their own under that item's id (Tooltip.madeItem).
-- An item's run is split by whose each line is (splitRun): a stat line the client writes from its own strings is a ui
-- record, the description takes only the lines its Japanese fits, and a line printing another spell shows that
-- spell's Japanese, found by the line's shape (Data/SpellShapes.lua, ADR-107). The missing marker goes only on the
-- description's own lines. The made item's run gets its "Equip: <stat template>" lines as ui records (showEquipLines).
-- Auras: a buff or debuff tooltip is GameTooltip:SetUnitAura / SetUnitBuff / SetUnitDebuff or their
-- *ByAuraInstanceID twins: buff frame, target of target, party, raid, compact frames [verified: Forever
-- 1.60.1 blizzard_buffframe/buffframe.lua:1179–1183, unitframe/mainline/targetframe.xml:45,
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

-- Enum.TooltipDataType names of the tooltips that show a spell without being a spell's tooltip.
Tooltip.SPELL_KINDS = { "Mount", "CompanionPet", "Macro" }

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

-- The run is every Equip / Use line in a row, and an item's own description may be only one of them: a staff whose
-- spell power line ("Equip: Increases damage and healing done by magical spells and effects by up to 26.") sits right
-- above its description ("Equip: Increases movement speed by 2% in …") had the 26 filled into the description's one
-- number and its spell power line folded away. When the description's Japanese fits exactly one line of the run on
-- its own (every name and number of it found in that line, the Translator's own check), the run is that line; the
-- run's other lines are then matched as stat lines, as on an item with no description. No line fitting, or a
-- Japanese of more than one paragraph, leaves the run as it was.
-- A Japanese with no name or number of its own fits every line, so that check cannot place it: a flavour line's
-- Japanese went onto the use line above it and the flavour line was folded away. Its English is plain text
-- then, so the line it was written for is the one whose words are that English, found by the entry's hash (the
-- addon holds no English). No such line, or two: the run is left as it was.
local function unprefixed(text, pre)
  for _, p in ipairs(pre) do
    if text:sub(1, #p) == p then return (text:sub(#p + 1):gsub("^%s+", "")) end
  end
  if #text > 2 and text:sub(1, 1) == '"' and text:sub(-1) == '"' then return text:sub(2, -2) end
  return text
end

-- The one line of the run that is the English with this hash, without its trigger word ("Use:") or the quotes
-- around a flavour line. → row | nil
function Tooltip.runLineOf(h1, texts, first, last)
  local N, Hh = WFJ.Normalize, WFJ.Hash
  if h1 == nil or not N or not Hh then return nil end
  local pre, found = prefixes(), nil
  for row = first, last do
    if texts[row] ~= "" and (Hh.h32x2(N.v1(unprefixed(texts[row], pre)))) == h1 then
      if found then return nil end
      found = row
    end
  end
  return found
end

-- Used for the item a spell makes (madeRun); an item's own run is split by splitRun, below.
-- → first, last, { [row] = { key, args } | false } for the other lines | nil
function Tooltip.narrowRun(id, texts, first, last, nameScope)
  if not first or not last or last == first then return first, last, nil end
  local lookup = WFJ.Lookup and WFJ.Lookup.get
  local entry = type(lookup) == "function" and lookup("item.description", id) or nil
  local ja = type(entry) == "table" and entry.ja or nil
  local align, index = WFJ.Align, WFJ.UIIndex
  -- a Japanese of several paragraphs is written for several lines of the run (a use line and its flavour text)
  if type(ja) ~= "string" or ja:find("\n") or type(align) ~= "table" or not index then return first, last, nil end
  local function duration(text) return index:duration(text, true) end -- a spell's `$d` forms, as Main's gate reads
  local fit, fits = nil, 0
  for row = first, last do
    if texts[row] ~= "" and align.check(ja, { texts[row] }, nameScope, duration) then
      fits = fits + 1
      fit = fit or row
    end
  end
  if fits > 1 then fit = Tooltip.runLineOf(entry.h1, texts, first, last) end
  if not fit then return first, last, nil end
  local others = {}
  for row = first, last do
    if row ~= fit and texts[row] ~= "" then
      local key, args = index:statLine(texts[row])
      others[row] = key and { key = key, args = args } or false
    end
  end
  return fit, fit, others
end

-- The spell an item's line prints, found by the line's shape: its wording with every value masked
-- (Align.variantKey, the twin of the key Data/SpellShapes.lua is written with, ADR-107). Nothing the client gives
-- names the spell behind one line: C_Item.GetItemSpell names one spell per item, GetItemStats only stats
-- [verified: blizzard_apidocumentationgenerated/itemdocumentation.lua:970-985, 1004-1018], and a tooltip data
-- line carries its kind but no documented spell field (tooltipinfoshareddocumentation.lua: TooltipDataLineType,
-- TooltipDataArg). Taken only when that spell's Japanese passes the gate on the line. `tail`: the Japanese of
-- the client's tail peeled off the line, added only to an ungated translation, as on the description.
-- → { spell = id, args } | nil
local function lineSpell(text, tail, duration)
  local shapes = WFJ.Data and WFJ.Data.spellShapes
  local lookup, gate, align = WFJ.Lookup and WFJ.Lookup.get, WFJ.GateText, WFJ.Align
  if type(shapes) ~= "table" or type(lookup) ~= "function" or type(gate) ~= "function" or type(align) ~= "table"
    or type(align.variantKey) ~= "function" then
    return nil
  end
  local key = align.variantKey(unprefixed(text, prefixes()), duration)
  local id = key and shapes[key]
  if type(id) ~= "number" then return nil end
  local entry = lookup("spell.description", id)
  if type(entry) ~= "table" or not gate(entry, { text }) then return nil end
  local args = (tail and entry.status == ".") and { form = "affix", before = "", after = tail } or nil
  return { spell = id, args = args }
end

-- Whose each line of an item's run is. The run is every trigger line in a row, but the item ships one
-- description, and the client may print more lines than that description was written for: an item whose
-- description was taken from another client's tables, or whose spells this client prints as stat lines
-- (seen in game: "Equip: Restores 3 Mana per 5 sec." is the client's TOOLTIP_ITEM_STAT_MANA_REGEN_INCREASE,
-- written by its compiled tooltip code with no Lua writer in the extract; the spell's own description reads
-- "mana"). So:
--   1. the item's description takes the lines its Japanese fits. A Japanese of one paragraph takes one line: the
--      one it fits, else, when it fits several, the one line among them that is not a stat line, else the line
--      whose words are its English (runLineOf). One of several paragraphs takes the longest block it fits
--      (stat lines inside it are folded into the description, as before);
--   2. every other line written from one of the client's stat strings shows the dictionary's Japanese
--      (index:statLine);
--   3. every other line shows the spell it prints (lineSpell);
--   4. a line nothing explains stays as the client wrote it, with no marker.
-- The missing marker goes only on lines the description owns. When its Japanese fits no line it owns what nothing
-- else took, when that is one place: the one line left (one paragraph) or the lines left in one block (several);
-- else nothing. A run nothing else explains at all is the description's, as before.
-- `texts`: the lines with the client's tails peeled off; `tails`: { [row] = the tail's Japanese }.
-- → first, last of the description's lines (nil when it owns none), and the other lines as
--   { [row] = { key, args } (a stat line) | { spell, args } | false (left as written) } | nil (the run is whole)
function Tooltip.splitRun(id, texts, first, last, nameScope, tails)
  local index, align = WFJ.UIIndex, WFJ.Align
  if not first or not last or not index or type(align) ~= "table" then return first, last, nil end
  local lookup = WFJ.Lookup and WFJ.Lookup.get
  local entry = type(lookup) == "function" and lookup("item.description", id) or nil
  local ja = type(entry) == "table" and type(entry.ja) == "string" and entry.ja ~= "" and entry.ja or nil
  -- a Japanese of several paragraphs is written for several lines (a use line and its flavour text); a branch
  -- line's (no plain Japanese) may be either
  local several = ja == nil or ja:find("\n") ~= nil
  local function duration(text) return index:duration(text, true) end -- a spell's `$d` forms, as Main's gate reads
  local function fits(a, b, scope)
    local lines = {}
    for row = a, b do
      if texts[row] ~= "" then lines[#lines + 1] = texts[row] end
    end
    return align.check(ja, lines, scope, duration, entry.values)
  end
  local stat = {}
  for row = first, last do
    if texts[row] ~= "" and type(index.statLine) == "function" then
      local key, args = index:statLine(texts[row])
      if key then stat[row] = { key = key, args = args } end
    end
  end
  -- the lines of `rows` that pass `keep`, or `rows` itself when none does (a test that leaves nothing decides nothing)
  local function narrowed(rows, keep)
    local out = {}
    for _, row in ipairs(rows) do
      if keep(row) then out[#out + 1] = row end
    end
    return #out > 0 and out or rows
  end
  local ownFirst, ownLast
  if ja and several then
    -- the longest block that fits, from the whole run down; two blocks of one length are a tie: none
    for span = last - first, 0, -1 do
      local found, count = nil, 0
      for a = first, last - span do
        if texts[a] ~= "" and texts[a + span] ~= "" and fits(a, a + span, nameScope) then
          found, count = a, count + 1
        end
      end
      if count == 1 then ownFirst, ownLast = found, found + span end
      if count > 0 then break end
    end
  elseif ja then
    -- the lines it fits; while several, those it fits on their own (a name found in the line, not in the item's
    -- name: "Sleep" is in "Rod of the Sleepwalker"), then those that are no stat line, then the line whose words
    -- are its English
    local rows = {}
    for row = first, last do
      if texts[row] ~= "" and fits(row, row, nameScope) then rows[#rows + 1] = row end
    end
    if #rows > 1 then rows = narrowed(rows, function(row) return fits(row, row, nil) end) end
    if #rows > 1 then rows = narrowed(rows, function(row) return not stat[row] end) end
    local fit = rows[1]
    if #rows > 1 then fit = Tooltip.runLineOf(entry.h1, texts, first, last) end
    if fit then ownFirst, ownLast = fit, fit end
  end
  if ownFirst == first and ownLast == last then return first, last, nil end
  local others, taken = {}, false
  for row = first, last do
    if texts[row] ~= "" and not (ownFirst and row >= ownFirst and row <= ownLast) then
      local s = stat[row] or lineSpell(texts[row], tails and tails[row], duration)
      others[row] = s or false
      taken = taken or s ~= nil
    end
  end
  if ownFirst then return ownFirst, ownLast, others end
  if not taken then return first, last, nil end
  if entry == nil then return nil, nil, others end
  local a, b, left = nil, nil, 0
  for row = first, last do
    if others[row] == false then a, b, left = a or row, row, left + 1 end
  end
  if not a or (left > 1 and not several) then return nil, nil, others end
  for row = a, b do
    if others[row] then return nil, nil, others end -- a line something else took sits between: not one block
  end
  for row = a, b do others[row] = nil end
  return a, b, others
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

-- A spell whose description splices in other spells' text (`$@spelldesc<id>`, `$@spellaura<id>`; their ids in
-- Data/SpellIncludes.lua): the client prints a spliced-in spell's text only once that spell's data is loaded and
-- leaves it empty before, so the line holds fewer numbers than its Japanese and stays English. The client does not
-- ask for those spells itself, so the addon does, and the line fits from then on [verified: in game, Druidic Auras
-- printed its two auras' crit chance once those spells were loaded, and Metamorphosis left Demon Charge and Demonic
-- Howl empty while theirs were not]. → how many were asked for
function Tooltip.loadIncluded(id)
  local spliced = WFJ.Data and WFJ.Data.spellIncludes and WFJ.Data.spellIncludes[id]
  local cached, load = Compat.get(DECLARE, "spellCached"), Compat.get(DECLARE, "spellLoad")
  if type(spliced) ~= "table" or type(cached) ~= "function" or type(load) ~= "function" then return 0 end
  local asked = 0
  for _, sid in ipairs(spliced) do
    if not cached(sid) then
      load(sid)
      asked = asked + 1
    end
  end
  return asked
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
  local function run()
    frame:Show()
    frame:Show()
  end
  fn = function()
    if inRefit[frame] then return end
    inRefit[frame] = true
    -- timed apart: a Show runs the client's own tooltip code (its post-calls, the comparison tooltips) again
    local ok, err = pcall(WFJ.Perf.call, "tooltip.refit", run)
    inRefit[frame] = false
    if not ok then error(err, 0) end
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

-- `flavour` = { row, from }: the item's flavour line, below the run with other lines between (Tooltip.flavourRow):
-- the run keeps the Japanese's paragraphs before `from` and the flavour line shows the rest, in the client's quotes.
local function showRun(surface, area, kind, id, lines, first, last, refit, runArgs, tag, peeled, scope, flavour)
  tag = tag or "desc"
  local texts = {}
  for i = first, last do texts[#texts + 1] = peeled and peeled[i] or lines[i].text end
  if flavour then texts[#texts + 1] = lines[flavour.row].text end -- the gate holds the Japanese to both
  local n = 0
  -- line 1 is the name: never replaced, never a number source, but a name the Japanese may legitimately use.
  -- `scope` stands in for it where the run belongs to another item than the tooltip's own (the item a spell makes)
  if WFJ.Render.show(surface, tag, lines[first].fs, lines[first].text, area, kind, id,
      { lines = texts, nameScope = scope or (lines[1] and lines[1].text) or nil, refit = refit, args = runArgs,
        partColors = runColors(lines, first, last), parts = flavour and flavour.from - 1 or nil }) then
    n = n + 1
  end
  for i = first + 1, last do
    if WFJ.Render.show(surface, tag .. "." .. i, lines[i].fs, lines[i].text, area, kind, id,
        { follow = tag, refit = refit }) then n = n + 1 end
  end
  if flavour then
    local l = lines[flavour.row]
    if WFJ.Render.show(surface, tag .. "." .. flavour.row, l.fs, l.text, area, kind, id,
        { follow = tag, from = flavour.from, head = '"', tail = '"', refit = refit }) then n = n + 1 end
  end
  return n
end

-- An item's flavour line ("\"Need bigger rock.\"", the item's own text in the client's quotes) that is not in
-- the run: on Forever the durability and requirement lines stand between an item's use or hit line and its flavour
-- text, so the run stops above them, and a Japanese written for both went whole onto the use line, the flavour line
-- left English. Taken when the item's Japanese has more paragraphs than the run has lines and the first quoted line
-- after the run comes before any other trigger line. → { row, from = the first paragraph it shows } | nil
function Tooltip.flavourRow(id, texts, first, last, stop)
  if not first then return nil end
  local lookup = WFJ.Lookup and WFJ.Lookup.get
  local entry = type(lookup) == "function" and lookup("item.description", id) or nil
  local ja = type(entry) == "table" and type(entry.ja) == "string" and entry.ja or nil
  if not ja or not ja:find("\n") then return nil end
  local paragraphs, lines = 0, 0
  for part in (ja .. "\n"):gmatch("(.-)\n") do
    if part ~= "" then paragraphs = paragraphs + 1 end
  end
  for row = first, last do
    if texts[row] ~= "" then lines = lines + 1 end
  end
  if paragraphs <= lines then return nil end
  local pre = prefixes()
  for row = last + 1, stop or #texts do
    local text = texts[row]
    if type(text) == "string" and #text > 2 and text:sub(1, 1) == '"' and text:sub(-1) == '"' then
      return { row = row, from = lines + 1 }
    end
    if isDescription(text, pre) then return nil end -- another trigger line: another run, not this item's text
  end
  return nil
end

-- Structural lines: lines 2…N, left then right, except the description lines [first, last]. A line whose
-- text is a dictionary word, template or label becomes a "ui" record with the captured values.
-- Lines only an item tooltip shows, matched by key: a free text and a word or two after it ("Sharpened (5 min)",
-- "Hearthstone missing"), and the crafter / gift lines the client may print without their colour (UIStrings.BARE).
local TOOLTIP_ONLY = { "ITEM_MISSING", "ITEM_ENCHANT_TIME_LEFT_DAYS", "ITEM_ENCHANT_TIME_LEFT_HOURS",
  "ITEM_ENCHANT_TIME_LEFT_MIN", "ITEM_ENCHANT_TIME_LEFT_SEC", "REAGENT_COST_CONSUME_CHARGES",
  "REAGENT_COST_CONSUME_SINGLE_CHARGE", "ITEM_CREATED_BY", "ITEM_WRAPPED_BY" }

local HEADED = { ShoppingTooltip1 = true, ShoppingTooltip2 = true, ItemRefShoppingTooltip1 = true,
  ItemRefShoppingTooltip2 = true } -- comparison tooltips: line 1 is "Currently Equipped", the name follows

-- A profession's spell names its skill before its own name ("Enchanting: Enchant Boots - Minor Speed", written by
-- the client's compiled tooltip code: no interface string holds the form). `name` is the spell's own name, as the
-- frame gives it. Some recipes are headed by what they make instead ("Alchemy: Elemental Fire" for the spell
-- "Transmute: Elemental Fire"): then the row is split at its first separator.
-- → the skill's Japanese with the separator kept, the name after it, and the skill's name card ({ ja, reading,
-- english }) | nil unless both have Japanese
local function craftHeader(text, name)
  local head, rest
  if type(name) == "string" and name ~= "" and #text > #name + 2 and text:sub(-#name - 2) == ": " .. name then
    head, rest = text:sub(1, #text - #name - 2), name
  else
    head, rest = text:match("^(.-): (.+)$")
  end
  if not head then return nil end
  local skill, reading = WFJ.Names.of(head)
  if not skill or not WFJ.Names.item(rest) then return nil end
  return skill .. ": ", rest, { ja = skill, reading = reading, english = head }
end

-- `sets`: { [row] = { key, args } | false } from setBonuses: a set bonus line written with its spell's Japanese, or
-- (false) left English whole, never half translated.
-- `made`: { first, last } the rows of the item a spell makes that are a run of their own, never walked here.
local function showStructural(surface, frame, lines, first, last, refit, name, skip, sets, area, made)
  local index = WFJ.UIIndex
  -- without the dictionary there are no structural lines to match; the name line needs only the name tables
  if not index and not WFJ.State.names then return 0 end
  local n = 0
  local headed = HEADED[frame:GetName()]
  local sides = { { "L", lines }, { "R", Tooltip.lines(frame, "Right") } }
  for i = 1, #lines do
    if not (first and i >= first and i <= last) and i ~= skip and not (made and i >= made.first and i <= made.last) then
      for _, side in ipairs(sides) do
        local l = side[2][i]
        -- an uncached item has no name yet: on a comparison tooltip the name is then line 2 by position
        local isName = side[1] == "L" and ((i == 1 and not headed) or (name ~= nil and l and l.text == name)
          or (headed and name == nil and i == 2))
        -- a spell the client shows with no name line: its first row holds no name, so it is a row like the others
        if isName and i == 1 and area == "spells" and l and type(name) == "string" and name ~= ""
          and not l.text:find(name, 1, true) and not craftHeader(l.text, name) then
          isName = false
        end
        -- such a row may still hold the spell's name inside it: a reagent named like the spell it is for
        if isName and i == 1 and area == "spells" and l and type(name) == "string" and name ~= ""
          and l.text ~= name and index and index:match(l.text) then
          isName = false
        end
        local set
        if side[1] == "L" and sets then set = sets[i] end
        -- the name line: the name's Japanese while names are on, under the tooltip's own area; a name with no
        -- Japanese is left unwritten
        if isName and l and l.text ~= "" and WFJ.State.names then
          local head, own, skill
          if not WFJ.Names.item(l.text) then head, own, skill = craftHeader(l.text, name) end
          if (head or WFJ.Names.item(l.text)) and WFJ.Render.show(surface, "name.L" .. i, l.fs, l.text, area, "name",
              own or l.text, { head = head, refit = refit, cards = skill and { skill } or nil }) then
            n = n + 1
          end
        end
        if set ~= nil and set ~= false and l then
          local ctx = { args = set.args, refit = refit, cards = set.cards }
          if WFJ.Render.show(surface, "ui.L" .. i, l.fs, l.text, "ui", "ui", set.key, ctx) then n = n + 1 end
        elseif set == nil and l and l.text ~= "" and not isName then
          local key, args, runs
          if index then -- with no dictionary only a name can show
            if l.text:find("|c%x%x%x%x%x%x%x%x") then
              -- a line the client coloured ("|cffff2020-11|r Armor"): matched as written, else without the colour
              -- codes, and the coloured runs no argument holds get their colour back, as in the comparison pass
              key, args, runs = Tooltip.matchColoured(index, l.text)
            else
              key, args = index:match(l.text)
            end
            -- ADR-042: the right side of line 1 is never a name: on an aura it is the dispel type ("Curse"),
            -- a restricted family found only where it is asked for
            if not key and side[1] == "R" and i == 1 then
              key, args = index:matchOnly(l.text, WFJ.Labels.families("DispelType").only)
            end
            -- the tooltip's own lines that are only matched where asked for (UIStrings.ONLY, the bare forms)
            if not key then key, args = index:matchOnly(l.text, TOOLTIP_ONLY) end
            -- the client printed a template unfilled ("%s yd range" on a pet's spell it gives no range): its
            -- Japanese, with the placeholders as the client left them
            if not key and l.text:find("%%%d*%$?[sd]") then
              key = index:keyOf(l.text)
              if key then
                args = {}
                for spec in l.text:gmatch("%%%d*%$?[sd]") do args[#args + 1] = spec end
              end
            end
          end
          if key and WFJ.Render.show(surface, "ui." .. side[1] .. i, l.fs, l.text, "ui", "ui", key,
              { args = args, refit = refit, runColours = runs }) then
            n = n + 1
          elseif not key and side[1] == "L" and WFJ.State.names and WFJ.Names.shown(l.text)
            -- no dictionary line, and exactly a name or a list of names: the item a recipe makes, its
            -- ingredients, a set's pieces
            and WFJ.Render.show(surface, "name.L" .. i, l.fs, l.text, area, "name", l.text, { refit = refit }) then
            n = n + 1
          elseif not key and side[1] == "L" and WFJ.State.names and WFJ.NameLabels
            and l.text:find("^.+ %(%d+/%d+%)$")
            -- a set's heading, ITEM_SET_NAME "<set> (3/5)" (no words of its own, so no dictionary line): the set's
            -- name in Japanese, its counts as the client wrote them
            and WFJ.NameLabels.lead(surface, "name.L" .. i, l.fs, area, refit) > 0 then
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
-- "Equip:" stat lines inside the run of the item a spell makes, when the addon has NO translation for it (ADR-016;
-- an item's own tooltip splits its run with splitRun instead). Each run line that
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
    local key, args = index:statLine(l.text)
    if key then
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

-- `learn` = { row, id }: a recipe's own "Teaches you" line, or a talent's next rank, a run of its own under that id.
-- `peeled`: the run's line texts without the client's tail (peelTrailer), what the run is matched against.
-- `sets`: the set bonus lines (setBonuses).
-- `made` = { id, first, last, args, peeled, scope }: the lines of the item a spell makes, a run under that item.
-- `spells` = { [row] = { spell, args } }: an item's lines that print a spell of their own (splitRun), each a
-- record of that spell's description, gated on its own line. An item's stat lines come in `sets` from splitRun,
-- which decides them on the data, never on what is shown now: hovered with the modifier held, the stat records
-- are captured but write nothing, and the description's record must still not take their lines.
local function show(frame, area, kind, id, lines, first, last, name, runArgs, learn, peeled, sets, made, spells,
    flavour)
  local surface = surfaceOf(frame)
  WFJ.Render.forget(surface)
  if first and lines[first].text == "" then first, last = nil, nil end
  local refit = refitFor(frame)
  -- One refit for the whole hover: the per-record refit is a no-op while inRefit is set, then the refit runs once.
  -- The flag is cleared even when a write errors, so the frame is never left silently unhandled.
  inRefit[frame] = true
  local ok, n = pcall(function()
    local written = 0
    if first then
      written = showRun(surface, area, kind, id, lines, first, last, refit, runArgs, nil, peeled, nil, flavour)
    end
    for row = 1, #lines do
      local s = spells and spells[row]
      if s and WFJ.Render.show(surface, "spell.L" .. row, lines[row].fs, lines[row].text, area, "spell.description",
          s.spell, { lines = { peeled and peeled[row] or lines[row].text }, nameScope = lines[1] and lines[1].text,
            refit = refit, args = s.args }) then
        written = written + 1
      end
    end
    if learn then
      written = written + showRun(surface, area, kind, learn.id, lines, learn.row, learn.row, refit, nil, "learn")
    end
    if made then
      -- as on the item's own tooltip: the stat lines of an item with no translation first, else its run
      local madeMatched, madeWritten = showEquipLines(surface, made.id, lines, made.first, made.last, refit)
      written = written + madeWritten
      if madeMatched == 0 then
        written = written + showRun(surface, "items", "item.description", made.id, lines, made.first, made.last,
          refit, made.args, "made", made.peeled, made.scope)
      end
    end
    return written + WFJ.Perf.call("tooltip.item.structural", showStructural, surface, frame, lines, first, last,
      refit, name, learn and learn.row, sets, area, made)
  end)
  inRefit[frame] = false
  if not ok then error(n, 0) end
  if n > 0 then refit() end
  return n
end

-- The tail the client adds to a run's line: the max-usable-level trailer, or the item's cooldown ("(1 Sec
-- Cooldown)"), neither part of the item's text. `texts` is rewritten in place without it: what the Collector records
-- and what the run is matched against, so the tail's number never counts as one of the line's values.
-- → affix args carrying the first tail's Japanese | nil (none, or not one Japanese for it), and each line's
-- tail Japanese { [row] = text }
local function peelTrailer(texts, first, last)
  local index = WFJ.UIIndex
  if not index then return nil, {} end
  local after
  local tails = {}
  for i = first, last do
    local head, key, args = index:clientTail(texts[i])
    if key then
      texts[i] = head
      local ja = index.rows[key] and index:fill(index.rows[key][1], args)
      tails[i] = ja or nil
      if ja and not after then after = ja end
    end
  end
  return after and { form = "affix", before = "", after = after } or nil, tails
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

-- The frame row the client typed SpellDescription, read from the tooltip data behind the frame. Read from the
-- description line itself, never from a map of rows to kinds: a line the client draws nothing for takes the row of
-- the line before it as its own (tooltipdatahandler.lua:319-335), so the nested block of the item a spell makes
-- shares the description's row when it follows it, and a map keyed by row kept only the block. → row | nil
local function frameDescriptionRow(frame)
  if type(frame.GetPrimaryTooltipInfo) ~= "function" then return nil end
  local ok, info = pcall(frame.GetPrimaryTooltipInfo, frame)
  local data = ok and type(info) == "table" and info.tooltipData or nil
  local enum = Compat.resolve("Enum.TooltipDataLineType")
  local want = type(enum) == "table" and enum.SpellDescription or nil
  if type(data) ~= "table" or type(data.lines) ~= "table" or want == nil then return nil end
  for _, line in ipairs(data.lines) do
    if type(line) == "table" and not anySecretOf(line.type, line.lineIndex) and line.type == want
      and type(line.lineIndex) == "number" then
      return line.lineIndex
    end
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
  if WFJ.State.enabled == false or WFJ.Modifier.english() or not WFJ.State.areaEnabled(area) then
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

-- An item set's bonus spells, as the client lists them for the player's specialization (0 when it has none)
-- [seen in game: C_Item.GetSetBonusesForSpecializationByItemID answers on Forever 1.60.1.70338]. → { spell id, … }
function Tooltip.setSpells(id)
  local bonuses = Compat.resolve("C_Item.GetSetBonusesForSpecializationByItemID")
  if type(bonuses) ~= "function" then return {} end
  local spec = 0
  local specOf = Compat.resolve("C_SpecializationInfo.GetSpecialization") or Compat.resolve("GetSpecialization")
  local specInfo = Compat.resolve("C_SpecializationInfo.GetSpecializationInfo")
    or Compat.resolve("GetSpecializationInfo")
  if type(specOf) == "function" and type(specInfo) == "function" then
    local ok, index = pcall(specOf)
    if ok and type(index) == "number" then
      local iok, specID = pcall(specInfo, index)
      if iok and type(specID) == "number" then spec = specID end
    end
  end
  local ok, list = pcall(bonuses, spec, id)
  local out = {}
  if not ok or type(list) ~= "table" then return out end
  for _, sid in ipairs(list) do
    if type(sid) == "number" and not anySecretOf(sid) then out[#out + 1] = sid end
  end
  return out
end

-- An item's set bonus lines ("(2) Set: Improves your chance to hit by 2.0%.", ITEM_SET_BONUS_GRAY; "Set: …" once
-- the bonus is active): the client fills them with a bonus spell's description. A line belongs to the bonus spell
-- whose description, as the client renders it, is the line's text, and shows that spell's Japanese when the
-- tooltip gate accepts it (WFJ.GateText). The gate alone cannot tell two bonuses apart (a Japanese with no number
-- fits any line), so a line whose spell the client does not name stays English whole.
-- → { [row] = { key, args with the Japanese in place } | false }, the English lines' { text }, the bonus spells no
-- line took | nil when the tooltip has no set line
-- one list for every call: the index caches its answers per list, so a list made per call matched every line of
-- every item from scratch (in game, most of an item tooltip's time)
local SET_GRAY = { "ITEM_SET_BONUS_GRAY" }
local function setBonuses(id, lines, taken)
  local index, gate = WFJ.UIIndex, WFJ.GateText
  local lookup = WFJ.Lookup and WFJ.Lookup.get
  if not index or type(gate) ~= "function" or type(lookup) ~= "function" then return nil end
  -- the active line by the client's own "Set: " (its "Set: %s" is shared with the boss loot banner's key)
  local active = Compat.resolve("ITEM_SET_BONUS")
  local prefix = type(active) == "string" and active:match("^(.-)%%s$") or nil
  -- a bonus line with nothing after its words ("(4) Set: ", "Set: "): the client wrote it before the bonus spell's
  -- text had loaded [seen in game: Forever 1.60.1.71091], and the template matches no empty value
  local gray = Compat.resolve("ITEM_SET_BONUS_GRAY")
  local grayHead = type(gray) == "string" and gray:match("^(.-)%%s$") or nil
  local grayEmpty = grayHead and grayHead:find("%d", 1, true)
    and "^" .. grayHead:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0"):gsub("%%%%d", "(%%d+)") .. "$" or nil
  local found = {}
  for i = 2, #lines do
    local text = lines[i].text
    if not taken(i) and text ~= "" then
      local key, args = index:matchOnly(text, SET_GRAY)
      if not key and prefix and prefix ~= "" and text:sub(1, #prefix) == prefix and #text >= #prefix then
        key, args = "ITEM_SET_BONUS", { text:sub(#prefix + 1) }
      end
      local count = not key and grayEmpty and text:match(grayEmpty)
      if count then key, args = "ITEM_SET_BONUS_GRAY", { count, "" } end
      if key and type(args) == "table" then found[#found + 1] = { row = i, key = key, args = args } end
    end
  end
  if #found == 0 then return nil end
  local spells = Tooltip.setSpells(id)
  local out, used, english = {}, {}, {}
  for _, f in ipairs(found) do
    local slot = f.key == "ITEM_SET_BONUS" and 1 or 2 -- the %s
    local inner = f.args[slot]
    local hit, hitId, filled
    local gateCards = WFJ.GateCards or gate
    -- no bonus text: the line's own words alone, with nothing to take from a spell
    if inner == "" then hit = "" end
    for _, sid in ipairs(type(inner) == "string" and inner ~= "" and spells or {}) do
      if not used[sid] and Tooltip.spellDescription(sid) == inner then
        local ok, text, durations = gateCards(lookup("spell.description", sid), { inner })
        if ok then hit, hitId, filled = text, sid, durations end
        break
      end
    end
    if hit then
      -- the line's template takes the names step before its values go in, and the spell's Japanese is a value:
      -- the names inside it ("Shadow Resistanceが10上昇します") take it here, as the spell's own tooltip line does
      local spans
      if WFJ.State.names then hit, spans = WFJ.Names.inText(hit) end
      local args = {}
      for k, v in pairs(f.args) do args[k] = v end
      args[slot] = hit
      -- the spell's own words, the names written into it, and the cards of what its values filled in (a
      -- duration's 秒), go on the line it is written into (a frozen copy's cards)
      local cards = hitId and WFJ.Readings and WFJ.Readings.cards("spell.description", hitId) or {}
      for _, c in ipairs(type(spans) == "table" and spans or {}) do cards[#cards + 1] = c end
      for _, c in ipairs(type(filled) == "table" and filled or {}) do cards[#cards + 1] = c end
      out[f.row] = { key = f.key, args = args, cards = cards }
      if hitId then used[hitId] = true end
    else
      out[f.row] = false
      english[#english + 1] = { text = inner }
    end
  end
  local free = {}
  for _, sid in ipairs(spells) do
    if not used[sid] then free[#free + 1] = sid end
  end
  return out, english, free
end

-- A recipe's tooltip on Forever is the crafted item's tooltip as a nested block, then the recipe's own "Use: Teaches
-- you …" line [seen in game: the tooltip data of a recipe on Forever 1.60.1.70338]. The tooltip data names both
-- items: its id is the recipe, the nested block's tooltipID the crafted item, and the recipe's line has its own
-- type. The item link may name either of them. → crafted id, recipe id, the recipe line's row | nil
function Tooltip.recipeOf(frame, lineCount)
  if type(frame.GetPrimaryTooltipInfo) ~= "function" then return nil end
  local ok, info = pcall(frame.GetPrimaryTooltipInfo, frame)
  local data = ok and type(info) == "table" and info.tooltipData or nil
  local lineTypes, dataTypes = Compat.resolve("Enum.TooltipDataLineType"), Compat.resolve("Enum.TooltipDataType")
  if type(data) ~= "table" or type(data.lines) ~= "table" or type(lineTypes) ~= "table" then return nil end
  local itemType = type(dataTypes) == "table" and dataTypes.Item or 0
  local crafted, nestedRow, row
  for _, line in ipairs(data.lines) do
    if type(line) == "table" and not anySecretOf(line.type, line.tooltipID, line.tooltipType, line.lineIndex) then
      if line.type == lineTypes.NestedBlock and line.tooltipType == itemType and type(line.tooltipID) == "number" then
        crafted, nestedRow = crafted or line.tooltipID, nestedRow or line.lineIndex
      elseif line.type == lineTypes.ItemSpellTriggerLearn and type(line.lineIndex) == "number" then
        row = row or line.lineIndex
      end
    end
  end
  local recipe = data.id
  if anySecretOf(recipe) or type(recipe) ~= "number" or not crafted or crafted == recipe then return nil end
  if not row or row < 2 or row > lineCount then return nil end
  -- the layout seen on Forever: the crafted item's block first, the recipe's line after it; any other is one item
  if type(nestedRow) ~= "number" or nestedRow >= row then return nil end
  return crafted, recipe, row
end

-- A spell that makes an item (a profession's recipe) shows that item's own tooltip under its rows: its name, its
-- requirements, its use line and its flavour text. The tooltip data names the item the way a recipe's does: a
-- nested block whose tooltipType is Item, its tooltipID the item, the block's rows after its lineIndex [unverified
-- on a spell's tooltip: the recipe item's layout was seen in game, and the tooltip trace shows each row's kind].
-- → item id, the row the block starts after | nil
function Tooltip.madeItem(frame, lineCount)
  if type(frame.GetPrimaryTooltipInfo) ~= "function" then return nil end
  local ok, info = pcall(frame.GetPrimaryTooltipInfo, frame)
  local data = ok and type(info) == "table" and info.tooltipData or nil
  local lineTypes, dataTypes = Compat.resolve("Enum.TooltipDataLineType"), Compat.resolve("Enum.TooltipDataType")
  if type(data) ~= "table" or type(data.lines) ~= "table" or type(lineTypes) ~= "table" then return nil end
  if lineTypes.NestedBlock == nil then return nil end
  local itemType = type(dataTypes) == "table" and dataTypes.Item or 0
  for _, line in ipairs(data.lines) do
    if type(line) == "table" and not anySecretOf(line.type, line.tooltipID, line.tooltipType, line.lineIndex)
      and line.type == lineTypes.NestedBlock and line.tooltipType == itemType then
      local id, row = line.tooltipID, line.lineIndex
      if type(id) ~= "number" or id <= 0 or type(row) ~= "number" or row < 1 or row >= lineCount then return nil end
      return id, row
    end
  end
  return nil
end

-- The made item's description run on a spell's tooltip: its use, equip and hit lines and its flavour text, looked
-- for under the nested block only and never across the spell's own description row. The run is narrowed and its
-- client tail peeled as on the item's own tooltip. → { id, first, last, args, peeled, scope } | nil
local function madeRun(frame, texts, descriptionRow)
  local id, row = Tooltip.madeItem(frame, #texts)
  if not id then return nil end
  local under = { "" } -- itemRun never takes its first line
  for i = row + 1, #texts do under[#under + 1] = texts[i] end
  local scope = texts[row + 1] -- the block opens with the item's name
  -- Under a spell the client lays the made item out its own way: its level line can stand between its equip line
  -- and its flavour text, so the run the item's own tooltip would have may stop short of the line it translates.
  -- The one row under the block that the item's Japanese fits is that line; the run is only the fallback.
  local fit, fitLast, fitOthers = Tooltip.narrowRun(id, texts, row + 1, #texts, scope)
  local first, last
  if fitOthers and not (descriptionRow and fit == descriptionRow) then
    first, last = fit, fitLast
  else
    first, last = Tooltip.itemRun(under)
    if not first then return nil end
    first, last = first + row - 1, last + row - 1
    if descriptionRow and descriptionRow >= first and descriptionRow <= last then return nil end
    first, last = Tooltip.narrowRun(id, texts, first, last, scope)
  end
  local peeled = {}
  for i, text in ipairs(texts) do peeled[i] = text end
  local args = peelTrailer(peeled, first, last)
  if args then -- only an ungated translation takes the tail's Japanese; a gated one keeps the whole line
    local lookup = WFJ.Lookup and WFJ.Lookup.get
    local entry = type(lookup) == "function" and lookup("item.description", id) or nil
    if not (entry and entry.status == ".") then args = nil end
  end
  return { id = id, first = first, last = last, args = args, peeled = peeled, scope = scope }
end

-- The lines and link of each tooltip's last full pass, as the client wrote them. The client rebuilds a comparison
-- tooltip a few times per refresh with the same lines (measured in game: about 3.5 times, whether or not we
-- redraw), and a full pass each time was most of a hover's cost: a rebuild with the same item and the same lines
-- only gets its Japanese back (Render.reapply). Forgotten when the tooltip hides.
-- A line's colour is part of what the pass writes (a flavour line keeps its own colour), so it is compared too.
local lastLines, lastLink = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local reapplied = setmetatable({}, { __mode = "k" }) -- tooltip → its last item pass was a reapply (onCompareShow too)

local function colourOf(fs)
  if type(fs.GetTextColor) ~= "function" then return -1 end
  local r, g, b = fs:GetTextColor()
  if anySecretOf(r, g, b) or type(r) ~= "number" then return -1 end
  return math.floor(r * 255 + 0.5) * 65536 + math.floor(g * 255 + 0.5) * 256 + math.floor(b * 255 + 0.5)
end

-- The left lines' widget, text and colour and the right lines' widget and text, as the client wrote them. Checked
-- by reading each kept widget in place: the check runs on every rebuild and builds nothing (in game, the line tables
-- a check built each time were most of the memory a hover churned).
local function textOf(fs)
  local t = fs:GetText() or ""
  if anySecretOf(t) then return nil end
  return t
end

local function sameAsLast(frame, link)
  -- while English is what shows a rebuild takes the full pass: there is no Japanese on the lines to keep
  if WFJ.Modifier and WFJ.Modifier.english() then return false end
  local seen = lastLines[frame]
  if not seen or lastLink[frame] ~= link or type(frame.NumLines) ~= "function" or frame:NumLines() ~= seen.n then
    return false
  end
  for i = 1, seen.n do
    local fs = seen.leftFs[i]
    if textOf(fs) ~= seen.left[i] or colourOf(fs) ~= seen.colour[i] then return false end
    local r = seen.rightFs[i]
    if r and textOf(r) ~= seen.right[i] then return false end
  end
  -- the records the full pass left must still be the live ones: another pass on the same tooltip without a hide (a
  -- spell link in the chat link tooltip, itemref.lua:20-25) replaces them, and there is nothing to put back then
  local SS = WFJ.SurfaceState
  for _, rec in ipairs(seen.recs) do
    if SS.get(rec.surface, rec.key) ~= rec then return false end
  end
  return true
end

local function remember(frame, link, lines, right)
  local seen = { n = #lines, leftFs = {}, left = {}, colour = {}, rightFs = {}, right = {}, recs = {} }
  for _, rec in pairs(WFJ.SurfaceState.records(surfaceOf(frame))) do seen.recs[#seen.recs + 1] = rec end
  for i = 1, #lines do
    seen.leftFs[i], seen.left[i], seen.colour[i] = lines[i].fs, lines[i].text, colourOf(lines[i].fs)
  end
  for i = 1, #right do seen.rightFs[i], seen.right[i] = right[i].fs, right[i].text end
  lastLines[frame], lastLink[frame] = seen, link
end

-- The Item post-call's target.
function Tooltip.onItem(frame)
  if inRefit[frame] then return 0 end -- our own refit re-runs the post-call; nothing new to read
  local itemName, link = Tooltip.itemOf(frame)
  reapplied[frame] = nil
  if not anySecretOf(link) and sameAsLast(frame, link) then
    WFJ.Perf.count("tooltip.item.reused")
    local n = WFJ.Render.reapply(surfaceOf(frame))
    if n > 0 then refitFor(frame)() end
    reapplied[frame] = true
    return n
  end
  WFJ.Perf.count("tooltip.item.full")
  local t0, k0 = WFJ.Perf.start("tooltip.item.read")
  local lines = Tooltip.lines(frame)
  WFJ.Perf.stop("tooltip.item.read", t0, k0)
  local texts = {}
  for i, l in ipairs(lines) do texts[i] = l.text end
  local right = Tooltip.lines(frame, "Right")
  lastLines[frame] = nil -- a pass that raises leaves no lines to match a rebuild against
  local readLines = {} -- as read: the pass below rewrites the texts in place (peelTrailer)
  for i, l in ipairs(lines) do readLines[i] = { fs = l.fs, text = l.text } end
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
  local crafted, recipe, learnRow = Tooltip.recipeOf(frame, #lines)
  if crafted then id = crafted end
  if not id or id <= 0 then
    WFJ.Render.forget(surfaceOf(frame))
    traceFrame(frame, "item without an id", nil, lines, "-> 0 (link " .. plain(link) .. ")")
    return 0
  end
  traceFrame(frame, "item as the client laid it out", id, lines, "")
  -- a recipe: the crafted item's run ends above the recipe's own line, which is a run of its own
  local first, last = Tooltip.itemRun(learnRow and { unpack(texts, 1, learnRow - 1) } or texts)
  local runFirst, runLast = first, last
  -- the tails come off before the run is split: a cooldown's number is no value of the line it ends
  local tails = first and select(2, peelTrailer(texts, first, last)) or {}
  local others
  first, last, others = Tooltip.splitRun(id, texts, first, last, texts[1], tails)
  local learn = learnRow and texts[learnRow] ~= "" and { row = learnRow, id = recipe } or nil
  local runArgs
  for row = first or 1, last or 0 do
    if tails[row] then runArgs = { form = "affix", before = "", after = tails[row] }; break end
  end
  -- The run is read before we write (the client rewrote every line); the Collector refuses our own text anyway.
  -- With no line the description's, the Collector reads the run as the client printed it, as before.
  local P = WFJ.Perf
  t0, k0 = P.start("tooltip.item.collector")
  local readFirst, readLast = first or runFirst, last or runLast
  if readFirst then
    WFJ.Collector.record("item", id, "description", table.concat(texts, "\n", readFirst, readLast))
  end
  if learn then WFJ.Collector.record("item", recipe, "description", texts[learnRow]) end
  P.stop("tooltip.item.collector", t0, k0)
  t0, k0 = P.start("tooltip.item.sets")
  local sets, setEnglish, setFree = setBonuses(id, lines, function(i)
    return (first ~= nil and i >= first and i <= last) or (learn ~= nil and i == learn.row)
  end)
  P.stop("tooltip.item.sets", t0, k0)
  -- the run's lines that are not the description (splitRun): a stat line goes with the structural lines; a spell's
  -- line is a record of its own, and the structural pass leaves it alone
  local spells
  if others then
    sets = sets or {}
    for row, set in pairs(others) do
      if set and set.spell then
        spells = spells or {}
        spells[row] = set
        set = false
      end
      if sets[row] == nil then sets[row] = set end
    end
  end
  -- a set line no bonus spell's Japanese fits is that spell's English: known only when one line and one spell are left
  if setEnglish and #setEnglish == 1 and #setFree == 1 and type(setEnglish[1].text) == "string" then
    WFJ.Collector.record("spell", setFree[1], "description", setEnglish[1].text)
  end
  if runArgs then -- only an ungated translation takes the trailer's Japanese; a gated one keeps the whole line
    local lookup = WFJ.Lookup and WFJ.Lookup.get
    local entry = type(lookup) == "function" and lookup("item.description", id) or nil
    if not (entry and entry.status == ".") then runArgs = nil end
  end
  -- the flavour line below the run, when the description's Japanese was written for it too; the structural pass
  -- leaves it to the run (false: no line of its own)
  local flavour = Tooltip.flavourRow(id, texts, first, last, learnRow and learnRow - 1 or nil)
  if flavour then
    sets = sets or {}
    sets[flavour.row] = false
  end
  -- No run still has structural lines.
  local n = show(frame, "items", "item.description", id, lines, first, last, itemName, runArgs, learn, texts, sets,
    nil, spells, flavour)
  remember(frame, link, readLines, right)
  traceFrame(frame, "readable item", id, lines, ("-> rendered %d"):format(n))
  -- the same tooltip one frame later, as the client drew it: a wrap that moves after this pass shows there
  local after = Tooltip.trace and Compat.resolve("C_Timer.After")
  if type(after) == "function" then
    after(0, function() traceFrame(frame, "item one frame later", id, Tooltip.lines(frame), "") end)
  end
  return n
end

-- The Spell post-call's target.
-- A talent's next rank: the talent tooltip appends the next rank's own data after "Next Rank:"
-- (TalentDisplayMixin:AddTooltipDescription → AppendInfo("GetTraitEntry", …), blizzard_talentdisplay.lua:368-371),
-- and the client runs the spell post-call again with that data, the tooltip's processingInfo marked `append`
-- (tooltipdatahandler.lua:241-298, 434-438). Its description is that data's SpellDescription line: the frame row
-- holding the same text, looked for from the bottom. → row, spell id | nil
function Tooltip.appendedDescription(frame, data, texts)
  local info = type(frame) == "table" and frame.processingInfo or nil
  if type(info) ~= "table" or not info.append or type(data) ~= "table" or type(data.lines) ~= "table" then
    return nil
  end
  local id = data.id
  local lineTypes = Compat.resolve("Enum.TooltipDataLineType")
  local want = type(lineTypes) == "table" and lineTypes.SpellDescription or nil
  if type(id) ~= "number" or anySecretOf(id) or want == nil then return nil end
  for _, line in ipairs(data.lines) do
    local text = type(line) == "table" and line.type == want and line.leftText or nil
    if type(text) == "string" and text ~= "" and not anySecretOf(text) then
      for row = #texts, 2, -1 do
        if texts[row] == text then return row, id end
      end
    end
  end
  return nil
end

-- The spell a mount's, a companion's or a macro's tooltip shows. These are data kinds of their own, so the
-- frame's GetSpell answers nothing for them [verified: forever-ui-1.60.1.71037
-- blizzard_sharedxmlgame/tooltip/tooltiputil.lua:25–32, blizzard_gametooltip/mainline/gametooltip.lua:1031]. The id
-- the post-call hands over is taken only when that spell's name is the tooltip's first line [unverified what the
-- id of each kind is; the window test's tooltip read shows whether these tooltips come out Japanese]; else the
-- spell is asked for by that name, which the client answers for a spell the character knows
-- [verified: blizzard_apidocumentationgenerated/spelldocumentation.lua:416–424]. → id, name | nil
function Tooltip.spellOf(frame, data)
  local nameOf, infoOf = Compat.get(DECLARE, "spellName"), Compat.get(DECLARE, "spellInfo")
  if type(nameOf) ~= "function" then return nil end
  local first = Compat.resolve(frame:GetName() .. "TextLeft1")
  local shown = type(first) == "table" and first:GetText() or nil
  if anySecretOf(shown) or type(shown) ~= "string" or shown == "" then return nil end
  -- a first line this addon already wrote: the name the client put there is the record's English
  local rec = WFJ.SurfaceState.records(surfaceOf(frame))["name.L1"]
  local ours = type(rec) == "table" and rec.fs == first and rec.applied == shown and type(rec.en) == "string"
  local name = ours and rec.en or shown
  local id = type(data) == "table" and data.id or nil
  if type(id) == "number" and not anySecretOf(id) and nameOf(id) == name then return id, name end
  local info = type(infoOf) == "function" and infoOf(name) or nil
  id = type(info) == "table" and info.spellID or nil
  if type(id) == "number" and not anySecretOf(id) and nameOf(id) == name then return id, name end
  return nil
end

-- `known` (optional): the spell's name and id, for a tooltip whose frame cannot say them (Tooltip.spellOf).
function Tooltip.onSpell(frame, data, knownName, knownId)
  if inRefit[frame] then return 0 end
  local spellName, id = knownName, knownId
  if id == nil then spellName, id = frame:GetSpell() end
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
  -- the client runs this post-call again on the same tooltip while the pass before is still on its lines (a talent
  -- adds its next rank as appended data, seen in game): those records are dropped first, which gives their lines the
  -- client's English back, and the lines are read again. Read with our Japanese on them, a line's record took that
  -- Japanese for its English, and the reveal key put it back in the client's font, as boxes.
  if next(WFJ.SurfaceState.records(surfaceOf(frame))) ~= nil then
    WFJ.Render.forget(surfaceOf(frame))
    lines = Tooltip.lines(frame)
    for i, l in ipairs(lines) do texts[i] = l.text end
    for i = #lines + 1, #texts do texts[i] = nil end
  end
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
  local nextRow, nextId = Tooltip.appendedDescription(frame, data, texts)
  local nextRank = nextRow and nextRow ~= i and { row = nextRow, id = nextId } or nil
  local made = madeRun(frame, texts, i)
  -- "spell.description": a bare "spell" would not name one field (spells also have `aura`)
  local n = show(frame, "spells", "spell.description", id, lines, i, i, spellName, nil, nextRank, nil, nil, made)
  local asked = Tooltip.loadIncluded(id)
  if asked > 0 then how = how .. (" (asked for %d spliced-in spells)"):format(asked) end
  traceFrame(frame, "readable spell", id, lines, ("-> rendered %d%s"):format(n, how))
  return n
end

-- The lines a comparison tooltip gets after its item post-call (see the header). → the number shown
local COMPARE_KEYS = { "ITEM_DELTA_DESCRIPTION", "ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION",
  "ITEM_COMPARISON_SWAP_ITEM_MAINHAND_DESCRIPTION", "ITEM_COMPARISON_SWAP_ITEM_OFFHAND_DESCRIPTION",
  "ITEM_COMPARISON_CYCLING_DISABLED_MSG_MAINHAND", "ITEM_COMPARISON_CYCLING_DISABLED_MSG_OFFHAND",
  -- the dual-wield comparison's "(With |c<hex><weapon>|r equipped in your main-hand)"
  -- (tooltipcomparisonmanager.lua:271)
  "ITEM_DELTA_DUAL_WIELD_COMPARISON_MAINHAND_DESCRIPTION", "ITEM_DELTA_DUAL_WIELD_COMPARISON_OFFHAND_DESCRIPTION" }
Tooltip.COMPARE_KEYS = COMPARE_KEYS

-- A stat change line colours its number on its own ("|cffff2020-11|r Armor", seen in game): the line is matched with
-- its colour codes taken out, and an argument the client had coloured gets its colour back in the Japanese. A
-- coloured run no argument holds (the bare line is a whole fixed string: "+17 Armor" is also an enchantment's text)
-- is returned as { run, code } pairs, for the renderer to colour where the Japanese has the same run.
-- → key, args, runs | nil
function Tooltip.matchColoured(index, text)
  local key, args = index:match(text)
  if not key then
    local bare = WFJ.UIStrings.stripColour(text)
    if bare == text then return nil end
    local shared
    key, shared = index:match(bare)
    if not key then return nil end
    -- a line the client coloured end to end ("|cffff2020Requires Level 60|r"): the Japanese in the same colour
    local open = text:match("^(|c%x%x%x%x%x%x%x%x)[^|]*|r$")
    if open then return key, { form = "wrapped", open = open, close = "|r", inner = shared } end
    -- the index memoizes `args` per text: a copy takes the colour, never the memo
    args = {}
    for k, v in pairs(shared or {}) do args[k] = v end
    for i, a in pairs(shared or {}) do
      if type(i) == "number" and type(a) == "string" and a ~= "" then
        local coloured = text:match("(|c%x%x%x%x%x%x%x%x" .. a:gsub("%p", "%%%0") .. "|r)")
        if coloured then args[i] = coloured end
      end
    end
  end
  -- a key whose Japanese writes its own colour codes (the dual-wield line's "|c%s%s|r") colours its runs itself
  local row = index.rows and index.rows[key]
  if type(row) == "table" and type(row[1]) == "string" and row[1]:find("|c", 1, true) then return key, args end
  local runs
  for coloured, code, run in text:gmatch("((|c%x%x%x%x%x%x%x%x)([^|]+)|r)") do
    local held = false
    for _, a in pairs(args or {}) do
      if type(a) == "string" and a:find(coloured, 1, true) then held = true end
    end
    if not held then
      runs = runs or {}
      runs[#runs + 1] = { run = run, code = code }
    end
  end
  return key, args, runs
end
-- A stat change with no template of its own: "<signed number> <short stat name>" ("+0.7 damage per second", the
-- ITEM_MOD_*_SHORT names the client's C_TooltipComparison.GetItemComparisonDelta writes), the number possibly
-- coloured. The name must be one of those stat names; it shows as "<Japanese name> <number as written>".
-- → key, args | nil
local statNameKeys = setmetatable({}, { __mode = "k" }) -- index → the list of its stat name keys
function Tooltip.matchStatChange(index, text)
  local bare = WFJ.UIStrings.stripColour(text)
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
-- A comparison tooltip's lines as the last comparison pass left them: the client shows these frames again and again
-- (Show, SetShown) with nothing new on them, and a full pass each time was most of what a hover still cost in game.
-- Kept as the line widgets and their texts, so the check reads each line once and builds nothing (it runs on every
-- show of a comparison tooltip). One per line count: the client shows a comparison tooltip twice per rebuild, once
-- with the item's own lines and again after it adds the stat changes (measured in game: 8 lines, then 14), and one
-- kept state made each show undo the other's.
local afterCompare = setmetatable({}, { __mode = "k" }) -- tooltip → { [line count] = { fs = { … }, text = { … } } }

local function headerOf(frame)
  local header = type(frame.CompareHeader) == "table" and frame.CompareHeader.Label or nil
  return type(header) == "table" and type(header.GetText) == "function" and header or nil
end

local function snapshot(frame)
  local seen = { fs = {}, text = {} }
  for i, l in ipairs(Tooltip.lines(frame)) do seen.fs[i], seen.text[i] = l.fs, l.text end
  -- the "Equipped" tab too: the client writes it again on every rebuild, also on one with no stat changes
  local header = headerOf(frame)
  seen.header = header and header:GetText() or nil
  local byCount = afterCompare[frame] or {}
  byCount[#seen.fs] = seen
  afterCompare[frame] = byCount
end

local function unchanged(frame)
  local byCount = afterCompare[frame]
  local seen = byCount and type(frame.NumLines) == "function" and byCount[frame:NumLines()]
  if not seen then return false end
  local header = headerOf(frame)
  local htext = header and header:GetText() or nil
  if anySecretOf(htext) or htext ~= seen.header then return false end
  for i = 1, #seen.fs do
    local text = seen.fs[i]:GetText() or ""
    if anySecretOf(text) or text ~= seen.text[i] then return false end
  end
  return true
end

function Tooltip.onCompareShow(frame)
  if inRefit[frame] then return 0 end
  if not (WFJ.Modifier and WFJ.Modifier.english()) then
    if reapplied[frame] or not unchanged(frame) then
      -- the client wrote the same English back: the Japanese goes back as written, then the lines are as we left them
      local n = WFJ.Render.reapply(surfaceOf(frame))
      if n > 0 then refitFor(frame)() end
      reapplied[frame] = nil
      if unchanged(frame) then
        WFJ.Perf.count("tooltip.compare.reused")
        return n
      end
    else
      WFJ.Perf.count("tooltip.compare.unchanged")
      return 0 -- shown again with nothing new on it
    end
  end
  WFJ.Perf.count("tooltip.compare.full")
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
    -- after the delta header, each line is a stat change the client formats ("-11 Armor"): a stat template.
    -- A line still showing our Japanese (put back before this pass, when only some lines changed) is matched on the
    -- English it was written over, so the header is still found and every line after it is read.
    local deltas = false
    for i, l in ipairs(Tooltip.lines(frame)) do
      local key, args, runs
      local en = l.text
      local held = WFJ.Modifier and WFJ.Modifier.english()
      local rec = not anySecretOf(en) and not held and WFJ.SurfaceState.get(surface, "ui.L" .. i)
      if rec and rec.fs == l.fs and rec.applied ~= nil and rec.applied == en then en = rec.en end
      if anySecretOf(en) then en = "" end -- a line the client hides is never read
      if en ~= "" then
        key, args = index:matchOnly(en, COMPARE_KEYS)
        if key == "ITEM_DELTA_DESCRIPTION" or key == "ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION" then
          deltas = true
        elseif not key and deltas and not anySecret({ en }) then
          key, args, runs = Tooltip.matchColoured(index, en)
          if not key then key, args = Tooltip.matchStatChange(index, en) end
        end
      end
      local ctx = { args = args, refit = refit, runColours = runs }
      if key and WFJ.Render.show(surface, "ui.L" .. i, l.fs, en, "ui", "ui", key, ctx) then n = n + 1 end
    end
  end)
  inRefit[frame] = false
  if not ok then error(err, 0) end
  if n > 0 then refit() end
  snapshot(frame)
  traceFrame(frame, "comparison lines", nil, Tooltip.lines(frame), ("-> rendered %d"):format(n))
  return n
end

function Tooltip.release(frame)
  lastLines[frame], lastLink[frame], reapplied[frame], afterCompare[frame] = nil, nil, nil, nil
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
  Compat.declare(DECLARE, "spellName", { "C_Spell.GetSpellName" })
  Compat.declare(DECLARE, "spellInfo", { "C_Spell.GetSpellInfo" })
  Compat.declare(DECLARE, "spellCached", { "C_Spell.IsSpellDataCached" })
  Compat.declare(DECLARE, "spellLoad", { "C_Spell.RequestLoadSpellData" })
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
      if frame then WFJ.Perf.call("tooltip.item", Tooltip.onItem, frame) end
    end)
    processor.AddTooltipPostCall(types.Spell, function(tt, data)
      local frame = dataFrame(tt, types.Spell, "GetSpell")
      if frame then WFJ.Perf.call("tooltip.spell", Tooltip.onSpell, frame, data) end
    end)
    -- a mount's, a companion's and a macro's tooltip show a spell under a data kind of their own
    for _, kind in ipairs(Tooltip.SPELL_KINDS) do
      if types[kind] ~= nil then
        processor.AddTooltipPostCall(types[kind], function(tt, data)
          local frame = dataFrame(tt, types[kind], "NumLines")
          if not frame then return end
          local id, name = Tooltip.spellOf(frame, data)
          if id then WFJ.Perf.call("tooltip.spell", Tooltip.onSpell, frame, data, name, id) end
        end)
      end
    end
  end
  -- the comparison pass, timed only when it runs (a SetShown(false) is no pass)
  local function compare(f) return WFJ.Perf.call("tooltip.compare", Tooltip.onCompareShow, f) end
  for _, name in ipairs(Tooltip.FRAMES) do
    local frame = Compat.get(DECLARE, name)
    if frame and frame.HookScript then
      resolvedFrames = resolvedFrames + 1
      frame:HookScript("OnHide", WFJ.Perf.wrap("tooltip.release", function(self) Tooltip.release(self) end))
      if HEADED[name] and type(frame.Show) == "function" then -- the comparison's appended lines
        hooksecurefunc(frame, "Show", compare)
        -- Forever's comparison manager shows its frames with SetShown, never Show
        -- [verified: blizzard_sharedxmlgame/tooltip/tooltipcomparisonmanager.lua:53-54]
        if type(frame.SetShown) == "function" then
          hooksecurefunc(frame, "SetShown", function(f, shown) if shown then compare(f) end end)
        end
      end
    end
  end
  -- Auras, on GameTooltip only (every aura caller in the client's UI uses it: the
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
      if method then WFJ.Perf.call("tooltip.aura", Tooltip.onAura, frame, method, unit, key, filter, count)
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
  for _, event in ipairs({ "enabled", "area", "language" }) do
    WFJ.State.on(event, function() pcall(Tooltip.restoreHidden) end)
  end
  -- Latched last, not first: if a registration or a hook raises, Main's guard records the failure and the
  -- surface stays retryable instead of being stuck permanently half-hooked (item hooked, spell not, no OnHide).
  hooked = true
  return resolvedFrames
end
