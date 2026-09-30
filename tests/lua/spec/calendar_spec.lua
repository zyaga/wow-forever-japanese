-- UI/Calendar.lua over a CalendarFrame replayed from camelot
-- blizzard_calendar/mainline/blizzard_calendar.xml (the static buttons and labels, the FilterButton at :285) and
-- blizzard_calendar.lua (the weekday row :1284, the month title :1425, the view-event type and header :2818,
-- :2862–2873, the accept button :3058 / :3076, the create button :4078–4081, the texture picker header :4507–4509).
-- Event titles, holiday names and player names stay as written; the surface waits for Blizzard_Calendar in either
-- load order and leaves a calendar without the mainline FilterButton alone.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Calendar.lua"

local ADDON = "Blizzard_Calendar"

local UI = {
  WEEKDAY_SUNDAY = { "Sunday", "日曜日" }, WEEKDAY_MONDAY = { "Monday", "月曜日" },
  WEEKDAY_TUESDAY = { "Tuesday", "火曜日" }, WEEKDAY_WEDNESDAY = { "Wednesday", "水曜日" },
  WEEKDAY_THURSDAY = { "Thursday", "木曜日" }, WEEKDAY_FRIDAY = { "Friday", "金曜日" },
  WEEKDAY_SATURDAY = { "Saturday", "土曜日" },
  MONTH_JANUARY = { "January", "1月" }, MONTH_MAY = { "May", "5月" },
  CALENDAR_FILTERS = { "Filters", "フィルター" },
  CALENDAR_TYPE_RAID = { "Raid", "レイド" }, CALENDAR_TYPE_DUNGEON = { "Dungeon", "ダンジョン" },
  CALENDAR_VIEW_EVENT = { "View Event", "イベントを表示" },
  CALENDAR_VIEW_GUILD_EVENT = { "View Guild Event", "ギルドイベントを表示" },
  CALENDAR_CREATE_EVENT = { "Create Event", "イベントを作成" },
  CALENDAR_TEXTURE_PICKER_TITLE_RAID = { "Choose a Raid", "レイドを選択" },
  CALENDAR_SIGNUP = { "Sign Up", "参加登録" }, ACCEPT = { "Accept", "承諾" },
  CALENDAR_CREATE = { "Create", "作成" }, CALENDAR_UPDATE = { "Update", "更新" },
  CALENDAR_VIEW_EVENT_TENTATIVE = { "Tentative", "仮承諾" }, DECLINE = { "Decline", "辞退" },
  CALENDAR_VIEW_EVENT_REMOVE = { "Remove", "削除" }, INVITE = { "Invite", "招待" },
  CALENDAR_MASS_INVITE = { "Mass Invite", "一括招待" },
  CALENDAR_MASSINVITE_GUILD_HELP = { "Invite guild members who meet the criteria:",
    "条件を満たすギルドメンバーを招待します:" },
  LEVEL = { "Level", "レベル" }, CLOSE = { "Close", "閉じる" },
  CALENDAR_TOOLTIP_TENTATIVEBUTTON = { "Mark yourself as tentative for this event.", "このイベントに仮承諾します。" },
  CALENDAR_EVENT_PICKER_TITLE = { "Select an Event", "イベントを選択" }, STATUS = { "Status", "状態" },
  CLASS = { "Class", "クラス" }, TIMEMANAGER_AM = { "AM", "午前" }, TIMEMANAGER_PM = { "PM", "午後" },
  CALENDER_INVITE_SELECT_COMMUNITY = { "Select Community", "コミュニティを選択" },
  CALENDAR_TOOLTIP_ONGOING = { "Ongoing", "開催中" },
  CALENDAR_EVENT_INVITEDBY_YOURSELF = { "This is your event", "あなたのイベントです" },
  CALENDAR_TOOLTIP_INVITE_RESPONDED = { "Responded on:", "返答日時:" },
}

local function en(key) return _G[key] end
local function fs(text) return Stub.fontString(text or "") end
local function header(text)
  local h = { Text = fs(text) }
  function h.Setup(self, t) self.Text:SetText(t) end -- DialogHeaderMixin:Setup (dialogtemplates.lua:10–13)
  return h
end

