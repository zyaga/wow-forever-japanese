-- UI/GuildBank.lua over a GuildBankFrame replayed from camelot
-- blizzard_guildbankui/mainline/blizzard_guildbankui.xml (:165–720, :799–806) and .lua (Update :146–229,
-- UpdateTabBuyingInfo :251–269, UpdateTabs :271–442), load-on-demand in both load orders. Tab names stay English.
-- the tab title's access word (guildBankTab), the withdrawal limit line, and the log lines
-- (guildBankLog: a template with its quantity and time suffix, rewritten in the message frame's history).
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")

local UI = {
  GUILD_BANK = { "Guild Bank", "ギルド銀行" }, GUILD_BANK_LOG = { "Log", "ログ" },
  GUILD_BANK_MONEY_LOG = { "Money Log", "資金ログ" }, GUILD_BANK_TAB_INFO = { "Info", "情報" },
  DEPOSIT = { "Deposit", "預ける" }, WITHDRAW = { "Withdraw", "引き出す" },
  NO_GUILDBANK_TABS = { "Your guild has not purchased any guild bank space.", "ギルド銀行のタブがありません。" },
  NUM_GUILDBANK_TABS_PURCHASED = { "(%d/%d tabs purchased)", "(タブ %d/%d 購入済み)" },
  BUY_GUILDBANK_TAB = { "Buy New Guild Bank Tab", "ギルド銀行タブを購入" },
  GUILDBANK_POPUP_TEXT = { "Enter Guild Bank Tab Name:", "ギルド銀行タブの名前を入力:" },
  GUILDBANK_LOG_TITLE_FORMAT = { "%s  Log", "%s  ログ" }, GUILDBANK_INFO_TITLE_FORMAT = { "%s Info", "%s 情報" },
  GUILDBANK_TAB_FULL_ACCESS = { "|cff20ff20(Full Access)|r", "|cff20ff20(フルアクセス)|r" },
  GUILDBANK_TAB_LOCKED = { "|cffff2020(Locked)|r", "|cffff2020(ロック中)|r" },
  GUILDBANK_REMAINING_MONEY = { "Remaining Daily Withdrawals for %s:  |cffffffff%s|r",
    "%sの本日の残り引き出し:  |cffffffff%s|r" },
  UNLIMITED = { "Unlimited", "無制限" }, STACKS = { "%d |4Stack:Stacks;", "%dスタック" },
  GUILDBANK_DEPOSIT_FORMAT = { "%s deposited %s", "%sが%sを預けました" },
  GUILDBANK_MOVE_FORMAT = { "%s moved %s x %d from %s to %s", "%sが%s x %dを%sから%sへ移動しました" },
  GUILD_BANK_LOG_TIME = { "|cff009999   ( %s ago )|r", "|cff009999   ( %s前 )|r" },
  LASTONLINE_HOURS = { "%d |4hour:hours;", "%d時間" },
}
local BOB = "|cffffd200Bob|r"
local LINEN = "|cff1eff00|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|r"
local AGO = "|cff009999   ( 3 hours ago )|r"

local function en(key) return _G[key] end

local function build()
  local frame = CreateFrame("Frame", "GuildBankFrame")
  for i, key in ipairs({ "GUILD_BANK", "GUILD_BANK_LOG", "GUILD_BANK_MONEY_LOG", "GUILD_BANK_TAB_INFO" }) do
    Stub.button("GuildBankFrameTab" .. i, en(key))
  end
  C.tree(frame, { DepositButton = { button = en("DEPOSIT") }, WithdrawButton = { button = en("WITHDRAW") },
    ErrorMessage = en("NO_GUILDBANK_TABS"), TabTitle = "", LimitLabel = "", ["BuyInfo.PurchasedText"] = "" })
  local popup = CreateFrame("Frame", "GuildBankPopupFrame")
  C.tree(popup, { ["BorderBox.EditBoxHeaderText"] = en("GUILDBANK_POPUP_TEXT") })
  frame.BankTabs = { { Button = Stub.button(nil, "") }, { Button = Stub.button(nil, "") } }
  function frame.UpdateTabs(self, title) self.TabTitle.text = title end
  function frame.UpdateTabBuyingInfo(self)
    self.BuyInfo.PurchasedText.text = string.format(en("NUM_GUILDBANK_TABS_PURCHASED"), 2, 6)
  end
  function frame.Update(self) self.LimitLabel.text = "Deposit" end -- a tab named like a dictionary word
  -- GuildBankMessageFrame: a ScrollingMessageFrame (AddMessage / Clear / TransformMessages / visible lines)
  local log = CreateFrame("Frame", "GuildBankMessageFrame")
  log.history, log.callbacks = {}, {}
  log.fontObject = Stub.fontObject("Fonts\\ARIALN.TTF", 12)
  log.visibleLines = { Stub.fontString("") }
  function log.AddMessage(self, message) self.history[#self.history + 1] = message end
  function log.Clear(self) self.history = {} end
  function log.TransformMessages(self, predicate, transform)
    for i, m in ipairs(self.history) do
      if predicate(m) then self.history[i] = transform(m) end
    end
  end
  function log.GetFontObject(self) return self.fontObject end
  function log.AddOnDisplayRefreshedCallback(self, cb) self.callbacks[#self.callbacks + 1] = cb end
  function log.Refresh(self)
    local line = self.visibleLines[1]
    line.messageInfo = { message = self.history[#self.history] }
    line:SetText(self.history[#self.history] or "")
    for _, cb in ipairs(self.callbacks) do cb(self) end
  end
  return frame
end

C.suite(getfenv(1), {
  title = "the guild bank on Forever", module = "GuildBank", file = "UI/GuildBank.lua",
  addon = "Blizzard_GuildBankUI", root = "GuildBankFrame", ui = UI, build = build,
  globals = { "GuildBankFrame", "GuildBankPopupFrame", "GuildBankMessageFrame", "GuildBankFrameTab1",
    "GuildBankFrameTab2",
    "GuildBankFrameTab3", "GuildBankFrameTab4" },
  cases = {
    { "tabs, buttons, the error message and the popup header are Japanese; Alt shows English; hide releases",
      function(frame, WFJ)
        frame:Show()
        assert.are.equal("ギルド銀行", _G.GuildBankFrameTab1:GetText())
        assert.are.equal("資金ログ", _G.GuildBankFrameTab3:GetText())
        assert.are.equal("預ける", frame.DepositButton:GetText())
        assert.are.equal("ギルド銀行のタブがありません。", frame.ErrorMessage:GetText())
        assert.are.equal("ギルド銀行タブの名前を入力:", _G.GuildBankPopupFrame.BorderBox.EditBoxHeaderText:GetText())
        C.alt(WFJ, true)
        assert.are.equal("Withdraw", frame.WithdrawButton:GetText())
        C.alt(WFJ, false)
        frame:Hide()
        assert.are.equal("Deposit", frame.DepositButton:GetText())
      end },
    { "writers: the purchased count and the two whole-key tab titles translate; a tab's name does not",
      function(frame)
        frame:Show()
        frame:UpdateTabBuyingInfo()
        assert.are.equal("(タブ 2/6 購入済み)", frame.BuyInfo.PurchasedText:GetText())
        frame:UpdateTabs(en("GUILD_BANK_MONEY_LOG"))
        assert.are.equal("資金ログ", frame.TabTitle:GetText())
        frame:UpdateTabs("Deposit") -- a tab named "Deposit"
        assert.are.equal("Deposit", frame.TabTitle:GetText())
        frame:UpdateTabs(en("BUY_GUILDBANK_TAB"))
        assert.are.equal("ギルド銀行タブを購入", frame.TabTitle:GetText())
      end },
    { "guildBankTab: the access word and the log title in Japanese, the tab's name kept; Alt English",
      function(frame, WFJ)
        frame:Show()
        frame:UpdateTabs("Deposit  Log  " .. "|cff20ff20(Full Access)|r") -- a tab named "Deposit"
        assert.are.equal("Deposit  ログ  |cff20ff20(フルアクセス)|r", frame.TabTitle:GetText())
        frame:UpdateTabs("Deposit  |cffff2020(Locked)|r")
        assert.are.equal("Deposit  |cffff2020(ロック中)|r", frame.TabTitle:GetText())
        C.alt(WFJ, true)
        assert.are.equal("Deposit  |cffff2020(Locked)|r", frame.TabTitle:GetText())
        C.alt(WFJ, false)
        frame:UpdateTabs("Deposit  (Mystery)") -- no access word: the whole title stays English
        assert.are.equal("Deposit  (Mystery)", frame.TabTitle:GetText())
      end },
    { "the withdrawal limit line in Japanese with the tab name kept", function(frame, WFJ)
      frame:Show()
      frame.LimitLabel.text = "Remaining Daily Withdrawals for Deposit:  |cffffffffUnlimited|r"
      WFJ.GuildBank.show()
      assert.are.equal("Depositの本日の残り引き出し:  |cffffffff無制限|r", frame.LimitLabel:GetText())
      frame.LimitLabel.text = "Remaining Daily Withdrawals for Deposit:  |cffffffff3 Stacks|r"
      WFJ.GuildBank.show()
      assert.are.equal("Depositの本日の残り引き出し:  |cffffffff3スタック|r", frame.LimitLabel:GetText())
    end },
    { "guildBankLog: a log line with quantity and time in Japanese, names and the item link kept; Alt English",
      function(_, WFJ)
        local log = _G.GuildBankMessageFrame
        log:Clear()
        log:AddMessage(BOB .. " deposited " .. LINEN .. " x 3" .. AGO)
        log:AddMessage(BOB .. " moved " .. LINEN .. " x 2 from Deposit to Tab 2" .. AGO)
        log:AddMessage(BOB .. " sneezed" .. AGO) -- no log template: stays English
        assert.are.equal(BOB .. "が" .. LINEN .. "を預けました x 3|cff009999   ( 3時間前 )|r", log.history[1])
        assert.are.equal(BOB .. "が" .. LINEN .. " x 2をDepositからTab 2へ移動しました|cff009999   ( 3時間前 )|r",
          log.history[2])
        assert.are.equal(BOB .. " sneezed" .. AGO, log.history[3])
        log.history[3] = nil
        log:Refresh()
        assert.are.equal(WFJ.Font.PATH, log.visibleLines[1].font.path)
        C.alt(WFJ, true)
        local moved = BOB .. " moved " .. LINEN .. " x 2 from Deposit to Tab 2" .. AGO
        assert.are.equal(moved, log.visibleLines[1]:GetText())
        assert.are.equal("Fonts\\ARIALN.TTF", log.visibleLines[1].font.path)
        C.alt(WFJ, false)
        assert.are.equal(log.history[2], log.visibleLines[1]:GetText())
        log:AddMessage(BOB .. " sneezed" .. AGO) -- English on the row the Japanese had: the log's font again
        log:Refresh()
        assert.are.equal("Fonts\\ARIALN.TTF", log.visibleLines[1].font.path)
        assert.are.equal(12, log.visibleLines[1].font.size)
      end },
    { "the buy-tab tooltip translates; a tab's name tooltip does not", function(frame)
      C.tooltip(frame.BankTabs[2].Button, { en("BUY_GUILDBANK_TAB") })
      assert.are.equal("ギルド銀行タブを購入", _G.GameTooltipTextLeft1:GetText())
      C.tooltip(frame.BankTabs[1].Button, { "Deposit" })
      assert.are.equal("Deposit", _G.GameTooltipTextLeft1:GetText())
    end },
  },
  name = function(frame, WFJ) -- the limit label only ever takes GUILDBANK_REMAINING_MONEY: a bare tab name is kept
    frame:Show()
    frame:Update()
    WFJ.GuildBank.show()
    assert.are.equal("Deposit", frame.LimitLabel:GetText())
    assert.is_true(C.unrecorded(WFJ, frame.LimitLabel))
  end,
  wrong = function(frame)
    frame.WithdrawButton, frame.BankTabs, frame.BuyInfo, frame.TabTitle = 7, "tabs", true, 3
    _G.GuildBankFrameTab2 = "tab"
    return function() assert.are.equal("預ける", frame.DepositButton:GetText()) end
  end,
})
