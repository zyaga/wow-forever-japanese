-- UI/TaintWatch: the action-bar taint watch. issecurevariable is stubbed: a table key or global listed in `taint`
-- reads as written by the addon named there.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

describe("UI/TaintWatch", function()
  local WFJ, TW, taint

  local function entriesOf(kind)
    local out = {}
    for _, e in ipairs(WFJ_Log.entries) do if e.kind == kind then out[#out + 1] = e end end
    return out
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "Core/Diag.lua", "UI/TaintWatch.lua" })
    WFJ.Compat.init(function(name) return _G[name] end)
    TW = WFJ.TaintWatch
    WFJ_Log = WFJ.Diag.load(nil)
    WFJ.Diag.setDeps({ clock = function() return "2026-10-04 10:00:00" end, print = function() end })
    _G.date = function() return "10:00:00" end
    taint = {}
    _G.issecurevariable = function(t, key)
      if key == nil then key, t = t, _G end
      local by = taint[key] and (t == _G or taint[key].t == t) and taint[key].by or nil
      return by == nil, by
    end
    _G.debugstack = function() return "[Interface/AddOns/Blizzard_X/X.lua]:12: in function 'Write'\n[C]: ?" end
    _G.StanceBar = { name = "StanceBar", snappedToFrame = 1, showAllButtons = 0 }
    _G.MultiBarLeft = { name = "MultiBarLeft", showAllButtons = 0, SetShowGrid = function() end }
    _G.ON_BAR_HIGHLIGHT_MARKS = {}
  end)

  after_each(function()
    _G.issecurevariable, _G.debugstack = nil, nil
    _G.StanceBar, _G.MultiBarLeft, _G.ON_BAR_HIGHLIGHT_MARKS = nil, nil, nil
  end)

  it("logs a field the first time it turns tainted, with the recent events, and again only after it was clean",
    function()
      TW.push("ADDON_LOADED Blizzard_PlayerSpells")
      assert.are.equal(0, TW.checkFields("load"))
      taint.snappedToFrame = { t = _G.StanceBar, by = "WoWForeverJapanese" }
      assert.are.equal(1, TW.checkFields("timer"))
      assert.are.equal(0, TW.checkFields("timer"))
      local turned = entriesOf("turned")
      assert.are.equal(1, #turned)
      assert.are.equal("StanceBar.snappedToFrame", turned[1].msg)
      assert.are.equal("WoWForeverJapanese", turned[1].by)
      assert.is_truthy(turned[1].events:find("ADDON_LOADED Blizzard_PlayerSpells", 1, true))
      taint.snappedToFrame = nil
      TW.checkFields("timer")
      taint.snappedToFrame = { t = _G.StanceBar, by = "WoWForeverJapanese" }
      assert.are.equal(1, TW.checkFields("timer"))
      assert.are.equal(2, entriesOf("turned")[1].n)
    end)

  it("a writer logs its stack only when the value comes out tainted; a global counts too", function()
    assert.is_nil(TW.wrote("MultiBarLeft.showAllButtons", _G.MultiBarLeft, "showAllButtons"))
    taint.showAllButtons = { t = _G.MultiBarLeft, by = "WoWForeverJapanese" }
    local e = TW.wrote("MultiBarLeft.showAllButtons", _G.MultiBarLeft, "showAllButtons")
    assert.are.equal("write", e.kind)
    assert.is_truthy(e.msg:find("<[Interface/AddOns/Blizzard_X/X.lua]:12: in function 'Write'>", 1, true))
    assert.is_truthy(e.stack:find("Blizzard_X", 1, true))
    taint.ON_BAR_HIGHLIGHT_MARKS = { by = "WoWForeverJapanese" }
    assert.is_table(TW.wrote("ON_BAR_HIGHLIGHT_MARKS", nil, "ON_BAR_HIGHLIGHT_MARKS"))
  end)

  it("the ring keeps the last RING events, oldest first; noisy and secret events are left out", function()
    for i = 1, TW.RING + 5 do TW.onEvent("EVENT_" .. i) end
    TW.onEvent("COMBAT_LOG_EVENT_UNFILTERED")
    TW.onEvent("CHAT_MSG_SAY", "hello")
    TW.onEvent("CHAT_MSG_SYSTEM", "Someone has come online.")
    local lines = {}
    for line in TW.events():gmatch("[^\n]+") do lines[#lines + 1] = line end
    assert.are.equal(TW.RING, #lines)
    assert.are.equal("10:00:00 EVENT_6", lines[1])
    assert.are.equal("10:00:00 EVENT_" .. (TW.RING + 5), lines[#lines])
    _G.issecretvalue = function(v) return v == "secret" end
    TW.onEvent("UNIT_DIED", "secret")
    assert.is_truthy(TW.events():find("UNIT_DIED$"))
    TW.onEvent("UI_INFO_MESSAGE", "Two words")
    assert.is_truthy(TW.events():find("UI_INFO_MESSAGE$"))
    TW.onEvent("ADDON_LOADED", "Blizzard_PlayerSpells")
    assert.is_truthy(TW.events():find("ADDON_LOADED Blizzard_PlayerSpells$"))
    assert.is_nil(TW.events():find("online", 1, true))
    TW.onEvent("UNIT_DIED", "Player-4621-0ABCDEF")
    assert.is_nil(TW.events():find("Player-", 1, true))
    _G.issecretvalue = nil
  end)

  it("the scan lists the tainted fields under its roots and this addon's globals; a block scans once", function()
    taint.snappedToFrame = { t = _G.StanceBar, by = "WoWForeverJapanese" }
    taint.WFJ_DB = { by = "WoWForeverJapanese" }
    _G.WFJ_DB = {}
    local fields, globals = TW.scan("slash")
    assert.are.same({ 1, 1 }, { fields, globals })
    local scan = entriesOf("taint")[1]
    assert.is_truthy(scan.fields:find("StanceBar.snappedToFrame (WoWForeverJapanese)", 1, true))
    assert.are.equal("WFJ_DB", scan.globals)
    assert.is_true(TW.onBlocked())
    assert.is_false(TW.onBlocked())
    assert.are.equal(2, entriesOf("taint")[1].n) -- the slash scan and the first block's (one clock second)
    assert.are.equal(2, entriesOf("context")[1].n) -- both blocks keep their events
    _G.WFJ_DB = nil
  end)

  it("hooks the writers it finds and starts nothing on a client without issecurevariable", function()
    local hooked = {}
    _G.hooksecurefunc = function(t, m) hooked[#hooked + 1] = type(t) == "table" and (t.name .. ":" .. m) or t end
    _G.C_Timer = { NewTicker = function() end }
    _G.ClearOnBarHighlightMarks = function() end
    local n = TW.init()
    assert.is_true(n >= 2)
    assert.is_truthy(table.concat(hooked, " "):find("MultiBarLeft:SetShowGrid", 1, true))
    assert.is_truthy(table.concat(hooked, " "):find("ClearOnBarHighlightMarks", 1, true))
    assert.is_false(TW.init()) -- once
    _G.ClearOnBarHighlightMarks = nil
  end)
end)
