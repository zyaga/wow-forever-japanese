-- UI/ChatCards: the word card on the chat line under the mouse, when it shows and when it must not, and the save
-- click.
local Env = require("tests.lua.spec.chat_env")

local SAID = "|Hplayer:Taro:12:SAY|h[Taro]|h says: 今日はダンジョンに行きませんか need help"

describe("word cards on chat", function()
  local WFJ, Cards, frame, line

  before_each(function()
    WFJ = Env.setup()
    Cards = WFJ.ChatCards
    frame = Env.chatFrame({ { SAID, Env.SAY } })
    line = frame.visibleLines[1]
    WFJ.ChatLines.init()
    Cards.init()
  end)

  -- one look at the mouse → the word now showing, as the card was given it
  local function look()
    WFJ.ChatLines.look()
    return Cards.shown() and Env.card and Env.card.word or nil
  end
  after_each(Env.teardown)

  it("shows a Japanese word's card and tints the word, in Japanese first", function()
    local first = Env.pointAt(line, "今日", 1)
    local w = look()
    assert.equals("今日", w.word)
    assert.equals("today", Env.card.card.meaning)
    assert.equals(first, Cards.shown().first)
    assert.is_true(Env.card.anchor.tints[1].shown)
    assert.equals(line, Env.card.anchor.allPoints) -- the cover lies on the chat line, which is left as it is
    assert.equals(SAID, line:GetText())
  end)

  it("gives the whole of a verb and its endings one card", function()
    Env.pointAt(line, "行きませんか", #"行きませ")
    assert.equals("行きませんか", look().word)
    assert.equals("行く", Env.card.card.lemma)
  end)

  it("shows no card for a Japanese word in English first, and an English word's card there", function()
    WFJ.State.direction = "en"
    Env.pointAt(line, "今日")
    assert.is_nil(look())
    assert.is_nil(Env.card)
    Env.pointAt(line, "need")
    assert.equals("need", look().word)
    assert.equals("必要", Env.card.card.ja)
  end)

  it("shows no card for an English word in Japanese first, or on the sender's name", function()
    Env.pointAt(line, "need")
    assert.is_nil(look())
    Env.pointAt(line, "Taro")
    assert.is_nil(look())
  end)

  it("shows no card while the reveal key is held, or with translation, word cards or the setting off", function()
    Env.pointAt(line, "今日")
    WFJ.State.modifierHeld = true
    assert.is_nil(look())
    WFJ.State.modifierHeld = false
    WFJ.State.enabled = false
    assert.is_nil(look())
    WFJ.State.enabled = true
    WFJ.ReadingView.enabled = false
    assert.is_nil(look())
    WFJ.ReadingView.enabled = true
    WFJ.Settings.set("chat.cards", false)
    assert.is_nil(look())
    WFJ.Settings.set("chat.cards", true)
    assert.is_table(look())
  end)

  it("never reads a line whose text the client keeps secret", function()
    Env.pointAt(line, "今日")
    Env.secrets[SAID] = true
    assert.is_nil(look())
    assert.is_nil(Env.card)
  end)

  it("shows no card on a line that has faded out, or with the mouse off the chat frame", function()
    Env.pointAt(line, "今日")
    line.alpha = 0.1
    assert.is_nil(look())
    line.alpha = 1
    frame.over = false
    assert.is_nil(look())
  end)

  it("shows the reading alone with meanings off, as on every word-card surface", function()
    Env.pointAt(line, "今日")
    WFJ.State.fire("glosses", false)
    WFJ.ChatLines.look()
    assert.is_table(Cards.shown())
    assert.is_nil(Env.card) -- no card: the reading box shows
    WFJ.State.fire("glosses", true)
    assert.equals("今日", look().word)
  end)

  it("finds the word once, not on every look, while the mouse rests on it", function()
    Env.pointAt(line, "今日")
    look()
    local real, calls = WFJ.ChatWords.japaneseAt, 0
    WFJ.ChatWords.japaneseAt = function(...) calls = calls + 1; return real(...) end
    look(); look()
    line.index = line.index + 1 -- another byte of the same word
    look()
    WFJ.ChatWords.japaneseAt = real
    assert.equals(0, calls)
  end)

  it("takes down the card when the player's own words change, and shows the new one on the next look", function()
    Env.pointAt(line, "今日")
    look()
    WFJ.ChatWords.add("ja", "今日", "きょう", "mine")
    assert.is_nil(Cards.shown())
    assert.equals("mine", look() and Env.card.card.meaning)
  end)

  it("clears the card when the mouse leaves the word", function()
    Env.pointAt(line, "今日")
    assert.is_table(look())
    line.index = nil
    assert.is_nil(look())
    assert.is_nil(Env.card)
    assert.is_nil(Cards.shown())
  end)

  it("saves a clicked word with what the player typed as its sentence", function()
    Env.pointAt(line, "今日")
    look()
    Env.down = true
    look()
    Env.down = false
    look()
    local entries = WFJ.Words.entries()
    assert.equals(1, #entries)
    assert.equals("今日", entries[1].word)
    assert.equals("今日はダンジョンに行きませんか need help", entries[1].sentence)
    assert.equals("today", entries[1].meaning)
    assert.equals("chat", entries[1].source)
  end)

  it("does not save without the save click's key", function()
    Env.ctrl = false
    Env.pointAt(line, "今日")
    look()
    Env.down = true
    look()
    Env.down = false
    look()
    assert.equals(0, #WFJ.Words.entries())
  end)
end)
