-- UI/Minimap.lua over a minimap cluster replayed from Forever blizzard_minimap/mainline/minimap.lua
-- (zone button :84–103 + Minimap_SetTooltip :180–216, tracking button :826–831, mail :485–490 with
-- FormatUnreadMailTooltip, zoom buttons :288–293 / :312–317), mainline/gametime.lua:63–81 and
-- mainline/addoncompartment.lua:12–16. Zone, subzone, faction and sender names stay English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Minimap.lua"

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local UI = {
  SANCTUARY_TERRITORY = { "(Sanctuary)", "(サンクチュアリ)" },
  CONTESTED_TERRITORY = { "(Contested Territory)", "(紛争地域)" },
  COMBAT_ZONE = { "(Combat Zone)", "(戦闘地域)" },
  FACTION_CONTROLLED_TERRITORY = { "(%s Territory)", "（%s領）" }, -- ARGS `text`, the faction kept
  FREE_FOR_ALL_TERRITORY = { "(PvP Area)", "(PvPエリア)" },
  WORLDMAP_BUTTON = { "World Map", "ワールドマップ" },
  TRACKING = { "Tracking", "追跡" },
  MINIMAP_TRACKING_TOOLTIP_NONE = { "Click to enable and disable tracking types.", "クリックで追跡の種類を切り替えます。" },
  HAVE_MAIL = { "You have unread mail", "未読のメールがあります" },
  HAVE_MAIL_FROM = { "Unread mail from:", "未読メールの差出人:" },
  GAMETIME_TOOLTIP_TOGGLE_CALENDAR = { "Click to show the calendar.", "クリックでカレンダーを表示します。" },
  GAMETIME_TOOLTIP_CALENDAR_INVITES = { "You have pending calendar invites.", "未回答のカレンダー招待があります。" },
  ADDONS = { "AddOns", "アドオン" },
  ZOOM_IN = { "Zoom In", "ズームイン" },
  ZOOM_OUT = { "Zoom Out", "ズームアウト" },
  -- a zone whose name is also a dictionary word: it must stay English on the zone button's tooltip
  RAID = { "Raid", "レイド" },
}
local function en(key) return UI[key][1] end
local function ja(key) return UI[key][2] end
local function tip(i) return _G["GameTooltipTextLeft" .. i]:GetText() end

local M = {} -- the replayed client state

local function installMinimap()
  local tt = _G.GameTooltip
  _G.UIParent = CreateFrame("Frame", "UIParent")
  local cluster = CreateFrame("Frame", "MinimapCluster")
  _G.MinimapZoneText = Stub.namedFontString("MinimapZoneText", "Raid")
  local zone = CreateFrame("Button")
  cluster.ZoneTextButton = zone
  zone:SetScript("OnEnter", function(self)
    tt:SetOwner(self)
    tt:ClearLines()
    tt:AddLine(M.zone)
    tt:AddLine(M.subzone)
    tt:AddLine(M.territory)
    tt:AddLine("World Map |cffffd200(M)|r")
    tt:Show()
  end)
  cluster.Tracking = { Button = CreateFrame("Button") }
  cluster.Tracking.Button:SetScript("OnEnter", function(self)
    tt:SetOwner(self)
    tt:SetText(en("TRACKING"))
    tt:AddLine(en("MINIMAP_TRACKING_TOOLTIP_NONE"))
    tt:Show()
  end)
  cluster.IndicatorFrame = { MailFrame = CreateFrame("Frame") }
  cluster.IndicatorFrame.MailFrame:SetScript("OnEnter", function(self)
    tt:SetOwner(self)
    local header = #M.senders >= 1 and en("HAVE_MAIL_FROM") or en("HAVE_MAIL")
    for _, sender in ipairs(M.senders) do header = header .. "\n" .. sender end
    tt:SetText(header)
    tt:Show()
  end)
  local clock = CreateFrame("Button", "GameTimeFrame")
  clock:SetScript("OnEnter", function(self) tt:SetOwner(self) end)
  clock:SetScript("OnUpdate", function(self)
    if tt:GetOwner() ~= self then return end
    tt:ClearLines()
    tt:AddLine("3:45 PM")
    tt:AddLine(" ")
    tt:AddLine(en("GAMETIME_TOOLTIP_TOGGLE_CALENDAR"))
    tt:Show()
  end)
  local compartment = CreateFrame("Button", "AddonCompartmentFrame")
  compartment:SetScript("OnEnter", function(self)
    tt:SetOwner(self)
    tt:ClearLines()
    tt:AddLine(en("ADDONS"))
    tt:Show()
  end)
  local map = CreateFrame("Frame", "Minimap")
  map.ZoomIn, map.ZoomOut = CreateFrame("Button"), CreateFrame("Button")
  map.ZoomIn:SetScript("OnEnter", function()
    if not M.uber then return end
    tt:SetOwner(_G.UIParent)
    tt:SetText(en("ZOOM_IN"))
  end)
  map.ZoomOut:SetScript("OnEnter", function()
    tt:SetOwner(_G.UIParent)
    tt:SetText(en("ZOOM_OUT"))
  end)
  return cluster
end

local function enter(frame) frame.scripts.OnEnter(frame) end

