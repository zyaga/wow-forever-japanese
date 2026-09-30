-- UI/TextToSpeech.lua: the text-to-speech panes of the chat configuration window on Forever (surfaces
-- "texttospeech" and "texttospeech.static", area "ui", ADR-016). TextToSpeechFrame is a child of
-- ChatConfigFrame (blizzard_chatframe/mainline/chatconfigframe.xml:536), built from TextToSpeechFrameTemplate
-- (blizzard_chatframe/shared/texttospeechframe.xml:35–165); its window tab appears when the textToSpeech setting is
-- on (chatconfigframe.lua:2399–2403) or after /tts (texttospeechframe.lua:520–529). It is a module of its own
-- because it changes with the text-to-speech feature, not with the chat options.
-- Static, parentKeys of TextToSpeechFrame.PanelContainer: VoiceOptionsLabel (xml:47); the check buttons' `text`,
--   written in their OnLoad (texttospeechframe.lua:396, 533–560); PlaySampleButton / PlaySampleAlternateButton
--   (xml:116, 133); the sliders' Text / Low / High: TEXT_TO_SPEECH_ADJUST_RATE with SLOW / FAST,
--   TEXT_TO_SPEECH_ADJUST_VOLUME (lua:667–671, 684–703). The volume slider's High is a percentage: restricted away.
-- Dynamic: TextToSpeechFrame_CreateCheckboxes(frame, …) (global, lua:603–631) → the message-type check buttons in
--   frame.checkBoxes, each `_G[type]` or `_G[type .. "_TTS_LABEL"]` ("Say", "Party Leader", "Item Loot"): fixed
--   words, keyed by widget.
-- The "more voices" line MoreVoicesURLContainer.Text TEXT_TO_SPEECH_MORE_VOICES (xml:99) carries a
--   `|HurlIndex:…|h…|h` link: the whole line is one entry whose link label stays verbatim, shown restricted.
-- Never touched: the two voice dropdowns (a voice is the operating system's name for it, lua:419–441).
local _, WFJ = ...
local TextToSpeech = {}
WFJ.TextToSpeech = TextToSpeech

local SURFACE = "texttospeech"
TextToSpeech.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
local Compat = WFJ.Compat

local PANEL = "TextToSpeechFrame.PanelContainer"
TextToSpeech.NEVER_TOUCH = { PANEL .. ".TtsVoiceDropdown", PANEL .. ".TtsVoiceAlternateDropdown",
  PANEL .. ".AdjustVolumeSlider.High" }

-- record key → { path under the panel, the one key it shows }
local STATIC_LABELS = {
  voiceOptions = { "VoiceOptionsLabel", "TEXT_TO_SPEECH_VOICE_OPTIONS" },
  lineBreakSound = { "PlaySoundSeparatingChatLinesCheckButton.text", "TEXT_TO_SPEECH_PLAY_LINE_BREAK_SOUND" },
  addName = { "AddCharacterNameToSpeechCheckButton.text", "TEXT_TO_SPEECH_ADD_CHARACTER_NAME" },
  activitySound = { "PlayActivitySoundWhenNotFocusedCheckButton.text", "TEXT_TO_SPEECH_PLAY_ACTIVITY_SOUND" },
  narrateMine = { "NarrateMyMessagesCheckButton.text", "TEXT_TO_SPEECH_NARRATE_MY_MESSAGES" },
  alternateVoice = { "UseAlternateVoiceForSystemMessagesCheckButton.text", "TEXT_TO_SPEECH_ALTERNATE_SYSTEM_VOICE" },
  playSample = { "PlaySampleButton", "TEXT_TO_SPEECH_PLAY_SAMPLE" },
  playSampleAlternate = { "PlaySampleAlternateButton", "TEXT_TO_SPEECH_PLAY_SAMPLE" },
  rate = { "AdjustRateSlider.Text", "TEXT_TO_SPEECH_ADJUST_RATE" }, rateLow = { "AdjustRateSlider.Low", "SLOW" },
  rateHigh = { "AdjustRateSlider.High", "FAST" },
  volume = { "AdjustVolumeSlider.Text", "TEXT_TO_SPEECH_ADJUST_VOLUME" },
  moreVoices = { "MoreVoicesURLContainer.Text", "TEXT_TO_SPEECH_MORE_VOICES" },
}
local STATIC_ORDER = {}
for key in pairs(STATIC_LABELS) do STATIC_ORDER[#STATIC_ORDER + 1] = key end
table.sort(STATIC_ORDER)

local CANDIDATES = {
  frame = { "TextToSpeechFrame" },
  messages = { "ChatConfigTextToSpeechMessageSettings" }, createCheckboxes = { "TextToSpeechFrame_CreateCheckboxes" },
  chatTypes = { "TEXT_TO_SPEECH_CHAT_TYPES" },
}

local function get(key) return Compat.get(SURFACE, key) end

local boxKey = WFJ.Labels.keyer("type.") -- a message-type check button's record key: follows the widget

-- The labels the client writes once. → the number of dictionary words found.
function TextToSpeech.showStatic()
  local items = {}
  for _, key in ipairs(STATIC_ORDER) do
    local l = STATIC_LABELS[key]
    items[#items + 1] = { key, get("static." .. key), { only = { l[2] } } }
  end
  return WFJ.Labels.showAll(STATIC, items)
end

-- The keys a message-type check box can show: for each chat type the client lists, `_G[type .. "_TTS_LABEL"]` or
-- `_G[type]` (blizzard_chatframe/shared/texttospeechframe.lua:568–572, 624; the list is TEXT_TO_SPEECH_CHAT_TYPES,
-- mainline/texttospeechframeconstants.lua:1, or the one CreateCheckboxes is given). Built from the client's own list,
-- so a type the client adds is covered and a label is never matched against the whole dictionary.
-- → { only = set } | nil when no list can be read (the boxes are then left as written).
local function boxOnly(types)
  if type(types) ~= "table" then types = get("chatTypes") end
  if type(types) ~= "table" then return nil end
  local set = {}
  for _, t in ipairs(types) do
    if type(t) == "string" then
      set[t] = true
      set[t .. "_TTS_LABEL"] = true
    end
  end
  return { only = set }
end

-- hooksecurefunc target (TextToSpeechFrame_CreateCheckboxes(frame, types)). → the number of dictionary words found.
function TextToSpeech.onCheckboxes(frame, types)
  local only = boxOnly(types)
  if not only then return 0 end
  if type(frame) ~= "table" then frame = get("messages") end
  local boxes = type(frame) == "table" and frame.checkBoxes or nil
  if type(boxes) ~= "table" then return 0 end
  local n = 0
  for _, box in pairs(boxes) do
    local text = type(box) == "table" and box.text or nil
    if type(text) == "table" then n = n + WFJ.Labels.show(SURFACE, boxKey(text), text, nil, only) end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- HookScript target (TextToSpeechFrame and the message pane OnShow).
function TextToSpeech.onShow()
  return TextToSpeech.showStatic() + TextToSpeech.onCheckboxes()
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function TextToSpeech.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(STATIC_LABELS) do Compat.declare(SURFACE, "static." .. key, { PANEL .. "." .. l[1] }) end
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  if type(get("createCheckboxes")) == "function" then
    hooksecurefunc("TextToSpeechFrame_CreateCheckboxes", TextToSpeech.onCheckboxes)
  end
  for _, f in ipairs({ frame, get("messages") }) do
    if type(f) == "table" and type(f.HookScript) == "function" then f:HookScript("OnShow", TextToSpeech.onShow) end
  end
  TextToSpeech.onShow()
  return true
end
