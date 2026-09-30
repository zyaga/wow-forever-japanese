-- UI/QuickJoin.lua: the social window's Quick Join panel and the social button beside the chat frame on Forever
-- (surface "quickjoin", area "ui", ADR-016). Blizzard_QuickJoin loads at login; QuickJoinFrame is a child of
-- FriendsFrame (quickjoin.xml:68), shown by the Quick Join tab (blizzard_friendsframe/camelot/friendsframe.lua:472;
-- the tab and the title are UI/Friends.lua's). QuickJoinToastButton is parented into the chat frame's button column
-- (blizzard_chatframebase/mainline/floatingchatframe.lua:474, 510).
-- Dynamic: QuickJoinFrame:UpdateJoinButtonState (the frame's own method, quickjoin.lua:182–203) writes
--   JoinQueueButton JOIN_QUEUE ("Request to Join") or SIGN_UP for a premade-group listing.
-- Help tooltips: JoinQueueButton's disabled reason QUICK_JOIN_ALREADY_IN_PARTY (JoinQueueButtonMixin:OnEnter,
--   quickjoin.lua:650–655); QuickJoinToastButton's title (MicroButtonTooltipText(SOCIAL_BUTTON, "TOGGLESOCIAL"), the
--   `binding` label form), and, while a toast is displayed (the tooltip's owner is then the Toast child),
--   SOCIAL_QUEUE_CLICK_TO_JOIN under the group's queue lines (quickjointoast.lua:377–400); a pooled row
--   (QuickJoinButtonMixin:OnEnter, quickjoin.lua:253–255), registered from the ScrollBox's initialized-frame callback
--   (keyed by widget). Both tooltips are written by SocialQueueUtil_SetTooltip (blizzard_uipanels_game/shared/
--   socialqueue.lua:106–175): its fixed lines "Queued for" / "queued for" (:115, 136), the delisted error (:130, 152),
--   "No Available Roles" (:168) and "Auto Accept" (:172) are matched; the title (a player name), the queue lines
--   ("- Dungeon: <name>", SocialQueueUtil_GetQueueName :14–60), the role-icon line (|T icons, :166) and a premade
--   group's LFGListUtil_SetSearchEntryTooltip lines are names or composites and are never matched (each owner is
--   restricted to its keys).
-- Composite lines (ADR-038):
--   dash: SocialQueueUtil_SetTooltip's queue lines are SocialQueueUtil_GetQueueName(queueData, "- %s")
--     (socialqueue.lua:136–140, names :39–52): after the global writer (post-hooked by name) each "- <queue>" line of
--     that tooltip whose queue is SOCIAL_QUEUE_FORMAT_ARENA ("Arena (%1$dv%1$d)"), _ARENA_SKIRMISH or _BATTLEGROUND
--     ("Battleground: %s", the map name kept) shows the dash and the queue's Japanese (surface "quickjoin.tip",
--     released on GameTooltip's OnHide); "Available Roles: <icons>" (:166) is a QUEUE_LINES key (colonPrefix);
--   toastTemplate: the toast's Toast.Text / Toast2.Text = QUICK_JOIN_TOAST_MESSAGE "%s queued for %s" or
--     _LFGLIST_MESSAGE '%s joined "%s"' (QuickJoinToastMixin:GetCurrentText, quickjointoast.lua:436–455), written by
--     its OnEvent, ShowToast and ToastToToastFinished (:76–81, 299–304, 476–481; post-hooked on QuickJoinToastButton):
--     the player's name and a listing title kept; a queue name that is an entry ("Arena Skirmish") in Japanese.
-- Never touched: the rows' member names and queue names (pooled QuickJoinButtonTemplate rows, quickjoin.lua:505–582:
--   names, client-table activity names and the player-written listing title), the friend / queue counters.
-- Set up only where FriendsFrame carries SetTitle (the mainline social window, UI/Labels.title).
local _, WFJ = ...
local QuickJoin = {}
WFJ.QuickJoin = QuickJoin

local SURFACE = "quickjoin"
QuickJoin.SURFACE = SURFACE
local Compat = WFJ.Compat

QuickJoin.NEVER_TOUCH = {}

local CANDIDATES = {
  friends = { "FriendsFrame" }, frame = { "QuickJoinFrame" }, join = { "QuickJoinFrame.JoinQueueButton" },
  toastButton = { "QuickJoinToastButton" }, toast = { "QuickJoinToastButton.Toast" },
  rows = { "QuickJoinFrame.ScrollBox" }, scrollUtil = { "ScrollUtil" },
  toastText = { "QuickJoinToastButton.Toast.Text" }, toast2Text = { "QuickJoinToastButton.Toast2.Text" },
  setTooltip = { "SocialQueueUtil_SetTooltip" }, tooltip = { "GameTooltip" },
}
local TIP = SURFACE .. ".tip"
local QUEUES = { "SOCIAL_QUEUE_FORMAT_ARENA", "SOCIAL_QUEUE_FORMAT_ARENA_SKIRMISH", "SOCIAL_QUEUE_FORMAT_BATTLEGROUND" }
local TOAST = { only = { "QUICK_JOIN_TOAST_MESSAGE", "QUICK_JOIN_TOAST_LFGLIST_MESSAGE" } }

