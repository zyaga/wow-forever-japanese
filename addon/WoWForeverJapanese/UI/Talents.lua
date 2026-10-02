-- UI/Talents.lua: the talent window's fixed words (surface "talents", area "ui", ADR-016, ADR-029).
-- The talent tree is PlayerSpellsFrame.TalentsFrame in the load-on-demand Blizzard_PlayerSpells
-- (camelot/classtalents/blizzard_classtalentsframe.xml:153), set up through WFJ.LoadOnDemand.when; every child is a
-- parentKey (dotted Compat candidates).
-- - The window title is written by PlayerSpellsFrame:UpdateFrameTitle, shared with the spellbook tab: UI/SpellBook
--   owns that one hook (TALENTS / TALENTS_INSPECT_FORMAT on surface "playerspells").
-- - Static XML text, never rewritten: ApplyButton TALENT_FRAME_APPLY_BUTTON_TEXT (xml:438), ActiveSpec.ActivateButton
--   TALENT_SPEC_ACTIVATE (:111), ActiveSpec.ActiveLabel TALENT_SPEC_ACTIVE (:102), ClassCurrencyDisplay.UnspentLabel
--   UNSPENT_POINTS (:13; the number is a separate FontString, classtalentsframe.lua:18–26). On "talents.static".
-- - Dual-spec tabs: TabSystem named tabs DUAL_SPEC_PRIMARY / DUAL_SPEC_SECONDARY
--   (camelot/…/blizzard_classtalentsframe.lua:124–134); ClassTalentsFrameTabMixin:GetTabText appends a checkmark or
--   lock atlas markup (:18–19, :39–49) and a force-disabled tab is wrapped in DISABLED_FONT_COLOR
--   (blizzard_sharedxml/shared/tabsystem/tabsystemtemplates.lua:192–196). Every write goes through the tab's own
--   UpdateTabText (SetIsActive :23–26, SetTabEnabled tabsystemtemplates.lua:202–207), called as self:…, hooked on
--   each tab instance. The composite is shown as the Japanese word with the markup and colour kept verbatim.
--   On "talents.static" too: UpdateTabs does not run on every show, so a released tab could stay English.
-- - Talent tooltips: TalentDisplayMixin:SetTooltipInternal builds GameTooltip (line 1 = the talent's name via
--   GameTooltip_SetTitle) and then triggers EventRegistry "TalentDisplay.TooltipCreated" (self, tooltip)
--   [verified: blizzard_sharedtalentui/blizzard_talentdisplay.lua:100–125, 290–305;
--   blizzard_talentbuttonspend.lua:84–137]. The talent buttons are pooled, so they are not registered help-tooltip
--   owners; the callback walks lines 2.. of that tooltip restricted to TOOLTIP_KEYS (surface "talents.tooltip").
--   Line 1 is never read or written. One Show() refit per pass that changed a line; forgotten on the tooltip's OnHide
--   and before each pass (the client rebuilt the lines).
-- - Talent requirement lines ("Spend 5 more points in Arms Talents"): the talent frame's AddConditionsToTooltip adds
--   each shown condition's tooltipText as a highlight line, red when unmet [verified:
--   blizzard_sharedtalentui/blizzard_sharedtalentframe.lua:1914-1972]. That text is the condition's tooltipFormat (a
--   SharedString row's English) formatted with spentAmountRequired and the tree's name [verified:
--   blizzard_sharedtalentui/blizzard_sharedtalentutil.lua:679-699, 726-730]. The pass reads, never calls, the frame's
--   own cache of those conditions (talentFrame.condInfoCache, blizzard_sharedtalentframe.lua:173, 1225-1232) for the
--   button's conditionIDs (nodeInfo on a talent button, entryInfo on a display; blizzard_talentbuttonbase.lua:254,
--   blizzard_talentdisplay.lua:379), and a line that is not a dictionary line is matched against each tooltipFormat
--   restricted to the SharedString family (UIStrings index:matchTemplate). The number and the tree's name are kept
--   as the client wrote them (names stay English).
-- - Button tooltips, both GameTooltip with the button as owner then Show(), so the buttons are
--   help-tooltip owners restricted to their one key:
--   - a force-disabled dual-spec tab adds its errorReason TALENT_SPEC_LOCKED (camelot/…/blizzard_classtalentsframe
--     .lua:151; TabSystemButtonMixin:OnEnter, tabsystemtemplates.lua:126–136);
--   - UndoButton's tooltipText TALENT_FRAME_DISCARD_CHANGES_BUTTON_TOOLTIP (camelot/…/blizzard_classtalentsframe.xml
--     :514–520; UIButtonMixin:OnEnter, blizzard_sharedxml/shared/button/uibuttontemplate.lua:20–45).
-- Not shown on camelot: PlayerSpellsFrame's own tab labels (TALENT_FRAME_TAB_LABEL_*). IsTabSystemAvailable is false
-- there (camelot/blizzard_playerspellsframe.lua:58–63) and UpdateTabs hides the TabSystem (blizzard_playerspellsframe
-- .lua:115–117).
local _, WFJ = ...
local Talents = {}
WFJ.Talents = Talents

