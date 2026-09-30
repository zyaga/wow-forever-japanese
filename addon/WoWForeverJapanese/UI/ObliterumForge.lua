-- UI/ObliterumForge.lua: the Obliterum Forge window on Forever (surface "obliterumforge.static", area "ui",
-- ADR-016 / ADR-029). Load-on-demand Blizzard_ObliterumUI; its [Bootstrap] file registers
-- Enum.PlayerInteractionType.ObliterumForge at login (blizzard_obliterumui_bootstrap.lua:7–17), so the window opens
-- when a game object sends that interaction. Set up through WFJ.LoadOnDemand.when.
-- The window's only fixed word is ObliterumForgeFrame.ObliterateButton OBLITERATE_BUTTON (XML text=,
-- blizzard_obliterumui.xml:60), written once at load: a static label, never released.
-- Never touched: the title, self:SetTitle(OBLITERUM_FORGE_TITLE) (blizzard_obliterumui.lua:13), the forge's name
-- (names stay in English), and the slotted item's tooltip (an item tooltip, UI/Tooltip's).
local _, WFJ = ...
local ObliterumForge = {}
WFJ.ObliterumForge = ObliterumForge

local SURFACE = "obliterumforge"
ObliterumForge.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
local Compat = WFJ.Compat
local ADDON = "Blizzard_ObliterumUI"

ObliterumForge.NEVER_TOUCH = { "ObliterumForgeFrame.TitleContainer.TitleText" }

local CANDIDATES = { frame = { "ObliterumForgeFrame" }, button = { "ObliterumForgeFrame.ObliterateButton" } }
local BUTTON = { only = { "OBLITERATE_BUTTON" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

-- The button the client labels once at load. → 1 | 0
function ObliterumForge.showStatic()
  return WFJ.Labels.showAll(STATIC, { { "obliterate", get("button"), BUTTON } })
end

local hooked = false

-- The Blizzard_ObliterumUI part: runs once that addon is loaded (now, or on its ADDON_LOADED). → true when hooked
function ObliterumForge.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if type(frame) ~= "table" then return false end
  WFJ.Labels.forbidNames(ObliterumForge.NEVER_TOUCH)
  ObliterumForge.showStatic()
  if hooked then return false end
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", ObliterumForge.showStatic) end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- was set up now; false while it waits for the addon.
function ObliterumForge.init()
  declare()
  local result = false
  WFJ.LoadOnDemand.when(ADDON, function() result = ObliterumForge.setup() end)
  return result
end
