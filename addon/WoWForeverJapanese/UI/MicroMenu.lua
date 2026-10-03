-- UI/MicroMenu.lua: the micro menu and action-bar help tooltips (surface "help", area "ui",
-- ADR-016). Every tooltip here is written in Lua with GameTooltip:SetText / AddLine / GameTooltip_SetTitle, so this
-- module only registers the frames that own them with UI/HelpTooltip, whose SetText / Show post-hooks walk the lines
-- after the client wrote them (and after each ~1 s performance rebuild or UpdateTooltip refresh). The one text written
-- here is the XP bar's own label (below); otherwise Blizzard tables are only read.
-- Forever runs the mainline micro menu with camelot overrides [verified: Forever blizzard_micromenu.toc:
-- [Family]\MainMenuBarMicroButtons.lua/.xml, [Game]\MicroMenuContainerOverrides.lua for camelot]:
--   micro buttons: camelot/micromenucontaineroverrides.lua GenerateButtonInfos places Character, Profession,
--     Spellbook, Talent, Legacy, QuestLog, Housing, Guild, LFD, Collections, EJ, Help, Store, MainMenu; the XML also
--     builds PlayerSpells and Achievement (mainline/mainmenubarmicrobuttons.xml:51–344). Each tooltip is
--     MainMenuBarMicroButtonMixin:EvaluateTooltipVisibility: SetOwner, GameTooltip_SetTitle(self.tooltipText),
--     AddLine(<disabled reason>) when disabled, Show (mainmenubarmicrobuttons.lua:411–438); the title is
--     MicroButtonTooltipText(<key>, <action>) (lua:56–60, "<text> |cffffd200(<key>)|r"). A name the client lacks is
--     skipped;
--   the performance / latency tooltip: the only caller of MainMenuBarPerformanceBarFrame_OnEnter is
--     MainMenuMicroButtonMixin:OnUpdate with self = the button (lua:1982–1984), so MainMenuMicroButton is a latency
--     owner too (registered once);
--   a disabled button's reason is the AddLine above (GetValueOrCallFunction(self, "disabledTooltip"), lua:432–433), so
--     every reason key is walked with its title (FEATURE_NOT_YET_AVAILABLE, LEGACY_MICRO_BUTTON_LOCKED_TOOLTIP, …);
--   the XP bar's own text: ExpBarMixin:UpdateCurrentText writes SetBarText(XP_STATUS_BAR_TEXT:format(
--     cur, max)) into bar.OverlayFrame.Text (blizzard_statustrackingbar/mainline/expbaroverrides.lua:10–12, shared/
--     statustrackingbar.lua:20–22), called as self:UpdateCurrentText() from Update and OnEnter (shared/expbar.lua:40,
--     75), so it is post-hooked on each container's Experience bar instance (surface "help.xpbar", restricted to
--     XP_STATUS_BAR_TEXT). The Experience bar is reached by reading
--     `container.bars[StatusTrackingBarInfo.BarsEnum.Experience]` of each status-bar container;
--   the exhaustion tick tooltip: ExhaustionTickMixin:ExhaustionToolTipText anchors it to UIParent
--     (GameTooltip_SetDefaultAnchor(tooltip, UIParent)) and writes XP_TEXT (numbers only), EXHAUST_TOOLTIP1,
--     EXHAUST_TOOLTIP2, and for a trial with banked XP XP_TEXT_BANKED_XP_HEADER + TRIAL_CAP_BANKED_*_TOOLTIP, then
--     Show (expbaroverrides.lua:20–55); it runs from the tick's OnEnter (method=, expbar.xml:20–31) and the bar's
--     OnEnter (shared/expbar.lua:87). UIParent owns every default-anchored tooltip, so it is never registered: each
--     tick's method is post-hooked and, when GameTooltip's owner is UIParent right then, walked once with
--     HelpTooltip.walkAs restricted to EXHAUST_KEYS. The lines are released with the other help lines on OnHide. The
--     tick itself is registered too (a tooltip it owns is walked as usual);
--   pet action buttons PetActionButton1..10: with UberTooltips off, SetText(_G[token]) (+ binding suffix) + Show;
--     with it on, the C setter GameTooltip:SetPetAction, walked after it [unknown: what the C setter writes];
--     restricted to the pet command / stance keys, since a non-token action's title is a spell name;
--   possess buttons PossessButton1..2: SetText(CANCEL) on the cancel slot; restricted to CANCEL.
-- Not here: backpack / keyring / bag-slot tooltips (UI/Bags.lua), the micro buttons have no text of their own.
-- Micro-button alerts (TALENT_MICRO_BUTTON_UNSPENT_TALENTS, CLUB_FINDER_NEW_COMMUNITY_JOINED) are HelpTip callouts:
--   UI/HelpTips rewrites them inside ApplyText, before the box is measured.
local _, WFJ = ...
local MicroMenu = {}
WFJ.MicroMenu = MicroMenu

