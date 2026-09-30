-- The skills panel on the Forever (camelot) client: SkillsFrame.SkillDetailFrame's empty prompt after
-- SetEmpty and its weapon-skill headers and templates (percent values verbatim) on pooled rows after LayoutRows. The
-- detail pane's Refresh is registered by reference, so the stub drives it directly; skill names stay English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local PS = require("tests.lua.spec.stub_playerspells")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Skills.lua"

local UI = {
  SKILL_DETAIL_SELECT_PROMPT = { "Select a skill to view its details.", "スキルを選ぶと詳細が表示されます。" },
  WEAPON_SKILL_DETAIL_SAME_LEVEL_HEADER = { "|cFFFFFFFFEqual-Level Enemy|r", "|cFFFFFFFF同レベルの敵|r" },
  WEAPON_SKILL_DETAIL_BOSS_HEADER = { "|cFFFFFFFFAgainst Raid Bosses|r", "|cFFFFFFFFレイドボス相手|r" },
  WEAPON_SKILL_DETAIL_SAME_LEVEL = { PS.G("WEAPON_SKILL_DETAIL_SAME_LEVEL"),
    "|cFFFFFFFF命中|r、および|cFFFFFFFF回避|r・|cFFFFFFFF受け流し|rされない確率: %s\n\n|cFFFFFFFFクリティカル|r率: %s" },
  WEAPON_SKILL_DETAIL_BOSS = { PS.G("WEAPON_SKILL_DETAIL_BOSS"),
    "|cFFFFFFFF命中|r、および|cFFFFFFFF回避|r・|cFFFFFFFF受け流し|rされない確率: %s\n\n|cFFFFFFFFクリティカル|r率: %s"
      .. "\n\n|cFFFFFFFFかすり|rは%sの確率で発生し、与ダメージが%s減少する。各種の追加効果や命中判定の説明はここに続き、"
      .. "日本語の方が長くなって行数が増える場合の試験用の長い文章です。" },
  WEAPON_SKILL_DETAIL_BOSS_RANGED = { PS.G("WEAPON_SKILL_DETAIL_BOSS_RANGED"),
    "|cFFFFFFFF命中|r率: %s\n\n|cFFFFFFFFクリティカル|r率: %s" },
  SWORDS = { "Swords", "片手剣" }, -- a skill name that is also a dictionary word
}

