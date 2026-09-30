local H = require("tests.lua.spec.helpers")

describe("Translator.resolve: the action table, and it stays pure", function()
  local WFJ, flags, deps, T
  local JA = "日本語のテキスト"

  local function entry(status) return { ja = JA, status = status } end

  before_each(function()
    WFJ = {}
    H.loadPure("Core/Translator.lua", "WoWForeverJapanese", WFJ)
    flags = { enabled = true, area = true, held = false, entry = nil, markerStale = true, markerMissing = false,
      alignResult = nil }
    deps = {
      enabled = function() return flags.enabled end,
      areaEnabled = function(a) assert.are.equal("quests", a); return flags.area end,
      modifierHeld = function() return flags.held end,
      lookup = function(kind, id) assert.are.equal("quest", kind); assert.are.equal(2, id); return flags.entry end,
      marker = function(n) if n == "stale" then return flags.markerStale end return flags.markerMissing end,
    }
    T = WFJ.Translator.new(deps)
  end)

  local function resolve(ctx) return T.resolve("quests", "quest", 2, ctx) end

  it("row 1: master off → leave", function()
    flags.enabled = false; flags.entry = entry(".")
    local a, p = resolve()
    assert.are.equal("leave", a); assert.is_nil(p)
  end)

  it("row 2: area off → leave", function()
    flags.area = false; flags.entry = entry(".")
    local a, p = resolve()
    assert.are.equal("leave", a); assert.is_nil(p)
  end)

  it("row 3: modifier held → leave, even with a trusted entry", function()
    flags.held = true; flags.entry = entry(".")
    local a, p = resolve()
    assert.are.equal("leave", a); assert.is_nil(p)
  end)

  it("row 4: no entry → none, missing marker only when enabled", function()
    local a, p = resolve()
    assert.are.equal("none", a); assert.are.same({}, p)
    flags.markerMissing = true
    a, p = resolve()
    assert.are.equal("none", a); assert.are.same({ marker = "missing" }, p)
    flags.entry = { status = "." } -- entry without ja is not shipped
    a, p = resolve()
    assert.are.equal("none", a); assert.are.same({ marker = "missing" }, p)
  end)

  it("row 5: trusted → apply { ja }", function()
    flags.entry = entry(".")
    local a, p = resolve()
    assert.are.equal("apply", a); assert.are.same({ ja = JA }, p)
  end)

  it("row 6: stale → apply with the stale marker only when enabled", function()
    flags.entry = entry("s")
    local a, p = resolve()
    assert.are.equal("apply", a); assert.are.same({ ja = JA, marker = "stale" }, p)
    flags.markerStale = false
    a, p = resolve()
    assert.are.equal("apply", a); assert.are.same({ ja = JA }, p)
  end)

  it("row 7: unaligned without an align dependency fails closed", function()
    flags.entry = entry("u")
    local a, p = resolve()
    assert.are.equal("none", a); assert.are.same({ reason = "unaligned_ungated" }, p)
    flags.markerMissing = true
    a, p = resolve()
    assert.are.equal("none", a)
    assert.are.same({ reason = "unaligned_ungated", marker = "missing" }, p)
  end)

  it("rows 8–9: unaligned with an align dependency applies on pass, none on fail", function()
    flags.entry = entry("u")
    local seen
    deps.align = function(ja, lines) seen = { ja, lines }; return flags.alignResult end
    T = WFJ.Translator.new(deps)
    flags.alignResult = true
    local a, p = resolve({ lines = { "Use: x" } })
    assert.are.equal("apply", a); assert.are.same({ ja = JA }, p)
    assert.are.same({ JA, { "Use: x" } }, seen)
    flags.alignResult = false
    a, p = resolve({ lines = {} })
    assert.are.equal("none", a); assert.are.same({ reason = "align_failed" }, p)
  end)

  it("an empty Japanese value fails closed", function()
    flags.entry = { ja = "", status = "." }
    local a, p = resolve()
    assert.are.equal("none", a); assert.are.same({}, p)
  end)

  it("an unknown status code is not shipped", function()
    flags.entry = entry("m")
    local a, p = resolve()
    assert.are.equal("none", a); assert.are.same({ reason = "not_shipped" }, p)
  end)

  it("never reads a global (loaded under the empty environment)", function()
    -- the module was loaded with H.loadPure; reaching any global would have raised in the cases above
    assert.is_function(WFJ.Translator.new)
  end)
end)

