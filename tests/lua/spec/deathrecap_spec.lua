-- UI/DeathRecap.lua over a DeathRecapFrame replayed from
-- blizzard_deathrecap/mainline/blizzard_deathrecap.lua (DeathRecapEntryMixin:Init :156–223, the DamageInfo tooltip
-- :44–81, OpenRecap :348–362) and .xml (Title :174, Unavailable :187, CloseButton :217). Load-on-demand, both orders.
-- Spell, caster and number widgets stay as the client wrote them. Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local ADDON = "Blizzard_DeathRecap"
local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/DeathRecap.lua"

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local UI = {
  DEATH_RECAP_TITLE = { "Death Recap", "死亡の記録" },
  DEATH_RECAP_UNAVAILABLE = { "Death Recap unavailable.", "死亡の記録は利用できません。" },
  CLOSE = { "Close", "閉じる" },
  COMBATLOG_UNKNOWN_UNIT = { "Something", "何か" },
  DEATH_RECAP_CAST_BY_TT = { "%s by %s", "%s（%sによる）" },
  DEATH_RECAP_CURR_HP_TT = { "%s sec before death at %s%% health.", "死亡の%s秒前、体力%s%%。" },
  DEATH_RECAP_DEATH_TT = { "Killing blow at %s%% health.", "体力%s%%でとどめの一撃。" },
  -- dictionary words that are also a spell's / a unit's name here: never shown on the name widgets
  ATTACK = { "Attack", "攻撃" },
  -- the damage line's trailer form and the Avoidable line's icon form
  DEATH_RECAP_DAMAGE_TT = { "%s %s", "%s %s" },
  TEXT_MODE_A_STRING_VALUE_SCHOOL = { "%s %s", "%s %s" },
  TEXT_MODE_A_STRING_RESULT_OVERKILLING = { "(%s Overkill)", "(%s オーバーキル)" },
  TEXT_MODE_A_STRING_RESULT_ABSORB = { "(%s Absorbed)", "(%s 吸収)" },
  TEXT_MODE_A_STRING_RESULT_BLOCK = { "(%s Blocked)", "(%s ブロック)" },
  STRING_SCHOOL_FIRE = { "Fire", "火炎" },
  DEATH_RECAP_AVOIDABLE_SPELL = { "Avoidable", "回避可能" },
}

local function en(key) return _G[key] end

local function installDeathRecap()
  local frame = CreateFrame("Frame", "DeathRecapFrame")
  frame.Title = Stub.fontString(en("DEATH_RECAP_TITLE"))
  frame.Unavailable = Stub.fontString(en("DEATH_RECAP_UNAVAILABLE"))
  frame.CloseButton = Stub.button(nil, en("CLOSE"))
  frame.ScrollBox = Stub.scrollBox()
  frame.rows = {}
  local function newRow()
    local row = CreateFrame("Frame")
    row.SpellInfo = { Name = Stub.fontString(""), Caster = Stub.fontString("") }
    row.DamageInfo = CreateFrame("Frame")
    row.DamageInfo.Amount, row.DamageInfo.AmountLarge = Stub.fontString(""), Stub.fontString("")
    row.DamageInfo:SetScript("OnEnter", function(owner) -- blizzard_deathrecap.lua:44–81
      _G.GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
      _G.GameTooltip:ClearLines()
      _G.GameTooltip:AddLine(row.line1 or string.format("%s %s", row.amount, ""))
      if row.avoidable then _G.GameTooltip:AddLine("|A:damagemeters-avoidabledamage-icon:16:16|aAvoidable") end
      _G.GameTooltip:AddLine(string.format(en("DEATH_RECAP_CAST_BY_TT"), row.spellName, row.caster))
      if row.seconds > 0 then
        _G.GameTooltip:AddLine(string.format(en("DEATH_RECAP_CURR_HP_TT"), string.format("%.1f", row.seconds), row.hp))
      else
        _G.GameTooltip:AddLine(string.format(en("DEATH_RECAP_DEATH_TT"), row.hp))
      end
      _G.GameTooltip:Show()
    end)
    return row
  end
  -- OpenRecap: every event initializes one pooled row (rows are reused from the front)
  function frame.OpenRecap(self, events)
    for i, e in ipairs(events) do
      local row = self.rows[i] or newRow()
      self.rows[i] = row
      self.ScrollBox:initFrame(row, e, function(r, data)
        r.spellName, r.caster, r.amount, r.seconds, r.hp = data.spell, data.caster or en("COMBATLOG_UNKNOWN_UNIT"),
          data.amount, data.seconds, data.hp
        r.line1, r.avoidable = data.line1, data.avoidable
        r.SpellInfo.Name.text, r.SpellInfo.Caster.text = r.spellName, r.caster
        r.DamageInfo.Amount.text, r.DamageInfo.AmountLarge.text = "-" .. data.amount, "-" .. data.amount
      end)
    end
    self:Show()
  end
  Stub.loadedAddons[ADDON] = true
  return frame
