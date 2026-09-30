-- UI/CurrencyTransfer.lua over a CurrencyTransferMenu and
-- CurrencyTransferLog replayed from blizzard_tokenui/blizzard_currencytransfer.xml (:17–131, :297, :396) and .lua
-- (:141, :240–242, :369–381, :514–518, :684). Loaded at login. Character and currency names stay English. Both
-- name-carrying templates take their `%s` as `text` (C.args; the core entry is in Core/UIStrings).
local C = require("tests.lua.spec.stub_commerce")

local UI = {
  CURRENCY_TRANSFER_MENU_TITLE = { "Transfer Currency - %s", "通貨の移動 - %s" },
  CURRENCY_TRANSFER_LOG_TITLE = { "Transfer Log", "移動ログ" },
  CURRENCY_TRANSFER_SOURCE = { "From", "移動元" }, CURRENCY_TRANSFER_AMOUNT_LABEL = { "Amount", "数量" },
  CURRENCY_TRANSFER_MAX_QUANTITY_BUTTON = { "Max", "最大" },
  CURRENCY_TRANSFER_CONFIRM_BUTTON_LABEL = { "Transfer", "移動" },
  CURRENCY_TRANSFER_LOG_EMPTY = { "No transfers found.", "移動の記録はありません。" },
  CURRENCY_TRANSFER_NEW_BALANCE_PREVIEW = { "%s's New Balance", "%sの新しい残高" },
  CURRENCY_TRANSFER_COST_TOOLTIP = { "%d currency will be lost in transfer.", "移動で%dの通貨が失われます。" },
}
local ARGS = { CURRENCY_TRANSFER_MENU_TITLE = { [1] = "text" },
  CURRENCY_TRANSFER_NEW_BALANCE_PREVIEW = { [1] = "text" } }
local GLOBALS = { "CurrencyTransferMenu", "CurrencyTransferLog" }

local function en(key) return _G[key] end

local function preview()
  local p = CreateFrame("Frame")
  C.tree(p, { Label = "", ["BalanceInfo.TransferCostDisplay"] = { frame = 1 }, ["BalanceInfo.Amount"] = "120" })
  function p.SetCharacterName(self, name) self.Label.text = en("CURRENCY_TRANSFER_NEW_BALANCE_PREVIEW"):format(name) end
  return p
end

local function build()
  local menu = C.window("CurrencyTransferMenu")
  menu:SetTitle(en("CURRENCY_TRANSFER_MENU_TITLE")) -- OnLoad writes the bare template (lua:141)
  C.tree(menu, { ["Content.SourceSelector.SourceLabel"] = en("CURRENCY_TRANSFER_SOURCE"),
    ["Content.SourceSelector.PlayerName"] = "To Max", -- a character named like a dictionary word
    ["Content.AmountSelector.TransferAmountLabel"] = en("CURRENCY_TRANSFER_AMOUNT_LABEL"),
    ["Content.AmountSelector.MaxQuantityButton"] = { button = en("CURRENCY_TRANSFER_MAX_QUANTITY_BUTTON") },
    ["Content.ConfirmButton"] = { button = en("CURRENCY_TRANSFER_CONFIRM_BUTTON_LABEL") } })
  menu.Content.SourceBalancePreview, menu.Content.PlayerBalancePreview = preview(), preview()
  local log = C.window("CurrencyTransferLog")
  C.tree(log, { EmptyLogMessage = en("CURRENCY_TRANSFER_LOG_EMPTY") })
  log:SetTitle(en("CURRENCY_TRANSFER_LOG_TITLE"))
  return menu
end

