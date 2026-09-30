-- The text-to-speech panes of the chat configuration window on Forever: UI/TextToSpeech.lua over a
-- TextToSpeechFrame replayed from camelot blizzard_chatframe/shared/texttospeechframe.xml:35–165 and
-- texttospeechframe.lua (CreateCheckboxes :603–631, the slider OnLoads :667–703). Voice names are never touched.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/TextToSpeech.lua"

local UI = { TEXT_TO_SPEECH_VOICE_OPTIONS = { "Voice Options", "音声オプション" },
  GUILD = { "Guild", "ギルド" }, RAID = { "Raid", "レイド" }, RAID_LEADER = { "Raid Leader", "レイドリーダー" },
  TEXT_TO_SPEECH_NARRATE_MY_MESSAGES = { "Read my own messages out loud", "自分のメッセージも読み上げる" },
  TEXT_TO_SPEECH_PLAY_SAMPLE = { "Play Sample", "サンプルを再生" },
  TEXT_TO_SPEECH_ADJUST_RATE = { "Adjust Rate of Speech", "読み上げ速度の調整" }, SLOW = { "Slow", "遅い" },
  FAST = { "Fast", "速い" }, TEXT_TO_SPEECH_ADJUST_VOLUME = { "Speech Volume", "読み上げ音量" },
  SAY = { "Say", "発言" }, PARTY_LEADER = { "Party Leader", "パーティーリーダー" }, LOOT_TTS_LABEL = { "Item Loot", "アイテム獲得" },
  -- the "more voices" line; its link label stays verbatim
  TEXT_TO_SPEECH_MORE_VOICES = { "For more voice options see our |cff00aaff|HurlIndex:56|hSupport Page|h|r",
    "その他の音声は|cff00aaff|HurlIndex:56|hSupport Page|h|rをご覧ください" } }

local function en(key) return _G[key] end
local function check(text) return { text = Stub.fontString(text) } end

local function installFrame()
  local f = CreateFrame("Frame", "TextToSpeechFrame")
  local p = {}
  f.PanelContainer = p
  p.VoiceOptionsLabel = Stub.fontString(en("TEXT_TO_SPEECH_VOICE_OPTIONS"))
  p.NarrateMyMessagesCheckButton = check(en("TEXT_TO_SPEECH_NARRATE_MY_MESSAGES"))
  p.PlaySampleButton = Stub.button(nil, en("TEXT_TO_SPEECH_PLAY_SAMPLE"))
  p.PlaySampleAlternateButton = Stub.button(nil, en("TEXT_TO_SPEECH_PLAY_SAMPLE"))
  p.AdjustRateSlider = { Text = Stub.fontString(en("TEXT_TO_SPEECH_ADJUST_RATE")), Low = Stub.fontString(en("SLOW")),
    High = Stub.fontString(en("FAST")) }
  p.AdjustVolumeSlider = { Text = Stub.fontString(en("TEXT_TO_SPEECH_ADJUST_VOLUME")), Low = Stub.fontString(""),
    High = Stub.fontString("100%") }
  p.MoreVoicesURLContainer = { Text = Stub.fontString(en("TEXT_TO_SPEECH_MORE_VOICES")) }
  p.TtsVoiceDropdown = { Text = Stub.fontString("Fast") } -- a voice the system calls like a dictionary word
  local messages = CreateFrame("Frame", "ChatConfigTextToSpeechMessageSettings")
  -- the client's list of chat types (mainline/texttospeechframeconstants.lua:1), a sample of it
  _G.TEXT_TO_SPEECH_CHAT_TYPES = { "SAY", "PARTY_LEADER", "GUILD", "RAID", "RAID_LEADER", "LOOT", "ENCOUNTER_EVENT" }
  _G.TextToSpeechFrame_CreateCheckboxes = function(frame, types)
    frame.checkBoxes = frame.checkBoxes or {}
    for i, t in ipairs(types) do
      frame.checkBoxes[i] = frame.checkBoxes[i] or check("")
      frame.checkBoxes[i].text.text = en(t .. "_TTS_LABEL") or en(t) or t
    end
  end
  return f, messages
end

