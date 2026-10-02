-- The mailbox's static labels before first show, the inbox expiry text, the open
-- letter and its invoice, the send-mail money text and C.O.D. error, Open All, the mail help tooltips, and the widgets
-- UI/Mail.lua must never record. The client is Forever's Blizzard_MailFrame, replayed by tests/lua/spec/stub_mail.lua
-- (M.installCamelot); the template titles and the method hooks are pinned in mail_camelot_spec.lua.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local MailStub = require("tests.lua.spec.stub_mail")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Mail.lua"

-- key → { English the client holds, Japanese }
local UI = {
  INBOX = { "Inbox", "受信箱" }, SENDMAIL = { "Send Mail", "郵便を送る" }, OPENMAIL = { "Open Mail", "郵便を開く" },
  TRIAL_RESTRICTED = { "You need to upgrade your account to access this feature.",
    "この機能を利用するにはアカウントのアップグレードが必要です。" },
  INBOX_TOO_MUCH_MAIL = { "Your inbox is full.", "受信箱がいっぱいです。" },
  INBOX_TOO_MUCH_MAIL_TOOLTIP = { "Not all of your mail can be displayed.|nPlease delete some mail to make room.",
    "すべての郵便を表示できません。|n郵便を削除して空きを作ってください。" },
  PREV = { "Prev", "前へ" }, NEXT = { "Next", "次へ" },
  OPEN_ALL_MAIL_BUTTON = { "Open All", "すべて開く" }, OPEN_ALL_MAIL_BUTTON_OPENING = { "Opening...", "開封中..." },
  MAIL_TO_LABEL = { "To:", "宛先:" }, SEND_MAIL_COST = { "Postage:", "郵送料:" },
  MAIL_SUBJECT_LABEL = { "Subject:", "件名:" }, SEND_MONEY = { "Send Money", "送金" }, COD = { "C.O.D.", "代引き" },
  CANCEL = { "Cancel", "キャンセル" }, SEND_LABEL = { "Send", "送信" },
  TAKE_ATTACHMENTS = { "Take Attachments:", "添付物を受け取る:" }, FROM = { "From:", "差出人:" },
  REPORT_SPAM = { "Report Player", "プレイヤーを通報" }, CLOSE = { "Close", "閉じる" }, DELETE = { "Delete", "削除" },
  REPLY_MESSAGE = { "Reply", "返信" }, SALE_PRICE_COLON = { "Sale Price:", "販売価格:" },
  DEPOSIT_COLON = { "Deposit:", "保証金:" }, AUCTION_HOUSE_CUT_COLON = { "Auction House Cut:", "オークション手数料:" },
  AUCTION_INVOICE_FUNDS_NOT_YET_SENT = { "Amount not yet sent", "未送金額" },
  ITEM_SOLD_COLON = { "Item Sold:", "売却したアイテム:" }, ITEM_PURCHASED_COLON = { "Item Purchased:", "購入したアイテム:" },
  PURCHASED_BY_COLON = { "Purchased By:", "購入者:" }, SOLD_BY_COLON = { "Sold By:", "販売者:" },
  AMOUNT_RECEIVED_COLON = { "Amount Received:", "受取額:" }, AMOUNT_PAID_COLON = { "Amount Paid:", "支払額:" },
  AUCTION_INVOICE_PENDING_FUNDS_COLON = { "Amount Pending:", "保留中の金額:" },
  AUCTION_INVOICE_FUNDS_DELAY = { "Estimated delivery time %s", "配達予定時間 %s" },
  BUYOUT = { "Buyout", "即決" }, HIGH_BIDDER = { "High Bidder", "最高入札者" }, PARENS_TEMPLATE = { "(%s)", "(%s)" },
  DAYS_ABBR = { "%d |4Day:Days;", "%d日" }, HOURS_ABBR = { "%d |4Hr:Hrs;", "%d時間" },
  MINUTES_ABBR = { "%d |4Min:Mins;", "%d分" }, SECONDS_ABBR = { "%d |4Sec:Secs;", "%d秒" },
  TIME_UNTIL_DELETED = { "Time until message is deleted", "郵便が削除されるまでの時間" },
  TIME_UNTIL_RETURNED = { "Time until message is returned", "郵便が返送されるまでの時間" },
  NO_ATTACHMENTS = { "No Attachments", "添付なし" }, MAIL_RETURN = { "Return", "返送" },
  AMOUNT_TO_SEND = { "Amount to send:", "送金額:" }, COD_AMOUNT = { "Cash on Delivery Amount:", "代引き金額:" },
  MAIL_COD_ERROR = { "C.O.D. must be <= %d", "代引き金額の上限: %d" },
  MAIL_COD_ERROR_COLORBLIND = { "C.O.D. must be <= %1$d%2$s", "代引き金額の上限: %1$d%2$s" },
  ATTACHMENT_TEXT = { "Drag an item here to include it with your mail", "ここにアイテムをドラッグすると郵便に添付できます" },
  ENCLOSED_MONEY = { "Enclosed amount", "同封金額" }, CASH_ON_DELIVERY = { "C.O.D.", "代引き" },
  MAIL_LETTER_TOOLTIP = { "Click to make a permanent\ncopy of this letter.", "クリックでこの手紙の\n永久コピーを作成します。" },
}

