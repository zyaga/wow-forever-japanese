local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua",
  "UI/Font.lua", "UI/OptionsText.lua", "UI/OptionsWidgets.lua", "UI/BindingNames.lua" }

local NAMES = { "BINDING_NAME_WFJ_TOGGLE", "BINDING_NAME_WFJ_REVEAL", "BINDING_NAME_WFJ_STUDY",
  "BINDING_NAME_WFJ_VOICE_PAUSE", "BINDING_NAME_WFJ_VOICE_REPLAY", "BINDING_NAME_WFJ_FREEZE_TOOLTIP" }

describe("UI/BindingNames: the key bindings' names in the player's language", function()
  local WFJ

  before_each(function()
    for _, name in ipairs(NAMES) do _G[name] = nil end
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(FILES)
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Settings.load(nil, 1, {})
  end)

  local function allAscii()
    for _, name in ipairs(NAMES) do
      if _G[name]:find("[\128-\255]") then return false end
    end
    return true
  end

  local function allJapanese()
    for _, name in ipairs(NAMES) do
      if not _G[name]:find("[\128-\255]") then return false end
    end
    return true
  end

  it("names all six in Japanese while Japanese shows", function()
    for _, name in ipairs(NAMES) do
      assert.is_string(_G[name], name)
      assert.is_true(#_G[name] > 0, name)
    end
    assert.is_true(allJapanese())
    assert.are.equal("ツールチップを固定（単語カード）", BINDING_NAME_WFJ_FREEZE_TOOLTIP)
  end)

  it("names them in English with translation off, and in Japanese again when it is back on", function()
    WFJ.State.setEnabled(false)
    assert.is_true(allAscii())
    assert.are.equal("Freeze the tooltip (word cards)", BINDING_NAME_WFJ_FREEZE_TOOLTIP)
    assert.is_truthy(BINDING_NAME_WFJ_REVEAL:find("settings", 1, true))
    WFJ.State.setEnabled(true)
    assert.is_true(allJapanese())
  end)

  it("follows the direction: English first names them in English", function()
    WFJ.State.setDirection("en")
    assert.is_true(allAscii())
    WFJ.State.setDirection("ja")
    assert.is_true(allJapanese())
  end)

  it("leaves the section's name alone", function()
    assert.are.equal("WoW Forever Japanese", BINDING_HEADER_WFJ)
  end)
end)
