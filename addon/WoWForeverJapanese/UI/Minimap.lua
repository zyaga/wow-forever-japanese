-- UI/Minimap.lua: the minimap cluster's help tooltips on Forever (records on surface "help", area "ui",
-- ADR-016). camelot runs the mainline minimap (blizzard_minimap.toc: mainline/minimap.lua|xml, mainline/gametime.*,
-- mainline/addoncompartment.*, camelot/minimapconstants.lua, camelot/skin.lua, camelot/diel.lua). Nothing on the
-- cluster is a label of its own: MinimapZoneText is the zone NAME (minimap.lua:160) and stays English; every other
-- text is a GameTooltip the client writes in Lua, so this module only registers the owners with UI/HelpTooltip, each
-- restricted (`only`) to the keys its writer shows: every one of these tooltips can also carry a name.
-- Owners and writers [verified: Forever 1.60.1.69913]:
--   MinimapCluster.ZoneTextButton: MinimapZoneTextButtonMixin:OnEnter → Minimap_SetTooltip: AddLine(zone name),
--     AddLine(subzone name), AddLine(SANCTUARY_TERRITORY | FREE_FOR_ALL_TERRITORY | CONTESTED_TERRITORY |
--     COMBAT_ZONE | format(FACTION_CONTROLLED_TERRITORY, factionName)), AddLine(self.tooltipText) where tooltipText
--     is MicroButtonTooltipText(WORLDMAP_BUTTON, "TOGGLEWORLDMAP"), then Show (minimap.lua:84–103, 180–216). Zone,
--     subzone and faction names stay English: the two name lines never match the `only` set, and the faction inside
--     "(%s Territory)" is a verbatim `text` argument (Core/UIStrings ARGS);
--   MinimapCluster.Tracking.Button: MiniMapTrackingButtonMixin:OnEnter: SetText(TRACKING), AddLine(
--     MINIMAP_TRACKING_TOOLTIP_NONE), Show (minimap.lua:826–831). The tracking MENU (UNCHECK_ALL, HUNTER_TRACKING_TEXT,
--     TOWNSFOLK_TRACKING_TEXT, filter and spell names) is a menu popup (UI/Menus);
--   MinimapCluster.IndicatorFrame.MailFrame: MinimapMailFrameUpdate → FormatUnreadMailTooltip(GameTooltip, header,
--     senders): ONE SetText of header .. "\n" .. sender .. … (minimap.lua:485–490; blizzard_sharedxml/
--     formattingutil.lua:181–187). With no sender the line is exactly HAVE_MAIL; with senders it is HAVE_MAIL_FROM
--     followed by "\n<name>" lines: the headerLines form, the first line in Japanese, the names as written;
--   GameTimeFrame: GameTimeFrame_OnUpdate rewrites the tooltip on EVERY frame while it owns it: ClearLines,
--     AddLine(GAMETIME_TOOLTIP_CALENDAR_INVITES | the game time | " " | GAMETIME_TOOLTIP_TOGGLE_CALENDAR), Show
--     (gametime.lua:63–81). The Show post-hook walks it each time (two `only` lookups); the time line never matches;
--   AddonCompartmentFrame: its OnLoad-set OnEnter: GameTooltip_SetTitle(ADDONS), Show (addoncompartment.lua:12–16).
--     The compartment's menu lists addon names: never touched;
--   Minimap.ZoomIn / Minimap.ZoomOut: with UberTooltips on, GameTooltip_SetDefaultAnchor(GameTooltip, UIParent) +
--     SetText(ZOOM_IN | ZOOM_OUT) (minimap.lua:288–293, 312–317). UIParent owns every default-anchored tooltip and is
--     never registered: each button's OnEnter script is post-hooked (HookScript) and, when GameTooltip's owner is
--     UIParent right then, walked once with HelpTooltip.walkAs restricted to that button's key (the exhaustion
--     tick pattern, UI/MicroMenu.lua).
-- Not here: MinimapCluster.IndicatorFrame.CraftingOrderFrame (crafting orders: a profession name inside a |4 plural
--   composite), ExpansionLandingPageMinimapButton (garrison / class hall / covenant reports), the coordinates text
--   (numbers only), TimeManagerClockButton (blizzard_timemanager's surface).
local _, WFJ = ...
local Minimap = {}
WFJ.Minimap = Minimap

local SURFACE = "help" -- records live on UI/HelpTooltip's surface
Minimap.SURFACE = SURFACE
local DECLARE = "help.minimap" -- this module's Compat names
local Compat = WFJ.Compat

-- Nothing is written here except tooltip lines through UI/HelpTooltip; the zone name is protected outright.
Minimap.NEVER_TOUCH = { "MinimapZoneText" }

local CANDIDATES = {
  zone = { "MinimapCluster.ZoneTextButton" }, tracking = { "MinimapCluster.Tracking.Button" },
  mail = { "MinimapCluster.IndicatorFrame.MailFrame" }, clock = { "GameTimeFrame" },
  compartment = { "AddonCompartmentFrame" },
  zoomIn = { "Minimap.ZoomIn" }, zoomOut = { "Minimap.ZoomOut" },
  tooltip = { "GameTooltip" }, uiParent = { "UIParent" },
}

-- owner key → the keys its writer shows
Minimap.OWNERS = {
  zone = { "SANCTUARY_TERRITORY", "FREE_FOR_ALL_TERRITORY", "FACTION_CONTROLLED_TERRITORY", "CONTESTED_TERRITORY",
    "COMBAT_ZONE", "WORLDMAP_BUTTON" },
  tracking = { "TRACKING", "MINIMAP_TRACKING_TOOLTIP_NONE" },
  mail = { "HAVE_MAIL", "HAVE_MAIL_FROM" },
  clock = { "GAMETIME_TOOLTIP_CALENDAR_INVITES", "GAMETIME_TOOLTIP_TOGGLE_CALENDAR" },
  compartment = { "ADDONS" },
}
local OWNER_ORDER = { "zone", "tracking", "mail", "clock", "compartment" }
local ZOOM = { zoomIn = { "ZOOM_IN" }, zoomOut = { "ZOOM_OUT" } }

local function get(key) return Compat.get(DECLARE, key) end

-- Post-hook of a zoom button's OnEnter: the UIParent-anchored tooltip it just wrote, walked once. Any other owner (a
-- tooltip the button did not build: UberTooltips off) is left alone. → the number of dictionary lines
function Minimap.onZoomEnter(keys)
  local tt, parent = get("tooltip"), get("uiParent")
  if type(tt) ~= "table" or type(tt.GetOwner) ~= "function" or parent == nil or tt:GetOwner() ~= parent then
    return 0
  end
  return WFJ.HelpTooltip.walkAs(tt, { only = keys })
end

local hooked = false
local registered = 0

-- Called by Main after Compat.init and HelpTooltip.init. → the number of owners registered, or false when the
-- cluster has no ZoneTextButton. A missing owner is skipped, like UI/MicroMenu's.
function Minimap.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(DECLARE, key, names) end
  if hooked then return registered end
  if type(get("zone")) ~= "table" then return false end
  hooked = true
  local n = 0
  for _, key in ipairs(OWNER_ORDER) do
    local owner = get(key)
    if type(owner) == "table" then
      WFJ.HelpTooltip.register(owner, { only = Minimap.OWNERS[key] })
      n = n + 1
    end
  end
  for key, keys in pairs(ZOOM) do
    local button = get(key)
    if type(button) == "table" and type(button.HookScript) == "function" then
      button:HookScript("OnEnter", function() Minimap.onZoomEnter(keys) end)
      n = n + 1
    end
  end
  registered = n
  return n
end