local SURFACE = "help" -- records live on UI/HelpTooltip's surface
MicroMenu.SURFACE = SURFACE
local DECLARE = "help.micromenu" -- this module's Compat names
local Compat = WFJ.Compat

-- The only widget written here is the XP bar text, restricted to XP_STATUS_BAR_TEXT: nothing to protect.
MicroMenu.NEVER_TOUCH = {}

MicroMenu.MICRO_BUTTONS = { "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
  "QuestLogMicroButton", "GuildMicroButton", "MainMenuMicroButton", "HelpMicroButton" }
-- The rest of the mainline menu's buttons.
MicroMenu.FOREVER_BUTTONS = { "ProfessionMicroButton", "PlayerSpellsMicroButton", "AchievementMicroButton",
  "LegacyMicroButton", "HousingMicroButton", "LFDMicroButton", "CollectionsMicroButton", "EJMicroButton",
  "StoreMicroButton" }
local LATENCY_OWNERS = { "MainMenuMicroButton" }
MicroMenu.LATENCY_OWNERS = LATENCY_OWNERS
local BAR_CONTAINERS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }
local NUM_PET_BUTTONS = 10 -- PetActionButton1..10
local NUM_POSSESS_BUTTONS = 2 -- PossessButton1..2

-- `only` lists for owners whose lines may also be names.
local PET_KEYS = { "PET_ACTION_ATTACK", "PET_ACTION_FOLLOW", "PET_ACTION_WAIT", "PET_ACTION_DISMISS",
  "PET_MODE_AGGRESSIVE", "PET_MODE_DEFENSIVE", "PET_MODE_PASSIVE", "PET_MODE_ASSIST" }
local POSSESS_KEYS = { "CANCEL" }

local function petName(i) return "PetActionButton" .. i end
local function possessName(i) return "PossessButton" .. i end

