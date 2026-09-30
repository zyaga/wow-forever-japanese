-- The calendar's composites (ADR-038) over UI/Calendar.lua, replayed from Forever
-- blizzard_calendar/mainline/blizzard_calendar.lua: FULLDATE on the date labels (lua:2824, 3438) and the day / invite
-- tooltips (lua:2123, 2706), the creator lines (lua:2822, 3579), the event type line (lua:2809), the day tooltip's
-- title / signed-up lines (lua:2155–2180), the day buttons' raid lockout titles (lua:1571–1582) and the event picker
-- (lua:4349), the holiday and raid descriptions (lua:2479–2482, 2524–2529). Names, titles and times stay as written.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Calendar.lua"

local UI = {
  FULLDATE = { "%1$s, %2$s %3$d %4$d", "%4$d年%2$s%3$d日(%1$s)" },
  WEEKDAY_THURSDAY = { "Thursday", "木曜日" }, MONTH_SEPTEMBER = { "September", "9月" },
  CALENDAR_EVENT_CREATORNAME = { "Created by %s", "作成者: %s" },
  CALENDAR_ANNOUNCEMENT_CREATEDBY_PLAYER = { "Created by %s", "作成者: %s" },
  CALENDAR_EVENT_INVITEDBY_PLAYER = { "Invited by %s", "招待者: %s" },
  CALENDAR_VIEW_EVENTTYPE = { "%1$s - %2$s", "%1$s - %2$s" }, CALENDAR_TYPE_RAID = { "Raid", "レイド" },
  CALENDAR_EVENTNAME_FORMAT_RAID_LOCKOUT = { "%s Unlocks", "%sのロック解除" },
  CALENDAR_EVENTNAME_FORMAT_START = { "%s Begins", "%s開始" },
  CALENDAR_EVENTNAME_FORMAT_RAID_RESET = { "%s Resets", "%sのリセット" },
  CALENDAR_SIGNEDUP_FOR_GUILDEVENT_WITH_STATUS = { "Signed up (%s)", "参加登録済み(%s)" },
  CALENDAR_STATUS_TENTATIVE = { "Tentative", "仮承諾" },
  CALENDAR_HOLIDAYFRAME_BEGINSENDS = { "%1$s|n|nBegins: %2$s %3$s|nEnds: %4$s %5$s",
    "%1$s|n|n開始: %2$s %3$s|n終了: %4$s %5$s" },
  CALENDAR_RAID_LOCKOUT_DESCRIPTION = { "Your %1$s instance unlocks at %2$s.", "%1$sのインスタンスは%2$sに解除されます。" },
  CALENDAR_TOOLTIP_INVITE_RESPONDED = { "Responded on:", "返答日時:" },
}

local function fs(text) return Stub.fontString(text or "") end

-- The day's events as C_Calendar.GetDayEvent returns them (blizzard_calendar.lua:1553, 2092, 4316); day 12 of the
-- current month. A guild event and a player's event whose typed titles look like the event-name formats.
local EVENTS = {
  { calendarType = "HOLIDAY", sequenceType = "START", title = "Darkmoon Faire" },
  { calendarType = "GUILD_EVENT", sequenceType = "", title = "Raid Night Begins" },
  { calendarType = "RAID_LOCKOUT", sequenceType = "", title = "Molten Core", difficultyName = "" },
  { calendarType = "PLAYER", sequenceType = "", title = "Onyxia Resets" },
  { calendarType = "COMMUNITY_EVENT", sequenceType = "", title = "Onyxia Unlocks" },
}
local function nameFormat(event, tooltip) -- CALENDAR_CALENDARTYPE_(TOOLTIP_)NAMEFORMAT, lua:395–452
  if event.calendarType == "HOLIDAY" and tooltip and event.sequenceType == "START" then return "%s Begins" end
  if event.calendarType == "RAID_LOCKOUT" then return "%s Unlocks" end
  if event.calendarType == "RAID_RESET" then return "%s Resets" end
  return "%s"
end

