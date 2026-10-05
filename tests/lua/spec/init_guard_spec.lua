-- One surface's init raising must cost that surface and nothing else.
--
-- The failure this pins is the one the Forever client produced: Main.lua ran ~20 init calls in
-- one unguarded sequence, Tooltip.init was the third, and when it threw, the other seventeen surfaces (and
-- Slash.register, so `/wfj` itself) never ran. The guard must keep the order and keep going.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

-- { guard name, namespace module }, in the order Main initialises them. The order is load-bearing (ButtonText /
-- HelpTooltip / LoadOnDemand before the surfaces; the never-touch registration before each window) and the guard
-- must not reorder it.
local ORDER = {
  { "buttontext", "ButtonText" }, { "helptooltip", "HelpTooltip" }, { "loadondemand", "LoadOnDemand" },
  { "questframe", "QuestFrame" }, { "questmap", "QuestMap" },
  { "tooltip", "Tooltip" },
  { "gamemenu", "GameMenu" }, { "gossip", "Gossip" },
  { "itemtext", "ItemText" },
  { "character", "Character" }, { "reputation", "Reputation" }, { "skills", "Skills" },
  { "pvprank", "PvPRank" },
  { "spellbook", "SpellBook" }, { "talents", "Talents" }, { "trainer", "Trainer" },
  { "gossipchrome", "GossipChrome" }, { "merchant", "Merchant" }, { "bank", "Bank" }, { "bags", "Bags" },
  { "mail", "Mail" }, { "friends", "Friends" }, { "friends.tooltip", "FriendsTooltip" },
  { "communities", "Communities" },
  -- the rest of the Communities window
  { "communities.frame", "CommunitiesFrame" }, { "communities.benefits", "CommunitiesGuild" },
  { "communities.clubfinder", "ClubFinder" }, { "communities.applicants", "ClubFinderApplicants" },
  { "communities.dialogs", "CommunitiesDialogs" },
  { "raid", "Raid" },
  { "micromenu", "MicroMenu" },
  -- every other Forever window >>>
  { "professions", "Professions" }, { "crafting", "Crafting" }, { "customerorders", "CustomerOrders" },
  { "questtimer", "QuestTimer" }, { "trade", "Trade" }, { "loot", "Loot" }, { "grouploot", "GroupLoot" }, { "taxi",
  "Taxi" }, { "tabard", "Tabard" }, { "petition", "Petition" }, { "guildregistrar", "GuildRegistrar" },
  { "dressup", "DressUp" }, { "castingbar", "CastingBar" }, { "maplegend", "MapLegend" }, { "worldmap",
  "WorldMap" }, { "mappins", "MapPins" }, { "flightmap", "FlightMap" }, { "battlefieldmap", "BattlefieldMap" },
  { "tracker", "Tracker" }, { "auctionhouse", "AuctionHouse" }, { "barbershop", "BarberShop" }, { "blackmarket",
  "BlackMarket" }, { "currency", "Currency" }, { "currencytransfer", "CurrencyTransfer" }, { "guildbank",
  "GuildBank" }, { "guildcontrol", "GuildControl" }, { "guildrename", "GuildRename" }, { "iteminteraction",
  "ItemInteraction" }, { "itemsocketing", "ItemSocketing" }, { "itemupgrade", "ItemUpgrade" }, { "obliterumforge",
  "ObliterumForge" }, { "scrappingmachine", "ScrappingMachine" }, { "stable", "Stable" },
  { "subscriptioninterstitial", "SubscriptionInterstitial" }, { "transmog", "Transmog" }, { "achievement",
  "Achievement" }, { "calendar", "Calendar" }, { "clickbinding", "ClickBinding" }, { "collections",
  "Collections" }, { "mountjournal", "MountJournal" }, { "petjournal", "PetJournal" }, { "wardrobe", "Wardrobe" },
  { "inspect", "Inspect" }, { "legacy", "Legacy" },
  { "statistics", "Statistics" }, { "widgets", "Widgets" }, { "macro", "Macro" }, { "spellsearch", "SpellSearch" },
  { "timemanager", "TimeManager" }, { "combattext", "CombatText" }, { "cooldownviewer", "CooldownViewer" },
  { "damagemeter", "DamageMeter" }, { "deathrecap", "DeathRecap" }, { "gamepadedit", "GamepadEdit" },
  { "hudlabels", "HudLabels" }, { "hudtips", "HudTips" }, { "minimap", "Minimap" }, { "pvpmatch", "PvPMatch" },
  { "queuestatus", "QueueStatus" }, { "raidmanager", "RaidManager" }, { "unitframes", "UnitFrames" },
  { "groupfinder", "GroupFinder" }, { "channels", "Channels" }, { "quickjoin", "QuickJoin" }, { "recentallies",
  "RecentAllies" }, { "recruitafriend", "RecruitAFriend" }, { "reportframe", "ReportFrame" }, { "helpframe",
  "HelpFrame" }, { "statusnotices", "StatusNotices" }, { "bnettoast", "BNetToast" }, { "settingspanel",
  "SettingsPanel" }, { "settingstutorials", "SettingsTutorials" }, { "editmode", "EditMode" }, { "quickkeybind",
  "QuickKeybind" }, { "colorpicker", "ColorPicker" }, { "chatconfig", "ChatConfig" }, { "texttospeech",
  "TextToSpeech" }, { "chattabs", "ChatTabs" }, { "combatlog", "CombatLog" }, { "addonlist", "AddonList" },
  { "scripterrors", "ScriptErrors" }, { "splash", "Splash" }, { "eventtrace", "EventTrace" }, { "chromietime",
  "ChromieTime" }, { "alerts", "Alerts" }, { "errors", "Errors" }, { "chatsystem", "ChatSystem" },
  { "bossbanner", "BossBanner" }, { "cinematic", "Cinematic" }, { "subtitles", "Subtitles" },
  { "coinpickup", "CoinPickup" }, { "combatfeedback", "CombatFeedback" }, { "equipmentflyout", "EquipmentFlyout" },
  { "ghostframe", "GhostFrame" }, { "guildinvite", "GuildInvite" }, { "instanceabandon", "InstanceAbandon" },
  { "instancedifficulty", "InstanceDifficulty" }, { "loothistory", "LootHistory" }, { "lossofcontrol",
  "LossOfControl" }, { "majorfactiontoast", "MajorFactionToast" }, { "partypose", "PartyPose" }, { "pethappiness",
  "PetHappiness" }, { "playerchoice", "PlayerChoice" }, { "readycheck", "ReadyCheck" }, { "stacksplit",
  "StackSplit" }, { "streamingicon", "StreamingIcon" }, { "zonetext", "ZoneText" },
  { "speech", "Speech" }, -- after ChatSystem, which it rewrites lines through
  -- <<<
  { "menus", "Menus" }, { "helptips", "HelpTips" },
  { "scan", "Scan" },
}

