-- UI/Channels.lua over ChannelFrame replayed from camelot
-- blizzard_channels/mainline (channelframe.lua:26, channelframe.xml:21–32, voicechatprompt.lua:39–63 + 87–92 +
-- 165–173, rosterbutton.lua:187–191, channellist.lua:10–13 + 79–86), blizzard_voicetogglebutton's roster buttons and
-- Blizzard_ChatFrame's headset / transcription buttons on the channel list (voicechatheadsetbutton.lua:223–252,
-- voicechattranscriptionbutton.lua:165–174). Channel and member names stay English.
local S = require("tests.lua.spec.stub_camelot_social")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = S.files("UI/Channels.lua")

local UI = {
  CHAT_CHANNELS = { "Chat Channels", "チャットチャンネル" }, ADD = { "Add", "追加" }, SETTINGS = { "Settings", "設定" },
  VOICE_CHAT_PROMPT_CHANNEL_ACTIVATE_ACCEPT = { "Accept", "承諾" },
  VOICE_CHAT_PROMPT_CHANNEL_ACTIVATE_PARTY = { "Join |c%sParty|r voice chat?", "|c%sParty|rボイスチャットに参加しますか?" },
  VOICE_CHAT_NOTIFICATION_CHANNEL_ACTIVATED_PARTY = { "Joined |c%sParty|r voice chat.",
    "|c%sParty|rボイスチャットに参加しました。" },
  VOICE_CHAT_NOTIFICATION_COMMS_MODE_PTT = { "Push %s to talk.", "%sを押して発言。" },
  VOICE_CHAT_NOTIFICATION_COMMS_MODE_VOICE_ACTIVATED = { "Open Mic.", "オープンマイク。" },
  VOICE_CHAT_AWAITING_MEMBER_NAME = { "Waiting...", "待機中..." },
  VOICE_TOOLTIP_DEAFEN = { "Deafen Voice Chat", "ボイスチャットの音声を切る" },
  MUTE = { "Mute", "ミュート" }, UNMUTE = { "Unmute", "ミュート解除" },
  VOICE_CHAT_JOIN = { "Join Voice Chat", "ボイスチャットに参加" },
  VOICE_CHAT_LEAVE = { "Leave Voice Chat", "ボイスチャットから退出" },
  VOICECHAT_DISABLED = { "Voice Chat Disabled", "ボイスチャットは無効です" },
  -- the headset's age-restriction title (voicechatheadsetbutton.lua:228–230)
  AGE_RESTRICTED_VOICE_CHAT_MINOR_TOOLTIP = { "Voice chat and other social features are unavailable on accounts "
    .. "belonging to minors.", "未成年者のアカウントでは、ボイスチャットやその他のソーシャル機能を利用できません。" },
  -- a Discord party channel's error line under the headset's title (voicechatheadsetbutton.lua:248–250)
  DISCORD_VOICE_TTS_STT_UNSUPPORTED = { "Text-to-Speech and Speech-to-Text are not supported in this channel because "
    .. "it uses the Discord service.", "このチャンネルはDiscordサービスを使用しているため、読み上げと音声入力は使えません。" },
  VOICE_CHAT_TRANSCRIPTION_ENABLE = { "Enable Voice Transcription", "音声の文字起こしを有効化" },
  CLOSE = { "Close", "閉じる" }, -- a word a channel or a member may happen to be called
  -- the parental-controls title (voicetogglebutton.lua:67), its "|n|n" inside the English
  VOICE_TOOLTIP_PARENTAL_MUTE_MIC = { "Mute|n|nYour account has been marked as voice-chat listen-only in Parental "
    .. "Controls.", "ミュート|n|nペアレンタルコントロールでボイスチャットが聞き取り専用に設定されています。" },
}
-- Core/UIStrings: the colour and the key name are `text` arguments; the self buttons' titles use the `binding` form
local NEEDS = { ARGS = { VOICE_CHAT_PROMPT_CHANNEL_ACTIVATE_PARTY = { [1] = "text" },
  VOICE_CHAT_NOTIFICATION_CHANNEL_ACTIVATED_PARTY = { [1] = "text" },
  VOICE_CHAT_NOTIFICATION_COMMS_MODE_PTT = { [1] = "text" } },
  LABELS = { VOICE_TOOLTIP_DEAFEN = "binding" } }

local C = {}