local WEEKDAY_KEYS = { "WEEKDAY_SUNDAY", "WEEKDAY_MONDAY", "WEEKDAY_TUESDAY", "WEEKDAY_WEDNESDAY",
  "WEEKDAY_THURSDAY", "WEEKDAY_FRIDAY", "WEEKDAY_SATURDAY" }

-- `mainline`: the calendar carries its FilterButton parentKey (false replays a calendar without it).
local function loadCalendar(mainline)
  local frame = CreateFrame("Frame", "CalendarFrame")
  frame.viewedMonth = 1
  if mainline then
    local filter = CreateFrame("DropdownButton")
    filter.name = "FilterButton"
    filter.Text = fs(en("CALENDAR_FILTERS"))
    function filter.UpdateText(self) self.Text.text = en("CALENDAR_FILTERS") end
    frame.FilterButton = filter
  end
  for i = 1, 7 do Stub.namedFontString("CalendarWeekday" .. i .. "Name", "") end
  Stub.namedFontString("CalendarMonthName", "")
  Stub.namedFontString("CalendarYearName", "2026")
  Stub.namedFontString("CalendarViewEventTypeName", "")
  Stub.namedFontString("CalendarViewEventTitle", "Close") -- an event title the player typed
  Stub.namedFontString("CalendarViewEventCreatorName", "Invite") -- a player name
  local view = CreateFrame("Frame", "CalendarViewEventFrame")
  view.Header = header("")
  local create = CreateFrame("Frame", "CalendarCreateEventFrame")
  create.Header = header("")
  local picker = CreateFrame("Frame", "CalendarTexturePickerFrame")
  picker.Header = header("")
  local holiday = CreateFrame("Frame", "CalendarViewHolidayFrame")
  holiday.Header = header("Invite") -- a holiday name, never hooked (lua:2476)
  Stub.button("CalendarViewEventAcceptButton", en("ACCEPT"))
  Stub.button("CalendarViewEventTentativeButton", en("CALENDAR_VIEW_EVENT_TENTATIVE"))
  Stub.button("CalendarViewEventDeclineButton", en("DECLINE"))
  Stub.button("CalendarViewEventRemoveButton", en("CALENDAR_VIEW_EVENT_REMOVE"))
  Stub.button("CalendarCreateEventInviteButton", en("INVITE"))
  Stub.button("CalendarCreateEventMassInviteButton", en("CALENDAR_MASS_INVITE"))
  Stub.button("CalendarCreateEventCreateButton", en("CALENDAR_CREATE"))
  Stub.button("CalendarEventPickerCloseButton", en("CLOSE"))
  local mass = CreateFrame("Frame", "CalendarMassInviteFrame")
  mass:addRegion(fs(en("CALENDAR_MASSINVITE_GUILD_HELP")))
  Stub.namedFontString("CalendarMassInviteLevelText", en("LEVEL"))
  local picker2 = CreateFrame("Frame", "CalendarEventPickerFrame")
  picker2.Header = header(en("CALENDAR_EVENT_PICKER_TITLE"))
  Stub.button("CalendarViewEventInviteListStatusSortButton", en("STATUS"))
  Stub.button("CalendarViewEventInviteListClassSortButton", en("CLASS"))
  local ampm = CreateFrame("DropdownButton")
  ampm.name = "AMPMDropdown"
  ampm.Text = fs(en("TIMEMANAGER_AM"))
  function ampm.UpdateText(self) self.Text.text = en(self.pm and "TIMEMANAGER_PM" or "TIMEMANAGER_AM") end
  create.AMPMDropdown = ampm
  -- the community dropdown's default text (blizzard_calendar.lua:3336) or a chosen community's name
  local community = CreateFrame("DropdownButton")
  community.Text = fs(en("CALENDER_INVITE_SELECT_COMMUNITY"))
  function community.UpdateText(self) self.Text.text = self.chosen or en("CALENDER_INVITE_SELECT_COMMUNITY") end
  create.CommunityDropdown = community
  for i = 1, 42 do CreateFrame("Button", "CalendarDayButton" .. i) end
  local list = CreateFrame("Frame", "CalendarViewEventInviteList")
  list.ScrollBox = Stub.scrollBox()
  local edit = CreateFrame("EditBox", "CalendarCreateEventTitleEdit")
  edit:SetText("Invite")
  -- the writers (blizzard_calendar.lua), replayed
  _G.CalendarFrame_UpdateTitle = function()
    _G.CalendarMonthName:SetText(frame.viewedMonth == 5 and en("MONTH_MAY") or en("MONTH_JANUARY"))
  end
  _G.CalendarFrame_Update = function()
    _G.CalendarFrame_UpdateTitle()
    for i = 1, 7 do _G["CalendarWeekday" .. i .. "Name"]:SetText(en(WEEKDAY_KEYS[i])) end
  end
  _G.CalendarViewEventFrame_Update = function()
    _G.CalendarViewEventTypeName:SetText(en(view.raid and "CALENDAR_TYPE_RAID" or "CALENDAR_TYPE_DUNGEON"))
    view.Header:Setup(en(view.guild and "CALENDAR_VIEW_GUILD_EVENT" or "CALENDAR_VIEW_EVENT"))
  end
  _G.CalendarViewEvent_SetEventButtons = function(signup)
    _G.CalendarViewEventAcceptButton:SetText(en(signup and "CALENDAR_SIGNUP" or "ACCEPT"))
  end
  _G.CalendarCreateEventCreateButton_SetText = function(text) _G.CalendarCreateEventCreateButton:SetText(text) end
  _G.CalendarCreateEventFrame_Update = function()
    create.Header:Setup(en("CALENDAR_CREATE_EVENT"))
    _G.CalendarCreateEventCreateButton_SetText(en(create.mode == "edit" and "CALENDAR_UPDATE" or "CALENDAR_CREATE"))
  end
  _G.CalendarTexturePickerTitleFrame_Update = function()
    picker.Header:Setup(en("CALENDAR_TEXTURE_PICKER_TITLE_RAID"))
  end
  _G.CalendarFrame_Update()
  Stub.loadedAddons[ADDON] = true
  return frame
