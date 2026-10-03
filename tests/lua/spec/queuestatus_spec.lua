-- The queue status HUD: UI/QueueStatus.lua over a QueueStatusFrame replayed from Forever
-- blizzard_queuestatusframe/mainline/queuestatusframe.lua. Update (:522–721) refills the pooled entries
-- (statusEntriesPool, :518) through QueueStatusEntry_SetMinimalDisplay / _SetFullDisplay (:1095–1252);
-- QueueStatusEntry_OnUpdate (:1254–1263) rewrites the queue timer. Battleground, dungeon and player names stay English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/QueueStatus.lua"

local UI = {
  QUEUED_STATUS_WAITING = { "Waiting", "待機中" },
  QUEUED_STATUS_PROPOSAL = { "Ready To Enter", "入場可能" },
  QUEUED_STATUS_LOCKED_EXPLANATION = { "You are locked to this match until it finishes.",
    "この試合が終わるまで離脱できません。" },
  HUD_EDIT_MODE_TITLE = { "HUD Edit Mode", "HUD編集モード" },
  RAID = { "Raid", "レイド" }, -- a dictionary word a queue may be NAMED
  -- The queue timer's "< 1 minute" (queuestatusframe.lua:1083–1086), a duration entry of the `time` kind
  TIME_IN_QUEUE = { "Time In Queue: %s", "待機時間: %s" }, LESS_THAN_ONE_MINUTE = { "< 1 minute", "1分未満" },
  -- an active battlefield's long description, GetBattlefieldStatus's 11th return (queuestatusframe.lua:801,
  -- 812–815; client-table row: no global; ADR-042)
  ["PvpLongDescription:7"] = { "Capture the enemy flag three times.", "敵の旗を3回奪取せよ。" },
}
local function en(key) return UI[key][1] end
local function ja(key) return UI[key][2] end

local Q = {} -- the replayed queues: { { title, status, subtitle, time, extra } }

