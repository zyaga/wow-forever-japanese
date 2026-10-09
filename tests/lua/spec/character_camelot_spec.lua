-- the character window on the Forever (camelot) client: the icon mode tabs' tooltips, the level line
-- (player and pet), the stat pane's pooled category headers, stat labels and stat tooltips, and an empty equipment
-- slot's tooltip. Names (class, spec, pet family, a skill-named stat row, the window title) stay English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local RC = require("tests.lua.spec.stub_camelot_character")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Character.lua"

local UI = {
  CHARACTER_FRAME_TAB_REPUTATION = { "Reputation", "評判" },
  CHARACTER_FRAME_TAB_STATISTICS = { "Statistics", "統計" },
  PLAYER_LEVEL = { RC.EN.PLAYER_LEVEL, "レベル%1$s |c%2$s%3$s %4$s|r" },
  PLAYER_LEVEL_NO_SPEC = { RC.EN.PLAYER_LEVEL_NO_SPEC, "レベル%1$s |c%2$s%3$s|r" },
  UNIT_TYPE_LEVEL_TEMPLATE = { RC.EN.UNIT_TYPE_LEVEL_TEMPLATE, "レベル%d %s" },
  -- a longer template that also reads "Level 60 Wind Serpent" (the communities roster line) and must not shadow the
  -- pet's level line under the level key set
  COMMUNITY_MEMBER_CHARACTER_INFO_FORMAT = { "Level %d %s %s", "レベル%d %s %s" },
  STAT_CATEGORY_GENERAL = { "General", "一般" },
  STAT_CATEGORY_PRIMARY_ATTRIBUTES = { "Primary Attributes", "基本能力値" },
  SPELL_STAT3_NAME = { "Stamina", "スタミナ" },
  DEFAULT_STAMINA_TOOLTIP = { "Increases health points.", "HPが上昇。" },
  HEADSLOT = { "Head", "頭" },
  SWORDS = { "Swords", "片手剣" }, -- a skill name that is also a dictionary word
  EQUIPSET_EQUIP = { "Equip", "装備" }, SAVE = { "Save", "保存" }, PAPERDOLL_NEWEQUIPMENTSET = { "New Set", "新規セット" },
  DELETE = { "Delete", "削除" }, EQUIPMENT_SET_SETTINGS = { "Settings", "設定" },
  PLAYER_TITLE_NONE = { "No Title", "称号なし" },
  GEARSETS_POPUP_TEXT = { "Enter Set Name (Max 16 Characters):", "セット名を入力 (最大16文字):" },
  ICON_SELECTION_CLICK = { "Click to view in the list", "クリックで一覧に表示" },
  ICON_SELECTION_NOTINLIST = { "This icon is not in the list", "このアイコンは一覧にありません" },
  -- a Warrior's hit hover, `_G["CR_"..class.."_HIT_CAP_TOOLTIP"]` formatted (camelot
  -- paperdollframestats.lua:449–451): the "%%" of the global string prints one "%"
  CR_WARRIOR_HIT_CAP_TOOLTIP = { "\n|cffBCBCBCTo never miss|r |cFFFF5A5ARaid Bosses|r|cffBCBCBC:\n  8.00%% Melee"
    .. "\n\nTo never miss|r |cFF52E31ELvl %d Targets|r", "\n|cffBCBCBC必中には|r |cFFFF5A5Aレイドボス|r|cffBCBCBC："
    .. "\n  8.00%% 近接\n\n必中には|r |cFF52E31ELv%dの対象|r" },
  -- the crit hover has no specifier at all, and is still printed through format() (:539–545)
  STAT_WARRIOR_CRIT_BONUS = { "Melee critical strikes deal 100%% increased damage", "近接クリティカルはダメージが100%%増加" },
  -- the pet damage row's hover title (CharacterDamageFrame_OnEnter, unit "pet", camelot paperdollframe.lua:
  -- 2293–2294) and the row's label word
  INVTYPE_WEAPONMAINHAND_PET = { "Main Attack", "主攻撃" }, DAMAGE = { "Damage", "ダメージ" },
  -- a pet's loyalty rank, C_PetInfo.GetPetLoyalty() (client-table row: no global; ADR-042)
  ["PetLoyalty:3"] = { "Submissive", "従順" },
  -- the parentheses around the pet's rank (camelot/paperdollframe.lua:537)
  PARENS_TEMPLATE = { "(%s)", "（%s）" },
}

