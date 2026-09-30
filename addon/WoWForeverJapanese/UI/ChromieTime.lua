-- UI/ChromieTime.lua: the Timewalking campaign window on Forever (surface "chromietime", area "ui", ADR-016).
-- Blizzard_ChromieTimeUI is load-on-demand; its bootstrap registers ChromieTimeFrame with the player-interaction
-- manager for Enum.PlayerInteractionType.ChromieTime (blizzard_chromietimeui/blizzard_chromietimeui_bootstrap.lua:
-- 3–17), so an NPC interaction loads and opens it. Whether any camelot NPC offers that interaction is an in-game
-- question (checklist). It may load before or after this module's init: waited for through WFJ.LoadOnDemand.when.
-- Static (XML text=): Title.Text CHROMIE_TIME_TITLE_TEXT (blizzard_chromietimeui.xml:105), SelectButton
--   CHROMIE_TIME_SELECT_EXAPANSION_BUTTON (xml:124).
-- Dynamic:
--   the preview card, CurrentlySelectedExpansionInfoFrame (xml:134–176): ResetSelection writes
--     CHROMIE_TIME_PREVIEW_CARD_DEFAULT_TITLE / _DESCRIPTION (lua:97–101); SetCurrentlySelectedExpansion writes the
--     chosen campaign's name and description (lua:90–95): a name and client-table text (ADR-042), so each widget is
--     restricted to its default key and the campaign's text stays English. Both are the card's own methods, hooked;
--   the campaign buttons, pooled in ChromieTimeFrame.ExpansionOptionsPool and filled by SetupExpansionButtons
--     (lua:41–51, the frame's own method, hooked): each RecommendLabel shows RECOMMENDED on Label and on its shadow
--     BGLabel (xml:37–41; blizzard_sharedxml/newfeaturelabel.lua:3–8); both are shown, so the shadow never spells
--     English behind the Japanese; keyed by widget. A button's hover is GameTooltip with CHROMIE_TIME_CAMPAIGN_COMPLETE
--     or _ALREADY_ON (lua:144–153): the button is a help-tooltip owner restricted to those two keys.
-- Never touched: a campaign button's Name (the campaign's name, lua:109).
local _, WFJ = ...
local ChromieTime = {}
WFJ.ChromieTime = ChromieTime

local SURFACE = "chromietime"
ChromieTime.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_ChromieTimeUI"

ChromieTime.NEVER_TOUCH = {}

local CARD = "ChromieTimeFrame.CurrentlySelectedExpansionInfoFrame"
local CANDIDATES = {
  frame = { "ChromieTimeFrame" }, title = { "ChromieTimeFrame.Title.Text" },
  select = { "ChromieTimeFrame.SelectButton" }, card = { CARD }, cardName = { CARD .. ".Name" },
  cardDescription = { CARD .. ".Description" },
}

local TITLE = { only = { "CHROMIE_TIME_TITLE_TEXT" } }
local SELECT = { only = { "CHROMIE_TIME_SELECT_EXAPANSION_BUTTON" } }
local CARD_NAME = { only = { "CHROMIE_TIME_PREVIEW_CARD_DEFAULT_TITLE" } }
local CARD_DESCRIPTION = { only = { "CHROMIE_TIME_PREVIEW_CARD_DEFAULT_DESCRIPTION" } }
local RECOMMENDED = { only = { "RECOMMENDED" } }
local HOVER = { only = { "CHROMIE_TIME_CAMPAIGN_COMPLETE", "CHROMIE_TIME_CAMPAIGN_ALREADY_ON" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

local labelKey = WFJ.Labels.keyer("recommended.") -- a campaign button's label: follows the widget

-- The window's fixed words and the preview card. hooksecurefunc target (card ResetSelection /
-- SetCurrentlySelectedExpansion) and HookScript target (OnShow). → the number of words found.
function ChromieTime.showStatic()
  return WFJ.Labels.showAll(SURFACE, {
    { "title", get("title"), TITLE }, { "select", get("select"), SELECT },
    { "cardName", get("cardName"), CARD_NAME }, { "cardDescription", get("cardDescription"), CARD_DESCRIPTION },
  })
end

-- One pooled campaign button. → the number of words found.
local function showButton(button)
  if type(button) ~= "table" then return 0 end
  WFJ.Labels.forbid(button.Name) -- the campaign's name
  WFJ.HelpTooltip.register(button, HOVER)
  local label, n = button.RecommendLabel, 0
  if type(label) == "table" then
    for _, fs in ipairs({ label.Label, label.BGLabel }) do
      if type(fs) == "table" then n = n + WFJ.Labels.show(SURFACE, labelKey(fs), fs, nil, RECOMMENDED) end
    end
  end
  return n
end

-- hooksecurefunc target (ChromieTimeFrame:SetupExpansionButtons): every active button. → the number of words found.
function ChromieTime.onButtons()
  local frame = get("frame")
  local pool = type(frame) == "table" and frame.ExpansionOptionsPool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  -- pairs over activeObjects, keyed by the button (blizzard_sharedxmlbase/pools.lua:150, 166–167)
  for button in pool:EnumerateActive() do n = n + showButton(button) end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- HookScript target (ChromieTimeFrame OnShow).
function ChromieTime.onShow()
  return ChromieTime.showStatic() + ChromieTime.onButtons()
end

local done = false

-- Blizzard_ChromieTimeUI's part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function ChromieTime.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if done or type(frame) ~= "table" then return false end
  done = true
  if type(frame.SetupExpansionButtons) == "function" then
    hooksecurefunc(frame, "SetupExpansionButtons", ChromieTime.onButtons)
  end
  local card = get("card")
  if type(card) == "table" then
    for _, method in ipairs({ "ResetSelection", "SetCurrentlySelectedExpansion" }) do
      if type(card[method]) == "function" then hooksecurefunc(card, method, ChromieTime.showStatic) end
    end
  end
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", ChromieTime.onShow) end
  ChromieTime.onShow()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when set up now;
-- false when the addon has not loaded yet (setup then runs on its ADDON_LOADED) or without the frame.
function ChromieTime.init()
  declare()
  local ready = false -- true only when the addon is loaded now and its window was set up
  WFJ.LoadOnDemand.when(ADDON, function() ready = ChromieTime.setup() end)
  return ready
end
