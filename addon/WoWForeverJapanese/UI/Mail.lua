-- UI/Mail.lua: the mailbox: inbox, send mail and the open letter (surfaces "mail" and "mail.static", area "ui",
-- ADR-016). The client loads Blizzard_MailFrame (blizzard_mailframe.toc:4–6, not load-on-demand), the
-- retail mail frame, so every frame exists before this addon loads.
-- Static labels (XML text= and OnLoad writes Blizzard never repeats) are shown once at init on "mail.static", before
-- the window's first show, so MailFrameTab1/2's OnShow → PanelTemplates_TabResize measures the Japanese. "To:",
-- "Subject:" and "Postage:" are unnamed FontString regions of SendMailNameEditBox / SendMailSubjectEditBox /
-- SendMailCostMoneyFrame, and Prev / Next of the parentKey-only inbox page buttons InboxFrame.PrevPageButton /
-- .NextPageButton (xml:394, 419): found by the client's exact English (Labels.region); the EditBox itself is never a
-- widget here.
-- Titles: MailFrameTab_OnClick writes INBOX / SENDMAIL with MailFrame:SetTitle (camelot mailframe.lua:197–230);
--   OpenMailFrame's inline OnShow writes OPENMAIL (mailframe.xml:1337–1341); SetTitle → TitleContainer.TitleText
--   (blizzard_sharedxml/portraitframe.lua:4–13). The client rewrites them on every tab click / letter, so they are
--   shown after those writers. Inbox and Send share the one FontString. A global MailFrameTitleText is tried first
--   (whether `$parent` resolves through the unnamed TitleContainer is an in-game check); the dotted path after.
-- Text that changes, each widget restricted (`only`) to the keys its writer can put there. InboxMixin:Update
-- (mailframe.lua:316) and OpenMailMixin:Update (:747) are called as InboxFrame:Update() / OpenMailFrame:Update()
-- (lua:147–148, 462, 471, 529, 549, 566, 587), so the frames' own methods are hooked (the mixin was copied onto them
-- at load):
--   InboxFrame:Update → MailItem1..7ExpireTime, a Button: GREEN .. format(DAYS_ABBR, n) .. " " .. |r, or RED ..
--     SecondsToTime(s) .. |r. SecondsToTime (Blizzard_SharedXML/TimeUtil.lua, maxCount 2, abbreviated) joins up to
--     two unit terms with TIME_UNIT_DELIMITER; the `wrapped` form takes one term ("5 Hrs") as its template and two
--     terms ("5 Hrs 30 Mins") as a duration (Core/UIStrings DURATIONS);
--   OpenMailFrame:Update → OpenMailAttachmentText (TAKE_ATTACHMENTS / NO_ATTACHMENTS), OpenMailDeleteButton
--     (DELETE / MAIL_RETURN), the invoice: OpenMailInvoiceAmountReceived, MoneyDelay (AUCTION_INVOICE_FUNDS_DELAY,
--     "12:22" verbatim). OpenMailInvoiceItemLabel / Purchaser are ITEM_SOLD_COLON / ITEM_PURCHASED_COLON /
--     SOLD_BY_COLON / PURCHASED_BY_COLON .. " " .. <item or player name>: the `colonPrefix` form shows the Japanese
--     label and keeps the name as written. When the client had no name it writes
--     AUCTION_HOUSE_MAIL_MULTIPLE_SELLERS / _BUYERS there (mailframe.lua:785–788), shown in Japanese too (the
--     `colonPrefixEntry` grant on those two keys, Core/UIStrings);
--   SendMailRadioButton_OnClick → SendMailMoneyText (AMOUNT_TO_SEND / COD_AMOUNT);
--   SendMailFrame OnShow → SendMailErrorText (MAIL_COD_ERROR[_COLORBLIND]); HookScript runs after the inline script;
--   OpenAllMail:StartOpening / StopOpening → its button text. The mixin's methods were copied onto the frame at load
--     and are called as self:Method(), so the frame's own method is hooked, not OpenAllMailMixin.
-- Records are never released on hide: every client rewrite of these widgets runs through a hooked writer, and one
-- that does not is dropped as stale on the next refresh (UI/Render).
-- The letter's body (ADR-042, the MailBody family: MailTemplate.Body_lang, the letters NPCs and events send):
--   OpenMailFrame:Update writes OpenMailBodyText:SetText(GetInboxText(id), true) (mailframe.lua:776–777), a
--   SimpleHTML (mailframe.xml:1007–1013) with no GetText [verified: blizzard_apidocumentationgenerated/
--   simplehtmlapidocumentation.lua: SetText(text, ignoreMarkup), per-text-type GetFont / SetFont]. A SetText
--   post-hook on it sees every text the client writes; a small adapter (below) gives SurfaceState the FontString
--   interface and writes back with the client's own call shape, SetText(text, true). The server sends the letter with
--   its tokens filled in: the player's name for `$N`, line breaks for `$B`. The live text is turned back into the
--   template's form the way the gossip surface keys a line (Core/Collector.text: the player's name becomes `$N`,
--   breaks `$B`), and only an exact MailBody row of that form takes it; the Japanese carries `{name}`, which the
--   translator fills like a quest line. A letter a player wrote is no row and is never touched.
-- Never touched: OpenMailSender.Name and OpenMailSubject (OpenMail_Reply copies both into the send EditBoxes with
-- GetText), MailItemNSender / Subject, every mail EditBox (their text is sent with SendMail or compared with GetText),
-- and any letter body that is no MailBody row. UNKNOWN in the sender slot stays.
-- Help tooltips (UI/HelpTooltip): the expiry hover (self.tooltip = TIME_UNTIL_DELETED / _RETURNED), the inbox-full
-- hover, the inbox row's money / C.O.D. lines (an item row's tooltip is an item tooltip and is never walked), the
-- empty send slot and the letter button.
local _, WFJ = ...
local Mail = {}
WFJ.Mail = Mail

