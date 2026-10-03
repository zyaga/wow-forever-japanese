-- UI/ReportWindow: Bug or Idea, the bug link and its paste fallback, the other-addon note, I sent it, and copy
-- short enough for one line in both languages.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local F = require("tests.lua.spec.stub_fixwindow")

local FILES = { "Core/ErrorLog.lua", "Core/Const.lua", "Core/Compat.lua", "Core/Normalize.lua", "Core/Hash.lua",
  "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua", "Core/Collector.lua", "Core/CollectorSend.lua",
  "Core/BugReport.lua", "UI/Font.lua", "UI/OptionsText.lua", "UI/OptionsWidgets.lua", "UI/ReportWindow.lua" }

local function ours(i)
  return ("Interface/AddOns/WoWForeverJapanese/UI/A.lua:%d: attempt to call a nil value"):format(i)
end

local function load(st)
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  F.install()
  local WFJ = H.loadChunks(FILES)
  WFJ.Compat.init(function(name) return _G[name] end)
  WFJ.Settings.load(nil, 1, {})
  WFJ.Collector.load(nil, H.collectorDeps())
  WFJ.ErrorLog.setDeps({ clock = function() return st.at end, stack = function() return st.stack end })
  WFJ.ErrorLog.install(function() return nil end, function(fn) st.handler = fn end)
  WFJ.ErrorLog.load({})
  return WFJ
end

describe("the report window", function()
  local WFJ, RW, st

  before_each(function()
    st = { at = "2026-10-03 14:40:00", stack = "" }
    WFJ = load(st)
    RW = WFJ.ReportWindow
  end)
  after_each(function() F.clear() end)

  local function ja(key, ...) return select(2, WFJ.OptionsText.get(key, ...)) end
  local function shown(w) return (w.frame or w):IsShown() end

  it("opens on Bug: the link carries build, version and the errors; I sent it marks them", function()
    WFJ.ErrorLog.record(ours(1))
    local f = RW.open()
    assert.is_true(f:IsShown())
    assert.are.equal(ja("report.title"), f.title:GetText())
    assert.is_true(f.bug:GetChecked())
    assert.is_false(f.idea:GetChecked())
    assert.are.equal(ja("report.bug"), f.bug.text:GetText())
    assert.are.equal(ja("report.summary.errors", 1), f.summary.en:GetText())
    assert.are.equal(ja("send.step1"), f.step1.en:GetText())
    local url = f.url:GetText():gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    assert.is_truthy(url:find("template=bug-report.yml&client-build=1.15.9.69722&addon-version=", 1, true))
    assert.is_truthy(url:find("&errors=1) 1 time, first 2026-10-03 14:40:00", 1, true))
    assert.are.equal(ja("report.step2.link"), f.step2.en:GetText())
    assert.is_false(shown(f.text))
    assert.are.equal(ja("report.step3"), f.step3.en:GetText())
    assert.is_true(shown(f.sent))
    f.sent.scripts.OnClick(f.sent, "LeftButton")
    assert.are.equal(ja("report.marked", 1), f.message.en:GetText())
    assert.is_false(shown(f.sent))
    assert.are.equal(0, #WFJ.ErrorLog.unsent())
  end)

  it("with no new errors the link fills build and version only and there is nothing to mark", function()
    local f = RW.open()
    assert.are.equal(ja("report.summary.none"), f.summary.en:GetText())
    assert.is_nil(f.url:GetText():find("&errors=", 1, true))
    assert.is_false(shown(f.sent))
    assert.are.equal("", f.step4.en:GetText())
  end)

  it("a link too long holds build and version; the errors go in a box to paste", function()
    st.stack = string.rep("...rface/AddOns/WoWForeverJapanese/UI/A.lua:1: in function <x>\n", 12)
    for i = 1, 6 do WFJ.ErrorLog.record(ours(i)) end
    local f = RW.open()
    assert.are.equal("paste", RW.pack.mode)
    assert.is_nil(f.url:GetText():find("&errors=", 1, true))
    assert.are.equal(ja("report.step2.paste"), f.step2.en:GetText())
    assert.is_true(shown(f.text))
    assert.is_truthy(f.text:getText():find("6) 1 time", 1, true))
  end)

  it("another addon catching errors: the note replaces the count", function()
    WFJ.ErrorLog.checkOurs(function() return function() end end)
    local f = RW.open()
    assert.are.equal(ja("report.summary.other"), f.summary.en:GetText())
  end)

  it("Idea links the idea form; the radios are exclusive and switch back", function()
    WFJ.ErrorLog.record(ours(1))
    local f = RW.open()
    f.idea.scripts.OnClick(f.idea, "LeftButton")
    assert.are.equal("idea", RW.mode)
    assert.is_true(f.idea:GetChecked())
    assert.is_false(f.bug:GetChecked())
    assert.are.equal(WFJ.BugReport.IDEA_URL, f.url:GetText())
    assert.are.equal(ja("report.summary.idea"), f.summary.en:GetText())
    assert.are.equal(ja("report.idea.step2"), f.step2.en:GetText())
    assert.is_false(shown(f.sent))
    assert.are.equal(0, RW.markSent()) -- nothing to mark in idea mode
    f.bug.scripts.OnClick(f.bug, "LeftButton")
    assert.are.equal("bug", RW.mode)
    assert.is_true(f.bug:GetChecked())
    assert.is_false(f.idea:GetChecked())
    assert.is_truthy(f.url:GetText():find("bug-report.yml", 1, true))
  end)

  it("a report after I sent it holds only errors new since", function()
    WFJ.ErrorLog.record(ours(1))
    RW.open()
    RW.markSent()
    st.at = "2026-10-03 15:00:00"
    WFJ.ErrorLog.record(ours(2))
    local f = RW.open()
    assert.are.equal(ja("report.summary.errors", 1), f.summary.en:GetText())
    assert.are.equal(1, #RW.pack.sent)
    assert.are.equal(ours(2), RW.pack.sent[1].msg)
  end)

  -- About 7 px per Latin character and 12 px per Japanese one at the window's 12 px font; the in-game checklist
  -- confirms it on the real font.
  local function width(s)
    local w = 0
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do w = w + (#ch == 1 and 7 or 12) end
    return w
  end

  it("every label of the window has both languages, and each step fits one line", function()
    local keys = { "report.title", "report.bug", "report.idea", "report.summary.errors", "report.summary.none",
      "report.summary.other", "report.summary.idea", "report.step2.link", "report.step2.paste", "report.step3",
      "report.idea.step2", "report.marked", "send.step1", "send.step4", "send.sent", "about.bug",
      "button.reportBug" }
    for _, key in ipairs(keys) do
      local en, jp = WFJ.OptionsText.get(key, 30)
      assert.is_true(en ~= "" and jp ~= "", key)
      assert.is_true(width(en) <= RW.INNER, key .. " (en) wraps")
      assert.is_true(width(jp) <= RW.INNER, key .. " (ja) wraps")
    end
  end)
end)
