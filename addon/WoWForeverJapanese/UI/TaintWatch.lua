-- UI/TaintWatch.lua: finds where this addon's taint reaches the action bars and the bags, so a blocked action can be
-- traced to the line that caused it instead of guessed at (docs/systems/diagnostics.md, ADR-058).
-- A bar layout in combat is blocked when Blizzard's code reads a value this addon's taint reached earlier, out of
-- combat; the block itself only shows the reader. This module records the writer. Everything here only reads:
--   fields   the Blizzard fields the bar layout reads (FIELDS), checked with issecurevariable every CHECK_EVERY
--            seconds; the first time one reads as tainted by this addon, a "turned" entry with the recent events;
--   writers  a post-hook on the Blizzard function that writes each of those fields: a "write" entry with the call
--            stack when the value comes out tainted (the stack names the path that carried the taint);
--   bars     every CHECK_EVERY * SWEEP_EVERY seconds out of combat, any field on the action bars that newly reads
--            as tainted, for fields not on the list;
--   events   the last RING game events, and the addon's own timed passes (Core/Perf) as "wfj <label>" lines, saved
--            with each entry above and with each block;
--   scan     at each different block of a session, and on /wfj taint: every field that reads as tainted under the
--            bar, Edit Mode, tracker, tooltip, spellbook, quest log, quest list, map and bag frames, under every frame
--            the addon's declarations resolved to, and the globals this addon tainted;
--   bags     what a bag item's click reads before it uses the item, checked with the fields above.
-- Its own post-hooks run after the hooked function returns and only read, so they add no taint of their own.
local _, WFJ = ...
local TaintWatch = {}
WFJ.TaintWatch = TaintWatch

local C = WFJ.Compat

TaintWatch.CHECK_EVERY = 2 -- seconds between field checks
-- field checks between bar sweeps: once a minute. A sweep walks every action bar (about 6 ms in game, a felt hitch
-- every 10 s when it ran every fifth check), and the taint it looks for builds up and stays.
TaintWatch.SWEEP_EVERY = 30
TaintWatch.RING = 200 -- game events and the addon's own passes kept
TaintWatch.SCAN_DEPTH = 2

TaintWatch.BARS = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
  "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar", "MultiCastActionBarFrame" }
TaintWatch.SNAPPED = { "MainActionBar", "StanceBar", "PetActionBar", "MainStatusTrackingBarContainer",
  "SecondaryStatusTrackingBarContainer", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft",
  "MultiBarRight", "MultiBar5", "MultiBar6", "MultiBar7", "PossessActionBar" }
-- the frames the block-time scan walks
TaintWatch.SCAN_ROOTS = { "StanceBar", "PetActionBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
  "MultiBarLeft", "MultiBarRight", "MultiBar5", "MultiBar6", "MultiBar7", "EditModeManagerFrame",
  "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "MicroButtonAndBagsBar",
  "ObjectiveTrackerFrame", "GameTooltip", "PlayerSpellsFrame", "QuestMapFrame", "WorldMapFrame", "QuestCache",
  "QuestScrollFrame", "ContainerFrameCombinedBags", "MerchantFrame", "BankFrame", "StackSplitFrame" }