local JOIN = { only = { "JOIN_QUEUE", "SIGN_UP" } }
local JOIN_TIP = { only = { "QUICK_JOIN_ALREADY_IN_PARTY" } }
-- SocialQueueUtil_SetTooltip's fixed lines (socialqueue.lua:115–172)
local QUEUE_LINES = { "SOCIAL_QUEUE_QUEUED_FOR", "SOCIAL_QUEUE_QUEUED_FOR_STANDALONE", "LFG_LIST_ENTRY_DELISTED",
  "QUICK_JOIN_TOOLTIP_NO_AVAILABLE_ROLES", "QUICK_JOIN_IS_AUTO_ACCEPT_TOOLTIP", "QUICK_JOIN_TOOLTIP_AVAILABLE_ROLES" }
local TOAST_TIP = { only = { "SOCIAL_BUTTON", "SOCIAL_QUEUE_CLICK_TO_JOIN", unpack(QUEUE_LINES) } }
local ROW_TIP = { only = QUEUE_LINES }

local function get(key) return Compat.get(SURFACE, key) end

-- hooksecurefunc target (QuickJoinFrame:UpdateJoinButtonState). → 1 | 0
function QuickJoin.onJoinButton()
  local n = WFJ.Labels.show(SURFACE, "join", get("join"), nil, JOIN)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- One pooled row after its initializer ran: (owner, frame, elementData) for a new row, (frame, elementData) for the
-- iterateExisting pass. Returns nothing: ForEachFrame stops at the first truthy return.
function QuickJoin.onRow(a, b)
  local row = a
  if a == QuickJoin then row = b end
  if type(row) == "table" then WFJ.HelpTooltip.register(row, ROW_TIP) end
end

-- After SocialQueueUtil_SetTooltip(tooltip, …): its "- <queue>" lines (the dash form). → n shown
function QuickJoin.onQueueTooltip(tt)
  if type(tt) ~= "table" or type(tt.NumLines) ~= "function" or type(tt.GetName) ~= "function" then return 0 end
  local name, n = tt:GetName(), 0
  if type(name) ~= "string" then return 0 end
  for i = 1, tt:NumLines() or 0 do
    local fs = Compat.resolve(name .. "TextLeft" .. i)
    local text = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
    local queue = type(text) == "string" and text:match("^%- (.+)$")
    local part = queue and WFJ.Labels.part(queue, QUEUES)
    if part then
      n = n + WFJ.Labels.showArgs(TIP, "L" .. i, fs, part.key, { form = "seq", parts = { "- ", part } })
    else
      WFJ.SurfaceState.drop(TIP, "L" .. i)
    end
  end
  if n > 0 and type(tt.Show) == "function" then tt:Show() end -- one refit for the new widths
  return n
end

-- After the toast's text writers. → the number of toast lines shown in Japanese
function QuickJoin.onToast()
  return WFJ.Labels.showAll(SURFACE, { { "toast", get("toastText"), TOAST },
    { "toast2", get("toast2Text"), TOAST } })
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function QuickJoin.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local friends, frame = get("friends"), get("frame")
  if hooked or type(frame) ~= "table" or type(friends) ~= "table" or type(friends.SetTitle) ~= "function" then
    return false -- a social window without SetTitle, or a client without the panel
  end
  hooked = true
  if type(frame.UpdateJoinButtonState) == "function" then
    hooksecurefunc(frame, "UpdateJoinButtonState", QuickJoin.onJoinButton)
  end
  local register = WFJ.HelpTooltip.register
  if type(get("join")) == "table" then register(get("join"), JOIN_TIP) end
  if type(get("toastButton")) == "table" then register(get("toastButton"), TOAST_TIP) end
  if type(get("toast")) == "table" then register(get("toast"), TOAST_TIP) end
  local rows, util = get("rows"), get("scrollUtil")
  if type(rows) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(rows, QuickJoin.onRow, QuickJoin, true)
  end
  local toastButton = get("toastButton")
  if type(toastButton) == "table" then
    for _, method in ipairs({ "ShowToast", "ToastToToastFinished" }) do
      if type(toastButton[method]) == "function" then hooksecurefunc(toastButton, method, QuickJoin.onToast) end
    end
    if type(toastButton.HookScript) == "function" then toastButton:HookScript("OnEvent", QuickJoin.onToast) end
  end
  if type(get("setTooltip")) == "function" then
    hooksecurefunc("SocialQueueUtil_SetTooltip", QuickJoin.onQueueTooltip)
  end
  local tt = get("tooltip")
  if type(tt) == "table" and type(tt.HookScript) == "function" then
    tt:HookScript("OnHide", function() WFJ.Render.release(TIP) end)
  end
  QuickJoin.onJoinButton()
  return true
end