-- The UIStrings entries this surface needs on camelot are in Core/UIStringKeys.lua (ARGS PLAYER_LEVEL …, the stat
-- labels' bareColon form); nothing is injected for them.
local ARGS = {}
local LABELS = { SWORDS = "bareColon" } -- only so the spec can show a skill-named row stays English anyway

describe("the character window on the Forever client", function()
  local WFJ, saved

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function left(i) return _G["GameTooltipTextLeft" .. i]:GetText() end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    RC.install()
    WFJ = H.loadChunks(FILES)
    saved = { args = {}, labels = {} }
    for k, v in pairs(ARGS) do saved.args[k] = WFJ.UIStrings.ARGS[k]; WFJ.UIStrings.ARGS[k] = v end
    for k, v in pairs(LABELS) do saved.labels[k] = WFJ.UIStrings.LABELS[k]; WFJ.UIStrings.LABELS[k] = v end
    H.uiSetup(WFJ, UI)
    WFJ.Labels.forbidNames(WFJ.Character.NEVER_TOUCH) -- Main registers every list before any init
    WFJ.Character.init()
  end)

  after_each(function()
    for k in pairs(ARGS) do WFJ.UIStrings.ARGS[k] = saved.args[k] end
    for k in pairs(LABELS) do WFJ.UIStrings.LABELS[k] = saved.labels[k] end
    H.uiTeardown()
  end)

  it("the level writers are hooked once", function()
    assert.are.equal(1, #Stub.hooks.PaperDollFrame_SetLevel)
    assert.are.equal(1, #Stub.hooks.PaperDollFrame_SetPetLevel)
    assert.is_false(WFJ.Character.init())
    assert.are.equal(1, #_G.CharacterStatsPaneScrollBox.ScrollBox.initCallbacks)
    assert.are.equal(1, #_G.CharacterStatsPanePetScrollBox.ScrollBox.initCallbacks)
    -- the window title left NEVER_TOUCH; the player's name title still stays English (next describe)
    assert.are.equal("Reyn", _G.CharacterFrame.TitleContainer.TitleText:GetText())
  end)

  it("a mode tab's tooltip translates; a tab whose word is not in the dictionary stays English", function()
    RC.hover(_G.CharacterFrameModeTab2)
    assert.are.equal("評判", left(1))
    alt(true)
    assert.are.equal("Reputation", left(1))
    alt(false)
    RC.hover(_G.CharacterFrameModeTab4)
    assert.are.equal("PvP", left(1))
    RC.hover(_G.CharacterFrameModeTab6)
    assert.are.equal("統計", left(1))
  end)

  it("the level line translates with the level, class colour, spec and class verbatim, with and without a spec,"
    .. " and the pet's level line keeps its family", function()
    _G.PaperDollFrame_SetLevel()
    assert.are.equal("レベル60 |cffc79c6eProtection Warrior|r", _G.CharacterLevelText:GetText())
    alt(true)
    assert.are.equal("Level 60 |cffc79c6eProtection Warrior|r", _G.CharacterLevelText:GetText())
    alt(false)
    RC.player.spec = nil
    _G.PaperDollFrame_SetLevel()
    assert.are.equal("レベル60 |cffc79c6eWarrior|r", _G.CharacterLevelText:GetText())
    RC.player.pet = { level = 58, family = "Wolf" }
    _G.PaperDollFrame_SetPetLevel()
    assert.are.equal("レベル58 Wolf", _G.PetCharacterLevelText:GetText())
    assert.are.equal("レベル60 |cffc79c6eWarrior|r", _G.CharacterLevelText:GetText()) -- the player's line is untouched
    alt(true)
    assert.are.equal("Level 58 Wolf", _G.PetCharacterLevelText:GetText())
    alt(false)
    assert.are.equal("レベル58 Wolf", _G.PetCharacterLevelText:GetText())
  end)

  it("the pet's level line with a loyalty rank: the level part and the rank in Japanese, the rank's colour kept;"
    .. " Alt shows the live English; a rank that is no PetLoyalty row stays as written", function()
    RC.player.pet = { level = 20, family = "Boar", loyalty = "Submissive" }
    _G.PaperDollFrame_SetPetLevel()
    assert.are.equal("レベル20 Boar |cffffffff（従順）|r", _G.PetCharacterLevelText:GetText())
    alt(true)
    assert.are.equal("Level 20 Boar |cffffffff(Submissive)|r", _G.PetCharacterLevelText:GetText())
    alt(false)
    assert.are.equal("レベル20 Boar |cffffffff（従順）|r", _G.PetCharacterLevelText:GetText())
    _G.PaperDollFrame_SetLevel() -- the other writer's hook leaves the pet's line as it is
    assert.are.equal("レベル20 Boar |cffffffff（従順）|r", _G.PetCharacterLevelText:GetText())
    RC.player.pet.loyalty = "Damage" -- a dictionary word, but no PetLoyalty row
    _G.PaperDollFrame_SetPetLevel()
    assert.are.equal("レベル20 Boar |cffffffff(Damage)|r", _G.PetCharacterLevelText:GetText())
    RC.player.pet.loyalty = "Loyal Beyond Words" -- not in the dictionary at all
    _G.PaperDollFrame_SetPetLevel()
    assert.are.equal("レベル20 Boar |cffffffff(Loyal Beyond Words)|r", _G.PetCharacterLevelText:GetText())
  end)

  it("a pet's line that is no UNIT_TYPE_LEVEL_TEMPLATE line stays English, rank and all", function()
    _G.PetCharacterLevelText.text = "Something Else |cffffffff(Submissive)|r"
    _G.PaperDollFrame_SetPetLevel()
    assert.are.equal("Something Else |cffffffff(Submissive)|r", _G.PetCharacterLevelText:GetText())
    _G.PetCharacterLevelText.text = "Something Else"
    _G.PaperDollFrame_SetPetLevel()
    assert.are.equal("Something Else", _G.PetCharacterLevelText:GetText())
  end)

  it("the stat pane's headers and stat labels translate on pooled rows; a skill-named row stays English", function()
    local rows = RC.setStats({ { header = "General" }, { label = "Stamina", value = "25" },
      { header = "Primary Attributes" }, { label = "Swords", value = "300" } })
    assert.are.equal("一般", rows[1].Title:GetText())
    assert.are.equal("スタミナ:", rows[2].Label:GetText())
    assert.are.equal("基本能力値", rows[3].Title:GetText())
    assert.are.equal("Swords:", rows[4].Label:GetText())
    assert.are.equal(0, rows[4].Label.calls.addonSetText)
    alt(true)
    assert.are.equal("Stamina:", rows[2].Label:GetText())
    alt(false)
    assert.are.equal("スタミナ:", rows[2].Label:GetText())
    -- the next update re-initializes the same pooled rows with other text: the records follow the widgets
    rows = RC.setStats({ { header = "Resistances" }, { label = "Fire", value = "5" } })
    assert.are.equal("Resistances", rows[1].Title:GetText())
    assert.are.equal("Fire:", rows[2].Label:GetText())
    alt(true); alt(false)
    assert.are.equal("Resistances", rows[1].Title:GetText()) -- no stale Japanese restored over the new English
  end)

  it("a stat row's tooltip translates (the row is a help-tooltip owner)", function()
    local rows = RC.setStats({ { header = "General" }, { label = "Stamina", value = "25",
      tooltip = "|cffffffffStamina 25|r", tooltip2 = "Increases health points." } })
    assert.is_true(WFJ.HelpTooltip.registered(rows[2]))
    assert.is_false(WFJ.HelpTooltip.registered(rows[1]))
    RC.hover(rows[2])
    assert.are.equal("|cffffffffスタミナ 25|r", left(1))
    assert.are.equal("HPが上昇。", left(2))
  end)

  it("a Warrior's hit-cap hover line translates, its numbers as printed", function()
    local rows = RC.setStats({ { header = "General" }, { label = "Stamina", value = "25",
      tooltip = "|cffffffffStamina 25|r", tooltip2 = string.format(UI.CR_WARRIOR_HIT_CAP_TOOLTIP[1], 1) } })
    RC.hover(rows[2])
    assert.are.equal("\n|cffBCBCBC必中には|r |cFFFF5A5Aレイドボス|r|cffBCBCBC：\n  8.00% 近接\n\n必中には|r"
      .. " |cFF52E31ELv1の対象|r", left(2))
    rows = RC.setStats({ { header = "General" }, { label = "Stamina", value = "25",
      tooltip = "|cffffffffStamina 25|r", tooltip2 = string.format(UI.STAT_WARRIOR_CRIT_BONUS[1]) } })
    RC.hover(rows[2])
    assert.are.equal("近接クリティカルはダメージが100%増加", left(2))
  end)

  it("a weapon-skill row's tooltip is never walked, even when the skill name is a dictionary word, and a pooled"
    .. " row that held a stat stops being walked once it carries a skill", function()
    local rows = RC.setStats({ { header = "General" }, { label = "Stamina", value = "25",
      tooltip = "Increases health points." } })
    RC.hover(rows[2])
    assert.are.equal("HPが上昇。", left(1))
    rows = RC.setStats({ { header = "General" }, { label = "Swords", value = "300", tooltip = "Swords",
      tooltip2 = "Increases health points." } })
    RC.hover(rows[2])
    assert.are.equal("Swords", left(1))
    assert.are.equal("Increases health points.", left(2))
    assert.are.equal("Swords:", rows[2].Label:GetText())
    -- the same row back on a stat: walked again
    rows = RC.setStats({ { header = "General" }, { label = "Stamina", value = "25",
      tooltip = "Increases health points." } })
    RC.hover(rows[2])
    assert.are.equal("HPが上昇。", left(1))
  end)

  it("the pet's level line with a two-word family translates, the family verbatim: the longer"
    .. " COMMUNITY_MEMBER_CHARACTER_INFO_FORMAT template does not shadow UNIT_TYPE_LEVEL_TEMPLATE under the level key"
    .. " set (Index:matchOnly retry)", function()
    RC.player.pet = { level = 60, family = "Wind Serpent" }
    _G.PaperDollFrame_SetPetLevel()
    assert.are.equal("レベル60 Wind Serpent", _G.PetCharacterLevelText:GetText())
    RC.player.pet.loyalty = "Submissive"
    _G.PaperDollFrame_SetPetLevel()
    assert.are.equal("レベル60 Wind Serpent |cffffffff（従順）|r", _G.PetCharacterLevelText:GetText())
  end)

  it("the pet stat pane is followed the same way", function()
    local rows = RC.setStats({ { header = "General" }, { label = "Stamina", value = "40" } },
      "CharacterStatsPanePetScrollBox")
    assert.are.equal("一般", rows[1].Title:GetText())
    assert.are.equal("スタミナ:", rows[2].Label:GetText())
  end)

  it("the pet damage row's hover title (INVTYPE_WEAPONMAINHAND_PET) translates; the numbers stay", function()
    local rows = RC.setStats({ { header = "General" }, { label = "Damage", value = "20-30", tooltip = "Main Attack",
      tooltip2 = "Damage: 20-30" } }, "CharacterStatsPanePetScrollBox")
    RC.hover(rows[2])
    assert.are.equal("主攻撃", left(1))
    alt(true)
    assert.are.equal("Main Attack", left(1))
    alt(false)
  end)

  it("an empty equipment slot's tooltip translates; a slot with an item is an item tooltip, never walked", function()
    RC.hover(_G.CharacterHeadSlot)
    assert.are.equal("頭", left(1))
    RC.headItem = "|cff0070dd|Hitem:12640::::::::60:::::|h[Lionheart Helm]|h|r"
    RC.hover(_G.CharacterHeadSlot)
    _G.GameTooltip:Show()
    assert.are.equal("Lionheart Helm", left(1))
  end)

  it("the equipment manager: its buttons and the popup header translate at init; a set row's name stays English"
    .. " (even a dictionary word) and its delete / settings tooltips translate", function()
    local pane = _G.PaperDollFrame.EquipmentManagerPane
    assert.are.equal("装備", pane.EquipSet:GetText())
    assert.are.equal("保存", pane.SaveSet:GetText())
    assert.are.equal("新規セット", (pane.NewSet:GetRegions()):GetText())
    assert.are.equal("セット名を入力 (最大16文字):", _G.GearManagerPopupFrame.BorderBox.EditBoxHeaderText:GetText())
    local rows = RC.setGearSets({ "Save", "Tanking" })
    assert.are.equal("Save", rows[1].text:GetText())
    assert.are.equal(0, rows[1].text.calls.addonSetText)
    assert.is_true(WFJ.Labels.forbidden(rows[1].text))
    RC.hover(rows[2].DeleteButton)
    assert.are.equal("削除", left(1))
    RC.hover(rows[2].EditButton)
    assert.are.equal("設定", left(1))
    alt(true)
    assert.are.equal("Equip", pane.EquipSet:GetText())
    assert.are.equal("Settings", left(1))
    alt(false)
    assert.is_true(WFJ.Labels.forbidden(_G.GearManagerPopupFrame.BorderBox.IconSelectorEditBox))
  end)

  it("the title pane: the No Title row translates; an earned title stays English, even a dictionary word", function()
    local rows = RC.setTitles({ "Save", "Private" })
    assert.are.equal("称号なし", rows[1].text:GetText())
    assert.are.equal("Save", rows[2].text:GetText())
    assert.are.equal("Private", rows[3].text:GetText())
    alt(true)
    assert.are.equal("No Title", rows[1].text:GetText())
    alt(false)
    rows = RC.setTitles({}) -- a pooled row keeps no stale translation
    assert.are.equal("称号なし", rows[1].text:GetText())
  end)

  it("the popup's icon description translates after SetSelectedIconText and after an icon is clicked", function()
    local popup = _G.GearManagerPopupFrame
    local desc = popup.BorderBox.SelectedIconArea.SelectedIconText.SelectedIconDescription
    RC.iconInList = false
    popup:SetSelectedIconText()
    assert.are.equal("このアイコンは一覧にありません", desc:GetText())
    popup.IconSelector:OnSelection(3)
    assert.are.equal("クリックで一覧に表示", desc:GetText())
    alt(true)
    assert.are.equal("Click to view in the list", desc:GetText())
    alt(false)
    assert.are.equal(1, #Stub.hooks["GearManagerPopupFrame:SetSelectedIconText"])
    assert.are.equal(1, #Stub.hooks["?:SetSelectedIndex"])
  end)

  it("a moved stat pane or a missing ScrollUtil degrades to nothing, with no error (type guards)", function()
    assert.has_no.errors(function() WFJ.Character.onStatRow(WFJ.Character, "moved") end)
    assert.has_no.errors(function() WFJ.Character.onStatRow({}) end)
    assert.has_no.errors(function() WFJ.Character.onGearSetRow(WFJ.Character, "moved") end)
    assert.has_no.errors(function() WFJ.Character.onGearSetRow({ DeleteButton = "moved" }) end)
    assert.has_no.errors(function() WFJ.Character.onTitleRow(WFJ.Character, "moved") end)
    assert.has_no.errors(function() WFJ.Character.onTitleRow({ text = "moved" }) end)
    _G.GearManagerPopupFrame.BorderBox = "moved"
    assert.are.equal(0, WFJ.Character.onIconText())
    _G.CharacterStatsPaneScrollBox.ScrollBox = "moved"
    _G.ScrollUtil = nil
    WFJ.Compat.init(function(name) return _G[name] end)
    assert.has_no.errors(function() WFJ.Character.init() end)
  end)
end)

-- the window title. CharacterFrameMixin:UpdateTitle →
-- SetTitle(characterFrameDisplayInfo[activeSubframe].title):
-- the player's name on the paperdoll, REPUTATION / CURRENCY / PVP / SKILLS / STATISTICS on the other panes
-- [camelot/characterframe.lua:254–258; camelot/characterframeconstants.lua:9–34].
describe("the character window's title on the Forever client", function()
  local WFJ

  local TITLES = { ReputationFrame = "Reputation", SkillsFrame = "Skills", TokenFrame = "Currency" }
  local TITLE_UI = {
    SKILLS = { "Skills", "スキル" }, REPUTATION = { "Reputation", "評判" }, CURRENCY = { "Currency", "通貨" },
    CLOSE = { "Close", "閉じる" }, -- a dictionary word that is no pane title
  }
  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function title() return _G.CharacterFrame.TitleContainer.TitleText:GetText() end

  local function setup(playerName)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    RC.install()
    local cf = _G.CharacterFrame
    cf.playerTitle = playerName or "Reyn"
    function cf.SetTitle(self, t) self.TitleContainer.TitleText.text = t end
    function cf.UpdateTitle(self) self:SetTitle(TITLES[self.activeSubframe] or self.playerTitle) end
    function cf.ShowSubFrame(self, pane) self.activeSubframe = pane; self:UpdateTitle() end
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, TITLE_UI)
    WFJ.Labels.forbidNames(WFJ.Character.NEVER_TOUCH)
    WFJ.Character.init()
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
  end)

  it("a pane title renders after SetTitle and after a second SetTitle; the paperdoll's name title stays English",
    function()
    setup()
    local cf = _G.CharacterFrame
    cf:ShowSubFrame("SkillsFrame")
    assert.are.equal("スキル", title())
    cf:UpdateTitle()
    assert.are.equal("スキル", title())
    cf:ShowSubFrame("ReputationFrame")
    assert.are.equal("評判", title())
    alt(true)
    assert.are.equal("Reputation", title())
    alt(false)
    cf:ShowSubFrame("PaperDollFrame")
    assert.are.equal("Reyn", title())
    cf:SetTitle("Close") -- not a pane title, though a dictionary word
    assert.are.equal("Close", title())
  end)

  it("a player named like a pane keeps the name on the paperdoll", function()
    setup("Skills")
    local cf = _G.CharacterFrame
    cf:ShowSubFrame("PaperDollFrame")
    assert.are.equal("Skills", title())
    alt(true)
    alt(false)
    assert.are.equal("Skills", title())
    cf:ShowSubFrame("SkillsFrame")
    assert.are.equal("スキル", title())
    cf:ShowSubFrame("PaperDollFrame")
    assert.are.equal("Skills", title())
    assert.are.equal(0, WFJ.SurfaceState.count("character.title"))
  end)

  it("a title host of the wrong shape degrades to English with no error", function()
    assert.has_no.errors(function()
      Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
      Stub.installTooltipAPI()
      RC.install()
      _G.CharacterFrame.TitleContainer = { TitleText = "moved" }
      _G.CharacterFrame.UpdateTitle = "moved"
      WFJ = H.loadChunks(FILES)
      H.uiSetup(WFJ, TITLE_UI)
      WFJ.Character.init()
      WFJ.Character.onUpdateTitle()
    end)
  end)
end)
