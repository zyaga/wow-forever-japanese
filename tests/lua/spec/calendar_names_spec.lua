-- The calendar's game names over UI/Calendar.lua, replayed from Forever blizzard_calendar/mainline/
-- blizzard_calendar.lua: a holiday's title on a day button (lua:1568–1574), in the event picker (lua:4350), on the
-- day tooltip (lua:411–416, 2148–2154) and as the holiday frame's header (lua:2476), and the names inside a
-- holiday's description (lua:2477–2482). A title a player typed is never read as a name. A title of two names with
-- a colon between them shows each half's Japanese.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Calendar.lua"

local UI = {
  FULLDATE = { "%1$s, %2$s %3$d %4$d", "%4$d年%2$s%3$d日(%1$s)" },
  WEEKDAY_THURSDAY = { "Thursday", "木曜日" }, MONTH_SEPTEMBER = { "September", "9月" },
  CALENDAR_EVENTNAME_FORMAT_START = { "%s Begins", "%s開始" },
  CALENDAR_HOLIDAYFRAME_BEGINSENDS = { "%1$s|n|nBegins: %2$s %3$s|nEnds: %4$s %5$s",
    "%1$s|n|n開始: %2$s %3$s|n終了: %4$s %5$s" },
  ["HolidayDescription:283"] = { "The battle for Warsong Gulch rages on.", "Warsong Gulchの戦いが続いています。" },
}

-- Day 12's events as C_Calendar.GetDayEvent returns them: two holidays, and a player's event typed like one.
local EVENTS = {
  { calendarType = "HOLIDAY", sequenceType = "ONGOING", title = "Darkmoon Faire" },
  { calendarType = "PLAYER", sequenceType = "", title = "Darkmoon Faire" },
  { calendarType = "HOLIDAY", sequenceType = "START", title = "Hallow's End" },
  { calendarType = "HOLIDAY", sequenceType = "", title = "A Holiday Nobody Spelled" },
}

local function loadCalendar()
  local frame = CreateFrame("Frame", "CalendarFrame")
  frame.FilterButton = CreateFrame("DropdownButton")
  frame.FilterButton.Text = Stub.fontString("")
  function frame.FilterButton.UpdateText() end
  local holiday = CreateFrame("Frame", "CalendarViewHolidayFrame")
  holiday.ScrollingFont = Stub.scrollingFont("")
  holiday.ScrollingFont.GetText = nil
  -- DialogHeaderMixin (blizzard_sharedxml/shared/dialog/dialogtemplates.lua:9–21): as wide as its text
  holiday.Header = CreateFrame("Frame")
  holiday.Header.Text = Stub.fontString("")
  holiday.Header.widths = 0
  function holiday.Header:UpdateWidth() self.widths = self.widths + 1 end
  function holiday.Header:Setup(text) self.Text:SetText(text); self:UpdateWidth() end
  for i = 1, 42 do
    local b = CreateFrame("Button", "CalendarDayButton" .. i)
    b.day, b.monthOffset = i, 0
  end
  for i = 1, 4 do
    CreateFrame("Button", "CalendarDayButton12EventButton" .. i)
    Stub.namedFontString("CalendarDayButton12EventButton" .. i .. "Text1", "")
  end
  _G.C_Calendar = {
    GetNumDayEvents = function(_, day) return day == 12 and #EVENTS or 0 end,
    GetDayEvent = function(_, day, i) return day == 12 and EVENTS[i] or nil end,
  }
  _G.CalendarFrame_UpdateDayEvents = function(index)
    for i = 1, 4 do
      _G["CalendarDayButton" .. index .. "EventButton" .. i].eventIndex = i
      _G["CalendarDayButton" .. index .. "EventButton" .. i .. "Text1"]:SetText(EVENTS[i].title)
    end
  end
  _G.CalendarEventPickerFrame = { dayButton = _G.CalendarDayButton12 }
  _G.CalendarEventPickerFrame_InitButton = function(button, elementData)
    button.Title:SetText(EVENTS[elementData.index].title)
  end
  _G.CalendarDayButton_OnEnter = function(self)
    local tt = _G.GameTooltip
    tt:SetOwner(self)
    tt:ClearLines()
    tt:AddLine("Thursday, September 25 2026")
    for _, event in ipairs(EVENTS) do
      tt:AddLine(" ")
      tt:AddDoubleLine(event.sequenceType == "START" and event.title .. " Begins" or event.title, "8:00 PM")
    end
    tt:Show()
  end
  _G.CalendarViewHolidayFrame_Update = function()
    holiday.Header:Setup("Darkmoon Faire")
    holiday.ScrollingFont:SetText("The battle for Warsong Gulch rages on.|n|nBegins: 9/25 8:00 AM|nEnds: 10/2 11:59 PM")
  end
  Stub.loadedAddons.Blizzard_Calendar = true
end

