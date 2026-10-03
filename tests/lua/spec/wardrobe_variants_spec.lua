-- ADR-042: UI/Wardrobe.lua. The sets tab's variant dropdown shows the set's variant word
-- ("Green", "Blue": the ItemNameDescription family), written with VariantSetsDropdown:SetText
-- (shared/blizzard_wardrobe_sets.lua:307) and post-hooked on the dropdown. Over stub_collections.lua's window.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_collections")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Wardrobe.lua"

local UI = {}
for k, v in pairs(C.UI) do UI[k] = v end
UI["ItemNameDescription:7"] = { "Green", "緑" }
UI["ItemNameDescription:8"] = { "Blue", "青" }
UI["LfgActivity:285"] = { "Custom", "カスタム" } -- another restricted family: never on this dropdown

describe("the wardrobe's variant dropdown on Forever", function()
  local WFJ

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end

  -- The dropdown's SetText (DropdownButtonMixin) writes its Text.
  local function withSetText()
    local d = _G.WardrobeCollectionFrame.SetsCollectionFrame.DetailsFrame.VariantSetsDropdown
    function d.SetText(self, t) self.Text.text = t end
    return d
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    C.unload()
  end)

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    describe("Blizzard_Collections " .. order[2], function()
      local dropdown
      before_each(function()
        load()
        if order[1] then
          C.load()
          dropdown = withSetText()
          assert.is_true(WFJ.Wardrobe.init())
        else
          assert.is_false(WFJ.Wardrobe.init())
          C.load()
          dropdown = withSetText()
          assert.are.equal(1, WFJ.LoadOnDemand.loaded(C.ADDON))
        end
      end)

      it("SetText with a variant word shows its Japanese; Alt English; the next variant follows", function()
        dropdown:SetText("Green")
        assert.are.equal("緑", dropdown.Text:GetText())
        alt(true)
        assert.are.equal("Green", dropdown.Text:GetText())
        alt(false)
        assert.are.equal("緑", dropdown.Text:GetText())
        dropdown:SetText("Blue")
        assert.are.equal("青", dropdown.Text:GetText())
      end)

      it("a word with no row, another family's word and a dictionary word stay as written", function()
        dropdown:SetText("Mythic")
        assert.are.equal("Mythic", dropdown.Text:GetText())
        dropdown:SetText("Custom")
        assert.are.equal("Custom", dropdown.Text:GetText())
        dropdown:SetText("Close") -- a global string word, not a variant
        assert.are.equal("Close", dropdown.Text:GetText())
        assert.is_nil(WFJ.UIIndex:match("Green")) -- the family only where the dropdown names it
      end)

      it("the dropdown is not a never-touch widget; SetText is hooked once", function()
        assert.is_false(WFJ.Labels.forbidden(dropdown.Text))
        assert.is_false(WFJ.Wardrobe.setup())
        assert.are.equal(1, #Stub.hooks["VariantSetsDropdown:SetText"])
      end)
    end)
  end

  it("a dropdown without SetText is not hooked and nothing errors", function()
    load()
    C.load()
    _G.WardrobeCollectionFrame.SetsCollectionFrame.DetailsFrame.VariantSetsDropdown.SetText = nil
    assert.has_no.errors(function() assert.is_true(WFJ.Wardrobe.init()) end)
    assert.is_nil(Stub.hooks["VariantSetsDropdown:SetText"])
    assert.are.equal(0, WFJ.Wardrobe.onVariant())
  end)
end)

-- The search box's placeholder: SearchBox.Instructions, SearchBoxTemplate's instructionText SEARCH written once at
-- load (mainline/blizzard_wardrobe.lua:1698–1700; inputboxtemplates.lua:174–177). The EditBox itself is the player's.
describe("the wardrobe's search box placeholder on Forever", function()
  local WFJ

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local SEARCH_UI = {}
  for k, v in pairs(UI) do SEARCH_UI[k] = v end
  SEARCH_UI.SEARCH = { "Search", "検索" }

  local box
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, SEARCH_UI)
    C.load()
    box = _G.WardrobeCollectionFrame.SearchBox
    box.Instructions = Stub.fontString(_G.SEARCH)
    box.text = ""
    function box.GetText(self) return self.text end
    function box.SetText(self, t) self.text = t end
    assert.is_true(WFJ.Wardrobe.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    C.unload()
  end)

  it("shows the Japanese placeholder; Alt shows the English; the typed text is never read or written", function()
    assert.are.equal("検索", box.Instructions:GetText())
    alt(true)
    assert.are.equal("Search", box.Instructions:GetText())
    alt(false)
    assert.are.equal("検索", box.Instructions:GetText())
    box:SetText("Search") -- the player types the dictionary word itself
    WFJ.Wardrobe.showStatic()
    assert.are.equal("Search", box:GetText())
    assert.is_true(WFJ.Labels.forbidden(box))
    assert.are.equal(0, WFJ.Labels.show("wardrobe", "probe", box))
  end)

  it("a placeholder that is no SEARCH text stays as written", function()
    box.Instructions:SetText("Search appearances")
    WFJ.Render.forget("wardrobe")
    WFJ.Wardrobe.showStatic()
    assert.are.equal("Search appearances", box.Instructions:GetText())
  end)
end)