local SURFACE = "mail"
Mail.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
Mail.STATIC = STATIC
local Compat = WFJ.Compat

local ROWS = 7 -- INBOXITEMS_TO_DISPLAY
local SEND_SLOTS = 16 -- SendMailAttachment1..16

local function set(list)
  local s = {}
  for _, k in ipairs(list) do s[k] = true end
  return s
end

-- Widgets this module must never record (global names; "Frame.Key" for a parentKey child).
Mail.NEVER_TOUCH = { "OpenMailSender.Name", "OpenMailSubject", "SendMailNameEditBox",
  "SendMailSubjectEditBox", "SendMailMoneyGold", "SendMailMoneySilver", "SendMailMoneyCopper" }
for i = 1, ROWS do
  Mail.NEVER_TOUCH[#Mail.NEVER_TOUCH + 1] = "MailItem" .. i .. "Sender"
  Mail.NEVER_TOUCH[#Mail.NEVER_TOUCH + 1] = "MailItem" .. i .. "Subject"
end

-- Static labels: record key → the widget's global name.
local STATIC_WIDGETS = {
  tab1 = "MailFrameTab1", tab2 = "MailFrameTab2", trialError = "MailFrameTrialError",
  tooMuchMail = "InboxTooMuchMailText", sendMoneyRadio = "SendMailSendMoneyButtonText",
  codRadio = "SendMailCODButtonText", cancel = "SendMailCancelButton", send = "SendMailMailButton",
  fromLabel = "OpenMailSenderLabel", subjectLabel = "OpenMailSubjectLabel", reportSpam = "OpenMailReportSpamButton",
  close = "OpenMailCancelButton", reply = "OpenMailReplyButton", salePrice = "OpenMailInvoiceSalePrice",
  deposit = "OpenMailInvoiceDeposit", houseCut = "OpenMailInvoiceHouseCut", notYetSent = "OpenMailInvoiceNotYetSent",
}
for i = 1, ROWS do STATIC_WIDGETS["cod" .. i] = "MailItem" .. i .. "ButtonCOD" end
local STATIC_ORDER = {}
for recKey in pairs(STATIC_WIDGETS) do STATIC_ORDER[#STATIC_ORDER + 1] = recKey end
table.sort(STATIC_ORDER)

-- Unnamed label regions: record key → { owner frame's candidate names, the global string it shows }.
local REGIONS = {
  prev = { { "InboxFrame.PrevPageButton" }, "PREV" }, -- xml:394
  next = { { "InboxFrame.NextPageButton" }, "NEXT" }, -- xml:419
  to = { { "SendMailNameEditBox" }, "MAIL_TO_LABEL" }, subject = { { "SendMailSubjectEditBox" }, "MAIL_SUBJECT_LABEL" },
  postage = { { "SendMailCostMoneyFrame" }, "SEND_MAIL_COST" },
}

-- The template titles (see the header) and the hosts of the method writers.
local CAMELOT = {
  frameTitle = { "MailFrameTitleText", "MailFrame.TitleContainer.TitleText" },
  openFrameTitle = { "OpenMailFrameTitleText", "OpenMailFrame.TitleContainer.TitleText" },
  tabClick = { "MailFrameTab_OnClick" }, inboxFrame = { "InboxFrame" }, openMailFrame = { "OpenMailFrame" },
  body = { "OpenMailBodyText" }, unitName = { "UnitName" }, unknownName = { "UNKNOWNOBJECT" },
}
local FRAME_TITLE = { only = set({ "INBOX", "SENDMAIL" }) }
local OPEN_TITLE = { only = set({ "OPENMAIL" }) }
local REGION_ORDER = { "prev", "next", "to", "subject", "postage" }

-- Text that changes: record key → { widget's global name, the keys its writer can show }.
local EXPIRY = set({ "DAYS_ABBR", "HOURS_ABBR", "MINUTES_ABBR", "SECONDS_ABBR" })
local DYNAMIC = {
  moneyText = { "SendMailMoneyText", set({ "SEND_MONEY", "AMOUNT_TO_SEND", "COD_AMOUNT" }) },
  codError = { "SendMailErrorText", set({ "MAIL_COD_ERROR", "MAIL_COD_ERROR_COLORBLIND" }) },
  openAll = { "OpenAllMail", set({ "OPEN_ALL_MAIL_BUTTON", "OPEN_ALL_MAIL_BUTTON_OPENING" }) },
  attachment = { "OpenMailAttachmentText", set({ "TAKE_ATTACHMENTS", "NO_ATTACHMENTS" }) },
  delete = { "OpenMailDeleteButton", set({ "DELETE", "MAIL_RETURN" }) },
  itemLabel = { "OpenMailInvoiceItemLabel", set({ "ITEM_SOLD_COLON", "ITEM_PURCHASED_COLON" }) },
  purchaser = { "OpenMailInvoicePurchaser", set({ "SOLD_BY_COLON", "PURCHASED_BY_COLON" }) },
  amount = { "OpenMailInvoiceAmountReceived",
    set({ "AMOUNT_PAID_COLON", "AMOUNT_RECEIVED_COLON", "AUCTION_INVOICE_PENDING_FUNDS_COLON" }) },
  moneyDelay = { "OpenMailInvoiceMoneyDelay", set({ "AUCTION_INVOICE_FUNDS_DELAY" }) },
}
local GROUPS = {
  inbox = {},
  openMail = { "attachment", "delete", "itemLabel", "purchaser", "amount", "moneyDelay" },
  radio = { "moneyText" }, sendShow = { "codError" }, openAll = { "openAll" },
}
for i = 1, ROWS do
  DYNAMIC["expire" .. i] = { "MailItem" .. i .. "ExpireTime", EXPIRY }
  GROUPS.inbox[i] = "expire" .. i
end

-- Help tooltip owners: global name → the keys their tooltip lines may show.
local HELP = { InboxTooMuchMail = set({ "INBOX_TOO_MUCH_MAIL_TOOLTIP" }),
  OpenMailLetterButton = set({ "MAIL_LETTER_TOOLTIP" }) }
local EXPIRY_TOOLTIP = set({ "TIME_UNTIL_DELETED", "TIME_UNTIL_RETURNED" })
-- A row with several items adds MAIL_MULTIPLE_ITEMS .. " (" .. n .. ")" (mailframe.lua:490–496; the count
-- kept by the `countLabel` form)
local ROW_TOOLTIP = set({ "ENCLOSED_MONEY", "COD_AMOUNT", "MAIL_MULTIPLE_ITEMS" })
local SLOT_TOOLTIP = set({ "ATTACHMENT_TEXT" })
for i = 1, ROWS do
  HELP["MailItem" .. i .. "ExpireTime"] = EXPIRY_TOOLTIP
  HELP["MailItem" .. i .. "Button"] = ROW_TOOLTIP
end
for i = 1, SEND_SLOTS do HELP["SendMailAttachment" .. i] = SLOT_TOOLTIP end

-- Shows one group of changing widgets (after their client writer ran). → the number of dictionary words found.
local function showGroup(group)
  local items = {}
  for _, recKey in ipairs(GROUPS[group]) do
    items[#items + 1] = { recKey, Compat.get(SURFACE, recKey), { only = DYNAMIC[recKey][2] } }
  end
  return WFJ.Labels.showAll(SURFACE, items)
end

function Mail.onInboxUpdate() return showGroup("inbox") end
function Mail.onOpenMailUpdate() return showGroup("openMail") end
function Mail.onRadio() return showGroup("radio") end
function Mail.onSendShow() return showGroup("sendShow") end
function Mail.onOpenAll() return showGroup("openAll") end

-- After MailFrameTab_OnClick (INBOX / SENDMAIL) and OpenMailFrame's OnShow (OPENMAIL). → 1 | 0
function Mail.onFrameTitle()
  return WFJ.Labels.show(SURFACE, "frameTitle", Compat.get(SURFACE, "frameTitle"), nil, FRAME_TITLE)
end
function Mail.onOpenTitle()
  return WFJ.Labels.show(SURFACE, "openFrameTitle", Compat.get(SURFACE, "openFrameTitle"), nil, OPEN_TITLE)
end

-- A writer: the frame's own Update method. → true | false
local function hookUpdate(hostKey, fn)
  local host = Compat.get(SURFACE, hostKey)
  if type(host) == "table" and type(host.Update) == "function" then
    hooksecurefunc(host, "Update", fn)
    return true
  end
  return false
end

-- The load-time labels, once (never released). → the number of dictionary words found.
function Mail.showStatic()
  local items = {}
  for _, recKey in ipairs(STATIC_ORDER) do items[#items + 1] = { recKey, Compat.get(SURFACE, recKey) } end
  for _, recKey in ipairs(REGION_ORDER) do
    local owner = Compat.get(SURFACE, "region." .. recKey)
    local region = type(owner) == "table" and WFJ.Labels.region(owner, REGIONS[recKey][2]) or nil
    if type(region) == "table" then
      items[#items + 1] = { recKey, region, { only = { [REGIONS[recKey][2]] = true } } }
    end
  end
  return WFJ.Labels.showAll(STATIC, items)
end

-- ── the letter's body ──────────────────────────────────────────────
-- logical: what GetText reports, the client's text as written or the text SurfaceState asked us to show.
local body = { html = nil, logical = nil, writing = false }
Mail.body = body
function body:GetText() return self.logical end
function body:SetText(text)
  self.writing = true
  local ok, err = pcall(self.html.SetText, self.html, text, true)
  self.writing = false
  if not ok then error(err, 0) end
  self.logical = text
end
function body:GetFont()
  if type(self.html.GetFont) ~= "function" then return nil end
  return self.html:GetFont("P")
end
function body:SetFont(path, size, flags) -- SimpleHTML's SetFont returns nothing: a refusal is read back
  if type(self.html.SetFont) ~= "function" then return false end
  self.html:SetFont("P", path, size, flags)
  return (self:GetFont()) == path
end

-- The player's name as the client spells it, or nil while it is not known.
local function playerName()
  local unitName = Compat.get(SURFACE, "unitName")
  local name = type(unitName) == "function" and unitName("player") or nil
  if type(name) ~= "string" or name == "" or name == Compat.get(SURFACE, "unknownName") then return nil end
  return name
end

-- The template forms the live body may be the expansion of, most specific first: the player's name as `$N` (a name
-- under 3 code points also as a whole word, as the gossip key does), then the text with nothing replaced.
local function templateForms(text)
  local name = playerName()
  local players = { name and { name = name } or false }
  if name and #name:gsub("[\128-\191]", "") < 3 then players[#players + 1] = { name = name, short = true } end
  players[#players + 1] = false
  local forms, seen = {}, {}
  for _, p in ipairs(players) do
    local form = WFJ.Collector.text(text, p or nil)
    if form ~= "" and not seen[form] then
      seen[form] = true
      forms[#forms + 1] = form
    end
  end
  return forms
end

-- The body the client last wrote, as a MailBody row's Japanese when it is one, else left as written. → 1 | 0
function Mail.showBody()
  if type(body.html) ~= "table" then return 0 end
  local text, key = body.logical, nil
  local rec = WFJ.SurfaceState.get(SURFACE, "body")
  if rec and rec.applied ~= nil and text == rec.applied then return 1 end -- still ours
  local index = WFJ.UIIndex
  if index and WFJ.Collector and type(text) == "string" and text ~= "" then
    local only = WFJ.Labels.families("MailBody").only
    for _, form in ipairs(templateForms(text)) do
      key = index:matchOnly(form, only)
      if key then break end
    end
  end
  local n = WFJ.Labels.showArgs(SURFACE, "body", body, key, nil)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- SetText post-hook on OpenMailBodyText: every text the client writes (ours is skipped).
function Mail.onBodyText(html, text)
  if body.writing then return end
  body.html, body.logical = html, type(text) == "string" and text or nil
  Mail.showBody()
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Mail.init()
  for recKey, name in pairs(STATIC_WIDGETS) do Compat.declare(SURFACE, recKey, { name }) end
  for recKey, r in pairs(REGIONS) do Compat.declare(SURFACE, "region." .. recKey, r[1]) end
  for recKey, names in pairs(CAMELOT) do Compat.declare(SURFACE, recKey, names) end
  for recKey, d in pairs(DYNAMIC) do Compat.declare(SURFACE, recKey, { d[1] }) end
  for name in pairs(HELP) do Compat.declare(SURFACE, "help." .. name, { name }) end
  for _, name in ipairs({ "SendMailRadioButton_OnClick", "SendMailFrame" }) do
    Compat.declare(SURFACE, name, { name })
  end
  if hooked then return false end
  hooked = true

  -- labels first, so the tabs' first OnShow measures the Japanese; the changing widgets' current (XML) text too
  Mail.showStatic()
  for group in pairs(GROUPS) do showGroup(group) end

  local html = Compat.get(SURFACE, "body")
  if type(html) == "table" and type(html.SetText) == "function" then
    body.html = html
    hooksecurefunc(html, "SetText", Mail.onBodyText)
  end
  hookUpdate("inboxFrame", Mail.onInboxUpdate)
  hookUpdate("openMailFrame", Mail.onOpenMailUpdate)
  if type(Compat.get(SURFACE, "SendMailRadioButton_OnClick")) == "function" then
    hooksecurefunc("SendMailRadioButton_OnClick", Mail.onRadio)
  end
  -- the template titles
  if type(Compat.get(SURFACE, "tabClick")) == "function" then
    hooksecurefunc("MailFrameTab_OnClick", Mail.onFrameTitle)
  end
  local openFrame = Compat.get(SURFACE, "openMailFrame")
  if type(openFrame) == "table" and type(openFrame.HookScript) == "function" then
    openFrame:HookScript("OnShow", Mail.onOpenTitle)
  end
  Mail.onFrameTitle()
  Mail.onOpenTitle()
  local sendFrame = Compat.get(SURFACE, "SendMailFrame")
  if type(sendFrame) == "table" and type(sendFrame.HookScript) == "function" then
    sendFrame:HookScript("OnShow", Mail.onSendShow)
  end
  local openAll = Compat.get(SURFACE, "openAll")
  if type(openAll) == "table" then
    for _, method in ipairs({ "StartOpening", "StopOpening" }) do
      if type(openAll[method]) == "function" then hooksecurefunc(openAll, method, Mail.onOpenAll) end
    end
  end
  for name, only in pairs(HELP) do
    local owner = Compat.get(SURFACE, "help." .. name)
    if type(owner) == "table" then WFJ.HelpTooltip.register(owner, { only = only }) end
  end
  return true
end
