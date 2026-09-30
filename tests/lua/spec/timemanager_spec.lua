-- The clock window on Forever: UI/TimeManager.lua over a TimeManagerFrame replayed from camelot
-- blizzard_timemanager/mainline/blizzard_timemanager.xml:3–176 (ButtonFrameTemplate, the unnamed TIMEMANAGER_TITLE
-- FontString, the OnLoad-written check texts, the AM / PM dropdown), :178–204 (TimeManagerClockButton), :206–340
-- (StopwatchFrame) and blizzard_timemanager.lua:493–510 (the clock tooltip). The alarm message stays as typed; the
-- surface waits for Blizzard_TimeManager in either load order.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/TimeManager.lua"

local ADDON = "Blizzard_TimeManager"

local UI = {
  TIMEMANAGER_TITLE = { "Clock", "時計" }, STOPWATCH_TITLE = { "Stopwatch", "ストップウォッチ" },
  TIMEMANAGER_SHOW_STOPWATCH = { "Show Stopwatch", "ストップウォッチを表示" },
  TIMEMANAGER_ALARM_TIME = { "Alarm Time", "アラーム時刻" },
  TIMEMANAGER_ALARM_MESSAGE = { "Alarm Message", "アラームメッセージ" },
  TIMEMANAGER_ALARM_ENABLED = { "Alarm Enabled", "アラーム有効" },
  TIMEMANAGER_24HOURMODE = { "24 Hour Mode", "24時間表示" }, TIMEMANAGER_LOCALTIME = { "Use Local Time", "現地時間を使用" },
  TIMEMANAGER_AM = { "AM", "午前" }, TIMEMANAGER_PM = { "PM", "午後" },
  TIMEMANAGER_TOOLTIP_TITLE = { "Time Info", "時刻情報" },
  TIMEMANAGER_TOOLTIP_REALMTIME = { "Realm time:", "レルム時間:" },
  TIMEMANAGER_TOOLTIP_LOCALTIME = { "Local time:", "現地時間:" },
  GAMETIME_TOOLTIP_TOGGLE_CLOCK = { "Click to show clock settings.", "クリックで時計の設定を表示します。" },
  TIMEMANAGER_ALARM_TOOLTIP_TURN_OFF = { "Click to turn off alarm.", "クリックでアラームを止めます。" },
  CLOSE = { "Close", "閉じる" }, -- a word an alarm message may happen to be
}

local function en(key) return _G[key] end

-- `mainline`: a ButtonFrameTemplate with a TitleContainer (false: a frame without it).
local function loadTimeManager(mainline)
  local frame = CreateFrame("Frame", "TimeManagerFrame")
  if mainline then frame.TitleContainer = { TitleText = Stub.fontString("") } end
  frame:addRegion(Stub.fontString(en("TIMEMANAGER_TITLE")))
  Stub.namedFontString("TimeManagerFrameTicker", "10:42")
  Stub.namedFontString("TimeManagerStopwatchFrameText", en("TIMEMANAGER_SHOW_STOPWATCH"))
  Stub.namedFontString("TimeManagerAlarmTimeLabel", en("TIMEMANAGER_ALARM_TIME"))
  Stub.namedFontString("TimeManagerAlarmMessageLabel", en("TIMEMANAGER_ALARM_MESSAGE"))
  Stub.namedFontString("TimeManagerAlarmEnabledButtonText", en("TIMEMANAGER_ALARM_ENABLED"))
  Stub.namedFontString("TimeManagerMilitaryTimeCheckText", en("TIMEMANAGER_24HOURMODE"))
  Stub.namedFontString("TimeManagerLocalTimeCheckText", en("TIMEMANAGER_LOCALTIME"))
  local edit = CreateFrame("EditBox", "TimeManagerAlarmMessageEditBox")
  edit:SetText("Close")
  local ampm = CreateFrame("DropdownButton")
  ampm.name = "AMPMDropdown"
  ampm.Text = Stub.fontString(en("TIMEMANAGER_AM"))
  function ampm.UpdateText(self) self.Text.text = en(self.pm and "TIMEMANAGER_PM" or "TIMEMANAGER_AM") end
  frame.AlarmTimeFrame = { AMPMDropdown = ampm }
  CreateFrame("Button", "TimeManagerClockButton")
  Stub.namedFontString("TimeManagerClockTicker", "10:42")
  CreateFrame("Frame", "StopwatchFrame")
  Stub.namedFontString("StopwatchTitle", en("STOPWATCH_TITLE"))
  Stub.namedFontString("StopwatchTickerHour", "00")
  Stub.loadedAddons[ADDON] = true
  return frame
end

local GLOBALS = { "TimeManagerFrame", "TimeManagerFrameTicker", "TimeManagerStopwatchFrameText",
  "TimeManagerAlarmTimeLabel", "TimeManagerAlarmMessageLabel", "TimeManagerAlarmEnabledButtonText",
  "TimeManagerMilitaryTimeCheckText", "TimeManagerLocalTimeCheckText", "TimeManagerAlarmMessageEditBox",
  "TimeManagerClockButton", "TimeManagerClockTicker", "StopwatchFrame", "StopwatchTitle", "StopwatchTickerHour" }