-- the bags: a bag item's click reads its button's fields (ContainerFrame<n>.Items[i].bagID,
-- mainline/containerframe.lua:1845-1847) before it uses the item, so a tainted button field makes the use a forbidden
-- call
for i = 1, 13 do TaintWatch.SCAN_ROOTS[#TaintWatch.SCAN_ROOTS + 1] = "ContainerFrame" .. i end
TaintWatch.COMPAT_DEPTH = 1 -- the frames the addon's declarations resolved to: their own fields and one level down
-- roots walked deeper than SCAN_DEPTH: a tracker quest block is ObjectiveTrackerFrame.modules[i].usedBlocks[t][id], and
-- clicking its title opens the quest log through the block's fields (blizzard_questobjectivetracker.lua:60-68); the
-- quest list's layout lives under QuestScrollFrame.Contents (questmapframe.lua:2159)
TaintWatch.SCAN_DEEP = { ObjectiveTrackerFrame = 5, QuestMapFrame = 3, QuestCache = 3, QuestScrollFrame = 3 }
-- pools whose rows the scan walks: a pool is a proxy that only has methods (CreateFramePool = CreateSecureFramePool,
-- blizzard_sharedxmlbase/pools.lua:736, 857), so its rows are reached through EnumerateActive, which only reads
TaintWatch.SCAN_POOLS = { QuestScrollFrame = { "titleFramePool", "objectiveFramePool" } }
TaintWatch.SCAN_HITS = 200 -- tainted fields a scan entry lists; the count is always whole
-- events too frequent to say anything about a taint
TaintWatch.NOISY = {}
for _, e in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_HEALTH",
  "UNIT_AURA", "UNIT_COMBAT", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_ABSORB_AMOUNT_CHANGED",
  "UNIT_HEAL_PREDICTION", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_COOLDOWN",
  "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_UPDATE_STATE", "CURSOR_CHANGED", "MODIFIER_STATE_CHANGED",
  "UPDATE_MOUSEOVER_UNIT", "UNIT_SPELLCAST_SENT", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_FLAGS",
  "UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE", "UNIT_TARGETABLE_CHANGED", "UPDATE_UI_WIDGET", "GLOBAL_MOUSE_DOWN",
  "GLOBAL_MOUSE_UP", "UNIT_MAXHEALTH", "UNIT_MAXPOWER", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
  "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED_QUIET", "BAG_UPDATE_COOLDOWN", "UPDATE_SHAPESHIFT_COOLDOWN",
  "UNIT_RANGEDDAMAGE", "UNIT_ATTACK_SPEED", "UNIT_DAMAGE", "UNIT_RESISTANCES", "UNIT_STATS",
  "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_SOFT_FRIEND_CHANGED", "CVAR_UPDATE",
  "WORLD_CURSOR_TOOLTIP_UPDATE", "COMBAT_LOG_MESSAGE", "ACTION_RANGE_CHECK_UPDATE",
  "SPELL_ACTIVATION_OVERLAY_HIDE" }) do
  TaintWatch.NOISY[e] = true
end

-- What a bag item's right-click reads before C_Container.UseContainerItem (ContainerFrameItemButton_OnClick,
-- mainline/containerframe.lua:1503-1611): one of them tainted makes the use a forbidden call out of combat.
TaintWatch.BAG_CLICK_GLOBALS = { "ContainerFrameItemButton_OnClick", "MerchantFrame_ResetRefundItem", "MerchantFrame",
  "StackSplitFrame", "BankFrame", "GuildBankFrame", "MailFrame", "AuctionFrame", "AuctionHouseFrame", "TradeFrame",
  "ItemUpgradeFrame", "ObliterumForgeFrame", "ChallengesKeystoneFrame", "AzeriteRespecFrame", "RuneforgeFrame",
  "ItemLocation", "ItemButtonUtil", "BankUtil_IsAccountBankDepositRefundable", "ContainerFrame_GetExtendedPriceString",
  "ContainerFrame_IsAccountBankTab", "C_Container", "C_Cursor", "C_Item", "C_AuctionHouse", "C_ItemSocketInfo",
  "C_ArtifactUI", "C_MountJournal", "GetCursorInfo", "SpellCanTargetItem", "SpellCanTargetItemID", "CursorHasItem",
  "MerchantFrame_ConfirmExtendedItemCost", "MerchantFrame_ConfirmHighCostItem", "MerchantFrame_SetRefundItem",
  "StaticPopup_Show" }
-- refundItem is cleared by the click's own first call (MerchantFrame_ResetRefundItem), so it is not on the list
TaintWatch.BAG_CLICK_MERCHANT = { "selectedTab", "extendedCost", "highPrice" }

