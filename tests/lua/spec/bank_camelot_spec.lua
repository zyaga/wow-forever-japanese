-- the bank window on the Forever (camelot) client: the mainline BankPanel inside camelot's BankFrame.
-- Static words at init; the title stays English (a bare Bank label ships as the English); the lock prompt after
-- Refresh; the deposit checkboxes after Init; pooled bag buttons, page tabs and bank tabs registered as help-tooltip
-- owners after their writers. Names (a bag, a bank tab the player named) stay English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local CI = require("tests.lua.spec.stub_camelot_inventory")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Bank.lua"

local UI = {
  BANK = { "Bank", "銀行" },
  COSTS_LABEL = { "Cost:", "費用:" },
  BAGSLOTTEXT_COLON = { "Bag Slots:", "バッグスロット:" },
  BANKSLOTPURCHASE = { "Purchase", "購入" },
  BANK_WITHDRAW_MONEY_BUTTON_LABEL = { "Withdraw", "引き出す" },
  BANK_DEPOSIT_MONEY_BUTTON_LABEL = { "Deposit", "預ける" },
  BANK_BAG = { "Bag Slot", "バッグスロット" },
  BANK_BAG_PURCHASE = { "Purchasable Bag Slot", "購入可能なバッグスロット" },
  PAGE_NUMBER = { "Page %d", "%dページ" },
  BAG_CLEANUP_BANK = { "Clean Up Bank", "銀行を整理" },
  BANK_LOCKED_REASON_BANK_DISABLED = { "This bank is currently unavailable.", "この銀行は現在利用できない。" },
  BANK_LOCKED_REASON_BANK_CONVERSION_FAILED = { "Bank conversion failed. Please relog to try again.",
    "銀行の変換に失敗した。再ログインしてやり直すこと。" },
  BANK_TAB_ASSIGN_EXPANSION_HEADER = { "Expansion:", "拡張:" },
  BANK_TAB_DEPOSIT_SETTINGS_HEADER = { "Assign to tab:", "タブに割り当て:" },
  BANK_TAB_CLEANUP_SETTINGS_HEADER = { "Cleanup:", "整理:" },
  BANK_TAB_ASSIGN_EQUIPMENT_CHECKBOX = { "Equipment", "装備品" },
  BANK_TAB_ASSIGN_CONSUMABLES_CHECKBOX = { "Consumables", "消耗品" },
  BANK_TAB_ASSIGN_PROFESSION_GOODS_CHECKBOX = { "Profession Goods", "専門職用品" },
  BANK_TAB_ASSIGN_REAGENTS_CHECKBOX = { "Reagents", "素材" },
  BANK_TAB_ASSIGN_JUNK_CHECKBOX = { "Junk", "ガラクタ" },
  BANK_TAB_IGNORE_IN_CLEANUP_CHECKBOX = { "Ignore this tab", "このタブを無視" },
  BANK_TAB_TOOLTIP_CLICK_INSTRUCTION = { "<Right-click for settings>", "<右クリックで設定>" },
}

