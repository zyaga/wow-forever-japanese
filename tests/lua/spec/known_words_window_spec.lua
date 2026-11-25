-- UI/KnownWordsWindow: the import, the export, the counts and scores, one language at a time.
local Env = require("tests.lua.spec.chat_env")
local Stub = require("tests.lua.spec.wow_stub")

describe("the known words window", function()
  local WFJ, Window, Status, frame

  before_each(function()
    WFJ = Env.setup()
    WFJ.Placeholders = { CLASS = {}, RACE = {} }
    WFJ.Data.add("freqJa", { ["今日\tきょう"] = "6,0,0,0,0,0", ["行く\tいく"] = "3,1,0,0,0,0" })
    WFJ.Data.add("freqEn", { need = "4,0,0,0,0,0", help = "2,0,0,0,0,0" })
    Window, Status = WFJ.KnownWordsWindow, WFJ.WordStatus
    Status.load(nil)
    frame = Window.open()
  end)
  after_each(Env.teardown)

  local function paste(text) frame.text.box:SetText(text) end

  it("shows its text in Japanese, and in English while the reveal key is held", function()
    assert.equals("既知の単語", frame.title:GetText())
    assert.is_truthy(frame.counts:GetText():find("既知：0", 1, true))
    assert.is_truthy(frame.score:GetText():find("ゲーム全体の理解度", 1, true))
    assert.is_nil(frame.score:GetText():find("You know", 1, true))
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.equals("Known words", frame.title:GetText())
    assert.is_truthy(frame.score:GetText():find("You know", 1, true))
    assert.is_nil(frame.score:GetText():find("ゲーム全体", 1, true))
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
  end)

  it("marks the pasted words known, leaves the unmatched ones in the box and keeps the numbers", function()
    paste("今日, 行き ぜったいない")
    local result = Window.import()
    assert.same({ 2, 1 }, { result.marked, #result.missing })
    assert.equals("known", Status.get("ja", "今日\tきょう"))
    assert.equals("known", Status.get("ja", "行く\tいく"))
    assert.equals("ぜったいない", frame.text.getText())
    assert.is_truthy(frame.counts:GetText():find("既知：2", 1, true))
    assert.is_truthy(frame.score:GetText():find("100", 1, true))
    assert.is_truthy(frame.last:GetText():find("2", 1, true))
    -- opened again: the last import is still there
    frame:Hide()
    Window.open()
    assert.is_truthy(frame.last:GetText() ~= "" and frame.last:GetText():find("前回", 1, true))
  end)

  it("marks its matches ignored when that is chosen", function()
    frame.as:GetScript("OnClick")(frame.as)
    paste("今日")
    Window.import()
    assert.equals("ignored", Status.get("ja", "今日\tきょう"))
  end)

  it("imports English words when English is chosen, into the English list", function()
    frame.language:GetScript("OnClick")(frame.language)
    paste("Need, help zebra")
    local result = Window.import()
    assert.same({ 2, 1 }, { result.marked, #result.missing })
    assert.equals("known", Status.get("en", "need"))
    assert.same({}, Status.entries("ja"))
  end)

  it("exports the player's statuses into the box", function()
    Status.set("ja", "今日\tきょう", "known")
    Status.set("ja", "行く\tいく", "learning")
    Window.export()
    assert.equals("今日\tきょう\tknown\n行く\tいく\tlearning", frame.text.getText())
  end)

  it("leaves the pasted words in the box when the statuses cannot be changed here", function()
    Status.load({ schema = 99 })
    paste("今日")
    assert.is_nil(Window.import())
    assert.equals("今日", frame.text.getText())
    assert.is_truthy(frame.last:GetText() ~= "")
  end)

  it("starts on the language being studied", function()
    assert.equals("ja", Window.studied())
    WFJ.Settings.set("direction", "en")
    assert.equals("en", Window.studied())
  end)
end)
