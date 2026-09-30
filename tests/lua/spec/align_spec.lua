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

  it("a range the client prints is one value, filled as A～B", function()
    local live = "Hurls a fiery ball that causes 14 to 22 Fire damage and an additional 2 Fire damage over 4 sec."
    assert.are.same({ "14～22", "2", "4" }, A.values(live))
    local ja = "$N1のFireダメージを与え、さらに$N3秒かけて$N2のFireダメージを与えます。"
    assert.are.equal("14～22のFireダメージを与え、さらに4秒かけて2のFireダメージを与えます。", A.fillValues(ja, live))
    local ok, text = A.check(ja, { live })
    assert.is_true(ok); assert.are.equal("14～22のFireダメージを与え、さらに4秒かけて2のFireダメージを与えます。", text)
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
