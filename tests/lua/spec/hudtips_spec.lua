-- UI/HudTips.lua over HUD buttons replayed from Forever blizzard_actionbar/shared/
-- vehicleleavebutton.lua:12–23, blizzard_overrideactionbar/overrideactionbar.xml:171–206, 262–275,
-- blizzard_durabilityframe/durabilityframe.lua:31–43 and blizzard_actionbar/shared/multicastactionbarframe.lua:
-- 527–537. A spell's tooltip on the same buttons is never walked.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/HudTips.lua"

local UI = {
  TAXI_CANCEL = { "Request Stop", "途中下車をリクエスト" },
  TAXI_CANCEL_DESCRIPTION = { "Land at the next available Flight Master.", "次のフライトマスターで降ります。" },
  LEAVE_VEHICLE = { "Exit", "降りる" },
  AIM_UP = { "Aim Up", "上を狙う" },
  AIM_DOWN = { "Aim Down", "下を狙う" },
  REPAIR_ARMOR_TOOLTIP_TITLE = { "Repair Armor", "防具の修理" },
  REPAIR_ARMOR_TOOLTIP_BROKEN = { "One of your items has broken. You'll gain no benefit from it until it's repaired. "
    .. "Visit a vendor in town to repair it.", "アイテムが1つ壊れました。修理するまで効果を得られません。街の商人で修理しましょう。" },
  MULTI_CAST_TOOLTIP_NO_TOTEM = { "No Totem", "トーテムなし" },
  CANCEL = { "Cancel", "キャンセル" },
}
local function en(key) return UI[key][1] end
local function ja(key) return UI[key][2] end
local function tip(i) return _G["GameTooltipTextLeft" .. i]:GetText() end

local S = {}

local function titleTip(owner, ...)
  local tt = _G.GameTooltip
  tt:SetOwner(owner)
  tt:ClearLines()
  for _, line in ipairs({ ... }) do tt:AddLine(line) end
  tt:Show()
end

local function installHud()
  local leave = CreateFrame("Button", "MainMenuBarVehicleLeaveButton")
  leave:SetScript("OnEnter", function(self)
    if S.taxi then titleTip(self, en("TAXI_CANCEL"), en("TAXI_CANCEL_DESCRIPTION"))
    else titleTip(self, en("LEAVE_VEHICLE")) end
  end)
  local bar = CreateFrame("Frame", "OverrideActionBar")
  bar.pitchFrame = { PitchUpButton = CreateFrame("Button"), PitchDownButton = CreateFrame("Button") }
  bar.leaveFrame = { LeaveButton = CreateFrame("Button") }
  bar.pitchFrame.PitchUpButton:SetScript("OnEnter", function(self) titleTip(self, en("AIM_UP")) end)
  bar.pitchFrame.PitchDownButton:SetScript("OnEnter", function(self) titleTip(self, en("AIM_DOWN")) end)
  bar.leaveFrame.LeaveButton:SetScript("OnEnter", function(self) titleTip(self, en("LEAVE_VEHICLE")) end)
  local durability = CreateFrame("Frame", "DurabilityFrame")
  durability:SetScript("OnEnter", function(self)
    titleTip(self, en("REPAIR_ARMOR_TOOLTIP_TITLE"), en("REPAIR_ARMOR_TOOLTIP_BROKEN"))
  end)
  _G.MultiCastFlyoutButton_SetTooltip = function(self)
    _G.GameTooltip:SetOwner(self)
    if self.spellId == 0 then _G.GameTooltip:SetText(en("MULTI_CAST_TOOLTIP_NO_TOTEM"))
    else Stub.setSpellTooltip(_G.GameTooltip, self.spellId, { "No Totem" }) end
  end
end

local GLOBALS = { "MainMenuBarVehicleLeaveButton", "OverrideActionBar", "DurabilityFrame",
  "MultiCastFlyoutButton_SetTooltip" }
local function enter(frame) frame.scripts.OnEnter(frame) end

describe("the HUD buttons' help tooltips on Forever", function()
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
    S = { taxi = true }
    WFJ = load()
    installHud()
    assert.are.equal(5, WFJ.HudTips.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, n in ipairs(GLOBALS) do _G[n] = nil end
  end)

  it("the vehicle leave button: taxi and vehicle tooltips translate; Alt shows English", function()
    enter(_G.MainMenuBarVehicleLeaveButton)
    assert.are.equal(ja("TAXI_CANCEL"), tip(1))
    assert.are.equal(ja("TAXI_CANCEL_DESCRIPTION"), tip(2))
    S.taxi = false
    enter(_G.MainMenuBarVehicleLeaveButton)
    assert.are.equal(ja("LEAVE_VEHICLE"), tip(1))
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal(en("LEAVE_VEHICLE"), tip(1))
  end)

  it("the override bar's buttons and the durability frame translate, each restricted to its own keys", function()
    enter(_G.OverrideActionBar.pitchFrame.PitchUpButton)
    assert.are.equal(ja("AIM_UP"), tip(1))
    enter(_G.OverrideActionBar.pitchFrame.PitchDownButton)
    assert.are.equal(ja("AIM_DOWN"), tip(1))
    enter(_G.OverrideActionBar.leaveFrame.LeaveButton)
    assert.are.equal(ja("LEAVE_VEHICLE"), tip(1))
    enter(_G.DurabilityFrame)
    assert.are.equal(ja("REPAIR_ARMOR_TOOLTIP_TITLE"), tip(1))
    assert.are.equal(ja("REPAIR_ARMOR_TOOLTIP_BROKEN"), tip(2))
    titleTip(_G.DurabilityFrame, "Cancel") -- a dictionary word outside this owner's set (or a name): untouched
    assert.are.equal("Cancel", tip(1))
  end)

  it("an empty totem slot translates; a slot holding a spell is a spell tooltip and is never walked", function()
    local button = CreateFrame("Button")
    button.spellId = 0
    _G.MultiCastFlyoutButton_SetTooltip(button)
    assert.are.equal(ja("MULTI_CAST_TOOLTIP_NO_TOTEM"), tip(1))
    assert.is_false(WFJ.HelpTooltip.registered(button))
    button.spellId = 8071 -- a spell NAMED like the dictionary word
    _G.MultiCastFlyoutButton_SetTooltip(button)
    assert.are.equal("No Totem", tip(1))
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    fresh()
    local ns = load()
    installHud()
    _G.MainMenuBarVehicleLeaveButton = "moved"
    _G.OverrideActionBar.pitchFrame = 4
    _G.OverrideActionBar.leaveFrame.LeaveButton = true
    _G.MultiCastFlyoutButton_SetTooltip = { "not a function" }
    assert.has_no.errors(function() assert.are.equal(1, ns.HudTips.init()) end)
    enter(_G.DurabilityFrame)
    assert.are.equal(ja("REPAIR_ARMOR_TOOLTIP_TITLE"), tip(1))
    assert.has_no.errors(function() ns.HudTips.onFlyoutTooltip(nil) end)
  end)

  it("init runs once; a client with none of the owners is skipped without error", function()
    assert.are.equal(5, WFJ.HudTips.init())
    assert.are.equal(1, #Stub.hooks["MultiCastFlyoutButton_SetTooltip"])
    fresh()
    local bare = load()
    assert.has_no.errors(function() assert.is_false(bare.HudTips.init()) end)
  end)
end)
