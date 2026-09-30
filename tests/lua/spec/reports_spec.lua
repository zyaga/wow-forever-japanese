-- Core/Reports: the pending fixes in WFJ_DB.reports.
local H = require("tests.lua.spec.helpers")

local function pure() -- the module loaded fresh, under the plain Lua environment (no WoW global)
  local ns = {}
  H.loadPure("Core/Reports.lua", "WoWForeverJapanese", ns)
  return ns.Reports
end

local function fix(o)
  local f = { type = "quest", id = 7, field = "description", ja_hash = "0011223344556677", reason = "awkward" }
  for k, v in pairs(o or {}) do f[k] = v end
  return f
end

describe("Core/Reports", function()
  local R, db

  before_each(function()
    R = pure()
    db = { schema = 1, settings = {} }
    R.load(db)
  end)

  it("an older WFJ_DB without reports loads as empty and keeps its shape until the first fix", function()
    assert.are.equal(0, R.count())
    assert.is_nil(db.reports) -- the collector dump fixture's WFJ_DB stays byte-identical
    assert.is_true(R.save(fix()))
    assert.are.same({ { type = "quest", id = 7, field = "description", ja_hash = "0011223344556677",
      reason = "awkward" } }, db.reports)
  end)

  it("keeps the player's name out of a fix: the note and the Japanese carry the placeholder", function()
    local typed = fix({ note = "Thrallina is greeted twice, thrallina!", ja = "ようこそ、Thrallina。THRALLINAよ。" })
    assert.is_true(R.save(typed, false, "Thrallina"))
    assert.are.equal("{name} is greeted twice, {name}!", R.list()[1].note)
    assert.are.equal("ようこそ、{name}。{name}よ。", R.list()[1].ja)
    assert.are.equal("Thrallina is greeted twice, thrallina!", typed.note) -- the caller's table is not written
  end)

  it("mentions: whole word, any ASCII case", function()
    assert.is_true(R.mentions("BoarとSaberを狩れ", "saber"))
    assert.is_false(R.mentions("Sabersを狩れ", "Saber"))
    assert.is_false(R.mentions("狩れ", nil))
  end)

  it("a name inside a longer word stays, and no name leaves the text as typed", function()
    assert.are.equal("Lightning, not {name}", R.withoutName("Lightning, not Light", "Light"))
    assert.are.equal("{name}", R.withoutName("Light", "Light"))
    assert.are.equal("as typed", R.withoutName("as typed", nil))
    assert.are.equal("as typed", R.withoutName("as typed", ""))
    assert.is_nil(R.withoutName(nil, "Light"))
  end)

  it("stores no time, and drops the one a file saved by an earlier version holds", function()
    db.reports = { { type = "quest", id = 7, field = "description", ja_hash = "0011223344556677", reason = "typo",
      t = 1759000000 } }
    R = pure()
    R.load(db)
    assert.are.equal(1, R.count())
    assert.is_nil(db.reports[1].t)
    assert.is_true(R.save(fix({ id = 8 })))
    assert.is_nil(db.reports[2].t)
  end)

  it("persists in WFJ_DB: a reload of the same table lists the same fixes; broken entries are dropped", function()
    R.save(fix({ note = "stiff", ja = "新しい文" }))
    db.reports[2] = { type = "quest" } -- a hand edit
    R = pure() -- /reload
    R.load(db)
    assert.are.equal(1, R.count())
    assert.are.equal("新しい文", R.list()[1].ja)
    assert.are.equal("stiff", R.list()[1].note)
  end)

  it("refuses a fix without a reason, a multi-line or long note, and a long Japanese", function()
    local none = fix()
    none.reason = nil
    assert.are.same({ false, "reason" }, { R.save(none) })
    assert.are.same({ false, "reason" }, { R.save(fix({ reason = "meh" })) })
    assert.are.same({ false, "note" }, { R.save(fix({ note = "a\nb" })) })
    assert.are.same({ false, "note" }, { R.save(fix({ note = ("x"):rep(R.NOTE_MAX + 1) })) })
    assert.are.same({ false, "ja" }, { R.save(fix({ ja = ("あ"):rep(R.JA_MAX) })) })
    assert.is_true(R.save(fix({ note = ("x"):rep(R.NOTE_MAX), ja = ("x"):rep(R.JA_MAX) })))
  end)

  it("one fix per address: a second is refused as `exists` unless the caller replaces", function()
    assert.is_true(R.save(fix({ reason = "wrong" })))
    assert.are.same({ false, "exists" }, { R.save(fix({ reason = "typo" })) })
    assert.is_true(R.save(fix({ reason = "typo", ja = "直した" }), true))
    assert.are.equal(1, R.count())
    assert.are.equal("typo", R.list()[1].reason)
    assert.are.equal(1, R.find("quest", 7, "description"))
    assert.is_nil(R.find("quest", 7, "title"))
  end)

  it("holds at most 25; the 26th is refused as `full`", function()
    for i = 1, R.CAP do assert.is_true(R.save(fix({ id = i }))) end
    assert.are.same({ false, "full" }, { R.save(fix({ id = 999 })) })
    assert.is_true(R.save(fix({ id = 3, reason = "typo" }), true)) -- a replace still fits
  end)

  it("empty note / Japanese are not stored; delete and clear", function()
    R.save(fix({ note = "", ja = "" }))
    assert.is_nil(R.list()[1].note)
    assert.is_nil(R.list()[1].ja)
    R.save(fix({ id = 8 }))
    assert.is_true(R.delete(1))
    assert.is_false(R.delete(5))
    assert.are.equal(8, R.list()[1].id)
    assert.are.equal(1, R.clear())
    assert.are.equal(0, R.count())
  end)

  it("before load nothing is saved", function()
    local fresh = pure()
    assert.are.same({ false, "unavailable" }, { fresh.save(fix()) })
    assert.are.equal(0, fresh.count())
  end)
end)
