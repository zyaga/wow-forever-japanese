-- The fix-report minimap button and its entry in the addon dropdown.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local F = require("tests.lua.spec.stub_fixwindow")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Normalize.lua", "Core/Hash.lua", "Core/State.lua",
  "Core/Settings.lua", "Core/Modifier.lua", "Core/RecentLines.lua", "Core/Reports.lua", "Core/ReportText.lua",
  "UI/Font.lua", "UI/OptionsText.lua", "UI/OptionsWidgets.lua", "UI/FixWindow.lua", "UI/MinimapButton.lua" }

local function load(saved)
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  F.install()
  local WFJ = H.loadChunks(FILES)
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

  it("right-click opens the menu: title, translation on / off, report, settings, hide", function()
    b:click("RightButton")
    local menu = F.menus[1]
    assert.are.equal(b, menu.owner)
    local texts = {}
    for i, el in ipairs(menu.elements) do texts[i] = el.kind .. ":" .. el.text end
    -- a divider sets the switch apart from the actions
    assert.are.same({ "title:WoW Forever Japanese", "checkbox:翻訳オン", "divider:",
      "button:翻訳を報告", "button:設定", "button:このボタンを隠す" }, texts)
    for _, i in ipairs({ 2, 4, 5, 6 }) do assert.are.equal(1, #menu.elements[i].initializers) end -- bundled font
  end)

  it("the checkbox is the master switch, the same state as the settings checkbox", function()
    b:click("RightButton")
    local cb = F.menus[1].elements[2]
    assert.is_true(cb.a())
    cb.b()
    assert.is_false(WFJ.Settings.get("enabled"))
    assert.is_false(WFJ.State.enabled)
    assert.is_false(cb.a())
    WFJ.Settings.set("enabled", true)
    assert.is_true(cb.a())
  end)

  it("report opens the fix window; settings opens the addon's settings", function()
    b:click("RightButton")
    local opened
    WFJ.Compat.openOptions = function(page) opened = page or "main" end
    F.menus[1].elements[4].a()
    assert.is_true(_G.WFJFixWindow:IsShown())
    F.menus[1].elements[5].a()
    assert.are.equal("main", opened)
  end)

  it("Hide this button turns the setting off; turning it on shows the button again", function()
    b:click("RightButton")
    F.menus[1].elements[6].a()
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
