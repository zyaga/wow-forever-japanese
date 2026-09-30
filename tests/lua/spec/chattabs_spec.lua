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
  CHAT_SAY_SEND = { "Say: ", "発言： " }, CHAT_WHISPER_SEND = { "Tell %s: ", "%sへ囁く： " } }

-- An edit box replayed from ChatFrameEditBoxMixin:UpdateHeader (chatframeeditbox.lua:613–711): the header's width is
-- its text's (6 per byte here), the typed text inset by it.
local function editBox(name)
  local header = Stub.fontString("")
  function header.GetLeft() return 0 end
  function header:GetRight() return (self.width and self.width > 0) and self.width or #(self.text or "") * 6 end
  function header:GetWidth() return self:GetRight() end
  function header:SetFormattedText(fmt, ...) self:SetText(string.format(fmt, ...)) end
  local suffix = Stub.fontString(": ")
  function suffix:SetShown(v) self.shown = v end
  function suffix.GetWidth() return 12 end
  local box = { chatType = "SAY", target = nil }
  function box.GetName() return name end
  function box.GetLeft() return 0 end
  function box.GetRight() return 400 end
  function box:SetTextInsets(l) self.inset = l end
  function box:UpdateHeader()
    header:SetWidth(0)
    if self.chatType == "WHISPER" then header:SetFormattedText(_G.CHAT_WHISPER_SEND, self.target)
    else header:SetText(_G["CHAT_" .. self.chatType .. "_SEND"]) end
    self:SetTextInsets(15 + header:GetWidth(), 13, 0, 0)
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
    assert.are.equal(0, WFJ.ChatTabs.registerEditBoxes()) -- hooked once
    for _, n in ipairs({ "ChatFrame1EditBox", "ChatFrame1EditBoxHeader", "ChatFrame1EditBoxHeaderSuffix",
      "CHAT_CHANNEL_SEND" }) do _G[n] = nil end
  end)
end)