describe("UI/Calendar: holiday names", function()
  local WFJ

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function text1(i) return _G["CalendarDayButton12EventButton" .. i .. "Text1"]:GetText() end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    WFJ.Data.add("name", {
      [WFJ.Names.key("Darkmoon Faire")] = "ダークムーン・フェア\tだーくむーん・ふぇあ",
      [WFJ.Names.key("Hallow's End")] = "ハロウズ・エンド\tはろうず・えんど",
      [WFJ.Names.key("Warsong Gulch")] = "ウォーソング・ガルチ\tうぉーそんぐ・がるち",
    })
    WFJ.State.setNames(true)
    -- as Main does
    WFJ.UIStrings.name = function(text) return WFJ.State.names and WFJ.Names.value(text) or nil end
    WFJ.UIStrings.inText = function(ja) return WFJ.State.names and (WFJ.Names.inText(ja)) or ja end
    loadCalendar()
    assert.is_true(WFJ.Calendar.init())
  end)

  after_each(function()
    WFJ.UIStrings.name, WFJ.UIStrings.inText = nil, nil
    WFJ.State.setNames(false)
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs({ "CalendarFrame", "CalendarViewHolidayFrame", "C_Calendar", "CalendarFrame_UpdateDayEvents",
      "CalendarEventPickerFrame", "CalendarEventPickerFrame_InitButton", "CalendarDayButton_OnEnter",
      "CalendarViewHolidayFrame_Update" }) do _G[name] = nil end
  end)

  it("a day button shows a holiday's name in Japanese; a player's title spelled the same stays", function()
    _G.CalendarFrame_UpdateDayEvents(12)
    assert.are.equal("ダークムーン・フェア", text1(1))
    assert.are.equal("Darkmoon Faire", text1(2)) -- a player typed it
    assert.are.equal("ハロウズ・エンド", text1(3))
    assert.are.equal("A Holiday Nobody Spelled", text1(4)) -- no line in the name list
    alt(true)
    assert.are.equal("Darkmoon Faire", text1(1))
    alt(false)
    assert.are.equal("ダークムーン・フェア", text1(1))
    _G.CalendarFrame_UpdateDayEvents(12) -- the client writes its English again
    assert.are.equal("ダークムーン・フェア", text1(1))
    WFJ.State.setNames(false)
    _G.CalendarFrame_UpdateDayEvents(12)
    assert.are.equal("Darkmoon Faire", text1(1))
  end)

  it("the event picker shows a holiday's name in Japanese and leaves a player's title", function()
    local button = { Title = Stub.fontString("") }
    _G.CalendarEventPickerFrame_InitButton(button, { index = 1 })
    assert.are.equal("ダークムーン・フェア", button.Title:GetText())
    _G.CalendarEventPickerFrame_InitButton(button, { index = 2 })
    assert.are.equal("Darkmoon Faire", button.Title:GetText())
  end)

  it("the day tooltip: a holiday's line, alone or with its begins wording; a player's title stays", function()
    _G.CalendarDayButton_OnEnter(_G.CalendarDayButton12)
    local function line(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
    assert.are.equal("2026年9月25日(木曜日)", line(1))
    -- a player's event typed like the holiday's name: the two lines cannot be told apart, so both stay
    assert.are.equal("Darkmoon Faire", line(3))
    assert.are.equal("Darkmoon Faire", line(5))
    assert.are.equal("ハロウズ・エンド開始", line(7))
    assert.are.equal("A Holiday Nobody Spelled", line(9))
    alt(true)
    assert.are.equal("Hallow's End Begins", line(7))
    alt(false)
    assert.are.equal("ハロウズ・エンド開始", line(7))
    local player = table.remove(EVENTS, 2)
    finally(function() table.insert(EVENTS, 2, player) end)
    _G.CalendarDayButton_OnEnter(_G.CalendarDayButton12)
    assert.are.equal("ダークムーン・フェア", line(3))
    alt(true)
    assert.are.equal("Darkmoon Faire", line(3))
    alt(false)
    assert.are.equal("ダークムーン・フェア", line(3))
  end)

  describe("a holiday whose title is two names with a colon between them", function()
    local JA = "コール・トゥ・アームズ: "
    local was
    before_each(function()
      WFJ.Data.add("name", {
        [WFJ.Names.key("Call to Arms")] = "コール・トゥ・アームズ\tこーる・とぅ・あーむず",
        [WFJ.Names.key("Arathi Basin")] = "アラシ・ベイスン\tあらし・べいすん",
      })
      was = {}
      for i, event in ipairs(EVENTS) do was[i] = event end
      EVENTS[1] = { calendarType = "HOLIDAY", sequenceType = "ONGOING", title = "Call to Arms: Warsong Gulch" }
      EVENTS[2] = { calendarType = "HOLIDAY", sequenceType = "START", title = "Call to Arms: Arathi Basin" }
      EVENTS[3] = { calendarType = "HOLIDAY", sequenceType = "", title = "Call to Arms: A Place Nobody Spelled" }
      EVENTS[4] = { calendarType = "HOLIDAY", sequenceType = "START", title = "Call to Arms: Nowhere" }
    end)
    after_each(function() for i, event in ipairs(was) do EVENTS[i] = event end end)

    it("a day button and the picker show both names in Japanese; a title with an unknown half stays", function()
      _G.CalendarFrame_UpdateDayEvents(12)
      assert.are.equal(JA .. "ウォーソング・ガルチ", text1(1))
      assert.are.equal(JA .. "アラシ・ベイスン", text1(2))
      assert.are.equal("Call to Arms: A Place Nobody Spelled", text1(3))
      alt(true)
      assert.are.equal("Call to Arms: Warsong Gulch", text1(1))
      alt(false)
      assert.are.equal(JA .. "ウォーソング・ガルチ", text1(1))
      _G.CalendarFrame_UpdateDayEvents(12) -- the client writes its English again
      assert.are.equal(JA .. "ウォーソング・ガルチ", text1(1))
      local button = { Title = Stub.fontString("") }
      _G.CalendarEventPickerFrame_InitButton(button, { index = 2 })
      assert.are.equal(JA .. "アラシ・ベイスン", button.Title:GetText())
      WFJ.State.setEnabled(false)
      assert.are.equal("Call to Arms: Warsong Gulch", text1(1))
      WFJ.State.setEnabled(true)
      WFJ.State.setNames(false)
      _G.CalendarFrame_UpdateDayEvents(12)
      assert.are.equal("Call to Arms: Warsong Gulch", text1(1))
      _G.CalendarEventPickerFrame_InitButton(button, { index = 2 })
      assert.are.equal("Call to Arms: Arathi Basin", button.Title:GetText())
    end)

    it("the day tooltip shows both names, alone and inside the begins line, and follows the names choice",
      function()
        _G.CalendarDayButton_OnEnter(_G.CalendarDayButton12)
        local function line(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
        assert.are.equal(JA .. "ウォーソング・ガルチ", line(3))
        assert.are.equal(JA .. "アラシ・ベイスン開始", line(5))
        assert.are.equal("Call to Arms: A Place Nobody Spelled", line(7))
        assert.are.equal("Call to Arms: Nowhere開始", line(9)) -- the line's own words, the title as written
        alt(true)
        assert.are.equal("Call to Arms: Warsong Gulch", line(3))
        assert.are.equal("Call to Arms: Arathi Basin Begins", line(5))
        alt(false)
        assert.are.equal(JA .. "ウォーソング・ガルチ", line(3))
        assert.are.equal(JA .. "アラシ・ベイスン開始", line(5))
        WFJ.State.setNames(false) -- a line already on screen follows the choice
        assert.are.equal("Call to Arms: Warsong Gulch", line(3))
        assert.are.equal("Call to Arms: Arathi Basin開始", line(5))
        WFJ.State.setNames(true)
        assert.are.equal(JA .. "アラシ・ベイスン開始", line(5))
        WFJ.State.setEnabled(false)
        assert.are.equal("Call to Arms: Arathi Basin Begins", line(5))
        WFJ.State.setEnabled(true)
      end)

    it("the holiday frame's header shows both names and is fitted to them", function()
      local frame = _G.CalendarViewHolidayFrame
      local write = _G.CalendarViewHolidayFrame_Update
      _G.CalendarViewHolidayFrame_Update = function()
        write()
        frame.Header:Setup("Call to Arms: Warsong Gulch")
      end
      _G.CalendarViewHolidayFrame_Update()
      WFJ.Calendar.onHoliday() -- the hook holds the writer it found at setup
      assert.are.equal(JA .. "ウォーソング・ガルチ", frame.Header.Text:GetText())
      assert.is_true(frame.Header.widths >= 3)
      alt(true)
      assert.are.equal("Call to Arms: Warsong Gulch", frame.Header.Text:GetText())
      alt(false)
      frame.Header:Setup("Call to Arms: Nowhere")
      WFJ.Calendar.onHoliday()
      assert.are.equal("Call to Arms: Nowhere", frame.Header.Text:GetText())
      WFJ.State.setNames(false)
      frame.Header:Setup("Call to Arms: Warsong Gulch")
      WFJ.Calendar.onHoliday()
      assert.are.equal("Call to Arms: Warsong Gulch", frame.Header.Text:GetText())
    end)
  end)

  it("the holiday frame's header shows the name and is fitted to it; the description's names follow", function()
    local frame = _G.CalendarViewHolidayFrame
    _G.CalendarViewHolidayFrame_Update()
    assert.are.equal("ダークムーン・フェア", frame.Header.Text:GetText())
    assert.is_true(frame.Header.widths >= 2) -- the client's fit, then ours for the Japanese
    assert.are.equal("ウォーソング・ガルチの戦いが続いています。|n|n開始: 9/25 8:00 AM|n終了: 10/2 11:59 PM",
      frame.ScrollingFont.fs:GetText())
    alt(true)
    assert.are.equal("Darkmoon Faire", frame.Header.Text:GetText())
    alt(false)
    WFJ.State.setNames(false)
    _G.CalendarViewHolidayFrame_Update()
    assert.are.equal("Darkmoon Faire", frame.Header.Text:GetText())
    assert.are.equal("Warsong Gulchの戦いが続いています。|n|n開始: 9/25 8:00 AM|n終了: 10/2 11:59 PM",
      frame.ScrollingFont.fs:GetText())
  end)
end)
