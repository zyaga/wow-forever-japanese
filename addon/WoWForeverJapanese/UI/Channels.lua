-- UI/Channels.lua: the Chat Channels window and the voice-chat prompts on Forever (surface "channels", area "ui",
-- ADR-016). Blizzard_Channels loads at login on `camelot` (its toc gates Mainline\* to mainline); the window
-- opens from the chat frame's channel button (blizzard_chatframebase/mainline/channelframebuttonmixin.lua), the
-- Communities window and a channel link (blizzard_uipanels_game/shared/itemrefhandlersshared.lua) through
-- ToggleChannelFrame. Blizzard_VoiceToggleButton's roster buttons are instantiated by this window's rows
-- (mainline/rosterbutton.xml:23–33), so their tooltips are served here.
-- Static labels: ChannelFrame's title, SetTitle(CHAT_CHANNELS) (mainline/channelframe.lua:26) → Labels.title;
--   NewButton ADD, SettingsButton SETTINGS (mainline/channelframe.xml:21, 32);
--   VoiceChatPromptActivateChannel.AcceptButton (mainline/voicechatprompt.xml:31).
-- Dynamic, each the frame's own method (mixins are copied onto the frame at load; every call is `self:…()`):
--   VoiceChatPromptActivateChannel:Setup → Text, "Join |c<colour>Party|r voice chat?"; the colour is the template's
--     argument, kept as written (mainline/voicechatprompt.lua:39–46, 87–92);
--   VoiceChatChannelActivatedNotification:Setup → Text ("Joined |c<colour>Party|r voice chat."), Text2 (push-to-talk
--     key / unbound / open mic; the key's name is kept as written) (voicechatprompt.lua:48–63, 165–173). A community
--     channel's notification carries the community's name and is never matched.
-- Help tooltips, registered from the roster ScrollBox's initialized-frame callback (pooled rows, keyed by widget):
--   SelfDeafenButton / SelfMuteButton / MemberMuteButton (PropertyBindingMixin:SetTooltip → GameTooltip_SetTitle,
--   blizzard_sharedxml/propertybindingmixin.lua:125–134; the texts, blizzard_voicetogglebutton/voicetogglebutton.lua:
--   58–69, 107–111, 228–231; the self buttons' titles carry the key binding, the `binding` label form); a row whose
--   member has not arrived shows VOICE_CHAT_AWAITING_MEMBER_NAME as its tooltip (mainline/rosterbutton.lua:187–191);
--   the same line is a member's name otherwise, so it is restricted to that key;
--   the channel list's headset and transcription buttons: each ChannelButtonTemplate row carries a Speaker
--   (VoiceChatHeadsetTemplate, mainline/channelbutton.xml:51–64; the templates are Blizzard_ChatFrame's,
--   blizzard_chatframe/mainline/voicechatheadsetbutton.xml:16–37). The rows come from three frame pools refilled by
--   ChannelFrame.ChannelList:Update (mainline/channellist.lua:10–13, 79–86), post-hooked and walked (keyed by widget).
--   Headset: VOICE_CHAT_JOIN / VOICE_CHAT_LEAVE, or the disabled reasons VOICECHAT_DISABLED /
--   COMMUNITY_FEATURE_UNAVAILABLE_MUTED / ERR_GROUPS_VOICE_CHAT_DISABLED, and the age-restriction titles
--   AGE_RESTRICTED_VOICE_CHAT_MINOR_TOOLTIP / _UNVERIFIED_TOOLTIP, and on a Discord party channel with text-to-speech
--   or speech-to-text on, the error line DISCORD_VOICE_TTS_STT_UNSUPPORTED (voicechatheadsetbutton.lua ShowTooltip,
--   :223–252 [verified: 1.60.1.70291]);
--   transcription: VOICE_CHAT_TRANSCRIPTION_ENABLE / _DISABLE (blizzard_chatframe/shared/
--   voicechattranscriptionbutton.lua ShowTooltip, :165–174). Its speech-to-text HelpTip is UI/HelpTips'.
-- Not here: the channel list's names and counts (channel names stay English), the right-click menus (UI/Menus), the
-- New Channel popup (CreateChannelPopup is shown with StaticPopupSpecial_Toggle, channelframe.lua:410, ADR-015 §5),
-- the voice HelpTip (UI/HelpTips), every chat-line announcement (ChatFrameUtil.DisplaySystemMessageInPrimary).
-- The surface is set up only where ChannelFrame carries SetTitle (the mainline ButtonFrameTemplate's
-- TitledPanelMixin, blizzard_sharedxml/portraitframe.lua:12; UI/Labels.title).
local _, WFJ = ...
local Channels = {}
WFJ.Channels = Channels

local SURFACE = "channels"
Channels.SURFACE = SURFACE
local Compat = WFJ.Compat

Channels.NEVER_TOUCH = { "ChannelFrame.ChannelRoster.ChannelName", "CreateChannelPopup.Name",
  "CreateChannelPopup.Password" }

local PROMPT, ACTIVATED = "VoiceChatPromptActivateChannel", "VoiceChatChannelActivatedNotification"

local LABELS = {
  new = { "ChannelFrame.NewButton", { "ADD" } }, settings = { "ChannelFrame.SettingsButton", { "SETTINGS" } },
  accept = { PROMPT .. ".AcceptButton", { "VOICE_CHAT_PROMPT_CHANNEL_ACTIVATE_ACCEPT" } },
  prompt = { PROMPT .. ".Text", { "VOICE_CHAT_PROMPT_CHANNEL_ACTIVATE_PARTY",
    "VOICE_CHAT_PROMPT_CHANNEL_ACTIVATE_INSTANCE", "VOICE_CHAT_PROMPT_CHANNEL_ACTIVATE_RAID" } },
  activated = { ACTIVATED .. ".Text", { "VOICE_CHAT_NOTIFICATION_CHANNEL_ACTIVATED_PARTY",
    "VOICE_CHAT_NOTIFICATION_CHANNEL_ACTIVATED_INSTANCE", "VOICE_CHAT_NOTIFICATION_CHANNEL_ACTIVATED_RAID" } },
  mode = { ACTIVATED .. ".Text2", { "VOICE_CHAT_NOTIFICATION_COMMS_MODE_PTT",
    "VOICE_CHAT_NOTIFICATION_COMMS_MODE_PTT_UNBOUND", "VOICE_CHAT_NOTIFICATION_COMMS_MODE_VOICE_ACTIVATED" } },
}
local STATIC = { "new", "settings", "accept" }

local CANDIDATES = {
  frame = { "ChannelFrame" }, roster = { "ChannelFrame.ChannelRoster.ScrollBox" }, scrollUtil = { "ScrollUtil" },
  prompt = { PROMPT }, activated = { ACTIVATED }, list = { "ChannelFrame.ChannelList" },
}

local TITLE = { only = { "CHAT_CHANNELS" } }
local ROW_TIP = { only = { "VOICE_CHAT_AWAITING_MEMBER_NAME" } }
local DEAFEN_TIP = { only = { "VOICE_TOOLTIP_DEAFEN", "VOICE_TOOLTIP_UNDEAFEN" } }
-- The silenced / parental-controls titles (voicetogglebutton.lua:63–69): their "|n|n" is inside the English,
-- MicroButtonTooltipText appends the binding after it (the `binding` form)
local MUTE_TIP = { only = { "VOICE_TOOLTIP_MUTE_MIC", "VOICE_TOOLTIP_UNMUTE_MIC", "VOICE_TOOLTIP_SILENCED_MUTE_MIC",
  "VOICE_TOOLTIP_SILENCED_UNMUTE_MIC", "VOICE_TOOLTIP_PARENTAL_MUTE_MIC", "VOICE_TOOLTIP_PARENTAL_UNMUTE_MIC" } }
local MEMBER_TIP = { only = { "MUTE", "UNMUTE", "MUTE_SILENCED", "UNMUTE_SILENCED" } }
-- The age-restriction titles come first (voicechatheadsetbutton.lua:231–233); a Discord party channel adds the
-- speech-features error line under the title (:248–250)
local HEADSET_TIP = { only = { "VOICE_CHAT_JOIN", "VOICE_CHAT_LEAVE", "VOICECHAT_DISABLED",
  "COMMUNITY_FEATURE_UNAVAILABLE_MUTED", "ERR_GROUPS_VOICE_CHAT_DISABLED", "AGE_RESTRICTED_VOICE_CHAT_MINOR_TOOLTIP",
  "AGE_RESTRICTED_VOICE_CHAT_UNVERIFIED_TOOLTIP", "DISCORD_VOICE_TTS_STT_UNSUPPORTED" } }
local TRANSCRIPTION_TIP = { only = { "VOICE_CHAT_TRANSCRIPTION_ENABLE", "VOICE_CHAT_TRANSCRIPTION_DISABLE" } }
local LIST_POOLS = { "textChannelButtonPool", "voiceChannelButtonPool", "communityChannelButtonPool" }

local function get(key) return Compat.get(SURFACE, key) end

-- Shows the named labels. → the number of dictionary words found.
function Channels.show(...)
  local items = {}
  for _, key in ipairs({ ... }) do
    items[#items + 1] = { key, get("label." .. key), { only = LABELS[key][2] } }
  end
  return WFJ.Labels.showAll(SURFACE, items)
end

-- One pooled roster row after its initializer ran: (owner, frame, elementData) for a new row, (frame, elementData)
-- for the iterateExisting pass. Returns nothing: ForEachFrame stops at the first truthy return.
function Channels.onRosterRow(a, b)
  local row = a
  if a == Channels then row = b end
  if type(row) ~= "table" then return end
  local register = WFJ.HelpTooltip.register
  register(row, ROW_TIP)
  if type(row.SelfDeafenButton) == "table" then register(row.SelfDeafenButton, DEAFEN_TIP) end
  if type(row.SelfMuteButton) == "table" then register(row.SelfMuteButton, MUTE_TIP) end
  if type(row.MemberMuteButton) == "table" then register(row.MemberMuteButton, MEMBER_TIP) end
end

-- hooksecurefunc target (ChannelFrame.ChannelList:Update): registers every listed channel's headset and
-- transcription buttons. → the number of buttons registered
function Channels.onList()
  local list = get("list")
  local n = 0
  if type(list) ~= "table" then return n end
  local register = WFJ.HelpTooltip.register
  for _, poolKey in ipairs(LIST_POOLS) do
    local pool = list[poolKey]
    if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
      for button in pool:EnumerateActive() do
        local speaker = type(button) == "table" and button.Speaker or nil
        if type(speaker) == "table" then
          if type(speaker.Button) == "table" then
            register(speaker.Button, HEADSET_TIP)
            n = n + 1
          end
          local transcription = speaker.Transcription
          if type(transcription) == "table" and type(transcription.Button) == "table" then
            register(transcription.Button, TRANSCRIPTION_TIP)
            n = n + 1
          end
        end
      end
    end
  end
  return n
end

-- hooksecurefunc targets.
function Channels.onPrompt() return Channels.show("prompt", "accept") end
function Channels.onActivated() return Channels.show("activated", "mode") end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Channels.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(LABELS) do Compat.declare(SURFACE, "label." .. key, { l[1] }) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" or type(frame.SetTitle) ~= "function" then return false end
  hooked = true
  WFJ.Labels.title(SURFACE, frame, TITLE)
  Channels.show(unpack(STATIC))
  local prompt, activated = get("prompt"), get("activated")
  if type(prompt) == "table" and type(prompt.Setup) == "function" then
    hooksecurefunc(prompt, "Setup", Channels.onPrompt)
  end
  if type(activated) == "table" and type(activated.Setup) == "function" then
    hooksecurefunc(activated, "Setup", Channels.onActivated)
  end
  local list = get("list")
  if type(list) == "table" and type(list.Update) == "function" then
    hooksecurefunc(list, "Update", Channels.onList)
    Channels.onList()
  end
  local roster, util = get("roster"), get("scrollUtil")
  if type(roster) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(roster, Channels.onRosterRow, Channels, true)
  end
  return true
end
