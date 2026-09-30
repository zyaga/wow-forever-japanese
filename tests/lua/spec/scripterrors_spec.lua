-- Lua error window on Forever: UI/ScriptErrors.lua over a ScriptErrorsFrame replayed from camelot
-- blizzard_scripterrorsframe (DisplayMessageInternal lua:88–93, xml:46, 75). The error text itself is never touched.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/ScriptErrors.lua"

local UI = { LUA_ERROR = { "Lua Error", "Luaエラー" }, LUA_WARNING = { "Lua Warning", "Lua警告" },
  RELOADUI = { "Reload UI", "UIを再読み込み" }, CLOSE = { "Close", "閉じる" } }

local function en(key) return _G[key] end

local function installFrame()
  local f = CreateFrame("Frame", "ScriptErrorsFrame")
  f.Title, f.IndexLabel = Stub.fontString(""), Stub.fontString("1 / 1")
  f.Reload, f.CloseButton = Stub.button(nil, en("RELOADUI")), Stub.button(nil, en("CLOSE"))
  f.ScrollFrame = { Text = CreateFrame("EditBox") }
  function f.DisplayMessageInternal(self, message, isWarning)
    self.Title.text = isWarning and en("LUA_WARNING") or en("LUA_ERROR")
    self.ScrollFrame.Text.text = message
    self:Show()
  end
  return f
end

describe("the Lua error window on Forever", function()
  local WFJ

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.ScriptErrorsFrame = nil
  end)

  it("the title follows the message type, the buttons are Japanese, the message is never touched", function()
    load()
    local f = installFrame()
    WFJ.Labels.forbidNames(WFJ.ScriptErrors.NEVER_TOUCH)
    assert.is_true(WFJ.ScriptErrors.init())
    f:DisplayMessageInternal("Close", false) -- an error message that is a dictionary word
    assert.are.equal("Luaエラー", f.Title:GetText())
    assert.are.equal("UIを再読み込み", f.Reload:GetText())
    assert.are.equal("閉じる", f.CloseButton:GetText())
    assert.are.equal("Close", f.ScrollFrame.Text:GetText())
    assert.are.equal(0, WFJ.Labels.show("scripterrors", "x", f.ScrollFrame.Text))
    f:DisplayMessageInternal("Close", true)
    assert.are.equal("Lua警告", f.Title:GetText())
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal("Lua Warning", f.Title:GetText())
    assert.is_false(WFJ.ScriptErrors.init())
    assert.are.equal(1, #Stub.hooks["ScriptErrorsFrame:DisplayMessageInternal"])
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    load()
    local f = installFrame()
    f.Title, f.Reload, f.DisplayMessageInternal = 4, "reload", "not a function"
    assert.has_no.errors(function() assert.is_true(WFJ.ScriptErrors.init()) end)
    assert.has_no.errors(function() f:Show() end)
    assert.are.equal("閉じる", f.CloseButton:GetText())
  end)

  it("no ScriptErrorsFrame → init is false, nothing touched", function()
    load()
    assert.has_no.errors(function() assert.is_false(WFJ.ScriptErrors.init()) end)
  end)
end)
