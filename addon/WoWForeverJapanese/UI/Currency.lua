-- UI/Currency.lua: the character window's Currency tab on Forever (surface "currency", area "ui", ADR-016).
-- `camelot` loads blizzard_tokenui at login (blizzard_tokenui.toc: no LoadOnDemand; camelot/blizzard_tokenui.lua|xml).
-- TokenFrame is a child of CharacterFrame (camelot/blizzard_tokenui.xml:160) and one of its sub-frames
-- (blizzard_uipanels_game/camelot/characterframeconstants.lua:1; the Currency tab, camelot/characterframe.lua:72,
-- 110–116; the tab is always shown, blizzard_micromenu/camelot/mainmenubarmicrobuttonsoverrides.lua:24–28).
-- Without TokenFrame init returns false and nothing is touched.
-- Every widget is parentKey-only (dotted Compat names).
--   TokenDetailFrame (xml:230, CharacterFrameSidePaneTemplate), static labels written by the XML:
--     InactiveCheckbox.Label UNUSED (xml:239), BackpackCheckbox.Label SHOW_ON_BACKPACK (xml:264),
--     CurrencyTransferToggleButton CURRENCY_TRANSFER_TOGGLE_BUTTON_LABEL (blizzard_currencytransfer.xml:279).
--   TokenDetailFrame:Refresh (lua:524–565; OnShow :492, TokenFrame:Update :405, ClearSelectionIfMissing :512), the
--     frame's own method, post-hooked → EmptyText TOKEN_DETAIL_SELECT_PROMPT (ShowEmptyState :568–570, SetEmpty,
--     blizzard_uipanels_game/camelot/characterframe.lua:939–948) and the pooled rows' Labels (rowPools,
--     characterframe.lua:840–845, AddRow / AddWrappedRow :891–907): CURRENCY_DETAIL_TOTAL_CAP_LABEL,
--     CURRENCY_DETAIL_WEEKLY_CAP_LABEL, CURRENCY_TRANSFER_LOSS, ACCOUNT_LEVEL_CURRENCY. Rows are keyed by widget.
--   Tooltips (GameTooltip lines, UI/HelpTooltip owners, each restricted to its keys):
--     InactiveCheckbox TOKEN_MOVE_TO_UNUSED (lua:602–606); BackpackCheckbox TOKEN_SHOW_ON_BACKPACK (:626–630);
--     CurrencyTransferToggleButton's disabled reasons (blizzard_currencytransfer.lua:17–31, 92; shown by
--       UIButtonMixin:OnEnter → GameTooltip_ShowDisabledTooltip, blizzard_sharedxml/shared/button/
--       uibuttontemplate.lua:48–52);
--     each pooled list entry (TokenEntryTemplate, xml:65; ShowCurrencyTooltip lua:167–183): CURRENCY_TRANSFER_LOSS and
--       CURRENCY_BUTTON_TOOLTIP_CLICK_INSTRUCTION after the client's own currency lines (GameTooltip:
--       SetCurrencyToken), which are a name and client-table text and never match; its Content.AccountWideIcon:
--       ACCOUNT_TRANSFERRABLE_CURRENCY / ACCOUNT_LEVEL_CURRENCY (:202–207). Entries are found through
--       ScrollUtil.AddInitializedFrameCallback on TokenFrame.ScrollBox (the element factory, lua:257–290);
--     each watched-currency button on the backpack (BackpackTokenFrame.tokenPool, lua:636–640; OnEnter :759–765):
--       TOKEN_REMOVE_FROM_BACKPACK_INSTRUCTION, registered after BackpackTokenFrame:Update.
--   the client-table text (ADR-042): the pane's description, SetDescription (lua:479–482, 537;
--     characterframe.lua:873–885) writes the Description ScrollingFont, the CurrencyDescription:* family only; the
--     same text as a line of an entry's tooltip (GameTooltip:SetCurrencyToken, lua:170); and the list's header rows:
--     TokenHeaderMixin:Initialize writes `.Name` (lua:5–8), TokenSubHeaderMixin:Initialize `.Text` wrapped in the
--     highlight colour (lua:215–219), the CurrencyCategory:* family only (the colour kept).
-- Never touched: a currency's name and count (pane Title / Subtitle) and entry names.
local _, WFJ = ...
local Currency = {}
WFJ.Currency = Currency

