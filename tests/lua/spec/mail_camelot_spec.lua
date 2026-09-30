-- Blizzard_MailFrame's template titles after MailFrameTab_OnClick and OpenMailFrame's
-- OnShow, the inbox / open-mail widgets after the InboxFrame:Update / OpenMailFrame:Update method hooks, and the
-- parentKey-only page buttons. The rest of the mailbox (labels, expiry, invoice, help, never-touch) is
-- ui_windows_mail_spec.lua, on the same Forever stub.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local MailStub = require("tests.lua.spec.stub_mail")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Mail.lua"

local UI = {
  INBOX = { "Inbox", "受信箱" }, SENDMAIL = { "Send Mail", "郵便を送る" }, OPENMAIL = { "Open Mail", "郵便を開く" },
  PREV = { "Prev", "前へ" }, NEXT = { "Next", "次へ" }, CANCEL = { "Cancel", "キャンセル" },
  TAKE_ATTACHMENTS = { "Take Attachments:", "添付物を受け取る:" }, NO_ATTACHMENTS = { "No Attachments", "添付なし" },
  DELETE = { "Delete", "削除" }, MAIL_RETURN = { "Return", "返送" },
  HOURS_ABBR = { "%d |4Hr:Hrs;", "%d時間" }, DAYS_ABBR = { "%d |4Day:Days;", "%d日" },
  AMOUNT_TO_SEND = { "Amount to send:", "送金額:" }, COD_AMOUNT = { "Cash on Delivery Amount:", "代引き金額:" },
  ITEM_SOLD_COLON = { "Item Sold:", "売却したアイテム:" }, PURCHASED_BY_COLON = { "Purchased By:", "購入者:" },
  AMOUNT_RECEIVED_COLON = { "Amount Received:", "受取額:" },
  SOLD_BY_COLON = { "Sold By:", "販売者:" }, AUCTION_HOUSE_MAIL_MULTIPLE_SELLERS = { "Multiple Sellers", "複数の販売者" },
  MAIL_MULTIPLE_ITEMS = { "Multiple items", "複数のアイテム" },
}

describe("the mailbox on Forever's Blizzard_MailFrame", function()
  local WFJ, S

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function title(frame) return frame.TitleContainer.TitleText:GetText() end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    MailStub.installCamelot()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    S = WFJ.Settings
    assert.is_true(WFJ.Mail.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
  end)

  it("the inbox / send title follows MailFrameTab_OnClick; the open-mail title follows OpenMailFrame's OnShow",
    function()
      MailStub.camelotOpenMailbox()
      assert.are.equal("受信箱", title(_G.MailFrame))
      MailStub.camelotSelectTab(2)
      assert.are.equal("郵便を送る", title(_G.MailFrame))
      MailStub.camelotSelectTab(1)
      assert.are.equal("受信箱", title(_G.MailFrame))
      MailStub.letter = { sender = "Thrall", subject = "Hello", items = 0, money = 0, canDelete = true }
      MailStub.camelotOpenLetter()
      assert.are.equal("郵便を開く", title(_G.OpenMailFrame))
      assert.are.equal(WFJ.Font.PATH, (_G.MailFrame.TitleContainer.TitleText:GetFont()))
      alt(true)
      assert.are.equal("Inbox", title(_G.MailFrame))
      assert.are.equal("Open Mail", title(_G.OpenMailFrame))
      alt(false)
      assert.are.equal("受信箱", title(_G.MailFrame))
      S.set("area.interface", false)
      assert.are.equal("Open Mail", title(_G.OpenMailFrame))
      S.set("area.interface", true)
    end)

  it("a title holding anything but INBOX / SENDMAIL / OPENMAIL is left as written", function()
    MailStub.camelotOpenMailbox()
    _G.MailFrame:SetTitle("Cancel") -- a dictionary word the title never shows
    WFJ.Mail.onFrameTitle()
    assert.are.equal("Cancel", title(_G.MailFrame))
  end)

  it("the inbox expiry and the open letter translate after the frames' own Update methods", function()
    MailStub.inbox = { { sender = "Thrall", subject = "Hello", daysLeft = 0.25, canDelete = true } }
    MailStub.camelotOpenMailbox()
    assert.are.equal("|cffff20206時間|r", _G.MailItem1ExpireTime:GetText())
    assert.are.equal("Thrall", _G.MailItem1Sender:GetText())
    MailStub.letter = { sender = "Jaina", subject = "Gift", items = 2, money = 0, canDelete = false,
      invoice = { type = "seller", item = "Linen Cloth", player = "Thrall", bid = 5, buyout = 5 } }
    MailStub.camelotOpenLetter()
    assert.are.equal("添付物を受け取る:", _G.OpenMailAttachmentText:GetText())
    assert.are.equal("返送", _G.OpenMailDeleteButton:GetText())
    assert.are.equal("売却したアイテム: Linen Cloth", _G.OpenMailInvoiceItemLabel:GetText())
    assert.are.equal("購入者: Thrall", _G.OpenMailInvoicePurchaser:GetText())
    assert.are.equal("Jaina", _G.OpenMailSender.Name:GetText())
    assert.are.equal(1, #Stub.hooks["InboxFrame:Update"])
    assert.are.equal(1, #Stub.hooks["OpenMailFrame:Update"])
    assert.is_nil(Stub.hooks.InboxFrame_Update)
    assert.is_nil(Stub.hooks.OpenMail_Update)
  end)

  it("Prev / Next on the parentKey-only page buttons translate; the send tab's money text follows the radio", function()
    assert.are.equal("前へ", _G.InboxFrame.PrevPageButton:GetRegions():GetText())
    assert.are.equal("次へ", _G.InboxFrame.NextPageButton:GetRegions():GetText())
    MailStub.camelotOpenMailbox()
    MailStub.camelotSelectTab(2)
    assert.are.equal("送金額:", _G.SendMailMoneyText:GetText())
  end)

  it("'Sold By: Multiple Sellers' and a row's 'Multiple items (3)' translate; names and counts kept",
    function()
      MailStub.letter = { sender = "Jaina", subject = "Sold", items = 0, money = 5, canDelete = true,
        invoice = { type = "buyer", item = "Linen Cloth", player = _G.AUCTION_HOUSE_MAIL_MULTIPLE_SELLERS, bid = 5,
          buyout = 5 } }
      MailStub.camelotOpenLetter()
      assert.are.equal("販売者: 複数の販売者", _G.OpenMailInvoicePurchaser:GetText())
      alt(true)
      assert.are.equal("Sold By: Multiple Sellers", _G.OpenMailInvoicePurchaser:GetText())
      alt(false)
      local tt = _G.GameTooltip
      tt:SetOwner(_G.MailItem1Button)
      tt:AddLine(_G.MAIL_MULTIPLE_ITEMS .. " (3)") -- mailframe.lua:494
      tt:Show()
      assert.are.equal("複数のアイテム (3)", _G.GameTooltipTextLeft1:GetText())
      tt:SetOwner(_G.MailItem1Button)
      tt:SetText("Multiple Sellers (3)") -- an entry not granted the count label: English
      tt:Show()
      assert.are.equal("Multiple Sellers (3)", _G.GameTooltipTextLeft1:GetText())
    end)

  it("hooks install once; a second init is a no-op", function()
    assert.is_false(WFJ.Mail.init())
    assert.are.equal(1, #Stub.hooks.MailFrameTab_OnClick)
    MailStub.camelotOpenMailbox()
    assert.are.equal("受信箱", title(_G.MailFrame))
  end)
end)
