-- UI/PlayerChoice.lua: the "make a choice" window on Forever (surface "playerchoice", area "ui", ADR-016).
-- Load-on-demand Blizzard_PlayerChoice; its [Bootstrap] file (blizzard_playerchoice_bootstrap.lua:1–47) runs at
-- login and PLAYER_CHOICE_UPDATE calls ShowPendingPlayerChoiceResponseUI (blizzard_game/mainline/
-- eventimplementation.lua:637–639, :777) → PlayerChoice_LoadUI → PlayerChoiceFrame:TryShow and the toggle buttons.
-- Nearly everything the window shows is the choice's own data from the server (question, option headers, texts,
-- button labels, rewards): not GlobalStrings, never matched here. The client's own words:
--   PlayerChoiceFrame.GridNoSelectionHeader PLAYER_CHOICE_GRID_HEADER and GridNoSelectionDescription
--     PLAYER_CHOICE_GRID_DESC, written once by SetupGridFrames at OnLoad (blizzard_playerchoice.lua:25–29) and shown
--     only for a grid choice (:339–340): shown at setup and on each OnShow;
--   the toggle button (Generic / Cypher / Torghast PlayerChoiceToggleButton, blizzard_playerchoicetogglebutton.xml:
--     30, 58, 92): PlayerChoiceToggleButtonMixin:UpdateButtonState writes Text = HIDE while the window is shown,
--     else the choice's pendingChoiceText (server text, `only` keeps it English) (:48–77). Called as
--     button:UpdateButtonState() (:30; blizzard_playerchoice.lua:285; bootstrap :35; timer :9): post-hooked on each
--     button instance.
-- playerChoicePrefix (ADR-038): a power choice's option text is GetRarityDescriptionString() ..
--   optionInfo.description (blizzard_playerchoicepowerchoicetemplate.lua:205–229; the generic template's override,
--   blizzard_playerchoicegenericpowerchoiceoptiontemplate.lua:35–45): PLAYER_CHOICE_QUALITY_STRING_* is
--   "|cAARRGGBB<word>|r|n|n" and is shown in Japanese; the server's description is kept as written. OptionText is a
--   Frame whose SetText writes a SimpleHTML (blizzard_playerchoiceoptionbase.lua:298–328, xml:70–93), which has no
--   GetText: an adapter gives Render the text of record (the English the client just wrote, or ours), writes through
--   OptionText:SetText, and uses the HTML's "P" font [unverified: GetFont/SetFont("P", …) on that SimpleHTML; in-game
--   check]. SetupOptionText is post-hooked on both mixin tables (frames created from them later copy the hook).
-- Never touched: the options, their buttons and rewards (server data; REWARD_REPUTATION_WITH_AMOUNT wraps a faction
-- name), the confirmation StaticPopups (ADR-015 §5).
local _, WFJ = ...
local PlayerChoice = {}
WFJ.PlayerChoice = PlayerChoice

local SURFACE = "playerchoice"
PlayerChoice.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_PlayerChoice"

PlayerChoice.NEVER_TOUCH = {}

local TOGGLES = { "GenericPlayerChoiceToggleButton", "CypherPlayerChoiceToggleButton",
  "TorghastPlayerChoiceToggleButton" }
local CANDIDATES = { frame = { "PlayerChoiceFrame" }, header = { "PlayerChoiceFrame.GridNoSelectionHeader" },
  description = { "PlayerChoiceFrame.GridNoSelectionDescription" } }
for _, name in ipairs(TOGGLES) do CANDIDATES[name] = { name } end

local HEADER = { only = { "PLAYER_CHOICE_GRID_HEADER" } }
local DESCRIPTION = { only = { "PLAYER_CHOICE_GRID_DESC" } }
local HIDE = { only = { "HIDE" } }
local QUALITY = { "PLAYER_CHOICE_QUALITY_STRING_COMMON", "PLAYER_CHOICE_QUALITY_STRING_UNCOMMON",
  "PLAYER_CHOICE_QUALITY_STRING_RARE", "PLAYER_CHOICE_QUALITY_STRING_EPIC" }
