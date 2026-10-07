-- The fix-report minimap button and its entry in the addon dropdown.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local F = require("tests.lua.spec.stub_fixwindow")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Normalize.lua", "Core/Hash.lua", "Core/State.lua",
  "Core/Settings.lua", "Core/Modifier.lua", "Core/RecentLines.lua", "Core/Reports.lua", "Core/ReportText.lua",
  "UI/Font.lua", "UI/OptionsText.lua", "UI/OptionsWidgets.lua", "UI/FixWindow.lua", "UI/MinimapButton.lua" }
-- the report window, for the menu's bug item (loaded on top: its own files need the collector's send)
local REPORT = { "Core/Collector.lua", "Core/CollectorSend.lua", "Core/ErrorLog.lua", "Core/BugReport.lua",
  "UI/ReportWindow.lua" }

local function load(saved)
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  F.install()
  local WFJ = H.loadChunks(FILES)
  H.loadChunks(REPORT, WFJ)
  WFJ.Compat.init(function(name) return _G[name] end)
  local db = WFJ.Settings.load(saved, 1, {})
  WFJ.Reports.load(db)
  WFJ.Lookup = { get = function() return nil end }
  WFJ.MinimapButton.init(db)
  return WFJ, db
end

local function at(deg)
  local r = 140 / 2 + 10
  local rad = math.rad(deg)
  return { "CENTER", _G.Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r }
end

