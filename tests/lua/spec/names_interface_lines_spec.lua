-- With Japanese names on, a game name inside an interface line's Japanese shows in katakana like one inside quest
-- text; an abbreviation or the game's own name, which the name tables leave out, stays as written.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

describe("names inside an interface line's Japanese", function()
  local WFJ, T

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    _G.WFJ_DB = nil
    WFJ = Loader.load("WoWForeverJapanese")
    local init = WFJ.Render.init -- the policy layer Main builds, with its real names step
    WFJ.Render.init = function(translator) T = translator; return init(translator) end
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    WFJ.Data.add("ui", { WFJ_TEST_LINE = { "トレーナーを訪ねてFishingを習得しましょう。PvPではありません。", 0, "." } })
  end)

  local function shown()
    local action, payload = T.resolve("ui", "ui", "WFJ_TEST_LINE", {})
    return action, payload and payload.ja
  end

  it("what the replacer reports for a name is what the word card view lays a name card from", function()
    local text, names = WFJ.Names.inText("トレーナーを訪ねてFishingを習得しましょう。")
    local spans = WFJ.Readings.withNames({}, text, names)
    assert.are.equal(1, #spans)
    assert.is_true(spans[1].name)
    assert.are.equal("フィッシング", text:sub(spans[1].first, spans[1].last))
    assert.are.equal("Fishing", spans[1].card.meaning)
  end)

  it("with names English no line is searched for names and no name is looked up", function()
    local searched, looked = 0, 0
    local inText, of = WFJ.Names.inText, WFJ.Names.of
    WFJ.Names.inText = function(...) searched = searched + 1; return inText(...) end
    WFJ.Names.of = function(...) looked = looked + 1; return of(...) end
    finally(function() WFJ.Names.inText, WFJ.Names.of = inText, of end)
    shown()
    local fs = CreateFrame("Frame"):CreateFontString()
    fs:SetText("Fishing")
    assert.are.equal(0, WFJ.NameLabels.show("skills", "name", fs))
    assert.are.equal("Fishing", fs:GetText())
    assert.are.equal(0, searched)
    assert.are.equal(0, looked)
  end)

  it("stays as written while names are English", function()
    local action, ja = shown()
    assert.are.equal("apply", action)
    assert.are.equal("トレーナーを訪ねてFishingを習得しましょう。PvPではありません。", ja)
  end)

  it("shows the name in katakana with Japanese names on, and leaves a word with no name row", function()
    WFJ.State.setNames(true)
    local _, ja = shown()
    assert.are.equal("トレーナーを訪ねてフィッシングを習得しましょう。PvPではありません。", ja)
  end)
end)
