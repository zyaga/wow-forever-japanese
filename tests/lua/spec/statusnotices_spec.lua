-- Status tray notices: UI/StatusNotices.lua over the GM chat, survey and behavioral-messaging notices
-- replayed from camelot blizzard_gmchatui (lua:185–187, xml:31), blizzard_wowsurveyui (lua:34–36) and
-- blizzard_behavioralmessaging (lua:17–21, 38–44, 148–160, 190–194). Each addon in both load orders.
local S = require("tests.lua.spec.stub_camelot_social")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = S.files("UI/StatusNotices.lua")

local UI = {
  GM_CHAT_STATUS_READY = { "GM Chat Request", "GMチャットのリクエスト" },
  GM_CHAT_STATUS_READY_DESCRIPTION = { "A GM would like to chat with you. Click here to begin.",
    "GMがチャットを希望しています。ここをクリックして開始します。" },
  GM_CHAT = { "Chatting with a GM", "GMとチャット中" },
  USER_SURVEY_STATUS_READY = { "Research Survey Available", "アンケートがあります" },
  USER_SURVEY_STATUS_READY_DESCRIPTION = { "We want your feedback! Click here to access the survey.",
    "ご意見をお聞かせください! ここをクリックしてアンケートを開きます。" },
  BEHAVIORAL_NOTIFICATION_WARNING = { "Behavior Warning", "行動に関する警告" },
  BEHAVIORAL_NOTIFICATION_OPEN = { "Click here to read the message", "ここをクリックしてメッセージを読む" },
  BEHAVIORAL_DETAILS_TITLE_BAR = { "WoW Customer Support", "WoWカスタマーサポート" },
  BEHAVIORAL_DETAILS_CLOSE_BUTTON = { "Close", "閉じる" },
  BEHAVIORAL_DETAILS_SOCIAL_TITLE = { "Warning - Communication", "警告 - コミュニケーション" },
  BEHAVIORAL_DETAILS_SOCIAL_MESSAGE = { "Your recent communication behavior is not in line.", "最近の発言に問題があります。" },
}

local function status(name, title, subtitle)
  local f = S.frame(name)
  f.TitleText, f.SubtitleText = S.fs(S.en(title)), S.fs(S.en(subtitle))
end

local LOADERS = {
  Blizzard_GMChatUI = function()
    status("GMChatStatusFrame", "GM_CHAT_STATUS_READY", "GM_CHAT_STATUS_READY_DESCRIPTION")
    Stub.namedFontString("GMChatTabText", S.en("GM_CHAT"))
  end,
  Blizzard_WowSurveyUI = function()
    status("WowSurveyStatusFrame", "USER_SURVEY_STATUS_READY", "USER_SURVEY_STATUS_READY_DESCRIPTION")
  end,
  Blizzard_BehavioralMessaging = function()
    local tray = S.frame("BehavioralMessagingTray")
    tray.pool = S.pool(function()
      return { TitleText = S.fs(""), SubtitleText = S.fs(S.en("BEHAVIORAL_NOTIFICATION_OPEN")) }
    end)
    function tray.EvaluateLayout() end -- the addon's hook target (blizzard_behavioralmessaging.lua:148–160)
    local details = S.frame("BehavioralMessagingDetails")
    details.Text = S.fs(S.en("BEHAVIORAL_DETAILS_TITLE_BAR"))
    details.CloseButton = S.button(nil, S.en("BEHAVIORAL_DETAILS_CLOSE_BUTTON"))
    details.Body = { TitleText = S.fs(""), BodyText = S.fs("") }
    function details.DisplayInternal(self, title, body)
      self.Body.TitleText.text, self.Body.BodyText.text = title, body
    end
  end,
}
local GLOBALS = { "GMChatStatusFrame", "GMChatTabText", "WowSurveyStatusFrame", "BehavioralMessagingTray",
  "BehavioralMessagingDetails" }

-- Replays BehavioralMessagingTrayMixin:OnEvent (lua:119–146): the pooled notification's UpdateText
-- (lua:38–44; a stack of n is AUCTION_MAIL_ITEM_STACK "<label> (<n>)") and then the tray's EvaluateLayout, which the
-- addon hooks. → the notification
local function notify(count)
  local tray = _G.BehavioralMessagingTray
  local notice = tray.pool.active[1] or tray.pool:Acquire()
  notice.TitleText.text = count > 1 and ("Behavior Warning (%d)"):format(count)
    or S.en("BEHAVIORAL_NOTIFICATION_WARNING")
  tray:EvaluateLayout()
  return notice
end

local function load(addon)
  LOADERS[addon]()
  Stub.loadedAddons[addon] = true
end

describe("the status tray notices on Forever", function()
  local WFJ
  before_each(function() WFJ = S.load(FILES, UI) end)
  after_each(function() S.teardown(GLOBALS) end)

  local function check()
    assert.are.equal("GMチャットのリクエスト", _G.GMChatStatusFrame.TitleText:GetText())
    assert.are.equal("GMがチャットを希望しています。ここをクリックして開始します。", _G.GMChatStatusFrame.SubtitleText:GetText())
    assert.are.equal("GMとチャット中", _G.GMChatTabText:GetText())
    assert.are.equal("アンケートがあります", _G.WowSurveyStatusFrame.TitleText:GetText())
    assert.are.equal("WoWカスタマーサポート", _G.BehavioralMessagingDetails.Text:GetText())
    assert.are.equal("閉じる", _G.BehavioralMessagingDetails.CloseButton:GetText())
    local notice = notify(1)
    assert.are.equal("行動に関する警告", notice.TitleText:GetText())
    assert.are.equal("ここをクリックしてメッセージを読む", notice.SubtitleText:GetText())
    notify(2) -- the stacked "<label> (2)" is a composite: left as written
    assert.are.equal("Behavior Warning (2)", notice.TitleText:GetText())
    _G.BehavioralMessagingDetails:DisplayInternal(S.en("BEHAVIORAL_DETAILS_SOCIAL_TITLE"),
      S.en("BEHAVIORAL_DETAILS_SOCIAL_MESSAGE"))
    assert.are.equal("警告 - コミュニケーション", _G.BehavioralMessagingDetails.Body.TitleText:GetText())
    assert.are.equal("最近の発言に問題があります。", _G.BehavioralMessagingDetails.Body.BodyText:GetText())
    S.alt(WFJ, true)
    assert.are.equal("GM Chat Request", _G.GMChatStatusFrame.TitleText:GetText())
    S.alt(WFJ, false)
  end

  it("addons loaded before the surface starts", function()
    for addon in pairs(LOADERS) do load(addon) end
    assert.is_true(WFJ.StatusNotices.init())
    check()
  end)

  it("addons loaded on demand", function()
    assert.is_false(WFJ.StatusNotices.init()) -- nothing loaded: nothing touched
    for addon in pairs(LOADERS) do
      load(addon)
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(addon))
    end
    check()
    assert.are.equal(1, #Stub.hooks["BehavioralMessagingTray:EvaluateLayout"])
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    for addon in pairs(LOADERS) do load(addon) end
    _G.GMChatStatusFrame.TitleText = 3
    _G.WowSurveyStatusFrame = "?"
    _G.BehavioralMessagingTray.pool = true
    _G.BehavioralMessagingDetails.DisplayInternal = 1
    assert.has_no.errors(function() WFJ.StatusNotices.init() end)
    assert.are.equal("GMとチャット中", _G.GMChatTabText:GetText())
  end)
end)
