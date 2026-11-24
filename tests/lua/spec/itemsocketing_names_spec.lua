-- UI/ItemSocketing: the socketed item's name, line 1 of ItemSocketingDescription (a GameTooltip filled by
-- SetSocketedItem). ItemSocketingFrame_Update fills it (blizzard_itemsocketingui.lua:56–67), and so does the scroll
-- frame's range callback (:35–37, 69–71). While names are on the name shows its Japanese, written only after
-- ItemSocketingFrame_Update and never laid out again by the addon, so no write of ours can start the range callback.
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")

describe("UI/ItemSocketing's item name", function()
  local WFJ, line, item, fills, shows

  before_each(function()
    WFJ = C.fresh({ "UI/ItemSocketing.lua" }, {})
    local frame = CreateFrame("Frame", "ItemSocketingFrame")
    C.tree(frame, { ["SocketingContainer.ApplySocketsButton"] = { button = "" } })
    function frame.SocketingContainer.Update() end
    line = Stub.namedFontString("ItemSocketingDescriptionTextLeft1", "")
    item, fills, shows = "Bandit Cloak", 0, 0
    _G.ItemSocketingDescription = {
      SetSocketedItem = function() fills = fills + 1; line.text = item end,
      Show = function() shows = shows + 1 end,
    }
    _G.ItemSocketingFrame_Update = function() -- :56–67
      frame.SocketingContainer:Update()
      _G.ItemSocketingDescription:SetSocketedItem()
    end
    _G.ItemSocketingSocketButton_OnScrollRangeChanged = function() -- :69–71
      _G.ItemSocketingDescription:SetSocketedItem()
    end
    Stub.loadedAddons.Blizzard_ItemSocketingUI = true
    WFJ.Data.add("name", { [WFJ.Names.key("Bandit Cloak")] = "バンディット・クローク\tばんでぃっと・くろーく" })
    WFJ.State.setNames(true)
    assert.is_true(WFJ.ItemSocketing.init())
    frame:Show()
  end)

  after_each(function()
    C.teardown({ "ItemSocketingFrame", "ItemSocketingDescriptionTextLeft1", "ItemSocketingDescription",
      "ItemSocketingFrame_Update", "ItemSocketingSocketButton_OnScrollRangeChanged" })
  end)

  it("shows the item's Japanese after ItemSocketingFrame_Update, with no refit of the tooltip", function()
    _G.ItemSocketingFrame_Update()
    assert.are.equal("バンディット・クローク", line:GetText())
    assert.are.equal(1, fills)
    assert.are.equal(0, shows)
    C.alt(WFJ, true)
    assert.are.equal("Bandit Cloak", line:GetText())
    C.alt(WFJ, false)
    assert.are.equal("バンディット・クローク", line:GetText())
    assert.are.equal(0, shows)
    _G.ItemSocketingFrame:Hide()
    assert.are.equal("Bandit Cloak", line:GetText())
  end)

  it("a fill from the range callback is the client's alone: nothing of ours runs after it", function()
    _G.ItemSocketingFrame_Update()
    local writes = line.calls.addonSetText
    _G.ItemSocketingSocketButton_OnScrollRangeChanged()
    assert.are.equal("Bandit Cloak", line:GetText())
    assert.are.equal(writes, line.calls.addonSetText)
    assert.are.equal(2, fills)
  end)

  it("an item with no Japanese, and names off, leave the client's line", function()
    item = "Nobody Known Sword"
    _G.ItemSocketingFrame_Update()
    assert.are.equal("Nobody Known Sword", line:GetText())
    item = "Bandit Cloak"
    WFJ.State.setNames(false)
    _G.ItemSocketingFrame_Update()
    assert.are.equal("Bandit Cloak", line:GetText())
    assert.are.equal(0, line.calls.addonSetText)
  end)
end)
