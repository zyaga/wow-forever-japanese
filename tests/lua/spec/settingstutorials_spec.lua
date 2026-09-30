-- The Options window's "About …" windows on Forever: UI/SettingsTutorials.lua over NamePlatesTutorial and
-- PingSystemTutorial replayed from blizzard_settingsdefinitions_frame (nameplates.xml:35–87, nameplates.lua:873–878;
-- pingsystem.xml:6–137, pingsystem.lua:148–157). The title is the ButtonFrameTemplate's TitleContainer.TitleText
-- (blizzard_sharedxml/portraitframe.lua:11–13).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local S = require("tests.lua.spec.stub_settings")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
for _, f in ipairs({ "UI/LabelTree.lua", "UI/TooltipLines.lua", "UI/SettingsKeys.lua", "UI/SettingsTutorials.lua" }) do
  FILES[#FILES + 1] = f
end

local UI = {
  NAMEPLATES_LABEL = { "Nameplates", "ネームプレート" },
  UNIT_NAMEPLATES_TUTORIAL_ENEMY_FRIENDLY = {
    "Enemy player nameplates can be set up |cnTUTORIAL_BLUE_FONT_COLOR:differently|r from friendly ones.",
    "敵プレイヤーのネームプレートは、味方のものと|cnTUTORIAL_BLUE_FONT_COLOR:別の設定|rにできます。" },
  PING_SYSTEM_TUTORIAL_LABEL = { "Ping System", "ピンシステム" },
  PING_SYSTEM_TUTORIAL_MACRO_3 = { "Macro command:", "マクロコマンド:" },
  LAYOUT_WORD = { "Layout", "配置" }, -- in the dictionary, never an Options key
}

-- A ButtonFrameTemplate window: TitleContainer.TitleText written by SetTitle, and a child frame of FontStrings.
local function tutorial(name, title, lines)
  local f = S.node("Frame", name)
  local container = S.node("Frame", nil, f, "TitleContainer")
  S.label(container, "TitleText", "")
  function f:SetTitle(text) self.TitleContainer.TitleText.text = text end
  f:SetTitle(title)
  local body = S.node("Frame", nil, f, "Tutorial1")
  for i, text in ipairs(lines) do S.label(body, "Line" .. i, text) end
  return f
end

describe("the Options window's tutorial windows on Forever", function()
  local WFJ, plates, ping

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end

  local function remove() _G.NamePlatesTutorial, _G.PingSystemTutorial = nil, nil end

  before_each(function()
    load()
    plates = tutorial("NamePlatesTutorial", _G.NAMEPLATES_LABEL, { _G.UNIT_NAMEPLATES_TUTORIAL_ENEMY_FRIENDLY })
    ping = tutorial("PingSystemTutorial", _G.PING_SYSTEM_TUTORIAL_LABEL,
      { _G.PING_SYSTEM_TUTORIAL_MACRO_3, "|cnNORMAL_FONT_COLOR:/ping [@target] Ping Type|r", "Layout" })
    assert.is_true(WFJ.SettingsTutorials.init())
  end)

  after_each(function()
    H.uiTeardown()
    remove()
  end)

  it("titles and tutorial lines translate at load, colour codes kept; typed syntax and non-keys stay", function()
    assert.are.equal("ネームプレート", plates.TitleContainer.TitleText:GetText())
    assert.are.equal(UI.UNIT_NAMEPLATES_TUTORIAL_ENEMY_FRIENDLY[2], plates.Tutorial1.Line1:GetText())
    assert.are.equal("ピンシステム", ping.TitleContainer.TitleText:GetText())
    assert.are.equal("マクロコマンド:", ping.Tutorial1.Line1:GetText())
    assert.are.equal("|cnNORMAL_FONT_COLOR:/ping [@target] Ping Type|r", ping.Tutorial1.Line2:GetText())
    assert.are.equal("Layout", ping.Tutorial1.Line3:GetText())
  end)

  it("a re-title and a re-show are followed", function()
    ping:SetTitle(_G.PING_SYSTEM_TUTORIAL_LABEL)
    assert.are.equal("ピンシステム", ping.TitleContainer.TitleText:GetText())
    plates.Tutorial1.Line1.text = _G.UNIT_NAMEPLATES_TUTORIAL_ENEMY_FRIENDLY
    plates:Show()
    assert.are.equal(UI.UNIT_NAMEPLATES_TUTORIAL_ENEMY_FRIENDLY[2], plates.Tutorial1.Line1:GetText())
  end)

  it("wrong-typed client names degrade with no error; hooks install once; a client without them is skipped", function()
    assert.has_no.errors(function()
      for _, bad in ipairs({ 42, "text", true }) do
        ping.TitleContainer, ping.Tutorial1 = bad, bad
        ping:Show()
      end
    end)
    assert.is_false(WFJ.SettingsTutorials.init())
    load()
    remove()
    _G.NamePlatesTutorial = "text"
    assert.has_no.errors(function() assert.is_false(WFJ.SettingsTutorials.init()) end)
  end)
end)
