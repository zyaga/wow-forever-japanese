-- UI/Minimap.lua: the minimap cluster's help tooltips on Forever (records on surface "help", area "ui",
-- ADR-016). camelot loads the mainline minimap (blizzard_minimap.toc: mainline/minimap.lua|xml, mainline/gametime.*,
-- mainline/addoncompartment.lua) with camelot's own files after it: camelot/minimapconstants.lua, camelot/minimap.lua
-- (the frame and mask by the rotate setting, the header placement, the external event button's anchor: lua:31–93),
-- camelot/minimapinstancedifficulty.lua (no instance difficulty frame), the ZoneTextButton, Tracking button, mail
-- frame and indicator templates, GameTimeFrameTemplate, the AddonCompartmentFrame, and camelot/diel.lua. camelot's
-- .lua files restyle those buttons (atlas, highlight) and write no text; the tooltip writers are mainline mixin
-- methods. Nothing on the cluster is a label of its own: MinimapZoneText is the zone NAME, written by the global
-- Minimap_Update, which the client calls by name on every zone change (minimap.lua:169–170, 372, 409). It is never a
-- dictionary word; while names are on a post-hook of that function shows the place's Japanese (UI/NameLabels, on
-- this module's own surface: the help surface's records come and go with its tooltips). Every other text is a
-- GameTooltip the client writes in Lua, so this module only registers the owners with UI/HelpTooltip, each
-- restricted (`only`) to the keys its writer shows: every one of these tooltips can also carry a name.
-- Owners and writers [verified: Forever 1.60.1.70425]:
--   MinimapCluster.ZoneTextButton: MinimapZoneTextButtonMixin:OnEnter → Minimap_SetTooltip: AddLine(zone name),
--     AddLine(subzone name), AddLine(SANCTUARY_TERRITORY | FREE_FOR_ALL_TERRITORY | CONTESTED_TERRITORY |
--     COMBAT_ZONE | format(FACTION_CONTROLLED_TERRITORY, factionName)), AddLine(self.tooltipText) where tooltipText
--     is MicroButtonTooltipText(WORLDMAP_BUTTON, "TOGGLEWORLDMAP"), then Show (minimap.lua:85–108, 190–226). The
--     two name lines never match the `only` set, and the faction inside "(%s Territory)" is a verbatim `text`
--     argument (Core/UIStrings ARGS). While names are on, a post-hook of the global Minimap_SetTooltip (called by
--     name from OnEnter and on a zone change, :105, 187) shows the zone's and the subzone's Japanese on the lines it
--     wrote (UI/NameLabels, on the help surface under the walk's record keys, with the help tooltip's refit); a
--     line the walk holds as a dictionary word keeps its record;
--   MinimapCluster.Tracking.Button: MiniMapTrackingButtonMixin:OnEnter: SetText(TRACKING), AddLine(
--     MINIMAP_TRACKING_TOOLTIP_NONE), Show (minimap.lua:923–930). The tracking MENU (UNCHECK_ALL, HUNTER_TRACKING_TEXT,
--     TOWNSFOLK_TRACKING_TEXT, filter and spell names) is a menu popup (UI/Menus);
--   MinimapCluster.IndicatorFrame.MailFrame: MinimapMailFrameUpdate → FormatUnreadMailTooltip(GameTooltip, header,
--     senders): ONE SetText of header .. "\n" .. sender .. … (minimap.lua:539–544; blizzard_sharedxml/
--     formattingutil.lua:181–187). With no sender the line is exactly HAVE_MAIL; with senders it is HAVE_MAIL_FROM
--     followed by "\n<name>" lines: the headerLines form, the first line in Japanese, the names as written;
--   GameTimeFrame: GameTimeFrameMixin:OnUpdate rewrites the tooltip on EVERY frame while it owns it: ClearLines,
--     AddLine(GAMETIME_TOOLTIP_CALENDAR_INVITES | the game time | " " | GAMETIME_TOOLTIP_TOGGLE_CALENDAR), Show
--     (gametime.lua:99–116). The Show post-hook walks it each time (two `only` lookups); the time line never matches;
--   AddonCompartmentFrame: AddonCompartmentMixin:OnEnter: GameTooltip_SetTitle(ADDONS), Show
--     (addoncompartment.lua:60–66). The compartment's menu lists addon names: never touched;
--   MinimapBackdrop.ExternalEventURLButton (minimap.xml:274, ExternalEventURLMinimapButtonTemplate): shown only when
--     C_ExternalEventURL.CanShow() and HasURL() (shared/externaleventurlminimapbutton.lua:76–83); its OnEnter:
--     SetText(GAMEMENU_EXTERNALEVENT), Show (:93–97);
--   Minimap.ZoomIn / Minimap.ZoomOut: with UberTooltips on, GameTooltip_SetDefaultAnchor(GameTooltip, UIParent) +
--     SetText(ZOOM_IN | ZOOM_OUT) (minimap.lua:298–303, 322–327). UIParent owns every default-anchored tooltip and is
--     never registered: each button's OnEnter script is post-hooked (HookScript) and, when GameTooltip's owner is
--     UIParent right then, walked once with HelpTooltip.walkAs restricted to that button's key (the exhaustion
--     tick pattern, UI/MicroMenu.lua).
-- Not here: ExpansionLandingPageMinimapButton (garrison / class hall / covenant reports), the coordinates text
--   (numbers only), TimeManagerClockButton (blizzard_timemanager's surface). camelot's indicator frame holds only the
--   mail frame (camelot/minimapindicatorframetemplate.xml:11–17): no crafting order indicator.
local _, WFJ = ...
local Minimap = {}
WFJ.Minimap = Minimap

local SURFACE = "help" -- records live on UI/HelpTooltip's surface
Minimap.SURFACE = SURFACE
local DECLARE = "help.minimap" -- this module's Compat names
local Compat = WFJ.Compat

-- Nothing is written here except tooltip lines through UI/HelpTooltip and the zone name's Japanese; the zone name is
-- never read as a dictionary word.
Minimap.NEVER_TOUCH = { "MinimapZoneText" }
local ZONE = "minimap.zone" -- the zone name's own surface
Minimap.ZONE = ZONE

local CANDIDATES = {
  zone = { "MinimapCluster.ZoneTextButton" }, tracking = { "MinimapCluster.Tracking.Button" },
  mail = { "MinimapCluster.IndicatorFrame.MailFrame" }, clock = { "GameTimeFrame" },
  compartment = { "AddonCompartmentFrame" }, externalEvent = { "MinimapBackdrop.ExternalEventURLButton" },
  zoomIn = { "Minimap.ZoomIn" }, zoomOut = { "Minimap.ZoomOut" },
  tooltip = { "GameTooltip" }, uiParent = { "UIParent" },
  zoneText = { "MinimapZoneText" }, update = { "Minimap_Update" }, setTooltip = { "Minimap_SetTooltip" },
}

-- owner key → the keys its writer shows
Minimap.OWNERS = {
  zone = { "SANCTUARY_TERRITORY", "FREE_FOR_ALL_TERRITORY", "FACTION_CONTROLLED_TERRITORY", "CONTESTED_TERRITORY",
    "COMBAT_ZONE", "WORLDMAP_BUTTON" },
  tracking = { "TRACKING", "MINIMAP_TRACKING_TOOLTIP_NONE" },
  mail = { "HAVE_MAIL", "HAVE_MAIL_FROM" },
  clock = { "GAMETIME_TOOLTIP_CALENDAR_INVITES", "GAMETIME_TOOLTIP_TOGGLE_CALENDAR" },
  compartment = { "ADDONS" },
  externalEvent = { "GAMEMENU_EXTERNALEVENT" },
}
local OWNER_ORDER = { "zone", "tracking", "mail", "clock", "compartment", "externalEvent" }
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

-- hooksecurefunc target (Minimap_Update): the zone name the client just wrote. → 1 | 0
function Minimap.onUpdate()
  return WFJ.NameLabels.show(ZONE, "zone", get("zoneText"))
end

-- hooksecurefunc target (Minimap_SetTooltip): the zone's and the subzone's names on the lines it just wrote, while
-- the zone button owns the tooltip. → the number of names shown
function Minimap.onSetTooltip()
  local tt, owner = get("tooltip"), get("zone")
  if type(tt) ~= "table" or type(tt.GetOwner) ~= "function" or owner == nil or tt:GetOwner() ~= owner then return 0 end
  local n = 0
  for i = 1, math.min(2, type(tt.NumLines) == "function" and tt:NumLines() or 0) do
    n = n + WFJ.HelpTooltip.nameAt(tt, i)
  end
  return n
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
  if type(get("setTooltip")) == "function" then hooksecurefunc("Minimap_SetTooltip", Minimap.onSetTooltip) end
  if type(get("update")) == "function" then
    hooksecurefunc("Minimap_Update", Minimap.onUpdate)
    Minimap.onUpdate() -- the name the client wrote before this addon loaded
  end
  registered = n
  return n
end
