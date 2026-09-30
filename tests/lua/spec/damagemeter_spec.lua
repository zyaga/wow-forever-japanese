-- UI/DamageMeter.lua over a DamageMeter frame and its session windows replayed from camelot's
-- blizzard_damagemeter (damagemeter.lua:284–289 SetupSessionWindow; damagemetersessionwindow.lua:800–811
-- SetDamageMeterType, :711–717 UpdateNotActiveText, :820–830 SetSession). Source rows, the session abbreviation and
-- the timer stay as written. Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/DamageMeter.lua"

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local UI = {
  DAMAGE_METER_TYPE_DAMAGE_DONE = { "Damage Done", "与ダメージ" },
  DAMAGE_METER_TYPE_HEALING_DONE = { "Healing Done", "回復量" },
  DAMAGE_METER_TYPE_DEATHS = { "Deaths", "死亡" },
  DAMAGE_METER_AVOIDABLE_DAMAGE_NOT_ACTIVE = { "Avoidable damage tracking is only active in current season instances",
    "回避可能ダメージの記録は現行シーズンのインスタンスでのみ有効です" },
  DAMAGE_METER_OVERALL_SESSION_SHORT = { "O", "全" }, -- in the dictionary, and never shown on this surface
}

local TYPE_NAMES = { [1] = "Damage Done", [2] = "Healing Done", [3] = "Deaths", [4] = "Avoidable Damage Taken" }

local function sessionWindow(name)
  local w = CreateFrame("Frame", name)
  w.DamageMeterTypeDropdown = { TypeName = Stub.fontString("") }
  w.SessionDropdown = { SessionName = Stub.fontString("") }
  w.MinimizeContainer = { NotActive = Stub.fontString("") }
  w.SessionTimer = Stub.fontString("")
  w.row = Stub.fontString("1. Deaths") -- a source row: a player who happens to be called "Deaths"
  function w.UpdateNotActiveText(self)
    self.MinimizeContainer.NotActive.text = self.damageMeterType == 4 and self.empty
      and "Avoidable damage tracking is only active in current season instances" or nil
  end
  function w.SetDamageMeterType(self, t)
    self.damageMeterType = t
    self.DamageMeterTypeDropdown.TypeName.text = TYPE_NAMES[t]
    self:UpdateNotActiveText()
  end
  function w.SetSession(self, short) self.SessionDropdown.SessionName.text = short end
  return w
end

local function installMeter()
  local frame = CreateFrame("Frame", "DamageMeter")
  function frame.SetupSessionWindow(_, index, windowData)
    windowData.sessionWindow = windowData.sessionWindow or sessionWindow("DamageMeterSessionWindow" .. index)
    windowData.sessionWindow:SetDamageMeterType(windowData.damageMeterType)
    windowData.sessionWindow:SetSession("O")
  end
  return frame
end

local GLOBALS = { "DamageMeter", "DamageMeterSessionWindow1", "DamageMeterSessionWindow2",
  "DamageMeterSessionWindow3" }

describe("the damage meter on Forever", function()
  local WFJ

  local function setup(install)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    if install then install() end
    WFJ.Labels.forbidNames(WFJ.DamageMeter.NEVER_TOUCH)
  end

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
  end)

  it("a window that exists at init: its type label is Japanese and follows a type change", function()
    setup(function() installMeter():SetupSessionWindow(1, { damageMeterType = 1 }) end)
    assert.is_true(WFJ.DamageMeter.init())
    local w = _G.DamageMeterSessionWindow1
    assert.are.equal("与ダメージ", w.DamageMeterTypeDropdown.TypeName:GetText())
    w:SetDamageMeterType(2)
    assert.are.equal("回復量", w.DamageMeterTypeDropdown.TypeName:GetText())
    alt(true)
    assert.are.equal("Healing Done", w.DamageMeterTypeDropdown.TypeName:GetText())
    alt(false)
    w.empty = true
    w:SetDamageMeterType(4) -- not in the fixture dictionary: the type stays English, the notice translates
    assert.are.equal("Avoidable Damage Taken", w.DamageMeterTypeDropdown.TypeName:GetText())
    assert.are.equal(UI.DAMAGE_METER_AVOIDABLE_DAMAGE_NOT_ACTIVE[2], w.MinimizeContainer.NotActive:GetText())
  end)

  it("a window created after init is followed; the session abbreviation and a source row stay as written", function()
    setup(installMeter)
    assert.is_true(WFJ.DamageMeter.init())
    _G.DamageMeter:SetupSessionWindow(2, { damageMeterType = 3 })
    local w = _G.DamageMeterSessionWindow2
    assert.are.equal("死亡", w.DamageMeterTypeDropdown.TypeName:GetText())
    assert.are.equal("O", w.SessionDropdown.SessionName:GetText())
    assert.is_true(WFJ.Labels.forbidden(w.SessionDropdown.SessionName))
    assert.are.equal(0, WFJ.Labels.show("damagemeter", "x", w.SessionDropdown.SessionName))
    assert.are.equal("1. Deaths", w.row:GetText())
    -- set up again with the same window (a reload of saved data): hooked once
    _G.DamageMeter:SetupSessionWindow(2, { damageMeterType = 1, sessionWindow = w })
    assert.are.equal("与ダメージ", w.DamageMeterTypeDropdown.TypeName:GetText())
    assert.are.equal(1, #Stub.hooks["DamageMeterSessionWindow2:SetDamageMeterType"])
  end)

  it("client names bound to the wrong type degrade to English with no error", function()
    setup(function()
      installMeter():SetupSessionWindow(1, { damageMeterType = 1 })
      _G.DamageMeterSessionWindow1.DamageMeterTypeDropdown = "moved"
      _G.DamageMeterSessionWindow1.MinimizeContainer = 5
      _G.DamageMeterSessionWindow2 = "not a frame"
      _G.DamageMeter.SetupSessionWindow = true
    end)
    assert.has_no.errors(function() assert.is_true(WFJ.DamageMeter.init()) end)
    assert.has_no.errors(function() WFJ.DamageMeter.onType(_G.DamageMeterSessionWindow1) end)
    assert.has_no.errors(function() WFJ.DamageMeter.onNotActive(_G.DamageMeterSessionWindow1) end)
    assert.has_no.errors(function() WFJ.DamageMeter.onSetup(nil, 1, "bad") end)
  end)

  it("hooks install once; without the DamageMeter frame init returns false", function()
    setup(installMeter)
    assert.is_true(WFJ.DamageMeter.init())
    assert.is_false(WFJ.DamageMeter.init())
    assert.are.equal(1, #Stub.hooks["DamageMeter:SetupSessionWindow"])
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
    setup(nil)
    assert.has_no.errors(function() assert.is_false(WFJ.DamageMeter.init()) end)
  end)
end)
