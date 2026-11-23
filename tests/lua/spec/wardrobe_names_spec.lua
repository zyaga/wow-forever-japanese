-- UI/Wardrobe: the sets tab's names. WardrobeSetsCollectionMixin:DisplaySet writes the set's name into
-- DetailsFrame.Name, measures it (IsTruncated) and moves it to LongName when it does not fit, then writes Label
-- (shared/blizzard_wardrobe_sets.lua:228–248); each list row's Init writes its Name and Label (:513–537). While names
-- are on, LongName, Label and the rows show the name's Japanese; DetailsFrame.Name is left (an auto-scaling FontString
-- the client measures on every write, blizzard_sharedxml/secureutil.lua:51–104).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_collections")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Wardrobe.lua"

describe("UI/Wardrobe's set names", function()
  local WFJ, sets, details, box

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function newRow()
    local row = CreateFrame("Button")
    row.Name, row.Label = Stub.fontString(""), Stub.fontString("")
    function row.Init(self, data)
      self.Name:SetText(data.name)
      self.Label:SetText(data.label)
    end
    return row
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, C.UI)
    C.load()
    sets = _G.WardrobeCollectionFrame.SetsCollectionFrame
    details = sets.DetailsFrame
    details.longNames = {} -- the set names the stub treats as too long for Name
    function sets.DisplaySet(self, set)
      local d = self.DetailsFrame
      d.Name:SetText(set.name)
      if d.longNames[set.name] then
        d.Name:Hide(); d.LongName:SetText(set.name); d.LongName:Show()
      else
        d.Name:Show(); d.LongName:Hide()
      end
      d.Label:SetText(set.label)
    end
    box = Stub.scrollBox()
    sets.ListContainer = { ScrollBox = box }
    WFJ.Data.add("name", {
      [WFJ.Names.key("Battlegear of Might")] = "バトルギア・オブ・マイト\tばとるぎあ・おぶ・まいと",
      [WFJ.Names.key("Molten Core")] = "モルテン・コア\tもるてん・こあ",
    })
    WFJ.State.setNames(true)
    assert.is_true(WFJ.Wardrobe.init())
    _G.WardrobeCollectionFrame:Show()
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    C.unload()
  end)

  it("the details: a long name and the label show their Japanese; Name stays as the client wrote it", function()
    details.longNames["Battlegear of Might"] = true
    sets:DisplaySet({ name = "Battlegear of Might", label = "Molten Core" })
    assert.are.equal("バトルギア・オブ・マイト", details.LongName:GetText())
    assert.are.equal("モルテン・コア", details.Label:GetText())
    assert.are.equal("Battlegear of Might", details.Name:GetText())
    assert.are.equal(0, details.Name.calls.addonSetText)
    alt(true)
    assert.are.equal("Battlegear of Might", details.LongName:GetText())
    alt(false)
    _G.WardrobeCollectionFrame:Hide()
    assert.are.equal("Battlegear of Might", details.LongName:GetText())
    assert.are.equal("Molten Core", details.Label:GetText())
  end)

  it("a set whose name fits leaves the hidden LongName as the client left it", function()
    details.longNames["Battlegear of Might"] = true
    sets:DisplaySet({ name = "Battlegear of Might", label = "" })
    details.longNames["Battlegear of Might"] = nil
    sets:DisplaySet({ name = "Battlegear of Might", label = "" })
    assert.are.equal("Battlegear of Might", details.LongName:GetText())
  end)

  it("the list rows show their names' Japanese, also after the client initializes a row again", function()
    local row = newRow()
    box:initFrame(row, { name = "Battlegear of Might", label = "Molten Core" },
      function(r, data) r:Init(data) end)
    assert.are.equal("バトルギア・オブ・マイト", row.Name:GetText())
    assert.are.equal("モルテン・コア", row.Label:GetText())
    row:Init({ name = "Nobody Known Set", label = "Molten Core" }) -- ReinitializeButtonWithBaseSetID
    assert.are.equal("Nobody Known Set", row.Name:GetText())
    alt(true)
    assert.are.equal("Molten Core", row.Label:GetText())
    alt(false)
  end)

  it("with names off nothing is written", function()
    WFJ.State.setNames(false)
    details.longNames["Battlegear of Might"] = true
    sets:DisplaySet({ name = "Battlegear of Might", label = "Molten Core" })
    local row = newRow()
    box:initFrame(row, { name = "Battlegear of Might", label = "" }, function(r, data) r:Init(data) end)
    assert.are.equal(0, details.LongName.calls.addonSetText)
    assert.are.equal(0, details.Label.calls.addonSetText)
    assert.are.equal(0, row.Name.calls.addonSetText)
  end)
end)
