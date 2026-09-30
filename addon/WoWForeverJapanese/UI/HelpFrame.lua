-- UI/HelpFrame.lua: the Customer Support window and the open-ticket notices on Forever (surface "helpframe", area
-- "ui", ADR-016). Blizzard_HelpFrame loads at login; ToggleHelpFrame is the game menu's Support button
-- (blizzard_gamemenu/shared/gamemenuframe.lua:253) and the help micro button (blizzard_micromenu/mainline/
-- mainmenubarmicrobuttons.lua:1925). The window's body is an embedded web browser: the client draws nothing but the
-- frame's chrome around it.
-- Title: HelpFrame:SetTitle(HELP_FRAME_TITLE) at its OnLoad (helpframe.lua:51; DefaultPanelTemplate's
--   TitleContainer.TitleText, blizzard_sharedxml/mainline/shareduipaneltemplates.xml:478–486) → Labels.title.
-- Static labels: BrowserSettingsTooltip.Title and .CookiesButton (helpframe.xml:82, 90).
-- Dynamic: TicketStatusTitleText, written by TicketStatusFrame_OnEvent (helpframe.lua:245–265). The XML binds that
--   global by reference (xml:241), so the frame's OnEvent script is post-hooked with HookScript.
-- Help tooltips: BrowserSettingsTooltip.CookiesButton (xml:103–105); HelpOpenWebTicketButton (helpframe.lua:154–177):
--   TICKET_STATUS, the status line (needs more info / high volume / wait time unavailable / "Average ticket wait
--   time:\n<time>"), GM_RESPONSE_ALERT and the grey click hint. A title or a description the server overrides is
--   server text and is never matched (the owner is restricted to its keys).
-- Not here: ReportCheatingDialog is shown with StaticPopupSpecial_Show (helpframe.lua:147, ADR-015 §5); the
-- external-link dialog is a StaticPopup (helpframe.lua:2–5).
-- Set up only where HelpFrame carries SetTitle (UI/Labels.title).
local _, WFJ = ...
local HelpFrame = {}
WFJ.HelpFrame = HelpFrame

local SURFACE = "helpframe"
HelpFrame.SURFACE = SURFACE
local Compat = WFJ.Compat

HelpFrame.NEVER_TOUCH = { "ReportCheatingDialogCommentFrameEditBox" }

local LABELS = {
  browserTitle = { "BrowserSettingsTooltip.Title", { "BROWSER_SETTINGS_TOOLTIP" } },
  cookies = { "BrowserSettingsTooltip.CookiesButton", { "BROWSER_DELETE_COOKIES" } },
  ticket = { "TicketStatusTitleText", { "TICKET_STATUS_NMI", "CHOSEN_FOR_GMSURVEY", "GM_RESPONSE_ALERT" } },
}
local ORDER = { "browserTitle", "cookies", "ticket" }

local CANDIDATES = { frame = { "HelpFrame" }, ticketFrame = { "TicketStatusFrame" },
  cookiesButton = { "BrowserSettingsTooltip.CookiesButton" }, ticketButton = { "HelpOpenWebTicketButton" } }

local TITLE = { only = { "HELP_FRAME_TITLE" } }
local COOKIES_TIP = { only = { "BROWSER_DELETE_COOKIES_TOOLTIP" } }
local TICKET_TIP = { only = { "TICKET_STATUS", "TICKET_STATUS_NMI", "GM_TICKET_HIGH_VOLUME", "GM_TICKET_UNAVAILABLE",
  "GM_TICKET_WAIT_TIME", "GM_RESPONSE_ALERT", "HELPFRAME_TICKET_CLICK_HELP" } }

local function get(key) return Compat.get(SURFACE, key) end

-- Shows the named labels (all of them when none is named). → the number of dictionary words found.
function HelpFrame.show(...)
  local keys = select("#", ...) > 0 and { ... } or ORDER
  local items = {}
  for _, key in ipairs(keys) do
    items[#items + 1] = { key, get("label." .. key), { only = LABELS[key][2] } }
  end
  return WFJ.Labels.showAll(SURFACE, items)
end

-- HookScript target (TicketStatusFrame's OnEvent).
function HelpFrame.onTicket() return HelpFrame.show("ticket") end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function HelpFrame.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(LABELS) do Compat.declare(SURFACE, "label." .. key, { l[1] }) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" or type(frame.SetTitle) ~= "function" then return false end
  hooked = true
  WFJ.Labels.title(SURFACE, frame, TITLE)
  local ticketFrame = get("ticketFrame")
  if type(ticketFrame) == "table" and type(ticketFrame.HookScript) == "function" then
    ticketFrame:HookScript("OnEvent", HelpFrame.onTicket)
  end
  if type(get("cookiesButton")) == "table" then WFJ.HelpTooltip.register(get("cookiesButton"), COOKIES_TIP) end
  if type(get("ticketButton")) == "table" then WFJ.HelpTooltip.register(get("ticketButton"), TICKET_TIP) end
  HelpFrame.show()
  return true
end
