-- ADR-038: UI/Tooltip additions. A comparison tooltip's lines appended after its item post-call (the delta
-- header and the cycling hint, blizzard_sharedxmlgame/tooltip/tooltipcomparisonmanager.lua:250–316) render Japanese,
-- key-only, the key binding kept; an item spell line's max-usable-level trailer (ITEM_SPELL_MAX_USABLE_LEVEL) is peeled
-- off the run: a trusted translation gets the trailer's Japanese appended, a gated one keeps its English. Every
-- other tooltip spec runs against the same module unchanged.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  ITEM_DELTA_DESCRIPTION = { "If you replace this item, the following stat changes will occur:",
    "このアイテムを置き換えると、次の能力値の変化が起こります:" },
  ITEM_COMPARISON_SWAP_ITEM_MAINHAND_DESCRIPTION = { "Press %s to cycle through your main-hand items.",
    "%sでメインハンドのアイテムを切り替えます。" },
  ITEM_SPELL_MAX_USABLE_LEVEL = { " (Requires level %d or below)", "(レベル%d以下が必要)" },
  ITEM_COOLDOWN_TOTAL_SEC = { "(%d Sec Cooldown)", "(クールダウン %d秒)" },
  INVTYPE_WEAPONMAINHAND = { "Main Hand", "メインハンド" },
  ARMOR_TEMPLATE = { "%s Armor", "アーマー %s" },
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = { "damage per second", "秒間ダメージ" },
  EQUIPPED = { "Equipped", "装備中" },
  ["SpellItemEnchantment:387"] = { "+17 Armor", "アーマー +17" }, -- an enchantment's whole text
}
local DATA = {
  [1001] = { ja = "体力を50回復する。", status = "." }, -- trusted, ungated
  [1002] = { ja = "体力を$N1回復する。", status = "u" }, -- gated
  -- gated, a branch line: with the extra clause or without it (ADR-043)
  [1003] = { variants = { "体力を$N1回復し、さらに精神が$N2上がる。", "体力を$N1回復する。" }, shapes = { "2/0", "1/0" },
    status = "u" },
}
local POTION_LINES = function(id)
  return "|Hitem:" .. id .. ":0:0:0|h[Minor Potion]|h", { "Minor Potion",
    "Use: Restores 50 health. (Requires level 60 or below)", "Sell Price: 5c" }
end

