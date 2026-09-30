-- The Forever micro menu, performance tooltip, XP exhaustion tick and the pet and possess bars' help-tooltip owners,
-- with the Blizzard writers replayed from the source. Every tooltip write is the client's (the
-- tooltip frame's own SetText / AddLine store fs.text), so the addon's writes are counted separately. Requires
-- Stub.install + Stub.installTooltipAPI first; build the UI index (H.uiSetup, which sets the English globals) before
-- M.installForever so the OnLoad replays read them.
local Stub = require("tests.lua.spec.wow_stub")

local M = {}

-- Strings the replays read that a spec's dictionary table may not carry (enUS).
M.GLOBALS = {
  MILLISECONDS_ABBR = "ms", UNKNOWN = "Unknown", NORMAL_FONT_COLOR_CODE = "|cffffd200", FONT_COLOR_CODE_CLOSE = "|r",
  GUILD = "Guild", NEWBIE_TOOLTIP_GUILDTAB = "Allows you to view information about your guild, and players in it. "
    .. "If you are an officer, you can also manage your guild from this tab.",
  TALENTS = "Talents", ABANDON_QUEST = "Abandon Quest", SHARE_QUEST = "Share Quest", CANCEL = "Cancel",
  MAINMENU_BUTTON = "Main Menu", LFG_LIST_MY_ACTIVITY_LIST_HEADER = "Your group is currently listed for:",
  NEWBIE_TOOLTIP_XPBAR = "The amount of experience (XP) you have earned. The color of the XP bar indicates your rest "
    .. "state: light blue for Rested, and purple for Normal.",
}

local function tooltip() return _G.GameTooltip end

-- A client Show (counted, so a spec can tell the addon's refit Show apart).
local function show()
  M.clientShows = M.clientShows + 1
  tooltip():Show()
end

local function button(name, kind)
  local b = Stub.button(name, "")
  b.kind = kind or "Button"
  function b:IsEnabled() return self.enabled end
  function b:GetID() return self.id or 0 end
  b.IsMouseOver = function() return true end
  b.GetCenter = function() return 100, 100 end
  return b
end

local function installTooltipHelpers()
  local tt = tooltip()
  -- [unknown] what the C setters write; modelled as the action's name on line 1 (a token's global, else the name).
  function tt:SetPetAction(id)
    local action = M.petActions[id]
    if not action then return false end
    self.item, self.spell = nil, nil
    self:writeLines({ action.token and _G[action.token] or action.name })
    self.shown = true
    return true
  end
  function tt:SetPossession(id)
    self.item, self.spell = nil, nil
    self:writeLines({ M.possessSpells[id] or "" })
    self.shown = true
  end

  -- Blizzard_SharedXML/SharedTooltipTemplates.lua:87–88, 128–131, 142–144, 166–172
  _G.GameTooltip_SetDefaultAnchor = function(t, parent) t:SetOwner(parent, "ANCHOR_NONE") end
  _G.GameTooltip_AddColoredLine = function(t, text) t:AddLine(text) end
  _G.GameTooltip_SetTitle = function(t, text)
    t:ClearLines()
    _G.GameTooltip_AddColoredLine(t, text)
  end
  _G.GameTooltip_AddNormalLine = function(t, text) _G.GameTooltip_AddColoredLine(t, text) end
  _G.GameTooltip_AddBlankLineToTooltip = function(t) t:AddLine(" ") end
  -- GameTooltip_AddNewbieTip (Blizzard_GameTooltip), which the performance builder calls
  _G.GameTooltip_AddNewbieTip = function(frame, normalText, r, g, b, newbieText, noNormalText)
    local t = tooltip()
    if _G.GetCVar("showNewbieTips") == "1" then
      _G.GameTooltip_SetDefaultAnchor(t, frame)
      if normalText then
        _G.GameTooltip_SetTitle(t, normalText)
        _G.GameTooltip_AddNormalLine(t, newbieText, true)
      else
        _G.GameTooltip_SetTitle(t, newbieText, nil, true)
      end
      show()
    elseif not noNormalText then
      t:SetOwner(frame, "ANCHOR_RIGHT")
      t:SetText(normalText, r, g, b)
    end
  end
  -- GameTooltip.lua:440–465: every TOOLTIP_UPDATE_TIME the owner's UpdateTooltip runs (a function value the client
  -- captured, so no global post-hook sees it).
  M.tooltipUpdate = function()
    local owner = tt:GetOwner()
    if owner and owner.UpdateTooltip then owner:UpdateTooltip() end
  end