-- the fields the bar layout and the bag click read: { label, global table name (nil for a global variable), key }
local function fieldList()
  local list = {}
  for _, n in ipairs(TaintWatch.BARS) do list[#list + 1] = { n .. ".showAllButtons", n, "showAllButtons" } end
  for _, n in ipairs(TaintWatch.SNAPPED) do list[#list + 1] = { n .. ".snappedToFrame", n, "snappedToFrame" } end
  list[#list + 1] = { "MultiCastActionBarFrame.inMainActionBarState", "MultiCastActionBarFrame",
    "inMainActionBarState" }
  list[#list + 1] = { "ObjectiveTrackerFrame.topModulePadding", "ObjectiveTrackerFrame", "topModulePadding" }
  list[#list + 1] = { "ON_BAR_HIGHLIGHT_MARKS", nil, "ON_BAR_HIGHLIGHT_MARKS" }
  list[#list + 1] = { "PET_ACTION_HIGHLIGHT_MARKS", nil, "PET_ACTION_HIGHLIGHT_MARKS" }
  for _, name in ipairs(TaintWatch.BAG_CLICK_GLOBALS) do list[#list + 1] = { name, nil, name } end
  for _, key in ipairs(TaintWatch.BAG_CLICK_MERCHANT) do
    list[#list + 1] = { "MerchantFrame." .. key, "MerchantFrame", key }
  end
  return list
end
TaintWatch.fieldList = fieldList

local ring, ringPos = {}, 0

local function clock()
  local d = C.resolve("date")
  return type(d) == "function" and d("%H:%M:%S") or ""
end

local counts = {} -- ring slot → how often the addon's pass on that line ran in a row (only when more than once)
local trailLabel -- the label of the newest line when that line is one of the addon's own passes

function TaintWatch.push(text)
  if WFJ.Perf then WFJ.Perf.settle() end -- an ended frame's passes go in before what came after them
  ringPos = ringPos % TaintWatch.RING + 1
  ring[ringPos] = clock() .. " " .. tostring(text)
  counts[ringPos], trailLabel = nil, nil
end

-- One frame's line of the addon's own timed passes (Core/Perf: its labels in the order they ran), so a block or a
-- taint shows which of our surfaces ran just before it. The same line again with nothing between (a hovered item
-- refreshing) is counted on that line: no string is built for a repeat.
function TaintWatch.trail(label)
  if label == trailLabel then
    counts[ringPos] = (counts[ringPos] or 1) + 1
    return
  end
  TaintWatch.push("wfj " .. tostring(label))
  trailLabel = label
end

-- The kept events, oldest first, one per line. The frame being timed goes to the trail first (Core/Perf), so the
-- addon's passes just before the moment asked about are in it.
function TaintWatch.events()
  if WFJ.Perf then WFJ.Perf.flush() end
  local out = {}
  for i = 1, TaintWatch.RING do
    local pos = (ringPos + i - 1) % TaintWatch.RING + 1
    local e = ring[pos]
    if e then
      if counts[pos] then e = e .. " ×" .. counts[pos] end
      out[#out + 1] = e
    end
  end
  return table.concat(out, "\n")
end

local function isSecret(v)
  local f = C.resolve("issecretvalue")
  return type(f) == "function" and f(v) and true or false
end

-- One game event into the ring, with its first argument when that is a number, a boolean or one short token (an
-- addon name, a unit, an id). Chat events, any text with a space and a player's GUID are left out: the log keeps no
-- game text and nothing that names a character.
-- A unit token ("player", "party2", "nameplate14"), never a name.
local UNIT_TOKENS = { player = true, pet = true, target = true, focus = true, mouseover = true, vehicle = true,
  npc = true, softenemy = true, softfriend = true, softinteract = true }
local NUMBERED = { party = true, raid = true, arena = true, boss = true, nameplate = true }
function TaintWatch.isUnitToken(s)
  local rest, n = s, 1
  while n > 0 and rest ~= "" do -- "raid12pettarget" → "raid12"
    local a, b
    rest, a = rest:gsub("target$", "")
    rest, b = rest:gsub("pet$", "")
    n = a + b
  end
  if rest == "" then return true end
  local base, num = rest:match("^(%a+)(%d*)$")
  if not base then return false end
  if num ~= "" then return NUMBERED[base] == true end
  return UNIT_TOKENS[base] == true
end

function TaintWatch.onEvent(event, a1)
  if TaintWatch.NOISY[event] or event:find("^CHAT_MSG_") then return end
  local arg = ""
  local t = type(a1)
  if (t == "number" or t == "boolean") and not isSecret(a1) then
    arg = " " .. tostring(a1)
  elseif t == "string" and not isSecret(a1) and (event == "ADDON_LOADED" or TaintWatch.isUnitToken(a1)) then
    arg = " " .. a1 -- only an addon or unit token: another event's text may be a player's name
  end
  TaintWatch.push(event .. arg)
end

-- → true and the tainting addon when field `key` of table `t` (a global variable when `t` is nil) reads as tainted
local function check(t, key)
  local isSecure = C.resolve("issecurevariable")
  if type(isSecure) ~= "function" then return false end
  local ok, secure, by
  if t == nil then ok, secure, by = pcall(isSecure, key) else ok, secure, by = pcall(isSecure, t, key) end
  return ok and not secure, by
end
TaintWatch.isTainted = check

local function inCombat()
  local f = C.resolve("InCombatLockdown")
  return type(f) == "function" and f() and true or false
end

local function stack()
  local f = C.resolve("debugstack")
  return type(f) == "function" and (f(3, 25, 25) or "") or ""
end

-- The writer of field `label` (on `t`, or a global when `t` is nil) just ran: logged when the value is tainted.
-- → the entry, or nil
local wroteBefore = {} -- a write entry's message → true once its stack and events were kept

function TaintWatch.wrote(label, t, key)
  local tainted, by = check(t, key)
  if not tainted then return nil end
  local s = stack()
  local site = WFJ.Diag.blockedSite(s) -- the first line outside this addon: the Blizzard writer
  local msg = label .. " <" .. site .. ">"
  -- a tainted writer runs again and again (the tracker redraws on every quest update): a repeat is only counted,
  -- the ring is read for the first one
  if wroteBefore[msg] then return WFJ.Diag.log("write", msg) end
  wroteBefore[msg] = true
  return WFJ.Diag.log("write", msg, { by = tostring(by), stack = s, combat = inCombat(),
    events = TaintWatch.events() })
end

local was = {}
TaintWatch.was = was

-- One pass over FIELDS: each field that turned tainted since the last pass is logged. → the number that turned
function TaintWatch.checkFields(reason)
  local n = 0
  TaintWatch.fields = TaintWatch.fields or fieldList()
  for _, f in ipairs(TaintWatch.fields) do
    local t = f[2] and C.resolve(f[2]) or nil
    if f[2] == nil or type(t) == "table" then
      local tainted, by = check(t, f[3])
      if tainted and not was[f[1]] then
        WFJ.Diag.log("turned", f[1], { by = tostring(by), reason = tostring(reason or "timer"), combat = inCombat(),
          events = TaintWatch.events() })
        n = n + 1
      end
      was[f[1]] = tainted and true or false
    end
  end
  return n
end

local function forbidden(t)
  local ok, yes = pcall(function() return t.IsForbidden and t:IsForbidden() end)
  return ok and yes
end

-- Each field `fn(label, key)` of table `t` that reads as tainted, `depth` levels down. A forbidden frame or a table
-- the client refuses to an addon (its iteration raises) is skipped. → the number of keys checked
-- `seen` holds the depth each table was walked at, so a table first reached near the end of one root's walk is walked
-- again, deeper, from a root that names it.
local function walk(t, label, depth, seen, fn)
  if type(t) ~= "table" or (seen[t] or -1) >= depth or forbidden(t) then return 0 end
  local again = seen[t] ~= nil
  seen[t] = depth
  local n = 0
  local ok = pcall(function()
    for k, v in pairs(t) do
      -- pools and module lists are arrays: their entries are walked, only named fields are checked
      local named = type(k) == "string"
      if named and not again then
        n = n + 1
        local tainted, by = check(t, k)
        if tainted then fn(label .. "." .. k, by) end
      end
      if depth > 0 and type(v) == "table" and k ~= "parent" then
        n = n + walk(v, named and label .. "." .. k or label .. "[" .. tostring(k) .. "]", depth - 1, seen, fn)
      end
    end
  end)
  if not ok then fn(label, "unreadable") end
  return n
end

local seenBarField = {}

-- Out of combat: any field on the bars that newly reads as tainted. → the number found
function TaintWatch.sweepBars()
  if inCombat() then return 0 end
  local n = 0
  for _, name in ipairs(TaintWatch.BARS) do
    walk(C.resolve(name), name, 0, {}, function(label, by)
      if not seenBarField[label] and by ~= "unreadable" then
        seenBarField[label] = true
        n = n + 1
        WFJ.Diag.log("turned", label, { by = tostring(by), reason = "bar sweep", combat = false,
          events = TaintWatch.events() })
      end
    end)
  end
  return n
end

-- Every tainted field under SCAN_ROOTS and every global this addon tainted, logged as "taint" entries.
-- → fields found, globals found
function TaintWatch.scan(reason)
  local hits, seen, checked, found = {}, {}, 0, 0
  local function hit(label, by)
    found = found + 1
    if found <= TaintWatch.SCAN_HITS then hits[#hits + 1] = label .. " (" .. tostring(by) .. ")" end
  end
  for _, name in ipairs(TaintWatch.SCAN_ROOTS) do
    local root = C.resolve(name)
    checked = checked + walk(root, name, TaintWatch.SCAN_DEEP[name] or TaintWatch.SCAN_DEPTH, seen, hit)
    for _, key in ipairs(TaintWatch.SCAN_POOLS[name] or {}) do
      local pool = type(root) == "table" and root[key]
      local ok, rows = pcall(function()
        local list = {}
        for row in pool:EnumerateActive() do list[#list + 1] = row end
        return list
      end)
      for _, row in ipairs(ok and rows or {}) do
        local id = type(row) == "table" and (row.questID or row.layoutIndex) or "?"
        checked = checked + walk(row, name .. "." .. key .. "[" .. tostring(id) .. "]", 1, seen, hit)
      end
    end
  end
  -- under the frames the addon's declarations resolved to, only this addon's taint is listed: those frames hold other
  -- addons' and the player's keys too (a roster, a channel list), which the log never keeps
  local function ours(label, by) if by == WFJ.ADDON or by == "unreadable" then hit(label, by) end end
  for _, entry in ipairs(C.tables()) do
    checked = checked + walk(entry[2], entry[1], TaintWatch.COMPAT_DEPTH, seen, ours)
  end
  if found > #hits then hits[#hits + 1] = "… " .. (found - #hits) .. " more" end
  local globals = {}
  for name in pairs(_G) do
    if type(name) == "string" then
      local tainted, by = check(nil, name)
      if tainted and by == WFJ.ADDON then globals[#globals + 1] = name end
    end
  end
  table.sort(globals)
  local why = tostring(reason or "slash")
  WFJ.Diag.log("taint", "scan " .. clock() .. " " .. why, { reason = why, checked = checked,
    fields = table.concat(hits, " | "), globals = table.concat(globals, " | ") })
  return found, #globals
end

local scannedBlocks = {} -- a block's message → true once its scan was queued this session

-- Main, after Diag logged a block naming this addon (`entry`, its log entry): the recent events, and a scan for each
-- different block, once per session and out of combat (it walks _G, too heavy for a fight; the tainted values it
-- looks for stay tainted until rewritten). Different blocks can have different writers, so each gets its own scan.
-- → true when this block queued the scan
TaintWatch.scanPending = false
function TaintWatch.onBlocked(entry)
  -- each different block keeps the events and passes before its first time; a repeat is counted on the block's own
  -- entry, and the ring is not read again for it
  local key = type(entry) == "table" and tostring(entry.msg) or "?"
  if scannedBlocks[key] then return false end
  scannedBlocks[key] = true
  TaintWatch.scanFor = key
  WFJ.Diag.log("context", "events before " .. key, { events = TaintWatch.events() })
  TaintWatch.scanPending = true
  TaintWatch.scanWhenSafe()
  return true
end

-- Runs the queued block scan when combat is over. → true when it ran
function TaintWatch.scanWhenSafe()
  if not TaintWatch.scanPending or inCombat() then return false end
  TaintWatch.scanPending = false
  TaintWatch.scan("block " .. tostring(TaintWatch.scanFor))
  return true
end

local function hook(t, method, fn)
  local h = C.resolve("hooksecurefunc")
  if type(h) ~= "function" then return false end
  if t == nil then
    if type(C.resolve(method)) ~= "function" then return false end
    h(method, fn)
  else
    if type(t) ~= "table" or type(t[method]) ~= "function" then return false end
    h(t, method, fn)
  end
  return true
end

-- The writers of FIELDS. → the number of hooks placed
local function hookWriters()
  local n = 0
  for _, name in ipairs(TaintWatch.BARS) do
    local bar = C.resolve(name)
    if hook(bar, "SetShowGrid", function(self) TaintWatch.wrote(name .. ".showAllButtons", self, "showAllButtons") end)
    then
      n = n + 1
    end
  end
  for _, name in ipairs(TaintWatch.SNAPPED) do
    local f = C.resolve(name)
    for _, m in ipairs({ "SetSnappedToFrame", "ClearFrameSnap" }) do
      if hook(f, m, function(self) TaintWatch.wrote(name .. ".snappedToFrame", self, "snappedToFrame") end) then
        n = n + 1
      end
    end
  end
  if hook(C.resolve("MultiCastActionBarFrame"), "MainActionBarStateOverridden", function(self)
    TaintWatch.wrote("MultiCastActionBarFrame.inMainActionBarState", self, "inMainActionBarState")
  end) then
    n = n + 1
  end
  -- the tracker is load-on-demand: hooked when Blizzard_ObjectiveTracker has loaded (now, or later)
  local function hookTracker()
    local tracker = C.resolve("ObjectiveTrackerFrame")
    hook(tracker, "UpdateTopPadding", function(self)
      TaintWatch.wrote("ObjectiveTrackerFrame.topModulePadding", self, "topModulePadding")
    end)
    -- MarkDirty always sets `dirty` and queues the update with RunNextFrame, which runs it with the caller's taint;
    -- a module's MarkDirty goes through the container's (mixinutil.lua:346-352,
    -- blizzard_objectivetrackermodule.lua:86-90), so a tainted `dirty` names the caller that tainted the update
    hook(tracker, "MarkDirty", function(self)
      TaintWatch.wrote("ObjectiveTrackerFrame.dirty", self, "dirty")
    end)
    -- a title click runs block:OnHeaderClick → module:OnBlockHeaderClick (blizzard_objectivetrackerblock.lua:284-286,
    -- 386-389; blizzard_questobjectivetracker.lua:53-68): a key of the block or its module written by tainted code
    -- (a block built or refilled while tainted) would taint the whole click
    for _, name in ipairs({ "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }) do
      hook(C.resolve(name), "OnBlockHeaderClick", function(module, block)
        for _, key in ipairs({ "OnBlockHeaderClick", "OnHeaderClick", "id", "parentModule" }) do
          if type(block) == "table" and block[key] ~= nil then
            TaintWatch.wrote(name .. " block." .. key, block, key)
          end
          if type(module) == "table" and module[key] ~= nil then
            TaintWatch.wrote(name .. "." .. key, module, key)
          end
        end
      end)
    end
  end
  -- the quest log reads DetailsFrame.questID on its next refresh, on the way to the map's quest pins
  -- (questmapframe.lua:915-919, 1044-1049); a tainted id there would carry into the pins' protected call
  if hook(nil, "QuestMapFrame_ShowQuestDetails", function()
    local q = C.resolve("QuestMapFrame")
    if type(q) == "table" and type(q.DetailsFrame) == "table" then
      TaintWatch.wrote("QuestMapFrame.DetailsFrame.questID", q.DetailsFrame, "questID")
    end
  end) then
    n = n + 1
  end
  local LOD = WFJ.LoadOnDemand
  if type(LOD) == "table" and type(LOD.when) == "function" then
    LOD.when("Blizzard_ObjectiveTracker", hookTracker)
  else
    hookTracker()
  end
  for _, fn in ipairs({ "ClearOnBarHighlightMarks", "UpdateOnBarHighlightMarksBySpell",
    "UpdateOnBarHighlightMarksByFlyout", "UpdateOnBarHighlightMarksByPetAction" }) do
    if hook(nil, fn, function() TaintWatch.wrote("ON_BAR_HIGHLIGHT_MARKS", nil, "ON_BAR_HIGHLIGHT_MARKS") end) then
      n = n + 1
    end
  end
  local pet = C.resolve("PetActionBar")
  for _, m in ipairs({ "UpdatePetActionHighlightMarks", "ClearPetActionHighlightMarks" }) do
    if hook(pet, m, function() TaintWatch.wrote("PET_ACTION_HIGHLIGHT_MARKS", nil, "PET_ACTION_HIGHLIGHT_MARKS") end)
    then
      n = n + 1
    end
  end
  return n
end

local started = false

-- Called by Main after Diag. → the number of writer hooks placed, or false on a client without issecurevariable
function TaintWatch.init()
  if started then return false end
  if type(C.resolve("issecurevariable")) ~= "function" then return false end
  started = true
  local create = C.resolve("CreateFrame")
  if type(create) == "function" then
    local f = create("Frame")
    if type(f.RegisterAllEvents) == "function" then
      f:RegisterAllEvents()
      f:SetScript("OnEvent",
        WFJ.Perf.wrap("idle.watch.event", function(_, event, a1) TaintWatch.onEvent(event, a1) end))
    end
  end
  for _, fn in ipairs({ "ShowUIPanel", "HideUIPanel" }) do
    hook(nil, fn, function(frame)
      TaintWatch.push(fn .. " " .. tostring(WFJ.Diag.nameOf(frame)))
    end)
  end
  local n = hookWriters()
  TaintWatch.checkFields("load")
  local timer = C.resolve("C_Timer")
  if type(timer) == "table" and type(timer.NewTicker) == "function" then
    local ticks = 0
    timer.NewTicker(TaintWatch.CHECK_EVERY, WFJ.Perf.wrap("idle.watch.tick", function()
      ticks = ticks + 1
      TaintWatch.checkFields("timer")
      TaintWatch.scanWhenSafe()
      if ticks % TaintWatch.SWEEP_EVERY == 0 then TaintWatch.sweepBars() end
    end))
  end
  return n
end
