-- An item's run holds more trigger lines than its one description covers. Each line is whose it is: a stat line the
-- client writes from its own strings shows the dictionary's Japanese, the description takes only the lines its
-- Japanese fits (the missing marker only there), and a line printing another spell shows that spell's Japanese,
-- found by the line's shape (Data/SpellShapes.lua). The three items are replayed as the window test read them in
-- game (their rows as the client wrote them), over the shipped Japanese of their rows.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

-- the shipped interface strings these tooltips need, English as the client has it and the shipped Japanese
local UI = {
  TOOLTIP_ITEM_STAT_MANA_REGEN_INCREASE = { "Equip: Restores %1$d Mana per 5 sec.", "装備時: 5秒ごとにマナを%1$d回復。" },
  TOOLTIP_ITEM_STAT_HEALTH_REGEN_INCREASE = { "Equip: Restores %1$d Health per 5 sec.",
    "装備時: 5秒ごとに体力を%1$d回復。" },
  TOOLTIP_ITEM_STAT_SPELL_POWER_INCREASE = {
    "Equip: Increases damage and healing done by magical spells and effects by up to %1$d.",
    "装備時: 呪文と効果によるダメージと回復量が最大%1$d増加。" },
  ITEM_SPELL_TRIGGER_ONEQUIP = { "Equip:", "装備時:" },
  ITEM_COOLDOWN_TOTAL = { "(%s Cooldown)", "(クールダウン %s)" },
  INT_SPELL_DURATION_SEC = { "%d sec", "%d秒" },
}

-- the shipped rows (Data/Item, Data/Spell): Japanese, h1, status, how many values the English prints
local ITEMS = {
  [1155] = { ja = "自分に対するSleep効果の命中率を$N1%低下させます。", h1 = 0x7614236e, status = "u", values = 1 },
  [6461] = { ja = "$D1ごとに体力を$N1回復します。", h1 = 0xe2d95cbb, status = "u", values = 2 },
  [273643] = { ja = "対象のWorgenを$D1スタンさせます。", h1 = 0x308da161, status = "u", values = 1 },
}
local SPELLS = {
  [7675] = { ja = "呪文と効果による回復量が最大$N1増加します。", h1 = 0x28fa3697, status = "u", values = 1 },
}
-- the shape of "Increases healing done by spells and effects by up to $s1." (spell_shapes.shape_key), and the spell
-- the shipped table gives it
local HEALING_SHAPE = "faa971e7fb8bfbb9"
local SHAPES = { [HEALING_SHAPE] = 7675 }

local MARKER = "未翻訳"

-- the rows of the window test's tooltip read, as the client wrote them
local SLIME = { "Slime-encrusted Pads", "Binds when picked up", "Shoulder", "32 Armor",
  "Equip: Restores 3 Mana per 5 sec.", "Equip: Restores 10 Health per 5 sec.", "Requires Level 20" }
local WORGENBANE = { "Worgenbane Talisman", "Binds when picked up", "Unique-Equipped", "Trinket",
  "Equip: Restores 2 Mana per 5 sec.", "Use: Stuns target Worgen for 4 sec. (5 |4Min:Min; Cooldown)",
  "Requires Level 21" }
local ROD = { "Rod of the Sleepwalker", "Binds when picked up", "Two-Hand", "39 - 60 Damage",
  "(17.7 damage per second)", "+11 Spirit",
  "Equip: Increases damage and healing done by magical spells and effects by up to 32.",
  "Equip: Reduces the hit chance of Sleep effects against you by 5%.", "Requires Level 24" }