describe("the bank on the Forever client", function()
  local WFJ

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function left(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
  local function bank() return _G.BankFrame end
  local function panel() return _G.BankFrame.BankPanel end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    for key, pair in pairs(UI) do _G[key] = pair[1] end -- the client's GlobalStrings, read by its XML
    CI.install()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    WFJ.Labels.forbidNames(WFJ.Bank.NEVER_TOUCH)
    assert.is_true(WFJ.Bank.init())
  end)

  after_each(function()
    H.uiTeardown()
    CI.teardown()
  end)

  it("the static words are Japanese from init", function()
    assert.are.equal("費用:", bank().BagCost:GetText())
    assert.are.equal("バッグスロット:", bank().BagText:GetText())
    assert.are.equal("購入", panel().PurchaseButton:GetText())
    assert.are.equal("引き出す", panel().MoneyFrame.WithdrawButton:GetText())
    assert.are.equal("預ける", panel().MoneyFrame.DepositButton:GetText())
    assert.are.equal("費用:", panel().PurchasePrompt.TabCostFrame.TabCost:GetText())
    assert.are.equal("購入", panel().PurchasePrompt.TabCostFrame.PurchaseButton:GetText())
    local menu = panel().TabSettingsMenu.DepositSettingsMenu
    assert.are.equal("拡張:", menu.AssignExpansionHeader:GetText())
    assert.are.equal("タブに割り当て:", menu.AssignSettingsHeader:GetText())
    assert.are.equal("整理:", menu.CleanUpSettingsHeader:GetText())
    assert.are.equal(WFJ.Font.PATH, (bank().BagText:GetFont()))
    assert.are.equal("Expand your bank", panel().PurchasePrompt.Title:GetText()) -- server data, never ours
    alt(true)
    assert.are.equal("Bag Slots:", bank().BagText:GetText())
    alt(false)
    assert.is_false(WFJ.Bank.init()) -- once
    assert.is_nil(Stub.hooks["BankFrame:SetTitle"]) -- the title is never hooked
  end)

  it("the title stays the English \"Bank\" (a bare Bank label ships as the English), even"
    .. " with BANK in the dictionary; the explicit BankFrameTitleText and the search box are never written", function()
    CI.openBank()
    local title = bank().TitleContainer.TitleText
    assert.are.equal("Bank", title:GetText())
    assert.are.equal(0, title.calls.addonSetText)
    CI.closeBank()
    assert.are.equal("Bank", title:GetText())
    assert.are.equal(0, _G.BankFrameTitleText.calls.addonSetText)
    assert.are.equal("Bank", _G.BankItemSearchBox:GetText())
    assert.are.equal(0, _G.BankItemSearchBox.calls.addonSetText)
  end)

  it("pooled bag buttons: an empty or purchasable slot's tooltip is Japanese, a slot holding a bag is an item"
    .. " tooltip and stays English; the pool is re-walked on every refresh", function()
    CI.openBank()
    local buttons = CI.bankBagButtons()
    assert.are.equal(6, #buttons)
    CI.hover(buttons[1])
    assert.are.equal("バッグスロット", left(1))
    CI.hover(buttons[2])
    assert.are.equal("購入可能なバッグスロット", left(1))
    CI.leave()
    CI.bagContents[2] = "Bag Slot" -- a bag named like a dictionary word
    bank():RefreshBagButtons()
    CI.hover(CI.bankBagButtons()[1])
    assert.are.equal("Bag Slot", left(1))
    CI.purchasedBags = 3
    bank():RefreshBagButtons()
    CI.hover(CI.bankBagButtons()[2])
    assert.are.equal("バッグスロット", left(1))
  end)

  it("page tabs show their page number in Japanese, the number verbatim", function()
    CI.pages = 3
    CI.openBank()
    local tabs = CI.bankPageTabs()
    assert.are.equal(3, #tabs)
    CI.hover(tabs[3])
    assert.are.equal("3ページ", left(1))
    alt(true)
    assert.are.equal("Page 3", left(1))
    alt(false)
  end)

  it("the clean-up button's tooltip is Japanese", function()
    CI.openBank()
    CI.hover(panel().AutoSortButton)
    assert.are.equal("銀行を整理", left(1))
  end)

  it("the lock prompt shows the locked reason in Japanese after Refresh", function()
    CI.lockReason = "disabled"
    CI.openBank()
    assert.are.equal("この銀行は現在利用できない。", panel().LockPrompt.PromptText:GetText())
    CI.lockReason = "failed"
    panel().LockPrompt:Refresh()
    assert.are.equal("銀行の変換に失敗した。再ログインしてやり直すこと。", panel().LockPrompt.PromptText:GetText())
  end)

  it("the deposit checkboxes are Japanese after every Init (their text is rewritten on each show)", function()
    local boxes = panel().TabSettingsMenu.DepositSettingsMenu.DepositSettingsCheckboxes
    boxes[1]:Show()
    assert.are.equal("装備品", boxes[1].Text:GetText())
    boxes[1]:Show()
    assert.are.equal("装備品", boxes[1].Text:GetText())
    boxes[6]:Show()
    assert.are.equal("このタブを無視", boxes[6].Text:GetText())
    alt(true)
    assert.are.equal("Ignore this tab", boxes[6].Text:GetText())
    alt(false)
  end)

  it("bank tabs (a client without player bags in the bank): the player's tab name stays English, the click"
    .. " instruction is Japanese", function()
    CI.tabs = { "Bank", "Consumables" } -- tab names that are dictionary words
    CI.openBank()
    local tabs = CI.bankTabs()
    assert.are.equal(2, #tabs)
    CI.hover(tabs[1])
    assert.are.equal("Bank", left(1))
    assert.are.equal("<右クリックで設定>", left(2))
    CI.hover(tabs[2])
    assert.are.equal("Consumables", left(1))
  end)

  it("a moved panel, pool or prompt degrades to English with no error (type guards)", function()
    assert.are.equal(0, WFJ.Bank.onBagButtons({ itemButtonBagPool = { EnumerateActive = "moved" } }))
    assert.are.equal(0, WFJ.Bank.onPageTabs("moved"))
    assert.are.equal(0, WFJ.Bank.onBankTabs({}))
    assert.are.equal(0, WFJ.Bank.onCheckboxInit("moved"))
    panel().LockPrompt.PromptText = "moved"
    assert.has_no.errors(function() WFJ.Bank.onLockPrompt() end)
  end)

  it("with the panel moved away, init still shows the static words and installs no camelot hook", function()
    H.uiTeardown()
    CI.teardown()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    for key, pair in pairs(UI) do _G[key] = pair[1] end
    CI.install()
    _G.BankFrame.BankPanel = "moved"
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    assert.has_no.errors(function() WFJ.Bank.init() end)
    assert.are.equal("費用:", _G.BankFrame.BagCost:GetText())
    assert.is_nil(Stub.hooks["BankFrame:SetTitle"])
  end)
end)
