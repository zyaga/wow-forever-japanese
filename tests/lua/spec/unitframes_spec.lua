-- UI/UnitFrames.lua (hud) over unit frames replayed from Forever blizzard_unitframe: the target-style
-- frames' static DeadText / UnconsciousText (mainline/targetframe.xml:182–187, 448–453), the compact frames' status
-- text (shared/compactunitframe.lua:1084–1114), group titles (shared/compactraidgroup.lua:42–51,
-- compactpartyframe.lua:1–32), the unit tooltip's instruction line (mainline/unitframe.lua:396–408) and the
-- "not present" icon tooltips (mainline/partyframetemplates.xml:356–360, compactunitframe.lua:2160–2166).
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
  -- the client's one writer of a unit frame's name: self.name:SetText(GetUnitName(self.unit, isParty))
  -- [verified: mainline/unitframe.lua:144–166], called by name from the target, focus, pet and party frames
  _G.UnitFrame_Update = function(self) if self.name then self.name.text = self.nextName end end
  -- the writer of a nameplate's and a raid-style frame's name: frame.name:SetText(GetUnitName(frame.unit, …))
  -- [verified: shared/compactunitframe.lua:826–857], called by name
  _G.CompactUnitFrame_UpdateName = function(frame) frame.name.text = frame.nextName end
end

local GLOBALS = { "TargetFrame", "FocusFrame", "Boss1TargetFrame", "PartyFrame", "CompactPartyFrame",
  "CompactUnitFrame_UpdateStatusText", "CompactUnitFrame_UpdateCenterStatusIcon",
  "CompactRaidGroup_InitializeForGroup", "CompactPartyFrame_Generate", "UnitFrame_UpdateTooltip", "issecretvalue",
  "UnitFrame_Update", "UnitIsPlayer", "UnitPlayerControlled", "CompactUnitFrame_UpdateName" }

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

  describe("with names on", function()
    local frame
    before_each(function()
      _G.UnitIsPlayer = function(unit) return unit == "party1" end
      _G.UnitPlayerControlled = function(unit) return unit == "party1" or unit == "pet" end
      WFJ.Data.add("name", { [WFJ.Names.key("Kobold Vermin")] = "コボルド・バーミン\tこぼるど・ばーみん" })
      WFJ.State.setNames(true)
      frame = { name = Stub.fontString(""), unit = "target", nextName = "Kobold Vermin" }
    end)
    after_each(function() WFJ.State.setNames(false) end)

    it("a creature's name shows its Japanese after the client's update; the reveal key gives it back", function()
      _G.UnitFrame_Update(frame)
      assert.are.equal("コボルド・バーミン", frame.name:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("Kobold Vermin", frame.name:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("コボルド・バーミン", frame.name:GetText())
      frame.nextName = "Nobody Known" -- another target, with no Japanese
      _G.UnitFrame_Update(frame)
      assert.are.equal("Nobody Known", frame.name:GetText())
    end)

    it("a player's and a pet's name stay as written, even one a creature shares", function()
      frame.unit = "party1"
      _G.UnitFrame_Update(frame)
      assert.are.equal("Kobold Vermin", frame.name:GetText())
      frame.unit = "pet"
      _G.UnitFrame_Update(frame)
      assert.are.equal("Kobold Vermin", frame.name:GetText())
      assert.are.equal(0, frame.name.calls.addonSetText)
    end)

    it("a creature's nameplate shows its Japanese after the client's update; a player's stays", function()
      local plate = { name = Stub.fontString(""), unit = "nameplate3", nextName = "Kobold Vermin" }
      _G.CompactUnitFrame_UpdateName(plate)
      assert.are.equal("コボルド・バーミン", plate.name:GetText())
      plate.nextName = "Nobody Known" -- the plate reused for a creature with no Japanese
      _G.CompactUnitFrame_UpdateName(plate)
      assert.are.equal("Nobody Known", plate.name:GetText())
      local raid = { name = Stub.fontString(""), unit = "party1", nextName = "Kobold Vermin" }
      _G.CompactUnitFrame_UpdateName(raid)
      assert.are.equal("Kobold Vermin", raid.name:GetText())
      assert.are.equal(0, raid.name.calls.addonSetText)
    end)

    -- A critter is a creature like any other, and a short name that is also a common word is still a name. A pet
    -- with the same name is its player's and stays.
    it("a critter's nameplate shows its Japanese; a pet named the same stays as written", function()
      WFJ.Data.add("name", { [WFJ.Names.key("Cat")] = "キャット\tきゃっと" })
      local plate = { name = Stub.fontString(""), unit = "nameplate40", nextName = "Cat" }
      _G.CompactUnitFrame_UpdateName(plate)
      assert.are.equal("キャット", plate.name:GetText())
      local pet = { name = Stub.fontString(""), unit = "pet", nextName = "Cat" }
      _G.CompactUnitFrame_UpdateName(pet)
      assert.are.equal("Cat", pet.name:GetText())
      assert.are.equal(0, pet.name.calls.addonSetText)
    end)

    it("a nameplate the client keeps from addons is never looked into, and a hidden name is never read", function()
      -- a forbidden frame: any field but IsForbidden raises, as on the client
      local forbidden = setmetatable({}, { __index = function(_, k)
        if k == "IsForbidden" then return function() return true end end
        if k == "name" then return { text = "x" } end -- the client's own writer may read it
        error("addon code looked into a forbidden nameplate: " .. tostring(k))
      end })
      rawset(forbidden, "nextName", "Kobold Vermin")
      assert.has_no.errors(function() _G.CompactUnitFrame_UpdateName(forbidden) end)
      local plate = { name = Stub.fontString(""), unit = "nameplate3", nextName = SECRET }
      assert.has_no.errors(function() _G.CompactUnitFrame_UpdateName(plate) end)
      assert.are.equal(SECRET, plate.name.text)
    end)

    it("a name the client hides is never read, and a frame with no name or no unit raises nothing", function()
      frame.nextName = SECRET
      assert.has_no.errors(function() _G.UnitFrame_Update(frame) end)
      assert.are.equal(SECRET, frame.name.text)
      assert.has_no.errors(function()
        _G.UnitFrame_Update({ unit = "target" })
        _G.UnitFrame_Update({ name = Stub.fontString("x"), nextName = "Kobold Vermin" })
      end)
    end)
  end)

  it("with names off a unit frame's name is never written", function()
    _G.UnitIsPlayer = function() return false end
    local frame = { name = Stub.fontString(""), unit = "target", nextName = "Kobold Vermin" }
    _G.UnitFrame_Update(frame)
    assert.are.equal(0, frame.name.calls.addonSetText)
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
