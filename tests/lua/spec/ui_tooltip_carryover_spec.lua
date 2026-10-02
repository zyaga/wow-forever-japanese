-- Item tooltip cases the ui area handles: bag-type words, durations inside
-- cooldown lines, enchantment stat lines, and "Equip:" stat lines inside a description run nothing was written on.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  CONTAINER_SLOTS = { "%d Slot %s", "%dスロットの%s" },
  ["ItemSubClass:1:1"] = { "Soul Bag", "ソウルバッグ" },
  ITEM_COOLDOWN_TOTAL = { "(%s Cooldown)", "(クールダウン %s)" },
  INT_SPELL_DURATION_SEC = { "%d sec", "%d秒" },
  ["SpellItemEnchantment:900"] = { "+3 Fire Spell Damage", "炎呪文ダメージ +3" },
  DAMAGE_TEMPLATE_WITH_SCHOOL = { "%s - %s %s Damage", "%s - %s %sダメージ" },
  ITEM_SPELL_TRIGGER_ONEQUIP = { "Equip:", "装備時:" },
  ITEM_MOD_SPELL_POWER = { "Increases spell power by %s.", "呪文パワーが%s上昇。" },
  ITEM_MOD_HIT_RATING = { "Improves your chance to hit by %s%%.", "命中率が%s%%上昇。" },
}
local RUN_JA = "【装備】翻訳済みの説明。"

describe("item tooltip carry-overs", function()
  local WFJ, tt

  local function left(i) return _G["GameTooltipTextLeft" .. i] end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    local files = {}
    for i, f in ipairs(H.UI_FILES) do files[i] = f end
    files[#files + 1] = "UI/TimeLine.lua"
    files[#files + 1] = "UI/Tooltip.lua"
    WFJ = H.loadChunks(files)
    local rows = H.uiSetup(WFJ, UI)
    WFJ.Render.init(WFJ.Translator.new({ -- as uiSetup, plus one translated item for the applied-run case
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id)
        if kind == "ui" then local r = rows[id]; return r and { ja = r[1], status = r[3] } end
        if kind == "item.description" and id == 7000 then return { ja = RUN_JA, status = "." } end
        return nil
      end,
      marker = function(n) return WFJ.Settings.get("marker." .. n) end,
      align = function() return true end,
      fill = function(ja, args) return WFJ.UIIndex:fill(ja, args) end,
    }))
    -- the addon's translation lookup (Core/Lookup): item 7000 has a translation, every other item none
    WFJ.Lookup = { get = function(kind, id)
      if kind == "item.description" and id == 7000 then return { ja = RUN_JA, status = "." } end
      return nil
    end }
    WFJ.Tooltip.init()
    tt = _G.GameTooltip
  end)

  after_each(H.uiTeardown)

  it("a bag's slot line shows the bag type in Japanese; an unknown type stays as shown", function()
    Stub.setItemTooltip(tt, "|Hitem:21340:0:0:0|h[Soul Pouch]|h", { "Soul Pouch", "16 Slot Soul Bag" })
    assert.are.equal("16スロットのソウルバッグ", left(2):GetText())
    Stub.setItemTooltip(tt, "|Hitem:9999:0:0:0|h[Odd Bag]|h", { "Odd Bag", "12 Slot Mystery Sack" })
    assert.are.equal("12スロットのMystery Sack", left(2):GetText())
  end)

  it("a cooldown line's duration is Japanese", function()
    Stub.setItemTooltip(tt, "|Hitem:6948:0:0:0|h[Hearthstone]|h", { "Hearthstone", "(30 sec Cooldown)" })
    assert.are.equal("(クールダウン 30秒)", left(2):GetText())
  end)

  it("an enchantment stat line matches by fingerprint and never becomes a weapon-damage line", function()
    Stub.setItemTooltip(tt, "|Hitem:15000:0:0:0|h[Robe of the Sorcerer]|h",
      { "Robe of the Sorcerer", "+3 Fire Spell Damage" })
    assert.are.equal("炎呪文ダメージ +3", left(2):GetText())
    assert.are.equal(WFJ.Font.PATH, (left(2):GetFont()))
  end)

  it("Equip: template lines of an untranslated run translate one by one; other run lines stay", function()
    Stub.setItemTooltip(tt, "|Hitem:8000:0:0:0|h[Plain Ring]|h", { "Plain Ring", "Finger",
      "Equip: Increases spell power by 12.", "Equip: Improves your chance to hit by 1%.", "Use: Restores 500 health." })
    assert.are.equal("装備時: 呪文パワーが12上昇。", left(3):GetText())
    assert.are.equal("装備時: 命中率が1%上昇。", left(4):GetText())
    assert.are.equal("Use: Restores 500 health.", left(5):GetText())
    assert.are.equal(0, left(5).calls.SetText)
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Equip: Increases spell power by 12.", left(3):GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("装備時: 呪文パワーが12上昇。", left(3):GetText())
  end)

  it("an untranslated item hovered with the modifier held gets its Equip lines on release, never the marker",
    function()
    assert.is_true(WFJ.Settings.get("marker.missing")) -- the default
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    Stub.setItemTooltip(tt, "|Hitem:8000:0:0:0|h[Plain Ring]|h", { "Plain Ring", "Finger",
      "Equip: Increases spell power by 12.", "Use: Restores 500 health." })
    assert.are.equal("Equip: Increases spell power by 12.", left(3):GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("装備時: 呪文パワーが12上昇。", left(3):GetText())
    assert.are.equal("Use: Restores 500 health.", left(4):GetText())
  end)

  it("a translated item hovered with the modifier held keeps its description run on release", function()
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    Stub.setItemTooltip(tt, "|Hitem:7000:0:0:0|h[Fine Ring]|h", { "Fine Ring", "Finger",
      "Equip: Increases spell power by 12.", "Equip: Improves your chance to hit by 1%." })
    assert.are.equal("Equip: Increases spell power by 12.", left(3):GetText())
    assert.is_nil(WFJ.SurfaceState.get("tooltip.GameTooltip", "ui.L3"))
    assert.is_nil(WFJ.SurfaceState.get("tooltip.GameTooltip", "ui.L4"))
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal(RUN_JA, left(3):GetText())
    assert.are.equal(" ", left(4):GetText()) -- the run's companion line, blank while the primary applies
  end)

  it("a description run that applies gets no ui record on any run line", function()
    Stub.setItemTooltip(tt, "|Hitem:7000:0:0:0|h[Fine Ring]|h", { "Fine Ring", "Finger",
      "Equip: Increases spell power by 12." })
    assert.are.equal(RUN_JA, left(3):GetText())
    assert.is_nil(WFJ.SurfaceState.get("tooltip.GameTooltip", "ui.L3"))
  end)
end)
