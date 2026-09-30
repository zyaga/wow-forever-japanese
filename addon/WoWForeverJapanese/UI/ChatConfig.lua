-- UI/ChatConfig.lua: the chat configuration window on Forever (surfaces "chatconfig" and "chatconfig.static", area
-- "ui", ADR-016). ChatConfigFrame is built at login by Blizzard_ChatFrame ([Family]\ChatConfigFrame.lua|xml,
-- mainline) and opened from a chat tab's menu (blizzard_chatframebase/mainline/floatingchatframe.lua:782), the
-- communities stream menu, /tts (blizzard_chatframe/shared/texttospeechframe.lua:526) and the ping settings. The
-- combat log's options are this window's "Combat" category, so they are this surface too.
-- Static labels (XML text= and OnLoad writes; shown when the window is shown):
--   the category list ChatConfigCategoryFrameButton1–7: CHAT, COMBAT, GLOBAL_CHANNELS, OTHER, SETTINGS (xml:383–420);
--   the filter buttons DELETE / ADD_FILTER / COPY_FILTER (xml:617–639); the combat tabs CombatConfigTab1–5, written
--     once in ChatConfigCombat_OnLoad from COMBAT_CONFIG_TABS (lua:1781–1807);
--   the combat panes' check buttons, each `_G[name.."Text"]:SetText(KEY)` in its OnLoad (xml:815–1471), the unnamed
--     MISCELLANEOUS / COLORIZE / FILTER_NAME labels (xml:749, 911, 1373), EXAMPLE_TEXT and HIGHLIGHTING titles;
--   the footer buttons CHAT_DEFAULTS, RESET_CHAT_WINDOW_POSITIONS, COMBATLOG_DEFAULTS, TEXT_TO_SPEECH_DEFAULTS, CANCEL,
--     OKAY (xml:1506–1571), TextToSpeechCharacterSpecificButton.Text (CHARACTER_SPECIFIC_SETTINGS inside a colour,
--     lua:2632–2636) and the text-to-speech message pane's SubTitle (xml:563).
-- Dynamic, each a global called by name, post-hooked:
--   ChatConfig_CreateCheckboxes(frame, table, template, title) (lua:819–892) → `<frame>Title` and every row's
--     `<frame>Checkbox<i>CheckText`; a row's text is a table's `text` or `_G[value.type]` (SAY, PARTY_LEADER, …);
--   ChatConfig_UpdateCheckboxes(frame) (lua:1018–1098) rewrites a row whose text is a function (Me / Custom Unit);
--   ChatConfig_CreateTieredCheckboxes (lua:894–975) → `<frame>Checkbox<i>Text` and the sub-rows `…_<k>Text`;
--   ChatConfig_CreateColorSwatches (lua:977–1016) → `<frame>Title`, `<frame>Swatch<i>Text`;
--   ChatConfigCategoryFrame_Refresh (lua:2182–2224) → ChatConfigFrame.Header.Text: TEXT_TO_SPEECH_CONFIG, or
--     CHATCONFIG_HEADER ("%s Config") around the chat window's own name, which is kept as written;
--   ChatConfigFrame.ChatTabManager:UpdateTabDisplay (lua:2391–2427) → the pooled window tabs: a tab shows a chat
--     window's name (never touched) except the text-to-speech tab, TEXT_TO_SPEECH (lua:2363–2370). Keyed by widget.
-- The rows are created on PLAYER_ENTERING_WORLD (lua:772–806), which may be before or after this module's init, so
-- every family is also walked when the window is shown. Widgets are found by the global names the client gives them
-- (`<frame>Checkbox<i>…`); records are keyed by widget, never by that index.
-- Tooltips: a check button's OnEnter is GameTooltip:SetText(self.tooltip) (xml:85–89), a sentence key
-- (*_COMBATLOG_TOOLTIP); the move-filter buttons use GameTooltip_SetTitle (xml:661–663, 684–686). Owners are
-- registered with WFJ.HelpTooltip.
-- Never touched: the channel rows of ChatConfigChannelSettingsLeft and ChatConfigTextToSpeechChannelSettingsLeft
-- ("1.General": channel names, lua:1717–1724, 1761–1768) and their overflow tooltips (lua:870–875), only those
-- frames' titles are shown; the filter list's buttons and the filter name EditBox (a filter's name is the player's,
-- lua:1840–1843, 1917); the example combat lines (lua:1277–1303).
local _, WFJ = ...
local ChatConfig = {}
WFJ.ChatConfig = ChatConfig

