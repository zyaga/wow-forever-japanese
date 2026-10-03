-- A sectioned line (the Camp Benefits aura, spell 1229741): the heading and each optional paragraph found by the
-- words it begins with, filled from its own values; on the shipped data, through Main's wiring.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

describe("sectioned lines (Camp Benefits)", function()
  local WFJ, sec
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI(); Stub.installItemTextAPI()
    WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    sec = WFJ.Lookup.get("spell.aura", 1229741).sections
  end)

  local HEAD = "Gained the following camp benefits:"
  local function live(...) return table.concat({ HEAD, ... }, "\n\n") end

  it("ships as sections, with no English", function()
    assert.is_table(sec)
    assert.are.equal("以下のキャンプの恩恵を得た：", sec.head)
    for _, s in ipairs(sec) do assert.is_nil(s.ja:find("Mana Well: Restores", 1, true)) end
  end)

  it("the heading and any set of paragraphs, each filled from its own values, in the client's order", function()
    local ok, text = WFJ.Align.sections(sec, { live("Mana Well: Restores 25 Mana every 5 seconds.",
      "Sharpening Wheel: Strength increased by 3.", "Faction Banner: Spirit increased by 4.") })
    assert.is_true(ok)
    assert.are.equal("以下のキャンプの恩恵を得た：\n\nMana Well：5秒ごとにマナを25回復する。\n\n"
      .. "Sharpening Wheel：筋力が3上昇。\n\nFaction Banner：精神が4上昇。", text)
    ok, text = WFJ.Align.sections(sec, { live("Fish Bowl: All stats increased by 2%.") })
    assert.is_true(ok)
    assert.are.equal("以下のキャンプの恩恵を得た：\n\nFish Bowl：全能力値が2%上昇。", text)
  end)

  it("an unknown paragraph, a changed heading or a paragraph that does not fit leaves the English", function()
    assert.is_false(WFJ.Align.sections(sec, { live("Hot Tub: Agility increased by 5.") }))
    assert.is_false(WFJ.Align.sections(sec, { "Gained these camp benefits:\n\nFish Bowl: All stats increased by 2%." }))
    assert.is_false(WFJ.Align.sections(sec, { live("Sharpening Wheel: Strength increased by 3 and 4.") }))
  end)
end)
