-- The mailbox: MailFrame (inbox + send mail), OpenMailFrame, and the writers UI/Mail.lua post-hooks,
-- replaying the client's mail frame writes and Blizzard_SharedXML/TimeUtil.lua (SecondsToTime). M.install builds the
-- shared widget set (first modelled on the Classic Era 1.15.9 files); M.installCamelot reshapes it as Forever's
-- Blizzard_MailFrame, the client the addon targets. A client write is stored as `fs.text = …` (not counted as ours).
-- Requires Stub.install and Stub.installTooltipAPI first.
--   M.inbox = { { sender, subject, daysLeft, cod, money, itemCount, canDelete }, … }
--   M.letter = { sender, subject, body, items, money, canDelete, invoice = { type, item, player, bid, buyout,
--     count } } (the open letter, InboxFrame.openMailID = 1)
-- Drivers (after M.installCamelot): M.camelotOpenMailbox(), M.camelotSelectTab(i), M.camelotOpenLetter(), M.radio(i),
-- M.openAll(), M.hover(owner), M.reply().
local Stub = require("tests.lua.spec.wow_stub")
local M = {}

-- The client's English for every global string the replayed writers use (a spec's ui table sets the same globals).
local EN = {
  INBOX = "Inbox", SENDMAIL = "Send Mail", OPENMAIL = "Open Mail", TRIAL_RESTRICTED =
  "You need to upgrade your account to access this feature.", INBOX_TOO_MUCH_MAIL = "Your inbox is full.",
  INBOX_TOO_MUCH_MAIL_TOOLTIP = "Not all of your mail can be displayed.|nPlease delete some mail to make room.",
  PREV = "Prev", NEXT = "Next", OPEN_ALL_MAIL_BUTTON = "Open All", OPEN_ALL_MAIL_BUTTON_OPENING = "Opening...",
  MAIL_TO_LABEL = "To:", SEND_MAIL_COST = "Postage:", MAIL_SUBJECT_LABEL = "Subject:", SEND_MONEY = "Send Money",
  COD = "C.O.D.", CANCEL = "Cancel", SEND_LABEL = "Send", TAKE_ATTACHMENTS = "Take Attachments:", FROM = "From:",
  REPORT_SPAM = "Report Player", CLOSE = "Close", DELETE = "Delete", REPLY_MESSAGE = "Reply",
  CASH_ON_DELIVERY = "C.O.D.", SALE_PRICE_COLON = "Sale Price:", DEPOSIT_COLON = "Deposit:",
  AUCTION_HOUSE_CUT_COLON = "Auction House Cut:", AUCTION_INVOICE_FUNDS_NOT_YET_SENT = "Amount not yet sent",
  ITEM_SOLD_COLON = "Item Sold:", PURCHASED_BY_COLON = "Purchased By:", AMOUNT_RECEIVED_COLON = "Amount Received:",
  DAYS_ABBR = "%d |4Day:Days;", HOURS_ABBR = "%d |4Hr:Hrs;", MINUTES_ABBR = "%d |4Min:Mins;",
  SECONDS_ABBR = "%d |4Sec:Secs;", TIME_UNIT_DELIMITER = " ", TIME_UNTIL_DELETED = "Time until message is deleted",
  TIME_UNTIL_RETURNED = "Time until message is returned", UNKNOWN = "Unknown", NO_ATTACHMENTS = "No Attachments",
  MAIL_RETURN = "Return", ITEM_PURCHASED_COLON = "Item Purchased:", SOLD_BY_COLON = "Sold By:",
  AMOUNT_PAID_COLON = "Amount Paid:", AUCTION_INVOICE_PENDING_FUNDS_COLON = "Amount Pending:", BUYOUT = "Buyout",
  HIGH_BIDDER = "High Bidder", AUCTION_MAIL_ITEM_STACK = "%s (%d)",
  AUCTION_INVOICE_FUNDS_DELAY = "Estimated delivery time %s", AMOUNT_TO_SEND = "Amount to send:",
  COD_AMOUNT = "Cash on Delivery Amount:", MAIL_COD_ERROR = "C.O.D. must be <= %d",
  MAIL_COD_ERROR_COLORBLIND = "C.O.D. must be <= %1$d%2$s", GOLD_AMOUNT_SYMBOL = "g",
  ATTACHMENT_TEXT = "Drag an item here to include it with your mail", ENCLOSED_MONEY = "Enclosed amount",
  MAIL_LETTER_TOOLTIP = "Click to make a permanent\ncopy of this letter.", MAIL_REPLY_PREFIX = "RE:",
  MAIL_MULTIPLE_ITEMS = "Multiple items",
}
M.EN = EN

