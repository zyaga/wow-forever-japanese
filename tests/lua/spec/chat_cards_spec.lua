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
    Cards.init()
  end)
  after_each(Env.teardown)

  it("shows a Japanese word's card and tints the word, in Japanese first", function()
    local first = Env.pointAt(line, "今日", 1)
    local w = Cards.look()
    assert.equals("今日", w.word)
    assert.equals("today", Env.card.card.meaning)
    assert.equals(first, Cards.shown().first)
    assert.is_true(Env.card.anchor.tints[1].shown)
  end)

  it("gives the whole of a verb and its endings one card", function()
    Env.pointAt(line, "行きませんか", #"行きませ")
    assert.equals("行きませんか", Cards.look().word)
    assert.equals("行く", Env.card.card.lemma)
  end)

  it("shows no card for a Japanese word in English first, and an English word's card there", function()
    WFJ.State.direction = "en"
    Env.pointAt(line, "今日")
    assert.is_nil(Cards.look())
    assert.is_nil(Env.card)
    Env.pointAt(line, "need")
    assert.equals("need", Cards.look().word)
    assert.equals("必要", Env.card.card.ja)
  end)

  it("shows no card for an English word in Japanese first, or on the sender's name", function()
    Env.pointAt(line, "need")
    assert.is_nil(Cards.look())
    Env.pointAt(line, "Taro")
    assert.is_nil(Cards.look())
  end)

  it("shows no card while the reveal key is held, or with translation, word cards or the setting off", function()
    Env.pointAt(line, "今日")
    WFJ.State.modifierHeld = true
    assert.is_nil(Cards.look())
    WFJ.State.modifierHeld = false
    WFJ.State.enabled = false
    assert.is_nil(Cards.look())
    WFJ.State.enabled = true
    WFJ.ReadingView.enabled = false
    assert.is_nil(Cards.look())
    WFJ.ReadingView.enabled = true
    WFJ.Settings.set("chat.cards", false)
    assert.is_nil(Cards.look())
    WFJ.Settings.set("chat.cards", true)
    assert.is_table(Cards.look())
  end)

  it("never reads a line whose text the client keeps secret", function()
    Env.pointAt(line, "今日")
    Env.secrets[SAID] = true
    assert.is_nil(Cards.look())
    assert.is_nil(Env.card)
  end)

  it("shows no card on a line that has faded out, or with the mouse off the chat frame", function()
    Env.pointAt(line, "今日")
    line.alpha = 0.1
    assert.is_nil(Cards.look())
    line.alpha = 1
    frame.over = false
    assert.is_nil(Cards.look())
  end)

  it("clears the card when the mouse leaves the word", function()
    Env.pointAt(line, "今日")
    assert.is_table(Cards.look())
    line.index = nil
    assert.is_nil(Cards.look())
    assert.is_nil(Env.card)
    assert.is_nil(Cards.shown())
  end)

  it("saves a clicked word with what the player typed as its sentence", function()
    Env.pointAt(line, "今日")
    Cards.look()
    Env.down = true
    Cards.look()
    Env.down = false
    Cards.look()
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
    Cards.look()
    Env.down = true
    Cards.look()
    Env.down = false
    Cards.look()
    assert.equals(0, #WFJ.Words.entries())
  end)
end)
