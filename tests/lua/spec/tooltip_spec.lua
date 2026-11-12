-- UI/Tooltip: the description run, companions, six frames, modifier, release, re-entrancy.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Align.lua", "Core/State.lua", "Core/Settings.lua",
  "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Normalize.lua", "Core/Hash.lua",
  "Core/Collector.lua", "UI/Font.lua", "UI/Render.lua",
  "UI/TimeLine.lua", "UI/Tooltip.lua", "UI/TooltipUnit.lua" }

local DATA = {
  -- keyed by the kind the surface asks for; field-qualified because spell has two fields
  ["item.description"] = {
    [117] = { ja = "18秒間でhealthを61回復。回復中は\n座っている必要があります。", status = "u" },
    [2001] = { ja = "Herbalismのスキルを2上昇させます。\n野生のハーブを摘むための取扱説明書。", status = "u" },
    [724] = { ja = "21秒間でhealthを243回復。10秒以上食事に時間をかけると、15分間StaminaとSpiritを4上昇させます。", status = "u" },
    [6948] = { ja = "【使用】Hearthstoneの場所に戻ります。", status = "u" },
    -- issue #87, Gnarled Necromancer's Staff: its description is the second of two Equip lines in a row
    [251534] = { ja = "Silverpine ForestとHillsbrad Foothillsでの移動速度が$N1%上昇します。", status = "u" },
    [900] = { ja = "移動速度が$N1%上昇します。", status = "u" }, -- names nothing: fits any line with a number
  },
  ["spell.description"] = {
    [17] = { ja = "味方にシールドを張り、$N1ダメージを吸収します。$N2秒間持続します。", status = "u" },
    [53] = { ja = "ターゲットを背後から攻撃し、$N1 ダメージを与えます。", status = "u" },
    [1310316] = { ja = "盾を装備している間にDodgeまたはParryすると、$N1%の確率で怒りを$N2生み出します。", status = "u" },
  },
}
local JERKY = "|Hitem:117:0:0:0:0:0:0:0|h[Tough Jerky]|h"
local JERKY_LINES = { "Tough Jerky", "Use: Restores 61 health over 18 sec. Must remain seated while eating.",
  "Sell Price: 5c" }

