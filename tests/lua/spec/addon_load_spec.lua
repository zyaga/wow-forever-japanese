local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

-- Hand-written files in dependency order; the generated block (Meta, Vectors, shards) sits between HEAD and TAIL.
local HEAD = { "Core/Const.lua", "Core/Compat.lua", "Core/Normalize.lua", "Core/Hash.lua", "Core/Data.lua" }
local TAIL = {
  "Core/Lookup.lua", "Core/Readings.lua", "Core/Glosses.lua", "Core/Align.lua", "Core/State.lua", "Core/Settings.lua",
  "Core/Modifier.lua",
  "Core/Placeholders.lua", "Core/Translator.lua", "Core/UIStringKeys.lua",
  "Core/UIStrings.lua", "Core/Objectives.lua", "Core/SurfaceState.lua",
  "Core/Collector.lua",
  "Core/RecentLines.lua", "Core/Reports.lua", "Core/ReportText.lua", -- the fix reports
  "UI/Font.lua", "UI/ReadingPopup.lua", "UI/Readings.lua", "UI/Render.lua",
  "UI/ButtonText.lua", "UI/Labels.lua", "UI/HtmlText.lua", "UI/LoadOnDemand.lua",
  "UI/HelpTooltip.lua",
  -- shared helpers (ADR-030)
  "UI/SettingsKeys.lua", "UI/LabelTree.lua", "UI/TooltipLines.lua",
  -- the always-visible windows
  "UI/Character.lua", "UI/Reputation.lua", "UI/Skills.lua", "UI/PvPRank.lua",
  "UI/SpellBook.lua", "UI/Talents.lua",
  "UI/Trainer.lua", "UI/GossipChrome.lua", "UI/Merchant.lua", "UI/Bank.lua", "UI/Bags.lua", "UI/Mail.lua",
  "UI/Friends.lua", "UI/FriendsTooltip.lua", "UI/Communities.lua",
  -- the rest of the Communities window
  "UI/CommunitiesKit.lua", "UI/CommunitiesFrame.lua", "UI/CommunitiesGuild.lua", "UI/ClubFinder.lua",
  "UI/ClubFinderApplicants.lua", "UI/CommunitiesDialogs.lua",
  "UI/Raid.lua", "UI/MicroMenu.lua", "UI/MenusUnit.lua", "UI/Gamepad.lua", "UI/Menus.lua",
  "UI/MenusTags.lua", "UI/MenusUntagged.lua", "UI/HelpTips.lua",
  -- Gamepad loads before MenusUntagged, which reads its menu keys at load
  "UI/QuestFrame.lua", "UI/QuestMap.lua", "UI/Tooltip.lua", "UI/TooltipUnit.lua", "UI/GameMenu.lua",
  "UI/Gossip.lua",
  "UI/ItemText.lua", -- every other Forever window (ADR-030)
  "UI/Professions.lua", "UI/Crafting.lua", "UI/CustomerOrders.lua", "UI/QuestTimer.lua", "UI/Trade.lua",
  "UI/Loot.lua", "UI/GroupLoot.lua", "UI/Taxi.lua", "UI/Tabard.lua", "UI/Petition.lua", "UI/GuildRegistrar.lua",
  "UI/DressUp.lua", "UI/CastingBar.lua", "UI/MapLegend.lua", "UI/WorldMap.lua", "UI/MapPins.lua",
  "UI/FlightMap.lua", "UI/BattlefieldMap.lua", "UI/Tracker.lua", "UI/AuctionHouse.lua", "UI/BarberShop.lua",
  "UI/BlackMarket.lua", "UI/Currency.lua", "UI/CurrencyTransfer.lua", "UI/GuildBank.lua", "UI/GuildControl.lua",
  "UI/GuildRename.lua", "UI/ItemInteraction.lua", "UI/ItemSocketing.lua", "UI/ItemUpgrade.lua",
  "UI/ObliterumForge.lua", "UI/ScrappingMachine.lua", "UI/Stable.lua", "UI/SubscriptionInterstitial.lua",
  "UI/Transmog.lua", "UI/Achievement.lua", "UI/Calendar.lua", "UI/ClickBinding.lua", "UI/Collections.lua",
  "UI/MountJournal.lua", "UI/PetJournal.lua", "UI/Wardrobe.lua", "UI/Inspect.lua", "UI/Legacy.lua",
  "UI/Statistics.lua", "UI/Widgets.lua",
  "UI/Macro.lua",
  "UI/SpellSearch.lua", "UI/TimeManager.lua", "UI/CombatText.lua", "UI/CooldownViewer.lua", "UI/DamageMeter.lua",
  "UI/DeathRecap.lua", "UI/GamepadEdit.lua", "UI/HudLabels.lua", "UI/HudTips.lua", "UI/Minimap.lua",
  "UI/PvPMatch.lua", "UI/QueueStatus.lua", "UI/RaidManager.lua", "UI/UnitFrames.lua", "UI/GroupFinder.lua",
  "UI/Channels.lua", "UI/QuickJoin.lua", "UI/RecentAllies.lua", "UI/RecruitAFriend.lua", "UI/ReportFrame.lua",
  "UI/HelpFrame.lua", "UI/StatusNotices.lua", "UI/BNetToast.lua", "UI/SettingsPanel.lua",
  "UI/SettingsTutorials.lua", "UI/EditMode.lua", "UI/QuickKeybind.lua", "UI/ColorPicker.lua", "UI/ChatConfig.lua",
  "UI/TextToSpeech.lua", "UI/ChatTabs.lua", "UI/CombatLog.lua", "UI/AddonList.lua", "UI/ScriptErrors.lua",
  "UI/Splash.lua", "UI/EventTrace.lua", "UI/ChromieTime.lua", "UI/Alerts.lua", "UI/Errors.lua", "UI/ChatSystem.lua",
  "UI/Speech.lua",
  "UI/BossBanner.lua",
  "UI/Cinematic.lua", "UI/Subtitles.lua",
  "UI/CoinPickup.lua", "UI/CombatFeedback.lua", "UI/EquipmentFlyout.lua", "UI/GhostFrame.lua",
  "UI/GuildInvite.lua", "UI/InstanceAbandon.lua", "UI/InstanceDifficulty.lua", "UI/LootHistory.lua",
  "UI/LossOfControl.lua", "UI/MajorFactionToast.lua", "UI/PartyPose.lua", "UI/PetHappiness.lua",
  "UI/PlayerChoice.lua", "UI/ReadyCheck.lua", "UI/StackSplit.lua", "UI/StreamingIcon.lua", "UI/ZoneText.lua",
  "UI/Tutorial.lua", -- the tutorial popup
  "UI/Popups.lua",
  "UI/Scan.lua",
  "UI/OptionsText.lua", "UI/OptionsWidgets.lua", "UI/KeyCapture.lua", "UI/FixWindow.lua", "UI/MinimapButton.lua",
  "UI/RevealBinding.lua",
  "UI/AddonListButton.lua",
  "UI/Options.lua", "UI/Slash.lua", "Main.lua", -- the settings pages' modules
}
-- the window modules declare the names of windows this stub does not build (and, in the client, windows that
-- load on demand); the unresolved checks below read only the other namespaces.
local WINDOW_NAMESPACES = { "character", "reputation", "skills", "spellbook", "talents", "trainer",
  "gossip.chrome", "merchant", "bank", "bags", "mail", "friends", "raid", "help",
  -- the camelot surfaces declare names only the Forever client defines
  "pvprank", "communities", "questmap",
  "professions", "crafting", "customerorders", "questtimer", "trade", "loot", "grouploot", "taxi",
  "tabard", "petition", "guildregistrar", "dressup", "castingbar", "maplegend", "worldmap", "mappins", "flightmap",
  "battlefieldmap", "tracker", "auctionhouse", "barbershop", "blackmarket", "currency", "currencytransfer",
  "guildbank", "guildcontrol", "guildrename", "iteminteraction", "itemsocketing", "itemupgrade", "obliterumforge",
  "scrappingmachine", "stable", "subscriptioninterstitial", "transmog", "achievement", "calendar", "clickbinding",
  "collections", "mountjournal", "petjournal", "wardrobe", "inspect", "legacy", "statistics", "widgets", "macro",
  "spellsearch",
  "timemanager", "combattext", "cooldownviewer", "damagemeter", "deathrecap", "gamepadedit",
  "gamepad", "hudlabels", "help",
  "help.hudtips", "help.minimap", "pvpmatch", "queuestatus", "raidmanager", "unitframes", "groupfinder",
  "channels", "quickjoin", "recentallies", "recruitafriend", "reportframe", "helpframe", "statusnotices",
  "bnettoast", "settingspanel", "settingstutorials", "editmode", "quickkeybind", "colorpicker", "chatconfig",
  "texttospeech", "chattabs", "combatlog", "addonlist", "scripterrors", "splash", "eventtrace", "chromietime",
  "alerts", "errors", "chatsystem", "speech", "bossbanner", "cinematic", "coinpickup", "combatfeedback",
  "equipmentflyout",
  "ghostframe",
  "guildinvite", "instanceabandon", "instancedifficulty", "loothistory", "lossofcontrol", "majorfactiontoast",
  "partypose", "pethappiness", "playerchoice", "readycheck", "stacksplit", "streamingicon", "zonetext",
  "popups", "tutorial" }
