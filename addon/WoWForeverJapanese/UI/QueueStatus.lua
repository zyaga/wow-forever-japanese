-- UI/QueueStatus.lua: the queue status button's hover panel on Forever (surface "queuestatus", area "ui",
-- ADR-016). Blizzard_QueueStatusFrame loads at login with camelot overrides (blizzard_queuestatusframe.toc:
-- [Family]\QueueStatusFrame.lua, [Game]\QueueStatusFrameOverrides.lua; the eye button is anchored to the minimap
-- and opens the Vanilla-style group finder, camelot/queuestatusframeoverrides.lua:5–37). QueueStatusButton shows
-- whenever the player has a queue, a listing or an active battlefield; hovering it shows QueueStatusFrame, a
-- tooltip-like frame (mainline/queuestatusframe.lua:192–196, xml:410) that is NOT a GameTooltip, so UI/HelpTooltip
-- never sees it. A client without QueueStatusFrame: init returns false and nothing is touched.
-- Writers:
--   QueueStatusFrame:Update (lua:522–721; every registered event calls self:Update(), :456–457) releases the pooled
--     QueueStatusEntryTemplate frames (statusEntriesPool, :518) and fills one per queue through
--     QueueStatusEntry_SetMinimalDisplay / _SetFullDisplay (:1095–1142, 1144–1252):
--       Status       a QUEUED_STATUS_* word (:1099)
--       Title        a battleground, dungeon-category or zone name, left English; the two fixed titles are
--                    HUD_EDIT_MODE_TITLE (edit mode's placeholder entry, :694) and PET_BATTLE_PVP_QUEUE (:1067–1075)
--       SubTitle     QUEUED_STATUS_LOCKED_EXPLANATION (:1027), LFG_LIST_PENDING_APPLICANTS (:987); otherwise a
--                    dungeon / activity name or a brawl description (server text)
--       TimeInQueue  TIME_IN_QUEUE with a SecondsToTime duration or LESS_THAN_ONE_MINUTE (:1083–1086)
--       AverageWait  LFG_STATISTIC_AVERAGE_WAIT with a SecondsToTime duration (:1235)
--     The frame's method is post-hooked and every active entry walked, keyed by widget (entries are pooled and
--     re-sorted, :478–507), each widget restricted to the keys it can legitimately show;
--   QueueStatusEntry_OnUpdate (:1254–1263), the entry's OnUpdate while it is visible, rewrites TimeInQueue every
--     0.1 s. It is a global read at SetScript time (:1084), so the post-hook reaches every entry set up after init.
-- The `%s` of TIME_IN_QUEUE / LFG_STATISTIC_AVERAGE_WAIT is a `time` argument (Core/UIStrings ARGS); without that
-- ARGS line the two lines stay English. "< 1 minute" does not start with a digit, so a first-minute line stays
-- English either way (in-game checklist).
-- Never touched: ExtraText (dungeon names joined with ", " after ALSO_QUEUED_FOR, or "<player> is not ready" lines
-- joined with "\n", :917–927: name-carrying composites), the role counts (PLAYERS_FOUND_OUT_OF_MAX, numbers).
-- Not here: the button's right-click menu (QueueStatusButtonMixin:ShowContextMenu, :222–290, handled with the menus)
-- and its HelpTip callout (:333–350, handled with the HelpTips).
-- Blizzard computes each entry's height from the English text right after writing it (:1106–1141); a Japanese line
-- that wraps differently is an in-game check.
local _, WFJ = ...
local QueueStatus = {}
WFJ.QueueStatus = QueueStatus

local SURFACE = "queuestatus"
QueueStatus.SURFACE = SURFACE
local Compat = WFJ.Compat

-- Pooled entries have no global names; ExtraText and the role counts are forbidden per entry in showEntry.
QueueStatus.NEVER_TOUCH = {}

local CANDIDATES = { frame = { "QueueStatusFrame" }, entryTick = { "QueueStatusEntry_OnUpdate" } }

local STATUS = { only = { "QUEUED_STATUS_IN_PROGRESS", "QUEUED_STATUS_LISTED", "QUEUED_STATUS_LOCKED",
  "QUEUED_STATUS_PROPOSAL", "QUEUED_STATUS_READY_CHECK_IN_PROGRESS", "QUEUED_STATUS_ROLE_CHECK_IN_PROGRESS",
  "QUEUED_STATUS_SIGNED_UP", "QUEUED_STATUS_SUSPENDED", "QUEUED_STATUS_UNKNOWN", "QUEUED_STATUS_WAITING" } }
local TITLE = { only = { "HUD_EDIT_MODE_TITLE", "PET_BATTLE_PVP_QUEUE" } }
local SUBTITLE = { only = { "QUEUED_STATUS_LOCKED_EXPLANATION", "LFG_LIST_PENDING_APPLICANTS" } }
local TIME = { only = { "TIME_IN_QUEUE" } }
local WAIT = { only = { "LFG_STATISTIC_AVERAGE_WAIT" } }
local FIELDS = { { "Title", TITLE }, { "Status", STATUS }, { "SubTitle", SUBTITLE }, { "TimeInQueue", TIME },
  { "AverageWait", WAIT } }
local COUNTS = { "TanksFound", "HealersFound", "DamagersFound" }

local function get(key) return Compat.get(SURFACE, key) end

local widgetKey = WFJ.Labels.keyer("entry.") -- a pooled entry widget's record key (follows the widget)

-- One entry's labels. → the number of dictionary words found.
function QueueStatus.showEntry(entry)
  if type(entry) ~= "table" then return 0 end
  WFJ.Labels.forbid(entry.ExtraText) -- names joined at run time
  for _, field in ipairs(COUNTS) do
    local found = entry[field]
    if type(found) == "table" then WFJ.Labels.forbid(found.Count) end
  end
  local n = 0
  for _, f in ipairs(FIELDS) do
    local widget = entry[f[1]]
    if type(widget) == "table" then n = n + WFJ.Labels.show(SURFACE, widgetKey(widget), widget, nil, f[2]) end
  end
  return n
end

-- hooksecurefunc target (QueueStatusEntry_OnUpdate(entry, elapsed)): the queue timer. → 1 | 0
function QueueStatus.onEntryTick(entry)
  local widget = type(entry) == "table" and entry.TimeInQueue or nil
  if type(widget) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, widgetKey(widget), widget, nil, TIME)
end

-- hooksecurefunc target (QueueStatusFrame:Update). → the number of dictionary words found.
function QueueStatus.onUpdate()
  local frame = get("frame")
  local pool = type(frame) == "table" and frame.statusEntriesPool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  for entry in pool:EnumerateActive() do n = n + QueueStatus.showEntry(entry) end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function QueueStatus.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end -- a client without the frame
  hooked = true
  if type(frame.Update) == "function" then hooksecurefunc(frame, "Update", QueueStatus.onUpdate) end
  if type(get("entryTick")) == "function" then
    hooksecurefunc("QueueStatusEntry_OnUpdate", QueueStatus.onEntryTick)
  end
  QueueStatus.onUpdate()
  return true
end
