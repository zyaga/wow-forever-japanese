-- The professions window's overview page on the Forever (camelot) client: UI/Professions.lua over a
-- ProfessionsFrame replayed from the extracted 1.60.1 source: blizzard_professions/camelot/blizzard_professionsframe
-- .xml|lua (BookPage, the overview side tab, SelectBookPage → SetTitleFormatted(TRADE_SKILL_TITLE, TRADE_SKILLS)),
-- blizzard_professionsbook/camelot/blizzard_professionsbooktemplates.xml (the five slots and their "missing" words)
-- and camelot/blizzard_professionsbook.lua (FormatProfession, the unlearn tooltip). camelot builds no standalone
-- ProfessionsBookFrame; both addons are load-on-demand. Profession names stay English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Professions.lua"

local FRAME_ADDON, BOOK_ADDON = "Blizzard_Professions", "Blizzard_ProfessionsBook"

local UI = {
  TRADE_SKILLS = { "Professions", "専門技術" },
  GUILD_TRADE_SKILL_TITLE = { "Guild %s", "ギルドの%s" },
  PROFESSIONS_FIRST_PROFESSION = { "First Profession", "第1専門技術" },
  PROFESSIONS_SECOND_PROFESSION = { "Second Profession", "第2専門技術" },
  PROFESSIONS_MISSING_PROFESSION = { "Visit a profession trainer in a major city to learn a new profession.",
    "主要都市の専門技術トレーナーを訪ねると、新しい専門技術を習得できます。" },
  PROFESSIONS_COOKING_MISSING = { "Visit a trainer to learn cooking.", "トレーナーを訪ねてCookingを習得しましょう。" },
  PROFESSIONS_FISHING_MISSING = { "Visit a trainer to learn fishing.", "トレーナーを訪ねてFishingを習得しましょう。" },
  PROFESSIONS_FIRST_AID_MISSING = { "Visit a trainer to learn first aid.",
    "トレーナーを訪ねてFirst Aidを習得しましょう。" },
  UNLEARN_SKILL_TOOLTIP = { "Unlearn this profession.", "この専門技術を忘れる。" },
  -- profession names that are also dictionary words here: they must stay English wherever they appear
  PROFESSIONS_COOKING = { "Cooking", "料理" }, MINING = { "Mining", "採掘" },
}

local function en(key) return _G[key] end
local function fs(text) return Stub.fontString(text or "") end

-- A PortraitFrameTemplate: SetTitle / SetTitleFormatted both write TitleContainer.TitleText directly
-- (blizzard_sharedxml/portraitframe.lua:11–17).
local function titled(f)
  f.TitleContainer = { TitleText = fs("") }
  function f.SetTitle(self, t) self.TitleContainer.TitleText.text = t end
  function f.SetTitleFormatted(self, fmt, ...) self.TitleContainer.TitleText.text = fmt:format(...) end
end

local function hover(owner, text)
  owner:SetScript("OnEnter", function(self)
    local tt = _G.GameTooltip
    tt:SetOwner(self, "ANCHOR_RIGHT")
    tt:ClearLines()
    tt:SetText(text(self))
    tt:Show()
  end)
end

-- One slot of the camelot book templates (xml:4–111, 113–186): the XML text and the inline OnLoad writes.
local function slot(parent, primary, header, missing)
  local f = CreateFrame("Frame", nil, parent)
  f.isPrimary = primary
  f.ProfessionName = fs(en("TRADE_SKILLS")) -- text="TRADE_SKILLS" until FormatProfession writes the name or ""
  f.specialization = fs("")
  f.missingHeader, f.missingText = fs(header), fs(missing)
  if primary then
    f.UnlearnButton = CreateFrame("Button", nil, f)
    hover(f.UnlearnButton, function() return en("UNLEARN_SKILL_TOOLTIP") end)
  end
  return f
end

