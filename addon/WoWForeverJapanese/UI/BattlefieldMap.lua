-- UI/BattlefieldMap.lua: the zone map on Forever (surface "battlefieldmap", area "ui", ADR-016): the small
-- movable map of the load-on-demand Blizzard_BattlefieldMap (blizzard_battlefieldmap.toc). Entry points: the key
-- binding TOGGLEBATTLEFIELDMINIMAP (blizzard_framexml/bindings_camelot.xml:1239–1241) and the PvP queue button's
-- menu (blizzard_queuestatusframe/mainline/queuestatusframe.lua:1348–1352) call ToggleBattlefieldMap →
-- BattlefieldMap_ToggleUI, which loads the addon (mainline/blizzard_battlefieldmap_bootstrap.lua:3–5;
-- blizzard_battlefieldmap_bootstrap.lua:3–11). Set up through WFJ.LoadOnDemand.when (either load order).
-- Its one fixed word is the drag tab's label: BattlefieldMapTab's ButtonText, text="BATTLEFIELD_MINIMAP" ("Zone Map",
-- mainline/blizzard_battlefieldmap.xml:3, 41), written once by the XML: a static label restricted to that key. The
-- tab's right-click menu (SHOW_BATTLEFIELDMINIMAP_PLAYERS, LOCK_BATTLEFIELDMINIMAP, BATTLEFIELDMINIMAP_OPACITY_LABEL,
-- mainline/blizzard_battlefieldmap.lua:48–80) is a menu popup (UI/Menus). Pin tooltips on the map are UI/MapPins'.
local _, WFJ = ...
local BattlefieldMap = {}
WFJ.BattlefieldMap = BattlefieldMap

local SURFACE = "battlefieldmap"
BattlefieldMap.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_BattlefieldMap"

BattlefieldMap.NEVER_TOUCH = {} -- the window has no name widget

local CANDIDATES = { tab = { "BattlefieldMapTab" } }
local TAB = { only = { "BATTLEFIELD_MINIMAP" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

-- The drag tab's label (static: never released). → 1 | 0
function BattlefieldMap.showTab()
  return WFJ.Labels.show(SURFACE, "tab", get("tab"), nil, TAB)
end

local done = false

-- Blizzard_BattlefieldMap's part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function BattlefieldMap.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  if done or type(get("tab")) ~= "table" then return false end
  done = true
  BattlefieldMap.showTab()
  return true
end

-- Called by Main after Compat.init, ButtonText.init and LoadOnDemand.init.
function BattlefieldMap.init()
  declare()
  return WFJ.LoadOnDemand.when(ADDON, BattlefieldMap.setup)
end
