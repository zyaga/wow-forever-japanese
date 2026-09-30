-- UI/Calendar.lua: the calendar on Forever (surface "calendar", area "ui", ADR-016). Blizzard_Calendar is
-- load-on-demand; `camelot` loads its mainline files plus camelot/calendarfilterdata.lua (blizzard_calendar.toc).
-- Entry points in the camelot load set: the /calendar command (blizzard_chatframebase/mainline/
-- slashcommandsoverrides.lua:200–206), the guild news' and the Communities calendar's ToggleCalendar
-- (blizzard_communities/guildnews.lua:230, communitiescalendar.lua:70) and the minimap's GameTimeFrame
-- (blizzard_minimap/mainline/gametime.lua). Everything waits through WFJ.LoadOnDemand.when. Without the
-- CalendarFrame.FilterButton parentKey this module sets nothing up.
-- Static labels (XML text= or an OnLoad write; blizzard_calendar/mainline/blizzard_calendar.xml; each restricted):
--   CalendarViewEventTentativeButton CALENDAR_VIEW_EVENT_TENTATIVE (:556), …DeclineButton DECLINE (:563),
--   …RemoveButton CALENDAR_VIEW_EVENT_REMOVE (:573), the two retrieving notes RETRIEVING_INVITE_LIST (:608, :971),
--   CalendarCreateEventInviteButton INVITE (:832), …MassInviteButton CALENDAR_MASS_INVITE (:881), …RaidInviteButton
--   CALENDAR_INVITE_MEMBERS (:911), CalendarMassInviteFrame's unnamed CALENDAR_MASSINVITE_GUILD_HELP (:1008),
--   CalendarMassInviteLevelText LEVEL (:1014), …RankText CALENDAR_MASSINVITE_GUILD_MINRANK (:1024), …AcceptButton
--   ACCEPT (:1078), CalendarEventPickerCloseButton CLOSE (:1140), CalendarTexturePickerCancelButton CANCEL (:1201),
--   …AcceptButton ACCEPT (:1221), CalendarCreateEventAutoApproveCheckText CALENDAR_AUTO_APPROVE and
--   …LockEventCheckText CALENDAR_LOCK_EVENT (OnLoad, blizzard_calendar.lua:3805, 3829); CalendarFrame.FilterButton's
--   own text CALENDAR_FILTERS (lua:1060; its popup entries CALENDAR_FILTER_* are UI/Menus'); CalendarEventPickerFrame's
--   Header CALENDAR_EVENT_PICKER_TITLE (textString, xml:1125; DialogHeaderMixin:OnLoad); the two invite lists' column
--   headers <list>ClassSortButton CLASS and <list>StatusSortButton STATUS (blizzard_calendartemplates.xml:286–311;
--   lists CalendarViewEventInviteList / CalendarCreateEventInviteList, xml:580, 788; the Name column's NAME stays
--   excluded); CalendarCreateEventFrame.AMPMDropdown's own selection TIMEMANAGER_AM / _PM (lua:3272–3290) through
--   Labels.dropdown (the hour and minute dropdowns hold digits).
-- Writers (globals called by name, post-hooked):
--   CalendarFrame_Update → CalendarWeekday<1–7>Name, a WEEKDAY_* word (lua:1284; CALENDAR_WEEKDAY_NAMES,
--     blizzard_framexmlbase/constants.lua:299); CalendarFrame_UpdateTitle → CalendarMonthName, a MONTH_* word
--     (lua:1425; the year beside it is digits);
--   CalendarViewEventFrame_Update → CalendarViewEventTypeName (a CALENDAR_TYPE_* word when the event has no texture
--     name, lua:2818) and the frame's Header (DialogHeaderMixin:Setup → Header.Text, blizzard_sharedxml/shared/dialog/
--     dialogtemplates.lua:10–13): CALENDAR_VIEW_ANNOUNCEMENT / _GUILD_EVENT / _COMMUNITY_EVENT / _EVENT
--     (lua:2862–2873);
--   CalendarViewEvent_SetEventButtons → CalendarViewEventAcceptButton CALENDAR_SIGNUP / ACCEPT (lua:3058, 3076);
--   CalendarCreateEventFrame_Update → its Header CALENDAR_CREATE_* / CALENDAR_EDIT_* (lua:3480–3505, 3586–3598);
--   CalendarCreateEventCreateButton_SetText → CalendarCreateEventCreateButton CALENDAR_CREATE / CALENDAR_UPDATE
--     (lua:3434, 3533, 4078–4081);
--   CalendarTexturePickerTitleFrame_Update → its Header CALENDAR_TEXTURE_PICKER_TITLE_RAID / _DUNGEON (lua:4507–4509).
--   The holiday and raid-lockout frames' Headers are a holiday's / a raid's name (lua:2476, 2522): never hooked.
-- Help tooltips (GameTooltip:SetOwner(self) then SetText): the four response buttons (lua:2902–2942), the two
--   check boxes (xml:766, 782), Mass Invite (xml:905), Invite Members (lua:4044–4046), the class totals (lua:4702);
--   the 42 day buttons CalendarDayButton<N> (created at load, lua:1083–1086): CalendarDayButton_OnEnter writes the
--   date, the event titles and times, CALENDAR_TOOLTIP_ONGOING and, for the player's own events, one of the four
--   *_YOURSELF lines (lua:2076–2186), restricted to those five keys, so titles, dates and names are never matched;
--   the invite list rows (pooled, CreateScrollBoxListLinearView, lua:2609–2610, 3133–3134; walked from each list's
--   ScrollBox initialized-frame callback): CALENDAR_TOOLTIP_INVITE_RESPONDED above a date and a time (lua:2697–2711).
-- The composites (ADR-038), each restricted to its keys (names, titles and times kept as `text`):
--   FULLDATE "%1$s, %2$s %3$d %4$d" (weekday, month, day, year; _CalendarFrame_GetFullDate, lua:670–674) → a Japanese
--     date: CalendarViewEventDateLabel (lua:2824), CalendarCreateEventDateLabel (lua:3438, 3543), the day tooltip's
--     first line (lua:2123) and an invite row's response date (lua:2706);
--   the creator lines CALENDAR_EVENT_CREATORNAME "Created by %s" (CalendarViewEventCreatorName lua:2822,
--     CalendarCreateEventCreatorName lua:3579), only that key, so the name is kept;
--   CALENDAR_VIEW_EVENTTYPE "%1$s - %2$s" on CalendarViewEventTypeName (a CALENDAR_TYPE_* entry and a name, lua:2809);
--   the day tooltip's signed-up lines (CALENDAR_*_BY_PLAYER, CALENDAR_SIGNEDUP_FOR_GUILDEVENT_WITH_STATUS,
--     lua:2155–2180) and its event-title lines (lua:2148–2154);
--   the day buttons' event titles <day>EventButton<1–4>Text1 (CalendarFrame_UpdateDayEvents, lua:1479–1599; max 4,
--     lua:128) and the event picker's Title (CalendarEventPickerFrame_InitButton, lua:4310–4349).
--   Event titles: CALENDAR_CALENDARTYPE_TOOLTIP_NAMEFORMAT / _NAMEFORMAT (lua:395–452) wrap a title in
--     CALENDAR_EVENTNAME_FORMAT_START / _END only for a HOLIDAY's START / END sequence (tooltip only) and in
--     _RAID_LOCKOUT / _RAID_RESET only for a RAID_LOCKOUT / RAID_RESET event; a PLAYER / GUILD_ANNOUNCEMENT /
--     GUILD_EVENT / COMMUNITY_EVENT / SYSTEM title is a plain "%s" the player typed. So a title line is offered those
--     keys only for the event it shows, read back through C_Calendar.GetDayEvent(monthOffset, day, index) the way the
--     client does (lua:2092, 1553, 4316): the day button's eventIndex, the picker button's elementData.index, and for
--     the tooltip the day's events whose formatted title's argument is that line's: "Raid Night Begins" typed for a
--     guild event stays byte-identical.
--   CalendarViewHolidayFrame.ScrollingFont (CALENDAR_HOLIDAYFRAME_BEGINSENDS, the description verbatim, lua:2479–2482)
--     and CalendarViewRaidFrame.ScrollingFont (CALENDAR_RAID_LOCKOUT / _RESET_DESCRIPTION, lua:2524–2529).
-- The two community dropdowns (CalendarCreateEventFrame.CommunityDropdown, CalendarMassInviteFrame's) show
--   SetDefaultText(CALENDER_INVITE_SELECT_COMMUNITY) until a community is picked (mainline/blizzard_calendar.lua:3336,
--   4117): Labels.dropdown restricted to that one key, so a chosen community's name is never matched.
-- Never touched: event titles and descriptions, holiday names, player names, the three EditBoxes whose default text
-- the client reads back (CALENDAR_EVENT_NAME / _DESCRIPTION / CALENDAR_PLAYER_NAME, lua:145–146, 3937–3958).
local _, WFJ = ...
local Calendar = {}
WFJ.Calendar = Calendar

local SURFACE = "calendar"
Calendar.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_Calendar"

Calendar.NEVER_TOUCH = { "CalendarCreateEventTitleEdit", "CalendarCreateEventInviteEdit",
  "CalendarCreateEventDescriptionContainer.ScrollingEditBox", "CalendarViewEventTitle",
  "CalendarViewEventDescriptionContainer.ScrollingFont",
  "CalendarViewHolidayFrame.Header.Text", "CalendarViewRaidFrame.Header.Text", "CalendarYearName" }

-- Static labels: record key → { candidate, the one key it shows }.
local STATIC_LABELS = {
  tentative = { "CalendarViewEventTentativeButton", "CALENDAR_VIEW_EVENT_TENTATIVE" },
  decline = { "CalendarViewEventDeclineButton", "DECLINE" },
  remove = { "CalendarViewEventRemoveButton", "CALENDAR_VIEW_EVENT_REMOVE" },
  viewRetrieving = { "CalendarViewEventFrameRetrievingFrameText", "RETRIEVING_INVITE_LIST" },
  createRetrieving = { "CalendarCreateEventFrameRetrievingFrameText", "RETRIEVING_INVITE_LIST" },
  invite = { "CalendarCreateEventInviteButton", "INVITE" },
  massInvite = { "CalendarCreateEventMassInviteButton", "CALENDAR_MASS_INVITE" },
  raidInvite = { "CalendarCreateEventRaidInviteButton", "CALENDAR_INVITE_MEMBERS" },
  massLevel = { "CalendarMassInviteLevelText", "LEVEL" },
  massRank = { "CalendarMassInviteRankText", "CALENDAR_MASSINVITE_GUILD_MINRANK" },
  massAccept = { "CalendarMassInviteAcceptButton", "ACCEPT" },
  pickerClose = { "CalendarEventPickerCloseButton", "CLOSE" },
  pickerTitle = { "CalendarEventPickerFrame.Header.Text", "CALENDAR_EVENT_PICKER_TITLE" },
  viewClass = { "CalendarViewEventInviteListClassSortButton", "CLASS" },
  viewStatus = { "CalendarViewEventInviteListStatusSortButton", "STATUS" },
  createClass = { "CalendarCreateEventInviteListClassSortButton", "CLASS" },
  createStatus = { "CalendarCreateEventInviteListStatusSortButton", "STATUS" },
  textureCancel = { "CalendarTexturePickerCancelButton", "CANCEL" },
  textureAccept = { "CalendarTexturePickerAcceptButton", "ACCEPT" },
  autoApprove = { "CalendarCreateEventAutoApproveCheckText", "CALENDAR_AUTO_APPROVE" },
  lockEvent = { "CalendarCreateEventLockEventCheckText", "CALENDAR_LOCK_EVENT" },
}
local STATIC_ORDER = {}
for key in pairs(STATIC_LABELS) do STATIC_ORDER[#STATIC_ORDER + 1] = key end
table.sort(STATIC_ORDER)

-- Help-tooltip owners: candidate → the keys its tooltip shows.
local TOOLTIPS = {
  CalendarViewEventAcceptButton = { "CALENDAR_TOOLTIP_SIGNUPBUTTON", "CALENDAR_TOOLTIP_AVAILABLEBUTTON" },
  CalendarViewEventTentativeButton = { "CALENDAR_TOOLTIP_TENTATIVEBUTTON" },
  CalendarViewEventDeclineButton = { "CALENDAR_TOOLTIP_DECLINEBUTTON" },
  CalendarViewEventRemoveButton = { "CALENDAR_TOOLTIP_REMOVESIGNUPBUTTON", "CALENDAR_TOOLTIP_REMOVEBUTTON" },
  CalendarCreateEventAutoApproveCheck = { "CALENDAR_TOOLTIP_AUTOAPPROVE" },
  CalendarCreateEventLockEventCheck = { "CALENDAR_TOOLTIP_LOCKEVENT" },
  CalendarCreateEventMassInviteButton = { "CALENDAR_TOOLTIP_MASSINVITE" },
  CalendarCreateEventRaidInviteButton = { "CALENDAR_TOOLTIP_INVITEMEMBERS_BUTTON_RAID",
    "CALENDAR_TOOLTIP_INVITEMEMBERS_BUTTON_PARTY" },
  CalendarClassTotalsButton = { "CALENDAR_TOOLTIP_INVITE_TOTALS" },
}

local WEEKDAYS = 7 -- CalendarWeekday1Name … CalendarWeekday7Name (Blizzard's own names, lua:1284)
local DAYS = 42 -- CalendarDayButton1 … CalendarDayButton42 (CALENDAR_MAX_DAYS_PER_MONTH, lua:116, 1083–1086)
local DAY_TOOLTIP = { only = { "CALENDAR_TOOLTIP_ONGOING", "CALENDAR_ANNOUNCEMENT_CREATEDBY_YOURSELF",
  "CALENDAR_GUILDEVENT_INVITEDBY_YOURSELF", "CALENDAR_COMMUNITYEVENT_INVITEDBY_YOURSELF",
  "CALENDAR_EVENT_INVITEDBY_YOURSELF", "FULLDATE", "CALENDAR_ANNOUNCEMENT_CREATEDBY_PLAYER",
  "CALENDAR_EVENT_INVITEDBY_PLAYER", "CALENDAR_SIGNEDUP_FOR_GUILDEVENT_WITH_STATUS" } }
local INVITE_ROW_TOOLTIP = { only = { "CALENDAR_TOOLTIP_INVITE_RESPONDED", "FULLDATE" } }
local EVENTS_PER_DAY = 4 -- CALENDAR_DAYBUTTON_MAX_VISIBLE_EVENTS (lua:128)
local DATE = { only = { "FULLDATE" } }
local CREATOR = { only = { "CALENDAR_EVENT_CREATORNAME" } }
local EVENT_NAME = { only = { "CALENDAR_EVENTNAME_FORMAT_RAID_LOCKOUT", "CALENDAR_EVENTNAME_FORMAT_RAID_RESET" } }
-- the event-name key a calendarType / sequenceType wraps its title in (lua:395–452); every other pair is "%s".
-- `button`: the day buttons' and the picker's format (a holiday's start / end is "%s" there, lua:438–443).
local TITLE_KEYS = {
  HOLIDAY = { START = "CALENDAR_EVENTNAME_FORMAT_START", END = "CALENDAR_EVENTNAME_FORMAT_END", button = false },
  RAID_LOCKOUT = { any = "CALENDAR_EVENTNAME_FORMAT_RAID_LOCKOUT", button = true },
  RAID_RESET = { any = "CALENDAR_EVENTNAME_FORMAT_RAID_RESET", button = true },
}
local HOLIDAY = { only = { "CALENDAR_HOLIDAYFRAME_BEGINSENDS" } }
local RAID = { only = { "CALENDAR_RAID_LOCKOUT_DESCRIPTION", "CALENDAR_RAID_RESET_DESCRIPTION" } }
local CANDIDATES = {
  frame = { "CalendarFrame" }, filter = { "CalendarFrame.FilterButton" }, month = { "CalendarMonthName" },
  massInviteFrame = { "CalendarMassInviteFrame" }, typeName = { "CalendarViewEventTypeName" },
  viewHeader = { "CalendarViewEventFrame.Header.Text" }, createHeader = { "CalendarCreateEventFrame.Header.Text" },
  textureHeader = { "CalendarTexturePickerFrame.Header.Text" }, accept = { "CalendarViewEventAcceptButton" },
  createButton = { "CalendarCreateEventCreateButton" }, ampm = { "CalendarCreateEventFrame.AMPMDropdown" },
  createCommunity = { "CalendarCreateEventFrame.CommunityDropdown" },
  massCommunity = { "CalendarMassInviteFrame.CommunityDropdown" },
  viewInvites = { "CalendarViewEventInviteList.ScrollBox" },
  createInvites = { "CalendarCreateEventInviteList.ScrollBox" }, scrollUtil = { "ScrollUtil" },
  viewCreator = { "CalendarViewEventCreatorName" }, createCreator = { "CalendarCreateEventCreatorName" },
  viewDate = { "CalendarViewEventDateLabel" }, createDate = { "CalendarCreateEventDateLabel" },
  holiday = { "CalendarViewHolidayFrame.ScrollingFont" }, raid = { "CalendarViewRaidFrame.ScrollingFont" },
}
-- global writer → the hook target it runs
local WRITERS = { CalendarFrame_Update = "onWeekdays", CalendarFrame_UpdateTitle = "onMonth",
  CalendarViewEventFrame_Update = "onViewEvent", CalendarViewEvent_SetEventButtons = "onAccept",
  CalendarCreateEventFrame_Update = "onCreateEvent", CalendarCreateEventCreateButton_SetText = "onCreateButton",
  CalendarTexturePickerTitleFrame_Update = "onTexturePicker", CalendarFrame_UpdateDayEvents = "onDayEvents",
  CalendarViewHolidayFrame_Update = "onHoliday", CalendarViewRaidFrame_Update = "onRaid",
  CalendarEventPickerFrame_InitButton = "onPickerButton", CalendarDayButton_OnEnter = "onDayTooltip" }

local SELECT_COMMUNITY = { only = { "CALENDER_INVITE_SELECT_COMMUNITY" } }
local WEEKDAY = { only = { "WEEKDAY_SUNDAY", "WEEKDAY_MONDAY", "WEEKDAY_TUESDAY", "WEEKDAY_WEDNESDAY",
  "WEEKDAY_THURSDAY", "WEEKDAY_FRIDAY", "WEEKDAY_SATURDAY" } }
local MONTH = { only = { "MONTH_JANUARY", "MONTH_FEBRUARY", "MONTH_MARCH", "MONTH_APRIL", "MONTH_MAY", "MONTH_JUNE",
  "MONTH_JULY", "MONTH_AUGUST", "MONTH_SEPTEMBER", "MONTH_OCTOBER", "MONTH_NOVEMBER", "MONTH_DECEMBER" } }
local EVENT_TYPE = { only = { "CALENDAR_TYPE_RAID", "CALENDAR_TYPE_DUNGEON", "CALENDAR_TYPE_PVP",
  "CALENDAR_TYPE_MEETING", "CALENDAR_TYPE_OTHER", "CALENDAR_VIEW_EVENTTYPE" } }
local VIEW_HEADER = { only = { "CALENDAR_VIEW_ANNOUNCEMENT", "CALENDAR_VIEW_GUILD_EVENT",
  "CALENDAR_VIEW_COMMUNITY_EVENT", "CALENDAR_VIEW_EVENT" } }
local CREATE_HEADER = { only = { "CALENDAR_CREATE_ANNOUNCEMENT", "CALENDAR_CREATE_GUILD_EVENT",
  "CALENDAR_CREATE_COMMUNITY_EVENT", "CALENDAR_CREATE_EVENT", "CALENDAR_EDIT_ANNOUNCEMENT",
  "CALENDAR_EDIT_GUILD_EVENT", "CALENDAR_EDIT_COMMUNITY_EVENT", "CALENDAR_EDIT_EVENT" } }
local TEXTURE_HEADER = { only = { "CALENDAR_TEXTURE_PICKER_TITLE_RAID", "CALENDAR_TEXTURE_PICKER_TITLE_DUNGEON" } }
local ACCEPT = { only = { "CALENDAR_SIGNUP", "ACCEPT" } }
local CREATE_BUTTON = { only = { "CALENDAR_CREATE", "CALENDAR_UPDATE" } }
local MASS_HELP = "CALENDAR_MASSINVITE_GUILD_HELP"

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  for key, l in pairs(STATIC_LABELS) do Compat.declare(SURFACE, "static." .. key, { l[1] }) end
  for name in pairs(TOOLTIPS) do Compat.declare(SURFACE, "tip." .. name, { name }) end
  for i = 1, WEEKDAYS do Compat.declare(SURFACE, "weekday" .. i, { "CalendarWeekday" .. i .. "Name" }) end
  for i = 1, DAYS do Compat.declare(SURFACE, "day" .. i, { "CalendarDayButton" .. i }) end
end

local function show(recKey, candidate, opts) return WFJ.Labels.show(SURFACE, recKey, get(candidate), nil, opts) end

-- hooksecurefunc targets, one per global writer. Each → the number of dictionary words found.
function Calendar.onWeekdays()
  local n = 0
  for i = 1, WEEKDAYS do n = n + show("weekday" .. i, "weekday" .. i, WEEKDAY) end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

function Calendar.onMonth() return show("month", "month", MONTH) end

function Calendar.onViewEvent()
  return show("typeName", "typeName", EVENT_TYPE) + show("viewHeader", "viewHeader", VIEW_HEADER)
    + show("viewCreator", "viewCreator", CREATOR) + show("viewDate", "viewDate", DATE)
end

-- The day's event `eventIndex` as the client reads it (C_Calendar.GetDayEvent, lua:1553, 2092, 4316). → table | nil
local function dayEvent(dayButton, eventIndex)
  local api = Compat.resolve("C_Calendar")
  if type(dayButton) ~= "table" or type(eventIndex) ~= "number" or type(api) ~= "table"
      or type(api.GetDayEvent) ~= "function" or dayButton.day == nil or dayButton.monthOffset == nil then
    return nil
  end
  local ok, event = pcall(api.GetDayEvent, dayButton.monthOffset, dayButton.day, eventIndex)
  return ok and type(event) == "table" and event or nil
end

-- true when a day button / picker button shows event `event` in a raid lockout / reset format.
local function buttonTitled(event)
  local t = event and TITLE_KEYS[event.calendarType]
  return t ~= nil and t.button
end

-- CalendarFrame_UpdateDayEvents(index, …): the day button's event titles: a raid lockout / reset line only, read from
-- the event each event button records (eventButton.eventIndex, lua:1560); any other event's title is never offered.
function Calendar.onDayEvents(index)
  local day = type(index) == "number" and index or nil
  local n = 0
  for d = day or 1, day or DAYS do
    local dayButton = Compat.resolve("CalendarDayButton" .. d)
    for i = 1, EVENTS_PER_DAY do
      local name = "CalendarDayButton" .. d .. "EventButton" .. i
      local recKey = "event." .. d .. "." .. i
      local eventButton = Compat.resolve(name)
      if buttonTitled(dayEvent(dayButton, type(eventButton) == "table" and eventButton.eventIndex or nil)) then
        n = n + WFJ.Labels.show(SURFACE, recKey, Compat.resolve(name .. "Text1"), nil, EVENT_NAME)
      else
        WFJ.SurfaceState.drop(SURFACE, recKey)
      end
    end
  end
  return n
end

local pickerKey = WFJ.Labels.keyer("picker.") -- a pooled picker button's record key

-- CalendarEventPickerFrame_InitButton(button, elementData): the pooled button's Title, a raid lockout / reset event's
-- only (the event is elementData.index of the picker's day button, lua:4310–4316).
function Calendar.onPickerButton(button, elementData)
  if type(button) ~= "table" or type(button.Title) ~= "table" then return 0 end
  local picker = Compat.resolve("CalendarEventPickerFrame")
  local index = type(elementData) == "table" and elementData.index or nil
  local recKey = pickerKey(button.Title)
  if not buttonTitled(dayEvent(type(picker) == "table" and picker.dayButton or nil, index)) then
    WFJ.SurfaceState.drop(SURFACE, recKey)
    return 0
  end
  return WFJ.Labels.show(SURFACE, recKey, button.Title, nil, EVENT_NAME)
end

-- After CalendarDayButton_OnEnter(dayButton) (post-hook: the day button's OnEnter script calls it by name,
-- blizzard_calendartemplates.xml:129, and so do the event refreshes, lua:2367, 2404): the tooltip's event-title
-- lines. Each of the day's events whose type wraps its title (TITLE_KEYS) admits one line of that key whose `%s` is
-- the title the client wrote (the raw title; a raid's through GetDungeonNameWithDifficulty, lua:2145–2147). A title
-- line that appears more often than such events account for (a guild event typed "Molten Core Unlocks" beside the
-- lockout) cannot be told apart and stays English, every copy. Records are on the help surface, so the tooltip's
-- refit and release are UI/HelpTooltip's. → the number shown
function Calendar.onDayTooltip(dayButton)
  local api = Compat.resolve("C_Calendar")
  if type(dayButton) ~= "table" or type(api) ~= "table" or type(api.GetNumDayEvents) ~= "function" then return 0 end
  local help = WFJ.HelpTooltip
  local tt = Compat.get(help.SURFACE, "tooltip")
  local index = WFJ.UIIndex
  if not index or type(tt) ~= "table" or type(tt.GetOwner) ~= "function" or tt:GetOwner() ~= dayButton
      or type(tt.NumLines) ~= "function" or type(tt.GetName) ~= "function" then return 0 end
  local ok, count = pcall(api.GetNumDayEvents, dayButton.monthOffset, dayButton.day)
  local expected, keys = {}, {}
  local withDifficulty = Compat.resolve("GetDungeonNameWithDifficulty")
  for i = 1, ok and type(count) == "number" and count or 0 do
    local event = dayEvent(dayButton, i)
    local t = event and TITLE_KEYS[event.calendarType]
    local key = t and (t.any or t[event.sequenceType])
    local title = key and event.title
    if key and t.any and type(withDifficulty) == "function" then
      local okName, name = pcall(withDifficulty, title, event.difficultyName)
      title = okName and name or nil
    end
    if type(title) == "string" then
      local id = key .. "\0" .. title
      if not expected[id] then keys[#keys + 1] = key end
      expected[id] = (expected[id] or 0) + 1
    end
  end
  if #keys == 0 then return 0 end
  local name, found, seen = tt:GetName(), {}, {}
  for i = 1, tt:NumLines() or 0 do
    local fs = Compat.resolve(name .. "TextLeft" .. i)
    local text = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
    local key, args
    if type(text) == "string" and text ~= "" then key, args = index:matchOnly(text, keys) end
    local id = key and type(args) == "table" and type(args[1]) == "string" and key .. "\0" .. args[1]
    if id and expected[id] then
      found[#found + 1] = { i = i, fs = fs, key = key, args = args, id = id }
      seen[id] = (seen[id] or 0) + 1
    end
  end
  local n = 0
  for _, f in ipairs(found) do
    if seen[f.id] <= expected[f.id] then
      n = n + WFJ.Labels.showArgs(help.SURFACE, "L" .. f.i, f.fs, f.key, f.args, help.refit)
    end
  end
  if n > 0 then help.refit() end
  return n
end

function Calendar.onHoliday() return show("holiday", "holiday", HOLIDAY) end

function Calendar.onRaid() return show("raid", "raid", RAID) end

function Calendar.onAccept() return show("accept", "accept", ACCEPT) end

function Calendar.onCreateEvent()
  return show("createHeader", "createHeader", CREATE_HEADER) + show("createCreator", "createCreator", CREATOR)
    + show("createDate", "createDate", DATE)
end

function Calendar.onCreateButton() return show("createButton", "createButton", CREATE_BUTTON) end

function Calendar.onTexturePicker() return show("textureHeader", "textureHeader", TEXTURE_HEADER) end

-- The labels the client writes once at load and the filter button's own text.
-- HookScript target (CalendarFrame OnShow). → the number of dictionary words found.
function Calendar.showStatic()
  local items = {}
  for _, key in ipairs(STATIC_ORDER) do
    items[#items + 1] = { key, get("static." .. key), { only = { STATIC_LABELS[key][2] } } }
  end
  items[#items + 1] = { "massHelp", WFJ.Labels.region(get("massInviteFrame"), MASS_HELP), { only = { MASS_HELP } } }
  local n = WFJ.Labels.showAll(SURFACE, items)
  n = n + WFJ.Labels.dropdown(SURFACE, "filter", get("filter"))
  n = n + WFJ.Labels.dropdown(SURFACE, "createCommunity", get("createCommunity"), SELECT_COMMUNITY)
  n = n + WFJ.Labels.dropdown(SURFACE, "massCommunity", get("massCommunity"), SELECT_COMMUNITY)
  return n + WFJ.Labels.dropdown(SURFACE, "ampm", get("ampm"))
end

-- One pooled invite-list row (ScrollUtil's initialized-frame callback: (owner, frame, elementData) for a new row,
-- (frame, elementData) for the iterateExisting pass). Returns nothing: ForEachFrame stops at the first truthy return.
function Calendar.onInviteRow(a, b)
  local row = a
  if a == Calendar then row = b end
  if type(row) == "table" then WFJ.HelpTooltip.register(row, INVITE_ROW_TOOLTIP) end
end

local hooked = false

-- Blizzard_Calendar's part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function Calendar.setup()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if type(frame) ~= "table" or type(get("filter")) ~= "table" then return false end -- not the mainline calendar
  WFJ.Labels.forbidNames(Calendar.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  Calendar.showStatic()
  for _, target in pairs(WRITERS) do Calendar[target]() end
  if hooked then return false end
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", Calendar.showStatic) end
  for writer, target in pairs(WRITERS) do
    if type(Compat.resolve(writer)) == "function" then hooksecurefunc(writer, Calendar[target]) end
  end
  for name, keys in pairs(TOOLTIPS) do WFJ.HelpTooltip.register(get("tip." .. name), { only = keys }) end
  for i = 1, DAYS do WFJ.HelpTooltip.register(get("day" .. i), DAY_TOOLTIP) end
  local util = get("scrollUtil")
  if type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    for _, key in ipairs({ "viewInvites", "createInvites" }) do
      local box = get(key)
      if type(box) == "table" then util.AddInitializedFrameCallback(box, Calendar.onInviteRow, Calendar, true) end
    end
  end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- was set up now; false while Blizzard_Calendar is not loaded or is not the mainline calendar.
function Calendar.init()
  declare()
  local done = false
  WFJ.LoadOnDemand.when(ADDON, function() done = Calendar.setup() end)
  return done
end
