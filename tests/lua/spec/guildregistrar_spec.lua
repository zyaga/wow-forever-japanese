-- UI/GuildRegistrar.lua over a GuildRegistrarFrame replayed from camelot
-- blizzard_uipanels_game/mainline/guildregistrarframe.xml and guildregistrarframe.lua:1–12.
local Stub = require("tests.lua.spec.wow_stub")
local G = require("tests.lua.spec.stub_gamepanels")

local FILES = G.files("UI/GuildRegistrar.lua")
local UI = {
  AVAILABLE_SERVICES = { "Available Services", "利用可能なサービス" }, CANCEL = { "Cancel", "キャンセル" },
  GUILD_CHARTER_PURCHASE = { "Purchase a Guild Charter", "ギルド設立許可証を購入する" },
  GUILD_CHARTER_REGISTER = { "Register a Guild Charter", "ギルド設立許可証を登録する" },
  GUILD_CREST_DESIGN = { "Design a Guild Crest", "ギルドの紋章をデザインする" },
  GUILD_REGISTRAR_PURCHASE_TEXT = { "To create a guild you must purchase this charter.", "ギルドを作るにはこの許可証の購入が必要です。" },
  COSTS_LABEL = { "Cost:", "費用:" }, PURCHASE = { "Purchase", "購入" },
  TRIAL_RESTRICTED = { "You need to upgrade your account to access this feature.",
    "この機能を利用するにはアカウントのアップグレードが必要です。" },
}
local NAMES = { "GuildRegistrarFrame", "AvailableServicesText", "GuildRegistrarFrameGoodbyeButton",
  "GuildRegistrarFrameCancelButton", "GuildRegistrarButton1", "GuildRegistrarButton2", "GuildRegistrarButton3",
  "GuildRegistrarPurchaseText", "GuildRegistrarCostLabel", "GuildRegistrarFramePurchaseButton",
  "GuildRegistrarFrameNpcNameText", "GuildRegistrarText", "GuildRegistrarFrameEditBox" }

local function patch(WFJ) -- the Core/UIStrings entry this surface needs
  WFJ.UIStrings.LABELS.TRIAL_RESTRICTED = "wrapped"
end

local function install()
  local frame = G.titled("GuildRegistrarFrame")
  Stub.namedFontString("AvailableServicesText", _G.AVAILABLE_SERVICES)
  Stub.button("GuildRegistrarFrameGoodbyeButton", _G.CANCEL)
  Stub.button("GuildRegistrarFrameCancelButton", _G.CANCEL)
  Stub.button("GuildRegistrarButton1", _G.GUILD_CHARTER_PURCHASE)
  Stub.button("GuildRegistrarButton2", _G.GUILD_CHARTER_REGISTER)
  Stub.button("GuildRegistrarButton3", _G.GUILD_CREST_DESIGN)
  Stub.namedFontString("GuildRegistrarPurchaseText", _G.GUILD_REGISTRAR_PURCHASE_TEXT)
  Stub.namedFontString("GuildRegistrarCostLabel", _G.COSTS_LABEL)
  Stub.button("GuildRegistrarFramePurchaseButton", _G.PURCHASE)
  Stub.namedFontString("GuildRegistrarFrameNpcNameText", "Purchase") -- an NPC named like a dictionary word
  Stub.namedFontString("GuildRegistrarText", "Cancel")               -- the NPC's own greeting
  local edit = CreateFrame("EditBox", "GuildRegistrarFrameEditBox")
  edit:SetText("Purchase")
  return frame
end

describe("the guild master NPC's window on Forever", function()
  local WFJ

  before_each(function() WFJ = G.load(FILES, UI, patch) end)
  after_each(function() G.clear(NAMES) end)

  it("every label translates; the NPC's name, its greeting and the name EditBox stay as written", function()
    local frame = install()
    WFJ.Labels.forbidNames(WFJ.GuildRegistrar.NEVER_TOUCH)
    assert.is_true(WFJ.GuildRegistrar.init())
    frame:Show()
    assert.are.equal("利用可能なサービス", _G.AvailableServicesText:GetText())
    assert.are.equal("キャンセル", _G.GuildRegistrarFrameGoodbyeButton:GetText())
    assert.are.equal("ギルド設立許可証を購入する", _G.GuildRegistrarButton1:GetText())
    assert.are.equal("ギルドの紋章をデザインする", _G.GuildRegistrarButton3:GetText())
    assert.are.equal(UI.GUILD_REGISTRAR_PURCHASE_TEXT[2], _G.GuildRegistrarPurchaseText:GetText())
    assert.are.equal("費用:", _G.GuildRegistrarCostLabel:GetText())
    assert.are.equal("購入", _G.GuildRegistrarFramePurchaseButton:GetText())
    assert.are.equal("Purchase", _G.GuildRegistrarFrameNpcNameText:GetText())
    assert.are.equal("Cancel", _G.GuildRegistrarText:GetText())
    assert.are.equal("Purchase", _G.GuildRegistrarFrameEditBox:GetText())
    assert.is_true(G.unrecorded(WFJ, _G.GuildRegistrarFrameEditBox))
    G.alt(WFJ, true)
    assert.are.equal("Purchase", _G.GuildRegistrarFramePurchaseButton:GetText())
    G.alt(WFJ, false)
    frame:Hide()
    assert.are.equal("Available Services", _G.AvailableServicesText:GetText())
  end)

  it("the purchase button's trial tooltip translates inside its colour", function()
    install()
    assert.is_true(WFJ.GuildRegistrar.init())
    G.tooltip(_G.GuildRegistrarFramePurchaseButton, { "|cffff2020" .. UI.TRIAL_RESTRICTED[1] .. "|r" })
    assert.are.equal("|cffff2020" .. UI.TRIAL_RESTRICTED[2] .. "|r", G.line(1))
  end)

  it("wrong-typed names degrade without error", function()
    local frame = install()
    _G.AvailableServicesText = 1
    _G.GuildRegistrarButton2 = "x"
    _G.GuildRegistrarFramePurchaseButton = false
    assert.has_no.errors(function() assert.is_true(WFJ.GuildRegistrar.init()) end)
    assert.has_no.errors(function() frame:Show() end)
    assert.are.equal("ギルド設立許可証を購入する", _G.GuildRegistrarButton1:GetText())
    assert.is_false(WFJ.GuildRegistrar.init())
  end)

  it("no frame: init is false and nothing is touched", function()
    assert.has_no.errors(function() assert.is_false(WFJ.GuildRegistrar.init()) end)
  end)
end)
