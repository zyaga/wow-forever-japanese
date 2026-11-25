-- UI/ChatMarks: the word status marks on visible chat lines, and the lines that take none.
local Env = require("tests.lua.spec.chat_env")

local SAID = "|Hplayer:Taro:12:SAY|h[Taro]|h says: 今日はダンジョンに行きませんか need help"

describe("word status marks on chat", function()
  local WFJ, ChatMarks, S, Status, frame, line

  before_each(function()
    WFJ = Env.setup()
    WFJ.Placeholders = { CLASS = {}, RACE = {} }
    WFJ.Data.add("freqJa", { ["今日\tきょう"] = "5,0,0,0,0,0", ["行く\tいく"] = "3,0,0,0,0,0" })
    WFJ.Data.add("freqEn", { need = "4,0,0,0,0,0" })
    ChatMarks, S, Status = WFJ.ChatMarks, WFJ.Settings, WFJ.WordStatus
    Status.load(nil)
    frame = Env.chatFrame({ { SAID, Env.SAY } })
    line = frame.visibleLines[1]
    ChatMarks.init()
    S.set("marks.chat", true)
  end)
  after_each(Env.teardown)

  local Stub = require("tests.lua.spec.wow_stub")
  local function overlay()
    for _, f in ipairs(Stub.frames) do
      if f.allPoints == line and f.markTex then return f end
    end
    return nil
  end
  local function marks()
    local o, n = overlay(), 0
    if not o or o.shown == false then return 0 end
    for _, t in ipairs(o.markTex) do if t.shown ~= false then n = n + 1 end end
    return n
  end

  it("finds every word of a line, and none inside a link's label", function()
    local words = {}
    for _, w in ipairs(ChatMarks.words(SAID, false)) do words[#words + 1] = w.word end
    assert.same({ "今日", "行きませんか" }, words)
    words = {}
    for _, w in ipairs(ChatMarks.words(SAID, true)) do words[#words + 1] = w.word end
    assert.same({ "need" }, words)
  end)

  it("underlines and highlights the unknown words of a visible line", function()
    assert.equals(1, ChatMarks.look())
    assert.equals(4, marks()) -- 今日 and 行く: an underline and the highlight each
    S.set("marks.highlight", "off")
    ChatMarks.look()
    assert.equals(2, marks())
    assert.equals(SAID, line:GetText()) -- the chat line is left as it is
  end)

  it("follows a status change, and draws nothing again while nothing changed", function()
    ChatMarks.look()
    assert.equals(0, ChatMarks.look())
    Status.set("ja", "今日\tきょう", "known")
    assert.equals(1, ChatMarks.look())
    assert.equals(2, marks())
  end)

  it("marks nothing with the chat place off, which is how it starts", function()
    assert.is_false(WFJ.Settings.definition("marks.chat").default)
    ChatMarks.look()
    S.set("marks.chat", false)
    assert.equals(0, marks())
    assert.equals(0, ChatMarks.look())
  end)

  it("marks no line that has faded out and no line the client keeps secret", function()
    line.alpha = 0.1
    assert.equals(0, ChatMarks.look())
    assert.equals(0, marks())
    line.alpha = 1
    Env.secrets[SAID] = true
    assert.equals(0, ChatMarks.look())
    assert.equals(0, marks())
  end)

  it("marks nothing while the reveal key is held or with word cards off", function()
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.equals(0, ChatMarks.look())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    S.set("readings.enabled", false)
    assert.equals(0, ChatMarks.look())
    S.set("readings.enabled", true)
    assert.equals(1, ChatMarks.look())
  end)

  it("marks the English words in English first", function()
    S.set("direction", "en")
    assert.equals(1, ChatMarks.look())
    assert.equals(2, marks()) -- need: an underline and the highlight
  end)

  it("draws again for the other language's words when the direction changes, and fades with its line", function()
    ChatMarks.look()
    assert.equals(4, marks())
    S.set("direction", "en")
    assert.equals(1, ChatMarks.look())
    assert.equals(2, marks())
    line.alpha = 0.5
    ChatMarks.look()
    assert.equals(0.5, overlay().alpha)
  end)

  it("takes a line's marks down when the line shows other text", function()
    ChatMarks.look()
    line:SetText("|Hplayer:Taro:12:SAY|h[Taro]|h says: ok")
    line.messageInfo.message = line:GetText()
    ChatMarks.look()
    assert.equals(0, marks())
  end)
end)
