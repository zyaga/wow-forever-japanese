-- UI/SpellBookNames: the spellbook's spell names, and the words around them, in Japanese on the addon's own labels.
-- The game's text keeps its text and font; only its alpha is changed, and put back.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local PS = require("tests.lua.spec.stub_playerspells")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/SpellBookNames.lua"

local WFJ, SBN, log, pushed
local realFontString, realCreateFrame
local fitAt -- a label is cut short while its font is larger than this

-- what the client's FontString has and the stub's does not: alpha, line count, width, alignment, shadow
local function fuller(fs)
  fs.alpha, fs.alphaWrites, fs.numLines = 1, 0, 1
  function fs:GetAlpha() return self.alpha end
  function fs:SetAlpha(a)
    self.alphaWrites = self.alphaWrites + 1
    self.alpha = a
  end
  function fs:GetNumLines() return self.numLines end
  function fs:GetWidth() return self.width or 170 end
  function fs:GetJustifyH() return self.justifyH or "LEFT" end
  function fs:SetMaxLines(n) self.maxLines = n end
  function fs.GetShadowColor() return 0, 0, 0, 1 end
  function fs.GetShadowOffset() return 1, -1 end
  function fs:SetShadowColor(...) self.shadowColor = { ... } end
  function fs:SetShadowOffset(...) self.shadowOffset = { ... } end
  function fs:SetPoint(...)
    self.points = self.points or {}
    self.points[#self.points + 1] = { ... }
  end
  function fs:IsTruncated() return fitAt ~= nil and self.font.size > fitAt end
  return fs
end

local function book() return _G.PlayerSpellsFrame.SpellBookFrame end
local function pagedSpells() return book().PagedSpellsFrame end
local function items() return pagedSpells().frames end
local function alt(down)
  Stub.keys.alt = down
  WFJ.Modifier.refresh()
end

-- the stub's page made like the client's: an item's three lines inside TextContainer, every frame visible, and
-- paging controls that are a frame
local function page()
  for _, item in ipairs(items()) do
    if item.Name then
      item.TextContainer = item.TextContainer or { Name = item.Name, SubName = item.SubName,
        RequiredLevel = item.RequiredLevel, GetFrameLevel = function() return 7 end }
    end
    item.shown = true
  end
  local controls = pagedSpells().PagingControls
  controls.shown, controls.alpha = true, 1
  function controls:IsVisible() return self.shown end
  function controls:GetAlpha() return self.alpha end
end

-- `ui`: the dictionary rows of the run; `spells` and `order`: the book's spells and what the page lists
local function start(ui, spells, order)
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  realFontString, realCreateFrame = Stub.fontString, _G.CreateFrame
  Stub.fontString = function(...) return fuller(realFontString(...)) end
  _G.CreateFrame = function(...)
    local frame = realCreateFrame(...)
    function frame:SetAllPoints(rel) self.allPoints = rel or true end
    return frame
  end
  fitAt = nil
  Stub.installTooltipAPI()
  PS.install()
  WFJ = H.loadChunks(FILES)
  H.uiSetup(WFJ, ui)
  WFJ.Data.name = {
    [WFJ.Names.key("Fireball")] = "ファイアボール\tふぁいあぼーる",
    [WFJ.Names.key("Frost Armor")] = "フロスト・アーマー\tふろすと・あーまー",
    [WFJ.Names.key("Arms")] = "アームズ\tあーむず",
  }
  WFJ.State.setNames(true)
  log = WFJ.Diag.load(nil)
  pushed = {}
  WFJ.TaintWatch = { push = function(text) pushed[#pushed + 1] = text end }
  SBN = WFJ.SpellBookNames
  PS.loadPlayerSpells()
  PS.spells, PS.book, PS.perPage = spells, order, #order
  PS.openSpellBook()
  page()
end

local function stop()
  Stub.fontString, _G.CreateFrame = realFontString, realCreateFrame
  H.uiTeardown()
end

describe("spell names over the spellbook's own text", function()
  before_each(function()
    start({}, {
      [10] = { name = "Fireball", subtext = "Rank 3", cached = true },
      [11] = { name = "Frost Armor", subtext = "Rank 1", cached = true },
      [12] = { name = "Zzyzx Ward", subtext = "", cached = true }, -- no line in the name list
    }, { 10, 11, 12 })
  end)

  after_each(stop)

  it("a visible spell gets the addon's own label; the game's text, font and size are never written", function()
    assert.is_true(SBN.init())
    assert.are.equal(2, SBN.tick())
    local name = items()[1].Name
    local label = SBN.labelOf(name)
    assert.are.equal("ファイアボール", label:GetText())
    assert.is_true(label:IsShown())
    assert.are.equal(WFJ.Font.PATH, (label:GetFont()))
    assert.are.equal(select(2, name:GetFont()), select(2, label:GetFont())) -- the game's size
    assert.are.same({ "TOPLEFT", name, "TOPLEFT", 0, 0 }, label.points[1])
    assert.are.same({ "TOPRIGHT", name, "TOPRIGHT", 0, 0 }, label.points[2])
    -- the game's own name: the same text and font, no SetText and no SetFont from the addon, only its alpha
    assert.are.equal("Fireball", name:GetText())
    assert.are.equal("Fonts\\FRIZQT__.TTF", (name:GetFont()))
    assert.are.same({ 0, 0 }, { name.calls.SetText, name.calls.SetFont })
    assert.is_true(name:IsShown())
    assert.are.equal(0, name:GetAlpha())
    assert.are.equal(1, name.alphaWrites)
    -- the subtext line is the game's
    assert.are.equal("Rank 3", items()[1].SubName:GetText())
    assert.are.equal(0, items()[1].SubName.alphaWrites)
  end)

  it("the label is the addon's: on its own frame, never a region of the item or its text container", function()
    SBN.init()
    SBN.tick()
    local label = SBN.labelOf(items()[1].Name)
    local own = false
    for _, region in ipairs(SBN.driver.children) do own = own or region == label end
    assert.is_true(own)
    assert.are.equal(book(), SBN.driver.parent)
    assert.are.equal(8, SBN.driver:GetFrameLevel()) -- one above the items' text
    for _, item in ipairs(items()) do
      assert.are.equal(0, #item.children)
    end
  end)

  it("nothing is hooked on a spellbook frame or method, and no script is set on one", function()
    local host, paged = _G.PlayerSpellsFrame, book().PagedSpellsFrame
    local before = { book = book().scripts.OnShow, hide = book().scripts.OnHide, update = book().scripts.OnUpdate }
    local methods = {}
    for k, v in pairs(paged) do methods[k] = v end
    local mixin = {}
    for k, v in pairs(_G.SpellBookItemMixin) do mixin[k] = v end
    local hooks = {}
    for label, list in pairs(Stub.hooks) do hooks[label] = #list end
    SBN.init()
    SBN.tick()
    -- no hook was added anywhere: what the shared helpers hooked at load is all there is
    for label, list in pairs(Stub.hooks) do assert.are.equal(hooks[label], #list) end
    assert.are.equal(before.book, book().scripts.OnShow)
    assert.are.equal(before.hide, book().scripts.OnHide)
    assert.are.equal(before.update, book().scripts.OnUpdate)
    assert.is_nil(next(host.scripts))
    for k, v in pairs(paged) do assert.are.equal(methods[k], v) end
    for k, v in pairs(_G.SpellBookItemMixin) do assert.are.equal(mixin[k], v) end
    for _, item in ipairs(items()) do
      assert.is_nil(next(item.scripts))
      for k, v in pairs(mixin) do assert.are.equal(v, item[k]) end
    end
    -- the pass and the give-back are scripts of the addon's own frame
    assert.is_function(SBN.driver.scripts.OnUpdate)
    assert.is_function(SBN.driver.scripts.OnHide)
  end)

  it("a spell with no Japanese gets no label and its text stays visible", function()
    SBN.init()
    SBN.tick()
    local name = items()[3].Name
    assert.is_nil(SBN.labelOf(name))
    assert.are.equal("Zzyzx Ward", name:GetText())
    assert.are.equal(1, name:GetAlpha())
    assert.are.equal(0, name.alphaWrites)
  end)

  it("names off, translation off and the reveal key each hide the label and put the game's alpha back", function()
    SBN.init()
    local name = items()[1].Name
    name.alpha = 0.6 -- a spell not learned: the game's own dimming
    local function shownAgain()
      assert.are.equal(0, SBN.tick())
      assert.is_false(SBN.labelOf(name):IsShown())
      assert.are.equal(0.6, name:GetAlpha())
      assert.are.equal("Fireball", name:GetText())
    end
    local function hiddenAgain()
      assert.are.equal(2, SBN.tick())
      assert.are.equal(0, name:GetAlpha())
      assert.are.equal(0.6, SBN.labelOf(name).alpha) -- the label is dimmed as the game dimmed the name
    end
    hiddenAgain()
    WFJ.State.setNames(false)
    shownAgain()
    WFJ.State.setNames(true)
    hiddenAgain()
    WFJ.State.setEnabled(false)
    shownAgain()
    WFJ.State.setEnabled(true)
    hiddenAgain()
    alt(true)
    shownAgain()
    alt(false)
    hiddenAgain()
    assert.are.same({ 0, 0 }, { name.calls.SetText, name.calls.SetFont })
  end)

  it("a refill that shows the game's text again is followed: the new alpha is remembered and hidden again", function()
    SBN.init()
    SBN.tick()
    local name = items()[1].Name
    name.alpha = 0.6 -- UpdateVisuals wrote it
    SBN.tick()
    assert.are.equal(0, name:GetAlpha())
    SBN.restore()
    assert.are.equal(0.6, name:GetAlpha())
    -- the game's alpha written while the label was up is never overwritten by an older one
    SBN.tick()
    name.alpha = 1
    SBN.restore()
    assert.are.equal(1, name:GetAlpha())
  end)

  it("the book closing gives every name back; a spell that left the page gets its name back at once", function()
    SBN.init()
    SBN.tick()
    local first, second = items()[1].Name, items()[2].Name
    table.remove(items(), 2) -- handed back to its pool
    assert.are.equal(1, SBN.tick())
    assert.are.equal(1, second:GetAlpha())
    assert.is_false(SBN.labelOf(second):IsShown())
    SBN.driver.scripts.OnHide(SBN.driver)
    assert.are.equal(1, first:GetAlpha())
    assert.are.equal(0, SBN.count())
  end)

  it("a changed name on the same item is followed; a header, a hidden item and a secret text are left alone", function()
    SBN.init()
    SBN.tick()
    local item = items()[1]
    item.Name.text = "Frost Armor" -- the pool reused the item for another spell
    SBN.tick()
    assert.are.equal("フロスト・アーマー", SBN.labelOf(item.Name):GetText())
    item.Name.text = "Zzyzx Ward"
    SBN.tick()
    assert.is_false(SBN.labelOf(item.Name):IsShown())
    assert.are.equal(1, item.Name:GetAlpha())
    -- a header has no spell data; an item not visible is not read
    local header = { Name = fuller(realFontString("Fireball")), TextContainer = {} }
    header.IsVisible = function() return true end
    header.TextContainer.Name = header.Name
    table.insert(items(), header)
    items()[2].shown = false
    items()[2].Name.alpha = 1
    SBN.tick()
    assert.are.equal(0, header.Name.alphaWrites)
    assert.is_nil(SBN.labelOf(header.Name))
    assert.are.equal(1, items()[2].Name:GetAlpha())
    _G.issecretvalue = function(v) return v == "Fireball" end
    item.Name.text = "Fireball"
    SBN.tick()
    assert.are.equal(1, item.Name:GetAlpha())
    _G.issecretvalue = nil
  end)

  it("a long name is drawn smaller before it is cut short, in no more lines than the English takes", function()
    SBN.init()
    items()[1].Name.numLines = 2
    fitAt = 11
    SBN.tick()
    local label = SBN.labelOf(items()[1].Name)
    assert.are.equal(11, select(2, label:GetFont()))
    assert.are.equal(2, label.maxLines)
    fitAt = 1 -- never fits: the floor holds
    items()[1].Name.numLines = 1
    SBN.tick()
    assert.are.equal(SBN.MIN_SIZE, select(2, label:GetFont()))
  end)

  it("while the client refuses the bundled font the English stays; it is hidden once the label can show", function()
    SBN.init()
    Stub.fontSetFails = true
    assert.are.equal(0, SBN.tick())
    local name = items()[1].Name
    assert.are.equal(1, name:GetAlpha())
    assert.are.equal(0, name.alphaWrites)
    Stub.fontSetFails = false
    assert.are.equal(2, SBN.tick())
    assert.are.equal(0, name:GetAlpha())
  end)

  it("in combat an unprotected item is handled as out of combat; a protected one is not written at all", function()
    SBN.init()
    Stub.combat = true
    assert.are.equal(2, SBN.tick())
    assert.are.equal(0, items()[1].Name:GetAlpha())
    -- a protected item: hidden before the fight, it is neither hidden again nor given back until combat ends
    local item = items()[2]
    item.IsProtected = function() return true end
    local writes = item.Name.alphaWrites
    item.Name.alpha = 1 -- the game refilled it
    assert.are.equal(1, SBN.tick())
    assert.are.equal(1, item.Name:GetAlpha())
    item.Name.alpha = 0
    WFJ.State.setNames(false)
    SBN.tick()
    assert.are.equal(writes, item.Name.alphaWrites)
    Stub.combat = false
    SBN.tick()
    assert.are.equal(writes + 1, item.Name.alphaWrites)
  end)

  it("the first pass of a session is logged once, and each alpha write goes into the taint watch's events", function()
    SBN.init()
    SBN.tick()
    SBN.tick()
    local found = {}
    for _, e in ipairs(log.entries) do
      if e.kind == "spellbooknames" then found[#found + 1] = e end
    end
    assert.are.equal(1, #found)
    assert.are.equal(2, found[1].labels)
    assert.are.equal("alpha", found[1].property)
    assert.is_false(found[1].combat)
    assert.is_nil(found[1].n)
    assert.are.same({ "spellbooknames alpha 2" }, pushed)
    WFJ.State.setNames(false)
    SBN.tick()
    assert.are.same({ "spellbooknames alpha 2", "spellbooknames gave back 2" }, pushed)
  end)

  it("waits for Blizzard_PlayerSpells; one frame is made, and none before the book exists", function()
    Stub.loadedAddons["Blizzard_PlayerSpells"] = nil
    assert.is_false(SBN.init())
    assert.is_nil(SBN.driver)
    assert.are.equal(0, SBN.tick())
    Stub.loadedAddons["Blizzard_PlayerSpells"] = true
    assert.are.equal(1, WFJ.LoadOnDemand.loaded("Blizzard_PlayerSpells"))
    local driver = SBN.driver
    assert.is_table(driver)
    assert.is_false(SBN.setup())
    assert.are.equal(driver, SBN.driver)
  end)
end)

describe("the words around the spell names: subtext, level line, header, page number", function()
  local UI = {
    SPELL_PASSIVE = { "Passive", "パッシブ" }, TOOLTIP_TALENT_RANK_CURRENT_ONLY = { "Rank %d", "ランク %d" },
    ["SpellSubtext:5227"] = { "Racial Passive", "種族パッシブ" },
    SPELLBOOK_AVAILABLE_AT = { "Level %d", "レベル %d" }, SPELLBOOK_TRAINABLE = { "See your trainer", "トレーナーで習得" },
    PAGE_NUMBER = { "Page %d", "ページ %d" }, PAGE_NUMBER_WITH_MAX = { "Page %d/%d", "ページ %d/%d" },
    STAT_CATEGORY_GENERAL = { "General", "一般" }, PET = { "Pet", "ペット" },
    SPELLBOOK_SEARCH_HEADER_EXACT = { "Exact Matches", "完全一致" },
    CLOSE = { "Close", "閉じる" }, -- a dictionary word that is no line of the spellbook
  }
  local function pageText() return pagedSpells().PagingControls.PageText end
  local function texts() -- every text of the game on the page
    local out = { pageText() }
    for _, item in ipairs(items()) do
      for _, key in ipairs({ "Name", "SubName", "RequiredLevel", "Text" }) do out[#out + 1] = item[key] end
    end
    return out
  end

  before_each(function()
    start(UI, {
      [10] = { name = "Fireball", subtext = "Rank 3", cached = true, level = 20 },
      [11] = { name = "Frost Armor", subtext = "", passive = true, cached = true, trainable = true },
      [12] = { name = "Zzyzx Ward", subtext = "Racial Passive", cached = true },
      [13] = { name = "Prowl", subtext = "Cat", cached = true }, -- a form's name: no dictionary line
      [14] = { name = "Bash", subtext = "Close", cached = true }, -- a dictionary word, but no spellbook line
    }, { "General", 10, 11, "Arms", 12, 13, 14, "Zzyzx School" })
    pagedSpells().PagingControls.currentPage, pagedSpells().PagingControls.maxPages = 2, 3
    pagedSpells().PagingControls:UpdateControls()
  end)

  after_each(stop)

  it("a subtext and a level line show the dictionary's Japanese on the addon's own labels", function()
    SBN.init()
    SBN.tick()
    local fire, frost, ward = items()[2], items()[3], items()[5]
    assert.are.equal("ランク 3", SBN.labelOf(fire.SubName):GetText())
    assert.are.equal("レベル 20", SBN.labelOf(fire.RequiredLevel):GetText())
    assert.are.equal("パッシブ", SBN.labelOf(frost.SubName):GetText())
    assert.are.equal("トレーナーで習得", SBN.labelOf(frost.RequiredLevel):GetText())
    assert.are.equal("種族パッシブ", SBN.labelOf(ward.SubName):GetText())
    for _, fs in ipairs({ fire.SubName, fire.RequiredLevel, frost.SubName, frost.RequiredLevel, ward.SubName }) do
      local label = SBN.labelOf(fs)
      assert.is_true(label:IsShown())
      assert.are.equal(WFJ.Font.PATH, (label:GetFont()))
      assert.are.same({ "TOPLEFT", fs, "TOPLEFT", 0, 0 }, label.points[1])
      assert.are.equal(0, fs:GetAlpha())
      assert.are.equal(1, fs.alphaWrites)
      assert.is_true(fs:IsShown())
    end
    -- the game's own lines: what the game wrote, in the game's font
    assert.are.equal("Rank 3", fire.SubName:GetText())
    assert.are.equal("Level 20", fire.RequiredLevel:GetText())
    assert.are.equal("Fonts\\FRIZQT__.TTF", (fire.SubName:GetFont()))
  end)

  it("a header shows a dictionary word, or a skill line's name while names are on", function()
    SBN.init()
    SBN.tick()
    local general, arms = items()[1].Text, items()[4].Text
    assert.are.equal("一般", SBN.labelOf(general):GetText())
    assert.are.equal("アームズ", SBN.labelOf(arms):GetText())
    assert.are.same({ 0, 0 }, { general:GetAlpha(), arms:GetAlpha() })
    assert.are.equal("General", general:GetText())
    -- names off: the word stays Japanese, the name goes back to the game's English
    WFJ.State.setNames(false)
    SBN.tick()
    assert.is_true(SBN.labelOf(general):IsShown())
    assert.are.equal(0, general:GetAlpha())
    assert.is_false(SBN.labelOf(arms):IsShown())
    assert.are.equal(1, arms:GetAlpha())
    WFJ.State.setNames(true)
    SBN.tick()
    assert.is_true(SBN.labelOf(arms):IsShown())
    assert.are.equal(0, arms:GetAlpha())
  end)

  it("the page number keeps the game's numbers and its place against the arrows", function()
    SBN.init()
    SBN.tick()
    local fs = pageText()
    local label = SBN.labelOf(fs)
    assert.are.equal("Page 2/3", fs:GetText())
    assert.are.equal("ページ 2/3", label:GetText())
    assert.are.same({ { "RIGHT", fs, "RIGHT", 0, 0 } }, label.points)
    assert.is_false(label.wordWrap)
    assert.are.equal(0, fs:GetAlpha())
    -- a page turn: the game writes the text again, and the label follows it
    pagedSpells().PagingControls.currentPage = 3
    pagedSpells().PagingControls:UpdateControls()
    SBN.tick()
    assert.are.equal("ページ 3/3", label:GetText())
    assert.are.equal("Page 3/3", fs:GetText())
    -- controls the game hides get their text back
    pagedSpells().PagingControls.alpha = 0
    SBN.tick()
    assert.is_false(label:IsShown())
    assert.are.equal(1, fs:GetAlpha())
  end)

  it("a text with no Japanese keeps the game's text visible and gets no label", function()
    SBN.init()
    SBN.tick()
    local cat, close, school = items()[6].SubName, items()[7].SubName, items()[8].Text
    for _, fs in ipairs({ cat, close, school, items()[5].RequiredLevel }) do
      assert.is_nil(SBN.labelOf(fs))
      assert.are.equal(1, fs:GetAlpha())
      assert.are.equal(0, fs.alphaWrites)
    end
    assert.are.equal("Close", close:GetText())
    -- a line the game hid is not covered, whatever text it still holds
    local level = items()[2].RequiredLevel
    level.shown = false
    SBN.tick()
    assert.is_false(SBN.labelOf(level):IsShown())
    assert.are.equal(1, level:GetAlpha())
  end)

  it("SetText and SetFont are never called on a text of the game, and nothing is hooked or scripted", function()
    local controls = pagedSpells().PagingControls
    local update = controls.UpdateControls
    local hooks = {}
    for label, list in pairs(Stub.hooks) do hooks[label] = #list end
    SBN.init()
    SBN.tick()
    WFJ.State.setNames(false)
    SBN.tick()
    alt(true)
    SBN.tick()
    alt(false)
    SBN.tick()
    for _, fs in ipairs(texts()) do
      assert.are.same({ 0, 0 }, { fs.calls.SetText, fs.calls.SetFont })
    end
    for label, list in pairs(Stub.hooks) do assert.are.equal(hooks[label], #list) end
    assert.are.equal(update, controls.UpdateControls)
    assert.is_nil(controls.scripts)
    for _, item in ipairs(items()) do
      assert.is_nil(next(item.scripts))
      assert.are.equal(0, #item.children)
    end
  end)

  it("translation off and the reveal key give every text back; names off gives back only the names", function()
    SBN.init()
    items()[2].SubName.alpha = 0.6 -- a spell not learned: the game's own dimming
    local function covered()
      local n = 0
      for _, fs in ipairs(texts()) do
        if fs:GetAlpha() == 0 then n = n + 1 end
      end
      return n
    end
    -- 2 names, 3 subtexts, 2 level lines, 2 headers, the page number
    assert.are.equal(10, SBN.tick())
    assert.are.equal(10, covered())
    assert.are.equal(0.6, SBN.labelOf(items()[2].SubName).alpha)
    WFJ.State.setEnabled(false)
    assert.are.equal(0, SBN.tick())
    assert.are.equal(0, covered())
    assert.are.equal(0.6, items()[2].SubName:GetAlpha())
    assert.are.equal(0, SBN.count())
    WFJ.State.setEnabled(true)
    assert.are.equal(10, SBN.tick())
    alt(true)
    assert.are.equal(0, SBN.tick())
    assert.are.equal(0, covered())
    alt(false)
    assert.are.equal(10, SBN.tick())
    WFJ.State.setNames(false)
    assert.are.equal(7, SBN.tick()) -- the words stay: the dictionary's text does not wait for the names setting
    assert.are.equal(7, covered())
    assert.are.equal(1, items()[2].Name:GetAlpha())
    WFJ.State.setNames(true)
    assert.are.equal(10, SBN.tick())
    SBN.driver.scripts.OnHide(SBN.driver) -- the book closes
    assert.are.equal(0, covered())
    assert.are.equal(0, SBN.count())
  end)

  it("a pass over an unchanged page looks nothing up and writes nothing", function()
    SBN.init()
    SBN.tick()
    local lookups, real, realItem = 0, WFJ.UIIndex.matchOnly, WFJ.Names.item
    WFJ.UIIndex.matchOnly = function(...)
      lookups = lookups + 1
      return real(...)
    end
    WFJ.Names.item = function(...)
      lookups = lookups + 1
      return realItem(...)
    end
    local writes = {}
    for i, fs in ipairs(texts()) do writes[i] = fs.alphaWrites end
    local labelWrites = SBN.labelOf(pageText()).calls.SetText
    pushed = {}
    SBN.tick()
    SBN.tick()
    assert.are.equal(0, lookups)
    for i, fs in ipairs(texts()) do assert.are.equal(writes[i], fs.alphaWrites) end
    assert.are.equal(labelWrites, SBN.labelOf(pageText()).calls.SetText)
    assert.are.same({}, pushed)
    -- one text changes: one lookup
    items()[2].SubName.text = "Rank 4"
    SBN.tick()
    assert.are.equal(1, lookups)
    assert.are.equal("ランク 4", SBN.labelOf(items()[2].SubName):GetText())
    WFJ.Names.item = realItem
  end)

  it("the first pass is logged with the labels of each kind", function()
    SBN.init()
    SBN.tick()
    local found
    for _, e in ipairs(log.entries) do
      if e.kind == "spellbooknames" then found = e end
    end
    assert.are.same({ 10, 2, 3, 2, 2, 1 },
      { found.labels, found.names, found.subtexts, found.levels, found.headers, found.pages })
    assert.are.equal("alpha", found.property)
    assert.are.same({ "spellbooknames alpha 10" }, pushed)
  end)
end)
