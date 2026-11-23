-- UI/Mail: an auction invoice's item line, ITEM_SOLD_COLON / ITEM_PURCHASED_COLON .. " " .. the item's name, or
-- AUCTION_MAIL_ITEM_STACK around it (mailframe.lua:797–848). The label is a dictionary line (the `colonPrefix` form)
-- and every interface line goes through the translator's names step, as Main wires it, so while names are on the
-- item's name shows its Japanese after the Japanese label, the count kept.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local MailStub = require("tests.lua.spec.stub_mail")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Mail.lua"

local UI = {
  ITEM_SOLD_COLON = { "Item Sold:", "売却したアイテム:" }, ITEM_PURCHASED_COLON = { "Item Purchased:", "購入したアイテム:" },
  PURCHASED_BY_COLON = { "Purchased By:", "購入者:" }, SOLD_BY_COLON = { "Sold By:", "販売者:" },
}

describe("the mail invoice's item name", function()
  local WFJ

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function open(item, count, kind)
    MailStub.letter = { sender = "Jaina", subject = "Sold", items = 0, money = 5, canDelete = true,
      invoice = { type = kind or "seller", item = item, player = "Goya", bid = 5, buyout = 5, count = count } }
    MailStub.camelotOpenLetter()
    return _G.OpenMailInvoiceItemLabel:GetText()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    MailStub.installCamelot()
    WFJ = H.loadChunks(FILES)
    local new = WFJ.Translator.new
    WFJ.Translator.new = function(deps) -- the names step, as Main.lua passes it
      deps.names = function(ja, kind)
        if not WFJ.State.names or type(kind) ~= "string" then return ja end
        return WFJ.Names.inText(ja, false)
      end
      return new(deps)
    end
    H.uiSetup(WFJ, UI)
    WFJ.Translator.new = new
    -- a name the client fills into an interface line, as Main.lua resolves it
    WFJ.UIStrings.name = function(text) return WFJ.State.names and WFJ.Names.value(text) or nil end
    WFJ.Data.add("name", {
      [WFJ.Names.key("Linen Cloth")] = "リネン・クロス\tりねん・くろす",
    })
    WFJ.State.setNames(true)
    assert.is_true(WFJ.Mail.init())
  end)

  after_each(function()
    WFJ.UIStrings.name = nil
    H.uiTeardown()
    Stub.keys.alt = false
  end)

  it("shows the item's Japanese after the label, for a sale and a purchase", function()
    assert.are.equal("売却したアイテム: リネン・クロス", open("Linen Cloth"))
    -- the stub's purchase line carries the buy mode after the name, kept as written
    assert.are.equal("購入したアイテム: リネン・クロス  (Buyout)", open("Linen Cloth", nil, "buyer"))
  end)

  it("keeps a stack's count", function()
    assert.are.equal("売却したアイテム: リネン・クロス (20)", open("Linen Cloth", 20))
  end)

  it("the reveal key shows the client's line; names off shows the label's Japanese with the name as written", function()
    open("Linen Cloth", 20)
    alt(true)
    assert.are.equal("Item Sold: Linen Cloth (20)", _G.OpenMailInvoiceItemLabel:GetText())
    alt(false)
    assert.are.equal("売却したアイテム: リネン・クロス (20)", _G.OpenMailInvoiceItemLabel:GetText())
    WFJ.State.setNames(false)
    assert.are.equal("売却したアイテム: Linen Cloth (20)", _G.OpenMailInvoiceItemLabel:GetText())
    WFJ.State.setNames(true)
    assert.are.equal("売却したアイテム: リネン・クロス (20)", _G.OpenMailInvoiceItemLabel:GetText())
  end)

  it("an item with no Japanese is kept as written", function()
    assert.are.equal("売却したアイテム: Nobody Known Sword", open("Nobody Known Sword"))
  end)
end)