describe("UI/Tooltip comparison lines and the max-usable-level trailer", function()
  local WFJ

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    local files = {}
    for i, f in ipairs(H.UI_FILES) do files[i] = f end
    files[#files + 1] = "UI/TimeLine.lua"
    files[#files + 1] = "UI/Tooltip.lua"
    WFJ = H.loadChunks(files)
    H.uiSetup(WFJ, UI, { lookup = function(kind, id)
      if kind == "item.description" then return DATA[id] end
    end })
    WFJ.Lookup = { get = function(kind, id) return kind == "item.description" and DATA[id] or nil end }
    local translator = WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      showsEnglish = WFJ.Modifier.english,
      lookup = function(kind, id)
        if kind == "item.description" then return DATA[id] end
        if kind == "ui" and WFJ.UIIndex.rows[id] then return { ja = WFJ.UIIndex.rows[id][1], status = "." } end
      end,
      marker = function(n) return WFJ.Settings.get("marker." .. n) end,
      align = WFJ.Align.check,
      alignVariants = WFJ.Align.checkVariants,
      fill = function(ja, args) return WFJ.UIIndex:fill(ja, args) end,
    })
    WFJ.Render.init(translator)
    -- a C method on the client that never calls the Lua Show; here it only records the state
    _G.ShoppingTooltip1.SetShown = function(self, shown) self.wfjShown = shown end
    WFJ.Tooltip.init()
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
  end)

  it("a comparison tooltip's delta header and cycling hint are Japanese, the key kept; Alt shows English", function()
    local tt = _G.ShoppingTooltip1
    Stub.setItemTooltip(tt, "|Hitem:2:0:0:0|h[Axe]|h", { "Currently Equipped", "Axe", "Main Hand" })
    assert.are.equal("メインハンド", _G.ShoppingTooltip1TextLeft3:GetText()) -- the structural line (unchanged path)
    tt:AddLine(" ")
    tt:AddLine(_G.ITEM_DELTA_DESCRIPTION)
    tt:AddLine("+5 Stamina") -- a delta line: not one of the keys, left alone
    tt:AddLine(_G.ITEM_COMPARISON_SWAP_ITEM_MAINHAND_DESCRIPTION:format("SHIFT-C"))
    tt:Show()
    assert.are.equal("このアイテムを置き換えると、次の能力値の変化が起こります:", _G.ShoppingTooltip1TextLeft5:GetText())
    assert.are.equal("+5 Stamina", _G.ShoppingTooltip1TextLeft6:GetText())
    assert.are.equal("SHIFT-Cでメインハンドのアイテムを切り替えます。", _G.ShoppingTooltip1TextLeft7:GetText())
    assert.are.equal("メインハンド", _G.ShoppingTooltip1TextLeft3:GetText()) -- its record kept
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal(_G.ITEM_DELTA_DESCRIPTION, _G.ShoppingTooltip1TextLeft5:GetText())
  end)

  it("Forever shows the frame with SetShown: the delta header and a stat change after it are Japanese", function()
    local tt = _G.ShoppingTooltip1
    Stub.setItemTooltip(tt, "|Hitem:2:0:0:0|h[Boots]|h", { "Ragged Leather Boots", "16 Armor" })
    tt:AddLine(" ")
    tt:AddLine(_G.ITEM_DELTA_DESCRIPTION)
    tt:AddLine("-11 Armor")
    tt:AddLine("|cffff2020-3|r Armor") -- the client colours the number on its own
    tt:AddLine("|cff20ff20+17|r Armor") -- a gain, green; its bare text is the enchantment's whole string
    tt:SetShown(true)
    assert.are.equal("このアイテムを置き換えると、次の能力値の変化が起こります:", _G.ShoppingTooltip1TextLeft4:GetText())
    assert.are.equal("アーマー -11", _G.ShoppingTooltip1TextLeft5:GetText())
    assert.are.equal("アーマー |cffff2020-3|r", _G.ShoppingTooltip1TextLeft6:GetText())
    assert.are.equal("アーマー |cff20ff20+17|r", _G.ShoppingTooltip1TextLeft7:GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("-11 Armor", _G.ShoppingTooltip1TextLeft5:GetText())
    assert.are.equal("|cffff2020-3|r Armor", _G.ShoppingTooltip1TextLeft6:GetText())
    assert.are.equal("|cff20ff20+17|r Armor", _G.ShoppingTooltip1TextLeft7:GetText())
  end)

  describe("a comparison rebuilt by the client", function()
    -- the client rebuilds a comparison tooltip a few times per refresh: every line again in English, then SetShown
    local GREEN, RED = "|cff20ff20", "|cffff2020"
    local LINK = "|Hitem:2:0:0:0|h[Axe]|h"
    local function lines(over)
      local l = { "Currently Equipped", "Axe", { "Main Hand", "Two-Hand" }, " ", _G.ITEM_DELTA_DESCRIPTION,
        GREEN .. "+7.5|r damage per second", RED .. "-311|r Armor", "-3 damage per second" }
      for i, v in pairs(over or {}) do l[i] = v end
      return l
    end
    local full, tt
    -- as the client does it (tooltipcomparisonmanager.lua SetItemTooltip): ProcessInfo writes the item's lines and runs
    -- the post-call, then the delta header and the stat changes are added, then the frame is shown
    -- shown twice per rebuild, as measured in game (8 lines, then 14): once with the item's lines, once with all
    local function build(l, link)
      local item = {}
      for i = 1, 3 do item[i] = l[i] end
      Stub.setItemTooltip(tt, link or LINK, item)
      tt:SetShown(true)
      for i = 4, #l do tt:AddLine(type(l[i]) == "table" and l[i][1] or l[i]) end
      tt:SetShown(true)
    end
    local function rebuild(over, link)
      local l = lines(over)
      local packed = {}
      for i = 1, 9 do if l[i] then packed[#packed + 1] = l[i] end end
      build(packed, link)
    end
    local function left(i) return _G["ShoppingTooltip1TextLeft" .. i]:GetText() end
    before_each(function()
      tt = _G.ShoppingTooltip1
      full = 0
      local itemRun = WFJ.Tooltip.itemRun
      WFJ.Tooltip.itemRun = function(...) full = full + 1; return itemRun(...) end
    end)

    it("the same lines again: no full pass, and every line is Japanese again, its colours kept", function()
      rebuild()
      rebuild()
      rebuild()
      assert.are.equal(1, full)
      assert.are.equal("メインハンド", left(3))
      assert.are.equal("このアイテムを置き換えると、次の能力値の変化が起こります:", left(5))
      assert.are.equal("秒間ダメージ " .. GREEN .. "+7.5|r", left(6))
      assert.are.equal("アーマー " .. RED .. "-311|r", left(7))
      assert.are.equal("秒間ダメージ -3", left(8))
    end)

    -- each change: a full pass, and the new value shown
    -- { what changed, the lines changed, the row to read, what it must show, full item passes after the change }:
    -- a stat line is the comparison pass's own, so only a change in the item's lines takes a second full item pass
    local CHANGES = {
      { "a stat change's sign flips", { [8] = "+3 damage per second" }, 8, "秒間ダメージ +3", 1 },
      { "a stat change's number", { [6] = GREEN .. "+8.0|r damage per second" }, 6, "秒間ダメージ " .. GREEN .. "+8.0|r",
        1 },
      { "a stat change's colour (a gain turned loss)", { [6] = RED .. "+7.5|r damage per second" }, 6,
        "秒間ダメージ " .. RED .. "+7.5|r", 1 },
      { "a plain stat change gains a colour", { [8] = RED .. "-3|r damage per second" }, 8,
        "秒間ダメージ " .. RED .. "-3|r", 1 },
      { "the right-hand text", { [3] = { "Main Hand", "One-Hand" } }, 3, "メインハンド", 2 },
      { "a stat change removed", { [8] = false }, 7, "アーマー " .. RED .. "-311|r", 1 },
    }
    for _, c in ipairs(CHANGES) do
      it(c[1] .. ": the new value shown", function()
        rebuild()
        local over = {}
        for k, v in pairs(c[2]) do over[k] = v end
        if over[8] == false then
          local l = lines()
          l[8] = nil
          build(l)
        else
          rebuild(over)
        end
        assert.are.equal(c[5], full)
        assert.are.equal(c[4], left(c[3]))
      end)
    end

    it("a line's own colour changed with the same text: a full pass", function()
      rebuild()
      local l = lines()
      l[2] = { "Axe", color = { 0, 1, 0 } }
      build(l)
      assert.are.equal(2, full)
    end)

    it("each of the two shows per rebuild keeps its own state, so neither undoes the other", function()
      local compareFull = 0
      local onCompare = WFJ.Tooltip.matchStatChange
      WFJ.Tooltip.matchStatChange = function(...) compareFull = compareFull + 1; return onCompare(...) end
      rebuild()
      local first = compareFull
      for _ = 1, 4 do rebuild() end
      assert.are.equal(first, compareFull) -- no stat line matched again on the four identical rebuilds
      assert.are.equal("秒間ダメージ -3", left(8))
      WFJ.Tooltip.matchStatChange = onCompare
    end)

    it("a line added: the added stat change Japanese", function()
      rebuild()
      local l = lines()
      l[9] = "+2 damage per second"
      build(l)
      assert.are.equal(1, full) -- the item's own lines are the same: only the comparison pass sees the new line
      assert.are.equal("秒間ダメージ +2", left(9))
    end)

    it("another item with the same lines: a full pass", function()
      rebuild()
      rebuild(nil, "|Hitem:3:0:0:0|h[Axe]|h")
      assert.are.equal(2, full)
    end)

    it("the reveal key held through a rebuild shows the English; let go, the Japanese", function()
      rebuild()
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      rebuild()
      assert.are.equal(GREEN .. "+7.5|r damage per second", left(6))
      assert.are.equal("Main Hand", left(3))
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("秒間ダメージ " .. GREEN .. "+7.5|r", left(6))
      assert.are.equal("メインハンド", left(3))
    end)

    -- the "Equipped" tab: SetItemTooltip writes it before ProcessInfo (tooltipcomparisonmanager.lua:241-247)
    local function withHeader(over)
      if not tt.CompareHeader then tt.CompareHeader = { Label = Stub.fontString("") } end
      tt.CompareHeader.Label:SetText("Equipped")
      rebuild(over)
    end

    it("the Equipped tab stays Japanese when a full item pass runs on lines whose left side did not change",
      function()
        withHeader()
        withHeader()
        assert.are.equal("装備中", tt.CompareHeader.Label:GetText())
        withHeader({ [3] = { "Main Hand", "One-Hand" } }) -- only the right-hand text: a full item pass
        assert.are.equal(2, full)
        assert.are.equal("装備中", tt.CompareHeader.Label:GetText())
      end)

    it("the Equipped tab stays Japanese on a comparison with no stat changes", function()
      tt.CompareHeader = { Label = Stub.fontString("") }
      local function plain(right)
        tt.CompareHeader.Label:SetText("Equipped")
        Stub.setItemTooltip(tt, LINK, { "Currently Equipped", "Axe", { "Main Hand", right } })
        tt:SetShown(true)
        tt:SetShown(true)
      end
      plain("Two-Hand")
      plain("Two-Hand")
      plain("One-Hand")
      assert.are.equal(2, full)
      assert.are.equal("装備中", tt.CompareHeader.Label:GetText())
    end)

    it("a show with the reveal key down before its refresh reaches this tooltip: English, in the client's face",
      function()
        rebuild()
        Stub.keys.alt = true -- down; the modifier refresh has not walked this tooltip yet
        tt:SetShown(true) -- the main tooltip's redraw in that refresh shows the comparison again
        WFJ.Modifier.refresh()
        assert.are.equal(GREEN .. "+7.5|r damage per second", left(6))
        assert.are_not.equal(WFJ.Font.PATH, (_G.ShoppingTooltip1TextLeft6:GetFont()))
      end)

    it("an item, then a spell on the same tooltip without a hide, then the item again: Japanese again", function()
      local ref = _G.ItemRefTooltip -- a chat link reuses it without hiding (itemref.lua:20-25)
      Stub.setItemTooltip(ref, LINK, { "Axe", "Main Hand" })
      assert.are.equal("メインハンド", _G.ItemRefTooltipTextLeft2:GetText())
      Stub.setSpellTooltip(ref, 133, { "Fireball", "Hurls a fiery ball." })
      Stub.setItemTooltip(ref, LINK, { "Axe", "Main Hand" })
      assert.are.equal("メインハンド", _G.ItemRefTooltipTextLeft2:GetText())
    end)

    it("hidden in between: the next show is a full pass", function()
      rebuild()
      tt.scripts.OnHide(tt)
      rebuild()
      assert.are.equal(2, full)
      assert.are.equal("秒間ダメージ " .. GREEN .. "+7.5|r", left(6))
    end)
  end)

  it("a stat change with only a short stat name shows the Japanese name, the number as the client wrote it",
  function()
    local tt = _G.ShoppingTooltip1
    Stub.setItemTooltip(tt, "|Hitem:2:0:0:0|h[Staff]|h", { "Handcrafted Staff", "(1.4 damage per second)" })
    tt:AddLine(" ")
    tt:AddLine(_G.ITEM_DELTA_DESCRIPTION)
    tt:AddLine("|cff20ff20+0.7|r damage per second") -- seen in game: the number green, the name white
    tt:AddLine("-2 damage per second")
    tt:AddLine("+3 Unknown Stat") -- a name the dictionary does not hold stays as written
    tt:SetShown(true)
    assert.are.equal("秒間ダメージ |cff20ff20+0.7|r", _G.ShoppingTooltip1TextLeft5:GetText())
    assert.are.equal("秒間ダメージ -2", _G.ShoppingTooltip1TextLeft6:GetText())
    assert.are.equal("+3 Unknown Stat", _G.ShoppingTooltip1TextLeft7:GetText())
    assert.are.equal("(1.4 damage per second)", _G.ShoppingTooltip1TextLeft2:GetText()) -- before the header: not ours
    assert.is_nil(WFJ.UIIndex:match("damage per second")) -- a stat name is asked for by key only (names collide)
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("|cff20ff20+0.7|r damage per second", _G.ShoppingTooltip1TextLeft5:GetText())
  end)

  it("a trusted item translation gets the max-usable-level trailer in Japanese; the Collector sees no trailer",
    function()
      local recorded
      WFJ.Collector.record = function(_, _, _, text) recorded = text end
      Stub.setItemTooltip(_G.GameTooltip, POTION_LINES(1001))
      assert.are.equal("体力を50回復する。(レベル60以下が必要)", _G.GameTooltipTextLeft2:GetText())
      assert.are.equal("Use: Restores 50 health.", recorded)
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("Use: Restores 50 health. (Requires level 60 or below)", _G.GameTooltipTextLeft2:GetText())
    end)

  it("the client's cooldown tail is set aside like the trailer: trusted gets it in Japanese, the Collector none",
    function()
      local recorded
      WFJ.Collector.record = function(_, _, _, text) recorded = text end
      Stub.setItemTooltip(_G.GameTooltip, "|Hitem:1001:0:0:0|h[Minor Potion]|h", { "Minor Potion",
        "Use: Restores 50 health. (1 Sec Cooldown)", "Sell Price: 5c" })
      assert.are.equal("体力を50回復する。(クールダウン 1秒)", _G.GameTooltipTextLeft2:GetText())
      assert.are.equal("Use: Restores 50 health.", recorded)
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("Use: Restores 50 health. (1 Sec Cooldown)", _G.GameTooltipTextLeft2:GetText())
    end)

  it("clientTail splits a line from the tail the client adds, and from nothing else", function()
    local head, key = WFJ.UIIndex:clientTail("Use: Restores 50 health. (1 Sec Cooldown)")
    assert.are.same({ "Use: Restores 50 health.", "ITEM_COOLDOWN_TOTAL_SEC" }, { head, key })
    head, key = WFJ.UIIndex:clientTail("Use: Restores 50 health. (Requires level 60 or below)")
    assert.are.same({ "Use: Restores 50 health.", "ITEM_SPELL_MAX_USABLE_LEVEL" }, { head, key })
    assert.is_nil(WFJ.UIIndex:clientTail("Use: Teaches you (Rank 2)"))
    assert.is_nil(WFJ.UIIndex:clientTail("Use: Restores 50 health."))
  end)

  it("a branch line is matched without the cooldown tail, so its number never picks the other variant", function()
    local function line(text)
      Stub.setItemTooltip(_G.GameTooltip, "|Hitem:1003:0:0:0|h[Snack]|h", { "Snack", text, "Sell Price: 5c" })
      return _G.GameTooltipTextLeft2:GetText()
    end
    assert.are.equal("体力を50回復し、さらに精神が5上がる。", line("Use: Restores 50 health and 5 Spirit. (1 Sec Cooldown)"))
    assert.are.equal("体力を50回復する。", line("Use: Restores 50 health. (1 Sec Cooldown)"))
    assert.are.equal("体力を50回復する。", line("Use: Restores 50 health."))
  end)

  it("a gated item translation keeps the whole line to its gate (no trailer appended)", function()
    Stub.setItemTooltip(_G.GameTooltip, POTION_LINES(1002))
    local text = _G.GameTooltipTextLeft2:GetText()
    assert.is_nil(text:find("レベル60以下", 1, true))
  end)
end)