local function loadCalendar()
  local frame = CreateFrame("Frame", "CalendarFrame")
  frame.FilterButton = CreateFrame("DropdownButton")
  frame.FilterButton.Text = fs("")
  function frame.FilterButton.UpdateText() end
  for _, n in ipairs({ "CalendarViewEventTypeName", "CalendarViewEventCreatorName", "CalendarViewEventDateLabel",
    "CalendarCreateEventCreatorName", "CalendarCreateEventDateLabel" }) do Stub.namedFontString(n, "") end
  local holiday = CreateFrame("Frame", "CalendarViewHolidayFrame")
  holiday.ScrollingFont = fs("")
  local raid = CreateFrame("Frame", "CalendarViewRaidFrame")
  raid.ScrollingFont = fs("")
  for i = 1, 42 do
    local b = CreateFrame("Button", "CalendarDayButton" .. i)
    b.day, b.monthOffset = i, 0
  end
  for i = 1, 4 do
    CreateFrame("Button", "CalendarDayButton3EventButton" .. i)
    Stub.namedFontString("CalendarDayButton3EventButton" .. i .. "Text1", "")
  end
  _G.C_Calendar = {
    GetNumDayEvents = function(_, day) return day == 12 and #EVENTS or 0 end,
    GetDayEvent = function(_, day, i) return (day == 12 or day == 3) and EVENTS[i] or nil end,
  }
  _G.GetDungeonNameWithDifficulty = function(name) return name end
  -- CalendarDayButton_OnEnter (lua:2076–2186): the date, then each event's formatted title and time
  _G.CalendarDayButton_OnEnter = function(self)
    local tt = _G.GameTooltip
    tt:SetOwner(self)
    tt:ClearLines()
    tt:AddLine("Thursday, September 25 2026")
    for _, event in ipairs(EVENTS) do
      tt:AddLine(" ")
      tt:AddDoubleLine(string.format(nameFormat(event, true), event.title), "8:00 PM")
      if event.calendarType == "GUILD_EVENT" then tt:AddLine("Invited by Thrall") end
    end
    tt:AddLine("Signed up (Tentative)")
    tt:Show()
  end
  _G.CalendarViewEventFrame_Update = function(ev)
    _G.CalendarViewEventTypeName:SetText("Raid - Molten Core")
    _G.CalendarViewEventCreatorName:SetText(string.format(UI.CALENDAR_EVENT_CREATORNAME[1], ev or "Thrall"))
    _G.CalendarViewEventDateLabel:SetText("Thursday, September 25 2026")
  end
  _G.CalendarCreateEventFrame_Update = function()
    _G.CalendarCreateEventCreatorName:SetText("Created by Jaina")
    _G.CalendarCreateEventDateLabel:SetText("Thursday, September 25 2026")
  end
  -- the day's first four events, each button recording its eventIndex (lua:1547–1599)
  _G.CalendarFrame_UpdateDayEvents = function(index)
    for i = 1, 4 do
      local event = EVENTS[i + 1]
      _G["CalendarDayButton" .. index .. "EventButton" .. i].eventIndex = i + 1
      _G["CalendarDayButton" .. index .. "EventButton" .. i .. "Text1"]:SetText(
        string.format(nameFormat(event, false), event.title))
    end
  end
  _G.CalendarEventPickerFrame = { dayButton = _G.CalendarDayButton12 }
  _G.CalendarEventPickerFrame_InitButton = function(button, elementData) -- lua:4310–4349
    local event = EVENTS[elementData.index]
    button.Title:SetText(string.format(nameFormat(event, false), event.title))
  end
  _G.CalendarViewHolidayFrame_Update = function()
    holiday.ScrollingFont:SetText("The Faire is in town. Come!|n|nBegins: 9/25 8:00 AM|nEnds: 10/2 11:59 PM")
  end
  _G.CalendarViewRaidFrame_Update = function()
    raid.ScrollingFont:SetText("Your Molten Core instance unlocks at 8:00 AM.")
  end
  Stub.loadedAddons.Blizzard_Calendar = true
  return frame