local MIXINS = { "PlayerChoicePowerChoiceTemplateMixin", "PlayerChoiceGenericPowerChoiceOptionTemplateMixin" }
for _, name in ipairs(MIXINS) do CANDIDATES[name] = { name } end
local OPTIONS = SURFACE .. ".options"

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

-- The grid's two static labels. → the number of dictionary words found.
function PlayerChoice.showGrid()
  return WFJ.Labels.showAll(SURFACE, { { "header", get("header"), HEADER },
    { "description", get("description"), DESCRIPTION } })
end

-- One toggle button's label (after its UpdateButtonState). → 1 | 0
function PlayerChoice.showToggle(name)
  local button = get(name)
  if type(button) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, name, button.Text, nil, HIDE)
end

-- An OptionText as a FontString (GetText / SetText / GetFont / SetFont), one per widget (weak).
local adapters = setmetatable({}, { __mode = "k" })
local function adapter(optionText)
  local a = adapters[optionText]
  if a then return a end
  a = { logical = nil }
  function a.GetText() return a.logical end
  function a.SetText(_, text)
    a.logical = text
    optionText:SetText(text)
  end
  local function object() return optionText.textObject end
  function a.GetFont()
    local o = object()
    if type(o) ~= "table" or type(o.GetFont) ~= "function" then return nil end
    if optionText.useHTML then return o:GetFont("P") end
    return o:GetFont()
  end
  function a.SetFont(_, path, size, flags)
    local o = object()
    if type(o) ~= "table" or type(o.SetFont) ~= "function" then return false end
    if optionText.useHTML then
      o:SetFont("P", path, size, flags)
      return (a.GetFont()) == path
    end
    return o:SetFont(path, size, flags)
  end
  adapters[optionText] = a
  return a
end

local optionKey = WFJ.Labels.keyer("option.")

-- After an option's SetupOptionText (self = the option frame). → 1 | 0
function PlayerChoice.onOptionText(option)
  if type(option) ~= "table" or type(option.OptionText) ~= "table" or type(option.OptionText.SetText) ~= "function"
      or type(option.optionInfo) ~= "table" or type(option.GetRarityDescriptionString) ~= "function" then return 0 end
  local ok, rarity = pcall(option.GetRarityDescriptionString, option)
  local description = option.optionInfo.description
  if not ok or type(rarity) ~= "string" or type(description) ~= "string" then return 0 end
  local a = adapter(option.OptionText)
  a.logical = rarity .. description -- what the client just wrote
  local part = rarity ~= "" and WFJ.Labels.part(rarity, QUALITY) or nil
  return WFJ.Labels.showArgs(OPTIONS, optionKey(option.OptionText), a, part and part.key,
    part and { form = "seq", parts = { part, description } })
end

local hooked = false

-- The Blizzard_PlayerChoice part: runs once that addon is loaded (now, or on its ADDON_LOADED). → true when hooked
function PlayerChoice.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if hooked or type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  hooked = true
  frame:HookScript("OnShow", PlayerChoice.showGrid)
  frame:HookScript("OnHide", function() WFJ.Render.release(OPTIONS) end)
  for _, name in ipairs(MIXINS) do
    local mixin = get(name)
    if type(mixin) == "table" and type(mixin.SetupOptionText) == "function" then
      hooksecurefunc(mixin, "SetupOptionText", PlayerChoice.onOptionText)
    end
  end
  PlayerChoice.showGrid()
  for _, name in ipairs(TOGGLES) do
    local button = get(name)
    if type(button) == "table" and type(button.UpdateButtonState) == "function" then
      hooksecurefunc(button, "UpdateButtonState", function() PlayerChoice.showToggle(name) end)
      PlayerChoice.showToggle(name)
    end
  end
  return true
end

-- Called by Main after Compat.init and LoadOnDemand.init. → true when the window was set up now; false
-- while it waits for the addon and on a second call.
function PlayerChoice.init()
  declare()
  local result = false
  WFJ.LoadOnDemand.when(ADDON, function() result = PlayerChoice.setup() end)
  return result
end