local SURFACE = "chatconfig"
ChatConfig.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
local Compat = WFJ.Compat

ChatConfig.NEVER_TOUCH = { "CombatConfigSettingsNameEditBox", "CombatConfigColorsExampleString1",
  "CombatConfigColorsExampleString2", "CombatConfigFormattingExampleString1", "CombatConfigFormattingExampleString2" }

-- Row families: the frames ChatConfig_Create* fills. `names` frames hold channel names: title only.
local ROW_FRAMES = { "ChatConfigChatSettingsLeft", "ChatConfigOtherSettingsCombat", "ChatConfigOtherSettingsPVP",
  "ChatConfigOtherSettingsSystem", "ChatConfigOtherSettingsCreature", "CombatConfigMessageSourcesDoneBy",
  "CombatConfigMessageSourcesDoneTo" }
local NAME_FRAMES = { "ChatConfigChannelSettingsLeft", "ChatConfigTextToSpeechChannelSettingsLeft" }
local TIERED_FRAMES = { "CombatConfigMessageTypesLeft", "CombatConfigMessageTypesRight",
  "CombatConfigMessageTypesMisc" }
local SWATCH_FRAMES = { "ChatConfigOtherSettingsAdditionalColors", "CombatConfigColorsUnitColors" }
local KIND = {}
for _, n in ipairs(ROW_FRAMES) do KIND[n] = "rows" end
for _, n in ipairs(NAME_FRAMES) do KIND[n] = "names" end
for _, n in ipairs(TIERED_FRAMES) do KIND[n] = "tiered" end
for _, n in ipairs(SWATCH_FRAMES) do KIND[n] = "swatches" end
-- The combat log's unit rows (done by, done to, unit colours: chatconfigframe.lua:330–432, 732–762) say
-- "Friends" for friendly units, which the friends list's "Friends" does not mean. That key owns its Japanese
-- (UIStrings.OWN), so these rows ask for the unit keys by name.
local UNIT_ROWS = { only = { "COMBATLOG_FILTER_STRING_ME", "COMBATLOG_FILTER_STRING_CUSTOM_UNIT",
  "COMBATLOG_FILTER_STRING_MY_PET", "COMBATLOG_FILTER_STRING_FRIENDLY_UNITS", "COMBATLOG_FILTER_STRING_HOSTILE_PLAYERS",
  "COMBATLOG_FILTER_STRING_HOSTILE_UNITS", "COMBATLOG_FILTER_STRING_NEUTRAL_UNITS",
  "COMBATLOG_FILTER_STRING_UNKNOWN_UNITS" } }
local UNIT_FRAMES = { CombatConfigMessageSourcesDoneBy = true, CombatConfigMessageSourcesDoneTo = true,
  CombatConfigColorsUnitColors = true }

-- A channel frame's title: the only text of those frames that is not a channel name.
local NAME_TITLE = { only = { "CHAT_CONFIG_CHANNEL_SETTINGS_TITLE_WITH_DRAG_INSTRUCTIONS", "CHANNELS" } }

