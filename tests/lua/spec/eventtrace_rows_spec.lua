-- UI/EventTrace.lua's log message rows (ADR-038) (eventTraceRow: FormatLine(id, ORANGE("--- %s ---")),
-- blizzard_eventtrace.lua:800–809, 930–940) and the EventTraceTooltip lines (tooltipFrame, lua:812–836). The id, the
-- dashes and the colours are kept; event names and argument values are never matched.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/TooltipLines.lua"
FILES[#FILES + 1] = "UI/EventTrace.lua"

local UI = {
  EVENTTRACE_LOG_START = { "Log started", "ログ開始" }, EVENTTRACE_MARKER = { "Marker", "マーカー" },
  EVENTTRACE_TIMESTAMP = { "Timestamp:", "タイムスタンプ:" }, EVENTTRACE_ARG_FMT = { "Arg %d:", "引数 %d:" },
}

local GRAY, ORANGE = "|cff808080", "|cffff8000"
local function line(id, message) return GRAY .. "[" .. id .. "]|r " .. ORANGE .. "--- " .. message .. " ---|r" end

local function install()
  local f = CreateFrame("Frame", "EventTrace")
  f.Log = { Events = { ScrollBox = Stub.scrollBox() }, Search = { ScrollBox = Stub.scrollBox() } }
  _G.EventTraceLogMessageButtonMixin = { SetLeftText = function(self, data) self.LeftLabel:SetText(data.line) end }
  Stub.tooltipFrame("EventTraceTooltip")
  Stub.loadedAddons.Blizzard_EventTrace = true
  return f
end

-- A message row as the client builds one: Init writes LeftLabel through SetLeftText, then the box's callbacks run.
local function row(f, text)
  local r = CreateFrame("Button")
  r.LeftLabel = Stub.fontString("")
  r.SetLeftText = _G.EventTraceLogMessageButtonMixin.SetLeftText
  f.Log.Events.ScrollBox:initFrame(r, { line = text }, function(b, data) b:SetLeftText(data) end)
  return r
end

describe("the Event Log's message rows and tooltip", function()
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
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.EventTrace, _G.EventTraceLogMessageButtonMixin, _G.EventTraceTooltip = nil, nil, nil
  end)

  it("a message row's text is Japanese with its id, dashes and colours kept; Alt shows English", function()
    local f = install()
    assert.is_true(WFJ.EventTrace.init())
    local r = row(f, line("001", "Log started"))
    assert.are.equal(line("001", "ログ開始"), r.LeftLabel:GetText())
    local m = row(f, line("002", "Marker"))
    assert.are.equal(line("002", "マーカー"), m.LeftLabel:GetText())
    alt(true)
    assert.are.equal(line("001", "Log started"), r.LeftLabel:GetText())
    alt(false)
    -- an event row (an event name, no message frame) and an unknown message are never touched
    local e = row(f, GRAY .. "[003]|r PLAYER_ENTERING_WORLD")
    assert.are.equal(GRAY .. "[003]|r PLAYER_ENTERING_WORLD", e.LeftLabel:GetText())
    local u = row(f, line("004", "Marker set by addon"))
    assert.are.equal(line("004", "Marker set by addon"), u.LeftLabel:GetText())
  end)

  it("EventTraceTooltip: the timestamp and argument labels translate; the event name and values stay", function()
    install()
    WFJ.EventTrace.init()
    local tt = _G.EventTraceTooltip
    tt:SetOwner(_G.EventTrace)
    tt:ClearLines()
    tt:AddLine("PLAYER_ENTERING_WORLD")
    tt:AddDoubleLine("Timestamp:", "12.345")
    tt:AddDoubleLine("Arg 1:", "true")
    tt:Show()
    assert.are.equal("PLAYER_ENTERING_WORLD", _G.EventTraceTooltipTextLeft1:GetText())
    assert.are.equal("タイムスタンプ:", _G.EventTraceTooltipTextLeft2:GetText())
    assert.are.equal("引数 1:", _G.EventTraceTooltipTextLeft3:GetText())
    assert.are.equal("true", _G.EventTraceTooltipTextRight3:GetText())
    alt(true)
    assert.are.equal("Arg 1:", _G.EventTraceTooltipTextLeft3:GetText())
  end)
end)
