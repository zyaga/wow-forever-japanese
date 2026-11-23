-- Core/Align is the Lua twin of align.py (shared vectors) and the runtime gate fails closed.
local H = require("tests.lua.spec.helpers")

local function set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end

describe("Core/Align: shared vectors", function()
  local A
  setup(function()
    local ns = {}
    H.loadPure("Core/Align.lua", "WoWForeverJapanese", ns)
    A = ns.Align
  end)

  it("loads under a std-lib-only environment and matches every vector", function()
    local V = dofile(H.ROOT .. "/vectors/align_vectors.lua")
    assert.is_true(#V.cases >= 25)
    for _, c in ipairs(V.cases) do
      local al = set(c.allowlist)
      local got
      if c.op == "names" then
        got = A.names(c.text, al)
      elseif c.op == "checkNames" then
        got = A.checkNames(c.text, c.scope, al)
      elseif c.op == "numbers" then
        got = {}
        for run, n in pairs(A.numbers(c.text)) do for _ = 1, n do got[#got + 1] = run end end
        table.sort(got, function(x, y) if #x ~= #y then return #x < #y end return x < y end)
      elseif c.op == "numberWords" then
        got = A.numberWords(c.text)
      elseif c.op == "values" or c.op == "valuesLoose" then
        got = A.values(c.text, nil, c.op == "valuesLoose")
      elseif c.op == "wordedSlots" then
        -- what `fill` writes, with the slots left as written: each fills itself
        local durations = { "$D1", "$D2", worded = { true } }
        got = A.fill(c.text, { "$N1", "$N2", "$N3" }, durations, {}) or ""
      elseif c.op == "grantedHead" then
        got = A.grantedHead(c.text, c.scope) or ""
      elseif c.op == "grantedCount" then
        local _, count = A.grantedHead(c.text, c.scope)
        got = count and tostring(count) or ""
      else
        got = c.expected -- variantKey needs Normalize and Hash: its vectors run in their own block below
      end
      assert.are.same(c.expected, got, c.id)
    end
  end)
end)

describe("Core/Align.check: placeholders and the gate", function()
  local A
  before_each(function()
    local ns = {}
    H.loadPure("Core/Align.lua", "WoWForeverJapanese", ns)
    A = ns.Align
  end)

  it("fills $N<k> from the live line's number tokens, in order", function()
    local ok, text = A.check("$N1ダメージを吸収。$N2秒間持続。", { "Absorbs 240 damage for 30 sec." })
    assert.is_true(ok)
    assert.are.equal("240ダメージを吸収。30秒間持続。", text)
    -- the corpus numbers placeholders in reading order of the English line; a swapped pair shows swapped values
    local _, swapped = A.check("$N2ダメージを吸収。$N1秒間持続。", { "Absorbs 240 damage for 30 sec." })
    assert.are.equal("30ダメージを吸収。240秒間持続。", swapped)
    assert.are.same({ "1200", "18.5", "3" }, A.values("Deals 1,200 damage over 18.5 sec. to 3 targets"))
    assert.is_nil(A.fill("$N3ダメージ", { "1", "2" }))
    assert.are.same({ "2", "1" }, select(2, A.fill("$N2と$N1", { "1", "2", "3" })))
    assert.are.equal("$Nだけ", A.fill("$Nだけ", {}))
    assert.is_false((A.check("$N3ダメージ", { "Deals 1 damage 2 times" })))
    local ok2, t2 = A.check("$N1ダメージ", { "Deals 1,200 damage" })
    assert.is_true(ok2); assert.are.equal("1200ダメージ", t2)
  end)

  it("a name may come from the tooltip's name line, numbers never (Hearthstone, seen in game)", function()
    local line = "Use: Returns you to Shadowglen. Speak to an Innkeeper in a different place to change your home "
      .. "location."
    assert.is_false((A.check("【使用】Hearthstoneの場所に戻ります。", { line })))
    assert.is_true((A.check("【使用】Hearthstoneの場所に戻ります。", { line }, "Hearthstone")))
    assert.is_false((A.check("$N1回復", { "Restores health." }, "Potion 5")))
    assert.is_false((A.check("5回復", { "Restores health." }, "Potion 5")))
  end)

  it("passes when every name and number is in the replaced lines", function()
    local ok, text = A.check("18秒間でhealthを61回復。回復中は\n座っている必要があります。",
      { "Use: Restores 61 health over 18 sec. Must remain seated while eating." })
    assert.is_true(ok)
    assert.are.equal("18秒間でhealthを61回復。回復中は\n座っている必要があります。", text)
  end)

  it("fails closed on a missing name, a missing number, or no lines", function()
    assert.is_false((A.check("Silverwind Refugeへ行け", { "Go to Splintertree Post." })))
    assert.is_false((A.check("18秒間でhealthを61回復", { "Use: Restores 70 health over 18 sec." })))
    assert.is_false((A.check("何か", {})))
    assert.is_false((A.check("何か", nil)))
    assert.is_false((A.check(nil, { "x" })))
  end)

  it("accepts allowlisted words, English number words, full-width digits, and ignores glued digits", function()
    assert.is_true((A.check("Healthを回復", { "Restores some hit points." })))
    assert.is_true((A.check("Kobold Verminを3匹", { "Kill three Kobold Vermin." })))
    assert.is_true((A.check("６１回復", { "Restores 61 health." })))
    assert.is_true((A.check("Mk2を使え", { "Use the Mk3." }))) -- "Mk2" is neither a name (2 letters) nor a number
    assert.is_false((A.check("2を使え", { "Use the Mk2." }))) -- a bare 2 in the Japanese, only a glued 2 in the line
    assert.is_true((A.check("1200ダメージ", { "Deals 1,200 damage" }))) -- a rendered thousands separator
    assert.are.same({ "1200", "18.5" }, A.values("Deals 1,200 damage over 18.5 sec to the Mk2 for 18sec"))
  end)
end)

-- `$D<k>`: the one value whose UNIT the client chooses. `$d` renders through
-- INT_SPELL_DURATION_SEC / _MIN / _HOURS / _DAYS, so the same template shows seconds on one item and minutes
-- on another; the Japanese must never name the unit itself. The renderer is UIStrings', stubbed here.
-- Align.gate: what the tooltip shows for a shipped item / spell entry, by the Translator's status rules.
describe("gate", function()
  local A
  setup(function()
    local ns = {}
    H.loadPure("Core/Align.lua", "WoWForeverJapanese", ns)
    A = ns.Align
  end)
  local LINE = { "Restores 50 health." }

  it("an unaligned or stale line goes through the gate", function()
    assert.are.same({ true, "体力を50回復する。" }, { A.gate({ ja = "体力を$N1回復する。", status = "u" }, LINE) })
    assert.are.same({ true, "体力を50回復する。" }, { A.gate({ ja = "体力を$N1回復する。", status = "s" }, LINE) })
    assert.is_false(A.gate({ ja = "体力を99回復する。", status = "u" }, LINE))
  end)

  it("a trusted line is shown ungated with its live values filled in", function()
    assert.are.same({ true, "体力を50回復する。" }, { A.gate({ ja = "体力を$N1回復する。", status = "." }, LINE) })
    assert.are.same({ true, "回復する。" }, { A.gate({ ja = "回復する。", status = "." }, LINE) })
  end)

  it("a branch line only when unaligned or stale; no Japanese, or another status, shows nothing", function()
    local branch = { variants = { "体力を$N1回復する。" }, shapes = { "1/0" } }
    branch.status = "u"
    assert.is_true((A.gate(branch, LINE)))
    branch.status = "."
    assert.is_false(A.gate(branch, LINE))
    assert.is_false(A.gate({ ja = "", status = "u" }, LINE))
    assert.is_false(A.gate({ ja = "x", status = "m" }, LINE))
    assert.is_false(A.gate(nil, LINE))
  end)
end)

describe("durations", function()
  local A
  setup(function()
    local ns = {}
    H.loadPure("Core/Align.lua", "WoWForeverJapanese", ns)
    A = ns.Align
  end)

  -- answers the way Index:duration does: only for a real duration entry, one or two of them
  local function renderer(map)
    return function(text) return map[text] end
  end
  local SEC = renderer({
    ["30 sec"] = "30秒", ["18 sec"] = "18秒", ["1.5 min"] = "1.5分", ["2 min"] = "2分",
    ["1 hr 30 min"] = "1時間30分", ["18秒"] = "18秒", ["10 days"] = "10日",
  })

  it("starts only where a number starts, and skips a number that is not a duration whole", function()
    -- "1.5 sec" has no renderer here (the float form is not shipped): it must not come back as "5 sec"
    assert.are.same({}, A.durations("Stuns for 1.5 sec.", renderer({ ["5 sec"] = "5秒" })))
    assert.are.same({ "30秒" }, A.durations("Absorbs 1,230 damage (30 sec).", SEC))
    assert.are.same({ "30秒" }, A.durations("Lasts 30 sec; stacks.", SEC))
    assert.are.same({ "30秒" }, A.durations('Lasts 30 sec" and more.', SEC))
  end)

  it("finds the live line's durations in order, already in Japanese", function()
    assert.are.same({ "18秒" }, A.durations("Restores 61 health over 18 sec.", SEC))
    assert.are.same({ "2分" }, A.durations("Lasts 2 min.", SEC))
    assert.are.same({ "1時間30分" }, A.durations("Lasts 1 hr 30 min.", SEC))
    -- the two-entry phrase is one duration, not also its second half
    assert.are.same({ "1時間30分" }, A.durations("1 hr 30 min", SEC))
    assert.are.same({ "30秒", "10日" }, A.durations("Stuns for 30 sec. Expires in 10 days.", SEC))
  end)

  -- the spell API's text keeps the client's plural code ("for 1 |4hour:hrs;."); the line the tooltip holds is
  -- that same text, and the renderer understands it whole, closing ";" included
  it("reads a duration written in the client's plural code, one or two of them", function()
    local raw = renderer({ ["1 |4hour:hrs;"] = "1時間", ["5 |4Hr:Hrs; 30 |4Min:Mins;"] = "5時間30分" })
    assert.are.same({ "1時間" }, A.durations("Increases armor by 34 for 1 |4hour:hrs;.", raw))
    assert.are.same({ "1時間" }, A.durations("for 1 |4hour:hrs;. Only one Blessing.", raw))
    assert.are.same({ "5時間30分" }, A.durations("Lasts 5 |4Hr:Hrs; 30 |4Min:Mins;.", raw))
    assert.are.same({}, A.durations("for 2 |4item:items;.", raw))
  end)

  it("a gated line in the plural code passes the gate and is filled from it", function()
    local raw = renderer({ ["1 |4hour:hrs;"] = "1時間" })
    local ok, text = A.check("$D1の間、味方の対象のアーマーを$N1上げます。",
      { "Increases the friendly target's armor by 34 for 1 |4hour:hrs;." }, nil, raw)
    assert.is_true(ok)
    assert.are.equal("1時間の間、味方の対象のアーマーを34上げます。", text)
  end)

  it("ignores a number that is not a duration, and a line already in Japanese is read too", function()
    assert.are.same({}, A.durations("Restores 61 health.", SEC))
    assert.are.same({}, A.durations("Deals 120 Fire damage to 5 enemies.", SEC))
    assert.are.same({}, A.durations("Requires Level 40 and 25 Mining.", SEC))
    -- our own UI strings make the client print "18秒", so the live line may already carry the Japanese unit
    assert.are.same({ "18秒" }, A.durations("Restores 61 health over 18秒.", SEC))
  end)

  it("returns nothing without a renderer, so a $D line fails closed rather than guessing", function()
    assert.are.same({}, A.durations("Lasts 30 sec.", nil))
    assert.are.same({}, A.durations(nil, SEC))
    assert.is_nil(A.fill("$D1かけて回復します。", {}, {}))
  end)

  it("fills $D<k> beside $N<k>, and fails closed when either has no value", function()
    local text, used = A.fill("$D2かけてhealthを$N1回復します。", { "61", "18" }, { "x", "18秒" })
    assert.are.equal("18秒かけてhealthを61回復します。", text)
    assert.are.same({ "18秒", "61" }, used)
    assert.is_nil(A.fill("$D3です。", { "1" }, { "18秒" }))
    assert.is_nil(A.fill("$N3です。", { "1" }, { "18秒" }))
    assert.are.equal("$Nと$Dはそのまま。", A.fill("$Nと$Dはそのまま。", {}, {}))
  end)

  -- `$D<k>` indexes the DURATIONS of the line, not the shared number space of `$N`: a drafter writes "the
  -- first duration". `$N` still counts every number, the duration's included.
  it("check fills the duration from the live line and still gates names and numbers", function()
    local lines = { "Restores 61 health over 18 sec." }
    local ja = "$D1かけてhealthを$N1回復します。"
    local ok, text = A.check(ja, lines, nil, SEC)
    assert.is_true(ok)
    assert.are.equal("18秒かけてhealthを61回復します。", text)
    -- the unit is never assumed: the same Japanese on a minutes line yields minutes
    local ok2, text2 = A.check(ja, { "Restores 61 health over 2 min." }, nil, SEC)
    assert.is_true(ok2)
    assert.are.equal("2分かけてhealthを61回復します。", text2)
    -- A baked unit is WRONG on the minutes line and the gate cannot see it: both numbers are in the line,
    -- and 分 against sec is Japanese text `check` never inspects. So the gate does not save a baked unit;
    -- `translate_lint`'s `duration_missing` is what keeps one out of the corpus.
    assert.is_true((A.check("18分かけてhealthを61回復します。", lines, nil, SEC)))
    -- without the renderer the placeholder cannot be filled, so the line stays English
    assert.is_false(A.check(ja, lines, nil, nil))
    -- $N still indexes every number, so the duration's number is reachable bare if a line ever wants it
    local ok3, text3 = A.check("$N2秒相当でhealthを$N1回復します。", lines, nil, SEC)
    assert.is_true(ok3)
    assert.are.equal("18秒相当でhealthを61回復します。", text3)
  end)
end)

-- a TRUSTED line's placeholders are filled without the gate. A quest objective reads
-- `Collect $1oa Lady's Tear Moss.` in the text the server sent; the count is only in the line the player is
-- shown, so the Japanese carries `$N<k>` and the addon fills it, but the names and numbers were already
-- checked offline, so re-checking them here would reject a good translation over that same count.
describe("fillValues", function()
  local A
  setup(function()
    local ns = {}
    H.loadPure("Core/Align.lua", "WoWForeverJapanese", ns)
    A = ns.Align
  end)

  it("a range whose ends carry a thousands separator fits like any other range", function()
    local live = "Smites an enemy, inflicting 1,350 to 1,650 Holy damage."
    assert.are.same({ "1350～1650" }, A.values(live))
    assert.are.same({ true, "敵に1350～1650のHolyダメージを与えます。" },
      { A.check("敵に$N1のHolyダメージを与えます。", { live }, nil, nil, 1) })
    -- one end only, and a second range after it
    assert.is_true((A.check("$N1のダメージ、さらに$N2。", { "Deals 335 to 1,005 damage, then 285 to 315 more." })))
    -- a range vouches for its own two ends only
    assert.is_false((A.check("$N1のダメージ。1350回。", { "Deals 1,350 to 1,650 damage." })))
  end)

  it("a range the client prints is one value, filled as A～B", function()
    local live = "Hurls a fiery ball that causes 14 to 22 Fire damage and an additional 2 Fire damage over 4 sec."
    assert.are.same({ "14～22", "2", "4" }, A.values(live))
    local ja = "$N1のFireダメージを与え、さらに$N3秒かけて$N2のFireダメージを与えます。"
    assert.are.equal("14～22のFireダメージを与え、さらに4秒かけて2のFireダメージを与えます。", A.fillValues(ja, live))
    local ok, text = A.check(ja, { live })
    assert.is_true(ok); assert.are.equal("14～22のFireダメージを与え、さらに4秒かけて2のFireダメージを与えます。", text)
  end)

  it("Wrath: one slot takes the range or the single number; two slots around one range never fill", function()
    local ja = "対象に$N1のNature属性ダメージを\n与えます。"
    local ok, text = A.check(ja, { "Causes 14 to 16 Nature damage to the target." })
    assert.is_true(ok); assert.are.equal("対象に14～16のNature属性ダメージを\n与えます。", text)
    ok, text = A.check(ja, { "Causes 15 Nature damage to the target." })
    assert.is_true(ok); assert.are.equal("対象に15のNature属性ダメージを\n与えます。", text)
    assert.is_false((A.check("対象に$N1-$N2のNature属性ダメージを\n与えます。",
      { "Causes 14 to 16 Nature damage to the target." })))
  end)

  it("fills from the live line without gating names or numbers", function()
    local live = "Collect 5 Lady's Tear Moss."
    assert.are.equal("Lady's Tear Mossを5個集める。", A.fillValues("Lady's Tear Mossを$N1個集める。", live))
    -- The difference from the gate: a name the OBJECTIVE line does not carry (the quest names Moonbrook in
    -- its description, not here) makes `check` refuse. `fillValues` does not check, because the offline
    -- check already read the whole quest's English (status.Scope), which this one line is not.
    assert.are.equal("Moonbrookで5個集める。", A.fillValues("Moonbrookで$N1個集める。", live))
    assert.is_false((A.check("Moonbrookで$N1個集める。", { live })))
  end)

  it("leaves a line with no placeholder exactly as it is, and never calls it a failure", function()
    assert.are.equal("7体倒す。", A.fillValues("7体倒す。", "Kill 7 Young Nightsabers."))
    assert.are.equal("7体倒す。", A.fillValues("7体倒す。", nil))  -- no live text needed
    assert.are.equal("", A.fillValues("", "x"))
  end)

  it("fails closed when a placeholder cannot be filled", function()
    assert.is_nil(A.fillValues("$N1個集める。", nil))        -- no live text at all
    assert.is_nil(A.fillValues("$N1個集める。", ""))
    assert.is_nil(A.fillValues("$N3個集める。", "Collect 5 Moss."))  -- no third value
    assert.is_nil(A.fillValues(nil, "x"))
  end)

  it("fills a duration too, with the unit the client chose", function()
    local SEC = function(t) return ({ ["30 sec"] = "30秒", ["2 min"] = "2分" })[t] end
    assert.are.equal("30秒続く。", A.fillValues("$D1続く。", "Lasts 30 sec.", SEC))
    assert.are.equal("2分続く。", A.fillValues("$D1続く。", "Lasts 2 min.", SEC))
    assert.is_nil(A.fillValues("$D1続く。", "Lasts 30 sec.", nil))  -- no renderer: fail closed
  end)
end)

-- a name-list tail. The live description is the head, then one line per known spell's name.
describe("name-list tail ($T)", function()
  local A
  setup(function()
    local ns = {}
    H.loadPure("Core/Align.lua", "WoWForeverJapanese", ns)
    A = ns.Align
  end)
  local live = "You are fluent in the following languages:\r\nCommon\r\nDwarvish"

  it("fills the head and copies the live lines from the first break on, byte for byte", function()
    assert.are.equal("次の言語を流暢に話せます：\r\nCommon\r\nDwarvish",
      A.fillValues("次の言語を流暢に話せます：$T", live))
    local ok, text = A.check("次の言語を流暢に話せます：$T", { live })
    assert.is_true(ok)
    assert.are.equal("次の言語を流暢に話せます：\r\nCommon\r\nDwarvish", text)
    -- a client that writes a bare \n keeps it as written
    assert.are.equal("次の言語：\nCommon", A.fillValues("次の言語：$T", "You know:\nCommon"))
  end)

  it("takes the head's values from the head only", function()
    assert.are.equal("4種類の鎧：\r\nCloth\r\nLeather", A.fillValues("$N1種類の鎧：$T", "Wear 4 types:\r\nCloth\r\nLeather"))
  end)

  it("with no known spell there is no tail to copy", function()
    assert.are.equal("次の言語を流暢に話せます：", A.fillValues("次の言語を流暢に話せます：$T", "You are fluent in:"))
  end)

  it("fails closed on a misplaced or doubled marker", function()
    assert.is_nil(A.fillValues("$T次の言語：", live))
    assert.is_nil(A.fillValues("次の言語：$T$T", live))
    assert.is_nil(A.fillValues("次の言語：$T", nil))
    assert.is_false(A.check("$T次の言語：", { live }))
  end)

  it("a line with no $T is unchanged by the tail rule", function()
    assert.are.equal("7体倒す。", A.fillValues("7体倒す。", "Kill 7 Young Nightsabers.\r\nmore"))
  end)
end)

describe("Core/Align: icons and branch variants (ADR-043)", function()
  local A
  local ICON = "|Tinterface\\icons\\inv_misc_food_15:0|t"
  setup(function()
    local ns = {}
    H.loadPure("Core/Align.lua", "WoWForeverJapanese", ns)
    A = ns.Align
  end)

  it("textures takes icon escapes out of a line and keeps them in order", function()
    local plain, icons = A.textures("Gain " .. ICON .. " Quick Draw and " .. ICON .. ".")
    assert.are.equal("Gain   Quick Draw and  .", plain)
    assert.are.same({ ICON, ICON }, icons)
  end)

  it("an escaped pipe never opens an icon escape", function()
    local plain, icons = A.textures("a ||Tfoo|t b " .. ICON)
    assert.are.equal("a ||Tfoo|t b  ", plain)
    assert.are.same({ ICON }, icons)
  end)

  it("$I<k> is filled with the k-th icon of the live line; a missing one fails closed", function()
    assert.are.equal(ICON .. " Quick Draw：25", (A.fill("$I1 Quick Draw：$N1", { "25" }, {}, { ICON })))
    assert.is_nil(A.fill("$I2 Quick Draw", {}, {}, { ICON }))
  end)

  it("check reads no value, name or number out of an icon path", function()
    local ok, text = A.check("$I1 Quick Draw：$N1のダメージ。", { "Gain " .. ICON .. " Quick Draw: 25 damage." })
    assert.is_true(ok)
    assert.are.equal(ICON .. " Quick Draw：25のダメージ。", text)
    -- without stripping, "15" and "0" in the path would have been $N1 and $N2
    assert.are.same({ "25" }, A.values((A.textures("Gain " .. ICON .. " Quick Draw: 25 damage."))))
    assert.is_false(A.check("$I1 Quick Draw：$N1のダメージ。", { "Gain Quick Draw: 25 damage." }))
  end)

  it("fillValues copies the icon too", function()
    assert.are.equal(ICON .. "を25回復", A.fillValues("$I1を$N1回復", "Restores " .. ICON .. " 25."))
  end)

  local FIRE = { "$N1のFireダメージを吸収する。さらに$N2%の確率でFire呪文を反射する。",
    "$N1のFireダメージを吸収する。" }
  local SHAPES = { "2/0", "1/0" }

  it("checkVariants picks the variant whose shape the live line has (Fire Ward, with and without it)", function()
    local live = "Absorbs 165 Fire damage and grants a 10% chance to reflect Fire spells."
    local ok, text = A.checkVariants(FIRE, SHAPES, { live })
    assert.is_true(ok)
    assert.are.equal("165のFireダメージを吸収する。さらに10%の確率でFire呪文を反射する。", text)
    ok, text = A.checkVariants(FIRE, SHAPES, { "Absorbs 165 Fire damage." })
    assert.is_true(ok)
    assert.are.equal("165のFireダメージを吸収する。", text)
  end)

  it("checkVariants picks by name when the shapes are alike (the faction sign items)", function()
    local signs = { "Orcish Tradeskill Signに加える。", "Dwarven Tradeskill Signに加える。" }
    local ok, text = A.checkVariants(signs, { "0/0", "0/0" }, { "Add the sign to your Dwarven Tradeskill Sign toy." })
    assert.is_true(ok)
    assert.are.equal("Dwarven Tradeskill Signに加える。", text)
  end)

  it("checkVariants fails closed when none or several variants pass", function()
    assert.is_false(A.checkVariants({ "攻撃する。", "防御する。" }, { "0/0", "0/0" }, { "Requires Cat Form." }))
    assert.is_false(A.checkVariants(FIRE, SHAPES, { "Absorbs 165 Fire damage and 10% and 3 more." }))
    assert.is_false(A.checkVariants({ "Stormwindへ。" }, { "0/0" }, { "Returns you to Orgrimmar." }))
    assert.is_false(A.checkVariants({}, {}, { "x" }))
    assert.is_false(A.checkVariants(FIRE, SHAPES, {}))
  end)

  it("identical variant texts count once", function()
    local ok, text = A.checkVariants({ "$N1回復。", "$N1回復。" }, { "1/0", "1/0" }, { "Restores 5." })
    assert.is_true(ok)
    assert.are.equal("5回復。", text)
  end)
end)

-- a list tail after a head of several lines (Riding, the Shaman totem lists): the Japanese head keeps the
-- English head's line breaks, so the live text is cut at the break after them.
describe("name-list tail after a multi-line head", function()
  local A
  setup(function()
    local ns = {}
    H.loadPure("Core/Align.lua", "WoWForeverJapanese", ns)
    A = ns.Align
  end)
  local live = "Allows you to ride basic ground mounts that require a riding skill of 75.\r\n\r\nKnown abilities:"
    .. "\r\nApprentice Riding\r\nBlack Stallion"
  local ja = "ライディングスキル$N1が必要な基本的な地上マウントに乗れます。\r\n\r\n習得済みの能力：$T"

  it("cuts the live text at the break after the head's own breaks", function()
    local head, tail = A.splitTail(ja, live)
    assert.are.equal("ライディングスキル$N1が必要な基本的な地上マウントに乗れます。\r\n\r\n習得済みの能力：", head)
    assert.are.equal("Allows you to ride basic ground mounts that require a riding skill of 75.\r\n\r\n"
      .. "Known abilities:", tail.scope)
    assert.are.equal("\r\nApprentice Riding\r\nBlack Stallion", tail.text)
    assert.are.equal("ライディングスキル75が必要な基本的な地上マウントに乗れます。\r\n\r\n習得済みの能力："
      .. "\r\nApprentice Riding\r\nBlack Stallion", A.fillValues(ja, live))
    local ok, text = A.check(ja, { live })
    assert.is_true(ok)
    assert.are.equal(A.fillValues(ja, live), text)
  end)

  it("a head written with bare line breaks counts them the same", function()
    local _, tail = A.splitTail("乗れます。\n\n習得済み：$T", "Ride.\n\nKnown:\nFoo\nBar")
    assert.are.equal("Ride.\n\nKnown:", tail.scope)
    assert.are.equal("\nFoo\nBar", tail.text)
  end)

  it("with nothing after the head there is no tail; with fewer breaks than the head it fails closed", function()
    local head, tail = A.splitTail(ja, "Allows you to ride.\r\n\r\nKnown abilities:")
    assert.are.equal("ライディングスキル$N1が必要な基本的な地上マウントに乗れます。\r\n\r\n習得済みの能力：", head)
    assert.are.same({ scope = "Allows you to ride.\r\n\r\nKnown abilities:", text = "" }, tail)
    assert.is_nil(A.splitTail(ja, "Allows you to ride. Known abilities:\r\nApprentice Riding"))
    assert.is_nil(A.fillValues(ja, "Allows you to ride. Known abilities:\r\nApprentice Riding"))
    assert.is_false(A.check(ja, { "Allows you to ride. Known abilities:\r\nApprentice Riding" }))
  end)

  it("a one-line head still cuts at the first break", function()
    local head, tail = A.splitTail("次の言語：$T", "You know:\r\nCommon\r\nDwarvish")
    assert.are.equal("次の言語：", head)
    assert.are.same({ scope = "You know:", text = "\r\nCommon\r\nDwarvish" }, tail)
  end)
end)

-- a VARIANT KEY: the hash of a live line's wording with its values masked, which picks between variants whose
-- numbers alone cannot tell them apart (the Druid feral talents). Python `align.variant_key` keys the English
-- template the same way; the vectors hold the pairs.
describe("Core/Align.variantKey and keyed variants", function()
  local A
  local SEC = function(t) return ({ ["30 sec"] = "30秒", ["18 sec"] = "18秒", ["3 sec"] = "3秒", ["4 sec"] = "4秒",
    ["5 sec"] = "5秒", ["2 min"] = "2分", ["1 hr 30 min"] = "1時間30分" })[t] end
  setup(function()
    local ns = {}
    H.loadPure("Core/Normalize.lua", "WoWForeverJapanese", ns)
    H.loadPure("Core/Hash.lua", "WoWForeverJapanese", ns)
    H.loadPure("Core/Align.lua", "WoWForeverJapanese", ns)
    A = ns.Align
  end)

  it("matches every vector: the live text keys to its template's key", function()
    local V = dofile(H.ROOT .. "/vectors/align_vectors.lua")
    local n = 0
    for _, c in ipairs(V.cases) do
      if c.op == "variantKey" then
        assert.are.equal(c.expected, A.variantKey(c.text, SEC), c.id)
        n = n + 1
      end
    end
    assert.is_true(n >= 8)
  end)

  it("masks values, durations with their unit, ranges and icons; the wording stays", function()
    local ICON = "|Tinterface\\icons\\x:0|t"
    assert.are.equal(A.variantKey("Deals 5 damage.", SEC), A.variantKey("Deals 1,200 damage.", SEC))
    assert.are.equal(A.variantKey("Lasts 30 sec.", SEC), A.variantKey("Lasts 2 min.", SEC))
    assert.are.equal(A.variantKey("Causes 14 to 22 damage.", SEC), A.variantKey("Causes 7 damage.", SEC))
    assert.are.equal(A.variantKey(ICON .. " Fire: 5", SEC), A.variantKey("Fire: 9", SEC))
    assert.are_not.equal(A.variantKey("Deals 5 damage.", SEC), A.variantKey("Deals 5 Fire damage.", SEC))
    assert.is_nil(A.variantKey(nil, SEC))
  end)

  it("checkVariants takes only the variant whose key the live line has", function()
    local V = { "与える全てのダメージが$N1%増加する。", "物理攻撃のダメージが$N1%増加する。" }
    V.shape = { "1/0", "1/0" }
    V.key = { A.variantKey("Increases all damage you deal by 10%.", SEC),
              A.variantKey("Increases the damage you deal with physical attacks by 10%.", SEC) }
    local ok, text = A.checkVariants(V, V.shape, { "Increases all damage you deal by 4%." }, nil, SEC)
    assert.is_true(ok)
    assert.are.equal("与える全てのダメージが4%増加する。", text)
    ok, text = A.checkVariants(V, V.shape, { "Increases the damage you deal with physical attacks by 4%." }, nil, SEC)
    assert.is_true(ok)
    assert.are.equal("物理攻撃のダメージが4%増加する。", text)
    -- a wording neither key matches, or a line without the values, fails closed
    assert.is_false(A.checkVariants(V, V.shape, { "Increases all damage you deal by 4% and more." }, nil, SEC))
    assert.is_false(A.checkVariants(V, V.shape, { "Increases all damage you deal." }, nil, SEC))
  end)

  it("a slot without keys behaves exactly as before", function()
    local V = { "攻撃する。", "防御する。" }
    assert.is_false(A.checkVariants(V, { "0/0", "0/0" }, { "Requires Cat Form." }))
    local one = { "$N1回復。" }
    local ok, text = A.checkVariants(one, { "1/0" }, { "Restores 5." })
    assert.is_true(ok)
    assert.are.equal("5回復。", text)
  end)
end)

-- A line numbered for English that prints another count of values. Every number it fills in is in the live line,
-- so the names and numbers gate passes it; only the count tells that the values have moved.
describe("the count of values a line is numbered to", function()
  local A
  setup(function()
    local ns = {}
    H.loadPure("Core/Align.lua", "WoWForeverJapanese", ns)
    A = ns.Align
  end)
  local OLD = "一定の確率でコストを$N1%軽減します。最大$N2回まで重なります。"
  local NEW = "$N1%の確率でコストを$N2%軽減します。最大$N3回まで重なります。"
  local SHORT = { "You have a chance to reduce the cost by 20%. Stacks up to 5 times." }
  local LONG = { "You have a 12% chance to reduce the cost by 20%. Stacks up to 5 times." }

  it("without a count, a line numbered for a shorter template passes with the wrong values", function()
    local ok, text = A.check(OLD, LONG)
    assert.is_true(ok)
    assert.are.equal("一定の確率でコストを12%軽減します。最大20回まで重なります。", text)
  end)

  it("with its count, it is shown on the line it was numbered for and on no other", function()
    assert.are.same({ true, "一定の確率でコストを20%軽減します。最大5回まで重なります。" }, { A.check(OLD, SHORT, nil, nil, 2) })
    assert.is_false((A.check(OLD, LONG, nil, nil, 2)))
    assert.are.same({ true, "12%の確率でコストを20%軽減します。最大5回まで重なります。" }, { A.check(NEW, LONG, nil, nil, 3) })
    assert.is_false((A.check(NEW, SHORT, nil, nil, 3)))
    assert.is_false((A.check(NEW, LONG, nil, nil, -1))) -- the count of a line that waits for a redraft
  end)

  it("counts what `values` reads: a range is one value, a glued digit and an icon's path are none", function()
    assert.are.same({ true, "14～22のダメージ。" }, { A.check("$N1のダメージ。", { "Deals 14 to 22 damage." }, nil, nil, 1) })
    assert.is_false((A.check("$N1のダメージ。", { "Deals 14 to 22 damage." }, nil, nil, 2)))
    local icon = { "|TInterface\\Icons\\inv_misc_food_15:16|t Restores 50 health with the Mk2." }
    assert.is_true((A.check("$I1 体力を$N1回復する。", icon, nil, nil, 1)))
  end)

  it("a name-list tail is not counted: the count is the head's", function()
    local live = { "You know 2 languages.\nCommon 2\nDarnassian" }
    assert.are.same({ true, "2個の言語を話せます。\nCommon 2\nDarnassian" }, { A.check("$N1個の言語を話せます。$T", live, nil, nil, 1) })
    assert.is_false((A.check("$N1個の言語を話せます。$T", live, nil, nil, 2)))
  end)

  it("the gate hands an entry's count on, for a gated and for a trusted line", function()
    for _, status in ipairs({ "u", "s", "." }) do
      assert.is_false(A.gate({ ja = OLD, status = status, values = 2 }, LONG), status)
      assert.is_true((A.gate({ ja = NEW, status = status, values = 3 }, LONG)), status)
      assert.is_true((A.gate({ ja = OLD, status = status }, LONG)), status) -- no count: gated as before
    end
  end)

  it("fillValues takes the count too, and a line with nothing to fill never fails on it", function()
    assert.is_nil(A.fillValues(OLD, LONG[1], nil, 2))
    assert.are.equal("12%の確率でコストを20%軽減します。最大5回まで重なります。", A.fillValues(NEW, LONG[1], nil, 3))
    assert.are.equal("変わりません。", A.fillValues("変わりません。", LONG[1], nil, 9))
  end)
end)

-- A spell the character does not know: the client prints its own words where a duration belongs, leaves out the
-- text of an ability the spell grants, and a few templates glue a value to a word.
describe("a spell the character does not know", function()
  local A
  -- the stub of UIStrings' renderer: the durations it knows, and the client's phrase with its Japanese
  local DUR = {
    render = function(t) return ({ ["1.5 sec"] = "1.5秒", ["2 sec"] = "2秒", ["5.2 sec"] = "5.2秒",
      ["10 sec"] = "10秒" })[t] end,
    words = { { en = "until canceled", ja = "解除されるまで" } },
  }
  local NUMBERS = function(t) return DUR.render(t) end -- a client whose dictionary has no Japanese for the phrase
  setup(function()
    local ns = {}
    H.loadPure("Core/Align.lua", "WoWForeverJapanese", ns)
    A = ns.Align
  end)

  it("fills a $D slot with \"until canceled\" where the Japanese after it can take words", function()
    local thorns = { "Thorns sprout from the friendly target causing 475 to 525 Nature damage to attackers when hit."
      .. "  Lasts until canceled." }
    assert.are.same({ true, "味方の対象からイバラが生え、攻撃者に475～525のNatureダメージを与えます。解除されるまで持続します。" },
      { A.check("味方の対象からイバラが生え、攻撃者に$N1のNatureダメージを与えます。$D1持続します。", thorns, nil, DUR, 2) })
    -- "over 10 sec" is written `$D1かけて`: the particle goes with the number
    local burn = { "Burns the enemy for Arcane damage and inflicts additional damage over until canceled." }
    local BURN = "敵を焼いてArcaneダメージを与え、さらに$D1かけて追加のダメージを与えます。"
    assert.are.same({ true, "敵を焼いてArcaneダメージを与え、さらに解除されるまで追加のダメージを与えます。" },
      { A.check(BURN, burn, nil, DUR, 1) })
    assert.are.same({ true, "敵を焼いてArcaneダメージを与え、さらに10秒かけて追加のダメージを与えます。" },
      { A.check(BURN, { "Burns the enemy for Arcane damage and inflicts additional damage over 10 sec." }, nil,
        DUR, 1) })
    -- the phrase holds the first value's place, so the later slots keep their numbers
    local whirl = { "You attack all nearby enemies for until canceled causing weapon damage plus an additional 5 "
      .. "every 5.2 sec." }
    assert.are.same({ true, "解除されるまでの間、近くの敵すべてを攻撃し、5.2秒ごとに武器ダメージに加えて5の追加ダメージを与えます。" },
      { A.check("$D1の間、近くの敵すべてを攻撃し、$D2ごとに武器ダメージに加えて$N2の追加ダメージを与えます。", whirl, nil, DUR, 3) })
  end)

  it("leaves the line English where the slot cannot take words, or the phrase has no Japanese", function()
    local tick = { "Suffering Arcane damage every until canceled." }
    assert.is_false((A.check("$D1ごとにArcaneダメージを受けています。", tick, nil, DUR, 1)))
    assert.is_false((A.check("$D1後に爆発します。", { "Explodes after until canceled." }, nil, DUR, 1)))
    local burn = { "Burns the enemy for Arcane damage and inflicts additional damage over until canceled." }
    assert.is_false((A.check("敵を焼いてArcaneダメージを与え、さらに$D1かけて追加のダメージを与えます。", burn, nil, NUMBERS, 1)))
    assert.is_false((A.check("敵を焼いてArcaneダメージを与え、さらに$D1かけて追加のダメージを与えます。", burn, nil, nil, 1)))
    -- the phrase is never a number: a `$N` pointing at its place fails closed
    assert.is_false((A.check("$N1の間、$D1持続します。", { "Lasts until canceled." }, nil, DUR, 1)))
    -- and it is counted only for a Japanese that asks for a duration
    assert.are.same({}, A.values("Appears poisoned until canceled."))
    assert.are.same({ false }, A.values("Appears poisoned until canceled.", DUR))
    assert.is_true((A.check("解除されるまで毒に見えます。", { "Appears poisoned until canceled." }, nil, DUR)))
    assert.are.same({ "解除されるまで", "2秒", worded = { true } }, A.durations("Lasts until canceled, then 2 sec.", DUR))
    assert.are.same({ "2秒" }, A.durations("uncanceled untilcanceled 2 sec.", DUR))
  end)

  it("a variant key masks the phrase as the duration it stands for", function()
    local ns = {}
    H.loadPure("Core/Normalize.lua", "WoWForeverJapanese", ns)
    H.loadPure("Core/Hash.lua", "WoWForeverJapanese", ns)
    H.loadPure("Core/Align.lua", "WoWForeverJapanese", ns)
    assert.are.equal(ns.Align.variantKey("Lasts 10 sec.", DUR), ns.Align.variantKey("Lasts until canceled.", DUR))
  end)

  it("shows a granted ability's heading and icon when the client left the ability's text out", function()
    local JA = "Wyvern Strikeのアビリティを得ます：\n\n$I1\n対象に$N1のダメージを与え、$D1の間$N2のダメージを与えます。"
    local short = { "Gain the Wyvern Strike ability:\r\n\r\n|T135125:24|t\r\n" }
    assert.are.same({ true, "Wyvern Strikeのアビリティを得ます：\n\n|T135125:24|t" }, { A.check(JA, short, nil, DUR, 3) })
    local rune = { "Engrave your chest with the Burnout rune:\r\n\r\n|T236207:24|t\r\n" }
    assert.are.same({ true, "胸部にBurnoutのルーンを刻みます：\n\n|T236207:24|t" },
      { A.check("胸部にBurnoutのルーンを刻みます：\n\n$I1\n呪文のクリティカル率が$N1%上昇します。", rune, nil, DUR, 1) })
    -- the heading is still held to the live line's names
    assert.is_false((A.check(JA, { "Gain the Mutilate ability:\r\n\r\n|T135125:24|t\r\n" }, nil, DUR, 3)))
    -- a live line that carries the ability's text gets the whole check
    local long = { "Gain the Wyvern Strike ability:\r\n\r\n|T135125:24|t\r\nDeals 40 damage, then 12 over 10 sec." }
    assert.are.same({ true, "Wyvern Strikeのアビリティを得ます：\n\n|T135125:24|t\n対象に40のダメージを与え、10秒の間12のダメージを与えます。" },
      { A.check(JA, long, nil, DUR, 3) })
    assert.is_false((A.check(JA, { long[1] .. " And 5 more." }, nil, DUR, 3)))
    -- a line with no icon, or a Japanese with no text after its icon, is not this case
    assert.is_false((A.check(JA, { "Gain the Wyvern Strike ability:" }, nil, DUR, 3)))
    assert.is_nil(A.grantedHead("Wyvern Strikeのアビリティを得ます：\n\n$I1", short[1]))
    assert.is_true((A.gate({ ja = JA, status = "u", values = 3 }, short, DUR)))
  end)

  -- spells 401417 and 412510 as the client prints them for a character without Temporal Beacon: a heading with
  -- values and durations of its own, the ability's name and icon, and nothing after the icon
  it("shows a granted ability's heading with its own values, held to the heading's count", function()
    local SECS = { render = function(t) return ({ ["12 sec"] = "12秒", ["60 sec"] = "60秒", ["30 sec"] = "30秒" })[t] end }
    local TEMPORAL = "$D1かけて体力を$N1回復し、$D2の間Temporal Beaconを付与します。\r\n\nTemporal Beacon\r\n$I1\r\n"
      .. "対象の時空間の位置を記録します。術者が与えたArcaneダメージの$N4%が変換されます。"
    local live = { "Heals the target for 450 health over 12 sec and applies Temporal Beacon for 60 sec. \r\n\r\n"
      .. "Temporal Beacon\r\n|T237538:24|t\r\n" }
    assert.are.same({ true, "12秒かけて体力を450回復し、60秒の間Temporal Beaconを付与します。\r\n\nTemporal Beacon\r\n"
      .. "|T237538:24|t" }, { A.check(TEMPORAL, live, nil, SECS) })
    assert.is_true((A.gate({ ja = TEMPORAL, status = "u" }, live, SECS)))
    local PARTY = "対象のプレイヤーから$N1ヤード以内にいる、そのプレイヤーのパーティーメンバー全員を$D1かけて体力を$N2回復し、"
      .. "それぞれに$D2の間Temporal Beaconを付与します。\r\n\nTemporal Beacon\r\n$I1\r\n本文の$N5%。"
    local party = { "Heals all of target player's party members within 40 yards of target player for 300 health over"
      .. " 12 sec and applies Temporal Beacon to each target for 30 sec.\r\n\r\nTemporal Beacon\r\n|T237538:24|t" }
    assert.are.same({ true, "対象のプレイヤーから40ヤード以内にいる、そのプレイヤーのパーティーメンバー全員を12秒かけて体力を"
      .. "300回復し、それぞれに30秒の間Temporal Beaconを付与します。\r\n\nTemporal Beacon\r\n|T237538:24|t" },
      { A.check(PARTY, party, nil, SECS) })
    -- a heading the client prints with one value more or one fewer: every later slot would move, English stays
    assert.is_false((A.check(TEMPORAL, { live[1]:gsub("for 60 sec", "for 60 sec, 5 times") }, nil, SECS)))
    assert.is_false((A.check(TEMPORAL, { live[1]:gsub("for 450 health ", "") }, nil, SECS)))
    -- still held to the heading's names, and to its durations
    assert.is_false((A.check(TEMPORAL, { live[1]:gsub("Temporal Beacon", "Chrono Beacon") }, nil, SECS)))
    assert.is_false((A.check(TEMPORAL, live, nil, nil)))
    -- the ability's text on the live line: the whole check, which the shortened sample cannot pass
    assert.is_false((A.check(TEMPORAL, { live[1] .. "Records the target's location." }, nil, SECS)))
  end)

  it("reads a number glued to a word only when the strict reading misses the line's count", function()
    local stun = { "Deal 294 Physical damage and stun for1.5 sec. Trolls take 2 times as much damage and stun "
      .. "duration." }
    local STUN = "$N1のPhysicalダメージを与え、$D1の間スタンさせます。トロールは$N3倍のダメージとスタン時間を受けます。"
    assert.are.same({ true, "294のPhysicalダメージを与え、1.5秒の間スタンさせます。トロールは2倍のダメージとスタン時間を受けます。" },
      { A.check(STUN, stun, nil, DUR, 3) })
    assert.are.same({ true, "蓄えた時間術のエネルギーを解き放ち、味方の対象の体力を即座に79から118回復します。" },
      { A.check("蓄えた時間術のエネルギーを解き放ち、味方の対象の体力を即座に$N1から$N2回復します。",
        { "Unleash stored chronomantic energy to instantly heal a friendly target for 79to 118." }, nil, DUR, 2) })
    assert.are.same({ true, "2秒ごとに140のNatureダメージを与えます。トロールには2倍のダメージを与えます。" },
      { A.check("$D1ごとに$N1のNatureダメージを与えます。トロールには$N3倍のダメージを与えます。",
        { "Inflicts140 Nature damage per 2 sec. Deaks 2 times as much damage to Trolls." }, nil, DUR, 3) })
    assert.are.same({ true, "対象に19～37のNatureダメージを与えます。Mechanicalの対象は2倍のダメージを受けます。" },
      { A.check("対象に$N1のNatureダメージを与えます。Mechanicalの対象は$N2倍のダメージを受けます。",
        { "Blasts a target for 19 to 37 Nature damage. Mechanical targets take 2x damage." }, nil, DUR, 2) })
    assert.are.same({ true, "故障が発生しました。2秒ごとにアーケインエネルギーが放出されます。" },
      { A.check("故障が発生しました。$N1秒ごとにアーケインエネルギーが放出されます。",
        { "A malfunction has occurred. Every 2s arcane energy is released dealing damage to players in a nearby "
          .. "area." }, nil, DUR, 1) })
    assert.are.same({ true, "焼き印を消費すると、-24～-21のShadowダメージを与えます。" },
      { A.check("焼き印を消費すると、$N1のShadowダメージを与えます。",
        { "Consuming a brand deals -24 to -21 Shadow damage." }, nil, DUR, 1) })
  end)

  it("never reads a name's number, and never changes a line the strict reading fits", function()
    -- no count, no loose reading
    assert.is_false((A.check("$N1のダメージ、$N2秒。", { "Deals 5 damage for2 sec." })))
    -- the strict reading has the count: the glued number stays out even though its shape is one the loose takes
    assert.are.same({ true, "5のダメージ、3回。" },
      { A.check("$N1のダメージ、$N2回。", { "Deals 5 damage 3 times for2 sec." }, nil, nil, 2) })
    -- a name's number is no shape the loose reading takes, so the count cannot be made up from it
    for _, name in ipairs({ "Mk2", "Mace2H", "247x128", "G00 DV-1B3", "AQ40", "x2", "30sec" }) do
      assert.is_false((A.check("$N1のダメージ、$N2。", { "Deals 5 damage with the " .. name .. "." }, nil, nil, 2)), name)
      assert.are.same({ "5" }, A.values("Deals 5 damage with the " .. name .. ".", nil, true), name)
    end
    -- the loose reading with more or fewer values than the count is refused too
    assert.is_false((A.check("$N1のダメージ。", { "Deals for5 damage for2 sec." }, nil, nil, 1)))
    assert.is_false((A.check("$N1、$N2、$N3、$N4。", { "Deals for5 damage for2 sec." }, nil, nil, 4)))
  end)
end)
