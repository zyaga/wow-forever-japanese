-- The spellbook on the Forever (camelot) client: PlayerSpellsFrame.SpellBookFrame in the load-on-demand
-- Blizzard_PlayerSpells: the host title, the page text, each displayed item's subtext and required-level line (by
-- EventRegistry, plus the late subtext and a data refresh), and the settings menu's checkbox labels.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local PS = require("tests.lua.spec.stub_playerspells")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
for _, f in ipairs({ "UI/SpellBook.lua", "UI/Talents.lua" }) do FILES[#FILES + 1] = f end

local UI = {
  SPELLBOOK = { "Spellbook", "呪文書" }, TALENTS = { "Talents", "タレント" },
  SPECIALIZATION = { "Specialization", "専門化" },
  TALENTS_INSPECT_FORMAT = { "Talents - %s", "タレント - %s" },
  TALENTS_LINK_FORMAT = { "Linked Talents (%s %s)", "リンクされたタレント(%s %s)" },
  PAGE_NUMBER_WITH_MAX = { "Page %d/%d", "ページ %d/%d" }, SPELL_PASSIVE = { "Passive", "パッシブ" },
  TOOLTIP_TALENT_RANK_CURRENT_ONLY = { "Rank %d", "ランク %d" }, APPRENTICE = { "Apprentice", "見習い" },
  SPELLBOOK_AVAILABLE_AT = { "Level %d", "レベル%d" }, SPELLBOOK_TRAINABLE = { "See your trainer", "トレーナーで習得" },
  SHOW_ALL_SPELL_RANKS = { "Show all spell ranks", "すべての呪文ランクを表示" },
  SPELLBOOK_FILTER_PASSIVES = { "Hide Passives", "パッシブを隠す" }, CLOSE = { "Close", "閉じる" },
  SPELLBOOK_SEARCH_INSTRUCTIONS = { "Search", "検索" },
  SPELLBOOK_SEARCH_HEADER_EXACT = { "Exact Match", "完全一致" }, SPELLBOOK_SEARCH_HEADER_NAME = { "Name Match", "名前一致" },
  SPELLBOOK_SEARCH_HIDE_PASSIVES_DISABLED = { "Unavailable while searching", "検索中は使えません" },
  GENERAL = { "General", "一般" }, -- a skill-line name that is also a dictionary word
  -- the Spell table's own subtexts, fingerprint rows (no global string)
  ["SpellSubtext:5227"] = { "Racial Passive", "種族パッシブ" }, ["SpellSubtext:2481"] = { "Racial", "種族" },
  -- "Summon": an exact global string (BATTLE_PET_SUMMON) with the same Japanese as the fingerprint row
  BATTLE_PET_SUMMON = { "Summon", "呼び出す" }, ["SpellSubtext:126"] = { "Summon", "呼び出す" },
}

describe("spellbook on the Forever client", function()
  local WFJ, S, SS

  local function recorded(fs)
    for _, recs in pairs(SS.surfaces()) do
      for _, rec in pairs(recs) do if rec.fs == fs then return true end end
    end
    return false
  end
  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function items() return _G.PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame.frames end
  local function title() return _G.PlayerSpellsFrame.TitleContainer.TitleText end
  local function pageText() return _G.PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame.PagingControls.PageText end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    PS.install()
    WFJ = H.loadChunks(FILES)
    S, SS = WFJ.Settings, WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
  end)

  after_each(function() H.uiTeardown() end)

  local function book()
    PS.spells = {
      [10] = { name = "Fireball", subtext = "Rank 3", cached = true },
      [11] = { name = "Frost Armor", subtext = "Rank 1", cached = false },
      [12] = { name = "Close", subtext = "", passive = true, cached = true }, -- a spell named like a dictionary word
      [13] = { name = "Blizzard", subtext = "Rank 1", cached = true, level = 20 },
      [14] = { name = "Arcane Intellect", subtext = "Rank 2", cached = true, trainable = true },
      [15] = { name = "Tailoring", subtext = "Apprentice", cached = true },
    }
    PS.book = { 10, 11, 12, 13, 14, 15 }
  end

  describe("load-on-demand wait", function()
    it("nothing is hooked before Blizzard_PlayerSpells loads; its ADDON_LOADED sets the book up once", function()
      assert.is_false(WFJ.SpellBook.init()) -- Blizzard_PlayerSpells is not loaded yet: nothing is set up
      PS.loadPlayerSpells(); book()
      assert.is_nil(Stub.hooks["PlayerSpellsFrame:UpdateFrameTitle"])
      assert.are.equal(1, WFJ.LoadOnDemand.loaded("Blizzard_PlayerSpells"))
      assert.are.equal(0, WFJ.LoadOnDemand.loaded("Blizzard_PlayerSpells"))
      PS.openSpellBook()
      assert.are.equal("呪文書", title():GetText())
      assert.is_false(WFJ.SpellBook.setupCamelot()) -- again: no second set of hooks
      assert.are.equal(1, #Stub.hooks["PlayerSpellsFrame:UpdateFrameTitle"])
    end)

    it("an addon already loaded when init runs is set up at once, including what the client already wrote", function()
      PS.loadPlayerSpells(); book()
      PS.openSpellBook() -- shown before the addon's init
      assert.are.equal("Spellbook", title():GetText())
      WFJ.SpellBook.init()
      assert.are.equal("呪文書", title():GetText())
      assert.are.equal("ページ 1/2", pageText():GetText())
      assert.are.equal("ランク 3", items()[1].SubName:GetText())
    end)
  end)

  describe("the book", function()
    before_each(function()
      PS.loadPlayerSpells(); book()
      WFJ.SpellBook.init()
    end)

    it("the host title follows UpdateFrameTitle (spellbook, talents, inspect with the name verbatim); Alt, area and"
      .. " the host's OnHide put the English back", function()
      PS.openSpellBook()
      assert.are.equal("呪文書", title():GetText())
      assert.are.equal(WFJ.Font.PATH, (title():GetFont()))
      PS.openTalents()
      assert.are.equal("タレント", title():GetText())
      _G.PlayerSpellsFrame:SetTab("specialization") -- forever_titles.txt `key SPECIALIZATION spellbook`
      assert.are.equal("専門化", title():GetText())
      _G.PlayerSpellsFrame:UpdateFrameTitle() -- a second SetTitle keeps it
      assert.are.equal("専門化", title():GetText())
      _G.PlayerSpellsFrame.inspectUnit = "Reyn"
      _G.PlayerSpellsFrame:UpdateFrameTitle()
      assert.are.equal("タレント - Reyn", title():GetText())
      alt(true)
      assert.are.equal("Talents - Reyn", title():GetText())
      alt(false)
      S.set("area.interface", false)
      assert.are.equal("Talents - Reyn", title():GetText())
      S.set("area.interface", true)
      assert.are.equal("タレント - Reyn", title():GetText())
      _G.PlayerSpellsFrame:Hide()
      assert.are.equal("Talents - Reyn", title():GetText())
      assert.are.equal(0, SS.count(WFJ.SpellBook.HOST))
    end)

    it("a linked build's title: the spec and class names kept; Alt English", function()
      PS.openTalents()
      local host = _G.PlayerSpellsFrame
      host.linked = { "Protection", "Warrior" }
      host:UpdateFrameTitle()
      assert.are.equal("リンクされたタレント(Protection Warrior)", title():GetText())
      alt(true)
      assert.are.equal("Linked Talents (Protection Warrior)", title():GetText())
      alt(false)
      host.linked = { "Holy.", "Paladin" } -- a period: never a `text` argument
      host:UpdateFrameTitle()
      assert.are.equal("Linked Talents (Holy. Paladin)", title():GetText())
      host.linked = nil
    end)

    it("the page text (PAGE_NUMBER_WITH_MAX) follows UpdateControls", function()
      PS.openSpellBook()
      assert.are.equal("ページ 1/2", pageText():GetText())
      _G.PlayerSpellsFrame.SpellBookFrame:DisplayPage(2)
      assert.are.equal("ページ 2/2", pageText():GetText())
      alt(true)
      assert.are.equal("Page 2/2", pageText():GetText())
      alt(false)
      assert.are.equal("ページ 2/2", pageText():GetText())
    end)

    it("each displayed item's subtext and required-level line translate; spell names are never touched", function()
      PS.openSpellBook()
      local it = items()
      assert.are.equal("ランク 3", it[1].SubName:GetText())
      assert.are.equal("", it[2].SubName:GetText()) -- Frost Armor's data is not loaded yet
      assert.are.equal("パッシブ", it[3].SubName:GetText())
      assert.are.equal("Close", it[3].Name:GetText())
      PS.loadSpell(11) -- the late subtext: UpdateSubName outside any event
      assert.are.equal("ランク 1", it[2].SubName:GetText())
      assert.are.equal(WFJ.Font.PATH, (it[2].SubName:GetFont()))
      _G.PlayerSpellsFrame.SpellBookFrame:DisplayPage(2)
      it = items()
      assert.are.equal("レベル20", it[1].RequiredLevel:GetText())
      assert.are.equal("ランク 1", it[1].SubName:GetText())
      assert.are.equal("トレーナーで習得", it[2].RequiredLevel:GetText())
      assert.are.equal("見習い", it[3].SubName:GetText())
      for _, item in ipairs(_G.PlayerSpellsFrame.SpellBookFrame.pool) do
        assert.are.equal(0, item.Name.calls.SetText)
        assert.is_false(recorded(item.Name))
      end
      alt(true)
      assert.are.equal("Level 20", it[1].RequiredLevel:GetText())
      assert.are.equal("Apprentice", it[3].SubName:GetText())
      alt(false)
      assert.are.equal("見習い", it[3].SubName:GetText())
    end)

    it("a racial subtext is Japanese by fingerprint; a form or pet-family subtext stays English",
      function()
        PS.spells[10].subtext = "Racial Passive"
        PS.spells[12].subtext, PS.spells[12].passive = "Racial", false
        PS.spells[15].subtext = "Cat"
        PS.spells[11].subtext, PS.spells[11].cached = "Summon", true -- Summon Imp
        PS.openSpellBook()
        local it = items()
        assert.are.equal("種族パッシブ", it[1].SubName:GetText())
        assert.are.equal("呼び出す", it[2].SubName:GetText())
        assert.are.equal("種族", it[3].SubName:GetText())
        assert.are.equal("Close", it[3].Name:GetText()) -- the spell name is never written
        alt(true)
        assert.are.equal("Racial Passive", it[1].SubName:GetText())
        alt(false)
        _G.PlayerSpellsFrame.SpellBookFrame:DisplayPage(2)
        assert.are.equal("Cat", items()[3].SubName:GetText())
      end)

    it("an item the pool makes after setup is Japanese from its first subtext, before any event",
      function()
        PS.openSpellBook()
        local item = PS.newItem() -- carries the hooked SpellBookItemMixin methods
        item:Init({ slotIndex = 12, spellBank = 0 }) -- no DisplayedSpellsChanged: only the mixin hook sees it
        assert.are.equal("パッシブ", item.SubName:GetText())
      end)

    it("records are keyed by spell slot: a page flip drops the slots no longer shown, a data refresh without the"
      .. " event re-shows, and the book's OnHide releases", function()
      PS.openSpellBook()
      assert.is_table(SS.get("spellbook", "sub.0.10"))
      _G.PlayerSpellsFrame.SpellBookFrame:DisplayPage(2)
      assert.is_nil(SS.get("spellbook", "sub.0.10"))
      assert.is_table(SS.get("spellbook", "sub.0.13"))
      local it = items()
      PS.spells[15].subtext = "Rank 2" -- the client's data changed: UpdateAllSpellData re-runs UpdateVisuals
      _G.PlayerSpellsFrame.SpellBookFrame:RefreshSpellData()
      assert.are.equal("ランク 2", it[3].SubName:GetText())
      _G.PlayerSpellsFrame.SpellBookFrame:Hide()
      assert.are.equal("Rank 2", it[3].SubName:GetText())
      assert.are.equal("Page 2/2", pageText():GetText())
      assert.are.equal(0, SS.count("spellbook"))
    end)

    it("the settings menu's checkbox labels translate through Menu.ModifyMenu; other entries stay; the book's hide"
      .. " forgets them", function()
      PS.openSpellBook()
      local buttons = PS.openMenu("MENU_SPELL_BOOK_SETTINGS", { "Hide Passives", "Group Similar Spells on Flyouts",
        "Show all spell ranks" })
      assert.are.equal("パッシブを隠す", buttons[1].fontString:GetText())
      assert.are.equal("Group Similar Spells on Flyouts", buttons[2].fontString:GetText()) -- no dictionary line
      assert.are.equal("すべての呪文ランクを表示", buttons[3].fontString:GetText())
      assert.are.equal(WFJ.Font.PATH, (buttons[3].fontString:GetFont()))
      alt(true)
      assert.are.equal("Show all spell ranks", buttons[3].fontString:GetText())
      alt(false)
      -- regenerated for a warrior (no ranks entry): the pooled buttons are reused for other labels
      buttons = PS.openMenu("MENU_SPELL_BOOK_SETTINGS", { "Group Similar Spells on Flyouts", "Hide Passives" })
      assert.are.equal("Group Similar Spells on Flyouts", buttons[1].fontString:GetText())
      assert.are.equal("パッシブを隠す", buttons[2].fontString:GetText())
      assert.is_nil(PS.menuMods.OTHER_MENU)
      _G.PlayerSpellsFrame.SpellBookFrame:Hide()
      assert.are.equal(0, SS.count(WFJ.SpellBook.MENU))
    end)
  end)

  it("a menu button's record is dropped by the menu's own resetter when the menu discards its frames; a pooled"
    .. " fontString reused by another menu is never written by a later refresh", function()
    PS.loadPlayerSpells(); book()
    WFJ.SpellBook.init()
    PS.openSpellBook()
    local buttons = PS.openMenu("MENU_SPELL_BOOK_SETTINGS", { "Show all spell ranks" })
    local fs = buttons[1].fontString
    assert.are.equal("すべての呪文ランクを表示", fs:GetText())
    PS.closeMenu()
    assert.are.equal(0, SS.count(WFJ.SpellBook.MENU))
    assert.are.equal("Show all spell ranks", fs:GetText()) -- dropped while still ours: the English is back
    fs.text = "Some Other Menu Entry" -- the pool hands the button to another menu (no ModifyMenu for it)
    local writes, fonts = fs.calls.addonSetText, fs.calls.addonSetFont
    alt(true); alt(false)
    S.set("area.interface", false); S.set("area.interface", true)
    _G.PlayerSpellsFrame.SpellBookFrame:Hide()
    assert.are.equal("Some Other Menu Entry", fs:GetText())
    assert.are.equal(writes, fs.calls.addonSetText)
    assert.are.equal(fonts, fs.calls.addonSetFont)
  end)

  describe("search", function()
    before_each(function()
      PS.loadPlayerSpells(); book()
      WFJ.SpellBook.init()
    end)

    it("the search box placeholder is Japanese from setup and never released; the EditBox is never written", function()
      local box = _G.PlayerSpellsFrame.SpellBookFrame.SearchBox
      assert.are.equal("検索", box.Instructions:GetText())
      assert.are.equal(WFJ.Font.PATH, (box.Instructions:GetFont()))
      PS.openSpellBook(); _G.PlayerSpellsFrame.SpellBookFrame:Hide()
      assert.are.equal("検索", box.Instructions:GetText())
      assert.is_nil(box.text)
      alt(true)
      assert.are.equal("Search", box.Instructions:GetText())
      alt(false)
    end)

    it("search-result section headers translate; a category header (a skill-line name) stays English; items still"
      .. " translate beside them; a page without headers drops their records", function()
      PS.perPage = 4
      PS.book = { "Exact Match", 10, "General", 12, "Name Match", 15 }
      PS.openSpellBook()
      local f = items()
      assert.are.equal("完全一致", f[1].Text:GetText())
      assert.are.equal("ランク 3", f[2].SubName:GetText())
      assert.are.equal("General", f[3].Text:GetText())
      assert.are.equal(0, f[3].Text.calls.SetText)
      _G.PlayerSpellsFrame.SpellBookFrame:DisplayPage(2)
      assert.are.equal("名前一致", items()[1].Text:GetText())
      alt(true)
      assert.are.equal("Name Match", items()[1].Text:GetText())
      alt(false)
      PS.book = { 10, 11 }
      _G.PlayerSpellsFrame.SpellBookFrame:DisplayPage(1)
      for key in pairs(SS.records("spellbook")) do assert.is_nil(key:find("^header%."), key) end
    end)

    it("the Hide Passives entry's disabled tooltip translates on the menu button that owns it", function()
      PS.openSpellBook()
      local buttons = PS.openMenu("MENU_SPELL_BOOK_SETTINGS", { "Hide Passives" })
      PS.hoverMenuButton(buttons[1], { "Unavailable while searching" })
      assert.are.equal("検索中は使えません", _G.GameTooltipTextLeft1:GetText())
      PS.hoverMenuButton(buttons[1], { "Close" }) -- restricted: another dictionary word on that owner stays
      assert.are.equal("Close", _G.GameTooltipTextLeft1:GetText())
    end)
  end)

  it("a moved or missing client name degrades to English with no error (type guards)", function()
    PS.loadPlayerSpells(); book()
    _G.PlayerSpellsFrame.UpdateFrameTitle = {} -- not a function
    _G.PlayerSpellsFrame.SpellBookFrame.ForEachDisplayedSpell = nil
    _G.PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame.PagingControls.UpdateControls = "moved"
    _G.EventRegistry = { RegisterCallback = true }
    _G.Menu = { ModifyMenu = {} }
    assert.has_no.errors(function() WFJ.SpellBook.init() end)
    assert.are.equal(0, WFJ.SpellBook.onDisplayedSpells())
    assert.are.equal(0, WFJ.SpellBook.onSettingsMenu(nil, { EnumerateElementDescriptions = "x" }))
    assert.are.equal(0, SS.count("spellbook"))
  end)
end)
