-- the merchant window on the Forever (camelot) client (the mainline MerchantFrame): the same tabs,
-- page text, Prev / Next and repair buttons; the title through SetTitle (the NPC name on the merchant tab stays
-- English, MERCHANT_BUYBACK on the buyback tab is Japanese); the sell-junk and guild-repair tooltips; the filter
-- dropdown's ALL / ITEM_BIND_ON_EQUIP (class and spec names stay English). Item names are never touched.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local CI = require("tests.lua.spec.stub_camelot_inventory")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Merchant.lua"

local UI = {
  MERCHANT = { "Merchant", "商人" }, BUYBACK = { "Buyback", "買い戻し" },
  MERCHANT_BUYBACK = { "Merchant Buyback", "商人の買い戻し" },
  MERCHANT_PAGE_NUMBER = { "Page %s of %s", "%s / %s ページ" },
  PREV = { "Prev", "前へ" }, NEXT = { "Next", "次へ" },
  REPAIR_ALL_ITEMS = { "Repair All Items", "すべて修理" }, REPAIR_AN_ITEM = { "Repair an Item", "アイテムを修理" },
  SELL_ALL_JUNK_ITEMS = { "Sell All Junk Items", "ガラクタをすべて売る" },
  GUILDBANK_REPAIR = { "Remaining amount for today's Guild Bank repairs:", "本日のギルド銀行修理の残額:" },
  GUILDBANK_REPAIR_PERSONAL = { "Personal amount to be spent:", "自己負担額:" },
  GUILDBANK_REPAIR_INSUFFICIENT_FUNDS = { "Insufficient funds to repair all items", "全修理には資金が足りない" },
  ALL = { "All", "すべて" },
  ITEM_BIND_ON_EQUIP = { "Binds when equipped", "装備すると魂縛される" },
  WARRIOR = { "Warrior", "戦士" }, -- a class name that is also a dictionary word
}

describe("the merchant on the Forever client", function()
  local WFJ, SS

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function left(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
  local function title() return _G.MerchantFrame.TitleContainer.TitleText end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    for key, pair in pairs(UI) do _G[key] = pair[1] end -- the client's GlobalStrings
    CI.install()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    WFJ.Labels.forbidNames(WFJ.Merchant.NEVER_TOUCH)
    assert.is_true(WFJ.Merchant.init())
  end)

  after_each(function()
    H.uiTeardown()
    CI.teardown()
  end)

  it("tabs and Prev / Next are Japanese from init; MerchantRepairText and MerchantNameText resolve nothing",
    function()
    assert.are.equal("商人", _G.MerchantFrameTab1:GetText())
    assert.are.equal("買い戻し", _G.MerchantFrameTab2:GetText())
    local prev = select(2, _G.MerchantPrevPageButton:GetRegions())
    assert.are.equal("前へ", prev:GetText())
    assert.is_nil(WFJ.Compat.get("merchant", "repairText"))
    assert.are.equal(_G.MerchantFrame.TitleContainer.TitleText, WFJ.Compat.get("merchant", "nameText"))
  end)

  it("the merchant tab's title is the NPC name (a dictionary word) and stays English; the page text is Japanese;"
    .. " the buyback tab's title is Japanese; hiding restores English", function()
    CI.merchantItems = { "Merchant", "Buyback" } -- item names that are dictionary words
    CI.openMerchant()
    assert.are.equal("Merchant Buyback", title():GetText())
    assert.are.equal(0, title().calls.addonSetText)
    assert.are.equal("1 / 3 ページ", _G.MerchantPageText:GetText())
    assert.are.equal("Merchant", _G.MerchantItem1Name:GetText())
    CI.merchantTab(2)
    assert.are.equal("商人の買い戻し", title():GetText())
    alt(true)
    assert.are.equal("Merchant Buyback", title():GetText())
    alt(false)
    CI.merchantTab(1)
    assert.are.equal("Merchant Buyback", title():GetText()) -- the NPC name again: the record was dropped
    assert.is_nil(SS.get("merchant", "ui.title"))
    CI.merchantTab(2)
    _G.MerchantFrame:Hide()
    assert.are.equal("Merchant Buyback", title():GetText())
    assert.are.equal(0, SS.count("merchant"))
    for i = 1, 12 do assert.are.equal(0, _G["MerchantItem" .. i .. "Name"].calls.addonSetText) end
  end)

  it("the sell-junk and guild-repair tooltips are Japanese, the money lines verbatim", function()
    CI.hover(_G.MerchantSellAllJunkButton)
    assert.are.equal("ガラクタをすべて売る", left(1))
    CI.hover(_G.MerchantGuildBankRepairButton)
    assert.are.equal("すべて修理", left(1))
    assert.are.equal("40|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t", left(2))
    assert.are.equal("本日のギルド銀行修理の残額:", left(3))
    assert.are.equal("自己負担額:", left(5))
    CI.guildRepair.personal = false
    CI.hover(_G.MerchantGuildBankRepairButton)
    assert.are.equal("全修理には資金が足りない", left(5))
  end)

  it("the filter dropdown: ALL and ITEM_BIND_ON_EQUIP are Japanese, a class or spec name stays English", function()
    CI.openMerchant()
    local text = _G.MerchantFrame.FilterDropdown.Text
    assert.are.equal("すべて", text:GetText())
    CI.setFilter("BOE")
    assert.are.equal("装備すると魂縛される", text:GetText())
    CI.setFilter("CLASS")
    assert.are.equal("Warrior", text:GetText())
    CI.setFilter("SPEC")
    assert.are.equal("Arms", text:GetText())
    CI.setFilter("ALL")
    assert.are.equal("すべて", text:GetText())
    alt(true)
    assert.are.equal("All", text:GetText())
    alt(false)
  end)

  it("the title goes through Labels.title: a second SetTitle(MERCHANT_BUYBACK) keeps the Japanese, and"
    .. " a SetTitle with the NPC's name drops it, with no writer in between", function()
    CI.openMerchant()
    CI.merchantTab(2)
    assert.are.equal("商人の買い戻し", title():GetText())
    _G.MerchantFrame:SetTitle(_G.MERCHANT_BUYBACK)
    assert.are.equal("商人の買い戻し", title():GetText())
    _G.MerchantFrame:SetTitle("Merchant") -- an NPC called "Merchant": a dictionary word, never this title's
    assert.are.equal("Merchant", title():GetText())
    assert.is_nil(SS.get("merchant", "ui.title"))
  end)

  it("a moved dropdown or title degrades to English with no error (type guards)", function()
    _G.MerchantFrame.FilterDropdown.Text = "moved"
    assert.are.equal(0, WFJ.Merchant.onFilterText())
    _G.MerchantFrame.TitleContainer = "moved"
    WFJ.Compat.declare("merchant", "nameText", { "MerchantNameText", "MerchantFrameTitleText",
      "MerchantFrame.TitleContainer.TitleText" })
    assert.are.equal(0, WFJ.Merchant.onBuybackInfo())
  end)
end)
