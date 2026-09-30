-- The shared spell / talent search on Forever: UI/SpellSearch.lua over the three hosts of
-- SpellSearchPreviewContainerTemplate: PlayerSpellsFrame.TalentsFrame and .SpellBookFrame (Blizzard_PlayerSpells) and
-- the Legacy tree (Blizzard_LegacySystem, stub_legacy.lua), replayed from blizzard_spellsearch/
-- blizzard_spellsearchtemplates.lua:94–183 and blizzard_sharedtalentui/blizzard_sharedtalentbuttontemplates.lua:10–37.
-- Result names (spells, talents) stay English; each host waits for its own addon in either load order.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local L = require("tests.lua.spec.stub_legacy")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/SpellSearch.lua"

local PLAYER_SPELLS = "Blizzard_PlayerSpells"

local UI = {
  TALENT_FRAME_SEARCH_PREVIEW_OVERFLOW_FORMAT = { "And %s more", "他%s件" },
  TALENT_FRAME_SEARCH_NOT_ON_ACTIONBAR = { "Missing from action bar", "アクションバーに未登録" },
  TALENT_FRAME_SEARCH_TOOLTIP_MATCH = { "Search match", "検索に一致" },
  TALENT_FRAME_SEARCH_TOOLTIP_EXACT_MATCH = { "Exact search match", "検索に完全一致" },
  TALENT_FRAME_SEARCH_TOOLTIP_NOT_ON_ACTIONBAR = { "Not on action bar", "アクションバーにありません" },
  SEARCH = { "Search", "検索" }, SPELLBOOK_SEARCH_INSTRUCTIONS = { "Search spells", "呪文を検索" },
  CLOSE = { "Close", "閉じる" }, -- a word a spell's name may happen to be
  -- the Legacy stub's labels (English only matters here)
  LEGACY_REWARD_TRACK_TAB_TOOLTIP = { "Legacy Rewards", "" },
  LEGACY_CHALLENGE_TAB_TOOLTIP = { "Legacy Challenges", "" },
  LEGACY_TREE_TAB_TOOLTIP = { "Legacy Trees", "" }, LEGACY_REWARD_TRACK_POINTS = { "Legacy Points", "" },
  LEGACY_TRACK_FRAME_TITLE = { "Progress Track", "" }, LEGACY_NO_CHALLENGES = { "No results.", "" },
  FILTER = { "Filter", "" }, LEGACY_POINTS_CURR_MAX = { "Legacy Points %d / %d", "" },
  TALENT_FRAME_APPLY_BUTTON_TEXT = { "Apply Changes", "" }, LEGACY_TREE_PROFESSIONS = { "Professions", "" },
  LEGACY_TREE_ADVENTURE = { "Adventure", "" }, LEGACY_TREE_PROGRESSION = { "Resourcefulness", "" },
  LEGACY_POINTS_AVAILABLE = { "Available points: %s", "" }, LEGACY_POINTS_AMOUNT = { "%d", "" },
  LEGACY_POINTS_SEASONAL_CAP = { "Cap %d", "" },
}

-- PlayerSpellsFrame with a talent tree and a spellbook, each owning a search box and a preview container.
local function loadPlayerSpells()
  local f = CreateFrame("Frame", "PlayerSpellsFrame")
  f.TalentsFrame = L.talentTree(CreateFrame("Frame"))
  f.TalentsFrame.name = "TalentsFrame"
  f.TalentsFrame.SearchPreviewContainer:AddSuggestedResult(_G.TALENT_FRAME_SEARCH_NOT_ON_ACTIONBAR)
  local book = CreateFrame("Frame")
  book.name = "SpellBookFrame"
  f.SpellBookFrame = book
  book.SearchBox = CreateFrame("EditBox")
  book.SearchBox.Instructions = Stub.fontString(_G.SPELLBOOK_SEARCH_INSTRUCTIONS)
  book.SearchPreviewContainer = L.previewContainer()
  Stub.loadedAddons[PLAYER_SPELLS] = true
  return f
end

local STATE = { points = 1, max = 2, available = 3, cap = 4 }
local RESULTS = { { name = "Close" }, { name = "Fireball" }, { name = "Frostbolt" }, { name = "Blink" } }

