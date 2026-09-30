-- UI/HelpFrame.lua over HelpFrame, BrowserSettingsTooltip, TicketStatusFrame and
-- HelpOpenWebTicketButton replayed from camelot blizzard_helpframe (helpframe.lua:51, 154–177, 245–265;
-- helpframe.xml:82–105). A server-written ticket title is left as written.
local S = require("tests.lua.spec.stub_camelot_social")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = S.files("UI/HelpFrame.lua")

local UI = {
  HELP_FRAME_TITLE = { "Customer Support", "カスタマーサポート" },
  BROWSER_SETTINGS_TOOLTIP = { "Support Browser Options", "サポートブラウザのオプション" },
  BROWSER_DELETE_COOKIES = { "Delete Cookies", "Cookieを削除" },
  BROWSER_DELETE_COOKIES_TOOLTIP = { "This will delete all browser cookies.", "ブラウザのCookieをすべて削除します。" },
  TICKET_STATUS = { "You have an open ticket.", "未解決のチケットがあります。" },
  TICKET_STATUS_NMI = { "Your ticket requires additional information", "チケットに追加情報が必要です" },
  GM_RESPONSE_ALERT = { "You have received a ticket response. Click here to read it.",
    "チケットへの返信が届きました。ここをクリックして読みます。" },
  HELPFRAME_TICKET_CLICK_HELP = { "Click here to open your ticket.", "ここをクリックしてチケットを開きます。" },
  CLOSE = { "Close", "閉じる" },
}

local function install(o)
  o = o or {}
  local en = S.en
  local frame = S.frame("HelpFrame")
  S.put(frame, "TitleContainer.TitleText", S.fs(""))
  if not o.untitled then
    function frame.SetTitle(self, title) self.TitleContainer.TitleText.text = title end
    frame:SetTitle(en("HELP_FRAME_TITLE"))
  end
  local browser = S.frame("BrowserSettingsTooltip")
  browser.Title = S.fs(en("BROWSER_SETTINGS_TOOLTIP"))
  browser.CookiesButton = S.button(nil, en("BROWSER_DELETE_COOKIES"))
  Stub.namedFontString("TicketStatusTitleText", "")
  local ticket = S.frame("TicketStatusFrame")
  ticket:RegisterEvent("UPDATE_WEB_TICKET")
  ticket:SetScript("OnEvent", function(_, _, key) _G.TicketStatusTitleText.text = en(key) end) -- bound by reference
  S.frame("HelpOpenWebTicketButton")
end

local GLOBALS = { "HelpFrame", "BrowserSettingsTooltip", "TicketStatusTitleText", "TicketStatusFrame",
  "HelpOpenWebTicketButton" }

describe("the customer support window on Forever", function()
  local WFJ
  before_each(function() WFJ = S.load(FILES, UI) end)
  after_each(function() S.teardown(GLOBALS) end)

  it("the title renders after SetTitle and again after a second SetTitle; the browser options are Japanese", function()
    install()
    assert.is_true(WFJ.HelpFrame.init())
    local title = _G.HelpFrame.TitleContainer.TitleText
    assert.are.equal("カスタマーサポート", title:GetText())
    _G.HelpFrame:SetTitle(S.en("HELP_FRAME_TITLE"))
    assert.are.equal("カスタマーサポート", title:GetText())
    assert.are.equal("サポートブラウザのオプション", _G.BrowserSettingsTooltip.Title:GetText())
    assert.are.equal("Cookieを削除", _G.BrowserSettingsTooltip.CookiesButton:GetText())
    S.alt(WFJ, true)
    assert.are.equal("Customer Support", title:GetText())
    S.alt(WFJ, false)
    assert.are.same({ "ブラウザのCookieをすべて削除します。" },
      S.tooltip(_G.BrowserSettingsTooltip.CookiesButton, { S.en("BROWSER_DELETE_COOKIES_TOOLTIP") }))
  end)

  it("the ticket notice follows its event; the ticket button's tooltip keeps a server-written title", function()
    install()
    WFJ.HelpFrame.init()
    _G.TicketStatusFrame:fire("UPDATE_WEB_TICKET", "TICKET_STATUS_NMI")
    assert.are.equal("チケットに追加情報が必要です", _G.TicketStatusTitleText:GetText())
    _G.TicketStatusFrame:fire("UPDATE_WEB_TICKET", "GM_RESPONSE_ALERT")
    assert.are.equal("チケットへの返信が届きました。ここをクリックして読みます。", _G.TicketStatusTitleText:GetText())
    assert.are.same({ "未解決のチケットがあります。", "チケットに追加情報が必要です", " ", "ここをクリックしてチケットを開きます。" },
      S.tooltip(_G.HelpOpenWebTicketButton, { S.en("TICKET_STATUS"), S.en("TICKET_STATUS_NMI"), " ",
        S.en("HELPFRAME_TICKET_CLICK_HELP") }))
    assert.are.same({ "Close", "Close" }, S.tooltip(_G.HelpOpenWebTicketButton, { "Close", "Close" })) -- overrides
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    install()
    _G.TicketStatusFrame, _G.HelpOpenWebTicketButton, _G.BrowserSettingsTooltip.CookiesButton = 4, "?", true
    assert.has_no.errors(function() assert.is_true(WFJ.HelpFrame.init()) end)
    assert.are.equal("サポートブラウザのオプション", _G.BrowserSettingsTooltip.Title:GetText())
  end)

  it("hooks install once; without the mainline HelpFrame init returns false and touches nothing", function()
    assert.is_false(WFJ.HelpFrame.init())
    install({ untitled = true })
    assert.is_false(WFJ.HelpFrame.init())
    assert.are.equal("Delete Cookies", _G.BrowserSettingsTooltip.CookiesButton:GetText())
    install()
    assert.is_true(WFJ.HelpFrame.init())
    assert.is_false(WFJ.HelpFrame.init())
    assert.are.equal(1, #Stub.hooks["HelpFrame:SetTitle"])
  end)
end)
