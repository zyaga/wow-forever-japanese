-- Main.lua: composition root. The only non-UI file allowed to create a frame. Wires the modules together on
-- ADDON_LOADED; no policy lives here (docs/architecture/addon-modules.md).
local ADDON, WFJ = ...

-- Global entry point for Bindings.xml (a binding body runs as a global chunk and cannot see the addon namespace).
function WFJ_ToggleTranslation()
  local S = WFJ.Settings
  S.set("enabled", not S.get("enabled"))
  print(("WFJ: translation %s"):format(S.get("enabled") and "on" or "off"))
end

-- Global entry point for the hidden WFJ_REVEAL binding (runOnUp: keystate "down" / "up"), which UI/RevealBinding
-- puts on a `bound` modifier key (ADR-018). The edge only invalidates; Modifier's poll is the truth.
function WFJ_RevealKey(keystate)
  local down = keystate == "down"
  WFJ.Modifier.bindingEdge(down)
  WFJ.RevealBinding.watch(down and WFJ.State.modifierHeld)
end

-- The TOC's AddonCompartmentFunc entries. Blizzard's addon dropdown on the minimap calls these globals by
-- name with (addonName, buttonName) on a click and (addonName, frame) on hover [verified: Blizzard_Minimap/Mainline/
-- AddonCompartment.lua:77–117]. Left-click opens the fix window, right-click the minimap button's menu.
function WFJ_OnAddonCompartmentClick(_, buttonName)
  WFJ.MinimapButton.click(nil, buttonName)
end

function WFJ_OnAddonCompartmentEnter(_, frame)
  WFJ.MinimapButton.showTooltip(frame)
end

function WFJ_OnAddonCompartmentLeave()
  WFJ.MinimapButton.hideTooltip()
end

-- The one reader of the player's own name / class / race / sex, shared by Core/Placeholders (the corpus tokens)
-- and Core/Collector (English normalization). Read at call time rather than cached at load. Each API
-- is guarded: a client without one leaves that token literal and makes the collector refuse (no_player) instead of
-- raising from every surface hook. A name equal to the client's UNKNOWNOBJECT string ("Unknown", when the global
-- exists) is treated as unavailable [unverified that "player" ever returns it once a quest window can be open].
local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  return fn(...)
end

local function player()
  local className, classFile = call(UnitClass, "player")
  local raceName, raceFile = call(UnitRace, "player")
  local name = call(UnitName, "player")
  if name ~= nil and name == _G.UNKNOWNOBJECT then name = nil end
  return {
    name = name, className = className, classFile = classFile,
    raceName = raceName, raceFile = raceFile, sex = call(UnitSex, "player"),
  }
end

-- The player as the Collector normalizes English with: the name and the localized class / race.
local function collectorPlayer()
  local p = player()
  return { name = p.name, class = p.className, race = p.raceName }
end

-- The key of a live English text for a keyed type (gossip: ADR-005 / ADR-017; book pages: ADR-022): the
-- first candidate key a translation of that type is shipped under, else the full key (for gossip, the value the
-- Collector stores as the line's hash). → function(text) → key | nil
local function keyOf(type_)
  return function(text)
    local keys = WFJ.Collector.keys(text, collectorPlayer())
    for _, k in ipairs(keys) do
      if WFJ.Lookup.keyed(type_, k) then return k end
    end
    return keys[1]
  end
end
local gossipKey = keyOf("gossip")

-- Whether `text` is the English quest `id`'s `field` ships under: one of its fingerprints (as the live check reads
-- them) is the entry's h1 or female-variant h1. → boolean
function WFJ.IsQuestFieldEnglish(id, field, text)
  local entry = WFJ.Lookup.get("quest." .. field, id)
  if type(entry) ~= "table" or type(text) ~= "string" or (entry.h1 == nil and entry.h1f == nil) then return false end
  for _, h in ipairs(WFJ.Collector.fingerprints(text, collectorPlayer())) do
    if h == entry.h1 or h == entry.h1f then return true end
  end
  return false
end

