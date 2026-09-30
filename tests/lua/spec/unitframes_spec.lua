-- UI/UnitFrames.lua (hud) over unit frames replayed from Forever blizzard_unitframe: the target-style
-- frames' static DeadText / UnconsciousText (mainline/targetframe.xml:182–187, 455–460), the compact frames' status
-- text (shared/compactunitframe.lua:1085–1115), group titles (shared/compactraidgroup.lua:42–51,
-- compactpartyframe.lua:1–32), the unit tooltip's instruction line (mainline/unitframe.lua:396–408) and the
-- "not present" icon tooltips (mainline/partyframetemplates.xml:356–360, compactunitframe.lua:2161–2167).
-- Unit names, health numbers and secret values are never touched.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/UnitFrames.lua"

local UI = {
  DEAD = { "Dead", "死亡" },
  UNCONSCIOUS = { "Unconscious", "気絶" },
  PLAYER_OFFLINE = { "Offline", "オフライン" },
  GROUP_NUMBER = { "Group %d", "グループ%d" },
  PARTY = { "Party", "パーティ" },
  UNIT_POPUP_RIGHT_CLICK = { "<Right click for Frame Settings>", "<右クリックでフレーム設定>" },
  PARTY_IN_PUBLIC_GROUP_MESSAGE = { "This player is currently in an instance group.",
    "このプレイヤーは現在インスタンスグループにいます。" },
  INCOMING_SUMMON_TOOLTIP_SUMMON_PENDING = { "Summon Pending", "召喚待ち" },
  RAID = { "Raid", "レイド" }, -- a dictionary word a unit may be NAMED
}
local function en(key) return UI[key][1] end
local function ja(key) return UI[key][2] end
local function tip(i) return _G["GameTooltipTextLeft" .. i]:GetText() end

local SECRET = {} -- stands for a secret value: comparing or matching it would raise on the client

local function targetStyle(name)
  local f = CreateFrame("Button", name)
  local container = { DeadText = Stub.fontString(en("DEAD")), UnconsciousText = Stub.fontString(en("UNCONSCIOUS")) }
  f.TargetFrameContent = { TargetFrameContentMain = { HealthBarsContainer = container,
    Name = Stub.fontString("Raid") } }
  f.totFrame = { HealthBar = { DeadText = Stub.fontString(en("DEAD")),
    UnconsciousText = Stub.fontString(en("UNCONSCIOUS")) }, Name = Stub.fontString("Hogger") }
  return f
end

local function compactFrame()
  local f = CreateFrame("Button")
  f.statusText = Stub.fontString("")
  f.name = Stub.fontString("Raid")
  f.centerStatusIcon = CreateFrame("Button")
  f.centerStatusIcon:SetScript("OnEnter", function(self)
    _G.GameTooltip:SetOwner(self)
    _G.GameTooltip:SetText(self.tooltip)
    _G.GameTooltip:Show()
  end)
  return f
end

local function installUnitFrames()
  targetStyle("TargetFrame")
  targetStyle("FocusFrame")
  targetStyle("Boss1TargetFrame")
  local party = CreateFrame("Frame", "PartyFrame")
  local member = CreateFrame("Button")
  member.NotPresentIcon = CreateFrame("Frame")
  member.NotPresentIcon:SetScript("OnEnter", function(self)
    _G.GameTooltip:SetOwner(self)
    _G.GameTooltip:SetText(self.tooltip)
    _G.GameTooltip:Show()
  end)
  party.PartyMemberFramePool = { EnumerateActive = function()
    local done = false
    return function() if not done then done = true; return member end end
  end }
  party.member = member
  _G.CompactUnitFrame_UpdateStatusText = function(frame) frame.statusText.text = frame.nextStatus end
  _G.CompactUnitFrame_UpdateCenterStatusIcon = function(frame) frame.centerStatusIcon.tooltip = frame.nextTooltip end
  _G.CompactRaidGroup_InitializeForGroup = function(frame, index)
    frame.title:SetText(string.format("Group %d", index))
  end
  _G.CompactPartyFrame_Generate = function()
    local f = CreateFrame("Frame", "CompactPartyFrame")
    f.title = Stub.button(nil, en("PARTY"))
    return f
  end
  _G.UnitFrame_UpdateTooltip = function(self)
    local tt = _G.GameTooltip
    tt:SetOwner(self)
    tt:ClearLines()
    tt:AddLine(self.unitName)
    tt:AddLine("Level 12 Orc Warrior")
    tt:AddLine(" ")
    tt:AddLine(en("UNIT_POPUP_RIGHT_CLICK"))
    tt:Show()
  end
  _G.issecretvalue = function(v) return v == SECRET end
end

local GLOBALS = { "TargetFrame", "FocusFrame", "Boss1TargetFrame", "PartyFrame", "CompactPartyFrame",
  "CompactUnitFrame_UpdateStatusText", "CompactUnitFrame_UpdateCenterStatusIcon",
  "CompactRaidGroup_InitializeForGroup", "CompactPartyFrame_Generate", "UnitFrame_UpdateTooltip", "issecretvalue" }

