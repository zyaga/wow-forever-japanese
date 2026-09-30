-- UI/CurrencyTransfer.lua: the account currency transfer window and its log on Forever (surface
-- "currencytransfer", area "ui", ADR-016). blizzard_tokenui loads blizzard_currencytransfer.lua|xml at login
-- on `camelot` (blizzard_tokenui.toc). CurrencyTransferMenu (xml:297, ButtonFrameTemplate) opens from the Currency
-- tab's detail pane: TokenDetailFrame.CurrencyTransferToggleButton:OnClick → the menu's CurrencyTransferRequested
-- event → ShowUIPanel (lua:49–55, 169–187). CurrencyTransferLog is built hidden inside TokenFrame
-- (camelot/blizzard_tokenui.xml:224); its only opener, CurrencyTransferLogToggleButtonTemplate (xml:372,
-- lua:782–786), is never instantiated in the camelot load set, so the log's title and empty message are shown
-- defensively and its entries are left alone. Without either frame init returns false.
-- Every widget is parentKey-only (dotted Compat names).
--   Title: CurrencyTransferMenu:SetTitle(CURRENCY_TRANSFER_MENU_TITLE:format(currency name)) (RefreshMenuTitle,
--     lua:240–242; the bare template written at load, :141, is replaced before the window is ever shown), through
--     Labels.title, the currency name kept as written (Core/UIStrings ARGS `text`); CurrencyTransferLog:SetTitle(
--     CURRENCY_TRANSFER_LOG_TITLE) (:684).
--   Static (XML text=): Content.SourceSelector.SourceLabel CURRENCY_TRANSFER_SOURCE (xml:17), Content.AmountSelector
--     .TransferAmountLabel CURRENCY_TRANSFER_AMOUNT_LABEL (:58) and .MaxQuantityButton
--     CURRENCY_TRANSFER_MAX_QUANTITY_BUTTON (:72), Content.ConfirmButton / CancelButton (:85, :92, :214, :220),
--     CurrencyTransferLog.EmptyLogMessage CURRENCY_TRANSFER_LOG_EMPTY (:396). Shown at init and on the menu's OnShow.
--   Writer: each balance preview's own SetCharacterName (lua:379–381; called as self:… from
--     SetCharacterAndCurrencyBalance :369–373) → Label, CURRENCY_TRANSFER_NEW_BALANCE_PREVIEW with the character's
--     name kept as written.
--   Tooltip: each preview's BalanceInfo.TransferCostDisplay (xml:131; OnEnter lua:514–518)
--     CURRENCY_TRANSFER_COST_TOOLTIP.
--   Content.SourceSelector.PlayerName = CURRENCY_TRANSFER_DESTINATION ("To <player>") written by the
--     selector's RefreshPlayerName (self:RefreshPlayerName() from its OnShow, lua:530–536), post-hooked on the
--     instance, restricted to that key, the player's name kept (`text`).
-- Never touched: the source dropdown (character names),
-- the amount EditBox, the balances, the log's entries (character names).
local _, WFJ = ...
local CurrencyTransfer = {}
WFJ.CurrencyTransfer = CurrencyTransfer

local SURFACE = "currencytransfer"
CurrencyTransfer.SURFACE = SURFACE
local Compat = WFJ.Compat

local CONTENT = "CurrencyTransferMenu.Content"

CurrencyTransfer.NEVER_TOUCH = { CONTENT .. ".AmountSelector.InputBox",
  CONTENT .. ".SourceBalancePreview.BalanceInfo.Amount", CONTENT .. ".PlayerBalancePreview.BalanceInfo.Amount" }

local CANDIDATES = {
  menu = { "CurrencyTransferMenu" }, log = { "CurrencyTransferLog" },
  source = { CONTENT .. ".SourceSelector.SourceLabel" }, amount = { CONTENT .. ".AmountSelector.TransferAmountLabel" },
  max = { CONTENT .. ".AmountSelector.MaxQuantityButton" }, confirm = { CONTENT .. ".ConfirmButton" },
  cancel = { CONTENT .. ".CancelButton" }, selector = { CONTENT .. ".SourceSelector" },
  destination = { CONTENT .. ".SourceSelector.PlayerName" }, logEmpty = { "CurrencyTransferLog.EmptyLogMessage" },
  sourcePreview = { CONTENT .. ".SourceBalancePreview" }, playerPreview = { CONTENT .. ".PlayerBalancePreview" },
}

local STATIC = {
  { "source", { only = { "CURRENCY_TRANSFER_SOURCE" } } },
  { "amount", { only = { "CURRENCY_TRANSFER_AMOUNT_LABEL" } } },
  { "max", { only = { "CURRENCY_TRANSFER_MAX_QUANTITY_BUTTON" } } },
  { "confirm", { only = { "CURRENCY_TRANSFER_CONFIRM_BUTTON_LABEL" } } },
  { "cancel", { only = { "CURRENCY_TRANSFER_CANCEL_BUTTON_LABEL" } } },
  { "logEmpty", { only = { "CURRENCY_TRANSFER_LOG_EMPTY" } } },
  { "destination", { only = { "CURRENCY_TRANSFER_DESTINATION" } } },
}
local PREVIEWS = { "sourcePreview", "playerPreview" }
local MENU_TITLE = { only = { "CURRENCY_TRANSFER_MENU_TITLE" } }
local LOG_TITLE = { only = { "CURRENCY_TRANSFER_LOG_TITLE" } }
local PREVIEW = { only = { "CURRENCY_TRANSFER_NEW_BALANCE_PREVIEW" } }
local COST_TOOLTIP = { only = { "CURRENCY_TRANSFER_COST_TOOLTIP" } }

local function get(key) return Compat.get(SURFACE, key) end

-- One balance preview's label after its SetCharacterName. → 1 | 0
function CurrencyTransfer.showPreview(key)
  local preview = get(key)
  return WFJ.Labels.show(SURFACE, key, type(preview) == "table" and preview.Label or nil, nil, PREVIEW)
end

-- The XML labels and both previews (the menu's OnShow, and init). → the number of dictionary words found.
function CurrencyTransfer.onShow()
  local n = 0
  for _, s in ipairs(STATIC) do n = n + WFJ.Labels.show(SURFACE, s[1], get(s[1]), nil, s[2]) end
  for _, key in ipairs(PREVIEWS) do n = n + CurrencyTransfer.showPreview(key) end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function CurrencyTransfer.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local menu = get("menu")
  if hooked or type(menu) ~= "table" then return false end -- no CurrencyTransferMenu
  hooked = true
  WFJ.Labels.title(SURFACE, menu, MENU_TITLE)
  WFJ.Labels.title(SURFACE, get("log"), LOG_TITLE, "logTitle")
  if type(menu.HookScript) == "function" then menu:HookScript("OnShow", CurrencyTransfer.onShow) end
  for _, key in ipairs(PREVIEWS) do
    local preview = get(key)
    if type(preview) == "table" then
      if type(preview.SetCharacterName) == "function" then
        hooksecurefunc(preview, "SetCharacterName", function() CurrencyTransfer.showPreview(key) end)
      end
      local info = preview.BalanceInfo
      WFJ.HelpTooltip.register(type(info) == "table" and info.TransferCostDisplay or nil, COST_TOOLTIP)
    end
  end
  local selector = get("selector")
  if type(selector) == "table" and type(selector.RefreshPlayerName) == "function" then
    hooksecurefunc(selector, "RefreshPlayerName", CurrencyTransfer.onShow)
  end
  CurrencyTransfer.onShow()
  return true
end