local SURFACE = "currency"
Currency.SURFACE = SURFACE
local Compat = WFJ.Compat

local DETAIL = "TokenDetailFrame"

Currency.NEVER_TOUCH = { DETAIL .. ".Title", DETAIL .. ".Subtitle" }

local CANDIDATES = {
  frame = { "TokenFrame" }, detail = { DETAIL, "TokenFrame.DetailFrame" },
  unusedBox = { DETAIL .. ".InactiveCheckbox" }, unused = { DETAIL .. ".InactiveCheckbox.Label" },
  backpackBox = { DETAIL .. ".BackpackCheckbox" }, backpack = { DETAIL .. ".BackpackCheckbox.Label" },
  transfer = { DETAIL .. ".CurrencyTransferToggleButton" }, empty = { DETAIL .. ".EmptyText" },
  scrollBox = { "TokenFrame.ScrollBox" }, scrollUtil = { "ScrollUtil" }, backpackTokens = { "BackpackTokenFrame" },
}

local STATIC = {
  { "unused", { only = { "UNUSED" } } }, { "backpack", { only = { "SHOW_ON_BACKPACK" } } },
  { "transfer", { only = { "CURRENCY_TRANSFER_TOGGLE_BUTTON_LABEL" } } },
}
local EMPTY = { only = { "TOKEN_DETAIL_SELECT_PROMPT" } }
local ROW = { only = { "CURRENCY_DETAIL_TOTAL_CAP_LABEL", "CURRENCY_DETAIL_WEEKLY_CAP_LABEL", "CURRENCY_TRANSFER_LOSS",
  "ACCOUNT_LEVEL_CURRENCY" } }
local UNUSED_TOOLTIP = { only = { "TOKEN_MOVE_TO_UNUSED" } }
local BACKPACK_TOOLTIP = { only = { "TOKEN_SHOW_ON_BACKPACK" } }
local TRANSFER_TOOLTIP = { only = { "RETRIEVING_DATA", "CURRENCY_TRANSFER_DISABLED_MAX_QUANTITY",
  "CURRENCY_TRANSFER_DISABLED_NO_VALID_SOURCES", "CURRENCY_TRANSFER_DISABLED_UNMET_REQUIREMENTS",
  "CURRENCY_TRANSFER_IN_PROGRESS", "ERR_CURRENCY_TRANSFER_DISABLED" } }
local ENTRY_KEYS = { "CURRENCY_TRANSFER_LOSS", "CURRENCY_BUTTON_TOOLTIP_CLICK_INSTRUCTION" }
local ACCOUNT_TOOLTIP = { only = { "ACCOUNT_TRANSFERRABLE_CURRENCY", "ACCOUNT_LEVEL_CURRENCY" } }
local WATCHED_TOOLTIP = { only = { "TOKEN_REMOVE_FROM_BACKPACK_INSTRUCTION" } }

local function get(key) return Compat.get(SURFACE, key) end

local rowKey = WFJ.Labels.keyer("row.") -- a pooled row's record key: follows the widget, never its index

-- The XML labels. → the number of dictionary words found.
function Currency.showStatic()
  local n = 0
  for _, s in ipairs(STATIC) do n = n + WFJ.Labels.show(SURFACE, s[1], get(s[1]), nil, s[2]) end
  return n
end

-- hooksecurefunc target (TokenDetailFrame:Refresh). → the number of dictionary words found.
function Currency.onRefresh()
  local n = Currency.showStatic() + WFJ.Labels.show(SURFACE, "empty", get("empty"), nil, EMPTY)
  local detail = get("detail")
  local pools = type(detail) == "table" and detail.rowPools or nil
  if type(pools) == "table" and type(pools.EnumerateActive) == "function" then
    for row in pools:EnumerateActive() do
      local label = type(row) == "table" and row.Label or nil
      if type(label) == "table" then n = n + WFJ.Labels.show(SURFACE, rowKey(label), label, nil, ROW) end
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The description pane, after SetDescription. → 1 | 0
function Currency.onDescription()
  local detail = get("detail")
  local fs, refit = WFJ.Labels.scrolling(type(detail) == "table" and detail.Description or nil)
  local n = WFJ.Labels.show(SURFACE, "description", fs, refit, WFJ.Labels.families("CurrencyDescription"))
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local headerKey = WFJ.Labels.keyer("header.") -- a pooled header row's record key