end

local GLOBALS = { "CalendarFrame", "CalendarMonthName", "CalendarYearName", "CalendarViewEventTypeName",
  "CalendarViewEventTitle", "CalendarViewEventCreatorName", "CalendarViewEventFrame", "CalendarCreateEventFrame",
  "CalendarTexturePickerFrame", "CalendarViewHolidayFrame", "CalendarViewEventAcceptButton",
  "CalendarViewEventTentativeButton", "CalendarViewEventDeclineButton", "CalendarViewEventRemoveButton",
  "CalendarCreateEventInviteButton", "CalendarCreateEventMassInviteButton", "CalendarCreateEventCreateButton",
  "CalendarEventPickerCloseButton", "CalendarMassInviteFrame", "CalendarMassInviteLevelText",
  "CalendarCreateEventTitleEdit", "CalendarFrame_UpdateTitle", "CalendarFrame_Update",
  "CalendarViewEventFrame_Update", "CalendarViewEvent_SetEventButtons", "CalendarCreateEventCreateButton_SetText",
  "CalendarCreateEventFrame_Update", "CalendarTexturePickerTitleFrame_Update", "CalendarEventPickerFrame",
  "CalendarViewEventInviteListStatusSortButton", "CalendarViewEventInviteListClassSortButton",
  "CalendarViewEventInviteList" }