end

local function installPerformanceBar()
  M.perf = { latencyHome = 45, latencyWorld = 60, fps = 59.6, bandwidth = 100, downloaded = 1.0, ipv6 = false,
    ipHome = 1, ipWorld = 2, protocolHome = 1, protocolWorld = 2, profiler = false, avgCPU = "12%", peakCPU = "40%",
    addons = { { name = "WoWForeverJapanese", mem = 2048.5 }, { name = "Quest Log", mem = 512 } } }
  _G.GetNetStats = function() return 0, 0, M.perf.latencyHome, M.perf.latencyWorld end
  -- Blizzard_PerformanceBar/PerformanceBar.lua:52–198
  _G.MainMenuBarPerformanceBarFrame_OnEnter = function(self)
    local tt, p = tooltip(), M.perf
    local detailed = _G.GetCVar("showNewbieTips") == "1"
    _G.GameTooltip_SetDefaultAnchor(tt, self)
    _G.GameTooltip_SetTitle(tt, self.tooltipText)
    _G.GameTooltip_AddNewbieTip(self, self.tooltipText, 1.0, 1.0, 1.0, self.newbieText)
    tt:AddLine(" ")
    tt:AddLine(string.format(_G.MAINMENUBAR_LATENCY_LABEL, p.latencyHome, p.latencyWorld))
    if detailed then tt:AddLine(_G.NEWBIE_TOOLTIP_LATENCY) end
    tt:AddLine(" ")
    local ipTypes, protocolTypes = { "IPv4", "IPv6" }, { "TCP", "UDP" }
    if p.ipv6 then
      tt:AddLine(string.format(_G.MAINMENUBAR_PROTOCOLS_LABEL, ipTypes[p.ipHome] or _G.UNKNOWN,
        ipTypes[p.ipWorld] or _G.UNKNOWN))
      if detailed then tt:AddLine(_G.NEWBIE_TOOLTIP_PROTOCOLS) end
      tt:AddLine(" ")
    end
    tt:AddLine(string.format(_G.MAINMENUBAR_COMMUNICATION_PROTOCOL_LABEL, protocolTypes[p.protocolHome] or _G.UNKNOWN,
      protocolTypes[p.protocolWorld] or _G.UNKNOWN))
    tt:AddLine(" ")
    tt:AddLine(string.format(_G.MAINMENUBAR_FPS_LABEL, p.fps))
    if detailed then tt:AddLine(_G.NEWBIE_TOOLTIP_FRAMERATE) end
    tt:AddLine(" ")
    tt:AddLine(string.format(_G.MAINMENUBAR_BANDWIDTH_LABEL, p.bandwidth))
    if detailed then tt:AddLine(_G.NEWBIE_TOOLTIP_BANDWIDTH) end
    tt:AddLine(" ")
    tt:AddLine(string.format(_G.MAINMENUBAR_DOWNLOAD_PERCENT_LABEL, math.floor(p.downloaded * 100 + 0.5)))
    if detailed then tt:AddLine(_G.NEWBIE_TOOLTIP_DOWNLOAD_PERCENT) end
    if p.profiler then -- AddonList:GetOverallMetric (Blizzard_AddOnList/AddonList.lua:711–724)
      _G.GameTooltip_AddBlankLineToTooltip(tt)
      _G.GameTooltip_AddColoredLine(tt, string.format(_G.ADDON_LIST_PERFORMANCE_AVERAGE_CPU, p.avgCPU))
      _G.GameTooltip_AddColoredLine(tt, string.format(_G.ADDON_LIST_PERFORMANCE_PEAK_CPU, p.peakCPU))
    end
    local total = 0
    for _, a in ipairs(p.addons) do total = total + a.mem end
    if total > 0 then
      if total > 1000 then
        tt:AddLine("\n")
        tt:AddLine(string.format(_G.TOTAL_MEM_MB_ABBR, total / 1000))
      else
        tt:AddLine("\n")
        tt:AddLine(string.format(_G.TOTAL_MEM_KB_ABBR, total))
      end
      if detailed then tt:AddLine(_G.NEWBIE_TOOLTIP_MEMORY) end
      for _, a in ipairs(p.addons) do
        if a.mem > 1024 then
          tt:AddLine(string.format("(%.2f MB) %s", a.mem / 1024, a.name)) -- ADDON_MEM_MB_ABBR
        else
          tt:AddLine(string.format("(%.0f KB) %s", a.mem, a.name)) -- ADDON_MEM_KB_ABBR
        end
      end
    end
    show()
  end