local function bookContent(host)
  local c = CreateFrame("Frame", nil, host)
  host.ProfessionsContentFrame = c
  c.PrimaryProfession1 = slot(c, true, en("PROFESSIONS_FIRST_PROFESSION"), en("PROFESSIONS_MISSING_PROFESSION"))
  c.PrimaryProfession2 = slot(c, true, en("PROFESSIONS_SECOND_PROFESSION"), en("PROFESSIONS_MISSING_PROFESSION"))
  c.SecondaryProfession1 = slot(c, false, "Cooking", en("PROFESSIONS_COOKING_MISSING"))
  c.SecondaryProfession2 = slot(c, false, "Fishing", en("PROFESSIONS_FISHING_MISSING"))
  c.SecondaryProfession3 = slot(c, false, "First Aid", en("PROFESSIONS_FIRST_AID_MISSING"))
  -- ProfessionsBookFrameMixin:FormatProfession (camelot/blizzard_professionsbook.lua:45–143)
  function host.FormatProfession(_, f, name) f.ProfessionName.text = name or "" end
end

-- `known` = { PrimaryProfession1 = "Mining", … }: the professions the character has
local function loadProfessions(known)
  Stub.loadedAddons[BOOK_ADDON] = true -- a dependency of Blizzard_Professions: always loaded first
  Stub.loadedAddons[FRAME_ADDON] = true
  local frame = CreateFrame("Frame", "ProfessionsFrame")
  titled(frame)
  frame.BookPage = CreateFrame("Frame", nil, frame)
  frame.CraftingPage = CreateFrame("Frame", nil, frame)
  bookContent(frame.BookPage)
  frame.BookPage:SetScript("OnShow", function(self) -- ProfessionsBookFrameMixin:OnShow → Update
    for name, f in pairs(self.ProfessionsContentFrame) do
      if type(f) == "table" and f.missingHeader then self:FormatProfession(f, (known or {})[name]) end
    end
  end)
  frame.ProfessionsOverviewTab = CreateFrame("Frame", nil, frame)
  frame.ProfessionsOverviewTab.tooltipText = en("TRADE_SKILLS")
  hover(frame.ProfessionsOverviewTab, function(self) return self.tooltipText end)
  frame.Professions1Tab = CreateFrame("Frame", nil, frame)
  frame.Professions1Tab.tooltipText = "Cooking" -- RefreshRightTab: the profession's name
  hover(frame.Professions1Tab, function(self) return self.tooltipText end)
  function frame.SelectBookPage(self) -- camelot/blizzard_professionsframe.lua:91–99
    self.CraftingPage:Hide()
    self.BookPage:Show()
    self:SetTitleFormatted(en("TRADE_SKILL_TITLE") or "%s", en("TRADE_SKILLS"))
  end
  function frame.SelectProfession(self, name) -- the crafting page: SetTitle(professionName)
    self.BookPage:Hide()
    self.CraftingPage:Show()
    self:SetTitle(name)
  end
  return frame
end

