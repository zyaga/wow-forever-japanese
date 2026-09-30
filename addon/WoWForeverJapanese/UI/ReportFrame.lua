-- UI/ReportFrame.lua: the Report Player window on Forever (surface "reportframe", area "ui", ADR-016).
-- Blizzard_ReportFrame (ReportFrame, reportframe.xml:3) inherits Blizzard_ReportFrameShared's
-- SharedReportFrameTemplate;
-- both load at login. It is an ordinary frame shown with self:Show() (reportframeshared.lua:121), not a StaticPopup,
-- opened by the unit menus' Report entries, the mail frame (blizzard_mailframe/mailframe.lua:1137), the calendar
-- and the group finder (blizzard_groupfinder_vanillastyle/blizzard_lfgvanilla_browse.lua:1442–1456).
-- Static labels (XML text=; each restricted to its own key): TitleText, ThankYouText (the "thank you" page is part of
--   the window, whatever its ERR_ name says), ReportingMajorCategoryDropdown.Label, ReportButton,
--   MinorReportDescription (reportframeshared.xml:69–191); the comment box's Instructions FontString, filled from the
--   `instructions` key value (xml:168); the EditBox's own text is never touched.
-- Dynamic, each the frame's own method (the mixin is copied onto the frame at load; every call is `self:…()`):
--   ReportFrame:InitiateReportInternal → ReportString "Report <player>", the name kept as written (lua:125–127);
--   ReportFrame:MajorTypeSelected → the pooled minor-category check buttons' Text, _G[C_ReportSystem
--     .GetMinorCategoryString(…)] (MinorCategoryButtonPool, lua:8, 165–175, 278–294), walked from the pool and keyed
--     by widget; each is also a help-tooltip owner for HARMFUL_TO_MINORS_DISABLED_TOOLTIP (lua:308–316);
--   the reason dropdown's own text after DropdownTextMixin:UpdateText (blizzard_menu/menutemplates.lua:712–713):
--     REPORTING_MAKE_SELECTION (SetDefaultText, lua:15) or the selected major category. The popup's entries are
--     not handled here.
-- Help tooltip: ReportButton's REPORTING_MAKE_SELECTION (lua:353–362).
-- Not here: the screenshot section and ReportScreenshotModeFrame serve decor reports only (housing is gated
-- `standard`, never loaded on camelot); the reported player's name.
-- Set up only where ReportFrame.ReportingMajorCategoryDropdown carries the Menu system's UpdateText.
local _, WFJ = ...
local ReportFrame = {}
WFJ.ReportFrame = ReportFrame

local SURFACE = "reportframe"
ReportFrame.SURFACE = SURFACE
local Compat = WFJ.Compat

ReportFrame.NEVER_TOUCH = { "ReportFrame.Comment.EditBox" }

