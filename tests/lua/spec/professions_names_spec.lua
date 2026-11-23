-- UI/Professions: the names in the professions window while Japanese names are on. Each slot's ProfessionName
-- (written by FormatProfession from ProfessionsBookFrameMixin:Update, camelot/blizzard_professionsbook.lua:22–28,
-- 43–137) and the crafting page's title (SetTitle(professionName)) show the profession's Japanese. The spell
-- buttons' labels stay English: each is a secure button whose click casts (ProfessionButtonTemplate inherits
-- SecureFrameTemplate, blizzard_professionsbooktemplates.xml:4; OnClick → C_SpellBook.CastSpellBookItem,
-- blizzard_professionsbook.lua:317–352).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Professions.lua"

local FRAME_ADDON, BOOK_ADDON = "Blizzard_Professions", "Blizzard_ProfessionsBook"
local UI = { TRADE_SKILLS = { "Professions", "専門技能" } }
local SLOTS = { "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1", "SecondaryProfession2",
  "SecondaryProfession3" }

describe("the professions window's names", function()
  local WFJ, frame, known

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end
  local function slot(name) return frame.BookPage.ProfessionsContentFrame[name] end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    WFJ.Data.add("name", {
      [WFJ.Names.key("Blacksmithing")] = "ブラックスミシング\tぶらっくすみしんぐ",
      [WFJ.Names.key("Mining")] = "マイニング\tまいにんぐ",
      [WFJ.Names.key("Smelting")] = "スメルティング\tすめるてぃんぐ",
    })
    WFJ.State.setNames(true)
    Stub.loadedAddons[BOOK_ADDON], Stub.loadedAddons[FRAME_ADDON] = true, true
    frame = CreateFrame("Frame", "ProfessionsFrame")
    frame.TitleContainer = { TitleText = Stub.fontString("") }
    function frame.SetTitle(self, t) self.TitleContainer.TitleText.text = t end
    function frame.SetTitleFormatted(self, fmt, ...) self.TitleContainer.TitleText.text = fmt:format(...) end
    local page = CreateFrame("Frame", nil, frame)
    frame.BookPage = page
    local content = CreateFrame("Frame", nil, page)
    page.ProfessionsContentFrame = content
    for _, name in ipairs(SLOTS) do
      local f = CreateFrame("Frame", nil, content)
      f.ProfessionName, f.specialization = Stub.fontString(_G.TRADE_SKILLS), Stub.fontString("")
      f.missingHeader, f.missingText = Stub.fontString(""), Stub.fontString("")
      f.SpellButton1 = CreateFrame("CheckButton", nil, f)
      f.SpellButton1.spellString, f.SpellButton1.subSpellString = Stub.fontString(""), Stub.fontString("")
      f.StatusBar = { Rank = { Text = Stub.fontString("") } }
      content[name] = f
    end
    -- the crafting page's rank bar: ProfessionsRankBarMixin:Update writes TRADESKILL_NAME_RANK into Rank.Text
    -- [verified: blizzard_professionstemplates/blizzard_professionsrankbar.lua:6–21, 141–143]
    frame.CraftingPage = CreateFrame("Frame", nil, frame)
    frame.CraftingPage.RankBar = { Rank = { Text = Stub.fontString("") } }
    function frame.CraftingPage.RankBar.Update(self, info)
      self.Rank.Text.text = ("%s %d/%d"):format(info.professionName, info.skillLevel, info.maxSkillLevel)
    end
    known = { PrimaryProfession1 = { "Blacksmithing", 135, 150, "Smelting", "Journeyman" } }
    -- FormatProfession: the name, the rank bar (TRADESKILL_NAME_RANK), the spell button's label and its subtext
    function page.FormatProfession(_, f, info)
      f.ProfessionName.text = info and info[1] or ""
      f.StatusBar.Rank.Text.text = info and ("%s %d/%d"):format(info[1], info[2], info[3]) or ""
      f.SpellButton1.spellString.text = info and info[4] or ""
      f.SpellButton1.subSpellString.text = info and info[5] or ""
    end
    function page.Update(self)
      for _, name in ipairs(SLOTS) do self:FormatProfession(content[name], known[name]) end
    end
    page:SetScript("OnShow", function(self) self:Update() end)
    function frame.SelectBookPage(self)
      self.BookPage:Show()
      self:SetTitleFormatted("%s", _G.TRADE_SKILLS)
    end
    function frame.SelectProfession(self, name)
      self.BookPage:Hide()
      self:SetTitle(name)
    end
    assert.is_true(WFJ.Professions.init())
    frame:Show()
    frame:SelectBookPage()
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.ProfessionsFrame = nil
  end)

  it("a learned profession's name shows its Japanese; the reveal key and the page closing give it back", function()
    local name = slot("PrimaryProfession1").ProfessionName
    assert.are.equal("ブラックスミシング", name:GetText())
    alt(true)
    assert.are.equal("Blacksmithing", name:GetText())
    alt(false)
    assert.are.equal("ブラックスミシング", name:GetText())
    frame.BookPage:Hide()
    assert.are.equal("Blacksmithing", name:GetText())
  end)

  it("a later update (a skill learned) shows the new name", function()
    known.PrimaryProfession2 = { "Mining", 1, 75, "Find Minerals", "Apprentice" }
    frame.BookPage:Update()
    assert.are.equal("マイニング", slot("PrimaryProfession2").ProfessionName:GetText())
    assert.are.equal("ブラックスミシング", slot("PrimaryProfession1").ProfessionName:GetText())
  end)

  it("an empty slot, the spell button's label and its rank word stay as written", function()
    local f = slot("PrimaryProfession1")
    assert.are.equal("", slot("SecondaryProfession1").ProfessionName:GetText())
    assert.are.equal("Smelting", f.SpellButton1.spellString:GetText())
    assert.are.equal("Journeyman", f.SpellButton1.subSpellString:GetText())
    assert.are.equal(0, f.SpellButton1.spellString.calls.addonSetText)
    assert.are.equal(0, slot("SecondaryProfession1").StatusBar.Rank.Text.calls.addonSetText)
  end)

  it("a slot's rank bar shows the name in Japanese and the numbers as written", function()
    local rank = slot("PrimaryProfession1").StatusBar.Rank.Text
    assert.are.equal("ブラックスミシング 135/150", rank:GetText())
    alt(true)
    assert.are.equal("Blacksmithing 135/150", rank:GetText())
    alt(false)
    known.PrimaryProfession1[2] = 136
    frame.BookPage:Update()
    assert.are.equal("ブラックスミシング 136/150", rank:GetText())
    frame.BookPage:Hide()
    assert.are.equal("Blacksmithing 136/150", rank:GetText())
  end)

  it("the crafting page's rank bar shows the name in Japanese after each Update, and English when the window closes",
    function()
      local bar = frame.CraftingPage.RankBar
      bar:Update({ professionName = "Mining", skillLevel = 20, maxSkillLevel = 75 })
      assert.are.equal("マイニング 20/75", bar.Rank.Text:GetText())
      bar:Update({ professionName = "Nobody Known Craft", skillLevel = 1, maxSkillLevel = 75 })
      assert.are.equal("Nobody Known Craft 1/75", bar.Rank.Text:GetText())
      bar:Update({ professionName = "Mining", skillLevel = 21, maxSkillLevel = 75 })
      assert.are.equal("マイニング 21/75", bar.Rank.Text:GetText())
      frame:Hide()
      assert.are.equal("Mining 21/75", bar.Rank.Text:GetText())
    end)

  it("with names off the names are never written", function()
    WFJ.State.setNames(false)
    frame.BookPage:Update()
    assert.are.equal("Blacksmithing", slot("PrimaryProfession1").ProfessionName:GetText())
  end)

  it("the crafting page's title is the profession's name in Japanese; the book page's is still a word", function()
    local title = frame.TitleContainer.TitleText
    assert.are.equal("専門技能", title:GetText())
    frame:SelectProfession("Blacksmithing")
    assert.are.equal("ブラックスミシング", title:GetText())
    alt(true)
    assert.are.equal("Blacksmithing", title:GetText())
    alt(false)
    frame:SelectBookPage()
    assert.are.equal("専門技能", title:GetText())
    frame:SelectProfession("Nobody Known Craft")
    assert.are.equal("Nobody Known Craft", title:GetText())
  end)
end)
