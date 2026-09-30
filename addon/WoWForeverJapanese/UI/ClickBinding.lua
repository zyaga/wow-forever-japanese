-- UI/ClickBinding.lua: the Click Cast Bindings window on Forever (surface "clickbinding", area "ui",
-- ADR-016). Blizzard_ClickBindingUI is load-on-demand; ToggleClickBindingFrame (its [Bootstrap] file,
-- blizzard_clickbindingui_bootstrap.lua:7–12) is called by the /click command (blizzard_chatframebase/mainline/
-- slashcommandsoverrides.lua:361) and by the key bindings panel's Click Cast Bindings button
-- (blizzard_settingsdefinitions_frame/mainline/keybindingsoverrides.lua:45).
-- ClickBindingFrame (blizzard_clickbindingui.xml:147, PortraitFrameTemplate; children are parentKeys):
--   titles: ClickBindingFrameMixin:OnLoad SetTitle(CLICK_CAST_BINDINGS) (blizzard_clickbindingui.lua:597) and
--     ClickBindingTutorialMixin:OnLoad TutorialFrame:SetTitle(CLICK_CAST_ABOUT_HEADER) (:813), through Labels.title;
--   static labels (XML text=): SaveButton SAVE (xml:175), AddBindingButton ADD_BINDING (:181), ResetButton
--     RESET_TO_DEFAULT (:187), EnableMouseoverCastCheckbox.Label ENABLE_MOUSEOVER_CAST (:213),
--     MouseoverCastKeyDropdown.Label MOUSEOVER_CAST_KEY (:227), TutorialFrame.SummaryText CLICK_CAST_TITLE (:276),
--     .InfoText CLICK_CAST_INFO (:281), .AlternateText CLICK_CAST_ALTERNATE (:287);
--   the binding list (ClickBindingFrame.ScrollBox, pooled ClickBindingLineTemplate / ClickBindingHeaderTemplate rows;
--     ClickBindingLineMixin:Init lua:237–259, ClickBindingHeaderMixin:Init :279–282), walked from the ScrollBox's
--     initialized-frame callback, keyed by widget:
--       Name: a header word CLICK_BINDINGS_DEFAULTS_HEADER / _CUSTOMS_HEADER (:188–191), or
--         CLICK_BINDING_INTERACTION_TITLE ("%s (Default)") around CLICK_BINDING_TARGET_UNIT / _OPEN_MENU (:179–183),
--         or CLICK_BINDING_MACRO_TITLE ("%s (Macro)", :177) around a macro's name, kept as written, and
--         grey-wrapped when unbound (:199–211, the `wrapped` form). The same FontString holds a spell's name:
--         restricted (`only`), so a name is never matched;
--       BindingText: a mouse button word (ButtonStrings, :1–36: LEFT_ / RIGHT_ / MIDDLE_BUTTON_STRING,
--         BUTTON_4_STRING … BUTTON_31_STRING) when the binding has no modifier. With a modifier it is the composite
--         CLICK_BINDINGS_BINDING_TEXT_FORMAT ("%s-%s", :228): the modifier key names stay as written ("SHIFT"), the
--         button word is Japanese (ARGS modifiers / entry). The three prompts are colour-wrapped (:216–222;
--         the `wrapped` form);
--   tooltips (GameTooltip with the widget as owner): the checkbox's OPTION_TOOLTIP_ENABLE_MOUSEOVER_CAST (:830–833),
--     the two portraits' MACROS / PLAYERSPELLS_BUTTON (:311–325).
-- Never touched: TutorialFrame.ThrallName (THRALL_NAME, a name), spell and macro names, the modifier dropdown's
-- entries (UI/Menus). The two confirmations are StaticPopups (ADR-015 §5).
local _, WFJ = ...
local ClickBinding = {}
WFJ.ClickBinding = ClickBinding

local SURFACE = "clickbinding"
ClickBinding.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_ClickBindingUI"

local FRAME = "ClickBindingFrame"
local TUTORIAL = FRAME .. ".TutorialFrame"

ClickBinding.NEVER_TOUCH = { TUTORIAL .. ".ThrallName" }

