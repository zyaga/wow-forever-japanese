-- the bags on the Forever (camelot) client: the mainline container frames (titles through SetTitle →
-- TitleContainer.TitleText, the combined backpack), their portrait tooltips, the lazily made add-slots button, the
-- backpack clean-up button and the bag bar's help tooltips. Bag and item names stay English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local CI = require("tests.lua.spec.stub_camelot_inventory")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Bags.lua"

local UI = {
  BACKPACK_TOOLTIP = { "Backpack", "バックパック" },
  KEYRING = { "Keyring", "キーリング" },
  COMBINED_BAG_TITLE = { "Combined Backpack", "統合バックパック" },
  CLICK_BAG_SETTINGS = { "|cff00ff00<Click for Bag Settings>|r", "|cff00ff00<クリックでバッグ設定>|r" },
  BACKPACK_AUTHENTICATOR_INCREASE_SIZE = { "Increase Backpack Size", "バックパックを拡張" },
  BAG_CLEANUP_BAGS = { "Clean Up Bags", "バッグを整理" },
  BAG_CLEANUP_BAGS_DESCRIPTION = { "Auto-sorts your inventory to make room for new items.",
    "所持品を自動で並べ替えて空きを作る。" },
  EQUIP_CONTAINER = { "Equip Container", "バッグを装備" },
  EQUIP_CONTAINER_REAGENT = { "Equip Reagent Bag", "素材バッグを装備" },
  SEARCH = { "Search", "検索" },
  NUM_FREE_SLOTS = { "%d Empty |4Slot:Slots; (Total)", "空きスロット %d（合計）" },
}

