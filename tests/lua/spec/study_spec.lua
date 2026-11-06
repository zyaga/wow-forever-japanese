-- Core/Study: the study queue over the saved word list (ADR-071): the saved table, what comes next, grading.
local H = require("tests.lua.spec.helpers")

local function load()
  local ns = {}
  H.loadPure("Core/Fsrs.lua", nil, ns)
  H.loadPure("Core/Study.lua", nil, ns)
  return ns.Study
end

local DAY = 86400
local NOW = 1790000000
local TODAY = "2026-09-21"

-- word list entries in saved order: keys a, b, c
local function entries()
  return { { key = "a", word = "数" }, { key = "b", word = "生き物" }, { key = "c", word = "狩り" } }
end
describe("Study", function()
  local S, E
  before_each(function()
    S = load()
    E = entries()
    S.load(nil, E)
  end)

  describe("load and prune", function()
    it("starts empty from nothing or garbage, and keeps only cards whose word is still in the list", function()
      local t = S.load(nil, E)
      assert.are.same({ schema = 1, cards = {}, days = {} }, t)
      t = S.load("junk", E)
      assert.are.same({ schema = 1, cards = {}, days = {} }, t)
      local saved = { schema = 1, cards = {
        a = { s = 2, d = 5, due = NOW, last = NOW - DAY, reps = 1, lapses = 0 },
        gone = { s = 2, d = 5, due = NOW, last = NOW - DAY, reps = 1, lapses = 0 },
        bad = "x", b = { s = "no" },
      }, days = { ["2026-09-20"] = 3, junk = "x" } }
      t = S.load(saved, E)
      assert.are.equal(2, t.cards.a.s)
      assert.is_nil(t.cards.gone)
      assert.is_nil(t.cards.bad)
      assert.is_nil(t.cards.b)
      assert.are.equal(3, t.days["2026-09-20"])
      assert.is_nil(t.days.junk)
      assert.is_false(S.readonly())
    end)

    it("keeps a table saved by a newer version untouched and refuses to grade", function()
      local newer = { schema = 2, cards = { a = { future = true } } }
      local t = S.load(newer, E)
      assert.are.equal(newer, t)
      assert.is_true(S.readonly())
      assert.is_nil(S.answer("a", S.GOOD, NOW, TODAY))
      assert.is_nil(S.next(E, NOW, TODAY, 20))
    end)

    it("prune drops the cards of removed words, so a word saved again starts as new", function()
      S.answer("a", S.GOOD, NOW, TODAY)
      S.answer("b", S.GOOD, NOW, TODAY)
      assert.are.equal(1, S.prune({ E[1], E[3] }))
      assert.is_nil(S.card("b"))
      assert.is_truthy(S.card("a"))
    end)
  end)

  describe("next", function()
    it("asks the earliest due card first, then a new card in saved order, then nothing", function()
      S.answer("b", S.GOOD, NOW - 10 * DAY, TODAY) -- due long ago
      S.answer("c", S.GOOD, NOW - 3 * DAY, TODAY)
      local e, kind = S.next(E, NOW, TODAY, 20)
      assert.are.equal("b", e.key)
      assert.are.equal("due", kind)
      S.answer("b", S.GOOD, NOW, TODAY)
      e, kind = S.next(E, NOW, TODAY, 20)
      assert.are.equal("c", e.key)
      assert.are.equal("due", kind)
      S.answer("c", S.GOOD, NOW, TODAY)
      e, kind = S.next(E, NOW, TODAY, 20)
      assert.are.equal("a", e.key)
      assert.are.equal("new", kind)
      S.answer("a", S.GOOD, NOW, TODAY)
      assert.is_nil(S.next(E, NOW, TODAY, 20))
    end)

    it("stops giving new cards once today's count reaches the cap, and the cap is per day", function()
      assert.are.equal("a", S.next(E, NOW, TODAY, 1).key)
      S.answer("a", S.GOOD, NOW, TODAY)
      assert.is_nil(S.next(E, NOW, TODAY, 1))
      assert.are.equal("b", S.next(E, NOW + DAY, "2026-09-22", 1).key)
    end)

    it("a card graded Again comes back after the relearn step, not before", function()
      S.answer("a", S.GOOD, NOW, TODAY)
      S.answer("a", S.AGAIN, NOW + DAY, TODAY)
      assert.is_nil(S.next({ E[1] }, NOW + DAY + 599, TODAY, 0))
      assert.are.equal("a", S.next({ E[1] }, NOW + DAY + 600, TODAY, 0).key)
    end)
  end)

  describe("counts", function()
    it("reports what is due, how many new cards are left today and when the next card comes", function()
      S.answer("b", S.GOOD, NOW - 10 * DAY, TODAY)
      S.answer("c", S.GOOD, NOW, TODAY)
      local c = S.counts(E, NOW, TODAY, 20)
      assert.are.equal(1, c.due)
      assert.are.equal(1, c.newLeft) -- a alone is new; b and c count toward today's 20, 18 left but 1 word
      assert.are.equal(1, c.fresh)
      assert.are.equal(S.card("c").due, c.nextDue)
      c = S.counts(E, NOW, TODAY, 2)
      assert.are.equal(0, c.newLeft)
      S.answer("b", S.GOOD, NOW, TODAY)
      c = S.counts({ E[2], E[3] }, NOW, TODAY, 20)
      assert.are.equal(0, c.due)
      assert.are.equal(0, c.newLeft)
      assert.are.equal(S.card("c").due, c.nextDue) -- the earliest: c comes back before b
    end)
  end)

  describe("answer", function()
    it("a new card graded Good gets FSRS's first stability, is due in whole days, and counts toward today", function()
      local st = S.answer("a", S.GOOD, NOW, TODAY)
      assert.are.equal(2.3065, st.s)
      assert.are.equal(NOW + 2 * DAY, st.due) -- 2.3065 days rounds to 2
      assert.are.equal(NOW, st.last)
      assert.are.equal(1, st.reps)
      assert.are.equal(0, st.lapses)
      assert.are.equal(1, S.load(S.table(), E).days[TODAY])
    end)

    it("Again puts the card back in ten minutes and counts a lapse; a later Good gives at least one day", function()
      local st = S.answer("a", S.AGAIN, NOW, TODAY)
      assert.are.equal(NOW + 600, st.due)
      assert.are.equal(1, st.lapses)
      st = S.answer("a", S.GOOD, NOW + 600, TODAY)
      assert.are.equal(NOW + 600 + DAY, st.due) -- a short stability still waits a whole day
      assert.are.equal(2, st.reps)
      assert.are.equal(1, st.lapses)
    end)

    it("an unknown key or a bad rating is refused", function()
      assert.is_nil(S.answer("zzz", S.GOOD, NOW, TODAY))
      assert.is_nil(S.answer("a", 2, NOW, TODAY))
      assert.is_nil(S.card("a"))
    end)

    it("grading a card a second time on the same day keeps it out of today's new count", function()
      S.answer("a", S.GOOD, NOW, TODAY)
      S.answer("a", S.AGAIN, NOW + 100, TODAY)
      assert.are.equal(1, S.table().days[TODAY])
    end)

    it("a new day's first new card replaces the old day's count (only today's is ever read)", function()
      S.answer("a", S.GOOD, NOW, TODAY)
      S.answer("b", S.GOOD, NOW + DAY, "2026-09-22")
      assert.are.same({ ["2026-09-22"] = 1 }, S.table().days)
    end)
  end)
end)
