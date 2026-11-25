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

  it("is listening on every chat event a player types into", function()
    for _, e in ipairs(Lines.EVENTS) do assert.equals(Lines.filter, Env.filters["CHAT_MSG_" .. e]) end
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
