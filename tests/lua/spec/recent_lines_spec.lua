-- Core/RecentLines and its one feed, UI/Render's sync.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local function pureNS(lookup)
  H.coreStub()
  local ns = {}
  H.loadChunks({ "Core/Const.lua", "Core/Normalize.lua", "Core/Hash.lua" }, ns)
  ns.Lookup = { get = lookup }
  H.loadPure("Core/RecentLines.lua", "WoWForeverJapanese", ns)
  return ns
end

describe("Core/RecentLines", function()
  local WFJ, R
  local rows = {
    ["quest.description"] = { [7] = { ja = "旅の者よ。", status = "." } },
    ["quest.title"] = { [7] = { ja = "旅立ち", status = "." } },
    ui = { OKAY = { ja = "了解", status = "." } },
    gossip = { ["0001ce030c010973"] = { ja = "ようこそ。", status = "." } },
    book = { ["00aa11bb22cc33dd"] = { ja = "本の頁。", status = "." } },
    ["item.description"] = { [25] = { variants = { "a", "b" }, status = "u" } }, -- a branch line (ADR-043)
    objective = { [5] = { ja = "目標の文", status = "." } },
  }
  before_each(function()
    WFJ = pureNS(function(kind, id) return rows[kind] and rows[kind][id] or nil end)
    R = WFJ.RecentLines
  end)

  it("reads a Lookup kind as the store's type and field", function()
    assert.are.same({ "quest", "title" }, { R.address("quest.title") })
    assert.are.same({ "ui", "text" }, { R.address("ui") })
    assert.are.same({ "gossip", "text" }, { R.address("gossip") })
    assert.are.same({ "book", "text" }, { R.address("book") })
    assert.are.same({ "item", "description" }, { R.address("item.description") })
    assert.are.same({ "spell", "aura" }, { R.address("spell.aura") })
    assert.are.same({ "objective", "text" }, { R.address("objective") })
    assert.are.same({ "area", "text" }, { R.address("area") })
    assert.is_nil(R.address("quest")) -- five fields: a bare quest kind names no line
    assert.is_nil(R.address("quest.nope"))
    assert.is_nil(R.address("unit"))
  end)

  it("records the address, the hash of the stored Japanese, the surface and the Japanese, never English",
    function()
    local rec = R.note("quest.description", 7, "questframe")
    assert.are.same({ type = "quest", id = 7, field = "description", ja_hash = WFJ.Hash.key("旅の者よ。"),
      ja = "旅の者よ。", surface = "questframe", group = "story", burst = 1, seq = 1 }, rec)
    assert.are.equal("book", R.note("book", "00aa11bb22cc33dd", {}).type) -- a table surface is not a name
    assert.is_nil(R.list()[1].surface)
  end)

  it("a branch line, an untranslated line or an unknown kind records nothing", function()
    assert.is_nil(R.note("item.description", 25, "tooltip"))
    assert.is_nil(R.note("quest.title", 999, "questframe"))
    assert.is_nil(R.note("unit", 1, "tooltip"))
    assert.are.equal(0, #R.list())
  end)

  it("keeps the text as shown, without the inline marker message or colour codes", function()
    local rec = R.note("ui", "OKAY", "s", "|cff808080[古い翻訳]|r\n了解 |cffffd100Reyn|r")
    assert.are.equal("了解 Reyn", rec.shown)
    assert.are.equal("了解", rec.ja) -- the stored line (what ja_hash is of) is untouched
    assert.is_nil(R.note("quest.title", 7, "s").shown)
  end)

  it("lists the newest burst first and each burst in the order it was written (the on-screen order)", function()
    R.note("quest.title", 7, "questframe", nil, 10.0)       -- the quest window: title, text, objective
    R.note("quest.description", 7, "questframe", nil, 10.0)
    R.note("objective", 5, "questframe", nil, 10.2)
    R.note("gossip", "0001ce030c010973", "gossip", nil, 30.0) -- later, an NPC
    local order = {}
    for i, rec in ipairs(R.list()) do order[i] = rec.type .. "." .. rec.field end
    assert.are.same({ "gossip.text", "quest.title", "quest.description", "objective.text" }, order)
    R.note("quest.title", 7, "questframe", nil, 40.0) -- the same surface after a pause starts a new burst
    assert.are.equal("title", R.list()[1].field)
    assert.are.equal("gossip", R.list()[2].type)
  end)

  it("groups lines (story / tooltips / windows) and caps each group on its own", function()
    R.note("quest.title", 7, "q")
    for i = 1, 150 do rows.ui["G" .. i] = { ja = "語" .. i, status = "." } end
    for i = 1, 150 do R.note("ui", "G" .. i, "s") end
    assert.are.equal(1, #R.list("story"))
    assert.are.equal("quest", R.list("story")[1].type)
    assert.are.equal(R.CAP, #R.list("windows"))
    assert.are.equal(R.CAP + 1, #R.list("all"))
    assert.are.equal(R.CAP + 1, #R.list())
    assert.are.equal(0, #R.list("tooltips"))
    assert.are.equal("story", R.group("gossip"))
    assert.are.equal("tooltips", R.group("spell"))
  end)

  it("newest first, a repeat moves to the front, at most 100", function()
    R.note("quest.title", 7, "a")
    R.note("ui", "OKAY", "b")
    R.note("quest.title", 7, "c")
    local l = R.list()
    assert.are.equal(2, #l)
    assert.are.equal("title", l[1].field)
    assert.are.equal("c", l[1].surface)
    rows.ui.many = nil
    for i = 1, 150 do rows.ui["K" .. i] = { ja = "語" .. i, status = "." } end
    for i = 1, 150 do R.note("ui", "K" .. i, "s") end
    l = R.list("windows")
    assert.are.equal(R.CAP, #l)
    assert.are.equal("K150", l[1].id)
    assert.are.equal("K51", l[100].id)
    R.clear()
    assert.are.equal(0, #R.list())
  end)
end)

describe("UI/Render feeds Core/RecentLines only on a primary apply", function()
  local WFJ, fs

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    local files = {}
    for i, f in ipairs(H.UI_FILES) do files[i] = f end
    files[#files + 1] = "Core/RecentLines.lua"
    WFJ = H.loadChunks(files)
    local rows = H.uiSetup(WFJ, { OKAY = { "Okay", "了解" }, CANCEL = { "Cancel", "キャンセル" } })
    WFJ.Lookup = { get = function(kind, id)
      if kind ~= "ui" or not rows[id] then return nil end
      return { ja = rows[id][1], status = rows[id][3] }
    end }
    WFJ.Settings.load(nil, 1, {})
    fs = Stub.fontString("Okay")
  end)
  after_each(function() H.uiTeardown() end)

  it("releasing the reveal key re-records nothing and reorders nothing", function()
    WFJ.Render.show("testsurface", "k1", fs, "Okay", "ui", "ui", "OKAY")
    WFJ.Render.show("testsurface", "k2", Stub.fontString("Cancel"), "Cancel", "ui", "ui", "CANCEL")
    local before = {}
    for i, r in ipairs(WFJ.RecentLines.list()) do before[i] = r.id .. "#" .. r.seq end
    assert.are.equal(2, #before)
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    Stub.keys.alt = false; WFJ.Modifier.refresh() -- every applied record is written again
    local after = {}
    for i, r in ipairs(WFJ.RecentLines.list()) do after[i] = r.id .. "#" .. r.seq end
    assert.are.same(before, after) -- (a line shown again by the client moves to the front: the newest-first test above)
  end)

  it("an applied line is recorded with its surface; English shown (Alt, master off, no translation) is not",
    function()
    WFJ.Render.show("testsurface", "k1", fs, "Okay", "ui", "ui", "OKAY")
    assert.are.equal("了解", fs:GetText())
    local l = WFJ.RecentLines.list()
    assert.are.equal(1, #l)
    assert.are.same({ type = "ui", id = "OKAY", field = "text", ja_hash = WFJ.Hash.key("了解"), ja = "了解",
      surface = "testsurface", shown = "了解", group = "windows", burst = 1, seq = 1 }, l[1])
    WFJ.RecentLines.clear()
    Stub.keys.alt = true; WFJ.Modifier.refresh() -- holding the reveal key: English
    WFJ.Render.show("testsurface", "k2", Stub.fontString("Cancel"), "Cancel", "ui", "ui", "CANCEL")
    assert.are.equal(0, #WFJ.RecentLines.list())
    -- letting go writes the Japanese again: only the line never recorded before (k2) is added; k1 was recorded when
    -- it was first shown, and a refresh never re-records or reorders
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal(1, #WFJ.RecentLines.list())
    assert.are.equal("CANCEL", WFJ.RecentLines.list()[1].id)
    WFJ.RecentLines.clear()
    WFJ.State.setEnabled(false)
    WFJ.Render.show("testsurface", "k3", Stub.fontString("Cancel"), "Cancel", "ui", "ui", "CANCEL")
    assert.are.equal(0, #WFJ.RecentLines.list())
    WFJ.State.setEnabled(true) -- back on: the lines are written again; only k3, never recorded, is added
    assert.are.equal(1, #WFJ.RecentLines.list())
    assert.are.equal("CANCEL", WFJ.RecentLines.list()[1].id)
    WFJ.RecentLines.clear()
    WFJ.Render.show("testsurface", "k4", Stub.fontString("Nope"), "Nope", "ui", "ui", "NOPE")
    assert.are.equal(0, #WFJ.RecentLines.list())
  end)

  it("a companion record (ctx.follow) is not a line of its own", function()
    WFJ.Render.show("tip", "desc", fs, "Okay", "ui", "ui", "OKAY")
    WFJ.Render.show("tip", "desc.2", Stub.fontString("more"), "more", "ui", "ui", "OKAY", { follow = "desc" })
    assert.are.equal(1, #WFJ.RecentLines.list())
  end)

  it("a RecentLines failure is counted and never stops the write", function()
    WFJ.RecentLines.note = function() error("boom") end
    WFJ.Render.show("testsurface", "k1", fs, "Okay", "ui", "ui", "OKAY")
    assert.are.equal("了解", fs:GetText())
    assert.are.equal(1, WFJ.Render.recentErrors)
  end)
end)

describe("every Render.show caller records a store line or nothing", function()
  -- The kinds each caller passes (read from the file at the listed lines). A new caller must be added here.
  local CALLERS = {
    ["UI/QuestFrame.lua"] = { "quest.title", "quest.objectives", "quest.description", "quest.progress",
      "quest.completion", "gossip" }, -- the greeting prose is gossip
    ["UI/QuestMap.lua"] = { "quest.title", "objective", "area", "ui" },
    ["UI/Tooltip.lua"] = { "item.description", "spell.description", "spell.aura", "ui" },
    ["UI/Labels.lua"] = { "ui" },
    ["UI/Talents.lua"] = { "ui" },
    ["UI/Popups.lua"] = { "ui" },
    ["UI/ItemText.lua"] = { "book" },
    ["UI/DamageMeter.lua"] = { "ui" },
    ["UI/CombatText.lua"] = { "ui" },
    ["UI/Gossip.lua"] = { "gossip" },
    ["UI/TooltipUnit.lua"] = { "quest.title" },
  }

  it("lists exactly the files that call Render.show (directly or passed on, as UI/Gossip does)", function()
    local found = {}
    local dirs = '"' .. H.ADDON_DIR .. '/UI" "' .. H.ADDON_DIR .. '/Core"'
    local p = assert(io.popen('grep -rlE "Render\\.show[^A-Za-z_]" ' .. dirs))
    for path in p:lines() do
      local rel = path:sub(#H.ADDON_DIR + 2)
      if rel ~= "UI/Render.lua" then found[rel] = true end
    end
    p:close()
    for rel in pairs(found) do assert.is_not_nil(CALLERS[rel], rel .. " calls Render.show: list its kinds") end
    for rel in pairs(CALLERS) do assert.is_true(found[rel] == true, rel .. " no longer calls Render.show") end
  end)

  it("every kind a caller passes names one store line", function()
    H.coreStub()
    local ns = {}
    H.loadChunks({ "Core/Const.lua" }, ns)
    H.loadPure("Core/RecentLines.lua", "WoWForeverJapanese", ns)
    for rel, kinds in pairs(CALLERS) do
      for _, kind in ipairs(kinds) do
        local type_, field = ns.RecentLines.address(kind)
        assert.is_not_nil(type_, rel .. " " .. kind)
        assert.is_not_nil(field, rel .. " " .. kind)
      end
    end
  end)
end)
