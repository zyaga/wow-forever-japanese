-- UI/ReadyCheck.lua over ReadyCheckListenerFrame replayed from camelot
-- blizzard_framexml/mainline/readycheck.lua:23–33, 40–41, 89–110 and readycheck.xml:35, 53, 79, 92.
local Stub = require("tests.lua.spec.wow_stub")
local X = require("tests.lua.spec.stub_framexml_hud")

local UI = {
  READY_CHECK = { "Ready Check", "レディチェック" }, READY = { "Ready", "準備完了" },
  NOT_READY = { "Not Ready", "準備未完了" },
  READY_CHECK_MESSAGE = { "%s has initiated a ready check.", "%sがレディチェックを開始しました。" },
  RAID_DIFFICULTY = { "Raid Difficulty", "レイド難易度" },
}
local ARGS = { READY_CHECK_MESSAGE = { [1] = "text" } }
local NAMES = { "ReadyCheckListenerFrame", "ReadyCheckFrameYesButton", "ReadyCheckFrameNoButton",
  "ReadyCheckFrameText" }

local function install()
  local f = CreateFrame("Frame", "ReadyCheckListenerFrame")
  f.TitleContainer = { TitleText = Stub.fontString("Ready Check") }
  f.Text = Stub.namedFontString("ReadyCheckFrameText", "")
  f.YesButton = Stub.button("ReadyCheckFrameYesButton", "Ready")
  f.NoButton = Stub.button("ReadyCheckFrameNoButton", "Not Ready")
  function f.Display(self, initiator, difficulty)
    local txt = _G.READY_CHECK_MESSAGE
    if difficulty then txt = txt .. "\n" .. _G.RAID_DIFFICULTY .. ": " .. difficulty end
    self.Text.text = txt:format(initiator)
    self:Show()
  end
end

describe("the ready check prompt on Forever", function()
  local WFJ
  before_each(function()
    WFJ = X.load("UI/ReadyCheck.lua", UI, { args = ARGS, before = install })
    assert.is_true(WFJ.ReadyCheck.init())
  end)
  after_each(function() X.teardown(NAMES) end)

  it("title, buttons and the message translate; the initiator's name is kept", function()
    _G.ReadyCheckListenerFrame:Display("Thrall")
    assert.are.equal("レディチェック", _G.ReadyCheckListenerFrame.TitleContainer.TitleText:GetText())
    assert.are.equal("準備完了", _G.ReadyCheckFrameYesButton:GetText())
    assert.are.equal("準備未完了", _G.ReadyCheckFrameNoButton:GetText())
    assert.are.equal("Thrallがレディチェックを開始しました。", _G.ReadyCheckFrameText:GetText())
    X.alt(WFJ, true)
    assert.are.equal("Thrall has initiated a ready check.", _G.ReadyCheckFrameText:GetText())
    X.alt(WFJ, false)
  end)

  it("a player named like a dictionary word is not translated", function()
    _G.ReadyCheckListenerFrame:Display("Ready")
    assert.are.equal("Readyがレディチェックを開始しました。", _G.ReadyCheckFrameText:GetText())
  end)

  it("readyCheckLine: both lines translate, the initiator and the difficulty name kept; Alt English",
    function()
      _G.ReadyCheckListenerFrame:Display("Thrall", "Heroic")
      assert.are.equal("Thrallがレディチェックを開始しました。\nレイド難易度: Heroic", _G.ReadyCheckFrameText:GetText())
      X.alt(WFJ, true)
      assert.are.equal("Thrall has initiated a ready check.\nRaid Difficulty: Heroic", _G.ReadyCheckFrameText:GetText())
      X.alt(WFJ, false)
      assert.are.equal("Thrallがレディチェックを開始しました。\nレイド難易度: Heroic", _G.ReadyCheckFrameText:GetText())
      _G.ReadyCheckListenerFrame:Display("Thrall") -- back to one line
      assert.are.equal("Thrallがレディチェックを開始しました。", _G.ReadyCheckFrameText:GetText())
    end)

  it("hooks once; wrong types and a missing frame leave English and raise nothing", function()
    assert.is_false(WFJ.ReadyCheck.init())
    assert.are.equal(1, #Stub.hooks["ReadyCheckListenerFrame:Display"])
    X.teardown(NAMES)
    local wrong = X.load("UI/ReadyCheck.lua", UI, { args = ARGS, before = function()
      install()
      _G.ReadyCheckFrameYesButton = 7
      _G.ReadyCheckListenerFrame.YesButton = "x"
      _G.ReadyCheckListenerFrame.TitleContainer = false
    end })
    assert.has_no.errors(function() assert.is_true(wrong.ReadyCheck.init()) end)
    assert.are.equal("準備未完了", _G.ReadyCheckFrameNoButton:GetText())
    X.teardown(NAMES)
    local none = X.load("UI/ReadyCheck.lua", UI, { args = ARGS,
      before = function() _G.ReadyCheckListenerFrame = "x" end })
    assert.has_no.errors(function() assert.is_false(none.ReadyCheck.init()) end)
  end)
end)
