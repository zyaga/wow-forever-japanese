-- UI/ChatTabs.lua over tabs replayed from camelot
-- blizzard_chatframebase/mainline/floatingchatframe.xml:357–372 and the channel button's MicroButtonTooltipText
-- title (mainline/channelframebuttonmixin.lua:27–29). A chat window's name is never touched.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/ChatTabs.lua"

local UI = { CHAT_TAB_NAME = { "%s Tab", "%sタブ" },
  CHAT_TAB_RIGHT_CLICK = { "<Right click for Tab Settings>", "<右クリックでタブ設定>" },
  CHAT_CHANNELS = { "Chat Channels", "チャットチャンネル" },
  CHAT_WINDOWS_COUNT = { "%d Chat Windows", "チャットウィンドウ %d個" }, GENERAL = { "General", "一般" },
  -- the edit box header (Lua's "Say:\32" is "Say: " in _G)
  CHAT_SAY_SEND = { "Say: ", "発言： " }, CHAT_WHISPER_SEND = { "Tell %s: ", "%sへ囁く： " },
  -- the newcomer chat hint under the edit box (chatframeeditboxoverrides.lua:33–45)
  NPEV2_CHAT_HELP_HINT_HERE = { "Type here to ask questions in Newcomer Chat", "ここに入力して初心者チャットで質問" },
  NPEV2_CHAT_HELP_HINT_DIFFERENT = { "Type %s to ask questions in Newcomer Chat", "%sと入力して初心者チャットで質問" } }

-- An edit box replayed from ChatFrameEditBoxMixin:UpdateHeader (chatframeeditbox.lua:613–711): the header's width is
-- its text's (6 per byte here), the typed text inset by it.
local function editBox(name)
  local header = Stub.fontString("")
  function header.GetLeft() return 0 end
  function header:GetRight() return (self.width and self.width > 0) and self.width or #(self.text or "") * 6 end
  function header:GetWidth() return self:GetRight() end
  function header:SetFormattedText(fmt, ...) self:SetText(string.format(fmt, ...)) end
  local suffix = Stub.fontString(": ")
  suffix.shown = false -- the client shows it only for a capped header
  function suffix:SetShown(v) self.shown = v end
  function suffix.GetWidth() return 12 end
  local box = { chatType = "SAY", target = nil, NewcomerHint = Stub.fontString("") }
  function box.GetName() return name end
  function box.GetLeft() return 0 end
  function box.GetRight() return 400 end
  function box:SetTextInsets(l) self.inset = l end
  function box:GetTextInsets() return self.inset or 0, 13, 0, 0 end
  function header:GetStringWidth() return #(self.text or "") * 6 end
  function suffix:IsShown() return self.shown == true end
  function box:UpdateHeader()
    header:SetWidth(0)
    if self.chatType == "WHISPER" then header:SetFormattedText(_G.CHAT_WHISPER_SEND, self.target)
    else header:SetText(_G["CHAT_" .. self.chatType .. "_SEND"]) end
    self:SetTextInsets(15 + header:GetWidth() + (self.extra or 0), 13, 0, 0)
  end
  -- ChatFrameEditBoxMixin:UpdateNewcomerEditBoxHint: "here" in the newcomer channel, else its slash command
  function box:UpdateNewcomerEditBoxHint()
    if self.sameChannel then self.NewcomerHint:SetText(_G.NPEV2_CHAT_HELP_HINT_HERE)
    else self.NewcomerHint:SetText(string.format(_G.NPEV2_CHAT_HELP_HINT_DIFFERENT, "/1")) end
  end
  _G[name], _G[name .. "Header"], _G[name .. "HeaderSuffix"] = box, header, suffix
  return box, header
end

local function en(key) return _G[key] end

local function hover(tab) -- the tab's OnEnter
  local tt = _G.GameTooltip
  tt:SetOwner(tab)
  tt:SetText(string.format(en("CHAT_TAB_NAME"), tab:GetText()))
  tt:AddLine(en("CHAT_TAB_RIGHT_CLICK"))
  tt:Show()
end

describe("the chat frame's hovers on Forever", function()
  local WFJ

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    -- the Core/UIStrings grants this surface needs
    WFJ.UIStrings.ARGS.CHAT_TAB_NAME = { [1] = "text" }
    WFJ.UIStrings.LABELS.CHAT_CHANNELS = "binding"
    H.uiSetup(WFJ, UI)
  end

  local function tabs()
    Stub.button("ChatFrame1Tab", "General")
    Stub.button("ChatFrame2Tab", "Combat Log")
    CreateFrame("Button", "ChatFrameChannelButton")
    _G.FCF_OpenTemporaryWindow = function() Stub.button("ChatFrame3Tab", "Thrall") end
    _G.FCFDockOverflowList_Update = function(list) list.numTabs.text = string.format(en("CHAT_WINDOWS_COUNT"), 12) end
  end

  after_each(function()
    H.uiTeardown()
    for _, n in ipairs({ "ChatFrame1Tab", "ChatFrame2Tab", "ChatFrame3Tab", "ChatFrameChannelButton",
      "FCF_OpenTemporaryWindow", "FCFDockOverflowList_Update" }) do _G[n] = nil end
  end)

  it("a tab's hover is Japanese around the window's name; the tab's own text is never touched", function()
    load()
    tabs()
    assert.is_true(WFJ.ChatTabs.init())
    hover(_G.ChatFrame1Tab)
    assert.are.equal("Generalタブ", _G.GameTooltipTextLeft1:GetText()) -- "General" is a dictionary word: kept
    assert.are.equal("<右クリックでタブ設定>", _G.GameTooltipTextLeft2:GetText())
    assert.are.equal("General", _G.ChatFrame1Tab:GetText())
    assert.are.equal(0, WFJ.Labels.show("chattabs", "x", _G.ChatFrame1Tab))
    _G.FCF_OpenTemporaryWindow() -- a whisper window's tab is registered when it appears
    hover(_G.ChatFrame3Tab)
    assert.are.equal("Thrallタブ", _G.GameTooltipTextLeft1:GetText())
    assert.is_false(WFJ.ChatTabs.init())
    assert.are.equal(1, #Stub.hooks["FCF_OpenTemporaryWindow"])
  end)

  it("the chat channels button's hover keeps its key binding", function()
    load()
    tabs()
    assert.is_true(WFJ.ChatTabs.init())
    local tt = _G.GameTooltip
    tt:SetOwner(_G.ChatFrameChannelButton)
    tt:SetText("Chat Channels |cffffd200(O)|r")
    assert.are.equal("チャットチャンネル |cffffd200(O)|r", _G.GameTooltipTextLeft1:GetText())
    tt:SetOwner(_G.ChatFrameChannelButton)
    tt:SetText("General") -- a line that is not this button's word
    assert.are.equal("General", _G.GameTooltipTextLeft1:GetText())
  end)

  it("the docked-tabs overflow list's count is Japanese", function()
    load()
    tabs()
    assert.is_true(WFJ.ChatTabs.init())
    local list = { numTabs = Stub.fontString("") }
    _G.FCFDockOverflowList_Update(list)
    assert.are.equal("チャットウィンドウ 12個", list.numTabs:GetText())
    assert.has_no.errors(function() WFJ.ChatTabs.onOverflow(nil); WFJ.ChatTabs.onOverflow({ numTabs = 3 }) end)
  end)

  it("client names bound to the wrong type degrade with no error", function()
    load()
    tabs()
    _G.ChatFrame2Tab, _G.ChatFrameChannelButton, _G.FCF_OpenTemporaryWindow = 7, "button", {}
    assert.has_no.errors(function() assert.is_true(WFJ.ChatTabs.init()) end)
    assert.are.equal(1, WFJ.ChatTabs.registerTabs())
  end)

  it("no chat tabs → init is false", function()
    load()
    assert.has_no.errors(function() assert.is_false(WFJ.ChatTabs.init()) end)
  end)

  it("the edit box header is Japanese after UpdateHeader, the whisper target kept; the typed text is"
    .. " inset by the Japanese; Alt shows the English", function()
    load()
    tabs()
    local box, header = editBox("ChatFrame1EditBox")
    assert.is_true(WFJ.ChatTabs.init())
    box:UpdateHeader()
    assert.are.equal("発言： ", header:GetText())
    assert.are.equal(15 + #"発言： " * 6, box.inset)
    box.chatType, box.target = "WHISPER", "Thrall"
    box:UpdateHeader()
    assert.are.equal("Thrallへ囁く： ", header:GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Tell Thrall: ", header:GetText())
    assert.are.equal(15 + #"Tell Thrall: " * 6, box.inset)
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    box.chatType = "CHANNEL" -- a channel header is a channel's name: never ours
    _G.CHAT_CHANNEL_SEND = "[1. General]: "
    box:UpdateHeader()
    assert.are.equal("[1. General]: ", header:GetText())
    assert.are.equal(15 + #"[1. General]: " * 6, box.inset)
    Stub.keys.alt = true; WFJ.Modifier.refresh(); Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal(15 + #"[1. General]: " * 6, box.inset) -- a refit never moves the client's inset for English
    -- whatever else the client adds to the inset is kept: the Japanese moves it by the width difference only
    box.chatType, box.extra = "SAY", 30
    box:UpdateHeader()
    assert.are.equal(15 + #"発言： " * 6 + 30, box.inset)
    assert.are.equal(0, WFJ.ChatTabs.registerEditBoxes()) -- hooked once
    for _, n in ipairs({ "ChatFrame1EditBox", "ChatFrame1EditBoxHeader", "ChatFrame1EditBoxHeaderSuffix",
      "CHAT_CHANNEL_SEND" }) do _G[n] = nil end
  end)
end)

-- UI/ChatTabs: the newcomer chat hint (ChatFrameEditBoxMixin:UpdateNewcomerEditBoxHint) in Japanese, the slash
-- command kept.
describe("the newcomer chat hint on Forever", function()
  local WFJ

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    Stub.button("ChatFrame1Tab", "General")
    CreateFrame("Button", "ChatFrameChannelButton")
    editBox("ChatFrame1EditBox")
    assert.is_true(WFJ.ChatTabs.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, n in ipairs({ "ChatFrame1Tab", "ChatFrameChannelButton", "ChatFrame1EditBox", "ChatFrame1EditBoxHeader",
      "ChatFrame1EditBoxHeaderSuffix" }) do _G[n] = nil end
  end)

  it("the hint is Japanese after the client writes it; the slash command stays; Alt shows English", function()
    local box = _G.ChatFrame1EditBox
    box.sameChannel = true
    box:UpdateNewcomerEditBoxHint()
    assert.are.equal("ここに入力して初心者チャットで質問", box.NewcomerHint:GetText())
    box.sameChannel = false
    box:UpdateNewcomerEditBoxHint()
    assert.are.equal("/1と入力して初心者チャットで質問", box.NewcomerHint:GetText())
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal("Type /1 to ask questions in Newcomer Chat", box.NewcomerHint:GetText())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    assert.are.equal("/1と入力して初心者チャットで質問", box.NewcomerHint:GetText())
  end)
end)
