-- UI/TooltipUnit.lua: the lines the client composes on a unit's mouseover tooltip on Forever: the
-- level / creature-type line ("Level 1 Humanoid", "Level 12 Elite Beast"), the corpse line and the skinning / herb /
-- ore lines. The client builds the unit tooltip from C_TooltipInfo and then runs the TooltipDataProcessor post-calls
-- for Enum.TooltipDataType.Unit (the same system UI/Tooltip uses for items, spells and auras); the lines are
-- GlobalStrings it fills (TOOLTIP_UNIT_LEVEL*, UNIT_*LEVEL_TEMPLATE, UNIT_SKINNABLE_*, CORPSE_TOOLTIP) [unverified:
-- which of them this build's C code sends]. A creature's tooltip on Forever also shows its type on a line of its own
-- ("Beast", the CreatureType row) and, for a quest it counts for, the kill count (QUEST_MONSTERS_KILLED,
-- "0/4 Young Thistle Boar slain": the creature's name stays English) [verified in game: a
-- screenshot on 1.60.1.70170].
-- This surface keeps its OWN records, rather than borrowing UI/HelpTooltip's walk:
-- TooltipDataHandlerMixin:InternalProcessInfo runs the post-calls and then calls `self:Show()` on the next line
-- [verified: blizzard_sharedxmlgame/tooltip/tooltipdatahandler.lua:298–300], and HelpTooltip's own Show hook treats a
-- tooltip whose owner it does not have registered as foreign, forgetting every record on its surface, which put the
-- client's English straight back over these lines. Records here are keyed by line, re-rendered on a modifier change
-- like every surface's, and released on the tooltip's OnHide so a later item or spell tooltip never inherits them.
-- Only lines 2 and below are read, and only against the keys below: line 1 is the unit's name, and a guild line
-- ("<Guild>"), a title or any server line matches none of them, so it stays as the client wrote it (names stay
-- in English). A race, class or pet family inside a level line is kept as shown; a creature type ("Humanoid") takes
-- its CreatureType row. A player's tooltip never takes the creature-type templates: "Level 60 Undead" is the same
-- text for an Undead player (race, stays English) and an undead creature, and only the unit tells them apart
-- (C_PlayerInfo.GUIDIsPlayer on the tooltip data's guid, as blizzard_objectapi/mainline/playerlocation.lua:59 does).
-- A client with no tooltip data processor is left untouched (init returns false).
local _, WFJ = ...
local TooltipUnit = {}
WFJ.TooltipUnit = TooltipUnit

local SURFACE = "tooltip.unit"
TooltipUnit.SURFACE = SURFACE
local Compat = WFJ.Compat

TooltipUnit.KEYS = { "TOOLTIP_UNIT_LEVEL", "TOOLTIP_UNIT_LEVEL_TYPE", "TOOLTIP_UNIT_LEVEL_RACE",
  "TOOLTIP_UNIT_LEVEL_RACE_TYPE", "UNIT_LEVEL_TEMPLATE", "UNIT_TYPE_LEVEL_TEMPLATE", "UNIT_PLUS_LEVEL_TEMPLATE",
  "UNIT_TYPE_PLUS_LEVEL_TEMPLATE", "UNIT_LEVEL_DEAD_TEMPLATE", "UNIT_SKINNABLE_LEATHER", "UNIT_SKINNABLE_HERB",
  "UNIT_SKINNABLE_ROCK", "UNIT_SKINNABLE_BOLTS", "CORPSE_TOOLTIP", "QUEST_MONSTERS_KILLED", "QUEST_PLAYERS_KILLED",
  -- written by the compiled client, named by no Lua: threat, the corpse and skull-level lines, already gathered, and
  -- the faction / player objective forms; the reputation, race and creature names in them stay as written
  "THREAT_TOOLTIP", "CORPSE", "DEAD", "PVP_ENABLED", "ELITE", "UNIT_LETHAL_LEVEL_TEMPLATE",
  "UNIT_TYPE_LETHAL_LEVEL_TEMPLATE", "UNIT_LETHAL_LEVEL_DEAD_TEMPLATE", "UNIT_TYPE_LEVEL_FACTION_TEMPLATE",
  "UNIT_ALREADY_SKINNED_LEATHER", "UNIT_ALREADY_SKINNED_HERB", "UNIT_ALREADY_SKINNED_ROCK",
  "UNIT_ALREADY_SKINNED_BOLTS", "UNIT_CAPTURABLE", "QUEST_FACTION_NEEDED", "QUEST_FACTION_NEEDED_NOPROGRESS",
  "QUEST_PLAYERS_KILLED_NOPROGRESS" }
-- the owner line under a pet, minion or guardian ("Bob's Pet", the UnitOwner line kind): the owner's name stays English
for _, k in ipairs({ "UNITNAME_TITLE_CHARM", "UNITNAME_TITLE_COMPANION", "UNITNAME_TITLE_CREATION",
  "UNITNAME_TITLE_GUARDIAN", "UNITNAME_TITLE_MINION", "UNITNAME_TITLE_OPPONENT", "UNITNAME_TITLE_PET",
  "UNITNAME_TITLE_SQUIRE" }) do
  TooltipUnit.KEYS[#TooltipUnit.KEYS + 1] = k
end
for _, i in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26,
  28, 29, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 53, 54, 55, 56, 57,
  58, 59, 60, 61 }) do
  TooltipUnit.KEYS[#TooltipUnit.KEYS + 1] = "UNITNAME_SUMMON_TITLE" .. i
end
-- a creature: the keys, and its type on a line of its own (built per call: the family's keys come from the index)
-- a creature's or a game object's lines: the unit keys, the creature type, and an object's lock and requirement text
-- (LockType's action / what it opens / verb, PlayerCondition's failure text, both client-table rows the C client
-- writes) [unverified in game: which object lines carry them]
local function creatureOnly()
  return WFJ.Labels.familiesWith(TooltipUnit.KEYS, "CreatureType", "LockTypeName", "LockTypeResource", "LockTypeVerb",
    "PlayerConditionFailure")
end
local CREATURE_TEMPLATES = { UNIT_TYPE_LEVEL_TEMPLATE = true, UNIT_TYPE_PLUS_LEVEL_TEMPLATE = true,
  UNIT_TYPE_LETHAL_LEVEL_TEMPLATE = true }
local PLAYER_KEYS = {}
for _, k in ipairs(TooltipUnit.KEYS) do
  if not CREATURE_TEMPLATES[k] then PLAYER_KEYS[#PLAYER_KEYS + 1] = k end
end
local ONLY_PLAYER = { only = PLAYER_KEYS }

-- Is the tooltip's unit a player? A missing or secret guid, or no C_PlayerInfo, counts as not a player. → boolean
local function isPlayer(data)
  local guid = type(data) == "table" and data.guid or nil
  if type(guid) ~= "string" then return false end
  local isSecret = Compat.resolve("issecretvalue")
  if type(isSecret) == "function" and isSecret(guid) then return false end
  local info = Compat.resolve("C_PlayerInfo")
  if type(info) ~= "table" or type(info.GUIDIsPlayer) ~= "function" then return false end
  return info.GUIDIsPlayer(guid) == true
end
TooltipUnit.isPlayer = isPlayer
local MAX_LINES = 30 -- a unit tooltip is a handful of lines; the walk stops at the client's own count anyway

local refitting = false

-- One Show() after a pass that changed a line, so the frame fits the Japanese; our own re-entry is ignored.
local function refitFor(tt)
  return function()
    if refitting then return end
    refitting = true
    tt:Show()
    refitting = false
  end
end

-- Each row's line kind (Enum.TooltipDataLineType name) from the tooltip data: the client sets `lineIndex` on every
-- line it writes [verified: blizzard_sharedxmlgame/tooltip/tooltipdatahandler.lua:319–335]. → { [row] = kind }
function TooltipUnit.lineKinds(data)
  local out = {}
  local enum = Compat.resolve("Enum.TooltipDataLineType")
  if type(data) ~= "table" or type(data.lines) ~= "table" or type(enum) ~= "table" then return out end
  local names = {}
  for name, value in pairs(enum) do names[value] = name end
  for _, line in ipairs(data.lines) do
    local row, kind = line.lineIndex, line.type
    if type(row) == "number" and kind ~= nil then out[row] = names[kind] end
  end
  return out
end

-- Quest titles by the hash of their English (the addon ships no English): built on first use. → { [h1] = { ids } }
local titleIds
local function titlesByHash()
  if titleIds then return titleIds end
  titleIds = {}
  for id in pairs(WFJ.Data.quest) do
    local entry = WFJ.Lookup.get("quest.title", id)
    if entry and entry.h1 then
      titleIds[entry.h1] = titleIds[entry.h1] or {}
      table.insert(titleIds[entry.h1], id)
    end
  end
  return titleIds
end

-- The quest a title line names. Quests sharing one English title (a chain's parts) are told apart by the quest log:
-- the client shows a quest title on a unit only for a quest the player has; still several → only when their Japanese
-- agrees. → quest id | nil, why
function TooltipUnit.questFor(title)
  local isSecret = Compat.resolve("issecretvalue")
  if type(title) ~= "string" or title == "" or (type(isSecret) == "function" and isSecret(title)) then
    return nil, "no readable title"
  end
  local h1 = WFJ.Hash.h32x2(WFJ.Normalize.v1(WFJ.Collector.text(title)))
  local ids = titlesByHash()[h1]
  if not ids then return nil, "no quest with that title" end
  if #ids > 1 then
    local inLog = Compat.resolve("C_QuestLog.GetLogIndexForQuestID")
    if type(inLog) == "function" then
      local held = {}
      for _, id in ipairs(ids) do
        local ok, index = pcall(inLog, id)
        if ok and type(index) == "number" then held[#held + 1] = id end
      end
      if #held >= 1 then ids = held end
    end
  end
  local first, ja = ids[1], nil
  for _, id in ipairs(ids) do
    local entry = WFJ.Lookup.get("quest.title", id)
    local text = entry and entry.ja
    if ja == nil then ja = text elseif text ~= ja then return nil, "quests sharing the title differ" end
  end
  return first
end

-- A quest title inside a system line, as its Japanese when exactly one translation answers it (UIStrings
-- questTitle arguments). → Japanese | nil
function TooltipUnit.titleJapanese(title)
  local id = TooltipUnit.questFor(title)
  local entry = id and WFJ.Lookup.get("quest.title", id)
  return entry and type(entry.ja) == "string" and entry.ja ~= "" and entry.ja or nil
end
WFJ.UIStrings = WFJ.UIStrings or {}
WFJ.UIStrings.questTitle = TooltipUnit.titleJapanese

-- The minimap mouseover is one line holding a block the client builds: names (a quest giver), a quest title, a colour
-- code, then the objectives as "- 2/7 Young Nightsaber slain" (seen in game). Each part is read on its own: a title
-- by its hash, an objective through UI/QuestMap's objective lookups, anything else (a name) kept as written. The
-- client rebuilds it every frame, so it is written without a record. A quest ready to turn in has no objectives, so
-- its block is the title alone on one line: `single` (the tooltip is the minimap mouseover's, never a unit's, whose
-- one line is a name) lets a one-line block through, still read only as a quest title by its hash.
-- → the block in Japanese | nil, notes
function TooltipUnit.minimapBlock(text, single)
  local isSecret = Compat.resolve("issecretvalue")
  if type(text) ~= "string" or (not single and not text:find("\n", 1, true))
    or (type(isSecret) == "function" and isSecret(text)) then
    return nil
  end
  local out, changed, notes = {}, false, {}
  for segment in (text .. "\n"):gmatch("(.-)\n") do
    local head = segment:match("^|c%x%x%x%x%x%x%x%x") or ""
    local rest = segment:sub(#head + 1)
    local tail = rest:match("|c%x%x%x%x%x%x%x%x$") or rest:match("|r$") or ""
    local core = rest:sub(1, #rest - #tail)
    local dash, objective = core:match("^(%- )(.+)$")
    local ja
    if objective then
      local o = WFJ.QuestMap.objectiveJapanese(objective, SURFACE)
      if o and o ~= objective then ja = dash .. o end
    else
      local id = TooltipUnit.questFor(core)
      if id then
        local t = WFJ.Render.preview(SURFACE, core, nil, "quests", "quest.title", id, { live = core, compact = true })
        if t and t ~= core then ja = t; notes[#notes + 1] = "title quest " .. id end
      end
    end
    if ja then changed = true end
    out[#out + 1] = head .. (ja or core) .. tail
  end
  if not changed then return nil, notes end
  -- the client draws the block in the line's gold (NORMAL_FONT_COLOR) up to its own white code, but rebuilt with our
  -- text the line comes back white (seen in the trace: 1.00,0.82,0.00 on the first pass, 1.00,1.00,1.00 after), so the
  -- gold is written into the text itself
  local block = table.concat(out, "\n")
  if not block:find("^|c") then block = "|cffffd100" .. block end
  return block, notes
end

-- The widget the minimap block was written on, to give it the client's face back when the tooltip hides.
local blockWidget
-- Enum.TooltipDataType.MinimapMouseover on this client (set by init), to tell its one-line block from a unit's name
local minimapType

-- The Unit post-call (tooltip, tooltip data): GameTooltip only (its OnHide releases these records).
-- → the number of lines shown
function TooltipUnit.onUnit(tt, data)
  if tt == nil or tt ~= Compat.get(SURFACE, "GameTooltip") or type(tt.NumLines) ~= "function" then return 0 end
  local name = tt:GetName()
  if type(name) ~= "string" then return 0 end
  local lines = math.min(tt:NumLines() or 0, MAX_LINES)
  local refit, n, only = refitFor(tt), 0, isPlayer(data) and ONLY_PLAYER or creatureOnly()
  local kinds, notes = TooltipUnit.lineKinds(data), {}
  if lines == 1 then
    local fs = Compat.resolve(name .. "TextLeft1")
    local single = minimapType ~= nil and type(data) == "table" and data.type == minimapType
    local ja, why = TooltipUnit.minimapBlock(type(fs) == "table" and fs:GetText() or nil, single)
    if ja and WFJ.State.enabled ~= false and not WFJ.Modifier.isDown() and WFJ.State.areaEnabled("quests") then
      fs:SetText(ja)
      WFJ.Font.bundle(fs) -- written outside a record, so the face is set here and given back on the tooltip's OnHide
      blockWidget = fs
      refit()
      notes[#notes + 1] = "minimap block: " .. table.concat(why or {}, ", ")
      if WFJ.Tooltip.trace then
        pcall(WFJ.Tooltip.traceFrame, tt, "minimap", nil, WFJ.Tooltip.lines(tt), "-> wrote 1 (" .. notes[1] .. ")")
      end
      return 1
    end
  end
  -- line 1 is the unit's or object's name: never read, never written; a minimap mouseover starts with a quest title
  local first = kinds[1] == "QuestTitle" and 1 or 2
  for i = first, lines do
    local fs = Compat.resolve(name .. "TextLeft" .. i)
    if type(fs) == "table" then
      if kinds[i] == "QuestTitle" then
        local title = fs:GetText()
        local id, why = TooltipUnit.questFor(title)
        if id and WFJ.Render.show(SURFACE, "L" .. i, fs, title, "quests", "quest.title", id, { refit = refit }) then
          n = n + 1
        elseif not id then
          WFJ.SurfaceState.drop(SURFACE, "L" .. i) -- an earlier tooltip's record on this row
        end
        notes[#notes + 1] = ("row %d quest title: %s"):format(i, id and ("quest " .. id) or why)
      else
        n = n + WFJ.Labels.show(SURFACE, "L" .. i, fs, refit, only)
      end
    end
  end
  for i = lines + 1, MAX_LINES do WFJ.SurfaceState.drop(SURFACE, "L" .. i) end
  if WFJ.Tooltip.trace then
    pcall(WFJ.Tooltip.traceFrame, tt, "unit", nil, WFJ.Tooltip.lines(tt), ("-> wrote %d%s"):format(n,
      #notes > 0 and (" (" .. table.concat(notes, "; ") .. ")") or ""))
  end
  return n
end

-- HookScript target (GameTooltip OnHide): the frame's lines are gone. → records released
function TooltipUnit.release()
  if blockWidget then pcall(WFJ.Font.restore, blockWidget); blockWidget = nil end
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Tooltip.init. → true when the Unit post-call was registered
function TooltipUnit.init()
  Compat.declare(SURFACE, "GameTooltip", { "GameTooltip" })
  if hooked then return true end
  local processor, types = WFJ.Tooltip.modern()
  if not processor or types.Unit == nil then return false end
  local tt = Compat.get(SURFACE, "GameTooltip")
  if type(tt) ~= "table" or type(tt.HookScript) ~= "function" then return false end
  processor.AddTooltipPostCall(types.Unit, TooltipUnit.onUnit)
  -- the other tooltips whose lines are a unit's or a quest's: the minimap mouseover (a quest's title and objectives,
  -- GameTooltip:SetMinimapMouseover, blizzard_minimap/mainline/minimap.lua:271), a game object, a corpse
  minimapType = types.MinimapMouseover
  for _, name in ipairs({ "MinimapMouseover", "Object", "Corpse" }) do
    if types[name] ~= nil then processor.AddTooltipPostCall(types[name], TooltipUnit.onUnit) end
  end
  tt:HookScript("OnHide", TooltipUnit.release)
  hooked = true
  return true
end
