-- The world the chat tools' specs share: the addon's own files for chat, a chat frame with visible lines that say
-- which character the mouse is on, the client names the tools read, and the word card recorded instead of drawn.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local F = require("tests.lua.spec.stub_fixwindow")

local Env = {}

Env.FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Data.lua", "Core/Readings.lua", "Core/Glosses.lua",
  "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua", "Core/Words.lua", "Core/ChatWords.lua",
  "Core/ChatPhrases.lua", "UI/Font.lua", "UI/OptionsText.lua", "UI/OptionsWidgets.lua", "UI/WordSave.lua",
  "UI/ChatCards.lua", "UI/ChatCopy.lua", "UI/ChatPhraseLines.lua", "UI/PhraseBook.lua", "UI/ChatWordsWindow.lua" }

Env.SAY, Env.GUILD, Env.SYSTEM = 1, 3, 9 -- chat type ids, as ChatTypeInfo holds them here
Env.DOT = "\194\183"

local function boundary(text, i)
  if i == #text + 1 then return true end
  local c = text:byte(i)
  return c ~= nil and (c < 0x80 or c >= 0xC0)
end

-- A visible chat line. `index`: the byte the mouse is on (nil: on no character); `over`: the mouse is on the line.
function Env.line(text, typeId)
  local line = Stub.fontString(text, "F.ttf", 14, "")
  line.messageInfo = { message = text, extraData = { typeId, n = 1 } }
  line.over, line.alpha, line.index = false, 1, nil
  function line.IsVisible() return true end
  function line:GetAlpha() return self.alpha end
  function line:IsMouseOver() return self.over end
  function line:FindCharacterIndexAtCoordinate() return self.index, self.index ~= nil end
  -- the client exits on a span that splits a character: here that is an error a spec would see
  function line:CalculateScreenAreaFromCharacterSpan(a, b)
    if not boundary(self.text, a) or not boundary(self.text, b) or b <= a then error("CRASH: split character") end
    return { { left = a, bottom = 0, width = b - a, height = 14 } }
  end
  return line
end

-- Puts the mouse on `word` of `line` (its first byte, or `offset` bytes into it).
function Env.pointAt(line, word, offset)
  local first = assert(line:GetText():find(word, 1, true), "no " .. word .. " in the line")
  line.over, line.index = true, first + (offset or 0)
  return first
end

