-- UI/ChatPhraseLines: an arriving phrase shown in the reader's language, and what the reveal key shows.
local Env = require("tests.lua.spec.chat_env")

describe("a phrase book phrase in chat", function()
  local WFJ, Lines, P, frame, raw

  local function arrive(msg)
    local filter = Env.filters["CHAT_MSG_SAY"]
    return filter(frame, "CHAT_MSG_SAY", msg, "Taro", "rest")
  end

  before_each(function()
    WFJ = Env.setup()
    Lines, P = WFJ.ChatPhraseLines, WFJ.ChatPhrases
    frame = Env.chatFrame({})
    Lines.init()
    raw = Env.DOT .. " Hello!"
  end)
  after_each(Env.teardown)

  it("is listening on every chat event a player types into, a BattleNet whisper among them", function()
    assert.equals(WFJ.ChatLines.TYPED, Lines.EVENTS)
    for _, e in ipairs(Lines.EVENTS) do assert.equals(Lines.filter, Env.filters["CHAT_MSG_" .. e]) end
    assert.equals(Lines.filter, Env.filters["CHAT_MSG_BN_WHISPER"])
  end)

  it("puts back what the chat code writes on a line after the reveal key is released", function()
    local shows = 0
    WFJ.ChatSystem = { show = function() shows = shows + 1 end }
    local shown = select(2, arrive(raw))
    frame.visibleLines[1] = Env.line("[Taro]: " .. shown, Env.SAY)
    Lines.reveal(frame) -- the key is not held and nothing was shown: nothing to do
    assert.equals(0, shows)
    WFJ.State.modifierHeld = true
    Lines.reveal(frame)
    WFJ.State.modifierHeld = false
    Lines.reveal(frame)
    assert.equals(1, shows)
  end)

  it("shows a marked phrase in the reader's language and passes the rest of the event on", function()
    local drop, msg, sender, rest = arrive(raw)
    assert.is_false(drop)
    assert.equals(P.MARK .. "こんにちは！", msg)
    assert.equals("Taro", sender)
    assert.equals("rest", rest)
    WFJ.State.direction = "en"
    assert.equals(P.MARK .. "Hello!", select(2, arrive(raw)))
  end)

  it("leaves any other message, a secret message, and every message with the setting off", function()
    assert.same({ false }, { arrive("Hello!") })
    assert.same({ false }, { arrive(Env.DOT .. " anything else") })
    Env.secrets[raw] = true
    assert.same({ false }, { arrive(raw) })
    Env.secrets[raw] = nil
    WFJ.Settings.set("chat.phrases", false)
    assert.same({ false }, { arrive(raw) })
    WFJ.Settings.set("chat.phrases", true)
    WFJ.State.enabled = false
    assert.same({ false }, { arrive(raw) })
  end)

  it("shows the message as it was sent while the reveal key is held, and the changed line again on release", function()
    local shown = select(2, arrive(raw))
    local text = "|Hplayer:Taro|h[Taro]|h says: " .. shown
    local line = Env.line(text, Env.SAY)
    frame.visibleLines[1] = line
    WFJ.State.modifierHeld = true
    Lines.reveal(frame)
    assert.equals("|Hplayer:Taro|h[Taro]|h says: " .. raw, line:GetText())
    WFJ.State.modifierHeld = false
    Lines.reveal(frame)
    assert.equals(text, line:GetText())
  end)

  it("shows the Japanese phrase while the reveal key is held in English first", function()
    WFJ.State.direction = "en"
    local shown = select(2, arrive(raw))
    local line = Env.line("[Taro]: " .. shown, Env.SAY)
    frame.visibleLines[1] = line
    WFJ.State.modifierHeld = true
    Lines.reveal(frame)
    assert.equals("[Taro]: " .. P.MARK .. "こんにちは！", line:GetText())
  end)

  it("knows a secret value without the mouse tracker having started", function()
    -- this spec never starts UI/ChatLines: its answer comes from the names it declared when its file loaded
    Env.secrets[raw] = true
    assert.is_true(WFJ.ChatLines.secret(raw))
  end)

  it("keeps a visible line in step with the translation switch, both ways", function()
    WFJ.State.setEnabled(false)
    assert.is_false(arrive(raw)) -- left as sent
    local sent = "|Hplayer:Taro|h[Taro]|h says: " .. raw
    local line = Env.line(sent, Env.SAY)
    frame.visibleLines[1] = line
    Lines.reveal(frame)
    assert.equals(sent, line:GetText())
    WFJ.State.setEnabled(true) -- the switch runs the pass itself
    local shown = line:GetText()
    assert.is_truthy(shown:find(P.MARK, 1, true))
    assert.is_nil(shown:find(raw, 1, true))
    WFJ.State.modifierHeld = true
    Lines.reveal(frame)
    assert.equals(sent, line:GetText())
    WFJ.State.modifierHeld = false
    Lines.reveal(frame)
    assert.equals(shown, line:GetText())
    WFJ.State.setEnabled(false)
    assert.equals(sent, line:GetText())
  end)

  it("in English first, shows the English phrase after the reveal key, and the Japanese through a redraw", function()
    WFJ.State.direction = "en"
    WFJ.State.setEnabled(false)
    local sent = "|Hplayer:Taro|h[Taro]|h says: " .. raw
    local line = Env.line(sent, Env.SAY)
    frame.visibleLines[1] = line
    WFJ.State.setEnabled(true)
    local shown = line:GetText()
    assert.is_truthy(shown:find(P.MARK .. "Hello!", 1, true))
    WFJ.State.modifierHeld = true
    Lines.reveal(frame)
    assert.is_truthy(line:GetText():find("こんにちは", 1, true))
    line:SetText(sent) -- a redraw puts the history's text back on the line while the key is still held
    Lines.reveal(frame)
    assert.is_truthy(line:GetText():find("こんにちは", 1, true))
    WFJ.State.modifierHeld = false
    Lines.reveal(frame)
    assert.equals(shown, line:GetText())
  end)

  it("changes only what a player typed: no system line, no emptied line, no words before the message", function()
    local system = Env.line("Taro waves. " .. raw, Env.SYSTEM)
    local emptied = Env.line("[Taro]: " .. raw, Env.SAY)
    emptied.messageInfo = nil
    local dotted = Env.line("|Hplayer:Hello!|h[" .. Env.DOT .. " Hello!]|h says: " .. raw, Env.SAY)
    frame.visibleLines[1], frame.visibleLines[2], frame.visibleLines[3] = system, emptied, dotted
    Lines.reveal(frame)
    assert.equals("Taro waves. " .. raw, system:GetText())
    assert.equals("[Taro]: " .. raw, emptied:GetText())
    local text = dotted:GetText()
    assert.is_truthy(text:find("[" .. Env.DOT .. " Hello!]", 1, true)) -- the sender's label is as it was
    assert.is_truthy(text:find("says: " .. P.MARK, 1, true))
  end)

  it("changes no line that holds no changed phrase, and never reads a secret line", function()
    local shown = select(2, arrive(raw))
    local plain = Env.line("[Taro]: hello there", Env.SAY)
    local hidden = Env.line("[Taro]: " .. shown, Env.SAY)
    Env.secrets[hidden:GetText()] = true
    frame.visibleLines[1], frame.visibleLines[2] = plain, hidden
    WFJ.State.modifierHeld = true
    Lines.reveal(frame)
    assert.equals("[Taro]: hello there", plain:GetText())
    assert.equals("[Taro]: " .. shown, hidden:GetText())
  end)

  it("picks up a chat window made later", function()
    local later = { visibleLines = {}, callbacks = {} }
    function later:AddOnDisplayRefreshedCallback(fn) self.callbacks[#self.callbacks + 1] = fn end
    _G.ChatFrame11 = later
    _G.CHAT_FRAMES[#_G.CHAT_FRAMES + 1] = "ChatFrame11"
    assert.equals(1, Lines.hookAll())
    assert.equals(Lines.reveal, later.callbacks[1])
    assert.equals(0, Lines.hookAll())
    _G.ChatFrame11 = nil
  end)

  it("runs its pass after each redraw of a chat frame, and on the reveal key", function()
    assert.equals(Lines.reveal, frame.callbacks[1])
    local shown = select(2, arrive(raw))
    local line = Env.line("[Taro]: " .. shown, Env.SAY)
    frame.visibleLines[1] = line
    WFJ.State.modifierHeld = true
    WFJ.State.fire("language", true)
    assert.equals("[Taro]: " .. raw, line:GetText())
  end)
end)