local function installChannels(o)
  o = o or {}
  local en = S.en
  local frame = S.frame("ChannelFrame")
  S.put(frame, "TitleContainer.TitleText", S.fs(""))
  if not o.untitled then
    function frame.SetTitle(self, title) self.TitleContainer.TitleText.text = title end
    frame:SetTitle(en("CHAT_CHANNELS"))
  end
  frame.NewButton, frame.SettingsButton = S.button(nil, en("ADD")), S.button(nil, en("SETTINGS"))
  S.put(frame, "ChannelRoster.ChannelName", S.fs("Close"))
  frame.ChannelRoster.ScrollBox = Stub.scrollBox()
  function C.row()
    local row = CreateFrame("Button")
    row.Name = S.fs("Close")
    row.SelfDeafenButton, row.SelfMuteButton, row.MemberMuteButton = S.frame(), S.frame(), S.frame()
    frame.ChannelRoster.ScrollBox:initFrame(row, {})
    return row
  end
  -- ChannelListMixin (channellist.lua:10–13, 79–86): three frame pools of ChannelButtonTemplate rows, each with a
  -- Speaker (VoiceChatHeadsetTemplate: Button + Transcription.Button), refilled by :Update
  local list = S.put(frame, "ChannelList", S.frame(nil, "ChannelList"))
  local function speakerRow()
    local row = CreateFrame("Button")
    row.Name = S.fs("Close")
    row.Speaker = { Button = S.frame(), Transcription = { Button = S.frame() } }
    return row
  end
  list.textChannelButtonPool, list.voiceChannelButtonPool = S.pool(speakerRow), S.pool(speakerRow)
  list.communityChannelButtonPool = S.pool(speakerRow)
  function list.Update(self)
    self.textChannelButtonPool:ReleaseAll()
    for _ = 1, C.channels or 1 do self.textChannelButtonPool:Acquire() end
  end
  list:Update()
  local prompt = S.frame("VoiceChatPromptActivateChannel")
  prompt.Text, prompt.AcceptButton = S.fs(""), S.button(nil, en("VOICE_CHAT_PROMPT_CHANNEL_ACTIVATE_ACCEPT"))
  function prompt.Setup(self) self.Text.text = en("VOICE_CHAT_PROMPT_CHANNEL_ACTIVATE_PARTY"):format("ff7fbfff") end
  local activated = S.frame("VoiceChatChannelActivatedNotification")
  activated.Text, activated.Text2 = S.fs(""), S.fs("")
  function activated.Setup(self)
    self.Text.text = C.community and "Joined |cff7fbfffClose|r voice chat."
      or en("VOICE_CHAT_NOTIFICATION_CHANNEL_ACTIVATED_PARTY"):format("ff7fbfff")
    self.Text2.text = C.openMic and en("VOICE_CHAT_NOTIFICATION_COMMS_MODE_VOICE_ACTIVATED")
      or en("VOICE_CHAT_NOTIFICATION_COMMS_MODE_PTT"):format("CTRL-T")
  end
end

local GLOBALS = { "ChannelFrame", "VoiceChatPromptActivateChannel", "VoiceChatChannelActivatedNotification" }

