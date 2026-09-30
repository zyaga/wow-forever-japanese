-- UI/EventTrace.lua over an EventTrace replayed from camelot
-- blizzard_eventtrace/blizzard_eventtrace.lua (OnLoad :100–122, SetTitle :111, UpdatePlaybackButton :182–184,
-- DisplayEvents :194–198, OnSearchDataProviderChanged :205–209, InitializeFilter :414–436, InitializeOptions :462),
-- in both load orders. The search box (an EditBox) is never touched. Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/TooltipLines.lua" -- the Event Log row tooltip
FILES[#FILES + 1] = "UI/EventTrace.lua"

local ADDON = "Blizzard_EventTrace"
local UI = {
  EVENTTRACE_HEADER = { "Event Log", "イベントログ" }, EVENTTRACE_LOG_HEADER = { "Log", "ログ" },
  EVENTTRACE_FILTER_HEADER = { "Filter", "フィルター" }, EVENTTRACE_RESULTS = { "Results: %d", "結果: %d" },
  EVENTTRACE_BUTTON_MARKER = { "Marker", "マーカー" }, EVENTTRACE_BUTTON_PLAY = { "Play", "再開" },
  EVENTTRACE_BUTTON_PAUSE = { "Pause", "一時停止" }, EVENTTRACE_BUTTON_DISCARD_FILTER = { "Discard All", "すべて破棄" },
  EVENTTRACE_BUTTON_ENABLE_FILTERS = { "Check All", "すべてチェック" },
  EVENTTRACE_BUTTON_DISABLE_FILTERS = { "Uncheck All", "すべてチェックを外す" },
  EVENTTRACE_OPTIONS = { "Options", "オプション" },
}

local function en(key) return _G[key] end

local function labelled(key) return { Label = Stub.fontString(key and en(key) or "") } end

local S = {} -- replayed client state

local function installEventTrace()
  local f = CreateFrame("Frame", "EventTrace")
  f.TitleContainer = { TitleText = Stub.fontString("") }
  function f.SetTitle(self, t) self.TitleContainer.TitleText.text = t end
  local dropdown = CreateFrame("Button")
  dropdown.Text = Stub.fontString("")
  function dropdown.UpdateText(self) self.Text.text = en("EVENTTRACE_OPTIONS") end
  f.SubtitleBar = { ViewLog = labelled("EVENTTRACE_LOG_HEADER"), ViewFilter = labelled("EVENTTRACE_FILTER_HEADER"),
    OptionsDropdown = dropdown }
  f.Log = { Bar = { Label = Stub.fontString(en("EVENTTRACE_LOG_HEADER")),
    MarkButton = labelled("EVENTTRACE_BUTTON_MARKER"), PlaybackButton = labelled(),
    DiscardAllButton = labelled("EVENTTRACE_BUTTON_DISCARD_FILTER"),
    SearchBox = CreateFrame("EditBox") } }
  f.Log.Bar.SearchBox.text = "Filter" -- the player typed a dictionary word
  f.Filter = { Bar = { Label = Stub.fontString(en("EVENTTRACE_FILTER_HEADER")),
    CheckAllButton = labelled("EVENTTRACE_BUTTON_ENABLE_FILTERS"),
    UncheckAllButton = labelled("EVENTTRACE_BUTTON_DISABLE_FILTERS"),
    DiscardAllButton = labelled("EVENTTRACE_BUTTON_DISCARD_FILTER") } }
  function f.UpdatePlaybackButton(self)
    self.Log.Bar.PlaybackButton.Label.text = S.paused and en("EVENTTRACE_BUTTON_PLAY") or en("EVENTTRACE_BUTTON_PAUSE")
  end
  function f.DisplayEvents(self) self.Log.Bar.Label.text = en("EVENTTRACE_LOG_HEADER") end
  function f.OnSearchDataProviderChanged(self) self.Log.Bar.Label.text = en("EVENTTRACE_RESULTS"):format(S.results) end
  -- OnLoad
  f:SetTitle(en("EVENTTRACE_HEADER"))
  dropdown:UpdateText()
  f:UpdatePlaybackButton()
  Stub.loadedAddons[ADDON] = true
  return f
end

describe("the Event Log developer window on Forever", function()
  local WFJ

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    S.paused, S.results = false, 3
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.EventTrace = nil
  end)

  for _, order in ipairs({ { true, "loaded before init" }, { false, "loaded on demand" } }) do
    it("Blizzard_EventTrace " .. order[2] .. ": labels, title and writers are Japanese; the search box is untouched",
      function()
        load()
        local f
        if order[1] then
          f = installEventTrace()
          assert.is_true(WFJ.EventTrace.init())
        else
          assert.is_false(WFJ.EventTrace.init())
          f = installEventTrace()
          assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
        end
        assert.are.equal("イベントログ", f.TitleContainer.TitleText:GetText())
        f:SetTitle(en("EVENTTRACE_HEADER")) -- a second SetTitle keeps it
        assert.are.equal("イベントログ", f.TitleContainer.TitleText:GetText())
        assert.are.equal("ログ", f.SubtitleBar.ViewLog.Label:GetText())
        assert.are.equal("フィルター", f.Filter.Bar.Label:GetText())
        assert.are.equal("すべてチェックを外す", f.Filter.Bar.UncheckAllButton.Label:GetText())
        assert.are.equal("すべて破棄", f.Log.Bar.DiscardAllButton.Label:GetText())
        assert.are.equal("オプション", f.SubtitleBar.OptionsDropdown.Text:GetText())
        assert.are.equal("一時停止", f.Log.Bar.PlaybackButton.Label:GetText())
        S.paused = true
        f:UpdatePlaybackButton()
        assert.are.equal("再開", f.Log.Bar.PlaybackButton.Label:GetText())
        f:OnSearchDataProviderChanged()
        assert.are.equal("結果: 3", f.Log.Bar.Label:GetText())
        f:DisplayEvents()
        assert.are.equal("ログ", f.Log.Bar.Label:GetText())
        assert.are.equal("Filter", f.Log.Bar.SearchBox:GetText())
        assert.are.equal(0, WFJ.Labels.show("eventtrace", "x", f.Log.Bar.SearchBox))
        Stub.keys.alt = true
        WFJ.Modifier.refresh()
        assert.are.equal("Event Log", f.TitleContainer.TitleText:GetText())
        assert.is_false(WFJ.EventTrace.setup()) -- once
      end)
  end

  it("a label holding another word keeps it (each label is restricted to its writer's keys)", function()
    load()
    local f = installEventTrace()
    f.Log.Bar.MarkButton.Label.text = en("EVENTTRACE_OPTIONS")
    assert.is_true(WFJ.EventTrace.init())
    assert.are.equal("Options", f.Log.Bar.MarkButton.Label:GetText())
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    load()
    local f = installEventTrace()
    f.SubtitleBar, f.Filter, f.UpdatePlaybackButton, f.TitleContainer = 4, "filter", "not a function", true
    assert.has_no.errors(function() assert.is_true(WFJ.EventTrace.init()) end)
    assert.has_no.errors(function() f:Show() end)
    assert.are.equal("すべて破棄", f.Log.Bar.DiscardAllButton.Label:GetText())
    load()
    _G.EventTrace = 12
    Stub.loadedAddons[ADDON] = true
    assert.has_no.errors(function() assert.is_false(WFJ.EventTrace.init()) end)
  end)

  it("no EventTrace frame → init is false, nothing touched", function()
    load()
    Stub.loadedAddons[ADDON] = true
    assert.has_no.errors(function() assert.is_false(WFJ.EventTrace.init()) end)
  end)
end)