describe("the text-to-speech panes on Forever", function()
  local WFJ

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end

  after_each(function()
    H.uiTeardown()
    for _, n in ipairs({ "TextToSpeechFrame", "ChatConfigTextToSpeechMessageSettings",
      "TextToSpeechFrame_CreateCheckboxes", "TEXT_TO_SPEECH_CHAT_TYPES" }) do _G[n] = nil end
  end)

  it("static labels and the message-type check buttons are Japanese; a voice's name is never touched", function()
    load()
    local f, messages = installFrame()
    WFJ.Labels.forbidNames(WFJ.TextToSpeech.NEVER_TOUCH)
    assert.is_true(WFJ.TextToSpeech.init())
    local p = f.PanelContainer
    assert.are.equal("音声オプション", p.VoiceOptionsLabel:GetText())
    assert.are.equal("自分のメッセージも読み上げる", p.NarrateMyMessagesCheckButton.text:GetText())
    assert.are.equal("サンプルを再生", p.PlaySampleButton:GetText())
    assert.are.equal("サンプルを再生", p.PlaySampleAlternateButton:GetText())
    assert.are.equal("読み上げ速度の調整", p.AdjustRateSlider.Text:GetText())
    assert.are.equal("遅い", p.AdjustRateSlider.Low:GetText())
    assert.are.equal("速い", p.AdjustRateSlider.High:GetText())
    assert.are.equal("読み上げ音量", p.AdjustVolumeSlider.Text:GetText())
    assert.are.equal("100%", p.AdjustVolumeSlider.High:GetText())
    assert.are.equal("Fast", p.TtsVoiceDropdown.Text:GetText())
    assert.are.equal("その他の音声は|cff00aaff|HurlIndex:56|hSupport Page|h|rをご覧ください",
      p.MoreVoicesURLContainer.Text:GetText())
    _G.TextToSpeechFrame_CreateCheckboxes(messages, { "SAY", "PARTY_LEADER", "LOOT", "ENCOUNTER_EVENT" })
    local shown = {}
    for i, box in ipairs(messages.checkBoxes) do shown[i] = box.text:GetText() end
    assert.are.same({ "発言", "パーティーリーダー", "アイテム獲得", "ENCOUNTER_EVENT" }, shown)
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal("Say", messages.checkBoxes[1].text:GetText())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    assert.is_false(WFJ.TextToSpeech.init())
    assert.are.equal(1, #Stub.hooks["TextToSpeechFrame_CreateCheckboxes"])
  end)

  it("every chat type the client passes shows its label in Japanese: Guild, Raid and Raid Leader too",
    function()
    load()
    local _, messages = installFrame()
    assert.is_true(WFJ.TextToSpeech.init())
    _G.TextToSpeechFrame_CreateCheckboxes(messages, { "GUILD", "RAID", "RAID_LEADER" })
    local shown = {}
    for i, box in ipairs(messages.checkBoxes) do shown[i] = box.text:GetText() end
    assert.are.same({ "ギルド", "レイド", "レイドリーダー" }, shown)
    _G.TextToSpeechFrame_CreateCheckboxes(messages, { "SAY" }) -- a list without Guild: its box is re-labelled "Say"
    assert.are.equal("発言", messages.checkBoxes[1].text:GetText())
  end)

  it("with no chat-type list to read, the boxes are left as the client wrote them", function()
    load()
    local _, messages = installFrame()
    _G.TEXT_TO_SPEECH_CHAT_TYPES = nil
    assert.is_true(WFJ.TextToSpeech.init())
    messages.checkBoxes = { { text = Stub.fontString("Guild") } }
    assert.are.equal(0, WFJ.TextToSpeech.onCheckboxes(messages))
    assert.are.equal("Guild", messages.checkBoxes[1].text:GetText())
  end)

  it("check buttons built before init are shown when the pane is shown", function()
    load()
    local _, messages = installFrame()
    _G.TextToSpeechFrame_CreateCheckboxes(messages, { "SAY" })
    assert.is_true(WFJ.TextToSpeech.init())
    assert.are.equal("発言", messages.checkBoxes[1].text:GetText())
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    load()
    local f, messages = installFrame()
    f.PanelContainer.AdjustRateSlider, f.PanelContainer.VoiceOptionsLabel = 9, "label"
    messages.checkBoxes = { 1, "two", { text = 3 } }
    _G.TextToSpeechFrame_CreateCheckboxes = "nope"
    assert.has_no.errors(function() assert.is_true(WFJ.TextToSpeech.init()) end)
    assert.has_no.errors(function() WFJ.TextToSpeech.onCheckboxes(5) end)
    assert.are.equal("サンプルを再生", f.PanelContainer.PlaySampleButton:GetText())
  end)

  it("no TextToSpeechFrame → init is false, nothing touched", function()
    load()
    assert.has_no.errors(function() assert.is_false(WFJ.TextToSpeech.init()) end)
  end)
end)
