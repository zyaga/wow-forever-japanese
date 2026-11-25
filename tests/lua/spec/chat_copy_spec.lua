-- UI/ChatCopy: what the copy box holds for a line, and when the icon shows.
local Env = require("tests.lua.spec.chat_env")

local SAID = "|Hplayer:Taro:12:SAY|h[Taro]|h says: 今日は|cffff0000ダンジョン|r"
local GUILD = "|Hchannel:GUILD|h[Guild]|h |Hplayer:Hana:3:GUILD|h[Hana]|h: 時間: 9時でいい？"
local LOOT = "You receive loot: |cff1eff00|Hitem:1|h[Thing]|h|r."

describe("copying a chat line", function()
  local WFJ, Copy, frame

  before_each(function()
    WFJ = Env.setup()
    Copy = WFJ.ChatCopy
    frame = Env.chatFrame({ { SAID, Env.SAY }, { GUILD, Env.GUILD }, { LOOT, Env.SYSTEM } })
    WFJ.ChatLines.init()
    Copy.init()
  end)
  after_each(Env.teardown)

  it("gives only what the player typed for a typed line, a colon in the message kept", function()
    assert.equals("今日はダンジョン", Copy.textOf(frame.visibleLines[1], SAID))
    assert.equals("時間: 9時でいい？", Copy.textOf(frame.visibleLines[2], GUILD))
  end)

  it("gives any other line whole, without its escape codes", function()
    assert.equals("You receive loot: [Thing].", Copy.textOf(frame.visibleLines[3], LOOT))
  end)

  it("gives a line of a typed shape whole when its chat type is not a typed one", function()
    local line = Env.line(SAID, Env.SYSTEM)
    assert.equals("[Taro] says: 今日はダンジョン", Copy.textOf(line, SAID))
  end)

  it("puts the icon on the line under the mouse and opens the box with that line", function()
    frame.visibleLines[2].over = true
    WFJ.ChatLines.look()
    local button = Copy.button()
    assert.is_true(button:IsShown())
    button:GetScript("OnClick")(button)
    assert.is_true(_G.WFJChatCopyWindow:IsShown())
    assert.equals("時間: 9時でいい？", _G.WFJChatCopyWindow.field.getText())
    frame.visibleLines[2].over = false
    WFJ.ChatLines.look()
    assert.is_false(button:IsShown())
  end)

  it("places the icon once for a line, not on every look", function()
    frame.visibleLines[2].over = true
    WFJ.ChatLines.look()
    local button = Copy.button()
    button.point = "kept"
    WFJ.ChatLines.look()
    assert.equals("kept", button.point)
  end)

  it("stops looking at the mouse when neither the cards nor the icon is wanted", function()
    local driver = WFJ.ChatLines.driver
    assert.is_true(driver:IsShown())
    WFJ.Settings.set("chat.copy", false)
    assert.is_true(driver:IsShown()) -- the cards still want it
    WFJ.Settings.set("chat.cards", false)
    assert.is_false(driver:IsShown())
    WFJ.Settings.set("chat.copy", true)
    assert.is_true(driver:IsShown())
    WFJ.State.setEnabled(false)
    assert.is_false(driver:IsShown())
  end)

  it("shows no icon on a secret line, with the setting off, or with translation off", function()
    frame.visibleLines[1].over = true
    Env.secrets[SAID] = true
    WFJ.ChatLines.look()
    assert.is_nil(Copy.button())
    Env.secrets[SAID] = nil
    WFJ.Settings.set("chat.copy", false)
    WFJ.ChatLines.look()
    assert.is_nil(Copy.button())
    WFJ.Settings.set("chat.copy", true)
    WFJ.State.enabled = false
    WFJ.ChatLines.look()
    assert.is_nil(Copy.button())
    WFJ.State.enabled = true
    WFJ.ChatLines.look()
    assert.is_true(Copy.button():IsShown())
  end)
end)