describe("the chat channels window on Forever", function()
  local WFJ

  before_each(function()
    WFJ = S.load(FILES, UI, NEEDS)
    C.community, C.openMic, C.channels = false, false, 1
  end)
  after_each(function() S.teardown(GLOBALS) end)

  it("the title renders after SetTitle and again after a second SetTitle; the buttons are Japanese", function()
    installChannels()
    assert.is_true(WFJ.Channels.init())
    local frame = _G.ChannelFrame
    assert.are.equal("チャットチャンネル", frame.TitleContainer.TitleText:GetText())
    frame:SetTitle(S.en("CHAT_CHANNELS"))
    assert.are.equal("チャットチャンネル", frame.TitleContainer.TitleText:GetText())
    frame:SetTitle("Close") -- never a name: the title is restricted to CHAT_CHANNELS
    assert.are.equal("Close", frame.TitleContainer.TitleText:GetText())
    assert.are.equal("追加", frame.NewButton:GetText())
    assert.are.equal("設定", frame.SettingsButton:GetText())
    S.alt(WFJ, true)
    assert.are.equal("Add", frame.NewButton:GetText())
    S.alt(WFJ, false)
    assert.are.equal("Close", frame.ChannelRoster.ChannelName:GetText())
    assert.is_true(S.unrecorded(WFJ, frame.ChannelRoster.ChannelName))
  end)

  it("voice prompts follow their Setup; a community's name is left as written", function()
    installChannels()
    WFJ.Channels.init()
    local prompt, activated = _G.VoiceChatPromptActivateChannel, _G.VoiceChatChannelActivatedNotification
    assert.are.equal("承諾", prompt.AcceptButton:GetText())
    prompt:Setup()
    assert.are.equal("|cff7fbfffParty|rボイスチャットに参加しますか?", prompt.Text:GetText())
    activated:Setup()
    assert.are.equal("|cff7fbfffParty|rボイスチャットに参加しました。", activated.Text:GetText())
    assert.are.equal("CTRL-Tを押して発言。", activated.Text2:GetText())
    C.community, C.openMic = true, true
    activated:Setup()
    assert.are.equal("Joined |cff7fbfffClose|r voice chat.", activated.Text:GetText())
    assert.are.equal("オープンマイク。", activated.Text2:GetText())
  end)

  it("roster rows: the voice buttons' tooltips translate; a member's name in the row tooltip does not", function()
    installChannels()
    WFJ.Channels.init()
    local row = C.row()
    assert.are.same({ "ミュート" }, S.tooltip(row.MemberMuteButton, { "Mute" }))
    assert.are.same({ "ボイスチャットの音声を切る |cffffd200(F9)|r" },
      S.tooltip(row.SelfDeafenButton, { "Deafen Voice Chat |cffffd200(F9)|r" }))
    assert.are.same({ "待機中..." }, S.tooltip(row, { "Waiting..." }))
    assert.are.same({ "Close" }, S.tooltip(row, { "Close" })) -- a member called like a UI word
    assert.are.same({ "Mute" }, S.tooltip(row.SelfDeafenButton, { "Mute" })) -- not this button's key
    assert.is_true(S.unrecorded(WFJ, row.Name))
  end)

  it("the self-mute button's parental-controls title, the binding kept after the |n|n sentence", function()
    installChannels()
    WFJ.Channels.init()
    local row = C.row()
    local en = "Mute|n|nYour account has been marked as voice-chat listen-only in Parental Controls."
    assert.are.same({ "ミュート|n|nペアレンタルコントロールでボイスチャットが聞き取り専用に設定されています。 |cffffd200(F10)|r" },
      S.tooltip(row.SelfMuteButton, { en .. " |cffffd200(F10)|r" }))
    assert.are.same({ "ミュート|n|nペアレンタルコントロールでボイスチャットが聞き取り専用に設定されています。" },
      S.tooltip(row.SelfMuteButton, { en }))
    assert.are.same({ en }, S.tooltip(row.SelfDeafenButton, { en })) -- not the deafen button's key
  end)

  it("channel list: the headset and transcription buttons' tooltips translate after ChannelList:Update", function()
    installChannels()
    WFJ.Channels.init()
    C.channels = 2
    _G.ChannelFrame.ChannelList:Update()
    local row = _G.ChannelFrame.ChannelList.textChannelButtonPool.active[2]
    assert.are.same({ "ボイスチャットに参加" }, S.tooltip(row.Speaker.Button, { "Join Voice Chat" }))
    assert.are.same({ "ボイスチャットは無効です" }, S.tooltip(row.Speaker.Button, { "Voice Chat Disabled" }))
    local minor = UI.AGE_RESTRICTED_VOICE_CHAT_MINOR_TOOLTIP
    assert.are.same({ minor[2] }, S.tooltip(row.Speaker.Button, { minor[1] }))
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(minor[1], _G.GameTooltipTextLeft1:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    local discord = UI.DISCORD_VOICE_TTS_STT_UNSUPPORTED
    assert.are.same({ "ボイスチャットから退出", discord[2] },
      S.tooltip(row.Speaker.Button, { "Leave Voice Chat", discord[1] }))
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(discord[1], _G.GameTooltipTextLeft2:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.same({ "ボイスチャットに参加", "Speech features are off." },
      S.tooltip(row.Speaker.Button, { "Join Voice Chat", "Speech features are off." }))
    assert.are.same({ "音声の文字起こしを有効化" },
      S.tooltip(row.Speaker.Transcription.Button, { "Enable Voice Transcription" }))
    assert.are.same({ "Join Voice Chat" }, S.tooltip(row.Speaker.Transcription.Button, { "Join Voice Chat" }))
    assert.are.equal("Close", row.Name:GetText())
    assert.are.equal(1, #Stub.hooks["ChannelList:Update"])
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    installChannels()
    _G.ChannelFrame.NewButton = 5
    _G.ChannelFrame.ChannelRoster.ScrollBox = "?"
    _G.VoiceChatPromptActivateChannel.Setup = true
    _G.VoiceChatChannelActivatedNotification = "?"
    _G.ChannelFrame.ChannelList.voiceChannelButtonPool = 7
    _G.ChannelFrame.ChannelList.textChannelButtonPool.active[1].Speaker = "?"
    assert.has_no.errors(function() assert.is_true(WFJ.Channels.init()) end)
    assert.are.equal("設定", _G.ChannelFrame.SettingsButton:GetText())
  end)

  it("hooks install once; without the mainline ChannelFrame init returns false and touches nothing", function()
    assert.is_false(WFJ.Channels.init()) -- no ChannelFrame at all
    installChannels({ untitled = true }) -- a ChannelFrame without SetTitle
    assert.is_false(WFJ.Channels.init())
    assert.are.equal("Add", _G.ChannelFrame.NewButton:GetText())
    installChannels()
    assert.is_true(WFJ.Channels.init())
    assert.is_false(WFJ.Channels.init())
    assert.are.equal(1, #Stub.hooks["ChannelFrame:SetTitle"])
    assert.are.equal(1, #Stub.hooks["VoiceChatPromptActivateChannel:Setup"])
  end)
end)
