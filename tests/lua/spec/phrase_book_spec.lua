-- UI/PhraseBook: the button that becomes the card, the card's topics, typing a phrase, the shared saved spot.
local Env = require("tests.lua.spec.chat_env")
local Stub = require("tests.lua.spec.wow_stub")

describe("the phrase book", function()
  local WFJ, Book

  before_each(function()
    WFJ = Env.setup()
    Book = WFJ.PhraseBook
    Env.chatFrame({})
    Book.init(Env.db)
  end)
  after_each(Env.teardown)

  -- the card's phrase rows now showing, in the order they were made (a frame's child frames are in Stub.frames)
  local function shownRows(card)
    local out = {}
    for _, f in ipairs(Stub.frames) do
      if f.parent == card and f.phrase and f:IsShown() then out[#out + 1] = f end
    end
    return out
  end

  it("shows the button at start, and swaps it for the card on a click", function()
    local button, card = Book.frames()
    assert.is_true(button:IsShown())
    assert.is_nil(card)
    button:GetScript("OnClick")(button)
    button, card = Book.frames()
    assert.is_false(button:IsShown())
    assert.is_true(card:IsShown())
  end)

  it("lists the open topic's phrases, and another topic's after its tab is clicked", function()
    local card = Book.open()
    local rows = shownRows(card)
    assert.equals(2, #rows)
    assert.equals("こんにちは！", rows[1].ja:GetText())
    assert.equals("Hello!", rows[1].en:GetText())
    local tab = card.tabSystem:GetTabButton(2)
    assert.equals("戦闘", tab.Text:GetText())
    tab:GetScript("OnClick")(tab)
    rows = shownRows(card)
    assert.equals(1, #rows)
    assert.equals("I'm out of mana.", rows[1].en:GetText())
  end)

  it("keeps one size whatever the topic", function()
    local card = Book.open()
    local w, h = card.size[1], card.size[2]
    Book.pick("combat")
    assert.equals(w, card.size[1])
    assert.equals(h, card.size[2])
  end)

  it("with no chat box open the phrase waits, the card collapses, and the player's own open types it", function()
    local card = Book.open()
    local row = shownRows(card)[1]
    row:GetScript("OnClick")(row)
    assert.is_nil(Env.opened) -- the addon never opens the chat box itself
    assert.equals(Env.DOT .. " Hello!", Book.waiting())
    local button = Book.frames()
    assert.is_false(card:IsShown())
    assert.is_true(button:IsShown())
    -- a box opened with the slash key already holds text: the phrase goes on waiting
    local slash = CreateFrame("EditBox")
    slash.text = "/"
    _G.ChatFrameUtil.ActivateChat(slash)
    assert.equals("/", slash.text)
    assert.equals(Env.DOT .. " Hello!", Book.waiting())
    local box = CreateFrame("EditBox")
    _G.ChatFrameUtil.ActivateChat(box)
    assert.equals(Env.DOT .. " Hello!", box.text)
    assert.is_nil(Book.waiting())
    _G.ChatFrameUtil.ActivateChat(box) -- typed once
    assert.equals(Env.DOT .. " Hello!", box.text)
  end)

  it("types into the chat box that is already open", function()
    Env.activeBox = CreateFrame("EditBox")
    Env.activeBox.text = "ok "
    local card = Book.open()
    local row = shownRows(card)[1]
    row:GetScript("OnClick")(row)
    assert.equals("ok " .. Env.DOT .. " Hello!", Env.activeBox.text)
    assert.is_nil(Env.opened)
  end)

  it("goes back to the button on the minus, and hides both on the X until it is opened again", function()
    local card = Book.open()
    card.minus:GetScript("OnClick")(card.minus)
    local button = Book.frames()
    assert.is_true(button:IsShown())
    Book.open()
    card.close:GetScript("OnClick")(card.close)
    assert.is_false(button:IsShown())
    assert.is_false(card:IsShown())
    Book.toggle()
    assert.is_true(card:IsShown())
  end)

  it("keeps one spot for both frames: a drag of either saves it and moves the other", function()
    local button = Book.frames()
    button:GetScript("OnDragStop")(button)
    assert.same({ "BOTTOMLEFT", "BOTTOMLEFT", 300, 400 }, Env.db.phrases.point)
    local card = Book.open()
    assert.same({ "BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 300, 400 }, card.point)
    Env.db.phrases.point = nil
    card:GetScript("OnDragStop")(card)
    assert.same({ "BOTTOMLEFT", "BOTTOMLEFT", 300, 400 }, Env.db.phrases.point)
    assert.same({ "BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 300, 400 }, button.point)
  end)

  it("shows no button with its setting off, still opens the card, and keeps the button with translation off", function()
    local button = Book.frames()
    WFJ.Settings.set("chat.phraseButton", false)
    assert.is_false(button:IsShown())
    Book.toggle()
    local _, card = Book.frames()
    assert.is_true(card:IsShown())
    Book.collapse()
    assert.is_false(button:IsShown())
    WFJ.Settings.set("chat.phraseButton", true)
    assert.is_true(button:IsShown())
    WFJ.State.setEnabled(false)
    assert.is_true(button:IsShown())
  end)
end)