describe("Main guards every surface init", function()
  local WFJ

  local function fresh()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI(); Stub.installItemTextAPI()
    return Loader.load("WoWForeverJapanese")
  end

  -- Loads the addon, optionally replacing named modules' `init` with one that raises, then fires ADDON_LOADED.
  local function load(broken)
    WFJ = fresh()
    for _, module in ipairs(broken or {}) do
      WFJ[module].init = function() error("stub client has no " .. module, 0) end
    end
    Stub.prints = {}
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    return WFJ
  end

  local function names(errors)
    local out = {}
    for i, e in ipairs(errors or {}) do out[i] = e.surface end
    return out
  end

  it("records nothing on a clean load", function()
    load()
    assert.are.same({}, names(WFJ.initErrors))
  end)

  it("runs every surface, in the order Main documents", function()
    WFJ = fresh()
    local seen = {}
    for _, row in ipairs(ORDER) do
      local module, original = row[2], WFJ[row[2]].init
      WFJ[module].init = function(...)
        seen[#seen + 1] = row[1]
        return original(...)
      end
    end
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    local expected = {}
    for i, row in ipairs(ORDER) do expected[i] = row[1] end
    assert.are.same(expected, seen)
    assert.are.same({}, names(WFJ.initErrors))
  end)

  -- ADR-025 claims the guard does not reorder the sequence, and names one property as load-bearing:
  -- `Labels.forbidNames` runs for every window BEFORE any window's `init`. Break that and the never-touch
  -- registration silently stops covering widgets that are then written over.
  it("registers every window's never-touch list before any window initialises (ADR-025)", function()
    WFJ = fresh()
    local seq = {}
    local forbidNames = WFJ.Labels.forbidNames
    WFJ.Labels.forbidNames = function(list)
      seq[#seq + 1] = "forbid"
      return forbidNames(list)
    end
    local WINDOWS = { "Character", "Reputation", "Skills", "SpellBook", "Talents", "Trainer",
      "GossipChrome", "Merchant", "Bank", "Bags", "Mail", "Friends", "Raid", "MicroMenu" }
    for _, module in ipairs(WINDOWS) do
      local original = WFJ[module].init
      WFJ[module].init = function(...) seq[#seq + 1] = "init"; return original(...) end
    end
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    local firstInit, lastForbid
    for i, kind in ipairs(seq) do
      if kind == "forbid" then lastForbid = i elseif not firstInit then firstInit = i end
    end
    assert.is_truthy(lastForbid, "no forbidNames call was made")
    assert.is_truthy(firstInit, "no window init was made")
    assert.is_true(lastForbid < firstInit,
      "a window initialised before its never-touch list was registered")
    assert.are.same({}, names(WFJ.initErrors))
  end)

  it("runs the core bootstrap before any surface, in order", function()
    WFJ = fresh()
    local seen = {}
    local hooks = {
      { "settings", WFJ.Settings, "load" }, { "collector", WFJ.Collector, "load" },
      { "render", WFJ.Render, "init" }, { "buttontext", WFJ.ButtonText, "init" },
      { "questframe", WFJ.QuestFrame, "init" },
    }
    for _, h in ipairs(hooks) do
      local label, tbl, key = h[1], h[2], h[3]
      local original = tbl[key]
      tbl[key] = function(...) seen[#seen + 1] = label; return original(...) end
    end
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    assert.are.same({ "settings", "collector", "render", "buttontext", "questframe" }, seen)
  end)

  it("a throwing Tooltip.init costs the tooltip and nothing after it (the Forever failure)", function()
    load({ "Tooltip" })
    assert.are.same({ "tooltip" }, names(WFJ.initErrors))
    assert.is_truthy(WFJ.initErrors[1].err:find("no Tooltip", 1, true))
    -- Slash.register is the last surface in the sequence and the one the Forever failure actually cost
    assert.is_function(SlashCmdList.WFJ)
  end)

  it("keeps /wfj answering when a late surface throws", function()
    load({ "Communities" })
    assert.are.same({ "communities" }, names(WFJ.initErrors))
    assert.is_function(SlashCmdList.WFJ)
  end)

  it("records every failure, not just the first, in order", function()
    load({ "Tooltip", "Mail" })
    assert.are.same({ "tooltip", "mail" }, names(WFJ.initErrors))
    assert.is_function(SlashCmdList.WFJ)
  end)

  it("a surface that throws does not stop the ones after it from initialising", function()
    WFJ = fresh()
    WFJ.Tooltip.init = function() error("no tooltip", 0) end
    local ran = {}
    for _, module in ipairs({ "GameMenu", "Gossip", "ItemText", "Trainer", "MicroMenu" }) do
      local original = WFJ[module].init
      WFJ[module].init = function(...) ran[#ran + 1] = module; return original(...) end
    end
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    assert.are.same({ "GameMenu", "Gossip", "ItemText", "Trainer", "MicroMenu" }, ran)
  end)

  -- The guard turned a loud abort into a recorded failure. For the two steps that ARE the SavedVariables
  -- globals that is dangerous, not safe: assigning the guard's nil would hand the client an empty global to
  -- write at logout and wipe the player's settings and their collected English. A failed load must keep what
  -- was on disk.
  it("keeps WFJ_DB and WFJ_Collector when their load step fails (SavedVariables are not wiped)", function()
    WFJ = fresh()
    _G.WFJ_DB = { schema = 1, marker = "on disk" }
    _G.WFJ_Collector = { quest = { [1] = "harvested English" } }
    local db, collector = _G.WFJ_DB, _G.WFJ_Collector
    WFJ.Settings.load = function() error("no settings on this client", 0) end
    WFJ.Collector.load = function() error("no collector on this client", 0) end
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    assert.are.equal(db, _G.WFJ_DB)
    assert.are.equal(collector, _G.WFJ_Collector)
    assert.are.equal("on disk", _G.WFJ_DB.marker)
    assert.are.same({ "settings", "collector" }, names(WFJ.initErrors))
    assert.is_function(SlashCmdList.WFJ) -- and the rest of the addon still came up
  end)

  it("/wfj debug prints the failed surface and its error, and 'none' when clean", function()
    load({ "Trainer" })
    Stub.prints = {}
    SlashCmdList.WFJ("debug")
    local printed = table.concat(Stub.prints, "\n")
    assert.is_truthy(printed:find("surface errors:", 1, true))
    assert.is_truthy(printed:find("trainer", 1, true))
    assert.is_truthy(printed:find("no Trainer", 1, true))

    load()
    Stub.prints = {}
    SlashCmdList.WFJ("debug")
    assert.is_truthy(table.concat(Stub.prints, "\n"):find("surface errors: none", 1, true))
  end)
end)

-- Found in game, not by the probe: a client name can resolve to an object that is not a text widget;
-- Labels.show called GetText on it and raised, which cost the whole raid surface on the Forever client
-- ("surface errors: raid: UI/Labels.lua:62: attempt to call a nil value"). Labels.widget is the
-- one place that decides what counts as a widget, so it is the one place that has to refuse.
describe("Labels refuses a resolved name that is not a text widget", function()
  local H2 = require("tests.lua.spec.helpers")
  local Stub2 = require("tests.lua.spec.wow_stub")
  local Loader2 = require("tests.lua.spec.loader")
  local WFJ

  before_each(function()
    Stub2.install(H2.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub2.installQuestAPI(); Stub2.installTooltipAPI(); Stub2.installGossipAPI(); Stub2.installItemTextAPI()
    WFJ = Loader2.load("WoWForeverJapanese")
    Stub2.fireAll("ADDON_LOADED", "WoWForeverJapanese")
  end)

  it("returns nil for a table with no GetText instead of handing it on", function()
    assert.is_nil(WFJ.Labels.widget({}))
    assert.is_nil(WFJ.Labels.widget({ SetText = function() end }))   -- writable but not readable
    assert.is_nil(WFJ.Labels.widget("not a table"))
    assert.is_nil(WFJ.Labels.widget(nil))
  end)

  it("still accepts a real font string", function()
    local fs = Stub2.namedFontString("SomeLabel", "Hello", "Fonts\\FRIZQT__.TTF", 12, "")
    assert.are.equal(fs, WFJ.Labels.widget(fs))
  end)

  it("show() drops the record instead of raising", function()
    assert.has_no.errors(function()
      assert.are.equal(0, WFJ.Labels.show("raid", "ui.thing", { SetText = function() end }))
    end)
  end)
end)