describe("the minimap button", function()
  local WFJ, db, MB, b

  before_each(function()
    WFJ, db = load(nil)
    MB = WFJ.MinimapButton
    b = _G.WFJMinimapButton
  end)
  after_each(function() F.clear() end)

  it("built on MiniMapButtonTemplate, shown by default at the default spot; WFJ_DB untouched", function()
    assert.are.equal("MiniMapButtonTemplate", b.template)
    assert.are.equal(_G.Minimap, b.parent)
    assert.is_true(b:IsShown())
    assert.are.same(at(MB.DEFAULT_ANGLE), b.point)
    assert.is_nil(db.minimap)
    assert.are.equal(MB.ICON, b.icon.texture)
    assert.are.equal("WFJMinimapButtonIcon", b.icon.name) -- the `<name>Icon` the template's press moves
  end)

  it("a drag moves it around the rim and saves the angle; the mouse-up that ends it is no click", function()
    F.cursor = { 1000, 580 } -- straight above the minimap's centre (1000, 500)
    b.scripts.OnDragStart(b)
    b.scripts.OnUpdate(b)
    assert.are.same(at(90), b.point)
    b.scripts.OnDragStop(b)
    assert.are.equal(90, db.minimap.angle)
    b:click("LeftButton")
    assert.is_nil(_G.WFJFixWindow) -- not opened by the drag's mouse-up
    b:click("LeftButton")
    assert.is_true(_G.WFJFixWindow:IsShown())
  end)

  it("a client that sends no click after a drag never swallows the next one", function()
    local t = 100
    _G.GetTime = function() return t end
    F.cursor = { 1000, 580 }
    b.scripts.OnDragStart(b)
    b.scripts.OnDragStop(b) -- no mouse-up click follows
    t = t + 2 -- the player clicks later
    b:click("LeftButton")
    assert.is_true(_G.WFJFixWindow:IsShown())
    _G.GetTime = function() return 0 end
  end)

  it("a saved angle is restored after /reload", function()
    F.clear()
    WFJ, db = load({ schema = 1, settings = {}, minimap = { angle = 45 } })
    assert.are.same(at(45), _G.WFJMinimapButton.point)
  end)

  it("left-click opens the fix window", function()
    b:click("LeftButton")
    assert.is_true(_G.WFJFixWindow:IsShown())
    assert.are.equal("recent", WFJ.FixWindow.current)
  end)

  -- the menu is the addon's own frame, not Blizzard's Menu: its rows, in order
  local function menuRows()
    local m = _G.WFJMinimapMenu
    local out = {}
    for i, row in ipairs(m.rows) do
      if row:IsShown() then out[i] = row end
    end
    return m, out
  end
  local function clickRow(i)
    local _, rows = menuRows()
    rows[i].scripts.OnClick(rows[i])
  end

  it("right-click opens the menu: title, translation on / off, report, bug or idea, settings, hide", function()
    b:click("RightButton")
    local m, rows = menuRows()
    assert.is_true(m:IsShown())
    assert.are.equal("WoW Forever Japanese", m.title:GetText())
    local texts = {}
    for i, row in ipairs(rows) do texts[i] = row.item.kind .. ":" .. row.text:GetText() end
    assert.are.same({ "checkbox:翻訳オン", "button:翻訳を報告", "button:不具合・提案を報告", "button:設定",
      "button:このボタンを隠す" }, texts)
    for _, row in ipairs(rows) do assert.are.equal(WFJ.Font.PATH, (row.text:GetFont())) end -- bundled font
    assert.is_table(m.divider) -- a divider sets the switch apart from the actions
    b:click("RightButton") -- a second right-click closes it
    assert.is_false(m:IsShown())
  end)

  it("a left-click on the button closes an open menu", function()
    b:click("RightButton")
    assert.is_true(_G.WFJMinimapMenu:IsShown())
    b:click("LeftButton")
    assert.is_false(_G.WFJMinimapMenu:IsShown())
  end)

  it("the checkbox is the master switch, the same state as the settings checkbox", function()
    b:click("RightButton")
    local _, rows = menuRows()
    assert.is_true(rows[1].item.isSelected())
    assert.is_true(rows[1].check:IsShown())
    clickRow(1)
    assert.is_false(WFJ.Settings.get("enabled"))
    assert.is_false(WFJ.State.enabled)
    assert.is_false(_G.WFJMinimapMenu:IsShown()) -- a row closes the menu
    b:click("RightButton")
    _, rows = menuRows()
    assert.is_false(rows[1].check:IsShown())
    WFJ.Settings.set("enabled", true)
  end)

  it("report opens the fix window; bug or idea opens the report window; settings opens the settings", function()
    local opened
    WFJ.Compat.openOptions = function(page) opened = page or "main" end
    b:click("RightButton")
    clickRow(2)
    assert.is_true(_G.WFJFixWindow:IsShown())
    b:click("RightButton")
    clickRow(3)
    assert.is_true(_G.WFJReportWindow:IsShown())
    assert.are.equal("bug", WFJ.ReportWindow.mode)
    b:click("RightButton")
    clickRow(4)
    assert.are.equal("main", opened)
  end)

  it("Hide this button turns the setting off; turning it on shows the button again", function()
    b:click("RightButton")
    clickRow(5)
    assert.is_false(WFJ.Settings.get("minimapButton"))
    assert.is_false(b:IsShown())
    assert.is_true(WFJ.Settings.set("minimapButton", "on")) -- as /wfj minimapButton on does
    assert.is_true(b:IsShown())
  end)

  it("a saved `off` keeps it hidden after /reload", function()
    F.clear()
    load({ schema = 1, settings = { minimapButton = false } })
    assert.is_false(_G.WFJMinimapButton:IsShown())
  end)

  it("hover shows the tooltip in Japanese (English with the reveal key held); leaving hides it", function()
    b.scripts.OnEnter(b)
    local tip = _G.WFJMinimapTooltip
    assert.is_true(tip:IsShown())
    assert.are.same({ "左クリック：翻訳を報告 ・ 右クリック：メニュー" }, tip.lines)
    b.scripts.OnLeave(b)
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    b.scripts.OnEnter(b)
    assert.are.same({ "Left-click: report a line · Right-click: menu" }, tip.lines)
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    b.scripts.OnLeave(b)
    assert.is_false(tip:IsShown())
  end)
end)

