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
-- the client modules that react when any setting changes, and the tables the bar update reads first: walked before
-- the rest so a scan's list starts with them
TaintWatch.LISTENER_ROOTS = { "StatusTrackingBarManager", "CVarCallbackRegistry", "ActionBarButtonEventsFrame",
  "ActionBarActionEventsFrame", "ActionBarController", "OverrideActionBar", "PossessActionBar",
  "GamepadMainActionBarFrame", "MainMenuBarBackpackButton", "ContainerFrameSettingsManager", "UIParent" }
TaintWatch.SCAN_ROOTS = { "StatusTrackingBarManager", "CVarCallbackRegistry", "ActionBarButtonEventsFrame",
  "ActionBarActionEventsFrame", "ActionBarController", "OverrideActionBar", "PossessActionBar",
  "GamepadMainActionBarFrame", "MainMenuBarBackpackButton", "ContainerFrameSettingsManager", "StanceBar", "PetActionBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
  "MultiBarLeft", "MultiBarRight", "MultiBar5", "MultiBar6", "MultiBar7", "EditModeManagerFrame",
  "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "MicroButtonAndBagsBar",
  "ObjectiveTrackerFrame", "GameTooltip", "PlayerSpellsFrame", "QuestMapFrame", "WorldMapFrame", "QuestCache",
  "QuestScrollFrame", "ContainerFrameCombinedBags", "MerchantFrame", "BankFrame", "StackSplitFrame",
  "GossipFrame", "PlayerInteractionFrameManager", "UIPanelWindows", "DUIQuestFrame" }