local function declareAll()
  local names = {}
  for _, list in ipairs({ MicroMenu.MICRO_BUTTONS, MicroMenu.FOREVER_BUTTONS, LATENCY_OWNERS, BAR_CONTAINERS }) do
    for _, name in ipairs(list) do names[#names + 1] = name end
  end
  for i = 1, NUM_PET_BUTTONS do names[#names + 1] = petName(i) end
  for i = 1, NUM_POSSESS_BUTTONS do names[#names + 1] = possessName(i) end
  for _, name in ipairs(names) do Compat.declare(DECLARE, name, { name }) end
  Compat.declare(DECLARE, "barInfo", { "StatusTrackingBarInfo" })
  Compat.declare(DECLARE, "tooltip", { "GameTooltip" })
  Compat.declare(DECLARE, "uiParent", { "UIParent" })
end

-- Registers one declared owner; a missing frame, or one registered already this init (MainMenuMicroButton is both a
-- micro button and the latency owner), is skipped. → 1 | 0
local seen
local function register(owner, opts)
  if type(owner) ~= "table" or (seen and seen[owner]) then return 0 end
  if seen then seen[owner] = true end
  WFJ.HelpTooltip.register(owner, opts)
  return 1
end

local XPBAR_SURFACE = SURFACE .. ".xpbar"
local XPBAR_KEYS = { "XP_STATUS_BAR_TEXT" }
local xpHooked = setmetatable({}, { __mode = "k" })

-- The Experience bar's own text, as record `recKey`. → 1 | 0
function MicroMenu.showXPText(bar, recKey)
  local overlay = type(bar) == "table" and bar.OverlayFrame or nil
  local text = type(overlay) == "table" and overlay.Text or nil
  return WFJ.Labels.show(XPBAR_SURFACE, recKey or "xp", text, nil, { only = XPBAR_KEYS })
end

local function hookXPText(bar, recKey)
  if xpHooked[bar] or type(bar.UpdateCurrentText) ~= "function" or type(bar.OverlayFrame) ~= "table" then return end
  xpHooked[bar] = true
  hooksecurefunc(bar, "UpdateCurrentText", function(self) MicroMenu.showXPText(self, recKey) end)
  WFJ.Diag.watch(bar, "UpdateCurrentText", recKey)
  MicroMenu.showXPText(bar, recKey)
end

local EXHAUST_KEYS = { "EXHAUST_TOOLTIP1", "EXHAUST_TOOLTIP2", "XP_TEXT_BANKED_XP_HEADER",
  "TRIAL_CAP_BANKED_LEVELS_TOOLTIP", "TRIAL_CAP_BANKED_XP_TOOLTIP" }
local tickHooked = setmetatable({}, { __mode = "k" })

-- Post-hook of a tick's ExhaustionToolTipText: the UIParent-anchored exhaustion tooltip, walked once.
-- Any other owner (a tooltip the writer did not build) is left to the usual walk.
-- → the number of dictionary lines
function MicroMenu.onExhaustionTooltip()
  local tt, parent = Compat.get(DECLARE, "tooltip"), Compat.get(DECLARE, "uiParent")
  if type(tt) ~= "table" or type(tt.GetOwner) ~= "function" or parent == nil or tt:GetOwner() ~= parent then
    return 0
  end
  return WFJ.HelpTooltip.walkAs(tt, { only = EXHAUST_KEYS })
end

local function hookExhaustionTooltip(tick)
  if type(tick) ~= "table" or tickHooked[tick] or type(tick.ExhaustionToolTipText) ~= "function" then return end
  tickHooked[tick] = true
  hooksecurefunc(tick, "ExhaustionToolTipText", MicroMenu.onExhaustionTooltip)
end

-- The exhaustion tick of each container's Experience bar (read only). → the number registered
local function registerExhaustionTicks()
  local info = Compat.get(DECLARE, "barInfo")
  local index = type(info) == "table" and type(info.BarsEnum) == "table" and info.BarsEnum.Experience
  if type(index) ~= "number" then return 0 end
  local n = 0
  for _, name in ipairs(BAR_CONTAINERS) do
    local container = Compat.get(DECLARE, name)
    local bars = type(container) == "table" and container.bars
    local bar = type(bars) == "table" and bars[index]
    if type(bar) == "table" then
      n = n + register(bar.ExhaustionTick)
      hookExhaustionTooltip(bar.ExhaustionTick)
      hookXPText(bar, "xp." .. name)
    end
  end
  return n
end

-- The stable's pet XP bar, the one camelot PetExpStatusBarTemplate instance (camelot
-- Blizzard_StableUI.xml:190, parentKey expBar of PetStableFrame; the TOC allows standard and camelot).
-- PetExpBarMixin:UpdateCurrentText writes SetBarText(XP_STATUS_BAR_TEXT:format(cur, max)) like the main bars
-- (blizzard_statustrackingbar/camelot/petexpbar.lua:24–26). The character sheet's pet bar writes a literal "XP %s/%s"
-- (camelot paperdollframe.lua:3634–3642), which is no global string: nothing to ship it under.
function MicroMenu.hookPetStableBar()
  Compat.declare(DECLARE, "petStableBar", { "PetStableFrame.expBar" })
  local bar = Compat.get(DECLARE, "petStableBar")
  if type(bar) ~= "table" then return false end
  hookXPText(bar, "xp.petstable")
  return true
end

local hooked = false
local registered = 0

-- Called by Main after Compat.init and HelpTooltip.init. → the number of owners registered
function MicroMenu.init()
  declareAll()
  if hooked then return registered end
  hooked = true
  seen = {}
  local n = 0
  for _, list in ipairs({ MicroMenu.MICRO_BUTTONS, MicroMenu.FOREVER_BUTTONS, LATENCY_OWNERS }) do
    for _, name in ipairs(list) do n = n + register(Compat.get(DECLARE, name)) end
  end
  n = n + registerExhaustionTicks()
  local LOD = WFJ.LoadOnDemand
  if type(LOD) == "table" and type(LOD.when) == "function" then
    LOD.when("Blizzard_StableUI", MicroMenu.hookPetStableBar)
  else
    MicroMenu.hookPetStableBar()
  end
  for i = 1, NUM_PET_BUTTONS do n = n + register(Compat.get(DECLARE, petName(i)), { only = PET_KEYS }) end
  for i = 1, NUM_POSSESS_BUTTONS do
    n = n + register(Compat.get(DECLARE, possessName(i)), { only = POSSESS_KEYS })
  end
  WFJ.HelpTooltip.after("SetPetAction") -- UberTooltips on: the pet bar's C setter
  seen = nil
  registered = n
  return n
end