-- The gossip key a translation of `text` is actually shipped under, or nil: quest text the client shows with no id
-- the addon can read (a quest's conditional description, its completion log line) is keyed like NPC dialogue.
-- Memoized per player and text (the minimap's quest block asks every frame; the keys depend on the player's name,
-- class and race); the memo is dropped at 256 entries. Nothing is memoized before the player is known, so an early
-- miss is asked again.
local shippedMemo, shippedCount, shippedWho = {}, 0, nil
function WFJ.ShippedGossipKey(text)
  if type(text) ~= "string" or text == "" then return nil end
  local p = collectorPlayer()
  local known = type(p.name) == "string" and type(p.class) == "string" and type(p.race) == "string"
  local who = known and (p.name .. "|" .. p.class .. "|" .. p.race) or nil
  if who ~= shippedWho then shippedMemo, shippedCount, shippedWho = {}, 0, who end
  local hit = shippedMemo[text]
  if hit ~= nil then return hit or nil end
  local found = false
  for _, k in ipairs(WFJ.Collector.keys(text, p)) do
    if WFJ.Lookup.keyed("gossip", k) then found = k; break end
  end
  if who then
    if shippedCount >= 256 then shippedMemo, shippedCount = {}, 0 end
    shippedMemo[text], shippedCount = found, shippedCount + 1
  end
  return found or nil
end

local function expand(ja)
  if not WFJ.Placeholders.mayHaveTokens(ja) then return ja end -- token-free text never touches the client
  return (WFJ.Placeholders.expand(ja, player()))
end

-- The client's live English for a UI string key (ADR-015): its global string. An item subclass has none the
-- tooltip uses (C_Item.GetItemSubClassInfo returns the long name "Staves" where the tooltip shows "Staff"),
-- so those rows are matched by the live line's fingerprint (Core/UIStrings). Never stored English: the
-- addon ships only the h1 of the English it was drafted against.
-- The renderer `$D<k>` copies a duration with: only the forms a spell's `$d` prints, with the unit the client
-- chose (ADR-028).
local function spellDuration(text)
  return WFJ.UIIndex and WFJ.UIIndex:duration(text, true) or nil
end

local function uiEnglish(key)
  -- item subclasses and enchantment stat lines are fingerprint rows: no client string to read
  if WFJ.UIStrings.isFingerprintKey(key) then return nil end
  local v = _G[key]
  return type(v) == "string" and v or nil
end

local function uiHash(text)
  return (WFJ.Hash.h32x2(WFJ.Normalize.v1(text)))
end

-- Builds WFJ.UIIndex from the shipped UI strings; called once at load (Core/UIStrings).
function WFJ.BuildUIIndex()
  WFJ.UIIndex = WFJ.UIStrings.build({ rows = WFJ.Data.ui, english = uiEnglish, hash = uiHash })
  return WFJ.UIIndex
end

-- Builds WFJ.ObjectiveIndex from the shipped objective texts (Core/Objectives) and the quests' area texts,
-- found by the fingerprint of the live line's text, the same hash the UI index uses.
function WFJ.BuildObjectiveIndex()
  WFJ.ObjectiveIndex = WFJ.Objectives.build({
    sources = { { type = "objective", rows = WFJ.Data.objective }, { type = "area", rows = WFJ.Data.area } },
    hash = uiHash,
  })
  return WFJ.ObjectiveIndex
end

-- One step of OnLoad. Every call below runs through this: a step that raises is recorded with its name and error
-- and the load continues, so one broken surface costs that surface and nothing else (an unguarded raise would also
-- take `Slash.register`, hence `/wfj` itself, down with it). Steps run in the order written; the
-- order is load-bearing and the guard does not change it. Returns the step's first value, or nil when it failed.
-- `/wfj debug` prints WFJ.initErrors.
local function step(name, fn)
  WFJ.initErrors = WFJ.initErrors or {} -- also called from the ADDON_LOADED handler, after OnLoad has run
  local ok, value = pcall(fn)
  if ok then return value end
  WFJ.initErrors[#WFJ.initErrors + 1] = { surface = name, err = tostring(value) }
  return nil
end

function WFJ.OnLoad()
  WFJ.initErrors = {}
  step("compat", function() WFJ.Compat.init(function(name) return _G[name] end) end)

  -- `or WFJ_DB` / `or WFJ_Collector` is load-bearing, not defensive noise: these two ARE the SavedVariables
  -- globals (see the TOC). Assigning `step`'s nil would hand the client an empty global to write at logout,
  -- wiping the player's settings and the whole collected English corpus, which cannot be regenerated. A failed
  -- load keeps what was on disk and reports the failure instead.
  WFJ_DB = step("settings", function()
    return WFJ.Settings.load(WFJ_DB, WFJ.SCHEMA, WFJ.Settings.MIGRATIONS)
  end) or WFJ_DB
  step("reports", function() WFJ.Reports.load(WFJ_DB) end) -- pending fixes live in WFJ_DB.reports
  step("forget", function() -- saved tables of mechanisms the addon no longer has
    if type(WFJ_DB) == "table" then WFJ_DB.buffIdentity, WFJ_DB.timeRule = nil, nil end
  end)
  WFJ_Collector = step("collector", function() return WFJ.Collector.load(WFJ_Collector, {
    enabled = function() return WFJ.Settings.get("collector.enabled") end,
    lookup = WFJ.Lookup.get,
    player = collectorPlayer, -- the collector reads the localized class / race names
    build = function()
      local version, build = GetBuildInfo()
      if type(version) ~= "string" or build == nil then return nil end
      return version .. "." .. tostring(build)
    end,
    print = print,
  }) end) or WFJ_Collector

  step("uiindex", WFJ.BuildUIIndex)
  step("objectiveindex", WFJ.BuildObjectiveIndex)
  step("render", function() WFJ.Render.init(WFJ.Translator.new({
    enabled = function() return WFJ.State.enabled end,
    areaEnabled = WFJ.State.areaEnabled,
    modifierHeld = WFJ.Modifier.isDown,
    lookup = WFJ.Lookup.get,
    marker = function(name) return WFJ.Settings.get("marker." .. name) end,
    -- the runtime gate for unaligned entries (ADR-007). The duration renderer is UIStrings',
    -- so a `$D<k>` in a tooltip translation copies the live line's duration with the unit the
    -- client chose instead of the Japanese naming one.
    align = function(ja, lines, nameScope)
      return WFJ.Align.check(ja, lines, nameScope, spellDuration)
    end,
    -- a branch line's variants (ADR-043), the one that fits the live line
    alignVariants = function(variants, shapes, lines, nameScope)
      return WFJ.Align.checkVariants(variants, shapes, lines, nameScope, spellDuration)
    end,
    expand = expand, -- {name}/{class}/{race} per player
    -- a trusted line's `$N<k>` / `$D<k>` filled from the live text, with no gate: a quest's
    -- count is in the line the player is shown, not in the text the server sent.
    fillValues = function(ja, live) return WFJ.Align.fillValues(ja, live, spellDuration) end,
    fill = function(ja, args) return WFJ.UIIndex:fill(ja, args) end, -- UI templates get the live values
    -- the quest live check: the stale marker follows the client's English (ADR-019)
    fingerprints = function(text, masked) return WFJ.Collector.fingerprints(text, collectorPlayer(), masked) end,
  })) end)
  step("modifier", WFJ.Modifier.refresh)
  -- Tab fonts across PanelTemplates state changes, Lua-built help tooltips, and the readiness of
  -- load-on-demand Blizzard addons (their ADDON_LOADED is forwarded below; ADR-016). Before the surfaces.
  step("buttontext", WFJ.ButtonText.init)
  step("helptooltip", WFJ.HelpTooltip.init)
  step("tooltipdata", WFJ.TooltipData.init) -- tooltip-data kinds with no module of their own
  step("loadondemand", function()
    WFJ.LoadOnDemand.init(function(name)
      return type(C_AddOns) == "table" and type(C_AddOns.IsAddOnLoaded) == "function" and C_AddOns.IsAddOnLoaded(name)
    end)
  end)
  -- Surfaces: declare their client names and post-hook the client's writers (ADR-009); each feeds the API English
  -- to the Collector before rendering.
  step("questframe", function() WFJ.QuestFrame.init({ key = gossipKey }) end) -- the greeting prose is gossip
  step("questmap", WFJ.QuestMap.init) -- the quest map, popup, list and tracker
  step("tooltip", WFJ.Tooltip.init)
  step("tooltip.unit", WFJ.TooltipUnit.init) -- the unit mouseover lines the client composes
  step("gamemenu", WFJ.GameMenu.init) -- the Esc menu's buttons (quest labels ride their surfaces' hooks)
  step("gossip", function() WFJ.Gossip.init({ key = gossipKey }) end) -- the NPC talk window
  step("speech", function() WFJ.Speech.init({ key = gossipKey, expand = expand }) end) -- NPC speech
  step("itemtext", function()
    WFJ.ItemText.init({ key = keyOf("book"), -- the book / letter / plaque window
      keys = function(text) return WFJ.Collector.keys(text, collectorPlayer()) end })
  end)
  -- The always-visible windows (ADR-016). Each shows its load-time labels now (before the window's first
  -- show, so a tab measures its Japanese), hooks its writers, and registers its help-tooltip owners; the talent
  -- frame, trainer and raid roster set up when their Blizzard addon loads. The never-touch widgets are registered
  -- first (Labels refuses them on any surface); a load-on-demand window registers its own again when it sets up.
  local windows = { "Character", "Reputation", "Skills", "SpellBook", "Talents", "Trainer", "GossipChrome",
    "Merchant", "Bank", "Bags", "Mail", "Friends", "Raid", "MicroMenu", "ItemText", "PvPRank",
    "Communities", "CommunitiesFrame", "CommunitiesGuild", "ClubFinder", "ClubFinderApplicants", "CommunitiesDialogs" }
  for _, name in ipairs(windows) do
    step("forbid." .. name:lower(), function() WFJ.Labels.forbidNames(WFJ[name].NEVER_TOUCH) end)
  end
  -- Every other window the Forever client loads, one surface each (ADR-030)
  -- (pipeline/forever_addon_dispositions.txt). Its never-touch lists join this pass; its inits run after the
  -- windows below, each under its own guard.
  local forever = {
    "Professions", "Crafting", "CustomerOrders", "QuestTimer", "Trade", "Loot", "GroupLoot", "Taxi", "Tabard",
    "Petition", "GuildRegistrar", "DressUp", "CastingBar", "MapLegend", "WorldMap", "MapPins", "FlightMap",
    "BattlefieldMap", "Tracker", "AuctionHouse", "BarberShop", "BlackMarket", "Currency", "CurrencyTransfer",
    "GuildBank", "GuildControl", "GuildRename", "ItemInteraction", "ItemSocketing", "ItemUpgrade",
    "ObliterumForge", "ScrappingMachine", "Stable", "SubscriptionInterstitial", "Transmog", "Achievement",
    "Calendar", "ClickBinding", "Collections", "MountJournal", "PetJournal", "Wardrobe", "Inspect", "Legacy",
    "Statistics", "Widgets",
    "Macro", "SpellSearch", "TimeManager", "CombatText", "CooldownViewer", "DamageMeter", "DeathRecap",
    "GamepadEdit", "Gamepad", "HudLabels", "HudTips", "Minimap", "PvPMatch", "QueueStatus", "RaidManager", "UnitFrames",
    "GroupFinder", "Channels", "QuickJoin", "RecentAllies", "RecruitAFriend", "ReportFrame", "HelpFrame",
    "StatusNotices", "BNetToast", "SettingsPanel", "SettingsTutorials", "EditMode", "QuickKeybind", "ColorPicker",
    "ChatConfig", "TextToSpeech", "ChatTabs", "CombatLog", "AddonList", "ScriptErrors", "Splash", "EventTrace",
    "ChromieTime", "Alerts", "Errors", "ChatSystem", "ChatInput", "BossBanner", "Cinematic", "Subtitles",
    "CoinPickup", "CombatFeedback", "EquipmentFlyout",
    "GhostFrame", "GuildInvite", "InstanceAbandon", "InstanceDifficulty", "LootHistory", "LossOfControl",
    "MajorFactionToast", "PartyPose", "PetHappiness", "PlayerChoice", "ReadyCheck", "StackSplit", "StreamingIcon",
    "ZoneText",
    -- the tutorial popup
    "Tutorial",
    -- the StaticPopup dialogs (ADR-037)
    "Popups"
  }
  for _, name in ipairs(forever) do
    step("forbid." .. name:lower(), function() WFJ.Labels.forbidNames(WFJ[name].NEVER_TOUCH) end)
  end
  step("character", WFJ.Character.init)
  step("reputation", WFJ.Reputation.init)
  step("skills", WFJ.Skills.init)
  step("pvprank", WFJ.PvPRank.init) -- the character window's PvP rank panel
  step("spellbook", WFJ.SpellBook.init)
  step("talents", WFJ.Talents.init)
  step("trainer", WFJ.Trainer.init)
  step("gossipchrome", WFJ.GossipChrome.init)
  step("merchant", WFJ.Merchant.init)
  step("bank", WFJ.Bank.init)
  step("bags", WFJ.Bags.init)
  step("mail", WFJ.Mail.init)
  step("friends", WFJ.Friends.init)
  step("friends.tooltip", WFJ.FriendsTooltip.init) -- the friends list's own tooltip (zone / realm)
  step("communities", WFJ.Communities.init) -- the guild UI is the Communities window
  -- the rest of the Communities window (chrome, guild benefits, ClubFinder, applicants, dialogs)
  step("communities.frame", WFJ.CommunitiesFrame.init)
  step("communities.benefits", WFJ.CommunitiesGuild.init)
  step("communities.clubfinder", WFJ.ClubFinder.init)
  step("communities.applicants", WFJ.ClubFinderApplicants.init)
  step("communities.dialogs", WFJ.CommunitiesDialogs.init)
  step("raid", WFJ.Raid.init)
  step("micromenu", WFJ.MicroMenu.init)
  for _, name in ipairs(forever) do step(name:lower(), function() return WFJ[name].init() end) end
  -- menu entries (Menu.ModifyMenu per tag) and HelpTip callouts, for every window above
  step("menus", WFJ.Menus.init)
  step("menus.untagged", WFJ.MenusUntagged.init) -- the Options and Edit Mode dropdowns (no tag)
  step("helptips", WFJ.HelpTips.init)
  step("scan", WFJ.Scan.init) -- /wfj debug ui scan
  step("slash", WFJ.Slash.register)
  step("minimapbutton", function() WFJ.MinimapButton.init(WFJ_DB) end) -- the fix-report minimap button

  -- The settings pages lean on client templates; a failure there must not take /wfj down with it (three
  -- pages, one AddOns category + two subcategories). The page error keeps its own field (the settings surface
  -- reads it) as well as being recorded by the guard.
  local ok, err = pcall(function()
    WFJ.Compat.registerOptions(WFJ.Options.build())
  end)
  if not ok then
    WFJ.Options.buildError = tostring(err)
    WFJ.initErrors[#WFJ.initErrors + 1] = { surface = "options", err = tostring(err) }
  end
  -- the AddOn List's "Settings" button; retried on Blizzard_AddOnList's ADDON_LOADED
  step("addonlistbutton", WFJ.AddonListButton.install)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name, ...)
  if event == "ADDON_LOADED" then
    if name == ADDON then
      if WFJ.loaded then return end -- ADDON_LOADED stays registered for the load-on-demand addons
      WFJ.loaded = true
      WFJ.OnLoad()
      self:RegisterEvent("MODIFIER_STATE_CHANGED")
      self:RegisterEvent("PLAYER_ENTERING_WORLD")
      self:RegisterEvent("PLAYER_REGEN_DISABLED")
      self:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
      -- Guarded like the load sequence. These run the deferred setup for the talent frame, the trainer and the
      -- raid roster; a failure in the first must not stop the second from running for the same event.
      if name == "Blizzard_AddOnList" and WFJ.loaded then
        step("addonlistbutton", WFJ.AddonListButton.install) -- listed after us
      end
      if WFJ.LoadOnDemand then
        -- Blizzard_PlayerSpells / _TrainerUI / _RaidUI arrive later
        step("loadondemand." .. tostring(name), function() WFJ.LoadOnDemand.loaded(name) end)
      end
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    WFJ.Options.setCombat(true)
  elseif event == "PLAYER_REGEN_ENABLED" then
    WFJ.RevealBinding.flush() -- a modifier change made in combat
    WFJ.Options.setCombat(false)
  elseif event == "MODIFIER_STATE_CHANGED" then
    WFJ.Modifier.refresh()
  elseif event == "PLAYER_ENTERING_WORLD" then
    local isLogin, isReload = name, ... -- PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
    if isLogin or isReload then WFJ.RevealBinding.apply() end -- again once bindings are loaded
    WFJ.Modifier.refresh()
    WFJ.Collector.disclose() -- once per dump, after the chat frame is up
    -- Fonts the client refused before the bundled font file finished loading (a fresh launch): retry once a second
    -- until none is pending (the file can take 30 s or more to load), with a 10-minute safety stop.
    local function retry() return WFJ.Render.retryFonts() + WFJ.Font.retryPending() end
    local left = retry()
    if left > 0 then WFJ.Font.startProbe(WFJ.Compat.resolve("UIParent")) end -- make the client load the font file
    WFJ.fontRetry = WFJ.fontRetry or { at = GetTime(), tries = 0, left = left, timer = type(C_Timer) == "table" }
    if left > 0 and type(C_Timer) == "table" and not WFJ.fontTicker then
      WFJ.fontRetry.running = true
      WFJ.fontTicker = C_Timer.NewTicker(1, function(ticker)
        local state = WFJ.fontRetry
        state.tries = state.tries + 1
        state.left = retry()
        if state.left == 0 or state.tries >= 600 then
          WFJ.Font.stopProbe()
          ticker:Cancel()
          WFJ.fontTicker = nil
          state.running = false
        end
      end)
    end
  end
end)