local function entryPool()
  local p = { active = {}, inactive = {} }
  function p.Acquire(self)
    local e = table.remove(self.inactive)
    if not e then
      e = CreateFrame("Frame")
      for _, k in ipairs({ "Title", "Status", "SubTitle", "TimeInQueue", "AverageWait", "ExtraText" }) do
        e[k] = Stub.fontString("")
      end
      e.TanksFound = { Count = Stub.fontString("") }
    end
    self.active[#self.active + 1] = e
    return e
  end
  function p.ReleaseAll(self)
    for _, e in ipairs(self.active) do self.inactive[#self.inactive + 1] = e end
    self.active = {}
  end
  function p.EnumerateActive(self)
    local i = 0
    return function()
      i = i + 1
      return self.active[i]
    end
  end
  return p
end

local function installQueueStatus()
  local frame = CreateFrame("Frame", "QueueStatusFrame")
  frame.statusEntriesPool = entryPool()
  function frame.Update(self)
    self.statusEntriesPool:ReleaseAll()
    for _, q in ipairs(Q) do
      local e = self.statusEntriesPool:Acquire()
      e.Title.text, e.Status.text, e.SubTitle.text = q.title, q.status, q.subtitle or ""
      e.TimeInQueue.text, e.ExtraText.text = q.time or "", q.extra or ""
      e.TanksFound.Count.text = "1/2"
    end
  end
  _G.QueueStatusEntry_OnUpdate = function(entry) entry.TimeInQueue.text = entry.nextTime end
  return frame
end

local GLOBALS = { "QueueStatusFrame", "QueueStatusEntry_OnUpdate" }

describe("the queue status panel on Forever", function()
  local WFJ

  local function load()
    local ns = H.loadChunks(FILES)
    H.uiSetup(ns, UI)
    return ns
  end

  local function fresh()
    H.uiTeardown()
    for _, n in ipairs(GLOBALS) do _G[n] = nil end
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
  end

  local function entries()
    local out = {}
    for e in _G.QueueStatusFrame.statusEntriesPool:EnumerateActive() do out[#out + 1] = e end
    return out
  end

  before_each(function()
    fresh()
    WFJ = load()
    installQueueStatus()
    Q = { { title = "Raid", status = en("QUEUED_STATUS_WAITING"), subtitle = "Warsong Gulch",
      extra = "Also queued for: Raid" } }
    assert.is_true(WFJ.QueueStatus.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, n in ipairs(GLOBALS) do _G[n] = nil end
  end)

  it("Update: the status word translates; the queue's name, the extra text and the counts stay English", function()
    _G.QueueStatusFrame:Update()
    local e = entries()[1]
    assert.are.equal(ja("QUEUED_STATUS_WAITING"), e.Status:GetText())
    assert.are.equal("Raid", e.Title:GetText()) -- a queue NAMED like a dictionary word
    assert.are.equal("Warsong Gulch", e.SubTitle:GetText())
    assert.are.equal("Also queued for: Raid", e.ExtraText:GetText())
    assert.are.equal("1/2", e.TanksFound.Count:GetText())
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal(en("QUEUED_STATUS_WAITING"), e.Status:GetText())
  end)

  it("an active battlefield's SubTitle is a PvpLongDescription row's Japanese; Alt shows English; other subtitles"
    .. " stay English", function()
    Q = { { title = "Warsong Gulch", status = "In Progress", subtitle = "Capture the enemy flag three times." },
      { title = "Arathi Basin", status = "In Progress", subtitle = "Raid" } }
    _G.QueueStatusFrame:Update()
    local list = entries()
    assert.are.equal("敵の旗を3回奪取せよ。", list[1].SubTitle:GetText())
    assert.are.equal("Warsong Gulch", list[1].Title:GetText())
    assert.are.equal("Raid", list[2].SubTitle:GetText()) -- a dictionary word, no family row: English
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal("Capture the enemy flag three times.", list[1].SubTitle:GetText())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    assert.are.equal("敵の旗を3回奪取せよ。", list[1].SubTitle:GetText())
  end)

  it("pooled entries are keyed by widget: a reused entry shows its new lines", function()
    _G.QueueStatusFrame:Update()
    Q = { { title = en("HUD_EDIT_MODE_TITLE"), status = en("QUEUED_STATUS_PROPOSAL"),
      subtitle = en("QUEUED_STATUS_LOCKED_EXPLANATION") } }
    _G.QueueStatusFrame:Update()
    local e = entries()[1]
    assert.are.equal(ja("HUD_EDIT_MODE_TITLE"), e.Title:GetText())
    assert.are.equal(ja("QUEUED_STATUS_PROPOSAL"), e.Status:GetText())
    assert.are.equal(ja("QUEUED_STATUS_LOCKED_EXPLANATION"), e.SubTitle:GetText())
  end)

  it("the entry tick leaves a timer line it cannot match as the client wrote it", function()
    _G.QueueStatusFrame:Update()
    local e = entries()[1]
    e.nextTime = "Time In Queue: soon"
    assert.has_no.errors(function() _G.QueueStatusEntry_OnUpdate(e, 0.1) end)
    assert.are.equal("Time In Queue: soon", e.TimeInQueue:GetText())
  end)

  it("the timer's \"< 1 minute\" is a duration entry, shown in Japanese; Alt English", function()
    _G.QueueStatusFrame:Update()
    local e = entries()[1]
    e.nextTime = "Time In Queue: < 1 minute"
    _G.QueueStatusEntry_OnUpdate(e, 0.1)
    assert.are.equal("待機時間: 1分未満", e.TimeInQueue:GetText())
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal("Time In Queue: < 1 minute", e.TimeInQueue:GetText())
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    fresh()
    local ns = load()
    local frame = installQueueStatus()
    frame.statusEntriesPool = 7
    _G.QueueStatusEntry_OnUpdate = "not a function"
    assert.has_no.errors(function() assert.is_true(ns.QueueStatus.init()) end)
    assert.has_no.errors(function()
      ns.QueueStatus.showEntry("x")
      ns.QueueStatus.showEntry({ Title = 4, Status = false, TanksFound = "x" })
      ns.QueueStatus.onEntryTick({ TimeInQueue = 1 })
    end)
  end)

  it("hooks install once; a client without QueueStatusFrame is skipped without error", function()
    assert.is_false(WFJ.QueueStatus.init())
    assert.are.equal(1, #Stub.hooks["QueueStatusFrame:Update"])
    fresh()
    local bare = load()
    assert.has_no.errors(function() assert.is_false(bare.QueueStatus.init()) end)
  end)
end)