end

local function installExhaustionTicks()
  -- Shared/StatusTrackingManager.lua:5–13 (unnamed bars and ticks); each tick's writer is set by M.installForever
  _G.StatusTrackingBarInfo = { BarsEnum = { None = -1, Reputation = 1, Honor = 2, Artifact = 3, Experience = 4 } }
  M.rest = { id = 1, name = "Rested", multiplier = 2 }
  _G.GetRestState = function() return M.rest.id, M.rest.name, M.rest.multiplier end
  _G.GetScreenWidth = function() return 1024 end
  M.ticks = {}
  for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
    local container = _G.CreateFrame("Frame", name)
    container.bars = {}
    for _, index in ipairs({ 1, 4 }) do
      local bar = _G.CreateFrame("Frame")
      bar.ExhaustionTick = button(nil)
      container.bars[index] = bar
    end
    local tick = container.bars[4].ExhaustionTick
    tick.shown = true
    M.ticks[#M.ticks + 1] = tick
  end
end

local function installActionBars()
  _G.KeybindFrames_InQuickKeybindMode = function() return false end
  -- Shared/ActionBar.lua:24–31 names; Shared/PetActionBar.lua:119–132 (Update) and 296–326 (OnEnter)
  M.petActions = {}
  M.pets = {}
  for i = 1, 10 do
    local b = button("PetActionButton" .. i, "CheckButton")
    b.id = i
    b:SetScript("OnEnter", function(self)
      if not self.tooltipName then return end
      local tt = tooltip()
      if _G.GetCVar("UberTooltips") == "0" and not _G.KeybindFrames_InQuickKeybindMode() then
        tt:SetOwner(self, "ANCHOR_RIGHT")
        local bindingText = _G.GetBindingText(_G.GetBindingKey("BONUSACTIONBUTTON" .. self:GetID()))
        if bindingText and bindingText ~= "" then
          tt:SetText(self.tooltipName .. _G.NORMAL_FONT_COLOR_CODE .. " (" .. bindingText .. ")"
            .. _G.FONT_COLOR_CODE_CLOSE, 1.0, 1.0, 1.0)
        else
          tt:SetText(self.tooltipName, 1.0, 1.0, 1.0)
        end
        if self.tooltipSubtext then tt:AddLine(self.tooltipSubtext) end
        show()
        self.UpdateTooltip = nil
      else
        _G.GameTooltip_SetDefaultAnchor(tt, self)
        if tt:SetPetAction(self:GetID()) then
          self.UpdateTooltip = self.scripts.OnEnter
        else
          self.UpdateTooltip = nil
        end
      end
    end)
    b:SetScript("OnLeave", function() tooltip():Hide() end)
    M.pets[i] = b
  end
  -- PetActionBarMixin:Update: a token action's name is its global (e.g. "PET_ACTION_ATTACK"), else the spell name.
  M.setPetAction = function(i, action)
    M.petActions[i] = action
    local b = M.pets[i]
    b.tooltipName = action.token and _G[action.token] or action.name
  end

  -- Shared/PossessActionBar.lua:92–106; POSSESS_CANCEL_SLOT = 2
  M.possessSpells = { "Mind Control" }
  M.possess = {}
  for i = 1, 2 do
    local b = button("PossessButton" .. i, "CheckButton")
    b.id = i
    b:SetScript("OnEnter", function(self)
      local tt = tooltip()
      if _G.GetCVar("UberTooltips") == "1" then _G.GameTooltip_SetDefaultAnchor(tt, self)
      else tt:SetOwner(self, "ANCHOR_RIGHT") end
      if self:GetID() == 2 then tt:SetText(_G.CANCEL) else tt:SetPossession(self:GetID()) end
    end)
    M.possess[i] = b
  end
end

-- Forever: the mainline micro menu with camelot overrides [verified: Forever
-- blizzard_micromenu/camelot/micromenucontaineroverrides.lua GenerateButtonInfos; mainline/mainmenubarmicrobuttons.xml
-- :51–344]: { name, title key, binding action }, each button's OnLoad / SetTextureAndTooltip title
-- (mainmenubarmicrobuttons.lua:542, 664, 716–720, 905–907, 968, 1035, 1106, 1146, 1251–1255, 1424, 1535, 1687, 1810,
-- 1934). HelpMicroButton sets no title at OnLoad (lua:1919–1928) and is left out.
M.FOREVER_MICRO = {
  { "CharacterMicroButton", "CHARACTER_BUTTON", "TOGGLECHARACTER0" },
  { "ProfessionMicroButton", "PROFESSIONS_BUTTON", "TOGGLEPROFESSIONBOOK" },
  { "PlayerSpellsMicroButton", "PLAYERSPELLS_BUTTON", "TOGGLETALENTS" },
  { "SpellbookMicroButton", "SPELLBOOK_ABILITIES_BUTTON", "TOGGLESPELLBOOK" },
  { "TalentMicroButton", "PLAYERSPELLS_BUTTON", "TOGGLETALENTS" },
  { "AchievementMicroButton", "ACHIEVEMENT_BUTTON", "TOGGLEACHIEVEMENT" },
  { "LegacyMicroButton", "LEGACY_BUTTON", "TOGGLELEGACYSYSTEM" },
  { "QuestLogMicroButton", "QUESTLOG_BUTTON", "TOGGLEQUESTLOG" },
  { "HousingMicroButton", "HOUSING_MICRO_BUTTON", "TOGGLEHOUSINGDASHBOARD" },
  { "GuildMicroButton", "GUILD", "TOGGLEGUILDTAB" },
  { "LFDMicroButton", "DUNGEONS_BUTTON", "TOGGLEGROUPFINDER" },
  { "CollectionsMicroButton", "COLLECTIONS", "TOGGLECOLLECTIONS" },
  { "EJMicroButton", "ADVENTURE_JOURNAL", "TOGGLEENCOUNTERJOURNAL" },
  { "StoreMicroButton", "BLIZZARD_STORE", nil },
  { "MainMenuMicroButton", "MAINMENU_BUTTON", "TOGGLEGAMEMENU" },
}

-- The Forever client's micro menu: the buttons above, each OnEnter
-- MainMenuBarMicroButtonMixin:EvaluateTooltipVisibility (SetOwner, GameTooltip_SetTitle, the disabled reason line,
-- Show; lua:411–438); no MainMenuBarPerformanceBarFrame[Button]: the performance tooltip is built by
-- MainMenuMicroButtonMixin:OnUpdate with the button as owner (lua:1947–1985). Also the pet and possess bars.
-- cvars: showNewbieTips, UberTooltips; bindings: action → key text.
function M.installForever()
  M.clientShows = 0
  M.cvars = { showNewbieTips = "1", UberTooltips = "1" }
  M.bindings = {}
  for k, v in pairs(M.GLOBALS) do if _G[k] == nil then _G[k] = v end end
  _G.GetCVar = function(name) return M.cvars[name] end
  _G.GetBindingKey = function(action) return M.bindings[action] end
  _G.GetBindingText = function(key) return key end
  _G.UIParent = _G.UIParent or _G.CreateFrame("Frame", "UIParent")
  installTooltipHelpers()
  installPerformanceBar()
  installExhaustionTicks() -- the status-bar containers; each tick's writer is the mainline one below
  _G.GameTooltip_AddHighlightLine = _G.GameTooltip_AddHighlightLine or function(t, text) t:AddLine(text) end
  -- mainline/expbaroverrides.lua:20–55: anchored to UIParent whatever the tick's position; M.xp and M.banked drive it
  M.xp = { cur = 1500, max = 2000 }
  M.banked = nil -- "header" (XP_TEXT_BANKED_XP_HEADER + TRIAL_CAP_BANKED_XP_TOOLTIP)
  local function exhaustionTooltip()
    local _, stateName, multiplier = _G.GetRestState()
    local tt = tooltip()
    _G.GameTooltip_SetDefaultAnchor(tt, _G.UIParent)
    _G.GameTooltip_SetTitle(tt, string.format("|cffffffff%s / %s  ( %d%% )|r\n\n", M.xp.cur, M.xp.max,
      math.ceil(M.xp.cur / M.xp.max * 100))) -- XP_TEXT: numbers only
    _G.GameTooltip_AddHighlightLine(tt, string.format(_G.EXHAUST_TOOLTIP1, stateName, multiplier * 100))
    if M.rest.id == 4 or M.rest.id == 5 then _G.GameTooltip_AddHighlightLine(tt, _G.EXHAUST_TOOLTIP2) end
    if M.banked then
      _G.GameTooltip_AddBlankLineToTooltip(tt)
      _G.GameTooltip_AddNormalLine(tt, _G.XP_TEXT_BANKED_XP_HEADER)
      _G.GameTooltip_AddHighlightLine(tt, _G.TRIAL_CAP_BANKED_XP_TOOLTIP)
    end
    show()
  end
  for _, tick in ipairs(M.ticks) do
    tick.ExhaustionToolTipText = exhaustionTooltip
    tick:SetScript("OnEnter", function(self) self:ExhaustionToolTipText() end) -- <OnEnter method=…> (expbar.xml:30)
    tick:SetScript("OnLeave", function() tooltip():Hide() end)
  end
  installActionBars()
  -- lua:56–60: FormatBindingKeyIntoText(text, action, "%s %s",
  --   NORMAL_FONT_COLOR_CODE .. "(%s)" .. FONT_COLOR_CODE_CLOSE)
  _G.MicroButtonTooltipText = function(text, action)
    local key = action and _G.GetBindingKey(action)
    if key then
      return text .. " " .. _G.NORMAL_FONT_COLOR_CODE .. "(" .. _G.GetBindingText(key) .. ")"
        .. _G.FONT_COLOR_CODE_CLOSE
    end
    return text
  end
  local function evaluate(self)
    local tt = tooltip()
    tt:SetOwner(self, "ANCHOR_RIGHT")
    _G.GameTooltip_SetTitle(tt, self.tooltipText)
    if not self:IsEnabled() and self.disabledTooltip then tt:AddLine(self.disabledTooltip) end
    show()
  end
  M.buttons = {}
  for _, spec in ipairs(M.FOREVER_MICRO) do
    local name, titleKey, action = spec[1], spec[2], spec[3]
    local b = button(name)
    b.action, b.titleKey = action, titleKey
    b.tooltipText = action and _G.MicroButtonTooltipText(_G[titleKey], action) or _G[titleKey]
    b:SetScript("OnEnter", evaluate)
    b:SetScript("OnLeave", function() tooltip():Hide() end)
    M.buttons[name] = b
  end
  M.updateBindings = function()
    for _, b in pairs(M.buttons) do
      b.tooltipText = b.action and _G.MicroButtonTooltipText(_G[b.titleKey], b.action) or _G[b.titleKey]
    end
  end
  local mm = M.buttons.MainMenuMicroButton
  mm.hover, mm.updateInterval = nil, 0
  mm:SetScript("OnEnter", function(self) self.hover = 1; self.updateInterval = 0 end)
  mm:SetScript("OnLeave", function(self) self.hover = nil; tooltip():Hide() end)
  mm:SetScript("OnUpdate", function(self, elapsed)
    if self.updateInterval > 0 then
      self.updateInterval = self.updateInterval - elapsed
    else
      self.updateInterval = 1
      if self.hover then
        self.tooltipText = _G.MicroButtonTooltipText(_G.MAINMENU_BUTTON, "TOGGLEGAMEMENU")
        _G.MainMenuBarPerformanceBarFrame_OnEnter(self)
      end
    end
  end)
end

-- Drivers: the mouse enters / leaves an owner; a frame's OnUpdate runs.
function M.hover(owner) owner.scripts.OnEnter(owner) end
function M.leave(owner) if owner.scripts.OnLeave then owner.scripts.OnLeave(owner) else tooltip():Hide() end end
function M.update(frame, elapsed) frame.scripts.OnUpdate(frame, elapsed or 0) end

return M
