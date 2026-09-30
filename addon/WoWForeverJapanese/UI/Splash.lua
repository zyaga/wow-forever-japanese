-- UI/Splash.lua: the "What's New" splash window on Forever (surface "splash", area "ui", ADR-016).
-- SplashFrame is built at login by Blizzard_SplashFrame ([Family]\SplashFrame.lua|xml, mainline). It
-- opens on OPEN_SPLASH_SCREEN
-- (blizzard_splashframe/mainline/splashframe.lua:11, 39–40), sent at login for a new season, and by the game menu's
-- What's New button (blizzard_gamemenu/shared/gamemenuframe.lua:233–235, when GameRulesUtil.ShouldShowSplashScreen()).
-- Whether camelot ever sends it is an in-game question (checklist).
-- Static (XML text=): BottomCloseButton CLOSE (splashframe.xml:70), RightFeature.StartQuestButton.Text
--   SPLASH_START_QUEST_NOW (xml:147).
-- Dynamic: SplashFrame:SetupFrame (the frame's own method, called as self:SetupFrame(…), lua:40, 50–86) → Header:
--   SPLASH_BASE_HEADER or SPLASH_NEW_HEADER_SEASON (lua:64–68).
-- Never touched: Label and the three features' Title / Description: the splash screen's own text, client-table data
-- handed over in screenInfo (lua:70–73, 156–158, 190–192).
local _, WFJ = ...
local Splash = {}
WFJ.Splash = Splash

local SURFACE = "splash"
Splash.SURFACE = SURFACE
local Compat = WFJ.Compat

local FEATURES = { "TopLeftFeature", "BottomLeftFeature", "RightFeature" }
Splash.NEVER_TOUCH = { "SplashFrame.Label" }
for _, f in ipairs(FEATURES) do
  Splash.NEVER_TOUCH[#Splash.NEVER_TOUCH + 1] = "SplashFrame." .. f .. ".Title"
  Splash.NEVER_TOUCH[#Splash.NEVER_TOUCH + 1] = "SplashFrame." .. f .. ".Description"
end

local CANDIDATES = {
  frame = { "SplashFrame" }, header = { "SplashFrame.Header" }, close = { "SplashFrame.BottomCloseButton" },
  startQuest = { "SplashFrame.RightFeature.StartQuestButton.Text" },
}

local HEADER = { only = { "SPLASH_BASE_HEADER", "SPLASH_NEW_HEADER_SEASON" } }
local CLOSE = { only = { "CLOSE" } }
local START_QUEST = { only = { "SPLASH_START_QUEST_NOW" } }

local function get(key) return Compat.get(SURFACE, key) end

-- hooksecurefunc target (SplashFrame:SetupFrame) and HookScript target (OnShow). → the number of words found.
function Splash.onSetup()
  local show = WFJ.Labels.show
  local n = show(SURFACE, "header", get("header"), nil, HEADER) + show(SURFACE, "close", get("close"), nil, CLOSE)
    + show(SURFACE, "startQuest", get("startQuest"), nil, START_QUEST)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Splash.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end -- no SplashFrame
  hooked = true
  if type(frame.SetupFrame) == "function" then hooksecurefunc(frame, "SetupFrame", Splash.onSetup) end
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", Splash.onSetup) end
  Splash.onSetup()
  return true
end
