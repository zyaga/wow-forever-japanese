-- UI/StreamingIcon.lua: the "game data is downloading" icon's tooltip on Forever (surface "streamingicon" via
-- UI/HelpTooltip, area "ui", ADR-016). Blizzard_FrameXML loads mainline/streamingframe.xml|lua at login on
-- `camelot`. StreamingIcon registers STREAMING_ICON itself (streamingframe.lua:4–7) and sets self.tooltip to
-- STATUS_ADDL_FILE_TOOLTIP / STATUS_MAJOR_FILE_TOOLTIP / STATUS_CORE_FILE_TOOLTIP by download status (:20–46); its
-- OnEnter shows that one line with GameTooltip:SetText (streamingframe.xml:50–55). The icon is registered as a tooltip
-- owner with UI/HelpTooltip, restricted to the three keys.
local _, WFJ = ...
local StreamingIcon = {}
WFJ.StreamingIcon = StreamingIcon

local SURFACE = "streamingicon"
StreamingIcon.SURFACE = SURFACE
local Compat = WFJ.Compat

StreamingIcon.NEVER_TOUCH = {}

local TOOLTIP = { only = { "STATUS_ADDL_FILE_TOOLTIP", "STATUS_MAJOR_FILE_TOOLTIP", "STATUS_CORE_FILE_TOOLTIP" } }

local done = false

-- Called by Main after Compat.init and HelpTooltip.init. → true when the icon was registered now; false on
-- a second call.
function StreamingIcon.init()
  Compat.declare(SURFACE, "icon", { "StreamingIcon" })
  if done then return false end
  local icon = Compat.get(SURFACE, "icon")
  if type(icon) ~= "table" then return false end
  done = true
  WFJ.HelpTooltip.register(icon, TOOLTIP)
  return true
end
