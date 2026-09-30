-- UI/Currency.lua over a TokenFrame / TokenDetailFrame replayed from camelot
-- blizzard_tokenui/camelot/blizzard_tokenui.xml (:65, :160, :230–264) and .lua (:167–207, :257–290, :524–570,
-- :602–640, :759–765), plus the detail pane's row pools (blizzard_uipanels_game/camelot/characterframe.lua:840–948).
-- Loaded at login. A currency's name stays English.
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")

local UI = {
  UNUSED = { "Unused", "未使用" }, SHOW_ON_BACKPACK = { "Show on Backpack", "バッグに表示" },
  CURRENCY_TRANSFER_TOGGLE_BUTTON_LABEL = { "Transfer", "移動" },
  TOKEN_DETAIL_SELECT_PROMPT = { "Select a currency to view its details.", "通貨を選ぶと詳細が表示されます。" },
  CURRENCY_DETAIL_TOTAL_CAP_LABEL = { "Maximum", "上限" },
  TOKEN_MOVE_TO_UNUSED = { "Moves this currency to the bottom of your list under the unused heading.",
    "この通貨をリストの一番下の「未使用」に移動します。" },
  CURRENCY_BUTTON_TOOLTIP_CLICK_INSTRUCTION = { "<Click to view options>", "<クリックでオプションを表示>" },
  ACCOUNT_LEVEL_CURRENCY = { "Account Currency", "アカウント通貨" },
  TOKEN_REMOVE_FROM_BACKPACK_INSTRUCTION = { "<Shift click to untrack>", "<Shiftクリックで追跡を解除>" },
  -- client-table rows (fingerprints: no global; ADR-042)
  ["CurrencyDescription:1901"] = { "Earned by defeating enemy players.", "敵プレイヤーを倒すと獲得できる。" },
  ["CurrencyCategory:1"] = { "Miscellaneous", "その他" },
  ["CurrencyCategory:2"] = { "Player vs. Player", "PvP" },
  ["CurrencyCategory:3"] = { "Unused", "カテゴリの未使用" }, -- a category English that is also the currency's Title
}
local DESC = "Earned by defeating enemy players."
local function headerRow(text) -- TokenHeaderMixin:Initialize (blizzard_tokenui.lua:5–8): `.Name`
  local row = CreateFrame("Button")
  row.Name = Stub.fontString(text)
  return row
end
local function subHeaderRow(text) -- TokenSubHeaderMixin:Initialize (:215–219): `.Text` in the highlight colour
  local row = CreateFrame("Button")
  row.Text = Stub.fontString("|cffffffff" .. text .. "|r")
  return row
end
local GLOBALS = { "TokenFrame", "TokenDetailFrame", "BackpackTokenFrame" }

local function en(key) return _G[key] end

local function build()
  local frame = CreateFrame("Frame", "TokenFrame")
  frame.ScrollBox = Stub.scrollBox()
  local detail = CreateFrame("Frame", "TokenDetailFrame")
  C.tree(detail, { ["InactiveCheckbox.Label"] = en("UNUSED"), ["BackpackCheckbox.Label"] = en("SHOW_ON_BACKPACK"),
    CurrencyTransferToggleButton = { button = en("CURRENCY_TRANSFER_TOGGLE_BUTTON_LABEL") }, EmptyText = "",
    Title = "Unused", Subtitle = "" }) -- a currency named like a dictionary word
  detail.Description = Stub.scrollingFont("") -- ScrollingFontTemplate (blizzard_tokenui.xml)
  function detail.SetDescription(self, text) self.Description:SetText(text) end -- characterframe.lua:873–885
  detail.rowPools = C.pool(function() return { Label = Stub.fontString("") } end)
  detail.empty = true
  function detail.Refresh(self)
    self.EmptyText.text = self.empty and en("TOKEN_DETAIL_SELECT_PROMPT") or ""
    if type(self.rowPools) ~= "table" then return end -- a spec moved the pools
    self.rowPools:ReleaseAll()
    if not self.empty then self.rowPools:Acquire().Label.text = en("CURRENCY_DETAIL_TOTAL_CAP_LABEL") end
  end
  local tokens = CreateFrame("Frame", "BackpackTokenFrame")
  tokens.tokenPool = C.pool(function() return CreateFrame("Button") end)
  function tokens.Update(self) self.tokenPool:ReleaseAll(); self.tokenPool:Acquire() end
  return frame
end

local function entry()
  local e = CreateFrame("Button")
  C.tree(e, { ["Content.AccountWideIcon"] = { frame = 1 } })
  return e
end