local function outsideWindows(list)
  local out = {}
  for _, name in ipairs(list) do
    local window = false
    for _, w in ipairs(WINDOW_NAMESPACES) do if name:sub(1, #w + 1) == w .. "." then window = true end end
    if not window then out[#out + 1] = name end
  end
  return out
end
local TOC_ORDER = {}
for _, f in ipairs(HEAD) do TOC_ORDER[#TOC_ORDER + 1] = f end
for _, f in ipairs(TAIL) do TOC_ORDER[#TOC_ORDER + 1] = f end

describe("addon loads in TOC order and answers /wfj version", function()
  local meta, WFJ

  setup(function()
    meta = Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI(); Stub.installItemTextAPI()
    WFJ = Loader.load("WoWForeverJapanese")
  end)

  it("lists the files in dependency order, generated block between Data and Lookup", function()
    local files = Loader.tocFiles(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    for i, f in ipairs(HEAD) do assert.are.equal(f, files[i]) end
    for i, f in ipairs(TAIL) do assert.are.equal(f, files[#files - #TAIL + i]) end
    local generated = {}
    for i = #HEAD + 1, #files - #TAIL do generated[#generated + 1] = files[i] end
    assert.are.equal("Data/Meta.lua", generated[1])
    assert.are.equal("Data/Vectors.lua", generated[2])
    assert.is_true(#generated > 2)
    for _, f in ipairs(generated) do assert.is_truthy(f:find("^Data/"), f) end
  end)

  it("exposes the namespace after load", function()
    assert.are.equal("WoWForeverJapanese", WFJ.ADDON)
    assert.are.equal(meta.Version, WFJ.VERSION)
    assert.is_function(WFJ.Normalize.v1)
    assert.is_function(WFJ.Hash.key)
    for _, m in ipairs({ "Compat", "Data", "Lookup", "Align", "Tooltip", "State", "Settings", "Modifier", "Translator",
      "SurfaceState", "Collector", "UIStrings", "ButtonText", "Labels", "GameMenu", "Gossip", "Scan",
      "Font", "Render", "QuestFrame", "Options", "Slash", "LoadOnDemand", "HelpTooltip", "Character",
      "Reputation", "Skills", "SpellBook", "Talents", "Trainer", "GossipChrome", "Merchant", "Bank", "Bags",
      "Mail", "Friends", "Raid", "MicroMenu", "ItemText",
      "OptionsText", "OptionsWidgets", "KeyCapture", "RevealBinding", "AddonListButton" }) do
      assert.is_table(WFJ[m], m)
    end
  end)

  it("builds the UI index on load from the client's globals and hooks the game menu", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI(); Stub.installItemTextAPI()
    _G.ACCEPT = "Accept"
    _G.QUEST_LOG = "Quest Log (changed)" -- not the English the Japanese was drafted from
    local ns = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    _G.ACCEPT, _G.QUEST_LOG = nil, nil
    local c = ns.UIIndex.counts
    assert.are.equal(ns.Data.count("ui"), c.shipped)
    assert.are.equal(2, c.indexed) -- ACCEPT, and ITEM_SPELL_TRIGGER_ONEQUIP ("Equip:", set by the tooltip stub)
    -- QUEST_LOG above, and the gossip stub's own GOSSIP_OPTION_PREPEND / QUEST_PREPEND globals, whose
    -- placeholder English is not the client's: three keys the index refuses to answer for
    assert.are.equal(3, c.mismatched)
    assert.are.equal("ACCEPT", (ns.UIIndex:match("Accept")))
    assert.are.equal(1, #(Stub.hooks["GameMenuFrame:InitButtons"] or {}))
    meta = Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI(); Stub.installItemTextAPI()
    WFJ = Loader.load("WoWForeverJapanese")
  end)

  it("registers the slash command on ADDON_LOADED for its own name only", function()
    Stub.fireAll("ADDON_LOADED", "SomeOtherAddon")
    assert.is_nil(SlashCmdList.WFJ)
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    assert.is_function(SlashCmdList.WFJ)
    assert.are.equal("/wfj", SLASH_WFJ1)
  end)

  it("creates WFJ_DB at the current schema and registers the options panel on load", function()
    assert.is_table(WFJ_DB)
    assert.are.equal(WFJ.SCHEMA, WFJ_DB.schema)
    assert.are.equal("RegisterCanvasLayoutCategory", Stub.settingsCalls[1][1])
    assert.are.equal("WoW Forever Japanese", Stub.settingsCalls[1][3])
  end)

  it("installs the quest surfaces on load: writer post-hooks and OnHide releases", function()
    assert.are.equal(1, #(Stub.hooks.QuestInfo_Display or {}))
    assert.is_nil(Stub.hooks.QuestFrameProgressPanel_OnShow) -- XML-bound: hooked as a frame script instead
    assert.is_function(QuestFrameProgressPanel.scripts.OnShow)
    Stub.quest = { id = 2, title = "T", description = "", objectives = "", progress = "P", completion = "" }
    QuestFrameProgressPanel:Show() -- the frame script is wrapped: our hook captures the progress fields
    assert.is_table(WFJ.SurfaceState.get("questframe.progress", "progress"))
    WFJ.Render.release("questframe.progress")
    assert.is_function(QuestFrame.scripts.OnHide)
    assert.are.same({}, outsideWindows(WFJ.Compat.unresolved()))
    -- the gossip surface subscribes to the ScrollBox and post-hooks Update; the greeting writer by name
    assert.are.equal(1, #(Stub.hooks["GossipFrame:Update"] or {}))
    -- two subscribers: the option rows (UI/Gossip) and the grey-quest suffix (UI/GossipChrome)
    assert.are.equal(2, #GossipFrame.GreetingPanel.ScrollBox.callbacks.OnInitializedFrame)
    assert.are.equal(1, #GossipFrame.GreetingPanel.ScrollBox.callbacks.OnReleasedFrame)
    assert.is_function(GossipFrame.scripts.OnHide)
    assert.are.equal(1, #(Stub.hooks.QuestFrameGreetingPanel_OnShow or {}))
    -- the book window: a SetText post-hook on the SimpleHTML page, the XML-bound OnEvent and OnHide wrapped
    assert.are.equal(1, #(Stub.hooks["ItemTextPageText:SetText"] or {}))
    assert.is_function(_G.ItemTextFrame.scripts.OnEvent)
    assert.is_function(_G.ItemTextFrame.scripts.OnHide)
  end)

  it("a missing writer on the client does not break load and shows in Compat.unresolved", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI(); Stub.installItemTextAPI()
    _G.QuestInfo_Display = nil
    local ns = Loader.load("WoWForeverJapanese")
    assert.has_no.errors(function() Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese") end)
    assert.are.same({ "questframe.display" }, outsideWindows(ns.Compat.unresolved()))
    -- restore the shared state the later cases read
    meta = Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI(); Stub.installItemTextAPI()
    WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
  end)

  it("fonts refused at load are retried after PLAYER_ENTERING_WORLD until none is pending", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI(); Stub.installItemTextAPI()
    local ticks = {}
    _G.C_Timer = { NewTicker = function(_, fn)
      local t = { cancelled = false }
      function t.Cancel() t.cancelled = true end
      ticks[#ticks + 1] = { fn = fn, t = t }
      return t
    end }
    CreateFrame("Frame", "UIParent") -- the client always has it; the probe hangs off it
    local ns = Loader.load("WoWForeverJapanese")
    Stub.fontSetFails = true -- a fresh launch: the bundled font file is not loaded yet
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    assert.is_true(ns.Render.pendingFonts() > 0 or ns.Font.retryPending() > 0)
    Stub.fireAll("PLAYER_ENTERING_WORLD", true, false)
    assert.are.equal(1, #ticks)
    local probe = ns.Font.startProbe() -- started by PLAYER_ENTERING_WORLD: one visible character asking for our font
    assert.is_table(probe)
    assert.are.equal("あ", probe:GetText())
    ticks[1].fn(ticks[1].t)
    assert.is_false(ticks[1].t.cancelled) -- still refused
    Stub.fontSetFails = false
    ticks[1].fn(ticks[1].t)
    assert.is_true(ticks[1].t.cancelled)
    assert.are.same({ ns.Font.PATH, 8, "" }, { probe:GetFont() })
    assert.is_false(ns.Font.stopProbe()) -- already stopped when nothing was pending
    assert.are.equal(0, ns.Render.pendingFonts())
    assert.are.equal(0, ns.Font.retryPending())
    Stub.fireAll("PLAYER_ENTERING_WORLD", false, false)
    assert.are.equal(1, #ticks) -- nothing pending: no second ticker
    _G.C_Timer = nil
  end)

  it("creates WFJ_Collector on load and discloses once, on the first PLAYER_ENTERING_WORLD", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI(); Stub.installItemTextAPI()
    Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    assert.are.same({ version = 1, disclosed = false, builds = {}, bytes = 0, capped = false, entries = {} },
      WFJ_Collector)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI(); Stub.installItemTextAPI()
    Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    Stub.prints = {}
    Stub.fireAll("PLAYER_ENTERING_WORLD")
    assert.are.equal(2, #Stub.prints)
    assert.is_truthy(Stub.prints[2]:find("/wfj collector off", 1, true))
    assert.is_true(WFJ_Collector.disclosed)
    Stub.fireAll("PLAYER_ENTERING_WORLD")
    assert.are.equal(2, #Stub.prints)
    -- next session: the saved table is already disclosed
    local saved = WFJ_Collector
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI(); Stub.installItemTextAPI()
    _G.WFJ_Collector = saved
    Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    Stub.prints = {}
    Stub.fireAll("PLAYER_ENTERING_WORLD")
    assert.are.equal(0, #Stub.prints)
    -- collector off before first run: nothing printed, not marked disclosed
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI(); Stub.installItemTextAPI()
    _G.WFJ_DB = { schema = 1, settings = { ["collector.enabled"] = false } }
    Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    Stub.prints = {}
    Stub.fireAll("PLAYER_ENTERING_WORLD")
    assert.are.equal(0, #Stub.prints)
    assert.is_false(WFJ_Collector.disclosed)
    -- restore the shared state the later cases read
    meta = Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI(); Stub.installItemTextAPI()
    WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
  end)

  it("routes MODIFIER_STATE_CHANGED and PLAYER_ENTERING_WORLD to Modifier.refresh", function()
    Stub.keys.alt = true
    Stub.fireAll("MODIFIER_STATE_CHANGED", "LALT", 1)
    assert.is_true(WFJ.State.modifierHeld)
    Stub.keys.alt = false
    Stub.fireAll("PLAYER_ENTERING_WORLD")
    assert.is_false(WFJ.State.modifierHeld)
  end)

  it("wires Lookup into the Translator: a trusted quest title renders through Render.show", function()
    -- quest 7 (quest 2's title is the item name "Sharptalon's Claw", English letters by rule)
    local fs = Stub.fontString("Kobold Camp Cleanup", "Fonts\\FRIZQT__.TTF", 12, "")
    WFJ.Render.show("quest", "title", fs, "Kobold Camp Cleanup", "quests", "quest.title", 7)
    assert.are.equal("Koboldキャンプの掃討", fs:GetText())
    WFJ.Render.release("quest")
    assert.are.equal("Kobold Camp Cleanup", fs:GetText())
    local itemId = next(WFJ.Data.item)
    local action, payload = WFJ.Translator.new({
      enabled = function() return true end, areaEnabled = function() return true end,
      modifierHeld = function() return false end, lookup = WFJ.Lookup.get, marker = function() return false end,
    }).resolve("items", "item", itemId)
    assert.are.equal("none", action)
    assert.are.equal("unaligned_ungated", payload.reason)
  end)

  it("Main's expand fills a real shipped line from the client's unit functions", function()
    -- quest 791 completion: "実にいいね、{name}。あらゆる本物の{class}は…\n\nHordeの名の下に…" (the two-paragraph variant
    -- ships: completeness is checked against VMaNGOS's two-paragraph reward text)
    local fs = Stub.fontString("Good.", "Fonts\\FRIZQT__.TTF", 12, "")
    WFJ.Render.show("quest", "completion", fs, "Good.", "quests", "quest.completion", 791)
    assert.are.equal("実にいいね、Reyn。あらゆる本物のハンターは戦場でのこのバッグの使い方を知ってるものさ。\n\nHordeの名の下に戦わんとするお前の意志に敬礼！", fs:GetText())
    WFJ.Render.release("quest")
    assert.are.equal("Good.", fs:GetText())
  end)

  it("a client without UnitSex / UnitClass still renders: tokens stay literal, token-free text is untouched",
  function()
    local sex, class = _G.UnitSex, _G.UnitClass
    _G.UnitSex, _G.UnitClass = nil, nil
    local title = Stub.fontString("Kobold Camp Cleanup", "Fonts\\FRIZQT__.TTF", 12, "")
    assert.has_no.errors(function()
      WFJ.Render.show("quest", "title", title, "Kobold Camp Cleanup", "quests", "quest.title", 7)
    end)
    assert.are.equal("Koboldキャンプの掃討", title:GetText())
    local fs = Stub.fontString("Good.", "Fonts\\FRIZQT__.TTF", 12, "")
    assert.has_no.errors(function()
      WFJ.Render.show("quest", "completion", fs, "Good.", "quests", "quest.completion", 791)
    end)
    assert.are.equal("実にいいね、Reyn。あらゆる本物の{class}は戦場でのこのバッグの使い方を知ってるものさ。\n\nHordeの名の下に戦わんとするお前の意志に敬礼！", fs:GetText())
    WFJ.Render.release("quest")
    -- the collector reads the same guarded reader: a missing UnitClass is a refusal, not an error
    WFJ.Settings.set("collector.enabled", true)
    assert.are.same({ "refused", "no_player" }, { WFJ.Collector.record("quest", 7, "description", "Kill ten boars.") })
    _G.UnitSex, _G.UnitClass = sex, class
  end)

  it("one player reader: the client's Unknown name is unavailable to both the tokens and the collector",
  function()
    local unknown = _G.UNKNOWNOBJECT
    _G.UNKNOWNOBJECT = "Reyn" -- the stub's player name plays the client's placeholder name
    local fs = Stub.fontString("Good.", "Fonts\\FRIZQT__.TTF", 12, "")
    WFJ.Render.show("quest", "completion", fs, "Good.", "quests", "quest.completion", 791)
    assert.are.equal("実にいいね、{name}。あらゆる本物のハンターは戦場でのこのバッグの使い方を知ってるものさ。\n\nHordeの名の下に戦わんとするお前の意志に敬礼！", fs:GetText())
    WFJ.Render.release("quest")
    WFJ.Settings.set("collector.enabled", true)
    assert.are.same({ "refused", "no_player" }, { WFJ.Collector.record("quest", 8, "description", "Kill ten wolves.") })
    _G.UNKNOWNOBJECT = unknown
  end)

  it("fills an unaligned item's placeholders from the live tooltip, on the real shards", function()
    local tt = _G.GameTooltip
    -- The client's own duration strings, as the real one defines them. UIStrings admits a row only when the
    -- client's English matches the English its Japanese was drafted against, so without these the duration
    -- renderer has nothing and a `$D<k>` line fails closed to English. That is the right failure, and is
    -- what every other spec in this file sees (ADR-028).
    _G.INT_SPELL_DURATION_SEC, _G.INT_SPELL_DURATION_MIN = "%d sec", "%d min"
    WFJ.BuildUIIndex()
    finally(function()
      _G.INT_SPELL_DURATION_SEC, _G.INT_SPELL_DURATION_MIN = nil, nil
      WFJ.BuildUIIndex()
    end)
    -- item 117 Tough Jerky, with the value and the duration as placeholders:
    --   "$D1かけて体力を$N1回復します。回復中は座っている必要があります。"
    -- The value and the duration both come out of the line the client is showing, so ONE stored translation
    -- serves every food item at any value, where the baked line it replaced only fitted this one.
    Stub.setItemTooltip(tt, "|Hitem:117:0:0:0:0:0:0:0|h[Tough Jerky]|h",
      { "Tough Jerky", "Use: Restores 61 health over 18 sec. Must remain seated while eating.", "Sell Price: 5c" })
    assert.are.equal("18秒かけて体力を61回復します。回復中は座っている必要があります。",
      _G.GameTooltipTextLeft2:GetText())
    assert.are.equal("Tough Jerky", _G.GameTooltipTextLeft1:GetText())
    assert.are.equal("Sell Price: 5c", _G.GameTooltipTextLeft3:GetText()) -- the stub client defines no SELL_PRICE
    tt:Hide()
    assert.are.equal("Use: Restores 61 health over 18 sec. Must remain seated while eating.",
      _G.GameTooltipTextLeft2:GetText())
    -- a different value is not a mismatch: it fills, so one stored line serves every value
    Stub.setItemTooltip(tt, "|Hitem:117:0:0:0:0:0:0:0|h[Tough Jerky]|h",
      { "Tough Jerky", "Use: Restores 70 health over 18 sec. Must remain seated while eating." })
    assert.are.equal("18秒かけて体力を70回復します。回復中は座っている必要があります。",
      _G.GameTooltipTextLeft2:GetText())
    tt:Hide()
    -- and a different UNIT follows the client, never the corpus (ADR-028)
    Stub.setItemTooltip(tt, "|Hitem:117:0:0:0:0:0:0:0|h[Tough Jerky]|h",
      { "Tough Jerky", "Use: Restores 70 health over 2 min. Must remain seated while eating." })
    assert.are.equal("2分かけて体力を70回復します。回復中は座っている必要があります。",
      _G.GameTooltipTextLeft2:GetText())
    tt:Hide()
  end)

  it("prints the TOC version on /wfj version", function()
    Stub.prints = {}
    SlashCmdList.WFJ("version")
    assert.are.equal(1, #Stub.prints)
    assert.is_truthy(Stub.prints[1]:find(meta.Version, 1, true))
  end)

  it("reports unknown verbs without erroring", function()
    Stub.prints = {}
    SlashCmdList.WFJ("bogus")
    assert.is_truthy(Stub.prints[1]:find("unknown command 'bogus'", 1, true))
  end)

  it("ships no legacy InterfaceOptions branch anywhere in the addon", function()
    for _, rel in ipairs(TOC_ORDER) do
      local src = H.readFile("addon/WoWForeverJapanese/" .. rel)
      assert.is_nil(src:find("InterfaceOptions_AddCategory", 1, true), rel)
      assert.is_nil(src:find("InterfaceOptionsFrame", 1, true), rel)
    end
  end)
end)