local LABELS = {
  title = { "ReportFrame.TitleText", { "BEHAVIORAL_DETAILS_TITLE_BAR" } },
  thankYou = { "ReportFrame.ThankYouText", { "ERR_REPORT_SUBMITTED_SUCCESSFULLY" } },
  player = { "ReportFrame.ReportString", { "REPORTING_REPORT_PLAYER" } },
  reason = { "ReportFrame.ReportingMajorCategoryDropdown.Label", { "REPORTING_REPORT_REASON" } },
  report = { "ReportFrame.ReportButton", { "REPORTING_REPORT" } },
  details = { "ReportFrame.MinorReportDescription", { "REPORTING_REPORT_DETAILS" } },
  instructions = { "ReportFrame.Comment.EditBox.Instructions", { "REPORTING_COMMENT_INSTRUCTIONS" } },
}
local ORDER = {}
for key in pairs(LABELS) do ORDER[#ORDER + 1] = key end
table.sort(ORDER)

local MAJOR = { only = { "REPORTING_MAKE_SELECTION", "REPORTING_MAJOR_CATEGORY_INAPPROPRIATE_COMMUNICATION",
  "REPORTING_MAJOR_CATEGORY_GAMEPLAY_SABOTAGE", "REPORTING_MAJOR_CATEGORY_CHEATING",
  "REPORTING_MAJOR_CATEGORY_INAPPROPRIATE_NAME", "REPORTING_MAJOR_CATEGORY_CHINA_HARMFUL_MINORS" } }
local MINOR_NAMES = { "TEXT_CHAT", "AFK", "HACKING", "INAPPROPRIATE", "BTAG", "VOICE_CHAT", "SPAM", "BLOCKING_PROG",
  "FEEDING", "BOTTING", "ADVERTISEMENT", "GROUP_NAME", "BOOSTING", "CUSTOM_GAME_NAME", "CHARACTER_NAME", "GUILD_NAME",
  "DESCRIPTION", "NAME", "HARMFUL_INFO_FOR_MINORS", "HARMFUL_TO_MINORS", "DISRUPTION", "TVEC", "CSEA" }
local MINOR = { only = {} }
for i, name in ipairs(MINOR_NAMES) do MINOR.only[i] = "REPORTING_MINOR_CATEGORY_" .. name end
local MINOR_TIP = { only = { "HARMFUL_TO_MINORS_DISABLED_TOOLTIP" } }
local REPORT_TIP = { only = { "REPORTING_MAKE_SELECTION" } }

local CANDIDATES = { frame = { "ReportFrame" }, dropdown = { "ReportFrame.ReportingMajorCategoryDropdown" },
  reportButton = { "ReportFrame.ReportButton" } }

local function get(key) return Compat.get(SURFACE, key) end

-- Shows the named labels (all of them when none is named). → the number of dictionary words found.
function ReportFrame.show(...)
  local keys = select("#", ...) > 0 and { ... } or ORDER
  local items = {}
  for _, key in ipairs(keys) do
    items[#items + 1] = { key, get("label." .. key), { only = LABELS[key][2] } }
  end
  return WFJ.Labels.showAll(SURFACE, items)
end

-- hooksecurefunc target (the reason dropdown's UpdateText). → 1 | 0
function ReportFrame.onReason()
  local dropdown = get("dropdown")
  if type(dropdown) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, "reasonText", dropdown.Text, nil, MAJOR)
end

local buttonKey = WFJ.Labels.keyer("minor.") -- a pooled check button's record key (follows the widget)

-- hooksecurefunc target (ReportFrame:MajorTypeSelected). → the number of dictionary words found.
function ReportFrame.onMajorType()
  local frame = get("frame")
  local pool = type(frame) == "table" and frame.MinorCategoryButtonPool or nil
  local n = 0
  if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
    for button in pool:EnumerateActive() do
      if type(button) == "table" and type(button.Text) == "table" then
        n = n + WFJ.Labels.show(SURFACE, buttonKey(button.Text), button.Text, nil, MINOR)
        WFJ.HelpTooltip.register(button, MINOR_TIP)
      end
    end
  end
  return n + ReportFrame.show("details")
end

-- hooksecurefunc target (ReportFrame:InitiateReportInternal): a new report resets the whole window.
function ReportFrame.onReport()
  return ReportFrame.show() + ReportFrame.onReason()
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function ReportFrame.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(LABELS) do Compat.declare(SURFACE, "label." .. key, { l[1] }) end
  local frame, dropdown = get("frame"), get("dropdown")
  if hooked or type(frame) ~= "table" or type(dropdown) ~= "table" or type(dropdown.UpdateText) ~= "function" then
    return false -- no report window of this shape
  end
  hooked = true
  hooksecurefunc(dropdown, "UpdateText", ReportFrame.onReason)
  if type(frame.InitiateReportInternal) == "function" then
    hooksecurefunc(frame, "InitiateReportInternal", ReportFrame.onReport)
  end
  if type(frame.MajorTypeSelected) == "function" then
    hooksecurefunc(frame, "MajorTypeSelected", ReportFrame.onMajorType)
  end
  if type(get("reportButton")) == "table" then WFJ.HelpTooltip.register(get("reportButton"), REPORT_TIP) end
  ReportFrame.onReport()
  return true
end