describe("UI/Tooltip: item and spell tooltips", function()
  local WFJ, S, SS, TT, tt

  local function fs(frameName, i) return _G[frameName .. "TextLeft" .. i] end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    S, SS, TT = WFJ.Settings, WFJ.SurfaceState, WFJ.Tooltip
    WFJ.Compat.init(function(name) return _G[name] end)
    S.load(nil, 1, {})
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      showsEnglish = WFJ.Modifier.english,
      lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      marker = function(n) return S.get("marker." .. n) end,
      align = WFJ.Align.check,
    }))
    assert.are.equal(6, TT.init())
    tt = _G.GameTooltip
    Stub.spellDescriptions[17] =
      "Draws on the soul of the friendly target to shield them, absorbing 44 damage. Lasts 30 sec."
    Stub.spellDescriptions[53] = "Backstab the target, causing 150% weapon damage plus 15 to the target."
  end)

  it("replaces the Use: line in place and leaves name and price alone", function()
    Stub.setItemTooltip(tt, JERKY, JERKY_LINES)
    assert.are.equal(DATA["item.description"][117].ja, fs("GameTooltip", 2):GetText())
    assert.are.equal(WFJ.Font.PATH, (fs("GameTooltip", 2):GetFont()))
    assert.are.equal("Tough Jerky", fs("GameTooltip", 1):GetText())
    assert.are.equal("Sell Price: 5c", fs("GameTooltip", 3):GetText())
    assert.are.equal(0, fs("GameTooltip", 1).calls.SetText)
    assert.are.equal(0, fs("GameTooltip", 3).calls.SetText)
    assert.are.equal(2, tt.calls.Show) -- one refit, two Shows (the layout count stays even)
    assert.are.equal(1, SS.count("tooltip.GameTooltip"))
  end)

  it("a Use: + Equip: + quote run collapses into its first line; the companions blank", function()
    Stub.setItemTooltip(tt, "|Hitem:724:0:0:0:0:0:0:0|h[Goretusk Liver Pie]|h", {
      "Goretusk Liver Pie", "Binds when picked up",
      "Use: Restores 243 health over 21 sec. Must remain seated while eating. If you spend at least 10 seconds "
        .. "eating you will become well fed and gain 4 Stamina and Spirit for 15 min.",
      "Equip: Something.", '"Tastes like liver."', "Sell Price: 5c" })
    assert.are.equal(DATA["item.description"][724].ja, fs("GameTooltip", 3):GetText())
    assert.are.equal(WFJ.Render.BLANK, fs("GameTooltip", 4):GetText())
    assert.are.equal(WFJ.Render.BLANK, fs("GameTooltip", 5):GetText())
    assert.are.equal("Binds when picked up", fs("GameTooltip", 2):GetText())
    assert.are.equal("Sell Price: 5c", fs("GameTooltip", 6):GetText())
    assert.are.equal(3, SS.count("tooltip.GameTooltip"))
    assert.are.equal(2, tt.calls.Show) -- one refit (two Shows)
  end)

  describe("an item description that is one Equip line among several (issue #87)", function()
    local POWER = "Equip: Increases damage and healing done by magical spells and effects by up to 26."
    local SPEED = "Equip: Increases movement speed by 2% in Silverpine Forest and Hillsbrad Foothills."
    before_each(function()
      WFJ.Lookup = { get = function(kind, id) return DATA[kind] and DATA[kind][id] end }
      WFJ.UIIndex = {
        statLine = function(_, text) if text == POWER then return "SPELL_POWER", { "26" } end end,
        duration = function() return nil end,
        match = function() return nil end,
        matchOnly = function() return nil end,
        clientTail = function() return nil end,
      }
    end)
    after_each(function() WFJ.Lookup, WFJ.UIIndex = nil, nil end)

    it("the description takes its own line's number; the spell power line is matched as a stat line", function()
      local shown = {}
      local real = WFJ.Render.show
      WFJ.Render.show = function(surface, key, w, en, area, kind, id, ctx)
        if kind == "ui" then shown[#shown + 1] = { key = key, id = id, args = ctx and ctx.args } end
        return real(surface, key, w, en, area, kind, id, ctx)
      end
      Stub.setItemTooltip(tt, "|Hitem:251534:0:0:0:0:0:0:0|h[Gnarled Necromancer's Staff]|h",
        { "Gnarled Necromancer's Staff", "+10 Spirit", POWER, SPEED, "Sell Price: 36s" })
      WFJ.Render.show = real
      assert.are.equal("Silverpine ForestとHillsbrad Foothillsでの移動速度が2%上昇します。", fs("GameTooltip", 4):GetText())
      assert.are.not_equal(WFJ.Render.BLANK, fs("GameTooltip", 3):GetText()) -- never folded into the description
      assert.are.same({ { key = "ui.L3", id = "SPELL_POWER", args = { "26" } } }, shown)
    end)

    it("a description whose Japanese fits both lines on their own keeps the whole run, as before", function()
      Stub.setItemTooltip(tt, "|Hitem:900:0:0:0:0:0:0:0|h[Two Speeds]|h",
        { "Two Speeds", "Equip: Increases movement speed by 3%.", "Equip: Increases movement speed by 5%." })
      assert.are.equal(WFJ.Render.BLANK, fs("GameTooltip", 3):GetText())
    end)
  end)

  it("a flavour line in another colour keeps its colour in the Japanese; one colour adds nothing", function()
    local GREEN, GOLD = { 0, 1, 0 }, { 1, 0.82, 0 }
    Stub.setItemTooltip(tt, "|Hitem:2001:0:0:0:0:0:0:0|h[Wild Harvest]|h", {
      "Wild Harvest", { "Use: Increases your Herbalism skill by 2.", color = GREEN },
      { '"An instruction manual for picking wild herbs."', color = GOLD } })
    assert.are.equal("Herbalismのスキルを2上昇させます。\n|cffffd100野生のハーブを摘むための取扱説明書。|r",
      fs("GameTooltip", 2):GetText())
    Stub.setItemTooltip(tt, "|Hitem:2001:0:0:0:0:0:0:0|h[Wild Harvest]|h", {
      "Wild Harvest", { "Use: Increases your Herbalism skill by 2.", color = GREEN },
      { '"An instruction manual for picking wild herbs."', color = GREEN } })
    assert.are.equal(DATA["item.description"][2001].ja, fs("GameTooltip", 2):GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh() -- Alt shows the client's English, colour and all
    assert.are.equal("Use: Increases your Herbalism skill by 2.", fs("GameTooltip", 2):GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
  end)

  it("colourRuns colours a whole number found once, from the right, never inside a longer number", function()
    local cr = WFJ.Render.colourRuns
    local G, R = "|cff20ff20", "|cffff2020"
    assert.are.equal("アーマー " .. G .. "+17|r", cr("アーマー +17", { { run = "+17", code = G } }))
    assert.are.equal("アーマー +170", cr("アーマー +170", { { run = "+17", code = G } })) -- part of a longer number
    assert.are.equal("+1 と +1", cr("+1 と +1", { { run = "+1", code = G } })) -- twice: left alone
    -- two runs: both coloured, neither inside the other's code ("20" also appears in the code)
    assert.are.equal(G .. "+20|r / " .. R .. "-5|r",
      cr("+20 / -5", { { run = "+20", code = G }, { run = "-5", code = R } }))
  end)

  it("part colours skip empty parts on both sides: a blank line or a paragraph break never shifts them", function()
    local cp = WFJ.Render.colourParts
    local gold = { n = 2, [2] = "ffffd100" }
    assert.are.equal("説明。\n\n|cffffd100フレーバー。|r", cp("説明。\n\nフレーバー。", gold))
    assert.are.equal("説明。\n|cffffd100フレーバー。|r", cp("説明。\nフレーバー。", gold))
    assert.are.equal("一。\n二。\n三。", cp("一。\n二。\n三。", gold)) -- parts do not line up: as it is
  end)

  it("no description run, no item, or a gate failure → nothing written", function()
    WFJ.Settings.set("marker.missing", false) -- on by default; this test reads the text, not the marker
    Stub.setItemTooltip(tt, "|Hitem:117:0:0:0:0:0:0:0|h[x]|h",
      { "Tough Jerky", "Binds when picked up", "Sell Price: 5c" })
    assert.are.equal(0, SS.count("tooltip.GameTooltip"))
    assert.are.equal(0, tt.calls.Show)
    Stub.setItemTooltip(tt, nil, JERKY_LINES)
    assert.are.equal("Use: Restores 61 health over 18 sec. Must remain seated while eating.",
      fs("GameTooltip", 2):GetText())
    Stub.setItemTooltip(tt, JERKY, { "Tough Jerky", "Use: Restores 70 health over 18 sec." })
    assert.are.equal("Use: Restores 70 health over 18 sec.", fs("GameTooltip", 2):GetText())
    assert.are.equal(0, fs("GameTooltip", 2).calls.SetText)
  end)

  it("the spell description is the last line, $N filled from it; rank/cost lines untouched", function()
    Stub.setSpellTooltip(tt, 17, { "Power Word: Shield", "Rank 1", "45 Mana", "30 yd range", "Instant cast",
      "Draws on the soul of the friendly target to shield them, absorbing 44 damage. Lasts 30 sec." })
    assert.are.equal("味方にシールドを張り、44ダメージを吸収します。30秒間持続します。", fs("GameTooltip", 6):GetText())
    for i = 1, 5 do assert.are.equal(0, fs("GameTooltip", i).calls.SetText, "line " .. i) end
  end)

  it("with a Next rank: block the description is the line above it; talent hints are skipped", function()
    Stub.setSpellTooltip(tt, 53, { "Backstab", "Rank 1", "10 Energy", "Melee Range", "Instant",
      "Backstab the target, causing 150% weapon damage plus 15 to the target.",
      "Next rank:", "Backstab the target, causing 150% weapon damage plus 25 to the target." })
    assert.are.equal("ターゲットを背後から攻撃し、150 ダメージを与えます。", fs("GameTooltip", 6):GetText())
    assert.are.equal("Next rank:", fs("GameTooltip", 7):GetText())
    assert.are.equal("Backstab the target, causing 150% weapon damage plus 25 to the target.",
      fs("GameTooltip", 8):GetText())
    tt:Hide()
    Stub.setSpellTooltip(tt, 53, { "Backstab", "Rank 1",
      "Backstab the target, causing 150% weapon damage plus 15 to the target.", "Left click to add a point" })
    assert.are.equal("ターゲットを背後から攻撃し、150 ダメージを与えます。", fs("GameTooltip", 3):GetText())
    assert.are.equal("Left click to add a point", fs("GameTooltip", 4):GetText())
  end)

  it("a talent's next rank, appended to the tooltip, is Japanese too; Alt shows both ranks' English", function()
    _G.Enum.TooltipDataLineType = { SpellDescription = 99 }
    local R1 = "Grants you a 50% chance to generate 5 Rage when you Dodge or Parry while a shield is equipped."
    local R2 = "Grants you a 100% chance to generate 5 Rage when you Dodge or Parry while a shield is equipped."
    Stub.spellDescriptions[1310316] = R1
    Stub.setSpellTooltip(tt, 1310316, { "Master of Defense", "Rank 1/2", "Passive", R1 })
    -- the talent tooltip appends the next rank (AppendInfo) and the client runs the post-call again with its data,
    -- the current rank's line still showing the Japanese of the pass before
    tt:AddLine(" "); tt:AddLine("Next Rank:"); tt:AddLine("Passive"); tt:AddLine(R2)
    tt.processingInfo = { append = true }
    for _, fn in ipairs(Stub.tooltipPostCalls[1]) do
      fn(tt, { id = 1310316, lines = { { type = 99, leftText = R2 } } })
    end
    tt.processingInfo = nil
    local JA1 = "盾を装備している間にDodgeまたはParryすると、50%の確率で怒りを5生み出します。"
    local JA2 = "盾を装備している間にDodgeまたはParryすると、100%の確率で怒りを5生み出します。"
    assert.are.equal(JA1, fs("GameTooltip", 4):GetText())
    assert.are.equal(JA2, fs("GameTooltip", 8):GetText())
    -- the current rank's record holds its real English, not the Japanese it was read with: Alt never shows boxes
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(R1, fs("GameTooltip", 4):GetText())
    assert.are.equal(R2, fs("GameTooltip", 8):GetText())
    assert.are_not.equal(WFJ.Font.PATH, (fs("GameTooltip", 4):GetFont()))
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal(JA1, fs("GameTooltip", 4):GetText())
    assert.are.equal(JA2, fs("GameTooltip", 8):GetText())
    _G.Enum.TooltipDataLineType = nil
  end)

  it("a blank line above Next rank: is never the description; an empty first line refuses the run", function()
    Stub.setSpellTooltip(tt, 53, { "Backstab", "Rank 1",
      "Backstab the target, causing 150% weapon damage plus 15 to the target.", "", "Next rank:",
      "Backstab the target, causing 150% weapon damage plus 25 to the target." })
    assert.are.equal("ターゲットを背後から攻撃し、150 ダメージを与えます。", fs("GameTooltip", 3):GetText())
    assert.are.equal(3, TT.spellLine({ "n", "Rank 1", "desc", "", "Next rank:", "x" })) -- positional rule too
    assert.are.equal("", fs("GameTooltip", 4):GetText())
    assert.are.equal(0, fs("GameTooltip", 4).calls.SetText)
    assert.are.equal(3, TT.spellLine({ "n", "Rank 1", "desc", "", "Next rank:", "x" }))
    assert.is_nil(TT.spellLine({ "n", "", "Next rank:", "x" }))
    tt:Hide()
    -- an item run can never start on an empty line (isDescription needs text): show()'s refusal is exercised directly
    Stub.setItemTooltip(tt, JERKY, { "Tough Jerky", "Binds when picked up", "", "Sell Price: 5c" })
    assert.are.equal(0, SS.count("tooltip.GameTooltip"))
  end)

  it("the description is found by content: an appended addon line or an aura line is never taken", function()
    Stub.setSpellTooltip(tt, 53, { "Backstab", "Rank 1", "10 Energy",
      "Backstab the target, causing 150% weapon damage plus 15 to the target.", "Spell ID: 53" })
    assert.are.equal("ターゲットを背後から攻撃し、150 ダメージを与えます。", fs("GameTooltip", 4):GetText())
    assert.are.equal("Spell ID: 53", fs("GameTooltip", 5):GetText())
    assert.are.equal(0, fs("GameTooltip", 5).calls.SetText)
    tt:Hide()
    Stub.setSpellTooltip(tt, 53, { "Backstab", "12 seconds remaining" }) -- an aura-shaped tooltip
    assert.are.equal("12 seconds remaining", fs("GameTooltip", 2):GetText())
    assert.are.equal(0, SS.count("tooltip.GameTooltip"))
    tt:Hide()
    Stub.spellDescriptions[53] = "" -- the API knows no description → no run
    Stub.setSpellTooltip(tt, 53,
      { "Backstab", "Rank 1", "Backstab the target, causing 150% weapon damage plus 15 to the target." })
    assert.are.equal(0, SS.count("tooltip.GameTooltip"))
    assert.are.equal(3, TT.spellLine({ "n", "x", "desc" }, "desc"))
    assert.is_nil(TT.spellLine({ "n", "desc" }, "other"))
    assert.is_nil(TT.spellLine({ "desc", "x" }, "desc")) -- never line 1
  end)

  it("without GetSpellDescription the positional rule stands in and /wfj debug can tell", function()
    Stub.noSpellDescriptionAPI = true
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    Stub.noSpellDescriptionAPI = false
    local ns = H.loadChunks(FILES)
    ns.Compat.init(function(name) return _G[name] end)
    ns.Settings.load(nil, 1, {})
    ns.Render.init(ns.Translator.new({
      enabled = function() return true end, areaEnabled = function() return true end,
      showsEnglish = function() return false end,
      lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      marker = function() return false end, align = ns.Align.check,
    }))
    ns.Tooltip.init()
    local _, _, api = ns.Tooltip.resolved()
    assert.is_false(api)
    Stub.setSpellTooltip(_G.GameTooltip, 53, { "Backstab", "Rank 1",
      "Backstab the target, causing 150% weapon damage plus 15 to the target." })
    assert.are.equal("ターゲットを背後から攻撃し、150 ダメージを与えます。", fs("GameTooltip", 3):GetText())
  end)

  it("a blank line inside the run belongs to it; no Equip: is left beside its translation", function()
    Stub.setItemTooltip(tt, "|Hitem:724:0:0:0:0:0:0:0|h[x]|h", { "Goretusk Liver Pie",
      "Use: Restores 243 health over 21 sec. If you spend at least 10 seconds eating you will become well fed and "
        .. "gain 4 Stamina and Spirit for 15 min.", "", "Equip: Nothing special.", "Sell Price: 5c" })
    assert.are.equal(DATA["item.description"][724].ja, fs("GameTooltip", 2):GetText())
    assert.are.equal(WFJ.Render.BLANK, fs("GameTooltip", 4):GetText())
    assert.are.equal("Sell Price: 5c", fs("GameTooltip", 5):GetText())
    assert.are.same({ 2, 4 }, { TT.itemRun({ "n", "Use: x", "", "Equip: y", "Sell" }) })
    assert.are.same({ 2, 2 }, { TT.itemRun({ "n", "Use: x", "", "Requires Level 20", "Equip: y" }) })
  end)

  it("the item's own name line is name scope for the run (Hearthstone)", function()
    Stub.setItemTooltip(tt, "|Hitem:6948:0:0:0:0:0:0:0|h[Hearthstone]|h", { "Hearthstone", "Soulbound", "Unique",
      "Use: Returns you to Shadowglen. Speak to an Innkeeper in a different place to change your home location. "
        .. "(1 Hr Cooldown)" })
    assert.are.equal(DATA["item.description"][6948].ja, fs("GameTooltip", 4):GetText())
    assert.are.equal("Hearthstone", fs("GameTooltip", 1):GetText())
    assert.are.equal(0, fs("GameTooltip", 1).calls.SetText)
  end)

  it("a $N placeholder without a value fails closed", function()
    WFJ.Settings.set("marker.missing", false) -- on by default; this test reads the text, not the marker
    Stub.setSpellTooltip(tt, 17, { "Power Word: Shield", "Rank 1", "Absorbs damage." })
    Stub.spellDescriptions[17] = "Absorbs damage."
    Stub.setSpellTooltip(tt, 17, { "Power Word: Shield", "Rank 1", "Absorbs damage." })
    assert.are.equal("Absorbs damage.", fs("GameTooltip", 3):GetText())
    assert.are.equal(0, fs("GameTooltip", 3).calls.SetText)
  end)

  it("six frames, six independent surfaces; a missing frame is unresolved, not an error", function()
    local shop = _G.ShoppingTooltip1
    Stub.setItemTooltip(tt, JERKY, JERKY_LINES)
    Stub.setItemTooltip(shop, JERKY, JERKY_LINES)
    assert.are.equal(DATA["item.description"][117].ja, fs("ShoppingTooltip1", 2):GetText())
    shop:Hide()
    assert.are.equal("Use: Restores 61 health over 18 sec. Must remain seated while eating.",
      fs("ShoppingTooltip1", 2):GetText())
    assert.are.equal(DATA["item.description"][117].ja, fs("GameTooltip", 2):GetText())
    assert.are.equal(0, SS.count("tooltip.ShoppingTooltip1"))
    assert.are.equal(1, SS.count("tooltip.GameTooltip"))
    -- a client without ItemRefShoppingTooltip2
    _G.ItemRefShoppingTooltip2 = nil
    local ns = H.loadChunks(FILES)
    ns.Compat.init(function(name) return _G[name] end)
    assert.are.equal(5, ns.Tooltip.init())
    assert.is_truthy(table.concat(ns.Compat.unresolved(), ","):find("tooltip.ItemRefShoppingTooltip2", 1, true))
  end)

  it("modifier restores every line and refits once; release on OnHide", function()
    Stub.setItemTooltip(tt, "|Hitem:724:0:0:0:0:0:0:0|h[x]|h", { "Goretusk Liver Pie",
      "Use: Restores 243 health over 21 sec. If you spend at least 10 seconds eating you will become well fed and "
        .. "gain 4 Stamina and Spirit for 15 min.", '"Tastes like liver."' })
    assert.are.equal(WFJ.Render.BLANK, fs("GameTooltip", 3):GetText())
    tt.calls.Show = 0
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.is_truthy(fs("GameTooltip", 2):GetText():find("^Use: Restores 243"))
    assert.are.equal('"Tastes like liver."', fs("GameTooltip", 3):GetText())
    assert.are.equal(2, tt.calls.Show) -- one refit (two Shows)
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal(DATA["item.description"][724].ja, fs("GameTooltip", 2):GetText())
    assert.are.equal(WFJ.Render.BLANK, fs("GameTooltip", 3):GetText())
    tt:Hide()
    assert.is_truthy(fs("GameTooltip", 2):GetText():find("^Use: Restores 243"))
    assert.are.equal('"Tastes like liver."', fs("GameTooltip", 3):GetText())
    assert.are.equal(0, SS.count("tooltip.GameTooltip"))
  end)

  it("Show() re-firing the script inside the refit does not double-apply", function()
    tt.refireOnShow = true
    Stub.setItemTooltip(tt, JERKY, JERKY_LINES)
    assert.are.equal(DATA["item.description"][117].ja, fs("GameTooltip", 2):GetText())
    assert.are.equal(1, fs("GameTooltip", 2).calls.SetText)
    assert.are.equal(2, tt.calls.Show) -- one refit (two Shows)
    assert.are.equal(1, SS.count("tooltip.GameTooltip"))
  end)

  it("a new hover on the same frame forgets the previous run (no stale companion)", function()
    Stub.setItemTooltip(tt, "|Hitem:724:0:0:0:0:0:0:0|h[x]|h", { "Goretusk Liver Pie",
      "Use: Restores 243 health over 21 sec. If you spend at least 10 seconds eating you will become well fed and "
        .. "gain 4 Stamina and Spirit for 15 min.", '"Tastes like liver."' })
    assert.are.equal(WFJ.Render.BLANK, fs("GameTooltip", 3):GetText())
    Stub.setItemTooltip(tt, JERKY, JERKY_LINES) -- line 3 is now "Sell Price: 5c", written by the client
    assert.are.equal("Sell Price: 5c", fs("GameTooltip", 3):GetText())
    assert.are.equal(1, SS.count("tooltip.GameTooltip"))
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Sell Price: 5c", fs("GameTooltip", 3):GetText())
  end)

  it("itemRun and spellLine are pure helpers", function()
    assert.are.same({ 3, 4 }, { TT.itemRun({ "n", "Binds", "Use: x", '"q"', "Sell" }) })
    assert.is_nil(TT.itemRun({ "n", "Binds", "Sell" }))
    assert.is_nil(TT.itemRun({ "Use: on line one is the name" }))
    assert.are.equal(3, TT.spellLine({ "n", "Rank 1", "desc" }))
    assert.are.equal(3, TT.spellLine({ "n", "Rank 1", "desc", "Next rank:", "desc2" }))
    assert.are.equal(3, TT.spellLine({ "n", "Rank 1", "desc", "", "Click to learn" }))
    assert.is_nil(TT.spellLine({ "n" }))
    assert.is_nil(TT.spellLine({ "n", "Next rank:", "x" }))
    assert.are.equal(2, TT.spellLine({ "n", "desc", "Spell ID: 1" }, "desc"))
  end)

  describe("feeds the Collector", function()
    it("records an item's description run, paragraph by line, before translating it", function()
      local db = WFJ.Collector.load(nil, H.collectorDeps())
      Stub.setItemTooltip(tt, "|Hitem:724:0:0:0:0:0:0:0|h[Goldenbark Apple]|h",
        { "Goldenbark Apple", "Use: Restores 243 health over 21 sec.", "",
          "Equip: Well Fed.", "\"Crisp.\"", "Sell Price: 1s" })
      assert.are.equal("Use: Restores 243 health over 21 sec.$B$BEquip: Well Fed.$B$B\"Crisp.\"",
        db.entries["item:724:description"].e)
      tt:Hide()
      Stub.setItemTooltip(tt, JERKY, { "Tough Jerky", "Sell Price: 5c" }) -- no run → nothing
      assert.is_nil(db.entries["item:117:description"])
    end)

    it("records a spell's GetSpellDescription string only", function()
      local db = WFJ.Collector.load(nil, H.collectorDeps())
      Stub.setSpellTooltip(tt, 17, { "Power Word: Shield", "Rank 1", Stub.spellDescriptions[17] })
      assert.are.equal(Stub.spellDescriptions[17], db.entries["spell:17:description"].e)
      tt:Hide()
      Stub.spellDescriptions[53] = ""
      Stub.setSpellTooltip(tt, 53, { "Backstab", "Rank 1", "Backstab the target." })
      assert.is_nil(db.entries["spell:53:description"])
    end)

    it("records nothing for a spell when the client has no GetSpellDescription", function()
      Stub.noSpellDescriptionAPI = true
      Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
      Stub.installTooltipAPI()
      Stub.noSpellDescriptionAPI = false
      local ns = H.loadChunks(FILES)
      ns.Compat.init(function(name) return _G[name] end)
      ns.Settings.load(nil, 1, {})
      ns.Render.init(ns.Translator.new({
        enabled = function() return true end, areaEnabled = function() return true end,
        showsEnglish = function() return false end, lookup = function() return nil end,
        marker = function() return false end, align = ns.Align.check,
      }))
      ns.Tooltip.init()
      local db = ns.Collector.load(nil, H.collectorDeps())
      Stub.setSpellTooltip(_G.GameTooltip, 53, { "Backstab", "Rank 1", "Backstab the target." })
      assert.is_nil(next(db.entries))
    end)
  end)
end)
