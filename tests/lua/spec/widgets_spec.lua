-- ADR-042: UI/Widgets.lua. The UI widgets' status lines ("Towers Controlled: 3"), NUMBERED
-- WidgetText rows. A UIWidgetManager replayed from blizzard_uiwidgetmanager.lua: registeredWidgetContainers (:284),
-- OnWidgetContainerRegistered (:640–642) and a container's ProcessWidget(widgetID, widgetType) that runs the widget
-- frame's Setup and keeps it in container.widgetFrames[widgetID] (:472–540). Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Widgets.lua"

-- A NUMBERED row's English here is its SKELETON ("#" for every number run): H.uiSetup hashes the English it is given
-- as the row's h1, and the pipeline's h1 for a WidgetText row is the skeleton's hash (pipeline core/numbered).
local UI = {
  ["WidgetText:4401"] = { "Towers Controlled: #", "制圧した塔: %1$s" },
  ["WidgetText:5120"] = { "Bases: #  Resources: #/#", "資源: %2$s/%3$s  拠点: %1$s" },
  ["WidgetText:6000"] = { "Alliance flag captures", "アライアンスの旗の奪取" }, -- a line with no number
  ["PvpColumn:1"] = { "Flag Captures", "旗の奪取" }, -- another restricted family: never on a widget
  CLOSE = { "Close", "閉じる" }, -- a dictionary word a base or player may be named
}

-- A frame with a GetChildren the walk descends through (the stub's frames have regions only).
local function frame(children)
  local f = CreateFrame("Frame")
  f.kids = children or {}
  function f.GetChildren(self) return unpack(self.kids) end
  return f
end

-- A container: ProcessWidget(widgetID) writes the widget's lines from `lines[widgetID]` (a list of texts) into its
-- frame: the text FontString on the frame, a child's, a grandchild's and a great-grandchild's (three levels down).
local function container(lines)
  local c = { widgetFrames = {}, lines = lines, calls = 0 }
  function c.ProcessWidget(self, widgetID)
    self.calls = self.calls + 1
    local f = self.widgetFrames[widgetID]
    if not f then
      local l4 = frame()
      local l3 = frame({ l4 })
      local l2 = frame({ l3 })
      local l1 = frame({ l2 })
      f = frame({ l1 })
      f.levels = { [0] = f, l1, l2, l3, l4 }
      for i = 0, 4 do f.levels[i].Text = f.levels[i]:addRegion(Stub.fontString("")) end
      f.levels[0]:CreateTexture() -- a texture region is no FontString
      self.widgetFrames[widgetID] = f
    end
    for i = 0, 4 do f.levels[i].Text.text = (self.lines[widgetID] or {})[i + 1] or "" end
  end
  return c
end

describe("the UI widgets' lines on Forever", function()
  local WFJ

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function text(c, id, level) return c.widgetFrames[id].levels[level].Text:GetText() end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.UIWidgetManager = nil
  end)

  local function manager(...)
    local registered = {}
    for _, c in ipairs({ ... }) do registered[c] = true end
    _G.UIWidgetManager = { registeredWidgetContainers = registered, OnWidgetContainerRegistered = function() end }
    return _G.UIWidgetManager
  end

  it("after ProcessWidget, the widget frame's lines three levels down are Japanese with the live numbers; Alt English",
    function()
      local c = container({ [101] = { "Towers Controlled: 3", "Bases: 2  Resources: 150/1600",
        "Alliance flag captures", "Towers Controlled: 4", "Towers Controlled: 5" } })
      manager(c)
      assert.is_true(WFJ.Widgets.init())
      c:ProcessWidget(101)
      assert.are.equal("制圧した塔: 3", text(c, 101, 0))
      assert.are.equal("資源: 150/1600  拠点: 2", text(c, 101, 1))
      assert.are.equal("アライアンスの旗の奪取", text(c, 101, 2))
      assert.are.equal("制圧した塔: 4", text(c, 101, 3)) -- three levels below the widget frame
      assert.are.equal("Towers Controlled: 5", text(c, 101, 4)) -- four levels: out of the walk
      alt(true)
      assert.are.equal("Towers Controlled: 3", text(c, 101, 0))
      assert.are.equal("Bases: 2  Resources: 150/1600", text(c, 101, 1))
      alt(false)
      assert.are.equal("制圧した塔: 3", text(c, 101, 0))
      -- the client rewrites the line with a new count: the next ProcessWidget shows it
      c.lines[101][1] = "Towers Controlled: 4"
      c:ProcessWidget(101)
      assert.are.equal("制圧した塔: 4", text(c, 101, 0))
    end)

  it("a base or player name, another family's word and a dictionary word on a widget stay English", function()
    local c = container({ [7] = { "Stormpike Graveyard", "Flag Captures", "Close", "" } })
    manager(c)
    WFJ.Widgets.init()
    c:ProcessWidget(7)
    assert.are.equal("Stormpike Graveyard", text(c, 7, 0))
    assert.are.equal("Flag Captures", text(c, 7, 1))
    assert.are.equal("Close", text(c, 7, 2))
    assert.are.equal("", text(c, 7, 3))
    assert.are.equal(0, WFJ.Widgets.showFrame(c.widgetFrames[7]))
  end)

  it("a widget already built when the container is hooked is shown at once", function()
    local c = container({ [3] = { "Towers Controlled: 2" } })
    c:ProcessWidget(3) -- before the addon hooks
    manager(c)
    WFJ.Widgets.init()
    assert.are.equal("制圧した塔: 2", text(c, 3, 0))
  end)

  it("a container registered later is hooked through OnWidgetContainerRegistered, once", function()
    local m = manager()
    assert.is_true(WFJ.Widgets.init())
    local c = container({ [9] = { "Towers Controlled: 1" } })
    c:ProcessWidget(9)
    assert.are.equal("Towers Controlled: 1", text(c, 9, 0)) -- not hooked yet
    m.registeredWidgetContainers[c] = true
    m:OnWidgetContainerRegistered(c)
    assert.are.equal("制圧した塔: 1", text(c, 9, 0))
    c.lines[9][1] = "Towers Controlled: 2"
    c:ProcessWidget(9)
    assert.are.equal("制圧した塔: 2", text(c, 9, 0))
    assert.are.equal(0, WFJ.Widgets.hookContainer(c)) -- already hooked
    assert.are.equal(1, #Stub.hooks["?:ProcessWidget"])
  end)

  it("init: once; false without a widget manager; wrong types degrade with no error", function()
    assert.is_false(WFJ.Widgets.init()) -- no UIWidgetManager
    manager()
    assert.is_true(WFJ.Widgets.init())
    assert.is_false(WFJ.Widgets.init())
    assert.are.equal(1, #Stub.hooks["?:OnWidgetContainerRegistered"])
    assert.has_no.errors(function()
      assert.are.equal(0, WFJ.Widgets.hookContainer(nil))
      assert.are.equal(0, WFJ.Widgets.hookContainer({ ProcessWidget = 3 }))
      WFJ.Widgets.onProcess(nil, 1)
      WFJ.Widgets.onProcess({ widgetFrames = 5 }, 1)
      WFJ.Widgets.onProcess({ widgetFrames = {} }, 1)
      assert.are.equal(0, WFJ.Widgets.showFrame("frame"))
    end)
  end)
end)