describe("skills on the Forever client", function()
  local WFJ, SS

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function detail() return _G.SkillsFrame.SkillDetailFrame end
  local function rows() return PS.rowPools.active end
  local SWORDS = { name = "Swords", description = "Allows the use of swords.",
    weapon = { values = { "+5.00%", "5.00%", "-2.40%", "3.10%", "40%", "35%" } } }

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    PS.install() -- SkillsFrame exists at login (Blizzard_UIPanels_Game)
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    WFJ.Labels.forbidNames(WFJ.Skills.NEVER_TOUCH) -- Main registers every list before any init
    WFJ.Skills.init()
  end)

  after_each(function() H.uiTeardown() end)

  it("the empty prompt translates after SetEmpty", function()
    _G.SkillsFrame:Show() -- no selection: Refresh → SetEmpty
    assert.are.equal("スキルを選ぶと詳細が表示されます。", detail().EmptyText:GetText())
    assert.are.equal(WFJ.Font.PATH, (detail().EmptyText:GetFont()))
    alt(true)
    assert.are.equal("Select a skill to view its details.", detail().EmptyText:GetText())
    alt(false)
    _G.SkillsFrame:Hide()
    assert.are.equal("Select a skill to view its details.", detail().EmptyText:GetText())
    assert.are.equal(0, SS.count("skills"))
    assert.is_false(WFJ.Skills.init()) -- once
    assert.are.equal(1, #Stub.hooks["?:SetEmpty"])
  end)

  it("a melee weapon skill's headers and templates translate on the pooled rows, the percentages verbatim; the pane"
    .. " title and description (names, client data) stay English", function()
    _G.SkillsFrame:Show()
    PS.selectSkill(SWORDS)
    local r = rows()
    assert.are.equal(4, #r)
    assert.are.equal("|cFFFFFFFF同レベルの敵|r", r[1].Label:GetText())
    assert.are.equal("|cFFFFFFFF命中|r、および|cFFFFFFFF回避|r・|cFFFFFFFF受け流し|rされない確率: +5.00%\n\n"
      .. "|cFFFFFFFFクリティカル|r率: 5.00%", r[2].Label:GetText())
    assert.are.equal("|cFFFFFFFFレイドボス相手|r", r[3].Label:GetText())
    assert.is_truthy(r[4].Label:GetText():find("|cFFFFFFFFかすり|rは40%の確率で発生し、与ダメージが35%減少", 1, true))
    assert.is_truthy(r[4].Label:GetText():find("確率: -2.40%", 1, true))
    assert.are.equal("Swords", detail().Title:GetText())
    assert.are.equal(0, detail().Title.calls.SetText)
    assert.are.equal("Allows the use of swords.", detail().Description:GetText())
    alt(true)
    assert.is_truthy(r[2].Label:GetText():find("^Chance to |cFFFFFFFFHit|r"))
    alt(false)
    assert.are.equal("|cFFFFFFFF同レベルの敵|r", r[1].Label:GetText())
  end)

  it("a taller Japanese row grows and the pane is laid out again; a category row keeps its height", function()
    _G.SkillsFrame:Show()
    PS.selectSkill(SWORDS)
    local r = rows()
    local v = SWORDS.weapon.values
    local english = Stub.textHeight(PS.G("WEAPON_SKILL_DETAIL_BOSS"):format(v[3], v[4], v[5], v[6]),
      { path = "Fonts\\FRIZQT__.TTF", size = 13 }, 200)
    assert.is_true(r[4]:GetHeight() > english) -- grown past the height the client measured from the English
    assert.are.equal(r[4].Label:GetStringHeight(), r[4]:GetHeight())
    assert.are.equal(20, r[1]:GetHeight())
    assert.is_true(PS.layouts >= 3) -- SetEmpty's, Refresh's, and ours after the grown row
  end)

  it("rows are pooled: another skill reuses them, the records follow the widgets, a ranged skill uses its own"
    .. " templates, and clearing the selection drops every row record", function()
    _G.SkillsFrame:Show()
    PS.selectSkill(SWORDS)
    PS.selectSkill({ name = "Bows", weapon = { ranged = true, values = { "+1.00%", "2.00%", "-3.00%", "0.00%" } } })
    local r = rows()
    assert.are.equal("|cFFFFFFFF命中|r率: -3.00%\n\n|cFFFFFFFFクリティカル|r率: 0.00%", r[4].Label:GetText())
    local n = 0
    for key in pairs(SS.records("skills")) do if key:find("^detail%.") then n = n + 1 end end
    assert.are.equal(4, n)
    PS.selectSkill(nil)
    n = 0
    for key in pairs(SS.records("skills")) do if key:find("^detail%.") then n = n + 1 end end
    assert.are.equal(0, n)
    assert.are.equal("スキルを選ぶと詳細が表示されます。", detail().EmptyText:GetText())
  end)

  it("a non-weapon skill has no rows and its title stays English even when it is a dictionary word", function()
    _G.SkillsFrame:Show()
    PS.selectSkill({ name = "Swords", description = "" })
    assert.are.equal(0, #rows())
    assert.are.equal("Swords", detail().Title:GetText())
    assert.is_true(WFJ.Labels.forbidden(detail().Title))
  end)

  it("a moved pane or pool degrades to English with no error (type guards)", function()
    detail().rowPools = { EnumerateActive = "moved" }
    assert.are.equal(0, WFJ.Skills.onLayoutRows())
    _G.SkillsFrame.SkillDetailFrame = "moved"
    WFJ.Compat.declare("skills", "detail", { "SkillsFrame.SkillDetailFrame" })
    assert.are.equal(0, WFJ.Skills.onLayoutRows())
  end)
end)

-- The list's category headers. SkillsHeaderMixin:Initialize writes the header's name (client data) into
-- the row's `.Name`; "Weapon Skills" and "Languages" read exactly as STAT_CATEGORY_WEAPON_SKILLS / LANGUAGES_LABEL and
-- are shown, every other header and every skill's name stays English [camelot/skillsframe.lua:127–141, 321–325, 372].
describe("skills on the Forever client: the list's category headers", function()
  local WFJ, SS, box

  local HEADERS = {
    STAT_CATEGORY_WEAPON_SKILLS = { "Weapon Skills", "武器スキル" }, LANGUAGES_LABEL = { "Languages", "言語" },
    SWORDS = { "Swords", "片手剣" }, -- a skill name that is also a dictionary word
    TRADE_SKILLS = { "Professions", "専門技術" }, -- a header that is a dictionary word, but not one of the two
  }
  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function headerRow()
    local row = CreateFrame("Frame")
    row.Name = Stub.fontString("")
    return row
  end
  local function entryRow()
    local row = CreateFrame("Frame")
    row.Content = { Name = Stub.fontString("") }
    return row
  end
  local function initHeader(row, data) row.Name.text = data.name end -- SkillsHeaderMixin:Initialize
  local function initEntry(row, data) row.Content.Name.text = data.name end -- SkillsEntryMixin:Initialize

  local function setup(shape)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    PS.install()
    box = Stub.scrollBox()
    _G.SkillsFrame.ScrollBox = box
    if shape then shape() end
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, HEADERS)
    WFJ.Labels.forbidNames(WFJ.Skills.NEVER_TOUCH)
    WFJ.Skills.init()
  end

  after_each(function() H.uiTeardown() end)

  it("Weapon Skills and Languages translate; a header that is no dictionary word, a header that is another"
    .. " dictionary word, and every skill name stay English", function()
    setup()
    assert.are.equal(1, #box.initCallbacks)
    local weapons, languages, armor, professions = headerRow(), headerRow(), headerRow(), headerRow()
    box:initFrame(weapons, { isHeader = true, name = "Weapon Skills" }, initHeader)
    box:initFrame(languages, { isHeader = true, name = "Languages" }, initHeader)
    box:initFrame(armor, { isHeader = true, name = "Armor Proficiencies" }, initHeader)
    box:initFrame(professions, { isHeader = true, name = "Professions" }, initHeader)
    local swords = entryRow()
    box:initFrame(swords, { isHeader = false, name = "Swords" }, initEntry)
    local sub = entryRow() -- a sub-header (SkillsSubHeaderTemplate inherits the entry: its name is Content.Name)
    box:initFrame(sub, { isHeader = true, isChild = true, name = "Languages" }, initEntry)
    assert.are.equal("武器スキル", weapons.Name:GetText())
    assert.are.equal(WFJ.Font.PATH, (weapons.Name:GetFont()))
    assert.are.equal("言語", languages.Name:GetText())
    assert.are.equal("Armor Proficiencies", armor.Name:GetText())
    assert.are.equal("Professions", professions.Name:GetText())
    assert.are.equal("Swords", swords.Content.Name:GetText())
    assert.are.equal(0, swords.Content.Name.calls.SetText)
    assert.is_true(WFJ.Labels.forbidden(swords.Content.Name))
    assert.are.equal("Languages", sub.Content.Name:GetText())
    alt(true)
    assert.are.equal("Weapon Skills", weapons.Name:GetText())
    alt(false)
    assert.are.equal("武器スキル", weapons.Name:GetText())
  end)

  it("a header row is pooled: the record follows the widget, and the panel's OnHide restores the English", function()
    setup()
    local row = headerRow()
    box:initFrame(row, { isHeader = true, name = "Weapon Skills" }, initHeader)
    box:initFrame(row, { isHeader = true, name = "Armor Proficiencies" }, initHeader) -- reused for another header
    assert.are.equal("Armor Proficiencies", row.Name:GetText())
    local n = 0
    for key in pairs(SS.records("skills")) do if key:find("^header%.") then n = n + 1 end end
    assert.are.equal(0, n)
    box:initFrame(row, { isHeader = true, name = "Languages" }, initHeader)
    assert.are.equal("言語", row.Name:GetText())
    _G.SkillsFrame:Show()
    _G.SkillsFrame:Hide()
    assert.are.equal("Languages", row.Name:GetText())
  end)

  it("rows built before the addon loaded are walked once at init", function()
    local row = headerRow()
    setup(function() box:initFrame(row, { isHeader = true, name = "Languages" }, initHeader) end)
    assert.are.equal("言語", row.Name:GetText())
  end)

  it("a moved list, a missing ScrollUtil or a row of the wrong shape degrades to English with no error", function()
    assert.has_no.errors(function() setup(function() _G.SkillsFrame.ScrollBox = "moved" end) end)
    assert.has_no.errors(function() setup(function() _G.ScrollUtil = "moved" end) end)
    assert.are.equal(0, #box.initCallbacks)
    setup()
    assert.has_no.errors(function()
      WFJ.Skills.onListRow(WFJ.Skills, "moved")
      WFJ.Skills.onListRow(WFJ.Skills, { Name = "moved" }, { isHeader = true })
      WFJ.Skills.onListRow({ Content = "moved", Name = "moved" }, { isHeader = true })
    end)
  end)
end)

-- ADR-042: the SkillLine table's description in the detail pane (SetDescription writes the Description
-- ScrollingFont, skillsframe.lua:273; characterframe.lua:873–885), the SkillLineDescription:* family only; and the
-- list's headers, which are SkillLineCategory names (the SkillCategory:* family) besides the two GlobalStrings.
describe("skills on the Forever client: client-table text", function()
  local WFJ, box

  local ROWS = {
    ["SkillLineDescription:43"] = { "Allows the use of swords.", "片手剣を扱えるようになる。" },
    ["SkillCategory:7"] = { "Class Skills", "クラススキル" },
    ["SkillCategory:9"] = { "Secondary Skills", "二次スキル" },
    STAT_CATEGORY_WEAPON_SKILLS = { "Weapon Skills", "武器スキル" }, LANGUAGES_LABEL = { "Languages", "言語" },
    SWORDS = { "Swords", "片手剣" }, -- a skill name that is also a dictionary word
    TRADE_SKILLS = { "Professions", "専門技術" }, -- a header that is a dictionary word, but no SkillCategory row
  }
  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function detail() return _G.SkillsFrame.SkillDetailFrame end
  local function headerRow(name)
    local row = CreateFrame("Frame")
    row.Name = Stub.fontString("")
    box:initFrame(row, { isHeader = true, name = name }, function(r, d) r.Name.text = d.name end)
    return row
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    PS.install()
    box = Stub.scrollBox()
    _G.SkillsFrame.ScrollBox = box
    local d = _G.SkillsFrame.SkillDetailFrame
    d.Description = Stub.scrollingFont("")
    function d.SetDescription(self, text) self.Description:SetText(text) end
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, ROWS)
    WFJ.Labels.forbidNames(WFJ.Skills.NEVER_TOUCH)
    WFJ.Skills.init()
  end)

  after_each(function() H.uiTeardown(); Stub.keys.alt = false end)

  it("the description: a SkillLineDescription row is Japanese, Alt shows English; another text stays English",
    function()
      assert.is_false(WFJ.Labels.forbidden(detail().Description))
      local sf = detail().Description
      detail():SetDescription("Allows the use of swords.")
      assert.are.equal("片手剣を扱えるようになる。", sf:GetText())
      assert.are.equal(sf.fs:GetStringHeight(), sf.container.height)
      alt(true)
      assert.are.equal("Allows the use of swords.", sf:GetText())
      alt(false)
      assert.are.equal("片手剣を扱えるようになる。", sf:GetText())
      detail():SetDescription("Allows the use of maces.")
      assert.are.equal("Allows the use of maces.", sf:GetText())
      detail():SetDescription("Swords") -- a dictionary word, but no SkillLineDescription row
      assert.are.equal("Swords", sf:GetText())
    end)

  it("list headers: a SkillCategory row is Japanese, the two GlobalStrings still are, a skill name stays English",
    function()
      local class, secondary = headerRow("Class Skills"), headerRow("Secondary Skills")
      local weapons, languages = headerRow("Weapon Skills"), headerRow("Languages")
      local professions, swords = headerRow("Professions"), headerRow("Swords")
      assert.are.equal("クラススキル", class.Name:GetText())
      assert.are.equal("二次スキル", secondary.Name:GetText())
      assert.are.equal("武器スキル", weapons.Name:GetText())
      assert.are.equal("言語", languages.Name:GetText())
      assert.are.equal("Professions", professions.Name:GetText())
      assert.are.equal("Swords", swords.Name:GetText())
      alt(true)
      assert.are.equal("Class Skills", class.Name:GetText())
      alt(false)
      assert.are.equal("クラススキル", class.Name:GetText())
    end)

  it("the pane title stays English even when a SkillCategory row has its English", function()
    _G.SkillsFrame:Show()
    PS.selectSkill({ name = "Class Skills", description = "" })
    assert.are.equal("Class Skills", detail().Title:GetText())
    assert.are.equal(0, detail().Title.calls.SetText)
  end)
end)