-- Static labels: record key → { candidate, the one key it shows }.
local STATIC_LABELS = {
  save = { FRAME .. ".SaveButton", "SAVE" }, addBinding = { FRAME .. ".AddBindingButton", "ADD_BINDING" },
  reset = { FRAME .. ".ResetButton", "RESET_TO_DEFAULT" },
  mouseoverCast = { FRAME .. ".EnableMouseoverCastCheckbox.Label", "ENABLE_MOUSEOVER_CAST" },
  mouseoverKey = { FRAME .. ".MouseoverCastKeyDropdown.Label", "MOUSEOVER_CAST_KEY" },
  summary = { TUTORIAL .. ".SummaryText", "CLICK_CAST_TITLE" }, info = { TUTORIAL .. ".InfoText", "CLICK_CAST_INFO" },
  alternate = { TUTORIAL .. ".AlternateText", "CLICK_CAST_ALTERNATE" },
}
local STATIC_ORDER = {}
for key in pairs(STATIC_LABELS) do STATIC_ORDER[#STATIC_ORDER + 1] = key end
table.sort(STATIC_ORDER)

local CANDIDATES = {
  frame = { FRAME }, tutorial = { TUTORIAL }, list = { FRAME .. ".ScrollBox" }, scrollUtil = { "ScrollUtil" },
  checkbox = { FRAME .. ".EnableMouseoverCastCheckbox" }, spellsPortrait = { FRAME .. ".PlayerSpellsPortrait" },
  macrosPortrait = { FRAME .. ".MacrosPortrait" },
}

local TITLE = { only = { "CLICK_CAST_BINDINGS" } }
local TUTORIAL_TITLE = { only = { "CLICK_CAST_ABOUT_HEADER" } }
local ROW_NAME = { only = { "CLICK_BINDINGS_DEFAULTS_HEADER", "CLICK_BINDINGS_CUSTOMS_HEADER",
  "CLICK_BINDING_INTERACTION_TITLE", "CLICK_BINDING_MACRO_TITLE" } }
local BUTTON_KEYS = { "LEFT_BUTTON_STRING", "RIGHT_BUTTON_STRING", "MIDDLE_BUTTON_STRING" }
for n = 4, 31 do BUTTON_KEYS[#BUTTON_KEYS + 1] = "BUTTON_" .. n .. "_STRING" end -- Blizzard's own key names
BUTTON_KEYS[#BUTTON_KEYS + 1] = "CLICK_BINDINGS_BINDING_TEXT_FORMAT" -- a modifier and a button
for _, k in ipairs({ "CLICK_BINDINGS_NEW_EMPTY_PROMPT", "CLICK_BINDINGS_SET_BINDING_PROMPT",
  "CLICK_BINDINGS_UNBOUND_TEXT" }) do BUTTON_KEYS[#BUTTON_KEYS + 1] = k end
local ROW_BINDING = { only = BUTTON_KEYS }
local CHECKBOX_TOOLTIP = { only = { "OPTION_TOOLTIP_ENABLE_MOUSEOVER_CAST" } }
local SPELLS_TOOLTIP = { only = { "PLAYERSPELLS_BUTTON" } }
local MACROS_TOOLTIP = { only = { "MACROS" } }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(STATIC_LABELS) do Compat.declare(SURFACE, "static." .. key, { l[1] }) end
end

local nameKey = WFJ.Labels.keyer("row.name.") -- a pooled row's record keys (they follow the widget)
local bindingKey = WFJ.Labels.keyer("row.binding.")

-- The labels the client writes once at load, and both titles. → the number of dictionary words found.
function ClickBinding.showStatic()
  local items = {}
  for _, key in ipairs(STATIC_ORDER) do
    items[#items + 1] = { key, get("static." .. key), { only = { STATIC_LABELS[key][2] } } }
  end
  local n = WFJ.Labels.showAll(SURFACE, items)
  n = n + WFJ.Labels.title(SURFACE, get("frame"), TITLE)
  return n + WFJ.Labels.title(SURFACE, get("tutorial"), TUTORIAL_TITLE, "tutorialTitle")
end

-- One pooled list row after its initializer ran (ScrollUtil's initialized-frame callback: (owner, frame, elementData)
-- for a new row, (frame, elementData) for the iterateExisting pass). Returns nothing: ForEachFrame stops at the
-- first truthy return (see UI/Raid.onRow).
local function showRow(row)
  if type(row.Name) == "table" then WFJ.Labels.show(SURFACE, nameKey(row.Name), row.Name, nil, ROW_NAME) end
  if type(row.BindingText) == "table" then
    WFJ.Labels.show(SURFACE, bindingKey(row.BindingText), row.BindingText, nil, ROW_BINDING)
  end
end

-- The window also calls a row's Init directly (after a binding is set, a new slot is added or
-- the list re-validates, blizzard_clickbindingui.lua:472, 493, 501, 717), not only through the ScrollBox's
-- initializer; so the first time a row is seen its own Init is post-hooked too (once per pooled row).
local rowHooked = setmetatable({}, { __mode = "k" })

function ClickBinding.onRow(a, b)
  local row = a
  if a == ClickBinding then row = b end
  if type(row) ~= "table" then return end
  if not rowHooked[row] and type(row.Init) == "function" then
    rowHooked[row] = true
    hooksecurefunc(row, "Init", showRow)
  end
  showRow(row)
end

local hooked = false

-- Blizzard_ClickBindingUI's part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function ClickBinding.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if type(frame) ~= "table" then return false end
  WFJ.Labels.forbidNames(ClickBinding.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  ClickBinding.showStatic()
  if hooked then return false end
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", ClickBinding.showStatic) end
  local list, util = get("list"), get("scrollUtil")
  if type(list) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(list, ClickBinding.onRow, ClickBinding, true)
  end
  WFJ.HelpTooltip.register(get("checkbox"), CHECKBOX_TOOLTIP)
  WFJ.HelpTooltip.register(get("spellsPortrait"), SPELLS_TOOLTIP)
  WFJ.HelpTooltip.register(get("macrosPortrait"), MACROS_TOOLTIP)
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- was set up now; false while Blizzard_ClickBindingUI is not loaded or has no frame.
function ClickBinding.init()
  declare()
  local done = false
  WFJ.LoadOnDemand.when(ADDON, function() done = ClickBinding.setup() end)
  return done
end