describe("the bags on the Forever client", function()
  local WFJ

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function left(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
  local function title(f) return f.TitleContainer.TitleText:GetText() end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    for key, pair in pairs(UI) do _G[key] = pair[1] end -- the client's GlobalStrings
    CI.install()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    WFJ.Labels.forbidNames(WFJ.Bags.NEVER_TOUCH)
    assert.is_true(WFJ.Bags.init())
  end)

  after_each(function()
    H.uiTeardown()
    CI.teardown()
  end)

  it("titles: the backpack and the keyring are Japanese, a bag's item name stays English, and a frame reused for"
    .. " a bag drops its record", function()
    local backpack = CI.openBag(0)
    assert.are.equal("バックパック", title(backpack))
    assert.are.equal(WFJ.Font.PATH, (backpack.TitleContainer.TitleText:GetFont()))
    local pouch = CI.openBag(1)
    assert.are.equal("Small Red Pouch", title(pouch))
    local keyring = CI.openBag(-2)
    assert.are.equal("キーリング", title(keyring))
    local named = CI.openBag(2) -- a bag whose item name is "Keyring"
    assert.are.equal("Keyring", title(named))
    _G.ContainerFrame_GenerateFrame(backpack, 16, 1) -- the backpack frame reused for a bag
    assert.are.equal("Small Red Pouch", title(backpack))
    assert.is_nil(WFJ.SurfaceState.get("bags", "ui.title.ContainerFrame1"))
    alt(true)
    assert.are.equal("Keyring", title(keyring))
    alt(false)
    assert.are.equal("キーリング", title(keyring))
  end)

  it("the combined backpack's title is Japanese", function()
    local combined = CI.openCombined()
    assert.are.equal("統合バックパック", title(combined))
  end)

  -- the title again after a second SetTitle (the frame generated again). UI/Bags keeps its own per-bag-id
  -- resolution rather than Labels.title: a ContainerFrame is reused for the backpack, the keyring and bags, so one
  -- fixed `only` per frame would change what a reused frame's title may match (see the "Keyring"-named bag above).
  it("the combined backpack's title stays Japanese after a second SetTitle", function()
    local combined = CI.openCombined()
    CI.openCombined()
    assert.are.equal("統合バックパック", title(combined))
    local backpack = CI.openBag(0)
    CI.openBag(0)
    assert.are.equal("バックパック", title(backpack))
  end)

  it("portrait tooltips: the backpack line keeps its key binding and the settings hint is Japanese; a bag's name"
    .. " stays English", function()
    local backpack = CI.openBag(0)
    CI.hover(backpack.PortraitButton)
    assert.are.equal("バックパック |cffffd200(B)|r", left(1))
    assert.are.equal("|cff00ff00<クリックでバッグ設定>|r", left(2))
    local pouch = CI.openBag(1)
    CI.hover(pouch.PortraitButton)
    assert.are.equal("Small Red Pouch", left(1))
    assert.are.equal("|cff00ff00<クリックでバッグ設定>|r", left(2))
    local combined = CI.openCombined()
    CI.hover(combined.PortraitButton)
    assert.are.equal("バックパック |cffffd200(B)|r", left(1))
  end)

  it("the add-slots button, made on first use, is registered after the backpack is generated", function()
    local backpack = CI.openBag(0)
    assert.is_true(WFJ.HelpTooltip.registered(backpack.AddSlotsButton))
    CI.hover(backpack.AddSlotsButton)
    assert.are.equal("バックパックを拡張", left(1))
  end)

  it("the clean-up button's title and description are Japanese", function()
    CI.hover(_G.BagItemAutoSortButton)
    assert.are.equal("バッグを整理", left(1))
    assert.are.equal("所持品を自動で並べ替えて空きを作る。", left(2))
  end)

  it("the bag bar: backpack (binding kept, free-slot count untouched), keyring, empty bag and reagent slots are"
    .. " Japanese; an equipped bag is an item tooltip", function()
    CI.hover(_G.MainMenuBarBackpackButton)
    assert.are.equal("バックパック|cffffd200 (B)|r", left(1))
    assert.are.equal("空きスロット 12（合計）", left(2))
    CI.hover(_G.KeyRingButton)
    assert.are.equal("キーリング", left(1))
    CI.hover(_G.CharacterBag0Slot)
    assert.are.equal("バッグを装備", left(1))
    CI.hover(_G.CharacterReagentBag0Slot)
    assert.are.equal("素材バッグを装備", left(1))
    CI.equipped.CharacterBag1Slot = "Equip Container"
    CI.hover(_G.CharacterBag1Slot)
    assert.are.equal("Equip Container", left(1))
  end)

  it("the search box's placeholder is Japanese (Alt shows the English); the box's own text is never written", function()
    local search = _G.BagItemSearchBox
    assert.are.equal("検索", search.Instructions:GetText())
    alt(true)
    assert.are.equal("Search", search.Instructions:GetText())
    alt(false)
    assert.is_nil(search.GetText and search:GetText() ~= "" and search:GetText() or nil)
  end)

  it("a padlocked extended slot made after init shows 'Increase Backpack Size' in Japanese", function()
    local ext = CI.makeExtended()
    CI.hover(ext)
    assert.are.equal("バックパックを拡張", left(1))
    alt(true)
    assert.are.equal("Increase Backpack Size", left(1))
    alt(false)
    CI.hover(ext) -- a second hover goes through the registered owner
    assert.are.equal("バックパックを拡張", left(1))
  end)

  it("the backpack's free-slot line keeps the count in either plural form", function()
    CI.freeSlots = 1
    CI.hover(_G.MainMenuBarBackpackButton)
    assert.are.equal("空きスロット 1（合計）", left(2))
    CI.freeSlots = nil
    -- the text as the client resolves the |4 grammar (singular and plural)
    for _, line in ipairs({ { "1 Empty Slot (Total)", "空きスロット 1（合計）" },
                            { "13 Empty Slots (Total)", "空きスロット 13（合計）" } }) do
      local saved = _G.NUM_FREE_SLOTS
      _G.NUM_FREE_SLOTS = line[1]:gsub("%d+", "%%d")
      CI.freeSlots = tonumber(line[1]:match("%d+"))
      CI.hover(_G.MainMenuBarBackpackButton)
      assert.are.equal(line[2], left(2))
      _G.NUM_FREE_SLOTS, CI.freeSlots = saved, nil
    end
  end)

  it("a generated frame without a name or a title widget degrades to English with no error", function()
    assert.are.equal(0, WFJ.Bags.onGenerate("moved", 16, 0))
    assert.are.equal(0, WFJ.Bags.onGenerate({ GetName = function() return nil end }, 16, 0))
    local f = CI.openBag(0)
    f.TitleContainer = { TitleText = "moved" } -- a title that is no text widget
    f.SetTitle = function() end
    assert.has_no.errors(function() _G.ContainerFrame_GenerateFrame(f, 16, 0) end)
  end)
end)
