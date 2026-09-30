-- Through Main's keyOf and Lookup on the loaded addon: a short player name finds the
-- $N row, a literal row wins, a female character finds the gender alias row, and quest rows carry h1f.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

describe("gender variants and short names through Main", function()
  local WFJ, name, sex

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
    Stub.installItemTextAPI()
    name, sex = "Reyn", 2
    _G.UnitName = function(unit) if unit == nil or unit == "player" then return name end end
    _G.UnitSex = function() return sex end
    WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
  end)

  local function key(e) return WFJ.Hash.key(WFJ.Normalize.v1(e)) end

  it("a gendered quest field returns h1f beside h1; a plain field has none", function()
    local e = WFJ.Lookup.get("quest.completion", 8234)
    assert.are.equal(0x860f19ff, e.h1)
    assert.are.equal(0xf0af4ecb, e.h1f)
    assert.is_nil(WFJ.Lookup.get("quest.title", 8234).h1f)
    assert.is_nil(WFJ.Lookup.get("quest.title", 2).h1f)
  end)

  it("a player named Ka sees the row shipped under the $N key", function()
    name = "Ka"
    WFJ.Data.add("book", { [key("Greetings, $N. This page names you.")] = { "ようこそ、{name}。", "." } })
    Stub.openItemText({ "Greetings, Ka. This page names you." })
    assert.are.equal("ようこそ、Ka。", WFJ.ItemText.page.fs.text) -- drawn in the page's FontString
  end)

  it("when the literal English also has a row, the literal row wins", function()
    name = "An"
    WFJ.Data.add("book", {
      [key("An old tome lies here.")] = { "古い書物がここにある。", "." },
      [key("$N old tome lies here.")] = { "{name}の古い書物。", "." },
    })
    Stub.openItemText({ "An old tome lies here." })
    assert.are.equal("古い書物がここにある。", WFJ.ItemText.page.fs.text) -- drawn in the page's FontString
  end)

  it("a female character finds the gender alias row by her live English", function()
    sex = 3
    local row = { "ケナリウスの加護を。", "." }
    WFJ.Data.add("book", { [key("May Cenarius watch over you, brother.")] = row,
      [key("May Cenarius watch over you, sister.")] = row }) -- the alias generate ships
    assert.are.same({ ja = "ケナリウスの加護を。", status = "." },
      WFJ.Lookup.keyed("book", key("May Cenarius watch over you, sister.")))
    Stub.openItemText({ "May Cenarius watch over you, sister." })
    assert.are.equal("ケナリウスの加護を。", WFJ.ItemText.page.fs.text) -- drawn in the page's FontString
  end)
end)
