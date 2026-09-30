-- UI/Gossip: the NPC talk window's greeting and option rows on the pooled ScrollBox (gossip_client.lua replays
-- the client). Every assertion about writes uses the stub's addon counters, so the client's own writes never count.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

-- the UI files too; a quest-prepended option shows its prepend through UI/Labels
local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "UI/Gossip.lua"

local PLAYER = { name = "Reyn", class = "Hunter", race = "Night Elf" }
local NPC = { name = "Innkeeper Allison", guid = "Creature-0-4372-0-17-6740-0000A1B2C3" }
local LONG_JA = "とても長い日本語の選択肢で、この行は二行に折り返されるはずです" -- wraps in a 275 px row

local function isJapanese(text)
  return type(text) == "string" and text:find("[\227-\233]") ~= nil
end

describe("UI/Gossip: the NPC talk window", function()
  local WFJ, S, SS, G, C, sb, data, db

  local function key(en) return C.key(en, PLAYER) end

  -- ja rows by English: { [en] = "ja" | { ja, status } }
  local function ship(rows)
    data = {}
    for en, v in pairs(rows) do
      local ja, status = v, "."
      if type(v) == "table" then ja, status = v[1], v[2] end
      data[key(en)] = { ja = ja, status = status }
    end
  end

  local function setup(viewRows)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installGossipAPI(viewRows)
    WFJ = H.loadChunks(FILES)
    S, SS, G, C = WFJ.Settings, WFJ.SurfaceState, WFJ.Gossip, WFJ.Collector
    WFJ.Compat.init(function(name) return _G[name] end)
    S.load(nil, 1, {})
    db = C.load(nil, H.collectorDeps({ lookup = function(kind, id)
      if kind == "gossip" then return data[id] end
    end }))
    data = {}
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id) if kind == "gossip" then return data[id] end end,
      marker = function(n) return S.get("marker." .. n) end,
    }))
    assert.is_true(G.init({ key = key }))
    sb = GossipFrame.GreetingPanel.ScrollBox
  end

  local function textOf(f)
    if f.GreetingText then return f.GreetingText:GetText() end
    return f:GetText()
  end

  local function fontOf(f)
    if f.GreetingText then return { f.GreetingText:GetFont() } end
    return { f:GetFontString():GetFont() }
  end

  -- every visible row is as tall as its extent, sits where the extents put it, and ends where the next row starts
  -- (the client stacks rows by their heights at the last layout; a row resized since would overlap or leave a gap).
  local function assertLayout()
    local rows = sb:visibleIndices()
    for n, i in ipairs(rows) do
      local f = sb.frames[i]
      assert.are.equal(sb.extents[i], f:GetHeight(), "row " .. i .. " height vs extent")
      assert.are.equal(sb:extentUntil(i), f.top, "row " .. i .. " top")
      local nxt = rows[n + 1] and sb.frames[rows[n + 1]]
      if nxt then assert.are.equal(f.top + f:GetHeight(), nxt.top, "row " .. i .. " overlaps or gaps") end
    end
  end

  local function options(n)
    local out = {}
    for i = 1, n do out[i] = "Option number " .. i end
    return out
  end

  before_each(function() setup() end)

  it("greeting and options translate by the gossip key of their API English", function()
    local greeting = "Greetings, Reyn. The hunter spirits are restless tonight."
    ship({ [greeting] = "ごきげんよう。今夜は精霊が騒がしい。", ["Make this inn your home."] = "この宿を拠点にする。",
      ["Reyn, what can a hunter do at an inn?"] = LONG_JA })
    Stub.showGossip({ text = greeting, npc = NPC,
      options = { "Make this inn your home.", "Reyn, what can a hunter do at an inn?", "Let me browse your goods." } })

    local rows = sb.frames
    assert.are.equal("ごきげんよう。今夜は精霊が騒がしい。", rows[1].GreetingText:GetText())
    assert.are.same({ WFJ.Font.PATH, 13, "" }, fontOf(rows[1]))
    assert.are.equal("この宿を拠点にする。", rows[4]:GetText())
    assert.are.same({ WFJ.Font.PATH, 12, "" }, fontOf(rows[4]))
    assert.are.equal(LONG_JA, rows[5]:GetText())
    assert.are.equal("Let me browse your goods.", rows[6]:GetText())
    assert.are.same({ "Fonts\\FRIZQT__.TTF", 12, "" }, fontOf(rows[6]))

    local rec = SS.get("gossip", "greeting")
    assert.are.equal("gossip", rec.meta.kind)
    assert.are.equal("gossip", rec.meta.area)
    assert.are.equal(key(greeting), rec.meta.id)
    assert.is_table(SS.get("gossip", "option.0"))
    assert.are.equal(key("Reyn, what can a hunter do at an inn?"), SS.get("gossip", "option.1").meta.id)
    -- the render key is the collector's stored hash: name and lowercase class both became tokens. The greeting has a
    -- shipped row, so it is known and not stored; the untranslated option is stored under its key.
    assert.is_nil(db.entries["gossip:" .. key(greeting) .. ":text"])
    assert.is_table(db.entries["gossip:" .. key("Let me browse your goods.") .. ":text"])
    data = {}
    C.clear()
    C.recordGossip(greeting, NPC.guid)
    local stored = db.entries["gossip:" .. key(greeting) .. ":text"]
    assert.is_table(stored)
    assert.are.equal("Greetings, $N. The $C spirits are restless tonight.", stored.e)
    assert.are.same({ 6740 }, stored.n)
  end)

  it("pooled rows reused across scrolling always show their own option's text", function()
    setup(5)
    local names = options(12)
    ship({ [names[2]] = "二番目の選択肢", [names[5]] = LONG_JA, [names[11]] = "十一番目" })
    local own = { [names[2]] = "二番目の選択肢", [names[5]] = LONG_JA, [names[11]] = "十一番目" }
    Stub.showGossip({ text = "Hello.", options = names, npc = NPC })

    local function check(alt)
      for _, i in ipairs(sb:visibleIndices()) do
        local f, ed = sb.frames[i], sb.frames[i].elementData
        if ed.info then
          local want = (not alt and own[ed.info.name]) or ed.info.name
          assert.are.equal(want, f:GetText(), "row " .. i)
        end
      end
      for _, rec in pairs(SS.records("gossip")) do
        local row = rec.meta.ctx.row
        assert.is_true(row.shown, rec.key)
        assert.is_nil(sb.released[row], rec.key .. " is on a released frame")
      end
    end

    check(false)
    sb:scrollTo(10)
    check(false)
    sb:scrollTo(4)
    check(false)
    sb:scrollTo(0)
    check(false)
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    check(true)
    sb:scrollTo(10)
    check(true)
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    check(false)
  end)

  it("row heights follow the shown text: first window of the session, scroll, Alt and release", function()
    setup(5)
    local names = options(12)
    ship({ ["Welcome."] = LONG_JA .. LONG_JA, [names[1]] = LONG_JA, [names[3]] = LONG_JA, [names[12]] = LONG_JA })
    Stub.showGossip({ text = "Welcome.", options = names, npc = NPC })
    -- measured in English before the measure widgets were hooked: laid out once more after Update
    assert.are.equal(1, sb.calls.FullUpdate)
    assert.is_true(isJapanese(sb.frames[4]:GetText()))
    assertLayout()
    local greetingMeasure, optionMeasure = G.measureWidgets()
    assert.are.equal(Stub.gossipMeasure.greeting.GreetingText, greetingMeasure)
    assert.are.equal(Stub.gossipMeasure.option, optionMeasure)
    for _, rec in pairs(SS.records("gossip")) do
      assert.are_not.equal(greetingMeasure, rec.fs)
      assert.are_not.equal(optionMeasure, rec.fs.button)
    end

    sb:scrollTo(10)
    assertLayout()
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(names[12], sb.frames[15]:GetText())
    assertLayout()
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal(LONG_JA, sb.frames[15]:GetText())
    assertLayout()

    -- the next window: the hooks exist, so the client's own layout is already right
    local before = sb.calls.FullUpdate
    Stub.closeGossip()
    Stub.showGossip({ text = "Welcome.", options = names, npc = NPC })
    assert.are.equal(before, sb.calls.FullUpdate)
    assertLayout()
  end)

  it("quest rows and a prepend-decorated option are never written and never recorded", function()
    setup(10)
    ship({ ["Tell me about the Scourge."] = "スカージについて教えて。", ["A Quest"] = "クエスト" })
    Stub.showGossip({ text = "Hail.", npc = NPC, available = { "A Quest" }, active = { "Another Quest" },
      options = { { name = "Tell me about the Scourge.", orderIndex = 0, prepend = true } } })
    local seen = 0
    for _, i in ipairs(sb:visibleIndices()) do
      local f = sb.frames[i]
      if f.kind == "available" or f.kind == "active" or (f.kind == "option") then
        seen = seen + 1
        local fs = f:GetFontString()
        assert.are.equal(0, fs.calls.addonSetText, f.kind)
        assert.are.equal(0, fs.calls.addonSetFont, f.kind)
        assert.is_false(isJapanese(f:GetText()))
      end
    end
    assert.are.equal(3, seen)
    assert.is_nil(SS.get("gossip", "option.0"))
    for _, rec in pairs(SS.records("gossip")) do assert.are.equal("greeting", rec.key) end
    local m = Stub.gossipMeasure
    for _, w in ipairs({ m.option, m.active, m.available }) do
      assert.are.equal(0, w:GetFontString().calls.addonSetText)
    end
  end)

  it("a prepend-decorated option shows the prepend in Japanese, the option's text as written",
    function()
      setup(10)
      ship({})
      H.uiSetup(WFJ, { GOSSIP_OPTION_PREPEND = { "|cff0000ff(%s)|r %s", "|cff0000ff(%s)|r %s" },
        QUEST_PREPEND = { "Quest", "クエスト" } }, { lookup = function(kind, id)
          if kind == "gossip" then return data[id] end
        end })
      Stub.showGossip({ text = "Hail.", npc = NPC,
        options = { { name = "Tell me about the Scourge. Now.", orderIndex = 0, prepend = true } } })
      local row
      for _, i in ipairs(sb:visibleIndices()) do
        if sb.frames[i].kind == "option" then row = sb.frames[i] end
      end
      assert.are.equal("|cff0000ff(クエスト)|r Tell me about the Scourge. Now.", row:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("|cff0000ff(Quest)|r Tell me about the Scourge. Now.", row:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      H.uiTeardown()
    end)

  it("a movie option's prepend (PLAY_MOVIE_PREPEND, the `entry` of GOSSIP_OPTION_PREPEND) in Japanese",
    function()
      setup(10)
      ship({})
      H.uiSetup(WFJ, { GOSSIP_OPTION_PREPEND = { "|cff0000ff%s|r %s", "|cff0000ff%s|r %s" },
        PLAY_MOVIE_PREPEND = { "(Play Movie)", "(ムービーを再生)" } }, { lookup = function(kind, id)
          if kind == "gossip" then return data[id] end
        end })
      Stub.showGossip({ text = "Hail.", npc = NPC,
        options = { { name = "Show me the battle.", orderIndex = 0, prepend = "movie" } } })
      local row
      for _, i in ipairs(sb:visibleIndices()) do
        if sb.frames[i].kind == "option" then row = sb.frames[i] end
      end
      assert.are.equal("|cff0000ff(ムービーを再生)|r Show me the battle.", row:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("|cff0000ff(Play Movie)|r Show me the battle.", row:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      H.uiTeardown()
      _G.PLAY_MOVIE_PREPEND = nil
    end)

  it("with no gossip data nothing is written anywhere and every line is collected", function()
    setup(5)
    Stub.showGossip({ text = "Hello, Reyn.", options = options(12), npc = NPC, active = { "A Quest" } })
    sb:scrollTo(10)
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    sb:scrollTo(0)
    Stub.closeGossip()
    for _, fs in ipairs(Stub.fontStrings) do
      if fs ~= G.banner then -- the marker banner is our own widget
        assert.are.equal(0, fs.calls.addonSetText, tostring(fs.text))
        assert.are.equal(0, fs.calls.addonSetFont, tostring(fs.text))
      end
    end
    assert.is_false(G.banner:IsShown())
    assert.are.equal(0, sb.calls.FullUpdate)
    local n = 0
    for k, e in pairs(db.entries) do
      assert.is_truthy(k:find("^gossip:"))
      assert.are.same({ 6740 }, e.n)
      n = n + 1
    end
    assert.are.equal(13, n)
    assert.is_table(db.entries["gossip:" .. key("Hello, Reyn.") .. ":text"])
  end)

  it("close restores every row; a new page while open keeps nothing of the old one", function()
    setup(5)
    local names = options(8)
    ship({ ["Page one."] = "一ページ目。", [names[1]] = "選択肢一", [names[2]] = LONG_JA, [names[7]] = "選択肢七" })
    Stub.showGossip({ text = "Page one.", options = names, npc = NPC })
    assert.is_true(isJapanese(sb.frames[1].GreetingText:GetText()))
    Stub.closeGossip()
    assert.are.equal(0, SS.count("gossip"))
    assert.are.equal("Page one.", sb.frames[1].GreetingText:GetText())
    assert.are.same({ "Fonts\\FRIZQT__.TTF", 13, "" }, fontOf(sb.frames[1]))
    assert.are.equal(names[1], sb.frames[4]:GetText())
    assert.are.same({ "Fonts\\FRIZQT__.TTF", 12, "" }, fontOf(sb.frames[4]))

    Stub.showGossip({ text = "Page one.", options = names, npc = NPC })
    sb:scrollTo(3) -- the pool now holds rows that showed Japanese
    Stub.showGossip({ text = "Page two.", options = { "Back", "Tell me more." }, npc = NPC }) -- still open
    local all = {}
    for _, pool in pairs(sb.pools) do for _, f in ipairs(pool) do all[#all + 1] = f end end
    for _, i in ipairs(sb:visibleIndices()) do all[#all + 1] = sb.frames[i] end
    for _, f in ipairs(all) do
      if f.GreetingText or f.GetFontString then
        assert.is_false(isJapanese(textOf(f)), tostring(textOf(f)))
        assert.are_not.equal(WFJ.Font.PATH, fontOf(f)[1])
      end
    end
    assert.are.equal("Page two.", sb.frames[1].GreetingText:GetText())
  end)

  it("master, area and modifier restore English; a stale row's marker is on the banner; no-op refresh", function()
    WFJ.Settings.set("marker.missing", false) -- on by default; this test reads the text, not the marker
    ship({ ["Hello."] = "こんにちは。", ["Old option."] = { "古い選択肢。", "s" } })
    Stub.showGossip({ text = "Hello.", options = { "Old option.", "Plain." }, npc = NPC })
    local greeting, stale = sb.frames[1], sb.frames[4]
    local marker = ""
    assert.are.equal("古い選択肢。", stale:GetText())
    assert.are.equal(WFJ.MARKER.stale, G.banner:GetText())
    assert.is_true(G.banner:IsShown())
    assertLayout()

    local updates = sb.calls.FullUpdate
    assert.are.equal(0, WFJ.Render.refresh("gossip"))
    assert.are.equal(updates, sb.calls.FullUpdate)

    for _, flip in ipairs({ { "enabled", false, true }, { "area.gossip", false, true } }) do
      S.set(flip[1], flip[2])
      assert.are.equal("Hello.", greeting.GreetingText:GetText(), flip[1])
      assert.are.equal("Old option.", stale:GetText(), flip[1])
      assert.are.same({ "Fonts\\FRIZQT__.TTF", 13, "" }, fontOf(greeting))
      assertLayout()
      S.set(flip[1], flip[3])
      assert.are.equal("こんにちは。", greeting.GreetingText:GetText(), flip[1])
      assertLayout()
    end
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Old option.", stale:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal(marker .. "古い選択肢。", stale:GetText())
    assertLayout()
  end)
  it("QA: a line shipped under its literal key renders for a player whose class it names (candidate keys)", function()
    -- the translation was keyed from a non-mage's dump: "mage" stayed literal; a Mage player's full key differs
    local line = "The undead gather near the mage tower."
    local mage = { name = "Reyn", class = "Mage", race = "Night Elf" }
    assert.are_not.equal(C.key(line, mage), C.key(line, nil))
    data = { [C.key(line, nil)] = { ja = "アンデッドが魔法使いの塔の近くに集まっている。", status = "." } }
    local pick = function(en) -- Main.lua's gossipKey over this player
      local keys = C.keys(en, mage)
      for _, k in ipairs(keys) do if data[k] then return k end end
      return keys[1]
    end
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc") -- a fresh surface wired with the candidate-key picker
    Stub.installGossipAPI()
    WFJ = H.loadChunks(FILES)
    S, SS, G, C = WFJ.Settings, WFJ.SurfaceState, WFJ.Gossip, WFJ.Collector
    WFJ.Compat.init(function(name) return _G[name] end)
    S.load(nil, 1, {})
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end, areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown, lookup = function(_, id) return data[id] end,
      marker = function(n) return S.get("marker." .. n) end,
    }))
    assert.is_true(G.init({ key = pick }))
    Stub.showGossip({ text = line, options = { "Goodbye." }, npc = NPC })
    assert.are.equal("アンデッドが魔法使いの塔の近くに集まっている。",
      GossipFrame.GreetingPanel.ScrollBox.frames[1].GreetingText:GetText())
    -- and the collector treats it as known under any candidate
    local collected = C.load(nil, H.collectorDeps({ player = function() return mage end,
      lookup = function(kind, id) if kind == "gossip" then return data[id] end end }))
    assert.are.equal("known", C.recordGossip(line, NPC.guid))
    assert.is_nil(next(collected.entries))
  end)

  it("QA: rows rebuilt while the window is closed are never shown or recorded", function()
    ship({ ["Hello."] = "こんにちは。" })
    rawset(GossipFrame, "gossipOptions", {})
    Stub.gossip = { text = "Hello.", options = {}, available = {}, active = {} }
    GossipFrame:Update() -- GOSSIP_SHOW with an auto-selected single option: Update runs, the frame never shows
    assert.are.equal("Hello.", sb.frames[1].GreetingText:GetText())
    assert.are.equal(0, SS.count("gossip"))
    assert.is_nil(next(db.entries))
  end)
  it("markers: the banner sits in the stone band; inline while the friendship bar holds it; hidden on close", function()
    S.set("marker.missing", true)
    Stub.showGossip({ text = "Hello.", options = { "Plain." }, npc = NPC })
    assert.are.equal(WFJ.MARKER.missing, G.banner:GetText())
    assert.are.equal("Hello.", sb.frames[1].GreetingText:GetText()) -- the parchment text is untouched
    assert.are.equal(0, sb.frames[1].GreetingText.calls.addonSetText)
    assert.are.same({ "TOP", GossipFrame, "TOP", 20, -38 }, G.bannerFrame.point) -- the stone band
    assert.are.equal(GossipFrame:GetFrameLevel() + WFJ.Render.BANNER_LIFT, G.bannerFrame:GetFrameLevel())
    Stub.closeGossip()
    assert.is_false(G.banner:IsShown())

    GossipFrame.FriendshipStatusBar:Show()
    Stub.showGossip({ text = "Hello.", options = { "Plain." }, npc = NPC })
    assert.is_false(G.banner:IsShown())
    local inline = WFJ.MARKER_INLINE_COLOR .. WFJ.MARKER.missing .. "|r\n"
    assert.are.equal(inline .. "Hello.", sb.frames[1].GreetingText:GetText())
    assertLayout()
    Stub.closeGossip()
    GossipFrame.FriendshipStatusBar:Hide()
    Stub.showGossip({ text = "Hello.", options = { "Plain." }, npc = NPC })
    assert.are.equal("Hello.", sb.frames[1].GreetingText:GetText())
    assert.are.equal(WFJ.MARKER.missing, G.banner:GetText())
    assertLayout()
  end)
end)