local SURFACE = "talents"
local STATIC = "talents.static"
Talents.SURFACE = SURFACE
local Compat = WFJ.Compat

local PLAYER_SPELLS = "Blizzard_PlayerSpells"
local TOOLTIP_EVENT = "TalentDisplay.TooltipCreated"
local TT = "talents.tooltip"
Talents.TOOLTIP_SURFACE = TT
local TAB_KEYS = { DUAL_SPEC_PRIMARY = true, DUAL_SPEC_SECONDARY = true }
local CAMELOT_STATIC_KEYS = { apply = { TALENT_FRAME_APPLY_BUTTON_TEXT = true },
  activate = { TALENT_SPEC_ACTIVATE = true }, activeLabel = { TALENT_SPEC_ACTIVE = true },
  unspent = { UNSPENT_POINTS = true } }
local TOOLTIP_KEYS = { TALENT_BUTTON_TOOLTIP_RANK_FORMAT = true, TALENT_BUTTON_TOOLTIP_RANK_NO_MAX_FORMAT = true,
  TALENT_BUTTON_TOOLTIP_NEXT_RANK = true, TALENT_BUTTON_TOOLTIP_PURCHASE_INSTRUCTIONS = true,
  TALENT_BUTTON_TOOLTIP_REFUND_INSTRUCTIONS = true, TALENT_BUTTON_TOOLTIP_REPURCHASE_INSTRUCTIONS = true,
  TALENT_BUTTON_TOOLTIP_CLEAR_REPURCHASE_INSTRUCTIONS = true, TALENT_BUTTON_TOOLTIP_QUICK_ASSIGN_INSTRUCTIONS = true,
  TALENT_BUTTON_TOOLTIP_REPLACED_BY_FORMAT = true, TALENT_BUTTON_TOOLTIP_SELECTION_CURRENT_INSTRUCTIONS = true,
  TALENT_BUTTON_TOOLTIP_SELECTION_COST_ERROR = true,
  TALENT_BUTTON_TOOLTIP_SELECTION_CHOICE_ERROR = true, TALENT_BUTTON_TOOLTIP_SELECTION_ERROR = true,
  TALENT_BUTTON_TOOLTIP_REFUND_INVALID_LINKS_ERROR = true, TALENT_BUTTON_TOOLTIP_REFUND_INVALID_CONDITIONS_ERROR = true,
  TALENT_FRAME_INCREASED_RANKS_TEXT = true,
  -- The button's action-bar status (ClassTalentButtonSpendMixin:AddTooltipInstructions →
  -- SpellSearchUtil.GetTooltipForActionBarStatus, classtalents/blizzard_classtalentbuttontemplates.lua:206–212) and the
  -- edge-requirements line (blizzard_sharedtalentframe.lua:2002)
  TALENT_FRAME_SEARCH_TOOLTIP_NOT_ON_ACTIONBAR = true, TALENT_FRAME_SEARCH_TOOLTIP_ON_DISABLED_ACTIONBAR = true,
  TALENT_FRAME_SEARCH_TOOLTIP_ON_INACTIVE_BONUSBAR = true, GENERIC_TRAIT_FRAME_EDGE_REQUIREMENTS_BUTTON_TOOLTIP = true }
local TAB_TOOLTIP_KEYS = { TALENT_SPEC_LOCKED = true }
local UNDO_TOOLTIP_KEYS = { TALENT_FRAME_DISCARD_CHANGES_BUTTON_TOOLTIP = true }
Talents.CAMELOT_KEYS = { static = CAMELOT_STATIC_KEYS, tabs = TAB_KEYS, tooltip = TOOLTIP_KEYS,
  tabTooltip = TAB_TOOLTIP_KEYS, undoTooltip = UNDO_TOOLTIP_KEYS }

