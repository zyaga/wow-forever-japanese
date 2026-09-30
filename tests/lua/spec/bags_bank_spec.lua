-- the bag and bank-tab filter lines. A bag's portrait tooltip and a bag slot's item
-- tooltip end with BAG_FILTER_ASSIGNED_TO (mainline/containerframe.lua:2022–2027; shared/mainmenubarbagbuttons.lua:
-- 112–118), the filters joined with LIST_DELIMITER (containerframe.lua:2319–2335); a bank tab's tooltip carries
-- BANK_TAB_EXPANSION_ASSIGNMENT / BANK_TAB_DEPOSIT_ASSIGNMENTS (mainline/bankframetemplates.lua:311–338). Every filter
-- shows in Japanese with the delimiter kept; bag and tab names stay English; Alt shows the client's English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local CI = require("tests.lua.spec.stub_camelot_inventory")

local UI = {
  BACKPACK_TOOLTIP = { "Backpack", "バックパック" },
  CLICK_BAG_SETTINGS = { "|cff00ff00<Click for Bag Settings>|r", "|cff00ff00<クリックでバッグ設定>|r" },
  BAG_FILTER_ASSIGNED_TO = { "Assigned to: |cffffffff%s|r", "割り当て先: |cffffffff%s|r" },
  BAG_FILTER_EQUIPMENT = { "Equipment", "装備品" }, BAG_FILTER_CONSUMABLES = { "Consumables", "消耗品" },
  BANK_TAB_TOOLTIP_CLICK_INSTRUCTION = { "<Right-click for settings>", "<右クリックで設定>" },
  BANK_TAB_EXPANSION_ASSIGNMENT = { "Expansion: |cnHIGHLIGHT_FONT_COLOR:%s|r", "拡張: |cnHIGHLIGHT_FONT_COLOR:%s|r" },
  BANK_TAB_EXPANSION_FILTER_CURRENT = { "Current Only", "現行のみ" },
  BANK_TAB_DEPOSIT_ASSIGNMENTS = { "Assigned to: |cnHIGHLIGHT_FONT_COLOR:%s|r",
    "割り当て先: |cnHIGHLIGHT_FONT_COLOR:%s|r" },
  EQUIP_CONTAINER = { "Equip Container", "バッグを装備" }, PAGE_NUMBER = { "Page %d", "%dページ" },
  BANK = { "Bank", "銀行" }, BAG_FILTER_TRADE_GOODS = { "Trade Goods", "交易品" },
}

local function left(i) return _G["GameTooltipTextLeft" .. i]:GetText() end

describe("bag and bank-tab filter lines (entryList)", function()
  local WFJ

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    for key, pair in pairs(UI) do _G[key] = pair[1] end
    CI.install()
    -- BaseBagSlotButtonMixin:OnEnterInternal, called as self:OnEnterInternal() (mainmenubarbagbuttons.lua:99–127)
    local slot = _G.CharacterBag2Slot
    function slot.OnEnterInternal(self)
      local tt = _G.GameTooltip
      tt:SetOwner(self, "ANCHOR_LEFT")
      Stub.setItemTooltip(tt, "|Hitem:4496:0:0:0|h[Consumables]|h", { "Consumables", "6 Slot Bag" })
      tt:AddLine(_G.BAG_FILTER_ASSIGNED_TO:format(self.filters))
      tt:Show()
    end
    local files = {}
    for i, f in ipairs(H.UI_FILES) do files[i] = f end
    files[#files + 1] = "UI/Bags.lua"
    files[#files + 1] = "UI/Bank.lua"
    WFJ = H.loadChunks(files)
    H.uiSetup(WFJ, UI)
    assert.is_true(WFJ.Bags.init())
    assert.is_true(WFJ.Bank.init())
  end)

  after_each(function()
    H.uiTeardown()
    CI.teardown()
    Stub.keys.alt = false
  end)

  it("a bag's portrait: two filters in Japanese, the delimiter kept; a bag named like a filter stays English",
    function()
    local pouch = CI.openBag(1)
    local tt = _G.GameTooltip
    CI.hover(pouch.PortraitButton)
    tt:AddLine(_G.BAG_FILTER_ASSIGNED_TO:format("Equipment,Consumables"))
    tt:Show()
    assert.are.equal("割り当て先: |cffffffff装備品,消耗品|r", left(3))
    alt(true)
    assert.are.equal("Assigned to: |cffffffffEquipment,Consumables|r", left(3))
    alt(false)
    CI.bagNames[1] = "Consumables" -- a bag's item name that is a dictionary word
    CI.hover(pouch.PortraitButton)
    assert.are.equal("Consumables", left(1))
  end)

  it("an equipped bag's item tooltip: the appended filter line is Japanese, the item's own lines untouched", function()
    local slot = _G.CharacterBag2Slot
    slot.filters = "Equipment, Consumables"
    slot:OnEnterInternal()
    assert.are.equal("Consumables", left(1)) -- the bag's name
    assert.are.equal("割り当て先: |cffffffff装備品, 消耗品|r", left(3))
    slot.filters = "Equipment, Trinkets" -- a piece no entry: the whole line stays English
    slot:OnEnterInternal()
    assert.are.equal("Assigned to: |cffffffffEquipment, Trinkets|r", left(3))
  end)

  it("a bank tab: the expansion and deposit assignments are Japanese, the tab's name English", function()
    CI.tabs = { "Equipment" }
    CI.openBank()
    local tab = CI.bankTabs()[1]
    local tt = _G.GameTooltip
    tt:SetOwner(tab, "ANCHOR_RIGHT")
    tt:SetText("Equipment")
    tt:AddLine(_G.BANK_TAB_EXPANSION_ASSIGNMENT:format(_G.BANK_TAB_EXPANSION_FILTER_CURRENT))
    tt:AddLine(_G.BANK_TAB_DEPOSIT_ASSIGNMENTS:format("Equipment,Consumables"))
    tt:AddLine(_G.BANK_TAB_TOOLTIP_CLICK_INSTRUCTION)
    tt:Show()
    assert.are.equal("Equipment", left(1))
    assert.are.equal("拡張: |cnHIGHLIGHT_FONT_COLOR:現行のみ|r", left(2))
    assert.are.equal("割り当て先: |cnHIGHLIGHT_FONT_COLOR:装備品,消耗品|r", left(3))
    assert.are.equal("<右クリックで設定>", left(4))
  end)
end)