end

describe("the death recap window on Forever", function()
  local WFJ, SS

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do
        if rec.fs == widget then return false end
      end
    end
    return true
  end

  local function fresh()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
  end

  local function setup(loadedFirst)
    fresh()
    _G.OpenDeathRecapUI = function() end -- the bootstrap's opener is there from login
    if loadedFirst then
      installDeathRecap()
      assert.is_true(WFJ.DeathRecap.init())
    else
      assert.is_false(WFJ.DeathRecap.init()) -- waits for the addon
      installDeathRecap()
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.DeathRecapFrame, _G.OpenDeathRecapUI, _G.issecretvalue = nil, nil, nil
  end)

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    describe("Blizzard_DeathRecap " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("title, unavailable text and the close button are Japanese; Alt shows the client's English", function()
        local f = _G.DeathRecapFrame
        assert.are.equal("死亡の記録", f.Title:GetText())
        assert.are.equal("死亡の記録は利用できません。", f.Unavailable:GetText())
        assert.are.equal("閉じる", f.CloseButton:GetText())
        alt(true)
        assert.are.equal("Death Recap", f.Title:GetText())
        assert.are.equal("Close", f.CloseButton:GetText())
        alt(false)
        assert.are.equal("死亡の記録", f.Title:GetText())
      end)

      it("rows: an unknown caster translates; a spell, a caster name and the amounts stay as written", function()
        local f = _G.DeathRecapFrame
        f:OpenRecap({ { spell = "Attack", caster = "Attack", amount = "120", seconds = 2.5, hp = 40 },
          { spell = "Fireball", caster = nil, amount = "300", seconds = 0, hp = 12 } })
        local first, second = f.rows[1], f.rows[2]
        assert.are.equal("Attack", first.SpellInfo.Name:GetText()) -- a dictionary word, but a spell name here
        assert.are.equal("Attack", first.SpellInfo.Caster:GetText()) -- and a unit's name here
        assert.are.equal("-120", first.DamageInfo.Amount:GetText())
        assert.is_true(unrecorded(first.SpellInfo.Name))
        assert.is_true(unrecorded(first.SpellInfo.Caster))
        assert.is_true(WFJ.Labels.forbidden(first.SpellInfo.Name))
        assert.are.equal("何か", second.SpellInfo.Caster:GetText())
        -- the pool reuses the first row for another event: its caster shows the new text
        f:OpenRecap({ { spell = "Fireball", caster = nil, amount = "300", seconds = 0, hp = 12 } })
        assert.are.equal("何か", first.SpellInfo.Caster:GetText())
        alt(true)
        assert.are.equal("Something", first.SpellInfo.Caster:GetText())
        alt(false)
      end)

      it("the damage tooltip: the health lines translate, the amount line stays English", function()
        local f = _G.DeathRecapFrame
        f:OpenRecap({ { spell = "Fireball", caster = "Kobold Geomancer", amount = "120", seconds = 2.5, hp = 40 },
          { spell = "Fireball", caster = "Kobold Geomancer", amount = "300", seconds = 0, hp = 12 } })
        local damage = f.rows[1].DamageInfo
        damage.scripts.OnEnter(damage)
        assert.are.equal("120 ", _G.GameTooltipTextLeft1:GetText())
        -- "%s by %s" takes names: it renders only once Core/UIStrings.ARGS carries its `text` arguments
        if WFJ.UIStrings.ARGS.DEATH_RECAP_CAST_BY_TT then
          assert.are.equal("Fireball（Kobold Geomancerによる）", _G.GameTooltipTextLeft2:GetText())
        else
          assert.are.equal("Fireball by Kobold Geomancer", _G.GameTooltipTextLeft2:GetText())
        end
        assert.are.equal("死亡の2.5秒前、体力40%。", _G.GameTooltipTextLeft3:GetText())
        local killing = f.rows[2].DamageInfo
        killing.scripts.OnEnter(killing)
        assert.are.equal("体力12%でとどめの一撃。", _G.GameTooltipTextLeft3:GetText())
      end)

      it("trailer: the damage line's school and result groups translate, amounts kept; Alt shows English",
        function()
          local f = _G.DeathRecapFrame
          local line = "1,200 Fire (300 Overkill) (50 Absorbed)"
          f:OpenRecap({ { spell = "Fireball", caster = "Kobold Geomancer", amount = "1,200", seconds = 0, hp = 0,
            line1 = line, avoidable = true } })
          local damage = f.rows[1].DamageInfo
          damage.scripts.OnEnter(damage)
          assert.are.equal("1,200 火炎 (300 オーバーキル) (50 吸収)", _G.GameTooltipTextLeft1:GetText())
          assert.are.equal("|A:damagemeters-avoidabledamage-icon:16:16|a回避可能", _G.GameTooltipTextLeft2:GetText())
          alt(true)
          assert.are.equal(line, _G.GameTooltipTextLeft1:GetText())
          alt(false)
          -- no school (the amount alone) and a trailing blank: the amount kept, the group translated
          f:OpenRecap({ { spell = "Fireball", caster = "Kobold Geomancer", amount = "80", seconds = 0, hp = 0,
            line1 = "80  (20 Blocked)" } })
          damage.scripts.OnEnter(damage)
          assert.are.equal("80  (20 ブロック)", _G.GameTooltipTextLeft1:GetText())
          -- an unknown group keeps the whole line English
          f:OpenRecap({ { spell = "Fireball", caster = "Kobold Geomancer", amount = "80", seconds = 0, hp = 0,
            line1 = "80 Fire (Crushing)" } })
          damage.scripts.OnEnter(damage)
          assert.are.equal("80 Fire (Crushing)", _G.GameTooltipTextLeft1:GetText())
        end)
    end)
  end

  it("a secret caster text is never read into a match", function()
    setup(true)
    local f = _G.DeathRecapFrame
    _G.issecretvalue = function(v) return v == "Something" end
    local fresh2 = H.loadChunks(FILES) -- a module that resolves issecretvalue
    H.uiSetup(fresh2, UI)
    assert.is_true(fresh2.DeathRecap.init())
    f:OpenRecap({ { spell = "Fireball", caster = nil, amount = "300", seconds = 0, hp = 12 } })
    assert.are.equal("Something", f.rows[1].SpellInfo.Caster:GetText())
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    fresh()
    _G.OpenDeathRecapUI = function() end
    local frame = installDeathRecap()
    frame.Title, frame.CloseButton, frame.ScrollBox = "Death Recap", 42, true
    assert.has_no.errors(function() WFJ.DeathRecap.init() end)
    assert.are.equal("死亡の記録は利用できません。", frame.Unavailable:GetText())
    _G.DeathRecapFrame = "not a frame"
    local other = H.loadChunks(FILES)
    H.uiSetup(other, UI)
    assert.has_no.errors(function() other.DeathRecap.init() end)
    -- a row of the wrong shape
    assert.has_no.errors(function() WFJ.DeathRecap.onRow({ SpellInfo = 1, DamageInfo = "x" }) end)
  end)

  it("hooks install once; a client without the death recap is skipped without error", function()
    setup(true)
    assert.has_no.errors(function() WFJ.DeathRecap.init() end)
    assert.are.equal(1, #_G.DeathRecapFrame.ScrollBox.initCallbacks)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    _G.DeathRecapFrame, _G.OpenDeathRecapUI = nil, nil
    local bare = H.loadChunks(FILES)
    H.uiSetup(bare, UI)
    assert.has_no.errors(function() assert.is_false(bare.DeathRecap.init()) end)
  end)
end)
