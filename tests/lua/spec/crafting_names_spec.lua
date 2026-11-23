-- UI/Crafting: the recipe form's output name, OutputText. UpdateOutputItem writes the item's name in its quality colour
-- with SetTextToFit, which sizes the FontString to the text it measures, then sets the output icon
-- (blizzard_professionsrecipeschematicform.lua:349–359, 1358–1388). While names are on, the name shows its Japanese
-- with the colour kept, written after that pass and sized again for the text shown; the inspect window's form too.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Crafting.lua"

local ADDON = "Blizzard_Professions"

-- a FontString the form measures: 7 pixels a byte, 12 a line
local function measured()
  local fs = Stub.fontString("")
  function fs.GetStringWidth(self) return #self.text * 7 end
  function fs.GetStringHeight() return 12 end
  function fs.SetHeight(self, h) self.height = h end
  return fs
end

local function newForm(parent)
  local form = CreateFrame("Frame", nil, parent)
  form.OutputText, form.RecraftingOutputText = measured(), measured()
  form.minimized, form.measures = false, {}
  function form.GetOutputItemMaxWidth(self) return self.minimized and 250 or 800 end -- :1349–1352
  function form.ShouldAllowMultiline(self) return self.minimized end -- :1354–1356
  function form.UpdateOutputItem(self) -- :1358–1388, the plain branch: SetTextToFit(self.OutputText, text, …)
    local fs = self.OutputText
    fs:SetHeight(200)
    fs:SetText(self.output)
    fs:SetWidth(self:GetOutputItemMaxWidth())
    if not self:ShouldAllowMultiline() then fs:SetWidth(fs:GetStringWidth()) end
    fs:SetHeight(fs:GetStringHeight())
    self.measures[#self.measures + 1] = fs:GetText()
  end
  return form
end

describe("UI/Crafting's output name", function()
  local WFJ, form, inspect

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, {})
    local frame = CreateFrame("Frame", "ProfessionsFrame")
    local page = CreateFrame("Frame", nil, frame)
    frame.CraftingPage = page
    form = newForm(page)
    page.SchematicForm = form
    _G.InspectRecipeFrame = CreateFrame("Frame", "InspectRecipeFrame")
    inspect = newForm(_G.InspectRecipeFrame)
    _G.InspectRecipeFrame.SchematicForm = inspect
    Stub.loadedAddons[ADDON] = true
    WFJ.Data.add("name", { [WFJ.Names.key("Copper Bracers")] = "カッパー・ブレイサー\tかっぱー・ぶれいさー" })
    WFJ.State.setNames(true)
    assert.is_true(WFJ.Crafting.init())
    page:Show()
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.ProfessionsFrame, _G.InspectRecipeFrame = nil, nil
  end)

  it("shows the item's Japanese in its colour after the client measured its English, sized for the text shown",
    function()
      form.output = "|cff1eff00Copper Bracers|r"
      form:UpdateOutputItem()
      local fs = form.OutputText
      assert.are.equal("|cff1eff00カッパー・ブレイサー|r", fs:GetText())
      assert.are.same({ "|cff1eff00Copper Bracers|r" }, form.measures) -- the client measured only its English
      assert.are.equal(#fs:GetText() * 7, fs.width)
      assert.are.equal(12, fs.height)
      alt(true)
      assert.are.equal("|cff1eff00Copper Bracers|r", fs:GetText())
      assert.are.equal(#"|cff1eff00Copper Bracers|r" * 7, fs.width)
      alt(false)
      assert.are.equal("|cff1eff00カッパー・ブレイサー|r", fs:GetText())
    end)

  it("keeps the client's width in the minimized window, where the name may wrap", function()
    form.minimized = true
    form.output = "|cff1eff00Copper Bracers|r"
    form:UpdateOutputItem()
    assert.are.equal("|cff1eff00カッパー・ブレイサー|r", form.OutputText:GetText())
    assert.are.equal(250, form.OutputText.width)
  end)

  it("the inspect window's form shows its name too", function()
    inspect.output = "|cffffd100Copper Bracers|r"
    inspect:UpdateOutputItem()
    assert.are.equal("|cffffd100カッパー・ブレイサー|r", inspect.OutputText:GetText())
  end)

  it("a name with no Japanese, and names off, leave the client's text", function()
    form.output = "|cff1eff00Nobody Known Sword|r"
    form:UpdateOutputItem()
    assert.are.equal("|cff1eff00Nobody Known Sword|r", form.OutputText:GetText())
    WFJ.State.setNames(false)
    form.output = "|cff1eff00Copper Bracers|r"
    form:UpdateOutputItem()
    assert.are.equal("|cff1eff00Copper Bracers|r", form.OutputText:GetText())
    assert.are.equal(0, form.OutputText.calls.addonSetText)
  end)
end)