describe("the professions window on the Forever client", function()
  local WFJ, SS

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function title() return _G.ProfessionsFrame.TitleContainer.TitleText end
  local function content() return _G.ProfessionsFrame.BookPage.ProfessionsContentFrame end
  local function left(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
  local function open() -- ToggleProfessionsBook: ShowProfessionsFrame, then SelectBookPage
    _G.ProfessionsFrame:Show()
    _G.ProfessionsFrame:SelectBookPage()
  end

  local function setup(loadedFirst, known, shape)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    if loadedFirst then
      local frame = loadProfessions(known)
      if shape then shape(frame) end
      assert.is_true(WFJ.Professions.init())
    else
      assert.is_false(WFJ.Professions.init()) -- waits for both addons
      local frame = loadProfessions(known)
      if shape then shape(frame) end
      WFJ.LoadOnDemand.loaded(BOOK_ADDON) -- camelot builds no standalone book: nothing to set up
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(FRAME_ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.ProfessionsFrame, _G.ProfessionsBookFrame = nil, nil
  end)

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    describe("Blizzard_Professions " .. order[2], function()
      before_each(function() setup(order[1], { PrimaryProfession1 = "Mining", SecondaryProfession1 = "Cooking" }) end)

      it("the window title renders after SetTitleFormatted, keeps it on a second write, and follows Alt", function()
        open()
        assert.are.equal("専門技術", title():GetText())
        assert.are.equal(WFJ.Font.PATH, (title():GetFont()))
        _G.ProfessionsFrame:SelectBookPage() -- a second write
        assert.are.equal("専門技術", title():GetText())
        _G.ProfessionsFrame:SetTitle(_G.TRADE_SKILLS) -- the SetTitle form
        assert.are.equal("専門技術", title():GetText())
        alt(true)
        assert.are.equal("Professions", title():GetText())
        alt(false)
        assert.are.equal("専門技術", title():GetText())
      end)

      it("a guild's profession view title 'Guild <profession>' is Japanese, the name kept", function()
        open()
        _G.ProfessionsFrame:SetTitleFormatted(_G.GUILD_TRADE_SKILL_TITLE, "Mining") -- blizzard_professionsframe.lua:253
        assert.are.equal("ギルドのMining", title():GetText())
        alt(true)
        assert.are.equal("Guild Mining", title():GetText())
        alt(false)
      end)

      it("the crafting page's title is the profession's name: English, even when it is a dictionary word", function()
        open()
        _G.ProfessionsFrame:SelectProfession("Mining")
        assert.are.equal("Mining", title():GetText())
        assert.are.equal(0, SS.count("professions"))
        _G.ProfessionsFrame:SelectBookPage()
        assert.are.equal("専門技術", title():GetText())
      end)

      it("the empty slots' headers and help texts render; profession names stay English", function()
        open()
        local c = content()
        assert.are.equal("第2専門技術", c.PrimaryProfession2.missingHeader:GetText())
        assert.are.equal("主要都市の専門技術トレーナーを訪ねると、新しい専門技術を習得できます。",
          c.PrimaryProfession2.missingText:GetText())
        assert.are.equal("第1専門技術", c.PrimaryProfession1.missingHeader:GetText()) -- hidden, still a label
        assert.are.equal("トレーナーを訪ねてFishingを習得しましょう。", c.SecondaryProfession2.missingText:GetText())
        assert.are.equal("トレーナーを訪ねてFirst Aidを習得しましょう。", c.SecondaryProfession3.missingText:GetText())
        -- names: a learned profession, and the secondary slots' headers (PROFESSIONS_COOKING is a profession name)
        assert.are.equal("Mining", c.PrimaryProfession1.ProfessionName:GetText())
        assert.are.equal(0, c.PrimaryProfession1.ProfessionName.calls.SetText)
        assert.is_true(WFJ.Labels.forbidden(c.PrimaryProfession1.ProfessionName))
        assert.is_true(WFJ.Labels.forbidden(c.SecondaryProfession1.specialization))
        assert.are.equal("Cooking", c.SecondaryProfession1.missingHeader:GetText())
        assert.are.equal("Cooking", c.SecondaryProfession1.ProfessionName:GetText())
        assert.are.equal("Fishing", c.SecondaryProfession2.missingHeader:GetText())
      end)

      it("the page's words are released when it hides and come back when it is shown; the title goes with the"
        .. " window", function()
        open()
        _G.ProfessionsFrame:SelectProfession("Mining") -- the book page hides
        assert.are.equal("Second Profession", content().PrimaryProfession2.missingHeader:GetText())
        assert.are.equal(0, SS.count("professions.book"))
        _G.ProfessionsFrame:SelectBookPage()
        assert.are.equal("第2専門技術", content().PrimaryProfession2.missingHeader:GetText())
        _G.ProfessionsFrame:Hide()
        assert.are.equal("Professions", title():GetText())
        assert.are.equal(0, SS.count("professions") + SS.count("professions.book"))
        _G.ProfessionsFrame:Show() -- ToggleFrame on a loaded window: no SelectBookPage runs
        assert.are.equal("専門技術", title():GetText())
        assert.are.equal("第2専門技術", content().PrimaryProfession2.missingHeader:GetText())
      end)

      it("the unlearn button's and the overview tab's tooltips translate; a profession tab's tooltip (its name)"
        .. " does not", function()
        open()
        local unlearn = content().PrimaryProfession1.UnlearnButton
        unlearn.scripts.OnEnter(unlearn)
        assert.are.equal("この専門技術を忘れる。", left(1))
        local tab = _G.ProfessionsFrame.ProfessionsOverviewTab
        tab.scripts.OnEnter(tab)
        assert.are.equal("専門技術", left(1))
        local cooking = _G.ProfessionsFrame.Professions1Tab
        cooking.scripts.OnEnter(cooking)
        assert.are.equal("Cooking", left(1))
        assert.is_false(WFJ.HelpTooltip.registered(cooking))
      end)

      it("hooks install once", function()
        assert.is_false(WFJ.Professions.setupFrame())
        assert.are.equal(1, #Stub.hooks["ProfessionsFrame:SetTitleFormatted"])
        open()
        open()
        assert.are.equal(1, #Stub.hooks["ProfessionsFrame:SetTitle"])
      end)
    end)
  end

  it("a client that builds the standalone book (Blizzard_ProfessionsBook.xml): its SetTitle(TRADE_SKILLS) title and"
    .. " its slots render, in the on-demand order", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    assert.is_false(WFJ.Professions.init())
    Stub.loadedAddons[BOOK_ADDON] = true
    local book = CreateFrame("Frame", "ProfessionsBookFrame")
    titled(book)
    bookContent(book)
    book:SetTitle(_G.TRADE_SKILLS) -- ProfessionsBookFrameStandaloneMixin:OnLoad
    assert.are.equal(1, WFJ.LoadOnDemand.loaded(BOOK_ADDON))
    assert.are.equal("専門技術", book.TitleContainer.TitleText:GetText())
    book:SetTitle(_G.TRADE_SKILLS)
    assert.are.equal("専門技術", book.TitleContainer.TitleText:GetText())
    book:Show()
    assert.are.equal("第1専門技術", book.ProfessionsContentFrame.PrimaryProfession1.missingHeader:GetText())
    book:Hide()
    assert.are.equal("Professions", book.TitleContainer.TitleText:GetText())
    assert.are.equal("First Profession", book.ProfessionsContentFrame.PrimaryProfession1.missingHeader:GetText())
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    assert.has_no.errors(function()
      setup(true, nil, function(frame)
        frame.BookPage.ProfessionsContentFrame.PrimaryProfession1 = "moved"
        frame.BookPage.ProfessionsContentFrame.PrimaryProfession2.missingHeader = "moved"
        frame.ProfessionsOverviewTab = "moved"
        frame.TitleContainer = "moved" -- no title widget: the client's own writers are stubbed out with it
        frame.SetTitle, frame.SetTitleFormatted = function() end, function() end
      end)
      open()
      _G.ProfessionsFrame:Hide()
    end)
    assert.are.equal(0, WFJ.Professions.showFrameTitle())
    local c = _G.ProfessionsFrame.BookPage.ProfessionsContentFrame
    _G.ProfessionsFrame:SelectBookPage()
    assert.are.equal("トレーナーを訪ねてFishingを習得しましょう。", c.SecondaryProfession2.missingText:GetText())
    assert.are.equal("主要都市の専門技術トレーナーを訪ねると、新しい専門技術を習得できます。",
      c.PrimaryProfession2.missingText:GetText()) -- the slot with a moved header keeps its other label
    _G.ProfessionsFrame = nil
    assert.has_no.errors(function()
      setup(true, nil, function(frame) frame.BookPage = "moved"; frame.SetTitleFormatted = "moved" end)
      _G.ProfessionsFrame:Show()
    end)
    assert.is_nil(Stub.hooks["ProfessionsFrame:SetTitleFormatted"])
    _G.ProfessionsFrame = "moved"
    Stub.loadedAddons[FRAME_ADDON] = true
    assert.has_no.errors(function() assert.is_false(WFJ.Professions.setupFrame()) end)
  end)

  it("without the frame init returns false and touches nothing", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    assert.is_false(WFJ.Professions.init())
    assert.is_false(WFJ.Professions.setupFrame())
    assert.is_false(WFJ.Professions.setupBook())
    assert.are.equal(0, WFJ.SurfaceState.count("professions"))
    assert.is_nil(Stub.hooks["ProfessionsFrame:SetTitleFormatted"])
  end)
end)