local function S(key) return _G[key] or EN[key] end

-- The client's format(): %N$ positionals resolved first (Lua's string.format has none).
local function format(template, ...)
  local args = { ... }
  local plain = template:gsub("%%(%d)%$(%a)", function(n, conv)
    return ("%" .. conv):format(args[tonumber(n)])
  end)
  if plain ~= template then return plain end
  return template:format(...)
end

local function client(fs, text) -- a FontString write by the client (a widget camelot removed is skipped)
  if fs then fs.text = text end
end
local function clientButton(b, text) b.fontString.text = text end

-- An EditBox: text the player types (never a FontString we may record), plus its XML label regions.
local function editBox(name)
  local e = CreateFrame("EditBox", name)
  e.text = ""
  function e:GetText() return self.text end
  function e:SetText(t) self.text = t end
  e.SetFocus = function() end
  return e
end

local function label(frame, text)
  return frame:addRegion(Stub.fontString(text))
end

-- SecondsToTime(seconds) with the defaults the inbox uses: at most two abbreviated terms (TimeUtil.lua:309–371).
local function secondsToTime(seconds)
  local time, count = "", 0
  seconds = math.floor(seconds)
  local function term(unit, key)
    if count < 2 and seconds >= unit then
      count = count + 1
      if time ~= "" then time = time .. S("TIME_UNIT_DELIMITER") end
      time = time .. format(S(key), math.floor(seconds / unit))
      seconds = seconds % unit
    end
  end
  term(86400, "DAYS_ABBR")
  term(3600, "HOURS_ABBR")
  term(60, "MINUTES_ABBR")
  if count < 2 and seconds > 0 then
    if time ~= "" then time = time .. S("TIME_UNIT_DELIMITER") end
    time = time .. format(S("SECONDS_ABBR"), seconds)
  end
  return time
end
M.secondsToTime = secondsToTime