-- Static labels by global name (a Button or a FontString). Each holds fixed dictionary words only.
local STATIC_LABELS = { "ChatConfigCategoryFrameButton1", "ChatConfigCategoryFrameButton2",
  "ChatConfigCategoryFrameButton3", "ChatConfigCategoryFrameButton4", "ChatConfigCategoryFrameButton5",
  "ChatConfigCategoryFrameButton6", "ChatConfigCategoryFrameButton7",
  "ChatConfigChatSettingsLeftColorHeader", "ChatConfigChannelSettingsLeftColorHeader",
  "ChatConfigCombatSettingsFiltersDeleteButton", "ChatConfigCombatSettingsFiltersAddFilterButton",
  "ChatConfigCombatSettingsFiltersCopyFilterButton",
  "CombatConfigTab1", "CombatConfigTab2", "CombatConfigTab3", "CombatConfigTab4", "CombatConfigTab5",
  "CombatConfigColorsExampleTitle", "CombatConfigFormattingExampleTitle", "CombatConfigColorsHighlightingTitle",
  "CombatConfigColorsHighlightingLineText", "CombatConfigColorsHighlightingAbilityText",
  "CombatConfigColorsHighlightingDamageText", "CombatConfigColorsHighlightingSchoolText",
  "CombatConfigColorsColorizeUnitNameCheckText", "CombatConfigColorsColorizeSpellNamesCheckText",
  "CombatConfigColorsColorizeSpellNamesSchoolColoringText", "CombatConfigColorsColorizeDamageNumberCheckText",
  "CombatConfigColorsColorizeDamageNumberSchoolColoringText", "CombatConfigColorsColorizeDamageSchoolCheckText",
  "CombatConfigColorsColorizeEntireLineCheckText", "CombatConfigColorsColorizeEntireLineBySourceText",
  "CombatConfigColorsColorizeEntireLineByTargetText",
  "CombatConfigFormattingShowTimeStampText", "CombatConfigFormattingShowBracesText",
  "CombatConfigFormattingUnitNamesText", "CombatConfigFormattingSpellNamesText",
  "CombatConfigFormattingItemNamesText", "CombatConfigFormattingFullTextText",
  "CombatConfigSettingsSaveButton", "CombatConfigSettingsShowQuickButtonText", "CombatConfigSettingsSoloText",
  "CombatConfigSettingsPartyText", "CombatConfigSettingsRaidText",
  "ChatConfigFrameDefaultButton", "ChatConfigFrameRedockButton", "CombatLogDefaultButton",
  "TextToSpeechDefaultButton", "TextToSpeechCharacterSpecificButton.Text", "ChatConfigFrameCancelButton",
  "ChatConfigFrameOkayButton", "ChatConfigTextToSpeechMessageSettings.SubTitle" }
-- Unnamed label regions: { owner, key }.
local REGIONS = { { "CombatConfigMessageTypesMisc", "MISCELLANEOUS" },
  { "CombatConfigColorsColorizeUnitName", "COLORIZE" }, { "CombatConfigSettingsNameEditBox", "FILTER_NAME" } }
-- Check buttons whose tooltip the XML sets in OnLoad, and the two move-filter buttons: help-tooltip owners.
local TOOLTIP_OWNERS = { "CombatConfigColorsHighlightingLine", "CombatConfigColorsHighlightingAbility",
  "CombatConfigColorsHighlightingDamage", "CombatConfigColorsHighlightingSchool",
  "CombatConfigColorsColorizeUnitNameCheck", "CombatConfigColorsColorizeSpellNamesCheck",
  "CombatConfigColorsColorizeSpellNamesSchoolColoring", "CombatConfigColorsColorizeDamageNumberCheck",
  "CombatConfigColorsColorizeDamageNumberSchoolColoring", "CombatConfigColorsColorizeDamageSchoolCheck",
  "CombatConfigColorsColorizeEntireLineCheck", "CombatConfigColorsColorizeEntireLineBySource",
  "CombatConfigColorsColorizeEntireLineByTarget", "CombatConfigFormattingShowTimeStamp",
  "CombatConfigFormattingShowBraces", "CombatConfigFormattingUnitNames", "CombatConfigFormattingSpellNames",
  "CombatConfigFormattingItemNames", "CombatConfigFormattingFullText", "CombatConfigSettingsShowQuickButton",
  "ChatConfigMoveFilterUpButton", "ChatConfigMoveFilterDownButton", "TextToSpeechCharacterSpecificButton" }

local CANDIDATES = {
  frame = { "ChatConfigFrame" }, tabManager = { "ChatConfigFrame.ChatTabManager" },
  header = { "ChatConfigFrame.Header.Text" },
  createCheckboxes = { "ChatConfig_CreateCheckboxes" }, updateCheckboxes = { "ChatConfig_UpdateCheckboxes" },
  createTiered = { "ChatConfig_CreateTieredCheckboxes" }, createSwatches = { "ChatConfig_CreateColorSwatches" },
  refresh = { "ChatConfigCategoryFrame_Refresh" },
}

local HEADER = { only = { "CHATCONFIG_HEADER", "TEXT_TO_SPEECH_CONFIG" } }
local WINDOW_TAB = { only = { "TEXT_TO_SPEECH" } } -- every other tab is a chat window's name

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

-- A widget by global name or dotted path ("Frame.Child.Text", which Compat walks). → table | nil
local function widget(path)
  local w = Compat.resolve(path)
  return type(w) == "table" and w or nil