describe("the shared spell search on Forever", function()
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

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
  end

  local function setup(loadedFirst)
    load()
    if loadedFirst then
      loadPlayerSpells()
      L.load(STATE)
      assert.is_true(WFJ.SpellSearch.init())
    else
      assert.is_false(WFJ.SpellSearch.init()) -- waits for both addons
      loadPlayerSpells()
      assert.are.equal(2, WFJ.LoadOnDemand.loaded(PLAYER_SPELLS)) -- the talent tree and the spellbook
      L.load(STATE)
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(L.ADDON))
    end
  end

  local function suggested(container)
    local out = {}
    for b in container.suggestedResultButtonsPool:EnumerateActive() do out[#out + 1] = b.Text:GetText() end
    return out
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    L.unload()
    _G.PlayerSpellsFrame = nil
  end)

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    describe("the host addons " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("the overflow line is Japanese on every host; result names are never touched", function()
        local hosts = { _G.PlayerSpellsFrame.TalentsFrame, _G.PlayerSpellsFrame.SpellBookFrame,
          _G.LegacySystemFrame.TreePage.LegacyTreeTraitPanel }
        for _, host in ipairs(hosts) do
          local c = host.SearchPreviewContainer
          c:SetPreviewResults(RESULTS)
          assert.are.equal("他2件", c.OverflowCount.Text:GetText())
          assert.are.equal("Close", c.rows[1].Name:GetText())
          assert.is_true(unrecorded(c.rows[1].Name))
          c:SetPreviewResults({ RESULTS[1], RESULTS[2], RESULTS[3] })
          assert.are.equal("他1件", c.OverflowCount.Text:GetText())
        end
        alt(true)
        assert.are.equal("And 1 more", hosts[1].SearchPreviewContainer.OverflowCount.Text:GetText())
        alt(false)
        assert.are.equal("他1件", hosts[1].SearchPreviewContainer.OverflowCount.Text:GetText())
      end)

      it("the suggested result is Japanese, on a reused pooled button too", function()
        local c = _G.PlayerSpellsFrame.TalentsFrame.SearchPreviewContainer
        c:SetPreviewResults({})
        assert.are.same({ "アクションバーに未登録" }, suggested(c))
        c:SetPreviewResults(RESULTS)
        assert.are.same({}, suggested(c))
        c:UpdateResultsDisplay()
        c.rows = {}
        c:UpdateResultsDisplay()
        assert.are.same({ "アクションバーに未登録" }, suggested(c))
      end)

      it("the talent tree's placeholder is Japanese; the spellbook's is left to its own surface", function()
        assert.are.equal("検索", _G.PlayerSpellsFrame.TalentsFrame.SearchBox.Instructions:GetText())
        assert.are.equal("Search spells", _G.PlayerSpellsFrame.SpellBookFrame.SearchBox.Instructions:GetText())
        assert.are.equal("Search", _G.LegacySystemFrame.TreePage.LegacyTreeTraitPanel.SearchBox.Instructions:GetText())
      end)

      it("a talent button's search icon tooltip is Japanese, for a button acquired after setup", function()
        for _, tree in ipairs({ _G.PlayerSpellsFrame.TalentsFrame,
          _G.LegacySystemFrame.TreePage.LegacyTreeTraitPanel }) do
          local b = tree:acquireButton()
          b.SearchIcon:SetMatchType("TALENT_FRAME_SEARCH_TOOLTIP_EXACT_MATCH")
          b.SearchIcon:OnEnter()
          assert.are.equal("検索に完全一致", _G.GameTooltipTextLeft1:GetText())
          b.SearchIcon:SetMatchType("TALENT_FRAME_SEARCH_TOOLTIP_NOT_ON_ACTIONBAR")
          b.SearchIcon:OnEnter()
          assert.are.equal("アクションバーにありません", _G.GameTooltipTextLeft1:GetText())
        end
      end)
    end)
  end

  it("talent buttons that exist before setup are registered once the host is set up", function()
    load()
    local f = loadPlayerSpells()
    local b = f.TalentsFrame:acquireButton()
    assert.is_true(WFJ.SpellSearch.init())
    b.SearchIcon:SetMatchType("TALENT_FRAME_SEARCH_TOOLTIP_MATCH")
    b.SearchIcon:OnEnter()
    assert.are.equal("検索に一致", _G.GameTooltipTextLeft1:GetText())
  end)

  it("hooks install once per host", function()
    setup(true)
    assert.is_false(WFJ.SpellSearch.setupHost("talents"))
    assert.are.equal(3, #Stub.hooks["SearchPreviewContainer:SetPreviewResults"])
    assert.are.equal(3, #Stub.hooks["SearchPreviewContainer:UpdateResultsDisplay"])
    assert.are.equal(1, #_G.PlayerSpellsFrame.TalentsFrame.callbacks)
  end)

  it("a client name bound to the wrong type degrades to untouched English with no error", function()
    load()
    local f = loadPlayerSpells()
    f.TalentsFrame.SearchPreviewContainer = "nope"
    f.TalentsFrame.RegisterCallback = 42
    f.TalentsFrame.EnumerateAllTalentButtons = false
    f.TalentsFrame.SearchBox = true
    f.SpellBookFrame.SearchPreviewContainer.suggestedResultButtonsPool = 7
    f.SpellBookFrame.SearchPreviewContainer.OverflowCount = "x"
    assert.has_no.errors(function() assert.is_true(WFJ.SpellSearch.init()) end)
    assert.has_no.errors(function() -- the hook targets, as the client's writers would reach them
      assert.are.equal(0, WFJ.SpellSearch.onResults("spellbook"))
      assert.are.equal(0, WFJ.SpellSearch.onDisplay("spellbook"))
      assert.are.equal(0, WFJ.SpellSearch.onResults("talents"))
    end)
    assert.has_no.errors(function() WFJ.SpellSearch.registerIcon({ SearchIcon = 1 }) end)
    assert.is_false(WFJ.SpellSearch.registerIcon("x"))
  end)

  it("a client with neither window: init returns false and hooks nothing", function()
    load()
    local before = 0
    for _ in pairs(Stub.hooks) do before = before + 1 end
    assert.is_false(WFJ.SpellSearch.init())
    Stub.loadedAddons[PLAYER_SPELLS], Stub.loadedAddons[L.ADDON] = true, true -- loaded, but no frames
    assert.is_false(WFJ.SpellSearch.init())
    local after = 0
    for _ in pairs(Stub.hooks) do after = after + 1 end
    assert.are.equal(before, after)
  end)
end)