describe("the unit frames' fixed words on Forever", function()
  local WFJ

  local function load()
    local ns = H.loadChunks(FILES)
    H.uiSetup(ns, UI)
    return ns
  end

  local function fresh()
    H.uiTeardown()
    for _, n in ipairs(GLOBALS) do _G[n] = nil end
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
  end

  before_each(function()
    fresh()
    WFJ = load()
    installUnitFrames()
    WFJ.Labels.forbidNames(WFJ.UnitFrames.NEVER_TOUCH)
    assert.is_true(WFJ.UnitFrames.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, n in ipairs(GLOBALS) do _G[n] = nil end
  end)

  it("Dead / Unconscious translate on the target-style frames and their target-of-target; names stay English",
    function()
      for _, name in ipairs({ "TargetFrame", "FocusFrame", "Boss1TargetFrame" }) do
        local main = _G[name].TargetFrameContent.TargetFrameContentMain
        assert.are.equal(ja("DEAD"), main.HealthBarsContainer.DeadText:GetText())
        assert.are.equal(ja("UNCONSCIOUS"), main.HealthBarsContainer.UnconsciousText:GetText())
        assert.are.equal(ja("DEAD"), _G[name].totFrame.HealthBar.DeadText:GetText())
        assert.are.equal("Raid", main.Name:GetText()) -- a unit named like a dictionary word
      end
      Stub.keys.alt = true
      WFJ.Modifier.refresh()
      assert.are.equal(en("DEAD"), _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
        .DeadText:GetText())
    end)

  it("a compact frame's status text: the two words translate, numbers and secret values are never read", function()
    local f = compactFrame()
    f.nextStatus = en("DEAD")
    _G.CompactUnitFrame_UpdateStatusText(f)
    assert.are.equal(ja("DEAD"), f.statusText:GetText())
    f.nextStatus = "4521" -- alive again: the record is dropped, the number stays
    _G.CompactUnitFrame_UpdateStatusText(f)
    assert.are.equal("4521", f.statusText:GetText())
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal("4521", f.statusText:GetText()) -- no stale word is restored over it
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    f.nextStatus = en("PLAYER_OFFLINE")
    _G.CompactUnitFrame_UpdateStatusText(f)
    assert.are.equal(ja("PLAYER_OFFLINE"), f.statusText:GetText())
    f.nextStatus = SECRET
    assert.has_no.errors(function() _G.CompactUnitFrame_UpdateStatusText(f) end)
    assert.are.equal(SECRET, f.statusText:GetText())
    assert.are.equal("Raid", f.name:GetText())
  end)

  it("group titles: Group %d and Party translate", function()
    local group = CreateFrame("Frame")
    group.title = Stub.button(nil, "")
    _G.CompactRaidGroup_InitializeForGroup(group, 3)
    assert.are.equal("グループ3", group.title:GetText())
    local party = _G.CompactPartyFrame_Generate() -- created after init
    assert.are.equal(ja("PARTY"), party.title:GetText())
  end)

  it("the unit tooltip: only the instruction line translates", function()
    _G.TargetFrame.unitName = "Raid"
    _G.UnitFrame_UpdateTooltip(_G.TargetFrame)
    assert.are.equal("Raid", tip(1))
    assert.are.equal("Level 12 Orc Warrior", tip(2))
    assert.are.equal(ja("UNIT_POPUP_RIGHT_CLICK"), tip(4))
    assert.is_false(WFJ.HelpTooltip.registered(_G.TargetFrame))
  end)

  it("the not-present icons own help tooltips restricted to their keys", function()
    local icon = _G.PartyFrame.member.NotPresentIcon
    icon.tooltip = en("PARTY_IN_PUBLIC_GROUP_MESSAGE")
    icon.scripts.OnEnter(icon)
    assert.are.equal(ja("PARTY_IN_PUBLIC_GROUP_MESSAGE"), tip(1))
    icon.tooltip = "Raid" -- a phased reason / any other text: not in the restricted set
    icon.scripts.OnEnter(icon)
    assert.are.equal("Raid", tip(1))
    local f = compactFrame()
    f.nextTooltip = en("INCOMING_SUMMON_TOOLTIP_SUMMON_PENDING")
    _G.CompactUnitFrame_UpdateCenterStatusIcon(f)
    f.centerStatusIcon.scripts.OnEnter(f.centerStatusIcon)
    assert.are.equal(ja("INCOMING_SUMMON_TOOLTIP_SUMMON_PENDING"), tip(1))
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    fresh()
    local ns = load()
    installUnitFrames()
    _G.FocusFrame = "moved"
    _G.Boss1TargetFrame.TargetFrameContent = 5
    _G.TargetFrame.totFrame = true
    _G.PartyFrame.PartyMemberFramePool = 3
    _G.CompactUnitFrame_UpdateStatusText = "not a function"
    _G.UnitFrame_UpdateTooltip = false
    _G.issecretvalue = 12
    assert.has_no.errors(function() assert.is_true(ns.UnitFrames.init()) end)
    assert.are.equal(ja("DEAD"), _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
      .DeadText:GetText())
    assert.has_no.errors(function()
      ns.UnitFrames.onStatusText({ statusText = 9 })
      ns.UnitFrames.onStatusText("x")
      ns.UnitFrames.onGroupInit({ title = false })
      ns.UnitFrames.onCenterIcon({ centerStatusIcon = "x" })
      ns.UnitFrames.onUnitTooltip(nil)
    end)
  end)

  it("hooks install once; a client without the mainline target frame is skipped without error", function()
    assert.is_false(WFJ.UnitFrames.init())
    assert.are.equal(1, #Stub.hooks["CompactUnitFrame_UpdateStatusText"])
    fresh()
    local bare = load()
    _G.TargetFrame = CreateFrame("Button", "TargetFrame") -- no TargetFrameContent
    assert.has_no.errors(function() assert.is_false(bare.UnitFrames.init()) end)
  end)
end)