end

local labelKey = WFJ.Labels.keyer("row.") -- a row label's record key: follows the widget
local tabKey = WFJ.Labels.keyer("windowTab.")

local function show(w, opts)
  if type(w) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, labelKey(w), w, nil, opts)
end

local function owner(w)
  -- no `only` on purpose: these owners' tooltips are Blizzard's check-button and filter sentences, never a name
  if type(w) == "table" then WFJ.HelpTooltip.register(w) end
end

-- One family's title and rows. → the number of dictionary words found.
local function walk(name)
  local kind = KIND[name]
  if not kind then return 0 end
  if kind == "names" then return show(widget(name .. "Title"), NAME_TITLE) end
  local n = kind ~= "tiered" and show(widget(name .. "Title")) or 0
  local stem = name .. (kind == "swatches" and "Swatch" or "Checkbox")
  local rowOpts = UNIT_FRAMES[name] and UNIT_ROWS or nil
  local i = 1
  while widget(stem .. i) do
    local row = stem .. i
    if kind == "rows" then
      n = n + show(widget(row .. "CheckText"), rowOpts)
      owner(widget(row .. "Check"))
    else
      n = n + show(widget(row .. "Text"), rowOpts)
    end
    if kind == "tiered" then
      owner(widget(row))
      local k = 1
      while widget(row .. "_" .. k) do
        n = n + show(widget(row .. "_" .. k .. "Text"))
        owner(widget(row .. "_" .. k))
        k = k + 1
      end
    end
    i = i + 1
  end
  return n
end

-- hooksecurefunc target (ChatConfig_CreateCheckboxes / _UpdateCheckboxes / _CreateTieredCheckboxes /
-- _CreateColorSwatches): the family the client just wrote. → the number of dictionary words found.
function ChatConfig.onFamily(frame)
  if type(frame) ~= "table" or type(frame.GetName) ~= "function" then return 0 end
  local ok, name = pcall(frame.GetName, frame)
  if not ok or type(name) ~= "string" then return 0 end
  local n = walk(name)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (ChatConfigCategoryFrame_Refresh). → 1 | 0
function ChatConfig.onHeader()
  return WFJ.Labels.show(SURFACE, "header", get("header"), nil, HEADER)
end

-- hooksecurefunc target (ChatTabManager:UpdateTabDisplay). → the number of dictionary words found.
function ChatConfig.onWindowTabs()
  local manager = get("tabManager")
  local pool = type(manager) == "table" and manager.tabPool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  for tab in pool:EnumerateActive() do
    if type(tab) == "table" then n = n + WFJ.Labels.show(SURFACE, tabKey(tab), tab, nil, WINDOW_TAB) end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The labels the client writes once. → the number of dictionary words found.
function ChatConfig.showStatic()
  local items = {}
  for _, path in ipairs(STATIC_LABELS) do items[#items + 1] = { path, widget(path) } end
  for _, r in ipairs(REGIONS) do
    items[#items + 1] = { r[1] .. "." .. r[2], WFJ.Labels.region(widget(r[1]), r[2]), { only = { r[2] } } }
  end
  return WFJ.Labels.showAll(STATIC, items)
end

-- HookScript target (ChatConfigFrame OnShow): everything, whatever ran before this module's init.
function ChatConfig.onShow()
  local n = ChatConfig.showStatic()
  for name in pairs(KIND) do n = n + walk(name) end
  for _, path in ipairs(TOOLTIP_OWNERS) do owner(widget(path)) end
  n = n + ChatConfig.onHeader() + ChatConfig.onWindowTabs()
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function ChatConfig.init()
  declare()
  local frame, manager = get("frame"), get("tabManager")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  for _, key in ipairs({ "createCheckboxes", "updateCheckboxes", "createTiered", "createSwatches" }) do
    if type(get(key)) == "function" then hooksecurefunc(CANDIDATES[key][1], ChatConfig.onFamily) end
  end
  if type(get("refresh")) == "function" then hooksecurefunc(CANDIDATES.refresh[1], ChatConfig.onHeader) end
  if type(manager) == "table" and type(manager.UpdateTabDisplay) == "function" then
    hooksecurefunc(manager, "UpdateTabDisplay", ChatConfig.onWindowTabs)
  end
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", ChatConfig.onShow) end
  ChatConfig.onShow()
  return true
end
