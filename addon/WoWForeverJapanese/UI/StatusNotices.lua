-- UI/StatusNotices.lua: the status tray's support notices on Forever (surface "statusnotices", area "ui",
-- ADR-016): three load-on-demand addons that each put a Blizzard_StatusUI notice under the buffs and share that one
-- shape (a StatusUIFrame's TitleText / SubtitleText), so they share this file. Each is loaded by an event routed in
-- blizzard_game/shared/eventimplementation.lua, and waited for through WFJ.LoadOnDemand.when:
--   Blizzard_GMChatUI (GMChatFrame_OnWhisperFromGM, :297; RestoreGMChatFrameSession, mainline/eventimplementation
--     .lua:918): GMChatStatusFrame's TitleText / SubtitleText, written once in its OnLoad (blizzard_gmchatui.lua:
--     185–187), and the GM chat window's tab label GMChatTabText GM_CHAT (blizzard_gmchatui.xml:31). The chat lines
--     themselves are chat text (GMChatFrame:AddMessage);
--   Blizzard_WowSurveyUI (WowSurveyStatusFrame_OnSurveyDelivered, :43): WowSurveyStatusFrame's TitleText /
--     SubtitleText (blizzard_wowsurveyui.lua:34–36). Its question is a StaticPopup (WOW_SURVEY; ADR-015 §5);
--   Blizzard_BehavioralMessaging (BehavioralMessagingTray_OnNotification, :302): the tray's pooled notifications:
--     TitleText is the notification's label, SubtitleText BEHAVIORAL_NOTIFICATION_OPEN (blizzard_behavioralmessaging
--     .lua:17–21, 38–44, .xml:17), walked from the pool after BehavioralMessagingTray:EvaluateLayout (the frame's own
--     method, lua:148–160), keyed by widget; and the BehavioralMessagingDetails window: its title bar Text, the
--     CloseButton (xml:87, 124) and Body.TitleText / Body.BodyText after :DisplayInternal (lua:190–194).
--     A stacked notification's "<label> (<n>)" is a composite and stays English.
-- Records written once at load are shown once at setup; nothing here is a name.
local _, WFJ = ...
local StatusNotices = {}
WFJ.StatusNotices = StatusNotices

local SURFACE = "statusnotices"
StatusNotices.SURFACE = SURFACE
local Compat = WFJ.Compat

StatusNotices.NEVER_TOUCH = { "GMChatFrameEditBox" }

local DETAILS = "BehavioralMessagingDetails"

-- addon → { record key → { candidate, the keys it may show } }
local ADDONS = {
  Blizzard_GMChatUI = {
    gmTitle = { "GMChatStatusFrame.TitleText", { "GM_CHAT_STATUS_READY" } },
    gmSubtitle = { "GMChatStatusFrame.SubtitleText", { "GM_CHAT_STATUS_READY_DESCRIPTION" } },
    gmTab = { "GMChatTabText", { "GM_CHAT" } },
  },
  Blizzard_WowSurveyUI = {
    surveyTitle = { "WowSurveyStatusFrame.TitleText", { "USER_SURVEY_STATUS_READY" } },
    surveySubtitle = { "WowSurveyStatusFrame.SubtitleText", { "USER_SURVEY_STATUS_READY_DESCRIPTION" } },
  },
  Blizzard_BehavioralMessaging = {
    detailsBar = { DETAILS .. ".Text", { "BEHAVIORAL_DETAILS_TITLE_BAR" } },
    detailsClose = { DETAILS .. ".CloseButton", { "BEHAVIORAL_DETAILS_CLOSE_BUTTON" } },
    detailsTitle = { DETAILS .. ".Body.TitleText",
      { "BEHAVIORAL_DETAILS_SOCIAL_TITLE", "BEHAVIORAL_DETAILS_TY_TITLE" } },
    detailsBody = { DETAILS .. ".Body.BodyText",
      { "BEHAVIORAL_DETAILS_SOCIAL_MESSAGE", "BEHAVIORAL_DETAILS_TY_MESSAGE" } },
  },
}
local ADDON_ORDER = { "Blizzard_GMChatUI", "Blizzard_WowSurveyUI", "Blizzard_BehavioralMessaging" }

local CANDIDATES = { tray = { "BehavioralMessagingTray" }, details = { DETAILS } }
local NOTICE_TITLE = { only = { "BEHAVIORAL_NOTIFICATION_WARNING", "BEHAVIORAL_NOTIFICATION_TY" } }
local NOTICE_SUBTITLE = { only = { "BEHAVIORAL_NOTIFICATION_OPEN" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for _, labels in pairs(ADDONS) do
    for key, l in pairs(labels) do Compat.declare(SURFACE, "label." .. key, { l[1] }) end
  end
end

-- Shows one addon's labels. → the number of dictionary words found.
function StatusNotices.show(addon)
  local items, keys = {}, {}
  for key in pairs(ADDONS[addon] or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    items[#items + 1] = { key, get("label." .. key), { only = ADDONS[addon][key][2] } }
  end
  return WFJ.Labels.showAll(SURFACE, items)
end

local noticeKey = WFJ.Labels.keyer("notice.") -- a pooled notification's record key (follows the widget)

-- hooksecurefunc target (BehavioralMessagingTray:EvaluateLayout). → the number of dictionary words found.
function StatusNotices.onTray()
  local tray = get("tray")
  local pool = type(tray) == "table" and tray.pool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  for notice in pool:EnumerateActive() do
    if type(notice) == "table" then
      if type(notice.TitleText) == "table" then
        n = n + WFJ.Labels.show(SURFACE, noticeKey(notice.TitleText), notice.TitleText, nil, NOTICE_TITLE)
      end
      if type(notice.SubtitleText) == "table" then
        n = n + WFJ.Labels.show(SURFACE, noticeKey(notice.SubtitleText), notice.SubtitleText, nil, NOTICE_SUBTITLE)
      end
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (BehavioralMessagingDetails:DisplayInternal).
function StatusNotices.onDetails() return StatusNotices.show("Blizzard_BehavioralMessaging") end

local hooked = {}

-- One addon's part: runs once it is loaded (now, or on its ADDON_LOADED). → true when anything was set up.
function StatusNotices.setup(addon)
  declare() -- its frames exist only now: forget what Compat memoized before
  local first = not hooked[addon]
  hooked[addon] = true
  if addon == "Blizzard_GMChatUI" then WFJ.Labels.forbidNames(StatusNotices.NEVER_TOUCH) end
  if addon == "Blizzard_BehavioralMessaging" and first then
    local tray, details = get("tray"), get("details")
    if type(tray) == "table" and type(tray.EvaluateLayout) == "function" then
      hooksecurefunc(tray, "EvaluateLayout", StatusNotices.onTray)
    end
    if type(details) == "table" and type(details.DisplayInternal) == "function" then
      hooksecurefunc(details, "DisplayInternal", StatusNotices.onDetails)
    end
    StatusNotices.onTray()
  end
  return StatusNotices.show(addon) > 0 and first
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
-- → true when at least one of the addons was already loaded.
function StatusNotices.init()
  declare()
  local any = false
  for _, addon in ipairs(ADDON_ORDER) do
    if WFJ.LoadOnDemand.when(addon, function() StatusNotices.setup(addon) end) then any = true end
  end
  return any
end