describe("UI/Tooltip: an item's lines its description does not cover", function()
  local WFJ, tt

  local function left(i) return _G["GameTooltipTextLeft" .. i] end
  local function link(id, name) return ("|Hitem:%d:0:0:0|h[%s]|h"):format(id, name) end
  local function noMarker(rows)
    for i = 1, #rows do assert.is_nil(left(i):GetText():find(MARKER, 1, true), "row " .. i) end
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    local files = {}
    for i, f in ipairs(H.UI_FILES) do files[i] = f end
    files[#files + 1] = "UI/TimeLine.lua"
    files[#files + 1] = "UI/Tooltip.lua"
    WFJ = H.loadChunks(files)
    local rows = H.uiSetup(WFJ, UI)
    local function lookup(kind, id)
      if kind == "item.description" then return ITEMS[id] end
      if kind == "spell.description" then return SPELLS[id] end
      return nil
    end
    -- the spell durations the gate copies, as Main hands them to Align
    local duration = { render = function(text) return WFJ.UIIndex:duration(text, true) end, words = {} }
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      showsEnglish = WFJ.Modifier.english,
      lookup = function(kind, id)
        if kind == "ui" then local r = rows[id]; return r and { ja = r[1], status = r[3] } end
        return lookup(kind, id)
      end,
      marker = function(n) return WFJ.Settings.get("marker." .. n) end,
      align = function(ja, lines, nameScope, count) return WFJ.Align.check(ja, lines, nameScope, duration, count) end,
      fill = function(ja, args) return WFJ.UIIndex:fill(ja, args) end,
      fillValues = function(ja, live, count) return WFJ.Align.fillValues(ja, live, duration, count) end,
    }))
    WFJ.Lookup = { get = lookup }
    WFJ.GateText = function(entry, lines) return WFJ.Align.gate(entry, lines, duration) end
    WFJ.Data.spellShapes = SHAPES
    WFJ.State.names = false
    WFJ.Tooltip.init()
    tt = _G.GameTooltip
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
  end)

  it("Slime-encrusted Pads: both regeneration lines are the client's stat lines, neither marked", function()
    Stub.setItemTooltip(tt, link(6461, "Slime-encrusted Pads"), SLIME)
    assert.are.equal("装備時: 5秒ごとにマナを3回復。", left(5):GetText())
    assert.are.equal("装備時: 5秒ごとに体力を10回復。", left(6):GetText())
    noMarker(SLIME)
    -- its description ("Restores $s1 health every $t1 sec.") is printed by no line, so it owns none
    assert.is_nil(WFJ.SurfaceState.get("tooltip.GameTooltip", "desc"))
  end)

  it("Worgenbane Talisman: the mana line is a stat line; the description is the use line, its cooldown peeled",
    function()
    Stub.setItemTooltip(tt, link(273643, "Worgenbane Talisman"), WORGENBANE)
    assert.are.equal("装備時: 5秒ごとにマナを2回復。", left(5):GetText())
    assert.are.equal("対象のWorgenを4秒スタンさせます。", left(6):GetText())
    noMarker(WORGENBANE)
  end)

  it("Rod of the Sleepwalker: the spell power line is a stat line; the Sleep line is the description", function()
    Stub.setItemTooltip(tt, link(1155, "Rod of the Sleepwalker"), ROD)
    assert.are.equal("装備時: 呪文と効果によるダメージと回復量が最大32増加。", left(7):GetText())
    assert.are.equal("自分に対するSleep効果の命中率を5%低下させます。", left(8):GetText())
    noMarker(ROD)
  end)

  it("the reveal key shows every line's English, and release brings the Japanese back", function()
    Stub.setItemTooltip(tt, link(1155, "Rod of the Sleepwalker"), ROD)
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    for i = 1, #ROD do assert.are.equal(ROD[i], left(i):GetText()) end
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("自分に対するSleep効果の命中率を5%低下させます。", left(8):GetText())
  end)

  it("with the translation off nothing is written", function()
    WFJ.State.setEnabled(false)
    Stub.setItemTooltip(tt, link(6461, "Slime-encrusted Pads"), SLIME)
    for i = 1, #SLIME do
      assert.are.equal(SLIME[i], left(i):GetText())
      assert.are.equal(0, left(i).calls.SetText)
    end
  end)

  describe("a line that prints another spell", function()
    -- the Rod with a line its description does not cover (a constructed row): the spell its shape names
    local HEALING = "Equip: Increases healing done by spells and effects by up to 22."
    local ROD_MORE = { "Rod of the Sleepwalker", "Two-Hand",
      "Equip: Reduces the hit chance of Sleep effects against you by 5%.", HEALING, "Requires Level 24" }

    it("the line's shape key is the one the pipeline wrote for the spell's English", function()
      local duration = function(text) return WFJ.UIIndex:duration(text, true) end
      assert.are.equal(HEALING_SHAPE,
        WFJ.Align.variantKey("Increases healing done by spells and effects by up to 22.", duration))
    end)

    it("shows that spell's Japanese, filled from its own line; the description keeps its own line", function()
      Stub.setItemTooltip(tt, link(1155, "Rod of the Sleepwalker"), ROD_MORE)
      assert.are.equal("自分に対するSleep効果の命中率を5%低下させます。", left(3):GetText())
      assert.are.equal("呪文と効果による回復量が最大22増加します。", left(4):GetText())
      noMarker(ROD_MORE)
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal(HEALING, left(4):GetText())
    end)

    it("a shape no shipped spell answers, or whose Japanese the line does not fit, stays as written, unmarked",
      function()
      WFJ.Data.spellShapes = {}
      Stub.setItemTooltip(tt, link(1155, "Rod of the Sleepwalker"), ROD_MORE)
      assert.are.equal(HEALING, left(4):GetText())
      assert.are.equal(0, left(4).calls.SetText)
      WFJ.Data.spellShapes = SHAPES
      SPELLS[7675].values = 2 -- the line prints one value: the gate refuses it
      Stub.setItemTooltip(tt, link(1155, "Rod of the Sleepwalker"), ROD_MORE)
      SPELLS[7675].values = 1
      assert.are.equal(HEALING, left(4):GetText())
      noMarker(ROD_MORE)
      assert.are.equal("自分に対するSleep効果の命中率を5%低下させます。", left(3):GetText())
    end)
  end)

  it("a description that fits no line keeps the marker on the one line nothing else explains", function()
    -- the talisman's use line with its number gone: the description cannot fit it, and no spell is found
    local rows = { "Worgenbane Talisman", "Trinket", "Equip: Restores 2 Mana per 5 sec.", "Use: Stuns target Worgen." }
    Stub.setItemTooltip(tt, link(273643, "Worgenbane Talisman"), rows)
    assert.are.equal("装備時: 5秒ごとにマナを2回復。", left(3):GetText())
    assert.is_truthy(left(4):GetText():find(MARKER, 1, true))
    assert.is_nil(left(3):GetText():find(MARKER, 1, true))
  end)
end)
