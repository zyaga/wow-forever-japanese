-- UI/Bags: a bag's title is its item's name (ContainerFrameMixin:UpdateName → SetTitle(C_Container.GetBagName(id)),
-- mainline/containerframe.lua:924–926, 1307). While names are on it shows the item's Japanese; the backpack's and the
-- keyring's dictionary titles are unchanged.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local CI = require("tests.lua.spec.stub_camelot_inventory")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Bags.lua"

local UI = {
  BACKPACK_TOOLTIP = { "Backpack", "バックパック" },
  KEYRING = { "Keyring", "キーリング" },
}

describe("UI/Bags: a bag's item name", function()
  local WFJ

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function title(f) return f.TitleContainer.TitleText:GetText() end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    for key, pair in pairs(UI) do _G[key] = pair[1] end
    CI.install()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    WFJ.Data.add("name", {
      [WFJ.Names.key("Small Red Pouch")] = "スモール・レッド・ポーチ\tすもーる・れっど・ぽーち",
    })
    WFJ.State.setNames(true)
    assert.is_true(WFJ.Bags.init())
  end)

  after_each(function()
    H.uiTeardown()
    CI.teardown()
    Stub.keys.alt = false
  end)

  it("a bag's title shows the item's Japanese, and the reveal key gives the English back", function()
    local pouch = CI.openBag(1)
    assert.are.equal("スモール・レッド・ポーチ", title(pouch))
    alt(true)
    assert.are.equal("Small Red Pouch", title(pouch))
    alt(false)
    assert.are.equal("スモール・レッド・ポーチ", title(pouch))
  end)

  it("a frame reused for the backpack shows the dictionary title again", function()
    local f = CI.openBag(1)
    _G.ContainerFrame_GenerateFrame(f, 16, 0)
    assert.are.equal("バックパック", title(f))
    _G.ContainerFrame_GenerateFrame(f, 16, 1)
    assert.are.equal("スモール・レッド・ポーチ", title(f))
  end)

  it("a bag whose item name is a dictionary word is never matched as one", function()
    local named = CI.openBag(2) -- a bag named "Keyring", with no name line
    assert.are.equal("Keyring", title(named))
    assert.are.equal(0, named.TitleContainer.TitleText.calls.addonSetText)
  end)

  it("with names off the title stays as the client wrote it", function()
    WFJ.State.setNames(false)
    local pouch = CI.openBag(1)
    assert.are.equal("Small Red Pouch", title(pouch))
    assert.are.equal(0, pouch.TitleContainer.TitleText.calls.addonSetText)
  end)
end)