C.suite(getfenv(1), {
  title = "the currency transfer window on Forever", module = "CurrencyTransfer",
  file = "UI/CurrencyTransfer.lua", root = "CurrencyTransferMenu", ui = UI, build = build, globals = GLOBALS,
  cases = {
    { "the title keeps the currency name; the labels and the log's title and empty message are Japanese",
      function(menu, WFJ)
        C.args(WFJ, UI, ARGS)
        menu:SetTitle(en("CURRENCY_TRANSFER_MENU_TITLE"):format("Honor")) -- RefreshMenuTitle (lua:240–242)
        menu:Show()
        assert.are.equal("通貨の移動 - Honor", menu.TitleContainer.TitleText:GetText())
        assert.are.equal("移動元", menu.Content.SourceSelector.SourceLabel:GetText())
        assert.are.equal("数量", menu.Content.AmountSelector.TransferAmountLabel:GetText())
        assert.are.equal("最大", menu.Content.AmountSelector.MaxQuantityButton:GetText())
        assert.are.equal("移動", menu.Content.ConfirmButton:GetText())
        local log = _G.CurrencyTransferLog
        assert.are.equal("移動ログ", log.TitleContainer.TitleText:GetText())
        assert.are.equal("移動の記録はありません。", log.EmptyLogMessage:GetText())
        C.alt(WFJ, true)
        assert.are.equal("Transfer Currency - Honor", menu.TitleContainer.TitleText:GetText())
        C.alt(WFJ, false)
      end },
    { "each balance preview follows its SetCharacterName, the name kept; its cost display owns a tooltip",
      function(menu, WFJ)
        C.args(WFJ, UI, ARGS)
        local p = menu.Content.PlayerBalancePreview
        p:SetCharacterName("Arthas")
        assert.are.equal("Arthasの新しい残高", p.Label:GetText())
        p:SetCharacterName("Jaina")
        assert.are.equal("Jainaの新しい残高", p.Label:GetText())
        C.tooltip(p.BalanceInfo.TransferCostDisplay, { en("CURRENCY_TRANSFER_COST_TOOLTIP"):format(5) })
        assert.are.equal("移動で5の通貨が失われます。", _G.GameTooltipTextLeft1:GetText())
      end },
  },
  name = function(menu, WFJ)
    menu:Show()
    local name = menu.Content.SourceSelector.PlayerName
    assert.are.equal("To Max", name:GetText())
    assert.is_true(C.unrecorded(WFJ, name))
    assert.are.equal("120", menu.Content.PlayerBalancePreview.BalanceInfo.Amount:GetText())
  end,
  wrong = function(menu)
    menu.Content.SourceBalancePreview, menu.Content.AmountSelector = "preview", 9
    _G.CurrencyTransferLog = true
    return function(m) assert.are.equal("移動元", m.Content.SourceSelector.SourceLabel:GetText()) end
  end,
})

-- the destination line "To <player>" (CURRENCY_TRANSFER_DESTINATION, written by the selector's
-- RefreshPlayerName, blizzard_currencytransfer.lua:530–536): Japanese with the character's name kept; Alt English.
describe("the currency transfer destination line", function()
  local UI45 = { CURRENCY_TRANSFER_DESTINATION = { "To %s", "%sへ" }, CURRENCY_TRANSFER_SOURCE = { "From", "移動元" } }
  after_each(function() C.teardown({ "CurrencyTransferMenu" }) end)

  it("follows RefreshPlayerName; the name is kept", function()
    local WFJ = C.fresh({ "UI/CurrencyTransfer.lua" }, UI45)
    local menu = C.window("CurrencyTransferMenu")
    C.tree(menu, { ["Content.SourceSelector.PlayerName"] = "" })
    local selector = menu.Content.SourceSelector
    local player = "Arthas"
    function selector.RefreshPlayerName(self)
      self.PlayerName.text = en("CURRENCY_TRANSFER_DESTINATION"):format(player)
    end
    assert.is_true(WFJ.CurrencyTransfer.init())
    selector:RefreshPlayerName()
    assert.are.equal("Arthasへ", selector.PlayerName:GetText())
    C.alt(WFJ, true)
    assert.are.equal("To Arthas", selector.PlayerName:GetText())
    C.alt(WFJ, false)
    player = "Max"
    selector:RefreshPlayerName()
    assert.are.equal("Maxへ", selector.PlayerName:GetText())
  end)
end)