-- the bags: a bag item's click reads its button's fields (ContainerFrame<n>.Items[i].bagID,
-- mainline/containerframe.lua:1845-1847) before it uses the item, so a tainted button field makes the use a forbidden
-- call
for i = 1, 13 do TaintWatch.SCAN_ROOTS[#TaintWatch.SCAN_ROOTS + 1] = "ContainerFrame" .. i end
-- the quest popup's and the quest window's scroll frames: a tainted scroll bar field there is read by the client's next
-- ScrollToBegin on that window (ADR-077); the details pane's is reached through QuestMapFrame
for _, name in ipairs({ "QuestLogPopupDetailFrameScrollFrame", "QuestDetailScrollFrame", "QuestProgressScrollFrame",
  "QuestRewardScrollFrame", "QuestGreetingScrollFrame" }) do
  TaintWatch.SCAN_ROOTS[#TaintWatch.SCAN_ROOTS + 1] = name
end
TaintWatch.COMPAT_DEPTH = 1 -- the frames the addon's declarations resolved to: their own fields and one level down
-- roots walked deeper than SCAN_DEPTH: a tracker quest block is ObjectiveTrackerFrame.modules[i].usedBlocks[t][id], and
-- clicking its title opens the quest log through the block's fields (blizzard_questobjectivetracker.lua:60-68); the
-- quest list's layout lives under QuestScrollFrame.Contents (questmapframe.lua:2159)
TaintWatch.SCAN_DEEP = { ObjectiveTrackerFrame = 5, QuestMapFrame = 3, QuestCache = 3, QuestScrollFrame = 3 }
-- pools whose rows the scan walks: a pool is a proxy that only has methods (CreateFramePool = CreateSecureFramePool,
-- blizzard_sharedxmlbase/pools.lua:736, 857), so its rows are reached through EnumerateActive, which only reads
TaintWatch.SCAN_POOLS = { QuestScrollFrame = { "titleFramePool", "objectiveFramePool" } }
TaintWatch.SCAN_HITS = 400 -- tainted fields a scan entry lists; the count is always whole
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
  "CONSOLE_MESSAGE", "ITEM_DATA_LOAD_RESULT",
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

local function isSecret(v) return C.secret(v) end

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
  -- rows of one list (Items[3].count, Items[4].count) are one line with their number, so a bag's 150 fields cannot
  -- fill the list and hide what came after them
  local hits, seen, checked, found = {}, {}, 0, 0
  local order, groups = {}, {}
  local function hit(label, by)
    if by ~= WFJ.ADDON and by ~= "unreadable" and label:find("^DUI") then return end -- another addon's own frame
    found = found + 1
    local key = label:gsub("%[[^%]]*%]", "[n]") .. " (" .. tostring(by) .. ")"
    if not groups[key] then
      groups[key] = 0
      order[#order + 1] = key
    end
    groups[key] = groups[key] + 1
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
  for i, key in ipairs(order) do
    if i > TaintWatch.SCAN_HITS then
      hits[#hits + 1] = "… " .. (#order - TaintWatch.SCAN_HITS) .. " more kinds"
      break
    end
    hits[#hits + 1] = groups[key] > 1 and (key .. " x" .. groups[key]) or key
  end
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
  -- the bug report carries the addon's caught errors: the refusal goes in as one, with the session's first causes
  if WFJ.ErrorLog and not TaintWatch.reported then
    TaintWatch.reported = true
    pcall(WFJ.ErrorLog.recordCaught, "Interface/AddOns/" .. tostring(WFJ.ADDON) .. "/UI/TaintWatch.lua:0: the game "
      .. "refused " .. key .. "; first tainted this session: " .. (causes[1] and TaintWatch.causes() or "none found"))
  end
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

-- The first time each field reads as tainted by this addon, found by a walk that never stops: a few hundred keys
-- every ORIGIN_EVERY seconds over the scan's roots and the frames the addon's declarations resolved to, round after
-- round. A block-time scan shows everything the taint reached; this shows the order it got there, each field with
-- the time it was first seen and, for the first ORIGIN_EVENTS of them, the events and passes before it. Rows of one
-- list (Items[3], Items[4]) are one field. It only reads.
TaintWatch.ORIGIN_EVERY = 0.1
TaintWatch.ORIGIN_KEYS = 500 -- keys checked per step
TaintWatch.ORIGIN_MAX = 300 -- fields a session logs
TaintWatch.ORIGIN_EVENTS = 4
local originQueue, originSeen, originFirst, originCount, originRound = {}, {}, {}, 0, 0

-- Tables a client function reads on the way to a field the walk found tainted, checked first in every round.
TaintWatch.ORIGIN_EXTRA = {}
TaintWatch.GLOBAL_MAX = 250 -- global names a session logs
TaintWatch.TRACE_ROOTS = 60 -- roots kept for tracing
TaintWatch.OWN_GLOBAL = { "^_G%.WFJ", "^_G%.WoWForeverJapanese", "^_G%.SLASH_WFJ", "^_G%.BINDING_[A-Z]+_WFJ" }

local globalCount = 0

local function byPath(path)
  local obj
  for part in path:gmatch("[^.]+") do
    if obj == nil then obj = C.resolve(part) else obj = type(obj) == "table" and obj[part] or nil end
    if obj == nil then return nil end
  end
  return obj
end

local originChecked = 0
local armed = {}

-- A root the walk found tainted is traced method by method from the next login on, in every session, so the next
-- time it turns the entry names the method and the calls that led to it. `_G` and UIParent are too wide to hook.
local function rootObject(root)
  for _, entry in ipairs(C.tables()) do
    if entry[1] == root then return entry[2] end
  end
  return byPath(root)
end

function TaintWatch.armPersisted()
  local roots = type(WFJ_Log) == "table" and WFJ_Log.traceRoots or nil
  if type(roots) ~= "table" then return 0 end
  local n = 0
  for root in pairs(roots) do
    if not armed[root] then
      local obj = rootObject(root)
      if type(obj) == "table" then
        armed[root] = true
        TaintWatch.traceObject(root, obj)
        n = n + 1
      end
    end
  end
  return n
end

local function rememberRoot(root)
  if type(WFJ_Log) ~= "table" or root == nil or root == "_G" or root == "UIParent" then return end
  local roots = WFJ_Log.traceRoots
  if type(roots) ~= "table" then
    roots = {}
    WFJ_Log.traceRoots = roots
  end
  if roots[root] then return end
  local count = 0
  for _ in pairs(roots) do count = count + 1 end
  if count < TaintWatch.TRACE_ROOTS then roots[root] = true end
end

local function originSeed()
  if originRound > 0 then
    WFJ.Diag.log("sweep", "round " .. originRound .. " finished", { checked = originChecked })
  end
  originRound = originRound + 1
  originChecked = 0
  originSeen = {}
  pcall(TaintWatch.armPersisted)
  -- every global name and one level under each global table: popped last, so the named roots are read first
  originQueue[#originQueue + 1] = { _G, "_G", 1 }
  for _, name in ipairs(TaintWatch.SCAN_ROOTS) do
    originQueue[#originQueue + 1] = { C.resolve(name), name, TaintWatch.SCAN_DEEP[name] or TaintWatch.SCAN_DEPTH }
  end
  originQueue[#originQueue + 1] = { C.resolve("UIParent"), "UIParent", 1 }
  for _, entry in ipairs(C.tables()) do
    originQueue[#originQueue + 1] = { entry[2], entry[1], TaintWatch.COMPAT_DEPTH }
  end
  for _, path in ipairs(TaintWatch.ORIGIN_EXTRA) do
    originQueue[#originQueue + 1] = { byPath(path), path, 1 }
  end
end

-- The first fields found tainted this session, as "<time> <field>": what a bug report says when the client then
-- refuses an action in the addon's name.
TaintWatch.CAUSES = 6
local causes = {}
local function cause(text)
  if #causes < TaintWatch.CAUSES then causes[#causes + 1] = clock() .. " " .. text end
end
function TaintWatch.causes() return table.concat(causes, "; ") end

local function originHit(label, by, root)
  if by ~= WFJ.ADDON then return end
  local key = label:gsub("%[[^%]]*%]", "[n]")
  if originFirst[key] then return end
  originFirst[key] = true
  if key:find("^_G%.") then
    for _, own in ipairs(TaintWatch.OWN_GLOBAL) do
      if key:find(own) then return end
    end
    globalCount = globalCount + 1
    if globalCount <= TaintWatch.GLOBAL_MAX then
      WFJ.Diag.log("global", key, { round = originRound, order = globalCount, combat = inCombat() })
    end
    return
  end
  rememberRoot(root)
  cause(key)
  originCount = originCount + 1
  if originCount > TaintWatch.ORIGIN_MAX then return end
  local fields = { example = label, round = originRound, order = originCount, combat = inCombat() }
  if originCount <= TaintWatch.ORIGIN_EVENTS then fields.events = TaintWatch.events() end
  WFJ.Diag.log("origin", key, fields)
end

-- One step of the walk. → the number of keys checked
function TaintWatch.originStep()
  local checked = 0
  while checked < TaintWatch.ORIGIN_KEYS do
    local item = table.remove(originQueue)
    if not item then
      originSeed()
      break -- a round ends the step, so an empty root list can never spin
    end
    local t, label, depth, root = item[1], item[2], item[3], item[4] or item[2]
    if type(t) == "table" and (originSeen[t] or -1) < depth and not forbidden(t) then
      local again = originSeen[t] ~= nil
      originSeen[t] = depth
      pcall(function()
        for k, v in pairs(t) do
          local named = type(k) == "string"
          if named and not again then
            checked = checked + 1
            local tainted, by = check(t, k)
            if tainted then originHit(label .. "." .. k, by, root) end
          end
          if depth > 0 and type(v) == "table" and k ~= "parent" then
            originQueue[#originQueue + 1] = { v, named and label .. "." .. k or label .. "[" .. tostring(k) .. "]",
              depth - 1, root }
          end
        end
      end)
    end
  end
  originChecked = originChecked + checked
  return checked
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

-- The merchant window's OnShow sets its tab (PanelTemplates_SetTab(MerchantFrame, 1), mainline/merchantframe.lua:154)
-- and then opens every bag; a bag item's click reads that tab before it uses the item (containerframe.lua:1544-1546).
-- A tab written tainted means the whole OnShow ran tainted: its stack and one scan (the talk window it often opens
-- from, the panel manager) name what carried the taint in.
local scannedMerchant = false
local function onSetTab(frame)
  local merchant = C.resolve("MerchantFrame")
  if frame == nil or frame ~= merchant then return end
  if not TaintWatch.wrote("MerchantFrame.selectedTab", frame, "selectedTab") then return end
  if scannedMerchant or inCombat() then return end
  scannedMerchant = true
  TaintWatch.scan("merchant tab written tainted")
end

-- The writers of FIELDS. → the number of hooks placed
local function hookWriters()
  local n = 0
  if hook(nil, "PanelTemplates_SetTab", onSetTab) then n = n + 1 end
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
    -- the rest of what the click reads before it opens the quest log (blizzard_objectivetrackerblock.xml:16-27, the
    -- title button's OnClick method; blizzard_questobjectivetracker.lua:51-68; chatframeutil.lua:625-633;
    -- objectcache.lua:5-20 and quest.lua:20-40, the quest's cache entry): any of them written by tainted code taints
    -- the click, and the quest log it opens writes the map's quest fields as this addon's
    local CLICK_GLOBALS = { "ChatFrameUtil", "IsModifiedClick", "GetQuestLink", "QuestUtil", "QuestCache", "C_QuestLog",
      "QuestMapFrame_OpenToQuestDetails", "ShowQuestComplete" }
    local QUEST_KEYS = { "isAutoComplete", "CheckRefresh", "IsComplete", "GetID", "questID", "hasQuestLogInfo" }
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
        local button = type(block) == "table" and block.HeaderButton or nil
        if type(button) == "table" and button.OnClick ~= nil then
          TaintWatch.wrote(name .. " block.HeaderButton.OnClick", button, "OnClick")
        end
        for _, g in ipairs(CLICK_GLOBALS) do
          if C.resolve(g) ~= nil then TaintWatch.wrote(g, nil, g) end
        end
        local chat = C.resolve("ChatFrameUtil")
        if type(chat) == "table" then
          for _, key in ipairs({ "TryInsertQuestLinkForQuestID", "TryInsertChatLink" }) do
            if chat[key] ~= nil then TaintWatch.wrote("ChatFrameUtil." .. key, chat, key) end
          end
        end
        local cache = C.resolve("QuestCache")
        local id = type(block) == "table" and block.id or nil
        if type(cache) == "table" and type(cache.objects) == "table" and id ~= nil then
          if cache.Get ~= nil then TaintWatch.wrote("QuestCache.Get", cache, "Get") end
          TaintWatch.wrote("QuestCache.objects[" .. tostring(id) .. "]", cache.objects, id)
          local quest = cache.objects[id]
          if type(quest) == "table" then
            for _, key in ipairs(QUEST_KEYS) do
              if quest[key] ~= nil then
                TaintWatch.wrote("QuestCache.objects[" .. tostring(id) .. "]." .. key, quest, key)
              end
            end
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
  -- the map's quest pins compare the shown map id before their protected call (blizzard_mapcanvas.lua:60-65); set
  -- by tainted code (the quest log opened from an addon), it blocks the pins on the next world map open in combat
  local function hookMap()
    hook(C.resolve("WorldMapFrame"), "SetMapID", function(self)
      TaintWatch.wrote("WorldMapFrame.mapID", self, "mapID")
    end)
  end
  local LOD = WFJ.LoadOnDemand
  if type(LOD) == "table" and type(LOD.when) == "function" then
    LOD.when("Blizzard_ObjectiveTracker", hookTracker)
    LOD.when("Blizzard_WorldMap", hookMap)
  else
    hookTracker()
    hookMap()
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

-- Client functions whose writes last the session and that an addon cannot read back (a panel's layout attributes
-- are written on the first call that asks for them and carry the taint of that call from then on [verified: forever
-- blizzard_uiparentpanelmanager/shared/uiparentpanelmanager.lua:85-109]). A call of one with an addon's file on the
-- stack is logged with that stack: the line that made the call, in this addon or another.
TaintWatch.CALLED = { "ShowUIPanel", "HideUIPanel", "ToggleUIPanel", "SetUIPanelShown", "SetUIPanelAttribute",
  "UpdateUIPanelPositions", "UIPanelUpdateScaleForFit", "GetUIPanelWidth", "GetUIPanelHeight", "MaximizeUIPanel",
  "RestoreUIPanelArea", "ToggleFrame", "CloseWindows", "CloseAllWindows", "CloseSpecialWindows", "ToggleGameMenu",
  "OpenAllBags", "CloseAllBags", "ToggleAllBags", "OpenBag", "CloseBag", "ToggleBag", "ToggleBackpack",
  "OpenBackpack", "CloseBackpack", "StaticPopup_Show", "StaticPopup_Hide", "ToggleCharacter", "ToggleQuestLog",
  "ToggleWorldMap", "ToggleFriendsFrame", "UIParent_ManageFramePositions", "ManageFramePositions",
  "ActionBarController_UpdateAll", "PanelTemplates_SetTab", "MerchantFrame_Update", "SetCVar" }
TaintWatch.CALLED_MAX = 30 -- distinct callers a session logs
TaintWatch.CALLED_EVENTS = 3 -- of them, the first few keep the events before the call

local calledSeen, calledCount = {}, 0

-- → the first stack line from an addon that is not the client's own and not this watcher, or nil
function TaintWatch.outsideCaller(s)
  for line in tostring(s):gmatch("[^\n]+") do
    local addon = line:match("[Aa]dd[Oo]ns[/\\]([^/\\]+)[/\\]")
    if addon and not addon:find("^Blizzard_") and not line:find("TaintWatch.lua", 1, true) then
      return (line:gsub("^%s+", ""))
    end
  end
  return nil
end

function TaintWatch.called(fn, a1)
  if calledCount >= TaintWatch.CALLED_MAX then return end
  local s = stack()
  local caller = TaintWatch.outsideCaller(s)
  if not caller then return end
  local site = caller:match("^(.-:%d+)") or caller
  local key = fn .. " " .. site
  if calledSeen[key] then return end
  calledSeen[key] = true
  calledCount = calledCount + 1
  local combat = C.resolve("InCombatLockdown")
  WFJ.Diag.log("caller", key, { arg = tostring(WFJ.Diag.nameOf(a1)), stack = s,
    events = calledCount <= TaintWatch.CALLED_EVENTS and TaintWatch.events() or nil,
    combat = type(combat) == "function" and combat() or false })
end

-- A client window whose fields the walk found tainted is traced method by method from the next login on (the roots
-- are kept in the log): every function the object carries gets a post-hook that looks for a field tainted since the
-- last look, so the first entry names the method after which taint first shows and the calls that led to it.
TaintWatch.TRACED_PER_OBJECT = 8
TaintWatch.TRACED_LOOKS = 3000 -- method calls an object is read after, per session
TaintWatch.TRACED_EVENTS = 4

local tracedCount = 0

local function tracedLook(label, method, obj, state)
  if state.hits >= TaintWatch.TRACED_PER_OBJECT then return end
  -- an object that stays clean stops being read: its methods can run every frame
  state.looks = (state.looks or 0) + 1
  if state.looks > TaintWatch.TRACED_LOOKS then
    state.hits = TaintWatch.TRACED_PER_OBJECT
    return
  end
  for k in pairs(obj) do
    if type(k) == "string" and not state.seen[k] then
      local tainted, by = check(obj, k)
      if tainted then
        state.seen[k] = true
        state.hits = state.hits + 1
        tracedCount = tracedCount + 1
        local fields = { by = tostring(by), stack = stack(), order = tracedCount, combat = inCombat() }
        if tracedCount <= TaintWatch.TRACED_EVENTS then fields.events = TaintWatch.events() end
        WFJ.Diag.log("traced", label .. ":" .. method .. " -> " .. k, fields)
        if state.hits >= TaintWatch.TRACED_PER_OBJECT then return end
      end
    end
  end
end

function TaintWatch.traceObject(label, obj)
  local h = C.resolve("hooksecurefunc")
  if type(obj) ~= "table" or type(h) ~= "function" then return 0 end
  local state, names = { seen = {}, hits = 0 }, {}
  for k, v in pairs(obj) do
    if type(k) == "string" then
      if check(obj, k) then state.seen[k] = true end
      if type(v) == "function" then names[#names + 1] = k end
    end
  end
  WFJ.Diag.log("traced", label .. " armed", { methods = #names, already = (function()
    local t = {}
    for k in pairs(state.seen) do t[#t + 1] = k end
    table.sort(t)
    return table.concat(t, " ")
  end)() })
  for _, name in ipairs(names) do
    pcall(h, obj, name, function() tracedLook(label, name, obj, state) end)
  end
  return #names
end

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
      -- the noisy events (combat log, power, every frame's kind) are turned away before any timing
      f:SetScript("OnEvent", function(_, event, a1)
        if TaintWatch.NOISY[event] or event:find("^CHAT_MSG_") then return end
        WFJ.Perf.call("idle.watch.event", TaintWatch.onEvent, event, a1)
      end)
    end
  end
  for _, fn in ipairs({ "ShowUIPanel", "HideUIPanel" }) do
    hook(nil, fn, function(frame)
      TaintWatch.push(fn .. " " .. tostring(WFJ.Diag.nameOf(frame)))
    end)
  end
  for _, fn in ipairs(TaintWatch.CALLED) do
    hook(nil, fn, function(a1) TaintWatch.called(fn, a1) end)
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
    timer.NewTicker(TaintWatch.ORIGIN_EVERY, WFJ.Perf.wrap("idle.watch.origin", TaintWatch.originStep))
  end
  return n
end
