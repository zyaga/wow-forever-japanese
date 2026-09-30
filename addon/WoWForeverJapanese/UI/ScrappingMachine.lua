-- UI/ScrappingMachine.lua: the scrapping machine window on Forever (surface "scrappingmachine.static", area "ui",
-- ADR-016 / ADR-029). Load-on-demand Blizzard_ScrappingMachineUI; its [Bootstrap] file registers
-- Enum.PlayerInteractionType.ScrappingMachine at login (blizzard_scrappingmachineui_bootstrap.lua:7–17), so the window
-- opens when a game object sends that interaction. Set up through WFJ.LoadOnDemand.when.
-- The window's only fixed word is ScrappingMachineFrame.ScrapButton SCRAP_BUTTON (XML text=,
-- blizzard_scrappingmachineui.xml:72), written once at load: a static label, never released.
-- Never touched: the title (SetTitle(SCRAPPING_MACHINE_TITLE) at load ("Shred-Master Mk1", a machine's name) and
-- SetTitle(C_ScrappingMachineUI.GetScrappingMachineName()) on every show (blizzard_scrappingmachineui.lua:51, 65):
-- names stay in English), and the slotted items' tooltips (item tooltips, UI/Tooltip's).
local _, WFJ = ...
local ScrappingMachine = {}
WFJ.ScrappingMachine = ScrappingMachine

local SURFACE = "scrappingmachine"
ScrappingMachine.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
local Compat = WFJ.Compat
local ADDON = "Blizzard_ScrappingMachineUI"

ScrappingMachine.NEVER_TOUCH = { "ScrappingMachineFrame.TitleContainer.TitleText" }

local CANDIDATES = { frame = { "ScrappingMachineFrame" }, button = { "ScrappingMachineFrame.ScrapButton" } }
local BUTTON = { only = { "SCRAP_BUTTON" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

-- The button the client labels once at load. → 1 | 0
function ScrappingMachine.showStatic()
  return WFJ.Labels.showAll(STATIC, { { "scrap", get("button"), BUTTON } })
end

local hooked = false

-- The Blizzard_ScrappingMachineUI part: runs once that addon is loaded (now, or on its ADDON_LOADED). → true when
-- hooked
function ScrappingMachine.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if type(frame) ~= "table" then return false end
  WFJ.Labels.forbidNames(ScrappingMachine.NEVER_TOUCH)
  ScrappingMachine.showStatic()
  if hooked then return false end
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", ScrappingMachine.showStatic) end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- was set up now; false while it waits for the addon.
function ScrappingMachine.init()
  declare()
  local result = false
  WFJ.LoadOnDemand.when(ADDON, function() result = ScrappingMachine.setup() end)
  return result
end