for i = 1, 7 do GLOBALS[#GLOBALS + 1] = "CalendarWeekday" .. i .. "Name" end
for i = 1, 42 do GLOBALS[#GLOBALS + 1] = "CalendarDayButton" .. i end

describe("the calendar on Forever", function()
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
      loadCalendar(true)
      assert.is_true(WFJ.Calendar.init())
    else
      assert.is_false(WFJ.Calendar.init()) -- waits for the addon
      loadCalendar(true)
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, name in ipairs(GLOBALS) do _G[name] = nil end
  end)

  for _, order in ipairs({ { true, "loaded before init" }, { false, "loaded on demand" } }) do
    describe("Blizzard_Calendar " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("weekdays, the month and the filter button are Japanese; the year is digits; Alt shows English", function()
        assert.are.equal("日曜日", _G.CalendarWeekday1Name:GetText())
        assert.are.equal("土曜日", _G.CalendarWeekday7Name:GetText())
        assert.are.equal("1月", _G.CalendarMonthName:GetText())
        assert.are.equal("2026", _G.CalendarYearName:GetText())
        assert.are.equal("フィルター", _G.CalendarFrame.FilterButton.Text:GetText())
        alt(true)
        assert.are.equal("Sunday", _G.CalendarWeekday1Name:GetText())
        assert.are.equal("January", _G.CalendarMonthName:GetText())
        alt(false)
        assert.are.equal("日曜日", _G.CalendarWeekday1Name:GetText())
      end)

      it("the month follows its writer when the page turns", function()
        _G.CalendarFrame.viewedMonth = 5
        _G.CalendarFrame_UpdateTitle()
        assert.are.equal("5月", _G.CalendarMonthName:GetText())
      end)

      it("static buttons and labels, and the mass-invite help, are Japanese", function()
        assert.are.equal("仮承諾", _G.CalendarViewEventTentativeButton:GetText())
        assert.are.equal("辞退", _G.CalendarViewEventDeclineButton:GetText())
        assert.are.equal("削除", _G.CalendarViewEventRemoveButton:GetText())
        assert.are.equal("招待", _G.CalendarCreateEventInviteButton:GetText())
        assert.are.equal("一括招待", _G.CalendarCreateEventMassInviteButton:GetText())
        assert.are.equal("閉じる", _G.CalendarEventPickerCloseButton:GetText())
        assert.are.equal("レベル", _G.CalendarMassInviteLevelText:GetText())
        assert.are.equal("条件を満たすギルドメンバーを招待します:", (_G.CalendarMassInviteFrame:GetRegions()):GetText())
      end)

      it("the view-event, create-event and texture-picker writers are followed", function()
        local view = _G.CalendarViewEventFrame
        view.raid, view.guild = true, true
        _G.CalendarViewEventFrame_Update()
        assert.are.equal("レイド", _G.CalendarViewEventTypeName:GetText())
        assert.are.equal("ギルドイベントを表示", view.Header.Text:GetText())
        _G.CalendarViewEvent_SetEventButtons(true)
        assert.are.equal("参加登録", _G.CalendarViewEventAcceptButton:GetText())
        _G.CalendarViewEvent_SetEventButtons(false)
        assert.are.equal("承諾", _G.CalendarViewEventAcceptButton:GetText())
        _G.CalendarCreateEventFrame.mode = "edit"
        _G.CalendarCreateEventFrame_Update()
        assert.are.equal("イベントを作成", _G.CalendarCreateEventFrame.Header.Text:GetText())
        assert.are.equal("更新", _G.CalendarCreateEventCreateButton:GetText())
        _G.CalendarTexturePickerTitleFrame_Update()
        assert.are.equal("レイドを選択", _G.CalendarTexturePickerFrame.Header.Text:GetText())
      end)

      it("event titles, player and holiday names and the title box stay as written", function()
        assert.are.equal("Close", _G.CalendarViewEventTitle:GetText())
        assert.are.equal("Invite", _G.CalendarViewEventCreatorName:GetText())
        assert.are.equal("Invite", _G.CalendarViewHolidayFrame.Header.Text:GetText())
        assert.are.equal("Invite", _G.CalendarCreateEventTitleEdit:GetText())
        assert.is_true(WFJ.Labels.forbidden(_G.CalendarViewEventTitle))
        assert.are.equal(0, WFJ.Labels.show("calendar", "x", _G.CalendarViewEventTitle))
        assert.are.equal("Close", _G.CalendarViewEventTitle:GetText())
      end)

      it("a response button's help tooltip translates", function()
        local tt = _G.GameTooltip
        tt:SetOwner(_G.CalendarViewEventTentativeButton)
        tt:SetText(en("CALENDAR_TOOLTIP_TENTATIVEBUTTON"))
        tt:Show()
        assert.are.equal("このイベントに仮承諾します。", _G.GameTooltipTextLeft1:GetText())
      end)

      it("the event picker title, the invite list headers and the AM / PM selection are Japanese", function()
        assert.are.equal("イベントを選択", _G.CalendarEventPickerFrame.Header.Text:GetText())
        assert.are.equal("状態", _G.CalendarViewEventInviteListStatusSortButton:GetText())
        assert.are.equal("クラス", _G.CalendarViewEventInviteListClassSortButton:GetText())
        local ampm = _G.CalendarCreateEventFrame.AMPMDropdown
        assert.are.equal("午前", ampm.Text:GetText())
        ampm.pm = true
        ampm:UpdateText()
        assert.are.equal("午後", ampm.Text:GetText())
      end)

      it("the community dropdown's default text is Japanese; a chosen community's name is not",
        function()
          local dd = _G.CalendarCreateEventFrame.CommunityDropdown
          assert.are.equal("コミュニティを選択", dd.Text:GetText())
          dd.chosen = "AM" -- a community named like another dictionary word stays as written
          dd:UpdateText()
          assert.are.equal("AM", dd.Text:GetText())
          dd.chosen = nil
          dd:UpdateText()
          assert.are.equal("コミュニティを選択", dd.Text:GetText())
        end)

      it("a day button's tooltip translates its labels; event titles and dates stay as written", function()
        local tt = _G.GameTooltip
        tt:SetOwner(_G.CalendarDayButton12)
        tt:ClearLines()
        tt:AddLine("Sunday, May 10 2026") -- FULLDATE: a date, never matched
        tt:AddLine(" ")
        tt:AddLine(en("CALENDAR_TOOLTIP_ONGOING"))
        tt:AddDoubleLine("Close", "10:00") -- an event the player named "Close"
        tt:AddLine(en("CALENDAR_EVENT_INVITEDBY_YOURSELF"))
        tt:Show()
        assert.are.equal("Sunday, May 10 2026", _G.GameTooltipTextLeft1:GetText())
        assert.are.equal("開催中", _G.GameTooltipTextLeft3:GetText())
        assert.are.equal("Close", _G.GameTooltipTextLeft4:GetText())
        assert.are.equal("あなたのイベントです", _G.GameTooltipTextLeft5:GetText())
      end)

      it("an invite row's tooltip translates its label; the row is found through the list's pool", function()
        local row = CreateFrame("Button")
        _G.CalendarViewEventInviteList.ScrollBox:initFrame(row, {})
        local tt = _G.GameTooltip
        tt:SetOwner(row)
        tt:ClearLines()
        tt:AddLine(en("CALENDAR_TOOLTIP_INVITE_RESPONDED"))
        tt:AddLine("Close") -- not a label of this row
        tt:Show()
        assert.are.equal("返答日時:", _G.GameTooltipTextLeft1:GetText())
        assert.are.equal("Close", _G.GameTooltipTextLeft2:GetText())
      end)

      it("labels are shown again when the window is re-shown", function()
        _G.CalendarViewEventDeclineButton:SetText(en("DECLINE")) -- the client rewrote it
        _G.CalendarFrame:Show()
        assert.are.equal("辞退", _G.CalendarViewEventDeclineButton:GetText())
      end)
    end)
  end

  it("hooks install once", function()
    setup(true)
    assert.is_false(WFJ.Calendar.setup())
    assert.are.equal(1, #Stub.hooks["CalendarFrame_Update"])
    assert.are.equal(1, #Stub.hooks["FilterButton:UpdateText"])
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    boot()
    loadCalendar(true)
    _G.CalendarMonthName = 7
    _G.CalendarViewEventDeclineButton = "x"
    _G.CalendarViewEventFrame_Update = true
    _G.CalendarMassInviteFrame = 3
    assert.has_no.errors(function() assert.is_true(WFJ.Calendar.init()) end)
    assert.are.equal("日曜日", _G.CalendarWeekday1Name:GetText())
    assert.are.equal("仮承諾", _G.CalendarViewEventTentativeButton:GetText())
    assert.is_nil(Stub.hooks["CalendarViewEventFrame_Update"])
  end)

  it("without the frame, or on a calendar without the FilterButton, init returns false and touches nothing",
    function()
      boot()
      assert.is_false(WFJ.Calendar.init())
      Stub.loadedAddons[ADDON] = true
      assert.is_false(WFJ.Calendar.setup())
      loadCalendar(false)
      assert.is_false(WFJ.Calendar.init())
      assert.are.equal("Sunday", _G.CalendarWeekday1Name:GetText())
      assert.are.equal("Decline", _G.CalendarViewEventDeclineButton:GetText())
      assert.is_false(WFJ.HelpTooltip.registered(_G.CalendarViewEventTentativeButton))
    end)
end)