describe("Translator.resolve: player tokens expanded on apply only", function()
  local WFJ, flags, calls, T

  local function build(withExpand)
    local deps = {
      enabled = function() return true end, areaEnabled = function() return true end,
      modifierHeld = function() return flags.held end,
      lookup = function() return flags.entry end,
      marker = function(n) return n == "stale" end,
      align = function(ja) flags.alignSaw = ja; return flags.alignOk, flags.alignText end,
    }
    if withExpand then
      deps.expand = function(ja) calls[#calls + 1] = ja; return (ja:gsub("{name}", "Reyn")), 0 end
    end
    return WFJ.Translator.new(deps)
  end

  before_each(function()
    WFJ = {}
    H.loadPure("Core/Translator.lua", "WoWForeverJapanese", WFJ)
    flags = { held = false, entry = nil, alignOk = true, alignText = nil }
    calls = {}
    T = build(true)
  end)

  it("trusted and stale apply the expanded text; the stale marker is kept", function()
    flags.entry = { ja = "やあ、{name}。", status = "." }
    local a, p = T.resolve("quests", "quest.description", 2)
    assert.are.equal("apply", a); assert.are.same({ ja = "やあ、Reyn。" }, p)
    flags.entry = { ja = "やあ、{name}。", status = "s" }
    a, p = T.resolve("quests", "quest.description", 2)
    assert.are.equal("apply", a)
    assert.are.same({ ja = "やあ、Reyn。", marker = "stale" }, p)
  end)

  it("unaligned: the gate sees the stored text; the applied (filled) text is expanded", function()
    flags.entry = { ja = "{name}に$N1ダメージ", status = "u" }
    flags.alignText = "{name}に240ダメージ"
    local a, p = T.resolve("spells", "spell", 17, { lines = { "x" } })
    assert.are.equal("{name}に$N1ダメージ", flags.alignSaw)
    assert.are.equal("apply", a); assert.are.same({ ja = "Reynに240ダメージ" }, p)
  end)

  it("none and leave never expand", function()
    flags.entry = { ja = "{name}", status = "u" }; flags.alignOk = false
    assert.are.equal("none", (T.resolve("spells", "spell", 17, {})))
    flags.held = true; flags.entry = { ja = "{name}", status = "." }
    assert.are.equal("leave", (T.resolve("quests", "quest.title", 2)))
    flags.held = false; flags.entry = nil
    assert.are.equal("none", (T.resolve("quests", "quest.title", 2)))
    assert.are.same({}, calls)
  end)

  it("without an expand dependency the stored text is applied byte-identical", function()
    T = build(false)
    flags.entry = { ja = "やあ、{name}。", status = "." }
    local _, p = T.resolve("quests", "quest.description", 2)
    assert.are.same({ ja = "やあ、{name}。" }, p)
  end)
end)

describe("Translator.resolve: align returns the filled text", function()
  local WFJ, T, flags, deps
  before_each(function()
    WFJ = {}
    H.loadPure("Core/Translator.lua", "WoWForeverJapanese", WFJ)
    flags = { result = nil, text = nil }
    deps = {
      enabled = function() return true end, areaEnabled = function() return true end,
      modifierHeld = function() return false end,
      lookup = function() return { ja = "$N1ダメージ", status = "u" } end,
      marker = function() return false end,
      align = function(_, _, nameScope) flags.nameScope = nameScope; return flags.result, flags.text end,
    }
    T = WFJ.Translator.new(deps)
  end)

  it("applies the text align returns, the entry's ja on a bare true, none on false", function()
    flags.result, flags.text = true, "240ダメージ"
    local a, p = T.resolve("spells", "spell", 17, { lines = { "Deals 240 damage" }, nameScope = "Fire" })
    assert.are.equal("apply", a); assert.are.same({ ja = "240ダメージ" }, p)
    assert.are.equal("Fire", flags.nameScope)
    flags.result, flags.text = true, nil
    a, p = T.resolve("spells", "spell", 17, {})
    assert.are.equal("apply", a); assert.are.same({ ja = "$N1ダメージ" }, p)
    flags.result, flags.text = false, nil
    a, p = T.resolve("spells", "spell", 17, {})
    assert.are.equal("none", a); assert.are.same({ reason = "align_failed" }, p)
  end)
end)

describe("Translator.resolve: UI templates get the live values", function()
  local WFJ, T, seen
  before_each(function()
    WFJ = {}
    H.loadPure("Core/Translator.lua", "WoWForeverJapanese", WFJ)
    seen = {}
    T = WFJ.Translator.new({
      enabled = function() return true end, areaEnabled = function() return true end,
      modifierHeld = function() return false end,
      lookup = function(_, key) return ({ MIN = { ja = "必要レベル %d", status = "." },
        STALE = { ja = "耐久度 %d / %d", status = "s" } })[key] end,
      marker = function(n) return n == "stale" end,
      fill = function(ja, args)
        seen[#seen + 1] = args
        if args.fail then return nil end
        return (ja:gsub("%%d", args[1]))
      end,
      expand = function(ja) return ja .. "!" end,
    })
  end)

  it("fills only when ctx.args is present, before expand; nil from fill fails closed", function()
    local a, p = T.resolve("ui", "ui", "MIN", { args = { "10" } })
    assert.are.equal("apply", a); assert.are.same({ ja = "必要レベル 10!" }, p)
    a, p = T.resolve("ui", "ui", "MIN", {})
    assert.are.equal("apply", a); assert.are.same({ ja = "必要レベル %d!" }, p)
    assert.are.equal(1, #seen)
    a, p = T.resolve("ui", "ui", "MIN", { args = { fail = true } })
    assert.are.equal("none", a); assert.are.same({ reason = "fill_failed" }, p)
    a, p = T.resolve("ui", "ui", "STALE", { args = { "5" } })
    assert.are.equal("apply", a); assert.are.same({ ja = "耐久度 5 / 5!", marker = "stale" }, p)
  end)
end)

-- ADR-019: the quest live check. The stale marker follows the client's English.
describe("Translator.resolve: quest live check", function()
  local WFJ, flags, T
  local JA = "報酬だ"
  local H1 = 0x1234abcd

  local function makeT(withFingerprints)
    local deps = {
      enabled = function() return true end,
      areaEnabled = function() return true end,
      modifierHeld = function() return false end,
      lookup = function() return flags.entry end,
      marker = function(n) return n == "stale" and flags.markerStale end,
    }
    if withFingerprints then
      deps.fingerprints = function(live)
        flags.asked[#flags.asked + 1] = live
        return flags.fps, flags.inconclusive
      end
    end
    return WFJ.Translator.new(deps)
  end

  before_each(function()
    WFJ = {}
    H.loadPure("Core/Translator.lua", "WoWForeverJapanese", WFJ)
    flags = { entry = { ja = JA, status = ".", h1 = H1 }, fps = { H1 }, markerStale = true, asked = {} }
    T = makeT(true)
  end)

  local function resolve(ctx, kind) return T.resolve("quests", kind or "quest.completion", 2, ctx) end

  it("trusted + a fingerprint equal to h1 → apply, no marker; the live English is what is fingerprinted",
  function()
    flags.fps = { 0x1, H1, 0x2 } -- any candidate (full, name only, none) may match
    local a, p = resolve({ live = "Well done, $N." })
    assert.are.equal("apply", a); assert.are.same({ ja = JA }, p)
    assert.are.same({ "Well done, $N." }, flags.asked)
  end)

  it("trusted + no fingerprint equal to h1 → apply marked stale; unmarked with the stale marker off", function()
    flags.fps = { 0x1, 0x2 }
    local a, p = resolve({ live = "Well done." })
    assert.are.equal("apply", a); assert.are.same({ ja = JA, marker = "stale" }, p)
    flags.markerStale = false
    a, p = resolve({ live = "Well done." })
    assert.are.equal("apply", a); assert.are.same({ ja = JA }, p)
  end)

  it("stale + a fingerprint equal to h1 → apply, no marker (the client shows the checked English)", function()
    flags.entry.status = "s"
    local a, p = resolve({ live = "Well done." })
    assert.are.equal("apply", a); assert.are.same({ ja = JA }, p)
  end)

  it("a fingerprint equal to the entry's h1f (female variant) → apply, no marker", function()
    flags.entry.h1f = 0x5555aaaa
    flags.fps = { 0x1, 0x5555aaaa }
    local a, p = resolve({ live = "Welcome, sister." })
    assert.are.equal("apply", a); assert.are.same({ ja = JA }, p)
    flags.fps = { 0x1, 0x2 } -- neither h1 nor h1f → marked, as before
    a, p = resolve({ live = "Welcome, cousin." })
    assert.are.equal("apply", a); assert.are.same({ ja = JA, marker = "stale" }, p)
  end)

  it("inconclusive fingerprints: a match unmarks, no match lets the status decide", function()
    flags.inconclusive = true
    flags.fps = { 0x1, H1 }
    local a, p = resolve({ live = "Well done, Jo." })
    assert.are.equal("apply", a); assert.are.same({ ja = JA }, p)
    flags.fps = { 0x1, 0x2 }
    a, p = resolve({ live = "Well done, Jo." }) -- trusted: no marker
    assert.are.equal("apply", a); assert.are.same({ ja = JA }, p)
    flags.entry.status = "s" -- stale at build time: marked by the status, not by the live check
    a, p = resolve({ live = "Well done, Jo." })
    assert.are.equal("apply", a); assert.are.same({ ja = JA, marker = "stale" }, p)
  end)

  it("a line filled from the live values is checked masked; the count never fails it", function()
    flags.entry = { ja = "Mossを$N1個集める。", status = ".", h1 = H1 }
    local maskedAsked
    local T2 = WFJ.Translator.new({
      enabled = function() return true end, areaEnabled = function() return true end,
      modifierHeld = function() return false end, lookup = function() return flags.entry end,
      marker = function(n) return n == "stale" end,
      fingerprints = function(_, masked) maskedAsked = masked; return flags.fps end,
    })
    flags.fps = { H1 } -- "Collect 10 Moss." masked is the shipped masked h1
    local a, p = T2.resolve("quests", "quest.objectives", 2, { live = "Collect 10 Moss." })
    assert.are.equal("apply", a); assert.are.same({ ja = "Mossを$N1個集める。" }, p)
    assert.is_true(maskedAsked)
    flags.fps = { 0x2 } -- reworded: marked stale
    local _, p2 = T2.resolve("quests", "quest.objectives", 2, { live = "Gather 10 Moss." })
    assert.are.same({ ja = "Mossを$N1個集める。", marker = "stale" }, p2)
    flags.entry = { ja = JA, status = ".", h1 = H1 } -- a line with no placeholder is not masked
    T2.resolve("quests", "quest.completion", 2, { live = "Well done." })
    assert.is_false(maskedAsked)
  end)

  it("no ctx.live, no fingerprints dep, an empty list, no h1 or a non-quest kind → the status decides", function()
    local cases = {
      { T = T, ctx = nil },
      { T = T, ctx = { refit = function() end } },
      { T = makeT(false), ctx = { live = "Well done." } },
      { T = T, ctx = { live = "Well done." }, fps = {} },
      { T = T, ctx = { live = "Well done." }, noH1 = true },
      { T = T, ctx = { live = "Well done." }, kind = "ui" },
    }
    for i, c in ipairs(cases) do
      for status, want in pairs({ ["."] = { ja = JA }, s = { ja = JA, marker = "stale" } }) do
        flags.fps = c.fps or { 0x99 } -- a mismatch would mark a trusted line: it must not be consulted
        flags.entry = { ja = JA, status = status, h1 = (not c.noH1) and H1 or nil }
        local a, p = c.T.resolve("quests", c.kind or "quest.completion", 2, c.ctx)
        assert.are.equal("apply", a, "case " .. i)
        assert.are.same(want, p, "case " .. i .. " status " .. status)
      end
    end
  end)

  it("unaligned and missing entries are untouched by the live check", function()
    flags.entry = { ja = JA, status = "u", h1 = H1 }
    local a, p = resolve({ live = "x" })
    assert.are.equal("none", a); assert.are.same({ reason = "unaligned_ungated" }, p)
    flags.entry = nil
    a = resolve({ live = "x" })
    assert.are.equal("none", a)
  end)
end)

-- ADR-007: a stale item / spell entry still goes through the align gate; a pass applies with the marker.
describe("Translator.resolve: gated item / spell entries", function()
  local WFJ, flags, T
  local JA = "【使用】$1秒間でhealthを$2回復。"

  before_each(function()
    WFJ = {}
    H.loadPure("Core/Translator.lua", "WoWForeverJapanese", WFJ)
    flags = { entry = nil, markerStale = true, alignResult = true, alignText = nil, seen = nil }
    T = WFJ.Translator.new({
      enabled = function() return true end,
      areaEnabled = function() return true end,
      modifierHeld = function() return false end,
      lookup = function() return flags.entry end,
      marker = function(n) return n == "stale" and flags.markerStale end,
      align = function(ja, lines)
        flags.seen = { ja, lines }
        return flags.alignResult, flags.alignText
      end,
    })
  end)

  -- the tooltip asks field-qualified
  for _, kind in ipairs({ "item", "spell", "item.description", "spell.description" }) do
    it(kind .. ": stale → gated; a pass applies the filled text with the stale marker", function()
      flags.entry = { ja = JA, status = "s" }; flags.alignText = "【使用】18秒間でhealthを61回復。"
      local a, p = T.resolve("items", kind, 117, { lines = { "Use: Restores 61 health over 18 sec." } })
      assert.are.equal("apply", a)
      assert.are.same({ ja = "【使用】18秒間でhealthを61回復。", marker = "stale" }, p)
      assert.are.same({ JA, { "Use: Restores 61 health over 18 sec." } }, flags.seen)
    end)

    it(kind .. ": stale → gated; a fail leaves the English (none, no marker)", function()
      flags.entry = { ja = JA, status = "s" }; flags.alignResult = false
      local a, p = T.resolve("items", kind, 117, { lines = { "Use: Restores 80 health over 18 sec." } })
      assert.are.equal("none", a); assert.are.same({ reason = "align_failed" }, p)
    end)

    it(kind .. ": stale with the stale marker off applies unmarked", function()
      flags.entry = { ja = JA, status = "s" }; flags.markerStale = false
      local a, p = T.resolve("items", kind, 117, { lines = {} })
      assert.are.equal("apply", a); assert.are.same({ ja = JA }, p)
    end)

    it(kind .. ": unaligned is gated as before, with no marker", function()
      flags.entry = { ja = JA, status = "u" }
      local a, p = T.resolve("items", kind, 117, { lines = {} })
      assert.are.equal("apply", a); assert.are.same({ ja = JA }, p)
    end)
  end

  it("a stale quest entry is not gated (unchanged: the quest live check decides the marker)", function()
    flags.entry = { ja = "クエスト", status = "s" }; flags.alignResult = false
    local a, p = T.resolve("quests", "quest.description", 2, {})
    assert.are.equal("apply", a); assert.are.same({ ja = "クエスト", marker = "stale" }, p)
    assert.is_nil(flags.seen)
  end)
end)

describe("Translator: branch lines (ADR-043)", function()
  local WFJ, T, flags
  before_each(function()
    WFJ = {}
    H.loadPure("Core/Translator.lua", "WoWForeverJapanese", WFJ)
    flags = { entry = nil, result = { false }, markerStale = true, calls = 0 }
    T = WFJ.Translator.new({
      enabled = function() return true end,
      areaEnabled = function() return true end,
      modifierHeld = function() return false end,
      lookup = function() return flags.entry end,
      marker = function(n) return n == "stale" and flags.markerStale end,
      alignVariants = function(variants, shapes, lines, nameScope)
        flags.calls = flags.calls + 1
        flags.got = { variants = variants, shapes = shapes, lines = lines, nameScope = nameScope }
        return (table.unpack or unpack)(flags.result) -- luacheck: ignore 143
      end,
      expand = function(ja) return ja .. "!" end,
    })
  end)

  local VARIANTS = { "a", "b", shape = { "1/0", "2/0" } }
  local function entry(status) return { variants = VARIANTS, shapes = VARIANTS.shape, status = status } end

  it("applies the one variant alignVariants chose, expanded, with the live lines and name scope", function()
    flags.entry = entry("u"); flags.result = { true, "選ばれた" }
    local a, p = T.resolve("items", "spell.description", 1, { lines = { "L" }, nameScope = "N" })
    assert.are.equal("apply", a)
    assert.are.same({ ja = "選ばれた!" }, p)
    assert.are.same({ variants = VARIANTS, shapes = VARIANTS.shape, lines = { "L" }, nameScope = "N" }, flags.got)
  end)

  it("a stale branch line carries the stale marker", function()
    flags.entry = entry("s"); flags.result = { true, "選ばれた" }
    local _, p = T.resolve("items", "spell.description", 1, { lines = { "L" } })
    assert.are.equal("stale", p.marker)
  end)

  it("no single variant → none (align_failed); no dep → none; not gated → none", function()
    flags.entry = entry("u"); flags.result = { false }
    local a, p = T.resolve("items", "spell.description", 1, { lines = { "L" } })
    assert.are.equal("none", a); assert.are.equal("align_failed", p.reason)
    flags.entry = entry(".")
    a, p = T.resolve("items", "spell.description", 1, { lines = { "L" } })
    assert.are.equal("none", a); assert.are.equal("not_shipped", p.reason)
    local T2 = WFJ.Translator.new({ enabled = function() return true end, areaEnabled = function() return true end,
      modifierHeld = function() return false end, lookup = function() return entry("u") end,
      marker = function() return false end })
    a, p = T2.resolve("items", "spell.description", 1, { lines = { "L" } })
    assert.are.equal("none", a); assert.are.equal("unaligned_ungated", p.reason)
  end)

  it("modifier held or master off still leaves the frame alone", function()
    local T3 = WFJ.Translator.new({ enabled = function() return true end, areaEnabled = function() return true end,
      modifierHeld = function() return true end, lookup = function() return entry("u") end,
      marker = function() return false end })
    assert.are.equal("leave", (T3.resolve("items", "spell.description", 1, {})))
  end)
end)