C.suite(getfenv(1), {
  title = "the Currency tab on Forever", module = "Currency", file = "UI/Currency.lua",
  root = "TokenFrame", ui = UI, build = build, globals = GLOBALS,
  cases = {
    { "the detail pane's checkboxes, transfer button, empty prompt and pooled rows are Japanese", function(_, WFJ)
      local detail = _G.TokenDetailFrame
      assert.are.equal("未使用", detail.InactiveCheckbox.Label:GetText())
      assert.are.equal("バッグに表示", detail.BackpackCheckbox.Label:GetText())
      assert.are.equal("移動", detail.CurrencyTransferToggleButton:GetText())
      detail:Refresh()
      assert.are.equal("通貨を選ぶと詳細が表示されます。", detail.EmptyText:GetText())
      detail.empty = false
      detail:Refresh()
      local row = detail.rowPools:EnumerateActive()()
      assert.are.equal("上限", row.Label:GetText())
      C.alt(WFJ, true)
      assert.are.equal("Maximum", row.Label:GetText())
      C.alt(WFJ, false)
    end },
    { "tooltips: the checkboxes, a list entry and its account icon, a watched currency on the backpack",
      function(frame)
        local detail = _G.TokenDetailFrame
        C.tooltip(detail.InactiveCheckbox, { en("TOKEN_MOVE_TO_UNUSED") })
        assert.are.equal("この通貨をリストの一番下の「未使用」に移動します。", _G.GameTooltipTextLeft1:GetText())
        local e = entry()
        frame.ScrollBox:initFrame(e, {})
        C.tooltip(e, { "Honor", en("CURRENCY_BUTTON_TOOLTIP_CLICK_INSTRUCTION") })
        assert.are.equal("Honor", _G.GameTooltipTextLeft1:GetText())
        assert.are.equal("<クリックでオプションを表示>", _G.GameTooltipTextLeft2:GetText())
        C.tooltip(e.Content.AccountWideIcon, { en("ACCOUNT_LEVEL_CURRENCY") })
        assert.are.equal("アカウント通貨", _G.GameTooltipTextLeft1:GetText())
        _G.BackpackTokenFrame:Update()
        local token = _G.BackpackTokenFrame.tokenPool:EnumerateActive()()
        C.tooltip(token, { "Honor", en("TOKEN_REMOVE_FROM_BACKPACK_INSTRUCTION") })
        assert.are.equal("<Shiftクリックで追跡を解除>", _G.GameTooltipTextLeft2:GetText())
      end },
    { "the description pane is a CurrencyDescription row's Japanese; other text stays English",
      function(_, WFJ)
        local detail = _G.TokenDetailFrame
        detail:SetDescription(DESC)
        assert.are.equal("敵プレイヤーを倒すと獲得できる。", detail.Description:GetText())
        assert.are.equal(detail.Description.fs:GetStringHeight(), detail.Description.container.height)
        C.alt(WFJ, true)
        assert.are.equal(DESC, detail.Description:GetText())
        C.alt(WFJ, false)
        assert.are.equal("敵プレイヤーを倒すと獲得できる。", detail.Description:GetText())
        detail:SetDescription("Unused") -- a dictionary word and a category's English, but no description row
        assert.are.equal("Unused", detail.Description:GetText())
        detail:SetDescription("A currency nobody translated.")
        assert.are.equal("A currency nobody translated.", detail.Description:GetText())
      end },
    { "list headers: a CurrencyCategory row's Japanese, the sub-header's colour kept; others English",
      function(frame, WFJ)
        local misc, dungeon = headerRow("Miscellaneous"), headerRow("Dungeon and Raid")
        frame.ScrollBox:initFrame(misc, {})
        frame.ScrollBox:initFrame(dungeon, {})
        assert.are.equal("その他", misc.Name:GetText())
        assert.are.equal("Dungeon and Raid", dungeon.Name:GetText())
        local pvp, plain = subHeaderRow("Player vs. Player"), subHeaderRow("Legacy")
        frame.ScrollBox:initFrame(pvp, {})
        frame.ScrollBox:initFrame(plain, {})
        assert.are.equal("|cffffffffPvP|r", pvp.Text:GetText())
        assert.are.equal("|cffffffffLegacy|r", plain.Text:GetText())
        local bare = subHeaderRow("Player vs. Player") -- a sub-header written without the colour
        bare.Text:SetText("Player vs. Player")
        frame.ScrollBox:initFrame(bare, {})
        assert.are.equal("PvP", bare.Text:GetText())
        local shown = headerRow("Show on Backpack") -- a dictionary word that is no CurrencyCategory row
        frame.ScrollBox:initFrame(shown, {})
        assert.are.equal("Show on Backpack", shown.Name:GetText())
        C.alt(WFJ, true)
        assert.are.equal("Miscellaneous", misc.Name:GetText())
        assert.are.equal("|cffffffffPlayer vs. Player|r", pvp.Text:GetText())
        C.alt(WFJ, false)
        assert.are.equal("|cffffffffPvP|r", pvp.Text:GetText())
      end },
    { "an entry's tooltip shows the currency description line in Japanese, the name kept", function(frame)
      local e = entry()
      frame.ScrollBox:initFrame(e, {})
      C.tooltip(e, { "Honor", DESC, en("CURRENCY_BUTTON_TOOLTIP_CLICK_INSTRUCTION") })
      assert.are.equal("Honor", _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("敵プレイヤーを倒すと獲得できる。", _G.GameTooltipTextLeft2:GetText())
      assert.are.equal("<クリックでオプションを表示>", _G.GameTooltipTextLeft3:GetText())
    end },
  },
  name = function(_, WFJ)
    local title = _G.TokenDetailFrame.Title
    _G.TokenDetailFrame:Refresh()
    assert.are.equal("Unused", title:GetText())
    assert.are.equal(0, WFJ.Labels.show("currency", "x", title))
    assert.is_true(C.unrecorded(WFJ, title))
  end,
  wrong = function()
    local detail = _G.TokenDetailFrame
    detail.rowPools, detail.BackpackCheckbox = "pools", 4
    _G.ScrollUtil, _G.BackpackTokenFrame.tokenPool = "moved", true
    return function()
      detail:Refresh()
      assert.are.equal("未使用", detail.InactiveCheckbox.Label:GetText())
      assert.are.equal("通貨を選ぶと詳細が表示されます。", detail.EmptyText:GetText())
    end
  end,
})