-- A header row's category name: a top-level header's `.Name`, or a sub-header's `.Text` in the highlight
-- colour, which is kept around the Japanese. → 1 | 0
function Currency.showHeader(row)
  local only = WFJ.Labels.families("CurrencyCategory").only
  if type(row.Name) == "table" then
    local n = WFJ.Labels.show(SURFACE, headerKey(row), row.Name, nil, { only = only })
    WFJ.Render.updateBanner(SURFACE)
    return n
  end
  local fs = WFJ.Labels.widget(row.Text)
  local text = fs and fs:GetText()
  local open, inner, close
  if type(text) == "string" then open, inner, close = text:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$") end
  local key = inner and WFJ.UIIndex and WFJ.UIIndex:matchOnly(inner, only) or nil
  local args = key and { form = "wrapped", open = open, close = close } or nil
  if not key and not inner and type(text) == "string" then -- an uncoloured sub-header: the plain row
    key = WFJ.UIIndex and WFJ.UIIndex:matchOnly(text, only) or nil
  end
  local n = WFJ.Labels.showArgs(SURFACE, headerKey(row), fs, key, args)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- ScrollUtil's initialized-frame callback: (owner, frame, elementData), or (frame, elementData) for the frames that
-- already exist. A header row (no Content) shows its category name; an entry owns its tooltip.
function Currency.onEntry(a, b)
  local entry = a
  if a == Currency then entry = b end
  if type(entry) ~= "table" then return false end
  if type(entry.Content) ~= "table" then
    if entry.Name ~= nil or entry.Text ~= nil then Currency.showHeader(entry) end
    return false
  end
  WFJ.HelpTooltip.register(entry, WFJ.Labels.familiesWith(ENTRY_KEYS, "CurrencyDescription"))
  local icon = entry.Content.AccountWideIcon
  if type(icon) == "table" then WFJ.HelpTooltip.register(icon, ACCOUNT_TOOLTIP) end
  return true
end

-- hooksecurefunc target (BackpackTokenFrame:Update): the watched-currency buttons own a tooltip. → the number seen
function Currency.onBackpackTokens()
  local tokens = get("backpackTokens")
  local pool = type(tokens) == "table" and tokens.tokenPool or nil
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return 0 end
  local n = 0
  for token in pool:EnumerateActive() do
    if type(token) == "table" then
      WFJ.HelpTooltip.register(token, WATCHED_TOOLTIP)
      n = n + 1
    end
  end
  return n
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Currency.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  local frame, detail = get("frame"), get("detail")
  if hooked or type(frame) ~= "table" or type(detail) ~= "table" then return false end -- no TokenFrame
  hooked = true
  if type(detail.Refresh) == "function" then hooksecurefunc(detail, "Refresh", Currency.onRefresh) end
  if type(detail.SetDescription) == "function" then
    hooksecurefunc(detail, "SetDescription", Currency.onDescription)
  end
  WFJ.HelpTooltip.register(get("unusedBox"), UNUSED_TOOLTIP)
  WFJ.HelpTooltip.register(get("backpackBox"), BACKPACK_TOOLTIP)
  WFJ.HelpTooltip.register(get("transfer"), TRANSFER_TOOLTIP)
  local box, util = get("scrollBox"), get("scrollUtil")
  if type(box) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(box, Currency.onEntry, Currency, true)
  end
  local tokens = get("backpackTokens")
  if type(tokens) == "table" and type(tokens.Update) == "function" then
    hooksecurefunc(tokens, "Update", Currency.onBackpackTokens)
  end
  Currency.onBackpackTokens()
  Currency.onRefresh()
  Currency.onDescription()
  return true
end
