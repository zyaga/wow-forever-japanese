-- Core/Fsrs: the FSRS-6 memory model (ADR-071), checked against the published library's own worked examples.
local H = require("tests.lua.spec.helpers")

local function load()
  local ns = {}
  H.loadPure("Core/Fsrs.lua", nil, ns)
  return ns.Fsrs
end

describe("Fsrs", function()
  local F
  before_each(function() F = load() end)

  it("carries the 21 published default parameters, a fresh copy on every read", function()
    local w = F.W()
    assert.are.equal(21, #w)
    assert.are.equal(0.212, w[1])
    assert.are.equal(0.1542, w[21])
    w[1] = 99
    assert.are.equal(0.212, F.W()[1])
    assert.are.equal(1, F.AGAIN)
    assert.are.equal(3, F.GOOD)
  end)

  -- py-fsrs 6.3.2 tests/test_basic.py::test_memo_state: default parameters, ratings Again, Good, Good, Good, Good,
  -- Good at day gaps 0, 0, 1, 3, 8, 21 give S = 53.62691 and D = 6.3574867
  it("reproduces py-fsrs's memo state example", function()
    local ratings = { F.AGAIN, F.GOOD, F.GOOD, F.GOOD, F.GOOD, F.GOOD }
    local gaps = { 0, 0, 1, 3, 8, 21 }
    local s, d = -1, 0
    for i = 1, #ratings do s, d = F.review(s, d, gaps[i], ratings[i]) end
    assert.is_true(math.abs(s - 53.62691) < 1e-4, "stability " .. s)
    assert.is_true(math.abs(d - 6.3574867) < 1e-4, "difficulty " .. d)
  end)

  it("the forgetting curve gives 90% recall when the elapsed time equals the stability", function()
    for _, s in ipairs({ 0.5, 3, 120 }) do
      assert.is_true(math.abs(F.retrievability(s, s) - 0.9) < 1e-9, "s = " .. s)
    end
    assert.is_true(F.retrievability(0, 3) > 0.999)
    assert.is_true(F.retrievability(30, 3) < F.retrievability(3, 3))
  end)

  it("a first grade sets the initial stability and difficulty", function()
    local s, d = F.review(-1, 0, 0, F.GOOD)
    assert.are.equal(2.3065, s)
    assert.is_true(d > 1 and d < 10)
    local s2 = F.review(-1, 0, 0, F.AGAIN)
    assert.are.equal(0.212, s2)
  end)

  it("Again on a reviewed card lowers its stability and raises its difficulty, within the bounds", function()
    local s, d = F.review(-1, 0, 0, F.GOOD)
    local s2, d2 = F.review(s, d, 3, F.AGAIN)
    assert.is_true(s2 < s)
    assert.is_true(d2 > d)
    for _ = 1, 30 do s2, d2 = F.review(s2, d2, 3, F.AGAIN) end
    assert.is_true(d2 <= 10 and d2 >= 1)
    assert.is_true(s2 >= 0.001)
  end)

  it("rounds the elapsed days: under half a day is a same-day review, which never lowers stability on Good", function()
    local s, d = F.review(-1, 0, 0, F.GOOD)
    local s2 = F.review(s, d, 0.3, F.GOOD)
    assert.is_true(s2 >= s)
    local s3 = F.review(s, d, 0.6, F.GOOD) -- rounds to one day: the long-term formula
    assert.is_true(s3 > s)
    assert.are_not.equal(s2, s3)
  end)
end)