describe("the minimap cluster's help tooltips on Forever", function()
  local WFJ

  local function load()
    local ns = H.loadChunks(FILES)
    H.uiSetup(ns, UI)
    return ns
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    CreateFrame("Frame", "PVPRankFrame") -- the Forever marker (UI/Camelot)
    Stub.installTooltipAPI()
    M = { zone = "Raid", subzone = "Valley of Trials", territory = "(Contested Territory)", senders = {}, uber = true }
    WFJ = load()
    installMinimap()
    WFJ.Labels.forbidNames(WFJ.Minimap.NEVER_TOUCH)
    assert.are.equal(7, WFJ.Minimap.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, n in ipairs({ "MinimapCluster", "Minimap", "GameTimeFrame", "AddonCompartmentFrame", "MinimapZoneText",
      "UIParent" }) do _G[n] = nil end
  end)

  it("the zone button: the territory word and the map hint translate; zone and subzone names stay English", function()
    enter(_G.MinimapCluster.ZoneTextButton)
    assert.are.equal("Raid", tip(1)) -- a zone NAME that is also a dictionary word
    assert.are.equal("Valley of Trials", tip(2))
    assert.are.equal(ja("CONTESTED_TERRITORY"), tip(3))
    assert.are.equal("ワールドマップ |cffffd200(M)|r", tip(4))
    assert.are.equal("Raid", _G.MinimapZoneText:GetText())
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal(en("CONTESTED_TERRITORY"), tip(3))
  end)

  it("a faction-controlled zone translates around the faction's name, which is kept as written", function()
    M.territory = "(Horde Territory)"
    enter(_G.MinimapCluster.ZoneTextButton)
    assert.are.equal("（Horde領）", tip(3))
  end)

  it("tracking, mail, clock and addon compartment tooltips translate", function()
    enter(_G.MinimapCluster.Tracking.Button)
    assert.are.equal(ja("TRACKING"), tip(1))
    assert.are.equal(ja("MINIMAP_TRACKING_TOOLTIP_NONE"), tip(2))
    enter(_G.MinimapCluster.IndicatorFrame.MailFrame)
    assert.are.equal(ja("HAVE_MAIL"), tip(1))
    enter(_G.GameTimeFrame)
    _G.GameTimeFrame.scripts.OnUpdate(_G.GameTimeFrame)
    assert.are.equal("3:45 PM", tip(1))
    assert.are.equal(ja("GAMETIME_TOOLTIP_TOGGLE_CALENDAR"), tip(3))
    _G.GameTimeFrame.scripts.OnUpdate(_G.GameTimeFrame) -- the next frame rewrites it; still Japanese
    assert.are.equal(ja("GAMETIME_TOOLTIP_TOGGLE_CALENDAR"), tip(3))
    enter(_G.AddonCompartmentFrame)
    assert.are.equal(ja("ADDONS"), tip(1))
  end)

  it("mail with senders: the header line in Japanese, the senders' names as written; Alt English",
    function()
      M.senders = { "Thrall", "Jaina" }
      enter(_G.MinimapCluster.IndicatorFrame.MailFrame)
      assert.are.equal(ja("HAVE_MAIL_FROM") .. "\nThrall\nJaina", tip(1))
      Stub.keys.alt = true
      WFJ.Modifier.refresh()
      assert.are.equal("Unread mail from:\nThrall\nJaina", tip(1))
      Stub.keys.alt = false
      WFJ.Modifier.refresh()
    end)

  it("the zoom buttons' UIParent-owned tooltip is walked once; UIParent is never registered", function()
    enter(_G.Minimap.ZoomIn)
    assert.are.equal(ja("ZOOM_IN"), tip(1))
    enter(_G.Minimap.ZoomOut)
    assert.are.equal(ja("ZOOM_OUT"), tip(1))
    assert.is_false(WFJ.HelpTooltip.registered(_G.UIParent))
    -- another default-anchored tooltip with the same words is not ours
    _G.GameTooltip:SetOwner(_G.UIParent)
    _G.GameTooltip:SetText(en("ZOOM_IN"))
    assert.are.equal(en("ZOOM_IN"), tip(1))
    -- UberTooltips off: the button wrote nothing, and whatever UIParent shows is left alone
    M.uber = false
    _G.GameTooltip:SetOwner(_G.MinimapCluster.Tracking.Button)
    _G.GameTooltip:SetText("Thrall")
    enter(_G.Minimap.ZoomIn)
    assert.are.equal("Thrall", tip(1))
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    H.uiTeardown()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    CreateFrame("Frame", "PVPRankFrame") -- the Forever marker (UI/Camelot)
    Stub.installTooltipAPI()
    local ns = load()
    local cluster = installMinimap()
    cluster.Tracking = 7
    cluster.IndicatorFrame = "moved"
    _G.GameTimeFrame = true
    _G.AddonCompartmentFrame = "gone"
    _G.Minimap.ZoomIn = 3
    _G.Minimap.ZoomOut = { HookScript = "not a function" }
    assert.has_no.errors(function() assert.are.equal(1, ns.Minimap.init()) end)
    assert.has_no.errors(function() enter(cluster.ZoneTextButton) end)
    assert.are.equal(ja("CONTESTED_TERRITORY"), tip(3))
  end)

  it("init runs once; a client without the cluster's zone button is skipped without error", function()
    assert.are.equal(7, WFJ.Minimap.init())
    H.uiTeardown()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    CreateFrame("Frame", "PVPRankFrame") -- the Forever marker (UI/Camelot)
    Stub.installTooltipAPI()
    _G.MinimapCluster = nil
    local era = load()
    assert.has_no.errors(function() assert.is_false(era.Minimap.init()) end)
  end)
end)
