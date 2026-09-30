-- UI/RaidManager.lua over a CompactRaidFrameManager replayed from camelot's
-- blizzard_compactraidframes/mainline/blizzard_compactraidframemanager.lua|xml (UpdateLabel :308–314, the leave
-- instance button's OnUpdate :1324–1333, CRFM_TooltipMixin:OnEnter :36–49, the two dropdowns :174–209). Counts and
-- group numbers stay as written. Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/RaidManager.lua"

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local UI = {
  RAID = { "Raid", "レイド" }, PARTY = { "Party", "パーティ" }, NONE = { "None", "なし" },
  GROUPMANAGER_UNIT_MARKER = { "Unit", "ユニット" }, GROUPMANAGER_GROUND_MARKER = { "Ground", "地面" },
  RAID_MANAGER_RESTRICT_PINGS_TO = { "Restrict Pings To:", "ピンの制限:" },
  RAID_MANAGER_RESTRICT_PINGS_TO_LEAD = { "Lead", "リーダー" },
  PARTY_LEAVE = { "Leave Party", "パーティを抜ける" },
  INSTANCE_PARTY_LEAVE = { "Leave Instance Group", "インスタンスグループを抜ける" },
  INSTANCE_WALK_IN_LEAVE = { "Leave Delve", "Delveを抜ける" },
  CRF_READY_CHECK = { "Ready Check", "レディチェック" }, CRF_COUNTDOWN = { "Countdown", "カウントダウン" },
  ALL_ASSIST_NOT_LEADER_ERROR = { "Only the Raid Leader may change this option.",
    "このオプションを変更できるのはレイドリーダーだけです。" },
}

local S = {} -- the replayed client state: S.inRaid, S.walkIn

-- A WowStyle1DropdownTemplate-like button: `.Text` rewritten by UpdateText from the selection.
local function dropdown(selection)
  local d = CreateFrame("DropdownButton")
  d.Text = Stub.fontString("")
  d.selection = selection
  function d.UpdateText(self) self.Text.text = self.selection end
  d:UpdateText()
  return d
end

local function tooltipButton(tooltip)
  local b = CreateFrame("Button")
  b.tooltip = tooltip
  function b.enter(self) -- CRFM_TooltipMixin:OnEnter
    _G.GameTooltip:SetOwner(self)
    _G.GameTooltip:ClearLines()
    _G.GameTooltip:AddLine(self.tooltip)
    _G.GameTooltip:Show()
  end
  return b
end

local function installManager()
  local frame = CreateFrame("Frame", "CompactRaidFrameManager")
  local display = CreateFrame("Frame")
  frame.displayFrame = display
  display.label = Stub.fontString("Raid")
  display.memberCountLabel = Stub.fontString("10/10")
  display.raidMarkers = CreateFrame("Frame")
  display.raidMarkers.raidMarkerUnitTab = Stub.button(nil, "Unit")
  display.raidMarkers.raidMarkerGroundTab = Stub.button(nil, "Ground")
  display.RestrictPingsLabel = Stub.fontString("Restrict Pings To:")
  display.ModeControlDropdown = dropdown("Raid")
  display.RestrictPingsDropdown = dropdown("None")
  display.filterOptions = { filterRoleTank = Stub.button(nil, "T 2/2") }
  display.readyCheckButton = tooltipButton("Ready Check")
  display.countdownButton = tooltipButton("Countdown")
  Stub.button("CompactRaidFrameManagerLeavePartyButton", "Leave Party")
  local leave = Stub.button("CompactRaidFrameManagerLeaveInstanceGroupButton", "Leave Instance Group")
  leave:SetScript("OnUpdate", function(self) -- LeaveInstanceGroupButtonMixin:OnUpdate
    self.fontString.text = S.walkIn and "Leave Delve" or "Leave Instance Group"
  end)
  _G.CompactRaidFrameManager_UpdateLabel = function()
    display.label.text = S.inRaid and "Raid" or "Party"
  end
  return frame
end

local GLOBALS = { "CompactRaidFrameManager", "CompactRaidFrameManagerLeavePartyButton",
  "CompactRaidFrameManagerLeaveInstanceGroupButton", "CompactRaidFrameManager_UpdateLabel" }

describe("the group manager panel on Forever", function()
  local WFJ

  local function setup(install)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    S.inRaid, S.walkIn = true, false
    if install then install() end
    WFJ.Labels.forbidNames(WFJ.RaidManager.NEVER_TOUCH)
  end

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
  end)

  it("static labels, the header and the dropdown selections render Japanese; counts stay as written", function()
    setup(installManager)
    assert.is_true(WFJ.RaidManager.init())
    local display = _G.CompactRaidFrameManager.displayFrame
    assert.are.equal("レイド", display.label:GetText())
    assert.are.equal("ユニット", display.raidMarkers.raidMarkerUnitTab:GetText())
    assert.are.equal("地面", display.raidMarkers.raidMarkerGroundTab:GetText())
    assert.are.equal("ピンの制限:", display.RestrictPingsLabel:GetText())
    assert.are.equal("パーティを抜ける", _G.CompactRaidFrameManagerLeavePartyButton:GetText())
    assert.are.equal("レイド", display.ModeControlDropdown.Text:GetText())
    assert.are.equal("なし", display.RestrictPingsDropdown.Text:GetText())
    assert.are.equal("10/10", display.memberCountLabel:GetText())
    assert.are.equal("T 2/2", display.filterOptions.filterRoleTank:GetText())
    alt(true)
    assert.are.equal("Raid", display.label:GetText())
    alt(false)
  end)

  it("UpdateLabel and a dropdown selection are followed", function()
    setup(installManager)
    WFJ.RaidManager.init()
    local display = _G.CompactRaidFrameManager.displayFrame
    S.inRaid = false
    _G.CompactRaidFrameManager_UpdateLabel()
    assert.are.equal("パーティ", display.label:GetText())
    display.RestrictPingsDropdown.selection = "Lead"
    display.RestrictPingsDropdown:UpdateText()
    assert.are.equal("リーダー", display.RestrictPingsDropdown.Text:GetText())
  end)

  it("the leave-instance button is re-rendered after each OnUpdate write", function()
    setup(installManager)
    WFJ.RaidManager.init()
    local leave = _G.CompactRaidFrameManagerLeaveInstanceGroupButton
    leave.scripts.OnUpdate(leave)
    assert.are.equal("インスタンスグループを抜ける", leave:GetText())
    S.walkIn = true
    leave.scripts.OnUpdate(leave)
    assert.are.equal("Delveを抜ける", leave:GetText())
  end)

  it("toolbar tooltips render Japanese; a name on an unregistered owner does not", function()
    setup(installManager)
    WFJ.RaidManager.init()
    local display = _G.CompactRaidFrameManager.displayFrame
    display.readyCheckButton:enter()
    assert.are.equal("レディチェック", _G.GameTooltipTextLeft1:GetText())
    local other = tooltipButton("Raid") -- a guild called "Raid" on some other frame's tooltip
    other:enter()
    assert.are.equal("Raid", _G.GameTooltipTextLeft1:GetText())
  end)

  it("client names bound to the wrong type degrade to English with no error", function()
    setup(function()
      installManager()
      local display = _G.CompactRaidFrameManager.displayFrame
      display.label = 7
      display.ModeControlDropdown = "x"
      display.readyCheckButton = true
      _G.CompactRaidFrameManagerLeaveInstanceGroupButton = 3
      _G.CompactRaidFrameManager_UpdateLabel = "nope"
    end)
    assert.has_no.errors(function() assert.is_true(WFJ.RaidManager.init()) end)
    assert.are.equal("ユニット", _G.CompactRaidFrameManager.displayFrame.raidMarkers.raidMarkerUnitTab:GetText())
  end)

  it("hooks install once; without the panel init returns false", function()
    setup(installManager)
    assert.is_true(WFJ.RaidManager.init())
    assert.is_false(WFJ.RaidManager.init())
    assert.are.equal(1, #Stub.hooks["CompactRaidFrameManager_UpdateLabel"])
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
    setup(nil)
    assert.has_no.errors(function() assert.is_false(WFJ.RaidManager.init()) end)
    -- a manager whose frame exists but has no marker tabs
    setup(function() CreateFrame("Frame", "CompactRaidFrameManager").displayFrame = CreateFrame("Frame") end)
    assert.is_false(WFJ.RaidManager.init())
  end)
end)
