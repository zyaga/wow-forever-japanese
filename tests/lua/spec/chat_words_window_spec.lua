-- UI/ChatWordsWindow: the player's own chat words: add, the list, remove, and the cards they take. Also the chat
-- tools' settings.
local Env = require("tests.lua.spec.chat_env")

describe("the player's own chat words", function()
  local WFJ, Window, saved

  before_each(function()
    WFJ = Env.setup()
    Window = WFJ.ChatWordsWindow
    saved = WFJ.ChatWords.load({})
    Env.chatFrame({})
  end)
  after_each(Env.teardown)

  it("keeps an added word in the saved table, lists it and gives it a card in chat", function()
    local frame = Window.open()
    frame.jaWord:SetText(" ぬるぽ ")
    frame.jaReading:SetText("ぬるぽ")
    frame.jaMeaning:SetText("a joke word")
    frame.addJa:GetScript("OnClick")(frame.addJa)
    assert.same({ reading = "ぬるぽ", meaning = "a joke word" }, saved.ja["ぬるぽ"])
    assert.equals("", frame.jaWord:GetText())
    local items = Window.items()
    assert.equals(1, #items)
    assert.equals("ぬるぽ", items[1].left)
    assert.equals("a joke word", WFJ.ChatWords.japaneseAt("ぬるぽ", 1).gloss.meaning)
  end)

  it("adds an English word with its Japanese, listed after the Japanese words", function()
    Window.open()
    assert.is_true(Window.add("ja", "ぬるぽ", "ぬるぽ", "a joke word"))
    assert.is_true(Window.add("en", "Pog", "すごい"))
    assert.equals("すごい", saved.en.pog.ja)
    local items = Window.items()
    assert.equals("pog", items[2].left)
    assert.equals("すごい", items[2].text)
    assert.equals("すごい", WFJ.ChatWords.englishAt("pog", 1).card.ja)
  end)

  it("keeps nothing for a word with no reading", function()
    Window.open()
    assert.is_false(Window.add("ja", "ぬるぽ", "", "x"))
    assert.equals(0, #Window.items())
  end)

  it("removes the picked word from the table, the list and chat", function()
    local frame = Window.open()
    Window.add("ja", "ぬるぽ", "ぬるぽ", "a joke word")
    local row = frame.list.box.frames[1]
    row:GetScript("OnClick")(row)
    assert.is_true(frame.remove.enabled)
    frame.remove:GetScript("OnClick")(frame.remove)
    assert.is_nil(saved.ja["ぬるぽ"])
    assert.equals(0, #Window.items())
    assert.is_nil(WFJ.ChatWords.japaneseAt("ぬるぽ", 1))
    assert.is_false(frame.remove.enabled)
  end)
end)

describe("the chat tools' settings", function()
  local WFJ
  before_each(function() WFJ = Env.setup() end)
  after_each(Env.teardown)

  it("are four switches, on by default, with both languages", function()
    for _, id in ipairs({ "chat.cards", "chat.copy", "chat.phraseButton", "chat.phrases" }) do
      local d = WFJ.Settings.definition(id)
      assert.equals("boolean", d.kind)
      assert.is_true(d.default)
      assert.is_true(WFJ.Settings.get(id))
      assert.is_true(type(d.label) == "string" and d.label ~= "")
      assert.is_true(type(d.ja) == "string" and d.ja ~= "")
    end
  end)

  it("have copy in both languages for every topic the phrases name", function()
    for _, topic in ipairs(WFJ.ChatPhrases.topics()) do
      local en, ja = WFJ.OptionsText.get("chat.topic." .. topic)
      assert.is_true(en ~= "" and ja ~= "")
    end
  end)
end)
