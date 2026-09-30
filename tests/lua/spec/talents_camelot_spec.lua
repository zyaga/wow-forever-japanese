-- The talents tab on the Forever (camelot) client: PlayerSpellsFrame.TalentsFrame in the load-on-demand
-- Blizzard_PlayerSpells: the static labels, the dual-spec tabs (the icon markup and disabled colour kept), and the
-- talent tooltip's lines through EventRegistry "TalentDisplay.TooltipCreated" (line 1, the talent's name, untouched).
-- The window title is UI/SpellBook's hook (playerspells_spellbook_spec); it is checked here with both modules loaded.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local PS = require("tests.lua.spec.stub_playerspells")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
for _, f in ipairs({ "UI/SpellBook.lua", "UI/Talents.lua" }) do FILES[#FILES + 1] = f end

local UI = {
  TALENTS = { "Talents", "タレント" }, SPELLBOOK = { "Spellbook", "呪文書" },
  TALENT_FRAME_APPLY_BUTTON_TEXT = { "Apply Changes", "変更を適用" }, TALENT_SPEC_ACTIVATE = { "Activate", "有効化" },
  TALENT_SPEC_ACTIVE = { "Active", "有効" }, UNSPENT_POINTS = { "Unspent Talents", "未使用タレント" },
  DUAL_SPEC_PRIMARY = { "Primary", "メイン" }, DUAL_SPEC_SECONDARY = { "Secondary", "サブ" },
  TALENT_BUTTON_TOOLTIP_RANK_FORMAT = { "Rank %s/%s", "ランク %s/%s" },
  TALENT_BUTTON_TOOLTIP_NEXT_RANK = { "Next Rank:", "次のランク:" },
  TALENT_BUTTON_TOOLTIP_PURCHASE_INSTRUCTIONS = { "Click to learn", "クリックで習得" },
  TALENT_BUTTON_TOOLTIP_REFUND_INSTRUCTIONS = { "Right click to unlearn", "右クリックで習得解除" },
  TALENT_BUTTON_TOOLTIP_REPLACED_BY_FORMAT = { "Replaced by %s", "%sに置き換え" },
  TALENT_SPEC_LOCKED = { "Locked", "ロック中" },
  TALENT_FRAME_DISCARD_CHANGES_BUTTON_TOOLTIP = { "Undo Pending Changes", "保留中の変更を取り消す" },
  -- the action-bar status and edge-requirements lines
  TALENT_FRAME_SEARCH_TOOLTIP_NOT_ON_ACTIONBAR = { "Not on your action bars", "アクションバーにありません" },
  GENERIC_TRAIT_FRAME_EDGE_REQUIREMENTS_BUTTON_TOOLTIP = { "Requires all preceding talents", "前提タレントがすべて必要" },
}

describe("talents on the Forever client", function()
  local WFJ, SS

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function talents() return _G.PlayerSpellsFrame.TalentsFrame end
  local function tab(id) return talents().TabSystem:GetTabButton(id) end
  local function line(i) return _G["GameTooltipTextLeft" .. i]:GetText() end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    PS.install()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
  end)

  after_each(function() H.uiTeardown() end)

  it("waits for Blizzard_PlayerSpells; after its ADDON_LOADED the static labels are Japanese", function()
    assert.is_false(WFJ.Talents.init())
    assert.are.equal(0, SS.count("talents.static"))
    PS.loadPlayerSpells()
    assert.are.equal(1, WFJ.LoadOnDemand.loaded("Blizzard_PlayerSpells"))
    assert.are.equal("変更を適用", talents().ApplyButton:GetText())
    assert.are.equal("有効化", talents().ActiveSpec.ActivateButton:GetText())
    assert.are.equal("有効", talents().ActiveSpec.ActiveLabel:GetText())
    assert.are.equal("未使用タレント", talents().ClassCurrencyDisplay.UnspentLabel:GetText())
    assert.are.equal(WFJ.Font.PATH, (talents().ClassCurrencyDisplay.UnspentLabel:GetFont()))
    alt(true)
    assert.are.equal("Apply Changes", talents().ApplyButton:GetText())
    alt(false)
    PS.openTalents(); _G.PlayerSpellsFrame:Hide()
    assert.are.equal("変更を適用", talents().ApplyButton:GetText()) -- static: never released
    assert.is_false(WFJ.Talents.setupCamelot())
  end)

  describe("loaded", function()
    before_each(function()
      PS.loadPlayerSpells()
      WFJ.SpellBook.init()
      WFJ.Talents.init()
    end)

    it("the window title (the shared UpdateFrameTitle hook) reads Talents in Japanese", function()
      PS.openTalents()
      assert.are.equal("タレント", _G.PlayerSpellsFrame.TitleContainer.TitleText:GetText())
    end)

    it("the dual-spec tabs keep the checkmark / lock markup and the disabled colour around the Japanese word",
      function()
        assert.are.equal("メイン " .. PS.CHECKMARK, tab(1).Text:GetText()) -- written at OnLoad, shown at setup
        assert.are.equal("|cff808080サブ " .. PS.LOCK .. "|r", tab(2).Text:GetText())
        PS.specGroups, PS.activeGroup = 2, 2 -- dual spec learned, the second group active
        talents():UpdateTabs()
        assert.are.equal("メイン", tab(1).Text:GetText())
        assert.are.equal("サブ " .. PS.CHECKMARK, tab(2).Text:GetText())
        assert.are.equal(WFJ.Font.PATH, (tab(2).Text:GetFont()))
        alt(true)
        assert.are.equal("Secondary " .. PS.CHECKMARK, tab(2).Text:GetText())
        alt(false)
        assert.are.equal("サブ " .. PS.CHECKMARK, tab(2).Text:GetText())
        tab(1).tabText = "Primary Talents" -- a text that is not the whole word stays English
        tab(1):UpdateTabText()
        assert.are.equal("Primary Talents", tab(1).Text:GetText())
      end)

    it("the locked secondary tab's tooltip and the undo button's tooltip translate", function()
      tab(2).scripts.OnEnter(tab(2))
      assert.are.equal("ロック中", line(1))
      _G.GameTooltip:Hide()
      talents().UndoButton.scripts.OnEnter(talents().UndoButton)
      assert.are.equal("保留中の変更を取り消す", line(1))
      alt(true)
      assert.are.equal("Undo Pending Changes", line(1))
      alt(false)
      _G.GameTooltip:Hide()
      PS.specGroups = 2 -- dual spec learned: the tab is enabled and shows no tooltip
      talents():UpdateTabs()
      tab(2).scripts.OnEnter(tab(2))
      assert.is_false(_G.GameTooltip.shown)
    end)

    it("the talent tooltip's rank / next-rank / instruction lines translate; line 1 (the name) never does, and each"
      .. " rebuild is walked again", function()
      local display = CreateFrame("Button") -- a pooled talent button
      PS.hoverTalent(display, { "Click to learn", "Rank |cffffffff1|r/5", "Increases your damage by 5%.",
        "Replaced by Mortal Strike", "", "Next Rank:", "Increases your damage by 10%.", "", "Click to learn" })
      assert.are.equal("Click to learn", line(1)) -- a talent named like a dictionary line
      assert.are.equal(0, _G.GameTooltipTextLeft1.calls.SetText)
      assert.are.equal("ランク |cffffffff1|r/5", line(2))
      assert.are.equal("Increases your damage by 5%.", line(3))
      assert.are.equal("Mortal Strikeに置き換え", line(4))
      assert.are.equal("次のランク:", line(6))
      assert.are.equal("クリックで習得", line(9))
      assert.are.equal(WFJ.Font.PATH, (_G.GameTooltipTextLeft2:GetFont()))
      local shows = _G.GameTooltip.calls.Show
      alt(true)
      assert.are.equal("Rank |cffffffff1|r/5", line(2))
      assert.is_true(_G.GameTooltip.calls.Show > shows) -- relaid out for the new text
      alt(false)
      PS.hoverTalent(display, { "Mortal Strike", "Rank |cffffffff5|r/5", "", "Right click to unlearn" })
      assert.are.equal("ランク |cffffffff5|r/5", line(2))
      assert.are.equal("右クリックで習得解除", line(4))
      assert.are.equal("", line(6)) -- the earlier record on a line the client cleared is gone, not restored
      _G.GameTooltip:Hide()
      assert.are.equal("Rank |cffffffff5|r/5", line(2))
      assert.are.equal(0, SS.count(WFJ.Talents.TOOLTIP_SURFACE))
    end)

    it("the action-bar status and edge-requirements lines translate", function()
      local display = CreateFrame("Button")
      PS.hoverTalent(display, { "Mortal Strike", "Rank |cffffffff0|r/1", "Requires all preceding talents",
        "Not on your action bars" })
      assert.are.equal("前提タレントがすべて必要", line(3))
      assert.are.equal("アクションバーにありません", line(4))
      _G.GameTooltip:Hide()
    end)
  end)

  it("a moved or missing client name degrades to English with no error (type guards)", function()
    PS.loadPlayerSpells()
    talents().TabSystem.GetTabButton = "moved"
    _G.EventRegistry = { RegisterCallback = {} }
    assert.has_no.errors(function() WFJ.Talents.init() end)
    assert.are.equal(0, WFJ.Talents.showTabs())
    assert.are.equal(0, WFJ.Talents.onTooltip(nil, nil, { GetName = true }))
    assert.are.equal(0, WFJ.Talents.showTab("tabPrimary", { Text = { GetText = "x" } }))
    assert.are.equal("Primary " .. PS.CHECKMARK, tab ~= nil and talents().TabSystem.tabs[1].Text:GetText())
  end)
end)