describe("the mailbox", function()
  local WFJ, S, SS

  -- no record on any surface holds this widget (a Button's record holds its ButtonText adapter)
  local function recorded(widget)
    for _, records in pairs(SS.surfaces()) do
      for _, rec in pairs(records) do
        if rec.fs == widget or (type(rec.fs) == "table" and rec.fs.button == widget) then return true end
      end
    end
    return false
  end

  local function resolve(path)
    local v = _G
    for part in path:gmatch("[^%.]+") do v = v and v[part] end
    return v
  end

  local function font(widget)
    local fs = widget.GetFontString and widget:GetFontString() or widget
    return (fs:GetFont())
  end

  local function line(i) return _G["GameTooltipTextLeft" .. i] end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    MailStub.installCamelot()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    S, SS = WFJ.Settings, WFJ.SurfaceState
    assert.is_true(WFJ.Mail.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
  end)

  it("static labels are Japanese at init, before the first show; the tabs measure the Japanese", function()
    assert.are.equal("受信箱", _G.MailFrameTab1:GetText())
    assert.are.equal("郵便を送る", _G.MailFrameTab2:GetText())
    assert.is_nil(_G.MailFrameTab1.measured) -- no OnShow has run yet
    MailStub.camelotOpenMailbox()
    assert.are.equal("受信箱", _G.MailFrameTab1.measured)
    assert.are.equal("郵便を送る", _G.MailFrameTab2.measured)
    assert.are.equal(WFJ.Font.PATH, font(_G.MailFrameTab1))
    for name, ja in pairs({ MailFrameTrialError = "この機能を利用するにはアカウントのアップグレードが必要です。",
      InboxTooMuchMailText = "受信箱がいっぱいです。", SendMailSendMoneyButtonText = "送金", SendMailCODButtonText = "代引き",
      SendMailCancelButton = "キャンセル", SendMailMailButton = "送信", OpenMailSenderLabel = "差出人:",
      OpenMailSubjectLabel = "件名:", OpenMailReportSpamButton = "プレイヤーを通報", OpenMailCancelButton = "閉じる",
      OpenMailReplyButton = "返信", OpenMailInvoiceSalePrice = "販売価格:", OpenMailInvoiceDeposit = "保証金:",
      OpenMailInvoiceHouseCut = "オークション手数料:", OpenMailInvoiceNotYetSent = "未送金額",
      MailItem1ButtonCOD = "代引き", MailItem7ButtonCOD = "代引き", OpenAllMail = "すべて開く",
      OpenMailAttachmentText = "添付物を受け取る:", OpenMailDeleteButton = "削除", OpenMailInvoiceItemLabel = "売却したアイテム:",
      OpenMailInvoicePurchaser = "購入者:", OpenMailInvoiceAmountReceived = "受取額:" }) do
      assert.are.equal(ja, _G[name]:GetText(), name)
    end
    assert.are.equal("代引き金額:", _G.SendMailMoneyText:GetText()) -- SendMailFrame's OnLoad left the C.O.D. text
    assert.are.equal(WFJ.Font.PATH, font(_G.OpenMailSenderLabel))
  end)

  it("unnamed To: / Subject: / Postage: / Prev / Next regions translate by their exact English only", function()
    local to = _G.SendMailNameEditBox:GetRegions()
    local subject = _G.SendMailSubjectEditBox:GetRegions()
    local postage = _G.SendMailCostMoneyFrame:GetRegions()
    assert.are.equal("宛先:", to:GetText())
    assert.are.equal("件名:", subject:GetText())
    assert.are.equal("郵送料:", postage:GetText())
    assert.are.equal("前へ", _G.InboxFrame.PrevPageButton:GetRegions():GetText())
    assert.are.equal("次へ", _G.InboxFrame.NextPageButton:GetRegions():GetText())
    assert.are.equal("", _G.SendMailNameEditBox:GetText()) -- the EditBox's own text is never written
    assert.is_false(recorded(_G.SendMailNameEditBox))
  end)

  it("a red expiry translates inside its colour wrapper, one term or two", function()
    MailStub.inbox = {
      { sender = "Thrall", subject = "Hello", daysLeft = 0.25, canDelete = true }, -- binary fractions: exact seconds
      { sender = "Jaina", subject = "Hi", daysLeft = 0.5625 },
      { sender = "Rexxar", subject = "Soon", daysLeft = 1 / 2048 },
    }
    MailStub.camelotOpenMailbox()
    assert.are.equal("|cffff20206時間|r", _G.MailItem1ExpireTime:GetText())
    assert.are.equal("|cffff202013時間30分|r", _G.MailItem2ExpireTime:GetText()) -- format() leaves |4; both terms
    assert.is_not_nil(SS.get("mail", "expire2"))
    assert.are.equal("|cffff202042秒|r", _G.MailItem3ExpireTime:GetText())
    assert.are.equal(WFJ.Font.PATH, font(_G.MailItem1ExpireTime))
    assert.are.equal("Thrall", _G.MailItem1Sender:GetText())
    assert.are.equal(0, _G.MailItem1Sender.calls.SetText)

    -- a later update that writes another text on the row translates the new text (the old one is never restored)
    MailStub.inbox[1].daysLeft = 1 / 1024
    _G.InboxFrame:Update()
    assert.are.equal("|cffff20201分24秒|r", _G.MailItem1ExpireTime:GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("|cffff20201 |4Min:Mins; 24 |4Sec:Secs;|r", _G.MailItem1ExpireTime:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("|cffff20201分24秒|r", _G.MailItem1ExpireTime:GetText())
  end)

  it("a green day expiry translates with its trailing space kept", function()
    MailStub.inbox = { { sender = "Thrall", subject = "Hello", daysLeft = 3.4 } }
    MailStub.camelotOpenMailbox()
    assert.are.equal("|cff20ff203日 |r", _G.MailItem1ExpireTime:GetText())
  end)

  it("Open Mail: attachment text and Delete / Return follow OpenMail_Update", function()
    MailStub.letter = { sender = "Thrall", subject = "Hello", body = "Lok'tar", items = 0, money = 0,
      canDelete = true }
    MailStub.camelotOpenLetter()
    assert.are.equal("添付なし", _G.OpenMailAttachmentText:GetText())
    assert.are.equal("削除", _G.OpenMailDeleteButton:GetText())
    MailStub.letter = { sender = "Jaina", subject = "Gift", items = 2, money = 0, canDelete = false }
    _G.OpenMailFrame:Update()
    assert.are.equal("添付物を受け取る:", _G.OpenMailAttachmentText:GetText())
    assert.are.equal("返送", _G.OpenMailDeleteButton:GetText())
    assert.are.equal(WFJ.Font.PATH, font(_G.OpenMailDeleteButton))
    assert.are.equal("Jaina", _G.OpenMailSender.Name:GetText())
    assert.are.equal("Gift", _G.OpenMailSubject:GetText())
  end)

  it("a seller invoice: amount label and the prefixes translate; item and buyer names stay verbatim",
    function()
    MailStub.letter = { sender = "Stormwind Auction House", subject = "Auction successful: Linen Cloth",
      items = 0, money = 500, canDelete = true,
      invoice = { type = "seller", item = "Linen Cloth", player = "Raid", bid = 500, buyout = 500, count = 5 } }
    MailStub.camelotOpenLetter()
    assert.are.equal("受取額:", _G.OpenMailInvoiceAmountReceived:GetText())
    -- "Item Sold: Linen Cloth (5)" / "Purchased By: Raid": the colonPrefix form, the rest kept as the client wrote it
    assert.are.equal("売却したアイテム: Linen Cloth (5)", _G.OpenMailInvoiceItemLabel:GetText())
    assert.are.equal("購入者: Raid", _G.OpenMailInvoicePurchaser:GetText())
    assert.are.equal(WFJ.Font.PATH, font(_G.OpenMailInvoiceAmountReceived))
    assert.are.equal(WFJ.Font.PATH, font(_G.OpenMailInvoiceItemLabel))
  end)

  it("the invoice prefixes translate with the item / player name verbatim; Alt shows the client's English",
    function()
      MailStub.letter = { sender = "AH", subject = "Won", items = 1, money = 0, canDelete = true,
        invoice = { type = "buyer", item = "Linen Cloth", player = "Thrall", bid = 500, buyout = 500 } }
      MailStub.camelotOpenLetter()
      -- the buyer's "  (Buyout)" tail is part of the rest: kept as written inside the item label
      assert.are.equal("購入したアイテム: Linen Cloth  (Buyout)", _G.OpenMailInvoiceItemLabel:GetText())
      assert.are.equal("販売者: Thrall", _G.OpenMailInvoicePurchaser:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("Item Purchased: Linen Cloth  (Buyout)", _G.OpenMailInvoiceItemLabel:GetText())
      assert.are.equal("Sold By: Thrall", _G.OpenMailInvoicePurchaser:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("購入したアイテム: Linen Cloth  (Buyout)", _G.OpenMailInvoiceItemLabel:GetText())

      MailStub.letter.invoice.type = "seller_temp_invoice"
      _G.OpenMailFrame:Update()
      assert.are.equal("売却したアイテム: Linen Cloth  (Buyout)", _G.OpenMailInvoiceItemLabel:GetText())
      assert.are.equal("購入者: Thrall", _G.OpenMailInvoicePurchaser:GetText())
    end)

  it("buyer and temporary invoices: Amount Paid / Pending and the delivery delay translate", function()
    MailStub.letter = { sender = "AH", subject = "Won", items = 1, money = 0, canDelete = true,
      invoice = { type = "buyer", item = "Linen Cloth", player = "Thrall", bid = 500, buyout = 500 } }
    MailStub.camelotOpenLetter()
    assert.are.equal("支払額:", _G.OpenMailInvoiceAmountReceived:GetText())
    assert.are.equal("販売者: Thrall", _G.OpenMailInvoicePurchaser:GetText())
    MailStub.letter.invoice.type = "seller_temp_invoice"
    _G.OpenMailFrame:Update()
    assert.are.equal("保留中の金額:", _G.OpenMailInvoiceAmountReceived:GetText())
    assert.are.equal("配達予定時間 12:22", _G.OpenMailInvoiceMoneyDelay:GetText())
  end)

  it("SendMailMoneyText follows the radio choice", function()
    MailStub.camelotOpenMailbox()
    MailStub.camelotSelectTab(2)
    assert.are.equal("送金額:", _G.SendMailMoneyText:GetText())
    MailStub.radio(2)
    assert.are.equal("代引き金額:", _G.SendMailMoneyText:GetText())
    MailStub.radio(1)
    assert.are.equal("送金額:", _G.SendMailMoneyText:GetText())
    assert.are.equal(WFJ.Font.PATH, font(_G.SendMailMoneyText))
  end)

  it("the C.O.D. error written on SendMailFrame's OnShow translates, colour-blind form included", function()
    MailStub.camelotOpenMailbox()
    MailStub.camelotSelectTab(2)
    assert.are.equal("代引き金額の上限: 10000", _G.SendMailErrorText:GetText())
    MailStub.camelotSelectTab(1)
    _G.ENABLE_COLORBLIND_MODE = "1"
    MailStub.camelotSelectTab(2)
    assert.are.equal("代引き金額の上限: 10000g", _G.SendMailErrorText:GetText())
  end)

  it("Open All shows the opening text while opening and the idle text after", function()
    MailStub.camelotOpenMailbox()
    MailStub.openAllKeepsOpening = true
    MailStub.openAll()
    assert.are.equal("開封中...", _G.OpenAllMail:GetText())
    _G.OpenAllMail:StopOpening()
    assert.are.equal("すべて開く", _G.OpenAllMail:GetText())
    MailStub.openAllKeepsOpening = false
    MailStub.openAll() -- nothing to open: StartOpening ends inside StopOpening
    assert.are.equal("すべて開く", _G.OpenAllMail:GetText())
    assert.are.equal(WFJ.Font.PATH, font(_G.OpenAllMail))
  end)

  it("mail help tooltips translate; an item tooltip on an inbox row is never walked", function()
    MailStub.inbox = {
      { sender = "Thrall", subject = "Gold", daysLeft = 0.25, money = 100, canDelete = true },
      { sender = "Jaina", subject = "Cloth", daysLeft = 0.25, money = 100, itemCount = 1 },
    }
    MailStub.camelotOpenMailbox()
    MailStub.hover(_G.MailItem1ExpireTime)
    assert.are.equal("郵便が削除されるまでの時間", line(1):GetText())
    MailStub.hover(_G.MailItem2ExpireTime)
    assert.are.equal("郵便が返送されるまでの時間", line(1):GetText())
    MailStub.hover(_G.MailItem1Button)
    assert.are.equal("同封金額", line(1):GetText())
    MailStub.hover(_G.MailItem2Button)
    assert.are.equal("Linen Cloth", line(1):GetText())
    assert.are.equal("Enclosed amount", line(4):GetText())
    MailStub.hover(_G.InboxTooMuchMail)
    assert.are.equal("すべての郵便を表示できません。|n郵便を削除して空きを作ってください。", line(1):GetText())
    MailStub.hover(_G.SendMailAttachment3)
    assert.are.equal("ここにアイテムをドラッグすると郵便に添付できます", line(1):GetText())
    MailStub.hover(_G.OpenMailLetterButton)
    assert.are.equal("クリックでこの手紙の\n永久コピーを作成します。", line(1):GetText())
    assert.are.equal(WFJ.Font.PATH, (line(1):GetFont()))
  end)

  it("Alt shows English and release shows Japanese; area.interface off restores English", function()
    MailStub.inbox = { { sender = "Thrall", subject = "Hello", daysLeft = 0.25 } }
    MailStub.camelotOpenMailbox()
    MailStub.camelotSelectTab(2)
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Inbox", _G.MailFrameTab1:GetText())
    assert.are.equal("To:", _G.SendMailNameEditBox:GetRegions():GetText())
    assert.are.equal("|cffff20206 |4Hr:Hrs;|r", _G.MailItem1ExpireTime:GetText())
    assert.are.equal("Amount to send:", _G.SendMailMoneyText:GetText())
    assert.are.equal("Send Mail", _G.MailFrame.TitleContainer.TitleText:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("受信箱", _G.MailFrameTab1:GetText())
    assert.are.equal("|cffff20206時間|r", _G.MailItem1ExpireTime:GetText())
    assert.are.equal(WFJ.Font.PATH, font(_G.MailFrame.TitleContainer.TitleText))
    S.set("area.interface", false)
    assert.are.equal("Inbox", _G.MailFrameTab1:GetText())
    assert.are.equal("Amount to send:", _G.SendMailMoneyText:GetText())
    assert.are.equal("C.O.D. must be <= 10000", _G.SendMailErrorText:GetText())
    S.set("area.interface", true)
    assert.are.equal("送金額:", _G.SendMailMoneyText:GetText())
  end)

  it("never-touch widgets holding dictionary English are never recorded, and Reply copies them as written",
    function()
      assert.is_true(#WFJ.Mail.NEVER_TOUCH >= 21)
      MailStub.inbox = { { sender = "Inbox", subject = "Delete", daysLeft = 0.25 } }
      MailStub.letter = { sender = "Send Money", subject = "Reply", body = "Close", items = 0, money = 0,
        canDelete = true }
      _G.SendMailNameEditBox:SetText("Cancel")
      _G.SendMailSubjectEditBox:SetText("Send")
      for _, part in ipairs({ "Gold", "Silver", "Copper" }) do _G["SendMailMoney" .. part]:SetText("Close") end
      MailStub.camelotOpenMailbox()
      MailStub.camelotOpenLetter()
      MailStub.camelotSelectTab(2)
      MailStub.radio(2)
      MailStub.openAll()
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      for _, path in ipairs(WFJ.Mail.NEVER_TOUCH) do
        local widget = resolve(path)
        assert.is_not_nil(widget, path)
        assert.is_false(recorded(widget), path)
        if widget.calls and widget.calls.SetText then assert.are.equal(0, widget.calls.SetText, path) end
      end
      assert.are.equal("Inbox", _G.MailItem1Sender:GetText())
      assert.are.equal("Delete", _G.MailItem1Subject:GetText())
      MailStub.reply()
      assert.are.equal("Send Money", _G.SendMailNameEditBox:GetText())
      assert.are.equal("RE: Reply", _G.SendMailSubjectEditBox:GetText())
    end)

  it("hooks install once; a client without the mail frames is skipped without error", function()
    assert.is_false(WFJ.Mail.init())
    MailStub.letter = { sender = "Thrall", subject = "Hello", items = 0, money = 0, canDelete = true }
    MailStub.camelotOpenLetter()
    assert.are.equal(1, #Stub.hooks["OpenMailFrame:Update"])
    assert.are.equal(1, #Stub.hooks["InboxFrame:Update"])
    assert.are.equal("削除", _G.OpenMailDeleteButton:GetText())

    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    local bare = H.loadChunks(FILES)
    H.uiSetup(bare, UI)
    assert.has_no.errors(function() bare.Mail.init() end)
    assert.are.equal(0, bare.Mail.showStatic())
  end)
end)