describe("the clock window on Forever", function()
  local WFJ

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function boot()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end

  local function setup(loadedFirst)
    boot()
    if loadedFirst then
      loadTimeManager(true)
      assert.is_true(WFJ.TimeManager.init())
    else
      assert.is_false(WFJ.TimeManager.init()) -- waits for the addon
      loadTimeManager(true)
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
  end)

  for _, order in ipairs({ { true, "loaded at login" }, { false, "loaded on demand" } }) do
    describe("Blizzard_TimeManager " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("the title, the static labels and the stopwatch title are Japanese; Alt shows English", function()
        assert.are.equal("時計", (_G.TimeManagerFrame:GetRegions()):GetText())
        assert.are.equal("ストップウォッチを表示", _G.TimeManagerStopwatchFrameText:GetText())
        assert.are.equal("アラーム時刻", _G.TimeManagerAlarmTimeLabel:GetText())
        assert.are.equal("アラームメッセージ", _G.TimeManagerAlarmMessageLabel:GetText())
        assert.are.equal("アラーム有効", _G.TimeManagerAlarmEnabledButtonText:GetText())
        assert.are.equal("24時間表示", _G.TimeManagerMilitaryTimeCheckText:GetText())
        assert.are.equal("現地時間を使用", _G.TimeManagerLocalTimeCheckText:GetText())
        assert.are.equal("ストップウォッチ", _G.StopwatchTitle:GetText())
        alt(true)
        assert.are.equal("Clock", (_G.TimeManagerFrame:GetRegions()):GetText())
        assert.are.equal("Stopwatch", _G.StopwatchTitle:GetText())
        alt(false)
        assert.are.equal("時計", (_G.TimeManagerFrame:GetRegions()):GetText())
      end)

      it("the AM / PM selection follows the dropdown's own writer", function()
        local ampm = _G.TimeManagerFrame.AlarmTimeFrame.AMPMDropdown
        assert.are.equal("午前", ampm.Text:GetText())
        ampm.pm = true
        ampm:UpdateText()
        assert.are.equal("午後", ampm.Text:GetText())
      end)

      it("the alarm message and the tickers are never touched", function()
        assert.are.equal("Close", _G.TimeManagerAlarmMessageEditBox:GetText())
        assert.are.equal("10:42", _G.TimeManagerFrameTicker:GetText())
        assert.is_true(WFJ.Labels.forbidden(_G.TimeManagerAlarmMessageEditBox))
        assert.are.equal(0, WFJ.Labels.show("timemanager", "x", _G.TimeManagerAlarmMessageEditBox))
        assert.are.equal("Close", _G.TimeManagerAlarmMessageEditBox:GetText())
      end)

      it("the clock tooltip translates; the alarm message the player typed does not", function()
        local tt = _G.GameTooltip
        tt:SetOwner(_G.TimeManagerClockButton)
        tt:ClearLines()
        tt:AddLine(en("TIMEMANAGER_TOOLTIP_TITLE"))
        tt:AddDoubleLine(en("TIMEMANAGER_TOOLTIP_REALMTIME"), "10:42 AM")
        tt:AddDoubleLine(en("TIMEMANAGER_TOOLTIP_LOCALTIME"), "7:42 PM")
        tt:AddLine(" ")
        tt:AddLine(en("GAMETIME_TOOLTIP_TOGGLE_CLOCK"))
        tt:Show()
        assert.are.equal("時刻情報", _G.GameTooltipTextLeft1:GetText())
        assert.are.equal("レルム時間:", _G.GameTooltipTextLeft2:GetText())
        assert.are.equal("10:42 AM", _G.GameTooltipTextRight2:GetText())
        assert.are.equal("現地時間:", _G.GameTooltipTextLeft3:GetText())
        assert.are.equal("クリックで時計の設定を表示します。", _G.GameTooltipTextLeft5:GetText())
        tt:ClearLines()
        tt:AddLine("Close") -- the alarm message
        tt:AddLine(" ")
        tt:AddLine(en("TIMEMANAGER_ALARM_TOOLTIP_TURN_OFF"))
        tt:Show()
        assert.are.equal("Close", _G.GameTooltipTextLeft1:GetText())
        assert.are.equal("クリックでアラームを止めます。", _G.GameTooltipTextLeft3:GetText())
      end)

      it("labels are shown again when the window is re-shown", function()
        _G.TimeManagerAlarmTimeLabel.text = en("TIMEMANAGER_ALARM_TIME") -- the client rewrote it
        _G.TimeManagerFrame:Show()
        assert.are.equal("アラーム時刻", _G.TimeManagerAlarmTimeLabel:GetText())
      end)
    end)
  end

  it("hooks install once", function()
    setup(true)
    assert.is_false(WFJ.TimeManager.setup())
    assert.are.equal(1, #Stub.hooks["AMPMDropdown:UpdateText"])
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    boot()
    loadTimeManager(true)
    _G.TimeManagerAlarmTimeLabel = 7
    _G.StopwatchFrame = "x"
    _G.TimeManagerClockButton = true
    _G.TimeManagerFrame.AlarmTimeFrame = 3
    assert.has_no.errors(function() assert.is_true(WFJ.TimeManager.init()) end)
    assert.are.equal("アラームメッセージ", _G.TimeManagerAlarmMessageLabel:GetText())
    assert.are.equal("Stopwatch", en("STOPWATCH_TITLE"))
  end)

  it("without the frame, or on a frame without a TitleContainer, init returns false and touches nothing",
    function()
      boot()
      assert.is_false(WFJ.TimeManager.init())
      Stub.loadedAddons[ADDON] = true
      assert.is_false(WFJ.TimeManager.setup())
      loadTimeManager(false)
      assert.is_false(WFJ.TimeManager.init())
      assert.are.equal("Alarm Time", _G.TimeManagerAlarmTimeLabel:GetText())
      assert.is_false(WFJ.HelpTooltip.registered(_G.TimeManagerClockButton))
    end)
end)