describe("the minimap menu's send entry", function()
  local WFJ, C

  local function texts()
    local out = {}
    for i, it in ipairs(WFJ.MinimapButton.items()) do out[i] = it.text end
    return out
  end
  local function record(n, from)
    for i = 1, n do C.record("quest", (from or 2000) + i, "title", "Some Quest " .. ((from or 2000) + i)) end
  end

  before_each(function()
    WFJ = load(nil)
    C = WFJ.Collector
    WFJ.CollectorSendWindow = { open = function() end } -- its own spec covers the window
  end)
  after_each(function() F.clear() end)

  it("is absent with nothing unsent", function()
    C.load(nil, H.collectorDeps())
    assert.are.same({ "翻訳オン", "翻訳を報告", "不具合・提案を報告", "設定", "このボタンを隠す" }, texts())
  end)

  it("shows the unsent count before the settings entry from one line up, and opens the send window", function()
    C.load(nil, H.collectorDeps())
    record(1)
    assert.are.same({ "翻訳オン", "翻訳を報告", "不具合・提案を報告", "集めた英語を送る（1）", "設定",
      "このボタンを隠す" }, texts())
    record(11, 3000)
    local items = WFJ.MinimapButton.items()
    assert.are.equal("集めた英語を送る（12）", items[4].text)
    local opened
    WFJ.CollectorSendWindow = { open = function(all) opened = all end }
    items[4].action()
    assert.is_false(opened)
  end)

  it("is English with the reveal key held or translation off", function()
    C.load(nil, H.collectorDeps())
    record(3)
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal("Send collected English (3)", WFJ.MinimapButton.items()[4].text)
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    WFJ.Settings.set("enabled", false)
    assert.are.equal("Send collected English (3)", WFJ.MinimapButton.items()[4].text)
    WFJ.Settings.set("enabled", true)
  end)

  it("a collector that cannot answer leaves the menu as it was", function()
    WFJ.Collector.status = function() error("broken") end
    assert.are.equal(5, #WFJ.MinimapButton.items())
  end)

  it("the menu widens for a label longer than its least width", function()
    WFJ.Collector.status = function() return { unsent = 1234567, readOnly = false } end
    local b = _G.WFJMinimapButton
    b:click("RightButton")
    local m = _G.WFJMinimapMenu
    local widest = 0
    for _, row in ipairs(m.rows) do
      if row:IsShown() then widest = math.max(widest, row.text:GetStringWidth()) end
    end
    assert.is_true(widest + 48 > WFJ.MinimapButton.MENU_WIDTH)
    assert.are.equal(math.ceil(widest + 48), m:GetWidth())
  end)

  it("is absent for a collector file from a newer version", function()
    C.load({ version = 2, entries = { ["quest:1:title"] = { t = "quest", i = 1, f = "title",
      h = "0123456789abcdef", e = "Old", b = 1 } }, builds = { "1.15.9.69722" } }, H.collectorDeps())
    assert.are.equal(5, #WFJ.MinimapButton.items())
  end)
end)

describe("the addon dropdown entry", function()
  it("the TOC declares AddonCompartmentFunc and its hover handlers, all defined in Main.lua", function()
    local toc = H.readFile("addon/WoWForeverJapanese/WoWForeverJapanese.toc")
    local main = H.readFile("addon/WoWForeverJapanese/Main.lua")
    for field, fn in pairs({ AddonCompartmentFunc = "WFJ_OnAddonCompartmentClick",
        AddonCompartmentFuncOnEnter = "WFJ_OnAddonCompartmentEnter",
        AddonCompartmentFuncOnLeave = "WFJ_OnAddonCompartmentLeave" }) do
      assert.is_truthy(toc:find("\n## " .. field .. ": " .. fn .. "\n", 1, true), field)
      assert.is_truthy(main:find("function " .. fn .. "(", 1, true), fn)
    end
  end)
end)
