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
    assert.is_truthy(e.msg:find("<[Interface/AddOns/Blizzard_X/X.lua]:12>", 1, true)) -- the Blizzard writer
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
    TW.onEvent("PARTY_INVITE_REQUEST", "Somebody") -- a player's name is never kept
    assert.is_truthy(TW.events():find("PARTY_INVITE_REQUEST$"))
    TW.onEvent("UNIT_PET", "party2")
    assert.is_truthy(TW.events():find("UNIT_PET party2$"))
    assert.is_true(TW.isUnitToken("nameplate14"))
    assert.is_true(TW.isUnitToken("raid12pet"))
    assert.is_false(TW.isUnitToken("Somebody"))
    assert.is_false(TW.isUnitToken("partygoer"))
    TW.onEvent("UNIT_TARGET", "targettarget")
    assert.is_truthy(TW.events():find("UNIT_TARGET targettarget$"))
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
    assert.are.equal(2, #entriesOf("taint")) -- the slash scan and the block's, each its own entry
    assert.are.equal(1, #entriesOf("context")) -- a repeat of the same block reads the ring no more
    _G.WFJ_DB = nil
  end)

  it("the scan reaches a tracker block, the quest log and the map, deeper than the bars", function()
    local block = { name = "block", id = 1 }
    _G.ObjectiveTrackerFrame = { modules = { { usedBlocks = { QuestBlock = { [1] = block } } } } }
    _G.QuestMapFrame = { DetailsFrame = { questID = 93949 } }
    taint.id = { t = block, by = "WoWForeverJapanese" }
    taint.questID = { t = _G.QuestMapFrame.DetailsFrame, by = "WoWForeverJapanese" }
    local fields = TW.scan("slash")
    assert.are.equal(2, fields)
    local scan = entriesOf("taint")[1].fields
    assert.is_truthy(scan:find("QuestMapFrame.DetailsFrame.questID", 1, true))
    assert.is_truthy(scan:find("%.id %(WoWForeverJapanese%)"))
    _G.ObjectiveTrackerFrame, _G.QuestMapFrame = nil, nil
  end)

  it("the scan reaches the quest list's pooled rows, also when the map reached the list first", function()
    local row = { questID = 93949 }
    local pool = { EnumerateActive = function() return pairs({ [row] = true }) end } -- the pools' proxy: methods only
    _G.QuestScrollFrame = { Contents = {}, titleFramePool = pool }
    _G.QuestMapFrame = { QuestsFrame = { ScrollFrame = _G.QuestScrollFrame } }
    taint.layoutIndex = { t = row, by = "WoWForeverJapanese" }
    row.layoutIndex = 1
    local fields = TW.scan("slash")
    assert.are.equal(1, fields)
    local scan = entriesOf("taint")[1].fields
    assert.is_truthy(scan:find("QuestScrollFrame.titleFramePool[93949].layoutIndex", 1, true))
    _G.QuestScrollFrame, _G.QuestMapFrame = nil, nil
  end)

  it("a quest shown in the quest log logs who wrote its id when that came out tainted", function()
    local hooks = {}
    _G.hooksecurefunc = function(t, fn) -- the global form: (name, hook)
      if type(t) == "string" then hooks[t] = fn end
    end
    _G.C_Timer = { NewTicker = function() end }
    _G.QuestMapFrame_ShowQuestDetails = function() end
    _G.QuestMapFrame = { DetailsFrame = { questID = 5 } }
    TW.init()
    assert.is_function(hooks.QuestMapFrame_ShowQuestDetails)
    hooks.QuestMapFrame_ShowQuestDetails(5)
    assert.are.equal(0, #entriesOf("write"))
    taint.questID = { t = _G.QuestMapFrame.DetailsFrame, by = "WoWForeverJapanese" }
    hooks.QuestMapFrame_ShowQuestDetails(5)
    assert.is_truthy(entriesOf("write")[1].msg:find("^QuestMapFrame%.DetailsFrame%.questID"))
    _G.QuestMapFrame_ShowQuestDetails, _G.QuestMapFrame = nil, nil
  end)

  it("a clicked quest block logs which of its own keys and its module's read as tainted", function()
    local hooked = {}
    _G.hooksecurefunc = function(t, m, fn)
      if type(t) == "table" then hooked[(t.name or "?") .. ":" .. m] = fn end
    end
    _G.C_Timer = { NewTicker = function() end }
    _G.ObjectiveTrackerFrame = { name = "ObjectiveTrackerFrame", UpdateTopPadding = function() end,
      MarkDirty = function() end }
    _G.QuestObjectiveTracker = { name = "QuestObjectiveTracker", OnBlockHeaderClick = function() end }
    TW.init()
    local click = hooked["QuestObjectiveTracker:OnBlockHeaderClick"]
    assert.is_function(click)
    local block = { id = 93949, OnHeaderClick = function() end, parentModule = _G.QuestObjectiveTracker }
    click(_G.QuestObjectiveTracker, block)
    assert.are.equal(0, #entriesOf("write"))
    taint.OnHeaderClick = { t = block, by = "WoWForeverJapanese" }
    click(_G.QuestObjectiveTracker, block)
    assert.is_truthy(entriesOf("write")[1].msg:find("^QuestObjectiveTracker block%.OnHeaderClick"))
    _G.ObjectiveTrackerFrame, _G.QuestObjectiveTracker = nil, nil
  end)

  it("a block in combat queues its scan until combat is over", function()
    local fighting = true
    _G.InCombatLockdown = function() return fighting end
    assert.is_true(TW.onBlocked())
    assert.are.equal(0, #entriesOf("taint"))
    assert.is_false(TW.scanWhenSafe())
    fighting = false
    assert.is_true(TW.scanWhenSafe())
    assert.are.equal(1, #entriesOf("taint"))
    assert.is_false(TW.scanWhenSafe()) -- once
    _G.InCombatLockdown = nil
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

  it("a tracker MarkDirty called by tainted code logs its caller's stack; a clean one logs nothing", function()
    local hooks = {}
    _G.hooksecurefunc = function(t, m, fn)
      if type(t) == "table" then
        local orig = t[m]
        t[m] = function(...) orig(...); fn(...) end
        hooks[#hooks + 1] = (t.name or "?") .. ":" .. m
      end
    end
    _G.C_Timer = { NewTicker = function() end }
    _G.ObjectiveTrackerFrame = { name = "ObjectiveTrackerFrame", UpdateTopPadding = function() end,
      MarkDirty = function(self) self.dirty = true end }
    TW.init()
    assert.is_truthy(table.concat(hooks, " "):find("ObjectiveTrackerFrame:MarkDirty", 1, true))
    _G.ObjectiveTrackerFrame:MarkDirty()
    assert.are.equal(0, #entriesOf("write"))
    taint.dirty = { t = _G.ObjectiveTrackerFrame, by = "WoWForeverJapanese" }
    _G.ObjectiveTrackerFrame:MarkDirty()
    local w = entriesOf("write")
    assert.are.equal(1, #w)
    assert.is_truthy(w[1].msg:find("^ObjectiveTrackerFrame%.dirty"))
    assert.is_truthy(w[1].stack:find("Blizzard_X", 1, true))
    _G.ObjectiveTrackerFrame = nil
  end)
  it("keeps 200 lines; the addon's own passes go in as \"wfj <label>\", a run of the same one as one ×n line",
    function()
      assert.are.equal(200, TW.RING)
      TW.onEvent("BAG_UPDATE", 0)
      TW.trail("items")
      TW.trail("items")
      TW.trail("items")
      TW.trail("bags")
      TW.onEvent("ITEM_LOCK_CHANGED")
      TW.trail("bags")
      local lines = {}
      for line in TW.events():gmatch("[^\n]+") do lines[#lines + 1] = line end
      assert.are.same({ "10:00:00 BAG_UPDATE 0", "10:00:00 wfj items ×3", "10:00:00 wfj bags",
        "10:00:00 ITEM_LOCK_CHANGED", "10:00:00 wfj bags" }, lines)
    end)

  it("scans once for each different block, and a repeat of the same block scans no more", function()
    local first = { msg = "UseContainerItem() <ContainerFrame.lua:1611>" }
    local other = { msg = "Button:SetPassThroughButtons() <MapCanvas_DataProviderBase.lua:290>" }
    assert.is_true(TW.onBlocked(first))
    assert.is_false(TW.onBlocked(first))
    assert.is_true(TW.onBlocked(other))
    -- one scan runs for the blocks queued before it, each different block keeps its own events
    local contexts = entriesOf("context")
    assert.are.equal(2, #contexts)
    assert.are.equal("events before " .. first.msg, contexts[1].msg)
    assert.are.equal("events before " .. other.msg, contexts[2].msg)
    assert.is_string(contexts[2].events)
  end)

  it("a frame of the addon's passes goes in before the events that came after it", function()
    local now = 1
    WFJ.Perf.setDeps({ clock = function() return 0 end, frame = function() return now end, trail = TW.trail })
    local t0 = WFJ.Perf.start("bags")
    WFJ.Perf.stop("bags", t0, 0)
    now = 2 -- the frame is over; the next thing in the ring is a game event
    TW.onEvent("BAG_UPDATE", 0)
    local lines = {}
    for line in TW.events():gmatch("[^\n]+") do lines[#lines + 1] = line end
    assert.are.same({ "10:00:00 wfj bags", "10:00:00 BAG_UPDATE 0" }, lines)
    WFJ.Perf.setDeps({})
  end)

  it("a tainted writer that runs again is only counted: its stack and events are kept from the first time", function()
    taint.showAllButtons = { t = _G.MultiBarLeft, by = "WoWForeverJapanese" }
    local reads = 0
    local events = TW.events
    TW.events = function() reads = reads + 1; return events() end
    for _ = 1, 5 do TW.wrote("MultiBarLeft.showAllButtons", _G.MultiBarLeft, "showAllButtons") end
    TW.events = events
    local w = entriesOf("write")
    assert.are.same({ 1, 5, 1 }, { #w, w[1].n, reads })
  end)

  it("the scan walks the bag frames and every table the addon's declarations resolved to", function()
    local button = { bagID = 0 }
    _G.ContainerFrame1 = { Items = { button } }
    local declared = { name = "SomeWindow", note = 1 }
    _G.SomeWindow = declared
    WFJ.Compat.declare("demo", "window", { "SomeWindow" })
    assert.are.equal(declared, WFJ.Compat.get("demo", "window"))
    taint.bagID = { t = button, by = "WoWForeverJapanese" }
    taint.note = { t = declared, by = "WoWForeverJapanese" }
    assert.are.equal(2, TW.scan("slash"))
    local scan = entriesOf("taint")[1].fields
    assert.is_truthy(scan:find("ContainerFrame1.Items[1].bagID (WoWForeverJapanese)", 1, true))
    assert.is_truthy(scan:find("demo.window.note (WoWForeverJapanese)", 1, true))
    _G.ContainerFrame1, _G.SomeWindow = nil, nil
  end)

  it("a value the bag item click reads that turns tainted is logged with the events before it", function()
    _G.MerchantFrame = { selectedTab = 1 }
    TW.fields = nil
    assert.are.equal(0, TW.checkFields("load"))
    taint.MerchantFrame = { by = "WoWForeverJapanese" }
    taint.selectedTab = { t = _G.MerchantFrame, by = "WoWForeverJapanese" }
    assert.are.equal(2, TW.checkFields("timer"))
    local msgs = {}
    for _, e in ipairs(entriesOf("turned")) do msgs[#msgs + 1] = e.msg end
    table.sort(msgs)
    assert.are.same({ "MerchantFrame", "MerchantFrame.selectedTab" }, msgs)
    _G.MerchantFrame = nil
  end)
end)