function Env.chatFrame(lines)
  local f = { visibleLines = {}, shown = true, over = true, callbacks = {} }
  function f:IsVisible() return self.shown end
  function f:IsMouseOver() return self.over end
  function f.GetEffectiveScale() return 1 end
  function f.GetLeft() return 40 end
  function f.GetBottom() return 120 end
  function f:AddOnDisplayRefreshedCallback(fn) self.callbacks[#self.callbacks + 1] = fn end
  for i, l in ipairs(lines) do f.visibleLines[i] = Env.line(l[1], l[2]) end
  _G.ChatFrame1 = f
  _G.CHAT_FRAMES = { "ChatFrame1" }
  return f
end

-- → WFJ, with the chat data of the specs loaded and the tools started
function Env.setup()
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  F.install()
  local create = _G.CreateFrame
  _G.CreateFrame = function(...)
    local f = create(...)
    function f:SetShown(v) if v then self:Show() else self:Hide() end end
    function f:SetEnabled(v) self.enabled = v and true or false end
    function f.GetPoint() return "BOTTOMLEFT", nil, "BOTTOMLEFT", 300, 400 end
    function f:Insert(t) self.text = (self.text or "") .. t end
    function f:HighlightText() self.highlighted = true end
    f.SetNormalAtlas, f.SetPushedAtlas, f.SetHighlightAtlas, f.SetHighlightTexture = Env.noop, Env.noop, Env.noop,
      Env.noop
    f.SetBackdrop, f.SetBackdropColor, f.SetBackdropBorderColor, f.SetAutoFocus = Env.noop, Env.noop, Env.noop,
      Env.noop
    local cfs = f.CreateFontString
    function f:CreateFontString(...)
      local fs = cfs(self, ...)
      fs.SetJustifyH, fs.SetJustifyV, fs.SetWordWrap, fs.SetTextColor = Env.noop, Env.noop, Env.noop, Env.noop
      function fs.GetStringHeight() return 14 end
      return fs
    end
    local tex = f.CreateTexture
    function f:CreateTexture(...)
      local t = tex(self, ...)
      t.SetColorTexture, t.ClearAllPoints, t.SetSize = Env.noop, Env.noop, Env.noop
      function t.Show(x) x.shown = true end
      function t.Hide(x) x.shown = false end
      return t
    end
    return f
  end
  for _, name in ipairs({ "WFJChatCopyWindow", "WFJPhraseCard", "WFJPhraseButton", "WFJChatWordsWindow" }) do
    _G[name] = nil -- the stub keeps named frames from an earlier test
  end
  Env.secrets, Env.down, Env.ctrl, Env.card, Env.filters, Env.opened = {}, false, true, nil, {}, nil
  _G.issecretvalue = function(v) return Env.secrets[v] == true end
  _G.IsMouseButtonDown = function() return Env.down end
  _G.IsControlKeyDown = function() return Env.ctrl end
  _G.IsShiftKeyDown, _G.IsMetaKeyDown = function() return false end, function() return false end
  _G.ChatTypeInfo = { SAY = { id = Env.SAY }, GUILD = { id = Env.GUILD }, SYSTEM = { id = Env.SYSTEM } }
  _G.ChatFrameUtil = {
    AddMessageEventFilter = function(event, fn) Env.filters[event] = fn end,
    GetActiveWindow = function() return Env.activeBox end,
    OpenChat = function(text) Env.opened = text end,
  }
  Env.activeBox = nil
  local WFJ = H.loadChunks(Env.FILES)
  WFJ.Compat.init(function(name) return _G[name] end)
  WFJ.Data.add("gloss", { [1] = "今日\tきょう\ttoday", [3] = "行く\tいく\tto go", [4] = "必要\tひつよう\tneed" })
  WFJ.Data.add("chatja", { ["今日"] = "きょう=1", ["行き"] = "いき=3" })
  WFJ.Data.add("chaten", { need = "必要=ひつよう=4" })
  WFJ.Data.add("chatword", { ["よろ"] = "よろ\tshort for よろしく" })
  WFJ.Data.add("chatwordEn", { lfm = "メンバー募集中" })
  WFJ.Data.add("pron", { need = "niːd" })
  WFJ.Data.add("phrase", {
    [1] = "greetings\tHello!\tこんにちは！",
    [2] = "greetings\tSee you later!\tまたね！",
    [3] = "combat\tI'm out of mana.\tマナがありません。",
  })
  Env.db = WFJ.Settings.load(nil, 1, {})
  WFJ.Words.load(nil)
  WFJ.ChatWords.load(nil)
  WFJ.ReadingView = { enabled = true, hint = Env.noop, solid = Env.noop, flash = Env.noop,
    -- as UI/Readings' guarded call answers for a chat line (its own checks are in readings_spec)
    spanAreas = function(fs, _, first, last, where, escapes)
      Env.span = { where = where, escapes = escapes }
      return fs:CalculateScreenAreaFromCharacterSpan(first, last + 1)
    end }
  WFJ.ReadingPopup = {
    show = function(anchor, _, _, word, card) Env.card = { anchor = anchor, word = word, card = card } end,
    hide = function() Env.card = nil end,
  }
  Env.WFJ = WFJ
  return WFJ
end

function Env.noop() end

function Env.teardown()
  F.clear()
  for _, name in ipairs({ "ChatFrame1", "CHAT_FRAMES", "issecretvalue", "IsMouseButtonDown", "IsControlKeyDown",
      "IsShiftKeyDown", "IsMetaKeyDown", "ChatTypeInfo", "ChatFrameUtil" }) do
    _G[name] = nil
  end
end

return Env