end

local GLOBALS = { "CalendarFrame", "CalendarViewEventTypeName", "CalendarViewEventCreatorName",
  "CalendarViewEventDateLabel", "CalendarCreateEventCreatorName", "CalendarCreateEventDateLabel",
  "CalendarViewHolidayFrame", "CalendarViewRaidFrame", "CalendarViewEventFrame_Update",
  "CalendarCreateEventFrame_Update", "CalendarFrame_UpdateDayEvents", "CalendarEventPickerFrame_InitButton",
  "CalendarViewHolidayFrame_Update", "CalendarViewRaidFrame_Update", "C_Calendar", "GetDungeonNameWithDifficulty",
  "CalendarDayButton_OnEnter", "CalendarEventPickerFrame" }
for i = 1, 42 do GLOBALS[#GLOBALS + 1] = "CalendarDayButton" .. i end
for i = 1, 4 do
  GLOBALS[#GLOBALS + 1] = "CalendarDayButton3EventButton" .. i
  GLOBALS[#GLOBALS + 1] = "CalendarDayButton3EventButton" .. i .. "Text1"
end

describe("the calendar's composites on Forever", function()
  local WFJ

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    loadCalendar()
    assert.is_true(WFJ.Calendar.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
  end)

  it("FULLDATE is a Japanese date; the creator's name and the event name are kept; Alt shows English", function()
    _G.CalendarViewEventFrame_Update()
    assert.are.equal("2026年9月25日(木曜日)", _G.CalendarViewEventDateLabel:GetText())
    assert.are.equal("作成者: Thrall", _G.CalendarViewEventCreatorName:GetText())
    assert.are.equal("レイド - Molten Core", _G.CalendarViewEventTypeName:GetText())
    _G.CalendarCreateEventFrame_Update()
    assert.are.equal("作成者: Jaina", _G.CalendarCreateEventCreatorName:GetText())
    assert.are.equal("2026年9月25日(木曜日)", _G.CalendarCreateEventDateLabel:GetText())
    alt(true)
    assert.are.equal("Thursday, September 25 2026", _G.CalendarViewEventDateLabel:GetText())
    assert.are.equal("Created by Thrall", _G.CalendarViewEventCreatorName:GetText())
    alt(false)
    _G.CalendarViewEventFrame_Update("Created by Bob") -- a name that is itself the template's English
    assert.are.equal("作成者: Created by Bob", _G.CalendarViewEventCreatorName:GetText())
  end)

  it("the day tooltip: date, a holiday's and a lockout's title lines and the creator line; a guild / player / "
    .. "community event's typed title stays byte-identical", function()
    _G.CalendarDayButton_OnEnter(_G.CalendarDayButton12)
    local function line(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
    assert.are.equal("2026年9月25日(木曜日)", line(1))
    assert.are.equal("Darkmoon Faire開始", line(3)) -- a HOLIDAY's START
    assert.are.equal("8:00 PM", _G.GameTooltipTextRight3:GetText())
    assert.are.equal("Raid Night Begins", line(5)) -- a GUILD_EVENT typed "Raid Night Begins"
    assert.are.equal("招待者: Thrall", line(6))
    assert.are.equal("Molten Coreのロック解除", line(8)) -- a RAID_LOCKOUT
    assert.are.equal("Onyxia Resets", line(10)) -- a PLAYER event
    assert.are.equal("Onyxia Unlocks", line(12)) -- a COMMUNITY_EVENT
    assert.are.equal("参加登録済み(仮承諾)", line(13))
    alt(true)
    assert.are.equal("Darkmoon Faire Begins", line(3))
    alt(false)
    assert.are.equal("Darkmoon Faire開始", line(3))
    -- a community event typed exactly like the lockout's line: the two cannot be told apart, both stay English
    EVENTS[6] = { calendarType = "COMMUNITY_EVENT", sequenceType = "", title = "Molten Core Unlocks" }
    _G.CalendarDayButton_OnEnter(_G.CalendarDayButton12)
    EVENTS[6] = nil
    assert.are.equal("Molten Core Unlocks", line(8))
    assert.are.equal("Molten Core Unlocks", line(14))
    assert.are.equal("Darkmoon Faire開始", line(3))
  end)

  it("day buttons and the event picker: a raid lockout's title translates; a guild / player / community event "
    .. "titled like one stays", function()
    _G.CalendarFrame_UpdateDayEvents(3)
    assert.are.equal("Raid Night Begins", _G.CalendarDayButton3EventButton1Text1:GetText())
    assert.are.equal("Molten Coreのロック解除", _G.CalendarDayButton3EventButton2Text1:GetText())
    assert.are.equal("Onyxia Resets", _G.CalendarDayButton3EventButton3Text1:GetText())
    assert.are.equal("Onyxia Unlocks", _G.CalendarDayButton3EventButton4Text1:GetText())
    local button = { Title = fs("") }
    _G.CalendarEventPickerFrame_InitButton(button, { index = 3 })
    assert.are.equal("Molten Coreのロック解除", button.Title:GetText())
    alt(true)
    assert.are.equal("Molten Core Unlocks", button.Title:GetText())
    alt(false)
    _G.CalendarEventPickerFrame_InitButton(button, { index = 5 }) -- the pooled button reused for a community event
    assert.are.equal("Onyxia Unlocks", button.Title:GetText())
    _G.CalendarEventPickerFrame_InitButton(button, { index = 4 })
    assert.are.equal("Onyxia Resets", button.Title:GetText())
  end)

  it("the holiday and raid descriptions: the description, dates and times kept", function()
    _G.CalendarViewHolidayFrame_Update()
    assert.are.equal("The Faire is in town. Come!|n|n開始: 9/25 8:00 AM|n終了: 10/2 11:59 PM",
      _G.CalendarViewHolidayFrame.ScrollingFont:GetText())
    _G.CalendarViewRaidFrame_Update()
    assert.are.equal("Molten Coreのインスタンスは8:00 AMに解除されます。", _G.CalendarViewRaidFrame.ScrollingFont:GetText())
  end)
end)

-- CALENDAR_HOLIDAYFRAME_BEGINSENDS's first argument is a `holidayDescription` (ADR-042): a HolidayDescription
-- row's Japanese inside the filled template when the description is one (without the row it stays as written, above).
describe("the calendar's holiday description", function()
  local WFJ

  local ROWS = {}
  for k, v in pairs(UI) do ROWS[k] = v end
  ROWS["HolidayDescription:479"] = { "The Faire is in town. Come!", "移動遊園地がやって来た。おいで！" }
  local TEXT = "The Faire is in town. Come!|n|nBegins: 9/25 8:00 AM|nEnds: 10/2 11:59 PM"

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, ROWS)
    loadCalendar()
    assert.is_true(WFJ.Calendar.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
  end)

  it("a HolidayDescription row's Japanese fills the template, the dates kept; Alt shows the English", function()
    local sf = _G.CalendarViewHolidayFrame.ScrollingFont
    _G.CalendarViewHolidayFrame_Update()
    assert.are.equal("移動遊園地がやって来た。おいで！|n|n開始: 9/25 8:00 AM|n終了: 10/2 11:59 PM", sf:GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(TEXT, sf:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("移動遊園地がやって来た。おいで！|n|n開始: 9/25 8:00 AM|n終了: 10/2 11:59 PM", sf:GetText())
  end)

  it("a description no row has is kept as written inside the Japanese template", function()
    local sf = _G.CalendarViewHolidayFrame.ScrollingFont
    sf:SetText("Children's Week is here.|n|nBegins: 9/25 8:00 AM|nEnds: 10/2 11:59 PM")
    WFJ.Calendar.onHoliday()
    assert.are.equal("Children's Week is here.|n|n開始: 9/25 8:00 AM|n終了: 10/2 11:59 PM", sf:GetText())
  end)
end)