function M.install()
  _G.GREEN_FONT_COLOR_CODE = "|cff20ff20"
  _G.RED_FONT_COLOR_CODE = "|cffff2020"
  _G.FONT_COLOR_CODE_CLOSE = "|r"
  _G.MAX_COD_AMOUNT = 10000
  _G.ENABLE_COLORBLIND_MODE = "0"
  _G.MailFrameTab_OnClick = nil -- only M.installCamelot defines one
  M.inbox, M.letter = {}, nil

  -- MailFrame and its tabs (xml:264–858); the tabs' OnShow resizes from the current text
  local mailFrame = CreateFrame("Frame", "MailFrame")
  Stub.namedFontString("MailFrameTrialError", EN.TRIAL_RESTRICTED)
  Stub.tab("MailFrameTab1", EN.INBOX)
  Stub.tab("MailFrameTab2", EN.SENDMAIL)

  -- inbox (xml:286–449)
  local inbox = CreateFrame("Frame", "InboxFrame")
  inbox.pageNum = 1
  Stub.namedFontString("InboxTitleText", EN.INBOX)
  CreateFrame("Frame", "InboxTooMuchMail")
  Stub.namedFontString("InboxTooMuchMailText", EN.INBOX_TOO_MUCH_MAIL)
  for i = 1, 7 do
    CreateFrame("Frame", "MailItem" .. i)
    Stub.namedFontString("MailItem" .. i .. "Sender", "")
    Stub.namedFontString("MailItem" .. i .. "Subject", "")
    Stub.button("MailItem" .. i .. "ExpireTime", "")
    Stub.button("MailItem" .. i .. "Button", "")
    Stub.namedFontString("MailItem" .. i .. "ButtonCOD", EN.CASH_ON_DELIVERY)
  end
  label(CreateFrame("Button", "InboxPrevPageButton"), EN.PREV)
  label(CreateFrame("Button", "InboxNextPageButton"), EN.NEXT)
  local openAll = Stub.button("OpenAllMail", EN.OPEN_ALL_MAIL_BUTTON)
  -- OpenAllMailMixin copied onto the frame (lua:1113–1129): nothing to open → StartOpening ends in StopOpening
  function openAll:StartOpening()
    clientButton(self, S("OPEN_ALL_MAIL_BUTTON_OPENING"))
    if not M.openAllKeepsOpening then self:StopOpening() end
  end
  function openAll:StopOpening()
    clientButton(self, S("OPEN_ALL_MAIL_BUTTON"))
  end

  -- send mail (xml:451–821)
  local send = CreateFrame("Frame", "SendMailFrame")
  Stub.namedFontString("SendMailTitleText", EN.SENDMAIL)
  Stub.namedFontString("SendMailErrorText", "")
  local mailEdit = editBox("MailEditBox")
  function mailEdit:GetEditBox() return self end
  label(editBox("SendMailNameEditBox"), EN.MAIL_TO_LABEL)
  label(CreateFrame("Frame", "SendMailCostMoneyFrame"), EN.SEND_MAIL_COST)
  label(editBox("SendMailSubjectEditBox"), EN.MAIL_SUBJECT_LABEL)
  for _, part in ipairs({ "Gold", "Silver", "Copper" }) do editBox("SendMailMoney" .. part) end
  Stub.namedFontString("SendMailMoneyText", EN.SEND_MONEY)
  CreateFrame("CheckButton", "SendMailSendMoneyButton")
  CreateFrame("CheckButton", "SendMailCODButton")
  Stub.namedFontString("SendMailSendMoneyButtonText", "")
  Stub.namedFontString("SendMailCODButtonText", "")
  client(_G.SendMailSendMoneyButtonText, EN.SEND_MONEY) -- the radio buttons' OnLoad (xml:729, 739)
  client(_G.SendMailCODButtonText, EN.COD)
  Stub.button("SendMailCancelButton", EN.CANCEL)
  Stub.button("SendMailMailButton", EN.SEND_LABEL)
  for i = 1, 16 do CreateFrame("Button", "SendMailAttachment" .. i) end

  -- open mail (xml:860–1274)
  CreateFrame("Frame", "OpenMailFrame")
  Stub.namedFontString("OpenMailTitleText", EN.OPENMAIL)
  Stub.namedFontString("OpenMailAttachmentText", EN.TAKE_ATTACHMENTS)
  Stub.namedFontString("OpenMailSenderLabel", EN.FROM)
  Stub.namedFontString("OpenMailSubjectLabel", EN.MAIL_SUBJECT_LABEL)
  Stub.namedFontString("OpenMailSubject", "")
  Stub.button("OpenMailReportSpamButton", EN.REPORT_SPAM)
  local sender = CreateFrame("Frame", "OpenMailSender")
  sender.Name = Stub.fontString("")
  local body = CreateFrame("SimpleHTML", "OpenMailBodyText")
  body.text = ""
  function body:GetText() return self.text end
  CreateFrame("Frame", "OpenMailInvoiceFrame")
  for name, text in pairs({ OpenMailInvoiceItemLabel = EN.ITEM_SOLD_COLON, OpenMailInvoicePurchaser =
    EN.PURCHASED_BY_COLON, OpenMailInvoiceBuyMode = "", OpenMailInvoiceSalePrice = EN.SALE_PRICE_COLON,
    OpenMailInvoiceDeposit = EN.DEPOSIT_COLON, OpenMailInvoiceHouseCut = EN.AUCTION_HOUSE_CUT_COLON,
    OpenMailInvoiceAmountReceived = EN.AMOUNT_RECEIVED_COLON, OpenMailInvoiceNotYetSent =
    EN.AUCTION_INVOICE_FUNDS_NOT_YET_SENT, OpenMailInvoiceMoneyDelay = "" }) do
    Stub.namedFontString(name, text)
  end
  CreateFrame("Button", "OpenMailLetterButton")
  Stub.button("OpenMailCancelButton", EN.CLOSE)
  Stub.button("OpenMailDeleteButton", EN.DELETE)
  Stub.button("OpenMailReplyButton", EN.REPLY_MESSAGE)

  -- writers (globals, looked up by name by the XML scripts and the Lua that calls them)
  _G.SecondsToTime = secondsToTime
  _G.InboxFrame_Update = function() -- lua:155–286 (text writes)
    local index = (_G.InboxFrame.pageNum - 1) * 7 + 1
    for i = 1, 7 do
      local mail = M.inbox[index]
      if mail then
        client(_G["MailItem" .. i .. "Subject"], mail.subject)
        client(_G["MailItem" .. i .. "Sender"], mail.sender or S("UNKNOWN"))
        local daysLeft = mail.daysLeft
        local text
        if daysLeft >= 1 then
          text = _G.GREEN_FONT_COLOR_CODE .. format(S("DAYS_ABBR"), math.floor(daysLeft)) .. " " ..
            _G.FONT_COLOR_CODE_CLOSE
        else
          text = _G.RED_FONT_COLOR_CODE .. secondsToTime(math.floor(daysLeft * 24 * 60 * 60)) ..
            _G.FONT_COLOR_CODE_CLOSE
        end
        local expire = _G["MailItem" .. i .. "ExpireTime"]
        clientButton(expire, text)
        expire.tooltip = mail.canDelete and S("TIME_UNTIL_DELETED") or S("TIME_UNTIL_RETURNED")
        local button = _G["MailItem" .. i .. "Button"]
        button.hasItem, button.itemCount = mail.itemCount, mail.itemCount
        button.money = (mail.money or 0) > 0 and mail.money or nil
        button.cod = (mail.cod or 0) > 0 and mail.cod or nil
      else
        client(_G["MailItem" .. i .. "Sender"], "")
        client(_G["MailItem" .. i .. "Subject"], "")
      end
      index = index + 1
    end
  end

  _G.OpenMail_Update = function() -- lua:473–740 (text writes)
    local l = M.letter
    if not l then return end
    client(_G.OpenMailSender.Name, l.sender or S("UNKNOWN"))
    client(_G.OpenMailSubject, l.subject)
    _G.OpenMailBodyText.text = l.body or ""
    local inv = l.invoice
    if inv then
      local item = inv.item
      if inv.count and inv.count > 1 then item = format(S("AUCTION_MAIL_ITEM_STACK"), item, inv.count) end
      local buyMode = inv.bid == inv.buyout and ("(" .. S("BUYOUT") .. ")") or ("(" .. S("HIGH_BIDDER") .. ")")
      if inv.type == "buyer" then
        client(_G.OpenMailInvoiceItemLabel, S("ITEM_PURCHASED_COLON") .. " " .. item .. "  " .. buyMode)
        client(_G.OpenMailInvoicePurchaser, S("SOLD_BY_COLON") .. " " .. inv.player)
        client(_G.OpenMailInvoiceAmountReceived, S("AMOUNT_PAID_COLON"))
        client(_G.OpenMailInvoiceBuyMode, "")
      elseif inv.type == "seller" then
        client(_G.OpenMailInvoiceItemLabel, S("ITEM_SOLD_COLON") .. " " .. item)
        client(_G.OpenMailInvoicePurchaser, S("PURCHASED_BY_COLON") .. " " .. inv.player)
        client(_G.OpenMailInvoiceAmountReceived, S("AMOUNT_RECEIVED_COLON"))
        client(_G.OpenMailInvoiceBuyMode, buyMode)
      elseif inv.type == "seller_temp_invoice" then
        client(_G.OpenMailInvoiceItemLabel, S("ITEM_SOLD_COLON") .. " " .. item .. "  " .. buyMode)
        client(_G.OpenMailInvoicePurchaser, S("PURCHASED_BY_COLON") .. " " .. inv.player)
        client(_G.OpenMailInvoiceAmountReceived, S("AUCTION_INVOICE_PENDING_FUNDS_COLON"))
        client(_G.OpenMailInvoiceBuyMode, "")
        client(_G.OpenMailInvoiceMoneyDelay, format(S("AUCTION_INVOICE_FUNDS_DELAY"), "12:22"))
      end
    end
    if (l.items or 0) + ((l.money or 0) > 0 and 1 or 0) > 0 then
      client(_G.OpenMailAttachmentText, S("TAKE_ATTACHMENTS"))
    else
      client(_G.OpenMailAttachmentText, S("NO_ATTACHMENTS"))
    end
    clientButton(_G.OpenMailDeleteButton, l.canDelete and S("DELETE") or S("MAIL_RETURN"))
  end

  _G.SendMailRadioButton_OnClick = function(index) -- lua:1051–1062
    if index == 1 then
      client(_G.SendMailMoneyText, S("AMOUNT_TO_SEND"))
    else
      client(_G.SendMailMoneyText, S("COD_AMOUNT"))
    end
  end
  -- SendMailFrame OnLoad passes (self, 1): `index` is the frame, so the C.O.D. branch runs (xml:803–807)
  _G.SendMailRadioButton_OnClick(send, 1)
  send:SetScript("OnShow", function() -- xml:808–815
    if _G.ENABLE_COLORBLIND_MODE == "1" then
      client(_G.SendMailErrorText, format(S("MAIL_COD_ERROR_COLORBLIND"), _G.MAX_COD_AMOUNT, S("GOLD_AMOUNT_SYMBOL")))
    else
      client(_G.SendMailErrorText, format(S("MAIL_COD_ERROR"), _G.MAX_COD_AMOUNT))
    end
  end)

  _G.OpenMail_Reply = function() -- lua:771–784: the sender and subject are read back with GetText
    _G.SendMailNameEditBox:SetText(_G.OpenMailSender.Name:GetText())
    local subject = _G.OpenMailSubject:GetText()
    local prefix = S("MAIL_REPLY_PREFIX") .. " "
    if subject:sub(1, #prefix) ~= prefix then subject = prefix .. subject end
    _G.SendMailSubjectEditBox:SetText(subject)
  end

  M.frame = mailFrame
  return mailFrame
end

-- The radio buttons' XML OnClick (xml:5–8).
function M.radio(i)
  _G.SendMailRadioButton_OnClick(i)
end

-- OpenAllMailMixin:OnClick (lua:1227–1229).
function M.openAll()
  _G.OpenAllMail:StartOpening()
end

-- A hover: the owner's OnEnter as the client runs it.
function M.hover(owner)
  local tt = _G.GameTooltip
  tt:ClearLines() -- SetOwner starts a new tooltip [likely: the client clears the lines]
  local name = owner:GetName() or ""
  if name:find("ExpireTime$") then -- xml:57–63
    if not owner.tooltip then return end
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    tt:SetText(owner.tooltip)
  elseif name == "InboxTooMuchMail" then -- xml:341–344
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    tt:SetText(S("INBOX_TOO_MUCH_MAIL_TOOLTIP"))
  elseif name:find("^MailItem%dButton$") then -- InboxFrameItem_OnEnter, lua:312–339
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    if owner.hasItem then
      if owner.itemCount == 1 then
        Stub.setItemTooltip(tt, "|Hitem:2589:0:0:0|h[Linen Cloth]|h", { "Linen Cloth", "Enclosed amount" })
      else
        tt:AddLine(S("MAIL_MULTIPLE_ITEMS") .. " (" .. owner.itemCount .. ")")
      end
    end
    if owner.money then
      if owner.hasItem then tt:AddLine(" ") end
      tt:AddLine(S("ENCLOSED_MONEY"))
      tt:AddLine(" ") -- GameTooltip_AddMoneyLine: the coins are a money frame beside a blank line [likely]
    elseif owner.cod then
      if owner.hasItem then tt:AddLine(" ") end
      tt:AddLine(S("COD_AMOUNT"))
      tt:AddLine(" ")
    end
    tt:Show()
  elseif name:find("^SendMailAttachment%d+$") then -- SendMailAttachment_OnEnter, lua:1084–1096 (empty slot)
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    tt:SetText(S("ATTACHMENT_TEXT"), 1.0, 1.0, 1.0)
  elseif name == "OpenMailLetterButton" then -- xml:1184–1187
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    tt:SetText(S("MAIL_LETTER_TOOLTIP"))
  end
end

function M.reply()
  _G.OpenMail_Reply()
end

-- Forever's Blizzard_MailFrame (camelot blizzard_mailframe/mailframe.{lua,xml}), the one client the addon
-- targets: M.install's widgets minus the three title FontStrings, MailEditBox, the two page buttons (now
-- parentKey-only InboxFrame.PrevPageButton / .NextPageButton, xml:394, 419) and OpenMailInvoiceBuyMode; titles through
-- SetTitle → TitleContainer.TitleText (portraitframe.lua:4–13); the writers are InboxFrame:Update /
-- OpenMailFrame:Update (lua:316, 747) and the global MailFrameTab_OnClick (lua:197–230); OpenMailFrame's inline OnShow
-- sets OPENMAIL (xml:1337–1341).
function M.installCamelot()
  M.install()
  local inboxUpdate, openUpdate = _G.InboxFrame_Update, _G.OpenMail_Update
  for _, name in ipairs({ "InboxFrame_Update", "OpenMail_Update", "InboxTitleText", "SendMailTitleText",
    "OpenMailTitleText", "InboxPrevPageButton", "InboxNextPageButton", "OpenMailInvoiceBuyMode", "MailEditBox" }) do
    _G[name] = nil
  end
  local function titled(frame)
    frame.TitleContainer = CreateFrame("Frame")
    frame.TitleContainer.TitleText = Stub.fontString("")
    function frame.SetTitle(self, t) self.TitleContainer.TitleText.text = t end
  end
  titled(_G.MailFrame)
  titled(_G.OpenMailFrame)
  local inbox = _G.InboxFrame
  inbox.name = "InboxFrame"
  inbox.PrevPageButton = CreateFrame("Button")
  label(inbox.PrevPageButton, EN.PREV)
  inbox.NextPageButton = CreateFrame("Button")
  label(inbox.NextPageButton, EN.NEXT)
  function inbox.Update() inboxUpdate() end -- InboxMixin:Update, copied onto the frame
  local open = _G.OpenMailFrame
  open.name = "OpenMailFrame"
  open.DeleteButton = _G.OpenMailDeleteButton
  function open.Update() openUpdate() end -- OpenMailMixin:Update
  open:SetScript("OnShow", function(self) self:SetTitle(S("OPENMAIL")) end)
  _G.MailFrameTab_OnClick = function(self, tabID)
    tabID = tabID or self:GetID()
    if tabID == 1 then
      _G.SendMailFrame:Hide()
      _G.InboxFrame:Show()
      _G.MailFrame:SetTitle(S("INBOX"))
    else
      _G.InboxFrame:Hide()
      _G.SendMailFrame:Show()
      _G.SendMailRadioButton_OnClick(1)
      _G.MailFrame:SetTitle(S("SENDMAIL"))
    end
  end
  return _G.MailFrame
end

-- MailFrame_Show → MailFrameTab_OnClick(nil, 1) → InboxFrame:Update() on MAIL_INBOX_UPDATE.
function M.camelotOpenMailbox()
  _G.MailFrame:Show()
  _G.MailFrameTab1:Show()
  _G.MailFrameTab2:Show()
  _G.MailFrameTab_OnClick(nil, 1)
  _G.InboxFrame:Update()
end

function M.camelotSelectTab(i)
  _G.MailFrameTab_OnClick(nil, i)
end

-- InboxFrame_OnClick: OpenMailFrame:Update(), then the panel shows (its OnShow sets the title).
function M.camelotOpenLetter()
  _G.OpenMailFrame:Update()
  _G.OpenMailFrame:Show()
  _G.InboxFrame:Update()
end

return M