-- Widgets this module must never record: none by name (talent names are tooltip line 1, never read).
Talents.NEVER_TOUCH = {}

function Talents.showCamelotStatic()
  local list = {}
  for _, name in ipairs({ "apply", "activate", "activeLabel", "unspent" }) do
    list[#list + 1] = { "camelot." .. name, Compat.get(SURFACE, name), { only = CAMELOT_STATIC_KEYS[name] } }
  end
  return WFJ.Labels.showAll(STATIC, list)
end

-- One dual-spec tab's text: "<word>", "<word> |A:…|a" (active / locked), either wrapped in a colour (force-disabled).
-- The Japanese word replaces the English word; the markup and colour are kept as the client wrote them. → 1 | 0
function Talents.showTab(recKey, tab)
  local fs = WFJ.Labels.widget(type(tab) == "table" and tab.Text or nil)
  local index = WFJ.UIIndex
  if not fs or not index or WFJ.Labels.forbidden(fs) then
    WFJ.SurfaceState.drop(STATIC, recKey)
    return 0
  end
  local en = fs:GetText()
  local rec = WFJ.SurfaceState.get(STATIC, recKey)
  if rec and rec.fs == fs and rec.applied ~= nil and en == rec.applied then return 1 end -- still ours
  local key, args
  if type(en) == "string" and en ~= "" then
    local open, inner, close = en:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
    local body = inner or en
    local word, markup = body:match("^(.-)( |A.-|a)$")
    key = index:matchOnly(word or body, TAB_KEYS)
    if key and index:exactKey(word or body) == nil then key = nil end -- the whole word, never a template
    args = markup and { form = "prefix", rest = markup } or nil
    if key and open then args = { form = "wrapped", open = open, close = close, inner = args } end
  end
  if not key then
    WFJ.SurfaceState.drop(STATIC, recKey)
    return 0
  end
  WFJ.Render.show(STATIC, recKey, fs, en, "ui", "ui", key, args and { args = args } or nil)
  return 1
end

-- Both dual-spec tabs (after any tab's UpdateTabText). → the number shown
function Talents.showTabs()
  local frame = Compat.get(SURFACE, "talentsFrame")
  local system = type(frame) == "table" and frame.TabSystem or nil
  if type(system) ~= "table" or type(system.GetTabButton) ~= "function" then return 0 end
  local n = 0
  for recKey, field in pairs({ tabPrimary = "primarySpecTabID", tabSecondary = "secondarySpecTabID" }) do
    local id = frame[field]
    if id ~= nil then n = n + Talents.showTab(recKey, system:GetTabButton(id)) end
  end
  WFJ.Render.updateBanner(STATIC)
  return n
end

local walking, lastTooltip = false, nil

-- The tooltipFormat of every condition the hovered button's frame has cached. → list (maybe empty)
local function conditionFormats(display)
  local formats = {}
  if type(display) ~= "table" then return formats end
  local frame = rawget(display, "talentFrame")
  local cache = type(frame) == "table" and rawget(frame, "condInfoCache") or nil
  if type(cache) ~= "table" then return formats end
  local seen = {}
  for _, field in ipairs({ "nodeInfo", "entryInfo" }) do
    local info = rawget(display, field)
    local ids = type(info) == "table" and info.conditionIDs or nil
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
      local cond = cache[id]
      local fmt = type(cond) == "table" and cond.tooltipFormat or nil
      if type(fmt) == "string" and fmt ~= "" and not seen[fmt] then
        seen[fmt] = true
        formats[#formats + 1] = fmt
      end
    end
  end
  return formats
end
Talents.conditionFormats = conditionFormats

-- The talent tooltip's single refit (a Render.refresh or the end of a pass): lay it out for the new text.
local function refitTooltip()
  if walking or type(lastTooltip) ~= "table" or type(lastTooltip.Show) ~= "function" then return end
  walking = true
  local ok, err = pcall(lastTooltip.Show, lastTooltip)
  walking = false
  if not ok then error(err, 0) end
end

function Talents.forgetTooltip()
  return WFJ.Render.forget(TT)
end

local tooltipHooked = setmetatable({}, { __mode = "k" })

-- A requirement line: a SharedString row matched against one of the conditions' own templates. → 1 | 0
local function showRequirement(recKey, fs, formats)
  local index, text = WFJ.UIIndex, fs:GetText()
  if not index or type(index.matchTemplate) ~= "function" or type(text) ~= "string" or text == "" then return 0 end
  local only = WFJ.Labels.families("SharedString").only
  for _, fmt in ipairs(formats) do
    local key, args = index:matchTemplate(text, fmt, only)
    if key then return WFJ.Labels.showArgs(TT, recKey, fs, key, args, refitTooltip) end
  end
  return 0
end

-- EventRegistry callback (owner, talentDisplay, tooltip). → the number of dictionary lines
function Talents.onTooltip(_, display, tooltip)
  if walking or type(tooltip) ~= "table" or type(tooltip.GetName) ~= "function"
      or type(tooltip.NumLines) ~= "function" then
    return 0
  end
  if not tooltipHooked[tooltip] and type(tooltip.HookScript) == "function" then
    tooltipHooked[tooltip] = true
    tooltip:HookScript("OnHide", Talents.forgetTooltip)
  end
  WFJ.Render.forget(TT) -- the client rebuilt every line
  lastTooltip = tooltip
  local name, n, changed = tooltip:GetName(), 0, false
  local formats = conditionFormats(display)
  walking = true
  local ok, err = pcall(function()
    for i = 2, tooltip:NumLines() or 0 do -- line 1 is the talent's name: never read, never written
      local fs = Compat.resolve(name .. "TextLeft" .. i)
      if type(fs) == "table" and type(fs.GetText) == "function" then
        local before = fs:GetText()
        local got = WFJ.Labels.show(TT, "L" .. i, fs, refitTooltip, { only = TOOLTIP_KEYS })
        if got == 0 and #formats > 0 then got = showRequirement("L" .. i, fs, formats) end
        n = n + got
        if fs:GetText() ~= before then changed = true end
      end
    end
  end)
  walking = false
  if not ok then error(err, 0) end
  WFJ.Render.updateBanner(TT)
  if changed then refitTooltip() end
  return n
end

local function declareCamelot()
  Compat.declare(SURFACE, "talentsFrame", { "PlayerSpellsFrame.TalentsFrame" })
  Compat.declare(SURFACE, "apply", { "PlayerSpellsFrame.TalentsFrame.ApplyButton" })
  Compat.declare(SURFACE, "activeLabel", { "PlayerSpellsFrame.TalentsFrame.ActiveSpec.ActiveLabel" })
  Compat.declare(SURFACE, "unspent", { "PlayerSpellsFrame.TalentsFrame.ClassCurrencyDisplay.UnspentLabel" })
  Compat.declare(SURFACE, "eventRegistry", { "EventRegistry" })
  Compat.declare(SURFACE, "undo", { "PlayerSpellsFrame.TalentsFrame.UndoButton" })
  Compat.declare(SURFACE, "activate", { "PlayerSpellsFrame.TalentsFrame.ActiveSpec.ActivateButton" })
end

local camelotHooked, camelotWaiting = false, false

-- The Blizzard_PlayerSpells part (now, or on its ADDON_LOADED). Declared again here to clear Compat's memo.
function Talents.setupCamelot()
  declareCamelot()
  Talents.showCamelotStatic()
  if camelotHooked then return false end
  local frame = Compat.get(SURFACE, "talentsFrame")
  if type(frame) ~= "table" then return false end
  camelotHooked = true
  local system = frame.TabSystem
  if type(system) == "table" and type(system.GetTabButton) == "function" then
    for _, field in ipairs({ "primarySpecTabID", "secondarySpecTabID" }) do
      local tab = frame[field] ~= nil and system:GetTabButton(frame[field]) or nil
      if type(tab) == "table" and type(tab.UpdateTabText) == "function" then
        hooksecurefunc(tab, "UpdateTabText", Talents.showTabs)
      end
      WFJ.HelpTooltip.register(tab, { only = TAB_TOOLTIP_KEYS })
    end
  end
  WFJ.HelpTooltip.register(Compat.get(SURFACE, "undo"), { only = UNDO_TOOLTIP_KEYS })
  local registry = Compat.get(SURFACE, "eventRegistry")
  if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
    registry:RegisterCallback(TOOLTIP_EVENT, Talents.onTooltip, Talents)
  end
  Talents.showTabs()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. The window waits on
-- Blizzard_PlayerSpells. → true when it was set up now (the addon was already loaded), false otherwise
function Talents.init()
  declareCamelot()
  if camelotWaiting then return false end
  camelotWaiting = true
  return WFJ.LoadOnDemand.when(PLAYER_SPELLS, Talents.setupCamelot)
end
